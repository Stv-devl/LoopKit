# Plan: EcoCrew day fixes   (entry: docs/specs/ecocrew-day-fixes.md · research: docs/work/ecocrew-day-fixes/research.md · design: n/a)
Token profile: critical
Base: 309dc3eb425a1632be35bc4c8d0f0f0ee9514071

## Skips
- DB, backend, front, wiring: SKIP — kit hooks, scripts and prompts only.
- INTERFACE: SKIP — no user surface.
- TS/Python test-first layers: none. Every suite here is a kit shell fixture suite, outside the freeze matcher. The discipline still holds: each leg's cases are written first and observed red, then the code; existing cases are never rewritten.

## Write chain (sequential)
1. **Stash guard.** SG1-SG17 red (SG8-SG12 are pass guards) → `stash_rule` in `.claude/hooks/enforce-git-workflow.sh` (and its header comment at :33).
2. **Case ids + malformed message + comment-out deny.**
   - AM64-AM74 and UW1-UW4 red. AM73 and AM74 also touch `tdd_py_lib.py` `unfrozen_ids` and the TS `.tdd-unfrozen` id reader.
   - Then `.claude/hooks/loop-record.py`:
     - `ledger_entry` normalises `[umrb][0-9]+` to uppercase, for both kinds;
     - `subagent_stop` emits a `systemMessage` for a malformed last block;
     - `UNFROZEN_LINE_RE` accepts lowercase.
   - Then `.claude/hooks/protect-files.sh`:
     - `line_re` accepts any case and normalises before the lookup;
     - a distinct deny for a `#` line that is not a verbatim comment-out.
3. **Python freeze import head.** PI1-PI20 red → `addons/fastapi/hooks/tdd-freeze-tests-py.py` (and `tdd_py_lib.py` if the head split and the rows bypass belong there).
4. **Route and audit scripts.** G32-G35, G39-G42, G46, G47, G49 and A47 red. G36-G38, G43 and G48 are guard cases that pass on today's code; they are written first and stay green → `.claude/hooks/kit-gate-route.py` (fix-base write, `fix-base.round`, error hints) and `.claude/hooks/kit-audit-surface.py` (error hint).
5. **Prompts.** PK61-PK69, G44, G45 and A48 red, then the prompts (and `docs/Claude_Workflows.md:168`):
   - `.claude/commands/loop/review.md` (3bis skeleton);
   - `.claude/commands/loop/plan.md` (step 6 skeleton);
   - `.claude/commands/loop/ship.md` (1bis step 5 audit skeleton, step 4 comment-out wording);
   - `.claude/commands/loop/orchestrate.md` (Phase 5 step 1: the route writes fix-base);
   - `.claude/agents/plan-critic.md` (status output line);
   - `.claude/agents/reviewer.md` (class on every finding in the route file);
   - `.claude/agents/arbiter.md` (id format, Python import sentence);
   - `.claude/agents/test-writer.md` (:145 import guidance).
6. **Run every suite:** every `.claude/hooks/test-*.sh`, which covers:
   - `test-hooks.sh` in full mode, including the fastapi addon fixtures such as `addons/fastapi/hooks/test_imported_symbols.py` (PX7);
   - `test-workflow-contracts.sh`, `test-gate-route.sh`, `test-audit-surface.sh`;
   - `test-install.sh`, `test-kit-doctor.sh`, `test-small-lane.sh`, `test-kit-track.sh`;
   - `test-attempts.sh`, `test-measure.sh`, `test-pr-assets.sh`, `test-rules-floor.sh`.

   Then run `python3 .claude/hooks/kit-doctor.py`.
7. **Refactor** under a green suite, no case edited.

## Parallel lots (inside this track, same tree)
| Lot | Files owned | Depends on |
| --- | --- | --- |
| A, legs 1-3, sequential inside | enforce-git-workflow.sh, loop-record.py, protect-files.sh, tdd-freeze-tests.sh, addons/fastapi/hooks/tdd-freeze-tests-py.py, addons/fastapi/hooks/tdd_py_lib.py, test-hooks.sh | none |
| B, legs 4-5, sequential inside | kit-gate-route.py, kit-audit-surface.py, test-gate-route.sh, test-audit-surface.sh, test-workflow-contracts.sh, commands/loop/{review,plan,ship,orchestrate}.md, agents/{plan-critic,reviewer,arbiter,test-writer}.md, docs/Claude_Workflows.md | none |

No file appears in both lots. Step 6 (every suite) runs after both.

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: the kit guard hooks (git guard, protect-files, freeze, ledger). No other kit pass runs beside this one until it is merged.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| .claude/hooks/enforce-git-workflow.sh | Edit | `stash_rule`: ask on tracked changes (staged or unstaged) |
| .claude/hooks/loop-record.py | Edit | id normalisation, malformed-block `systemMessage`, lowercase `UNFROZEN_LINE_RE` |
| .claude/hooks/protect-files.sh | Edit | any-case `line_re`, distinct non-verbatim `#` deny |
| addons/fastapi/hooks/tdd-freeze-tests-py.py | Edit | import-head allowance (auto + unfreeze verdict), rows mode included |
| addons/fastapi/hooks/tdd_py_lib.py | Edit | head split / rows-refusal bypass helper; `unfrozen_ids` accepts lowercase |
| .claude/hooks/tdd-freeze-tests.sh | Edit | `.tdd-unfrozen` id reader accepts lowercase (AM74) |
| docs/Claude_Workflows.md | Edit | stash ask list (:168) |
| .claude/hooks/kit-gate-route.py | Edit | route writes `fix-base` + `fix-base.round` on `fix-batch`; error hints |
| .claude/hooks/kit-audit-surface.py | Edit | "has no findings list" names the envelope |
| .claude/hooks/test-hooks.sh | Edit | SG1-SG17, AM64-AM74, UW1-UW4, PI1-PI20 (added only) |
| .claude/hooks/test-gate-route.sh | Edit | G32-G49 (added only) |
| .claude/hooks/test-audit-surface.sh | Edit | A47, A48 (added only) |
| .claude/hooks/test-workflow-contracts.sh | Edit | PK61-PK69 (added only) |
| .claude/commands/loop/review.md, plan.md, ship.md, orchestrate.md | Edit | skeletons, fix-base sentence, comment-out wording |
| .claude/agents/plan-critic.md, reviewer.md, arbiter.md, test-writer.md | Edit | status value, class rule, id format, Python imports |

## Contracts
- **Stash.** The subcommand is found the way git and `kit_stash` find it (`enforce-git-workflow.sh:1365`): `args[0]` when it is a known subcommand (`list`, `show`, `drop`, `pop`, `apply`, `branch`, `push`, `save`, `clear`, `create`, `store`), else `push`. So `git stash -p show` is a push.

  For `push` and `save`, `stash_rule(args, ctx)` returns `ask:` when the tree has tracked changes, staged or unstaged. This means `worktree_clean(dir, [], ctx)` is False (`git diff --quiet HEAD`), which includes "could not check".

  A tree with no tracked change passes, whatever the flags (`-u`, `-a`, `--include-untracked`, `--all`, `-qu`, `--incl` included), as the spec says: "a stash with no tracked change pass as today". An untracked-only stash also puts work aside; that is a follow-up, not this pass (arbiter correction 1).

  It returns `-` for `list`, `show`, `create`, `store`, `pop`, `apply`, `branch` (the pop/apply/branch kit rules are unchanged). `clear` and `drop` keep asking. The ask text opens `git stash would put tracked work aside` and ends with the existing "Show the exact call, then let the user decide." suffix. In auto, bash `ask()` turns it into `auto mode — blocked stop: …`. A kit deny still wins (`kit_combine`).
- **Ledger.**
  - `ledger_entry` accepts `case` matching `^[UMRBumrb][0-9]+$` and stores `case[0].upper() + case[1:]`, for both `frozen-case` and `declared-rewrite`. A `test_…` name stays as written.
  - `subagent_stop` takes the last block. When `ledger_entry` returns None, it prints one JSON line `{"systemMessage": "arbiter verdict not recorded: <field> <problem>; …"}` naming the first failing field (`kind`, `path`, `case`, `sha256` or `verdict`) and records nothing. With no block at all, it prints nothing (AM26/AM27 unchanged).
  - `UNFROZEN_LINE_RE` accepts lowercase ids and compares them uppercased.
  - The freeze-side readers of listed ids accept lowercase too and uppercase them: `addons/fastapi/hooks/tdd_py_lib.py` `unfrozen_ids` (:550-564) and the TS `.tdd-unfrozen` id reader (`tdd-freeze-tests.sh:~200`). A `# b204:` line therefore means the same to every reader.
- **`.tdd-unfrozen` check.**
  - `line_re` accepts `[UMRBumrb][0-9]+` (comma lists included). Each id is uppercased before the `(path, id)` lookup.
  - An **annotated comment-out** is denied, in auto and in moi alike. It is a new line that starts with `#` and, after the `#`, holds an existing entry line plus other text around it, where the entry line was removed in the same edit. The deny text is: `.tdd-unfrozen: a comment-out is the bare '# ' prefix of the exact existing line, nothing else; to drop an entry, delete its line`.
  - Unchanged: a plain new `#` header comment, `# <exact line>` and `#<exact line>` (both accepted today by `unfrozen_removal_only`), and the moi guarded ask for every other change.
- **Python import head.**
  - The head is the module docstring, `from __future__` lines, blank lines, `#` comment lines, and whole `import …` / `from … import …` statements (multi-line parenthesised included). It ends at the first other statement.
  - An Edit of a frozen test file whose only change is new whole import statements inserted into the head passes when all of these hold:
    - the session is auto;
    - a `frozen-case unfreeze` verdict exists for that path, and no `refuse` verdict;
    - every existing head line is kept in order and unchanged;
    - no new name (the binding, or its `as` alias) is an identifier token already present in the current file.
  - It passes whether rows mode is on (the file is listed in `.tdd-unfrozen`) or off (verdict ledgered, no line yet).
  - Always refused, even with a verdict:
    - a star import `from x import *`;
    - any text after the statement on its line other than a `#` comment (`import os; g = 1`);
    - a binding named `pytestmark`, `pytest_plugins`, `setup_module`, `teardown_module`, `setup_function`, `teardown_function`, `setUpModule`, `tearDownModule`, or any `pytest_*` name. This is the Python twin of TS `TEST_GLOBALS`.
  - Known limit, stated in the hook header: an imported fixture (autouse, or one that shadows a conftest fixture by name) is not detected.
  - A mixed edit made of a head addition plus a pure new case (with its own assertion) is judged as that insertion.
  - A head addition plus a rewrite of an existing case's body in one Edit is not covered: Python takes the imports in their own Edit. Anything else falls through to today's checks. A Write is never covered.
- **Route.** `route` in review mode with `next == "fix-batch"` decides the fix-base as follows:
  - **Written** (the tree sha to `docs/work/<slug>/fix-base` via `write_atomic`, and the round to `docs/work/<slug>/fix-base.round`) when:
    - `fix-base` is absent;
    - or `fix-base.round` exists and holds another round;
    - or this is round 1, `fix-base.round` exists, and its recorded route-file digest differs from this call's. A fresh `/loop:review` is round 1 with a new route file, and round 1 never reads the scope, so a leftover base from an earlier review is replaced.
  - `fix-base.round` holds `<round> <sha256 of the route input file>` on one line. A rerun of the same round-1 route file (same digest) is kept, even with tracked changes made in between (proposed answer to plan-critic F6).
  - **Kept** when:
    - `fix-base` exists with no `fix-base.round` (written by `snapshot`, the orchestrate Phase 5 step 1 command, which still runs);
    - or `fix-base.round` holds this round and the round is >= 2.
  - Output gains `"fix_base": "written" | "kept"`. Any other `next`, and plan mode, writes nothing and adds no key.
  - The round-R scope still reads the fix-base present before the write.
  - `snapshot` overwrites `fix-base` and **deletes** `fix-base.round`. Its base then belongs to no round, so the next route keeps it. `read_fix_base` is unchanged: `fix-base` holds only the tree sha.
- **Error hints.**
  - `status must be one of ('new', 'not-fixed')` gains `; a fixed or refuted finding is dropped before the route`.
  - `a P1 finding needs kind demonstrated or interpretation` gains `; a vigilance finding takes p1_class null`.
  - `input: mode must be plan or review` gains `; add "mode": "review" (route-review-<round>.json) or "mode": "plan" (route-plan-<pass>.json)`.
  - The audit `has no findings list` gains `; wrap the list as {"findings": [...]}`.
- **Skeletons.**
  - Each of review.md 3bis, plan.md step 6 and ship.md 1bis step 5 holds one fenced `json` block, right after a line starting `Skeleton (accepted as written by`.
  - The review and plan skeletons hold one complete finding each, with every required key, and name the allowed values in the prose around them.

## Test plan (gate — validated before EXECUTE)

### Test-after — kit shell fixture suites (outside the freeze matcher; written first, observed red, never rewritten)

#### .claude/hooks/test-hooks.sh — stash guard (new group, ids SG)
**Reproduction**
- [ ] SG1 with a modified tracked file, `git stash -q` is asked (reason contains `git stash would put tracked work aside`)
**Core behaviour**
- [ ] SG2 with a modified tracked file, bare `git stash` is asked
- [ ] SG3 with a modified tracked file, `git stash push -m x` is asked
- [ ] SG4 with a modified tracked file, `git stash save x` is asked
- [ ] SG5 with a modified tracked file, `ruff check . && git stash -q` is asked
- [ ] SG6 with a modified tracked file, `git -C <tree> stash` is asked
- [ ] SG7 in a tree whose loop record is auto, with a modified tracked file, `git stash` is denied with `auto mode — blocked stop:`
**Business rules**
- [ ] SG8 with a tracked-clean tree, `git stash` passes
- [ ] SG9 with a modified tracked file, `git stash list` passes
- [ ] SG10 with a modified tracked file, `git stash show` passes
- [ ] SG11 with a tracked-clean tree holding an untracked file, `git stash -u` passes
- [ ] SG12 with a tracked-clean tree holding an untracked file, `git stash push --include-untracked`, `git stash -a`, `git stash --all`, `git stash -qu` and `git stash --incl` each pass
- [ ] SG15 with a modified tracked file, `git stash -u` is asked
- [ ] SG16 with a modified tracked file, `git stash -p show` (pathspec `show`, a push) is asked
- [ ] SG17 with a change that is only staged (`git add` done, worktree equal to the index), `git stash` is asked
**Edge cases**
- [ ] SG13 with a modified kit file (`.claude/hooks/x`), `git stash` is still denied with the kit reason (not downgraded to the ask)
- [ ] SG14 `GIT_DIR=x git stash` (tracked state cannot be checked) is asked, never passed

#### .claude/hooks/test-hooks.sh — ledger ids and malformed blocks (AM family)
**Reproduction**
- [ ] AM64 an arbiter block `kind: frozen-case`, `case: b204`, valid path/sha/`verdict: unfreeze` is ledgered with id `B204`
**Core behaviour**
- [ ] AM65 in auto, the `.tdd-unfrozen` line `<path>  # b204: <reason>` backed by that verdict is accepted by protect-files
- [ ] AM66 in auto, `<path>  # B204, b205: <reason>` is accepted when both verdicts are ledgered (as `B204` and `B205`)
- [ ] AM67 a block missing `sha256` makes the arbiter stop print a `systemMessage` that names `sha256`; the record gains no verdict
- [ ] AM68 a block with `verdict: maybe` prints a `systemMessage` naming `verdict`; nothing recorded
**Business rules**
- [ ] AM69 a `declared-rewrite` block with `case: b204` is ledgered as `B204`; one with `case: test_s27_ac5_a` keeps that name as written
- [ ] AM70 a second verdict `case: B204` after a ledgered `b204` for the same path is a duplicate: the first stays, nothing added
- [ ] AM71 `loop-record.py --clear` comments out a `.tdd-unfrozen` line written `<path>  # b204: <reason>` whose verdict it backed
**Edge cases**
- [ ] AM72 an arbiter that emitted no `ARBITER VERDICT` block still prints nothing (silent, as AM26)
- [ ] AM73 moi rows mode, Python: the record holds **no plan row for B2** (rows emptied after `lp_py_project`), and a `.tdd-unfrozen` line `tests/services/test_b.py  # b2: <reason>` lets the freeze accept an edit of case B2 through `unfrozen_ids` (the lowercase id is read as `B2`)
- [ ] AM74 moi rows mode, TS: no plan row for U2, and a `.tdd-unfrozen` line `<path>  # u2: <reason>` is read as `U2` by the TS freeze's listed-id reader

#### .claude/hooks/test-hooks.sh — `.tdd-unfrozen` comment-out (ids UW)
**Reproduction**
- [ ] UW1 in auto, replacing an entry by `# applied: <exact line>`, and separately by `# <exact line> applied`, is each denied with a text containing `a comment-out is the bare '# ' prefix`
**Core behaviour**
- [ ] UW2 in auto, replacing an entry by `# <exact line>` passes
- [ ] UW3 in moi, replacing an entry by `# applied: <exact line>` is denied with the same text (not the guarded ask)
- [ ] UW4 in moi, adding a new header line `# entries for story 3` is still the guarded ask (unchanged), and in auto `#<exact line>` (no space) replacing an entry still passes

#### .claude/hooks/test-hooks.sh — Python freeze import head (ids PI; frozen `tests/services/test_b.py` from `lp_py_project`, auto record with `am_freeze_rec`)
**Reproduction**
- [ ] PI1 the file listed in `.tdd-unfrozen` (rows mode on), record `rows: []` and one `frozen-case unfreeze` verdict for the path: an Edit inserting `from datetime import UTC` right after the existing import passes (the EcoCrew 3.3 case)
**Core behaviour**
- [ ] PI2 rows mode off: `.claude/.tdd-unfrozen` emptied after `lp_py_project`, auto record with one `unfreeze` verdict for the path: the same head insertion passes
- [ ] PI3 the same insertion, with an `unfreeze` verdict ledgered only for a **different** path, is denied, in both rows on (PI1 state) and rows off (PI2 state)
- [ ] PI4 with a verdict, changing the existing import to `from app.services.b import g, h` is denied, in both rows states
- [ ] PI5 with a verdict, adding `from x import g` (a name already in the file) is denied, in both rows states
**Business rules**
- [ ] PI6 with a verdict, adding a multi-line `from x import (\n    a,\n    c,\n)` passes
- [ ] PI7 with a verdict, adding `import numpy as np` passes; adding `import numpy as g` is denied
- [ ] PI8 with a verdict, adding `X = 1` to the head is denied
- [ ] PI9 the path holds an `unfreeze` verdict for case B1 and a `refuse` verdict for case B2: the head insertion is denied
- [ ] PI10 a file that opens with a module docstring and `from __future__ import annotations`: inserting `import os` after its imports passes with a verdict
**Edge cases**
- [ ] PI11 with a verdict, a Write of the whole file that adds the import is denied
- [ ] PI12 with a verdict, one Edit holding a head import plus a new case with its own assertion appended at the end passes
- [ ] PI13 with a verdict, an import inserted inside a case body is denied
- [ ] PI14 moi mode (no auto record), file not in `.tdd-unfrozen`: the head insertion is denied (unchanged)
- [ ] PI15 with a verdict, adding `from x import *` is denied
- [ ] PI16 with a verdict, adding `import os; g = 1` is denied, and `import os  # for paths` passes
- [ ] PI17 with a verdict, adding `from h import pytestmark`, `from h import setup_module` and `from h import pytest_generate_tests` are each denied
- [ ] PI18 with a verdict, one Edit holding a head import plus a rewrite of case B2's body is denied (Python takes the imports in their own Edit)
- [ ] PI19 with a verdict, an Edit that adds an import and removes an existing head line is denied
- [ ] PI20 with a verdict, an import inserted at module level between the two cases (after the head ends) is denied

#### .claude/hooks/test-gate-route.sh — fix-base and error hints (G32+; each case in its own slug dir, never `docs/work/t` or `v`)
**Reproduction**
- [ ] G32 slug `fa`, with an uncommitted tracked change to `src/a.ts`: a round-1 review route with a blocking finding (`next: fix-batch`) and no fix-base writes `fix-base` and `fix-base.round` starting `1 `; `git ls-tree <fix-base> src/a.ts` names the blob `git hash-object src/a.ts` prints, so the base is the working tree, not HEAD; the output has `"fix_base": "written"`
**Core behaviour**
- [ ] G33 slug `fb`: a round-2 fix-batch route with `fix-base.round` = `2 <sha256 of another file>` already present leaves `fix-base` byte-identical and outputs `"fix_base": "kept"`
- [ ] G34 after G32, a tracked change to `src/b.ts` made after the route call: `diff docs/work/fa/plan.md fix` exits 0 with no manual `snapshot`, names `src/b.ts`, and does not name the pre-route `src/a.ts` change
- [ ] G35 slug `fc`: a round-2 route ending in `fix-batch`, with `fix-base.round` = `1 <sha256>`, judges its scope against the round-1 base, then rewrites `fix-base` to the current tree and `fix-base.round` to start with `2 `
- [ ] G46 slug `fd`: after a `snapshot` (no `fix-base.round`), a round-1 fix-batch route outputs `"fix_base": "kept"` and leaves `fix-base` byte-identical (the existing fixture's order)
- [ ] G47 slug `fe`: `fix-base.round` = `1 <digest of another route file>` left by an earlier, cleared review, then a new round-1 fix-batch route outputs `"fix_base": "written"` and the current tree
- [ ] G49 slug `ff`: the same round-1 fix-batch route file routed twice, with a tracked change made between the calls: the second call outputs `"fix_base": "kept"` and `fix-base` is byte-identical
**Business rules**
- [ ] G36 a review route ending in `clear` writes no fix-base and has no `fix_base` key
- [ ] G37 a review route ending in `write-closure` writes no fix-base
- [ ] G38 a plan route never writes fix-base
- [ ] G39 `snapshot` overwrites `fix-base` and deletes `fix-base.round`
- [ ] G48 every existing case G1-G31 runs unchanged and green (the shared `docs/work/t` snapshot is kept by G1/G2/G3)
**Edge cases (error hints)**
- [ ] G40 a review finding with `status: refuted` is refused with text containing `a fixed or refuted finding is dropped before the route`
- [ ] G41 a plan finding with `p1_class: b`, `kind: vigilance` is refused with text containing `a vigilance finding takes p1_class null`
- [ ] G42 a route file with no `mode` is refused with text containing `add "mode": "review"`
- [ ] G43 a round-2 route with no fix-base at all is still refused (`fix-base`, as G23)

#### .claude/hooks/test-gate-route.sh and test-audit-surface.sh — skeletons and audit hint
- [ ] G44 the `json` block after `Skeleton (accepted as written by` in review.md 3bis (a round-1 example), written to `docs/work/sk/route-review-1.json` (its own slug, with a `plan.md` holding `Base:`), is routed with exit 0
- [ ] G45 the same for plan.md step 6, written to `docs/work/sp/route-plan-1.json`
- [ ] A47 a bare list in `audit-1.json` is refused with text containing `wrap the list as {"findings": [...]}`
- [ ] A48 the `json` block after `Skeleton (accepted as written by` in ship.md 1bis is accepted by `follow-ups`

#### .claude/hooks/test-workflow-contracts.sh — prompt pins (PK61+)
- [ ] PK61 arbiter.md's frozen-case block states the id is the case id in capitals and names `test_b204_… → B204`
- [ ] PK62 arbiter.md step 3 names the Python freeze accepting import lines at the head with an unfreeze verdict and says `the Python freeze takes the imports in their own Edit`; `in one Edit with it` sits in a TypeScript-only sentence; every AMC21 needle is still present
- [ ] PK63 test-writer.md's import sentence names `an unfreeze verdict` for both freezes
- [ ] PK64 ship.md step 4 names `the bare \`# \` prefix` and still holds `remove the applied \`.tdd-unfrozen\` entries in one Edit`
- [ ] PK65 plan-critic.md's status output line names `not-fixed` and says a fixed finding is left out of the route; T1 still passes
- [ ] PK66 orchestrate.md Phase 5 states that the route writes `fix-base` on `fix-batch`; T4's `kit-gate-route.py snapshot` needle still passes
- [ ] PK67 reviewer.md says the route file carries `class` on every finding, Minor included
- [ ] PK68 the prose around each route skeleton names the allowed values: `mode` (`review` / `plan`) in both; review.md `status` `new`/`not-fixed` and every `class`; plan.md `kind` (`demonstrated`, `interpretation`, `vigilance`) and `p1_class` (`a`-`d` or `null`, `null` for a vigilance finding)
- [ ] PK69 docs/Claude_Workflows.md's list of stash asks names the tracked-changes stash; PK50 (`import a frozen test case needs`) still passes after the test-writer.md edit

## Vigilance (carried from research)
- **Stash:**
  - a stash with a modified kit file stays a kit deny (SG13, G19.019 unchanged);
  - "could not check" asks (SG14);
  - option parsing never mistakes `-m x`'s value for a subcommand;
  - `git -C` and chains are covered.
- **Fix-base:**
  - the round-R scope is computed from the fix-base present before the route's write (G35);
  - a base the route wrote for round R is replaced at round R+1's fix batch (the residual case of a `snapshot`-written base is the known limit below);
  - `read_fix_base` and `diff … fix` stay byte-compatible: `fix-base` holds only the tree sha;
  - G29 (no git option injection) stays green.
- **Ids:**
  - the ledger, protect-files and `--clear` normalise the same way;
  - `test_…` rewrite names are never uppercased;
  - `ROW_RE` (plan rows) is unchanged.
- **SubagentStop:**
  - the message goes out only as a top-level `systemMessage` on a malformed block;
  - an arbiter with no block stays silent;
  - IN63 settings wiring is unchanged.
- **Python allowance:**
  - only auto plus an unfreeze verdict;
  - existing head lines unchanged and in order;
  - no rebinding, by identifier token and alias;
  - in rows mode it bypasses `rows_refusal` only for a pure head addition;
  - a Write is never covered;
  - no new assertion-less body insertion slips through.
- **Prompts:**
  - every AMC21, T1, T2, T4, T5, T13, T14, PK49-PK49.5 and ship.md :877 needle stays green;
  - each skeleton really is accepted by its script (G44, G45, A48), and the review skeleton's dimension stays one of `DIMENSIONS`;
  - reviewer.md and the skeleton agree on `class`.
- **Comment-out:**
  - the new deny never catches the bare `# <exact line>` that `--clear` writes (UW2, AM71);
  - nor a plain header comment or `#<line>` (UW4).
- **Fix-base residual (known limit):** if orchestrate's `snapshot` ran in round 1 but was skipped before a round-2 batch, the route keeps the round-1 base (a fix-base with no `.round`). The `snapshot` step stays mandatory in orchestrate.md, and the route covers only the case where it was forgotten entirely.
- **Plan-critic pass 1 Minors carried as review checks:**
  - F3: the skeleton prose lists the allowed values (PK68);
  - F4: an untracked-only stash passes, per the spec (SG11, SG12); follow-up recorded;
  - F5: freeze-side id readers are normalised (AM73, AM74);
  - Q4: the comment-out deny is scoped to annotated comment-outs (UW4);
  - Q5: subcommand per git/`kit_stash`, `-qu`/`--incl` (SG12, SG16);
  - Q6: PK50 and `docs/Claude_Workflows.md:168` (PK69);
  - Q7: the skeleton and fix-base cases use their own slug dirs.

## Acceptance criteria (carried from the entry artifact)
- [ ] In a fixture repo with a modified tracked file, `git stash`, `git stash -q`, `git stash push -m x` and `ruff check . && git stash -q` are asked (denied with the blocked-stop reason in auto mode); with no tracked change, and for `git stash list` / `git stash show`, the guard passes.
- [ ] `kit-gate-route.py route` on a review route file whose result is `fix-batch` creates `docs/work/<slug>/fix-base` when absent and reports it; a second call does not overwrite it; `diff … fix` then works without a manual `snapshot`.
- [ ] An arbiter verdict block with `case: b204` is ledgered as `B204`; the `.tdd-unfrozen` line `<path>  # b204: <reason>` backed by it is accepted; a block missing `sha256` produces a visible message naming the field, and records nothing.
- [ ] In a frozen Python test file backed by an unfreeze verdict, an Edit adding `from datetime import UTC` to the import head passes; the same addition without a verdict, an edit changing an existing import line, and an added import of a name already bound in the file are refused; this holds when the file is in rows mode.
- [ ] `review.md`, `plan.md`, `ship.md` hold a JSON skeleton that `kit-gate-route.py route` / `kit-audit-surface.py follow-ups` accepts as written (a contract test feeds each skeleton to its script); `plan-critic.md` names `not-fixed`; the three named error cases print the fix.
- [ ] `ship.md` defines comment-out as the bare `# ` prefix; an annotated `#` line in `.tdd-unfrozen` is denied with a text that names the comment-out format.
- [ ] Every existing hook fixture, contract and suite stays green (`test-hooks.sh`, `test-workflow-contracts.sh`, `test-gate-route.sh`, `test-audit-surface.sh`, the fastapi addon fixtures, `kit-doctor.py`).

## Open questions (proposed answers, decided at the test-plan gate)
1. **Fix-base lifecycle.** Answer: the sibling `fix-base.round` (`<round> <route-file sha256>`) decides. The route writes when `fix-base` is absent, when `.round` holds another round, or on round 1 when the recorded digest differs from this route file's. It keeps a base that has no `.round` (written by `snapshot`), and a same round >= 2. `snapshot` deletes `.round`; `read_fix_base` is unchanged. Decides G32-G39, G43 and G46-G48.
2. **Untracked-only stash.** Answer (corrected by the arbiter): it passes, per the spec's literal "a stash with no tracked change pass as today". The untracked-only case is recorded as a follow-up. Decides SG11, SG12 and SG15.
3. **Python name check.** Answer: the identifier tokens of the current file, as in TS, aliases included. Decides PI5 and PI7.
4. **Python allowance outside auto.** Answer: auto plus an unfreeze verdict only. In moi, a listed file is already a whole-file exemption. Decides PI3 and PI14.
5. **Where the skeleton tests live.** Answer: in the two script suites, which read the prompt files (G44, G45, A48).
6. **Lowercase ids in the TS freeze.** Answer: in scope after plan-critic F5, but limited to the `.tdd-unfrozen` id reader (`tdd-freeze-tests.sh:~200-205`, AM74). The TS case-title regex (`:401`) stays uppercase.
7. **Plan-critic F6: does a round-1 rerun of the same route file overwrite?** Answer: no. `fix-base.round` records the route file's digest, so the same file rerun is kept (G49) while a new review's file is written (G47).

## Plan critic
- pass 1: completeness 78, quality 60 (Q1 Critical, Q2, Q3, F1, F2 Major; rewrite)
- pass 2: completeness 90, quality 87; pass-1 blockers fixed; minors F7, F8, Q8-Q10 fixed in place
- surviving blockers: none (F6, a Major interpretation, goes to the arbiter at the test-plan gate)

### Plan critic, open
- **F6:** does a round-1 rerun of the same route file overwrite fix-base? The entry says a second call does not overwrite.
  - Proposed answer, written into the Route contract, G47, G49 and Open question 7: `fix-base.round` records `<round> <route-file sha256>`. The same file rerun is kept, and a new review's round-1 file is written.

## Gate
- 2026-11-26 arbiter go (auto, round 2 of 2; round 1 asked for 10 corrections, all applied)
- Contract: as written (Contract gate, 2026-11-26)
- OQ1 fix-base lifecycle → `fix-base.round` holds `<round> <route-file sha256>`.
  - Written when the base is absent, when `.round` holds another round, or on round 1 with another digest.
  - Kept when there is no `.round`, or on the same round >= 2.
  - `snapshot` deletes `.round`.
- OQ2 untracked-only stash → passes (spec literal), follow-up
- OQ3 Python name check → identifier tokens of the file, aliases included
- OQ4 Python allowance → auto + unfreeze verdict only
- OQ5 skeleton tests → in test-gate-route.sh and test-audit-surface.sh
- OQ6 TS lowercase ids → only the `.tdd-unfrozen` id reader; the title regex stays uppercase
- OQ7 / plan-critic F6 → a rerun of the same round-1 route file is kept (G49); a new review's file is written (G47)
- Frozen cases to amend: none
- EXECUTE deviations (2026-11-26, recorded for the review):
  - **Lot A, leg 1:** the stash code was written before the SG cases. Red was then observed by running the new cases against a `git archive HEAD` copy of the hooks; SG1-SG7 and SG14-SG17 went red there.
  - **Lot A, AM73/AM74:** the record holds a row for B1/U1 only, because with an empty rows list moi exempts the whole file. There is still no row for the edited B2/U2.
  - **Lot A, helper:** it uses its own `day_v`, since `am_v` is redefined globally by step-4 cases.
  - **Lot A, `insertion_refusal`:** the existing comments in the extracted block were condensed into its docstring.
  - **Lot B:** only G32 and A47 were seen red in a suite run, because the suites stop at the first failure. PK61-PK69 were red by construction (needles absent at HEAD, checked by `git grep`).
  - **Lot B, labels:** the PK cases are labelled `PK61 [...]`, because an unrelated PK61 already exists.
