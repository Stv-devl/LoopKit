# Plan: Plan critic and review that converge   (entry: docs/specs/review-convergence.md · research: docs/work/review-convergence/research.md · design: n/a)
Token profile: standard
Base: a8efa59
Revision: 3. It answers critic pass 2 (87/88). One Major (verifier-confirmed): the Vigilance
append and the hook-covered fix applied only on `rewrite`. Both now run unconditionally, before
any `next` branch; T2 pins the order. Also folded in from the pass-2 Minors:
- P2 requires the hook to be registered in `settings.json` (G17);
- a missing `Base:` on a round-2 review exits 2 (G24);
- G22 writes `follow-ups.md` itself before diffing.

Revision 2 answered critic pass 1 (80/76). Three Majors survived the verifier:
- F1 `write-closure` handling;
- F2 K2 for the plan half;
- F3 the small-lane range.
F4 was refuted. The cheap Minors are folded in too (open questions block, refuted `demonstrated`
drops, `Growth:` printed, fixture order, gate artifacts excluded from the diffs, P2 limited to
hooked paths, follow-ups reset per case, refactor before the gate run).

## Skips
- DB: SKIP. Kit tooling, no schema.
- Backend: SKIP. No service layer.
- INTERFACE: SKIP. No user surface.
- Front TS layers: SKIP.
  - The two test-first layers are kit suites: `test-gate-route.sh` against
    `kit-gate-route.py`, and the wording cases in `test-workflow-contracts.sh`.
  - The TDD hooks match only `src/` and `shared/`, so the RED here is observed by running the
    suite, not by a marker (`05-testing.md`: "Foreign toolchains use their own cycle").

## Write chain (sequential)
1. **L1 RED.** One `test-writer` writes `.claude/hooks/test-gate-route.sh` (cases G1-G25
   below), runs it, and returns the failure: `kit-gate-route.py` is absent.
2. **L1 GREEN.** The main thread writes `.claude/hooks/kit-gate-route.py` until G1-G25 pass.
   The suite does not move.
3. **L2 RED.** The same `test-writer` (SendMessage) appends cases T1-T11 to
   `.claude/hooks/test-workflow-contracts.sh`, runs it, and returns the first failure.
   - Each T case is its own `grep`/`section` block, placed before the final `echo`.
4. **L2 GREEN.** The main thread edits the prose, in this order, so the suite moves forward
   one file at a time:
   - `plan-critic.md`;
   - `plan.md` (steps 6-7 and the template);
   - `reviewer.md`, `verifier.md`, `implementer.md`;
   - `review.md`, `orchestrate.md` (Phase 5 and the resume line only), `ship.md`;
   - `docs/Claude_Workflows.md`.
   - Existing pins are kept verbatim (see `## Vigilance`).
5. **Registration** (test-after, asserted by the existing suites):
   - `.claude/settings.json` allows;
   - `install.sh` `PROMPT_ALLOWS`;
   - the count pins 23 → 26 in `test-install.sh:460` and `test-workflow-contracts.sh:721-726`;
   - the `k2_suite` list `test-workflow-contracts.sh:797`;
   - the `kit-ci.yml` step;
   - `kit-doctor.py` `NON_HOOKS`.
6. **Refactor**: `kit-gate-route.py` under a green `test-gate-route.sh`, no test edited.
7. **Full gate run, last, on the final state**:
   - the suites `test-gate-route.sh`, `test-workflow-contracts.sh`, `test-hooks.sh`,
     `test-install.sh`, `test-kit-doctor.sh`, `test-small-lane.sh`, `test-attempts.sh` and
     `test-rules-floor.sh`;
   - `python3 .claude/hooks/kit-doctor.py`;
   - `ruff check --select E4,E7,E9,F .claude/hooks` and `shellcheck -S warning` on the new
     `.sh`, when those tools are installed (if not, say so);
   - `git diff a8efa59 -- .claude/scripts/` empty, and orchestrate.md lines 73-104 identical
     to `git show a8efa59:.claude/commands/loop/orchestrate.md` lines 73-104.

## Parallel lots (inside this track, same tree)
None. The run is fully sequential: L2 GREEN depends on the CLI names L1 fixes, and
registration touches files that L2 also pins.

## Track isolation
- Worktree: `.claude/worktrees/review-convergence` on `feat/review-convergence`, because
  project-config is in flight in the main tree (user choice, 2026-11-15).
- Shared foundations touched: `install.sh`, `.claude/settings.json`, `kit-ci.yml`, and the
  suite registration lists. project-config also edits `install.sh` and `test-hooks.sh`, so
  expect a manual merge on `install.sh` at integration. Rebase on whichever lands second.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/kit-gate-route.py` | Create | R1: `snapshot`, `diff`, `route` (plan and review), follow-ups writer |
| `.claude/hooks/test-gate-route.sh` | Create | L1 suite, G1-G25 |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | L2 cases T1-T11; pins 23 → 26; `k2_suite` += `test-gate-route` |
| `.claude/agents/plan-critic.md` | Edit | P1 classes, `demonstrated`/`interpretation`, `vigilance` kind, `Closure:`, rerun `fixed \| not fixed` (P3) |
| `.claude/commands/loop/plan.md` | Edit | step 6 (P1-P3, route call, the `next` handling below, refuted `demonstrated` drops, K2 narrow-first), step 7 (`Plan critic, open`, P4), template `Base:` line |
| `.claude/agents/reviewer.md` | Edit | finding fields (`class`, scenario, `regression`, `Closure:`), re-review mode (C1, K1) **only when handed a fix diff**, `fix-introduced` |
| `.claude/agents/verifier.md` | Edit | input: fix-batch base and fix diff for a `regression` claim (open question 3) |
| `.claude/agents/implementer.md` | Edit | K2 shrink-first, the `Growth:` line in the report |
| `.claude/commands/loop/review.md` | Edit | top attempt sentence (:10-11) aligned to the route; stage 3 route call, `follow-ups.md` (C2) |
| `.claude/commands/loop/orchestrate.md` | Edit | Phase 5 only (snapshot before the batch, re-review inputs, route, the `next` handling below, print the batch's `Growth:`) + the resume line :121-122 (step 2, outside the small lane) |
| `.claude/commands/loop/ship.md` | Edit | merge step 2 and output: follow-ups count + path |
| `docs/Claude_Workflows.md` | Edit | D1, in French |
| `.claude/settings.json` | Edit | allows: `python3 .claude/hooks/kit-gate-route.py *`, `bash .claude/hooks/test-gate-route.sh`, `… *` |
| `install.sh` | Edit | `PROMPT_ALLOWS` += the same 3 |
| `.claude/hooks/test-install.sh` | Edit | count pin 23 → 26, `hp_suite` list += `gate-route` |
| `.github/workflows/kit-ci.yml` | Edit | step `run: .claude/hooks/test-gate-route.sh` |
| `.claude/hooks/kit-doctor.py` | Edit | `NON_HOOKS` += both new files |

Not touched:
- the small lane: orchestrate.md:73-104 (step 1; step 2 starts at :105) and `small-*.sh`.
  The small review never runs review.md stage 3 or Phase 5 (orchestrate.md:82), so the route
  is never called from it;
- `.claude/rules/*`;
- `enforce-git-workflow.sh`: the capture runs git from Python, so no new allow rule is
  needed;
- `kit-attempts.py`;
- the reviewer and verifier counts.

## Contracts

### `kit-gate-route.py` CLI
Shape:
- `#!/usr/bin/env python3`, stamp `# cwk-guard-api: 1`, argparse, pathlib, typed.
- Every path argument must match `docs/work/<slug>/<file>`, relative to the cwd (same rule as
  `kit-attempts.py:93-99`); otherwise exit 2.
- Writes are atomic (temp file + replace). Never calls `kit-attempts.py` and never writes the
  board.

Subcommands:
- **`snapshot docs/work/<slug>/plan.md`** records the fix-batch base.
  - It builds a tree of the working tree:
    - a temporary `GIT_INDEX_FILE` seeded by `git read-tree HEAD`;
    - then `git add -A` (untracked files included, ignored ones excluded);
    - then `git write-tree`.
  - It writes the tree sha plus `\n` to `docs/work/<slug>/fix-base`, prints the sha, and
    exits 0.
  - The real index is never touched.
- **`diff docs/work/<slug>/plan.md fix|feature`** prints a unified patch to stdout, `-U3`, new
  files included.
  - `fix`: the tree in `fix-base` → a fresh snapshot tree of the working tree.
  - `feature`: the plan's `Base: <sha>` → a fresh snapshot tree.
  - A missing `fix-base` (for `fix`) or a missing `Base:` line (for `feature`) exits 2 and
    names the missing item.
  - Both diffs, and the `fix hunk` and `feature file` sets below, exclude the gate's own
    directory `docs/work/<slug>/` (`plan.md`, `fix-base`, `route-*.json`, `follow-ups.md`,
    `attempts.json`, `handoff.md`). The exclusion is a git pathspec
    `:(exclude)docs/work/<slug>`.
- **`route docs/work/<slug>/<name>.json`** reads one input file (below) and prints one result
  JSON to stdout. In review mode it appends follow-ups to `docs/work/<slug>/follow-ups.md`.
  - It reads `plan.md` (`Base:`) and `fix-base` from the same directory.
  - Exit 0 on a result. Exit 2 on an invalid input: a missing field, an unknown enum,
    `pass` > 3, or `round` ≥ 2 with no `fix-base`.

### Input files
Written by the main thread with Write, never from the shell:
`docs/work/<slug>/route-plan-<pass>.json` and `docs/work/<slug>/route-review-<round>.json`.

Plan input:
```json
{"mode": "plan", "pass": 2, "findings": [
  {"id": "F1", "severity": "Critical|Major|Minor", "claim": "…",
   "p1_class": "a|b|c|d|null", "kind": "demonstrated|interpretation|null",
   "status": "new|not-fixed", "in_rewritten_section": true,
   "closure": "…|null", "hook": "require-red|freeze|null", "leg": "claude|codex",
   "test_path": "src/x.utils.test.ts|null"}]}
```

Review input:
```json
{"mode": "review", "round": 2, "findings": [
  {"id": "F1", "severity": "Critical|Major|Minor", "dimension": "correctness|tests|db|security|ui",
   "class": "security|correctness|data-integrity|architecture|test-quality|maintainability|other",
   "path": "src/x.ts", "line": 12, "problem": "…", "scenario": "…|null",
   "regression": false, "status": "new|not-fixed", "closure": "…|null"}]}
```

### Plan routing (per finding, first rule that matches)
1. `severity` Minor, or `p1_class` null → `vigilance` (P1, G15).
2. `hook` set, `leg` = `claude`, and `test_path` under a hooked root → `hook-covered`: the main
   thread fixes the plan, no attempt (P2, G17).
   - The hook must be registered: `.claude/settings.json`, read relative to the cwd (the
     project root, like every other path of this script), must contain the named hook's
     command. `require-red` maps to `tdd-require-red.sh` and `freeze` maps to
     `tdd-freeze-tests.sh`, both for `src/` and `shared/`. Their `-py` twins
     (`tdd-require-red-py`, `tdd-freeze-tests-py`) cover `tests/services/`.
   - A missing or unreadable settings file means nothing is registered.
   - Any other `leg` or `test_path` (a kit suite under `.claude/`, for example) goes on
     through the rules below (G18).
3. `closure` null: Major → `vigilance` (recorded as Minor); Critical → `needs-closure` (K1,
   G14).
4. `pass` ≥ 2, `status` new, `in_rewritten_section` false, `kind` interpretation → `vigilance`
   (P3, G19).
5. `pass` 1 → `rewrite` (G21).
6. `kind` interpretation → `arbitrate` (P4, G12).
7. `kind` demonstrated: `pass` 2 → `rewrite`; `pass` 3 → `blocked` (G11, G16).

A finding with `p1_class` set and `kind` null is an invalid input (exit 2).

Result:
```json
{"mode": "plan", "pass": 2,
 "findings": [{"id": "F1", "route": "rewrite|arbitrate|blocked|vigilance|hook-covered|needs-closure"}],
 "attempt": {"action": "fail|pass|none", "reason": "F1: <claim>"},
 "next": "write-closure|blocked|rewrite|arbitrate|clear"}
```
`next` and `attempt` take the first rule that matches:
- any `needs-closure` → `write-closure`, attempt `none`;
- any `blocked` → `blocked`, `fail`;
- any `rewrite` → `rewrite`, `fail`;
- any `arbitrate` → `arbitrate`, `none` (the `pass` is recorded on the user's go, step 7);
- otherwise → `clear`, `pass`.

The reason is the first failing finding's `id: claim`. `reason` is present only for `fail`.

### Review routing (per finding, first rule that matches)
`fix hunk` = a line inside a new-side hunk of `diff fix` computed at `-U0`. A file created in
the fix diff counts as one whole hunk.

`feature file` = a path changed or created between `Base:` and the current snapshot.

A review input with `round` ≥ 2 on a plan with no `Base:` line exits 2 and names `Base:` (G24).
The main thread adds the line (the merge-base of the branch) and reruns. A plan written before
this change is caught here instead of silently routing everything out of scope.

1. `severity` Minor → `follow-up` `(minor)` (G5).
2. `closure` null: Major → `follow-up` `(minor)`; Critical → `needs-closure` (K1, G13).
3. `round` 1 → `blocking` (no scoping before a fix batch, G1).
4. `status` not-fixed → `blocking` (C1: a prior finding not closed, G2).
5. Inside a fix hunk → `blocking` + `fix_introduced` (G7).
6. `regression` true and `scenario` set → `blocking` + `fix_introduced`, anywhere (G8). With
   `regression` true and no scenario → `follow-up` `(out of scope)` (G9).
7. `class` ∈ {security, correctness, data-integrity}, `scenario` set, and the path is a feature
   file → `blocking` (G3).
8. Otherwise → `follow-up` `(out of scope)` (G4).

Result:
```json
{"mode": "review", "round": 2,
 "findings": [{"id": "F1", "route": "blocking|follow-up|needs-closure", "fix_introduced": false}],
 "attempt": {"action": "fail|pass|none", "reason": "F1: <problem>"},
 "next": "write-closure|fix-batch|clear", "follow_ups": "docs/work/<slug>/follow-ups.md", "follow_ups_added": 2}
```
`next` and `attempt` take the first rule that matches:
- any `needs-closure` → `write-closure`, `none`;
- any `blocking` → `fix-batch`, `fail`;
- otherwise → `clear`, `pass`.

Follow-up line, appended only when the exact line is not already in the file (a rerun adds no
duplicate): `- [<dimension>] <path>:<line> — <problem> (minor|out of scope)`.

### What the main thread does on `next`
This is written into plan.md step 6 for plan mode, and into orchestrate.md Phase 5 plus review.md
stage 3 for review mode.

**Before any branch, whatever `next` is** (plan mode), the main thread does three things:
- A `demonstrated` finding the verifier refuted is dropped before the route. It is never
  re-entered as `interpretation`.
- After the route, every `vigilance` finding is appended to the plan's `## Vigilance`, as a
  line the review must check. A line already present is not appended again (a `write-closure`
  rerun).
- Every `hook-covered` finding is fixed in place in the plan (the missing RED leg or
  `.tdd-unfrozen` line is added), with no failed attempt.

These run on `clear` and `arbitrate` as well as `rewrite`.

- `write-closure`:
  1. For each `needs-closure` finding, the main thread writes a `Closure:`. It is the
     observable state that closes the finding, a named case that passes as a rule.
  2. It records that `Closure:` in the finding text and in the input file (Edit).
  3. It reruns `route` on the same file, with the same `pass`/`round`.
  - No fix batch, rewrite or attempt happens before that rerun.
- `rewrite` (plan):
  - The main thread rewrites only for the `rewrite` findings.
  - A finding sitting in a section a previous pass rewrote is answered first by narrowing
    that rewrite (K2).
- `arbitrate`: the main thread goes to step 7 (`Plan critic, open`).
- `blocked`: the main thread applies the BLOCKED contract.
- `fix-batch` (review):
  1. `kit-gate-route.py snapshot` runs before the batch starts.
  2. Then come the batch, with `fix-introduced` findings first under K2, and the printed
     `Growth:` line.
  3. Then the re-review of the affected dimensions with `diff fix` and `diff feature`, round
     + 1.
- `clear`: the gate clears (`pass`).

### How the main thread calls `kit-attempts.py` from a result
- `attempt.action` fail →
  `python3 .claude/hooks/kit-attempts.py fail docs/work/<slug>/plan.md <plan-critic|review> "<attempt.reason>"`,
  plus `--board/--unit` from the main tree only (orchestrate.md:54-63).
- pass → `… pass docs/work/<slug>/plan.md <gate>`.
- none → no call.
- `arbitrate` → `pass plan-critic` only on the user's `go` at step 7.

### Agent output fields (prose contracts, asserted by T1-T7)
- **plan-critic**:
  - each Critical/Major item adds `p1_class: a|b|c|d`, `kind: demonstrated|interpretation`,
    `closure:` (the line in the prose reads `Closure:`);
  - a non-P1 remark is reported with `kind: vigilance`, never above Minor;
  - on a rerun it receives the surviving findings plus the rewritten sections, answers
    `fixed | not fixed` per finding against its `Closure:`, and admits a new finding only in a
    rewritten section or when `demonstrated`;
  - `completeness` always re-walks every acceptance criterion.
- **reviewer**:
  - each finding carries `severity`, `class`, `path:line`, the scenario (entry point, input,
    wrong result), `regression: yes|no`, and `Closure:`;
  - re-review mode applies **only when the launch hands it a fix diff** (Phase 5 after a
    batch). The small lane's second review hands none and keeps today's behaviour. In that
    mode it gets the confirmed findings with their `Closure:`, `diff fix` and `diff feature`,
    and answers `fixed | not fixed` per prior finding with `path:line` evidence;
  - admissibility is applied by `kit-gate-route.py`, which also tags `fix-introduced`.
- **verifier**: in a re-review it also gets the `fix-base` tree and `diff fix`. A `regression`
  claim is refuted unless the scenario holds after the fix and not at the base
  (`git show <tree>:<path>`) through a fix-diff hunk.
- **implementer**:
  - a `fix-introduced` finding is answered first by the smaller fix: revert or narrow the
    part of the previous batch that created it;
  - the report gains `Growth: none | <files beyond the findings and their tests> — <reason>`,
    which the main thread prints.

## Test plan (gate — validated by the user before EXECUTE)

### Open questions from research (proposed answers, written into the cases below)
1. **The review attempt threshold.** Every admissible Critical/Major routed `blocking` records
   a failed `review` attempt and starts a fix batch.
   - review.md:10-11 is reworded to defer to the route.
   - The PASS/CONCERNS/FAIL wording stays as it is (spec OUT). A Major-only verdict reads
     CONCERNS and still records `fail` when routed `blocking`.
   - Decides G1, G3, G10 and T8.
2. **Fix-diff base capture.** Option (a): `kit-gate-route.py snapshot`, a temp-index tree
   written from Python into `docs/work/<slug>/fix-base`.
   - It needs no new git allow rule and catches untracked files.
   - Decides G6, G22 and T4.
3. **Verifier input.** Yes. verifier.md gets one input line (the `fix-base` tree, `diff fix`)
   and one method line for a `regression` claim. Its role is unchanged. Decides T7.
4. **Allow lines.** Three:
   - `Bash(python3 .claude/hooks/kit-gate-route.py *)`;
   - `Bash(bash .claude/hooks/test-gate-route.sh)`;
   - `Bash(bash .claude/hooks/test-gate-route.sh *)`.
   - They go in `settings.json` and `PROMPT_ALLOWS`; the count goes 23 → 26.
   - Decides the test-after registration checks.
5. **Input format.** A JSON file written with Write at
   `docs/work/<slug>/route-<plan|review>-<n>.json`, never stdin. Decides G23.

### Test-first — L1: `.claude/hooks/test-gate-route.sh` against `kit-gate-route.py`

Suite shape:
- `set -euo pipefail`, `SCRATCH=$(mktemp -d)` + trap, `export CLAUDE_PROJECT_DIR=$SCRATCH`.
- A throwaway git repo in `$SCRATCH/repo` (fixed `user.name`/`email`). Every call is
  `python3 -I "$HOOKS_DIR/kit-gate-route.py" …` with the cwd at that repo.
- Hand-written inputs and literal expected routes, read with `jq -e`.
- Every case id is in a comment and in the failure message:
  `|| { echo "G<n> failed" >&2; exit 1; }`.
- The final line is `echo 'gate route fixtures: green.'`.

Fixture:
1. Commit 1 (the base): `a.ts` (30 numbered lines), `b.ts` (10), `e.ts` (10).
2. Commit 2: `docs/work/t/plan.md` holding `Base: <commit 1 sha>`. It sits in the excluded gate
   directory, so it shows in no diff.
3. Feature edits, uncommitted: `a.ts` lines 1-10 changed, `c.ts` created (untracked).
4. `snapshot`.
5. Fix edits: `a.ts` line 20 changed, `d.ts` created (50 lines, untracked).
6. Each review case that asserts on `follow-ups.md` first deletes
   `docs/work/t/follow-ups.md` (`rm -f` of that one file), so the cases do not depend on their
   order.

Review mode (round 2 unless said):

**Core behaviour**
- [ ] G1 Round 1: a test-quality Major with a closure at `e.ts:3` is `blocking`, because there
  is no scoping before a fix batch. Attempt `fail`, next `fix-batch`.
- [ ] G2 A prior finding with `status` not-fixed at `e.ts:3`, class architecture, is
  `blocking` and not `fix_introduced`.
- [ ] G3 (spec B1) A correctness Major with a scenario and a closure at `a.ts:5` (feature file,
  outside every fix hunk) is `blocking`, `fix_introduced` false. Attempt `fail` with reason
  `F1: <problem>`. `follow-ups.md` is not created.
- [ ] G4 (spec B2) An architecture Major with a closure at `a.ts:5` is `follow-up`. The file
  holds exactly `- [correctness] a.ts:5 — <problem> (out of scope)`. Attempt `pass`, next
  `clear`.
- [ ] G7 (spec B2) The same architecture Major at `a.ts:20` (inside the fix hunk) is
  `blocking`, `fix_introduced` true.
- [ ] G8 (spec B3) A correctness Major at `e.ts:3` (outside the feature diff) with
  `regression` true and a scenario is `blocking`, `fix_introduced` true.

**Business rules**
- [ ] G5 (spec B3) A Minor at `a.ts:20` (inside a fix hunk) is `follow-up`, with the line
  ending `(minor)`. A Minor at round 1 is `follow-up` too.
- [ ] G6 (spec B4) A test-quality Major at `d.ts:40` (new file in the fix diff, a line far from
  any edit) is `blocking`, `fix_introduced` true.
- [ ] G9 (spec B3) A Major with `regression` true and `scenario` null at `e.ts:3` is
  `follow-up` `(out of scope)`.
- [ ] G10 Only Minors and out-of-scope findings: attempt `pass`, next `clear`,
  `follow_ups_added` = their count.
- [ ] G13 (spec B8) A Major with `closure` null at `a.ts:20` is `follow-up` `(minor)`. A
  Critical with `closure` null is `needs-closure`, attempt `none`, next `write-closure`, even
  when a `blocking` finding is also present.

**Edge cases**
- [ ] G20 Running the same review input twice leaves each follow-up line exactly once in
  `follow-ups.md`.
- [ ] G22 It first runs one review `route` that writes a follow-up, so `follow-ups.md` and
  `fix-base` both exist. Then `diff … fix` shows `d.ts` as a new file and the `a.ts` line-20 hunk, and does not
  show the feature's lines 1-10. `diff … feature` shows `c.ts`, `d.ts` and both `a.ts`
  hunks. Neither diff names any path under `docs/work/t/`, even after `route` wrote
  `follow-ups.md` and `fix-base` there. `git diff --cached --quiet` still exits 0: the real
  index is untouched.
- [ ] G23 Refusals exit 2 and write nothing:
  - an input path outside `docs/work/<slug>/`;
  - a review `round` 2 input with no `fix-base` file;
  - an unknown `class`;
  - a plan finding with `p1_class` set and `kind` null.
- [ ] G24 Uses its own slug `docs/work/u/`, with a `plan.md` without `Base:` and its own
  `snapshot`, so the shared `docs/work/t/` stays intact. On that plan without `Base:`, `diff … feature` exits 2 and stderr names `Base:`. A
  review `route` with `round` 2 (with `fix-base` present) also exits 2 naming `Base:`, and
  writes no `follow-ups.md`.

Plan mode:

**Core behaviour**
- [ ] G11 (spec B5) Pass 2, a `demonstrated` (c) Major with a closure is `rewrite` and the same
  with (d) is `rewrite`: never `arbitrate`. Attempt `fail`, next `rewrite`.
- [ ] G12 (spec B6) Pass 2, only `interpretation` Majors with closures (in rewritten sections)
  are all `arbitrate`, attempt `none`, next `arbitrate`. A mix gives `rewrite` for the
  demonstrated, `arbitrate` for the others, attempt `fail`, next `rewrite`.
- [ ] G16 (spec B7) Pass 3, a `demonstrated` (a) Major is `blocked`, attempt `fail`, next
  `blocked`.

**Business rules**
- [ ] G14 (spec B8) A `demonstrated` (a) Major with `closure` null is `vigilance`. A Critical
  with none is `needs-closure`, next `write-closure`, attempt `none`.
- [ ] G15 (spec B7) A non-P1 item (`p1_class` null), Critical or Major, is `vigilance`. Alone
  it gives attempt `pass`, next `clear`.
- [ ] G17 (P2) A demonstrated (b) Major with a closure, `hook` require-red, `leg` claude and
  `test_path` `src/x.utils.test.ts` is `hook-covered` when `$SCRATCH/repo/.claude/settings.json`
  (cwd-relative) registers `tdd-require-red.sh`. Alone it gives attempt `pass`.
  With a settings file that does not register the hook, the same finding is `rewrite`.
- [ ] G18 (P2) The same with `leg` codex is `rewrite` at pass 1, attempt `fail`. The same with
  `leg` claude and `test_path` `.claude/hooks/test-x.sh` is also `rewrite`, because no hook
  guards that path.
- [ ] G19 (P3) Pass 2, a `new` `interpretation` Major outside every rewritten section is
  `vigilance`, attempt `pass`. A `new` `demonstrated` (b) Major outside them is `rewrite`.
- [ ] G21 Pass 1, an `interpretation` Major with a closure is `rewrite` (arbitration starts at
  pass 2).

**Edge cases**
- [ ] G25 `pass` 4 exits 2 with stderr `never a pass 4`.
- [x] G26 (review fix C-M3) a `path` of `./a.ts`, `/a.ts` or `a/../a.ts` exits 2 with `path` on
  stderr.
- [x] G27 (review fix C-M5) `scenario: none`/`None` is null: a correctness Major routes
  `follow-up`, not `blocking`.
- [x] G28 (review fix T-M1) correctness Major, no scenario, a.ts:5 → follow-up `(out of scope)`;
  with scenario, not a regression, e.ts:3 → follow-up.
- [x] G29 (review fix S-M1) `Base: --output=x` and a `fix-base` of `--output=y` exit 2 on diff and
  route, and create no `x`/`y`.

### Test-first — L2: `.claude/hooks/test-workflow-contracts.sh` (wording; each fails on today's files)
- [ ] T1 `plan-critic.md` contains `vigilance`, `(a)`, `(b)`, `(c)`, `(d)`, `demonstrated`,
  `interpretation`, `Closure:` and `fixed | not fixed`.
- [ ] T2 `plan.md`, from `6. **PLAN CRITIC GATE` to `7. **TEST PLAN GATE`, contains
  `rewritten sections`, `## Vigilance`, `no failed attempt`, `kit-gate-route.py`,
  `write-closure`, `narrowing that rewrite` and `never re-entered as \`interpretation\``, and
  still contains `Critical/Major claim to a \`verifier\``. It also contains
  `whatever \`next\` is`, and that phrase comes before the first `write-closure` in the
  section (an `awk` index comparison), so the Vigilance append and the hook-covered fix are
  unconditional.
- [ ] T3 `plan.md`, from `7. **TEST PLAN GATE` to `8. **Stop`, contains `Plan critic, open`
  and `kit-attempts.py pass`.
- [ ] T4 `orchestrate.md`, from `## Phase 5 —` to `## Phase 6 —`, contains `fix diff`,
  `follow-ups.md`, `kit-gate-route.py snapshot`, `kit-gate-route.py`, `write-closure` and
  `Growth:`.
- [ ] T5 `reviewer.md` contains `fixed | not fixed`, `regression`, `Closure:`,
  `fix-introduced` and `only when`. `review.md`, from `### Stage 3 — SYNTHESIS` to `## Output`,
  contains `follow-ups.md`, `kit-gate-route.py` and `write-closure`. `ship.md` contains
  `follow-ups.md`.
- [ ] T6 `implementer.md` contains `fix-introduced`, `smaller fix` and `Growth:`.
- [ ] T7 `verifier.md` contains `fix-base` and `regression`.
- [ ] T8 `review.md` lines 1-15 do not contain `Any surviving Critical/Major records one failed
  attempt`, and do contain `kit-gate-route.py`: one source for what records a failed attempt.
- [ ] T9 The `plan.md` template contains `Base: <sha>`.
- [ ] T10 orchestrate.md's resume line for `fixes-handed-to-codex` contains `fix diff`.
- [ ] T11 `docs/Claude_Workflows.md` contains `follow-ups.md`, `fix-introduced`, `Vigilance`
  and `interprétation`.
- [x] T12 (review fix C-M1) `plan.md` step 6 names `workflow-routing.yml`, `execute-red` and
  `always \`claude\``.
- [x] T13 (review fixes C-M2, SH2) review.md 3bis contains `status: not-fixed`, `main thread` and
  `a fresh \`/loop:review\` is round 1`.

### Test-after
Registration, asserted by the existing suites once updated:
- `test-workflow-contracts.sh:721-727` and `test-install.sh:455-460` expect the 3 new allows
  (count 26).
- `k2_suite` includes `test-gate-route`, which the kit-ci step satisfies.
- `kit-doctor` `check_hook_wiring` is clean with both files in `NON_HOOKS` (run `kit-doctor.py`
  and `test-kit-doctor.sh`).

This plan corrects no defect: it adds behaviour, so there is no Reproduction block.

## Vigilance (carried from research)
- One source for a failed `review` attempt: review.md:10-11 is rewritten to defer to the route
  result. The PASS/CONCERNS/FAIL verdict wording at :229-230 and reviewer.md:74 stays
  unchanged (spec OUT). Check that no text still says "any surviving Major fails".
- The verifier gets the `fix-base` and `diff fix` inputs. Check that a `regression` claim is
  refuted unless its causal path crosses a fix hunk.
- Fix-diff capture:
  - only through `kit-gate-route.py` (Python git calls, temp index);
  - no `git ls-files`, `git stash create`, `git add -N` or shell redirect in any command text;
  - the real index is untouched (G22).
- The suite sets `CLAUDE_PROJECT_DIR` to its scratch dir. `kit-gate-route.py` writes no
  kit-health line.
- The small lane stays byte-identical:
  - check `git diff a8efa59 -- .claude/scripts/` is empty;
  - check the orchestrate.md:73-104 bytes (step 1), by diffing that range against the base.
    The resume line at :121-122 is step 2 and is edited on purpose.
- reviewer.md re-review mode only when a fix diff is handed in, so the small lane's second
  review is unchanged.
- The `## Phase 5 —` and `## Phase 6 —` anchors stay exact. The verifier sentence of plan.md:79-80
  stays verbatim (pin :30). Step 7 keeps `proposed answer` and `asks step 7 again` (pins
  :304-309). Ship merge step 2 keeps `amended` and `test hunk` (:348-354).
- The count pin is 26 in both suites, and `settings.json` is a superset of `PROMPT_ALLOWS`.
- `follow-ups.md` line format is exactly `- [<dimension>] path:line — <problem> (minor | out of scope)`.
  `docs/specs/ship-audit-surface.md` will append to the same file.
- P2's `hook-covered` route applies only with `leg: claude`. `plan.md` step 6 tells the main
  thread how to fill `leg` from `.claude/workflow-routing.yml` (`execute-red` is always
  Claude).
- Merge with project-config: `install.sh` and `test-hooks.sh` conflict. Rebase before the
  merge and rerun the gates.

## Acceptance criteria (carried from the entry artifact)
- [ ] A plan whose only surviving Major is an implementation mechanism or layout value is not rewritten for it: the item lands in `## Vigilance` and records no failed attempt.
- [ ] A plan missing a RED leg for a test-first file is fixed by the main thread without a failed attempt; the same omission on a leg handed to Codex records a failed attempt.
- [ ] A `plan-critic` rerun receives its findings and the rewritten sections; an `interpretation` Major outside them records no failed attempt.
- [ ] After pass 2 with only `interpretation` Majors, step 7 shows them with proposed answers and one `go` clears `plan-critic` and starts EXECUTE.
- [ ] A `demonstrated` finding of any class (a)-(d), an uncovered criterion as well as an impossible order or a violated rule, still fails the critic up to `BLOCKED` and is never offered to `go`; no pass 4 is ever run.
- [ ] After a code fix batch, the re-review receives the confirmed findings with their closure conditions, the fix diff and the feature diff. A new security, correctness or data-integrity Major with a failure scenario anywhere in the feature diff fails it; so does a regression caused by the fix outside it. A Major of another kind, or without a scenario, on a line the fix did not touch lands in `follow-ups.md` without a failed attempt.
- [ ] Every Critical and Major carries `Closure:` and the rerun answers against it; a Major without one is a Minor in `follow-ups.md`; a Critical without one gets one from the main thread before the batch.
- [ ] A re-review finding in a fix-diff hunk or caused by the fix is tagged `fix-introduced`, and the next batch report shows the smaller fix tried first or declares the growth with its reason.
- [ ] A code-review verdict with only Minors starts no fix batch, records `pass`, and every Minor is in `follow-ups.md`; `/loop:ship` shows the count and path.
- [ ] Small lane unchanged.
- [ ] `test-workflow-contracts.sh`, `test-gate-route.sh`, `test-hooks.sh`, `kit-doctor`, `test-rules-floor.sh` pass.

## Plan critic
- completeness: 94
- quality: 91
- surviving blockers: none
- History:
  - pass 1: 80/76, 3 Majors confirmed and 1 refuted;
  - pass 2: 87/88, 1 Major confirmed;
  - pass 3: clean, and its 3 Minors are folded in.
  - `plan-critic` cleared 2026-11-15.

## Gate
- 2026-11-15 go
- Contract: as written
- OQ1, the review threshold → a `blocking` route records `fail` and starts a fix batch.
  review.md:10-11 defers to the route, and the verdict wording is unchanged.
- OQ2, the fix-diff base → `kit-gate-route.py snapshot`, a Python temp-index tree, written to
  `docs/work/<slug>/fix-base`.
- OQ3, the verifier input → one input line plus one method line for a `regression` claim; the
  role is unchanged.
- OQ4, the allows → 3 lines (`kit-gate-route.py *`, `test-gate-route.sh`, `… *`); count
  23 → 26.
- OQ5, the input format → a JSON file written with Write,
  `docs/work/<slug>/route-<plan|review>-<n>.json`.
- amended 2026-11-16, review round 1 fix batch: pure additions G26-G29 (test-gate-route.sh) and
  T12-T13 (test-workflow-contracts.sh); no existing case changed. To confirm at merge.
