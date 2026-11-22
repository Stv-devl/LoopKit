# Research: CD templates hardening   (entry: docs/specs/harness-cd.md)
Token profile: critical

## Pattern to follow
- Contract style: `.claude/hooks/test-workflow-contracts.sh`: bare `grep -Fq`, `grep -Fxq`, `jq -e`, relying on `set -euo pipefail` (`:2`), labels as comments `# Kn …`; last label `# K1f` at `:514`; ends with `echo 'workflow contract fixtures: green.'`.
- Install cases: `.claude/hooks/test-install.sh`: `"$ROOT/install.sh" "$TARGET" --no-ci >/dev/null 2>&1`, then a check; labels `# I1`, `# I2`, `# I3` (`:104`, `:119`, `:216`); scratch from `mktemp -d` (`:5`). No case uses `--deploy=` today.
- No existing contract reads `deploy.yml`, `ci.yml`, `ssh.yml` or a `uses:` line.

## Wiring points
- Job `if:`: `templates/github/deploy.yml:62-64`, a three-line `>-` scalar at 4 spaces, comment above at `:58-61`.
- Trigger: `deploy.yml:33-38`, `workflow_run` with `branches: [main, master]`, plus `workflow_dispatch`.
- Dispatch path: `deploy.yml:105-107`, `gh run list --workflow=CI --branch="$DEFAULT_BRANCH" --status=success --limit=1 --json … --jq …`.
- Download: `deploy.yml:159-165`, by `dist-<sha>` and run id.
- Assembly: `install_deploy` at `install.sh:127-189`: an awk pass replaces only the `# >>> PUBLISH_… <<<` lines, every other line is printed unchanged, so assembly leaves the `if:` line and its indentation alone. Fragments are printed verbatim.
- `uses:` lines, 13 in all, none with a trailing comment: `ci.yml:39,51,56,175`; `deploy.yml:146,150,151,160`; `publish/ghcr.yml:35,38,44`; `publish/pages.yml:11,16`. No other file quotes them.
- CLI lines: `publish/netlify.yml:9`, `publish/vercel.yml:23`. `deploy.yml:129` is a comment only.
- SSH: `publish/ssh.yml`: header `:8-10`, secret list `:25-29`, `env:` block `:36-39`, guards `:42-43`, key written `:49-51`, rsync `:52-54`. `accept-new` appears only at `:8` and `:53`.
- Dependabot: no such file anywhere. `install.sh:634-639` is the branch; nothing enumerates shipped templates, so it needs an explicit `copy_file`.

## Reusable
- `copy_file` (`install.sh:80-89`): an existing destination is kept and the copy lands as `.new`.
- `section` helper in `test-workflow-contracts.sh:287`.
- Pins and CLI versions: `docs/research-cache/github-actions.md`.
- `check_fill_markers` (`kit-doctor.py:1023-1048`) scans `templates/github/**/*.yml`, so the new file is covered and must hold no `FILL`.

## Blast radius
- `kit-doctor.py` `check_workflow_names` (`:593-632`) reads `--workflow=(\S+)` and `workflows: […]`; `--event=push` does not match. `check_ci_scripts` reads `pnpm <script>` in `ci.yml` only. No check reads `uses:` lines or the SSH fragment.
- `test-kit-doctor.sh` builds its own scratch `ci.yml`, so it is unaffected.
- Docs that describe the changed behaviour: `.claude/skills/templates/ci.md:194-198` (property 1), `:184` (`ssh` row, nothing about host keys); `docs/ADAPTATION.md:244-262` (deploy section, nothing about pins or host keys).
- Existing targets only get `deploy.yml.new` (`install.sh:85-86`), so they keep the hole until they merge.
- Guards: `.claude/hooks/test-*.sh` are guarded paths, so each edit asks the user; `templates/github/*` and `install.sh` are not guarded (`hook-guarded.sh:20-34`). Neither test scripts nor `install.sh` is in `GUARD_FILES` (`install.sh:206-207`), so no api bump.

## Live DB state
n/a

## External surface
- Pins: table in `docs/research-cache/github-actions.md` [fetched 2026-11-01, `git ls-remote`, `npm view`].
- `gh run list -e, --event` exists (`gh run list --help:15`) [measured]; accepted values not listed in the manual.
- `workflow_run` runs the default branch's file and may hold secrets and write tokens even when the previous workflow could not; a fork `pull_request` run has a read-only token and no secrets; first-time contributors may need approval, configurable per repository [fetched, `docs/research-cache/github-workflow-run-dependabot.md`].
- Not documented on the pages read: whether artifact upload works on a fork run, which workflow file a fork `pull_request` run uses, the `branches:` filter on a fork's same-named branch [fetched: not documented]. C1's exposure therefore rests on knowledge of GitHub's behaviour, not a citation and not a run. C1's fix does not depend on the answer.
- Run object fields `event`, `conclusion`, `head_branch`, `head_sha`, `head_repository.full_name` are present on the REST object of run 41295729202 [measured]. The webhook page documents no nested fields, so that the `workflow_run` context carries the same object is assumed from the shared shape.
- Dependabot: `directory: "/"` covers `.github/workflows`; it updates a same-line version comment on a SHA pin; `npm` is the value for pnpm v7-v12; `ignore` takes `version-update:semver-major` [fetched]. Behaviour with `npm` and no manifest: not documented. Whether majors are proposed by default: not documented.

## Traps (points of vigilance for the review)
- C1 replaces all three lines `deploy.yml:62-64`; a kept continuation line breaks the YAML or leaves a second condition. The one-line form parses as YAML (PyYAML, measured).
- The `if:` contract is `grep -Fxq` including the 4-space indentation, on the skeleton; also assert it on an assembled `deploy.yml`, since that is what ships.
- Without the dispatch arm the job skips on dispatch; without `conclusion` a red run deploys.
- The `uses:` contract must fail on zero lines found and must not abort early under `set -euo pipefail` when `grep -v` matches nothing.
- `pnpm/action-setup` v4.4.0 is one commit past floating `v4` (still v4.3.0); the other nine equal their floating tag. Its tag is annotated: the SHA is the peeled commit `fc06bc1…`, not the tag object `a15d269…`.
- A new required secret: `DEPLOY_KNOWN_HOSTS:?` stops every SSH deploy until it exists. It must be in the header's secret list and in `docs/ADAPTATION.md`, and passed through `env:`, never `${{ }}` in the command (`ssh.yml:19-23`).
- `StrictHostKeyChecking=yes` must sit inside the `-e "ssh …"` string, and the header comment `:8-10` goes too, since the contract forbids `accept-new` anywhere.
- `netlify-cli` 27 needs Node `>=22.13.0`; `node-version: '22'` resolves to the latest 22.x, so this holds only while it stays unpinned.
- Every install fixture today uses `--no-ci`, and `--deploy=none` writes a `deploy.yml` whose snippet is `exit 1` (`ci.md:153-154`): the new cases must not read that as a working deploy.
- `kit-ci` is red on this branch for an unrelated reason (`test-hooks.sh:420-425`, `harness-kit-ci`); a local green is not a CI green.
- `65facf8` is not pushed before the user's review; the ship commit stays local, and a PR needs its own base.

## Open questions
1. Dependabot `npm` on a target with no `package.json`: the behaviour is not documented. Keep the `npm` entry in the shipped file as the spec says, and accept a possible failed job on a Python-only target, or leave `npm` out? The kit assumes a React front (`01-stack.md`), so such a target is rare.
2. Should dependabot's major-version PRs be left on? The spec routes major bumps through dependabot, so no `ignore` key is the reading that matches it; whether majors are proposed by default is undocumented and shows only on a first real run.
