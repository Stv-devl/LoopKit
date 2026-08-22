# Edge Function Auth

<!-- FILL: `example-*` are placeholder function names, and the `_shared/` helpers
     named here must exist in this repo before an agent imports them. Delete any
     section whose helper you did not implement — see addons/supabase/functions/. -->

> See `edge-function.md` for the main pattern (helpers, plain/Hono styles).

No shared `auth()`/`serviceAuth()`/`validate()` middleware. Auth and
validation are called **manually** at the start of the handler. Two modes:

| Mode | Helper | Module | For |
| --- | --- | --- | --- |
| User JWT | `AuthService.authenticateRequest(req)` | `_shared/services/auth.service.ts` | routes called from the front end |
| Service-role | `authenticateServiceRole(req)` | `_shared/utils/auth-helpers.ts` | cron, inter-function (pg_net → function) |

---

## User JWT — `AuthService.authenticateRequest`

A **static** method that actually validates the token and the Supabase session:

```typescript
type AuthResult =
  | { success: true; user: User; userId: string }
  | { success: false; error: string; code:
      "INVALID_TOKEN" | "EXPIRED_TOKEN" | "INVALID_SESSION" | "NO_USER" | "AUTH_ERROR" };
```

### Style A — plain `Deno.serve`

```typescript
import { AuthService } from "../_shared/services/auth.service.ts";
import { buildCorsHeaders, handleCorsPreflight } from "../_shared/utils/cors.ts";
import { createErrorResponse, createJsonResponse } from "../_shared/utils/http.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = buildCorsHeaders(req);
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  const auth = await AuthService.authenticateRequest(req);
  if (!auth.success) {
    return createErrorResponse("Non autorisé", 401, corsHeaders);
  }

  // auth.userId / auth.user available
  return createJsonResponse({ userId: auth.userId }, 200, corsHeaders);
});
```

### Style B — Hono

Auth stays a manual call **inside the handler** (not an `app.use()`), because
`authenticateRequest` takes a raw `Request` (`c.req.raw`):

```typescript
import type { Context } from "hono";
import { AuthService } from "../_shared/services/auth.service.ts";

async function meHandler(c: Context): Promise<Response> {
  const auth = await AuthService.authenticateRequest(c.req.raw);
  if (!auth.success) return c.json({ error: "Non autorisé" }, 401);
  return c.json({ userId: auth.userId });
}
```

> `example-api` factors this check into a small **local** Hono middleware
> (`example-api/lib/*`) that sets `userId` in the `Variables` — not a shared
> `_shared/` middleware.

---

## Service-role — `authenticateServiceRole`

For server-to-server calls (cron via `pg_net`, function → function).
Returns `{ authorized: boolean; error? }`.

**By default it accepts exactly one thing**: a bearer equal to the secret /
service-role key (`SUPABASE_SECRET_KEY` or `SUPABASE_SERVICE_ROLE_KEY`),
compared in constant time. Send that header from `pg_cron` and nothing else is
needed — `edge-function-cron.md` shows the Vault lookup that builds it.

```typescript
import { authenticateServiceRole } from "../_shared/utils/auth-helpers.ts";

const guard = authenticateServiceRole(req);
if (!guard.authorized) {
  return createErrorResponse("Service role required", 401, corsHeaders);
}
```

### The `role: service_role` claim is not the second format

A JWT carrying `payload.role === "service_role"` is **refused** unless you opt
in with `{ trustRoleClaim: true }`, and that option is safe in exactly one
situation: the function is deployed with **JWT verification ON**, so the platform
gateway checked the signature before the handler ran. On a function deployed
`--no-verify-jwt` — every webhook, most cron targets — nobody checked it, and
anyone can mint that claim with `btoa`. There is no third case.

```typescript
// Only on a function whose config.toml keeps verify_jwt = true.
const guard = authenticateServiceRole(req, { trustRoleClaim: true });
```

If a caller you control cannot send the key itself, give it its own secret
header instead of trusting a claim — that is what the `x-scheduler-token`
variant below does.

> The `example-scheduler` function has its own `authenticateSchedulerRequest`
> (`example-scheduler/auth/internal-auth.ts`) that accepts ONLY the
> `role = service_role` claim (or an `x-scheduler-token`). See `edge-function-cron.md`.

---

## Validation — manual Zod `safeParse`

No `validate('json', schema)` middleware. You parse the body yourself and
return 400 if invalid.

```typescript
import { z } from "zod";

const createItemSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().optional(),
});

const parsed = createItemSchema.safeParse(await req.json().catch(() => ({})));
if (!parsed.success) {
  // Optional detail for the client (handy in dev)
  const details = parsed.error.issues
    .map((i) => `${i.path.join(".")}: ${i.message}`)
    .join(", ");
  return createErrorResponse(`Données invalides: ${details}`, 400, corsHeaders);
}
// parsed.data is typed
```

In Hono, same logic in the handler: `schema.safeParse(await c.req.json())`
then `c.json({ error }, 400)`.

> **Actual error shape**: `{ "error": "message" }` (flat). No
> `{ error: { code, requestId } }`.

---

## Complementary auth helpers (`_shared/utils/auth-helpers.ts`)

| Helper | Usage |
| --- | --- |
| `extractUserIdFromToken(req)` | decodes the JWT `sub` without verifying the signature — **only** for a rate-limit key before full auth. Never as proof of identity: the caller controls this value |
| `extractClientIp(req)` | best-effort client IP for rate limiting and abuse logs. `x-forwarded-for` is client-supplied and the platform only appends to it, so the leftmost entries can be forged; skipping private and loopback ranges stops the cheapest spoofing and nothing more. It is not an identity |

---

## Checklist

- [ ] CORS first (`handleCorsPreflight` + `buildCorsHeaders`)
- [ ] Manual auth: `AuthService.authenticateRequest` (user) OR `authenticateServiceRole` (internal)
- [ ] `schema.safeParse` + explicit 400 return
- [ ] Responses via `createJsonResponse` / `createErrorResponse` (or `c.json`)
- [ ] Error in flat shape `{ error: "..." }`
