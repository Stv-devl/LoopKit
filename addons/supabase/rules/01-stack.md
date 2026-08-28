<!-- budget: 150 lines · /kit:doctor rules-budget -->
# Technical Stack

<!-- OVERRIDE of `.claude/rules/01-stack.md`: install.sh copies this file OVER the core one.
     The two drift silently — a correction to the core file does NOT reach
     here. When you edit one, diff it against the other in the same pass. -->

| Category      | Technology                            |
| ------------- | ------------------------------------- |
| Frontend      | React 19 + TypeScript 6 (strict)      |
| Build         | Vite 8 (Rolldown)                     |
| Runtime       | Node 20.19+ or 22.12+                 |
| Styles        | Tailwind CSS v4                       |
| Backend       | **Supabase** (Postgres + Auth + Edge Functions) |
| Data fetching | TanStack React Query v5               |
| Client state  | Zustand v5                            |
| Routing       | TanStack Router v1 (file-based)       |
| Forms         | React Hook Form v7 + @hookform/resolvers v5 |
| Validation    | Zod v4                                |
| Tests         | Vitest 4 + Testing Library (front) · `deno test` (edge functions) |
| Lint          | ESLint 10 + typescript-eslint 8 + `@vitest/eslint-plugin` |
| Compiler      | React Compiler 1.0 (`babel-plugin-react-compiler`) — **on** |

> **This file replaces the core `01-stack.md`, so it has to carry everything
> that one carried.** The three sections below are not Supabase-specific and are
> reproduced **verbatim from the core file** — "Version floors that are not
> cosmetic", "React Compiler" and "The lint on the tests": `00-project.md` and
> `05-testing.md` both point at the last one by name, and after the overwrite
> this is the only file that can answer. Change one of them in the core file,
> change it here too — and diff the two in the same pass.
>
> **The settled facts are no longer among them, and that is deliberate.** They
> live in `docs/research-cache/settled.md`, which this addon does not touch, so
> `cp addons/supabase/rules/01-stack.md .claude/rules/` can no longer delete
> answers the loop had already paid `/loop:research` to establish — which is exactly
> what it used to do, silently. Do **not** reintroduce a dated table here:
> `/kit:doctor`'s `settled-ledger` reports it.
>
> Their rationale is **not** here either: it lives in
> `.claude/guides/01-stack.md`, which nothing loads at session start and which
> this addon does **not** override. Same split as the core kit — a trap stays in
> the rule, a retrospective goes to the guide. The Supabase-specific sections
> below carry no retrospective, so they have no guide of their own.

## Version floors that are not cosmetic

Three rows carry a constraint. Downgrading one is a decision: say which, and why.

- **TypeScript 6, not 7.** `typescript-eslint` caps its peer at `<6.1.0` because
  TS 7 ships no stable programmatic API. Here `pnpm lint --max-warnings=0` is a
  **ship gate** (`00-project.md`) — on TS 7 the linter does not degrade, it fails
  to run, and the gate goes with it. Re-check both conditions before any TS bump
  and write the outcome as a row in the ledger.
- **Node 20.19+ / 22.12+.** Vite 8's floor. Vite 8 is ESM-only.
- **React 19, so no `forwardRef`.** `ref` is a plain prop on function components
  since 19. The component template is written against 19 — keep it that way.

## React Compiler

The compiler is **on** and memoizes at build time, so this repo does **not**
write `useMemo`, `useCallback` or `memo` by hand — the rule and its two
exceptions live in `03-conventions.md` ("Memoization").

**The bail-out is the whole risk.** The compiler only memoizes a component it can
**prove** follows the Rules of React. Mutate a prop, write during render, read a
ref at the wrong moment — it silently skips that component. No error, no build
warning: you believe you are memoized and you are not.

**The lint is the only signal**, which is why `pnpm lint` is a ship gate. The
diagnostics ship as `react-hooks/*` rules in `eslint-plugin-react-hooks` v6+
(`eslint-plugin-react-compiler` is dead). Two of them are `warn`, and under
`--max-warnings=0` a warning fails the gate — intended for `unsupported-syntax`,
which names code the compiler skips. Never raise `--max-warnings` to silence one
rule; silence that rule, with a comment.

## The lint on the tests

`@vitest/eslint-plugin` (not `eslint-plugin-vitest`, the old one) turns five
judgement calls into build failures. `pnpm test:run` stays **green** on all five
— that is exactly why they belong to the lint gate.

| Rule | What it makes impossible |
| --- | --- |
| `expect-expect` | a test with **no assertion at all** — the shape of a RED phase that passes |
| `no-focused-tests` | `it.only` / `describe.only` left behind: the suite goes green because it ran one test |
| `no-disabled-tests` | `it.skip` — turning a failing case off instead of fixing the code |
| `no-conditional-expect` | an assertion inside an `if`/`catch`, silently asserting nothing when the branch is not taken |
| `no-identical-title` | two `it()` with the same name in one `describe` — one case overwritten, and the count still goes up |

**`it.todo` is deliberately not caught** — it is the honest way to park a case.
In one of the three frozen test-first files it is a hole no lint can see, and
`/loop:review`'s `tests` dimension owns it, because only it reads the plan.

## Settled external facts

**The ledger is `docs/research-cache/settled.md`**, cold on purpose, read by
`/loop:research` and `doc-researcher` and by nobody else. This addon does not
override it: installing Supabase leaves every settled answer in place. No row
is ever copied back into a rule file — `/kit:doctor`'s `settled-ledger` refuses
a dated table here.


## The data client

| Question | Answer for this repo |
| --- | --- |
| Where does the client live? | `src/lib/supabase.ts` |
| Which files may import it? | `*.gateway.ts` and `services.ts` only |
| Auth mechanism | Supabase Auth — JWT in a session, refreshed by `supabase-js` |
| Server-side authorization | **RLS** — see `06-database.md` and `patterns/rls.md` |
| Migrations | `supabase/migrations/`, via `/database:migration` |
| Generated DB types | `supabase gen types --linked` <!-- FILL: output path + script --> |

Everything downstream reads this table: the `reviewer` agent's `correctness`,
`security` and `db` dimensions, and every command that talks about "the data
layer". Leave it stale and the guardrails guard the wrong thing.

**`enforce-architecture.py` does not read it — it carries its own copy**, and
here it must read `DATA_CLIENT_MODULE = "lib/supabase"`,
`DATA_CLIENT_OWN_PATH = "lib/supabase.ts"`. Change both together, never one
alone: the hook matching a module nobody imports is not a loose guardrail, it is
**no guardrail at all**, silently, while this table says the layer is covered.

## API keys

Supabase is migrating from the legacy `anon` / `service_role` keys to
**publishable** (`sb_publishable_…`) and **secret** (`sb_secret_…`) keys. Both
work today; a project created recently is on the new ones.

<!-- FILL: which key system this project is on, and the env var names. -->

| Key | Where it may appear | Never |
| --- | --- | --- |
| Publishable (or legacy `anon`) | Browser bundle, `src/lib/supabase.ts` | — |
| Secret (or legacy `service_role`) | Edge functions, server jobs | Anywhere the browser can load. **It bypasses RLS.** |

In deployed edge functions the runtime injects `SUPABASE_URL` plus the legacy
`SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`, and — on the new system —
`SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS`, which hold a **JSON object
keyed by key name**, not a plain string. Locally the CLI injects the singular
`SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY`. Read the ones this project
actually has (`supabase status`) rather than assuming.

## Edge functions

Deno runtime, in `supabase/functions/`. Layout, conventions and the shared infra
helpers: `02-architecture.md` (Backend section) and
`.claude/skills/patterns/edge-function*.md`.
