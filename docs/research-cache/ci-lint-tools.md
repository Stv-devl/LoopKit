---
topic: ci-lint-tools
checked: 2026-11-07
stability: volatile
sources:
  - https://api.github.com/repos/rhysd/actionlint/releases/latest
  - https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_checksums.txt
  - https://raw.githubusercontent.com/rhysd/actionlint/main/docs/install.md
  - https://raw.githubusercontent.com/rhysd/actionlint/main/docs/usage.md
  - https://pypi.org/pypi/ruff/json
  - https://api.github.com/repos/koalaman/shellcheck/releases/latest
  - https://raw.githubusercontent.com/actions/runner-images/main/images/ubuntu/Ubuntu2404-Readme.md
  - https://docs.github.com/en/rest/repos/rules?apiVersion=2022-11-28#get-rules-for-a-branch
  - https://registry.npmjs.org/lefthook/latest
  - (web searches only, snippets not pages: CODEOWNERS, ruff defaults, runner-images ubuntu26, lefthook, ruff-action)
---

## 1. actionlint
- Latest: v1.7.12 (published 2026-03-30).
- Tarball: https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz
- sha256 (from actionlint_1.7.12_checksums.txt): `8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8`
- install.md: the download script (`bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)`, 1st arg = version, 2nd = target dir) is "a recommended way ... in some shell script"; usage.md says for GitHub Actions "Preparing actionlint executable with the download script is recommended". The script fetches from main (unpinned script); a pinned tarball plus sha256 check is the stricter alternative (our inference, not an official statement).
- shellcheck: usage.md: "If you want to enable shellcheck integration, install shellcheck command" and "shellcheck is pre-installed on Ubuntu worker". `-shellcheck` flag = path to executable; empty string disables it. Whether it is silently skipped when absent is NOT stated in the docs read.

## 2. ruff
- Latest on PyPI: 0.17.4 (upload date not read).
- Install: `pipx install ruff==X` / `pip install ruff==X` not verified against docs (model knowledge). `astral-sh/ruff-action`: v4.0.0 exists (immutable releases, node24), per a Renovate PR snippet from search; latest v4.x tag and commit SHA NOT obtained (no git ls-remote available).
- Default rules: through 0.15.x `select = ["E4","E7","E9","F"]`. Per search snippets (pydevtools, byteiota; docs.astral.sh/ruff/default-rules not opened), ruff 0.16.0 enlarged the default set (~59 to ~413 rules). 0.17.4 therefore lints with the larger set when no config exists. Pin an explicit `select` to be stable.

## 3. shellcheck
- Latest: v0.11.0 (2025-08-04).
- https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.gz sha256 `b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6` (GitHub asset digest field). The .tar.xz sha256 is `8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198`.
- ubuntu-24.04 image 20261101.360.1: apt package ShellCheck 0.9.0-1 (read from Ubuntu2404-Readme.md).
- ubuntu 26.04: only an arm64 image note (20260604.22.1, via a newreleases.io mirror snippet) lists shellcheck 0.11.0-2. The x64 26.04 value was not read. Spec claim 0.9.0 (24.04) confirmed; 0.11.0 (26.04) plausible, only arm64 seen.

## 4. GitHub REST
- `GET /repos/{o}/{r}/rules/branches/{branch}`: docs list only 200, "Array of Repository Rule objects", "all active rules that apply"; branch need not exist; evaluate/disabled rulesets excluded. Empty-array vs 404 for no rulesets and the token scope are NOT stated on the page: empty array 200 is the likely behaviour (inference).
- `GET .../branches/{branch}/protection`: docs list 404 "Resource not found" (search snippet). The "Branch not protected" message and a 403 on private free-plan repos were NOT confirmed. `gh api` exit code: model knowledge, not checked (non-2xx gives exit 1).

## 5. CODEOWNERS
- Locations: `.github/`, repo root, `docs/`; first found in that order wins; the file must be on the PR's base branch (GitHub docs, via search snippet).
- Enforcement: docs describe "Require review from Code Owners" in branch protection. The ruleset wording ("Require review from Code Owners" in the pull-request rule) is secondary-source only.

## 6. lefthook
- Latest npm: 2.2.2, bin `lefthook`, `postinstall: node postinstall.js` (no `engines`).
- Install for pnpm: `pnpm add -D lefthook` then `pnpm exec lefthook install` (npm route confirmed by a snippet, pnpm form model knowledge). pnpm 10 blocks dependency postinstall scripts unless allowed (`onlyBuiltDependencies`), model knowledge, not checked.
- Config: `pre-push:` with `commands: <name>: run: <cmd>`. `parallel` default NOT settled: sources conflict, official page 404'd on the guessed URL. Set `parallel: false` explicitly for sequential.

## Measured by the main thread (2026-11-07)
- `git ls-remote --tags https://github.com/astral-sh/ruff-action.git`: latest v4.1.0 → `278981a28ce3188b1e39527901f38254bf3aac89` (lightweight tag, no `^{}`); v4.0.0 → `0ce1b0bf8b818ef400413f810f8a11cdbda0034b`.
- `gh api repos/Stv-devl/LoopKit/rules/branches/main` (public repo, one repo ruleset): 200, array of 3 rules (`deletion`, `non_fast_forward`, `pull_request`), exit 0. Same call on a branch with no rule: `[]`, exit 0.
- `gh api repos/Stv-devl/LoopKit/branches/<any>/protection` with the user's token: HTTP 403 "Resource not accessible by personal access token", exit 1 — the classic-protection read needs admin rights the token lacks. A 403 means "unknown", never "unprotected".
- ruff 0.17.4 `ruff-x86_64-unknown-linux-gnu.tar.gz` sha256 (release `.sha256` file): `3ab2b34aeacdbc1ea5c529cdbda3e05792633d587228123fd09f3b5a0facb27a`. `action.yml` at `278981a…` declares the inputs `args`, `src`, `version`, `checksum` (read 2026-11-07).
- `actions/checkout` v4.4.0 → `11d5960a326750d5838078e36cf38b85af677262` (`git ls-remote`).
- shellcheck and actionlint tarballs downloaded 2026-11-07: both `sha256sum -c` OK against the digests above.

## Not found
- ruff 0.17.4 upload date.
- Classic protection 404 body on an unprotected branch with an admin token.
- lefthook `parallel` default and ordering of commands in sequence.
- Ubuntu 26.04 x64 shellcheck version.
