---
topic: github-workflow-run-dependabot
checked: 2026-11-01
stability: volatile
sources:
  - https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference
  - https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
  - https://cli.github.com/manual/gh_run_list
  - https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories
  - https://docs.github.com/en/webhooks/webhook-events-and-payloads
  - https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks
  - https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories
  - https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/auto-update-actions
---

Method note: pages were read through a summarising fetcher, not raw. Options-reference chunk 0-200k chars was read in two parts; webhook page in two parts (the workflow_run section was in the second).

## 1. Dependabot npm, directory /, repo with no package.json
Not documented. The options reference does not say whether the job errors, is ignored, or alerts. Only stated: updates are configured for "repositories that contain a dependency manifest or lock file for one of the supported package managers", and the repository "must also contain a dependency manifest or lock file for each package manager". Behaviour with none present: not found. Needs an empirical probe.

## 2. github-actions on `uses: o/a@<sha> # vX.Y.Z`
- Version comment: documented. "Dependabot updates the version documentation of GitHub Actions when the comment is on the same line." Also: if the pinned commit is not associated with any tag, Dependabot updates to the latest commit. Dependabot resolves versions from git tags; SemVer prerelease tags are prerelease. Updating the SHA itself on a tagged pin: implied by the above, not stated in one sentence.
- Major bumps by default: not documented in the pages read (options reference states no default for majors). Keys: `ignore` entries take `dependency-name`, `versions` ("ignore specific versions or ranges") and `update-types`; `version-update:semver-major` is the documented value for majors. Whether majors are proposed by default is not stated.
- Directory: documented. "The `directory` must be set to `"/"` to check for workflow files in `.github/workflows`." Options reference: with `/`, "Dependabot will search the `/.github/workflows` directory".
- Only GitHub repository syntax is supported; local actions/reusable workflows are ignored.

## 3. npm ecosystem with pnpm-lock.yaml
Documented. Supported-ecosystems table: pnpm uses YAML value `npm`, versions v7, v8, v9, v10, v11, v12; vendoring not supported. Limit: when pnpm writes `pnpm-lock.yaml` as two YAML documents, the dependency graph does not detect those dependencies, so no alerts/security updates for them; version updates still work.

## 4. workflow_run
- Webhook payload (webhook-events-and-payloads, workflow_run section): `action` documented (`completed`, `in_progress`, `requested`). `workflow_run` is an object marked required with no nested fields listed there. So `event`, `conclusion`, `head_branch`, `head_sha`, `head_repository.full_name`: NOT documented on that page. The events-that-trigger-workflows page mentions only that a run triggers regardless of the previous conclusion. (REST "workflow runs" schema was not opened.)
- `branches` filter: "specify what branches the triggering workflow must run on". Fork same-name branch handling: not documented.
- Default branch and secrets: documented. "This event will only trigger a workflow run if the workflow file exists on the default branch." `GITHUB_REF` is the default branch. The triggered workflow "is able to access secrets and write tokens, even if the previous workflow was not."

## 5. pull_request from a fork
- Which workflow file: the `pull_request` section does not say. The page contrasts `pull_request_target`, which "runs in the context of the default branch of the base repository, rather than in the context of the merge commit, as the `pull_request` event does."
- Token: "The `GITHUB_TOKEN` has read-only permissions in pull requests from forked repositories." "secrets are not passed to the runner when a workflow is triggered from a forked repository" (except `GITHUB_TOKEN`).
- Artifact upload with that token: not documented on the pages read.
- Approval: documented. "a maintainer with write access may need to approve running workflows on the pull request" for a first-time contributor to a public repo. The approve-runs-from-forks page says fork runs "may require manual approval", configurable at repository/org/enterprise level; it does not describe the first-time-contributor setting names, nor the workflow file used.

## 6. gh run list --event
Documented: `-e, --event <event>`, "Filter runs by which event triggered the run." The manual lists no accepted values. Other flags: -a, -b, -c, --created, -q, --json, -L (default 20), -s, -t, -u, -w, -R.

## Not found
- npm ecosystem with no manifest present.
- Default for major updates; fork same-name branch filtering; workflow_run nested payload fields; which workflow file runs for fork pull_request; artifact upload under read-only token; gh run list --event value list.
