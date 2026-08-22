# Webhook Template (full scaffold)

<!-- FILL: function name, provider, event types. What must not change: signature
     first, raw body before parsing, idempotence, flat error shape. -->

> See `patterns/edge-function-webhooks.md` for the reference of the signature
> verification helpers, and `patterns/edge-function.md` for the main pattern
> (plain `Deno.serve`, response helpers, auth). This template is the "full
> scaffold" version of what `edge-function-webhooks.md` describes.

A webhook is a **standalone** function: a single `index.ts` with a
`Deno.serve(async (req) => {...})`. **No** `createApp` factory, no
`_shared/app/`, no `_shared/clients/`, no Hono middleware. Signature
verification and logic live in the handler. **Flat** error shape:
`{ "error": "message" }` (never `{ error: { code, requestId } }`).

> Provider webhooks are server-to-server: JWT verification off, and no CORS at
> all — a browser never calls them. Keep the CORS helpers only if a front end
> genuinely posts to the function.

## Actual structure

```
supabase/functions/
├── _shared/utils/
│   ├── http.ts                    # createJsonResponse / createErrorResponse
│   ├── secure-logger.ts           # secureLogger.info/warn/error
│   ├── provider-webhook-auth.ts    # verifyProviderSignature
│   └── webhook-validator.ts       # class WebhookValidator (Stripe)
└── example-webhook/
    └── index.ts                   # Deno.serve + signature + logic
```

For heavy logic, split into modules **local** to the function
(`example-webhook/handlers.ts`, `example-webhook/db.ts`) imported by `index.ts`.
Stay standalone: put no business logic in `_shared/`.

## Idempotence (processed events table)

A webhook can be replayed (provider retry, double delivery). We deduplicate
on the event's `id` via a dedicated table — the insert that violates the
unique constraint signals a duplicate.

```sql
-- To create via /database:migration (never manual SQL).
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_webhook_events_type ON public.webhook_events (type);

-- Server-side only: the function writes it with the secret key, which bypasses
-- RLS. Enabling RLS with zero policies is exactly right here — it makes the
-- table invisible to `anon` and `authenticated`, and changes nothing for the
-- function. A table left without it is readable by anyone holding the
-- publishable key (`.claude/skills/patterns/rls.md`).
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
```

```typescript
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

/**
 * Atomically reserves the event. Returns true if already processed
 * (insert conflict) — the caller can then ack without replaying the logic.
 */
async function alreadyProcessed(
  supabase: SupabaseClient,
  eventId: string,
  eventType: string,
): Promise<boolean> {
  const { error } = await supabase
    .from("webhook_events")
    .insert({ id: eventId, type: eventType });
  // 23505 = unique_violation = event already recorded.
  return error?.code === "23505";
}
```

## index.ts — full scaffold (generic provider)

Signature first, inline service-role client, ack 200 even on internal error so a
retrying provider does not loop.

```typescript
/**
 * Edge Function: example-webhook
 *
 * Receives <provider> events. Verifies the signature, deduplicates, processes.
 *
 * POST /example-webhook
 * Auth: webhook provider (no JWT — deployed with --no-verify-jwt).
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  createErrorResponse,
  createJsonResponse,
} from "../_shared/utils/http.ts";
import { secureLogger } from "../_shared/utils/secure-logger.ts";
import { verifyProviderSignature } from "../_shared/utils/provider-webhook-auth.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return createErrorResponse("Method not allowed", 405);
  }

  // 1. Signature (constant-time). ok:true also when the secret is not yet
  //    configured (bootstrap mode: wire up before propagating).
  const sig = verifyProviderSignature(req);
  if (!sig.ok) {
    secureLogger.warn("Webhook signature missing or invalid", {
      operation: "example-webhook",
      reason: sig.reason,
    });
    return createErrorResponse("Invalid signature", 401);
  }

  try {
    // 2. Read the body. If the signature covers the body, read the raw text
    //    first (req.text()) BEFORE parsing — cf. Stripe variant.
    const body = await req.json();

    secureLogger.info("Webhook received", {
      operation: "example-webhook",
      event: body.event,
    });

    const eventId = body.id as string | undefined;
    const eventType = (body.event as string | undefined) ?? "unknown";
    if (!eventId) {
      return createJsonResponse({ received: true, processed: false }, 200);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 3. Idempotence: if already seen, ack without replaying.
    if (await alreadyProcessed(supabase, eventId, eventType)) {
      secureLogger.info("Webhook already processed", {
        operation: "example-webhook",
        eventId,
      });
      return createJsonResponse({ received: true, duplicate: true }, 200);
    }

    // 4. Route by event type.
    await handleEvent(supabase, eventType, body);

    secureLogger.info("Webhook processed", {
      operation: "example-webhook",
      eventId,
      eventType,
    });
    return createJsonResponse({ received: true, processed: true }, 200);
  } catch (error) {
    secureLogger.error("Webhook error", {
      operation: "example-webhook",
      error: error instanceof Error ? error.message : String(error),
    });
    // Ack 200: absorb the error so the provider does not retry in a loop.
    // (The problematic payload is traced via secureLogger.)
    return createJsonResponse({ received: true, error: "internal" }, 200);
  }
});

async function handleEvent(
  supabase: SupabaseClient,
  eventType: string,
  body: Record<string, unknown>,
): Promise<void> {
  switch (eventType) {
    case "new_relation":
      // … business logic (upsert, interactions, advance state…)
      break;
    default:
      secureLogger.warn("Unhandled event type", {
        operation: "example-webhook",
        eventType,
      });
  }
}
```

> `verifyProviderSignature(req)` accepts the secret in `?token=` or the headers
> `x-provider-signature` / `x-signature` / `provider-auth` / `x-provider-auth` /
> `Authorization: Bearer …`. Returns `{ ok: true } | { ok: false, reason }`
> where `reason ∈ { "missing", "invalid" }`.

## Stripe variant — `WebhookValidator`

Two steps: (1) Stripe verifies the signature on the **raw body**, then (2)
`WebhookValidator` covers the time window + deduplication (`stripe_events`
table).

> ⚠️ The synchronous `constructEvent` throws in Deno (`SubtleCryptoProvider
> cannot be used in a synchronous context`) — it wants Node's sync crypto.
> `constructEventAsync` **with an explicit Web Crypto provider** is the shape
> that works.

```typescript
import Stripe from "npm:stripe@22";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  createErrorResponse,
  createJsonResponse,
} from "../_shared/utils/http.ts";
import { secureLogger } from "../_shared/utils/secure-logger.ts";
import {
  WebhookValidator,
  type SupabaseAdminClient,
} from "../_shared/utils/webhook-validator.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const cryptoProvider = Stripe.createSubtleCryptoProvider();
const validator = new WebhookValidator();

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return createErrorResponse("Method not allowed", 405);
  }

  const sig = req.headers.get("stripe-signature");
  if (!sig) return createErrorResponse("Missing signature", 400);

  // Raw body required for Stripe signature verification.
  const rawBody = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      sig,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
      undefined,
      cryptoProvider,      // Web Crypto — required in Deno
    );
  } catch {
    return createErrorResponse("Invalid signature", 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Adapter expected by WebhookValidator (isEventProcessed + getClient).
  const adminClient: SupabaseAdminClient = {
    isEventProcessed: async (id) => {
      const { data } = await supabase
        .from("stripe_events")
        .select("event_id")
        .eq("event_id", id)
        .maybeSingle();
      return Boolean(data);
    },
    getClient: () => supabase,
  };

  // Time window (300s) + dedup via stripe_events.
  const check = await validator.validateWebhook(event, adminClient);
  if (!check.valid) {
    return createErrorResponse(check.error ?? "Rejected", 400);
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":
        // … create the subscription
        break;
      case "customer.subscription.updated":
        // … update the status
        break;
      default:
        secureLogger.info("Unhandled Stripe event", {
          operation: "stripe-webhook",
          eventType: event.type,
        });
    }
    return createJsonResponse({ received: true }, 200);
  } catch (error) {
    secureLogger.error("Stripe webhook error", {
      operation: "stripe-webhook",
      error: error instanceof Error ? error.message : String(error),
    });
    return createErrorResponse("Internal error", 500);
  }
});
```

> `WebhookValidator` exposes `validateTimestamp(event)`,
> `isEventProcessed(id, client)`, `markEventAsProcessed(id, client)`,
> `validateWebhook(event, client)` (chains the three). Constant
> `MAX_TIMESTAMP_DIFF_SECONDS = 300`.

## Generic HMAC variant (GitHub, Slack…)

For a provider not covered, a pure WebCrypto helper — a **function**, not a
middleware. Call it at the top of the handler (cf.
`patterns/edge-function-webhooks.md` for the detailed version).

```typescript
/** Verifies a hex HMAC signature in constant time. */
async function verifyHmac(
  rawBody: string,
  provided: string,
  secret: string,
  algorithm: "SHA-256" | "SHA-1" = "SHA-256",
): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: algorithm },
    false,
    ["sign"],
  );
  const buf = await crypto.subtle.sign("HMAC", key, enc.encode(rawBody));
  const expected = Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const got = provided.includes("=") ? provided.split("=")[1]! : provided;
  if (got.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) {
    diff |= got.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}
```

```typescript
const rawBody = await req.text();
const ok = await verifyHmac(
  rawBody,
  req.headers.get("x-hub-signature-256") ?? "",
  Deno.env.get("GITHUB_WEBHOOK_SECRET")!,
);
if (!ok) return createErrorResponse("Invalid signature", 401);
const payload = JSON.parse(rawBody);
```

## Providers

| Provider | Header / location | Verification |
| --- | --- | --- |
| Generic provider | `?token` / `x-provider-signature` / Bearer | `verifyProviderSignature` |
| Stripe | `stripe-signature` | `constructEventAsync` + `WebhookValidator` |
| GitHub | `x-hub-signature-256` | `verifyHmac` (SHA-256) |
| Slack | `x-slack-signature` | `verifyHmac` (SHA-256) |

## Retry / ack (optional)

If processing can fail transiently and the provider does not retry on its side
(many do not), persist the event for a homemade retry via cron.

```sql
-- To create via /database:migration.
CREATE TABLE IF NOT EXISTS public.webhook_retry_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  next_retry_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ
);

CREATE INDEX idx_retry_queue_next ON public.webhook_retry_queue (next_retry_at)
  WHERE processed_at IS NULL AND attempts < max_attempts;

-- `payload` holds the provider's event verbatim — customer identifiers, amounts,
-- emails. Written by the function with the secret key, which bypasses RLS; read
-- by nobody else. RLS on, zero policies.
ALTER TABLE public.webhook_retry_queue ENABLE ROW LEVEL SECURITY;
```

```typescript
/** Enqueues (or re-enqueues) an event with exponential backoff. */
async function enqueueForRetry(
  supabase: SupabaseClient,
  eventId: string,
  eventType: string,
  payload: unknown,
  lastError: string,
): Promise<void> {
  // Backoff: 1min, 5min, 30min, 2h, 12h.
  const backoffMinutes = [1, 5, 30, 120, 720];
  const { data: existing } = await supabase
    .from("webhook_retry_queue")
    .select("attempts")
    .eq("event_id", eventId)
    .maybeSingle();

  const attempts = (existing?.attempts ?? 0) + 1;
  const backoff = backoffMinutes[Math.min(attempts - 1, backoffMinutes.length - 1)];

  await supabase.from("webhook_retry_queue").upsert(
    {
      event_id: eventId,
      event_type: eventType,
      payload,
      attempts,
      last_error: lastError,
      next_retry_at: new Date(Date.now() + backoff * 60_000).toISOString(),
    },
    { onConflict: "event_id" },
  );
}
```

A separate cron function (`process-webhook-retries`) drains the queue. It
authenticates as **service-role** via `authenticateServiceRole(req)` (from
`_shared/utils/auth-helpers.ts`) — no `serviceAuth()` middleware.

```typescript
import { authenticateServiceRole } from "../_shared/utils/auth-helpers.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (!authenticateServiceRole(req).authorized) {
    return createErrorResponse("Service role required", 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: pending } = await supabase
    .from("webhook_retry_queue")
    .select("*")
    .is("processed_at", null)
    .lte("next_retry_at", new Date().toISOString())
    .limit(10);

  for (const item of pending ?? []) {
    try {
      await handleEvent(supabase, item.event_type, item.payload);
      await supabase
        .from("webhook_retry_queue")
        .update({ processed_at: new Date().toISOString() })
        .eq("event_id", item.event_id);
    } catch (err) {
      await enqueueForRetry(
        supabase,
        item.event_id,
        item.event_type,
        item.payload,
        err instanceof Error ? err.message : String(err),
      );
    }
  }

  return createJsonResponse({ processed: pending?.length ?? 0 }, 200);
});
```

## Secrets

```bash
supabase secrets set PROVIDER_WEBHOOK_SECRET=...
# Stripe:
supabase secrets set STRIPE_SECRET_KEY=sk_...
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
```

## Deployment

Provider webhooks do not send a Supabase JWT → the gateway must not require one.
Declare it in `config.toml` so the setting survives a redeploy, instead of living
only in whoever's shell ran the last command:

```toml
# supabase/config.toml
[functions.example-webhook]
verify_jwt = false
```

```bash
supabase functions deploy example-webhook --no-verify-jwt
```

> With JWT verification off, **nothing upstream authenticated the caller**. The
> signature check at the top of the handler is the only barrier — it is not
> defence in depth, it is the whole defence.
>
> Deploy **one function at a time**. A bulk deploy has been known to reset
> per-function flags and orphan `config.toml` entries; verify in the dashboard
> after deploying, and re-check whenever the CLI is upgraded.

## Checklist

- [ ] Plain `Deno.serve` (no factory, no Hono)
- [ ] Signature verified **first**, in constant time
- [ ] Raw body (`req.text()`) read before parsing if the signature covers the body
- [ ] Idempotence: dedup on the event's `id` (table `webhook_events` or
      `stripe_events`)
- [ ] Service-role Supabase client created inline (`createClient`)
- [ ] Logs via `secureLogger` with `operation`
- [ ] Errors in flat shape `{ "error": "..." }` (via `createErrorResponse`)
- [ ] Ack 200 on internal error if the provider retries in a loop
- [ ] `verify_jwt = false` in `config.toml` **and** deployed with `--no-verify-jwt`
- [ ] Deployed alone, then verified in the dashboard
```
