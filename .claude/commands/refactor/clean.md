---
description: Cleans up dead code (unused exports, dependencies, variables)
context: fork
disable-model-invocation: true
argument-hint: [files or feature to clean]
---

# Clean Agent

Cleans up dead code.

## Tools

```bash
npx knip              # Unused exports, files and dependencies (one pass)
pnpm lint             # Unused vars (the repo's lint script, see 00-project.md)
```

> `knip` replaces the `ts-prune` + `depcheck` pair, both unmaintained. It
> understands the flat ESLint config, Vite and Vitest, so it does not report the
> test setup and the config files as dead. Run it before deleting anything: an
> export used only by a test, or only by the router, is a false positive in any
> of these tools — check each hit.

## Process

1. Run tools above
2. Remove dead code
3. `pnpm test:run` then `pnpm typecheck` — the **run-once** script. `pnpm test`
   is watch mode and never exits: it hangs this command
   (`.claude/rules/00-project.md`).

## Rules

- Remove completely, don't comment
- Update imports after removal

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
