---
description: Writes backend tests (pytest + pytest-asyncio) for endpoints and services
context: fork
disable-model-invocation: true
argument-hint: [target, e.g. "projects endpoint" or "ingestion service"]
---

# Backend Test Agent

Writes pytest tests for FastAPI endpoints and services.

## Read first

`.claude/skills/patterns/pytest-backend.md` — source of truth for fixtures and
mocking.

## Process

1. **Identify** the target: API route or business service
2. **Read** the code under test: the module, its Pydantic schemas, its external
   dependencies — **`tests/api/` and `tests/core/` only.** For a
   `tests/services/` file, step 2 is forbidden and step 3 is where you start:
   see the box below.
3. **Read** `tests/conftest.py` — reuse fixtures, don't clone them
4. **Write**: endpoint → `tests/api/test_{name}.py`, service →
   `tests/services/test_{name}.py`
5. **Run**: `python -m pytest tests/{path} -v`

> **A service test is not written the same way as an endpoint test, and this
> command is usually the wrong entry for it.** `tests/services/` is the
> **test-first, frozen** half (`.claude/rules/07-backend.md`): its file comes
> *before* the module, and once proved red it stops moving. If the service does
> not exist yet, use `/backend:service` — it walks RED→GREEN in order. Come here
> for `tests/api/`, `tests/core/`, or to **append** a case to a service test that
> the plan missed (allowed as a pure insertion carrying its own assertion).
>
> **On that append, step 2 does not apply — do not open the service module.**
> The freeze stops a test being *edited* into agreeing with the code; the
> isolation stops it being *written* that way, and it holds for a case appended
> to a frozen file exactly as it holds for the first one
> (`.claude/rules/05-testing.md`, "Isolate the context that writes the test").
> Write the case from the plan's `Contracts` and `Test plan`, or — for a bugfix —
> from the bug report, which *is* its specification. If you cannot state the
> expected value without reading the implementation, the case is not specified
> yet: say so and stop, rather than deriving it from the code it is meant to
> constrain.
>
> Writing a `tests/services/` file for a module that already exists is the shape
> the prover refuses: it passes on save, no marker is recorded, and it says so.

## What to cover

### Endpoint

| Case | Expectation |
| ---- | ----------- |
| Happy path | 201 / 200 with the right body |
| Validation | 422 on an invalid payload |
| Not found | 404 on an unknown id |
| Isolation | another tenant sees nothing |
| Pagination | `offset` / `limit` actually apply |
| Empty | list returns `[]`, not `null` |

### Service

| Case | Expectation |
| ---- | ----------- |
| Happy path | returns the entity |
| Not found | raises `NotFoundError` |
| Isolation | cross-tenant read raises / returns `None` |
| Edge cases | optional fields, boundary values |
| External calls | mocked — assert the **outcome** they produced (state, returned value), not that the mock was called |

## Rules

- `asyncio_mode = "auto"` in `pyproject.toml`, otherwise
  `pytestmark = pytest.mark.asyncio` at the top of the file. A missing marker
  makes the test **fail** with `async def functions are not natively supported`
  — measured on pytest 9.1.1, both with pytest-asyncio 1.4.0 in strict mode and
  with no async plugin at all. Loud, but the message names plugins rather than
  your code, and every async test in the repo shows it at once
- Arrange → Act → Assert, one logical assertion per test
- Naming: `test_{action}_{scenario}`
- Each test independent; no state shared between tests
- **Always** test isolation — nothing else enforces it
- **Assert the behaviour, never the call** (`.claude/rules/05-testing.md`): the
  returned value, or the row/status the call left behind. The one exception —
  an effect with no return value and no readable trace, such as the tenant
  filter sent to the vector store — is spelled out in
  `.claude/skills/patterns/pytest-backend.md`
- `AsyncMock` + `patch` on the **import site** (`app.services.x.client`), never
  the origin module
- Never reach a real LLM, vector store, or third-party API
- No `Any` in tests either

## Checklist

- [ ] Happy path
- [ ] Error cases (validation, not found)
- [ ] Cross-tenant isolation
- [ ] External services mocked at the import site
- [ ] `python -m pytest tests/{path} -v` green

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
