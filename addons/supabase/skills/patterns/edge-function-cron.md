# Edge Function Cron

<!-- FILL: `example-*` are placeholder function names, and the `_shared/` helpers
     named here must exist in this repo before an agent imports them. Delete any
     section whose helper you did not implement — see addons/supabase/functions/. -->

> See `edge-function.md` for the main pattern (helpers, plain/Hono styles).

An Edge Function triggered by **pg_cron** via `net.http_post(...)`. Style
**plain `Deno.serve`** (the `example-scheduler` example below). Auth = service-role:
`Authorization: Bearer <service_role>` OR a secret `x-scheduler-token` header
(fetched from Vault by pg_cron).

---

## Skeleton (based on `example-scheduler/index.ts`)

```typescript
// daily-cleanup/index.ts
import { createClient } from "supabase";
import { buildCorsHeaders, handleCorsPreflight } from "../_shared/utils/cors.ts";
import { createErrorResponse, createJsonResponse } from "../_shared/utils/http.ts";
import { authenticateServiceRole } from "../_shared/utils/auth-helpers.ts";
import { secureLogger } from "../_shared/utils/secure-logger.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = buildCorsHeaders(req);
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  // Service-role only (pg_cron / inter-function)
  if (!authenticateServiceRole(req).authorized) {
    return createErrorResponse("Service role required", 401, corsHeaders);
  }

  try {
    const [sessions, notifications] = await Promise.all([
      cleanupExpiredSessions(supabase),
      cleanupOldNotifications(supabase),
    ]);
    secureLogger.info("cron cleanup completed", {
      operation: "daily-cleanup",
      sessions,
      notifications,
    });
    return createJsonResponse({ success: true, sessions, notifications }, 200, corsHeaders);
  } catch (error) {
    secureLogger.error("cron cleanup failed", {
      operation: "daily-cleanup",
      error: error instanceof Error ? error.message : "Unknown",
    });
    return createErrorResponse("Internal error", 500, corsHeaders);
  }
});
```

> **`x-scheduler-token` variant**: the `example-scheduler` function does not use
> `authenticateServiceRole` but a local check
> (`example-scheduler/auth/internal-auth.ts`) accepting the `role = service_role` claim
> OR a secret token stored in Vault. For a simple new cron function,
> `authenticateServiceRole` is enough.

---

## pg_cron configuration (SQL migration)

> Do not write SQL by hand → `/database:migration`. Reference schema:

```sql
-- Service-role Bearer via Vault (preferred: the secret never appears in the migration)
SELECT cron.schedule(
  'daily-cleanup',
  '0 3 * * *', -- every day at 3am
  $$
    SELECT net.http_post(
      url     := 'https://<project-ref>.supabase.co/functions/v1/daily-cleanup',
      body    := '{}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
        )
      )
    );
  $$
);
```

Secret header variant (like `example-scheduler`):

```sql
headers := jsonb_build_object(
  'Content-Type', 'application/json',
  'x-scheduler-token', (
    SELECT decrypted_secret FROM vault.decrypted_secrets
    WHERE name = 'SCHEDULER_TOKEN'
  )
)
```

The secret (`service_role_key`, `SCHEDULER_TOKEN`…) lives in
**Supabase Vault**, never in plaintext in the migration.

---

## Common schedules

| Schedule | Cron | Usage |
| --- | --- | --- |
| Every minute | `* * * * *` | dispatch queue, example-scheduler |
| Every 5 min | `*/5 * * * *` | due reminders, light sync |
| Every hour | `0 * * * *` | aggregations, reports |
| Every day at 3am | `0 3 * * *` | cleanup, maintenance |
| Monday 6am | `0 6 * * 1` | weekly reports |
| 1st of the month | `0 0 1 * *` | archiving |

---

## Batch processing

Process in batches to avoid timeouts (the cron run must stay short):

```typescript
const BATCH_SIZE = 100;

async function processPendingEmails(supabase: SupabaseClient): Promise<number> {
  let processed = 0;
  while (true) {
    const { data: batch } = await supabase
      .from("email_queue")
      .select("*")
      .eq("status", "pending")
      .limit(BATCH_SIZE);
    if (!batch?.length) break;

    for (const email of batch) {
      try {
        await sendEmail(email);
        await supabase.from("email_queue")
          .update({ status: "sent", sent_at: new Date().toISOString() })
          .eq("id", email.id);
        processed++;
      } catch (err) {
        await supabase.from("email_queue")
          .update({ status: "failed", error: String(err) })
          .eq("id", email.id);
      }
    }
  }
  return processed;
}
```

---

## Avoiding parallel executions

Two options depending on context:

**a) The infra lock `concurrent-lock.ts`** (per-user, already wired on the
quota-bound third-party endpoints — cf. `edge-function-middlewares.md`).

**b) A simple DB lock** for a singleton cron job:

```typescript
async function acquireLock(
  supabase: SupabaseClient,
  lockName: string,
  ttlMinutes = 30,
): Promise<boolean> {
  const expiresAt = new Date(Date.now() + ttlMinutes * 60_000).toISOString();

  // Clear an expired lock first: without this the TTL column is decoration and
  // a handler that dies before `releaseLock` blocks the job forever.
  await supabase.from("cron_locks").delete()
    .eq("name", lockName)
    .lt("expires_at", new Date().toISOString());

  const { error } = await supabase
    .from("cron_locks")
    .insert({ name: lockName, expires_at: expiresAt });

  if (!error) return true;
  // 23505 = unique_violation = lock already held by a live run.
  if (error.code === "23505") return false;
  // Anything else (RLS, network, schema) means we do NOT know whether we hold
  // the lock. Fail closed: `return error.code !== "23505"` would claim it.
  secureLogger.error("lock acquisition failed", {
    operation: "daily-cleanup",
    lockName,
    error,
  });
  return false;
}

async function releaseLock(supabase: SupabaseClient, lockName: string): Promise<void> {
  await supabase.from("cron_locks").delete().eq("name", lockName);
}
```

```sql
-- via /database:migration
CREATE TABLE public.cron_locks (
  name TEXT PRIMARY KEY,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cron_locks_expires ON public.cron_locks(expires_at);

-- Held and released by the function with the secret key, which bypasses RLS.
-- No client has any business here: RLS on, zero policies (`patterns/rls.md`).
ALTER TABLE public.cron_locks ENABLE ROW LEVEL SECURITY;
```

Usage: `if (!await acquireLock(...)) return createJsonResponse({ skipped: true }, 200, corsHeaders);`
then `releaseLock` in a `finally`.

---

## Monitoring

```sql
-- pg_cron run history
SELECT start_time, status, return_message
FROM cron.job_run_details
ORDER BY start_time DESC LIMIT 20;
```

For an application-level history, a `cron_runs` table (started_at, completed_at,
status, result jsonb) logged at the start/end of the handler stays useful.

---

## Checklist

- [ ] Plain `Deno.serve` + `authenticateServiceRole` (or `example-scheduler`-style check)
- [ ] Service-role Supabase client created in module scope
- [ ] pg_cron migration (`/database:migration`), secret in Vault
- [ ] Atomic / retry-safe handler, batch for large volumes
- [ ] Lock (infra or DB) if exclusive execution required, release in `finally`
- [ ] `secureLogger` logs with `operation`
- [ ] Deployment: `supabase functions deploy <function-name>`
