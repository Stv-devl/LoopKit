# Spec: Guarded set, shell side
Token profile: critical (a shell parser is where the guard is bypassed; maximum independent challenge)
Split from: `docs/specs/light-permissions.md` (2026-10-28, pass 2 of 3). Needs `docs/specs/guard-writes.md` shipped (`hook-guarded.sh`, the spike verdict). Research reused: `docs/work/light-permissions/research.md`; plan-critic findings: `docs/work/light-permissions/plan.md`.

## Objective
A shell command that writes a guarded path asks the user, and one that writes `.claude/.tdd-red/**` is denied, whatever verb, wrapper, `cd` or quoting carries the write. Running a kit script never asks. A recursive `rm`/`mv` under a protected dir asks.

## Scope
- IN :
  - **`.claude/hooks/shell_targets.py`** (new, `python3 -B`). It **resolves, never classifies**: input the command and the base dir (`.cwd`, else `$CLAUDE_PROJECT_DIR`); output one row per write: `<verb>\t<target>`, where `<target>` is a repo-relative path, `?unknown`, `?glob:<literal prefix>`, `?inline:<program text>` or `?outside`. `prevent-destructive-commands.sh` classifies each row with `cwk_is_guarded` / `cwk_is_guard_denied` (`guard-writes.md`): one list, no copy in python.
    - Heredoc bodies are cut before tokenising, except a heredoc feeding `python*`/`node`/`ruby`/`perl`/`bash|sh|zsh` (stdin program) → `?inline:<body>`; inside an **unquoted** heredoc body, `$(…)`/backticks are recursed into.
    - shlex per segment; segments split on `;`, `&&`, `||`, `|`, `&`, newline, `(`, `)`, `{`, `}`; `$(…)` and backticks, also inside double quotes, are recursed into as commands.
    - Stripped before the verb: the git parser's wrapper set (`enforce-git-workflow.sh:108-109,243-245`) plus `do`, `then`, `else`, `elif`, `if`, `while`, `until`, `!`, `time`, `sudo`, `exec`, `stdbuf [opts]`, `setsid`, `xargs [opts]`, `env [-i] [VAR=x…]`, `nice [-n N]`, `nohup`, `timeout [-k N] [-s SIG] N`, `command`, `builtin`.
    - `cd`/`pushd`/`popd` tracked, scoped to the enclosing `( … )`; to an unknown dir or `-` → later relative targets `?unknown`.
    - Writers and their target position: redirect `>`, `>>`, `>|`, `&>`, `>&file` (not `>&N`, not `2>&1`); `tee` operands; `cp`/`install`/`ln`/`rsync` last operand or `-t`/`--target-directory[=]`; every operand of `mv`, `rm`, `rmdir`, `unlink`, `shred`, `truncate`, `touch`, `chmod`, `chown`; `patch` target; `sed`/`perl` with `-i`/`--in-place*` (bundled or separate) → their file operands; sed script `w`/`W` file, `s///w file`; sed `e` → `?unknown`; `--output[=]` / `--output <f>`; `find … -exec|-execdir|-ok|-okdir|-delete|-fprint*|-fls` → the find roots and the named file; `python*`, `node`, `perl`, `ruby`, `bash|sh|zsh -c`, `-e`/`--eval`, `eval` → `?inline:<program>`; `rg --pre`/`--pre=` → `?unknown`.
    - Quoted text with no `$(`/backtick is data (`git commit -m "note > package.json"` writes nothing). Running a script with arguments is not a writer.
  - **Classification in `prevent-destructive-commands.sh`**, per row: a denied target (or an `?inline` program text naming `.claude/.tdd-red`) → deny; a guarded target → ask; `?unknown`, `?inline` → ask; `?glob:<prefix>` → ask when the prefix resolves inside the project and is guarded or a folder above a guarded pattern; `?outside` → nothing.
  - **Failure is not a pass**: python3 missing, `shell_targets.py` missing, nonzero exit, empty or malformed output, a shlex `ValueError` → deny when the raw text names `.claude/.tdd-red`; else ask when it names `.claude/`, a guarded root file, or holds a heredoc or a writer verb; else pass.
  - **Recursive `rm`/`mv` under a protected dir asks** (`PROTECTED_DIRS`, `prevent-destructive-commands.sh:75`): recursive = a token matching `-[a-zA-Z]*[rR][a-zA-Z]*` or a prefix of `--recursive`, anywhere among the `rm` arguments; `mv` of a path under a protected dir always counts. The "protected dir" test applies to these two verbs only, never to the glob rule. Existing denies on the dir itself unchanged.
  - **Order**: one deny pass over all segments (existing denies, deny rows), then one ask pass (existing asks, ask rows, recursive rm/mv). No ask is emitted before every deny was checked.
  - The text at `prevent-destructive-commands.sh:101` ("Specify a subdirectory") is updated: that form now asks.
  - `kit-doctor.py` `NON_HOOKS` gains `shell_targets.py`.
- OUT :
  - Write/Edit (`guard-writes.md`). Git rules, `settings.json`, `install.sh` (`light-permissions-git.md`).

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/hooks/{shell_targets.py (new),prevent-destructive-commands.sh,test-hooks.sh,kit-doctor.py}` and `prevent-destructive-commands.sh` fixtures.

## Acceptance criteria
- [ ] Every shell write marker listed in Scope, on a guarded path, asks — from the main tree, from a worktree path, and with a worktree `cwd`; on `.claude/.tdd-red/**` it is denied.
- [ ] Kit scripts run with arguments (`kit-doctor.py`, `kit-attempts.py`, `test-hooks.sh 2>&1 | tail`) and reads of guarded paths pass.
- [ ] A recursive `rm`/`mv` under a protected dir asks, flag first, last or abbreviated.
- [ ] With `shell_targets.py` missing, a guarded write asks and a `.tdd-red` write is denied.
- [ ] `test-hooks.sh`, `kit-doctor` pass.

## Business logic to cover
No TypeScript. `prevent-destructive-commands.sh` fixtures, `cwd` `__PROJECT_ROOT__` unless named:
- X1 ask each: `mv .claude/hooks/tdd-freeze-tests.sh /tmp/`, `cp x .claude/.tdd-unfrozen`, `echo x >> .claude/.size-exempt`, `echo x > package.json`, `echo x >| package.json`, `echo x &> package.json`, `echo x >&package.json`, `tee .claude/settings.json`, `ln -sf x .claude/hooks/a.sh`, `install x .claude/hooks/a.sh`, `rsync x .claude/hooks/`, `truncate -s0 vite.config.ts`, `patch package.json p.diff`, `sed -n -i 's/a/b/' .claude/settings.json`, `sed --in-place 's/a/b/' tsconfig.json`, `perl -i -pe 's/a/b/' eslint.config.js`, `rm .claude/hooks/a.sh`, `rmdir .claude/scripts`, `unlink .claude/hooks/a.sh`, `shred .claude/hooks/a.sh`, `chmod -x .claude/hooks/a.sh`, `chown u .claude/hooks/a.sh`, `cp -t .claude/hooks x`, `cp --target-directory=.claude/hooks x`, `git diff --output=.claude/.tdd-unfrozen`, `git diff --output .claude/.tdd-unfrozen`.
- X2 ask each (find, sed, rg): `find .claude/hooks -name a -exec cp x {} \;`, `find .claude/hooks -name a -execdir rm {} \;`, `find .claude/hooks -ok rm {} \;`, `find .claude/hooks -okdir rm {} \;`, `find .claude/hooks -delete`, `find . -fprint .claude/.size-exempt`, `find . -fprintf .claude/.size-exempt x`, `find . -fls .claude/.size-exempt`, `sed 'w .claude/.size-exempt' f`, `sed 'W .claude/.size-exempt' f`, `sed -n 's/x/y/w .claude/.size-exempt' f`, `sed 'e cmd' f`, `rg --pre ./x pat`, `rg --pre=./x pat`.
- X3 ask each (interpreters): `node -e "1"`, `bash -c "true"`, `sh -c "true"`, `zsh -c "true"`, `perl -e "1"`, `ruby -e "1"`, `eval "x"`. Deny each: `python3 -c "open('.claude/.tdd-red/m','w')"`, `python3 - <<'EOF'` / `open('.claude/.tdd-red/m','w')` / `EOF`.
- X4 folders: `rm -rf .github/workflows`, `mv .github /tmp/`, `cp -r /tmp/h/. .claude/worktrees/x/.claude/`: ask each; `rm -r .claude/.tdd-red`: deny.
- X5 worktree: `sed -i 's/a/b/' .claude/worktrees/x/.claude/hooks/a.sh`; `sed -i 's/a/b/' a.sh` with `cwd` `__PROJECT_ROOT__/.claude/worktrees/x/.claude/hooks`: ask each.
- X6 resolution, ask each: `cd .claude/hooks && sed -i 's/a/b/' a.sh`; `sed -i 's/a/b/' a.sh` with `cwd` `__PROJECT_ROOT__/.claude/hooks`; `sed -i 's/a/b/' ../package.json` with `cwd` `__PROJECT_ROOT__/src`; `pushd .claude/hooks; popd; sed -i 's/a/b/' package.json`; `pushd .claude/hooks && sed -i 's/a/b/' a.sh`; `cd "$D" && sed -i 's/a/b/' a.sh`; `echo x > $T`; `cp x .claude/hooks/*`; `rm "$f"`; `for f in package.json tsconfig.json; do sed -i 's/a/b/' "$f"; done`; `find .claude/hooks -name '*.sh' | xargs sed -i 's/x/y/'`.
- X7 wrappers and compounds, ask each: `env sed -i 's/a/b/' package.json`, `nice -n 5 sed -i 's/a/b/' package.json`, `timeout -k 1 5 sed -i 's/a/b/' package.json`, `sudo sed -i 's/a/b/' package.json`, `time sed -i 's/a/b/' vite.config.ts`, `(cd .claude/hooks && sed -i 's/a/b/' a.sh)`, `(cd src); sed -i 's/a/b/' package.json`, `{ sed -i 's/a/b/' package.json; }`, `if true; then sed -i 's/a/b/' package.json; fi`, `echo "$(sed -i 's/a/b/' package.json)"`, `cat <<EOF` / `$(sed -i 's/a/b/' package.json)` / `EOF`.
- X8 heredocs: `cat > package.json <<'EOF'` / `it's` / `EOF`: ask; `cat > .claude/.tdd-red/m <<'EOF'` / `it's` / `EOF`: deny; `touch .claude/.tdd-red/m`: deny.
- X9 pass each: `cat .claude/hooks/a.sh`, `grep x .claude/settings.json`, `git commit -m "note > package.json"`, `rm /tmp/x-*`, `sed -i 's/a/b/' src/*.ts`, `echo x 2>&1`, `python3 .claude/hooks/kit-doctor.py`, `.claude/hooks/test-hooks.sh 2>&1 | tail -1`, `bash .claude/hooks/test-small-lane.sh`, `python3 .claude/hooks/kit-attempts.py fail docs/work/x/plan.md test "expected > in vite.config.ts"`, `python3 .claude/hooks/kit-attempts.py pass docs/work/x/plan.md test`.
- X10 recursive, ask each: `rm -rf src/features/x`, `rm src/features/x -rf`, `rm --rec src/features/x`, `rm -Rf src/features/x`, `mv src/features/x /tmp/`.
- X11 order, deny each: `rm -rf src/features/x; mkfs.ext4 /dev/sdb`, `cp x .claude/hooks/a.sh; touch .claude/.tdd-red/m`.
- X12 failure, with `shell_targets.py` renamed in a scratch kit copy: `sed -i 's/a/b/' package.json` ask; `touch .claude/.tdd-red/m` deny; `ls src` pass.
- X13 existing `prevent-destructive-commands.sh` fixtures keep their verdicts.
