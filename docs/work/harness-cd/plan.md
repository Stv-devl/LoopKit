# Plan: CD templates hardening   (entry: docs/specs/harness-cd.md · research: docs/work/harness-cd/research.md · design: n/a)
Token profile: critical

## Skips
- INTERFACE: SKIP, no screen.
- DB, backend, front, wiring: SKIP, kit templates and shell contracts only.
- C4 (AWS S3 + CloudFront): SKIP, dropped by DC2 (the user deploys on Lightsail, covered by the SSH target).
- DC1: done in research, `docs/research-cache/github-actions.md`.
- Test-first layers: none exist here (`utils`, `mapper`, `repository`, `services`). The contracts are written before the change anyway, and each is seen failing.

## Write chain (sequential)
0. On the gate's answer to open question 3: if taken, amend `docs/specs/harness-cd.md` C1 with the same `if:` line and `head_branch` wording, and record the amendment in `## Gate`.
1. Contracts first: append the `HC` block to `.claude/hooks/test-workflow-contracts.sh` and the `I4` block to `.claude/hooks/test-install.sh`, each after the file's last case and before its final `echo`. Both are guarded paths, so each edit asks the user: make one Edit per file. Run both suites: each must fail on its first new case. `set -euo pipefail` stops at the first failure, so fixing one item exposes the next, and every group is seen red in turn. Record each first failure in the plan's `## Gate`.
2. C1: `templates/github/deploy.yml` `if:`, `--event=push`, comment `:58-61`. Contracts `HC1*` turn green, `HC3a` is the next red.
3. C3: `templates/github/publish/ssh.yml`. `HC3*` green, `HC2a` next red.
4. C2: pin the 13 `uses:` lines from the cache, pin the two CLIs, create `templates/github/dependabot.yml`, add the `copy_file` in `install.sh`. `HC2*` and `I4*` green, `HC4` next red.
5. Docs: `.claude/skills/templates/ci.md`, `docs/ADAPTATION.md`, until `HC4` is green. Then run `python3 .claude/hooks/kit-doctor.py` at the kit root, which no suite does locally, and on one target per `--deploy` value; each must report no divergence.
6. One-off proof, not shipped: a scratch script compares each pinned SHA in `templates/github/` with `git ls-remote` for its tag (peeled with `^{}` for an annotated tag). Result recorded in `## Gate`.
7. Mutation proof, on a scratch copy of the repo, never in the tree: apply each mutation of the Test plan on a fresh copy, run the owning suite with `bash -x`, and record in `## Gate` the last command before the failure. It must be the check of the named case: a suite red for another reason proves nothing. Each leg of a case has its own mutation.

**Shape of a negative check.** Under `set -euo pipefail`, `! grep …` and the left side of `a && b` do not stop the script. Every negative check uses `if grep …; then exit 1; fi`, as the file already does.

## Parallel lots (inside this track, same tree)
none, fully sequential.

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: none. `install.sh`, `test-install.sh` and `test-workflow-contracts.sh` take appends that `harness-hooks` and `harness-kit-ci` also touch, so they run after this pass or rebase.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `templates/github/deploy.yml` | Edit | C1 |
| `templates/github/ci.yml` | Edit | C2, 4 `uses:` |
| `templates/github/publish/ghcr.yml` | Edit | C2, 3 `uses:` |
| `templates/github/publish/pages.yml` | Edit | C2, 2 `uses:` |
| `templates/github/publish/netlify.yml` | Edit | C2, CLI pin |
| `templates/github/publish/vercel.yml` | Edit | C2, CLI pin |
| `templates/github/publish/ssh.yml` | Edit | C3 |
| `templates/github/dependabot.yml` | Create | C2 |
| `install.sh` | Edit | C2, one `copy_file` |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | `HC` contracts |
| `.claude/hooks/test-install.sh` | Edit | `I4` cases |
| `.claude/skills/templates/ci.md` | Edit | Property 1, SSH secret |
| `docs/ADAPTATION.md` | Edit | Deploy section |
| `docs/specs/harness-cd.md` | Edit | C1 literal, if open question 3 is taken |

## Contracts
**C1, `deploy.yml`.** Lines `:62-64` (`if: >-` and its two continuation lines) become this one line, 4 spaces of indentation:

```
    if: github.event_name == 'workflow_dispatch' || (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_repository.full_name == github.repository && github.event.workflow_run.head_branch == github.event.repository.default_branch)
```

The `head_branch` arm is new against the spec's literal: without it, a push to `master` on a repository whose default branch is `main` deploys (`deploy.yml:37`, `ci.yml:19-21`), which contradicts the Objective. It is decided at the gate, open question 3; on `go` the spec's literal is amended the same way.

`:105` becomes, at 12 spaces like the file:

```
            read -r id sha < <(gh run list --workflow=CI --branch="$DEFAULT_BRANCH" --event=push \
```

The comment `:58-61` (French, like the file) states: `workflow_run` leaves only on a green CI run from a push to the default branch of this repository; a fork's run is refused because a fork controls its own `ci.yml`; dispatch applies the same filter in the Resolve step. The comments `deploy.yml:10-13` and `:98` say the same.

**C2.** Each `uses:` line takes the SHA and tag of the cache table, `owner/action@<sha> # vX.Y.Z`, keeping its `- ` and indentation. `pnpm dlx netlify-cli@27.16.1 deploy …`, `pnpm dlx vercel@65.9.0 deploy …`.

`templates/github/dependabot.yml`, exactly:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
```

`install.sh`, in the `else` branch, right after the `ci.yml` `copy_file` at `:637` (so `.github/` already exists whatever `copy_file` does about folders):

```
    copy_file "$KIT_DIR/templates/github/dependabot.yml" "$TARGET/.github/dependabot.yml"
```

**C3, `ssh.yml`** (comments in French, like the file).
- Header `:8-10` is replaced: the host key is pinned, `DEPLOY_KNOWN_HOSTS` holds it, `StrictHostKeyChecking=yes` refuses any other key; obtain it once with `ssh-keyscan` and check it out of band (on Lightsail, against the key shown in the browser SSH console); a replaced instance changes its key, and the deploy then refuses until the secret is updated.
- The same header and the `DEPLOY_HOST` line of the secret list say: `DEPLOY_HOST` holds a static IP or a stable name. A `known_hosts` entry is tied to that value, so a Lightsail instance on its default IP changes address on a stop and start, and the deploy refuses even though the key did not change.
- Secret list gains `#   secret  DEPLOY_KNOWN_HOSTS  (sortie de ssh-keyscan, vérifiée hors bande)`.
- `env:` gains `DEPLOY_KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}`.
- After the `DEPLOY_PATH` guard: `: "${DEPLOY_KNOWN_HOSTS:?secret DEPLOY_KNOWN_HOSTS manquant — refus de deployer sans cle d hote}"`.
- After `chmod 600 ~/.ssh/deploy_key`: `printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > ~/.ssh/known_hosts` and `chmod 600 ~/.ssh/known_hosts`.
- `:53`, at 12 spaces like the file: `-e "ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=yes" \`.

**Docs.**
- `ci.md:194-198`, property 1: the run must be a green run "from a push to the default branch of this same repository", on both paths. Wrap the file so that `same repository` stays on one line.
- `ci.md`, a new sentence after the fragment paragraph at `:184` (there is no `ssh` row): `DEPLOY_KNOWN_HOSTS` is required.
- `docs/ADAPTATION.md:244-262`: the SSH target needs `DEPLOY_KNOWN_HOSTS` and a `DEPLOY_HOST` on a static IP or stable name; an existing target must merge `deploy.yml.new`; dependabot arrives with the CI.

## Test plan (gate — validated by the user before EXECUTE)
No test-first layer exists here, so these cases carry labels, not `U/M/R/B` ids. This plan corrects a defect: `HC1a` reproduces it and comes first. Its bug: a run from a fork's `main` satisfies today's `if:`.

Each case names the mutation that must turn it red. The mutations run on a scratch copy (write chain step 7).

### `.claude/hooks/test-workflow-contracts.sh`, block `# HC harness-cd`
**Reproduction**
- [ ] HC1a `deploy.yml` holds the exact `if:` line above, by `grep -Fxq`. Mutations: drop `head_repository`; drop `event == 'push'`; drop `conclusion`; drop `head_branch`; drop the dispatch arm; add a `|| true` arm on the line.

**Core behaviour**
- [ ] HC1b `deploy.yml` holds exactly one job-level `if:` (`grep -c '^    if:'` = 1), no `>-` anywhere, and the first non-blank line after it has at most 4 spaces of indentation, since YAML folds a deeper line into the expression. Mutations: `      || true` on the next line; a blank line, then `      || true`; the two old continuation lines kept; a second `    if:` line; a `>-` added.
- [ ] HC1c the `gh run list` line, `:105`, holds `--event=push`, by exact line at 12 spaces. Mutation: remove the flag.
- [ ] HC3a `ssh.yml` holds no `accept-new` and no `StrictHostKeyChecking=no`, comments included. Mutations: restore the `:8` comment; `StrictHostKeyChecking=no` on the rsync line.
- [ ] HC3b the `-e "ssh …"` line holds `StrictHostKeyChecking=yes`, by exact line at 12 spaces. Mutation: move the option to a comment.
- [ ] HC3c `DEPLOY_KNOWN_HOSTS:?` and the `> ~/.ssh/known_hosts` write are present, and the guard's line number is lower than the write's, itself lower than that of `rsync -az`. Mutations: remove the guard; move the write after `rsync -az`.
- [ ] HC3d `env:` holds `DEPLOY_KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}`, the header's secret list names it, the `DEPLOY_HOST` line of that list says static IP or stable name (`statique`), and no line after `run:` holds `${{`. Mutations: remove the `env:` line; remove it from the secret list; remove `statique`; put `${{ secrets.DEPLOY_KNOWN_HOSTS }}` in the command.
- [ ] HC2a every line matching `^\s*(- )?uses:` under `templates/github/`, recursively, matches `@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$`. The list must be non-empty, and the check must survive `grep -v` finding nothing under `set -euo pipefail`. Mutations: one line back to `@v4`; one SHA of 39 characters; one comment removed.
- [ ] HC2b those same anchored lines number 13, so a removed or commented line fails (`= 13`). Mutations: delete a `uses:` line; prefix one with `# `.
- [ ] HC2c every line under `templates/github/` matching `pnpm dlx (netlify-cli|vercel)` also matches `pnpm dlx (netlify-cli|vercel)@[0-9]+\.[0-9]+\.[0-9]+ `, and both CLIs appear. Mutations: remove the version from either; add `pnpm dlx vercel@latest pull`; a bare `pnpm dlx vercel` at end of line; delete the netlify line.
- [ ] HC2d `dependabot.yml` holds `package-ecosystem: github-actions`, `package-ecosystem: npm`, `directory: "/"` and `interval: weekly`, and no `ignore`. Mutations: remove each entry; add an `ignore:` key.
- [ ] HC4 `ci.md` holds `DEPLOY_KNOWN_HOSTS`, and property 1 holds `push` and `same repository`; `docs/ADAPTATION.md` holds `DEPLOY_KNOWN_HOSTS`, `statique`, `deploy.yml.new` and `dependabot`; the comment above the `if:` in `deploy.yml` holds `push` and `fork`; the comments at `:10-13` and `:98` each hold `push`. Mutation: remove each.

### `.claude/hooks/test-install.sh`, block `# I4 harness-cd`
**Core behaviour**
- [ ] I4a `install.sh <t> --deploy=none` installs `.github/dependabot.yml`, byte-identical to the template. Mutation: remove the `copy_file`.
- [ ] I4b `install.sh <t> --no-ci` installs no `.github/dependabot.yml`. Mutation: move the `copy_file` above the `if $NO_CI`.
- [ ] I4c for each target in `templates/github/publish/*.yml`, `none` included, `install.sh <t> --deploy=<target>` on a fresh `mktemp -d` per target (`copy_file` would otherwise keep the first `deploy.yml`) writes a `deploy.yml` that holds the exact `if:` line and whose `uses:` lines all match the pin regex. Mutation: an unpinned `uses:` in `publish/pages.yml`, then in `publish/ghcr.yml`.
- [ ] I4d `--deploy=ssh` writes a `deploy.yml` holding `DEPLOY_KNOWN_HOSTS:?` and `StrictHostKeyChecking=yes`. Mutation: remove the guard from the fragment.

**Edge cases**
- [ ] I4e a second install on the same target keeps `.github/dependabot.yml` and writes `.github/dependabot.yml.new`. Mutation: `cp` in place of `copy_file`.

## Vigilance (carried from research)
- All three lines `deploy.yml:62-64` go. A kept continuation line still parses: YAML folds it into the expression (`research.md` wrongly says it breaks the YAML), so `|| true` on the next line opens the guard for every run. HC1b holds that.
- Without the dispatch arm the job skips on dispatch; without `conclusion` a red run deploys.
- The new `if:` reads `event`, `head_repository.full_name`, `head_branch` and `repository.default_branch` from the `workflow_run` context. The published webhook schema `@octokit/openapi-webhooks-types` 12.2.0 lists all four, and the first three are on a real REST run object (measured). If one were absent, the comparison would be false and the job would skip with no error, so nothing would deploy. Only a first real deploy shows this: say so at ship, and name that check.
- The `uses:` check fails on zero lines, and does not abort early under `set -euo pipefail`.
- `pnpm/action-setup` is pinned to the peeled commit `fc06bc1…`, not the tag object `a15d269…`. v4.4.0 is one commit past floating `v4`.
- `DEPLOY_KNOWN_HOSTS:?` stops every SSH deploy until the secret exists: header, `ADAPTATION.md`, and `env:`, never `${{ }}` in the command.
- `accept-new` leaves both `:8` and `:53`.
- `netlify-cli` 27 needs Node `>=22.13.0`, which `node-version: '22'` satisfies while unpinned.
- `--deploy=none` writes a `deploy.yml` whose snippet is `exit 1`: the install cases read files, they do not treat it as a working deploy.
- `kit-ci` is red on this branch for an unrelated reason (`test-hooks.sh:420-425`); a local green is not a CI green. Run `test-hooks.sh` with and without an inherited `trap '' PIPE` and report both.
- The ship commit stays local: `65facf8` is not pushed before the user's review, and a PR needs its own base.
- Nothing proves C1 end to end: neither a fork run nor a legitimate push deploy is driven on GitHub, the proof is the contract plus the review. Say so at ship.

## Open questions, with the answer proposed for the gate
1. Dependabot `npm` on a target with no `package.json` (behaviour undocumented). Proposed: keep the entry, as the spec says, and accept a possible failed job on a Python-only target; the kit assumes a React front. Decides HC2d.
2. Major-version dependabot PRs (default undocumented). Proposed: no `ignore` key, since the spec routes majors through dependabot. Decides HC2d's `no ignore` leg.
3. A push to `master` when `main` is the default branch deploys, against the Objective; the spec's literal `if:` has no branch arm. Proposed: add the `head_branch == default_branch` arm and amend the spec's literal. Its cost: a repository whose default branch is not its release branch (default `develop`, production `main`) stops deploying, with no error. It needs the user's go since it changes the contract. Decides HC1a.

## Acceptance criteria (carried from the entry artifact)
- [ ] A deploy runs only from a push to `main` of this repository, with pinned actions and CLIs, and an SSH target whose host key is known in advance. Each item is held by a contract in `test-workflow-contracts.sh`, not by reading: the contract catches a regression on the forms it names, not every edit of these files (amended 2026-11-01, see `## Gate`).
- [ ] C1–C3 contracts green in `test-workflow-contracts.sh`; `test-install.sh` green; `kit-doctor.py` no divergence.

## Plan critic
- pass 1: completeness 84, quality 76, 4 Majors survived the verifier (fixed above).
- completeness: 94
- quality: 93
- surviving blockers: none (pass 2; its 6 Minors closed above)

## Gate
- 2026-11-01 go
- Contract: as written, Lightsail confirmed as an instance through the SSH target, plus the amendment taken on open question 3 (`head_branch` arm in the C1 literal).
- Dependabot `npm` with no manifest → keep the entry.
- Major-version dependabot PRs → no `ignore` key.
- Push to the non-default branch deploying → add `head_branch == default_branch`, spec amended.
- 2026-11-01 first reds, before any template change: `test-workflow-contracts.sh` stops on HC1a's `grep -Fxq` (rc 1); `test-install.sh` stops on I4a's `cmp -s` (rc 2, no such file). Blocks landed: `HC` and `I4`.
- 2026-11-01 execute steps 2–5 complete: C1 advanced contracts to HC3; C3
  advanced them to HC2; C2 advanced them to HC4; docs made the contract suite
  green. Final deterministic results: `test-workflow-contracts.sh` green,
  `test-install.sh` green, and `python3 .claude/hooks/kit-doctor.py` exit 0
  (`No divergence`; existing FILL markers informational). Steps 6–7 remain
  reserved for Claude as stated in the handoff.
- 2026-11-01 step 6, by a verifier: all 13 `uses:` lines match `git ls-remote` for their tag, peeled for `pnpm/action-setup`; both CLI versions exist.
- 2026-11-01 step 7, by a verifier: both suites green on a clean copy; all 54 mutations red on their named check. `kit-doctor.py` no divergence at the root and on all 6 assembled targets. Traces: session scratchpad `mutation-cd/run1/`. Unlisted mutations that stay green, and the missing `deploy.yml.new` sentence, go to review.
- 2026-11-01 review 1/3 FAIL, nothing refuted by the verifiers. Critical on the "proved by a contract" criterion: no contract ties `DEPLOY_KNOWN_HOSTS` to `known_hosts`. Majors in scope: netlify step cannot run; a tag named `main` passes both paths; `--status=success` unprotected; other CLI call forms; merge sentence. Pre-existing, outside C1-C3: `concurrency` at workflow level, ghcr uppercase, repository-level secrets, dispatch from another ref. Ready patches: session scratchpad `verify-cd-tests/tools/`.
- 2026-11-01 user's decisions on that review, spec amended (the Objective is unchanged): netlify form `pnpm --package=netlify-cli@27.16.1 dlx netlify`; Resolve refuses a commit not on the default branch; dependabot `npm` ignores majors, which replaces the gate's "no `ignore` key" for that entry only; docs carry the environment branch rule and environment secrets; `concurrency`, ghcr, doctor and CLI transitives recorded in `harness-hardening.md`. Fix batch to `implementer`, not Codex: it touches guarded test files whose prompts Codex would not get.
- amended 2026-11-01 HC2c: every active `pnpm … dlx` call is one of the two pinned forms, and no other launcher appears. amended HC2d: `dependabot.yml` is byte-identical to the literal in the suite. amended HC3c, HC3d, HC4, HC1b, I4c, I4d: stricter checks of the review. New: HC1d `--status=success --limit=1` exact line; HC1e the Resolve check; HC3e `known_hosts` receives the secret by exact line and two body lines only; HC3f allow-list on `StrictHostKeyChecking`. The user confirms these at the merge.
- 2026-11-01 review 2/3 FAIL on the contracts, the shipped templates hold (Resolve measured on a public repository: `identical`, `ahead`, `behind`, `diverged`, `refs/heads/<tag>` 404). A scan replacing the `chmod` line stays green; the Resolve check can sit in a dispatch-only branch. Decision: stop adding greps, each pass finds a neighbouring spelling. HC1e and HC3c-f become one check each: the whole Resolve `run:` body and the whole SSH `run:` body compared byte for byte with a literal in the suite. A deliberate edit of these two bodies then edits the literal too, which is the intended friction. Docs Majors: the snippets name repository secrets while the docs require environment secrets, and `ghcr` has no secret for the environment to withhold.
- 2026-11-01 review 3/3 FAIL, ceiling reached, no fourth cycle without the user. No Critical; the staged templates hold, all three Majors are regressions the suite lets through. Reproduced by the main thread on index copies (session scratchpad `refute/refute.py`): M1 `DEFAULT_BRANCH: ${{ github.ref_name }}` on Resolve stays green; M2 `cd_run_body` takes the first same-name step, so a dead `Publish` holding the literal followed by a real one without the pinned key stays green; M3 the HC2c launcher leg misses `npm --prefix sub install vercel`, `yarn --cwd x dlx vercel`, `yarn -q dlx vercel`, and a ` #` inside quotes hides `npx`. Minors and the mutation table: the reviewer's report, tools in session scratchpad `rr/tools/`. Docs checked against docs.github.com by the reviewer: true, except that nothing says to create the environment and private Free has no stated path. Both suites rc 0 under `LC_ALL=C` and inherited ignored SIGPIPE.
- 2026-11-01 the user's decision at the ceiling: ship with the criterion narrowed, no fourth cycle. The Objective and the acceptance criterion now read "held by a contract ... on the forms it names", and M1-M3 with the Minors are recorded in `harness-hardening.md`, Open follow-ups. The amendment re-enters no phase: no template, contract or test changes, by that decision. `review` stays at 3 in `attempts.json`.
- 2026-11-01 ship: `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` rc 0; `test-hooks.sh` green plain, 1 failure of 800 under an inherited ignored SIGPIPE (the known `harness-kit-ci` one). The `pnpm` gates do not exist in this kit. `/audit:security` `supply-chain` (surface chosen by the main thread, the ship table has no deploy row): 0 Critical, 2 Major, 8 Minor, recorded in `harness-hardening.md`, no verifier pass since neither Major stops the ship.
