# Research: Kit CI, GitHub settings, hook failure mode   (entry: docs/specs/harness-kit-ci.md)
Token profile: standard

Probes: 2 `explorer` (K1+K5 hooks; K2+K3+K4 CI/install/doctor), 1 `doc-researcher` (cache `docs/research-cache/ci-lint-tools.md`, new), main-thread measures (ruff-action tags, `gh api` probes, SIGPIPE repro). Base `audit/slim` at `576f8ef`.

## Pattern to follow
- **Contract case** (K1g, K2 contract, K3 `kit` check): flat bare-command cases under `set -euo pipefail` in `.claude/hooks/test-workflow-contracts.sh`, each `# <ID> <title>:` comment then a command; K1f at `:529-535` (jq over `.hooks[][].hooks[]`, `endswith` on basenames, `onFailure == "block"`). `SETTINGS` defined at `:459`. File ends `:759`. Spec's `:514-520` is stale.
- **SHA pin check** (K2): HC2a-b `test-workflow-contracts.sh:628-632` — regex `uses: <owner>/<repo>@<40 hex> # vX.Y.Z` over `templates/github` (`CD_DIR` `:538`), count `-eq 13`. Same regex in `test-install.sh:419-421`. kit-ci.yml is outside both scans.
- **Target assembly loop** (K2 actionlint): `test-install.sh:397-422` — `cd_install() { mkdir -p "$1"; "$ROOT/install.sh" "$@" >/dev/null 2>&1 </dev/null; }`, loop over `templates/github/publish/*.yml` (not `DEPLOY_TARGETS`), `cd_install <dir> --deploy=<t>`, read `<dir>/.github/workflows/deploy.yml`.
- **Shipped CI file + presence test** (K3 CODEOWNERS): `install.sh:674-680` copies `ci.yml`, `dependabot.yml` with `copy_file` (`:81-91`, writes `<dst>.new` if present) inside the `else` of `if $NO_CI`; tests I4a/I4b `test-install.sh:403-409` (present with CI, absent with `--no-ci`).
- **Doctor check** (K3): `kit-doctor.py` checks return `Finding`s (`:48-53`), statuses `ok/DIVERGENCE/MISSING/FILL/skip/OVER` (`:35-38`), no INFO status; `FAILING = (DIVERGENCE, MISSING, OVER)`. Tool-presence analogue `check_hook_prerequisites` `:1049-1074` (`shutil.which`). Subprocess precedent: `git -c core.fsmonitor=false -C ROOT …` `:577`, `:1273`. Sections in `CHECKS` `:1251-1264`.
- **PATH shim** (K3 `gh`): `test-workflow-contracts.sh:133-151` (heredoc `$WS/bin/codex`, `chmod +x`, `PATH="$WS/bin:$PATH" … </dev/null`); `test-kit-doctor.sh:8-31` builds a scratch kit (copies `kit-doctor.py`, `git init`), no shim yet.
- **Terminal question** (K4): `install.sh:594-606` (`-t 0`, `read -r -p "  [O/n] : "`, default yes via `${answer:-o}`); non-terminal default `:638-640`. Tests simulate no terminal with `</dev/null` (`test-install.sh:399`).
- **git-guard rows** (K5): `.claude/hooks/fixtures/_harness/git-guard.jsonl`, `{"id","verdict","command"[,"reason","cwd","setup"]}`, last id `G17.95` (line 500), runner `test-hooks.sh:879-920` → `run_case` `:114`, placeholders `:122`. No gh rows there; gh cases live as per-hook fixtures `fixtures/enforce-git-workflow.sh/09-f07-gh-pr-create-ask.json`, `69-h9-gh-comment-before-commit-deny.json`.

## Wiring points
- `.claude/settings.json` PreToolUse Write|Edit `:80`: `tdd-freeze-tests.sh` `:110`, `tdd-require-red.sh` `:115`, both t5, no `onFailure`. Guards with `block`: protect-files ×3 (`:91,:144,:160`), prevent-destructive `:127`, enforce-git-workflow `:133`.
- `install.sh` `install_settings` `:271-345`: react mode copies the kit file whole (`:277`); core mode jq-filters to six commands (`:276-291`, drops both tdd handlers); merge `group_by(.command)|map(last)` (`:300-345`) so the kit handler object (with its key) wins. `add_py_hooks` `:356-400` appends addon python TDD handlers without `onFailure`.
- `.github/workflows/kit-ci.yml`: `push:` + `pull_request:` (`:4-5`), `permissions: contents: read`, job `kit` ubuntu-latest, `actions/checkout@v4` tag pin `:14`, `apt-get install -y jq` `:15-16`, then `jq empty`, 7 suites, `kit-doctor.py` (`:17-34`). No `timeout-minutes`, no `persist-credentials`, no `test-measure.sh`. Only workflow in `.github/workflows/`; never installed (`install.sh:677-678` copies only `ci.yml`, `dependabot.yml`).
- `templates/github/ci.yml`: job `gates`, display `name: Gates` `:33-34` (the required check name for K3).
- `enforce-git-workflow.sh`: early exit unless `git`/`\bgh\b` `:90`; DENY pass (comment `:1300-1304`), commit attribution grep `:1313-1319` (`grep -qiE 'Co-Authored-By|Generated with .*Claude|🤖'` on `$COMMAND`, inside `IS_COMMIT` `:1307`); ASK section: `gh pr create|merge|edit|close|reopen|ready` `:1380-1381`, `gh issue|release|repo|api` `:1384-1385`, `gh … comment` `:1388-1389`. Sources `hook-lib.sh` `:74`. api 3 (`:2`).
- `hook-guarded.sh` path helpers: `cwk_real_path` `:152`, `cwk_real_file` `:176` (symlinks, 40 hops), `cwk_real_rel` `:211` (exit 1 outside the physical project), `cwk_guard_rel` `:229`; exposed via `hook-lib.sh:61-62`.
- `.claude/skills/templates/ci.md` (250 lines): sections `:9,26,64,94,124,133,165,192,235`; environment/branch-rule text inside "The four properties" `:219-234`; no `CODEOWNERS`, no `Gates` named as required check (`:61` generic).
- `docs/ADAPTATION.md`: fail-closed paragraph `:467-469` (K1 line, French); §4 bis CI `:215-301` (K3 `kit` check note); trailer/gh statement `:324-330`; guard api `:520-530`.

## Reusable
- K1f jq shape → K1g; HC2 regex → kit-ci SHA pin check; `cd_install` loop → CI actionlint loop; `copy_file` + I4a/I4b → CODEOWNERS; `check_hook_prerequisites` + `subprocess` git precedent → gh check; codex shim → gh shim; `cwk_real_rel` → `--body-file` resolution (gh branch is shell, bash helper fits); commit attribution regex `:1317` → the one shared list K5 asks for (to be extracted, today it is inline, not shared).
- Pins: `actions/checkout` v4.4.0 `11d5960a326750d5838078e36cf38b85af677262` [cache 2026-11-01, github-actions.md]; actionlint v1.7.12 tarball sha256 `8aca8db9…a3d8`; shellcheck v0.11.0 `linux.x86_64.tar.gz` sha256 `b7af85e4…e6f6`; ruff 0.17.4 (PyPI); `astral-sh/ruff-action` v4.1.0 `278981a28ce3188b1e39527901f38254bf3aac89` [cache 2026-11-07, ci-lint-tools.md].

## Blast radius
- `enforce-git-workflow.sh` (api 3) edited by K5 → bump decision: `install.sh` `GUARD_FILES` `:206-208` + `guard_api_missing` `:241-` hold P1 for a target copy with a lower number (A0 clause). K1 touches no guard file → no bump.
- `test-hooks.sh` side-effects case `:702-708` (K2 first fix): `.claude/hooks/test-*.sh` match neither `CWK_TEST_FILE_RE` (`hook-lib.sh:266`) nor `TEST_SUPPORT_RE` (`tdd-freeze-tests.sh:79`); `.claude/.tdd-unfrozen` absent → no TDD freeze applies, but the case is an approved frozen row by the kit's own process: changing it is an amendment for `## Gate`.
- `.claude/agents/github.md:30-34` names `Claude-Session` as forbidden, no hook refuses it (commit regex has no session-link pattern) → K5 list extension also tightens `git commit`: existing commit fixtures must stay green.
- Shellcheck/ruff scope: 23 `.claude/hooks/*.sh` + 5 `.claude/scripts/*.sh`; 8 `.claude/hooks/*.py`; no `.shellcheckrc`/`ruff.toml`/`pyproject.toml`; disables `hook-guarded.sh:81,95` (SC2053), directive `small-dispatch-check.sh:9`.
- ADAPTATION, `ci.md`, `claude-code-permissions.md:35`, `kit-doctor` output (new line) — kit-doctor twin checks unaffected unless a new twin is declared.

## Live DB state
n/a — no database.

## External surface
- actionlint v1.7.12, sha256 from checksums file; docs recommend the (unpinned, from `main`) download script — the pinned tarball + `sha256sum -c` is stricter [fetched]. Runs shellcheck on `run:` blocks when on PATH; `-shellcheck=` disables [fetched].
- shellcheck: latest v0.11.0; ubuntu-24.04 image 20261101.360.1 ships 0.9.0-1 (spec confirmed); 26.04 x64 not read [fetched].
- ruff 0.17.4; default rule set grew in 0.16.0 (~59 → ~413 rules, secondary sources) → an explicit `select` is needed for a stable baseline [fetched, partial]. `astral-sh/ruff-action` v4.1.0 SHA [measured].
- GitHub REST, measured with the user's token on `Stv-devl/LoopKit` (public): `rules/branches/main` → 200 + 3 rules, exit 0; branch without rules → `[]`, exit 0; `branches/<b>/protection` → **403** "Resource not accessible by personal access token", exit 1 (needs admin) [measured 2026-11-07].
- CODEOWNERS: `.github/`, root, `docs/` (first wins), read from the base branch; enforced only with "Require review from Code Owners" [fetched, snippets].
- lefthook 2.2.2 (npm, postinstall script; pnpm 10 may block it unless in `onlyBuiltDependencies`, unchecked); `pre-push: commands: <n>: run:`; `parallel` default unsettled → set `parallel: false` [fetched, partial].
- Claude Code `onFailure` measured on 2.1.316 (`docs/work/git-allow-grammar/plan.md:194`) [cache]; `claude-code-permissions.md:35` says "invalid output" blocks under `onFailure`, contradicted by the measure (non-JSON stdout + exit 0 runs); the measure does not state whether the key was set on the exit-0 arms.

## Traps (points of vigilance for the review)
- SIGPIPE cause reproduced on the main thread: `(trap '' PIPE; bash -c 'source hook-guarded.sh; trap -p')` prints `trap -- '' SIGPIPE`. The before/after comparison must be taken **in the same `bash -c`** (before the `source`), so a trap set by the hook still fails the case.
- kit-ci.yml must use the exact `@<40 hex> # vX.Y.Z` form, or a new regex; adding kit-ci to HC2's scan changes its `-eq 13` count — keep the count check scoped.
- ruff without a config lints ~413 rules on 0.17.x: pin `select` (or a config file) before measuring the baseline; a step never lands red.
- shellcheck version drift 0.9.0 (24.04) vs 0.11.0 (latest): pin by tarball+sha256, or record the drift; actionlint also calls whatever shellcheck is on PATH.
- An actionlint download script fetched from `main` is an unpinned remote script in CI: pin the tarball + checksum.
- Classic protection read returns 403 without admin: the doctor must treat 403/any non-2xx as "unknown → nothing", not "unprotected" (informational only, never a failing status: no INFO status exists, use `ok`/`skip`).
- `gh` in the doctor is a subprocess on the user's network: must not run in the kit's own test suite without a shim, and must not block (timeout).
- K5 deny must sit in the DENY pass (before `:1380-1389` asks), or an ask shadows it; `gh pr review` matches no rule today (falls through: decide its verdict); `gh api` reads vs writes need `-X/--method`/`-f/-F` parsing.
- K5 body file: path resolved with `cwk_real_rel` (no link out of the project), `-`/stdin → ask, unreadable → ask; a git-guard row needs a new `setup` key that creates the file in the fixture tree.
- K5 one shared list: extending to `Claude-Session`/`claude.ai/code` also changes the `git commit` deny; the `🤖` pattern exists today, keep it.
- `enforce-git-workflow.sh` edit → api bump question (A0); the 2 s dry-run budget is not the wall-clock bound (other git calls 1 s each, `:431-455`, `:503-520`); with `onFailure: block` an overrun of the 5 s timeout blocks every git call.
- `install.sh` `read` under `set -euo pipefail` (`:25`): EOF on `read` aborts instead of defaulting — the lefthook prompt must guard it (`|| answer=`).
- Addon python TDD handlers (`add_py_hooks` `:356-400`) also lack `onFailure`: out of K1's text, name it as follow-up or include.
- Spec citation drift: K1f `:529-535` (not `:514-520`); side-effects case `:702-708` (not `:420-425`); `claude-code-permissions.md:35` (not `:34`, which is the heading).

## Open questions
1. K1 measure: which "largest local repo" for the git hook timing (ecocrew? this kit?), and how many runs for the median (proposal: 20 runs of a `git status`/`git add` hook replay)?
2. K1: do the addon python TDD guards (`tdd-require-red-py.py`, `tdd-freeze-tests-py.py`) also get `"onFailure": "block"` in `add_py_hooks`, or is that a follow-up?
3. K2 install method: actionlint and shellcheck by pinned tarball + `sha256sum -c`; ruff by `pipx install ruff==0.17.4` (no hash) or `astral-sh/ruff-action@278981a…` (SHA-pinned action)? And is the shellcheck 0.9.0/0.11.0 drift pinned (tarball) or recorded as accepted?
4. K2 ruff rule set: `select = ["E4","E7","E9","F"]` (the pre-0.16 default) in a `ruff.toml` at the root, or the new default set with its baseline fixes?
5. K2 proof "kit-ci.yml green on a PR": needs a push + PR, which is blocked while `65facf8`'s security gate is not concluded (memory/handoff). Is the local baseline + contract the proof for this pass, the PR run deferred?
6. K3 doctor: section for the gh line (`wiring` next to `hook-prerequisites`, or `health`)? Which status for "neither": `skip` with the informational text, or `ok`?
7. K5 verdicts: `gh pr review` (today falls through = pass?) — ask like comment? `gh api` without `-X`/`-f`/`-F` = read: still ask as today?
8. K5: `enforce-git-workflow.sh` api 3 → 4 (target copies hold P1 until reinstalled), or no bump (the change only adds denies)?
