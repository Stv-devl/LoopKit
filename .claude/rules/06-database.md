<!-- budget: 25 lines · /kit:doctor rules-budget -->
# Database & Migrations

<!-- FILL: if no owned schema, say “No database owned — API is boundary” and
delete `/database:migration`. Otherwise fill provider, inspection and barrier. -->

## Provider
<PostgreSQL / MySQL / SQLite / managed BaaS>

## Migration and inspection

All schema changes go through `/database:migration`; never hand-write migration
SQL or mutate the database outside a migration. That command owns naming, UP,
rollback, execution and verification. `/loop:research` uses these read-only
inspection commands:

```bash
<schema dump command>
<migration state command>
```

## Authorization
<!-- FILL: real server barrier — RLS, middleware, or application checks. -->

Supabase projects replace this file with `addons/supabase/rules/06-database.md`.
