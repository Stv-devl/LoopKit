---
description: Whole-backend security audit (FastAPI + PostgreSQL + vector store)
context: fork
agent: Explore
disable-model-invocation: true
argument-hint: [scope, or "everything"]
---

# Backend Security Audit Agent

Read-only, whole-surface. For a single route, use `/backend:audit` instead.

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

Then the patterns that say what "correct" looks like here:

`.claude/skills/patterns/config-settings.md` (what a safe default looks like) ·
`.claude/skills/patterns/fastapi-auth.md` (token and identity rules) ·
`.claude/skills/patterns/file-upload.md` (upload and download rules)

## Inspect

`app/core/config.py` (secrets, settings) · `app/core/auth.py` (JWT, hashing) ·
`app/api/deps.py` · every file in `app/api/` · `app/services/` ·
`app/models/` (what is stored in clear) · `app/main.py` (middlewares, handlers) ·
`Dockerfile`, `.env.example` (never `.env`)

## Checklist

### Authentication

- [ ] Password hashing with a slow KDF (bcrypt/argon2), per-password salt
- [ ] Short-lived access token + refresh, expiry actually verified
- [ ] Algorithm pinned on decode (`algorithms=["HS256"]`) — an unpinned decode
      accepts `alg: none` on some libraries
- [ ] Token signature verified on every request, not just at login
- [ ] No user-controlled field trusted for identity (`tenant_id` from the token,
      never from the body)

### Authorization

- [ ] Every route has an auth dependency — enumerate them, do not sample
- [ ] Role checks where roles exist, and they are checked server-side
- [ ] Object-level check on every id taken from the path

### Isolation

- [ ] Every SQL query filters on the isolation key
- [ ] Every vector query filters on it too — the vector store has no RLS
- [ ] Deleting an entity deletes its derived data (chunks, vectors, files)

### Input

- [ ] Pydantic on every body, bounded strings and lists
- [ ] SQLAlchemy expressions only — no f-string SQL, no `text()` with interpolation
- [ ] Uploads: extension **and** content type **and** size checked; stored under a
      generated name, never the client's filename
- [ ] No path built from user input without normalisation (path traversal)
- [ ] SSRF: no server-side fetch of a user-supplied URL without an allowlist

### Configuration

- [ ] No secret hardcoded, none in a default value, none in a log line
- [ ] CORS: explicit origins, never `["*"]` with credentials
- [ ] `debug=False` in production, docs routes gated if the API is not public
- [ ] Rate limiting present on auth routes and on anything that costs money
      (LLM, embeddings, exports)
- [ ] Generic error responses — no stack trace, no ORM message, no file path

### LLM-specific

- [ ] Prompt injection: retrieved document text is data, never instructions —
      the system prompt says so, and tool/function access is not granted to it
- [ ] Provider keys server-side only
- [ ] Per-tenant spend bounded (rate limit or quota), or the bill is unbounded
- [ ] Model output that reaches SQL, a shell, or a URL is validated against a
      whitelist first

### Dependencies

- [ ] `pip-audit` clean of CRITICAL/HIGH (see `/backend:deps-audit`)

## Severity

| Score  | Severity | Fix within |
| ------ | -------- | ---------- |
| 75-125 | CRITICAL | 24h        |
| 50-74  | HIGH     | 1 week     |
| 25-49  | MEDIUM   | 1 month    |
| 1-24   | LOW      | continuous |

## Output

Same shape as `/backend:audit`: id, `file:line`, impact, fix. Read-only —
propose, apply nothing.

## Task: $ARGUMENTS
