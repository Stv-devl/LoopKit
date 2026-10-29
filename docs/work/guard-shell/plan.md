# Plan: Guarded set, shell side   (entry: docs/specs/guard-shell.md · research: docs/work/guard-shell/research.md · design: n/a)
Token profile: critical

## Skips
- Interface : SKIP — kit hook, no user surface.
- DB, Backend, Front app layers : SKIP — `Data model: none`, `Custom backend: NONE`, no `src/`. The TDD hooks do not key on `.claude/`: test-first is by hand — every case of a step is written first and **observed failing on its own verdict or reason** (`FAIL prevent-destructive-commands.sh / <id>: …`) before the code it covers changes. The run output is pasted into the handoff.

## Write chain (sequential)
1. **Cases first** — `fixtures/_harness/shell-guard.jsonl` (ids X1-X11) and its runner `run_shell_guard_cases`; harness functions `run_shell_guard_failure_cases` (X12) and `run_shell_guard_budget_case` (X14), all in `test-hooks.sh`. Run `test-hooks.sh`: every ask/deny case is observed failing **except the regression pins** marked *(pin)* below, which are green today and must stay green; X9 and X13 must be green today. Record the failure count.
2. **`shell_targets.py`** (new) — resolver only, contract below.
3. **`prevent-destructive-commands.sh`** — `.cwd`; one resolver call; one classification of the rows; deny verdicts placed after every existing deny (after `:372`); new asks placed **first in the ask pass**, before the formatter ask and the TS ask; text fallback; `:98-102` comment and text updated. Run → X1-X14 green, X13 unchanged.
4. **`kit-doctor.py`** — `NON_HOOKS` += `shell_targets.py`. **`docs/ADAPTATION.md` §14** — one line: shell writes on guarded paths ask too, and any `rm -r`/`mv` under a protected dir asks (open question 7).
5. **Tests** — every `kit-ci.yml` suite (`test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-small-lane.sh`, `test-attempts.sh`, `test-workflow-contracts.sh`, `test-rules-floor.sh`) + `python3 .claude/hooks/kit-doctor.py`; `bash -n` and `python3 -B -m py_compile` on the two sources.
6. **Refactor** — under a green suite, no case edited. The TS/PY source-write regexes stay (they own the TDD deny and the TS ask).

## Parallel lots (inside this track, same tree)
none — fully sequential (one hook, its resolver, its test runner).

## Track isolation
- Worktree: none, single track (main tree, branch `audit/slim`).
- Shared foundations touched: `prevent-destructive-commands.sh` (every Bash call), `test-hooks.sh`. No other pass in flight.
- Kit-development cost: from step 3 on, shell writes on `.claude/hooks/**` in this repo ask; edits go through Write/Edit (which already ask since guard-writes).

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/shell_targets.py` | Create | tokenise a Bash command, print one row per write target, then the sentinel; resolves, never classifies |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | `.cwd`; classification; deny verdicts in the deny pass; text fallback; new asks first in the ask pass; recursive rm/mv; `:98-102` |
| `.claude/hooks/test-hooks.sh` | Edit | `run_shell_guard_cases` (jsonl → `run_case`), `run_shell_guard_failure_cases` (X12), `run_shell_guard_budget_case` (X14) |
| `.claude/hooks/fixtures/_harness/shell-guard.jsonl` | Create | the X1-X11 cases |
| `.claude/hooks/kit-doctor.py` | Edit | `NON_HOOKS` |
| `docs/ADAPTATION.md` | Edit | §14, one line (open question 7) |

## Contracts

### Case file and runner
`fixtures/_harness/shell-guard.jsonl`: one object per line, `{"id":"X1.04","verdict":"ask|deny|pass","command":"…","cwd":"__PROJECT_ROOT__…","reason":"…"}` (`cwd` defaults to `__PROJECT_ROOT__`; `reason` required on every ask/deny case). `run_shell_guard_cases` writes each line as `{"tool_name":"Bash","tool_input":{"command":…},"cwd":…,"_expect_reason":…}` into a temp fixture `<id>-<verdict>.json` and calls the existing `run_case prevent-destructive-commands.sh <file> <verdict>` (same placeholder substitution, verdict, JSON and reason checks; failures named by id). The runner **fails** on a missing file, zero parsed lines, an unparsable line, or a duplicate id.

Reason substrings (the `reason` of each case, by block below): **G** = `guarded path:`, **U** = `unresolved write target`, **D** = `is written only by tdd-prove-red.sh`, **P** = `under a protected dir`, **F** = `shell guard unavailable`.

### `shell_targets.py`
`python3 -B shell_targets.py <command> <base>` (`base` = input `.cwd`, else `$CLAUDE_PROJECT_DIR`; absolute). Prints rows `<verb>\t<target>`, then **always** a last line `#end\t<row count>`; exit 0. Any internal failure (including `ValueError`) exits nonzero. Bash treats a missing or wrong sentinel as failure.

**Pre-scan** (one quote-aware pass over the raw text before any shlex, tracking `'…'`, `"…"` and `$(…)` nesting — the shape of `strip_comments` in `enforce-git-workflow.sh`):
- `#` at a word start outside quotes → comment to end of line, dropped.
- `<<[-]WORD`, `<<'WORD'`, `<<"WORD"` outside quotes, or inside a `$(…)` (also within double quotes) → heredoc opener: the body lines up to the terminator line are cut; the opener line keeps its redirects. `<<<` is a here-string, never an opener. Body fed to an interpreter (below) → that segment gets `?inline:<body>`; an unquoted-delimiter body is scanned for `$(…)`/backticks, recursed into.
- Each `$(…)`/backtick region is recorded with its quoting context, so "quoted data" is decided here, not after shlex: single-quoted text is data; double-quoted text is data except its `$(…)`/backticks, which are recursed into as commands (depth ≤ 3; deeper → one `?unknown:<text>` row). Arithmetic `$((…))` is neither a command region nor a heredoc context (`$((1<<2))` opens nothing).
- Glob marks reach the tokens through placeholders: before shlex, every `*`, `?`, `[`, `{` **inside quotes in the current command region** (quoting restarts inside each `$(…)`/backtick region) is replaced by a private-use character, restored in the operand after tokenising; an operand still holding a raw `*`, `?`, `[` or a `{` followed later by `,` or `..` and `}` is a glob (`'a[1].txt'` is a literal name, `{a,b}.sh` a glob).

**Segments**: `shlex.shlex(posix=True, whitespace_split=True, punctuation_chars=";&|()<>\n")` — braces are **not** punctuation, so `{}` and `x{a,b}y` stay words; `<>` are, so a redirect glued to a word (`echo x>package.json`) is cut out of it. Each punctuation token is split by **longest match** against the operator table `&&` `||` `;;` `|&` `&>>` `&>` `>>` `>|` `>&` `<<<` `<<` `<&` `<>` `<` `>` `;` `&` `|` `(` `)` newline, so a merged `);` closes the scope and ends the segment and `>|` stays one redirect. Only the control operators (`&&` `||` `;;` `|&` `;` `&` `|` `(` `)` newline) end a segment; redirect operators take the next word as their target; `>&`/`<&` followed by a digits-only word is an fd dup (no target); a digits-only word right before a redirect operator is its fd number, not an operand (shlex loses adjacency; no guarded name is all digits). A word that is exactly `{` at command position is stripped as a prefix; a word that is exactly `}` ends the segment. A segment after `|` is marked **piped**. shlex lexes `\;` as `;`: an `-exec` command therefore ends at its segment's end.

**Before the verb, stripped**: `VAR=x` assignments; the git parser's set `env`, `command`, `exec`, `time`, `nice`, `nohup`, `setsid`, `{`, `!`, `if`, `then`, `else`, `elif`, `while`, `until`, `do`; plus `sudo`, `builtin`, `stdbuf [opts]`, `xargs [opts]` (marks **implicit operands**), `env [-i] [VAR=x…]`, `nice [-n N]`, `timeout [-k N] [-s SIG] N`. A `for x in …` segment writes nothing.

**Directory tracking**: `cd`/`pushd`/`popd` per scope, `pushd`/`popd` a stack; `( … )` opens a scope restored at `)`; `cd`/`pushd` to an operand with `$`, a backtick, `-`, `~`, or no operand → unknown dir; a relative target under an unknown dir → `?unknown:<operand>`.

**Target** forms:
- an **absolute, lexically normalised** path: the operand joined to the tracked dir (`os.path.normpath`; no filesystem access, no symlink resolution, no project stripping — that is `cwk_guard_rel`'s);
- `?glob:<abs folder>` — a glob operand: folder = `normpath(join(dir, dirname(<literal prefix>)))`, the literal prefix being the text before the first glob char (`docs/*.md` → `<dir>/docs`; `*.json` → `<dir>`; `.claude/.tdd-red/*` → `<dir>/.claude/.tdd-red`; `/tmp/x-*` → `/tmp`);
- `?unknown:<raw operand>` — an operand holding `$`, a backtick or `$(`, or starting with `~`; a writer with implicit operands (`xargs`, or `sed -i`/`perl -i` with no file operand) → `?unknown:<segment text>`; sed `e`; `rg --pre`;
- `?inline:<program text>`.
- In every target (path or `?…:<text>` marker) tabs and newlines are replaced by spaces, so one row is one line.
- **Row order within a segment**: path and glob rows first, in operand order, then `?unknown` rows, then `?inline` rows.

**Writers** (verb `\t` target):
- redirects `>`, `>>`, `>|`, `&>`, `>&file` (not `>&N`, not `N>&M`) on any segment, verb `>`;
- `tee` operands; `cp`/`install`/`ln`/`rsync` last operand, or `-t X` / `--target-directory[=]X`;
- every operand of `mv`, `rm`, `rmdir`, `unlink`, `shred`, `truncate`, `touch`, `chmod`, `chown` (`chmod`/`chown` first operand is mode/owner, skipped; `truncate -s N` / `-sN` value skipped); **`rm` with a recursive flag — a token `-[a-zA-Z]*[rR][a-zA-Z]*` or a prefix of `--recursive` of 3+ chars, anywhere among its args — prints verb `rm-r`**;
- `patch` first operand;
- `sed`/`perl` with `-i*`/`--in-place*` (bundled `-ni` or separate) → file operands (sed script = first non-option unless `-e`/`-f`);
- sed script grammar, with or without `-i`: commands separated by `;`/newline, each `[address[,address]][!]` then a command letter; addresses are a line number, `$`, `/re/`, `\cREc` (any delimiter), `first~step`, and as second address `+N` or `~N`; `s` and `y` take their own delimiter (`s|a|b|w f`), `s` flags follow the third delimiter; `a`, `i`, `c` take text to end of line (never a command); `:label`, `b`/`t`/`T label`, `{`, `}` are structure; `r`/`R <file>` read. `w`/`W <file>` at command position and the `w <file>` flag of `s` → that file; `e` at command position or as an `s` flag → `?unknown`. A script the grammar cannot read → `?unknown:<script>`;
- `--output=<f>` / `--output <f>` on any verb;
- `find`: `-delete` → each root (operands before the first `-`, `(`, `!`); `-exec|-execdir|-ok|-okdir <cmd> … ;|+` → `<cmd>` resolved as its own segment with `{}` standing for each root, so a writer verb there yields the roots and a reader (`grep`, `bash -n`) yields nothing; under `-execdir`/`-okdir` any other relative operand of a writer resolves in each matched file's folder, unknown here → `?unknown:<operand>`; `-fprint|-fprint0|-fprintf|-fls <f>` → that file (open question 5);
- `rg --pre[=]` → `?unknown`;
- **interpreters** → `?inline:<program>`: `bash|sh|zsh|dash` and `python*` with a short-flag bundle containing `c` (`-c`, `-lc`, `-Bc`); `perl`/`ruby` with a bundle containing `e`/`E` (`-e`, `-ne`, `-pe`); `node` with `-e`, `-p`, `--eval`, `--print`; `eval` → its args; a heredoc or `<<<` here-string feeding an interpreter → body; an interpreter with `-` or with no program operand in a **piped** segment → `?inline:<whole command text>` (open question 4).
- **Running is not writing**: `python* <file|-m mod> args`, `bash|sh|zsh <file> args`, `node <file>`, `python3 < file`, a bare path to a script → no row. An interpreter with no program, not piped and no heredoc → no row.

**Row cap**: past 64 rows the resolver prints a single `?unknown:<whole command text>` row (plus the sentinel) instead; bash's `.tdd-red` substring test on it stays linear.

### `prevent-destructive-commands.sh`
- `HOOK_DIR="$(dirname "${BASH_SOURCE[0]}")"` (not defined today). `BASE="$(jq -r '.cwd // empty' <<<"$INPUT")"`, empty → `$CLAUDE_PROJECT_DIR`. `ROWS="$(python3 -B "$HOOK_DIR/shell_targets.py" "$COMMAND" "$BASE" 2>/dev/null)" || RESOLVER_FAILED=1`; also failed when the last line is not `#end\t<n>` with `n` equal to the row count, or a row does not match `^[^\t]+\t.+$`.
- **Classification, once** (results kept in two arrays reused by both passes; every `cwk_guard_rel` call written `rel=$(…) || continue` so `set -e` never aborts):
  - path → `cwk_guard_rel`; outside → nothing; `cwk_is_guard_denied` → deny **D**; `cwk_is_guarded` → ask **G**;
  - `?glob:<folder>` → `cwk_guard_rel <folder>`; outside → nothing; denied → deny **D**; guarded → ask **G**; no further cut in bash;
  - `?inline:<text>` / `?unknown:<text>` → deny **D** when the text contains `.claude/.tdd-red`, else ask **U**;
  - verb `rm-r` or `mv`, target a path or a glob folder whose repo-relative first segment matches `^($PROTECTED_DIRS)$` → ask **P** (spec:19's "never to the glob rule" read as: the protected-dir test feeds no other verb's glob row).
  - **One verdict per row**, in this precedence: **D** > **G** > **P** > **U** (a row both guarded and under a protected dir is **G**). **Reason chosen over all rows by the same precedence**, row order breaking ties: any D → deny D; else any G → ask G (first G row); else any P; else any U.
- **Deny pass**: after every existing deny (after `:372`): the first deny verdict → `BLOCKED: .claude/.tdd-red/ is written only by tdd-prove-red.sh (<verb> <target>)`. Resolver failed and the raw text names `.claude/.tdd-red` → `BLOCKED: shell guard unavailable and the command names .claude/.tdd-red/ …` (**F**).
- **Ask pass**, first in the pass (before the formatter ask `:424` and the TS ask `:428`): resolver failed and the raw text names `.claude/` or a literal prefix of `CWK_GUARDED` (each pattern cut at its first glob char — no second list), holds `<<`, a redirect `>`/`>>`/`>|`/`&>` (not an fd dup), or a writer verb word from the list above → ask `shell guard unavailable: …` (**F**); else the ask reason chosen by the precedence above: **G** `guarded path: <rel> written by <verb> (kit guardrail; approve only if you meant to change it)`, **U** `unresolved write target (<verb> <text>)`, **P** `recursive delete/move under a protected dir: <rel>`.
- `:98-102`: the comment drops "documented escape"; the deny text ends `A subdirectory is asked, not blocked: name it and let the user approve.`

## Test plan (gate — validated by the user before EXECUTE)

Test-first by hand: every case below is written and observed failing on its verdict or reason before step 2, except *(pin)* cases, green today and kept green. Ids are the spec's X1-X13 plus X14; the case file numbers each command `X<n>.<k>` in the order listed. `cwd` is `__PROJECT_ROOT__` unless named. Bold letter = expected reason substring.

### `fixtures/_harness/shell-guard.jsonl` via `run_shell_guard_cases`
**Core behaviour — a guarded write asks, `.tdd-red` is denied**
- [ ] X1 ask **G** each: `mv .claude/hooks/tdd-freeze-tests.sh /tmp/`, `cp x .claude/.tdd-unfrozen`, `echo x >> .claude/.size-exempt`, `echo x > package.json`, `echo x>package.json`, `echo x >| package.json`, `echo x &> package.json`, `echo x >&package.json`, `tee .claude/settings.json`, `ln -sf x .claude/hooks/a.sh`, `install x .claude/hooks/a.sh`, `rsync x .claude/hooks/`, `truncate -s0 vite.config.ts`, `patch package.json p.diff`, `sed -n -i 's/a/b/' .claude/settings.json`, `sed --in-place 's/a/b/' tsconfig.json`, `perl -i -pe 's/a/b/' eslint.config.js`, `rm .claude/hooks/a.sh`, `rmdir .claude/scripts`, `unlink .claude/hooks/a.sh`, `shred .claude/hooks/a.sh`, `chmod -x .claude/hooks/a.sh`, `chown u .claude/hooks/a.sh`, `cp -t .claude/hooks x`, `cp --target-directory=.claude/hooks x`, `git diff --output=.claude/.tdd-unfrozen`, `git diff --output .claude/.tdd-unfrozen`.
- [ ] X8 heredocs: `cat > package.json <<'EOF'` / `it's` / `EOF` → ask **G**; `echo "<<EOF"` / `sed -i 's/a/b/' package.json` → ask **G** (a quoted `<<` opens nothing); `cat > .claude/.tdd-red/m <<'EOF'` / `it's` / `EOF` → deny **D**; `touch .claude/.tdd-red/m` → deny **D**.
- [ ] X4 folders: `rm -rf .github/workflows`, `mv .github /tmp/`, `cp -r /tmp/h/. .claude/worktrees/x/.claude/`, `rm -rf .claude/hooks` (guarded and protected: **G** wins) → ask **G** each; `rm -r .claude/.tdd-red`, `rm .claude/.tdd-red/*` → deny **D** each.

**Business rules — every carrier of the write**
- [ ] X2 ask each: **G** `find .claude/hooks -name a -exec cp x {} \;`, `find .claude/hooks -name a -execdir rm {} \;`, `find .claude/hooks -ok rm {} \;`, `find .claude/hooks -okdir rm {} \;`, `find .claude/hooks -delete`, `find . -fprint .claude/.size-exempt`, `find . -fprintf .claude/.size-exempt x`, `find . -fls .claude/.size-exempt`, `sed 'w .claude/.size-exempt' f`, `sed 'W .claude/.size-exempt' f`, `sed -n 's/x/y/w .claude/.size-exempt' f`, `sed 's|x|y|w .claude/.size-exempt' f`; **U** `sed 'e cmd' f`, `rg --pre ./x pat`, `rg --pre=./x pat`, `find .claude/hooks -name a.sh -execdir sed -i 's/a/b/' a.sh \;`.
- [ ] X3 ask **U** each: `node -e "1"`, `node -p "1"`, `bash -c "true"`, `bash -lc "true"`, `sh -c "true"`, `zsh -c "true"`, `python3 -Bc "1"`, `perl -e "1"`, `perl -ne 'print'`, `ruby -e "1"`, `eval "x"`, `echo x | bash`; deny **D** each: `python3 -c "open('.claude/.tdd-red/m','w')"`, `python3 - <<'EOF'` / `open('.claude/.tdd-red/m','w')` / `EOF`, `printf "open('.claude/.tdd-red/m','w')" | python3`, `touch "$CLAUDE_PROJECT_DIR/.claude/.tdd-red/m"`.
- [ ] X5 worktree, ask **G** each: `sed -i 's/a/b/' .claude/worktrees/x/.claude/hooks/a.sh`; `sed -i 's/a/b/' a.sh` with cwd `__PROJECT_ROOT__/.claude/worktrees/x/.claude/hooks`.
- [ ] X6 resolution: ask **G** each: `cd .claude/hooks && sed -i 's/a/b/' a.sh`; `sed -i 's/a/b/' a.sh` with cwd `__PROJECT_ROOT__/.claude/hooks`; `sed -i 's/a/b/' ../package.json` with cwd `__PROJECT_ROOT__/src`; `pushd .claude/hooks; popd; sed -i 's/a/b/' package.json`; `pushd .claude/hooks && sed -i 's/a/b/' a.sh`; `cp x .claude/hooks/*`; `cp x .claude/hooks/{a,b}.sh`; `sed -i 's/a/b/' *.json`. Ask **U** each: `cd "$D" && sed -i 's/a/b/' a.sh`; `cd -; sed -i 's/a/b/' a.sh`; `echo x > $T`; `rm "$f"`; `sed -i 's/a/b/' ~/x/package.json`; `for f in package.json tsconfig.json; do sed -i 's/a/b/' "$f"; done`; `find .claude/hooks -name '*.sh' | xargs sed -i 's/x/y/'`. Pass: `pushd .claude/hooks; popd; sed -i 's/a/b/' a.sh` (the `popd` restores the root).
- [ ] X7 wrappers and compounds, ask **G** each: `env sed -i 's/a/b/' package.json`, `nice -n 5 sed -i 's/a/b/' package.json`, `timeout -k 1 5 sed -i 's/a/b/' package.json`, `sudo sed -i 's/a/b/' package.json`, `time sed -i 's/a/b/' vite.config.ts`, `(cd .claude/hooks && sed -i 's/a/b/' a.sh)`, `(cd src); sed -i 's/a/b/' package.json`, `{ sed -i 's/a/b/' package.json; }`, `if true; then sed -i 's/a/b/' package.json; fi`, `echo "$(sed -i 's/a/b/' package.json)"`, `echo "$(rm .claude/hooks/*)"`, `cat <<EOF` / `$(sed -i 's/a/b/' package.json)` / `EOF`, `x=$((1<<2))` / `sed -i 's/a/b/' package.json` (arithmetic opens no heredoc).
- [ ] X10 recursive, ask **P** each: `rm -rf src/features/x`, `rm src/features/x -rf`, `rm --rec src/features/x`, `rm -Rf src/features/x`, `mv src/features/x /tmp/`, `rm -rf src/*`, `mv src/* /tmp/`. Deny *(pin, reason changes)*: `rm -rf src` with reason `A subdirectory is asked`.
- [ ] X11 order, deny each: `rm -rf src/features/x; mkfs.ext4 /dev/sdb` *(pin, reason `Disk formatting`)*, `cp x .claude/hooks/a.sh; touch .claude/.tdd-red/m` (**D**).

**Edge cases — what must not ask**
- [ ] X9 pass each: `cat .claude/hooks/a.sh`, `cat .claude/hooks/a.sh # don't`, `grep x .claude/settings.json`, `sed -n '/error/p;s/we/x/p' .claude/settings.json`, `sed -n '0~4p;/x/,+3p' .claude/settings.json`, `find . -name '*.ts' -exec grep -l x {} +`, `git commit -m "note > package.json"`, `git commit -m "$(cat <<'EOF'` / `it's fine` / `EOF` / `)"`, `rm /tmp/x-*`, `rm 'a[1].txt'` (a quoted bracket is no glob), `sed -i 's/a/b/' docs/*.md` *(open question 1)*, `echo x 2>&1`, `python3 .claude/hooks/kit-doctor.py`, `.claude/hooks/test-hooks.sh 2>&1 | tail -1`, `bash .claude/hooks/test-small-lane.sh`, `python3 .claude/hooks/kit-attempts.py fail docs/work/x/plan.md test "expected > in vite.config.ts"`, `python3 .claude/hooks/kit-attempts.py pass docs/work/x/plan.md test`.

### Harness cases in `test-hooks.sh`
- [ ] X12 failure, scratch kit copy (`cp *.sh *.py` like W8), five resolver states — renamed (missing), 0-byte, `sys.exit(1)`, prints `garbage`, prints rows without the sentinel — and a sixth run with `python3` absent: a scratch bin dir of symlinks to every tool the hook calls except `python3` (the `run_missing_jq_cases` shape, `test-hooks.sh:253-274`), alone on `PATH`. Each state: `sed -i 's/a/b/' package.json` → ask **F**; `echo x > .github/workflows/ci.yml` → ask **F**; `touch .claude/.tdd-red/m` → deny **F**; `ls src` → pass.
- [ ] X14 budget: `rm f1 … f500 package.json` (500 operands) → ask, wall time under 2 s; `rm f1 … f70 .claude/.tdd-red/m` → deny **D** (the cap row keeps the whole text).

### Added after the go (review 1 fix batch, 2026-10-29: reproduction cases, each observed failing first)
- [ ] X15 line continuation: `cp /tmp/m \⏎  .claude/.tdd-red/m` deny **D**; `mv /tmp/a \⏎  .claude/hooks/a.sh` ask **G**; `rm -rf \⏎  src/features/x` ask **P**; `touch .claude/.tdd-\⏎red/m` deny **D**; `cat \⏎  .claude/hooks/a.sh` pass.
- [ ] X16 bash 3.2 (`run_shell_guard_bash3_case`): hook with `mapfile`/`readarray` disabled → `echo x > package.json` ask **G**, `echo hi` pass; the hook holds no bash 4+ construct.
- [ ] X17 cd: `cd -P .claude && touch .tdd-red/m` deny **D**; `cd -- .claude/hooks && sed -i 's/a/b/' a.sh` ask **G**; `env -C .claude/hooks sed -i 's/a/b/' a.sh` ask **G**; `cd /nonexistent; touch .claude/.tdd-red/m` deny **D**; `false && cd /tmp; sed -i 's/a/b/' package.json` ask **G**.
- [ ] X18 `$(…)` position: `cd .claude/hooks && echo "$(touch ../.tdd-red/m)" && cd /tmp` deny **D**; `x=$(sed -i 's/a/b/' package.json); cd docs` ask **G**.
- [ ] X19 target dir: `cp -rt .claude/.tdd-red x` deny **D**; `cp -t.claude/hooks x`, `mv --target-directory=.claude/hooks x`, `install -Dt .claude/hooks x`, `cp --target=.claude/hooks x` ask **G**.
- [ ] X20 patch: `patch -p1 < fix.diff` ask **U**; `patch -o package.json x p.diff` ask **G**.
- [ ] X21 perl -i script: `perl -i -p fix.pl package.json`, `perl -pi fix.pl package.json` ask **G**.
- [ ] X22 reason split (`run_shell_guard_reason_split_case`): broken resolver, `touch .claude/.tdd-red/m` → deny with `shell guard unavailable`, without the D substring.
- [ ] X23 no base (`run_shell_guard_no_base_case`): no `.cwd`, no `CLAUDE_PROJECT_DIR`, `echo x > app/api/routes.py` → pass.

### Regression
- [ ] X13 existing `fixtures/prevent-destructive-commands.sh/01-19` keep their verdicts; every other hook's fixtures and the W/harness cases unchanged.

## Vigilance (carried from research)
- One resolver (`cwk_guard_rel`) and one list (`hook-guarded.sh`): python prints absolute paths, folders and markers, never a verdict or a pattern; the fallback derives its prefixes from `CWK_GUARDED`.
- Every new deny follows the existing denies and precedes every ask; new asks precede the formatter and TS asks, so reasons are the new rule's (X1.12, X11).
- Failure is not a pass, decided in bash; the sentinel catches silent empties; `set -e` never aborts (X12).
- Target position only; running a script, `python3 < file`, `-m` never asks (X9).
- Quoting decided in the pre-scan, not after shlex; heredoc bodies cut (a quoted `<<` opens nothing); comments dropped (X8, X9).
- Bundled interpreter flags and piped stdin programs are inline (X3).
- `xargs` and `sed -i` without file operand → `?unknown`, never "no target" (X6).
- `cd` scoped to `( … )`, `popd` restores, unknown `cd` poisons later relative targets (X6, X7).
- Glob rows carry their folder: root globs ask, `docs/*` passes, `/tmp/*` passes, `.tdd-red/*` denies; `rm -r`/`mv` globs under a protected dir ask (X4, X6, X9, X10).
- `find -exec` asks only when the executed command writes (X2, X9).
- Recursive flag first, last, bundled, abbreviated; `.tdd-red` stays deny over the recursive ask; existing worktree `rm -r` deny unchanged.
- `PROTECTED_DIRS` line shape unchanged (kit-doctor parses it, addons patch it).
- 64-row cap keeps the hook far under its 5 s timeout (X14).
- Accepted limits, out of the writer list: `pnpm add`/`npm install` (package.json), `curl -o`, `wget -O`, `sort -o`, `dd of=` (non-device), awk redirection / `-i inplace`, `tar -C … -x`, `unzip -d`, `sed -f <script file>`, `python3 < file` writing; git's own writers (`light-permissions-git.md`).

## Acceptance criteria (carried from the entry artifact)
- [ ] Every shell write marker listed in Scope, on a guarded path, asks — from the main tree, from a worktree path, and with a worktree `cwd`; on `.claude/.tdd-red/**` it is denied.
- [ ] Kit scripts run with arguments (`kit-doctor.py`, `kit-attempts.py`, `test-hooks.sh 2>&1 | tail`) and reads of guarded paths pass.
- [ ] A recursive `rm`/`mv` under a protected dir asks, flag first, last or abbreviated.
- [ ] With `shell_targets.py` missing, a guarded write asks and a `.tdd-red` write is denied.
- [ ] `test-hooks.sh`, `kit-doctor` pass.

### Proof map
| AC | Proof |
| --- | --- |
| 1 | X1, X2, X3, X7, X8 (markers and carriers), X4 (folders), X5 (worktree path and cwd), X6 (resolution) |
| 2 | X9 |
| 3 | X10, X11 |
| 4 | X12 |
| 5 | step 5 runs |

## Open questions for the gate (from research and plan-critic, with proposed answers)
1. `sed -i 's/a/b/' src/*.ts` (spec X9) collides with the existing TS-source ask → keep the TS ask; X9 uses `sed -i 's/a/b/' docs/*.md`.
2. Who makes a target repo-relative → python prints absolute paths and glob folders; bash's `cwk_guard_rel` decides inside/outside; no `?outside` row. Decides X5, X6, X9.
3. `mv` under a protected dir → every operand, source or destination. Decides X10.5, X10.7.
4. Interpreters → bundled `-c`/`-e` and `node -p`, and a program read from a pipe, are inline (ask, or deny when the command names `.tdd-red`); `python3 -m pkg`, `python3 < file` and a bare interpreter are running. Decides X3.
5. `find -exec|-execdir|-ok|-okdir` (spec: "the find roots") → the roots only when the executed command is itself a writer; a read-only `-exec grep` passes (AC 2). `-delete`, `-fprint*`, `-fls` unchanged. Decides X2, X9.5.
6. "Empty output → failure" (spec, the fallback's `.claude/` trigger kept as written) → empty output is how a read-only command answers, so the resolver ends with a sentinel `#end\t<n>`; a missing sentinel (0-byte script included) is the failure. Decides X12.
7. `docs/ADAPTATION.md` §14 (outside the spec's file list) gains one line saying shell writes on guarded paths ask and `rm -r`/`mv` under a protected dir asks. Decides nothing frozen.

## Plan critic
- pass 1: completeness 78 / quality 60 — failed (Q1, Q3, Q6 + partial C1, Q2, Q4, Q5)
- pass 2: completeness 92 / quality 76 — failed (brace/segment rule, reason precedence)
- pass 3: completeness 94 / quality 80 — failed: **BLOCKED — plan-critic failed 3x**
- surviving blocker: the segment rule's `punctuation_chars=";&|()\n"` has no `<>`, so `>|`, `>&file`, `&>` tokenise as separate separators (X1.5-X1.7 would pass) and `echo x>package.json` stays one word (guarded write with no prompt). Measured with shlex. Critic's fix: `punctuation_chars=";&|()<>\n"`, each punctuation run split by longest match against `&&` `||` `;;` `|&` `&>>` `&>` `>>` `>|` `>&` `<<<` `<&` `<>` `<` `>` `;` `&` `|` `(` `)` newline; only control operators end a segment; `>&`/`<&` + digits = fd dup; case `echo x>package.json` → ask G.
- open Minors: glob placeholders must restart quoting inside `$(…)`/backticks (case `echo "$(rm .claude/hooks/*)"` → G); sed addresses `N~M`, `addr,+N`, `addr,~N`.
- 2026-10-28, user: ceiling waived — "Fix, then gate". The critic's fix and both Minors applied (Segments paragraph, placeholders, sed addresses; cases X1 `echo x>package.json`, X7 `echo "$(rm .claude/hooks/*)"`, X9 `sed -n '0~4p;/x/,+3p'`), no fourth critic run (the critic judged it unnecessary: X1.5-X1.8 fail deterministically at RED if the rule is wrong).
- final: completeness 94 / quality 80 + the applied fix; surviving blockers: none (by the user's waiver).

## Gate
- 2026-10-28 go
- Contract: as written
- plan-critic ceiling (3 failures) waived by the user: "Fix, then gate"; the pass-3 fix applied without a fourth critic run.
- OQ1 `src/*.ts` vs the TS ask → keep the TS ask; X9 uses `docs/*.md`.
- OQ2 repo-relative → python emits absolute paths and glob folders; `cwk_guard_rel` decides; no `?outside` row.
- OQ3 `mv` under a protected dir → every operand, source or destination.
- OQ4 interpreters → bundled `-c`/`-e`, `node -p`, piped programs inline; `-m`, `< file`, bare interpreter are running.
- OQ5 `find -exec` → roots only when the executed command writes.
- OQ6 empty output → sentinel `#end\t<n>`; a missing sentinel is the failure.
- OQ7 `docs/ADAPTATION.md` §14 gains one line.
- amended 2026-10-29 X14.01: "500 operands → ask, wall time of run_case under 2 s" → "500 operands → ask (run_case); the 2 s bound times the hook process alone". Reason: run_case adds 3 python3 starts, load-sensitive (review 1, tests). User-approved; to confirm at the merge.
