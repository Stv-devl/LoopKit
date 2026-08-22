# Edge Function Core

<!-- FILL: `example-api` / `example-worker` are placeholder function names. Replace
     them with this repo's. What must not change: each function is autonomous,
     `_shared/` holds infra only, and the error shape is flat. -->

> **The convention**: no `createApp()` factory, no `_shared/app/`, no
> `_shared/clients/`, no shared `error-codes.ts`. Each function is **autonomous**.
> Two styles coexist: **plain `Deno.serve`** (default, simple functions) and **Hono**
> (multi-route functions — `example-api` below). `_shared/` = infra only.

> **Handler shape.** `Deno.serve(handler)` is what this page uses and what the
> runtime has always supported. Note that recent CLI versions scaffold a
> different shape with `supabase functions new` —
> `export default { fetch: withSupabase({ auth: [...] }, handler) }`. Both run.
> Pick one per repo and say which here, otherwise half the functions will not
> look like the other half.

## `_shared/` layout

The helpers below are **your code**, not a Supabase feature. A working
implementation of the core six ships with this addon in
`addons/supabase/functions/_shared/` — copy it, then `deno check _shared/**/*.ts`.

```
supabase/functions/
├── deno.json        # import map — "@shared/" → "./_shared/"
└── _shared/
    ├── middleware/  # security-headers  (+ your own: rate-limiter, concurrent-lock…)
    ├── services/    # auth.service.ts
    ├── schemas/     # shared Zod (shared request/response shapes)
    └── utils/       # cors.ts, http.ts, auth-helpers.ts, secure-logger.ts
```

Infra helpers reused everywhere:

| Need | Helper | Module |
| --- | --- | --- |
| JSON response | `createJsonResponse(data, status?, headers?)` | `_shared/utils/http.ts` |
| Error response | `createErrorResponse(message, status?, headers?)` | `_shared/utils/http.ts` |
| CORS | `buildCorsHeaders(req)`, `handleCorsPreflight(req)` | `_shared/utils/cors.ts` |
| Security headers | `buildSecurityHeaders(SECURITY_PRESETS.API)` | `_shared/middleware/security-headers.ts` |
| Structured log | `secureLogger.info/warn/error(msg, ctx)` | `_shared/utils/secure-logger.ts` |
| User JWT auth | `AuthService.authenticateRequest(req)` | `_shared/services/auth.service.ts` |
| Service-role auth | `authenticateServiceRole(req)` | `_shared/utils/auth-helpers.ts` |

> `createJsonResponse`/`createErrorResponse` already inject `SECURITY_PRESETS.API`.
> **Actual error shape**: `{ "error": "message" }` (flat), not `{ error: { code, requestId } }`.

## Rules

1. **Autonomy**: business logic in the function's own files (`index.ts` + local
   modules). `_shared/` only contains infra.
2. **CORS first**: respond to the `OPTIONS` preflight, then add `buildCorsHeaders(req)`
   on every response.
3. **Manual Zod validation**: `schema.safeParse(body)` then return 400 if `!success`.
   No `zValidator` middleware.
4. **Inline Supabase client**: `createClient(...)` inside the function (secret /
   service-role, or user-scoped depending on need). No shared factory.
5. **Contract first**: routes / auth / schema / HTTP codes before coding.

> **Which key.** The secret (`service_role`) key **bypasses RLS** — use it only
> where the handler enforces access itself, and say in the code why it has to.
> The default, and what Style A below does, is to act *as the caller* and let
> RLS do the work: publishable key plus the user's `Authorization` header
> forwarded. Authenticating the user and then querying with the secret key is
> the shape that quietly turns every policy off.
>
> ```typescript
> const supabase = createClient(url, publishableKey, {
>   global: { headers: { Authorization: req.headers.get("Authorization")! } },
> });
> ```
>
> Key names differ between the legacy (`SUPABASE_ANON_KEY` /
> `SUPABASE_SERVICE_ROLE_KEY`) and the current (`SUPABASE_PUBLISHABLE_KEYS` /
> `SUPABASE_SECRET_KEYS`, JSON objects keyed by key name) systems. Read what the
> project actually has — see `.claude/rules/01-stack.md`.

## Style A — plain `Deno.serve` (default)

```typescript
// example-worker/index.ts
import { createClient } from "supabase";
import { z } from "zod";
import { buildCorsHeaders, handleCorsPreflight } from "../_shared/utils/cors.ts";
import { createErrorResponse, createJsonResponse } from "../_shared/utils/http.ts";
import { secureLogger } from "../_shared/utils/secure-logger.ts";
import { AuthService } from "../_shared/services/auth.service.ts";

const requestSchema = z.object({
  item_id: z.string().uuid(),
});

Deno.serve(async (req: Request): Promise<Response> => {
  const corsHeaders = buildCorsHeaders(req);
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return createErrorResponse("Method not allowed", 405, corsHeaders);
  }

  // User JWT auth
  const auth = await AuthService.authenticateRequest(req);
  if (!auth.success) {
    return createErrorResponse("Non autorisé", 401, corsHeaders);
  }

  try {
    const parsed = requestSchema.safeParse(await req.json());
    if (!parsed.success) {
      return createErrorResponse("Données invalides", 400, corsHeaders);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );

    const result = await doWork(supabase, auth.userId, parsed.data);
    return createJsonResponse({ success: true, ...result }, 200, corsHeaders);
  } catch (error) {
    secureLogger.error("example-worker failed", {
      operation: "example-worker",
      error: error instanceof Error ? error.message : "Unknown",
    });
    return createErrorResponse("Erreur interne", 500, corsHeaders);
  }
});
```

## Style B — Hono (multi-route)

`new Hono().basePath('/<function-name>')`, served by `Deno.serve(app.fetch)`. CORS, auth,
errors wired **inline** (no factory).

```typescript
// example-api/index.ts
import { app } from "./app.ts";
Deno.serve(app.fetch);
```

```typescript
// example-api/app.ts (extrait)
import { Hono } from "hono";
import type { Context } from "hono";
import { authenticateServiceRole } from "../_shared/utils/auth-helpers.ts";
import { buildCorsHeaders, handleCorsPreflight } from "../_shared/utils/cors.ts";
import { secureLogger } from "../_shared/utils/secure-logger.ts";
import { jobRunnerRequestSchema } from "./schema.ts";

export const app = new Hono().basePath("/example-api");

app.options("*", (c) => handleCorsPreflight(c.req.raw) ?? c.body(null, 204));
app.use("*", async (c, next) => {
  await next();
  for (const [k, v] of Object.entries(buildCorsHeaders(c.req.raw))) {
    c.res.headers.set(k, v);
  }
});

app.get("/health", (c) => c.json({ ok: true }));
app.post("/", dispatch);

app.notFound((c) => c.json({ error: "Not found" }, 404));
app.onError((e, c) => {
  secureLogger.error("Unhandled error in example-api", {
    operation: "example-api",
    error: e instanceof Error ? e.message : "Unknown",
  });
  return c.json({ error: "Internal server error" }, 500);
});

async function dispatch(c: Context): Promise<Response> {
  const raw = await c.req.json().catch(() => ({}));
  const parsed = jobRunnerRequestSchema.safeParse(raw);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((i) => `${i.path.join(".")}: ${i.message}`)
      .join(", ");
    return c.json({ error: `Validation failed: ${details}` }, 400);
  }
  // … auth per mode + logic
  return c.json({ accepted: true }, 202);
}
```

> **Sub-routers** (`example-api`): `app.route('/items', itemsRouter)` where
> `itemsRouter = new Hono<{ Variables: HonoVariables }>()`. Local response helpers
> (`ok/err/validationError` in `example-api/lib/responses.ts`).

## Auth

```typescript
// User JWT (routes called from the front end)
import { AuthService } from "../_shared/services/auth.service.ts";
const auth = await AuthService.authenticateRequest(req); // { success, user, userId } | { success:false }
if (!auth.success) return createErrorResponse("Non autorisé", 401, corsHeaders);

// Service-role (cron, inter-function) — constant-time compare against the secret key
import { authenticateServiceRole } from "../_shared/utils/auth-helpers.ts";
if (!authenticateServiceRole(req).authorized) {
  return createErrorResponse("Service role required", 401, corsHeaders);
}
```

> An unverified JWT carrying `role: service_role` is **not** proof of anything
> on a function deployed with `--no-verify-jwt` — anyone can forge that claim.
> `authenticateServiceRole` compares against the secret key and ignores the
> claim unless you pass `{ trustRoleClaim: true }`.

## deno.json (import map)

Lives at `supabase/functions/deno.json`. Relative specifiers resolve **from that
file**, so `_shared/` is `./_shared/` — not `./supabase/functions/_shared/`.

```jsonc
{
  "imports": {
    "supabase": "npm:@supabase/supabase-js@2",
    "hono": "npm:hono@4",
    "zod": "npm:zod@4",
    "std/": "jsr:@std/",
    "@shared/": "./_shared/"
  }
}
```

## Checklist

### Contract
- [ ] Routes / methods / auth (user JWT vs service-role) defined
- [ ] Zod schema for the body / query
- [ ] HTTP codes identified (400 validation, 401 auth, 429 rate-limit, 5xx internal)

### Structure
- [ ] CORS: `handleCorsPreflight` + `buildCorsHeaders` on every response
- [ ] Responses via `createJsonResponse` / `createErrorResponse` (or `c.json` in Hono)
- [ ] `safeParse` validation + explicit 400 return
- [ ] Supabase client created inline (service-role OR anon depending on RLS)
- [ ] Logs via `secureLogger` with `operation`

### Deploy
```bash
supabase functions deploy <function-name>
```
