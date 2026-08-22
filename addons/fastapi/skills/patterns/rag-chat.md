# RAG — Retrieval, generation, streaming

The answering half. One orchestrator (`chat_stream`), a search module it calls,
and a prompt module that owns every string sent to the model.

```
services/chat/
├── stream.py         # orchestrates the whole turn, yields SSE
├── query_rewrite.py  # question + history → search query (+ intent flags)
├── prompts.py        # every system prompt, in one file
├── conversation.py   # conversation + message persistence
└── extraction.py     # optional structured extraction, run in parallel
services/search.py    # vector queries, merging, dedup, scoring
```

## The turn, end to end

```python
async def chat_stream(
    db: AsyncSession,
    *,
    tenant_id: str,
    project_id: str,
    user_id: str,
    question: str,
    conversation_id: str | None = None,
) -> AsyncGenerator[str, None]:
    """1. resolve conversation  2. persist question  3. load history
    4. rewrite + classify  5. retrieve  6. build context  7. stream  8. persist."""

    conv = (
        await get_conversation(db, tenant_id, conversation_id)
        if conversation_id
        else await create_conversation(db, tenant_id, project_id, user_id, question[:60])
    )

    db.add(Message(conversation_id=conv.id, role="user", content=question))
    await db.commit()

    # The client needs the id before the first token, to route the stream
    yield f"data: {json.dumps({'type': 'conversation', 'id': conv.id})}\n\n"

    history = await load_recent_messages(db, conv.id, limit=HISTORY_WINDOW)

    # 4. Rewrite: resolves pronouns against history, returns intent flags
    search_query, related_queries, structured = await rewrite_query(question, history[:-1])
    scope = classify_scope(question)          # deterministic, see below

    if scope == "broad":
        search_limit, context_max, score_threshold, max_sources = 20, 48_000, 0.30, 10
    else:
        search_limit, context_max, score_threshold, max_sources = 20, 24_000, 0.40, 5

    # 5. Retrieve — a failure here is a message, never a 500 mid-stream
    try:
        results = await search_merged(
            tenant_id=tenant_id, project_id=project_id,
            queries=[q for q in (search_query, question, *related_queries) if q],
            limit=search_limit, score_threshold=score_threshold,
        )
    except Exception as exc:
        logger.error("Search failed: %s", exc)
        yield f"data: {json.dumps({'type': 'error', 'content': '<user-facing message>'})}\n\n"
        yield f"data: {json.dumps({'type': 'done'})}\n\n"
        return

    # 6. Context under an explicit character budget + the sources that back it
    context_block, sources = build_context_and_sources(
        results, score_threshold=score_threshold,
        context_max=context_max, max_sources=max_sources,
    )
    messages = build_messages(context_block, question, history, scope)

    if not context_block:
        sources = []       # no context = no citations, ever

    # 7. Side extraction runs *while* the answer streams
    table_task = (
        asyncio.create_task(extract_table(context_block, question))
        if structured == "table" and context_block else None
    )

    answer = ""
    stream = await llm_client.chat.stream_async(
        model=CHAT_MODEL, messages=messages, temperature=0.1,
    )
    async for event in stream:
        token = event.data.choices[0].delta.content
        if token:
            answer += token
            yield f"data: {json.dumps({'type': 'token', 'content': token})}\n\n"

    if table_task is not None:
        table = await table_task
        if table:
            yield f"data: {json.dumps({'type': 'structured', 'content': table.model_dump()})}\n\n"

    if sources:
        yield f"data: {json.dumps({'type': 'sources', 'content': [s.model_dump(mode='json') for s in sources]})}\n\n"

    # 8. Persist only once the stream is complete
    db.add(Message(
        conversation_id=conv.id, role="assistant", content=answer,
        sources_json=json.dumps([s.model_dump(mode="json") for s in sources]),
    ))
    await db.commit()

    yield f"data: {json.dumps({'type': 'done'})}\n\n"
```

## Query rewriting

The user's question is rarely a good search query: it carries pronouns
("and for the second one?"), politeness, and no vocabulary from the corpus.
Rewrite it against the history with `temperature=0.0`, and make the model return
**JSON**: the query plus the intent flags the pipeline needs downstream.

```python
{"query": "...", "related": ["...", "..."], "scope": "broad|specific",
 "structured": "table|none"}
```

Rules that stop this from becoming a failure point:

- **Every parse failure falls back to the original question.** A rewrite is an
  optimisation; it may never be the reason a turn fails.
- **Strip markdown fences** before `json.loads` — models wrap JSON in ```` ```json ````
  no matter what the prompt says.
- **Clamp what comes back**: query truncated to ~25 words, `related` to 2 items
  of ~15 words. An unclamped rewrite keyword-stuffs itself and the embedding
  drifts away from every real chunk.
- **Validate enums against a whitelist**, defaulting to the safe branch.
- **Off-topic detection** goes here too: a sentinel token in the response, and
  the pipeline answers without retrieving at all.
- Trust the LLM for *rephrasing*, not for *routing*. Scope classification driven
  by a regex on the question (`summarise|list all|every|overview`) is
  reproducible; the model's own `scope` field drifts between calls on the same
  input.

## Retrieval

One embedding call for all queries, one vector search per vector, merged by
point id keeping the best score:

```python
async def search_merged(
    *, tenant_id, project_id, queries: list[str],
    limit: int = 12, score_threshold: float = 0.40,
) -> list[SearchResult]:
    vectors = await embed_texts(queries)      # single API call for every query
    must = [
        FieldCondition(key="tenant_id", match=MatchValue(value=str(tenant_id))),
        FieldCondition(key="project_id", match=MatchValue(value=str(project_id))),
    ]

    best: dict[str, tuple[float, object]] = {}
    for vector in vectors:
        hits = await vector_client.search(
            collection_name=COLLECTION,
            query_vector=vector,
            query_filter=Filter(must=must),
            limit=limit * 3,                  # over-fetch: dedup will thin this out
            score_threshold=score_threshold,
        )
        for hit in dedup_by_latest_version(hits):
            point_id = str(hit.id)
            if point_id not in best or hit.score > best[point_id][0]:
                best[point_id] = (hit.score, hit)

    if not best:
        ...  # single retry, lower threshold, larger limit
```

The techniques that actually move recall, in the order they pay off:

1. **Multi-query.** Search the rewritten query *and* the original *and* 0–2
   adjacent phrasings. Different phrasings hit different chunks; the union is
   strictly better and costs one extra embedding call.
2. **Over-fetch then filter.** Ask for `limit * 3`, then dedup, penalise, cut.
   Filtering before fetching returns 4 results when you wanted 12.
3. **A threshold plus a fallback.** `score_threshold=0.40` keeps garbage out of
   the context; a broad question ("summarise the project") legitimately matches
   nothing above it. Retry once at `0.35` with a bigger limit rather than
   answering "I found nothing" on a question the corpus can answer.
4. **Version dedup.** When several documents share a type, keep only the chunks
   of the most recently `ingested_at` one. Without it, a superseded revision
   argues with the current one inside the same answer.
5. **Score penalties over hard filters.** A document type that matches broadly
   but rarely answers (boilerplate, administrative, diagnostic) gets
   `score *= 0.80` — unless the question is *about* that topic. A hard exclusion
   makes the one question that needed it unanswerable.
6. **Diversity for broad questions.** Cap hits per document (`per_document=2`)
   so one verbose file cannot own the whole context window.

## Context building

- Budget in **characters**, explicit, adapted to scope (~24k specific, ~48k
  broad). Not "top 5 chunks": chunk sizes vary by an order of magnitude.
- Group by source, order by document then page — a model reading interleaved
  fragments from four files invents transitions between them.
- Prefix each block with its provenance (`filename`, `page`, section path). That
  is what makes "according to X page 12" possible in the answer.
- Sources handed to the UI are built from **the same filtered list** as the
  context. Two code paths = citations pointing at chunks the model never saw.
- Empty context → no sources, and a prompt that instructs the model to say it
  does not know. Never let it answer from parametric memory while the UI shows a
  citation footer.

## Streaming (SSE)

The endpoint stays a one-liner; the service yields.

```python
@router.post("/{project_id}/chat")
async def chat(
    project_id: str,
    data: ChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> StreamingResponse:
    return StreamingResponse(
        chat_stream(db, tenant_id=current_user.tenant_id, project_id=project_id,
                    user_id=current_user.id, question=data.question),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",   # nginx buffers SSE into uselessness without it
        },
    )
```

Wire format — `data: {json}\n\n`, double newline mandatory. Event vocabulary,
declared once and shared with the frontend:

Every frame is `{"type": …}` — **one envelope, one parse branch on the client**.
The same vocabulary as `/backend:sse-stream`; a second shape (a bare
`[DONE]` sentinel, a `{"text": …}` frame) means the frontend carries two parsers
forever and one of them rots.

| `type`         | Payload key       | When                       |
| -------------- | ----------------- | -------------------------- |
| `conversation` | `id`              | first, before any token    |
| `token`        | `content`         | during generation          |
| `structured`   | `content`         | after the text             |
| `sources`      | `content`         | after the text             |
| `error`        | `content`         | instead of the rest        |
| `done`         | —                 | always last, on every path |

Traps:

- **`done` on the error path too.** A client waiting for a terminator that
  never comes shows a spinner forever.
- **Errors inside the generator cannot become HTTP status codes** — the 200 was
  sent with the first byte. Catch, emit an `error` event, terminate.
- **Persist after the stream, not during.** A commit per token is a commit per
  token.
- **Run side extraction with `asyncio.create_task` before the stream loop**, and
  await it after. Sequentially, the user waits for both.
- **Never share the request's `AsyncSession` across `asyncio.gather`.** An
  `AsyncSession` is not concurrency-safe; parallel queries on one session raise
  `InterfaceError` under load and pass in dev.
- **A client that hangs up kills the generator where it stands.** Starlette
  closes it, `GeneratorExit` is raised at the current `yield`, and everything
  after — the `sources` frame, the assistant message, the token accounting —
  never runs. The user sees a half answer that was never saved. If the turn must
  survive the disconnect, persist from a `finally` that only *writes* (never
  `yield`s — see `/backend:sse-stream`), or hand the persistence to a task that
  does not live on the stream.

## Prompts

**Retrieved text is data, never instructions.** Everything in the context block
came from a file a user uploaded, so treat it as hostile input: delimit each
source explicitly (a fenced block with its provenance header), state in the
system prompt that the content between the delimiters is reference material and
that instructions found inside it are to be ignored and reported, and give the
answering call **no tools** — no SQL, no shell, no fetch. A model that can only
emit text can only be talked into saying something wrong; one holding a tool can
be talked into doing something wrong. `/backend:security` checks exactly this.

One `prompts.py`. Every system prompt is a module-level constant, no f-string
concatenation scattered across the service. It makes prompts diffable in review,
and it is the only way a prompt change shows up as a prompt change in git.

## Testing

- `rewrite_query` with a mocked LLM: valid JSON, fenced JSON, garbage, and an
  exception — all four must return a usable query
- `search_merged` with a mocked vector client: assert `tenant_id` is in the
  filter, assert dedup keeps the newest, assert the low-threshold retry fires
- `chat_stream` with both mocked: collect the yielded strings and assert the
  event sequence, including a `done` frame on the error path
- Never call a real provider in the suite
