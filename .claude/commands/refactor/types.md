---
description: Improves TypeScript typing (removes any, adds return types, aligns Zod)
context: fork
disable-model-invocation: true
argument-hint: [files or feature to type]
---

# Types Agent

Improves TypeScript typing.

## Checklist

- [ ] No `any` (use `unknown`)
- [ ] Explicit return types
- [ ] Zod schemas match types

## Process

1. Run `pnpm typecheck`
2. Search for `any` — including the forms the `no-any-type` hook lets through on
   an Edit delta: `Record<string, any>`, `any` already present elsewhere in the file
3. Add return types
4. `pnpm test:run` — the **run-once** script. `pnpm test` is watch mode and never
   exits: it hangs this command (`.claude/rules/00-project.md`).

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
