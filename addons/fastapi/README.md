# Addon — FastAPI / Python (+ RAG)

The core kit is a front-end kit: its rules, hooks and patterns describe a React
app talking to *some* backend. This addon adds the other half — a FastAPI +
Python service, its layer discipline, its test and audit commands, and the RAG
pipeline patterns (ingestion, retrieval, streaming) if the service has one.

Ported from a production FastAPI + PostgreSQL + Qdrant + LLM codebase, then
generalised: the provider names are `<FILL>`, the shapes are real.

## Install

From the project root, after installing the core kit:

```bash
KIT=../loopkit/addons/fastapi
cp $KIT/rules/*.md                        .claude/rules/
mkdir -p .claude/commands/backend .claude/commands/database .claude/commands/refactor
cp $KIT/commands/backend/*.md             .claude/commands/backend/
cp $KIT/commands/database/migration.md    .claude/commands/database/
cp $KIT/commands/refactor/clean-python.md .claude/commands/refactor/
cp $KIT/skills/patterns/*.md              .claude/skills/patterns/
cp $KIT/skills/templates/endpoint.md      .claude/skills/templates/
cp $KIT/hooks/*.py $KIT/hooks/*.sh        .claude/hooks/
chmod +x .claude/hooks/*.sh .claude/hooks/*.py
```

Two files **overwrite** their core counterpart: `rules/06-database.md`
(Postgres + SQLAlchemy + Alembic) and `commands/database/migration.md`
(Alembic revisions instead of hand-written `.sql` — the core version
contradicts the Alembic rule). `rules/07-backend.md` is new.

Or, from the kit: `./install.sh /path/to/project --fastapi`.

## Wiring

`./install.sh <project> --fastapi` now wires **what it owns** — meaning only the
files this run just wrote, never one that already existed:

| Wired automatically | Condition |
| --- | --- |
| The six hooks in `settings.json` | the kit wrote that `settings.json` (otherwise they land in the `.new`, for you to merge) |
| `@07-backend.md` in the `CLAUDE.md` rules index | same |
| `app\|alembic` in `PROTECTED_DIRS` | same |

Everything below needs to know what **your** project does, and stays manual.
None of it is optional: a guardrail that is not wired is indistinguishable from
a guardrail that found nothing.

### 1. `.claude/rules/01-stack.md` → the backend row and the data-client table

Fill "Backend" with FastAPI, and answer the table honestly. On a FastAPI stack
the answer to **server-side authorization** is usually *not* RLS — it is the
`WHERE tenant_id = …` clause in `services/`. Which means the barrier is code, a
missing filter is a silent leak, and the `security` reviewer needs to be told
that. Write it down.

On the front-end side this is the easy case for the mock layer: the client is
plain REST over `fetch`, so `.claude/skills/patterns/msw.md` applies as written —
no addon-specific handler shapes, no SDK interception surprise. Match your own
route paths and you are done.

### 2. `.claude/rules/00-project.md` → the commands

Add the backend half of the **six** gate roles: `python -m pytest` (run-once, no
watch trap — and `-m`, never the bare script: see `07-backend.md`),
`mypy app` or `pyright` (typecheck), `ruff check .` (lint), **`pip-audit`
(dependency audit)**, `docker build` (build), `uvicorn --reload` (dev). A gate
cannot invent a script that does not exist.

> **Six, not five — the dependency audit is the one that used to be dropped
> here.** `07-backend.md` states it in the same breath as the others ("a repo
> carrying this addon has **two** dependency trees, and `pnpm audit` says
> nothing about the Python one. **Both run at `/loop:ship`, or the gate covers half
> of what it claims**"), and on a backend-only repo it is the *only* CVE check
> that would run at all. `/backend:deps-audit` exists — what was missing is its
> place in the gate.

### 3. `.claude/commands/loop/ship.md` → the gates

**This is the edit everyone forgets, and it makes `/loop:ship` useless on a Python
repo.** The gate block is written in `pnpm`: on a backend-only project none of
those five commands exist. Add the backend ones alongside (the file already
carries a `<!-- FILL -->` right there), or replace them outright if the repo has
no front end:

```bash
python -m pytest        # run-once, no watch mode. `-m` puts the root on sys.path
mypy app                # typecheck
ruff check .            # lint — the hook does not block; this does
pip-audit               # known CVEs in the Python tree (uv: `uv pip audit`)
docker build .          # build
```

`pip-audit` follows `00-project.md`'s decision rule, unchanged: a high/critical
advisory **with a fix available** is a red gate — bump it. One with **no fix
published** is not a wall — announce the package, the advisory and whether the
vulnerable path is even reachable, and let the user decide. Swallowing it
silently is the one forbidden answer.

### 4. `.claude/agents/reviewer.md` → the backend dimension

The reviewer reads "only the rule files tied to your assigned dimensions", and
that list names front-end rules only. Add `07-backend.md` to the `architecture`,
`tests` and `security` dimensions, or a backend diff is reviewed against the
rules of a React app.

### 5. `.claude/rules/02-architecture.md` → the Backend section

Replace "None — this repo is front-end only" with:

```
app/
├── main.py               # app, middlewares, exception handlers
├── api/                  # HTTP only — routing, validation, status codes
│   ├── deps.py           # get_db, get_current_user
│   └── router.py         # root APIRouter
├── services/             # business logic — the only layer touching models/ and clients
├── models/               # SQLAlchemy ORM
├── schemas/              # Pydantic request/response
└── core/                 # config, database, auth, exceptions, middleware, clients
```

Rules: no business logic in `api/` · no `fastapi` import in `services/` ·
business exceptions converted by one global handler · every query filtered by
the isolation key · async everywhere. Details in
`.claude/rules/07-backend.md`; patterns in
`.claude/skills/patterns/fastapi-architecture.md`.

### 6. `.claude/rules/05-testing.md` → nothing to do

It already points here. `05-testing.md` carries the block that says it describes
the TypeScript cycle, that a repo with this addon has a Python twin, and that
`07-backend.md` is the only copy of what differs. It also names what does **not**
change and is therefore not repeated on the backend side: the ordering inside a
file, "the test name is the spec", "assert the behaviour, not the call", and the
single `.claude/.tdd-unfrozen` shared by both cycles.

This used to be a manual edit, which put the one line tying the two cycles
together in the list of things nobody does.

### 7. `enforce-backend-layers.py` → the configuration

`MODULE_ROOT` (default `app/`, matched on a path boundary), `SESSION_NAMES` (how
this project names its `AsyncSession`) and `EXTERNAL_CLIENTS` (your LLM / vector
/ storage clients and the modules allowed to import them). Left empty, check 3
is off.

> `.claude/hooks/enforce-architecture.py` (the front-end one) is untouched: it
> only inspects `src/**/*.ts`.

### 8. The hooks, if you wire them by hand

```json
{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/no-any-type-py.py",         "timeout": 5 },
{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/enforce-backend-layers.py", "timeout": 5 },
{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-require-red-py.py",     "timeout": 5 },
{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-freeze-tests-py.py",    "timeout": 5 }
```
under the `Write|Edit` PreToolUse matcher, and
```json
{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ruff-on-save.sh",   "timeout": 30 },
{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/tdd-prove-red-py.py", "timeout": 180 }
```
under `Write|Edit` PostToolUse.

> **The prover's timeout is 180, not 30, and it is not padding**: it runs pytest.
> Its own internal ceiling is 150 s, deliberately under the harness timeout, so a
> slow suite comes back with a message instead of being killed silently — and a
> TDD hook that dies without a word reads exactly like a gate that passed.
>
> The three `tdd-*-py` hooks ship with `tdd_py_lib.py` beside them. It is a
> module, not a hook: never declare it in `settings.json`. Copy it along with
> them or none of the three can import.

> **Keep the `$CLAUDE_PROJECT_DIR/` prefix** — every hook in the core
> `settings.json` carries it. A bare `.claude/hooks/…` resolves against the
> process working directory, which is not guaranteed to be the project root: the
> hook then fails to start, and a hook that never runs looks exactly like a hook
> that found nothing.

`english-comments.py` (a core hook) now covers `.py` as well: French comments and
docstrings are refused, same rule as in TS, nothing extra to declare.

## Commands

| Command | What it does |
| ------- | ------------ |
| `/backend:endpoint` | One endpoint: schema + service + route + registration |
| `/backend:crud` | Full CRUD: model → schema → service → routes → migration → tests |
| `/backend:model` | SQLAlchemy model + Alembic revision, with the autogenerate traps |
| `/backend:service` | A service or a multi-step pipeline, HTTP-free |
| `/backend:test` | pytest tests for an endpoint or a service |
| `/backend:sse-stream` | An SSE streaming route (LLM tokens, job progress) |
| `/backend:middleware` | CORS, rate limit, logging, timing, size limit |
| `/backend:rag` | Build or extend a RAG pipeline step |
| `/backend:rag-audit` | Diagnose bad answers — backwards through the pipeline |
| `/backend:audit` | Read-only audit of one route or service |
| `/backend:security` | Whole-backend security audit, LLM section included |
| `/backend:perf` | N+1, sequential awaits, missing pagination, blocking sync calls |
| `/backend:deps-audit` | CVEs, licences, dead and ghost dependencies |
| `/database:migration` | Alembic revision — overrides the kit's SQL-file version |
| `/refactor:clean-python` | Dead Python code, minus the side-effect imports |

They slot into the existing loop: `/loop:research` → `/loop:interface` (skip, no UI) →
`/loop:plan` → EXECUTE → `/loop:review` → `/loop:ship`. The backend commands are the *build*
tools EXECUTE reaches for; the audit ones are what `/loop:review` findings turn into
when a dimension needs depth.

Two properties of `context: fork`, which all fifteen carry, are worth knowing
before you run one:

- **A forked skill runs in the background** (Claude Code v2.1.218+), so the turn
  that launched it does not wait, and *its edits land outside your session's
  checkpoints — `/rewind` will not undo them*. On the commands that write six
  files at once (`/backend:crud`, `/backend:endpoint`), add `background: false`
  to the frontmatter if you would rather keep the result inline and undoable.
- **The five audit commands use `agent: Explore`**, which skips `CLAUDE.md` to
  keep its context small. They therefore start with **none of `.claude/rules/`
  loaded** — which is why each one now opens by naming the rule files it must
  read. Delete that block and the audit judges your repo against a generic
  FastAPI app.

## Files

| File | Role |
| ---- | ---- |
| `rules/07-backend.md` | Layers, non-negotiables, commands, size thresholds |
| `guides/07-backend.md` | Le rationnel : les trois comportements de pytest mesurés, l'argument de périmètre, pourquoi le plancher est un critère de review. Copié dans `.claude/guides/`, **jamais chargé au démarrage** |
| `rules/06-database.md` | Postgres + SQLAlchemy + Alembic, autogenerate traps |
| `commands/database/migration.md` | Alembic flavour of `/database:migration` |
| `skills/patterns/fastapi-architecture.md` | Endpoint/service/model/schema shapes, isolation, background work |
| `skills/patterns/fastapi-auth.md` | Hashing, JWT access/refresh, the identity dependency, reset flows |
| `skills/patterns/config-settings.md` | Settings, required secrets, environment flags, startup checks |
| `skills/patterns/file-upload.md` | Upload validation, storage layout, download, deletion, orphans |
| `skills/patterns/pytest-backend.md` | conftest, fixtures, mocking, the isolation test |
| `skills/patterns/rag-ingestion.md` | file → chunks → vectors, status machine, payload |
| `skills/patterns/rag-chat.md` | rewrite → retrieve → context → stream, SSE contract |
| `skills/templates/endpoint.md` | Full CRUD scaffold to copy |
| `hooks/enforce-backend-layers.py` | Blocks HTTP-in-services, DB-in-api, client outside its owner |
| `hooks/no-any-type-py.py` | Blocks `Any` hints in `.py` — tokenised, so docstrings and strings are exempt |
| `hooks/ruff-on-save.sh` | `ruff format` + `ruff check` feedback |

Not a RAG app? Delete the two `rag-*.md` patterns and the two `rag*` commands.
A pattern describing a pipeline that does not exist is how an agent writes an
import to nothing.

## Traps this addon encodes

- **`alembic revision --autogenerate` is a draft, not a migration.** It turns a
  column rename into drop + add (data loss), skips server defaults, partial
  indexes and extensions, and can *drop* objects created outside the models.
  Read every revision before applying it.
- **An unexported model produces an empty revision.** Autogenerate only sees
  models imported by the time `env.py` runs — hence the `# noqa: F401`
  re-exports that `/refactor:clean-python` must never delete.
- **A secret with a default value boots.** The app starts, signs tokens with a
  string that is published in the repository, and nothing warns anyone. Required
  fields, no defaults, validated at import.
- **A `dev_mode: bool = True` turns its bypass on by default.** One missing
  environment variable in one deploy and the API serves unauthenticated requests
  on a seeded admin account. A flag that disables a safety defaults to safe.
- **`jwt.decode` without `algorithms=[...]`** lets the token declare its own
  algorithm — including `none` on some libraries.
- **`await file.read()` with no argument** loads the whole upload into memory
  before any size check can run; the limit that follows is decoration.
- **The usual `client` fixture overrides `get_current_user`**, so it can never
  prove a route is protected. Keep a second, unauthenticated client — otherwise
  a route that loses its dependency stays green forever.
- **Isolation is a WHERE clause, not a database feature.** No RLS, no error, no
  warning: a forgotten filter returns another customer's rows and the test suite
  stays green. That is why every service gets a cross-tenant test.
- **`db.get(Model, id)` bypasses the tenant filter by construction.**
- **A missing `pytest.mark.asyncio` skips the test silently** when
  `asyncio_mode` is not `auto`. Green suite, zero assertions run.
- **`app.dependency_overrides` is process-global.** A fixture that dies before
  its cleanup leaks a fake authenticated user into every later test file.
- **SQLite is not PostgreSQL.** `JSONB`, `ARRAY`, `ILIKE`, partial indexes and
  `ON CONFLICT` behave differently or not at all.
- **One sync call blocks the whole event loop**, not just its request.
  `requests`, `time.sleep`, a sync SDK client — highest impact per line.
- **`asyncio.gather` on one `AsyncSession` is a bug.** It is not
  concurrency-safe: it fails under load, never in dev.
- **`BackgroundTasks` dies with the worker** and never retries — and the task
  must open its own session, since the request's is closed with the response.
- **Once SSE has sent its first byte the status is 200.** An exception can no
  longer become a 500: catch it, emit an `error` event, and always terminate the
  stream — a client waiting for a terminator that never comes spins forever.
- **But never `yield` that terminator from a `finally`.** It is the obvious way
  to guarantee it, and when the client hangs up mid-stream Python raises
  `RuntimeError: async generator ignored GeneratorExit` instead. Emit it on both
  normal paths; keep `finally` for cleanup that does not yield.
- **One identity shape, or none.** `get_current_user` returns the `User` row
  everywhere in these patterns. A variant returning a dict of claims is
  defensible — but half the routes reading `user.tenant_id` while the other half
  reads `user["tenant_id"]` is a `TypeError` waiting for the first shared helper.
- **Nginx buffers SSE into a single delivery** without `X-Accel-Buffering: no`.
- **Deleting a document must delete its vectors.** Orphaned points keep
  answering questions about a file the user deleted.
- **Retrieved document text is data, never instructions.** Everything that
  reaches the context window is user-controlled input.
