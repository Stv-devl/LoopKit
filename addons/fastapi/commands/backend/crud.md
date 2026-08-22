---
description: Generates a full CRUD (model → schema → service → endpoint → migration → tests)
context: fork
disable-model-invocation: true
argument-hint: [entity and fields, e.g. "Lot (name: str, code: str, project_id: FK)"]
---

# CRUD Agent

Generates a complete REST CRUD for one entity.

## Read first

- `.claude/skills/templates/endpoint.md` — the full scaffold
- `.claude/rules/07-backend.md` — layer rules
- `.claude/skills/patterns/pytest-backend.md` — test shapes

## Process

1. **Parse**: entity, fields, types, FKs, constraints
2. **Inspect**: `models/base.py`, existing models/schemas/services/api,
   `api/router.py`, `tests/conftest.py` (which fixtures already exist)
3. **Write in this order** — each step depends on the previous one:

| Step | File | Must contain |
| ---- | ---- | ------------ |
| 1 | `models/{name}.py` | `TenantMixin` + `TimestampMixin`, composite indexes, export in `__init__.py` |
| 2 | `schemas/{name}.py` | Create, Update (partial), Response, ListResponse |
| 3a | `tests/services/test_{name}.py` | **first** — the layer is test-first and frozen (`07-backend.md`). RED before 3b exists |
| 3b | `services/{name}.py` | create, get_by_id, list_all (paginated), update, delete — all tenant-filtered |
| 4 | `api/{name}.py` | POST 201, GET list, GET by id, PATCH, DELETE 204 + registration |
| 5 | migration | `alembic revision --autogenerate -m "add {name} table"`, **then read the generated file** |
| 6 | tests | `tests/api/test_{name}.py` — the service test was step 3a, not here |

4. **Verify**: `python -m pytest tests/ -v --tb=short` and `ruff check .`

## Migration warning

`--autogenerate` emits a rename as drop + add (data loss), misses server
defaults and partial indexes, and can drop objects created outside the models.
Read the revision before it is applied — every time.

## Tests to write

Happy path · 422 on invalid payload · 404 on unknown id · **cross-tenant access
returns nothing** · pagination · empty list returns `[]`.

## Checklist

- [ ] Model with mixins + indexes, exported
- [ ] 4 schemas
- [ ] Service: 5 methods, all tenant-filtered
- [ ] 5 routes, each with `Depends(get_current_user)`
- [ ] Router registered
- [ ] Migration generated **and read**
- [ ] API + service tests, isolation included
- [ ] `python -m pytest -v` green, `ruff check .` clean

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
