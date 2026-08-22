---
description: Creates Alembic migrations (revision, upgrade/downgrade, indexes) — the only way schema changes enter the repo
context: fork
argument-hint: [migration description]
---

# Migration Agent — Alembic

Creates migrations for this repo's PostgreSQL database. Replaces the kit's
generic SQL-file version: here, schema changes go through Alembic revisions,
never through hand-written `.sql`.

## Core rules

- **Never apply**: propose the revision file and the commands, let the human run
  them. `alembic upgrade head` on a shared database is not an agent's call
- **Inspect first**: `alembic current`, `alembic history -i`, the last two
  revisions in `alembic/versions/`, and the models the change touches
- **One revision per intent** — a rename and a new table are two revisions
- **Every revision has a real `downgrade()`**. `pass` is acceptable only for a
  data-only migration that cannot be undone, and then say so in the docstring

## Process

1. **State of the world**

   ```bash
   alembic current          # where the DB actually is
   alembic history -i       # revisions, and whether the tree has branched
   ```

   Two heads = two sessions generated a revision from the same parent. Fix it
   with `alembic merge` before adding anything, or the next `upgrade head` fails.

2. **Autogenerate the draft**

   ```bash
   alembic revision --autogenerate -m "add lots table"
   ```

   The model must be imported by the time `alembic/env.py` runs — usually via
   `models/__init__.py`. An unexported model produces an **empty revision**, and
   an empty revision looks exactly like "nothing to do".

3. **Read the generated file and fix it.** This is the step that matters; the
   list of what autogenerate gets wrong is below.

4. **Review the SQL it will actually run**

   ```bash
   alembic upgrade head --sql        # offline: prints the SQL, touches nothing
   ```

5. **Hand over the commands**

   ```bash
   alembic upgrade head              # apply
   alembic downgrade -1              # rollback one revision
   ```

6. **Give the verification queries** — the `\d+ <table>` and the count that
   proves the change landed.

## What autogenerate gets wrong, every time

| It emits | Reality | Fix |
| -------- | ------- | --- |
| `drop_column` + `add_column` | a **rename** — that is data loss | `op.alter_column("t", "old", new_column_name="new")` |
| `alter_column(type_=...)` | Postgres refuses an incompatible cast | add `postgresql_using="col::new_type"` |
| nothing | server defaults, `CHECK`, partial and expression indexes | write them by hand with `op.execute` |
| nothing | extensions, views, triggers, `pg_cron` jobs | write them by hand |
| `drop_table` / `drop_index` on objects it did not create | anything made outside the models is invisible to it | delete those lines |
| an empty revision | models not imported in `env.py`, or the DB is not the one you think | check `target_metadata` and the URL |

Nothing here is exotic: it is the same list on every Alembic project, and it is
why a generated revision is a **draft**, not a migration.

## Shapes

### Standard revision

```python
"""add lots table

Revision ID: a1b2c3d4e5f6
Revises: 9f8e7d6c5b4a
"""

revision = "a1b2c3d4e5f6"
down_revision = "9f8e7d6c5b4a"


def upgrade() -> None:
    op.create_table(
        "lots",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("tenant_id", sa.String(36), sa.ForeignKey("tenants.id"), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_lots_tenant_name", "lots", ["tenant_id", "name"])


def downgrade() -> None:
    op.drop_index("ix_lots_tenant_name", table_name="lots")
    op.drop_table("lots")
```

### Adding a NOT NULL column to a populated table

Three steps, never one:

```python
def upgrade() -> None:
    op.add_column("documents", sa.Column("status", sa.String(20), nullable=True))
    op.execute("UPDATE documents SET status = 'ready' WHERE status IS NULL")
    op.alter_column("documents", "status", nullable=False)
```

A single `nullable=False` with no default fails on the first non-empty table —
in production, at the worst moment.

### Index on a large table

```python
def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.create_index(
            "ix_chunks_document", "chunks", ["document_id"], postgresql_concurrently=True,
        )
```

`CONCURRENTLY` cannot run inside a transaction, and Alembic wraps every
migration in one. Without the autocommit block it raises; with a plain
`create_index`, it takes a write lock on the table for the duration.

### Data migration

Use `op.execute` with plain SQL or a lightweight table definition — **never
import your ORM models** into a revision. Models change; a revision must keep
running years later against the schema it was written for.

```python
def upgrade() -> None:
    op.execute("UPDATE documents SET type = lower(type) WHERE type <> lower(type)")
```

## Safety rules

- Destructive change → multi-step across releases: add, backfill, switch reads,
  drop. Never add-and-drop in one revision
- Rename → `alter_column(new_column_name=...)`, never drop + add
- Long backfill → batch it, and say in the docstring how long it ran on a copy
- Check the isolation column: a new business table needs `tenant_id`, its
  index, and its FK, in this same revision
- `--sql` output read before anything is applied to a shared database

## Checklist

- [ ] `alembic current` / `history` inspected, no unmerged heads
- [ ] Revision autogenerated **then read line by line**
- [ ] Renames and type changes corrected by hand
- [ ] Server defaults, checks, partial indexes added by hand
- [ ] `downgrade()` real, or documented as irreversible
- [ ] No ORM model imported in the revision
- [ ] `upgrade head --sql` reviewed
- [ ] Isolation column + index present on new business tables
- [ ] Commands handed over, nothing applied by the agent

## Task: $ARGUMENTS
