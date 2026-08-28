<!-- budget: 45 lines · /kit:doctor rules-budget -->
# Technical Stack

| Category | Technology |
| --- | --- |
| Frontend | React 19 + TypeScript 6 strict |
| Build/runtime | Vite 8 · Node 20.19+ or 22.12+ |
| Styles | Tailwind CSS v4 |
| Backend | <BaaS / REST / GraphQL — name it> |
| Data/state | TanStack Query v5 · Zustand v5 |
| Routing/forms | TanStack Router v1 · React Hook Form v7 |
| Validation/tests | Zod v4 · Vitest 4 + Testing Library |
| Lint/compiler | ESLint 10 · React Compiler 1.0 on |

Version changes are decisions. Preserve Vite's Node floor and verify
TypeScript against `typescript-eslint` before upgrading. React 19 takes `ref` as
a prop; no new `forwardRef`. Compiler bail-outs are red lint findings, never a
reason to add manual memoization. Details: `.claude/guides/01-stack.md`.

Settled external facts live only in `docs/research-cache/settled.md` and are read
by `/loop:research` and `doc-researcher`, never copied into a hot rule.

## The data client

| Question | Answer for this repo |
| --- | --- |
| Where does the client live? | `src/lib/<client>.ts` |
| Which files may import it? | `*.gateway.ts`, bare `services.ts`, and the composition root |
| Auth mechanism | <session / JWT / cookie> |
| Server-side authorization | <RLS / middleware / none — name it> |
| Migrations | <tool + folder, or n/a> |

The first row must match `DATA_CLIENT_MODULE` and `DATA_CLIENT_OWN_PATH` in
`enforce-architecture.py`; the composition roots must match `02-architecture.md`
and `COMPOSITION_ROOTS`. Change each pair together. Supabase projects replace
this file with the addon copy.

Scaffolding config: `.claude/skills/templates/tooling-config.md`.
