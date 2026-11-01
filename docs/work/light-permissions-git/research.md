# Research: Git rules and the narrow permissions — amendment 2 re-entry   (entry: docs/specs/light-permissions-git.md)
Token profile: critical

Re-run after amendment 2 (re-review FAIL, 2026-10-29). Amendment 1 is implemented,
staged and green (592 hook cases, 4 gates, K2); its plan's gate decisions are in
`docs/work/light-permissions-git/prior-gate.md`. Sources of this map: the three
re-review reports (each finding measured by piping hook JSON into the staged hooks
against scratch repos) and the greps quoted below. No new explorer: every surface was
mapped line by line by those reviewers and by the amendment-1 research.

## Pattern to follow
- The `cd` rule (`enforce-git-workflow.sh`, `walk`: `if prog in ("cd", "pushd"): state["cd"] = True`; `parse_git`: `addv = "cd"` when set) — amendment 2 generalises it to "any statement before the add other than git add/stage/status/diff/log".
- `COMMIT` table (`dangerous` / `short`) for `-p`/`--patch`/`--interactive`, as `--include`/`--only` were added.
- `floor_subs` (bash) and `fallback_rows(strict=True)` (python) for the fail-closed paths.

## Wiring points
- `walk` iterates `segments(tokens(text))`, nested `$()`/backticks/`eval`/`bash -c` first per segment, then strips `PREFIXES`/assignments, then dispatches on `prog`. A segment that is only prefixes (`then`, `do`, `{`) is skipped (`if i >= len(seg): continue`).
- `parse_git` appends one row per git call; `add_verdict` runs only for `sub == "add"`.
- Deny loop: `addv ∉ {ok, -}` → `add_reason`; `EFF_SUB == add` via alias → hidden. `git stage` is a builtin, so `EFF_SUB == "stage"` and nothing fires (security re-review, measured `git stage -f .env.local` → pass).
- Floor: `floor_subs` splits on whitespace after replacing `;&|()` and newlines; quote characters stay in the words, so `'git` ≠ `git` (correctness re-review, measured `bash -c 'git add -f .env.local'` → pass without python3).
- Cap: `parse_git` returns before `add_verdict` once 50 rows exist; strict fallback tokenises each logical line with shlex, so a quoted `bash -c '…'` / `"$(…)"` stays one token and its git call is never seen (measured pass for add and `--amend`).
- `strip_comments`: the comment test reads `text[i - 1]` of the original text; after a deleted `\`+NL the previous char is the newline, so `x\⏎# ; git add …` drops the rest (measured pass).

## Reusable
- `ADD_UNREADABLE_REASON` already names "a cd before it"; extend it to "another command before it" (the reason substring `cd before` of frozen G11.17/G11.18 must stay).
- `no_python_bin`, `-nopy-` setup, `_harness/git-guard.jsonl` row format.
- `adapt_guard`-style section slicing in `test-workflow-contracts.sh` (§14) for scoping K1c to §15.

## Blast radius
- Frozen pass cases with a `git add`/`git stage` after another statement: **none** (`git-guard.jsonl` passes G3.01-07, G12.01, G11.19 — the add is first; the 01-85 fixture files: none, grep over every `*-pass.json`).
- Kit flows chaining `… && git add` / `; git add` in `.claude/commands`, `.claude/agents`, `.claude/skills`, `.claude/scripts`, `workflow.sh`, `codex-handoff.sh`: **none** (grep). `.claude/commands/loop/small.md:16` uses `git -C <tree> add …` (first statement).
- Frozen deny cases where the add follows another statement: G6.01 `git push origin feat/x && git add -f .env.local` (reason `--force`), G11.22 `touch src/new.ts && git add src/new.ts` (reason `same call`), G11.17/G11.18 (`cd before`): the new rule must not change their reason → apply it only when the add's own verdict is `ok`.
- `github.md` step 3 lists asks `--amend`, `--no-verify`, `--all` only; `ADAPTATION.md` §15 and the hook header claim "every git add denied" on the fail-closed paths (false today for quoted forms).
- `test-hooks.sh`: `HOME` export is wider than needed — git reads `$HOME/.config/git/ignore` only when `XDG_CONFIG_HOME` is unset or empty (tests re-review); `run_git_guard_cases` header comment says "G1-G9", "`setup` (secrets|shim)".

## Live DB state
n/a — kit tooling.

## External surface
- `acceptEdits` auto-approves `mv`, `cp`, `rm`, `sed` on in-project paths `[cache 2026-10-28]`; `.gitignore` is not a guarded path — so `mv .gitignore x && git add -A` runs with no prompt (security re-review, measured: secrets staged).
- A `\`+NL continuation is one call to the matcher `[cache 2026-10-29, measured K2b]`.
- `git stage` is git's builtin synonym of `git add` (git docs; `git --list-cmds=builtins` lists it) `[01-stack.md n/a — git 2.43 on this machine]`.

## Traps (points of vigilance for the review)
- "Alone" means: no earlier statement in the same call except `git add`/`git stage`/`git status`/`git diff`/`git log` (any global options); prefix-only segments (`then`, `do`, `{`) and the add's own wrappers do not count; nested `$()` before the add counts.
- Apply the rule only after the add's own verdict is `ok`, so frozen reasons (`--force`, `same call`, `cd before`) are unchanged.
- `git stage` gets every add rule: force, hidden, nodry, cd/prior, secret dry-run, alias, floor, fallback, cap.
- Raw scans (floor, cap) treat quotes, `$(`, backticks as separators; they over-deny a commit message that names `git add` — fail-closed, accepted on those degraded paths only.
- The comment test reads the last emitted char, not the original text.
- `-p` is a commit short flag here, `-p` of other subcommands untouched (classify per family).
- Fixture HOME isolation: keep `XDG_CONFIG_HOME` set to a scratch dir; drop the `HOME` move.

## Open questions
1. Does a `git -C <dir> add` count as "alone" when it is first? Proposed: yes (the kit's small lane uses it; `-C` already drives the dry-run dir).
2. Is `git status && git add .` allowed (status before add)? Proposed: yes, the allowed set is add/stage/status/diff/log.
3. An assignment-only statement before the add (`X=1; git add a`): proposed counts as a prior statement (deny) — rare, fail-closed.
4. A pipe into the add (`echo a | git add --pathspec-from-file=-`) is already `hidden`; `printf x | git add a` → proposed: the `printf` segment counts (deny).
5. Minors in: github.md `git -C <tree> add` hint + full asks list, stale harness comments, HOME→XDG only, G12.01b/c for `.env.sample`/`.env.template`. Out (follow-ups): the floor's over-deny of a message naming git add (documented), `git -c core.hooksPath=…` commit (prompts: not allow-listed), `g\it` prefilter, `export GIT_WORK_TREE=…` (documented limit), `.env*` back-fill into old `.gitignore` blocks.
