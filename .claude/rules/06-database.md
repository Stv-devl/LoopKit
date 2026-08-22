<!-- budget: 50 lines · /kit:doctor rules-budget -->
# Database & Migrations

<!-- FILL: this whole file. If the repo owns no schema, replace it with
     "No database owned by this repo — the API is the boundary." and delete
     the /database:migration command. -->

## Provider

<PostgreSQL / MySQL / SQLite / a managed BaaS — name it>

## Migration Rules

**Always use the migration command:**

```
/database:migration
```

**Forbidden:**

- Manually creating SQL files in the migrations folder
- Modifying the DB directly without a migration

The command owns the rest: naming
(`<migrations folder>/YYYYMMDDHHMMSS_description.sql`), the UP file, the
rollback instructions, the execution commands and the verification queries.

## Inspection commands

<!-- FILL: the read-only commands an agent may run to see the real state —
     schema dump, table sizes, unused indexes, slow queries, migration state.
     `/research` runs these; without them it guesses from the schema file. -->

```bash
<schema dump command>
<migration state command>
```

## Authorization

<!-- FILL: where the real barrier is (row-level security, API middleware,
     application checks). The `security` reviewer gates against this line. -->

> Using Supabase? Replace this file with `addons/supabase/rules/06-database.md`.
