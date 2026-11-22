# Spec: Kit CI, GitHub settings, hook failure mode
Token profile: standard
Split from: `docs/specs/harness-hardening.md` Phase 3 and D4 (rewritten 2026-10-29, corrected 2026-10-30 and 2026-11-01 after further reviews + refutations).
Needs: for K2 only, `harness-cd` DC1 (`docs/research-cache/github-actions.md`). K1, K3 and K4 are free.
Open before K2's proof: `kit-ci` is red on `audit/slim` (runs 40839709923 and 41295729202, both at `1a92ff0`), and `65facf8` has never run on CI. Cause found 2026-11-01: the runner starts the step with SIGPIPE ignored, `trap -p` then prints `trap -- '' SIGPIPE`, and the `hook-guarded.sh / side-effects` case (then `test-hooks.sh:420-425`, now W1 `:736-740` calling `guarded_side_effects`) expects no trap at all. Reproduced locally at `65facf8` with `trap '' PIPE` before the suite: 1 failure across 800 cases. The test is too strict; nothing shows the hook at fault. Fix, first in K2: compare `trap -p` after sourcing with `trap -p` before it in the same shell, so an inherited trap passes and a trap set by the hook still fails. The steps after this one were skipped on CI, so `kit-ci` has not shown them on this code.

## Objective
- The kit's own CI checks the hooks' code and the workflow templates.
- The repository settings that make the gates binding are documented and reported.
- A guard hook that times out or crashes blocks the call instead of letting it through.

## K1. Guard hooks fail closed (old D4, `light-permissions-git` OQ7)
- **Today.**
  - `65facf8` put `"onFailure": "block"` on five of the seven handlers (`protect-files.sh` ×3, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`), pinned by K1f (`test-workflow-contracts.sh:529-535`). The two `tdd-*` handlers lack it.
  - Measured on 2.1.316 only, on a stub, one run each (`docs/work/git-allow-grammar/plan.md:194`): past-timeout, `exit 1` and a missing script block with the key and run without it; silent `exit 0` runs; non-JSON stdout with `exit 0` still runs. That last result contradicts `docs/research-cache/claude-code-permissions.md:35`.
  - `enforce-git-workflow.sh` runs a `git add --dry-run` on a 2 s deadline inside a 5 s timeout.
- **Change.**
  - `"onFailure": "block"` on `tdd-require-red.sh` and `tdd-freeze-tests.sh`.
  - `claude-code-permissions.md:35` is corrected from the measure: non-JSON stdout with `exit 0` does not block.
  - `docs/ADAPTATION.md` gains one line: this was measured on 2.1.316; an older version is assumed to ignore the key, not tested.
- **Proof.**
  - K1g in `test-workflow-contracts.sh`, a pure new case: both `tdd-*` handlers carry the key. K1f is not edited.
  - The git hook's real time is measured on the largest local repo and recorded. If the median is above 1 s, its dry-run deadline is revisited.

## K2. Kit CI covers the hooks' own code (old H11)
- `.github/workflows/kit-ci.yml` gets `persist-credentials: false`, `timeout-minutes: 30` (15 amended 2026-11-07 by the user: the local rehearsal used ≈ 13.5 min), and actions pinned by SHA from the DC1 cache of `harness-cd`.
- An install step gets `ruff` and `actionlint`, at pinned versions. `kit-ci.yml:16` installs only `jq`. `shellcheck` comes with the current runner images, but in different versions (0.9.0 on Ubuntu 24.04, 0.11.0 on 26.04), so pin it too or record the drift as accepted.
- New steps:
  - `shellcheck -S warning .claude/hooks/*.sh .claude/scripts/*.sh`
  - `ruff check .claude/hooks`
  - `actionlint` on `.github/workflows`, and on each target assembled the way `test-install.sh` does it. For each target in `DEPLOY_TARGETS`, run `install.sh <tmp> --deploy=<target>` into a `mktemp -d`, then `actionlint <tmp>/.github/workflows/*.yml`. That covers the installed `ci.yml` and each assembled `deploy.yml`. The raw `publish/*.yml` fragments and `deploy.yml` placeholders do not lint on their own.
  - `test-measure.sh`
- **Baseline first.** None of the three tools is installed on this machine, so install them first. Before adding a step, run it locally and record the finding count. A step whose baseline is not zero lands with its fixes in the same pass, or with an explicit ignore list. It never lands red.
- **Proof.**
  - `kit-ci.yml` is green on a PR.
  - `test-workflow-contracts.sh` checks that the steps are present and that every `uses:` in `kit-ci.yml` is pinned by full SHA.

## K3. GitHub repository settings, documented and reported (old H10)
- **Repository settings section.** `.claude/skills/templates/ci.md`, which ships to every target, gains a "Repository settings" section:
  - a ruleset on `main`: PR required, required check `Gates`, no force push, no deletion;
  - `CODEOWNERS` covering `.claude/hooks/`, `.claude/settings.json` and `.github/workflows/`;
  - an environment `production` with a required reviewer.

  The `kit` check is **this repo's own** setting, written in the kit's `docs/ADAPTATION.md`, never in `ci.md`. `kit-ci.yml` is not installed in targets, so a target requiring `kit` could never merge.
- **CODEOWNERS template.** `install.sh` ships a `CODEOWNERS` template.
- **Doctor check.** `/kit:doctor` reports, informational only, when `gh` is authenticated and `main` has neither a ruleset (`repos/{o}/{r}/rules/branches/main`) nor classic protection.
- **Proof.**
  - `test-kit-doctor.sh` with a `gh` shim:
    - ruleset present → nothing;
    - classic protection present → nothing;
    - neither → the informational line;
    - no `gh` → nothing.
  - `test-install.sh`: `CODEOWNERS` is installed with the CI.
  - Contract: `ci.md` does not name `kit` as a required check.

## K4. Optional local pre-push (old H12)
`templates/lefthook.yml` (pre-push: typecheck, lint, `test:run`). `install.sh` gains a `--lefthook` option. Without it, it asks only on a terminal, and the default answer is no. No terminal → not installed.
- **Proof.** `test-install.sh`:
  - absent by default;
  - absent with no terminal;
  - present with `--lefthook`.

## K5. No attribution line leaves the machine through `gh` (user, 2026-11-05)
Observed: an attribution/signature line reached a GitHub PR description. `enforce-git-workflow.sh` refuses attribution trailers only on `git commit`; on `gh pr create`/`gh pr edit` it only asks and never reads the body, and in auto mode the ask went through. Project rule: no attribution line anywhere (`.claude/agents/github.md`).
- **Rule.** On `gh pr create`, `gh pr edit`, `gh issue create`/`edit`/`comment`, `gh pr comment`/`review` and `gh api` writes, deny when the inline body or title (`--body`/`-b`, `--title`/`-t`, `-f`/`-F body=…`) carries an attribution line: the same patterns the commit check refuses (`Co-Authored-By:`, `Generated with`, the session link), reusing one shared list.
- **Body from a file.** `--body-file`/`-F` and `-F body=@<file>`: the hook reads the file (path resolved like the other hooks, never following a link out of the project, `-` = stdin → ask), and denies on the same patterns; an unreadable file → ask.
- **Proof.** `git-guard.jsonl` rows: inline body with the trailer → deny, per subcommand; body file with it → deny; clean body and clean file → ask as today (remote action); `--body-file -` → ask; trailer in `--title` → deny.

## Decisions already taken
- **DK1.** Answered: `block`, measured on 2.1.316 (K1). The fallback branch is removed: frozen K1f requires `block` on three hooks, so it could not pass without amending that case.

## Order
K1, K3, K4, K5 in any order. K2 after `harness-cd` DC1.

## Done when
- Every proof above is green.
- `test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-workflow-contracts.sh`, `test-small-lane.sh` and `test-measure.sh` are green.
- `kit-doctor.py` reports no divergence.
