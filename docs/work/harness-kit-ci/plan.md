# Plan: Kit CI, GitHub settings, hook failure mode   (entry: docs/specs/harness-kit-ci.md · research: docs/work/harness-kit-ci/research.md · design: n/a)
Token profile: standard

## Skips
- INTERFACE: SKIP — no user surface (hooks, CI, install, doctor).
- DB / backend / front layers: SKIP — kit repo, no `src/`, no `package.json`; no `utils/mapper/repository` file, so no TS test-first leg. The proof files are the kit's shell suites and JSONL fixtures, written first and observed failing before each change (same discipline as `harness-prompts`).
- Deploy: SKIP — nothing deployed; K2's "green on a PR" waits for a push (see Q5).

## Write chain (sequential)
Order K2.0 → K1 → K5 → K3 → K4 → K2 (spec order: K1/K3/K4/K5 free, K2 after DC1, which is cached). Each item: RED rows/cases first, run, observe the expected failure, then the change, then the suite green.

0. **K2.0 SIGPIPE strictness (reproduction first).** `test-hooks.sh` side-effects case `:702-708` (W1). Step a (pure refactor, no verdict change): move W1's check into one shell function `guarded_side_effects <hook-path>` defined once in `test-hooks.sh` (it runs the `bash -c 'source …'` and the `$out`/exit/log comparison, returns 0/1 and prints its failure text on stdout, captured by callers: `msg="$( (trap '' PIPE; guarded_side_effects …) )" || fail … "$msg"`); W1 calls it unchanged in a plain shell. Step b RED: T1 calls the same function from `( trap '' PIPE; guarded_side_effects "$HOOKS_DIR/hook-guarded.sh" )` → observed failing on `trap -- '' SIGPIPE`; T2 calls it on a scratch copy of `hook-guarded.sh` with `trap 'true' EXIT` appended and expects failure (green today, must stay green). Step c GREEN: only the function body changes — inside the one `bash -c`, `b="$(trap -p)"` before `source`, `a="$(trap -p)"` after, print `trap-changed` when `a != b`, then `shopt -p extglob`; the expected `$out` stays `shopt -u extglob`. Amended frozen case (`## Gate` line, user confirms at merge): W1's body becomes the function call (title unchanged).
1. **K1 fail closed.** RED: `K1g` in `test-workflow-contracts.sh` after K1f (`:535`), pure insertion. GREEN: `"onFailure": "block"` on `.claude/settings.json` `:110` and `:115`. Then text: `docs/research-cache/claude-code-permissions.md:35` rewritten with the spec's sentence: under `onFailure: block`, a past-timeout hook, `exit 1` and a missing script block; silent `exit 0` and non-JSON stdout with `exit 0` do not block (measured 2.1.316, stub, n=1, `docs/work/git-allow-grammar/plan.md:194`); `docs/ADAPTATION.md` one French line after `:467-469` (measured on 2.1.316; an older version is assumed to ignore the key, not tested). Then the measure: `enforce-git-workflow.sh` wall time (Q1a), recorded in `## Gate`; median > 1 s → `DRY_RUN_BUDGET` revisit is a new decision for the user, not done silently.
2. **K5 attribution via gh.** RED: git-guard rows `G18.01+` + one commit row for the session link. Fixture setup `ghbody` (new branch in `test-hooks.sh` `run_case`, keyed on `*-ghbody-*` like the other setups `:421-494`): sets `project_dir="$tmp"` (instead of the kit root `:116`), writes the body files under `$tmp/.feat/docs/` (the case cwd `__FEAT_TREE__`), writes `$tmp/docs/pr-only-root.md` clean while `$tmp/.feat/docs/pr-only-root.md` carries the trailer (pins cwd-relative resolution), and writes `$(dirname "$fixture")/outside-trailer.md` carrying the trailer (`$fixture` is `run_case`'s 2nd argument, `:115`, so this is the `run_git_guard_cases` scratch dir `:888`, a separate `mktemp -d` outside the project `$tmp` `:118`, removed by `rm -r` at `test-hooks.sh:919`, so nothing leaks) and makes `$tmp/.feat/docs/pr-out.md` a symlink to it: a hook that follows the link out of the project reads the trailer and denies, so the link-out ask row fails without the containment check. GREEN in `enforce-git-workflow.sh`: one `ATTRIBUTION_RE` near the commit check (`:1313-1319`), used by the commit check and by a new gh check placed **next to the commit attribution check, before `floor_subs`** (`:1355`) and before the asks `:1380-1389`; body-file reader per the contract below. `gh pr review` joins the ask at `:1388` (Q7). `.claude/agents/github.md:30-34` and `ADAPTATION.md:324-330` say gh bodies are refused too.
3. **K3 repo settings.** RED: contract cases `K3a-c` (`test-workflow-contracts.sh`), install cases `I5a-b` (`test-install.sh`), doctor cases `KD1-8` (`test-kit-doctor.sh`, gh shim). First, in the same RED batch: `test-kit-doctor.sh` exports `CWK_DOCTOR_OFFLINE=1` at its top so every existing doctor run stays offline (`:5` runs on the kit source, whose remote is GitHub); KD1-7 unset it with a shim on PATH. GREEN: `templates/github/CODEOWNERS`; `install.sh` copies it to `.github/CODEOWNERS` next to `:678` (inside the `else` of `if $NO_CI`); `ci.md` section "Repository settings" before `:235`; `ADAPTATION.md` §4 bis line on the kit's own `kit` check; `kit-doctor.py` `check_github_protection` + status `INFO` (Q6).
4. **K4 lefthook.** RED: `I6a-e` in `test-install.sh`. GREEN: `templates/lefthook.yml`; `install.sh` `--lefthook` option (parsing `:36-45`); the question sits after the CD block (`:594-640`) and before the copy of `.claude/`, default no, EOF guarded; non-terminal → not installed, no question; usage/help text; `ADAPTATION.md` one line.
5. **K2 kit CI.** Baseline first (scratch only, never in the repo): install shellcheck v0.11.0 and actionlint v1.7.12 from the pinned tarballs (sha256 checked) and ruff 0.17.4 (`uv tool run ruff@0.17.4`) into the session scratchpad; run each new step locally with the exact CI scope, record the finding counts in `## Gate`. Non-zero → fixes in this pass (behaviour-neutral, suites green after) or an explicit ignore with reason (`# shellcheck disable=SCxxxx  # reason` on the line, or a listed `--exclude`), each listed in `## Gate`. A finding inside a frozen case body of a test suite is never edited silently: inline `# shellcheck disable=… # reason` above it, or an amendment line in `## Gate`. A hook-behaviour change found by a linter is a new user decision. RED: contract cases `K2a-d`. GREEN: `kit-ci.yml` rewrite. Then the CI rehearsal (recorded, Q5): a fresh `git clone` of the working tree into scratch, every `kit-ci.yml` `run:` step executed in order inside `( trap '' PIPE; … )`, all green.
6. **Refactor**: none planned beyond the K5 shared regex; no behaviour change, suites green.

## Parallel lots
none — fully sequential (K3, K4 both edit `install.sh` and `test-install.sh`; K1, K3, K4, K5 all touch `ADAPTATION.md` or `test-workflow-contracts.sh`).

## Track isolation
- Worktree: none, single track (main tree, `audit/slim`, base `576f8ef`).
- Shared foundations touched: `.claude/settings.json` (hook wiring), `install.sh`, guard hook `enforce-git-workflow.sh`. No other pass runs beside this one.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/test-hooks.sh` | Edit | K2.0 side-effects case + repro/guard cases; K5 `ghbody` setup |
| `.claude/hooks/fixtures/_harness/git-guard.jsonl` | Edit (append) | K5 rows G18.01+ |
| `.claude/hooks/test-workflow-contracts.sh` | Edit (append cases) | K1g, K2a-d, K3a-c |
| `.claude/hooks/test-install.sh` | Edit (append cases) | I5a-b, I6a-e, suite setup `exec </dev/null` + `CWK_DOCTOR_OFFLINE=1` |
| `.claude/hooks/test-kit-doctor.sh` | Edit (append cases) | KD1-8, `CWK_DOCTOR_OFFLINE=1` at top, gh shim |
| `.claude/settings.json` | Edit | K1 `onFailure` on the two tdd handlers |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | K5 shared `ATTRIBUTION_RE`, gh deny, `gh pr review` ask |
| `.claude/hooks/kit-doctor.py` | Edit | K3 `INFO` status + `check_github_protection` |
| `.claude/commands/kit/doctor.md` | Edit | K3 one sentence under Wiring (`:120`): `github-protection` is `INFO`, never failing, fix in `ci.md` "Repository settings" |
| `install.sh` | Edit | K3 CODEOWNERS copy; K4 `--lefthook` |
| `templates/github/CODEOWNERS` | Create | K3 template |
| `templates/lefthook.yml` | Create | K4 template |
| `.github/workflows/kit-ci.yml` | Edit | K2 |
| `.claude/skills/templates/ci.md` | Edit | K3 "Repository settings" |
| `.claude/agents/github.md` | Edit | K5 one line |
| `docs/ADAPTATION.md` | Edit | K1, K3 (`kit` check), K4, K5 lines (French) |
| `docs/research-cache/claude-code-permissions.md` | Edit | K1 `:35` correction |
| `docs/research-cache/ci-lint-tools.md` | Edit | pins actually used |
| `docs/specs/harness-hardening.md` | Edit | follow-ups (addon python TDD `onFailure`, K2 PR run, gh bodies outside K5's scope: `gh pr merge -b`, `gh release create --notes/--notes-file`, `--body "$(cat f)"`; `install.sh:602` remote `read` EOF) |
| `docs/specs/harness-kit-ci.md` | Edit | citation refresh (K1f `:529-535`, side-effects `:702-708`, cache `:35`) |
| shell/python files flagged by the baseline | Edit | K2 behaviour-neutral fixes, listed in `## Gate` |

## Contracts
- **K1**: every `.hooks.PreToolUse[].hooks[]` whose command ends with `tdd-require-red.sh` or `tdd-freeze-tests.sh` has `onFailure == "block"`; exactly 2 such handlers; K1f untouched.
- **K5**, `enforce-git-workflow.sh`:
  - `ATTRIBUTION_RE` (one definition, case-insensitive): `Co-Authored-By|Generated with .*Claude|🤖|Claude-Session|claude\.ai/code`. Used by the commit deny (`:1317`, unchanged message) and the gh deny.
  - Scope of the gh deny: a segment whose verb words are `gh pr create|edit|comment|review`, `gh issue create|edit|comment`, or `gh api` with a write marker (`-X`/`--method` other than GET, `-f`/`-F`/`--field`/`--raw-field`, `--input`).
  - Inline: the command text matches `ATTRIBUTION_RE` → deny (same whole-text test as the commit check; covers `--body`, `-b`, `--title`, `-t`, `-f body=`).
  - File: `--body-file <p>`/`--body-file=<p>`, `-F <p>` on pr/issue (= body file), `-F <k>=@<p>`/`--field <k>=@<p>` and `--input <p>` on api. `-` or empty → ask. A relative `<p>` resolves against the hook input `.cwd` (absolute kept); then `cwk_real_file` follows links and `cwk_real_rel` must place the result inside the physical `CLAUDE_PROJECT_DIR`, else ask (link out, outside). The resolved path must be a regular readable file (`[[ -f && -r ]]`), else ask (missing, FIFO, dir). Read capped at 1 MiB (`head -c 1048576`); content matches → deny; clean → falls through to today's ask.
  - Deny reason: `attribution line in a gh body (<where>): the project forbids it (.claude/agents/github.md)`.
  - `gh pr review` → ask (remote action), reason as `gh … comment`.
  - No guard api bump (Q8): the change only adds denies/asks; a stale target copy is weaker, not unsafe with new allows.
- **K3**, `kit-doctor.py`: new status `INFO = "INFO"`, not in `FAILING`. `check_github_protection()` in section `wiring`, label `github-protection`. Returns `[]` with no subprocess at all when `CWK_DOCTOR_OFFLINE=1` or `gh` is not on PATH. Otherwise, in order, each call with cwd `ROOT`, `timeout=5`, `capture_output=True`, env `GH_PROMPT_DISABLED=1`; any timeout/exception → `[]`:
  1. `gh auth status` — exit ≠ 0 → `[]`.
  2. `gh api repos/{owner}/{repo}/rules/branches/main` — exit ≠ 0, or stdout not a JSON list → `[]`; a non-empty list → `[]`.
  3. `gh api --include repos/{owner}/{repo}/branches/main/protection` — status = the 3-digit code of the first stdout line matching `^HTTP/\S+ (\d{3})` (gh prints the headers on stdout with `--include` whatever the exit code). 200 → `[]`; 404 → one `INFO` finding `main has no ruleset and no classic protection`; 403 → one `INFO` finding `main has no ruleset; classic protection not readable (HTTP 403, needs admin)`; anything else or no status line → `[]`.
  Output count line unchanged: INFO never counts as divergence, exit code unchanged.
- **K3 shim** (`test-kit-doctor.sh`): `$WS/bin/gh` reads `$GH_SHIM_RULES` (stdout for call 2, exit 0), `$GH_SHIM_PROT` (`200`/`404`/`403`: prints `HTTP/2.0 <code> X` then an empty line then `{}`, exits 0 for 200 and 1 otherwise), `$GH_SHIM_AUTH` (exit of `auth status`, default 0), `$GH_SHIM_HANG=1` (`exec sleep 30` on `api`, prints nothing); appends each argv to `$WS/gh.log`.
- **K3**, `templates/github/CODEOWNERS`: `# FILL:` comment naming the owner to set, then `/.claude/hooks/ @OWNER`, `/.claude/settings.json @OWNER`, `/.github/workflows/ @OWNER`. Installed at `.github/CODEOWNERS` with the CI, absent with `--no-ci`, `.new` if present.
- **K4**: `templates/lefthook.yml` = `pre-push:` `parallel: false`, commands `typecheck` (`pnpm typecheck`), `lint` (`pnpm lint`), `test` (`pnpm test:run`). `install.sh --lefthook` → `$TARGET/lefthook.yml` (`copy_file`, `.new` if present) + one line `lefthook: pnpm add -D lefthook && pnpm exec lefthook install`. No option + `-t 0` → `read -r -p "  [o/N] : " answer || answer=""`, `[oOyY]*` installs; no terminal → not installed, no question.
- **K2**, `kit-ci.yml`: job `kit`, `timeout-minutes: 30` (amended from 15); `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0` with `persist-credentials: false`; install step: `jq` (apt), shellcheck v0.11.0 and actionlint v1.7.12 tarballs to `$RUNNER_TEMP/bin` with `sha256sum -c` against the cached digests, added to `$GITHUB_PATH`; ruff via `astral-sh/ruff-action@278981a28ce3188b1e39527901f38254bf3aac89 # v4.1.0` with `version: 0.17.4`, `args: check --select E4,E7,E9,F`, `src: .claude/hooks`, `checksum: <sha256 of ruff-x86_64-unknown-linux-gnu.tar.gz 0.17.4, read from the release's .sha256 file at EXECUTE and cached in ci-lint-tools.md>` (the action appends `src`, default the whole workspace — `action.yml` at that SHA, `src/ruff-action.ts:145`; Q4); steps `shellcheck -S warning .claude/hooks/*.sh .claude/scripts/*.sh`, `actionlint` on `.github/workflows/*.yml` then on each target (`for f in templates/github/publish/*.yml`, `install.sh "$d" --deploy=<t> </dev/null`, `actionlint "$d"/.github/workflows/*.yml`), `test-measure.sh`; existing steps kept.

## Test plan (gate — validated by the user before EXECUTE)
No TS test-first file. Each block is written first and observed failing (RED) before its change, except cases marked `(guard)`, which hold today. Ids per suite, next free in each.

### K2.0: `test-hooks.sh` — hook-guarded side-effects
All three call the one function `guarded_side_effects` (step 0a); GREEN edits only its body.
**Reproduction (fail today)**
- T1 `guarded_side_effects` on `hook-guarded.sh` from `( trap '' PIPE; … )` passes (today: fails on `trap -- '' SIGPIPE`).
**Guards**
- T2 `guarded_side_effects` on a scratch copy of `hook-guarded.sh` with `trap 'true' EXIT` appended fails (a hook-set trap is still caught) `(guard: green today and after; kills a "drop trap -p" fix)`.
- T3 W1 (amended body = the function call, same title) green in a plain shell `(guard)`.

### K1: `test-workflow-contracts.sh`
- K1g both handlers ending with `tdd-require-red.sh` and `tdd-freeze-tests.sh` in `settings.json` carry `"onFailure": "block"`, exactly two of them.
- K1f unchanged `(guard)`.

### K5: `git-guard.jsonl` (G18.01+, setup `ghbody`, project `$tmp`, cwd `$tmp/.feat`; files under `$tmp/.feat/docs/`: `pr-sign.md` with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`, `pr-clean.md`, `pr-sess.md` with `Claude-Session: https://claude.ai/code/session_x`, `pr-only-root.md` with the trailer (its `$tmp/docs/` twin clean), `pr-out.md` symlink to `$(dirname "$fixture")/outside-trailer.md`, which carries the trailer and sits outside `$tmp`, `pr-fifo` a FIFO)
**Reproduction (fail today: ask)**
- G18.01 deny `gh pr create --title t --body "x 🤖 Generated with [Claude Code](https://claude.com/claude-code)"`.
**Core**
- deny inline, per subcommand: `gh pr edit 1 --body "Co-Authored-By: Claude <noreply@anthropic.com>"`, `gh pr comment 1 -b "Generated with Claude Code"`, `gh pr review 1 --comment -b "Claude-Session: https://claude.ai/code/session_x"`, `gh issue create -t t -b "Co-Authored-By: x"`, `gh issue edit 2 --body "Generated with Claude"`, `gh issue comment 2 --body "🤖"`, `gh api -X POST repos/o/r/issues -f body="Co-Authored-By: x"`, `gh api repos/o/r/issues/1/comments -f body="Generated with Claude"`.
- deny title: `gh pr create --title "Generated with Claude" --body b`.
- deny file: `gh pr create --title t --body-file docs/pr-sign.md`, `gh pr create -t t --body-file=docs/pr-sess.md`, `gh issue create -t t -F docs/pr-sign.md`, `gh api repos/o/r/issues -F body=@docs/pr-sign.md`, `gh api repos/o/r/issues --input docs/pr-sign.md`.
- deny cwd base: `gh pr create -t t --body-file docs/pr-only-root.md` (resolved against `.cwd`; resolving against the project dir would read the clean twin → ask).
- deny commit, session link (new pattern): `git commit -m "x" -m "Claude-Session: https://claude.ai/code/session_x"`.
- deny before the python floor: setup `nopy` (`ghbody` not needed), `git switch x && gh pr create -t t -b "Co-Authored-By: x"` → deny, `reason` pinned to `attribution line in a gh body` (today: the floor ask on `switch`; no commit in the command, so the commit deny cannot shadow it).
**Edges**
- ask (as today): `gh pr create --title t --body b`, `gh pr create -t t --body-file docs/pr-clean.md`, `gh issue comment 2 --body ok`, `gh api repos/o/r/issues -f body=ok`.
- ask: `gh pr create -t t --body-file -` (stdin), `gh pr create -t t --body-file docs/pr-out.md` (link out of the project; the target carries the trailer, so a hook that follows the link turns this row deny), `gh pr create -t t --body-file docs/missing.md` (missing), `gh pr create -t t --body-file docs/pr-fifo` (not a regular file; returns at once, no hang; a missing `-f` test hangs into the case timeout), `gh pr review 1 --approve` (new ask, today pass). The `-` and `missing.md` rows only pin the required verdict: a hook that opens `-` or skips the existence test also ends in ask, so they catch no defect on their own.
- `(guard)`: existing commit fixtures with `Co-Authored-By`/`Generated with`/`🤖` stay deny; `gh pr view 1` and `gh api repos/o/r` (read) keep today's verdicts; fixtures `09-f07`, `69-h9` unchanged.

### K3: `test-workflow-contracts.sh`, `test-install.sh`, `test-kit-doctor.sh`
- K3a `ci.md` has a `Repository settings` section naming the ruleset on `main` (PR required, required check `Gates`, no force push, no deletion), `CODEOWNERS` with the three paths, environment `production` with a required reviewer.
- K3b `ci.md` never names `kit` as a required check; `ADAPTATION.md` does (the kit's own check).
- K3c `templates/github/CODEOWNERS` covers `/.claude/hooks/`, `/.claude/settings.json`, `/.github/workflows/`.
- I5a install with CI → `.github/CODEOWNERS` present, equal to the template.
- I5b install with `--no-ci` → `.github/CODEOWNERS` absent.
Doctor cases run `kit-doctor.py` on the scratch kit of `test-kit-doctor.sh:8-31` with `CWK_DOCTOR_OFFLINE` unset and the shim first on PATH (contract "K3 shim").
- KD1 rules `[{"type":"deletion"}]` → no `github-protection` line.
- KD2 rules `[]`, protection 200 → no line.
- KD3 rules `[]`, protection 404 → one `INFO` `github-protection` line `main has no ruleset and no classic protection`; doctor exit code equal to the same run with KD2's shim.
- KD4 rules `[]`, protection 403 → one `INFO` line naming `not readable`.
- KD5 no `gh` on PATH: `PATH="$WS/nogh"`, a dir holding only symlinks to `python3` and `git` (`/usr/bin/gh` exists on the dev machine and on runners) → no line.
- KD6 `GH_SHIM_AUTH=1` → no line, and `gh.log` holds no `api` call.
- KD7 `GH_SHIM_HANG=1` (`exec sleep 30`) → no line, doctor returns within 12 s.
- KD8 `CWK_DOCTOR_OFFLINE=1` with KD3's shim → no line and `gh.log` empty.

### K4: `test-install.sh`
Suite setup (non-case line, first RED step): `exec </dev/null` after `trap … EXIT` at the top of `test-install.sh`, so the ~16 existing `--no-ci` installs (`:10`, `:28`, … `:460`, no redirect today) never reach the new terminal question when the suite is run from a terminal; the I6 tty cases get their tty from `script -qec` and their input from a pipe (`printf '\n' | script …`, `printf 'o\n' | …`, `: | …`). Same line exports `CWK_DOCTOR_OFFLINE=1` (doctor runs `:21`, `:80`, `:162` stay offline).
Every case passes `--no-ci` (skips the remote and CD questions, `install.sh:592,608`) and asserts exit 0 and `.claude/settings.json` installed.
- I6a install on a simulated terminal (`script -qec`, answer Enter) → the lefthook question is printed, `lefthook.yml` absent.
- I6b install with no terminal (`</dev/null`) → absent, and no lefthook question printed.
- I6c install with `--lefthook` → `lefthook.yml` present, equal to `templates/lefthook.yml`, no question printed.
- I6d install on a simulated terminal answering `o` → present.
- I6e EOF on the question (simulated terminal, input ends before an answer) → install exits 0, absent.

### K2: `test-workflow-contracts.sh`
- K2a `kit-ci.yml` has the steps `shellcheck -S warning .claude/hooks/*.sh .claude/scripts/*.sh`, the ruff step with `args: check --select E4,E7,E9,F` and `src: .claude/hooks`, `actionlint` on `.github/workflows` and on assembled targets, `test-measure.sh`, and keeps the 7 suites + `kit-doctor.py`.
- K2b every `uses:` in `kit-ci.yml` matches `@<40 hex> # vX.Y.Z` (own scan; HC2's `-eq 13` over `templates/github` untouched).
- K2c `timeout-minutes: 30` (amended from 15, see `## Gate`) and `persist-credentials: false` present.
- K2d each downloaded tarball is checked with `sha256sum -c` against a literal 64-hex digest naming the same file the step extracts; no `|| true` and no `continue-on-error` in `kit-ci.yml`.
- Local baseline (recorded, not a test): each new step run in scratch on this tree with the CI scope = 0 findings after the pass's fixes/ignores.
- CI rehearsal (recorded, not a test): fresh clone, every `run:` step in order under `( trap '' PIPE; … )`, all green; substitutions named in `## Gate`: `RUNNER_TEMP` = a scratch dir, `GITHUB_PATH` lines prepended to `PATH`, apt step skipped (jq present), ruff-action replaced by `uv tool run ruff@0.17.4 check --select E4,E7,E9,F .claude/hooks`.

### Measure (recorded in `## Gate`, not a test)
- K1: `enforce-git-workflow.sh` replayed 20× on `git add -A` and `git commit -m x` hook inputs in a `git clone --local` scratch copy of CRMperso (largest local repo, 2000 tracked files); median and max recorded.

## Vigilance (carried from research)
- T1/T2: before/after `trap -p` taken in the same `bash -c`; a hook-set trap still fails.
- kit-ci pins in the exact `@<sha> # vX.Y.Z` form; HC2 count untouched.
- ruff runs an explicit `--select`, never the 0.17 default set; a step never lands red.
- shellcheck and actionlint from pinned tarballs + sha256, never `apt` drift nor the `main` download script.
- Doctor: 403/any non-2xx/timeout → nothing or `INFO`, never a failing status; no network call in the suite without a shim; CI runner has no `GH_TOKEN` → `gh auth status` fails → nothing.
- K5 deny sits before the asks; `gh pr review` verdict decided; `gh api` reads untouched.
- K5 body file through `cwk_real_rel`; `-`, link out, unreadable → ask; fixture files created by setup `ghbody`.
- K5 shared regex keeps `🤖` and the commit message; the session link now also denies commits.
- `enforce-git-workflow.sh` api unchanged (Q8); with `onFailure`, a slow hook blocks every git call — the K1 measure decides.
- `install.sh` `read` under `set -e`: EOF guarded (I6e).
- Addon python TDD handlers lack `onFailure`: follow-up in `harness-hardening.md` (Q2), not this pass.
- Spec line refs stale: K1f `:529-535`, side-effects `:702-708`, `claude-code-permissions.md:35`; fix the spec's citations in the same pass.

## Acceptance criteria (carried from the entry artifact)
- [ ] Every proof above is green.
- [ ] `test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-workflow-contracts.sh`, `test-small-lane.sh` and `test-measure.sh` are green.
- [ ] `kit-doctor.py` reports no divergence.

## Proposed answers to research's open questions (decided at the gate)
1. Q1a measure → CRMperso scratch clone, 20 runs, median + max (block "Measure"). Q1b `claude-code-permissions.md:35` → the spec's sentence (non-JSON stdout with `exit 0` does not block), with "2.1.316, stub, n=1".
2. Q2 addon python TDD `onFailure` → follow-up in `harness-hardening.md`, not this pass.
3. Q3 install → shellcheck + actionlint pinned tarballs with sha256 (drift avoided, shellcheck 0.11.0 everywhere); ruff via SHA-pinned `astral-sh/ruff-action` v4.1.0 with `version: 0.17.4`.
4. Q4 ruff rules → `--select E4,E7,E9,F` on the command line, no config file.
5. Q5 "kit-ci.yml green on a PR" → not provable this pass (no push while `65facf8`'s gate is open); proof here = local baseline 0 + contract K2a-d + the CI rehearsal under `trap '' PIPE`; the PR run recorded as a follow-up, criterion reported unmet at ship.
6. Q6 doctor → section `wiring`, new non-failing status `INFO` (KD3-4).
7. Q7 `gh pr review` → ask; `gh api` without a write marker → today's ask unchanged.
8. Q8 → no api bump on `enforce-git-workflow.sh`.

## Plan critic
- attempt 1 (2026-11-07): completeness 88, quality 58. Verified surviving (verifier): M1 K5 fixture project dir, M2 T1 shared check (partial), M3 K4 `--no-ci` (partial), M4 KD7 bound, M5 gh status mechanism, M6 unshimmed doctor gh calls, M7 ruff-action `src`. Minors folded in (cache sentence, spec citations row, CI rehearsal, KD count, K2d strength, frozen-case lint fixes, out-of-scope gh bodies follow-up, deny before `floor_subs`, regular-file + capped read). Rewritten.
- attempt 2 (2026-11-07): completeness 92, quality 72. The 7 attempt-1 Majors closed (critic probes: bash trap before/after, `script -qec`, `gh api --include` 403 on stdout exit 1, ruff-action `src`). 2 new Majors, verified on the main thread by reading the code: floor-order row shadowed by the commit deny (`enforce-git-workflow.sh:1307-1319`) → `git switch x && gh …` row with pinned reason; lefthook question would hang `test-install.sh` on a terminal (`:10` no redirect) → `exec </dev/null` suite line. Minors folded in (Files counts, KD5 no-gh PATH, test-install offline doctor, no tmp leak, captured failure text, ruff checksum, rehearsal substitutions). Rewritten.
- attempt 3 (2026-11-07): completeness 94, quality 80. The 2 attempt-2 Majors closed (critic probes: `nopy` fixture returns the floor ask; `exec </dev/null` + `printf | script -qec` keeps a tty). 1 new Major, verified on the main thread (plan.md:14 vs :86): the `pr-out.md` link-out row cannot fail, because `/etc/hostname` carries no trailer (proposed fix: link to a trailer file in the `run_git_guard_cases` scratch dir, cleaned by `test-hooks.sh:919`). Minors: `/kit:doctor` doc row for `github-protection`/`INFO` (`.claude/commands/kit/doctor.md:120`); the `-` and missing-file rows cannot catch a defect. **BLOCKED: plan-critic failed 3x** (`attempts.json`).
- user decision (2026-11-07): targeted fix, verified on the main thread, no 4th critic. Applied: `pr-out.md` → `$(dirname "$fixture")/outside-trailer.md` with the trailer (plan.md:14 and the K5 header now agree; `$fixture` = `run_case` arg `:115`, scratch dir `:888` ≠ project `$tmp` `:118`, removed `:919`); Files row for `doctor.md`; the `-`/missing rows noted as verdict-only. Gate cleared by `kit-attempts.py pass`.
- final scores: completeness 94, quality 80 (attempt 3), the one Major fixed as above.
- surviving blockers: none

## Gate
- 2026-11-07 go
- Contract: as written (the user first picked "amend" with no text, then confirmed "as written")
- Q1 K1 measure → CRMperso `git clone --local` scratch, 20 runs, median + max; `claude-code-permissions.md:35` gets the spec's sentence (2.1.316, stub, n=1)
- Q2 addon python TDD `onFailure` → follow-up in `harness-hardening.md`
- Q3 install → shellcheck 0.11.0 + actionlint 1.7.12 tarballs with sha256; ruff-action v4.1.0 by SHA with ruff 0.17.4
- Q4 ruff rules → `--select E4,E7,E9,F`
- Q5 "kit-ci.yml green on a PR" → not provable this pass (no push); reported unmet at ship, follow-up
- Q6 doctor → `INFO` status, section `wiring`
- Q7 `gh pr review` → ask; `gh api` reads unchanged
- Q8 → no api bump on `enforce-git-workflow.sh`
- amended 2026-11-07 W1 (`test-hooks.sh` hook-guarded side-effects): inline `bash -c 'source …; trap -p; shopt -p extglob'` + comparison → `msg="$(guarded_side_effects "$HOOKS_DIR/hook-guarded.sh")" || fail hook-guarded.sh side-effects "$msg"`, same title and same failure text; the function compares `trap -p` before/after the `source` (planned T3, user confirms at merge)
- K1 record: K1g RED observed (contracts exit 1 at K1g), GREEN after `onFailure` on both tdd handlers. Measure (Q1a): `git clone --local` CRMperso (2000 files), branch `feat/measure`, 20 runs each: `git add -A` median 148.5 ms, max 158 ms (ask); `git commit -m x` median 137.5 ms, max 144 ms (pass). Median < 1 s: no `DRY_RUN_BUDGET` revisit. Side note: `hook-lib.sh:44` timing redirect prints an error when the project has no `.claude/` (pre-existing, cosmetic, never on an installed target).
- K3 record: RED observed (contracts stop at K3a `ruleset`, doctor stops at KD1 log check, install stops at I5a `cmp`); GREEN: contracts, doctor (KD1-8) and install suites exit 0. `INFO` declared as `OVER, INFO = "OVER", "INFO"` (the comments hook refused a commented line).
- K4 record: RED observed (I6a: no `pre-push local` question); GREEN: install suite exit 0 with I6a-e.
- K5 record: G18.01-29 appended; RED observed 38 failures (G18.01-18 ask instead of deny, G18.27 pass instead of ask; guards 19-26, 28, 29 held). GREEN: `run_git_guard_cases` 529 cases, 0 failures. Probe: same `pr-out.md` link with `CLAUDE_PROJECT_DIR=/` → deny (so G18.24 fails without the containment check). Clean/unreadable body files fall through to the usual remote ask (reason `acts on a pull request`); `gh pr review` joined that ask.
- K2.0 record: T1 RED observed (`got exit 0, 'trap -- '' SIGPIPE / shopt -u extglob'`, 1/49), GREEN 0/49 plain and under `trap '' PIPE`
- K2 baseline (scratch, CI scope, pinned tools sha256-checked): shellcheck 15 findings (13 SC2034, 1 SC2209, 1 SC1112), ruff 4 (E741), actionlint 0 on `.github/workflows`, 1 per assembled target ×6 (SC2046 in `templates/github/ci.yml` Bundle secrets). Fixes, all behaviour-neutral: `rd` local dropped (`hook-guarded.sh`), `mode="write"` quoted (`small-plan.sh`), `l`→`ln` in 4 generators (`english-comments.py`, `kit-doctor.py`); inline ignores with reason: SC2034 ×12 (variables read by a sourcing/sourced file: `CWK_GUARD_HOOK` ×5, `CWK_HOOK_TIMING`, 6 `hook-lib.sh` regexes), SC1112 ×1 (French apostrophe needle, `test-workflow-contracts.sh`, a directive line above the loop, no case body edited), SC2046 ×1 (absent `.env.example` must expand to no word; `ship.md:49` copy not linted, unchanged). After: 0 / 0 / 0. Trap: `uv tool run ruff@0.17.4` exits 0 printing nothing on this machine (not even `--version`), so a first baseline and rehearsal reported ruff green without running it; replaced by the release tarball checked against the same digest as `kit-ci.yml` `checksum:`.
- K2 record: K2a-d RED observed (contracts exit 1 at K2a's first grep), GREEN after the `kit-ci.yml` rewrite (checkout v4.4.0 SHA re-read by `git ls-remote`; ruff-action inputs `args/src/version/checksum` read from `action.yml` at the SHA). actionlint on the new `kit-ci.yml`: 0.
- CI rehearsal: fresh `git clone` + tracked/untracked working-tree files, each `run:` step in order under `( trap '' PIPE; bash -e -o pipefail -c … )`; substitutions: `RUNNER_TEMP`/`GITHUB_PATH` scratch, apt skipped (jq present), ruff-action → release binary `ruff check --select E4,E7,E9,F .claude/hooks`. All 16 steps green (test-hooks 1749 cases 618 s, test-install 152 s, total ≈ 800 s, i.e. ≈ 13.5 of the 15 `timeout-minutes` on this machine).
- K3 fix found by the rehearsal (bugfix, reproduced first): KD5 was vacuous here, `python3` is a pyenv shim with `#!/usr/bin/env bash`, so under `PATH=nogh` the doctor never started (rc 127) and the case passed. New pure case KD5b (`WIRING` reached) observed RED, then the setup line links `sys.executable` (`python3 -I`); GREEN. KD5 body untouched.
- amended 2026-11-07 K2c by the user's decision: `timeout-minutes: 15` → `30` (local rehearsal ≈ 13.5 min, a slower runner would time out); spec line 26 and plan lines 70/130 follow. RED observed (contracts exit 1 with the yml at 15), GREEN at 30, actionlint 0. User confirms at merge.
- Review 1 fix batch (user "ok go", 5 Majors + 2 cheap Minors): RED written and observed on the main thread: G18.30 (M1 `git -C ..` then body file), G18.31-38 (M2 `-R/--repo` before/inside the gh verb, deny and ask) → 17 failures over 541; KD9 (M4 CODEOWNERS FILL) and K3d (M3 self-ownership) red. Guards green today, each mutation-checked in a scratch copy: KD3b (M5, INFO-as-failing mutant killed), K2e (ruff `version`/`checksum`, deleted-checksum mutant killed), G18.39-40 (each session alternative alone), G18.41 (gh read with attribution text stays pass, kills `GH_WRITE=1`). GREEN by the implementer: `$BASE_DIR` for body files; `gh_skip_repo` skips `-R X|-RX|--repo X|--repo=X` before the group and before the verb, ask regexes accept the same; CODEOWNERS owns `/.github/CODEOWNERS` (ci.md, ADAPTATION follow); doctor scans `templates/github/CODEOWNERS` and `.github/CODEOWNERS`. Main thread: diff read, no global name clash (`K`, `GRP`, `VRB`), rehearsal 3 all 16 steps green (test-hooks 1761).
