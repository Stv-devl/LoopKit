---
description: Creates a complete FastAPI endpoint (schema + service + route + registration)
context: fork
disable-model-invocation: true
argument-hint: [endpoint, e.g. "lots" or "PATCH /api/projects/:id/status"]
---

# Endpoint Agent

Creates a FastAPI endpoint that respects the layer discipline.

## Read first

- `.claude/skills/templates/endpoint.md` — the shapes, source of truth
- `.claude/rules/07-backend.md` — the layer rules, and the test gate
- `.claude/skills/patterns/pytest-backend.md` — the fixtures, before writing a
  test that clones one that exists

## Process

1. **Parse** the request: which verbs, which entity, which fields
2. **Inspect** the existing code before writing anything:
   - `app/models/base.py` — available mixins
   - `app/schemas/`, `app/services/`, `app/api/` — the conventions actually used
     (service class vs module functions, routing style)
   - `app/api/router.py` — where the router gets registered
3. **Write**, in this order:
   - `schemas/{name}.py` — Create, Update (partial), Response, ListResponse
   - `services/{name}.py` — logic, every query filtered by the isolation key
   - `api/{name}.py` — routes, `Depends(get_current_user)` on each
4. **Register** the router in `api/router.py`
5. **Write the tests** — `tests/api/test_{name}.py`. New business logic without
   its tests in the same diff is a **FAIL** at the gate
   (`.claude/rules/07-backend.md`), not a follow-up task.

   > `tests/services/test_{name}.py` is **not** written here: `app/services/` is
   > test-first, so its test comes before step 3 wrote the service, not after.
   > If this endpoint's service carries a branch, drive it with
   > `/backend:service` — writing the service test now means writing it against
   > code that already exists, and the prover refuses to record a red for that.
6. **Verify** with the checklist, then `python -m pytest -x` and `ruff check .`

## Rules

- **Schema**: `ConfigDict(from_attributes=True)` on responses, `Field()` constraints on inputs
- **Service**: every query filtered by `tenant_id` — never `db.get(Model, id)` on a business entity
- **Endpoint**: auth dependency on every route, no logic in the body, delegates to the service
- **Errors**: `NotFoundError` / `ForbiddenError` from `core/exceptions.py`, never `HTTPException` in a service
- **Lists**: `offset` + `limit` Query params, always
- **Types**: no `Any`, explicit return type on every function
- **Async**: `async def` + `await` for all I/O

## Checklist

- [ ] Create + Update (partial) + Response + ListResponse
- [ ] Isolation key filtered in every service method
- [ ] `Depends(get_current_user)` on every route
- [ ] No business logic in `api/`
- [ ] Router registered in `api/router.py`
- [ ] No `Any`, explicit return types
- [ ] Tests written: happy path, 422, 404, **cross-tenant isolation**
- [ ] `python -m pytest -x` green, `ruff check .` clean

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
