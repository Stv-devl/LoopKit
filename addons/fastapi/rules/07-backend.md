<!-- budget: 290 lines · /kit:doctor rules-budget -->
# Backend — FastAPI + Python

<!-- FILL: Python version, package manager (pip / uv / poetry), and the real
     module root if it is not `app/`. Everything else is layer discipline. -->

## Stack

| Category      | Technology                                     |
| ------------- | ---------------------------------------------- |
| Framework     | FastAPI (Python 3.12+)                         |
| ORM           | SQLAlchemy 2.0 (async)                         |
| Migrations    | Alembic                                        |
| Validation    | Pydantic v2                                    |
| Auth          | <bcrypt + JWT / OAuth provider — name it>      |
| LLM           | <provider + models, or "none">                 |
| Vector DB     | <Qdrant / pgvector / none>                     |
| Tests         | pytest + pytest-asyncio                        |
| Lint / format | Ruff                                           |

## Commands

```bash
uvicorn app.main:app --reload          # Dev server
python -m pytest                       # Run tests once — USE THIS in any gate
python -m pytest --cov=app             # With coverage — floor in "Tests" below
python -m pytest -x                    # Stop on first failure
ruff check .                           # Lint — reads only, safe repo-wide
ruff format app/                       # Format — see the warning below
mypy app                               # Typecheck — part of the ship gate <!-- FILL: keep or drop -->
alembic upgrade head                   # Apply migrations
alembic revision --autogenerate -m ""  # Generate a migration
```

> **The six roles a gate needs** — the same six as `00-project.md`: run-once
> tests (`python -m pytest`), typecheck (`mypy` or `pyright`), **lint**
> (`ruff check .`), **dependency audit** (`pip-audit`, or `uv pip audit`), build,
> dev server. pytest is already run-once — no watch trap here. If a role has no
> command, say so; a gate cannot invent one.
>
> The audit role is per-ecosystem, not per-repo: a repo carrying this addon has
> **two** dependency trees, and `pnpm audit` says nothing about the Python one.
> Both run at `/ship`, or the gate covers half of what it claims.
>
> **`ruff format` is scoped to `app/`, and that is a guardrail, not a habit.**
> It REWRITES files from the shell, where no PreToolUse hook can see it: run on
> `.`, it rewrites `tests/services/**` — the frozen half — past the freeze, and
> flips the RED marker's digest so a cycle in progress loses its proof. Whatever
> reformats the test tree must carve it out:
>
> ```toml
> [tool.ruff]
> extend-exclude = ["tests/services"]
> ```
>
> `ruff check` only reads, so it stays repo-wide. `--fix` writes: scope it too.
>
> **`python -m pytest`, never the bare `pytest` script**, everywhere in this file
> and in every gate: the console script does not add the project root to
> `sys.path`, so `from app.…` fails before a single test runs.
>
> **`ruff check` belongs in `/ship`, not only in the hook.** `ruff-on-save.sh` is
> deliberately **non-blocking**. The gate is the only thing that catches an
> unused import shadowing a real one, a mutable default argument, a bare
> `except`, a missing `await` (`RUF006`) — `pytest` stays green on all of them.

## Layers

```
api/        → HTTP only (routing, validation, status codes, dependencies)
services/   → Business logic — the only layer that touches models/ and external clients
models/     → SQLAlchemy ORM
schemas/    → Pydantic request/response (shared between api/ and services/)
core/       → Config, auth, DB session, external clients, exceptions, middleware
```

```
app/
├── main.py               # FastAPI app, middlewares, exception handlers
├── api/
│   ├── deps.py           # get_db, get_current_user, get_current_tenant
│   ├── router.py         # Root APIRouter — every sub-router registers here
│   └── {domain}.py       # One file per domain
├── services/
│   ├── {domain}.py       # Simple service
│   └── {pipeline}/       # Multi-step pipeline: pipeline.py + one file per step
├── models/
│   ├── base.py           # DeclarativeBase, TenantMixin, TimestampMixin, uuid4_str
│   └── {entity}.py
├── schemas/{domain}.py
└── core/
    ├── config.py, database.py, auth.py, exceptions.py, middleware.py
    └── {client}.py       # One module per external client (LLM, vector DB, storage)
```

## Non-negotiables

- No `Any` in type hints → proper types, generics, `Protocol`, `TypeVar`
- Every function signature typed: parameters **and** return
- `async def` + `await` for every I/O operation — a sync call in an async path
  blocks the whole event loop
- **No business logic in `api/`** — no SQLAlchemy query, no external client call
- **No HTTP in `services/`** — no `HTTPException`, no `Request`/`Response`,
  no status codes. Business exceptions from `core/exceptions.py`, converted by
  the global handler
- External clients (LLM, vector DB, storage) only in `core/{client}.py` and the
  services declared as their owners — never in `api/`
- Every endpoint carries its auth dependency: `Depends(get_current_user)`
- Every DB query and every vector query filters by the isolation key
  (`tenant_id` / `user_id`) <!-- FILL: single-tenant app? delete this line and
  the multi-tenant checks in the backend commands. -->
- User-facing messages in <user language>, logs and errors in English
- Pydantic v2 for every request/response body; SQLAlchemy 2.0 style
  (`mapped_column`, `DeclarativeBase`)
- Never write SQL by hand outside a migration → `/database:migration`

## Tests — order, freeze, floor

**This section is the only statement of where the backend stands in the kit's
TDD apparatus.** The *principle* — what a genuine RED is, why the file freezes,
what the exception list is for — is `05-testing.md` and is not restated here.
This section says what is **different** on Python.

### `app/services/` is test-first and frozen. Nothing else is.

The TypeScript trio keys on a filename ending in `\.tsx?$`, so a `.py` never
matches it. Python has its own trio, wired by `install.sh --fastapi`:

| Hook | Event | Refuses |
| --- | --- | --- |
| `tdd-prove-red-py.py` | Post | recording a marker for a failure that proves nothing |
| `tdd-require-red-py.py` | Pre | **creating** a service module with no marker for its test |
| `tdd-freeze-tests-py.py` | Pre | editing a proved test file, except a pure insertion |

They share `.claude/.tdd-red/` and `.claude/.tdd-unfrozen` with the TypeScript
cycle and derive marker names the same way, so one exception list covers both and
`/review`'s `tests` dimension works on a backend diff without knowing the
language. Writing them from the shell is denied like their TypeScript twins
(`prevent-destructive-commands.sh`, `CWK_TDD_PY_TARGET_RE`).

**Scope: `app/services/**`, in both spellings** — the package this file
prescribes, and the flat `app/services.py` a small service ends up with. `api/`,
`models/`, `schemas/` and `core/` stay test-after. Widening the scope is one
constant: `TEST_FIRST_DIRS` in `tdd_py_lib.py`.

**The test↔module mapping is the mirror**, which is why `tests/` mirroring `app/`
(`patterns/pytest-backend.md`) is load-bearing rather than a convention:
`app/services/project.py` ↔ `tests/services/test_project.py`. Break the mirror
and the hooks cannot find the test at all.

> **`/audit:mutation` does NOT cover this layer.** It runs Stryker with the
> vitest runner, which cannot mutate Python. So a frozen `app/services/` file is
> granted the authority of a specification and **nothing verifies it deserves
> it**. Until `mutmut` or `cosmic-ray` and a Python section in the command exist,
> never tell a reader the backend freeze is mutation-checked.

### Two pytest facts you need before running a gate

1. **A green run can exit non-zero.** With the `addopts` below in force, running
   one file prints `1 passed` and exits **1**, because whole-package coverage is
   under the floor. Never read "exit ≠ 0" as a failing test without looking.
2. **`@pytest.mark.skip` has no lint behind it.** On the front end
   `@vitest/eslint-plugin` fails the build on `it.skip`; ruff has no equivalent.
   **Two** mechanisms see it here, and they cover different moments: the freeze
   refuses a skip introduced by an insertion, and the prover refuses to write a
   RED marker for a file that carries one. The second is the one that matters
   most — a skip present at RED time was armed and shipped frozen, i.e. the
   specification switched off inside a file that can no longer be corrected,
   and the freeze never looked because it only inspects what an edit *adds*.

How the provers work around pytest's exit codes is in
`.claude/guides/07-backend.md` — read it before changing one of them.

### The layers that stayed test-after — still not a discount

Test-after is an ordering, not a discount. The gate is unchanged:

| Layer | Tests | Level |
| --- | --- | --- |
| `services/` (business logic) | **Required** | mandatory |
| `api/` (routes) | **Required** | mandatory |
| `core/` (auth, config, exceptions) | **Required** | mandatory |
| `models/` | as needed | optional |
| Alembic revisions | n/a | — |

- New or modified business logic **without its tests in the same diff = FAIL**
  (`05-testing.md`, "Required (gate)").
- Every service taking an isolation key gets its **cross-tenant test**. Nothing
  else enforces isolation — no RLS, no error, no warning. It is frozen once
  written, so it belongs in the `/plan` test plan, not in the review.
- Assert the **behaviour**: the returned value or an observable effect, not that
  a mock was called (`patterns/pytest-backend.md`, "Mocking external services").
- **Outside `services/`, the test file is not frozen**, so nothing stops it being
  adjusted into agreeing with a bug. That is `/review`'s `tests` dimension on
  `api/`, `core/` and `models/` — a heavier duty there than on the front end, so
  say it in the review request.

### Coverage floor

| Scope | Lines | Branches |
| --- | --- | --- |
| `app/services/`, `app/core/` | 90 | 85 |
| `app/api/` | 80 | 75 |

> **Four numbers are declared and one is enforced.** `--cov-fail-under` is a
> single global threshold — coverage.py has no per-path floor, so the config
> below fails the build at **85 % overall** and nothing mechanical distinguishes
> `services/` from `api/`. The table is a **review criterion**: `/review`'s
> `tests` dimension reads the per-scope numbers off the `term-missing` report.
> Enforcing them needs a per-package run in `/ship`, which is a decision about
> gate time, not a config line.

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
# WITHOUT THIS LINE NOTHING RUNS: the console script does not put the project
# root on sys.path, and tests/conftest.py imports `from app.main import app` on
# its first line. Either this, or `pip install -e .`, or always `python -m
# pytest`. Pick one and write it down — the failure reads as a broken test.
pythonpath = ["."]
addopts = "--cov=app --cov-report=term-missing --cov-fail-under=85"

[tool.coverage.run]
source = ["app"]
omit = ["app/main.py", "*/alembic/*", "*/tests/*"]

[tool.coverage.report]
exclude_also = ["if TYPE_CHECKING:", "raise NotImplementedError"]
```

A floor is a floor, not a target. It makes an unwalked branch impossible to ship
silently, nothing more.

## File size thresholds

Over-threshold in review = **Minor**. Split with `/refactor:split`.

| Type                 | Max lines |
| -------------------- | --------- |
| `api/{domain}.py`    | 200       |
| `services/{name}.py` | 300 (else split into a `{name}/` package with one file per step) |
| `models/{entity}.py` | 150       |
| `schemas/{domain}.py`| 200       |

## Dependency flow

```
api/ → services/ → models/ (SQLAlchemy) → PostgreSQL
                 → core/{client} → LLM / vector DB / storage
       schemas/ ← api/ and services/ both read it, it depends on nothing
```

A `services/` module importing `fastapi` is a bug. A `models/` module importing
a service is a cycle waiting to happen.

## Patterns (read IF creating)

- Clean architecture, endpoint/service/model/schema shapes →
  `.claude/skills/patterns/fastapi-architecture.md`
- Tests → `.claude/skills/patterns/pytest-backend.md`
- Full CRUD scaffold → `.claude/skills/templates/endpoint.md`
- Auth: hashing, JWT, the identity dependency, reset flows →
  `.claude/skills/patterns/fastapi-auth.md`
- Settings, secrets, environment flags →
  `.claude/skills/patterns/config-settings.md`
- File upload, storage, download, deletion →
  `.claude/skills/patterns/file-upload.md`
- Document ingestion pipeline → `.claude/skills/patterns/rag-ingestion.md`
- Retrieval + generation + SSE → `.claude/skills/patterns/rag-chat.md`

Rationale — the measured pytest behaviours and the scope argument:
`.claude/guides/07-backend.md`.
