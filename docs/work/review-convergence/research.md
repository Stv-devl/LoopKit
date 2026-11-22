# Research: Plan critic and review that converge   (entry: docs/specs/review-convergence.md)
Token profile: standard

Track: worktree `.claude/worktrees/review-convergence`, branch `feat/review-convergence`, base
`a8efa59`. Two explorers (plan side, review side). No external surface. Key claims re-checked
on the main thread: review.md:10-11 vs 229-230, reviewer.md:74, verifier.md:30-37,
orchestrate.md:285-294.

## Spec citation drift (actual lines)
- `plan.md` step 6 is 77-87 (matches). Step 7 runs 88-150, step 8 151-152. The `## Vigilance
  (carried from research)` header is **240** (the spec says 239).
- `settings.json`: tdd-freeze-tests 108-113, tdd-require-red 114-119 (the spec says 119-124).
- `review.md` stage 3 SYNTHESIS is **211-234** (the spec says 193-208, which is stage 2/2.5).
- `orchestrate.md`: Phase 5 is **285-294**, the review resume is **121-122**, the execute-green
  routing is 200-216 (the handoff command is at 209).
- `reviewer.md` severity is 55-61 (matches).

## Pattern to follow
- **Script + suite**: `.claude/hooks/kit-attempts.py` (152 lines) and `test-attempts.sh` (74
  lines).
  - The script: `#!/usr/bin/env python3`, stamp `# cwk-guard-api: 1` (:2),
    `from __future__ import annotations`, argparse (:113-121), pathlib, typed signatures,
    `SystemExit` exit codes.
  - Paths: the artifact must match `docs/work/<slug>/<file>` (:93-99), refusal exits 2.
  - JSON writes: indent 2, sorted keys, atomic via a temp file (:26-30, :47-52).
  - The suite: `set -euo pipefail`, `SCRATCH=$(mktemp -d)` + trap, fixtures copied in, bare
    assertions (`jq -e`, `grep -Fq`, `cmp -s`), `set +e … set -e` around expected non-zero exits,
    a `refused()` helper (:32-42), case ids in comments only, a final `echo '… green.'` (:74).
  - The project_config suites call `python3 -I` (test-workflow-contracts.sh:239, :853).
- **Wording cases**: `test-workflow-contracts.sh` (902 lines).
  - Path vars at :6-22. `section FILE START END` at :287 exits non-zero on a missing end anchor.
    Usage `gate_plan="$(section "$PLAN" '7. **TEST PLAN GATE' '8. **Stop')"` (:304), then
    `grep -Fq … <<<"$gate_plan"`.
  - Ids are in comments only (`# W5` :863). A failure exits 1, some cases add an
    `|| { echo …; exit 1; }` message.
- **Base-relative change set including untracked files**: `.claude/scripts/small-scope.sh:24-45`
  unions `git diff --name-only`, `git diff --cached --name-only` and
  `git ls-files --others --exclude-standard`.
- **Tree snapshot without a Bash git call**: `kit-pr-assets.py:208-217` uses a temporary
  `GIT_INDEX_FILE` with `read-tree`/`write-tree`/`commit-tree` from Python. The Bash hook never
  sees it.

## Wiring points
- **plan-critic.md** (67 lines):
  - completeness 19-26, quality 28-36; the row "Contracts are precise enough…" is at :31;
  - find/refute 38-46: `Critical | Major | Minor`, and Critical/Major = "not executable yet"
    :45-46;
  - output YAML 48-67: `completeness {score, missing[]}`, `quality {score, findings[]}`, items
    `severity, claim, evidence, failure_scenario`;
  - nothing on reruns, closure, vigilance, demonstrated or interpretation.
- **plan.md step 6** (77-87):
  - verifier at :79-80, "Hand every Critical/Major claim to a `verifier` using the same
    find-then-refute mechanics as `/loop:review`";
  - the rewrite reruns only the affected axis (:82-83); the record is "through
    `kit-attempts.py`" with no command line (:83-84); third failure → BLOCKED, never a fourth
    rewrite (:84-86); scores go under `## Plan critic` (:86-87).
  - The canonical `kit-attempts` forms are orchestrate.md:54-63; in a worktree, omit
    `--board/--unit` (:61-62).
- **plan.md step 7** (88-150): open questions 91-99, light-pass contract question + the only
  `AskUserQuestion` (:107-112), proposed answers 113-117, `## Gate` 118-124, three questions
  140-144.
- **Template**: `## Test plan` 197-238, `## Vigilance` 240-241 (filled by hand at step 4 from
  research `## Traps`, plan.md:68-71), `## Plan critic` 246-249, `## Gate` 251-256.
  - Vigilance consumers: review.md:107-112, implementer.md:30, orchestrate.md:287.
- **reviewer.md** (78 lines):
  - dimensions 39-53 (`correctness`, `tests`, `db`, `security`, `ui`); severity 55-61;
  - the finding format is just `path:line — problem [+ why it breaks]` (:68-72), and the
    scenario is asked only in prose (:27-29);
  - verdict PASS/FAIL, FAIL on ≥1 Critical or an uncovered criterion (:74);
  - diff: bare `git diff` / `git diff --staged` (:37), no base ref; no rerun mode.
- **verifier.md**: input = finding texts + entry path + repo + `git diff`/`--staged` (:30-37),
  no base ref and no fix diff. Default `refuted: true` when ambiguous (:27-28). Output
  `refuted, evidence, failure scenario, confidence, notes` (:57-66). Nearest existing text to
  a regression refutation: "reviewer misread the diff direction (pre-existing code)" (:48).
- **review.md**:
  - stage 0 20-80 (1bis Impeccable 33-44), stage 1 81-179, stage 2 REFUTE 181-194 (Minors
    skip, :191), stage 2.5 196-209;
  - stage 3 211-234: aggregate :213, kit-health log :215-226, criteria walk :227-228,
    verdict :229-230, propose fixes :233-234; output template 236-256;
  - it never calls kit-attempts itself; the key is declared at orchestrate.md:50.
- **orchestrate.md**:
  - Phase 5 285-294, ending "Then re-run only the affected dimensions." (:293-294);
  - review resume :121-122;
  - small lane review paragraph 88-95: unchanged, and pinned by test-workflow-contracts
    :393-397 (`one reviewer`, `one verifier`, `implementer`, no `AskUserQuestion`).
- **implementer.md** (59 lines): the fix batch at 16-25 (reproduction case first, a frozen file
  takes only a pure new case, "passes before the fix → stop"); "Stay inside the batch's files"
  :43; "No refactor beyond the batch" :50; report 54-59 (`Files`, `Proof`, `Blocked on`). No
  shrink-first, no growth declaration.
- **ship.md**: merge step 2 145-150 (pinned: `amended`, `test hunk`, and never
  `otherwise ask for them here` :348-354); output template 228-249 (`Board:` :240, `Next:`
  :241); no mention of follow-ups or Minors.
- **codex-handoff.sh**: `review-fixes` is only a routing role (:36-50); the prompt is generic
  (:99); guards at :78-97. The re-review after Codex comes only from the Phase 5 resume
  branch, orchestrate.md:121-122.
- **Docs**: `docs/Claude_Workflows.md` loop table 312-315, plan-critic/BLOCKED paragraph
  357-361, `review-fixes` 290-291.

## Reusable
- `kit-attempts.py` stays the only attempt writer. kit-gate-route.py returns routes and the
  main thread calls kit-attempts from them (spec R1). Do not re-implement counting.
- `section()` in test-workflow-contracts.sh for T2-T4.
- The small-scope.sh union idiom, and the kit-pr-assets.py temp-index snapshot, for the
  fix-diff base.
- `## Vigilance` already exists in the template and is already read by review (review.md:107-112).

## Blast radius
- Registering a new suite or script touches:
  - `.github/workflows/kit-ci.yml:61-63` style step (by hand);
  - `kit-doctor.py` `NON_HOOKS` :772-778: **both** new files, or `check_hook_wiring` reports
    "on disk, registered nowhere" (:843-852);
  - `.claude/settings.json` allows: `test-attempts.sh` at :56-57, `kit-attempts.py *` at :46.
    Without an allow line, every `kit-gate-route.py` call prompts;
  - `install.sh` `PROMPT_ALLOWS` :224-234 (count pinned **23** at test-install.sh:460 and
    test-workflow-contracts.sh:726, suite list :721, settings superset check :727);
  - optional: the `k2_suite` list at test-workflow-contracts.sh:797 (not exhaustive:
    test-pr-assets is absent).
- Shipping: `install.sh:666` `copy_tree` copies all of `.claude/`, and :768 sets chmod +x. No
  manifest to edit.
- Pinned text that the edits could break (test-workflow-contracts.sh):
  - plan-critic :25-28 (`model: inherit`, `completeness:`, `quality:`, `Never average`);
  - plan.md :29 (`PLAN CRITIC GATE`) and :30 (the exact verifier sentence of plan.md:79-80);
  - step 7 :304-309 (`amended:`, `proposed answer`, `## Gate`, `asks step 7 again`,
    `` `research.md` is read-only ``);
  - orchestrate: the `## Phase 4 —`…`## Phase 5 —` anchors :324, resume phases :218-219, the
    small block :366-431;
  - review.md :36-37, :46-57, :417, :894; ship.md :348-354, :831-832, :896-897;
  - implementer :267, :343;
  - commands/loop has exactly 13 files :63.
- Size: `test-rules-floor.sh` checks only CLAUDE.md + `.claude/rules/*` (516/520), and
  test-workflow-contracts :864-868 pins `RULES_TOTAL <= 516`. Rules are OUT of scope, so this
  is safe. Agents and commands have no line budget.
- Lint: kit-ci runs `ruff check --select E4,E7,E9,F` on `.claude/hooks` (:34-42) and
  `shellcheck -S warning` on hooks/*.sh and scripts/*.sh.
- Shared artifact: `docs/specs/ship-audit-surface.md:37,:86` also writes `follow-ups.md` (same
  line format, dimension `audit:<surface>`). It is queued after this spec, so this spec fixes
  the format.

## Live DB state
n/a (kit tooling).

## External surface
n/a. The spec cites `liza-mas/liza` as already read (2026-11-05). No fetch is needed.

## Traps (points of vigilance for the review)
- The review verdict is already split: review.md:10-11 counts a surviving Major as a failed
  attempt, while review.md:229-230 and reviewer.md:74 call Major-only `CONCERNS`/not FAIL. C1,
  C2 and B1-B3 must leave one source for "what records a failed `review` attempt".
- The verifier has no fix-batch base or fix diff in its input (verifier.md:30-37). A
  `regression` claim ("correct at base, fails after") cannot be refuted as written. The C1
  causal check needs an input line there. The verifier is OUT of scope only for its *role*, not
  its input.
- Fix-diff capture vs the shell guard and the allow list:
  - `git diff *` and `git rev-parse *` are allowed (settings.json:30, :32).
  - `git ls-files`, `git stash create`, `git write-tree` and `git -c …` have no allow line and
    would prompt.
  - `git add -N` is asked by the hook (`grammar_value_ok` rejects `-` values,
    enforce-git-workflow.sh:1628-1630).
  - `git stash create` misses untracked files.
  - A Python snapshot (temp index, as in kit-pr-assets.py:208-217) is invisible to the Bash
    hook. A shell redirect to save a diff is forbidden by CLAUDE.md.
- `kit-attempts.py` writes the count before validating the board (:141-145). Its health log
  goes to `$CLAUDE_PROJECT_DIR/.claude/.kit-health.jsonl`, falling back to the cwd (:33-44). The
  new suite must set `CLAUDE_PROJECT_DIR` to its scratch dir, and kit-gate-route must not
  double-log.
- The small lane must stay byte-identical in orchestrate.md:73-124 (pinned :393-412), and in
  small-plan.sh's Vigilance copy (small-plan.sh:149, test-small-lane.sh:147/202/249).
- P2's hook-guarantee holds only for legs Claude executes. Codex takes the non-test-first GREEN
  legs after repository/services (orchestrate.md:202-209). A test-first RED leg always stays
  on Claude, so a missing RED leg is normally hook-covered. The plan must say how the critic
  or the route knows which leg is routed.
- `## Phase 5 —` and `## Phase 6 —` anchors must stay exact: test-workflow-contracts' `section`
  fails hard on a missing end anchor.
- Adding a prompt allow changes the pinned count 23 in two suites and the :721 list.

## Open questions
1. **Review blocking threshold.** After this pass, does a surviving Major (admissible under C1)
   record a failed `review` attempt and start a fix batch, as review.md:10-11 says, with the
   verdict text at :229-230 and reviewer.md:74 aligned to it? Or does Major stay `CONCERNS`?
   The spec's B1-B3 assume Major → `blocking`.
2. **Fix-diff base capture (C1).** Which mechanism: (a) a `kit-gate-route.py snapshot`
   subcommand that writes a tree sha with a temp index from Python, stored in
   `docs/work/<slug>/`, with no new allow rule and untracked files included; (b) a WIP commit
   before each fix batch (`git add` + `git commit -m`, both already allowed); (c) a new allow for
   `git ls-files --others --exclude-standard` plus a recorded `git rev-parse HEAD`
   (untracked-at-base files are then indistinguishable)?
3. **Verifier input.** Is adding the fix-batch base and the fix diff to verifier.md's input
   section accepted as in scope (needed to refute a `regression` claim), given the spec puts
   "verifier's role" OUT?
4. **kit-gate-route.py allow line.** Add `Bash(python3 .claude/hooks/kit-gate-route.py *)` to
   settings.json, and the suite to `PROMPT_ALLOWS` (count 23 → 24 or 25), like kit-attempts? Or
   accept a prompt on each call?
5. **Input format for kit-gate-route.py.** Should the findings come as a JSON file written with
   Write under `docs/work/<slug>/` (for example `findings-<gate>-<n>.json`), or as JSON on
   stdin? Stdin from a heredoc is a shell write the guards may ask on.
