# Plan: Guarded set, Write/Edit side   (entry: docs/specs/guard-writes.md · research: docs/work/guard-writes/research.md · design: n/a)
Token profile: standard

## Skips
- Interface : SKIP — kit hooks, no user surface.
- DB, Backend, Front app layers : SKIP — `Data model: none`, `Custom backend: NONE`, no `src/`. The TDD hooks do not key on `.claude/` shell: test-first by hand — every case below is written first and **observed failing on its own verdict** before the code it covers.

## Write chain (sequential)
0. **Spike** (open question 1) — before any code. Scratch dir `$SP/spike` (`$SP` = the session scratchpad): `git init -q`, one seed commit (`git commit --allow-empty -m seed`), git identity set with `git -c user.email=spike@loopkit.invalid -c user.name=Spike`, `.claude/settings.json` = `{"permissions":{"defaultMode":"acceptEdits","allow":["Bash(git commit -m *)"]},"hooks":{"PreToolUse":[{"matcher":"Write|Edit|Bash","hooks":[{"type":"command","command":"<absolute path of ask.sh>"}]}]}}` (the path written out, never `$SP`), `ask.sh` made executable (`chmod +x`), appends `$(jq -c .tool_input)` to `$SP/spike/hook.log` and prints the `ask` JSON. One run per case, from `$SP/spike`: `claude -p "<one exact call>" --permission-mode acceptEdits --output-format json --max-turns 2 --tools <Write|Bash>`, then the same with the hook removed from settings (control). Cases: (a) Write `vite.config.ts` content `x`; (b) Bash `git commit -m x --amend --allow-empty`; (c) Bash `sed -i 's/a/b/' vite.config.ts` (file seeded). Verdict per case: `hook.log` has the call + the call is in the JSON `permission_denials` + the control shows it ran (file/commit/edit observed) → "ask overrides". An empty `hook.log` on a hooked run means the setup is broken (fix it and rerun), not that ask lost. Anything else stops EXECUTE for the user's decision. Results → `docs/research-cache/claude-code-permissions.md` (new section "Hook ask vs acceptEdits, measured 2026-10-28") and `## Gate`.
1. **RED, all at once** (these are test files, nothing they exercise exists yet; written before any guard so writing them prompts nothing extra):
   - `test-hooks.sh`: a new `run_guarded_cases` (W1, W2, W6), called after `run_missing_jq_cases`.
   - `fixtures/protect-files.sh/06-…` to `…-ask/deny/pass.json` (W3, W4, W5).
   - `test-workflow-contracts.sh`: W7 greps.
   - Run `test-hooks.sh` and `test-workflow-contracts.sh`: each new case fails on its own verdict (W1/W2/W6 on "hook-guarded.sh missing" or the wrong exit; W3/W4 `expected ask|deny, got pass`; W7 the grep); W5 already green (regression guard). Output kept for `## Gate`.
2. **GREEN `hook-guarded.sh`** → W1, W2 green.
3. **GREEN `hook-lib.sh` source + `CWK_GUARD_HOOK=1`** in the five guard hooks → W6 green; `run_missing_jq_cases` still green.
4. **GREEN W7**: TDD deny texts (`tdd-require-red.sh:179,185,207,217,223`, `tdd-freeze-tests.sh:387,390`), `docs/ADAPTATION.md`; `kit-doctor.py` `NON_HOOKS` += `hook-guarded.sh`.
5. **GREEN `protect-files.sh`** (last: from here every Write/Edit of a guarded path in this repo asks) → W3, W4 green, W5 still green.
6. **Tests** — `test-hooks.sh`, `test-workflow-contracts.sh`, `test-kit-doctor.sh`, `test-install.sh`, `test-small-lane.sh`, `kit-doctor.py`, every `kit-ci.yml` suite.
7. **Refactor** — `protect-files.sh` `deny`/`ask` share one emitter; suite green, no case edited.

## Parallel lots (inside this track, same tree)
none — fully sequential (one runner, every hook sources `hook-lib.sh`).

## Track isolation
- Worktree: none, single track (main tree, `audit/slim`).
- Shared foundations touched: `hook-lib.sh` (sourced by every hook and `.claude/scripts/small-lib.sh`). No other loop runs beside this one.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/hook-guarded.sh` | Create | sets, `cwk_guard_rel`, `cwk_is_guarded`, `cwk_is_guard_denied` |
| `.claude/hooks/hook-lib.sh` | Edit | sources it after the timing block; fail-closed for guard hooks |
| `.claude/hooks/{protect-files,prevent-destructive-commands,enforce-git-workflow,tdd-require-red,tdd-freeze-tests}.sh` | Edit | `CWK_GUARD_HOOK=1` before `source` |
| `.claude/hooks/protect-files.sh` | Edit | `ask()`; guarded ask, `.tdd-red` deny |
| `.claude/hooks/tdd-require-red.sh`, `.claude/hooks/tdd-freeze-tests.sh` | Edit | deny texts |
| `.claude/hooks/test-hooks.sh` | Edit | `run_guarded_cases` |
| `.claude/hooks/fixtures/protect-files.sh/06-*` … | Create | W3-W5 |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | W7 |
| `.claude/hooks/kit-doctor.py` | Edit | `NON_HOOKS` |
| `docs/ADAPTATION.md` | Edit | guarded set, kit-development prompts |
| `docs/research-cache/claude-code-permissions.md` | Edit | spike result |

## Contracts
- **`hook-guarded.sh`** — sourced; defines only variables and functions: no trap, no output, no file write, no `shopt`/`set` change (patterns matched with plain `[[ $rel == $pat ]]`, where `*` crosses `/`).
  - `CWK_GUARDED=( '.claude/hooks/*' '.claude/scripts/*' '.claude/settings.json' '.claude/settings.local.json' '.claude/.tdd-unfrozen' '.claude/.size-exempt' 'vitest.config.*' 'eslint.config.*' 'vite.config.*' 'package.json' 'tsconfig*.json' '.github/workflows/*' )`; `CWK_GUARD_DENIED=( '.claude/.tdd-red/*' )`.
  - **Fixed dir** of a pattern = its text up to the first glob char, cut back to the last `/` (`.claude/hooks/*` → `.claude/hooks`; `vite.config.*` → `.`; `.claude/settings.json` → `.claude`).
  - `cwk_is_guarded <rel>`: exit 0 when `<rel>` matches a `CWK_GUARDED` pattern, or `<rel>` is `.` or a fixed dir or an ancestor of one (`.claude`, `.claude/hooks`, `.claude/scripts`, `.github`, `.github/workflows`, `.`); else 1. Resolves nothing, prints nothing.
  - `cwk_is_guard_denied <rel>`: exit 0 when `<rel>` matches `.claude/.tdd-red/*` or equals `.claude/.tdd-red`; else 1. (Ancestors `.claude` and `.` are not denied: they are guarded → ask. Gate question 2.)
  - `cwk_guard_rel <path> [<base>]`: empty `<path>` → exit 1. Relative → `<base>/<path>` (`<base>` empty → `$CLAUDE_PROJECT_DIR`). Then lexical normalisation (collapse `//`, drop `.` segments, `..` pops one segment; popping above `/` stays `/`). Then, with `P=$CLAUDE_PROJECT_DIR` normalised and `PP=$(cd -P "$P" && pwd -P)`: strip `P/` or `PP/` (equal to `P` or `PP` → `.`); else take the deepest existing parent `D` of the path, `DR=$(cd -P "$D" && pwd -P)`, and if `DR` is `PP` or under it, rebuild `DR` + the non-existing remainder and strip `PP/`; else exit 1, nothing printed. Then strip a leading `.claude/worktrees/<x>/` (or `.claude/worktrees/<x>` → `.`). Print the result, exit 0. Uses no `$PWD`, no `realpath` (macOS-portable).
- **`hook-lib.sh`**, after the timing block: `source "$(dirname "${BASH_SOURCE[0]}")/hook-guarded.sh" 2>/dev/null || { if [[ "${CWK_GUARD_HOOK:-0}" == 1 ]]; then echo "BLOCKED: hook-guarded.sh missing — the guarded-path list of this kit is gone, so this guard refuses rather than passes. Restore .claude/hooks/hook-guarded.sh." >&2; exit 2; else echo "WARNING: hook-guarded.sh missing (.claude/hooks/)" >&2; fi; }`.
- **`protect-files.sh`**, after the write list (Read/Grep/Glob already exited): `REL=$(cwk_guard_rel "$FILE_PATH" "$(jq -r '.cwd // empty' <<<"$INPUT")") || exit 0` (outside the project → pass; never a bare assignment under `set -e`); `cwk_is_guard_denied "$REL"` → deny `BLOCKED: .claude/.tdd-red/ is written only by tdd-prove-red.sh — a hand-written RED marker lets a module in with no observed failing test.`; `cwk_is_guarded "$REL"` → ask `guarded path: <REL> (kit guardrail; approve only if you meant to change it)`.
- **TDD deny texts**: each sentence naming `.tdd-unfrozen` gains ` (this write will ask the user)` right after the file name.

## Test plan (gate — validated by the user before EXECUTE)

Fixtures in `.claude/hooks/fixtures/protect-files.sh/`, absolute paths as `__PROJECT_ROOT__/…` unless named; harness cases in `test-hooks.sh` `run_guarded_cases`. Each RED observed before its GREEN.

### Test-first — harness (`test-hooks.sh`)
- [ ] W1 `cwk_is_guarded`: `.claude/scripts/a.sh`, `.claude/hooks`, `.github`, `.claude`, `.`, `package.json`, `tsconfig.app.json` → 0; `src/x.ts`, `src`, `docs/x.md`, `apps/web/package.json` → 1. `cwk_is_guard_denied`: `.claude/.tdd-red/m`, `.claude/.tdd-red` → 0; `.claude`, `.claude/hooks/a.sh` → 1. Each prints nothing; the same results from a subshell `cd`'d to `.claude/hooks/`. Sourcing **`hook-guarded.sh` alone** in `bash -c`, with `CLAUDE_PROJECT_DIR` = a scratch root holding a seeded `.claude/.hook-timings.log`, leaves that log byte-identical (sha256 before/after), prints nothing, leaves `trap -p` empty and `shopt extglob` unchanged.
- [ ] W2 `cwk_guard_rel` (`CLAUDE_PROJECT_DIR=$P`): `$P/.claude/worktrees/x/.claude/hooks/a.sh` → `.claude/hooks/a.sh`; `$P/src/../vite.config.ts` → `vite.config.ts`; `$P//package.json` → `package.json`; `$P/./package.json` → `package.json`; `../package.json` base `$P/src` → `package.json`; `package.json` with no base → `package.json`; `$ALIAS/vite.config.ts` where `$ALIAS` is a symlink to `$P` → `vite.config.ts`; `$P/vite.config.ts` with `CLAUDE_PROJECT_DIR=$ALIAS` → `vite.config.ts`; `$P/../y` → nothing, exit 1; `/etc/passwd` → nothing, exit 1.
- [ ] W6 in a scratch copy of `.claude/hooks/` without `hook-guarded.sh`, looping like `run_missing_jq_cases` (`test-hooks.sh:259-271`): each of `protect-files.sh`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`, `tdd-require-red.sh`, `tdd-freeze-tests.sh`, fed `{}`, exits 2 with stderr `BLOCKED: hook-guarded.sh missing`; `eslint-batch.sh` (`CLAUDE_PROJECT_DIR` = an empty scratch root) exits 0 with stderr `WARNING: hook-guarded.sh missing`.

### Test-first — `protect-files.sh` fixtures
- [ ] W3 ask each (Write): `.claude/hooks/a.sh`, `.claude/hooks/fixtures/x.json`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.ts`, `eslint.config.js`, `vite.config.ts`, `package.json`, `tsconfig.json`, `tsconfig.app.json`, `.github/workflows/ci.yml`, `.claude/scripts/a.sh`; `.claude/worktrees/x/.claude/hooks/a.sh`; `.claude/worktrees/x/vite.config.ts`; `src/../vite.config.ts`; relative `package.json` with `"cwd":"__PROJECT_ROOT__"`; relative `../vite.config.ts` with `"cwd":"__PROJECT_ROOT__/src"`. Edit on `.claude/settings.json`: ask. One ask fixture carries `_expect_reason: "guarded path: package.json"`.
- [ ] W4 deny each (Write): `.claude/.tdd-red/m`, `.claude/worktrees/x/.claude/.tdd-red/m`; one carries `_expect_reason: "written only by tdd-prove-red.sh"`.
- [ ] W5 pass each: Write `src/x.ts`, Write `docs/x.md`, Write `apps/web/package.json`, Write `__FIXTURE_ROOT__/package.json` (outside the project), Read `.claude/settings.json`; fixtures `01`-`05` keep their verdicts.

### Test-after — contracts (`test-workflow-contracts.sh`)
- [ ] W7 every `.tdd-unfrozen` deny sentence of `tdd-require-red.sh` (5) and `tdd-freeze-tests.sh` (2) holds `this write will ask the user` (count = 7); `docs/ADAPTATION.md` (French) has a section `## 14. Chemins gardés` holding the literal strings `hook-guarded.sh`, `.claude/.tdd-red/`, `vite.config.*`, `package.json`, and the sentence fragment `dans le dépôt du kit, chaque écriture d'un hook, d'un script ou des settings demande ton accord`.

### Review reproduction cases (added 2026-10-28, `/loop:review` fix batch)
- [ ] W8 (Reproduction, Major 1) in a scratch copy of `.claude/hooks/`, `hook-guarded.sh` emptied, then separately `CWK_GUARDED=()` appended: each of the five guard hooks exits 2 with stderr `hook-guarded.sh missing or broken`.
- [ ] W9 (Reproduction, shadow Major 3) scratch copy with `hook-lib.sh` stripped of its hook-guarded block + current `protect-files.sh`: Write `$P/package.json` and Write `$P/.claude/.tdd-red/x` deny.
- [ ] W10 (Reproduction, Major 2) `cwk_guard_rel "$P/x\n/../package.json"` → `package.json`; `"$P/a\n/../.claude/.tdd-red/m"` → `.claude/.tdd-red/m`; fixtures `33-w8-newline-escape-ask.json` (ask) and `34-w8-newline-tdd-red-deny.json` (deny).
- [ ] W11 (regression guards, Minors) `cwk_is_guarded .git` → 1, `cwk_is_guarded .claude/hook` → 1; full `shopt -p; set +o` identical before/after sourcing `hook-guarded.sh`.
- [ ] W12 (Reproduction, shadow Major 4 + Minor, contracts) orchestrate Phase 4 and `audit/mutation.md` hold `the \`.tdd-unfrozen\` write asks the user`; "Correcting one never stops EXECUTE — it may run unattended" is gone; ADAPTATION §14 names `.claude/settings.json` and `.claude/settings.local.json`, not `settings*.json`.

## Vigilance (carried from research)
- `hook-guarded.sh` has no side effect: no trap, log, output, `shopt`/`set` (W1).
- `cwk_is_guarded` resolves nothing; only `cwk_guard_rel` resolves, never against `$PWD` (W1 from `.claude/hooks/`, W2 no-base case).
- Normalisation on both branches (W2 `..`, `//`, `./`); symlink alias both ways (W2).
- `.claude/worktrees/<x>/` stripped after the project prefix (W2, W3, W4).
- Folders above a guarded pattern are guarded (W1).
- Fail-closed only with `CWK_GUARD_HOOK=1`; Stop hook exits 0 (W6); `run_missing_jq_cases` stays green.
- `jq -r '.cwd // empty'` (W3 relative cases).
- Ask after existing denies; Read/Grep/Glob unchanged (W5).
- `protect-files.sh` lands last (step 5).
- Lock-out: once step 3 lands, a broken `hook-guarded.sh` makes the five guard hooks exit 2 on every Write/Edit/Bash, the repair included. Every edit of it is checked with `bash -n` and W1/W2 by sourcing it in a subshell before any hook loads it; if it breaks anyway, the user restores it from a terminal: `git checkout -- .claude/hooks/hook-guarded.sh` (or deletes the untracked file and re-saves the last good copy).

## Acceptance criteria (carried from the entry artifact)
- [ ] The spike's three verdicts are recorded, each with its control; if any is not "ask overrides", the pass stopped for the user's decision.
- [ ] A Write/Edit of any guarded path asks, given absolute, relative with a `cwd`, non-canonical (`..`, `//`, `./`), and under `.claude/worktrees/x/`; a Write of `.claude/.tdd-red/**` is denied; `src/x.ts` passes.
- [ ] With `hook-guarded.sh` missing, `protect-files.sh` blocks (exit 2) and `eslint-batch.sh` exits 0.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-workflow-contracts.sh` pass.

### Proof map
| AC | Proof |
| --- | --- |
| 1 | step 0, `## Gate` + research cache |
| 2 | W2, W3, W4, W5 |
| 3 | W6 |
| 4 | step 6 |

## Open questions for the gate
1. Spike → run first (step 0); any case other than "ask overrides" stops EXECUTE for your decision.
2. Spec says folders above `.claude/.tdd-red` are **denied**; that would deny `.claude` and `.` themselves (e.g. a later `find .claude -exec …`). Proposed: only `.claude/.tdd-red` and below deny; `.claude` and `.` stay guarded → **ask** (W1). Contract amendment, one line.
3. Routing → EXECUTE inline on Claude (`--inline-execute`), as on small-lane.

## Plan critic
- completeness: 94
- quality: 90
- surviving blockers: none
- Minor kept as a writing rule for W7's section: the denied set is written `.claude/.tdd-red/` (no wildcard), and any other `.claude/` pattern named there must match a shipped file (`kit-doctor.py:851-862` `check_shipped_paths`).

## Gate
- 2026-10-28 go
- Contract: amended: only `.claude/.tdd-red` and below are denied; `.claude` and `.` stay guarded (ask). Spec line edited. No re-entry at Phase 1: `research.md` never relied on the denied ancestors, and this plan, already scored by plan-critic, carried the amended line as open question 2.
- 1. Spike → run first; any case other than "ask overrides" stops EXECUTE for the user.
- 2. Denied ancestors → amended as above (W1).
- 3. Routing → EXECUTE inline on Claude.
- Spike 2026-10-28 (AC 1): (a) Write, (b) allow-rule commit incl. `--amend`, (c) `sed -i` — hook ran, call in `permission_denials`, control executed: **ask overrides** in all three. Case (b) needed `--allowedTools` for the allow rule: the project-settings allow is not applied in `-p` (cached in `docs/research-cache/claude-code-permissions.md`).
- amended 2026-10-28 W1 (side-effects case): `bash -c '…; trap -p; shopt -p extglob'` → `bash -c '…; trap -p; shopt -p extglob || true'`. Reason: `shopt -p` exits 1 when the option is off, so the case failed on any module; the assertions (exit 0, output `shopt -u extglob`, log sha256 unchanged) are unchanged.
