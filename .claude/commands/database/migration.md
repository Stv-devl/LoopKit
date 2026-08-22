---
description: Creates SQL migrations (DDL, indexes, rollback) — the only way schema changes enter the repo
context: fork
argument-hint: [migration description]
---

# Migration Agent

Creates migrations for this repo's database.

<!-- FILL: the migrations folder, the CLI, and the apply command. Everything
     else on this page is provider-agnostic. Using Supabase? Replace this file
     with addons/supabase/commands/database/migration.md. -->

## Core rules

- **READ-ONLY**: never execute writes, only propose files
- **Inspection**: read the existing migrations in `<migrations folder>/` + a
  read-only schema dump before writing anything
- **Files**: create in `<migrations folder>/` only

## File format

`YYYYMMDDHHMMSS_description.sql` (local timezone)

## Structure

```sql
-- Migration: filename
-- Context: why this migration
-- Impact: perf, storage, compatibility
-- Risks: locks, duration, dependencies

-- UP
BEGIN;
-- DDL (use IF NOT EXISTS)
COMMIT;

-- DOWN
BEGIN;
-- Rollback
COMMIT;
```

## Safety rules

- Destructive changes → multi-step migrations (add, backfill, switch, drop)
- Large tables → create indexes concurrently, outside a transaction
- Always include the DOWN section
- **Redefining an existing object** (`CREATE OR REPLACE` on a function, a view, a
  policy): source the body from the **latest** migration that defines it, never
  from the one the spec cites. Stacked redefinitions are how an improvement gets
  silently reverted.
- New table → it must be covered by the authorization barrier named in
  `.claude/rules/06-database.md`, in the same migration.

## Process

1. Audit the schema (read existing migrations + schema dump)
2. Estimate volume and lock impact
3. Propose the migration file
4. Provide execution steps — and **list the pending migrations first**: an apply
   command runs every pending file, including ones another session wrote
5. Provide verification queries

## Task: $ARGUMENTS
