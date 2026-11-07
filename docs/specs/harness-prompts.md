# Spec: Fewer permission prompts, same guardrails
Token profile: critical (it widens what runs without a prompt)
Split from: `docs/specs/harness-hardening.md` Phase 4. Rewritten 2026-10-29, then corrected 2026-10-30 and 2026-11-01 after further reviews and refutations.
Needs:
- `65facf8` (`acceptEdits`, P1 allows, hold-back, git grammar).
- From `docs/specs/harness-hooks.md`: the guard-api bump clause of A0; A2's fetch half (refspecs, `--refmap`, `--upload-pack`); A4's outside-project, resolution-base, tsc, config and flag-row parts. A4's fix flags and A5 are not needed: no allow below reaches `pnpm lint *`, `eslint` or `ruff`, and no row cites A5. The allows are safe only because those hooks police the dangerous forms, and a hook `ask` overrides an allow rule (measured, `docs/research-cache/claude-code-permissions.md:27-31` and `:84-92`).

## Objective
Remove the prompts that guard nothing, on a target project and in this repo.

Source: the prompt audit of 2026-10-29, which read the Bash heads from the last 10-15 sessions of LoopKit and ecocrew. Most prompts come from the native allowlist. A large share come from the agent writing files through interpreters, which prompts twice.

Rule for every allow below:
- it runs code already allowed today in another form (`pnpm test:run *` runs agent-written tests silently), or a kit script named exactly, under a guarded path;
- every dangerous flag **and every config it loads from an unguarded path** is caught by a hook ask or deny (the harness-hooks parts named under Needs).

Contract labels are prefixed `HP-` so they never collide with the existing `K1`/`K1b`/`K1c` in `test-workflow-contracts.sh`.

## B1. The agent writes files through Write/Edit, never through an interpreter
- **Today.**
  - Write sessions: about 120 `python3 - <<EOF … open(p,'w').write(s)` in LoopKit and 86 in ecocrew, plus `sed -i` and `cat >`. Each one prompts natively, then again through the hook's "unresolved write target" ask.
  - `CLAUDE.md:50` names redirection, `tee` and `sed -i`, but not interpreters.
  - Suite runs are spread over `for` loops, `bash -x`, `timeout 200 bash …`, direct paths and `2>&1`.
- **Change.**
  - `CLAUDE.md:50`, same line:
    - name `python3 -`/`-c`, `node -e`, `perl -i` and heredocs;
    - say that a guarded-path ask is answered by the user, never by switching tools.

    Net +0 or +1 line: `CLAUDE.md` is at 138/140 and `test-rules-floor.sh` at 514/520. Reading and computing with an inline program stay allowed.
  - `.claude/agents/implementer.md` and `test-writer.md` carry the same one line.
  - `docs/Claude_Workflows.md`, `## Hors boucle` (`:452`): one suite per call, in the form `bash .claude/hooks/test-<name>.sh`. No `for` loop, no `bash -x` (debug by hand). This is the form B2 allows. The file ships to targets (`install.sh:629`), and the line is accepted there.
  - Hook ask reasons gain "Write files with the Write/Edit tool instead." **only if DB1 shows the reason reaches the model**. Otherwise they stay unchanged.
- **Contracts** (`test-workflow-contracts.sh`):
  - `HP-B1`: `CLAUDE.md` names `python3 -` and `node -e` on the shell-write line, both agent files carry the line, and `Claude_Workflows.md` names the suite form.

## B2. Allowlist widened with exact forms
- **Today.** These are unlisted, so they prompt:
  - `pnpm vitest …` (124 calls in ecocrew), `pnpm exec …` (109), `uv run …` (118);
  - `python3 .claude/hooks/kit-attempts.py` (44 + 32);
  - the small-lane scripts, the kit test suites, `git fetch`.

  `git worktree add` prompts too, and keeps its prompt: the git grammar asks on it before any allow applies (measured, frozen G14.70).
- **Change.** `.claude/settings.json` `allow` gains, verbatim:

  | Allow | Why it is safe |
  | --- | --- |
  | `Bash(pnpm vitest run *)`, `Bash(pnpm exec vitest run *)` | No wider than `pnpm test:run *`. A4 asks or denies the delete and write flags and `-c`/`--config`/`--root`/`--dir`. |
  | `Bash(pnpm exec tsc --noEmit)`, `Bash(pnpm exec tsc --noEmit *)` | The space before `*` keeps `--noEmitOnError` out. A4 catches `--noEmit false`, `--tsBuildInfoFile` and `-p <unguarded>`. |
  | `Bash(pnpm exec playwright test *)` | A4 catches `--output` and `-c`. `playwright.config.*` is guarded (A4). |
  | `Bash(python3 .claude/hooks/kit-attempts.py *)`, `Bash(python3 .claude/hooks/kit-doctor.py)`, `Bash(python3 .claude/hooks/kit-doctor.py *)` | Kit scripts, named exactly, under a guarded path. |
  | `Bash(.claude/scripts/small-dispatch-check.sh *)`, `Bash(.claude/scripts/small-paths.sh *)`, `Bash(.claude/scripts/small-plan.sh *)`, `Bash(.claude/scripts/small-scope.sh *)` | Exact names. No `*` before `.sh`, because a middle `*` matches `/..`. |
  | `Bash(bash .claude/hooks/test-<name>.sh)` and `Bash(bash .claude/hooks/test-<name>.sh *)`, for each of the eight suites: `attempts`, `hooks`, `install`, `kit-doctor`, `measure`, `rules-floor`, `small-lane`, `workflow-contracts` | Exact names. |
  | `Bash(git fetch)`, `Bash(git fetch *)` | A2 asks on refspecs and `--refmap` into a local branch, and on `--upload-pack`. |
  | `Bash(git stash list)` | |

  - **Never listed:**
    - `pnpm exec *`, `uv run *`, `python3 *`, `node *`;
    - `bash *`, `bash -x *`, `mkdir -p *`, `sed -i *`;
    - `git switch *`, `git branch *`, `git worktree add *`, `git worktree remove *`;
    - any rule with a `*` inside a path.
  - **Accepted over-match.** An allowed call still asks when an argument puts `git` next to `add`, `commit` or `switch`: `git fetch origin feat/add-x` and `kit-attempts.py fail docs/work/git-x/plan.md review "add a test"` (measured). The same is inferred, not measured, for the small-lane and suite allows.
  - **fastapi addon.** `add_py_hooks` in `install.sh` gets `Bash(uv run ruff check .)`, `Bash(uv run ruff check app)`, `Bash(uv run ruff check app/)`, `Bash(uv run mypy app)` and `Bash(uv run pyright)`.
    - They are exact forms, next to today's bare `ruff check` forms, and they take no flag, so they depend on no hook.
    - They are **not** in `PROMPT_ALLOWS` and not in the `settings.json` check.
  - **`kit-attempts.py`** refuses an artifact whose resolved path does not hold the consecutive components `docs/work`, and a `--board` whose resolved path does not hold `docs/product`. A prefix or project-root check would break `test-attempts.sh:8,14`, which passes an absolute `$SCRATCH/docs/work/…`. Today it creates `attempts.json` in any folder and rewrites a row of any file (`kit-attempts.py:24-28, 63-101`).
- **Install.**
  - A new `PROMPT_ALLOWS` array in `install.sh` is held back under the same condition as `P1_ALLOWS`: not added on a stale guard api, and removed if a previous install added it.
  - `P1_ALLOWS` stays the five git allows, so `K1b` is untouched.
  - The A2 and A4 hook files are in `GUARD_FILES` with bumped numbers (harness-hooks A0's bump clause), so a target without them never gets these allows.
- **Contracts and fixtures.**
  - `HP-B2` (`test-workflow-contracts.sh`):
    - every allow above is present verbatim in `settings.json`;
    - `PROMPT_ALLOWS` equals that set;
    - none of the "never listed" forms is present;
    - `install.sh`'s `add_py_hooks` holds the five `uv run` forms.
  - `test-install.sh`:
    - a held-back install has none of `PROMPT_ALLOWS`;
    - a current install has all of them;
    - on hold-back, a previous install's `PROMPT_ALLOWS` is removed and the target's other allows are kept.
  - `test-attempts.sh`: an artifact `.claude/hooks/x.md` → refused; a board `src/a.md` → refused; an absolute `$SCRATCH/docs/work/…` → accepted.
  - `test-hooks.sh`: every new allowed command form is run with every A4 flag that applies, in `=` and space forms, and gets A4's verdict:
    - `pnpm vitest run --coverage.reportsDirectory=src` → deny
    - `pnpm exec playwright test --output src` → deny (`src` is a protected root)
    - `pnpm exec playwright test --output e2e` → ask
    - `pnpm exec tsc --noEmit --tsBuildInfoFile src/a/a.utils.test.ts` → deny
    - `git fetch origin main --refmap='+refs/heads/*:refs/heads/*'` → ask
    - `git worktree add .claude/worktrees/../../x -b y` → ask (already green, the grammar's last ask)

## B3. Prompts on the kit's own hooks in this repo: not changed
The `.claude/.kit-dev` exemption (old H14) is dropped, for three reasons:
- **It covered the guard code itself.** One silent Edit of `hook-guarded.sh` disables every guard.
- **It allowed silent writes followed by a silent run** of a new `test-x.sh` or a stdlib-shadowing `json.py`.
- **acceptEdits probably prompts on `.claude/` natively anyway** (`claude-code-permissions.md:13`, documented, not measured).

Edits of `.claude/hooks/*` keep one prompt each, and B1 removes the second prompt that an interpreter write added. B3 is reopened only on a measured DB2 showing the native prompt is absent, and even then never for guard files.

## Decisions to take before EXECUTE
- **DB1.** Is a PreToolUse `ask` reason shown to the model, or only to the user?
  - Method: one headless run (`claude -p --output-format json`, `--settings` naming the fixture hook) that asks with a marker string, then check the transcript. Headless cannot show the interactive case, so a marker absent from this run leaves the question open: the reason stays unchanged.
  - Decides B1's hook-reason half.
- **DB2** (informational, does not block). With `acceptEdits` and no hook, does a headless Edit of `.claude/hooks/x.sh` trigger the native prompt? The answer is recorded in the research cache.
- **DB3.** Is `bash .claude/hooks/test-hooks.sh 2>&1` matched by `Bash(bash .claude/hooks/test-hooks.sh)`, or only by the ` *` form?
  - Method: one headless run per form, with `--settings` holding only that allow.
  - If neither matches, B1's documented form drops `2>&1`.

## Order
DB1, DB3 → B1 → B2.

## Measure
- **Method.** A one-off script, kept in the plan and not shipped, classifies every Bash `tool_use` of a session statically:
  - "prompted, native": the command is not matched by the allow list in force, judged per compound part, with the read-only built-ins exempt;
  - "prompted, hook": the hook harness replay returns ask;
  - "interpreter write": `python3 -`/`-c`, `node -e`, `perl -i`, `sed -i` or `cat >` writing a file.

  Results are given per 100 Bash calls. `permissionDecision` fields in the transcript confirm the hook column where present.
- **Before.** The five most recent ecocrew sessions at the start of the pass, session ids listed in the plan, classified against today's allow list.
- **After.** The first five ecocrew sessions after B ships, classified against the new list.
  - Precondition: ecocrew's `CLAUDE.md.new` and agent `.new` files are merged, so the B1 line is in force.
- **Target.**
  - Interpreter writes: at most 1 per 100 Bash calls.
  - Native-allowlist prompts per 100 Bash calls: at least halved.

  Below target, B2's list is reopened with the after-sessions.

## Done when
- `HP-B1` and `HP-B2` are green, and so are `test-hooks.sh`, `test-install.sh`, `test-attempts.sh`, `test-workflow-contracts.sh` and `test-rules-floor.sh`.
- `kit-doctor.py` reports no divergence, and `CLAUDE.md` is within its budget.
- The measure is recorded in the plan's `## Gate`.

## Out of scope
- Compound commands (`cd X && …`) still match per part (`claude-code-permissions.md:16-17`). B1 only asks for one suite per call.

## Amendments (harness-prompts plan, 2026-11-04)
- **B0 prerequisites** (plan Q10, user go): B0a dangling `\` read as a literal backslash; B0b snapshot flags ask; B0c `--generateCpuProfile`, `--last-failed-file`, `--attachmentsDir`, `--coverage.htmlDir` writers, `--coverage.thresholds.autoUpdate` and `tsc --init` ask, `--clearCache` asks; B0d a parse failure asks for runners and `fetch`; B0e `git fetch` resolved against git 2.43's pinned option list (tags, stash, notes, `-P`, `--force`, `--stdin`, `--set-upstream`, shallow options, `--filter`, unknown or ambiguous options ask); B0f substitutions inside `$((…))` and process substitutions scanned. Guard api 3 on `shell_targets.py`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`; `kit-attempts.py` api 1 joins `GUARD_FILES`.
- **D0 measured** (`claude-code-permissions.md`, CLI 2.1.318): the ask reason reaches the model (so B1's reason line ships); `2>&1` is matched by the bare allow; a dangling `\`, `$'…'`, `$(( $(…) ))` and `<(…)` do not match a ` *` allow.
- **B1 doc form**: `Claude_Workflows.md` names concrete suites (`bash .claude/hooks/test-hooks.sh`, …): kit-doctor reads a `<name>` placeholder under `.claude/` as a missing path.
- **B0c is a safe-option allowlist** (review 2 FAIL, user decision 2026-11-04): for vitest, vite, playwright test, tsc and their package scripts (`test:run`, `test:coverage`, `typecheck`, `build`), an option word passes only when it is spelled exactly as a listed safe option or a listed checked option (its existing flag-w/flag-r/cfg/snapshot/cfg-write/cache-clear row applies); any other word starting with `-` (a bundle, `---x`, an empty `=`, an unlisted dotted key, a value on a boolean) asks, its reason quoting the word and naming the hook's safe-option list. Exceptions kept: kebab aliases of listed checked options, tsc case/single-dash folding, recorded loaders (`--diff`, `--tsconfig`). A tsc `@file` asks for scripts too.
- **Review 3 FAIL, ceiling overridden** (user decision 2026-11-05: fix, then a review scoped to the fix, then move on). Fix batch Critical + Major, Minors deferred: (1) for mri tools (vite, vitest, their scripts) a word starting with `-` is never taken as an option's value, it is read as its own option (tsc and commander keep consuming it); (2) `--diff` leaves the safe list and asks (`data:` URLs run inline code), the `--diff` loader exception above is withdrawn; (3) NAME options (`--reporter`, `--coverage.reporter`, `--environment`, `--pool`, playwright `--reporter`) pass only built-in names, a bare name may resolve to a local module; (4) a positional of `vite build`/`pnpm build` asks (it is vite's root and loads its config); (5) a word starting with an unquoted glob character asks for these tools (it may expand to an option); (6) `kit-doctor.py` with a root argument asks, and kit-doctor runs git with `core.fsmonitor` off. Rows X24.370-392, G17.78-81.
- **Review 4 FAIL → targeted batch, review 5 FAIL → argument allows retired** (user decisions 2026-11-05). Batch: per-script parser (`SCRIPT_TOOL`), mri only vite/vitest, real reporter lists, consumed/leading glob asks (rows X24.393-410). Review 5 measured new holes in every round (vitest NAME values not comma-split, `html` → planted `@vitest/ui/reporter.mjs`, glob as `=` value, attached `-c` on vitest scripts, `pnpm lint -o`/`-*`, `typecheck`=`tsc -b` positional, `build`=`tsc`): a script name does not tell the hook which parser runs. **Decision A**: the kit ships no argument wildcard for `test:run`, `test:coverage`, `typecheck`, `lint`, `build`, `vitest run`, `exec vitest run`, `exec tsc --noEmit`, `exec playwright test`; `install.sh` removes them from a target on every install; bare forms stay (DB3: `2>&1` still matches). B2's runner rows above are withdrawn; `PROMPT_ALLOWS` is 27 entries. `shell_targets.py` tables stay as defence in depth under a user's own allow; their open findings (`.kit-health.jsonl` 2026-11-05T18:03:28Z) are follow-ups, not blockers. Test contract changes: `test-install.sh` hold-back (b) and A0 merged-back `gates_wild_all` → `gates_wild_none`, HP-A block; `test-workflow-contracts.sh` HP_WANT 31 → 27 + retired forms forbidden. Confirm at the merge.
- **Ship stopped by the authz audit, fix batch** (user decision 2026-11-05). C1: every kit `python3 -`/`-c` call takes `-I` (a planted root `re.py`/`json.py`/`pathlib.py` was imported under the allowed small scripts and suites). C2: root `install.sh`, `workflow.py`, `workflow.sh`, `codex-handoff.sh` join `CWK_GUARDED`; the test-install and test-workflow-contracts allows stay in the kit and never ride to a target, `PROMPT_ALLOWS` 27 → 23. M1: `git fetch` asks on a repository that is not a bare remote name or that names a path, and on `-o`/`--server-option`. New rows: G17.82-95, X24.411-412, protect-files 38-41, small-lane Q6, contracts "Ship audit C1/C2", install hp-kitdev. Test contract changes: HP_ALLOWS/HP_WANT 27 → 23 (suites install, workflow-contracts out of the target list); C1 exception: the one-token `-I` change on the frozen lines `test-hooks.sh:60,78,97`, `test-small-lane.sh:564`, `test-workflow-contracts.sh:239`. Confirm at the merge.
- **Review 6 FAIL → targeted batch, no 7th review** (user decision 2026-11-06). C2 extended: `addons/*` joins `CWK_GUARDED` (the allowed `test-hooks.sh` runs `addons/fastapi/hooks/*.py`); `hook-guarded.sh` goes api 2 → 3 (the list grew, A0 bump clause), so a stale target copy holds P1 and the prompt allows back. C1 extended: `workflow.sh` runs `python3 -I` (the launcher imported a planted root module). Text: the shell-guard fallback ask and `ADAPTATION.md` §14 name the root launchers and `addons/`; `Claude_Workflows.md` says the kit-dev suites are not allowed in a target. New rows: protect-files 42, X24.413-415, install A9, contracts "Review 6 workflow.sh". Deferred to `harness-hardening.md` follow-ups: planted bare repo + `cd` + `git fetch` (`readable_git_dir` on fetch), nested `docs/.claude/` copies, symlink to a guarded file, `pnpm audit --registry` egress, kit-dev guard entries (`install.sh`, `addons/*`) shipped to targets. Confirm at the merge.
- **Ship audit 2 (authz) Major → fix batch, then ship, no 7th review** (user decision 2026-11-06). The new allows are cwd-relative, so a nested `docs/x/.claude/` copy ran under `cd docs/x && bash .claude/hooks/test-hooks.sh` with no prompt. Rule `kit-cwd`: a kit script run by a relative `.claude/hooks/` or `.claude/scripts/` path asks unless the effective cwd (hook `cwd` after `cd`/`pushd`/`env -C`) is the project root or a `.claude/worktrees/<n>` root; an unknown cwd asks. Minor: xargs feeding `kit-doctor.py` asks like an explicit argument. Rows X24.416-432. Confirm at the merge.
- **Ship audit 3 (authz) 2 Majors → fix batch, then ship, no 7th review** (user decision 2026-11-06; the 3 Minors go to `harness-hardening.md` follow-ups). M-A: a `.claude/worktrees/<n>` root counts only when git registered it (a `<project>/.git/worktrees/*/gitdir` names `<n>/.git`); a copied folder, a `cp -r` of a real worktree or a missing dir asks. M-B: the cwd the hook checks is the one bash reaches: `cd -P`/`pushd -P`, `set -P`/`set -o physical`, and `env -C` resolve physically (or count as unknown when a symlink lies on the way); a plain logical `cd` keeps passing. A physical cd also leaves `$PWD` on the physical path, so a later logical `cd ..` starts from there (main-thread check of the GREEN: `cd -P node_modules/foo && cd ../..` ran the planted copy). Rows X24.429-430 amended pass → ask, new X24.433-447. Confirm at the merge.
- **Ship audit 4 (authz) 3 Critical → `kit-cwd` simplified, no cwd model** (user decision 2026-11-06; same pattern as decision A: each fix of the cwd tracking opened new holes — cd after `||`, cd in a pipeline, `cd -PL`, `set`/`shopt` modes, `! cd`). A kit script run by a relative path passes only when the directory is known without modelling bash: the hook `cwd` is the project root or a git-registered worktree root, and no `cd`, `pushd`, `popd`, `set`, `shopt`, `env -C`/`--chdir` or `CDPATH=` comes before it in the command. One exception: the command's first segment is `cd <absolute path>` with no option and no expansion, followed directly by `&&`, and that path is the root or a registered worktree root; then that path is the cwd. Everything else asks (relative `cd` included: no kit doc uses it). The `strict` tracking and the physical mode go. Minors in the batch: a relative `gitdir` resolves from its `.git/worktrees/<n>/` folder; X24.443 used `pushd -P`, which bash rejects. Amended pass → ask: X24.432, 434, 444, 447; X24.443 command → `cd -L -P …`. New rows X24.448-462 (setup `kitwtrel`). Confirm at the merge.
- **Ship audit 5 (authz) conditional Major → "nothing runs before the kit"** (user decision 2026-11-06). The mover list missed `function ls { cd x; }; ls && …` and `trap … DEBUG` (hook pass, bash ran the planted copy), and its Minors (`source`, `BASH_ENV=`, `$'cd'`, `find -execdir`, `env -iC`) showed a denylist of verbs stays incomplete. Rule, an allowlist of positions: a kit script run by a relative path passes only (a) as the command's first segment, with no assignment and no wrapper before its verb (`bash`/`sh`/python verb with the kit path as its script, or the kit path itself), the hook `cwd` being the root or a registered worktree root; or (b) as the second segment right after a first segment literally `cd <absolute path, no option, no expansion, no ..>` joined by `&&`, that path being the root or a registered worktree root. What follows the kit script does not matter (it has already started), so `cd <abs root> && bash … 2>&1 | tail` passes. A kit script found anywhere else (later segment, substitution, `find -execdir`, xargs, wrappers) asks. Also: a root or worktree must match lexically as well as by `realpath` (`cd /proc/self/cwd` resolved in the hook process); a registered worktree needs its `<dir>/.git` file to name its registry entry back (a stale entry asks); the kit-cwd ask has its own text naming the risk ("not the project root or a registered worktree"). New rows X24.463-477 (setup `kitwt` gains a stale entry). Confirm at the merge.
