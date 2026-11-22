# Spec: Harness hooks — the holes still open
Token profile: critical (authorization guardrails, secret exposure, frozen tests)
Split from: `docs/specs/harness-hardening.md`. Rewritten 2026-10-29, corrected 2026-10-30 and 2026-11-01 after further reviews + refutations. The "today" lines were replayed against the hooks before `65facf8` or measured in a scratch repo. The 2026-11-01 review re-measured only the lines it corrects, so the plan's research replays the rest.
Needs: `65facf8` in the branch (it owns `cwk-guard-api: 1`, the hold-back, `GUARD_ASK_R` and the git grammar). No push before the user's review of `readable_git_dir`. In A2, only the `git diff` step inherits that premise; a change from the review means a rebase of this pass, since it edits the same hook.

## Objective
Close the paths a **mistaken** agent still has around the kit:
- destructive git commands;
- tool flags and configs that delete or write folders the shell guard never sees;
- a heredoc that creates a test-first module;
- secrets read through glob or bypass forms;
- the auto-approve hook's last path gaps.

What must hold against a deliberate agent stays native (`permissions.deny`, sandbox, branch protection); this spec does not claim it.

Already shipped, not in scope:
- the guarded paths on Write/Edit and shell (old H1, d6839cb + 1a92ff0);
- recursive `rm` asks inside the project, including `rm -rf src/*`, `.git` and `docs` (guard-shell + light-permissions-git);
- `curl … | bash` asks (unresolved write target);
- auto-approve refuses `..` (bc11dea).

Every change lands with the fixture that fails before it and passes after.

## A0. Install: a stale target loses what the new hooks police
- **Today.**
  - `GUARD_FILES` (`install.sh:206-207`) omits `tdd-require-red.sh` and `auto-approve-config.sh`, so a bump on A1 or A7 holds nothing back.
  - Holding P1 back removes only `defaultMode` and the five git allows (`install.sh:267-275, 294-297`). The wildcard gate allows through which A4's holes run stay: `pnpm build *`, `test:run *`, `test:coverage *`, `lint *`, `typecheck *`.
  - An existing target only ever gets `.new` copies (`install.sh:84-86`).
- **Change.**
  - `tdd-require-red.sh` and `auto-approve-config.sh` carry `# cwk-guard-api: 1` and join `GUARD_FILES`.
  - Each guard file this spec changes bumps its number.
  - A held-back install also removes the `pnpm <gate> *` wildcard allows, from a separate list (`P1_ALLOWS` stays the five git allows, so `K1b` is untouched). A user's own identical `pnpm build *` goes too. Their bare forms (`pnpm build`, `pnpm test:run`, …) stay, so the gates still run without a prompt. `kit-doctor.py`'s gate-allowlist check accepts the bare form alone, and `pnpm audit *`, which it needs, is not in the list.
  - `docs/ADAPTATION.md:474,484` ("les cinq autorisations", "tes autres autorisations") and the `install.sh:244` comment ("nothing else does") state the new list.
  - The hold-back message names the `.new` files to merge.
- **Proof.**
  - `test-install.sh` (a): a target whose `tdd-require-red.sh` lacks the api line → P1 held back, no `pnpm build *`, `pnpm build` kept.
  - `test-install.sh` (b): after the `.new` merge → everything is back.
  - `test-kit-doctor.sh` on the held-back settings → no gate divergence.

## A1. A RED marker must carry its digest (old H4)
- **Today.** Both paths of `tdd-require-red.sh` skip the digest check when the marker has no `sha256:` line:
  - module creation, `:230-237`;
  - Edit, `:189-193`: a marker holding only `missing:bonus` passes.

  Tools and the shell can no longer write a marker (`protect-files.sh:181`, `prevent-destructive-commands.sh:464-469`), so this is defence in depth.
- **Change.** No `sha256:` line → deny "marker without digest, re-save the test", on both paths. `unavailable` stays accepted only when `file_digest` reports no hashing tool.
- **Fixtures.** New `run_case` setup branches write the marker in the temp root.

  | Case | Verdict |
  | --- | --- |
  | Creation path, empty marker | deny |
  | Edit path, `missing:bonus` without digest | deny |
  | Matching digest, both paths | pass |
  | Other digest | deny |

## A2. Destructive git, in the git parser (old H3, git half)
- **Today.** All of these pass both hooks, with or without `-C`/`-c`, and through a non-`!` alias. The exception is a spelled-out `worktree add`, which holds the word `add` and so reaches the grammar's last ask (`enforce-git-workflow.sh:945-951`); only its alias form passes.

  | Kind | Commands |
  | --- | --- |
  | Clean, reset, restore | `git clean -fdx`; `git -c clean.requireForce=false clean -dx`; `reset --hard`; `checkout -- .`; `restore .`; `restore '*.ts'`; `restore ':!README.md'` |
  | Frozen tests rewritten | `restore --source=HEAD~1 <frozen test>`; `checkout HEAD~1 -- <frozen test>` |
  | Stash, branch, refs | `stash clear\|drop`; `branch -D\|-M\|-C … main`; `update-ref refs/heads/main …` |
  | Fetch into `main` | `fetch origin main --refmap='+refs/heads/*:refs/heads/*'` (force-rewinds `main`); `fetch . feat:main` (fast-forwards `main` around the merge ask) |
  | Arbitrary command | `fetch --upload-pack='cmd' .`; `clone -u cmd x` |
  | Worktrees, by alias only (`alias.wa = worktree add`) | `git wa -B main ../wt x`; `git wa wt x`; `git wa .claude/worktrees/../../x` (a tree where `cwk_guard_rel` stops seeing guarded paths, `hook-guarded.sh:150-151`) |

  The hook reads an alias's own flags only for commit, switch and checkout (`enforce-git-workflow.sh:869`).

  Also open, from the `git-allow-grammar` reviews:
  - the scans at `enforce-git-workflow.sh:749,829` are quadratic under a UTF-8 locale (`harness-hardening.md`, Open follow-ups): a padded call now blocks instead of prompting;
  - `--git-dir` and `--work-tree` values with shell characters are not covered by the `-C` deny;
  - the 4000-character cut in `decide` adds no truncation marker.
- **Change.** In `enforce-git-workflow.sh`, on the parsed row, never in `prevent-destructive-commands.sh`'s regexes. A non-`!` alias is expanded, and its expansion goes through the same rules. Each reason names what is lost.
  - **Traps, read before planning:** the parsed rows carry no arguments today, so the row format grows; the `continue` at `:885` skips later rules; the alias is read in bash (`:736`), not in the python block.
  - `LC_ALL=C` on both scans, with a row proving the match is unchanged for ASCII calls (the speed is measured, the matching is not); non-ASCII text matches on the strict side (amended, plan Q13). `dir_unread` on `--git-dir` and `--work-tree` is not coded: `other_globals` already sends such an `add` to `hidden`, and destructive calls ask with those globals anyway (amended, plan Q10). `decide` marks a cut reason.
  - Ask:
    - `clean`, unless `-n`/`--dry-run`/`-i`;
    - `reset --hard`;
    - `checkout`/`restore` writing the work tree with a pathspec of `.`, `:/`, a directory, or one holding glob or magic characters;
    - `stash clear|drop`;
    - `branch` with `-D`/`-M`/`-C`/`-f`/`--force`;
    - `update-ref` on `refs/heads/*`.
  - Deny: `checkout`/`restore` writing the work tree whose pathspec matches the test-first or frozen-test pattern (`TDD_TARGET_RE` and the freeze pattern), with or without `--source`/a tree-ish.
    - `--staged`-only stays pass.
    - A named non-test file with uncommitted changes asks. The check is `git diff --quiet HEAD -- <p>` (amended, plan Q8: without `HEAD` a staged-only change is invisible, and `git checkout HEAD -- <p>` destroys it; side effect, `git restore <p>` on a staged file also asks). It runs a planted repo's `core.fsmonitor` (measured on a `--separate-git-dir` layout), so it holds the same preconditions as the `add` dry-run: `readable_git_dir`, no other git global or `GIT_*` variable, no `dir_unread`, the same 2 s deadline. Otherwise it asks, with no `git diff` run, and a timeout asks. `-c core.fsmonitor=false` is no substitute: other config was not tested.
  - Ask on fetch, pull, clone:
    - `fetch` with any refspec (positional or `--refmap`) whose destination is `refs/heads/*` or a bare branch name, forced or not;
    - `-u`/`--update-head-ok`;
    - `--upload-pack` on `fetch`/`pull`/`clone`/`ls-remote`, and `-u` on `clone`;
    - `-c` setting `*.uploadpack` or `remote.*.fetch`.
  - Ask on `worktree add` reached through an alias, with `-B`, `-f`/`--force`, or a path that is not under `<top>/.claude/worktrees/`. The path is normalised lexically, then physically, against the repo's top level (`git rev-parse --show-toplevel` of the call's directory, measured to fire no `core.fsmonitor`). A spelled-out `worktree add` keeps the grammar's ask whatever its path. Adding a strict form for it is a decision of the user, not this pass.
- **Fixtures** in `_harness/git-guard.jsonl`, each with its reason. The fixture repo setup configures `alias.nuke = clean -fdx` and `alias.wa = worktree add`, and a new setup key leaves a file modified for `git restore src/x.ts`. Each ask case is also run as `git -C . …`, and the clean case as `git nuke`.
  - Ask or deny: the cases above, as listed.
  - Pass:
    - `git clean -n`
    - `git reset --soft HEAD~1`
    - `git restore --staged src/x.ts`
    - `git restore src/x.ts` (clean file)
    - `git fetch origin`
    - `git fetch origin main`
    - `git fetch origin main:refs/remotes/origin/main`
    - `git branch -d feat/x`
  - Ask:
    - `git restore src/x.ts` on a modified file;
    - `git worktree add .claude/worktrees/x -b feat/x` (frozen G14.70 pins the same grammar ask on `git worktree add ../x`);
    - `git restore src/x.ts` where `readable_git_dir` refuses the repo, with no fsmonitor fired.

## A3. `.git` cannot be deleted
- **Today.**
  - `rm -rf .git` asks (`GUARD_ASK_R`).
  - `rm -rf .*`, `.g*`, `.[!.]*` and `find . -name .git -exec rm -rf {} +` ask with "guarded path: .".
  - `find .git -delete` passes.
  - `git log --output=.git/refs/heads/main` and `--output=.git/config` run with no prompt (`harness-hardening.md`, Open follow-ups): `main` moved with no reflog entry, and a replaced config ran a script on the next `git status`.
- **Change.**
  - `'.git/*'` joins `CWK_GUARD_DENIED` (`hook-guarded.sh:37`, api bump). A row that resolves to `.git` or under it is denied, whichever verb produced it.
  - The deny text at `prevent-destructive-commands.sh:465` names only RED markers. It becomes general, and each denied path keeps its reason.
  - Glob rows are not touched: `shell_targets.py:882` emits `?glob:<dir>` with no pattern, so `rm -rf .*`, `.g*` and `find . -name .git …` resolve to `.` and keep their ask.

  `docs` is **not** added to `PROTECTED_DIRS`. Every `mv docs/a docs/b` would ask, and the recursive `rm` ask already covers it.
- **Before EXECUTE.** Replay the full suite with `.git/*` added on a scratch copy. A static sweep of 177 cases found no frozen row resolving to `.git`, but the replay itself has not been run.
- **Fixtures.**
  - Deny: `rm -rf .git`, `rm -r ./.git/objects`, `find .git -delete`, `git log --output=.git/config`, `git log --output=.git/refs/heads/main`.
  - Ask (unchanged): `rm -rf .*`, `rm -rf .g*`, `find . -name .git -exec rm -rf {} +`, `rm -rf .github/tmp`.

## A4. Tool flags and configs that delete or write a folder
- **Today.** Measured in a scratch repo. Everything below passes both hooks, allowed by today's `Bash(pnpm build *)`, `test:run *`, `test:coverage *`, `lint *`, `typecheck *`.
  - **Deletes a folder:**
    - `pnpm build --outDir src` empties `src/`.
    - `--coverage.reportsDirectory=src` deletes `src/`; `=..` deletes the project's parent.
    - `pnpm exec playwright test --output=src` deletes `src/`. So does `outputDir: 'src'` in an unguarded `playwright.config.*`.
    - `vitest -c e2e/v.config.ts` whose config moves the reports directory, and `--root`/`--dir`, do the same.
  - **No verdict outside the project:** a target outside the project gets no verdict at all, because `guard_classify` returns early (`prevent-destructive-commands.sh:445`). `rm -rf ../..` passes too.
  - **Overwrites a file:**
    - `--reporter=json --outputFile=<frozen test>` overwrites it.
    - `tsc --noEmit --incremental --tsBuildInfoFile <file>` overwrites the file; `tsc --noEmit --noEmit false` emits.
  - **Rewrites frozen tests:** `pnpm lint --fix` (any argument is appended to the script, e.g. `eslint .`) and `eslint --fix <test file>`. `ruff check --fix-only|--fix=` pass.
  - **Already asks:** `ruff check --fix` on a folder and `eslint --fix .` (whole-folder formatter check, `prevent-destructive-commands.sh:511-552`).
  - **Wrong base folder:** flag paths resolve against the shell's cwd, while a package script runs at the package root.
  - **Runs a file or a command under a read allow:** `sed -n -f`, `sed -n --expr='1e …'` and `rg --hostname-bin` get no decision from either hook, through `Bash(sed -n *)` and `Bash(rg *)` (`harness-hardening.md`, Open follow-ups).
- **Change.**
  - **Resolution base.** For `pnpm|npm|yarn <script>`, `pnpm exec` and `npx`, flag paths resolve against the nearest ancestor of the call's directory holding `package.json`, or the `-C`/`--dir` value.
  - **Outside the project.**
    - A recursive delete row (from `rm -r` or a flag below) that resolves to the project root or one of its ancestors → deny.
    - One that resolves elsewhere outside the project → ask.
    - A write row outside the project → ask.
  - **Flag rows** (`shell_targets.py`), in `=` and space forms:
    - recursive delete: vite `--outDir`/`--out-dir`/`--emptyOutDir`, `--coverage.reportsDirectory`, playwright `--output`;
    - write: `--outputFile`, `--outputFile.*`, `--output-file`, tsc `--outDir`/`--outFile`/`--declarationDir`/`--generateTrace`/`--tsBuildInfoFile`.

    `prevent-destructive-commands.sh` classifies them like `rm -r` and a redirect:
    - deny on a protected root, `.git`, or a test-first/test path;
    - ask on a guarded path, under a protected dir, or (recursive delete) anywhere else.
  - **tsc.** Ask on `--noEmit false`/`--noEmit=false`, and on `-p`/`--project` naming anything but a guarded `tsconfig*.json`.
  - **Configs.**
    - `playwright.config.*` joins `CWK_GUARDED` (`hook-guarded.sh`, api bump).
    - Ask on `-c`/`--config`/`--root`/`--dir` passed to vite, vitest or playwright when the value is not a guarded config.
  - **Fix flags.** Extend the existing formatter check, with no parallel rule:
    - a package script named `lint*` with `--fix`, `--fix-only`, `--fix=` or `--unsafe-fixes` → always ask;
    - direct `eslint`/`ruff` keep today's named-file and `app/` exemptions, gain `--fix-only`, `--fix=` and `--unsafe-fixes`, and deny any target on a test path.
  - **Read allows that run code.** `shell_targets.py` emits an ask on `sed` with `-f`, `--file`, `-e`/`--expr…` or an `e` command in its script, and on `rg --hostname-bin` and `--pre`.
- **Fixtures.** Each one is also run through `pnpm vitest run`, `pnpm exec vitest run` and `pnpm exec playwright test` where the flag applies, in `=` and space forms.

  | Verdict | Commands |
  | --- | --- |
  | Deny | `pnpm build --outDir src`<br>`pnpm test:run --coverage.reportsDirectory=..`<br>cwd `docs` + `pnpm build --outDir src`<br>`--outputFile=src/a/a.utils.test.ts`<br>`pnpm exec tsc --noEmit --incremental --tsBuildInfoFile src/a/a.utils.test.ts`<br>`eslint --fix src/a/a.utils.test.ts` |
  | Ask | `sed -n -f x.sed f.txt`<br>`sed -n --expr='1e id' f.txt`<br>`rg --hostname-bin x KEY`<br>`--outDir build`<br>`--output=e2e`<br>`--output /tmp/x`<br>`pnpm exec tsc --noEmit --noEmit false`<br>`pnpm exec tsc -p docs/x.json`<br>`pnpm exec playwright test -c e2e/p.config.ts`<br>`pnpm lint --fix`<br>`pnpm lint --fix src/a.ts`<br>`ruff check --fix-only .`<br>Edit `playwright.config.ts` (`protect-files.sh`) |
  | Pass | `sed -n 1,5p f.txt`<br>`rg KEY src/`<br>`--outputFile=report.json`<br>`ruff check --fix app/`<br>`ruff check --fix-only app` (amended, plan Q12: the `app/` exemption wins, `--fix-only` behaves like `--fix`)<br>`pnpm build`<br>`pnpm test:run`<br>`pnpm exec playwright test`<br>`pnpm exec tsc --noEmit` |

## A5. An inline program that writes a test-first module is denied (from old H15)
- **Today.**
  - `python3 - <<EOF` + `open("src/features/a/a.repository.ts","w")` + `EOF` gets only the generic "unresolved write target" ask.
  - Approving it creates the module with no RED: `SRC_WRITE_RE` (`prevent-destructive-commands.sh:342`) requires `-c|-e|--eval|-p`.
  - The `-c` form is denied, including a `-c` that only reads a test-first file.
- **Change.** The text of every `?inline:` row, heredoc body included, is checked against `TDD_TARGET_RE` and the frozen-test pattern → deny with the TDD reason. This is the same policy as `-c`: a heredoc naming a test-first file is denied even if it only reads it (the Read tool reads).
- **Fixtures.**
  - The heredoc above → deny.
  - `node - <<EOF` + `fs.writeFileSync("src/x/x.mapper.ts")` → deny.
  - A heredoc reading `src/a.ts` → ask (unchanged generic).

## A6. Secrets through glob and bypass forms (old H2, rewritten)
- **Today.**
  - These pass: `cat .en*`, `cat .e*`, `cat .?nv`, `cat .[e]nv`, `cat .e\nv`, `cat .e""nv`, `printenv`, `env`, `set`.
  - `rg -uu KEY` and `rg --no-ignore KEY .` read `.env`.
  - **The grep wrapper.** Claude Code's shell runs `grep` through a wrapper (`ugrep --ignore-files --hidden`), so a plain `grep -r KEY .` skips gitignored files (measured 2026-10-30; version-dependent). These forms bypass it and print the secret: `grep -rZ`/`--null`, `command grep -r`, `/usr/bin/grep -r`, `git grep --untracked --no-exclude-standard`.
  - **Dropping `Bash(grep *)` changes nothing.** grep, cat, head, tail and find are in Claude Code's built-in read-only set (`docs/research-cache/claude-code-permissions.md:40`).
- **Change.** In `prevent-destructive-commands.sh`:
  - For a secret-reading verb, glob operands are expanded against the real directory listing (`glob.glob` once per possible working directory, amended by Q14 from fnmatch: it applies bash's dot rule and reads directories in the pattern; only unquoted glob characters count, backslashes and quotes removed first), and each basename is tested against the secret set, instead of matching on spelling. The secret set is `\.env(\..+)?` (any number of segments, so `.env.development.local` counts), a name ending `.pem` or `.key`, and `\.?credentials(\..*)?`, minus `.env.example|sample|template` and `.env.<mode>.example|sample|template` (amended by review 2/3). This lives in `shell_targets.py` or under `python3 -I`, never in a new inline interpreter without `-I`.
  - Ask on:
    - a recursive grep reached without the wrapper (`command grep`, an absolute path, `env grep`, `xargs grep`; `\grep` also asks, conservatively, though a backslash skips only an alias and not the wrapper function: research cache 7b) or with `-Z`/`--null`;
    - `git grep` with `--untracked` or `--no-exclude-standard`;
    - `rg` with any `-u…`, `--no-ignore*` or `--hidden`, whatever the root;
    - bare `env`, `printenv` or `set` with no argument.
- **Native deny and sandbox: decision DA1**, not shipped blind. A kit `permissions.deny` is only valid if `install_settings` also unions `permissions.deny`: today `$new * $old` drops the kit's array when the target has one (`install.sh:286-292`). `light-permissions-git.md`'s OUT clause is amended in the same commit.
- **Fixtures.**
  - Deny: `cat .en*`, `cat .e*`, `cat .?nv`, `cat .[e]nv`, `cat .e""nv`.
  - Ask: `printenv`, `env`, `set`, `rg -uu KEY`, `command grep -r KEY .`, `grep -rZ KEY .`, `git grep --untracked KEY`.
  - Pass: `printenv HOME`, `cat .env.example`, `rg KEY src/`, `grep -rn KEY src/`, `grep -r KEY .`.
  - The wrapper fact goes to the research cache with its version.

## A7. Auto-approve and credentials: the last path gaps (old H5, open part)
- **Today.**
  - `auto-approve-config.sh` allows a relative `file_path` (`notes.md`), and also `$P//.claude/worktrees/w/n.md` and `$P/./.claude/worktrees/w/n.md`.
  - Symlinks are not resolved: `docs/link.md` → `~/.ssh/id_rsa` is auto-approved.
  - `.credentials.json` passes Write and Read (`protect-files.sh:104`), and `git add .credentials.json` passes (`enforce-git-workflow.sh:337-341`, `startswith("credentials.")`).
  - The shell's `SECRET_FILE` (`prevent-destructive-commands.sh:154`) is unanchored and already denies `cat .credentials.json`.
  - **Why `cwk_guard_rel` is not the right resolver:**
    - it strips `.claude/worktrees/<x>/`, so a worktree's `package.json` would become `package.json` → allow;
    - it follows no symlink that is lexically inside the project.
- **Change.**
  - **New resolver.** `hook-guarded.sh` gains `cwk_real_rel <path> <base>`: a relative path joins `<base>`, then goes through `cwk_real_file`: A4's `cwk_real_path`, then a bash 3.2 `readlink` loop on the last component (40 hops). Amended at A7: one path for every machine, no python3 (`readlink` without `-f` exists on macOS); `..` stays lexical, unlike `realpath`. It returns the project-relative path only if the physical result is inside the physical project, and it never strips worktrees.
    - It returns non-zero for an outside path. `protect-files.sh` has `set -e` and `onFailure: block`, so every caller writes the `||` form (`:179` shows it). A bare `X=$(cwk_real_rel …)` would block every outside path.
  - **`auto-approve-config.sh`** rejects a lexically normalised path under `.claude/worktrees/`, read relative to `$CLAUDE_PROJECT_DIR` so frozen `02-worktree-config-allow.json` stays green, **before** resolving, then decides on `cwk_real_rel`. Outside the project → no decision.
  - **`protect-files.sh`** tests secret patterns on both the given name and the absolute physical path. `cwk_real_rel` returns nothing for an outside target, so the physical path comes from the resolver's realpath step, not from its result.
  - **Credentials pattern.** The anchored form `(^|/)\.?credentials(\.|$)` goes into `protect-files.sh` `SECRET_PATTERNS`, `auto-approve-config.sh:49`, and the git hook's secret test (which also gains `.credentials.`). `SECRET_RE` is **left as is**, because anchoring it would break today's shell deny.
- **Fixtures.** The symlink cases need a `run_case` setup branch that builds the link in a temp root.
  - No decision (auto-approve):
    - the `//` and `/./` worktree forms
    - `$P/.claude/worktrees/w/package.json`
    - trailing `/..`
    - unset `CLAUDE_PROJECT_DIR`
    - a file symlink inside → outside
    - a folder symlink (`docs/ext/` → outside)
  - Allow: `notes.md` with `cwd` = project.
  - Deny:
    - Read `.credentials.json`
    - `protect-files.sh` on a symlink inside the project → a secret outside it, named `.env` (`id_rsa` is not in `SECRET_PATTERNS`, so the `~/.ssh/id_rsa` link above stays "no decision" and is not denied)
    - `git add .credentials.json`
    - `cat credentials.json` and `cat .credentials.json` (regression guard)

## Decisions to take before EXECUTE
- **DA1.** Read `docs/research-cache/claude-code-permissions.md` first, then run one `doc-researcher` for what it lacks:
  - the exact `Read(...)` deny path syntax and its template exceptions;
  - whether a Read deny binds Bash;
  - sandbox availability and keys on this Claude Code.

  If deny binds Bash or the sandbox is available → add it, with the `install.sh` deny union and its `test-install.sh` case. Otherwise A6's hook changes ship alone, and the gap is written in `docs/ADAPTATION.md`.

## Order
A0 → A1 → A2 → A3 → A4 → A5 → A7 → A6 (after DA1). A0 comes first so that every later bump is held back on a stale target.

## Done when
- The table below replays through `test-hooks.sh` fixtures.
- These are green: `test-hooks.sh`, `test-install.sh` (one hold-back case per guard-api bump), `test-kit-doctor.sh`, `test-attempts.sh`, `test-workflow-contracts.sh`, `test-rules-floor.sh`, `test-measure.sh`, `test-small-lane.sh`.
- `kit-doctor.py` reports no divergence.

| Probe | Today | Target |
| --- | --- | --- |
| held-back install keeps `pnpm build *` | yes | no |
| empty RED marker (creation), `missing:` marker without digest (Edit) | pass | deny |
| `git clean -fdx`, `git -C . reset --hard`, `git branch -M x main`, `git stash clear` | pass | ask |
| `git fetch origin main --refmap='+refs/heads/*:refs/heads/*'`, `git fetch . feat:main` | pass | ask |
| `git checkout HEAD~1 -- src/a/a.utils.test.ts` | pass | deny |
| `git wa ../x` (`alias.wa = worktree add`), `git clone -u cmd x` | pass | ask |
| `git worktree add .claude/worktrees/x -b feat/x` | ask | ask |
| `rm -rf .git`, `find .git -delete`, `git log --output=.git/config` | ask / pass / pass | deny |
| `rm -rf .*`, `rm -rf .g*` | ask | ask |
| `sed -n -f x.sed f.txt`, `rg --hostname-bin x KEY` | pass | ask |
| `pnpm build --outDir src`, `pnpm test:run --coverage.reportsDirectory=..` | pass | deny |
| `pnpm exec tsc --noEmit --tsBuildInfoFile <frozen test>` | pass | deny |
| `pnpm exec playwright test --output=e2e`, `pnpm lint --fix src/a.ts` | pass | ask |
| `python3 - <<EOF` writing `src/…/x.repository.ts` | ask | deny |
| `cat .e*`, `cat .?nv` | pass | deny |
| `printenv`, `rg -uu KEY`, `command grep -r KEY .` | pass | ask |
| Read `docs/link.md` → `~/.ssh/id_rsa` | auto-approved | no decision |
| Read `.credentials.json`, `git add .credentials.json` | pass | deny |

## Out of scope
- Variable or substitution targets (`F=x; cat $F`, `eval`): as write targets they are asked as unresolved, but as read operands in secret mode (`cat $F`, `cat $(…)`) they get no verdict from this scan (a live `$` or backtick operand is skipped; recorded in `harness-hardening.md`); the native deny and the sandbox are the answer (DA1).
- What a target's own `lint` script contains: A4 asks on every fix flag passed to it instead of reading the script.
- `mv`, `cp -r` and `mkdir -p` into a new `x/.git`: they pass `prevent-destructive-commands.sh`, and only Claude Code's protected-path prompt would stop them, not driven. This is the premise of `readable_git_dir`, so it stays out until the user's review decides it.
- A strict grammar form for `git worktree add` under `.claude/worktrees/`: the user's decision.
