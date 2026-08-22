---
description: Creates an isolated business service (pipeline, worker, async job)
context: fork
disable-model-invocation: true
argument-hint: [service, e.g. "ingestion pipeline" or "PDF export"]
---

# Service Agent

Creates a business service that is not tied to one REST route — pipelines,
workers, background jobs.

## Read first

`.claude/skills/patterns/fastapi-architecture.md` · `.claude/rules/07-backend.md`
For an ingestion or retrieval pipeline, also
`.claude/skills/patterns/rag-ingestion.md` / `rag-chat.md`.

## Process

1. **Parse**: what process, which steps, which external dependencies
2. **Inspect**: `app/services/` (conventions), `app/core/` (available clients),
   `app/models/` (what it manipulates)
3. **Write the test FIRST** — `tests/services/test_{name}.py`, external calls
   mocked. `app/services/` is a **test-first, then frozen** layer
   (`.claude/rules/07-backend.md`): `tdd-require-red-py.py` denies creating the
   module until `tdd-prove-red-py.py` has seen this file fail for a reason that
   proves something. Take the cases from `docs/work/<slug>/plan.md`'s `Test plan`
   when there is one.

   > The name is not free: `tests/` **mirrors** `app/`, and that mapping is how
   > the hooks pair the two files. `tests/services/test_export.py` pairs with
   > `app/services/export.py`; a multi-step package pairs file by file
   > (`tests/services/export/test_pipeline.py` ↔ `app/services/export/pipeline.py`).

4. **Read the RED verdict, then write**:
   - simple service → `services/{name}.py`
   - multi-step → package `services/{name}/` with `pipeline.py` orchestrating and
     one file per step

   Just enough to pass. The test does not move: from here it is frozen, and
   correcting it is a plan-level decision that goes through
   `.claude/.tdd-unfrozen`, visibly.

## Shapes

```python
class ExportService:
    """Generates PDF exports for a project's documents."""

    async def generate(
        self, db: AsyncSession, tenant_id: str, project_id: str,
    ) -> bytes:
        ...


export_service = ExportService()
```

```
services/{name}/
├── __init__.py
├── pipeline.py      # orchestrates, times each step, owns the status machine
├── step_one.py
└── step_two.py
```

The orchestrator owns error handling: **it never lets an exception escape
without writing a terminal state**. A job that dies leaving `processing` forever
is the classic failure of this shape.

## Rules

- **No HTTP**: no `fastapi` import, no status codes, no `Request`/`Response`
- **Isolation key** as an explicit parameter of every public method
- **Business exceptions** from `core/exceptions.py`
- **Async** for every I/O; a sync call blocks the whole event loop
- **Mockable**: external clients reached through `core/{client}.py`, never
  instantiated inline — otherwise no test can isolate them
- Own session for background work: the request's `AsyncSession` is closed once
  the response is sent
- No `Any`, explicit return types, docstring on the class and public methods

## Checklist

- [ ] No HTTP concept anywhere in the module
- [ ] Isolation key parameterised
- [ ] Terminal state written on every error path
- [ ] Business exceptions, not `HTTPException`
- [ ] Async I/O throughout
- [ ] Tests with mocked external services
- [ ] `python -m pytest -x` green, `ruff check .` clean

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
