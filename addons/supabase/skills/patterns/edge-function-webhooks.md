# Edge Function Webhooks

<!-- FILL: `example-*` are placeholder function names, and the `_shared/` helpers
     named here must exist in this repo before an agent imports them. Delete any
     section whose helper you did not implement — see addons/supabase/functions/. -->

> See `edge-function.md` for the main pattern (helpers, plain/Hono styles).

Signature verification for incoming webhooks. **No** Hono middleware
importing `HttpError`/`ERROR_CODES`: we verify at the top of a `Deno.serve`
handler and return `createErrorResponse(..., 401/400, corsHeaders)` on
failure. The error shape is flat: `{ "error": "..." }`.

| Webhook | Helper | Module |
| --- | --- | --- |
| Generic provider | `verifyProviderSignature(req)` | `_shared/utils/provider-webhook-auth.ts` |
| Stripe | `class WebhookValidator` (timestamp + dedup) | `_shared/utils/webhook-validator.ts` |
| Generic HMAC | local WebCrypto helper (below) | — |

---

## Generic provider — `verifyProviderSignature`

Compares in constant time a shared secret received in the URL (`?token=`) or a
header (`x-provider-signature`, `x-signature`, `provider-auth`, `x-provider-auth`,
`Authorization: Bearer …`). Returns `{ ok: true }` or `{ ok: false, reason }`.
If `PROVIDER_WEBHOOK_SECRET` is not set → `ok: true` (bootstrap mode:
wire up the webhook before propagating the secret).

```typescript
import { verifyProviderSignature } from "../_shared/utils/provider-webhook-auth.ts";
import { buildCorsHeaders, handleCorsPreflight } from "../_shared/utils/cors.ts";
import { createErrorResponse, createJsonResponse } from "../_shared/utils/http.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = buildCorsHeaders(req);
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  const sig = verifyProviderSignature(req);
  if (!sig.ok) {
    const status = sig.reason === "missing" ? 401 : 403;
    return createErrorResponse("Webhook signature rejected", status, corsHeaders);
  }

  const payload = await req.json().catch(() => null);
  if (!payload) return createErrorResponse("Invalid payload", 400, corsHeaders);

  // … handle the event
  return createJsonResponse({ received: true }, 200, corsHeaders);
});
```

> `ProviderSignatureResult = { ok: true } | { ok: false; reason: "missing" | "invalid" }`.

---

## Stripe — `WebhookValidator`

Two steps: (1) Stripe verifies the signature, then (2) `WebhookValidator` covers
the time window + deduplication (table `stripe_events`).

> ⚠️ **`constructEvent` (synchronous) throws in Deno.** It reaches for Node's
> synchronous crypto, which does not exist here — you get
> `SubtleCryptoProvider cannot be used in a synchronous context`. Always the
> async variant, with the Web Crypto provider:
> `constructEventAsync(body, sig, secret, undefined, Stripe.createSubtleCryptoProvider())`.

```typescript
import Stripe from "npm:stripe@22";
import { WebhookValidator } from "../_shared/utils/webhook-validator.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const cryptoProvider = Stripe.createSubtleCryptoProvider();
const validator = new WebhookValidator();

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = buildCorsHeaders(req);
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  const sig = req.headers.get("stripe-signature");
  if (!sig) return createErrorResponse("Missing signature", 400, corsHeaders);

  const rawBody = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      sig,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
      undefined,
      cryptoProvider,
    );
  } catch {
    return createErrorResponse("Invalid signature", 400, corsHeaders);
  }

  // Timestamp window (5 min) + dedup via DB
  const check = await validator.validateWebhook(event, adminClient);
  if (!check.valid) return createErrorResponse(check.error ?? "Rejected", 400, corsHeaders);

  // … switch (event.type)
  return createJsonResponse({ received: true }, 200, corsHeaders);
});
```

`WebhookValidator` exposes: `validateTimestamp(event)`, `isEventProcessed(id, client)`,
`markEventAsProcessed(id, client)`, `validateWebhook(event, client)` (chains the
three). `MAX_TIMESTAMP_DIFF_SECONDS = 300`.

---

## Generic HMAC (GitHub, Slack…)

For an uncovered provider, a reusable WebCrypto helper — a pure function,
**not** a middleware. We call it at the top of the handler.

```typescript
/** Verifies a hex HMAC signature (compares in constant time). */
async function verifyHmac(
  rawBody: string,
  provided: string,
  secret: string,
  algorithm: "SHA-256" | "SHA-1" = "SHA-256",
): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secret), { name: "HMAC", hash: algorithm }, false, ["sign"],
  );
  const buf = await crypto.subtle.sign("HMAC", key, enc.encode(rawBody));
  const expected = Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  // Supports "sha256=xxx" or "xxx"
  const got = provided.includes("=") ? provided.split("=")[1]! : provided;
  if (got.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}
```

Usage (GitHub) :

```typescript
const rawBody = await req.text();
const ok = await verifyHmac(
  rawBody,
  req.headers.get("x-hub-signature-256") ?? "",
  Deno.env.get("GITHUB_WEBHOOK_SECRET")!,
);
if (!ok) return createErrorResponse("Invalid signature", 401, corsHeaders);
const payload = JSON.parse(rawBody);
```

---

## Providers

| Provider | Header | Verification |
| --- | --- | --- |
| Generic provider | `?token` / `x-provider-signature` / Bearer | `verifyProviderSignature` |
| Stripe | `stripe-signature` | `constructEventAsync` + `WebhookValidator` |
| GitHub | `x-hub-signature-256` | HMAC SHA-256 |
| Slack | `x-slack-signature` | HMAC SHA-256 |

---

## Rules

- Read the body as **raw text** (`req.text()`) BEFORE any JSON parsing when the
  signature covers the body — re-parse afterward.
- Compare signatures in **constant time**.
- Failure → `createErrorResponse(..., 401|400|403, corsHeaders)` (flat shape).
- Idempotency: deduplicate (Stripe via `stripe_events`, others via a business key).
