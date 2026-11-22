# Plan: Harness hooks, the holes still open   (entry: docs/specs/harness-hooks.md · research: docs/work/harness-hooks/research.md · design: n/a)
Token profile: critical

H = `.claude/hooks`.

## Skips
- DB, Backend, Front, Wiring, INTERFACE: SKIP, kit tooling with no screen.
- TypeScript test-first layers: none. Fixture rows are the RED legs, observed failing before the code. Freeze = plan rule, a corrected row is recorded in `## Gate` as `amended …`.
- Codex (`execute-green`, `review-fixes`): SKIP, `codex_safe: no`. Every file here is a guarded path, and Codex gets none of the prompts the guarded ask gives the user. Same decision as `harness-cd`'s fixes. Fix batches go to `implementer`.
- `sandbox.enabled` in the kit's settings: SKIP, Q2.
- `git worktree add` strict form, `mv`/`cp -r`/`mkdir -p` into `x/.git`: SKIP, spec's Out of scope.

## Write chain (sequential, in the spec's order)
For each section: rows RED → run `setsid --wait bash .claude/hooks/test-hooks.sh` (plain `setsid` returns 0 at once from the tool shell, measured) → code GREEN → full `test-hooks.sh` green → refresh `handoff.md`. **What must fail at RED:** every `ask`, `deny` and `no decision` row not marked `(guard)`. **What holds at RED by design:** rows marked `(guard)` and every row of a `pass:` list; they pin behaviour the change must not break, and pass rows that do go red today are named in the list. A row expected to fail that passes is a vacuous test: stop and fix the row, never the code.

1. **A0** install: `test-install.sh`, `test-kit-doctor.sh` cases RED → `install.sh`, two api lines, docs GREEN.
2. **A1** marker digest: fixtures + `run_case` setup RED → `tdd-require-red.sh` GREEN.
3. **A2** git: rows + fixture repo setup RED → `enforce-git-workflow.sh` GREEN (`LC_ALL=C` and the truncation marker first, then the alias expansion, then the rule function, then the `git diff` step).
4. **A3** `.git`: `setup` key on shell-guard rows in `test-hooks.sh`, rows RED → `hook-guarded.sh`, deny text GREEN.
5. **A4** flags: rows RED → `shell_targets.py`, then `guard_classify`, then the formatter check, `hook-guarded.sh` GREEN.
6. **A5** inline: rows RED → `guard_classify` GREEN.
7. **A7** paths: fixtures RED → `hook-guarded.sh`, `auto-approve-config.sh`, `protect-files.sh`, git secret test GREEN.
8. **A6** secrets: rows RED → `shell_targets.py` secret mode, `prevent-destructive-commands.sh` GREEN → DA1: `install.sh` deny union case RED → settings, `install.sh`, docs, spec OUT clause GREEN; wrapper fact to the research cache.
9. **Refactor** under a green suite, no row edited.
10. **Gates**: the eight suites (`test-hooks.sh` under `setsid --wait`), `kit-doctor.py`, the Done-when table replayed.

Each api bump lands with its section, and each bump gets its `test-install.sh` hold-back case in that step. Every step edits a guarded path, so it prompts the user. Probe strings naming secrets or `.git`: the Write tool, never a Bash heredoc, because the session's own hook reads them.

## Parallel lots
none: `test-hooks.sh`, `hook-guarded.sh`, `guard_classify` and both jsonl files are shared.

## Track isolation
- Worktree: none, single track (main tree, `audit/slim`).
- Shared foundations touched: kit hooks and `install.sh`. No other pass beside it. `harness-prompts` and `harness-kit-ci` wait.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `install.sh` | Edit | guard files, pnpm hold-back list, message, deny union |
| `.claude/settings.json` | Edit | `permissions.deny` |
| `H/hook-guarded.sh` | Edit | `.git/*`, `playwright.config.*`, `cwk_real_rel`, api 2 |
| `H/shell_targets.py` | Edit | runner prefixes, flag rows, sed/rg asks, secret mode, api 2 |
| `H/prevent-destructive-commands.sh` | Edit | outside verdicts, flag classes, inline deny, formatter, secret asks, deny text, api 2 |
| `H/enforce-git-workflow.sh` | Edit | destructive rules, alias expansion, `LC_ALL=C`, marker, secret test, api 2 |
| `H/hook-lib.sh`, `H/tdd-freeze-tests.sh` | Edit | `TEST_FILE_RE` moves to `hook-lib.sh` as `CWK_TEST_FILE_RE`, `tdd-freeze-tests.sh:74` reads it; a guard file among them bumps |
| `H/tdd-require-red.sh` | Edit | digest required, api 1 |
| `H/auto-approve-config.sh` | Edit | real path, credentials, api 1 |
| `H/protect-files.sh` | Edit | physical path, credentials, api 2 |
| `H/fixtures/_harness/{git-guard,shell-guard}.jsonl` | Edit | new rows; `X22.10` amended |
| `H/fixtures/{tdd-require-red,auto-approve-config,protect-files}.sh/*` | Create | new cases |
| `H/test-hooks.sh` | Edit | setup branches, `setup` key on shell-guard rows, `HOME=$tmp` for setup `secrets-home` |
| `H/test-install.sh`, `H/test-kit-doctor.sh`, `H/test-workflow-contracts.sh` | Edit | hold-back, gate case, K1 message and deny |
| `docs/ADAPTATION.md` | Edit | §15 lists, deny, sandbox gap |
| `docs/specs/light-permissions-git.md` | Edit | OUT clause (`:31`) amended |
| `docs/specs/harness-hooks.md` | Edit | amended by Q8, Q10, Q12, Q13, in the step of the section they touch |
| `docs/specs/harness-hardening.md` | Edit | follow-ups closed, Q11 recorded |
| `docs/research-cache/claude-code-permissions.md` | Edit | measured deny, wrapper fact with version |

## Contracts

### A0
- `GUARD_FILES` gains `tdd-require-red.sh`, `auto-approve-config.sh`. New `P1_GATE_ALLOWS` = `Bash(pnpm build *)`, `Bash(pnpm test:run *)`, `Bash(pnpm test:coverage *)`, `Bash(pnpm lint *)`, `Bash(pnpm typecheck *)`. `P1_ALLOWS` unchanged. Both removed on both sides when held back (`install.sh:269-273,294-297`). Bare forms and `Bash(pnpm audit *)` stay.
- Message: `P1 held back: <names> — merge <each name>.new, then re-run install.sh`. `test-workflow-contracts.sh` K1 and `ADAPTATION.md:510` follow. The `install.sh:244` comment and `ADAPTATION.md:471,497,505,514-515` state the new list.

### A1
Both paths: no `sha256:` line or an empty value → deny `marker without digest, re-save the test`. `unavailable` passes only when `file_digest` returns `unavailable` now.

### A2, in the python parser
- **Row**: one new last column, `destr`, never empty: `-`, `ask:<reason>` or `deny:<reason>`, with no tab in it. The existing six columns do not move. `:804` and `:845` read it. Deny pass acts on `deny:`, ask pass on `ask:`, both before `:880`'s block, so `:885`'s `continue` skips nothing new.
- **Alias**: python reads it with `git -C <dir> config --get alias.<x>` for a non-builtin, same conditions as `:734-737`, up to 5 hops, `shlex.split`, alias args prepended. A cycle or a parse error → `ask`. `!` aliases keep today's path. `:736-741` keep their role for the existing rules, so `G13.23`, `G8.06` keep their verdicts. A row reached by alias is marked, because the worktree rule needs it.
- **Regex**: bash passes `$CWK_TDD_SHELL_TARGET_RE` and `$CWK_TDD_SHELL_FROZEN_TEST_RE` as argv 3 and 4, python replaces `[:space:]` with `\s`. A row proves one hit each.
- **Options** match by unique prefix, as `--no-dry-run` does (`--har`, `--upload-p`, `--refm`), and short options when bundled (`-df`, `-fn`).
- **Rules** (`destr`), each reason naming what is lost:
  - ask: `clean` unless `-n`/`--dry-run`/`-i`/`--interactive`; `reset --hard`; `stash clear|drop`; `branch` with `-D`/`-M`/`-C`/`-f`/`--force`; `update-ref` on `refs/heads/*`, on `HEAD`, or with `--stdin`.
  - `checkout`/`restore`: `--pathspec-from-file` → ask. **First**, on every non-flag operand, whatever its position, on disk or not: a match of the two regexes → deny, unless `restore --staged` alone. This covers `git checkout HEAD~1 <test>` with no `--` and a deleted file. Then, for what writes the work tree (`restore` unless `--staged` alone; `checkout` with `--`, with an operand after the first, or with one operand that exists on disk or holds glob or magic characters): `.`, `:/`, a directory, glob or magic → ask. Else named files: the `git diff` step.
  - `git diff` step: new `worktree_dirty()` beside `dry_run`, with `readable_git_dir`, no `other_globals`, no `GIT_*`, no `dir_unread`, the shared deadline, `Popen` and timeout. It runs `git diff --quiet HEAD -- <p>`, not the spec's `git diff --quiet -- <p>`, because a staged-only change is invisible to the latter and `git checkout HEAD -- <p>` destroys it (measured, Q8). Exit 0 → `-`. Anything else, a failed precondition, or a timeout → ask.
  - **`state["cd"]` or `prior` set → ask, for the `git diff` step and every disk test of these rules** (directory, operand on disk, `git wa` path), without running anything. A `cd` only sets state and keeps `base` (`:537-539`), so the check would read the wrong tree: `cd .claude/worktrees/feat && git restore src/x.ts` would check a clean base and destroy the worktree's edit (measured). The regex deny runs first and is not affected.
  - fetch/pull/clone: `fetch` refspec (positional or `--refmap`) whose destination is `refs/heads/*` or has no `refs/` prefix; `-u`/`--update-head-ok` on `fetch`/`pull`; `--upload-pack` on `fetch`/`pull`/`clone`/`ls-remote`; `-u` on `clone`; `-c` or `--config-env` naming `*.uploadpack` or `remote.*.fetch`, case-insensitive.
  - worktree: alias-reached `worktree add` with `-B`, `-f`/`--force`, or a path not under `<top>/.claude/worktrees/`, normalised lexically then by `realpath`, `<top>` from `git rev-parse --show-toplevel` with the same timeout. A failure asks.
- `dir_unread` on `--git-dir`, `--work-tree`: not coded (Q10). `other_globals` already sends such an `add` to `hidden` first (`:431`), so the change has no observable effect (replayed). `LC_ALL=C grep` on the scans at `:749,829,833,893-895`; non-ASCII text then matches on the strict side (`git commité` counts as a commit, Q13). `decide` cuts at 4000 minus the marker, then appends `[reason truncated]`.
- Stated gaps, in the hook's header: with python missing or bad, the existing floor applies and the destructive rules do not run (`nopy` rows prove the floor still answers). Wrapped or unparsable calls (`timeout 5 git clean -fdx`, `git reset --hard` beside a heredoc with an apostrophe) become `?unread`/`UNPARSABLE`, which `fallback_rows` does not read: they stay no verdict (Q11).

### A3
`.git/*` in `CWK_GUARD_DENIED`, api 2. Deny text general: `<path> written by <verb>` with the reason per path (`.git`: history and config; `.tdd-red`: the marker proves a RED).

### A4, `shell_targets.py`
- **Runner prefixes**: `pnpm exec`, `npx`, `npm exec`, `yarn exec` are stripped to the real command, skipping their own flags (`-y`, `--yes`, `-p`/`--package` and value, `-r`, `--filter` and value, `-c`/`--call` → `?unknown`). The command then gets all its normal rows (Q4). `pnpm -C x`, `pnpm --dir x` before them set the base.
- **Package script** (Q9): `pnpm|npm|yarn [run] <script>`, where `<script>` is not a runner builtin (`install`, `i`, `add`, `remove`, `update`, `audit`, `outdated`, `list`, `why`, `publish`, `pack`, `dlx`, `create`, `init`, `config`, `store`, `link`, `unlink`, `rebuild`, `prune`, `fetch`, `import`), is read as an unknown tool with the whole flag table, tsc's rows included. `--` is skipped.
- **Base**: flag paths resolve against the nearest ancestor of the call's directory holding `package.json`, **with the walk stopping at the physical `$CLAUDE_PROJECT_DIR`** (`os.path.realpath` on both sides; read from the environment; unset → no walk), else the call's directory, or the `-C`/`--dir` value. Without the bound, `/home/stevan/package.json` wins on this machine.
- **`exec_rows`** (`:488-500`): a `{}` word emits `?glob:<root>`, not a plain path. `{}` stands for the matches, never the root, and today's row is a plain `rm-r <project>`: step 2 below would otherwise deny `find . -name __pycache__ -exec rm -rf {} +`.
- **Flag rows**, `=` and space forms: labels `flag-r` (`--outDir`, `--out-dir`, `--emptyOutDir` when its value is neither absent nor `true`/`false` (a following word starting with `-` counts as absent), `--coverage.reportsDirectory`, `--output` on playwright and a package script) and `flag-w` (`--outputFile`, `--outputFile.*`, `--output-file`, tsc `--outDir`, `--outFile`, `--declarationDir`, `--generateTrace`, `--tsBuildInfoFile`). `vite` gets `flag-r` for `--outDir`, `tsc` gets `flag-w`, a package script gets `flag-r` (the stricter one).
- **New row kind `cfg<TAB><absolute path>`**, judged in `guard_classify`, because the resolver "resolves, never classifies" (`shell_targets.py:7`) and the guarded list has one home: `-p`/`--project` after tsc or a package script; `-c`/`--config`/`--root`/`--dir` after vite, vitest, playwright or a package script. After a package script only, a value with no `/`, no `.` at all, that names no existing path under the base, in a call with no earlier segment (`prior` unset, as in A2), is not a path and gets no row (`pnpm dev -p 3000`, `pnpm test:run --project=unit`). Anything else gets a row: `x.mts` included, and `mkdir -p docs && … -p docs`, whose directory does not exist yet when the hook runs. A row on a path that does not exist is judged as a file. `--dir` stays on the package-script list deliberately (the spec names it), though vitest's `--dir` loads no config: `pnpm test:run --dir src` asks. A **directory value** (existing on disk) loads the config it holds, so the row carries the directory, judged as such in `guard_classify` (step 4), never as a folder of the guarded list.
- **`?unknown` asks**: tsc or package script `--noEmit false`, `--noEmit=false`; `sed` with `-f`, `--fi…`, `-e`, `--e…`, bundled (`-nf`, `-ne`), `script_file` included; `rg --hostname-bin`.
- Base for a `-c`: `pnpm -c` before the script stays pnpm's own.

### A4, `guard_classify`
Order, first match wins:
1. `?inline:`/`?unknown:` branch, unchanged (A5 adds to it).
2. A plain (not `?glob:`) `rm-r`/`flag-r` row whose physical path (`cwk_real_path`, added to `hook-guarded.sh` in this step, A7 reuses it) equals the physical project root or an ancestor of it → deny. Compared with `$CLAUDE_PROJECT_DIR`'s physical path, never with `cwk_guard_rel`'s result, because it strips worktrees. Unset → skipped. `rm -rf .*` is a `?glob:` row and keeps its ask.
3. `rel="$(cwk_guard_rel "$target")"` fails: `CLAUDE_PROJECT_DIR` unset → no verdict, as today. Otherwise the target is outside, and the alias handling of `cwk_guard_rel` (`hook-guarded.sh:121-147`) decides that, never a new lexical test:
   - `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/fd/*` → no verdict (Q1).
   - `rm-r`/`flag-r` → ask, glob rows included.
   - any other row with target `/tmp` or under `/tmp/` (`?glob:/tmp` and `cp x /tmp/` resolve to `/tmp`) → no verdict (Q1), elsewhere → ask. `cfg` → ask.
4. Inside: `flag-r`/`flag-w`: deny on a root of `PROTECTED_DIRS` except `dist` (Q7), on `cwk_is_guard_denied`, on a rel matching `TDD_TARGET_RE` or `CWK_TEST_FILE_RE` (`.spec.ts`, `test_x.py`, the spec's "test path"). Ask on guarded, under a protected dir, or `flag-r` anywhere else. `flag-w` otherwise no verdict. `cfg` on a file: `cwk_is_guarded` → no verdict, else ask (a file never meets `hook-guarded.sh:62-63`'s folder rule). `cfg` on a directory: the physical project root → no verdict, any other directory → ask, `.claude` and `.github` included, whatever `cwk_is_guarded` says of the folder.
5. Existing rules.

Reason text of the verdicts of steps 2-4 and the formatter's deny: contains the target as resolved (rel inside, absolute outside). A row's `_expect_reason` is that path.

Formatter, two places, so a deny is never hidden by an earlier ask (the file's deny-first contract, `:191-195`): a **deny pre-pass before `:484`** walks the same segments for direct `eslint`/`ruff` with a fix flag: a **named file** matching `CWK_TEST_FILE_RE` → deny, the spec's "test path" only, so `eslint --fix src/a/a.utils.ts` keeps passing. A folder such as `tests/services` is not a named test file, so frozen fixture 19 keeps its ask. **The asks stay at `:511`**: a package script named `lint*` with `--fix`, `--fix-only`, `--fix=`, `--unsafe-fixes` → ask. Direct `eslint`/`ruff` treat those three flags like `--fix`, with today's exemptions (Q12).

### A5
In `guard_classify`'s `?inline:` branch, text matching `TDD_TARGET_RE` or `TDD_FROZEN_TEST_RE` sets `GUARD_INLINE_TDD`, denied with the TDD reason at `:464`'s deny block, after `.tdd-red`'s check.

### A6
- `shell_targets.py --secret-reads "<cmd>" "<base>" "<verbs>"` prints `deny<TAB>…` / `ask<TAB>…` / `#end<TAB>N`; `<verbs>` is the `SECRET_VERB` variable, passed, so one list exists. The hook calls it with `python3 -I -B`, once, with `HOOK_DIR` and `GUARD_BASE` moved above `:177`. **A failed run or a missing `#end` adds no verdict**: `SECRET_RE` stays as the text floor, the existing `shell guard unavailable` asks keep their job, and frozen X12 (`ls src` passes in all six broken states) holds.
- **Placement**: `deny` lines at the secret block (`:177-186`), so before every ask; `ask` lines join the ask group (`:487-499`), so after `:199`'s deny of disk commands.
- **Walk**: the mode is driven by `Walker` (`finish(seg, state)`), so `$(...)` bodies come through `subs` and each segment arrives with its `State`. A `cd` is read from `state.dirs`, never from a fixed `<base>`.
- **Raw words**: `shlex` drops the backslash of `\grep` and `strip_prefixes` drops `command` and `env`. Mechanism: `Scan` **inserts** a hidden marker in the `HIDE` style (`shell_targets.py:22`) **before** an unquoted backslash at the start of a word, and keeps the backslash, so shlex still reads the escape (replacing it moves X2.01-X2.04, X2.16 and breaks `echo \"x\" > notes.md`, measured). The marker survives `walk_flat`'s CONTROL/REDIRECT checks and is stripped at `seg.words.append` and in `redirect()`, which records `escaped_first` on the `Segment`. Replayed by the critic: zero row change on the 158 shell-guard rows. `strip_prefixes` also returns the names it dropped; `escaped_first` is tested on the first word after stripping, assignments included (`x=1 \grep`). A bypass is an escaped first word, a first word holding `/`, or a dropped exec-type wrapper: `command`, `env`, `exec`, `nice`, `nohup`, `setsid`, `sudo`, `stdbuf`, `timeout`, `xargs`, runner prefixes. Shell keywords, `{`, `!`, `time`, `builtin` are not bypasses.
- **Other operands**: `Walker.redirect` stores the `<` target word in a new `Segment` field `stdin_target` (the `stdin_file` bool stays for `interpreter()`, `:458`); it is tested whatever the verb, like today's text floor (`prevent-destructive-commands.sh:172`). `.` and `source` join the verbs for this mode only. Bare `env`: strip leaves no word and dropped holds `env`; `printenv`, `set` alone.
- **Operands of a reader verb**: the first non-flag operand of `grep`, `egrep`, `fgrep`, `rg`, `sed`, `awk` is a pattern or script, never a file, unless `-e`/`-f` gave it, in any form: separate, bundled (`-rne`), `--regexp=`, `--file=`, `--expression=`. It is skipped. **A glob character counts only if unquoted**, read from `Scan`'s quoted-glob marking (`shell_targets.py:22,120`), so `sed -n 's/a.*b/c/p' f.txt` and `cat '.e*'` are literals. Quotes and backslashes are then removed: literal → set test, so `cat .e""nv` and `cat .e\nv` hit it.
- **Glob**: braces expanded, then, once per directory `d` in `state.dirs`, `glob.glob(os.path.join(glob.escape(d), os.path.expanduser(pattern)))`, each basename tested. `os.path.join` drops `d` for an absolute pattern, so `cat /abs/project/.e*` and `cat ~/.e*` resolve. A `None` in `state.dirs` with a glob operand → ask. It applies bash's dot rule by itself (`*` skips `.env`, `.e*` finds it) and reads directories in the pattern, so `cat */.env` works. This replaces the spec's fnmatch (Q14). An unreadable directory finds nothing, as bash would, and `SECRET_RE` stays the floor.
- **Secret set**, on the basename, its own definition, not `SECRET_FILE` anchored (that would lose `server.pem`, `credentials.json`): `\.env(\..+)?` (any number of segments: `.env.development.local` is a secret), or ending `.pem`/`.key`, or `\.?credentials(\..*)?`, minus `.env.example|sample|template` and the `.env.<mode>.example|sample|template` forms (amended by review 2/3, consistent with the settings carve-outs of DA1). A row pins each.
- Asks as the spec lists. `SECRET_RE` stays, so `cat .env.exam*` keeps today's deny.

### A7
As the spec. `cwk_real_rel <path> <base>` prints the relative path, returns 1 outside. It and `protect-files.sh` use A4's `cwk_real_path <path> <base>`. The `$P//…`, `/./` rejection is lexical, before resolving. Relative paths join `.cwd`, else `$CLAUDE_PROJECT_DIR`. Credentials pattern `(^|/)\.?credentials(\.|$)`.

### DA1, `.claude/settings.json`, order significant
`"deny": ["Read(.env)", "Read(.env.*)", "Read(!.env.example)", "Read(!.env.sample)", "Read(!.env.template)", "Read(!.env.*.example)", "Read(!.env.*.sample)", "Read(!.env.*.template)", "Read(*.pem)", "Read(*.key)", "Read(credentials.*)", "Read(.credentials.*)"]` (12 entries; the three `.env.*.<suffix>` carve-outs were added by fix batch 1, user-approved 2026-11-03, unmeasured on Claude Code)

`install.sh` union: target's entries first, then the kit's not already there, **in order, no `unique`** (`:293`'s `unique` sorts, and `!` sorts first, which carves nothing). Never removed on hold-back. Measured 2026-11-01 on 2.1.316 with fake files: Read tool and `cat` denied on `.env`, `.env.local`; `.env.example` read in both.

## Test plan (gate — validated by the user before EXECUTE)

Every `ask` and `deny` row carries a reason. Each ask in A2 also runs as `git -C . …`, the clean case also as `git nuke`. Each A4 flag case also runs through `pnpm vitest run`, `pnpm exec vitest run`, `pnpm exec playwright test` where the flag applies, `=` and space forms.

### A0: `test-install.sh`, `test-kit-doctor.sh`
**Core**
- `tdd-require-red.sh` without its api line in the target → P1 held back, no `pnpm build *`, `pnpm build` kept.
- After merging the `.new` copies and re-running → all five wildcards and P1 back.
- Same two for `auto-approve-config.sh`.
- Held-back settings → `kit-doctor.py` reports no gate divergence (new `test-kit-doctor.sh` case) `(guard)`: the bare forms already satisfy it, and it proves the removal does not break it.
**Rules**
- Message names `<file>.new`.
- `Bash(pnpm audit *)` kept on hold-back `(guard)`. A user's own `Bash(pnpm build *)` removed (stated).
- `P1_ALLOWS` still exactly five (K1b, `(guard)`).
- One hold-back case per bumped file: `hook-guarded.sh`, `shell_targets.py`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`, `protect-files.sh`, and `hook-lib.sh`, `tdd-freeze-tests.sh` where they are guard files, at their previous api → held back.

### A1: `fixtures/tdd-require-red.sh/`, `run_case` branches writing the marker in `$tmp`, `project_dir=$tmp`
- 08 creation, empty marker → deny.
- 09 Edit, `missing:bonus` without digest → deny.
- 10, 15 empty `sha256:` value, both paths → deny.
- 16, 17 `sha256:unavailable` on a machine that can hash, both paths → deny.
- 18 `sha256:unavailable` with `sha256sum` and `shasum` off `PATH` → pass `(guard)`.
- 11, 12 matching digest, both paths → pass `(guard)`.
- 13, 14 other digest, both paths → deny `(guard)`.

### A2: `git-guard.jsonl` G16.*; setup: `alias.nuke`, `alias.wa`, `alias.rs = restore`, new keys `modified`, `staged`, `cycle` (alias loop), `credfile` (untracked `.credentials.json`). Planted repo: G15-style runner (`test-hooks.sh:724-760`), the only one that checks a sentinel
**Reproduction: destructive, all pass today**
- ask: `git clean -fdx`, `git -c clean.requireForce=false clean -dx`, `git reset --hard`, `git checkout -- .`, `git restore .`, `git restore '*.ts'`, `git restore ':!README.md'`, `git restore :/`, `git restore src`, `git stash clear`, `git stash drop`, `git branch -D x`, `git branch -M x main`, `git branch -C x main`, `git branch -f x`, `git branch --force x`, `git update-ref refs/heads/main HEAD`, `git update-ref HEAD x`, `git update-ref --stdin`.
- ask, prefixes and bundles: `git reset --har`, `git branch -df x`, `git fetch --upload-p=cmd .`, `git fetch origin main --refm='+refs/heads/*:refs/heads/*'`, `git fetch --update-head-ok origin`, `git pull -u origin`, `git --config-env=remote.o.fetch=V fetch`, `git -c REMOTE.o.FETCH=x fetch`, `git --git-dir='$X' clean -fdx`. `(guard)`: `git --work-tree='$X' reset --hard`, already an ask.
- deny: `git rs src/a/a.utils.test.ts` (alias), `git restore --source=HEAD~1 src/a/a.utils.test.ts`, `git checkout HEAD~1 -- src/a/a.utils.test.ts`, `git checkout HEAD~1 src/a/a.utils.test.ts` (no `--`, file not on disk), `git checkout feat src/a/a.repository.ts`, `git restore src/a/a.utils.ts`, `git restore '*.test.ts'`.
- ask: `git fetch origin main --refmap='+refs/heads/*:refs/heads/*'`, `git fetch . feat:main`, `git fetch origin main:refs/heads/x`, `git fetch -u origin`, `git fetch --upload-pack=cmd .`, `git pull --upload-pack=cmd`, `git ls-remote --upload-pack=cmd .`, `git clone --upload-pack=cmd x`, `git clone -u cmd x`, `git -c remote.origin.fetch=x fetch`, `git -c core.x=y -c remote.o.uploadpack=z fetch`.
- ask: `git nuke`, `git -C . nuke`, `git wa -B main ../wt x`, `git wa wt x`, `git wa ../x`, `git wa .claude/worktrees/../../x`, `git wa -f .claude/worktrees/x`.
**Rules**
- `git restore src/x.ts` with setup `modified` → ask.
- G15.32 `git restore src/x.ts` in a planted repo (`--separate-git-dir`, sentinel `core.fsmonitor`) → ask, sentinel file absent.
- `git checkout -- src/x.ts` with setup `modified` → ask.
- ask: `cd .claude/worktrees/feat && git restore src/x.ts`, `git stash pop && git restore src/x.ts`, `printf x > notes.md && git restore notes.md`.
- `git checkout HEAD -- src/x.ts` and `git restore --source=HEAD --staged --worktree src/x.ts` with setup `staged` → ask.
- Short restore forms: `git restore -SW src/x.ts` with setup `modified` → ask; `git restore -SW src/a/a.utils.test.ts` → deny.
- ask, disk test blocked by `prior` or `cd`: `git fetch origin && git checkout main`, `cd src && git checkout main`.
- New `run_locale_cases` in `test-hooks.sh` (the jsonl has no locale input). It picks a UTF-8 locale from `locale -a`, case-insensitive on `utf-?8`; none → skipped with a printed line. Shape: repeated `git ` words then `; commit`, and repeated `gh ` words then `; comment`, 60 KB each (a literal `git commit -m "<pad>"` matches at once and proves nothing). **Speed row, must fail at RED**: the hook returns in under 2 s; measured today 5.45 s and 5.03 s at 50 KB, past the 5 s timeout, against 0.11 s under `C`. **Match row** `(guard)`: ASCII `git commit`, `gh comment`, and `git status` get the same verdict in both locales. Non-ASCII differs by design (Q13).
- A reason over 4000 chars ends in `[reason truncated]`.
- Alias cycle, setup `cycle` → ask `(guard)`, already the chain rule.
**Pass and guards**
- pass: `git clean -n`, `git clean -fn`, `git clean --dry-run`, `git reset --soft HEAD~1`, `git restore --staged src/x.ts`, `git restore src/x.ts` (clean), `git fetch origin`, `git fetch origin main`, `git fetch origin main:refs/remotes/origin/main`, `git branch -d feat/x`, `git checkout main`, `git wa .claude/worktrees/x -b feat/x`.
- ask `(guard)`: `git worktree add .claude/worktrees/x -b feat/x`.
- `(guard)`: `G2.02`, `G2.06`, `G8.06`, `G13.23`, `G14.70`.

### A3: `shell-guard.jsonl` X23.*
- deny: `rm -rf .git`, `rm -r ./.git/objects`, `find .git -delete`, `git log --output=.git/config`, `git log --output=.git/refs/heads/main`.
- ask `(guard)`: `rm -rf .*`, `rm -rf .g*`, `find . -name .git -exec rm -rf {} +`, `find . -name __pycache__ -exec rm -rf {} +`, `find . -name x -execdir rm -rf {} \;`, `rm -rf .github/tmp`.
- Alias project dir (`CLAUDE_PROJECT_DIR` a symlink, `cwd` physical), setup `aliasdir` on the new `setup` key: `rm -rf .git` → deny, `touch .claude/.tdd-red/m` → deny `(guard)`, `touch notes.md` → pass `(guard)`.

### A4: X24.*
**Reproduction**
- deny (Q4, A3's `.git` deny reached through the runner stripping): `pnpm exec rm -rf .git`, `npx rm -rf .git`, `pnpm -r exec rm -rf .git`, `pnpm --filter x exec rm -rf .git`.
- deny: `pnpm build --emptyOutDir=src`, `pnpm build --outDir src`, `pnpm test:run --coverage.reportsDirectory=..`, `--outputFile=src/a/a.utils.test.ts`, `pnpm exec tsc --noEmit --incremental --tsBuildInfoFile src/a/a.utils.test.ts`, `eslint --fix src/a/a.utils.test.ts`, `pnpm exec playwright test --output=src`.
- deny, setup `pkgroot` (`$tmp/package.json`, `project_dir=$tmp`): cwd `$tmp/docs` + `pnpm build --outDir src`.
- Hermetic bound, setup `pkgabove` (`$tmp/package.json`, `project_dir=$tmp/p`, cwd `__FIXTURE_ROOT__/p`, no `package.json` inside): `pnpm build --outDir src` → deny, only a bounded walk gives it; `pnpm build --outDir out/x` → ask on `out/x`. Same with a symlinked project dir.
- ask, setup `pkgsub` (`$tmp/sub/package.json`, `$tmp/sub/src`, `project_dir=$tmp`): `pnpm -C sub build --outDir src` from `$tmp`, reason naming `sub/src`, which proves the `-C` base: resolved from `$tmp`, it would deny on the root `src`.
- deny: `pnpm test:run --outputFile=tests/services/test_x.py`, `--outputFile=src/a.spec.ts`, `--outputFile=e2e/a.spec.ts`.
- deny: `rm -rf ../..`, `pnpm test:run --coverage.reportsDirectory=.`, `rm -rf <absolute project>`. `(guard)`: `rm -rf ..`, already denied.
- deny: `pnpm exec tsc --declarationDir src/a/a.utils.test.ts`, `pnpm test:run --outputFile.json=src/a/a.utils.test.ts`, `pnpm test:run --output-file=src/a/a.utils.test.ts`, `pnpm exec tsc --outFile src/a/a.utils.test.ts`, `pnpm exec tsc --generateTrace src/a/a.utils.test.ts`, `pnpm exec vite build --out-dir src`, `pnpm run build --outDir src`, `npm run build -- --outDir src`.
- deny: `rm -rf docs/x; eslint --fix src/a/a.utils.test.ts` (deny before ask), `ruff check --fix-only tests/services/test_x.py`, `eslint --fix src/a.spec.ts`.
**Rules**
- ask: `pnpm typecheck --noEmit false`, `pnpm typecheck --noEmit=false`, `pnpm typecheck -p docs/x.json`, `pnpm typecheck --project docs/x.json`, `pnpm exec vitest run --root docs`, `pnpm exec vitest run --dir docs`, `pnpm exec vitest run --config docs/vitest.config.ts`, `-c docs/vitest.config.ts`.
- pass (`cfg`): `pnpm exec vitest run -c vitest.config.ts`, `pnpm exec tsc -p tsconfig.app.json`, `pnpm install --dir x` (a builtin, Q9), `pnpm exec vitest run --root .` `(guard)`.
- ask, setup `cfgdirs` (`docs/` and `.github/` exist): `pnpm typecheck -p docs`, `pnpm test:run --root docs`, `pnpm test:run --root .github/`, `pnpm exec vitest run --root .github`, `pnpm exec tsc -p docs`, `pnpm test:run --dir src`.
- ask: `pnpm test:run -c x.mts`, `mkdir -p docs && cp tsconfig.json docs/ && pnpm typecheck -p docs` (no `docs/` beforehand).
- ask `(guard)`: `find . -name x -exec rm -rf {} \;` (the escaped `;` must never become an empty word, i.e. the project root).
- ask: `sed -n -f x.sed f.txt`, `sed -nf x.sed f.txt`, `sed -n --file=x f.txt`, `sed -n --expr='1e id' f.txt` (reason `unresolved write target`, no longer `guard unavailable`), `sed -n --expr=1p f.txt` (reason `unresolved write target`: it asks today with `guard unavailable`), `rg --hostname-bin x KEY`, `--outDir build`, `pnpm exec playwright test --output=e2e`, `--output /tmp/x`, `pnpm exec tsc --noEmit --noEmit false`, `pnpm exec tsc -p docs/x.json`, `pnpm exec playwright test -c e2e/p.config.ts`, `pnpm lint --fix`, `pnpm lint --fix src/a.ts`, `ruff check --fix-only .`, `ruff check --fix=true .`, `ruff check --unsafe-fixes .`, `eslint --fix-only .`, `ruff check --fix-only tests/services`.
- ask: Edit `playwright.config.ts` (`protect-files.sh` fixture 35).
- ask: `rm -rf /tmp/x` (**`X22.10` amended pass → ask**, the spec's "elsewhere outside the project"), `tee /home/x`, `ls > /home/x`.
- ask: `pnpm build --outDir dist` (Q7), `pnpm exec sed -i s/a/b/ package.json` (guarded, Q4).
**Pass and guards**
- pass: `pnpm build --emptyOutDir true`, `pnpm build --emptyOutDir --mode staging`, `pnpm dev -p 3000`, `pnpm test:run --project=unit`, `sed -n 1,5p f.txt`, `rg KEY src/`, `--outputFile=report.json`, `ruff check --fix app/`, `ruff check --fix-only app/`, `ruff check --fix-only app` (Q12), `eslint --fix src/a/a.utils.ts`, `pnpm build`, `pnpm test:run`, `pnpm exec playwright test`, `pnpm exec tsc --noEmit`.
- pass (Q1): `ls 2>/dev/null`, `ls > /dev/null`, `ls > /tmp/x`, `tee /tmp/x`, `rm /tmp/x`, `rm /tmp/x-*` (`X9.09` `(guard)`).
- `(guard)`: prevent-destructive fixtures 06, 08, 13, 14, 17, 19; `X2.09`-`X2.15`, `X9.04`, `X9.05`, `X9.11`.
- `CLAUDE_PROJECT_DIR` unset, new `run_case` branch: `rm -rf /tmp/x` → pass, `python3 -c 'x'` → ask `(guard)`, an inline `.tdd-red` text → deny `(guard)`.

### A5: X25.*
- deny: `python3 - <<EOF` + `open("src/features/a/a.repository.ts","w")`; `node - <<EOF` + `fs.writeFileSync("src/x/x.mapper.ts")`; a `bash <<EOF` body naming `x.utils.test.ts`.
- ask `(guard)`: heredoc reading `src/a.ts`, `X8.01`, `X8.02`, `X3.01`-`X3.12`.
- `(guard)`: `X3.13`-`X3.16`, `X8.03` (`.tdd-red` reason unchanged), `X9.08` pass.

### A7: `fixtures/auto-approve-config.sh/`, `fixtures/protect-files.sh/`, `git-guard.jsonl`, `shell-guard.jsonl`; symlink branches with `project_dir=$tmp`
- no decision: `$P//.claude/worktrees/w/n.md`, `$P/./.claude/worktrees/w/n.md`, file symlink inside → outside, folder symlink `docs/ext/` → outside, `notes.md` with `cwd` outside the project (Q5).
- no decision `(guard)`: `$P/.claude/worktrees/w/package.json`, trailing `/..`, unset `CLAUDE_PROJECT_DIR`.
- allow `(guard)`: `notes.md` with `cwd` = project; frozen `02-worktree-config-allow.json`.
- deny: Read `.credentials.json`; `protect-files.sh` on a symlink inside → outside secret named `.env`; `git add .credentials.json` with setup `credfile`, reason naming the secret, so the row fails today (without the file, the dry-run already denies for the wrong reason); `cat credentials.json`, `cat .credentials.json` `(guard)`.

### A6: X26.*, setup `secrets` (on the `setup` key added at A3, matched exactly by the shell-guard branch, never by substring as `test-hooks.sh:174` does, so `secrets-sub` and `secrets-dot` get none of `secrets`' files; fake `.env`, `.env.example`, `server.pem`, `credentials.json`, `notes.txt` in `$tmp`, cwd `$tmp`)
- deny: `cat .en*`, `cat .e*`, `cat .?nv`, `cat .[e]nv`, `cat .e""nv`, `cat .e\nv`, `cat .{e,f}nv`, `cat serv*`, `cat cred*`, `cat */.e*` (setup adds `sub/.env`), `cat __FIXTURE_ROOT__/.e*`, `echo "$(cat .e*)"`, `grep --regexp=KEY .e*`, `grep -rne KEY .e*`, `cat < .e*`, `. .e*`.
- deny, setup `secrets-home` (`run_case` sets `HOME=$tmp`): `cat ~/.e*`.
- setup `secrets-sub` (`.env` only in `sub/`, none in `$tmp`): `cd sub && cat .e*` → deny; `cd "$X" && cat .e*` → ask (unknown directory, nothing found in `$tmp`).
- ask: `timeout 5 grep -r KEY .`, `nice grep -r KEY .`, `x=1 \grep -r KEY .`.
- deny: `tr -d x < .e*`.
- pass: `if grep -rq TODO src; then echo y; fi`, `{ grep -r KEY src; }`.
- deny `(guard)`: `cat .env.exam*` (`SECRET_RE`), `printenv && mkfs.ext4 /dev/sdb` (the disk deny stays first, its reason).
- ask: `printenv`, `env`, `set`, `rg -uu KEY`, `rg --no-ignore KEY .`, `rg --hidden KEY`, `command grep -r KEY .`, `\grep -r KEY .`, `/usr/bin/grep -r KEY .`, `env grep -r KEY .`, `find . -name x | xargs grep -r KEY`, `grep -rZ KEY .`, `grep -r --null KEY .`, `git grep --untracked KEY`, `git grep --no-exclude-standard KEY`.
- pass: `printenv HOME`, `cat .env.example`, `cat notes*`, `rg KEY src/`, `grep -rn KEY src/`, `grep -r KEY .`, `X9.03`, `X9.06`. Quoted patterns, under `secrets`: `sed -n 's/a.*b/c/p' notes.txt`, `sed -n '/^a/,/b*/p' notes.txt`, `grep 'a/b*' notes.txt`, `grep '.*' notes.txt`, `rg 'https?://x' src/`, `awk '/x.*/' notes.txt`, `grep -rn 'import .* from' src/`, `cat '.e*'`. Setup `secrets-dot` (only `.env` and `notes.txt`): `grep TODO *`, `head *`.
- Broken resolver `(guard)`: frozen X12 stays, `ls src` passes in all six states.
- `test-install.sh`: a target with its own `permissions.deny` keeps it and gains the kit's, with `Read(!.env.example)` still after `Read(.env.*)`. Re-run adds nothing. Held-back install keeps the deny.

## Vigilance (carried from research)
- `2>/dev/null` makes a write row: no gate command starts asking.
- `curl -o` and `mkdir -p` make no row: an uneven ask, not a claim of coverage.
- `guard_classify` outside the project and unset `CLAUDE_PROJECT_DIR` take the same return: unset must stay no verdict.
- `pnpm exec`/`npx` not wrappers today: A4's stripping brings them under A3's deny, so their rows live in A4.
- Readers emit no row; `SECRET_RE` is literal.
- `prevent-destructive-commands.sh:395` runs `-B`, not `-I`: the new secret mode runs `-I -B`. With `-I`, `shell_targets.py` must import nothing from `H`.
- `flags_column` `s:--force` on `clean` stays inert.
- `:885` skips `:887-889` only; no new rule goes after it.
- `effective_sub` keeps the first word only: `G13.23` and `G8.06` must hold.
- Alias reads, `dir_protected`, `branch --show-current` run with no `readable_git_dir`, not tested for fsmonitor. Review checks the new `git config --get` adds no new hole, and `rev-parse --show-toplevel` is the spec's measured call.
- `readable_git_dir`'s 1 s timeout sits outside the 2 s budget.
- `LC_ALL=C` must reach `grep`, not a `local` in bash.
- Empty `sha256:` counts as missing; `unavailable` checks `file_digest`.
- Api numbers stay single digit (`install.sh:215` fails open on `08`).
- `.git/*` reaches `protect-files.sh:181`; `:158` denies first.
- `protect-files.sh` `set -e`: every `cwk_real_rel` call uses `||`.
- `auto-approve-config.sh:70` never reads `.cwd`: that is a behaviour change, Q5.
- `run_case` defaults to the real repo: symlink and marker setups use `$tmp`.
- `kit-doctor.py:378` matches exact strings.
- The `git-guard` fixture repo has one commit: deny verdicts must not depend on `HEAD~1` resolving.
- `unique` on the deny union would put `!` first and carve nothing.
- `readable_git_dir`'s re-audit never concluded: A2's `git diff` inherits it. Local commit only, no push before the user's review.

## Acceptance criteria (carried from the entry artifact)
- [ ] The table below replays through `test-hooks.sh` fixtures.
- [ ] These are green: `test-hooks.sh`, `test-install.sh` (one hold-back case per guard-api bump), `test-kit-doctor.sh`, `test-attempts.sh`, `test-workflow-contracts.sh`, `test-rules-floor.sh`, `test-measure.sh`, `test-small-lane.sh`.
- [ ] `kit-doctor.py` reports no divergence.

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

## Research open questions and proposed answers (decided at the gate)
- **Q1** Which outside-project writes stay silent? `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/fd/*`, and non-recursive writes under `/tmp/`. `rm -r` in `/tmp` asks; `find /tmp/x -delete` has verb `find` and stays no verdict. Decides the Q1 pass rows of A4.
- **Q2** Sandbox or deny? Kit ships `permissions.deny` with the union. No `sandbox.enabled`: `autoAllowBashIfSandboxed` defaults to true and removes prompts, and its interaction with a hook `ask` is unmeasured. `ADAPTATION.md` states the gap (interpreters, `grep -r`) and that the sandbox works here (`bwrap` exits 0).
- **Q3** `Read(!.env.example)`: settled by the probe, works as written on 2.1.316, Read tool and `cat`.
- **Q4** `pnpm exec <writer>`, `npx <writer>` get the writer's rows: yes. Spec extension, decides A4's Q4 rows.
- **Q5** Relative auto-approve path with `cwd` outside the project: no decision.
- **Q6** `.git/*` replay: done on a scratch copy, all eight suites green, no frozen row moved.
- **Q7** (new, from planning) `pnpm build --outDir dist`: `dist` is a `PROTECTED_DIRS` root, so the spec's rule denies the tool's default output. Proposed: ask.
- **Update** `update-ref HEAD`, `update-ref --stdin` ask, beyond the spec's `refs/heads/*`: same hole. Decided by the A2 rows.
- **Q8** (new, measured) `git diff --quiet HEAD -- <p>` replaces the spec's `git diff --quiet -- <p>`: the spec's command exits 0 on a staged-only change, and `git checkout HEAD -- <p>` then destroys it. Side effect: `git restore <p>` on a staged file, which loses nothing, also asks. The spec's line is amended.
- **Q9** (new) `pnpm typecheck *` and siblings are the allowed route, so tsc's and config's asks also apply to package scripts, except runner builtins. Spec extension: it names vite, vitest, playwright, tsc.
- **Q10** (new) The spec's `dir_unread` on `--git-dir`/`--work-tree` is not coded: no observable effect, since `other_globals` catches `add` first, and destructive commands ask with those globals anyway (rows in A2). Spec amended.
- **Q11** (new) `timeout 5 git clean -fdx` and a destructive call beside an unparsable heredoc stay no verdict: stated gap, the spec targets a mistaken agent, and fixing it means rewriting `fallback_rows`. Goes to `harness-hardening.md`, Open follow-ups.
- **Q13** (new, measured) Spec's "a row proving the match is unchanged" holds for ASCII only: under `C`, `git commité` matches the scan and does not under UTF-8. It errs on the strict side, on a nonsense word. The row pins ASCII, the spec's line is amended.
- **Q14** (new) `glob.glob` replaces the spec's fnmatch on a listing: it applies bash's dot rule and directory patterns itself.
- **Q12** (new) Spec's fixture `ruff check --fix-only app` expects ask, its text says the `app/` exemptions stay, and `ruff check --fix app` passes today. Proposed: the text wins, `--fix-only` behaves like `--fix`. `ruff check --fix-only app` passes, `ruff check --fix-only .` asks. Spec's fixture amended.

## Plan critic
Pass 5, the user's decision (2026-11-02): M1, M2, the M3 mechanism and the pass-4 Minors applied; one quality check of those edits: quality 72, one Major (the marker *replaced* the backslash: moves X2.01-X2.04, X2.16, breaks quoting, would deny `find … -exec rm -rf {} \;` after A4), with its fix measured by the critic (insert before the backslash: zero row change on 158 rows). Applied with the six Minors (cfg exemption, `--dir`, exec-type bypass list, stdin target, exact setup match, header). Not verified again. Gate not cleared: the user decides.

Pass 4, the user's single pass (2026-11-02), applied pass-3 fixes and Minors first. FAILED, completeness 90, quality 72, recorded (count 4). No rewrite, the user decides.

Survivors after the verifier:
- **M1**, lines 92, 104: the package-script "not a path" exemption covers every cfg flag, so `pnpm test:run --root docs` and `pnpm typecheck -p docs` get no row. Measured on tsc 5.9.3 and vitest 2.1.9: they load an agent-written `docs/` config, and `tsc -p docs` wrote into `src/`. `--root .github/` gets a row, but `cwk_is_guarded` answers 0 for a folder above a guarded pattern (`hook-guarded.sh:62-63`), so no verdict while `.github/vitest.config.ts` is unguarded. Fix: judge a directory value by the config file it implies through `cwk_is_guarded`, never by the folder; exempt only a value that is not an existing directory; one row each.
- **M2**, line 222: `cd "$X" && cat .e*` under `secrets` gives dirs `[None, $tmp]`, the glob finds the fake `.env` in `$tmp`, the deny goes first. Fix: run it under the `sub/`-only setup, or expect deny.

Refuted: M3 (raw words). `Scan.run()` keeps the unquoted `\grep` in the flat text given to `walk_flat`, so the mechanism exists but is unnamed. Name a Scan-side marker for a leading backslash at line 118.

Minors, not verified: `cat < .e*` and `. .e*` escape A6; `timeout`, `sudo`, `nice` before `grep -r` are not bypass forms; `--emptyOutDir --mode x` takes `--mode` as value; `sed -n --expr=1p f.txt` asks today (needs its `_expect_reason`); `cat ~/.e*` needs a `HOME` override `run_case` lacks; A3's alias-dir rows need the `setup` key one step earlier.

Pass 3, BLOCKED, `plan-critic` failed 3/3 (2026-11-02). Scores: completeness 93, quality 76.

Survivors after the verifier, each with its minimum fix:
- **F1**, line 14: plain `setsid bash .claude/hooks/test-hooks.sh` returns 0 at once from the tool shell (measured 0.002 s, no output, suite still running), so RED and GREEN cannot be read. `setsid --wait` returned the real code (1 on a planted red row, 217 s). Fix: `setsid --wait` at line 14, and name it in the handoff.
- **F2**, lines 19, 178, 87, 14: the four A3 rows `pnpm exec rm -rf .git`, `npx rm -rf .git`, `pnpm -r exec …`, `pnpm --filter x exec …` still pass with `.git/*` denied, because runner stripping is A4's. A3 cannot go green. Fix: move them to A4's X24 list.
- **F3**, lines 113, 115, 117: `cat /abs/project/.e*`, `cat ~/.e*` and `cd sub && cat .e*` get no verdict and print a fake secret, while the literal spelling is denied. Fix: glob once per directory in `state.dirs` (`None` → ask) with `os.path.join(glob.escape(d), os.path.expanduser(pattern))`, one X26 row each.

Refuted: `echo "$(cat .e*)"` reaches the segment through `Walker`'s subs. No row pins it: add one with F3.

Minors, not verified: `--emptyOutDir` and `sed -n --file=x` have no row; line 14 does not classify `no decision` rows, so `$P//.claude/worktrees/w/n.md` need not be seen red; row `cat */.env` is denied today, use `cat */.e*`; `grep --regexp=KEY .e*` and `grep -rne KEY .e*` escape the pattern skip; `git restore -SW` unpinned; `cfg` asks on `pnpm dev -p 3000` and `pnpm test:run --project=unit`; reason text of the new denies undefined; plain branch switch after `cd` or a prior segment asks, no row; Q1's wording overstates `/tmp` (`find /tmp/x -delete` gets no verdict); shell-guard `setup` key introduced at A6, used at A4.

Pass-2 Majors all fixed. `exec_rows` `?glob:` moves no frozen row except the planned `X22.10` (799-case replay on a prototype, flag rows not prototyped).

Final scores: completeness 90 (pass 4), quality 72 (pass 5, its one Major fixed by the critic's measured wording, not re-verified). Gate `plan-critic` cleared on the user's explicit go at step 7, 2026-11-02, after four failed passes: the user's decision, not a clean critic pass.

## Gate
- 2026-11-02: `go`.
- Contract: `as written`, with the amendments Q4, Q8, Q9, Q10, Q12, Q13, Q14 (spec lines amended in the step of their section).
- Frozen-row amendment: `X22.10` pass → ask.
- Q1 `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/fd/*`, non-recursive `/tmp/` writes silent; `rm -r` in `/tmp` asks; `find /tmp/x -delete` no verdict.
- Q2 `permissions.deny` with the `install.sh` union, no `sandbox.enabled`; gap in `ADAPTATION.md`.
- Q3 `Read(!.env.example)` works on 2.1.316.
- Q4 `pnpm exec`/`npx <writer>` get the writer's rows.
- Q5 relative auto-approve path with `cwd` outside → no decision.
- Q6 `.git/*` replay done, eight suites green.
- Q7 `--outDir dist` asks.
- Q8 `git diff --quiet HEAD -- <p>`; `git restore <p>` on a staged file asks.
- Q9 package scripts get tsc's flag table.
- Q10 `dir_unread` not coded.
- Q11 `timeout 5 git clean -fdx` and a destructive call beside an unparsable heredoc stay no verdict, gap to `harness-hardening.md`.
- Q12 `ruff check --fix-only app` passes.
- Q13 locale match row pins ASCII.
- Q14 `glob.glob` replaces fnmatch.
- Q15 secret set covers multi-segment `.env.<mode>.local` (review 2/3): `\.env(\..+)?` minus `.env.example|sample|template` and `.env.<mode>.example|sample|template`.
- DA1 deny is now 12 entries: `Read(!.env.*.example)`, `Read(!.env.*.sample)`, `Read(!.env.*.template)` follow the three existing carve-outs. User-approved 2026-11-03 (fix batch 1); unmeasured on Claude Code (the 2.1.316 measurement covered only the three plain carve-outs).
