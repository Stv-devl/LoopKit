# RAG — Ingestion pipeline

Turning a user's file into retrievable chunks. One orchestrator, one file per
step, and a status the UI can read at any moment.

```
services/ingestion/
├── pipeline.py        # orchestrates, times, and owns the status machine
├── extraction.py      # PDF / DOCX / XLSX → pages of text
├── cleaning.py        # strip headers, footers, table-of-contents pages
├── classification.py  # LLM → {type, category, …} used to pick the strategy
├── chunking.py        # pages → chunks + metadata
└── embedding.py       # chunks → vectors → vector store
```

## Status machine

The document row is the progress bar. Set it before the work, not after.

| Status       | Meaning                                            |
| ------------ | -------------------------------------------------- |
| `processing` | row created, pipeline started                      |
| `ready`      | indexed, `chunk_count > 0`                         |
| `empty`      | pipeline succeeded but produced **0 chunks**       |
| `error`      | `error_message` holds `Type: message`, truncated   |

`empty` earns its own state: it is not a failure (nothing crashed) and it is not
success (nothing is searchable). Folded into `ready`, it becomes a silent hole
in retrieval that nobody can explain three weeks later.

## Orchestrator

```python
async def run_ingestion(document_id: str, tenant_id: str) -> None:
    """Extract → classify → chunk → embed → persist. Never raises.

    Takes **ids, not objects**, and opens its own session: a BackgroundTasks
    callback runs after the response, and the request's `AsyncSession` — and
    every ORM row still attached to it — is closed by then.
    """
    async with async_session() as db:
        document = await db.get(Document, document_id)
        if document is None or document.tenant_id != tenant_id:
            return
        file_path = storage_path(document)

        try:
            started = time.perf_counter()

            # 1. Extract, then clean, then OCR only what came out empty
            extraction = extract(file_path)
            extraction.pages = clean_pages(extraction.pages)
            if file_path.suffix.lower() == ".pdf":
                extraction.pages = await ocr_sparse_pages(file_path, extraction.pages)
            extraction.full_text = "\n\n".join(p.text for p in extraction.pages)

            # 2. Classify — decides the chunking strategy and the routing
            classification = await classify_document(
                extraction.full_text, file_path=file_path, nb_pages=len(extraction.pages) or 1,
            )
            document.type = classification["type"]

            # 2b. Some types are stored but not indexed (pure images, plans…)
            if classification["type"] in NOT_INDEXED_TYPES:
                document.status, document.chunk_count = "ready", 0
                await db.commit()
                return

            if not extraction.full_text.strip():
                document.status = "error"
                document.error_message = "No text could be extracted from file"
                await db.commit()
                return

            # 3. Chunk — strategy driven by the classified type
            chunks = chunk_document(extraction.pages, classification["type"])
            if not chunks:
                document.status = "empty"
                document.error_message = "Chunking produced 0 chunks from extracted text"
                await db.commit()
                return

            # 4. Embed + index — returns one point id per chunk, in order
            ingested_at = datetime.now(UTC)
            point_ids = await index_chunks(
                chunks, tenant_id=tenant_id, document_id=document.id,
                doc_type=classification["type"], filename=document.filename,
                ingested_at=ingested_at,
            )

            # 5. Mirror the chunks in SQL, paired with their vector ids
            for chunk, point_id in zip(chunks, point_ids, strict=True):
                db.add(Chunk(
                    document_id=document.id,
                    text=chunk.text,
                    page=chunk.page,
                    position=chunk.position,
                    vector_point_id=point_id,
                    section_title=chunk.section_title or None,
                    content_type=chunk.content_type,
                    keywords=chunk.keywords or None,
                    char_count=chunk.char_count or len(chunk.text),
                ))

            document.status = "ready"
            document.chunk_count = len(point_ids)
            document.ingested_at = ingested_at
            document.error_message = None
            await db.commit()

            logger.info(
                "[PIPELINE] %s | %d chunks | total=%.1fs",
                document.filename, len(point_ids), time.perf_counter() - started,
            )

        except Exception as exc:
            logger.exception("Ingestion failed for document %s", document.id)
            document.status = "error"
            document.error_message = f"{type(exc).__name__}: {exc}"[:500]
            await db.commit()
```

Non-negotiables in that function:

- **Ids in, own session inside.** The caller is
  `background.add_task(run_ingestion, doc.id, tenant_id)` — the same two
  arguments in `patterns/file-upload.md` and `patterns/fastapi-architecture.md`.
  Passing the `Document` object instead raises on the first attribute read, once
  the response has closed the session it was loaded in.
- **The tenant is re-checked after the load.** `db.get` bypasses every WHERE
  clause by construction; the id arrives from a task queue, so this check is the
  only thing between a mis-queued id and another tenant's file.
- **`strict=True` on the zip.** Chunks and point ids must be the same length; if
  they ever diverge, you want a crash, not chunk N carrying chunk N+1's vector.
- **The `except` commits.** A pipeline that dies leaving `processing` forever is
  the single most common RAG bug in production.
- **Time every step and log the total.** Ingestion latency is the number that
  gets asked about, and it can only be reconstructed from logs.

## Chunking

Chunk boundaries decide retrieval quality more than the embedding model does.

- Split on **document structure** (headings, sections, table rows), then pack to
  a target size — never a blind `text[i:i+1000]`
- Carry the heading path with the chunk (`parent_sections`, `section_title`) and
  **prepend it to the embedded text**, not just to the payload: the vector must
  contain the context the reader would have had
- Tag a `content_type` (`prose`, `table`, `heading`, `admin`) — retrieval later
  needs to down-weight boilerplate
- Keep `page` and `position`: citations without a page are not citations
- Target 500–1500 characters. Log the size distribution of every run; a spike of
  `< 100` char chunks means the splitter found structure that is not there

```python
texts = [
    f"{c.heading_prefix}\n\n{c.text}" if c.heading_prefix else c.text
    for c in batch
]
```

## Embedding + indexing

```python
BATCH_SIZE = 10          # chunks per embedding call
_MAX_RETRIES = 3
_RETRY_BASE_DELAY = 1.0  # seconds, doubled each attempt


async def embed_texts(texts: list[str]) -> list[list[float]]:
    """Embed a batch, retrying only transient provider errors."""
    for attempt in range(_MAX_RETRIES):
        try:
            response = await llm_client.embeddings.create_async(
                model=EMBEDDING_MODEL, inputs=texts,
            )
            return [item.embedding for item in response.data]
        except Exception as exc:
            message = str(exc)
            transient = "503" in message or "429" in message or "timeout" in message.lower()
            if not transient or attempt == _MAX_RETRIES - 1:
                raise
            await asyncio.sleep(_RETRY_BASE_DELAY * (2**attempt))
    raise AssertionError("unreachable")
```

Retry **only** on 429/503/timeout. Retrying a 400 three times is three times the
same rejection, plus three times the latency.

Payload written with every point:

```python
payload = {
    "tenant_id": str(tenant_id),      # ← the isolation key, always first
    "project_id": str(project_id),
    "document_id": str(document_id),
    "type": doc_type,
    "filename": filename,
    "page": chunk.page,
    "position": chunk.position,
    "text": chunk.text,               # store the text: retrieval must not re-query SQL
    "section_title": chunk.section_title,
    "parent_sections": chunk.parent_sections,
    "content_type": chunk.content_type,
    "keywords": keywords,
    "char_count": chunk.char_count,
    "ingested_at": ingested_at.isoformat(),   # ← lets retrieval prefer the latest version
}
```

`ingested_at` in the payload is what makes "keep only the newest version of this
document type" possible at query time. Add it on day one; backfilling a vector
store is a migration nobody wants to write.

## Lifecycle

- **Delete a document** → delete its vectors in the same transaction boundary:
  ```python
  await vector_client.delete(
      collection_name=COLLECTION,
      points_selector=Filter(must=[
          FieldCondition(key="document_id", match=MatchValue(value=str(document_id))),
      ]),
  )
  ```
  Orphan vectors keep answering questions about a file the user deleted. That is
  a data-protection problem, not a tidiness one.
- **Re-ingest** = delete the old points first, then index. Otherwise both
  versions compete in every future search.
- **`ensure_collection()`** at index time, idempotent — creating the collection
  with the wrong vector size fails at the first upsert, which is the good case;
  the bad case is a silent dimension mismatch on a second embedding model.

## Testing this pipeline

Mock the embedding call and the vector client (see `pytest-backend.md`), then
assert on:

- status transitions, including `empty` and `error`
- `chunk_count` matching the number of SQL rows
- **`tenant_id` equal to the CALLER's tenant in every written payload** — never
  merely "present". `rag.md` calls the payload filter "the entire barrier", and
  a pipeline writing `payload["tenant_id"] = document.uploader_tenant` — the
  wrong variable — satisfies a presence check completely. The only
  implementation change a presence check can fail is deleting or renaming the
  key: the change detector `05-testing.md` defines, on the one assertion the
  isolation rests on. Ingest for a **second** tenant in the same test, or the
  equality has nothing to disagree with:

  ```python
  await ingest(other_document.id, "other-tenant")
  await run_ingestion(document.id, tenant.id)

  written = [c.kwargs["points"] for c in upsert.call_args_list][-1]
  assert {p.payload["tenant_id"] for p in written} == {tenant.id}
  ```

- one test per real fixture file per format (a 3-page PDF, a DOCX with tables)

Fixture files belong in `tests/fixtures/` and stay small — a 40 MB sample in git
is a repo everyone clones slowly, forever.
