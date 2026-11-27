# Research: EcoCrew day fixes   (entry: docs/specs/ecocrew-day-fixes.md)
Token profile: critical

## Pattern to follow
- **Item 1 (stash):** `checkout_rule` uses `worktree_clean` (`.claude/hooks/enforce-git-workflow.sh:785-790`, `git diff --quiet HEAD -- <paths>`, used at :924) to ask only on a dirty tree. A stash rule follows the same shape inside `stash_rule` (:838-842, today asks on `clear|drop` only), registered in `DESTRUCTIVE_RULES` (:1616-1618).
- **Item 4 (Python import head):** the TS freeze `import_additions` (`.claude/hooks/tdd-freeze-tests.sh:232-305`: `head_split`, `decl_names`, the in-order walk, `TEST_GLOBALS` and whole-file identifier collision, auto + `frozen-case unfreeze` verdict for the path at :289-290). Fixtures `run_auto_mode_import_cases` AM48-AM59 (`test-hooks.sh:6817-6884`) are the case list to mirror.
- **Item 3 (ids):** the freeze side already normalises: `loop-record.py:694-703` (`case_ids`, `.upper()`), `addons/fastapi/hooks/tdd_py_lib.py:620-622` (`test_([A-Za-z])([0-9]+)` → upper).
- **Item 3 (message):** SubagentStop hooks report through a top-level `systemMessage` (`eslint-batch.sh:43,79`, `tdd-freeze-tests.sh:88`).

## Wiring points
- Git guard: the python program `parse_segments` (`enforce-git-workflow.sh:218`). Commands split on `;&|()\n` (:234, :369-389), so `ruff check . && git stash -q` reaches `stash_rule` as its own segment. Bash `ask()` (:131-141) turns an ask into `auto mode — blocked stop:` in auto. `kit_combine` keeps deny over ask (:1713-1714).
- Ledger: `loop-record.py` `verdict_blocks` (:402-416), `ledger_entry` (:449-466, `CASE_RE` :40, `REWRITE_CASE_RE` :44, `ROW_RE` :45 shares the id class), `subagent_stop` (:526-560: silent `return` on a None entry, only `blocks[-1]` used, dedupe on raw id :546-550). Dispatch is at :884; settings `^arbiter$` SubagentStop entry (`settings.json:244-256`, pinned by IN63 `test-install.sh:1023-1034`).
- `.tdd-unfrozen` check: `protect-files.sh` `unfrozen_removal_only` (:276-315, accepts deletion or a `# ` / `#` prefix of an existing line), `unfrozen_record_rows` (:325-417, `line_re` :386 uppercase only), auto deny :425 "no unfreeze verdict backs this .tdd-unfrozen entry", non-auto falls to the guarded ask (:~432).
- `--clear` comment-out: `loop-record.py` `comment_row_lines` (:588-611, `UNFROZEN_LINE_RE` :585 uppercase, writes `"# " + line` :605).
- Python freeze: `addons/fastapi/hooks/tdd-freeze-tests-py.py`. Rows setup is at :182-193 (`rows_mode = bool(rows) or bool(refused_ids)`, and in auto the rows come from verdicts too). The import-only insertion refusal is at :307-308. The rows path goes through `tdd_py_lib.rows_refusal` (:638-684, :651-655 "changes text outside every case"). The verdict ledger reader is `loop_auto` (:528-547).
- Route: `kit-gate-route.py` `snapshot_tree` (:107-115, a bare tree sha), `read_fix_base` (:130-136, the whole stripped file resolved as one tree), `command_snapshot` (:540-545, unconditional overwrite), `route_review` (:475-508: `review_scope` reads fix-base when round >= 2 at :478, BEFORE `next` is computed :481-486), main dispatch :555-572.
- Audit: `kit-audit-surface.py` `follow_ups` (:242-267, "has no findings list" :256), loads the route module via `gate_route()` (:210-217).

## Reusable
- `worktree_clean` (git guard), `kit_combine`, bash `ask()`; `head_split`/`decl_names` logic as the spec of the Python twin; `loop_auto` (Python verdict reader); `write_atomic`, `snapshot_tree`, `Refused` in kit-gate-route; `systemMessage` emission shape.
- Test harness: `git-guard.jsonl` + `run_git_guard_cases` (`test-hooks.sh:1010-1050`; `*-modified-*` / `*-staged-*` setups ~:480-500); `am_block`/`am_stop`/`am_v` (:6251-6269, :6548); `lp_py_project` + `am_freeze_rec` + `rv2_pair` + `pv_expect` (:5246, :6720, :2689, :1848); `rf`/`review_in`/`pf`/`plan_in` (`test-gate-route.sh:27-56`); `fin`/`fu` (`test-audit-surface.sh:354-357`).

## Blast radius
- `stash_rule` change touches every `git stash` form; pinned neighbours: G16.010/.011/.089/.090 (clear/drop ask), the kit-boundary family G19.013/.019/.028 (`test-hooks.sh:4319-4351`: a stash with a modified kit file must stay **deny**, `nokit` stash in a src-only tree accepts an ask). Setup lines there use `git stash -q` as fixture commands, not hook calls.
- `CASE_RE` used only in `ledger_entry`; `ROW_RE` shares the id class (plan rows, :200); `line_re` only at protect-files :406; `UNFROZEN_LINE_RE` only in `comment_row_lines`. Normalising the ledger id to uppercase keeps `--clear` matching.
- AM25 (malformed block, `test-hooks.sh:6501-6512`) checks records only; AM26/AM27 (`am_no_decision`) expect empty output for a block-less arbiter and must stay silent.
- Route: G23 (`test-gate-route.sh:180-195`) pins "round 2 with no fix-base is refused" (`refused G23 'fix-base' …` :189) — a design change moves this case. G29 (:295-307) pins fix-base never reaching git as an option. Highest id G31.
- Prompts pinned by contracts (`test-workflow-contracts.sh`): T1 plan-critic `fixed | not fixed` (:1083-1086, line 81 of plan-critic.md); T2 plan.md step 6 needles and order (:1088-1094); T4 orchestrate Phase 5 `kit-gate-route.py snapshot` (:1098-1100); T5 reviewer/review/ship (:1102-1105); T13 review 3bis `status: not-fixed` (:1126); T14 ship 1bis (:1172-1173); PK49-PK49.5 review 3bis dimension list == `DIMENSIONS` (:1690-1706); AMC21 arbiter import phrases (`whole static import declarations`, `top import block`, `import-first`, … :1611-1613); ship.md `remove the applied \`.tdd-unfrozen\` entries in one Edit` (:877).

## Live DB state
n/a

## External surface
n/a

## Traps (points of vigilance for the review)
- T-stash-kit: a stash with a modified kit file stays a **deny** (kit reason), never downgraded to the new ask (G19.019).
- T-stash-unknown: `worktree_clean` returns False for "dirty" and "could not check" alike → both ask (safe); never pass on unknown.
- T-stash-options: `-q`, `-m x`, `push -- <paths>`, `save x`, `-u`/`--include-untracked`/`-a` sit in the args; `list`/`show` must still pass; a stash that only puts untracked files aside (`-u` on a tracked-clean tree) is also putting work aside.
- T-stash-chain: the rule must fire on a stash segment inside `&&`/`;` chains and behind `git -C <dir>`.
- T-fixbase-order: round >= 2 reads fix-base (scope) before `next` is known (`kit-gate-route.py:478`); writing it "when next is fix-batch" must not be needed for the *current* round's scope, only for the next round.
- T-fixbase-stale: fix-base carries no round; "write when absent" lets round 1's base survive into round 3's `fix` diff. The base must be the state right before **this** batch.
- T-fixbase-reader: `read_fix_base` resolves the whole stripped file as one tree — any added marker in the same file breaks it and `diff … fix`, verifier inputs (verifier.md:38-39).
- T-ids-both-sides: ledger id and `.tdd-unfrozen` line must normalise the same way, and `comment_row_lines`/`UNFROZEN_LINE_RE` must still match after `--clear`.
- T-ids-rewrite: `declared-rewrite` keeps Python function names as written (`REWRITE_CASE_RE`); normalise only the `[umrb][0-9]+` form, never `test_…` names.
- T-subagentstop-silent: the new malformed-block message must not fire for an arbiter that emitted no block (AM26/AM27 stay silent) and must use a SubagentStop-valid channel (`systemMessage`), never PreToolUse `hookSpecificOutput`.
- T-py-gate: the Python import-head allowance needs the same gate as TS (auto + `frozen-case unfreeze` verdict for that path); without a verdict, a changed/removed import, a non-import line, a rebinding of a name already in the file, or a test global stays refused — in rows mode too (`rows_refusal` :651-655 bypass only for a pure head addition).
- T-py-multiline: `from x import (\n a,\n b)` multi-line imports and `import a as b` must be read whole; `__future__` imports and module docstrings precede the head.
- T-arbiter-text: arbiter.md import sentence must become true for Python while keeping the AMC21 needles; test-writer.md:145 "refuses an import-only insertion" must match both freezes.
- T-skeleton-real: each JSON skeleton in a prompt must be accepted by its script as written (the spec's contract test), and stay consistent with PK49's dimension list and T13's `status: not-fixed`.
- T-plan-critic-T1: plan-critic.md line 81 `fixed | not fixed` is pinned (T1); the status *output* line (:104) is what must say `not-fixed` and that fixed/refuted findings are dropped before the route.
- T-reviewer-class: reviewer.md says `class` only for Critical/Major (:67-68) but the route requires it on every finding — the skeleton and reviewer.md must agree.
- T-unfrozen-wording: ship.md `remove the applied \`.tdd-unfrozen\` entries in one Edit` phrase stays verbatim; the new deny for a non-verbatim `#` line must not catch the bare `# <exact line>` that `--clear` writes.

## Open questions
1. **Fix-base lifecycle.** Spec: route writes fix-base "when none exists for that round" and never overwrites. Since fix-base has no round (T-fixbase-stale), how is "for that round" known? Proposed: route on round R with `next: fix-batch` writes `fix-base` and a sibling `fix-base.round` holding R; it skips the write when `fix-base.round` already holds R (same-round rerun) and overwrites a base from an earlier round; `read_fix_base` unchanged; `snapshot` (manual) still overwrites and writes no round file. G23 stays (a round-2 route with no fix-base at all is still refused — the round-1 route now writes it).
2. **Stash with untracked-only work** (`git stash -u` on a tracked-clean tree): ask too? Proposed: yes — `-u`, `--include-untracked`, `-a`, `--all` always ask (work is put aside); plain stash asks only on tracked changes.
3. **Name-bound check for Python imports**: whole-file identifier tokens (TS parity, conservative) or `ast` bindings? Proposed: identifier tokens of the current file, like TS (`idents`), plus pytest fixture-ish globals none — refuse any imported name that already appears as an identifier.
4. **Python allowance outside auto** (moi mode with a listed `.tdd-unfrozen` file): TS gates on auto only. Proposed: same — auto + unfreeze verdict only; in moi a listed file is already a whole-file exemption (`tdd-freeze-tests-py.py:187-190`), so nothing is needed there.
5. **Where the skeleton contract test lives**: proposed `test-workflow-contracts.sh` extracts each fenced `json` skeleton from review.md / plan.md / ship.md and feeds it to `kit-gate-route.py route` / `kit-audit-surface.py follow-ups` in a temp repo (or `test-gate-route.sh` / `test-audit-surface.sh` read the prompt files); proposed: in the two script suites, one case each per prompt.
6. **Lowercase ids in the TS freeze** (`tdd-freeze-tests.sh:401` is case-sensitive): out of the spec; proposed: leave (TS titles are uppercase by `test-writer` convention), note as follow-up.
