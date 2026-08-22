---
description: Builds or extends a RAG pipeline (ingestion step, retrieval, prompt, streaming)
context: fork
disable-model-invocation: true
argument-hint: [what to build, e.g. "XLSX ingestion" or "query rewriting" or "chat over documents"]
---

# RAG Agent

Builds or extends a retrieval-augmented pipeline.

## Read first

- `.claude/skills/patterns/rag-ingestion.md` — file → chunks → vectors
- `.claude/skills/patterns/rag-chat.md` — question → context → answer → SSE
- `.claude/rules/07-backend.md` — layer rules (this is a `services/` job)

## Locate the request first

| Ask | Lands in |
| --- | -------- |
| New file format, OCR, cleaning | `services/ingestion/extraction.py` / `cleaning.py` |
| Different splitting for a document type | `services/ingestion/chunking.py` |
| Different embedding model, batching, retries | `services/ingestion/embedding.py` |
| New metadata to filter or cite on | payload **and** the SQL chunk row **and** the search filters |
| Better recall, wrong chunks retrieved | `services/search.py` |
| Rephrasing, pronoun resolution, intent flags | `services/chat/query_rewrite.py` |
| Answer quality, tone, refusals, citations | `services/chat/prompts.py` |
| Streaming, event shape, side extraction | `services/chat/stream.py` |

If the request is "answers are bad", it is a retrieval question until proven
otherwise — run `/backend:rag-audit` before writing a line of prompt.

## Process

> **Every row of the table above lands in `app/services/**`, which is
> test-first and FROZEN** (`.claude/rules/07-backend.md`). There is no path
> through this command that writes code before its test: `tdd-require-red-py`
> denies creating `services/ingestion/chunking.py`, `services/search.py` or
> `services/chat/prompts.py` until the matching `tests/services/…` file has been
> observed failing. That is why step 3 below is "write the test, read the RED
> verdict, then write the step" and not "write it".
>
> A constants-only module is not an exception — `prompts.py` is red-provable
> like any other (the import of the constant fails before it exists).

1. **Inspect** the existing pipeline end to end before touching one step: the
   payload written at index time constrains every filter available at query time
2. **State the change** in one sentence, and which step owns it
3. **Write the step's TEST first**, in `tests/services/…` mirroring the module,
   from the sentence in step 2 — then read `tdd-prove-red-py`'s verdict. Only
   `RED confirmed` unlocks step 4. If the module already exists, the case is an
   append to the frozen file, still written without opening the module
   (`.claude/rules/05-testing.md`, "Isolate the context that writes the test")
4. **Write** the change in that step only, just enough to pass. A change
   spanning ingestion *and* retrieval means the payload changed — say it
   explicitly, because it needs a re-index
5. **Re-index if the payload changed**: existing points do not gain a field
   retroactively. Either backfill or re-ingest; a search filtering on a field
   half the corpus lacks silently returns half the corpus
6. **Run the suite** with mocked provider calls
   (`.claude/skills/patterns/pytest-backend.md`)

## Non-negotiables

- **Isolation key in every vector query**, exactly like in SQL. The vector store
  has no row-level security; the payload filter is the entire barrier
- **Embed the context, not just the text**: prepend the heading path to the
  chunk before embedding
- **Store `text` in the payload** — retrieval must not need a second SQL round trip
- **Store `ingested_at`** — it is what lets retrieval prefer the newest version
- **Deleting a document deletes its vectors**, in the same operation
- **Every provider call is mockable**, reached through `core/{client}.py`
- **Retries only on 429 / 503 / timeout**, exponential backoff
- A parse failure of an LLM's JSON output **falls back**, never raises
- Prompts live in `prompts.py` as constants — a prompt change must be readable
  as a prompt change in the diff

## Checklist

- [ ] The touched step is the only one touched (or the payload change is stated)
- [ ] Isolation key in every vector filter
- [ ] Payload carries what retrieval and citations need
- [ ] Re-index plan if the payload changed
- [ ] Provider errors: retried when transient, surfaced when not
- [ ] Status machine still writes a terminal state on every path
- [ ] Every touched `app/services/**` module opened on a **RED confirmed**
      verdict, not on a write
- [ ] Tests with mocked provider, isolation asserted **on the value** — the
      caller's tenant id, proved against a second tenant, never "the key is
      present" (`patterns/rag-ingestion.md`, "Testing this pipeline")
- [ ] `python -m pytest -x` green, `ruff check .` clean

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
