<!-- budget: 60 lines · /kit:doctor rules-budget -->
# Project Overview

<!-- FILL: one sentence describing this product. -->

Web application with clean architecture and feature-based modules.

## Commands

<!-- FILL: the real scripts of this repo. Keep the six roles below. -->

```bash
pnpm dev          # Start dev server
pnpm build        # Build for production
pnpm test:run     # Run tests once — USE THIS in any gate or agent
pnpm test:coverage # vitest run --coverage — thresholds from 05-testing.md
pnpm typecheck    # tsc --noEmit — part of the ship gate
pnpm lint         # eslint --max-warnings=0 — part of the ship gate
pnpm audit --audit-level=high   # known CVEs in the dependency tree — ship gate
pnpm test         # Watch mode — interactive only, it never exits
pnpm test:ui      # Run tests with UI
```

> `pnpm test` is the runner in **watch mode**: it hangs an agent's Bash call.
> Gates and subagents use `pnpm test:run`, optionally scoped to paths.

**The six roles a gate needs**, whatever they are named here: run-once tests,
typecheck, **lint**, **dependency audit**, build, dev server. If a role has no
script, say so — a gate cannot invent one.

**Five of the six run twice, and that is not redundancy.** `/ship` runs them
before the commit; `.github/workflows/ci.yml` runs them after the push, where
nobody can skip them. The sixth, the dev server, has nothing to serve in CI. A
green CI is **not** a reason to stop running `/ship` — it reports on a diff
already pushed.

Two of the six are gates for reasons that are not obvious, and both reasons are
worth knowing before anyone proposes dropping them:

- **`pnpm audit`** is the only security surface a reviewer cannot see in a diff —
  a CVE published last week changes nothing in your code. A high/critical
  advisory **with a fix** is red: bump it. One with **no fix** is not a wall:
  announce the package, the advisory and whether the vulnerable path is even
  called, and let the user decide. What is forbidden is the third option,
  swallowing it silently.
- **`pnpm lint --max-warnings=0`** catches three classes of defect that keep
  `test:run` green: conditional hooks and exhaustive-deps, a component the React
  Compiler **silently skipped**, and a test that asserts nothing or is
  `.only`/`.skip`'d. `eslint-check.sh` runs after every write and is
  **non-blocking** — it prints a count. Only the gate stops these.

Rationale in full: `.claude/guides/00-project.md`.

## Import Aliases

<!-- FILL: the aliases actually declared in tsconfig / the bundler config. -->

- `@/*` → `src/*`
- `@shared/*` → `shared/*` (code shared with the backend, if any)
