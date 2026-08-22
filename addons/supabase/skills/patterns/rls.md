# RLS Policies

> RLS is the **only** server-side authorization barrier on this stack. Every
> other check — the guard component, the `where` clause in the gateway, the `if`
> in the edge function — runs on the caller's side of the trust boundary or can
> be bypassed by calling PostgREST directly.

Migrations that create policies go through `/database:migration`. This file is
the shape they must follow.

## The default: every table, every time

```sql
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
```

Two failure modes, neither of which raises an error:

| State | Symptom |
| --- | --- |
| RLS **off** in an exposed schema | Anyone with the publishable key reads the whole table |
| RLS **on**, zero policies | Nobody reads anything — the table looks empty, no error |

Being *exposed* is a separate switch from RLS: depending on the project's Data
API settings a new table may not be reachable until `anon`/`authenticated` are
granted access. Grant and enable RLS in the same migration, never one alone.

## Policy shape

```sql
CREATE POLICY "items_select_own"
  ON public.items FOR SELECT
  TO authenticated                          -- 1
  USING ((select auth.uid()) = user_id);    -- 2
```

1. **`TO authenticated`** scopes the policy to a role. Without it the policy is
   also evaluated for `anon`.
2. **`(select auth.uid())`**, not bare `auth.uid()`. Wrapped in a subquery it is
   evaluated once per statement; bare, it is called once **per row** — 5-10x
   slower, and it gets worse as the table grows.

### UPDATE needs both clauses

```sql
CREATE POLICY "items_update_own"
  ON public.items FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = user_id)         -- which rows I may target
  WITH CHECK ((select auth.uid()) = user_id);   -- what they may look like after
```

Without `WITH CHECK`, a user can **reassign `user_id` to someone else** — the
row passes `USING` on the way in and lands in another user's account.

### INSERT has only `WITH CHECK`

```sql
CREATE POLICY "items_insert_own"
  ON public.items FOR INSERT
  TO authenticated
  WITH CHECK ((select auth.uid()) = user_id);
```

### UPDATE and DELETE need a SELECT policy too

Postgres must read a row before it can modify it. With no SELECT policy, an
UPDATE silently affects **0 rows** — no error, no change, and a client that
reports success.

## Indexes are part of the policy

A policy predicate on an unindexed column scans the table on every request.

```sql
CREATE INDEX IF NOT EXISTS idx_items_user_id ON public.items(user_id);
```

Same migration as the policy. Not a follow-up.

## Multi-tenant / team access

Do not inline a join in the policy — wrap it in a `SECURITY DEFINER` function so
the lookup is one indexed call instead of a per-row subquery.

```sql
CREATE SCHEMA IF NOT EXISTS private;   -- not exposed by the Data API

CREATE OR REPLACE FUNCTION private.is_team_member(team_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''                -- mandatory: an empty search_path blocks
AS $$                               -- schema-shadowing attacks
  SELECT EXISTS (
    SELECT 1 FROM public.team_members
    WHERE team_members.team_id = $1
      AND team_members.user_id = (select auth.uid())   -- always re-check the caller
  );
$$;

-- Postgres grants EXECUTE to PUBLIC on every new function. Close that, then
-- open exactly one door — see "The grant is not optional" below.
REVOKE EXECUTE ON FUNCTION private.is_team_member(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION private.is_team_member(uuid) TO authenticated;

CREATE POLICY "items_select_team"
  ON public.items FOR SELECT
  TO authenticated
  USING ((select private.is_team_member(team_id)));
```

### The grant is not optional

**A policy expression runs with the privileges of the caller, not the table
owner.** Revoke `EXECUTE` from `authenticated` and every read of `items` by a
logged-in user dies on the spot:

```
ERROR:  permission denied for function is_team_member
```

Not "0 rows" — an error, on the very first `select`. Which is why the shape
above revokes from `PUBLIC` and `anon` (who must never call it) and grants to
`authenticated` (who cannot read the table without it).

**Do not grant `USAGE` on the schema.** It is not needed for the policy path —
Postgres checks `EXECUTE` there, not schema access — and withholding it is what
keeps the client from calling the function directly:

```
-- as authenticated, EXECUTE granted, USAGE withheld
select count(*) from public.items;                  -- works, the policy calls it
select private.is_team_member('…');                 -- ERROR: permission denied for schema private
```

## `SECURITY DEFINER` — the two traps

- **It bypasses RLS.** That is the point, and the danger. Never add
  `SECURITY DEFINER` to make a permission error go away: it removes the check
  instead of fixing the cause. Default to `SECURITY INVOKER`.
- **In `public`, it is a public API endpoint.** Postgres grants `EXECUTE` to
  `PUBLIC` on every new function, and `anon`/`authenticated` inherit from it. A
  `SECURITY DEFINER` function in `public` is callable by anyone, with no extra
  grant. Keep them in a private schema, always check `auth.uid()` inside the
  body, `REVOKE EXECUTE FROM PUBLIC, anon` — then grant it back to the one role
  that needs it, because a policy calling a function it may not execute is an
  error, not a filter.

## Views bypass RLS

A view runs with its owner's privileges by default — it hands out exactly what
the underlying policies were meant to withhold.

```sql
CREATE VIEW public.item_summary
  WITH (security_invoker = true) AS      -- Postgres 15+
  SELECT id, title FROM public.items;
```

On older Postgres: revoke `anon`/`authenticated` access, or put the view in an
unexposed schema.

## Things that are not authorization

| Looks like a check | Why it is not |
| --- | --- |
| `auth.role() = 'authenticated'` | Deprecated, and it **passes for anonymous sign-ins** — they carry the `authenticated` role. Use the `TO` clause. |
| `TO authenticated` alone | Authentication without authorization. Every logged-in user reads every row (BOLA/IDOR). It needs an ownership predicate in `USING`. |
| A claim read from `user_metadata` | User-editable. Authorization claims live in `app_metadata`. |
| A `.eq('user_id', userId)` in the gateway | Runs client-side. Useful for correctness, worthless as a barrier. |
| Deleting the user | Does **not** invalidate their existing access tokens. Revoke sessions. |

## Testing policies

RLS is the one thing unit tests cannot cover from the front end: the front-end
client is always the authenticated caller. Test at the SQL level, in a migration
test or a seeded script run against the local stack.

```sql
-- Run against the local stack (supabase db reset first).
BEGIN;
  SET LOCAL role = authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

  -- Sees only its own rows
  SELECT count(*) = 1 AS only_own_rows FROM public.items;

  -- Cannot hand a row to someone else (must raise or affect 0 rows)
  UPDATE public.items
    SET user_id = '22222222-2222-2222-2222-222222222222'
    WHERE user_id = '11111111-1111-1111-1111-111111111111';
ROLLBACK;
```

And run the advisors, which catch the whole class at once:

```bash
supabase db advisors            # CLI v2.81.3+, else MCP get_advisors
```

## Checklist

- [ ] RLS enabled on every table in an exposed schema
- [ ] At least one policy per operation the client actually performs
- [ ] `TO authenticated` (or the right role) on every policy
- [ ] `auth.uid()` wrapped in `(select …)`
- [ ] `WITH CHECK` on every UPDATE and INSERT policy
- [ ] SELECT policy present if the client updates or deletes
- [ ] Index on every column a predicate touches, same migration
- [ ] `SECURITY DEFINER` functions: private schema, `SET search_path = ''`,
      internal `auth.uid()` check, `REVOKE EXECUTE FROM PUBLIC, anon` — and
      `GRANT EXECUTE` to the role whose policy calls it, or every read errors
- [ ] Views created `WITH (security_invoker = true)`
- [ ] `supabase db advisors` clean
