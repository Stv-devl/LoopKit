<!-- budget: 140 lines · /kit:doctor rules-budget -->
# Database & Migrations

<!-- OVERRIDE of `.claude/rules/06-database.md`: install.sh copies this file OVER the core one.
     The two drift silently — a correction to the core file does NOT reach
     here. When you edit one, diff it against the other in the same pass. -->

## Provider

Supabase (PostgreSQL)

## Schema workflow

<!-- FILL: keep the line that matches this repo, delete the other. -->

- **Imperative migrations** — hand-authored files in `supabase/migrations/`.
- **Declarative schemas** — desired state in `supabase/schemas/`, migrations
  generated from it. Use this if `supabase/schemas/` exists or `config.toml`
  sets `schema_paths`.

## Migration Rules

**Always use the command:**

```
/database:migration
```

**Forbidden:**

- Creating a migration filename by hand — `supabase migration new <name>` owns
  the timestamp and the history entry
- Hand-writing a migration on a declarative-schema project
- Modifying the DB directly without capturing it in a migration

**Naming format (handled by the CLI):**

```
supabase/migrations/YYYYMMDDHHMMSS_description.sql
```

**The command provides:**

- The migration file (UP only — the CLI runs every statement; see below)
- Rollback instructions, **commented out line by line**
- Execution commands (`supabase migration list` → `supabase db push`)
- Verification queries + `supabase db advisors`

> `supabase db push` applies **every** pending migration, including ones another
> session wrote. `supabase migration list` first, always.

## Authorization

**The server-side barrier is RLS.** Not the client, not the edge function, not
the `where` clause in the gateway — those run on the caller's side of the trust
boundary. This is the section the `reviewer` agent's `db` and `security`
dimensions read.

- **Every table in an exposed schema (`public` by default) has RLS enabled.** A
  table without it is readable by anyone holding the publishable key. A table
  with RLS on and **zero policies** is invisible to everyone — and neither case
  raises an error.
- **Being exposed is separate from RLS.** Depending on the project's Data API
  settings, a new table may not be reachable at all until `anon`/`authenticated`
  are granted access. Grant + enable RLS together, never one without the other.
- **The secret / `service_role` key bypasses RLS entirely.** It belongs in edge
  functions and server-side jobs only, never in anything the browser loads.
- **Never authorize on `user_metadata`** — it is user-editable. Authorization
  claims live in `app_metadata`.
- Policy shape, roles, `SECURITY DEFINER`, views, and the performance rules:
  `.claude/skills/patterns/rls.md`.

## Supabase CLI

```bash
# Local stack
supabase start                          # Boot the local stack
supabase stop                           # Stop it
supabase db reset                       # Rebuild local DB from migrations + seed.sql
supabase status                         # Local URLs and keys

# Schema
supabase db dump --schema public        # Current schema
supabase migration list                 # Migration state (local vs remote)
supabase db diff --linked               # Drift between remote and migrations
supabase db pull <name> --yes           # Capture drift into a new migration
supabase gen types --linked > src/types/database.types.ts   # Generated DB types

# Inspection (read-only)
supabase inspect db table-sizes         # Table sizes
supabase inspect db index-sizes         # Index sizes
supabase inspect db unused-indexes      # Unused indexes
supabase inspect db bloat               # Table/index bloat
supabase inspect db locks               # Active locks
supabase inspect db calls               # Most-called queries
supabase inspect db outliers            # Slowest queries
supabase db advisors                    # Security + performance findings (v2.81.3+)

# Edge functions
supabase functions list                 # Deployed edge functions
```

> The CLI structure changes between versions. `supabase <group> --help` rather
> than guessing a flag. `supabase db query` needs v2.79.0+, `supabase db
> advisors` needs v2.81.3+ — otherwise fall back to the MCP tools (`execute_sql`,
> `get_advisors`) or `psql`.
>
> Installed as a project dependency? Prefix every command
> (`pnpm supabase …` / `npx supabase …`).

## Generated types

`supabase gen types --linked` writes the DB types the data layer builds on.
Regenerate it **in the same change as the migration** — a gateway typed against
last week's schema is how `any` gets back in (see `03-conventions.md`).

<!-- FILL: the exact output path and the script that wraps it, e.g.
     "pnpm db:types" → supabase gen types --linked > src/types/database.types.ts -->

## Supabase features used

<!-- FILL: delete what this project does not use. Each line kept is a surface
     the reviewer will gate against. -->

- Authentication
- Database (PostgreSQL)
- Real-time subscriptions
- Edge Functions
- Storage

## Depth beyond this file

This file is the project's contract. For Postgres and Supabase depth — RLS
edge cases, index strategy, query plans, connection limits, logs — use the
official `supabase` skill and `supabase-postgres-best-practices` skill rather
than duplicating them here. They are maintained upstream; this file is not.
