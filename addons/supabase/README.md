# Addon — Supabase

The core kit is stack-agnostic about the backend. This addon carries the parts
that only make sense on Supabase: the database and stack rules, the migration
command, RLS, the front-end client, realtime, storage, and the edge-function
patterns — plus a working `_shared/` infra layer for the functions.

## Install

```bash
./install.sh /path/to/project --supabase
```

Or by hand, from the project root, after installing the core kit:

```bash
KIT=../loopkit/addons/supabase
cp $KIT/rules/01-stack.md               .claude/rules/     # overwrites the core one
cp $KIT/rules/06-database.md            .claude/rules/     # overwrites the core one
cp $KIT/commands/database/migration.md  .claude/commands/database/
cp $KIT/skills/patterns/*.md            .claude/skills/patterns/
cp $KIT/skills/templates/*.md           .claude/skills/templates/
cp -r $KIT/functions/.                  supabase/functions/   # the _shared/ layer
```

## Wiring — seven edits, two of them done by the installer

The installer copies files, and on a **fresh** install it wires steps 2 and 3
itself — they are marked below. What it never touches is a file the project
already owns: that one comes back as `.new`, and its step is yours again.

Run `/kit:doctor` after any manual pass. Steps 2 and 3 are twins — one value
written in two files — and it reports the pair the day they drift.

1. **`.claude/rules/02-architecture.md` → Backend section.** Replace
   "None — this repo is front-end only" with the block below, and point the
   Patterns list at `.claude/skills/patterns/edge-function*.md`.
2. **`.claude/hooks/enforce-architecture.py`** → `DATA_CLIENT_MODULE = "lib/supabase"`,
   `DATA_CLIENT_OWN_PATH = "lib/supabase.ts"`. Left at the default it guards a
   door that does not exist. **Wired by `install.sh --supabase` on a fresh
   install.**
3. **`.claude/hooks/prevent-destructive-commands.sh`** → add `supabase` to
   `PROTECTED_DIRS`, **and the same entry to the list in `CLAUDE.md`** — the
   value is declared twice. **Both wired by `install.sh --supabase` on a fresh
   install.**
4. **`.claude/rules/01-stack.md`** → fill the two `FILL` markers (generated-types
   path, which API key system).
5. **`.claude/rules/00-project.md`** → add the edge-function gate
   (`cd supabase/functions && deno task gate` — check, lint, fmt, test) next to
   the front-end scripts, so the ship gate has something to call.
6. **`.claude/rules/04-state.md`** → its real-time row points at the data layer
   in the abstract; point it at `.claude/skills/patterns/realtime.md`.
7. **the `test.exclude` key of `vite.config.ts`** → add `supabase/functions/**`
   (`.claude/skills/templates/tooling-config.md` — never a separate
   `vitest.config.ts`, which replaces `vite.config.ts` rather than merging it).
   The shipped config already carries that line; this step is for a project that
   owned its config before the kit landed. This addon ships
   `_shared/tests/shared.test.ts`, a **Deno** test importing `jsr:@std/assert`.
   Vitest's default `include` matches `**/*.test.ts` everywhere, so left alone it
   collects that file, fails on the `jsr:` specifier, and `pnpm test:run` — the
   `/loop:ship` gate — goes red on a file that is green under `deno task test`.

Then: `grep -rn "FILL" .claude/` — the patterns carry markers for the example
function names, which are placeholders, not this repo's.

**Not on the list, because it needs no wiring**: the front-end hooks keep out of
`supabase/functions/` on their own. `cwk_foreign_toolchain` (`hooks/hook-lib.sh`)
looks for a `deno.json` above the file, and `format-on-save`, `eslint-check` and
the three `tdd-*` hooks skip it when there is one. Without that, Prettier
rewrites the layer this addon ships — measured: 6 files of 7, 325 lines — and
`deno fmt --check` in the gate goes red on code nobody touched; ESLint chokes on
`npm:`/`jsr:` specifiers; and a `supabase/functions/<fn>/utils.ts` is unwritable
until someone proves a vitest red for a Deno test. Keep `deno.json` at the root
of the functions tree and there is nothing to do.

## Backend section to paste into `02-architecture.md`

```
supabase/functions/
├── deno.json                # import map: "@shared/" → "./_shared/"
├── _shared/                 # infra only (no createApp factory, no _shared/app|clients)
│   ├── middleware/          # security-headers (+ rate-limiter, concurrent-lock… if you add them)
│   ├── schemas/             # shared Zod only
│   ├── services/            # auth.service.ts
│   └── utils/               # cors.ts, http.ts, auth-helpers.ts, secure-logger.ts
└── my-function/             # autonomous: business logic in its own files
    ├── index.ts             # Deno.serve(handler) OR Deno.serve(app.fetch) if Hono
    ├── app.ts               # routes (only if Hono / multi-routes)
    ├── schema.ts            # specific Zod
    └── types.ts             # local types
```

Rules: each function autonomous (no cross-function import) · `_shared/` = infra,
never business logic · manual Zod `safeParse()` · auth/CORS/rate-limit called by
hand in the handler · flat error shape `{ "error": "message" }`.

## `_shared/` — shipped, not described

`addons/supabase/functions/` contains a **working** implementation of the eight
helpers the patterns import (`createJsonResponse`, `createErrorResponse`,
`buildCorsHeaders`, `handleCorsPreflight`, `secureLogger`,
`AuthService.authenticateRequest`, `authenticateServiceRole`,
`buildSecurityHeaders`), plus the supporting exports they need
(`applySecurityHeaders`, `SECURITY_PRESETS`, `extractClientIp`,
`isAllowedOrigin`, `resolveAllowedOrigin`, `extractUserIdFromToken`,
`createEmptyResponse`). It typechecks, lints, formats and has **29 tests**:

```bash
cd supabase/functions
deno task gate     # check + lint + fmt --check + test, in that order
```

Or one role at a time — `deno task check` · `lint` · `fmt` · `test`. The four are
the backend half of the gate roles `00-project.md` asks for; wire `deno task gate`
into `/loop:ship` next to the front-end ones.

> `deno lint` and `deno fmt --check` are in there for the same reason `pnpm lint`
> is a ship gate: `deno test` stays green on an `async` test that never awaits, and
> a formatting drift that nobody sees becomes a diff that nobody can read.

Five helpers are **named by the patterns but not shipped**, because a generic
version would be wrong: `checkRateLimit`, `acquireConcurrentLock`,
`withProviderGuard`, `WebhookValidator`, `verifyProviderSignature`. Implement the
ones you need and **delete the pattern sections you did not implement** — a
pattern describing a helper that does not exist is how an agent writes an import
to nothing. Details in `functions/README.md`.

## What this addon does NOT own

Supabase ships an official plugin (`supabase` + `supabase-postgres-best-practices`
skills, and an MCP server). It is better than this addon at everything that
changes upstream, and it is maintained. Split the work:

| This addon | The official skill / MCP |
| --- | --- |
| Where code lives, which layer may import the client | Current API surface, changelog, breaking changes |
| The project's migration discipline (`/database:migration`) | Live introspection, `execute_sql`, logs |
| Edge-function conventions for **this** repo | Postgres depth: indexes, plans, connections, bloat |
| The RLS rules the reviewer gates against | `db advisors` / `get_advisors` findings |

`rules/06-database.md` points at them instead of duplicating them. When the two
disagree, the official skill is right about Supabase and this addon is right
about the project.

## Files

| File | Role |
| --- | --- |
| `rules/01-stack.md` | Stack + data-client table, prefilled for Supabase, API keys |
| `rules/06-database.md` | Provider, schema workflow, migration rules, **Authorization/RLS**, CLI |
| `commands/database/migration.md` | `/database:migration`, Supabase flavour |
| `functions/_shared/**` | Working infra layer + its tests |
| `functions/deno.json` | Import map and test tasks |
| `skills/patterns/rls.md` | Policy shape, roles, `SECURITY DEFINER`, views, testing |
| `skills/patterns/supabase-client.md` | Front-end client, generated types, auth session |
| `skills/patterns/realtime.md` | Channels, publication, cleanup, React Query wiring |
| `skills/patterns/storage.md` | Buckets, path-based policies, signed URLs |
| `skills/patterns/edge-function.md` | Core pattern (plain `Deno.serve` and Hono) |
| `skills/patterns/edge-function-auth.md` | User JWT vs service-role |
| `skills/patterns/edge-function-middlewares.md` | CORS, security headers, locks, rate limit |
| `skills/patterns/edge-function-cron.md` | pg_cron + pg_net scheduled invocations |
| `skills/patterns/edge-function-webhooks.md` | Signature verification per provider |
| `skills/patterns/edge-function-tests.md` | Deno test layout |
| `skills/patterns/api-tests.md` | Hono integration tests via `app.request` |
| `skills/templates/migration.md` | SQL migration template |
| `skills/templates/webhook.md` | Full webhook function scaffold |

## API keys

Supabase is moving from `anon` / `service_role` to **publishable**
(`sb_publishable_…`) and **secret** (`sb_secret_…`) keys. Both work; a recent
project is on the new ones. Deployed functions get the legacy
`SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` **and**
`SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` — the plural ones hold a
**JSON object keyed by key name**, not a string. Locally the CLI injects the
singular `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY`. Check
`supabase status` rather than assuming.

**The shipped helpers read the singular spellings only** — `SUPABASE_SECRET_KEY`
then `SUPABASE_SERVICE_ROLE_KEY` in `auth-helpers.ts`, `SUPABASE_PUBLISHABLE_KEY`
then `SUPABASE_ANON_KEY` in `auth.service.ts`. That covers local development and
every deployed function, since the runtime still injects the legacy pair
alongside the new one. Parsing the plural JSON objects is left out on purpose:
it means choosing *which* named key to use, and that choice is the project's.
A repo that has retired its legacy keys has to add it — and no test will tell it.

## Traps this addon encodes

- **RLS on, zero policy** = a table nobody can read, and no error saying so. RLS
  off in `public` = a table everybody can read, also silently.
- **An UPDATE policy without `WITH CHECK`** lets a user reassign a row to
  someone else. `TO authenticated` alone is authentication, not authorization.
- **`auth.uid()` unwrapped in a policy** is called once per row. `(select auth.uid())`.
- **`CREATE INDEX CONCURRENTLY` cannot go in a migration** — it cannot run in a
  transaction block, and the CLI (v2.92.1+) rejects it with `SQLSTATE 25001`.
- **The CLI does not read `-- DOWN` markers.** It runs every statement in the
  file; the rollback must be commented out line by line or it reverts the UP.
- **Never invent a migration filename** — `supabase migration new <name>`.
- **`supabase db push` applies every pending migration**, including ones another
  session wrote. `supabase migration list` first.
- **Stacked `CREATE OR REPLACE`**: source a function body from the _latest_
  migration that defines it, never the one a spec cites. That is how an
  improvement gets silently reverted.
- **Stripe's `constructEvent` throws in Deno.** `constructEventAsync` with an
  explicit `Stripe.createSubtleCryptoProvider()`.
- **An unverified `role: service_role` claim proves nothing** on a function
  deployed with `--no-verify-jwt` — anyone can forge it.
- **Deploy one function at a time.** A bulk deploy has reset per-function flags
  and orphaned `config.toml` entries; declare `verify_jwt` in `config.toml`, not
  only on the command line.
- **Views bypass RLS** unless created `WITH (security_invoker = true)`.
- **Storage upsert needs INSERT + SELECT + UPDATE.** With only INSERT, the first
  upload works and every replacement fails silently.
