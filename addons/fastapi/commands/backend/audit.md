---
description: Audits one FastAPI endpoint or service (auth, validation, errors, isolation, layering)
context: fork
agent: Explore
disable-model-invocation: true
argument-hint: [endpoint or service, e.g. "/api/projects" or "ingestion"]
---

# Backend Audit Agent

Read-only audit of a single endpoint or service. Narrow scope, concrete findings.

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

`app/api/` (the route) · `app/services/` (the logic) · `app/schemas/` (the
contract) · `app/models/` (the storage) · `app/core/` (auth, deps, config) ·
`tests/` (what is actually covered)

## Checklist

### Auth

- [ ] Route carries `Depends(get_current_user)` — check **every** verb, not just GET
- [ ] The isolation key comes from the authenticated user, never from the payload
      or a query param
- [ ] No route reachable before the dependency runs

### Validation

- [ ] Pydantic schema on request **and** response
- [ ] Constraints on inputs (`min_length`, `max_length`, `pattern`, `ge`/`le`)
- [ ] Upload size and content type bounded
- [ ] No raw SQL built from user input

### Isolation

- [ ] Every SQL query filters on the isolation key
- [ ] No `db.get(Model, id)` on a business entity without a tenant re-check
- [ ] Every vector-store query carries the same filter in its payload filter
- [ ] `update` / `delete` go through the same tenant-checked read as `get_by_id`

### Errors

- [ ] Business exceptions, converted by the global handler — one error shape
- [ ] No stack trace or internal identifier in a response
- [ ] Logs in English, user messages in the product language, no secrets logged

### Layering

- [ ] No business logic in `api/`
- [ ] No SQLAlchemy query in `api/`
- [ ] No `fastapi` import in `services/`
- [ ] External clients only in their owning modules
- [ ] `async`/`await` on every I/O — no sync client in an async path

### Tests

- [ ] Happy path, validation, not found
- [ ] **Cross-tenant access is tested** (nothing else enforces isolation)
- [ ] External services mocked at the import site

## Output

```
# Audit: [target]

## Score: X/100

## CRITICAL
[A-001] Title
- Location: file:line
- Impact: what an attacker or a user actually gets
- Fix: the code

## HIGH / MEDIUM / LOW
[...]

## Not verified
[what could not be checked without running it]
```

Read-only: report, change nothing. A finding without `file:line` and a concrete
failing input is a suspicion — mark it as such rather than inflating it.

## Task: $ARGUMENTS
