<!-- budget: 75 lines · /kit:doctor rules-budget -->
# Clean Architecture

## Project Structure

`src/features/<name>/` owns domain types/schemas, `services/`, hooks, UI state,
components and pages. Shared leaf roots are `src/components`, `hooks`, `lib`,
`types`, `stores`, `config`; `src/routes` and `providers` are wiring. Cross-runtime
schemas live in `shared/schemas` when present.

## Services — Role of each file

| File | Responsibility |
| --- | --- |
| `*.gateway.ts` | raw DB/API calls and row types |
| `*.mapper.ts` | typed raw row ↔ domain, pure, no casts |
| `*.repository.ts` | gateway + mapper, returns `Result<T>` |
| `*.errors.ts` | feature codes extending shared `ServiceError` |
| `*.utils.ts` | pure logic, no external dependency |
| bare `services.ts` | unsplit data layer |

The unsplit name is exactly `services.ts`, never `<name>.services.ts`: the TDD
matcher and data-client allowlist otherwise disagree. `types.ts` contains no
transport shape. `hooks.ts` calls the repository, never the data client.

## Result Type

`Result<T>`, `ok`, `err`, `unwrap`, `ServiceError` and `formatServiceError` come
once from `.claude/skills/templates/lib-core.md`; never redefine or throw across
the repository boundary.

## The data client and the composition root

May import the client: its own module, `*.gateway.ts`, bare `services.ts`, and
the composition root: `src/main.tsx`, `src/routes/__root.tsx`. Providers, guards,
route helpers, hooks and UI use repositories. Keep this line synchronized with
`COMPOSITION_ROOTS` in `enforce-architecture.py`.

## File size thresholds

| Type | Max lines |
| --- | --- |
| Component | 150 |
| Hook | 100 |
| `hooks.ts` | 300 |
| `services.ts` | 150, or split at 3 domains |

## Dependency Flow and Import Rules

Pages → components → hooks/stores → repository → gateway → client; mapper stays
pure below the repository.

**Forbidden:** `features/A` → `features/B`; and shared leaf code
(`src/components/*`, `src/hooks/*`, `src/lib/*`, `src/types/*`, `src/stores/*`,
`src/config/*`) → `features/*`. Shared code takes behaviour as a parameter;
routes/providers inject it. If two features share logic, move it down once.

No business logic in pages/components. Use `index.ts` only for 20+ exports.

## Backend (fill or delete)

None — this repo is front-end only.

## Router

Before creating a surface, read `.claude/skills/project-rules/SKILL.md`; it routes
to the one template/pattern needed. Architecture rationale and seam exceptions:
`.claude/guides/02-architecture.md`.
