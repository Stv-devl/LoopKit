# Research: Guarded set, Write/Edit side   (entry: docs/specs/guard-writes.md)
Token profile: standard

Reuses `docs/work/light-permissions/research.md` (external facts, overlap with harness-hardening) and the plan-critic findings in `docs/work/light-permissions/plan.md`; only what this pass touches is re-read here.

## Pattern to follow
- **Ask emitter**: `enforce-git-workflow.sh:52-66` (`decide`/`deny`/`ask` via `jq -n`); `protect-files.sh:75-86` has the same `deny` shape (jq-built, `\n` expanded) — `ask` is its twin with `permissionDecision: "ask"`.
- **Fixtures**: `test-hooks.sh:179-197` sweeps `fixtures/<hook>/*-{pass,deny,ask,allow}.json`; `semantic_verdict` (`:17-41`) already reads `ask`. Placeholders `:88`. Hooks run with `CLAUDE_PROJECT_DIR=$PROJECT_ROOT` (`:150`), the real repo — so `__PROJECT_ROOT__/…` paths are inside the project, `__FIXTURE_ROOT__/…` ones are outside. Top-level `"cwd"` already used by git fixtures (`fixtures/enforce-git-workflow.sh/08-*`).
- **Harness cases** (non-fixture): `run_missing_jq_cases` `:253-274` and `run_harness_edges` `:221-251` — scratch dir, `set +e`, `CASES++`, `fail <hook> <name> <msg>`; called at `:295-305`.
- **`_expect_reason`** on a fixture checks a substring of the reason (`:62-79`).

## Wiring points
- `hook-lib.sh:1-47`: timing trap installed at source time unless `CWK_HOOK_TIMING=0`; the new `source hook-guarded.sh` line goes **after** the timing block, before `cwk_require_jq` (`:62`).
- Who sources hook-lib: the five guard hooks (`protect-files.sh:36`, `prevent-destructive-commands.sh:9`, `enforce-git-workflow.sh:31`, `tdd-require-red.sh:42`, `tdd-freeze-tests.sh:39`), plus `eslint-batch.sh` (Stop/SubagentStop, `settings.json:140-157`), `format-on-save.sh`, `eslint-check.sh`, `no-any-type.sh`, `no-forbidden-icons.sh`, `auto-approve-config.sh`, `tdd-prove-red.sh`, `hook-timings-report.sh`, `test-hooks.sh`, `test-small-lane.sh`, `.claude/scripts/small-lib.sh:8`. Each guard hook sets `CWK_GUARD_HOOK=1` on the line before its `source`.
- `protect-files.sh`: TOOL_NAME/FILE_PATH `:51-52`; secrets deny `:104-135`; Read/Grep/Glob exit `:145-147`; write list `:149-162`; **guarded block after `:162`**, before `exit 0`.
- TDD deny texts: `tdd-require-red.sh:179,185,207,217,223`; `tdd-freeze-tests.sh:387,390`.
- `kit-doctor.py:752-757` `NON_HOOKS` (else `check_hook_wiring` `:828` flags `hook-guarded.sh` as mute).
- `test-workflow-contracts.sh`: grep cases (W7) append before its success echo.

## Reusable
- `protect-files.sh` `deny()` → copy as `ask()`.
- `realpath` exists here (`/usr/bin/realpath`); portable fallback for macOS: `cd -P "$dir" && pwd -P` on the deepest existing parent.

## Blast radius
- Existing protect-files fixtures `01-05` use `__FIXTURE_ROOT__` (outside the project) → unaffected.
- TDD fixtures write under `$tmp` (outside) → unaffected. `test-hooks.sh` itself writes `.claude/.tdd-red/` from the shell (`:106-115`), never through Write: not a PreToolUse event.
- After `protect-files.sh` gains the ask, **every Write/Edit of `.claude/hooks/**`, `.claude/scripts/**`, settings, `package.json` in this repo prompts**, this session included.
- `small-lib.sh` sources hook-lib with `CWK_HOOK_TIMING=0`: the new source must stay side-effect free (W1).

## Live DB state
n/a.

## External surface
- Hook input carries a top-level `cwd` (session cwd). [cached, `docs/research-cache/claude-code-permissions.md`]
- Hook `ask` vs `acceptEdits`: undocumented → the spec's spike. Only exit 2 blocks; 127/crash fail open. [cached]

## Traps (points of vigilance for the review)
- `hook-guarded.sh` must not install a trap, write a log, print, or set `shopt` globally (W1 checks the timing log byte-identical).
- `cwk_is_guarded` takes a repo-relative path and resolves nothing; resolution lives only in `cwk_guard_rel`, never on `$PWD`.
- Normalisation on **both** branches (absolute paths with `..`, `//`, `./`).
- Worktree prefix `.claude/worktrees/<x>/` stripped after the project prefix — `acceptEdits` does not prompt there.
- Folders above a guarded pattern count (`.claude`, `.github`, `.`), folders above `.tdd-red` deny.
- Fail-closed source only for hooks that set `CWK_GUARD_HOOK=1`; `eslint-batch.sh` on Stop must never exit 2 (it would loop the session).
- `jq -r '.cwd // empty'` (without `-r`, quotes break every relative path).
- The ask comes **after** the existing denies; Read/Grep/Glob never reach it.
- Order of EXECUTE: the `protect-files.sh` change lands last, so the other kit edits don't each prompt.

## Open questions
1. **Spike** (spec's first IN item): run before any code, three cases + controls; any case not "ask overrides" stops the pass.
