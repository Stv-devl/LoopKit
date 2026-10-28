---
description: Dispatch a bounded small ticket into its own worktree
argument-hint: [small change description or --status]
---

# /loop:small — one bounded change, one merge

## Process

1. If `$ARGUMENTS` is `--status`, run the status report below, then stop.
2. Research inline, read-only: the files the description names, their tests, their direct imports, their base branch and the local conventions. No fan-out. Its traps become the spec's `Vigilance`.
3. Judge the S2 triggers on the description **and** this research, one line each: schema change, critical trigger (`11-token-budget.md`: authorization, payment, destructive data), new dependency, or new screen (a change to an existing screen is fine). A hit proposes `/loop:spec`; do not dispatch it here.
4. Draft the small spec using the template, in the session, not on disk. Run `.claude/scripts/small-paths.sh <path>...` and `.claude/scripts/small-dispatch-check.sh <name> <path>...`; a refusal stops with its line.
5. Ask exactly one `AskUserQuestion` with three answers: go, edit (back to the draft, step 4), or route to `/loop:spec`.
6. After go, run `.claude/scripts/small-paths.sh <path>...` and `.claude/scripts/small-dispatch-check.sh <name> <path>...` again on the final `Files`. A refusal stops with its output.
7. Fork, as separate Bash calls, never chained with `&&` (`enforce-git-workflow.sh` reads the first segment's tree, and the main tree may be on main): (a) `git worktree add .claude/worktrees/small-<name> -b feat/small-<name>`; (b) write `docs/specs/small/<name>.md` in the worktree with the Write tool, with `Base:` set to the main tree's branch and `HEAD` sha at the fork; (c) `git -C .claude/worktrees/small-<name> add docs/specs/small/<name>.md`; (d) `git -C .claude/worktrees/small-<name> commit -m "spec: small <name>"`. The spec is the branch's first commit and nothing else is written in the main tree.
8. Setup, announced: `pnpm -C .claude/worktrees/small-<name> install --frozen-lockfile`. The user copies any env file (`protect-files` forbids it to an agent; `.worktreeinclude` does not apply to `git worktree add`, D1). This session never enters the worktree: it stays in the main tree, free for the next `/loop:small`.
9. Hand over exactly: `cd .claude/worktrees/small-<name> && ./workflow.sh "/loop:orchestrate docs/specs/small/<name>.md"`, to run in another terminal.

## Status (`--status`)

Read from git, never change a ticket. Print one table; each row names its source rule and the commands offered (each prompts, the user chooses):

| State | Source | Commands offered |
| --- | --- | --- |
| in flight | `small-*` worktree whose branch is not merged (S4.4: spec commit and ancestor of the `Base:` branch) | none |
| ejected | same, and the branch holds `docs/work/small-<name>/ejected` | `git worktree remove .claude/worktrees/small-<name>` alone (the branch stays as a reference) |
| failed dispatch | `small-*` worktree whose branch has no spec commit | `git worktree remove .claude/worktrees/small-<name>` and `git branch -d feat/small-<name>` |
| merged, to clean | spec commit present, branch an ancestor of the `Base:` branch (S4.4), worktree still there | `git worktree remove .claude/worktrees/small-<name>` and `git branch -d feat/small-<name>` |

## Template

```markdown
# Small: <title>
Pipeline: small
Token profile: economy
Base: <branch> <sha>

## Objective
<observable result, 1-2 lines>

## Files
- <path>
- <path of its test file>

## Contracts
<signatures, query keys, Zod types touched, or `none`>

## Vigilance
<traps from the inline research, or `none`>

## Done when
- [ ] <observable result>

## Test cases
#### <test-first file, e.g. utils.test.ts>
- [ ] U1 <test-first case>

#### <test-after file, e.g. useThing.test.ts>
- [ ] <test-after case>

## Verify
<run-once commands>
```

## Rules

- Small means at most six `src/` paths outside the foundations, test files included. `Files` holds one repo-relative path per line, no glob, no prose, test files included.
- Every logic file has its test file in `Files`: the utils, mapper, repository and services layers, and hooks (`small-dispatch-check.sh` S4.6).
- A test-first file holds cases with ids (`- [ ] U1 <case>`); a test-after file holds cases without ids (`- [ ] <case>`).
- `Base:` is written by the dispatcher: the main tree's branch and `HEAD` at the fork.
- The spec is committed alone on its small branch, never edited after; the main tree remains clean.
- A later S2 trigger is written as `S2 trigger: <kind>` and ejects to `/loop:spec`.

## Task: $ARGUMENTS
