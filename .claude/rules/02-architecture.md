<!-- budget: 190 lines · /kit:doctor rules-budget -->
# Clean Architecture

## Project Structure

```
src/
├── components/          # Shared UI (ui/, layouts/, states/, loading/, guards/)
├── features/            # Functional modules
├── hooks/               # Shared React hooks
├── lib/                 # Utilities (data client, queryClient, result, errors)
├── providers/           # Context providers
├── config/              # Configuration
├── routes/              # Route definitions
├── stores/              # App-level Zustand stores (no single feature owns them)
├── types/               # Shared TypeScript types
├── styles/              # Global styles
└── test/                # Test setup

shared/
└── schemas/             # Zod schemas shared with the backend (if any)
```

## Feature Module Structure

```
features/{name}/
├── types/
│   ├── types.ts              # Domain entities (pure, framework-agnostic)
│   └── schemas.ts            # Zod validation
├── services/                 # role of each file → table below
│   ├── {name}.gateway.ts
│   ├── {name}.mapper.ts
│   ├── {name}.repository.ts
│   ├── {name}.errors.ts
│   └── {name}.utils.ts
├── hooks/hooks.ts            # React Query: queryFn → repository
├── stores/store.ts           # Zustand (UI state only)
├── components/
└── pages/
```

### Services — Role of each file

| File            | Responsibility                                     | Imports                 |
| --------------- | -------------------------------------------------- | ----------------------- |
| `gateway.ts`    | DB/API calls, returns raw rows                     | data client, DB types   |
| `mapper.ts`     | Transforms raw row → domain entity (and vice versa) | `types.ts` + the row **type** from `gateway.ts` |
| `repository.ts` | Combines gateway + mapper, returns `Result<T>`     | gateway, mapper, errors |
| `errors.ts`     | Feature-specific errors                            | `src/lib/errors.ts`     |
| `utils.ts`      | Pure functions with no external dependency         | nothing                 |

**The raw row type is declared in the gateway** — it describes the payload the
transport returns, and `types.ts` must stay free of transport shapes. The mapper
imports it **type-only**, which creates no runtime edge, so the mapper stays
pure. An un-annotated gateway pushes an implicit `any` up into the repository,
where `no-any-type` denies the write far from the cause. Shape in
`templates/feature.md`.

The **data client** is whatever `01-stack.md` declares. The rule is not about a
vendor: raw I/O lives in one named layer, and nothing above it knows the transport.

**The un-split variant is spelled `services.ts`, bare** — the four files above
carry the `{name}.` prefix, that one does not. `{name}.services.ts` is the
natural-looking name and it is a trap: the TDD hooks and the coverage glob match
it, but `enforce-architecture.py` allows the data client only in `*.gateway.ts`
and in the exact basename `services.ts`. It would be denied the one import it
exists to hold.

### Result Type (`src/lib/result.ts`)

```typescript
type Result<T, E = ServiceError> =
  | { success: true; data: T }
  | { success: false; error: E };
```

Repositories always return a `Result` — never an implicit `throw`.

`Result`, `ok`, `err`, `unwrap`, `ServiceError` and `formatServiceError` are
scaffolded **once** from `.claude/skills/templates/lib-core.md`, the single
source of truth for their shapes — never redeclared per feature. A repo that has
not scaffolded them must do it before its first feature.

### The data client and the composition root

**One exception** to "raw I/O lives in the data layer": the *composition root* —
the file that **creates** the client instance and injects it.

| May import the data client | Why |
| --- | --- |
| `src/lib/<client>.ts` | it *is* the client module |
| `*.gateway.ts`, `services.ts` | the data layer |
| `src/main.tsx`, `src/routes/__root.tsx` | composition root: creates the instance, injects it into the router/provider context |

Everything else — providers, guards, route helpers, hooks, components — goes
through a repository: an `AuthProvider` reads the session via the `auth` feature's
repository, not via `client.auth`. `enforce-architecture.py` enforces exactly this
list; if your composition root lives elsewhere, update `COMPOSITION_ROOTS` — don't
work around it.

### File size thresholds

**This table is the only copy.** `/refactor:split` and the `reviewer` agent read
it here. Split a file once it exceeds its threshold. Over-threshold in review =
**Minor**.

| Type          | Max lines |
| ------------- | --------- |
| Component     | 150       |
| Hook          | 100       |
| `hooks.ts`    | 300       |
| `services.ts` | 150, or 3+ domains → split into gateway/mapper/repository |

## Dependency Flow

```
pages → components → hooks/stores → repository → gateway → data client
                                        ↓            ↓
                                     mapper       raw rows
                                        ↓
                                   Result<Entity>
```

## Import Rules

**Allowed from anywhere:** `shared/*`, `src/components/*`, `src/lib/*`,
`src/hooks/*`, `src/types/*`, `src/stores/*`, `src/config/*`, `src/providers/*`

**Forbidden:**

- `features/A` → `features/B` (cross-feature)
- `src/components/*`, `src/hooks/*`, `src/lib/*`, `src/types/*`, `src/stores/*`,
  `src/config/*` → `features/*` — shared **leaf** code must not depend on a
  feature. The arrow points one way. An app-level store is leaf code: a theme
  store that imports a feature is a store no other feature can read.
  If a shared helper needs feature behaviour, it takes it as a parameter and the
  wiring layer injects it (see `patterns/guards.md`).

**Wiring is the exception**: `src/routes/*` and `src/providers/*` compose
features, so they may import them. Nothing imports them for their logic.

**The arrow is checked on the direct edge, and only there.** A shared guard may
import a provider, and that provider may import a feature: the chain
guards → providers → features passes `enforce-architecture.py`, and it is the
shape `patterns/guards.md` ships. The provider is the seam — it exposes a
feature-agnostic contract (`useAuth()`), so swapping the feature behind it
changes no component. What the rule forbids is the shared file **naming a
feature itself**. For the transitive guarantee, inject the behaviour instead;
`patterns/guards.md` shows both.

If two features share code → move it into `shared/` or `src/`. Beware: the four
layer words are test-first and **frozen** under `shared/` exactly as under `src/`
(the TDD hooks key on the filename, not the root — `05-testing.md`).

## Rules

- No business logic in components/pages
- `hooks.ts`: calls the repository (or `services.ts`), never the data client
- `mapper.ts`: no cast (`as`), explicit input/output typing
- `repository.ts`: returns `Result<T>`, never throws
- `types.ts`: pure, no transport/DB types
- Use `index.ts` only for 20+ exports, otherwise import directly

## Backend (fill or delete)

None — this repo is front-end only.

## Patterns (read IF creating)

- **Bootstrapping a repo** (do this first) → `.claude/skills/templates/lib-core.md`
  (`Result`, `ServiceError`, `unwrap` — everything else imports them — **and
  `queryClient.ts`**, whose defaults every hook inherits), then
  `.claude/skills/templates/tooling-config.md` (compiler, lint gate, coverage),
  then `.claude/skills/templates/ci.md` (the same gates, server-side)
- New feature → `.claude/skills/templates/feature.md`
- Shared UI component → `.claude/skills/templates/component.md`
- A page or a layout → `.claude/skills/templates/page.md` (which of layout and
  page owns the landmark and the heading)

Rationale — the seam, and who catches duplication: `.claude/guides/02-architecture.md`.
