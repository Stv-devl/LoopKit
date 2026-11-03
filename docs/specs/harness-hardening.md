# Spec index: Harness hardening
Source: harness audit of 2026-10-27; prompt audit, review and refutation of 2026-10-29 (3 reviewers, 3 verifiers). The single spec was not plannable as written: its baseline no longer matched the code, and its Phase 4 opened holes. It is split into four specs, each a loop pass of its own.

| Spec | Profile | Needs |
| --- | --- | --- |
| `docs/specs/harness-hooks.md` | critical | `65facf8` in the branch; no push before the user's review of `readable_git_dir` |
| `docs/specs/harness-prompts.md` | critical | `65facf8`; the parts of `harness-hooks` A0, A2 and A4 named in its header |
| `docs/specs/harness-cd.md` | critical | — |
| `docs/specs/harness-kit-ci.md` | standard | K2 only: `harness-cd` DC1 (cached SHAs) |

Real constraints: `harness-prompts` after `harness-hooks`; `harness-kit-ci` K2 after `harness-cd` DC1. `harness-cd` may run first, and its C1 hole argues for it. Recommended order: `harness-cd` → `harness-hooks` → `harness-prompts` → `harness-kit-ci`.

Third review and refutation on 2026-11-01 (3 reviewers, 1 verifier), corrected in place in all four specs. The follow-ups below that it folded in are marked "→".

Second review and refutation on 2026-10-30 (3 reviewers, 3 verifiers), corrected in place:
- `harness-hooks`:
  - A0 is new: the install hold-back.
  - A2 now covers `--refmap`, `branch -M/-C`, globs, `clone -u` and restores of frozen tests.
  - A4 now covers targets outside the project, the resolution base, tsc and configs.
  - A6 is rewritten: glob expansion and the grep wrapper.
  - A7 gets a new resolver; `SECRET_RE` is left untouched.
- `harness-prompts`: tsc, playwright and suite forms, the `uv` allows moved to the addon, a static measure, and `HP-` contract labels.
- `harness-cd`: the dispatch path and exact contracts.
- `harness-kit-ci`: one proof per K1 branch, `kit` no longer required in targets, and a named `--lefthook` option.

## Open follow-ups
Folded on 2026-11-01: `sed`/`rg` → `harness-hooks` A4; `git log --output=.git/…` → A3; the worktree re-check → A2 and `harness-prompts` B2; `LC_ALL=C`, `--git-dir`/`--work-tree` and the truncation marker → A2. Still open and undecided: the premise of `readable_git_dir`, `mv`/`cp -r`/`mkdir -p` into `x/.git`, `git status`/`git diff` running a planted repository's config.

- From `harness-hooks` A6 (2026-11-02): the Bash tool's `grep` function also falls back to the real grep on `-z`, `--null-data`, `--config`, `--pager`, `--view`, `--filter`, `--format-open`, `--save-config`, `---*` and `-@*` (read with `type grep` on 2.1.316, `docs/research-cache/claude-code-permissions.md` 7b). A6 asks on `-Z`/`--null` and the wrapper bypasses only, as the spec says; a recursive grep with those other forms gets no verdict. Extending the rows was declined during EXECUTE: it is the user's call.
- From `harness-hooks` A2 (2026-11-02, plan Q11): a wrapped or unparsable git call (`timeout 5 git clean -fdx`, a destructive call beside a heredoc shlex cannot read) becomes `?unread`/`UNPARSABLE`, which `fallback_rows` does not read for the destructive rules: it stays no verdict. Fixing it means rewriting `fallback_rows`; the spec targets a mistaken agent, not a hostile one.
- From the `harness-cd` review (2026-11-01), pre-existing, confirmed by a verifier, not fixed there:
  - `templates/github/deploy.yml` `concurrency` is at workflow level: a run the job `if:` refuses (a red run, a fork PR's run from a branch named `main`) still takes the pending slot and cancels a legitimate deploy. Fix tried on a copy: move the block under the job; the fix itself rests on a third-party probe.
  - `publish/ghcr.yml` tag uses `github.repository` as is, so an owner or repository with an uppercase letter (`Stv-devl`) gives an invalid reference. Fix tried on a copy: a step lowercasing `${REPO,,}`.
  - `/kit:doctor` stays green on a target whose `deploy.yml` predates the fix and whose `.new` was never merged (measured).
  - `pnpm dlx` resolves the CLIs' transitive dependencies at deploy time with the token in the environment; neither CLI publishes a shrinkwrap. A lockfile-backed manifest would fix this and the hand-bumped pins.
- From the `harness-cd` re-review 3/3 (2026-11-01), accepted by the user to ship, not fixed; the staged templates hold, these are regressions the contracts let through. Reproduced on index copies:
  - `test-workflow-contracts.sh` pins the `run:` body, not the step: `DEFAULT_BRANCH: ${{ github.ref_name }}` on Resolve stays green. Also green, by the reviewer's mutations: a step before Resolve or `Publish` (a fake `gh` on `GITHUB_PATH`, a `~/.ssh/config`), `id: run` moved, `if: false` or `continue-on-error` on `Publish`, the `environment:` block removed.
  - `cd_run_body` takes the first step of that name and never counts them: a dead `Publish` holding the literal, then a real one without the pinned key, stays green. `test-install.sh:305-307` has no whole-body check on the assembled file. Fix proposed: compare the whole step, require each name once.
  - HC2c's launcher leg is a deny-list: `npm --prefix sub install vercel`, `yarn --cwd x dlx vercel`, `yarn -q dlx vercel` stay green, and the comment stripper cuts at a ` #` inside quotes, hiding `npx`. Not named by the spec, also green: `npm add`, `pnpm install vercel`, `pnpm -C sub add`, `bun x`, `deno run`. Fix proposed: an allow-list of commands.
  - Minors: the `grep -vE | grep -Fq` at `test-workflow-contracts.sh:612` misses from about 128 KB of active lines; doc needles at `:658`, `:663` are satisfied by the plan-limits sentences; HC2c false-reds on a step name or heredoc naming a launcher, and on any file added under `templates/github/`.
  - Docs: nothing says to create the `production` environment, and GitHub creates a missing one with no rules or secrets, so a repository that kept repository-level secrets, or `ghcr`, deploys ungated; private Free has no stated path while `ssh.yml:38-39`, `netlify.yml`, `vercel.yml` say "not the repository page"; `ssh.yml:10-15` names a command that prints only the fingerprint, while the secret needs the raw `ssh-keyscan` line. Unverified: whether the default admin bypass covers a branch rule; whether a job naming `environment:` on private Free still reads repository secrets.
- From the `harness-cd` `/audit:security` `supply-chain` (2026-11-01), 0 Critical, not fixed there, read and not driven, no verifier pass:
  - Major, pre-existing since `1365a28`: `templates/github/deploy.yml` restores the pnpm store CI writes (`cache: pnpm`). A compromised dependency in the secretless push CI can plant a `netlify-cli` or `vercel` entry on a new lockfile key; `pnpm dlx` at `Publish` may then take it, with the account token in its environment. The deploy installs nothing, so the cache brings no benefit. Fix proposed: remove that line. The lockfile-backed manifest above would not close this.
  - Major, `pages` target only: `upload-pages-artifact` v3.0.1 is composite and calls `actions/upload-artifact@v4`, a floating tag, in a job holding `pages: write` and `id-token: write`. `v4` is on the pinned commit today. Fix proposed: v4.0.0, which pins by SHA, but it excludes dotfiles from the tar and departs from "latest within the major": the user's decision.
  - Minor: pnpm 9 or older has no `dlx` script policy, so transitive lifecycle scripts may run with the token and nothing enforces a floor; `actions/checkout` keeps its default credential persistence, reaching a compromised CLI and, on `ghcr`, the build context; no `--ignore-scripts` in CI; `.perms` land at workflow level, and pnpm is set up for targets that do not use it; a committed `.vercel/output/` is published beside `dist/`; a re-run of an older green run may redeploy it (`ahead` passes); `FROM nginx:alpine` undigested with no `docker` dependabot entry; `ssh.yml` root guard passes `//` and `/./`; no security headers in the SPA fragments; the kit's own `kit-ci.yml:14` is unpinned.
- From `git-allow-grammar` (OQ4, plan pass of 2026-10-31): `sed -n -f`, `sed -n --expr='1e …'` and `rg --hostname-bin` run a file or a command with no decision from either hook. Fix: `shell_targets.py` asks on them, or the `Bash(sed -n *)`/`Bash(rg *)` allows narrow. Not a regression: both allows are in HEAD since `1365a28`.
- From `git-allow-grammar` review (2026-10-31), for `harness-hooks` A3: `git log --output=.git/refs/heads/main` and `--output=.git/config` run with no prompt (`git log *` allowed, `.git/` outside the shell guard lists, while `protect-files.sh` denies Write there). Measured: `main` moved with no reflog entry, a replaced config ran a script on the next `git status`. With P1's free commit, a feature commit can land on `main` this way, no prompt until the push. Pre-existing in HEAD. Fix measured on a copy: `'.git/*'` in `CWK_GUARD_DENIED` plus a general deny text; `rm -rf .git` then goes from ask to deny.
- From the same review, re-check before running: the grammar asks last on any call naming `git` and `add`, so `harness-hooks` A2 (`:95`, fixture `pass` for `git worktree add .claude/worktrees/x -b feat/x`; `:239`) cannot go green, and the `harness-prompts` allow `Bash(git worktree add .claude/worktrees/*)` (`:52`) removes no prompt, a hook ask overrides an allow. Frozen G14.70 pins the ask. Line citations of `enforce-git-workflow.sh` in `harness-hooks` (`:67`, `:191`) moved too.
- Accepted limits of the same review: a `.gitignore` edit in an earlier call makes a later strict add of the once-ignored file pass (same power as Write under `acceptEdits`, the secret list holds); `git add <tracked dir removed from disk>` passes; `is_secret` is case-sensitive and reads the basename.
- From the re-review of the same pass (2026-10-31), the hook-timeout fail-open that `docs/work/light-permissions-git/prior-gate.md:13` says was carried here and never was: `enforce-git-workflow.sh` scans `\bgit\b[^|;&]*\bcommit\b` and `\bgh\b[^|;&]*\bcomment\b` are quadratic under a UTF-8 locale (60 KB: 5.4 s, 0.002 s under `LC_ALL=C`), so past about 55 KB the hook is killed at its 5 s timeout with no decision. Measured on 2.1.316: a timed-out hook does not block (a stand-in hook sleeping 12 s let `git add -f ignored.txt` run with no prompt), and the shipped config is saved only by the matcher, which refuses over 10000 characters before an allow applies, an undocumented constant (a padded call prompts, or is denied in `-p`). It degrades a deny to a generic prompt today, and staged with no prompt under `--dangerously-skip-permissions` or a whole-tool `Bash` allow. A later Claude Code raising that limit reopens it. Fix: `LC_ALL=C` on both scans (speed measured, matching not), and `"onFailure": "block"` on the guard handlers.
- From the `/audit:security` of the same pass (2026-11-01): **the re-audit of `readable_git_dir` did not conclude** (a safety classifier stopped it); its premise, that a git dir under a `.git` segment cannot be written with no prompt, rests on `protect-files.sh` for Write. `mv`, `cp -r` and `mkdir -p` into a new `x/.git` pass `prevent-destructive-commands.sh`; only Claude Code's protected-path prompt would stop them, not driven. `git status` and `git diff` in a planted repository still run its config (reviewer measured the real call, pre-existing). `--git-dir` and `--work-tree` values with shell characters are not covered by the `-C` deny. `"onFailure": "block"` closes the timeout fail-open above for the guard hooks on 2.1.316; `LC_ALL=C` on the two scans is still open, a padded call now blocks instead of prompting.
- From the same re-review: the 4000-character cut in `decide` adds no truncation marker, so a long secret list or alias reason ends mid-word with its advice gone (the verdict holds); no case covers a long reason on `ask`; G10.03 relies on Linux's per-argument limit, so a bound on the reason is not asserted elsewhere.
- From the `harness-hooks` review 1/3 (2026-11-02), Minors not fixed in the fix batch (no code, one line each; the Critical, the code Majors, the dropped A4/A6 rows, the `.git/*.lock` removal, the template carve-outs, cache 7b and `Claude_Workflows.md` were fixed there):
  - `L1.*` locale rows check elapsed time only, not the verdict they would give.
  - `hold-a0` loop misses a bare `pnpm build`; Q1 rows are missing for `dev` stdout and the other silent targets.
  - Formatter deny pre-pass: the reason on a quoted test path names the unquoted word; a directory symlink removal is reported as the root; `find <root> -exec rm …` asks instead of the root deny.
  - Secret reads: a read-write redirect (`<>`) is not a stdin source; `export` and `declare -x` dump the environment with no ask; `sort`, `diff`, `cut`, `dd` read a file as a secret-reading verb but are not in `SECRET_VERB`.
  - Git: `protocol.ext.allow` set on the command line is not asked; `checkout-index` and `read-tree` overwrite the work tree with no rule; git calls outside the shared budget (`quick_git`) can still stack up to the hook's timeout.
  - A write through an in-project symlink to git internals (`ln -s .git/config x; echo > x`) resolves to the link, not `.git/config`.
  - `.claude/settings.json` deny union: a target-own carve-out placed before the kit's broad entry changes what the union denies (order is significant). `Read(!.env.*.example|sample|template)` was added by the fix batch but not measured on Claude Code 2.1.316.
  - `pnpm dlx <cmd>` is not read as the command it runs in secret mode (the text floor `SECRET_RE` stays); `rm -f .git/*.lock` (a glob) is still denied; `pnpm dev -p 3000` after an earlier segment in the same call asks (the not-a-path exemption needs a first call).
- From the `harness-hooks` review 2/3 (2026-11-03), not fixed in fix batch 2 (one line each):
  - Grep tool `glob` field is judged by spelling (`protect-files.sh:137-153`): `.e?v`, `credentials*`, `*.pe?` pass; `rg -g` overrides gitignore. Pre-existing.
  - Live `$` and backtick operands in secret mode get no verdict (`cat $F`, `cat $(…)`); the spec's Out of scope now says so.
  - `SECRET_VERB` lacks `diff`, `sort`, `cut`, `uniq`, `cmp`, `comm`, `rev`, `paste`, `fold`, `column` and `git diff --no-index`.
  - The shared parser does not read `<(…)` or a `case` inside `$(…)`, in either mode.
  - Upload-pack prefixes: a per-subcommand table of long options, plus `ls-remote --exec` and `archive --exec`.
  - `.GIT` and other case variants on a case-insensitive filesystem are not read as `.git`.
  - `verdicts[:MAX_ROWS]` can cut a deny off behind enough asks, lowering the call to ask.
  - Runner forms not read as the command they run: `yarn workspace x exec`, `pnpm dlx`, `yarn dlx`, `bunx`, `corepack`.
  - Shell options that change glob semantics (`globstar`, `extglob`, `dotglob`, `nullglob`) are not modelled; a user who sets them in a profile sees other matches than the scan. Also not modelled: `shopt -s …` in the same call (`shopt -s dotglob; cat *`), `nocaseglob`, `GLOBIGNORE`, `extglob` patterns.
  - Git fixtures: G16.127 and G16.132 do not place `-C .` consistently, and G16.029 and G16.066 have no `-C .` copies.
  - The root-row deny reasons name the target as typed, not the resolved path.
  - The settings carve-outs (`Read(!.env.*.example|sample|template)`) are pinned as strings only: `test-install.sh` does not run Claude Code's matcher.
  - A hook path read with `$(…)` loses a trailing newline (`FILE_PATH` of `auto-approve-config.sh`, `protect-files.sh`): a file whose name ends in a newline reads as its stripped name. `cwk_real_path` refuses a resolved path that ends in one, but the input path is cut before it gets there.
  - Any glob that matches more than 256 entries (or a brace list that expands past 256 words) now asks in secret mode, even when no secret is among them; the cap is `MAX_GLOB` in `shell_targets.py`.
- From the `harness-hooks` review 3/3 (2026-11-03), Minors, no code in the test-only batch (one line each):
  - A trailing `\` or other unparsable input drops the verdicts in secret and flag-row modes, not only for git.
  - `$((…))` hides a `$(…)` inside it from the shell guard.
  - pnpm shell-line options go before `exec` (`pnpm -c|--shell-mode exec`), npm `-c|--call` anywhere, `npx` takes a bundled `-yc`: plan A4's grammar (`:87`) is wrong for pnpm, and X24.177 and X28.47 pin a form pnpm rejects.
  - `pnpm <non-script word>` runs a system command (Q9 reads it as a package script).
  - Wrapper long or space value options are not skipped (`timeout --signal KILL 5`, `nice --adjustment`, `env --unset`, `exec -a`), and wrappers are missing: `ionice`, `doas`, `su -c`, `flock`, `strace`, `watch`, `script`, `chroot`, `busybox`.
  - A bracket class holding an escaped or quoted glob character (`.[\*e]nv`) is not expanded as the shell does.
  - `~+` and `~-` are not expanded.
  - The template suffix list lives in 6 places, `ADAPTATION.md` §2 bis says 2.
  - Stale hook-lib: the freeze message "re-run install.sh" is wrong, and `prevent-destructive-commands.sh` gives the wrong reason on an empty regex.
  - The glob cap asks even when every listed match is a secret (a deny is expected).
  - The git-guard runner ignores an unknown `setup` (the shell-guard runner fails on it).
  - The per-case timeout is 60 s (`CWK_CASE_TIMEOUT`) against the hooks' 5 s.
  - `tdd-freeze-tests.sh` `common_affix_len` takes more than 5 s on a 20 KB `old_string` and has no `"onFailure": "block"` (pre-existing).
- From the ship `/audit:security secrets` of `harness-hooks` (2026-11-03, 0 Critical, measured by the auditor, not refuted):
  - Major: `install.sh` `ensure_gitignore` adds `*.pem`, `*.key`, `credentials.*` to a target but never `.env`, `.env.*` and the template exceptions, while `protect-files.sh:20-23` and the `grep -r` ask text rely on `.env` being ignored; `grep -rn KEY .` reads a non-ignored `.env` under `Bash(grep *)`. Add the lines and a doctor check.
  - Major: secrets in git history read with no verdict under `Bash(git log|diff|show *)`: `git show HEAD~1:.env`, `git log -p -- .env`, `git grep X HEAD~1`. Ask on a `<rev>:<secret>` operand and secret pathspecs; document that a bare `git show <sha>` cannot be blocked.
  - Major: shell secret mode tests the operand's name, not its target: `cat notes.txt` with `notes.txt -> .env` (or `.env.example -> .env`) passes while Read denies. Realpath each operand before `is_secret_name`. Hard links pass on both sides.
  - Major: every secret-name check is case-sensitive (`protect-files.sh`, `auto-approve-config.sh`, `shell_targets.py`, `SECRET_RE`): `Read .ENV` on macOS APFS opens `.env`. Native `Read(.env)` case behaviour unmeasured.
  - Minor: `install.sh` `copy_tree` copies the working folder (untracked `settings.local.json`, `.kit-health.jsonl`, an addon `supabase/functions/.env`), not `git ls-files`.
  - Minor: the bundle scan's `grep -vE '(ANON|PUBLIC|PUBLISHABLE)_KEY'` drops a whole line, so a line holding an anon key and a service-role key reads clean; names like `VITE_*_APIKEY`, `VITE_*_SK` missed; `define`/`envPrefix`/`loadEnv(…, '')` unscanned.
  - Minor: no guard for `id_rsa`/`id_ed25519`, `.npmrc`, `.netrc`, `*.p12`/`*.pfx`, `~/.config/gh/hosts.yml`, service-account JSON; `.git-credentials` on the Read side.
  - Minor: `cat /proc/self/environ` dumps the environment with no verdict under `Bash(cat *)`.
  - Minor: Codex runs without the kit's hooks (`codex-handoff.sh` `workspace-write`), and `docs/work/<slug>/codex-last-message.txt` is not ignored.
  - Minor: `secure-logger.ts` `SENSITIVE_KEY` misses `key`, `privateKey`, `serviceKey`, `jwt`, `bearer`, and opaque `sk_live_…` values.
  - Minor: `Read(credentials.*)` misses a bare `credentials` file; `protect-files` lets `.git-credentials` through where the shell floor denies; the shell floor blocks harmless patterns (`grep … credentials`, `node -p process.env`).

## Where each old item went
Older docs cite these ids (`docs/work/small-lane/plan.md`, `docs/specs/light-permissions.md`, `docs/work/light-permissions-git/prior-gate.md`).

| Old | Status |
| --- | --- |
| H1 guarded paths ask, `.tdd-red` denied | shipped (d6839cb, 1a92ff0) |
| H2 secrets | `harness-hooks` A6. Dropping `Bash(grep *)` is removed because it has no effect. `grep -r KEY .` is covered by Claude Code's grep wrapper (measured); its bypass forms ask. Bare `set` asks. |
| H3 destructive git and shell | git → `harness-hooks` A2; `.git` deny → A3; `rm -rf src/*`, `docs`, `curl \| bash` already ask; `docs` not added to `PROTECTED_DIRS` |
| H4 RED marker digest | `harness-hooks` A1 |
| H5 auto-approve paths | `..` shipped (bc11dea); open part → `harness-hooks` A7 |
| H6, H7, H8 | `harness-cd` C1, C2, C3 |
| H9 AWS target | dropped 2026-11-01: the user deploys on Lightsail, covered by the SSH target (`harness-cd` DC2) |
| H10, H11, H12 | `harness-kit-ci` K3, K2, K4 |
| H13 allowlist | `harness-prompts` B2, exact forms only |
| H14 `.kit-dev` exemption | dropped (`harness-prompts` B3) |
| H15 no interpreter writes | rule → `harness-prompts` B1; TDD deny on heredocs → `harness-hooks` A5 |
| D1 | `harness-hooks` DA1 |
| D2, D3 | `harness-cd` DC1, DC2 |
| D4 (OQ7) | `harness-kit-ci` K1 / DK1 |
| D5 | answered by `docs/research-cache/claude-code-permissions.md`; remaining → `harness-prompts` DB1, DB2 |

Found by the review, not in the old spec: tool flags that delete or write folders through today's allows (`pnpm build --outDir src`, `--coverage.reportsDirectory`, `--outputFile`, `pnpm lint --fix`) → `harness-hooks` A4.
