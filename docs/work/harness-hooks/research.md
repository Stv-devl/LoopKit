# Research: Harness hooks, the holes still open   (entry: docs/specs/harness-hooks.md)
Token profile: critical

H = `.claude/hooks`. All replays fed JSON on stdin to the hook, nothing was executed. Scratch: `/tmp/claude-1000/-home-stevan-Travail-Projetperso-LoopKit/7fb1ac49-c5be-4621-8713-5152cc09e76d/scratchpad/`.

## Pattern to follow
- Resolver rows: `H/shell_targets.py` prints `verb<TAB>target` then `#end<TAB>N`; `H/prevent-destructive-commands.sh:430-456` (`guard_classify`) judges them. `output_rows` (`shell_targets.py:541-548`) is the model for a generic flag row, `rm-r` the label that yields the recursive asks (`prevent-destructive-commands.sh:448-455`).
- Git rows: `H/enforce-git-workflow.sh:501` builds a six-column row in the python heredoc (`:159-686`, `python3 -I`), bash reads it at `:804` and `:845`.
- `add_verdict` + `dry_run` (`enforce-git-workflow.sh:412-437`, `:377-410`) is the model for the `git diff --quiet` step: it lives in python, because `readable_git_dir` (`:362-374`) is not callable from bash.
- Install hold-back: `install.sh:222-236` (`guard_api_missing`), `:267-274`, `:294-297`.

## Wiring points
- `H/hook-guarded.sh:2` api line, `:20-33` `CWK_GUARDED`, `:37-39` `CWK_GUARD_DENIED`, `:126-155` `cwk_guard_rel`. Consumers: `prevent-destructive-commands.sh:445-452,475`; `protect-files.sh:175-186`; `hook-lib.sh:60-68`; `install.sh:206-233`; `kit-doctor.py:753`; `test-hooks.sh:364-530`; `test-workflow-contracts.sh:440`.
- `H/hook-lib.sh:252-262`: `CWK_TDD_SHELL_TARGET_RE`, `CWK_TDD_SHELL_FROZEN_TEST_RE`. Already in scope in the git hook through `:62`, never referenced there.
- `install.sh:206-207` `GUARD_FILES`, `:208-209` `P1_ALLOWS`, `:292` `$new * $old`, `:293` allow union.
- `.claude/settings.json:19-23` git allows, `:24-35` pnpm bare and wildcard pairs, `:55,108,124` `onFailure: block`.
- Fixtures: `H/fixtures/<hook-file>/NN-<slug>-<pass|deny|ask|allow>.json` swept at `test-hooks.sh:250-268`; `_harness/shell-guard.jsonl` (158 rows, `:529-573`); `_harness/git-guard.jsonl` (272 rows, `:575`). `run_case` `:101`, setup branches `:111-215`.

## Reusable
- `readable_git_dir`, `DRY_RUN_BUDGET`, the shared deadline and the Popen/timeout block (`enforce-git-workflow.sh:362-374,383-385,387-405`), and the `other_globals` / `git_env` / `dir_unread` tests (`:431-433`).
- `CWK_TDD_SHELL_TARGET_RE`, `CWK_TDD_SHELL_FROZEN_TEST_RE`.
- The whole-folder formatter check (`prevent-destructive-commands.sh:511-552`): extended, per the spec.
- Already guarded, no change needed: `tsconfig*.json`, `vitest.config.*`, `vite.config.*` (`hook-guarded.sh:27-31`). `playwright.config.*` is absent.
- `strip_prefixes` (`shell_targets.py:505-538`) for `env`, `command`, absolute paths and `\x`.

## Blast radius
Citation drift in the spec, otherwise accurate:
- `install.sh:267-275` → `:267-274`; `ADAPTATION.md:474,484` → `:471,497,505,510,514-515`; `tdd-require-red.sh:189-193` → `:185-194`, `:230-237` → `:223-235`.

Replays against "Today":
- A2: all 16 replayed verdicts match. Not replayed: `git -c clean.requireForce=false clean -dx`, `restore '*.ts'`, `restore ':!README.md'`.
- A3, A4, A5, A6: all match, except `sed -n --expr='1e id' f.txt`, which already asks by accident ("shell guard unavailable"): `--expr` is unrecognised, `f.txt` is read as the script, `sed_writes` raises (`shell_targets.py:709-710`). `sed -n --expr=1p f.txt` gets the same misleading ask.
- A0: `$new * $old` confirmed with jq 1.7, vacuous today (no kit `deny`). The `kit-doctor.py:354-407` claim holds.
- A1: only writer `tdd-prove-red.sh:344-356`, always emits `sha256:` (`:161` for `unavailable`). A census of 222 real markers found none without the line, so the deny breaks no marker.
- A7: relative `notes.md`, `//`, `/./`, symlink: auto-approved, matches. By code only (the shell guard refused the replay): Read `.credentials.json` no decision, `git add .credentials.json` pass, `cat .credentials.json` deny, empty marker and `missing:bonus` pass.

Frozen rows that move:
- `X22.10` `rm -rf /tmp/x` pass → ask, required by A4 "elsewhere outside the project". Only frozen pass row in `shell-guard.jsonl` with a plain outside row (measured with `rows.py`). `X9.09` `rm /tmp/x-*` resolves to a `?glob:` row; whether it flips depends on how the plan treats globs outside the project.
- `G13.23` deny `git st src/x.ts` (stalias) must still deny on the expanded `stage`. `G8.06` ask `git ci -m x --amend` must keep its ask. `G2.02`, `G2.06`, `G14.70` keep their reasons.
- No frozen row covers clean, reset, restore, stash, update-ref, fetch, pull, clone, ls-remote. No `.git` target row in `shell-guard.jsonl`.
- `test-workflow-contracts.sh:484-488` is the real K1b: `P1_KIT` stays exactly the five git allows, so the pnpm list must be separate.
- `test-workflow-contracts.sh` (K1) greps the hold-back message, and `ADAPTATION.md:510` copies it: a reworded message moves both.

"Frozen" on fixtures is a convention: `tdd-freeze-tests.sh` covers only test files. The real protection is the guarded-path ask on `.claude/hooks/*`, so every hook and fixture edit prompts the user.

Baseline: all eight suites green on a copy. `test-hooks.sh` 800 cases under `setsid`, `test-small-lane.sh` 92 cases. Under the agent's own shell, `test-hooks.sh:418-425` shows one failure, because ignored job-control signals are inherited and `trap -p` prints them.

## Live DB state
n/a

## External surface
- `[fetched]` `Read(...)` deny uses gitignore patterns; `Read(.env)` equals `Read(**/.env)`. An allow cannot carve an exception; a later `Read(!x)` in the same deny list can, not across settings sources, not for `/`, `~/`, `//` anchored rules. Cache: `docs/research-cache/claude-code-permissions.md` sections 7-10.
- `[fetched]` Read deny binds built-in tools, recognised Bash file commands (`cat`, `head`, `tail`, `sed`, `tee`) and redirections. It does not bind `grep -r pattern .` or interpreter subprocesses.
- `[fetched]` Sandbox: `sandbox.enabled`, `sandbox.filesystem.{denyRead,allowRead,denyWrite,allowWrite}`, `excludedCommands`, `autoAllowBashIfSandboxed` (default true). Needs bubblewrap and socat. Read/Edit deny rules merge into the sandbox config. Hooks and file tools run outside it.
- `[measured 2026-11-01]` `bwrap --ro-bind / / true` exits 0 on this machine; `bwrap` and `socat` are installed.
- `[cache 2026-10-28]` Built-in read-only set includes grep, cat, head, tail, find (`claude-code-permissions.md:40`). A hook ask overrides an allow rule and `acceptEdits` (`:48-57`).

DA1's own condition is met: a Read deny binds some Bash, and the sandbox is available here.

## Traps (points of vigilance for the review)
- **`2>/dev/null` yields a write row outside the project** (`>` `/dev/null`, measured). A literal "write row outside → ask" makes every such call ask, including gate commands. No frozen row caught this because the row filter is new.
- `curl -o /tmp/x` and `mkdir -p /tmp/x` produce no row; `curl --output /tmp/x` does. The new ask is uneven by construction.
- `guard_classify` returns early outside the project and also when `CLAUDE_PROJECT_DIR` is unset (`prevent-destructive-commands.sh:445`). The fix must not turn "unset" into a deny of everything.
- `npx`, `npm`, `yarn`, `pnpm`, `pnpm exec` are not wrappers: `pnpm exec rm -rf .git`, `npx rm -rf .git` and `pnpm exec sed -i s/a/b/ package.json` get no verdict. A3's "whichever verb produced it" does not reach them unless A4's resolution base also strips these prefixes.
- Readers emit no row (`shell_targets.py`), so A6's glob matching has no existing plug; `SECRET_RE` matches literal text and `.en*` never contains `.env`.
- `prevent-destructive-commands.sh:395` runs `python3 -B`, not `-I`: `H` stays on `sys.path[0]`. Glob expansion added there inherits that; `enforce-git-workflow.sh:160` and `tdd-freeze-tests.sh:82` use `-I`.
- `flags_column` classifies every subcommand, so `clean -fdx` gets `s:--force`, inert today. Growing the row must not make it live.
- `:885`'s `continue` skips only the merge/rebase ask at `:887-889`, so it is narrower than the spec suggests, but a rule placed after it is skipped outside a work tree.
- `effective_sub` keeps only the alias's first word (`:738`); args are dropped. A2 needs the full expansion, parsed by the same rules, and `git wa` must produce `worktree add` with its own path.
- The alias read at `:736` and `dir_protected`, `branch --show-current`, `rev-parse` run with no `readable_git_dir` guard. Not tested for fsmonitor firing; A2's `git rev-parse --show-toplevel` claim is measured by the spec only.
- `readable_git_dir`'s own 1 s timeout sits outside the 2 s budget.
- `LC_ALL=C` goes on the `grep` side of each pipe (`:749,829`; same shape at `:833,893-895`). `local LC_ALL=C` at `:947` does not reach child processes unless exported.
- A `sha256:` line with an empty value is skipped today; A1 must treat it as missing. `unavailable` is accepted today even when hashing works; A1 must check `file_digest`.
- `install.sh:215` accepts leading zeros: `[[ 08 -lt 1 ]]` errors and reads as current, so an `08` api number fails open. Bumps here stay single digit.
- `.git/*` in `CWK_GUARD_DENIED` also reaches `protect-files.sh:181`; `\.git/` near `:158` denies first, so `:182`'s RED-only text stays unreachable for it. Read-shaped tools exit at `:149-151`, before it.
- `protect-files.sh` has `set -e` and `onFailure: block`: every `cwk_real_rel` call takes the `||` form.
- `auto-approve-config.sh:70` never reads `.cwd`. `notes.md` with a `cwd` outside the project is allowed today, a case the spec does not list. Resolving against `.cwd` is a behaviour change.
- `run_case` defaults `project_dir` to the real repo, and `tdd-require-red.sh:07` writes a real marker there (`test-hooks.sh:126-131`, removed `:246`). Symlink and marker setups must set `project_dir` to `$tmp`.
- `test-kit-doctor.sh` has no gate-allowlist case: A0's proof needs a new one. `kit-doctor.py:378` is exact-string matching.
- A `git-guard` fixture repo has one commit, so `HEAD~1` does not resolve; deny verdicts must not depend on it.
- Writing tests about this: the guard text-matches its own triggers, so fixtures go through Write/Edit (guarded ask), never the shell.
- The re-audit of `readable_git_dir` never concluded: A2's `git diff` step inherits that premise. Local commit only, no push before the user's review.

## Open questions
1. **Which outside-project writes stay silent?** The spec says every write row outside the project asks. Measured, that catches `2>/dev/null`. Recommended: exempt `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/fd/*`, and decide whether `$TMPDIR`//tmp asks. Asking on `/tmp` follows the spec's `--output /tmp/x` fixture but adds prompts to agents' scratch writes.
2. **Does DA1 ship the sandbox, the deny, or both?** The spec's condition is met. Recommended: ship `permissions.deny` for secrets with the `install.sh` union, and do not enable `sandbox.enabled` by kit default, because `autoAllowBashIfSandboxed` defaults to true and removes prompts, and how it interacts with a hook `ask` is unmeasured. The sandbox is documented in `ADAPTATION.md` as the user's choice.
3. **Does `Read(!.env.example)` work as written?** Settled by one headless probe in a scratch project before the deny ships. Run at the plan step.
4. **Do `pnpm exec <writer>` and `npx <writer>` get resolved as the writer?** Not in the spec's fixtures. Recommended: yes, since A4's resolution base already has to recognise those prefixes, and A3's deny would otherwise be bypassed by a prefix.
5. **`.cwd` outside the project on a relative auto-approve path:** recommended no decision, which is the spec's "outside the project → no decision" applied to the joined path.
6. **Full suite replay with `.git/*` added on a scratch copy:** the spec requires it before EXECUTE; to be run at the plan step.
