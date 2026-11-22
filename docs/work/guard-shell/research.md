# Research: Guarded set, shell side   (entry: docs/specs/guard-shell.md)
Token profile: critical

Reuses `docs/work/light-permissions/research.md` (external facts, overlap with harness-hardening), its plan-critic findings (`docs/work/light-permissions/handoff.md`, pass 3), and `docs/work/guard-writes/research.md`. Probed on the main thread (the surface is four files already read in full for this pass); no explorer, no external fetch: every external question is cached.

## Pattern to follow
- **Shlex segment parser in python, rows back to bash**: `enforce-git-workflow.sh:100-289` — `parse_segments` runs `python3 - "$1" "$2" <<'PY'`, wrapper set `PREFIXES` `:108-109`, assignments skipped `:243-245`, `$(`/backtick recursion with a depth cap `:236-240`, `ValueError` → `state["unread"]` `:231-234`, one tab-separated row per call. `shell_targets.py` is the same shape as a file (`python3 -B`), resolving only.
- **Classifier**: `hook-guarded.sh` (shipped d6839cb) — `cwk_guard_rel <path> [<base>]` `:125-154` (join base, lexical normalisation, project or physical prefix strip, symlink fallback, `.claude/worktrees/<x>/` strip, exit 1 outside), `cwk_is_guarded` `:54-65` (folders above a pattern count, `.` included), `cwk_is_guard_denied` `:69-77` (`.claude/.tdd-red` and below).
- **Emitters**: `prevent-destructive-commands.sh` `decide/deny/ask` `:31-49`; every existing deny `:60-372` precedes the two existing asks `:424-430` (comment `:187-195`).
- **Fixtures**: `fixtures/prevent-destructive-commands.sh/01-19` (commands listed in the run of this probe); top-level `"cwd"` already used by git fixtures; `run_case` pins `CLAUDE_PROJECT_DIR=$PROJECT_ROOT` and substitutes `__PROJECT_ROOT__` (`test-hooks.sh:81-160`). Harness cases on a scratch kit copy: `run_guarded_hardening_cases` W8 (`test-hooks.sh:402-423`, `cp *.sh *.py` into `$tmp`, `guard_hook_run` `:395-398`) — the shape for X12.

## Wiring points
- `prevent-destructive-commands.sh`: input `COMMAND` `:17` (no `.cwd` read yet); `PROTECTED_DIRS` `:76` (parsed by `kit-doctor.py:95`, patched by the fastapi/supabase addons — keep the line shape); recursive-rm deny loop `:95-120`, text to update `:101-102`; `find -delete` deny `:136-141`; secrets deny `:176-185`; system denies `:198-220`; frozen-test rm/mv deny `:257-262`; snapshot deny `:290-295`; Python/TS source-write `:349-372`; formatter ask `:385-426`; TS-source ask `:428-430`. New deny rows go after `:372`'s loop, new asks after `:426`.
- Bash hook timeout 5 s (`.claude/settings.json`, PreToolUse `Bash`), shared with `enforce-git-workflow.sh`.
- `kit-doctor.py:752-757` `NON_HOOKS` (has `hook-guarded.sh`, lacks `shell_targets.py`; else `check_hook_wiring` `:828` flags it mute).
- `install.sh:202` copies every file under `.claude/hooks/` except `*.pyc`: `shell_targets.py` ships with no install edit.
- `test-hooks.sh` run order `:457-470`; kit CI runs it and doctor (`.github/workflows/kit-ci.yml:20,34`).

## Reusable
- `cwk_guard_rel`, `cwk_is_guarded`, `cwk_is_guard_denied`: the only resolver and the only list; python neither copies the patterns nor decides.
- `cwk_segments` (`hook-lib.sh:207`) stays for the existing regex rules; the new rule does not use it.
- The git parser's wrapper set and its `$(`/backtick recursion (`enforce-git-workflow.sh:108-109,236-245`) as the reference list; not imported (a heredoc-embedded script), copied into `shell_targets.py` as named in the spec.

## Blast radius
- Existing fixtures 01-19 (X13): none names a writer verb on a guarded path. `10` (`prettier --write $(git diff --name-only)`) recurses into a read-only `git diff` → no row; `15` (`xargs npx prettier --write`) has no writer verb; `16` is quoted data; `18` keeps its formatter ask.
- Existing behaviour that changes: `rm -rf src/features/x` passes today (the documented "specify a subdirectory" escape, `:98-102`) and asks after (X10).
- `test-hooks.sh` writes into the real `.claude/.tdd-red/` from its own process (`:106-115`): running it is not a writer (X9).
- Harness W8 (`test-hooks.sh:404-423`) copies `*.sh *.py` into a scratch kit: `shell_targets.py` rides along; it must not break the `guarded-empty` variant (the hook exits 2 at source, before any python).
- After ship, in this repo: every shell write on `.claude/hooks/**`, `.claude/scripts/**`, settings, `package.json`, `tsconfig*.json`, `vite.config.*`… asks, and any `mv` under `src/`, `.claude/`, `shared/`… asks.

## Live DB state
n/a.

## External surface
- `acceptEdits` auto-approves `rm`, `mv`, `cp`, `sed`, `touch`, `mkdir` inside the working dir and does not prompt under `.claude/worktrees/` [cache 2026-10-28, `claude-code-permissions.md`]: there this hook is the only guard (X5).
- A hook `ask` overrides `acceptEdits` and allow rules — spike of guard-writes, three cases [cache 2026-10-28].
- Only exit 2 blocks; a crash or a timeout falls through to normal permissions [cache 2026-10-28]: the "failure is not a pass" branch must run in bash, never depend on python.
- Hook input carries a top-level `cwd` [cache 2026-10-28]; read it with `jq -r '.cwd // empty'`.

## Traps (points of vigilance for the review)
- **The existing TS-source ask collides with X9.** `SRC_WRITE_RE` (`:340`) matches `sed -i 's/a/b/' src/*.ts` and asks today; X9 lists it as pass. X13 does not cover it (no existing fixture), the spec does not retire the TS ask (Open question 1).
- **Resolution has one copy.** The spec's row format says `<target>` is repo-relative or `?outside`; making python compute that duplicates `cwk_guard_rel` (physical project form, symlink fallback, worktree strip) — the drift plan-critic pass 3 flagged (Open question 2).
- **Every deny row before every ask**, including the existing denies: X11 (`mkfs` after an ask-worthy `rm -rf`, `.tdd-red` after a guarded `cp`). The new rows are computed once and consumed by two passes.
- **Fail closed in bash**: python3 missing, script missing, nonzero exit, empty/malformed output, `ValueError` → the text fallback (`.tdd-red` deny, `.claude/` / guarded root file / heredoc / writer verb ask). `set -e` is on (`:8`): the python call must not abort the hook.
- **Target position only**: `python3 <script> args`, `bash <script>`, `<script> 2>&1 | tail` never produce a row (X9); `2>&1`, `>&2` are fd dups, not targets.
- **Quoted text is data** unless it holds `$(`/backtick: `git commit -m "note > package.json"` passes; `echo "$(sed -i … package.json)"` asks.
- **Heredocs**: body cut before shlex (`it's` would raise), except a stdin-program heredoc (`python3 - <<EOF`, `bash <<EOF`) → `?inline:<body>`; an unquoted body is scanned for `$(`/backticks.
- **Implicit operands**: a writer reached through `xargs` (`… | xargs sed -i 's/x/y/'`) has no visible file operand → `?unknown`, never "no target".
- **`cd` scope**: `(cd src); sed -i … package.json` — the `cd` dies with its subshell; `cd "$D"`, `cd -` → later relative targets `?unknown`; `pushd`/`popd` a stack.
- **Glob rows**: `cwk_is_guarded .` is true (folders above count), so a glob whose literal prefix has no `/` (`rm *.log` from the root) resolves its folder to `.` and asks; `rm /tmp/x-*` is `?outside`.
- **Recursive rule spelling**: flag first, last, bundled (`-Rf`), abbreviated (`--rec`); `rm -r .claude/.tdd-red` must come out deny, not the recursive ask; the worktree `rm -r` deny (`:66`) keeps its own message.
- **`PROTECTED_DIRS` line shape** is parsed by `kit-doctor.py:95` and sed-patched by addons: read it, never rewrite it.
- **Time budget**: one `python3 -B` start plus one `cwk_guard_rel` per row (each forks `cd -P`), inside a 5 s timeout shared by nothing else in this hook; a timeout fails open.
- **Accepted limit, out of the writer list**: `pnpm add` / `npm install` rewrite `package.json` without a listed verb; `git checkout -- package.json` is git's (`light-permissions-git.md`).

## Open questions
1. **`sed -i 's/a/b/' src/*.ts` (X9 pass) vs the existing TS-source ask (`:338-341,428-430`).** Proposed: keep the TS ask (out of this spec's scope) and replace the X9 case with a non-TS glob outside the guarded set, `sed -i 's/a/b/' docs/*.md`, which proves the same thing (a glob whose prefix is not guarded passes).
2. **Who makes a target repo-relative?** Proposed: `shell_targets.py` emits the **absolute, lexically joined** path (base + tracked `cd`), never a repo-relative one; bash runs `cwk_guard_rel` on it, and its exit 1 is the `?outside` verdict. Rows stay `<verb>\t<target>` with the same `?unknown`, `?glob:<prefix>`, `?inline:<text>` markers; `?outside` is no longer printed by python.
3. **`mv` "of a path under a protected dir"**: the sources only (the path that leaves), or the destination too? Proposed: every `mv` operand, source or destination, resolved under a protected dir (`mv /tmp/x src/` replaces a tree under `src/` as surely as moving one out).
4. **Interpreters running a module or with no program**: `python3 -m pkg`, a bare `node` with no argument and no heredoc. Proposed: `-m <mod>` is running (no row, like a script); an interpreter with neither a program file, `-c/-e`, `-` nor a heredoc reads a terminal → no row.
