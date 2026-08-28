<!-- budget: 35 lines · /kit:doctor rules-budget -->
# Project Overview

<!-- FILL: one sentence describing this product. -->
Web application with clean architecture and feature-based modules.

## Commands

<!-- FILL: replace with the real scripts; keep every gate role or say absent. -->

```bash
pnpm dev
pnpm build
pnpm test:run
pnpm test:coverage
pnpm typecheck
pnpm lint
pnpm audit
pnpm test
pnpm test:ui
```

Gates and agents use the run-once test command, never `pnpm test` watch mode.
`/loop:ship` requires tests, coverage, typecheck, lint with zero warnings, build
and dependency audit; CI mirrors them when a remote exists. A gate with no real
script is reported missing, never invented or silently skipped.

Gate rationale and advisory handling: `.claude/guides/00-project.md`.
Tooling and CI copies: `.claude/skills/templates/tooling-config.md` and `ci.md`.

## Import Aliases

<!-- FILL: aliases actually declared in tsconfig and bundler config. -->
- `@/*` → `src/*`
- `@shared/*` → `shared/*` (if present)
