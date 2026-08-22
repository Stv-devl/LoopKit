---
description: Creates PostgreSQL migrations for Supabase (DDL, RLS, indexes, rollback) — the only way schema changes enter the repo
context: fork
argument-hint: [migration description]
---

# Migration Agent

Creates PostgreSQL migrations for Supabase.

## Step 0 — which schema workflow does this repo use?

Check before writing anything:

| Signal | Workflow | What you do |
| --- | --- | --- |
| `supabase/schemas/` exists, or `config.toml` sets `schema_paths` | **Declarative** | Edit the desired end state in `supabase/schemas/`, then generate the migration (`supabase db diff -f <name>`) and review it. Do **not** hand-write a migration. |
| Neither | **Imperative** | `supabase migration new <name>`, then write the SQL into the file it created. |

Getting this wrong on a declarative project produces a migration that the next
`db diff` immediately contradicts.

## Core rules

- **READ-ONLY**: never execute writes, only propose files
- **Inspection**: read the existing migrations in `supabase/migrations/` +
  `supabase db dump --schema public` before writing anything
- **Files**: create in `supabase/migrations/` only
- **Never invent a filename.** `supabase migration new <name>` owns the
  timestamp and the history entry. Hand-computed `YYYYMMDDHHMMSS` names land out
  of order.

## Structure

The Supabase CLI runs **every statement in the file**. There is no `-- DOWN`
section it will skip: the rollback is written **commented out, line by line**.

```sql
-- Migration: <filename>
-- Context: why this migration exists
-- Impact: perf, storage, compatibility
-- Risks: locks, duration, dependencies

BEGIN;
-- DDL (use IF NOT EXISTS)
COMMIT;

-- Rollback (manual — DO NOT uncomment in this file):
-- BEGIN;
--   ...
-- COMMIT;
```

## Safety rules

- Destructive changes → multi-step migrations (add, backfill, switch, drop),
  one migration per step
- **New table → RLS enabled and covered by policies in the same migration.** On
  Supabase the authorization barrier is RLS: a table in an exposed schema with
  RLS off is readable by anyone holding the publishable key, and a table with
  RLS on and zero policies is invisible to everyone — neither raises an error.
  Policy shape and traps: `.claude/skills/patterns/rls.md`.
- **Index every column a policy predicate touches**, in the same migration.
- **`CREATE INDEX CONCURRENTLY` cannot run in a migration.** It cannot run
  inside a transaction block, and the CLI (v2.92.1+) wraps each migration in a
  pipeline — it fails with `SQLSTATE 25001`. Either use a plain `CREATE INDEX`
  and state the expected lock duration, or keep it out of the migration and
  apply it out of band. Say which you chose.
- **Redefining an existing object** (`CREATE OR REPLACE` on a function, a view,
  a trigger): source the body from the **latest** migration that defines it,
  never from the one the spec cites. Stacked redefinitions are how an
  improvement gets silently reverted.
- Always provide the commented rollback.

## Process

1. Audit the schema — read existing migrations + `supabase db dump --schema public`
2. Estimate volume and lock impact
3. Create the file with `supabase migration new <name>`, then propose its content
4. Provide execution steps — and **list the pending migrations first**:

   ```bash
   supabase migration list          # what is pending, locally and remotely
   supabase db push                 # applies EVERY pending migration
   ```

   `db push` applies every pending file, including ones another session wrote.
   Never push without reading that list.
5. Provide verification queries + `supabase db advisors` (CLI v2.81.3+, else MCP
   `get_advisors`) to catch the security and performance findings the queries miss

## Drift

If `supabase db diff --linked` reports changes nobody wrote, the remote schema
moved without a migration. Capture it instead of overwriting it:

```bash
supabase db pull <descriptive_name> --yes    # writes the drift into a new migration
supabase migration list                       # verify histories now agree
```

## Patterns

**Before starting, read:** `.claude/skills/templates/migration.md` and, for
anything touching policies, `.claude/skills/patterns/rls.md`.

## Task: $ARGUMENTS
