# Spec: CD templates hardening
Token profile: critical (deploy path)
Split from: `docs/specs/harness-hardening.md` Phase 2 (rewritten 2026-10-29 after review + refutation; corrected 2026-11-01 after a third review + refutation).
Needs: nothing. It may run before `harness-hooks`, and C1's hole argues for it. `65facf8` is not pushed before the user's review of `readable_git_dir`, so a PR of this pass needs its own base branch, with small append conflicts in `install.sh`, `test-install.sh` and `test-workflow-contracts.sh`.

## Objective
A deploy runs only from a push to `main` of this repository, with pinned actions and CLIs, and an SSH target whose host key is known in advance. Each item is held by a contract in `test-workflow-contracts.sh`, not by reading: the contract catches a regression on the forms it names, not every edit of these files. Accepted gaps, the user's decision of 2026-11-01: `docs/specs/harness-hardening.md`, Open follow-ups.

## C1. Deploy refuses a non-push or foreign run (old H6)
Two paths reach a deploy today. Each one runs off a CI run selected by branch name only, so a fork PR from a branch named `main` matches on both paths. The upload condition (`templates/github/ci.yml:174`) is no barrier: a `pull_request` run uses the PR's own workflow file, so the fork can drop `github.event_name == 'push'`, keep `name: CI`, and upload `dist-<head sha>`, which `deploy.yml:162` downloads by name and run id. Read from the files and GitHub's documented behaviour; no end-to-end fork run was driven.
- **Change.**
  - `workflow_run` path: the job `if:` becomes this expression, on one line, keeping both of today's arms:

    ```
    if: github.event_name == 'workflow_dispatch' || (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_repository.full_name == github.repository && github.event.workflow_run.head_branch == github.event.repository.default_branch)
    ```

    Without the dispatch arm the job skips on dispatch; without `conclusion` a red run deploys; without `head_branch` a push to `master` deploys on a repository whose default branch is `main`. Accepted cost (user's go, 2026-11-01): a repository whose default branch is not its release branch stops deploying, with no error.
  - `workflow_dispatch` path: `gh run list` gains `--event=push` (`deploy.yml:105-107`, same `=` style as its other flags).
  - Both paths: the Resolve step refuses a commit that is not on the default branch, by `gh api repos/$GH_REPO/compare/$sha...refs/heads/$DEFAULT_BRANCH` (`ahead` or `identical` pass, anything else or a `gh` error stops the step). A tag push reports its tag name as `head_branch`, so a tag named `main` otherwise passes the `if:`. Added by the user's decision of 2026-11-01. It has not run on GitHub.
  - The comment at `deploy.yml:58-61` and `.claude/skills/templates/ci.md:194-198` state the push and same-repository conditions.
- **Contract.**
  - The file holds the `if:` line above exactly, by a fixed whole-line match (`grep -Fxq` with its indentation).
  - The `gh run list` line holds `--event=push`.

## C2. Supply chain (old H7)
- Every `uses:` in `templates/github/ci.yml`, `deploy.yml`, `publish/*.yml` pinned by full SHA with the exact tag in a comment, on **the latest release within the major in use**. All ten actions have a newer major today (`git ls-remote`, 2026-11-01), and major bumps go through dependabot, not this pass. The ten actions: `actions/checkout`, `actions/setup-node`, `pnpm/action-setup`, `actions/upload-artifact`, `actions/download-artifact`, `actions/upload-pages-artifact`, `actions/deploy-pages`, `docker/login-action`, `docker/setup-buildx-action`, `docker/build-push-action`.
- `pnpm --package=netlify-cli@<x.y.z> dlx netlify`, `pnpm dlx vercel@<x.y.z>`. `netlify-cli` has two binaries, so `pnpm dlx netlify-cli` fails on every pnpm tried (8 to 12). Dependabot reads neither line: the CLI pins are bumped by hand.
- `install.sh` copies `templates/github/dependabot.yml` (`github-actions` + `npm`, weekly) to `$TARGET/.github/dependabot.yml`, in the `else` branch at `install.sh:636-639`. The `npm` entry ignores major versions (`01-stack.md`: a version change is a decision); the `github-actions` entry does not.
- **Contracts.**
  - Every `uses:` line under `templates/github/` matches `@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$`.
  - Every active `pnpm … dlx` call under `templates/github/` is `pnpm --package=netlify-cli@<x.y.z> dlx netlify` or `pnpm dlx vercel@<x.y.z>`, and no `npx`, `pnpx`, `bunx`, `yarn dlx` or `npm i|install|exec` remains.
  - `test-install.sh`: dependabot present with `--deploy=none`, absent with `--no-ci`.

## C3. SSH host key pinned (old H8)
This is also the user's real deploy path: a Lightsail instance is an SSH target. `DEPLOY_HOST` must hold its static IP or a stable name, because a replaced instance changes its host key and the deploy then refuses until `DEPLOY_KNOWN_HOSTS` is updated.
`publish/ssh.yml`: secret `DEPLOY_KNOWN_HOSTS` written to `~/.ssh/known_hosts`, `StrictHostKeyChecking=yes`, `:?` guard on it; the snippet header's secret list gains it (`ssh-keyscan` once on the host part of `DEPLOY_HOST`, keeping one key type, its fingerprint compared out of band with `ssh-keygen -lf` run on the server, for Lightsail from the browser SSH console).
The `-o StrictHostKeyChecking=accept-new` in the rsync command (`ssh.yml:53`) and the header comment that names it (`:8-10`) are replaced.
- **Contract.**
  - `ssh.yml` contains no `accept-new` and no `StrictHostKeyChecking=no`, anywhere, comments included.
  - The `-e "ssh …"` string itself holds `StrictHostKeyChecking=yes`.
  - `DEPLOY_KNOWN_HOSTS:?` is present.
  - `known_hosts` receives that secret, by exact line, and nothing else writes it or scans a key.

## Decisions
- **DC2, answered 2026-11-01.** The user deploys on AWS Lightsail. The S3 + CloudFront target of old C4 (H9) is dropped, and `--deploy=ssh` with C3 covers a Lightsail instance. A Lightsail container service would not be covered, and reopens this.

## Decision to take before EXECUTE
- **DC1.** Run on the main thread, not by `doc-researcher` (no Bash, a budget of 6 questions for 12-13 items):
  - read `docs/research-cache/settled.md`;
  - `git ls-remote --tags` per action, reading `^{}` for an annotated tag, to get the exact `vX.Y.Z` and its commit SHA within the major in use;
  - `npm view netlify-cli version`, `npm view vercel version`.

  The answer is cached in `docs/research-cache/github-actions.md`, and `harness-kit-ci` K2 reuses it. No allow rule is added: this runs once, and approving a prompt is fine.

## Order
C1 → C3 → DC1 → C2.

## Done when
C1–C3 contracts green in `test-workflow-contracts.sh`; `test-install.sh` green; `kit-doctor.py` no divergence.
