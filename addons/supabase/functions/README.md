# `supabase/functions/_shared/` — the infra the patterns assume

Copy this tree to `supabase/functions/` in your project. Everything the `edge-function*.md` patterns
import from `_shared/` is here and compiles as-is:

```
supabase/functions/
├── deno.json                          # import map — "@shared/" → "./_shared/"
└── _shared/
    ├── middleware/security-headers.ts # buildSecurityHeaders, SECURITY_PRESETS, applySecurityHeaders
    ├── services/auth.service.ts       # AuthService.authenticateRequest  (user JWT)
    └── utils/
        ├── auth-helpers.ts            # authenticateServiceRole, extractUserIdFromToken, extractClientIp
        ├── cors.ts                    # buildCorsHeaders, handleCorsPreflight, isAllowedOrigin, resolveAllowedOrigin
        ├── http.ts                    # createJsonResponse, createErrorResponse, createEmptyResponse
        └── secure-logger.ts           # secureLogger.info/warn/error
```

Verify after copying:

```bash
cd supabase/functions && deno check _shared/**/*.ts
```

## Configuration

| Secret                                              | Used by           | Absent →                                                    |
| --------------------------------------------------- | ----------------- | ----------------------------------------------------------- |
| `ALLOWED_ORIGINS`                                   | `cors.ts`         | falls back to `*` — fine while wiring up, not in production |
| `SUPABASE_URL`                                      | `auth.service.ts` | auth returns `AUTH_ERROR`                                   |
| `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_ANON_KEY`    | `auth.service.ts` | same                                                        |
| `SUPABASE_SECRET_KEY` / `SUPABASE_SERVICE_ROLE_KEY` | `auth-helpers.ts` | service-role auth always refuses                            |

The runtime injects the `SUPABASE_*` ones. `ALLOWED_ORIGINS` is yours:

```bash
supabase secrets set ALLOWED_ORIGINS=https://app.example.com
```

## Two traps encoded in this code

**`authenticateServiceRole` does not trust the `role` claim by default.** A JWT carrying
`role: service_role` is only meaningful if something verified its signature. On a function deployed
with `--no-verify-jwt` — which is every webhook and most cron targets — nothing did, and the claim
is forgeable by anyone. Only the constant-time comparison against the secret key is safe there.
`{ trustRoleClaim: true }` exists for functions that keep gateway JWT verification on; read the
comment before setting it.

**`AuthService.authenticateRequest` costs a round-trip, on purpose.** Decoding the JWT locally is
faster and proves nothing. If you need the user id merely to key a rate limiter _before_
authenticating, that is what `extractUserIdFromToken` is for — and it is documented as not being an
identity.

## Not shipped

These are named by the patterns but are project-shaped enough that a generic version would be wrong.
Implement the ones you need — and **delete the pattern sections you did not implement**, so no agent
writes an import to nothing:

| Helper                                                       | Pattern that documents it                           | What it needs from you                              |
| ------------------------------------------------------------ | --------------------------------------------------- | --------------------------------------------------- |
| `checkRateLimit`                                             | `edge-function-middlewares.md`                      | a `rate_limits` table + your quotas                 |
| `acquireConcurrentLock` / `releaseConcurrentLock`            | `edge-function-middlewares.md`                      | a `concurrent_locks` table with `UNIQUE(lock_key)`  |
| `withProviderGuard`                                          | `edge-function-middlewares.md`                      | only if you drive a quota-bound third-party account |
| `WebhookValidator` + the `SupabaseAdminClient` type it takes | `edge-function-webhooks.md`, `templates/webhook.md` | a `stripe_events` (or equivalent) dedup table       |
| `verifyProviderSignature`                                    | `edge-function-webhooks.md`                         | your provider's signature scheme                    |
