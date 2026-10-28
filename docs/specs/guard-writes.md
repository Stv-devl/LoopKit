# Spec: Guarded set, Write/Edit side
Token profile: standard (adds asks and one deny, widens nothing)
Split from: `docs/specs/light-permissions.md` (2026-10-28, pass 1 of 3; then `guard-shell.md`, then `light-permissions-git.md`). Research reused: `docs/work/light-permissions/research.md`; plan-critic findings of that plan: `docs/work/light-permissions/plan.md`.

## Objective
One list of guarded paths, read by every hook, and a Write/Edit on any of them asks the user, from the main tree and from a worktree. `.claude/.tdd-red/**` is denied. Nothing here widens a permission: it ships safely on its own, before `light-permissions-git.md` turns on `acceptEdits`.

## Scope
- IN :
  - **Spike first** (answers "does a hook `ask` override `acceptEdits`?", which decides `ask` vs deny-with-text for this spec and the next two). Scratch project in the session scratchpad: `git init`, one seed commit, settings `defaultMode: acceptEdits`, allow `Bash(git commit -m *)`, a throwaway PreToolUse hook that logs each call to `hook.log` and returns `ask`. One `claude -p --permission-mode acceptEdits --output-format json --max-turns 2 --tools <the tool under test>` run per case (`--tools` restricts; no `--allowedTools`, which would approve), plus a control run without the hook: (a) Write `vite.config.ts`; (b) Bash `git commit -m x --amend --allow-empty` (allow rule); (c) Bash `sed -i 's/a/b/' vite.config.ts` (acceptEdits' own Bash auto-approval). Verdict per case: hook logged + the call in `permission_denials` + control approved = "ask overrides". Any other outcome stops the pass for the user's decision. Result written to `docs/research-cache/claude-code-permissions.md`.
  - **`.claude/hooks/hook-guarded.sh`** (new, sourced, **no side effect**: no trap, no log, no output, no `shopt` outside a function-local scope).
    - Guarded patterns (repo-relative, `[[ == ]]` matching, `*` crosses `/` — an over-match, never an under-match): `.claude/hooks/*`, `.claude/scripts/*`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.*`, `eslint.config.*`, `vite.config.*`, `package.json`, `tsconfig*.json`, `.github/workflows/*`. Denied: `.claude/.tdd-red/*`.
    - **Folders count**: a path that is a folder above a pattern's fixed part (`.`, `.claude`, `.claude/hooks`, `.claude/scripts`, `.github`, `.github/workflows`) is guarded; `.claude/.tdd-red` itself is denied; its ancestors (`.claude`, `.`) are guarded, so they ask (amended 2026-10-28 at the plan gate). This is what makes a later `rm -rf .github/workflows` or `cp -r x/. .claude/` catchable.
    - `cwk_guard_rel <path> [<base>]` prints the repo-relative path: a relative path is joined to `<base>` (callers pass the hook input's `.cwd` via `jq -r '.cwd // empty'`, else `$CLAUDE_PROJECT_DIR`; **never `$PWD`**); then, on both branches, lexical normalisation (`//`, `/./`, `..`); then strip `$CLAUDE_PROJECT_DIR/` or its `pwd -P` form, else compare the `realpath` of the deepest existing parent with the project's `pwd -P`; then strip a leading `.claude/worktrees/<x>/`. Outside the project: prints nothing, exit 1.
    - `cwk_is_guarded <rel>` / `cwk_is_guard_denied <rel>` take an already repo-relative path, resolve nothing, print nothing: exit 0/1. This is the **only** classifier; `guard-shell.md` and `docs/specs/fast-lane.md` F2 call it, never copy the list.
  - **`hook-lib.sh` sources it fail-closed for guard hooks only**: a hook that sets `CWK_GUARD_HOOK=1` before sourcing (`protect-files.sh`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`, `tdd-require-red.sh`, `tdd-freeze-tests.sh`) gets `BLOCKED: hook-guarded.sh missing`, exit 2, when the source fails; every other hook (Stop/SubagentStop `eslint-batch.sh`, PostToolUse) warns on stderr and continues.
  - **`protect-files.sh`** gains an `ask` emitter (shape of `enforce-git-workflow.sh`'s). Write/Edit only (Read/Grep/Glob unchanged), after the existing denies: denied → deny `BLOCKED: .claude/.tdd-red/ is written only by tdd-prove-red.sh`; guarded → ask `guarded path: <rel> (kit guardrail; approve only if you meant to change it)`.
  - The deny texts of `tdd-require-red.sh` and `tdd-freeze-tests.sh` keep naming `.tdd-unfrozen`, and add "this write will ask the user".
  - `kit-doctor.py` `NON_HOOKS` gains `hook-guarded.sh`.
  - **Docs.** `docs/ADAPTATION.md`: the guarded set, and that in the kit repo itself every hook/script/settings/fixture edit now prompts, by design.
- OUT :
  - Shell write markers (`guard-shell.md`). Git rules, `settings.json`, `install.sh` (`light-permissions-git.md`).

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/hooks/{hook-guarded.sh (new),hook-lib.sh,protect-files.sh,tdd-require-red.sh,tdd-freeze-tests.sh,test-hooks.sh,kit-doctor.py}`, the five guard hooks' `CWK_GUARD_HOOK=1` line, `protect-files.sh` fixtures, `.claude/hooks/test-workflow-contracts.sh`, `docs/ADAPTATION.md`, `docs/research-cache/claude-code-permissions.md`.

## Acceptance criteria
- [ ] The spike's three verdicts are recorded, each with its control; if any is not "ask overrides", the pass stopped for the user's decision.
- [ ] A Write/Edit of any guarded path asks, given absolute, relative with a `cwd`, non-canonical (`..`, `//`, `./`), and under `.claude/worktrees/x/`; a Write of `.claude/.tdd-red/**` is denied; `src/x.ts` passes.
- [ ] With `hook-guarded.sh` missing, `protect-files.sh` blocks (exit 2) and `eslint-batch.sh` exits 0.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-workflow-contracts.sh` pass.

## Business logic to cover
No TypeScript. Hook fixtures and harness cases (`test-hooks.sh`):
- W1 `hook-guarded.sh`: `cwk_is_guarded .claude/scripts/a.sh` 0, `src/x.ts` 1, `.claude/hooks` 0, `.github` 0, `.claude` 0, `src` 1; `cwk_is_guard_denied .claude/.tdd-red/m` 0, `.claude/.tdd-red` 0; all print nothing, same result from the root and from `.claude/hooks/`; `.claude/.hook-timings.log` byte-identical before/after sourcing.
- W2 `cwk_guard_rel`: `$P/.claude/worktrees/x/.claude/hooks/a.sh` → `.claude/hooks/a.sh`; `$P/src/../vite.config.ts` → `vite.config.ts`; `$P/./package.json` → `package.json`; `../package.json` with base `$P/src` → `package.json`; a symlinked alias of `$P` + `/vite.config.ts` → `vite.config.ts`; `$P/../y` → nothing, exit 1.
- W3 Write on each of `.claude/hooks/a.sh`, `.claude/hooks/fixtures/x.json`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.ts`, `eslint.config.js`, `vite.config.ts`, `package.json`, `tsconfig.json`, `tsconfig.app.json`, `.github/workflows/ci.yml`, `.claude/scripts/a.sh` (absolute): ask each. `.claude/hooks/a.sh` and `vite.config.ts` under `.claude/worktrees/x/`: ask. `src/../vite.config.ts` (absolute): ask. Relative `package.json` with `cwd` `__PROJECT_ROOT__`: ask. Edit on `.claude/settings.json`: ask.
- W4 Write on `.claude/.tdd-red/m`, absolute and under `.claude/worktrees/x/`: deny.
- W5 Write on `src/x.ts`, `docs/x.md`: pass. Read on `.claude/settings.json`: pass. Existing `protect-files.sh` fixtures keep their verdicts.
- W6 `hook-guarded.sh` renamed in a scratch kit copy: `protect-files.sh` on any Write exits 2 with `BLOCKED: hook-guarded.sh missing`; `eslint-batch.sh` exits 0.
- W7 `test-workflow-contracts.sh`: the `tdd-require-red.sh` and `tdd-freeze-tests.sh` deny texts hold "this write will ask the user"; `docs/ADAPTATION.md` names the kit-development prompts.
