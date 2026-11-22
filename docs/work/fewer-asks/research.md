# Research: Fewer asks   (entry: docs/specs/fewer-asks.md)
Token profile: standard

Two `explorer` probes (shell guard; protect-files / git / prompts), 2026-11-09. Paths under `.claude/hooks/` unless shown. No external surface.

## Pattern to follow
- Hook changes land with fixtures: one JSON per case in `fixtures/<hook>/NN-slug-<pass|deny|ask|allow>.json` (19 for `prevent-destructive-commands.sh`, suffix = verdict, optional `_expect_reason`), or one line in `fixtures/_harness/shell-guard.jsonl` (808 lines, `{"id","verdict","command","cwd?","setup?","reason"}`), run by `test-hooks.sh` (`run_fixture_sweep` :552-575, `run_shell_guard_cases` :876-919, verdict `semantic_verdict` :50-72). CI: `.github/workflows/kit-ci.yml:55`.
- Prompt changes land with a contract grep in `test-workflow-contracts.sh` (example :449 `grep -Fq 'the \`.tdd-unfrozen\` write asks the user' "$ORCHESTRATE"`).
- No Python unit test exists for `shell_targets.py`; it is covered only through the hook harness.

## Wiring points
- `prevent-destructive-commands.sh`: text regexes `SRC_WRITE_RE` :369-372 (loop :397-403: DENY :401 on a test-first target, else ASK :736-737), `PY_WRITE_RE` :380-383 (DENY :392-393 only, gated by `CWK_TDD_PY_TARGET_RE`). Resolver call :421 (`2>/dev/null`, exit code not read → `GUARD_FAILED`), rows → `guard_classify` :508-571, messages :582 / :635-636 / :638-639 / :657 / :659-661 / :669-670. Formatter loop :686-729 (count :709-726). `PROTECTED_DIRS` :78.
- `shell_targets.py`: row format `verb\ttarget` + `#end\tN` (:1755-1762); `target()` :1723-1737; inline rows `?inline:` (:617, :662, :669, :673, :677, :681) hold raw program text, `target()` is not applied to it (:1711); `kit_cwd_rows` :534-549 (needs separator `&&`, :545), `cd_to_root` :1199-1206; `sed_rows` :1543 → `sed_writes(unhide(script))` :1581, `sed_writes` :1608, `Unreadable("unknown sed command")` :1690-1691; ARITH lift :215-219, `arith_end` :273-280; exit: Unreadable/ValueError/IndexError/RecursionError → stderr + exit 1 (:1768-1771), other exception → traceback exit 1, usage → exit 2.
- `protect-files.sh` (PreToolUse `Write|Edit`, `settings.json:80-89`): path-only, reads `file_path|path|glob|pattern` (:54-66), guarded ask :199-200 via `cwk_is_guarded` (`hook-guarded.sh:25`, :76-87).
- `.tdd-unfrozen` parsers (three, "change all three together"): `tdd-freeze-tests.sh:124-146`, `tdd-require-red.sh:136-151`, `addons/fastapi/hooks/tdd_py_lib.py:318-345` — everything after the first `#` dropped, first field, must contain `/`, substring match. A commented line is inert.
- `enforce-git-workflow.sh`: `grammar_strict` :1577-1596, `commit_form` :1582 (`^git commit -m (…)$`, no `-C`, one `-m`), `add_form` :1581 accepts `-C` and calls `grammar_add_ok` :1561-1575; `grammar_decide` :1598-1604 asks or returns; `decide()` :100-112 emits ask/deny only — a pass is silence, so Claude Code's own allow list still applies. `PROTECTED_BRANCHES` :94; commit on a protected tree denied :1314-1315, :1441, :1458 (`-C` tree honoured).
- `settings.json:33-35` allows `Bash(git add *)`, `Bash(git commit -m *)`, `Bash(git switch -c *)`; `test-workflow-contracts.sh:461-468` forbids wider git allows.

## Reusable
- ARITH placeholder (`shell_targets.py:33`, U+E012) already marks arithmetic regions; F9 needs only `sed_rows` to substitute it before `sed_writes`.
- `TDD_TARGET_RE` (:262, `hook-lib.sh:264`), `TDD_FROZEN_TEST_RE`, `cwk_is_guarded`, `GUARD_PROTECTED_RE` (:457) — the classification helpers V3 needs.
- `add_form`'s `-C` handling and `grammar_add_ok`'s tree check (V12 reuses them for commit).
- The freeze hooks' read of the current file (`tdd-freeze-tests.sh:153`, `:298`) — the pattern for reading old content to compute a removal-only Edit (V4).
- Contract-grep and fixture harnesses above.

## Blast radius
- Fixtures that flip under V3: `shell-guard.jsonl` X7.05 (`time sed -i 's/a/b/' vite.config.ts`, ask "guarded path:" → deny), X24.412 (`cp /tmp/x workflow.py`, ask → deny), X25.04 (`python3 - <<'EOF' print(open("src/a.ts").read())`, ask "unresolved write target" → deny). Stay ask (no repo path): X3.01-X3.03, X3.05-X3.09, X24.108. Stay deny: X3.13, X3.14, X24.109, X25.01-X25.03. Stay ask, check reason text: X28.79 (`echo … > src/b.ts`), X24.413 (`echo x > addons/…/tdd_py_lib.py`).
- Parse-failure cases X24.280-285 expect "could not parse" (:636); `run_shell_guard_failure_cases` (`test-hooks.sh:1369-1400`) stubs the script and expects "shell guard unavailable" — a distinct Unreadable exit code must keep both.
- No existing case covers: anchored flags (F1), prettier + redirect (F2), sed `$((…))` (F9), `git -C <feat tree> commit -m` pass or `-m a -m b` ask (F14), removal-only `.tdd-unfrozen` Edit (F12a). All new.
- Prompts: `orchestrate.md` (Phase 0 :67, `.tdd-unfrozen` :258-264, contract amendment :184-192), `ship.md` step 4 :114-122, `github.md` :47-51 / :125-133, `implementer.md:47-48`, `test-writer.md:130-131`, `e2e-tester.md` (no rule today), `spec.md:18-24` and `bmad/pm.md:22-32` (token-profile question "asked alone and asked always"), `interface.md:81-100` and `plan.md:103-111` (contract re-ask), `11-token-budget.md` (only copy of the `critical` trigger list).
- Contract greps that touch edited text: `test-workflow-contracts.sh:701-706` (CLAUDE.md `**Never write source from the shell**` with `-A2`, needles `python3 -`, `node -e`, `perl -i`, `heredoc`, `never by switching tools`; same needles in implementer and test-writer), :449, :468.

## Live DB state
n/a

## External surface
n/a

## Traps (points of vigilance for the review)
- **V3 "keyed on rows" is new code, not a re-wiring.** `guard_classify` makes no decision from a `.ts`/`.tsx`/`.py` path row today; every such decision comes from the text regexes. The deny tier must be added on rows (verbs `sed`, `perl`, `cp`, `tee`, and the other WRITERS except `mv`), keeping redirections (`>`) on today's ask.
- **Redirection vs in-place writes differ only by verb** (`>` vs `sed`/`perl`/`cp`/`tee`). `<>` is recorded as a write redirection (`shell_targets.py:42`, :563).
- **Inline programs carry raw text**: `target()` is never applied to `?inline:` content. "A quoted token that resolves under the project" needs new extraction + resolution; it must not deny `python3 -c "print('a.ts')"` when no such file exists (F3).
- **Anchoring the text regexes alone opens the quoted-flag bypass** (`sed '-i' …`): F1 must ship with the row-based deny, never before it.
- **Guarded configs under V3**: `sed -i vite.config.ts` turns from "guarded path" ask into a Write/Edit deny; the follow-up Edit still asks as guarded — the user is not skipped, only the shell route.
- **Exit code**: Unreadable and a crash both exit 1 today; the new distinct code must not turn a crash into a parse-failure message (X12 stubs expect "shell guard unavailable").
- **Formatter redirect words**: `cwk_segments` splits `2>&1` at `&`, so the segment ends with `2>`; a bare `>` is its own word; `/dev/null` follows a bare operator. The skip rule must cover all three.
- **`mv` message says "recursive" for a single file** (:659-661, no recursion check for `mv`).
- **V4 removal-only needs the old content**: `protect-files.sh` is path-only and never reads `old_string`/`new_string`/`content`; `replace_all` is read by no hook; no MultiEdit handling (matcher is `Write|Edit`). The check must compute the resulting file and prove every resulting line is an existing line or that line commented out — a "comment" that keeps the path before the `#` is still active.
- **V12 is not only the hook**: the hook never emits `allow`, and `Bash(git commit -m *)` does not match `git -C <tree> commit -m …`, so Claude Code prompts even once `commit_form` accepts it (`github.md:125-126` already says so for `git -C add`). Either a new settings allow (forbidden wider allows are checked at `test-workflow-contracts.sh:461-468`) or an explicit hook `allow` is needed.
- **Spec premise on `ship.md`**: step 4 (:114-122) never asks for a body; the body came from the main thread's own prompt. The fix is a positive line ("hand the subject only"), plus `github.md`'s routing of a requested body to the PR.
- **No `.tdd-unfrozen` clean-up step exists in `ship.md`**: part C's 6 clean-up Edits were improvised. V4's "clean-up is one Edit" needs a home.
- **Token profile question**: `spec.md:18-24` and `bmad/pm.md:22-32` say "asked alone and asked always"; `11-token-budget.md` holds the only copy of the `critical` list — V6's new trigger ("loosens a kit guard / widens what runs without a prompt") goes there, and `11-token-budget.md` is at its line budget.
- **Budgets**: `CLAUDE.md` 139/140 lines (V11 must rewrite lines 50-52 in place), rules floor 515/520; contract grep :701-704 reads `-A2` after the bolded phrase, so a renamed phrase breaks it.
- **No "je lance" wording exists in `.claude/`**: V6's rule is a new prohibition, not a removal.

## Open questions
1. V12: let `git -C <tree> commit -m "<one line>"` through by adding `Bash(git -C * commit -m *)` to `settings.json` (the hook's strict grammar still asks on anything else) or by having the hook emit an explicit `allow` on that exact form? (recommendation: the settings allow, the same shape as the three existing ones, with the contract test updated to name it)
2. V1 `mv` of one named file under a protected dir: pass, or keep the ask with a correct message ("move under a protected dir", not "recursive")? (recommendation: keep the ask, fix the message — a move out of `src/` is a deletion from the tree)
3. V4 clean-up: where does the "remove applied entries in one Edit" step live — `ship.md` (before the commit) or `orchestrate.md`'s `.tdd-unfrozen` paragraph? (recommendation: `ship.md`, it is where part C did it)
4. V6: the token-profile question in `spec.md` and `bmad/pm.md` becomes "printed, asked only on a trigger" — confirm the fourth trigger wording for `11-token-budget.md`: "loosens a kit guard or widens what runs without a prompt".
