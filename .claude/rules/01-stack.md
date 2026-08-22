<!-- budget: 120 lines · /kit:doctor rules-budget -->
# Technical Stack

| Category      | Technology                            |
| ------------- | ------------------------------------- |
| Frontend      | React 19 + TypeScript 6 (strict)      |
| Build         | Vite 8 (Rolldown)                     |
| Runtime       | Node 20.19+ or 22.12+                 |
| Styles        | Tailwind CSS v4                       |
| Backend       | <BaaS / REST API / GraphQL — name it> |
| Data fetching | TanStack React Query v5               |
| Client state  | Zustand v5                            |
| Routing       | TanStack Router v1 (file-based)       |
| Forms         | React Hook Form v7 + @hookform/resolvers v5 |
| Validation    | Zod v4                                |
| Tests         | Vitest 4 + Testing Library            |
| Lint          | ESLint 10 + typescript-eslint 8 + `@vitest/eslint-plugin` |
| Compiler      | React Compiler 1.0 (`babel-plugin-react-compiler`) — **on** |

> The config files for the compiler, the lint and the coverage floor are written
> once, at scaffolding: `.claude/skills/templates/tooling-config.md`.

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
`/review`'s `tests` dimension owns it, because only it reads the plan.

## Settled external facts

**The ledger is `docs/research-cache/settled.md`, and it is cold on purpose.**
It holds every version-pinned behaviour a probe has already settled — 30 rows
today, and it only grows. `/research` reads it before it fetches anything, and
`doc-researcher` reads it before its first network call. Those are its two
readers, both name it, and neither of them is a session that is merely writing
code.

**No row is ever copied back into this file to make it easier to find.** Each of
the traps that fires *while code is being written* is already carried by the
pattern read at that moment — the `devtools` `MODE` default in
`patterns/zustand.md`, the `setQueryData` bail-out and the awaited `onSettled`
in `patterns/react-query.md`. A row promoted here is a row paid for by every
session and every subagent, to be read by neither. `/kit:doctor`'s
`settled-ledger` refuses a dated table in any rule file.

Who writes a row, what qualifies as one, and when a row dies: the ledger's own
header. Why the cache exists at all: `.claude/guides/01-stack.md`.

## The data client

| Question | Answer for this repo |
| --- | --- |
| Where does the client live? | `src/lib/<client>.ts` |
| Which files may import it? | `*.gateway.ts` and `services.ts` — plus the composition root, which creates the instance (`src/main.tsx`, `src/routes/__root.tsx`; `02-architecture.md`) |
| Auth mechanism | <session / JWT / cookie> |
| Server-side authorization | <RLS / API middleware / none — name the real barrier> |
| Migrations | <tool + folder, or "n/a"> |

Everything downstream reads this table: the `reviewer` agent's `correctness`,
`security` and `db` dimensions, and every command that talks about "the data
layer". Leave it stale and the guardrails guard the wrong thing.

**`enforce-architecture.py` does not read it — it carries its own copy.** Row 1
has an enforced twin in `DATA_CLIENT_MODULE` / `DATA_CLIENT_OWN_PATH`, row 2's
composition root in `COMPOSITION_ROOTS`. Change both together, never one alone:
a hook matching a module nobody imports is **no guardrail at all**, silently,
while this table says the layer is covered.

> Using Supabase? `addons/supabase/` ships a prefilled version of this file, the
> database rules, the migration command, the RLS/client/realtime/storage patterns
> and the edge function `_shared/` layer. Copy them over the core files.

Rationale and the measurement behind the cache: `.claude/guides/01-stack.md`.
