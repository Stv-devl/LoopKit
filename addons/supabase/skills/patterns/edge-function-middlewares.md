# Edge Function Middlewares

<!-- FILL: `example-*` are placeholder function names, and the `_shared/` helpers
     named here must exist in this repo before an agent imports them. Delete any
     section whose helper you did not implement — see addons/supabase/functions/. -->

> See `edge-function.md` for the main pattern (helpers, plain/Hono styles).

There is **no** shared middleware stack nor `createApp()` factory.
`_shared/middleware/` (singular) contains infra helpers that you call
**manually** at the start of each handler, in the desired order. CORS lives in
`_shared/utils/cors.ts`.

| Concern | Helper | Module | Call |
| --- | --- | --- | --- |
| CORS | `buildCorsHeaders`, `handleCorsPreflight` | `_shared/utils/cors.ts` | manual |
| Security headers | `buildSecurityHeaders(SECURITY_PRESETS.API)` | `_shared/middleware/security-headers.ts` | injected by `createJsonResponse`/`createErrorResponse` |
| Concurrent lock | `acquireConcurrentLock` / `releaseConcurrentLock` | `_shared/middleware/concurrent-lock.ts` | manual |
| Rate limiting | `checkRateLimit` | `_shared/middleware/rate-limiter.ts` | manual |
| Provider guard | `withProviderGuard` | `_shared/middleware/provider-guard.ts` | wrapper |

---

## CORS — `_shared/utils/cors.ts`

```typescript
import { buildCorsHeaders, handleCorsPreflight } from "../_shared/utils/cors.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = buildCorsHeaders(req);
  const preflight = handleCorsPreflight(req); // Response (204) if OPTIONS, otherwise null
  if (preflight) return preflight;
  // … then pass `corsHeaders` to every createXxxResponse(...)
});
```

Exports, and the list is exhaustive: `buildCorsHeaders(req)`,
`handleCorsPreflight(req)` (→ `Response | null`), `isAllowedOrigin(origin)`,
`resolveAllowedOrigin(req)`. There is no `corsMiddleware` and no
`handlePreflight` — CORS is called by hand, like everything else here.

---

## Security headers — `security-headers.ts`

```typescript
import {
  buildSecurityHeaders,
  SECURITY_PRESETS,
} from "../_shared/middleware/security-headers.ts";

const headers = {
  ...buildSecurityHeaders(SECURITY_PRESETS.API),
  "Content-Type": "application/json",
};
```

Available presets: `SECURITY_PRESETS.API`, `.EMAIL`, `.WEBHOOK`, `.MINIMAL`.
In practice, you **almost never call** `buildSecurityHeaders` directly:
`createJsonResponse`/`createErrorResponse` already inject `SECURITY_PRESETS.API`.
The `.WEBHOOK` preset is used by `example-scheduler` and the webhooks.

Other exports: `applySecurityHeaders`, `secureJsonResponse`.

---

## Concurrent lock — `concurrent-lock.ts`

Serializes expensive operations per user (anti-abuse + anti-ban). Config in
`_shared/config/rate-limits.ts` (`CONCURRENT_LOCKS[endpoint]`). `acquire…`
returns a `Response` (to return as-is to short-circuit) if the lock
is unavailable, otherwise `null`.

```typescript
import {
  acquireConcurrentLock,
  releaseConcurrentLock,
} from "../_shared/middleware/concurrent-lock.ts";

const requestId = crypto.randomUUID();
const locked = await acquireConcurrentLock(
  req,
  "expensive-search", // endpoint declared in CONCURRENT_LOCKS
  auth.userId,
  supabase,
  corsHeaders,
  requestId,
);
if (locked) return locked; // 429/423 already formatted

try {
  return await doExpensiveWork();
} finally {
  await releaseConcurrentLock("expensive-search", auth.userId, supabase, requestId);
}
```

Signature: `acquireConcurrentLock(req, endpoint, userId, supabase, corsHeaders?, requestId?)`.
Atomicity via `UNIQUE(lock_key)` on the `concurrent_locks` table (23505 = lock
already taken). See also `getLockStatus`.

---

## Rate limiting — `rate-limiter.ts`

Config-driven (`RATE_LIMITS[endpoint]` in `_shared/config/rate-limits.ts`),
called **manually**. DB backend (`rate_limits` table) if you pass a client,
otherwise in-memory fallback. Returns a 429 `Response` (with
`X-RateLimit-*` + `Retry-After` headers) if exceeded, otherwise `null`.

```typescript
import { checkRateLimit } from "../_shared/middleware/rate-limiter.ts";

const limited = await checkRateLimit(req, "expensive-search", supabase, corsHeaders);
if (limited) return limited; // 429 already formatted
```

Signature: `checkRateLimit(req, endpoint, supabase?, corsHeaders?)`.
`getRateLimitConfig(endpoint)` and `buildRateLimitHeaders(...)` exposed from the
config. The `RateLimiter` class (`_shared/services/rate-limiter.service.ts`) is
the low-level implementation.

> Recommended order in an expensive handler: CORS → auth →
> `checkRateLimit` (anti-abuse) → `acquireConcurrentLock` (one-at-a-time) → work
> → release in a `finally`.

---

## Third-party action guard — `provider-guard.ts`

Wrapper that applies ALL the protections a rate-limited third-party account needs
(explicit pause, time window, weekend, daily cap, jitter) around a handler. Use
it for any action that consumes the provider's quota or risks its account.

```typescript
import { withProviderGuard } from "../_shared/middleware/provider-guard.ts";

return await withProviderGuard(
  req,
  supabase,
  userId,
  { actionType: "send_message" },
  async (ctx) => {
    // execute the provider action; return a Response
    return createJsonResponse({ sent: true }, 200, corsHeaders);
  },
  corsHeaders,
);
```

Signature: `withProviderGuard(req, supabase, userId, options, handler, corsHeaders?)`.
The `ProviderRateLimitError` / `ProviderSoftRestrictionError` errors (exported)
are caught and converted to **429** / **423**. The guard acquires the global
`provider-account-global` lock (one provider call at a time per user).

---

## Key points

- None of these helpers is a global `app.use()`: you **call them in the
  handler**, in the desired business order.
- Short-circuit responses (`acquireConcurrentLock`, `checkRateLimit`): return them
  as-is.
- `releaseConcurrentLock` **always** in a `finally`.
