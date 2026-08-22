---
description: Creates a SQLAlchemy model (mixins, FKs, indexes) and prepares its migration
context: fork
disable-model-invocation: true
argument-hint: [model and fields, e.g. "Lot (name, code, project_id)"]
---

# Model Agent

Creates a SQLAlchemy 2.0 model and prepares the Alembic revision.

## Read first

`.claude/skills/patterns/fastapi-architecture.md` (Model section) ·
`.claude/rules/06-database.md`

## Process

1. **Parse**: entity, fields, relations, constraints
2. **Inspect**: `models/base.py` (mixins, `uuid4_str`), neighbouring models,
   the latest revision in `alembic/versions/`
3. **Write** `models/{name}.py`
4. **Export** it in `models/__init__.py` — Alembic autogenerate only sees
   imported models; an unexported model produces an **empty revision**
5. **Generate**: `alembic revision --autogenerate -m "add {name} table"`
6. **Read the generated file** and fix what autogenerate got wrong

## Shape

```python
class Feature(Base, TenantMixin, TimestampMixin):
    __tablename__ = "features"
    __table_args__ = (
        Index("ix_features_tenant_project", "tenant_id", "project_id"),
    )

    id: Mapped[str] = mapped_column(primary_key=True, default=uuid4_str)
    name: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="active")
    project_id: Mapped[str] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"))

    project: Mapped["Project"] = relationship(back_populates="features")
```

## Rules

- `TenantMixin` on every business entity — it carries `tenant_id` **and its index**
- `TimestampMixin` always
- `uuid4_str` for string PKs
- Composite index `(tenant_id, <filtered column>)`; `tenant_id` alone does not
  cover a filtered list query
- `ForeignKey(..., ondelete=...)` chosen on purpose, not left to the default
- `Mapped[T]` required / `Mapped[T | None]` nullable
- `String(N)` with a length, never bare `String`
- `back_populates`, never `backref`
- No `Any`

## Autogenerate traps

- A **rename** comes out as drop + add → data loss. Rewrite as
  `op.alter_column(..., new_column_name=...)`.
- A **type change** often needs `postgresql_using`.
- Server defaults, `CHECK`, partial indexes, extensions: usually missed.
- Objects created outside the models (views, triggers, jobs) can be **dropped**.

## Checklist

- [ ] Both mixins applied
- [ ] PK via `uuid4_str`
- [ ] Composite index on the real filter pattern
- [ ] FK with explicit `ondelete`
- [ ] `String(N)` everywhere
- [ ] Exported in `models/__init__.py`
- [ ] Revision generated, **read**, and corrected
- [ ] `alembic upgrade head` then `alembic downgrade -1` both work

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
