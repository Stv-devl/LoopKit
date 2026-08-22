---
description: Backend performance audit (N+1, sequential awaits, pagination, lazy loading, timeouts)
context: fork
agent: Explore
disable-model-invocation: true
argument-hint: [scope, e.g. "services/ingestion" or "api/chat" or "everything"]
---

# Backend Performance Audit Agent

Read-only. Finds the anti-patterns below, ranked by user-visible impact.

## Read first — this fork starts with no project context

`agent: Explore` keeps the context small by **skipping CLAUDE.md**, so none of
`.claude/rules/` is loaded for you. Nothing below is knowable from the code
alone; read these before the first finding, or the audit judges this repo
against a generic FastAPI app:

- `.claude/rules/07-backend.md` — layers, non-negotiables, the test gate
- `.claude/rules/01-stack.md` — the data client, and **what the real
  server-side authorization barrier is** (on FastAPI it is usually a `WHERE`
  clause in `services/`, not RLS)
- `.claude/rules/06-database.md` — provider, isolation, inspection commands

## Inspect

`app/services/` (main target) · `app/api/` (pagination, response shape) ·
`app/models/` (relations, indexes) · `app/core/` (client timeouts)

## Anti-patterns

### 1. N+1 queries

```python
# ❌ one query, then one per row
for project in projects:
    docs = await db.execute(select(Document).where(Document.project_id == project.id))

# ✅
stmt = select(Project).options(selectinload(Project.documents)).where(...)
```

Look for: `await db.execute` or `await db.get` **inside a loop**.

### 2. Sequential awaits that could be concurrent

```python
# ❌ three independent calls, in series
chunks = await search(...)
history = await get_history(...)
prefs = await get_preferences(...)

# ✅
chunks, history, prefs = await asyncio.gather(search(...), get_history(...), get_preferences(...))
```

Look for: 2+ consecutive `await`s on independent data.

**But**: `asyncio.gather` on tasks sharing one `AsyncSession` is a bug —
`AsyncSession` is not concurrency-safe. Group external calls, not DB calls on
the same session.

### 3. Missing pagination

```python
# ❌ returns the whole table
select(Document).where(Document.tenant_id == tenant_id)
```

Look for: a `select()` without `.limit()` in any `list_*` method.

### 4. Uncontrolled lazy loading

```python
project = await db.get(Project, project_id)
count = len(project.documents)   # implicit query — and under asyncio, often MissingGreenlet
```

Look for: attribute access on a relationship never `selectinload`ed.

### 5. No timeout on external calls

```python
response = await asyncio.wait_for(llm_client.chat(...), timeout=30.0)
```

Look for: LLM, vector store, and `httpx` calls with no timeout. A provider that
hangs holds a worker until the client gives up.

### 6. Whole tables in memory

`.all()` on chunks/messages/documents. Paginate, or stream with `yield_per`.

### 7. Heavy serialization

A `Response` schema carrying `list[Nested]` loads and serialises the whole
relation on every list call. Return a count, or a dedicated endpoint.

### 8. Missing indexes

Collect every `.where()` and `.order_by()` column in the scope, and check the
model has a matching index — composite `(tenant_id, col)`, in that order.

### 9. Sync in an async path

`requests`, `time.sleep`, `open().read()` on a large file, a sync SDK client:
each one blocks the **entire** event loop, not just that request. Highest
impact-per-line of anything on this list.

### 10. LLM-specific

Embedding one text per call instead of batching · re-embedding the same query
twice in a turn · rewrite + answer + extraction awaited in series when
extraction could run as a task · no cache on an idempotent classification.

## Output

```
# Performance Audit — [scope]

## CRITICAL (high impact, simple fix)
[PERF-001] N+1 in the ingestion pipeline
- services/ingestion/pipeline.py:45
- Impact: O(n) queries — 100 documents = 100 round trips
- Fix: [code]

## HIGH / MEDIUM
[...]

## Estimated
| Endpoint | Before | After | Gain |
```

## Rules

- No premature optimisation: measure or reason from the anti-pattern list, do not
  guess
- Rank by user-facing frequency
- Verify no fix breaks isolation
- Read-only: propose, apply nothing

## Task: $ARGUMENTS
