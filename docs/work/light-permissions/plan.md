# Plan: Light loop without permission prompts   (entry: docs/specs/light-permissions.md · research: docs/work/light-permissions/research.md · design: n/a)
Token profile: critical

## Skips
- Interface : SKIP — kit hooks and settings, no user surface.
- DB, Backend, Front app layers : SKIP — `Data model: none`, `Custom backend: NONE`, no `src/`. The TDD hooks do not key on `.claude/` shell: test-first is by hand — every fixture of a step is written first and **observed failing on its own verdict** (`FAIL <hook> / <fixture>: expected <x>, got <y>`) before the hook code it covers changes.

## Write chain (sequential)
0. **Spike S0** (before any code; Open question 5). Scratch project under the session scratchpad: `git init`, one seed commit, `.claude/settings.json` with `defaultMode: acceptEdits`, allow `Bash(git commit -m *)`, and a throwaway PreToolUse hook (Write|Edit and Bash) that appends `<tool>\t<input>` to `hook.log` and returns `ask`. Each case is one `claude -p --permission-mode acceptEdits --output-format json --max-turns 2 --tools <only the tool under test>` run (`--tools` restricts the toolset; **no `--allowedTools`**, so the only allow rule is the scratch settings' `Bash(git commit -m *)`), with a prompt naming one exact tool call, plus a **control run without the hook**:
   - (a) Write `vite.config.ts`; (b) Bash `git commit -m x --amend --allow-empty` (allow rule matches); (c) Bash `sed -i 's/a/b/' vite.config.ts` (acceptEdits' own Bash auto-approval).
   - Verdict per case from the JSON `permission_denials` for that tool_use and `hook.log` (the hook fired); the control must show the call approved. "ask overrides" = hook logged + denial listed + control approved. Any case that does not override, or is indeterminate: EXECUTE stops, the user decides (deny-with-text instead of ask) before step 1. Results go to `docs/research-cache/claude-code-permissions.md` and `## Gate`.
1. **`hook-guarded.sh` + `hook-lib.sh`** — [H8 RED → GREEN], then hook-lib sources it **fail-closed for PreToolUse guards only**: a hook sets `CWK_GUARD_HOOK=1` before sourcing hook-lib; a failed `source` then prints `BLOCKED: hook-guarded.sh missing` and exits 2; any other hook (`eslint-batch.sh` on Stop/SubagentStop, PostToolUse hooks) warns on stderr and continues. Harness case H8b.
2. **`protect-files.sh`** — [H3, H4, H7-write RED → GREEN].
3. **`prevent-destructive-commands.sh` + `shell_targets.py`** — [H5, H5b, H5c, H5d, H9, H10, H12, H13-shell, H7-run, H16 ordering RED → GREEN]; text at `:101` updated.
4. **`enforce-git-workflow.sh`** — [H1, H2, H13-git, H6, H11, H16-git RED → GREEN]; text at `:70` (`git checkout -b` → `git switch -c`) updated.
5. **TDD deny texts** — `tdd-require-red.sh:179-223`, `tdd-freeze-tests.sh:387,390` gain "this write will ask the user"; [T1 RED → GREEN] (`_expect_reason` on one existing deny fixture of each).
6. **`.gitignore`, `install.sh`** — [H14, I-P1 RED → GREEN in `test-install.sh`]: `*.pem`, `*.key`, `credentials.*` (kit file, heredoc, back-fill); `install_settings` holds back P1 when the guard hooks did not land.
7. **`kit-doctor.py`** — `NON_HOOKS` += `hook-guarded.sh`, `shell_targets.py`.
8. **P1 last** — `.claude/settings.json` (`defaultMode` + 5 allows), `.claude/agents/github.md` forms; [K-P1, H15 contract greps RED → GREEN in `test-workflow-contracts.sh`]. Last, so this session runs steps 1-7 under today's permissions.
9. **P3 docs + Measure method** — `docs/ADAPTATION.md` (install merge and the P1 hold-back, guarded set prompts, kit-development prompts, the measure method), `docs/Claude_Workflows.md` (prompts left on a light pass, French).
10. **Smoke S1** (AC 1, before merge) — scratch target: `git init -b main`, a `package.json` with `"test:run": "true"`, a seed commit, `git switch -c feat/x`, then `install.sh` into it (fresh install, P1 merged). Then headless `claude -p --output-format json --max-turns 2 --tools <Write|Bash>` runs (no `--allowedTools`, no `--permission-mode` flag: the installed `defaultMode` applies), one tool call each, in order: Write `src/x.ts`; `git add src/x.ts`; `git commit -m "x"`; `pnpm test:run` → each absent from `permission_denials` and its effect observed (file, staged, commit, exit 0); `git push`, `gh pr list`, `git commit -m x --amend`, `git switch -c y --discard-changes` → each present in `permission_denials`, and for `--amend`/`--discard-changes` the hook's own ask reason is the one recorded (not the protected-branch deny). No remote, no gh auth in the scratch.
11. **Tests** — every `kit-ci.yml` suite + doctor.
12. **Refactor** — dedup between the shell hooks and `shell_targets.py`, suite green, no fixture edited.

## Parallel lots (inside this track, same tree)
none — fully sequential (every hook sources `hook-lib.sh`; steps 2-4 share `hook-guarded.sh` and the fixture runner).

## Track isolation
- Worktree: none, single track (main tree, branch `audit/slim`).
- Shared foundations touched: `.claude/settings.json`, `hook-lib.sh` and the guard hooks, `install.sh`.
- Kit-development cost (H15): from step 2 on, every Write/Edit of a hook, fixture, script or settings file in this repo **asks the user**. Expected and announced.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/hook-guarded.sh` | Create | sets, `cwk_guard_rel`, `cwk_is_guarded`, `cwk_is_guard_denied`; no side effect |
| `.claude/hooks/hook-lib.sh` | Edit | sources `hook-guarded.sh`, fail-closed |
| `.claude/hooks/protect-files.sh` | Edit | `ask` emitter; guarded ask, denied deny, resolved paths |
| `.claude/hooks/shell_targets.py` | Create | shlex tokeniser of a Bash command: per segment, the write targets and unknown operands, `cd`/`pushd` tracking; prints rows `deny|ask \t reason` |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | deny pass then ask pass; calls `shell_targets.py`; recursive rm/mv ask |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | args column; commit/switch/checkout/add rules; dry-run; PARSE_FAILED `add` deny |
| `.claude/hooks/tdd-require-red.sh`, `.claude/hooks/tdd-freeze-tests.sh` | Edit | deny texts |
| `.claude/hooks/test-hooks.sh` | Edit | per-name setup: worktree project dirs, cwd placeholders, git fixture files, slow/failing `git` shim; H8/H8b harness cases |
| `.claude/hooks/fixtures/{protect-files.sh,prevent-destructive-commands.sh,enforce-git-workflow.sh}/*` | Create | `NN-hX-<what>-<verdict>.json` |
| `.claude/hooks/test-install.sh` | Edit | H14, I-P1 |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | K-P1, H15, T1 greps |
| `.claude/hooks/kit-doctor.py` | Edit | `NON_HOOKS` |
| `.gitignore`, `install.sh` | Edit | secret patterns; P1 hold-back |
| `.claude/settings.json`, `.claude/agents/github.md` | Edit | P1 |
| `docs/ADAPTATION.md`, `docs/Claude_Workflows.md` | Edit | P3, measure method |

## Contracts
- **Sets** (repo-relative, matched with bash `[[ == ]]`: `*` **crosses `/`** — an over-match, never an under-match; no `shopt` is set outside a function-local scope): guarded `.claude/hooks/*`, `.claude/scripts/*`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.*`, `eslint.config.*`, `vite.config.*`, `package.json`, `tsconfig*.json`, `.github/workflows/*`; denied `.claude/.tdd-red/*` and `.claude/.tdd-red`.
- `cwk_guard_rel <path> [<base>]`: relative paths are joined to `<base>` (callers pass the input `.cwd`, else `$CLAUDE_PROJECT_DIR`; **never `$PWD`**); then, on **both** branches, lexical normalisation (`//`, `/./`, `..` collapsed); then strip `$CLAUDE_PROJECT_DIR/` or its `pwd -P` form; failing both, the `realpath` of the path's deepest existing parent is compared with `pwd -P` of the project (a symlinked alias of the project resolves inside); then a leading `.claude/worktrees/<x>/` is stripped; outside → prints nothing, exit 1. `cwk_is_guarded <rel>` / `cwk_is_guard_denied <rel>` take an **already repo-relative** path, resolve nothing, print nothing, write nothing (H8).
- **protect-files.sh** (Write|Edit only; Read/Grep/Glob unchanged): resolves with `cwk_guard_rel "$FILE_PATH" "$(jq .cwd)"`; denied → deny `BLOCKED: .claude/.tdd-red/ is written only by tdd-prove-red.sh`; guarded → ask `guarded path: <rel> (kit guardrail; approve only if you meant to change it)`. Existing denies run first.
- **shell_targets.py** (`python3 -B`): input the command and the base dir. Heredoc bodies are cut before tokenising (the `<<[-]WORD` line keeps its redirect, the body up to `WORD` is dropped); then shlex per segment, segments split on `;`, `&&`, `||`, `|`, `&`, newline, `(`, `)`, `{`, `}`; `$(…)` and backticks — **also inside double quotes** — are recursed into as their own commands; strips, before the verb, the git parser's wrapper set (`enforce-git-workflow.sh:108-109,243-245`) plus `do`, `then`, `else`, `elif`, `if`, `while`, `until`, `!`, `time`, `sudo`, `exec`, `stdbuf [-oL…]`, `setsid`, `xargs [opts]`, `env [-i] [VAR=x…]`, `nice [-n N]`, `nohup`, `timeout [-k N] [-s SIG] N`, `command`, `builtin`; tracks `cd`/`pushd`/`popd`, **scoped to the enclosing `( … )`** (to an unknown dir or `-` → later relative targets unknown). **Failure is not a pass**: python3 missing, the script missing, a nonzero exit, empty or malformed output, or a shlex `ValueError` → prevent-destructive denies when the raw text names `.claude/.tdd-red`, else asks when it names `.claude/`, a guarded root file, or contains a heredoc or a writer verb, else passes. Writer verbs and target position: redirect `>`, `>>`, `>|`, `&>`, `>&file` (not `>&N`, not `2>&1`); `tee` args; `cp`/`install`/`ln`/`rsync` last operand or `-t`/`--target-directory`; every operand of `mv`, `rm`, `rmdir`, `unlink`, `shred`, `truncate`, `touch`, `chmod`, `chown`; `patch` target; `sed`/`perl` with `-i`/`--in-place`* → their file operands; sed scripts with `w`/`W` file or `s///w file` or `e` → that file (or ask for `e`); `--output[=]`; `find … -exec|-execdir|-ok|-okdir|-delete|-fprint*|-fls` → the find roots + named file; interpreters `python*`, `node`, `perl`, `ruby`, `bash|sh|zsh -c`, `eval` with an inline program → ask (target unknown), **except** that the inline program text is scanned for a denied path (`.claude/.tdd-red`) and a match is a deny; `rg --pre`/`--pre=` → ask always. A target that is unknown (`$`, backtick, `$(`, an unknown cwd) for a writer verb → ask; a **glob** target → ask only when its literal prefix (up to the first glob char) resolves inside the project and could reach a guarded path or a protected dir (`rm /tmp/x-*` and `sed -i … src/*.ts` pass, `cp x .claude/hooks/*` asks). Output rows: denied target → `deny`, guarded → `ask`, unknown → `ask`. Single- or double-quoted text with no `$(`/backtick is data (`git commit -m "note > package.json"` passes). Running a script with arguments is not a writer verb (H7, H10).
- **prevent-destructive-commands.sh**: **deny pass over all segments first** (existing denies, `shell_targets` deny rows), **then one ask pass** (existing asks, `shell_targets` ask rows, recursive `rm`/`mv` under a protected dir). Recursive = a token `-[a-zA-Z]*[rR][a-zA-Z]*` or a prefix of `--recursive` anywhere among the `rm` arguments; `mv` of a path under a protected dir always counts.
- **enforce-git-workflow.sh**: row gains an args column (tab-safe). Long flags by unique prefix, short flags unbundled, anywhere: commit `--amend`, `--no-verify`, `--all`, `-n`, `-a` → ask; switch/checkout `--discard-changes`, `--force`, `--force-create`, `-f`, `-C` → ask. **Deny pass**: add `--force`/`-f`; add with `$(`, backtick, `$`, `--pathspec-from-file`, `--pathspec-file-nul`; then the dry-run, run **inside the python block** with `subprocess.run(["git","-C",dir,"add","--dry-run",*args], timeout=2)` — the user's arguments in their order, **no inserted `--`** (no coreutils `timeout`) — deny on timeout, nonzero exit, or a listed path matching `.env*` (except `.env.example`/`.env.sample`/`.env.template`), `*.pem`, `*.key`, `credentials.*`; PARSE_FAILED and some line has `add` **in subcommand position** (after `git` and its global options) → deny `unreadable git add`. Ask pass after.
- **install.sh `install_settings`**: P1 is **held back** when, after the copy, any of the target's `hook-lib.sh`, `hook-guarded.sh`, `shell_targets.py`, `protect-files.sh`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh` is missing or **differs from the kit copy** (`cmp -s`; an identical file that landed as `.new` does not count). Held back = the kit's `permissions.defaultMode` and the 5 P1 allows are **not added from `$new`**; whatever `$old` already holds is **never removed**. It prints `P1 held back: <files that differ> — merge their .new copies, then re-run install.sh`.
- **settings.json P1**: `permissions.defaultMode: "acceptEdits"`; allow += `Bash(git add *)`, `Bash(git commit -m *)`, `Bash(git switch -c *)`, `Bash(git branch --show-current)`, `Bash(git worktree list)`.
- **github.md P1**: commit exactly `git commit -m "<one line>"` (no heredoc, no `$(...)`, no `-a`); staging `git add <explicit paths>` (never `.`, `-A`, `--all`, `-u`, a directory or a glob).
- **Measure method** (`ADAPTATION.md`): before/after = permission-prompt dead time on a light pass, from the session transcript: the gaps between a `tool_use` and its `tool_result` on calls that prompted (`docs/measuring-the-loop.md:28-30`), summed per pass; "before" from an existing light pass transcript, "after" from the next one. Named, not automated.

## Test plan (gate — validated by the user before EXECUTE)

Fixtures in `.claude/hooks/fixtures/<hook>/`, run by `test-hooks.sh`. Ids are the spec's H1-H15 plus H5b, H8b, H16, T1, I-P1, K-P1. Every relative-path shell fixture carries `"cwd"`. Setup files named in `test-hooks.sh` per fixture name: git fixture tree `.feat/src/x.ts`, `.feat/.env.example` (tracked), `.feat/certs/a.pem`, `.feat/.env.local` (untracked, only for H6/H11 fixtures); worktree project dir `$tmp/.claude/worktrees/x` for the worktree cases.

### Test-first — hook fixtures

#### `hook-guarded.sh` (harness cases in `test-hooks.sh`)
- [ ] H8 `cwk_is_guarded .claude/scripts/a.sh` exits 0, `cwk_is_guarded src/x.ts` exits 1, `cwk_is_guard_denied .claude/.tdd-red/m` exits 0, all printing nothing, run from `.claude/hooks/` and from the root with the same result; `.claude/.hook-timings.log` byte-identical before/after sourcing; `cwk_guard_rel` of `$P/.claude/worktrees/x/.claude/hooks/a.sh` → `.claude/hooks/a.sh`, of `$P/src/../vite.config.ts` → `vite.config.ts`, of `$P/./package.json` → `package.json`, of `../package.json` with base `$P/src` → `package.json`, of `$P/../y` → nothing, exit 1.
- [ ] H8b `hook-guarded.sh` renamed in a scratch kit copy: `protect-files.sh` on any Write exits 2 with `BLOCKED: hook-guarded.sh missing`; `eslint-batch.sh` (Stop) in the same copy exits 0.

#### `protect-files.sh`
- [ ] H3 Write on each of `.claude/hooks/a.sh`, `.claude/hooks/fixtures/x.json`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.ts`, `eslint.config.js`, `vite.config.ts`, `package.json`, `tsconfig.json`, `tsconfig.app.json`, `.github/workflows/ci.yml` (absolute): ask; `.claude/hooks/a.sh` and `vite.config.ts` under `.claude/worktrees/x/`: ask; `src/../vite.config.ts`: ask; Edit on `.claude/settings.json`: ask.
- [ ] H3 Write on `.claude/.tdd-red/m` (absolute, and under `.claude/worktrees/x/`): deny.
- [ ] H4 Write on `src/x.ts`, `docs/x.md`: pass.
- [ ] H7 Write on `.claude/scripts/a.sh`: ask.
- [ ] Regression: existing `01-05` keep their verdicts; Read on `.claude/settings.json`: pass.

#### `prevent-destructive-commands.sh` (cwd `__PROJECT_ROOT__` unless named)
- [ ] H5 ask each: `mv .claude/hooks/tdd-freeze-tests.sh /tmp/`, `cp x .claude/.tdd-unfrozen`, `echo x >> .claude/.size-exempt`, `echo x > package.json`, `echo x >| package.json`, `tee .claude/settings.json`, `ln -sf x .claude/hooks/a.sh`, `install x .claude/hooks/a.sh`, `rsync x .claude/hooks/`, `truncate -s0 vite.config.ts`, `patch package.json p.diff`, `sed -n -i 's/a/b/' .claude/settings.json`, `sed --in-place 's/a/b/' tsconfig.json`, `perl -i -pe 's/a/b/' eslint.config.js`, `rm .claude/hooks/a.sh`, `rmdir .claude/scripts`, `chmod -x .claude/hooks/a.sh`, `git diff --output=.claude/.tdd-unfrozen`, `find .claude/hooks -name a -exec cp x {} \;`, `find .claude/hooks -name a -execdir rm {} \;`, `find .claude/hooks -delete`, `find . -fprintf .claude/.size-exempt x`, `cp -t .claude/hooks x`, `cp --target-directory=.claude/hooks x`, `node -e "1"`, `bash -c "true"`, `sh -c "true"`, `zsh -c "true"`, `perl -e "1"`, `ruby -e "1"`, `eval "x"`, `echo x &> package.json`, `echo x >&package.json`, `unlink .claude/hooks/a.sh`, `shred .claude/hooks/a.sh`, `chown u .claude/hooks/a.sh`, `find .claude/hooks -ok rm {} \;`, `find .claude/hooks -okdir rm {} \;`, `find . -fls .claude/.size-exempt`, `sed 'W .claude/.size-exempt' f`, `sed 'e cmd' f`, `git diff --output .claude/.tdd-unfrozen`, `env sed -i 's/a/b/' package.json`, `nice -n 5 sed -i 's/a/b/' package.json`, `timeout -k 1 5 sed -i 's/a/b/' package.json`, `cat > package.json <<'EOF'` / `it's` / `EOF` (heredoc). Deny each: `python3 -c "open('.claude/.tdd-red/m','w')"` (scanned inline program), `touch .claude/.tdd-red/m`, `cat > .claude/.tdd-red/m <<'EOF'` / `it's` / `EOF`. Pass each: `cat .claude/hooks/a.sh`, `grep x .claude/settings.json`, `git commit -m "note > package.json"`, `rm /tmp/x-*`, `sed -i 's/a/b/' src/*.ts`, `echo x 2>&1`.
- [ ] H5c compound forms, ask each: `(cd .claude/hooks && sed -i 's/a/b/' a.sh)`, `{ sed -i 's/a/b/' package.json; }`, `time sed -i 's/a/b/' vite.config.ts`, `echo "$(sed -i 's/a/b/' package.json)"`, `if true; then sed -i 's/a/b/' package.json; fi`, `sudo sed -i 's/a/b/' package.json`; and `(cd src); sed -i 's/a/b/' package.json` (the `cd` does not leak out of its subshell): ask.
- [ ] H5d failure modes, with `shell_targets.py` renamed in a scratch kit copy: `sed -i 's/a/b/' package.json` → ask; `touch .claude/.tdd-red/m` → deny; `ls src` → pass.
- [ ] H5b worktree: `sed -i 's/a/b/' .claude/worktrees/x/.claude/hooks/a.sh`, and `sed -i 's/a/b/' a.sh` with cwd `__PROJECT_ROOT__/.claude/worktrees/x/.claude/hooks`: ask each.
- [ ] H9 ask each: `cd .claude/hooks && sed -i 's/a/b/' a.sh`, `pushd .claude/hooks; popd; sed -i 's/a/b/' package.json`, `sed -i 's/a/b/' a.sh` with cwd `__PROJECT_ROOT__/.claude/hooks`, `sed -i 's/a/b/' ../package.json` with cwd `__PROJECT_ROOT__/src`, `echo x > $T`, `cp x .claude/hooks/*`, `rm "$f"`, `for f in package.json tsconfig.json; do sed -i 's/a/b/' "$f"; done`, `find .claude/hooks -name '*.sh' | xargs sed -i 's/x/y/'`, `pushd .claude/hooks && sed -i 's/a/b/' a.sh`, `cd "$D" && sed -i 's/a/b/' a.sh`.
- [ ] H10 pass each: `python3 .claude/hooks/kit-doctor.py`, `.claude/hooks/test-hooks.sh 2>&1 | tail -1`, `bash .claude/hooks/test-small-lane.sh`.
- [ ] H7 pass each: `python3 .claude/hooks/kit-attempts.py fail docs/work/x/plan.md test "expected > in vite.config.ts"`, `python3 .claude/hooks/kit-attempts.py pass docs/work/x/plan.md test`.
- [ ] H12 ask each: `rm -rf src/features/x`, `rm src/features/x -rf`, `rm --rec src/features/x`, `rm -Rf src/features/x`, `mv src/features/x /tmp/`.
- [ ] H13 ask each: `sed 'w .claude/.size-exempt' f`, `sed -n 's/x/y/w .claude/.size-exempt' f`, `rg --pre ./x pat`, `rg --pre=./x pat`, `find . -fprint .claude/.size-exempt`.
- [ ] H16 deny each (deny pass before ask pass): `rm -rf src/features/x; mkfs.ext4 /dev/sdb`, `cp x .claude/hooks/a.sh; touch .claude/.tdd-red/m`.
- [ ] Regression: existing `01-19` keep their verdicts.

#### `enforce-git-workflow.sh` (cwd `__FEAT_TREE__` unless named)
- [ ] H1 ask each: `git commit -m x --amend`, `git commit --am -m x`, `git commit -am x`, `git commit -m x --no-verify`, `git commit -m x -n`; pass: `git commit -m "x"`.
- [ ] H2 ask each: `git switch -c x --discard-changes`, `git checkout -f main`, `git switch -C x`; pass: `git switch -c y`.
- [ ] H13 ask each: `git switch --force-create x`, `git switch --force-c x`.
- [ ] H6 deny each: `git add -f x`, `git add --forc x`, `git add -Af`, `git add .env.local`, `git add certs/a.pem`, `git add .` (untracked `certs/a.pem`); pass each: `git add src/x.ts`, `git add .env.example`, `git add -- src/x.ts`, and on a fixture tree **without** the untracked secrets `git add -A`, `git add -u`.
- [ ] H11 deny each: `git add $(cat list)`, ``git add `x` ``, `git add $F`, `git add --pathspec-from-file=l`, `git add missing.ts` (dry-run fails), `git add src/x.ts` with a `git` shim first on PATH that sleeps 3 s (timeout), the heredoc `git add -f .env.local <<'EOF'` / `it's` / `EOF` (unparsable).
- [ ] H16 deny: `git push origin feat/x && git add -f .env.local`.
- [ ] H11b pass: the unparsable commit `git commit -F - <<'EOF'` / `add the user's flag` / `EOF` (the word `add` outside subcommand position).
- [ ] Regression: existing 85 keep their verdicts.

#### `install.sh` (`test-install.sh`)
- [ ] H14 a fresh install and an upgraded install (existing block) both ignore `*.pem`, `*.key`, `credentials.*`.
- [ ] I-P1 (a) an upgrade over a target whose old `enforce-git-workflow.sh` differs and whose settings have no `defaultMode`: the merged settings hold no `defaultMode` and no `Bash(git add *)`, and the output prints `P1 held back: .claude/hooks/enforce-git-workflow.sh`; (b) the same target after its `.new` hooks are moved into place, install re-run: both present, nothing held back; (c) a fresh install, then install re-run: both still present (identical files landing as `.new` do not hold P1 back, and nothing is removed).

### Test-after — contracts (`test-workflow-contracts.sh`)
- [ ] K-P1 `settings.json`: `permissions.defaultMode == "acceptEdits"`, the 5 allows verbatim, and no `Bash(git commit *)`, `Bash(git switch *)`, `Bash(git branch *)`, `Bash(git push *)`, `Bash(git *)`.
- [ ] H15 `docs/ADAPTATION.md` names the kit-development prompts, the install merge of `defaultMode`, the P1 hold-back and the measure method; `docs/Claude_Workflows.md` has the section on the prompts left on a light pass (`git push`, `gh pr`, `--amend`, guarded paths); `.claude/agents/github.md` holds `git commit -m "<one line>"` and forbids `git add .`.
- [ ] T1 `tdd-require-red.sh` and `tdd-freeze-tests.sh` deny texts hold "this write will ask the user" (plus `_expect_reason` on one deny fixture each).
- [ ] S1 (step 10) recorded in `## Gate`: the four allowed calls absent from `permission_denials`, the four guarded ones present.

## Vigilance (carried from research)
- Every dangerous flag is tested last, bundled and abbreviated (git **and** `rm`).
- `hook-guarded.sh` has no side effect (H8); hook-lib sources it fail-closed (H8b).
- Paths resolved on both branches, against `.cwd`/`$CLAUDE_PROJECT_DIR`, never `$PWD`; `.claude/worktrees/<x>/` stripped — there `acceptEdits` does not prompt, P2 is the only guard (H5b).
- Writer verbs with unknown operands ask; `cd`/`pushd` tracked; `xargs`/`do`/wrappers stripped; quoted text is data.
- Marker in target position only, so running kit scripts never asks (H7, H10).
- Every new deny precedes every new ask, in both shell hooks (H16).
- `git add` dry-run in python with `timeout=2`, fail closed; PARSE_FAILED `add` denies.
- A removed or chmod'd hook fails open: the `mv`/`rm`/`chmod` asks on `.claude/hooks/**` are the guard.
- Reinstall never ships P1 without P2 (I-P1); this plan ships no kit `permissions.deny`/`ask` (install would replace a target's array).
- protect-files' ask is Write/Edit only.
- `.gitignore` patterns in three places and `test-install.sh`.
- P1 lands last in this repo; kit-development prompts from step 2 on.

## Acceptance criteria (carried from the entry artifact)
- [ ] On a real light pass: no prompt for edits, `git add <paths>`, `git commit -m "<one line>"`, gates; `git push`, `gh pr *`, `git commit -m x --amend`, `git switch -c x --discard-changes` still prompt.
- [ ] Writing any guarded path prompts, by Write/Edit and by every shell write marker of P2, from the main tree and from a worktree; writing `.claude/.tdd-red/**` is denied.
- [ ] `git add -f .env`, `git add --forc .env.local`, and `git add .` with an untracked `certs/a.pem` are denied; `git add .env.example` and `git add src/x.ts` pass.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-install.sh` pass.

### Proof map
| AC | Proof |
| --- | --- |
| 1 | S0 (hook ask beats acceptEdits and allow rules) + S1 headless smoke on a scratch install, before merge; hook side H1, H2, H6, H7, H10 |
| 2 | Write/Edit: H3, H7 (main tree + worktree); shell: H5 (one fixture per marker and wrapper of the contract), H5b (worktree), H5c (compound forms), H5d (failure modes), H9, H12, H13, H16; `.tdd-red` deny: H3, H5, H5d |
| 3 | H6, H11 |
| 4 | the three suites + doctor (+ every `kit-ci.yml` suite) |

## Open questions for the gate (from research, with proposed answers)
5. Does a hook `ask` override `acceptEdits` / an allow rule? → S0 settles it per case before step 1; any case not overriding stops EXECUTE for your decision.
6. Measure → settled IN by the spec: the method is named in `ADAPTATION.md` (Contracts, "Measure method"); the before/after numbers come from the next light pass, not automated here.
7. Routing sends `execute-green` to Codex → EXECUTE inline on Claude (`--inline-execute`), fix batches by `implementer`, as on small-lane.

## Plan critic
<pending>
