---
description: Splits oversized files into coherent modules
context: fork
disable-model-invocation: true
argument-hint: [files to split]
---

# Split Agent

Splits oversized files.

## Thresholds

Read them from **`.claude/rules/02-architecture.md` → "File size thresholds"**.
That table is the only copy — it also covers `services.ts` (150 → split into
gateway/mapper/repository), which a duplicate here kept losing.

## Process

1. Identify file >threshold (against the table in `02-architecture.md`)
2. Find logical boundaries
3. Extract to separate files
4. Update imports
5. `pnpm test:run <paths>` — the **run-once** script. `pnpm test` is watch mode
   and never exits: it hangs this command (`.claude/rules/00-project.md`).
6. `pnpm typecheck` — extraction breaks imports silently more often than tests do

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
