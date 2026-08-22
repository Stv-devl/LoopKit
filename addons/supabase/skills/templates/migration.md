# Migration Template

## Creating the file

**Never hand-compute the filename.** The CLI owns the timestamp format and the
migration history:

```bash
supabase migration new add_notifications_table
# → supabase/migrations/20251014153045_add_notifications_table.sql
```

Then write the SQL into the file it created. Inventing
`YYYYMMDDHHMMSS_description.sql` by hand is how a migration lands out of order
or with a format the CLI later refuses.

> Project on **declarative schemas** (`supabase/schemas/` exists, or
> `config.toml` sets `schema_paths`)? Do not write a migration by hand at all —
> edit the desired end state in `supabase/schemas/` and generate the migration.
> See `.claude/rules/06-database.md`.

## ⚠️ Critical rule about the DOWN section

The Supabase CLI **does not interpret** `-- UP` / `-- DOWN` markers — it runs
**all** the SQL statements in the file, in order. The rollback section MUST be
**commented out line by line** (each line prefixed with `-- `), otherwise the
DOWN runs right after the UP and reverts the migration.

## Structure

```sql
-- Migration: 20251014153045_add_notifications_table.sql
-- Context: Add user notification system
-- Impact: New table, ~0 downtime
-- Risks: None (additive only)

BEGIN;

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT,
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index every column used by an RLS policy — a policy predicate on an
-- unindexed column scans the table on every request.
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Policy shape, three non-negotiable parts:
--   TO authenticated          → without it the policy is also evaluated for anon
--   (select auth.uid())       → evaluated once, not once per row
--   WITH CHECK on UPDATE      → without it a user can reassign user_id to someone else
CREATE POLICY "Users can view own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = user_id);

CREATE POLICY "Users can update own notifications"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "Users can delete own notifications"
  ON public.notifications FOR DELETE
  TO authenticated
  USING ((select auth.uid()) = user_id);

COMMIT;

-- Rollback (manual — DO NOT uncomment in this file):
-- BEGIN;
--   DROP TABLE IF EXISTS public.notifications;
-- COMMIT;
```

> No INSERT policy above on purpose: notifications are written by the backend
> with the secret/service-role key, which bypasses RLS. If the client inserts,
> add a `FOR INSERT ... WITH CHECK ((select auth.uid()) = user_id)` policy —
> `WITH CHECK` is the only clause INSERT has.

Full policy rules (roles, views, `SECURITY DEFINER`, the traps):
`.claude/skills/patterns/rls.md`.

## Indexes on a large table

`CREATE INDEX CONCURRENTLY` **cannot run inside a transaction block**, and the
Supabase CLI (v2.92.1+) wraps each migration in a pipeline — a migration
containing it is rejected with `SQLSTATE 25001`. Two options, pick one:

1. **Plain `CREATE INDEX`** inside the migration. Takes an `ACCESS EXCLUSIVE`
   lock for the duration of the build: fine on a small or cold table, an outage
   on a hot one. Announce the expected duration.
2. **Out of band**: keep the index out of the migration entirely, run it
   yourself against the database, then record it in a follow-up migration
   guarded by `IF NOT EXISTS` so a fresh environment still gets it.

```sql
-- Option 2, run manually (NOT via db push), outside any transaction:
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email ON public.users(email);
```

Say which option you took, and why, in the migration header.

## Add nullable column

```sql
BEGIN;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
COMMIT;
```

## Add NOT NULL column (safe)

Three separate migrations, not three statements in one — the backfill must be
committed and verified before the constraint lands.

```sql
-- Migration 1: add nullable
ALTER TABLE public.users ADD COLUMN role TEXT;

-- Migration 2: backfill (batch it if the table is large)
UPDATE public.users SET role = 'user' WHERE role IS NULL;

-- Migration 3: constrain
ALTER TABLE public.users ALTER COLUMN role SET DEFAULT 'user';
ALTER TABLE public.users ALTER COLUMN role SET NOT NULL;
```

## Rename column

A rename breaks every client still sending the old name. Prefer add → backfill →
switch → drop when the table is read by anything you do not deploy in lockstep.

```sql
BEGIN;
ALTER TABLE public.users RENAME COLUMN name TO full_name;
COMMIT;

-- Rollback (manual — DO NOT uncomment):
-- BEGIN;
--   ALTER TABLE public.users RENAME COLUMN full_name TO name;
-- COMMIT;
```

## Redefining an existing object

`CREATE OR REPLACE` on a function, a view or a trigger: source the body from the
**latest** migration that defines it, never from the one a spec or an old doc
cites. Stacked redefinitions are how an improvement gets silently reverted.

```bash
grep -rln "FUNCTION public.my_function" supabase/migrations/ | sort | tail -1
```

## Post-deploy verification

```sql
-- Table exists
SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = 'notifications');

-- RLS enabled (false = the table is readable by anyone with the publishable key)
SELECT rowsecurity FROM pg_tables WHERE tablename = 'notifications';

-- Policies — an RLS-enabled table with zero rows here is invisible to everyone,
-- and nothing raises an error to tell you so.
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies WHERE tablename = 'notifications';

-- Indexes
SELECT indexname FROM pg_indexes WHERE tablename = 'notifications';
```

Then run the advisors — they catch what these queries do not:

```bash
supabase db advisors            # CLI v2.81.3+, else MCP get_advisors
```
