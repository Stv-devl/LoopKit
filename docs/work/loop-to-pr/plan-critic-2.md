# Plan critic, pass 2 (rerun after rewrite 1) — docs/work/loop-to-pr/plan.md
Token profile: critical
Scores: completeness 66 (was 74), quality 74 (was 48). Saved by the main thread from the critic's report.
Pass-1 C1, C2, C3, C4, Q1-Q6: all **fixed** (Q1 probed on git 2.43: `worktree add <wt> -b feat/s1 audit/x` → `Created from audit/x`; digests LP6/LP41 recomputed correct; Q5 fixed by the contract-amendment route, holds only if accepted — N5).

```yaml
completeness:
  score: 66
  missing:
    - id: N1
      severity: Major
      p1_class: a
      kind: demonstrated
      claim: AC1's "no chat confirmation" has no write or case outside 4bis; ship.md step 4 ("Anything remote (push, PR) waits for the user's explicit go-ahead") and section 2 ("the user's to confirm, once, in the merge presentation (step 4bis, which every pass reaches)") are not scheduled; PK26 reads only 4bis-PR.
      evidence: .claude/commands/loop/ship.md:129-133, .claude/commands/loop/ship.md:152-155, docs/work/loop-to-pr/plan.md:184-196, docs/specs/loop-to-pr.md:64
      failure_scenario: Main thread follows step 4 and asks "Je pousse et j'ouvre la PR ?"; every PK passes.
      closure: "Closure: step 8 schedules the rewrite of ship.md step 4 (no go-ahead for the pass's push/PR when the hook allows them) and section 2 (amended cases go into the PR body; the merge presentation applies to 4bis-local only), and a PK case asserts ship.md outside 4bis-local no longer contains 'waits for the user's explicit go-ahead' or 'in the merge presentation (step 4bis, which every pass reaches)'; it passes."
      status: new
    - id: N2
      severity: Major
      p1_class: a
      kind: demonstrated
      claim: AC2's close-on-MERGED has no executor; no command runs loop-pr-state.sh at session start; ship.md step 5 (story Done, board SHIPPED right after 4bis) not rescheduled.
      evidence: docs/work/loop-to-pr/plan.md:190-193, .claude/commands/loop/ship.md:198-206, docs/specs/loop-to-pr.md:19, docs/specs/loop-to-pr.md:65
      failure_scenario: Board reads SHIPPED for a PR later closed unmerged; a merged single-track pass is never cleaned up.
      closure: "Closure: the plan names the command and phase that runs `loop-pr-state.sh --chain` at session start (e.g. orchestrate Phase 0 or ship's opening step) and schedules its write; ship.md step 5 is rescheduled so board/story move only on `closable`; a PK case asserts both; it passes."
      status: new
    - id: N3
      severity: Major
      p1_class: a
      kind: demonstrated
      claim: "/loop:small follows V5 too" has no mechanism: a small pass never reaches a Plan gate (no record), and ship.md's Small-ticket integration still does a local merge --ff-only, unscheduled.
      evidence: docs/specs/loop-to-pr.md:19, .claude/commands/loop/orchestrate.md:80-85, .claude/commands/loop/small.md:5-9, .claude/commands/loop/ship.md:245-255
      failure_scenario: A small ticket with a remote and the server rule ships by local ff merge, or push/PR ask every time; AC1 fails for small, unnoticed.
      closure: "Closure: the plan states how a small pass obtains a record (which go, in which tree, branch feat/small-<name>) and schedules ship.md's Small-ticket integration rewrite to the PR path when a remote exists, with an LP case and a PK needle; or an explicit OUT line for small that the user's go accepts."
      status: new
    - id: N4
      severity: Major
      p1_class: b
      kind: demonstrated
      claim: github.md prescribes `gh pr create --title "<short>" --body-file …` (no --repo/--base/--head) and no `git push -u origin <B>` form; never matches the hook's exact grammar; no case.
      evidence: .claude/agents/github.md:84, .claude/agents/github.md:153, docs/work/loop-to-pr/plan.md:113-116, docs/work/loop-to-pr/plan.md:407-408
      failure_scenario: The agent runs its documented form; record_allow never matches; V5 silently does nothing; every case passes.
      closure: "Closure: step 8 rewrites github.md's push and PR command lines to the hook's exact forms, and a PK case asserts both literal forms in github.md and ship.md 4bis-PR; it passes."
      status: new
    - id: N5
      severity: Major
      p1_class: a
      kind: interpretation
      claim: The rows-print-title amendment contradicts AC5 ("shown as hashed rows") and the V10 row grammar; no spec write scheduled; plan.md routes a contract amendment through the contract question, not the test-plan go.
      evidence: docs/work/loop-to-pr/plan.md:69-76, docs/specs/loop-to-pr.md:26, docs/specs/loop-to-pr.md:68, .claude/commands/loop/plan.md:129-139
      failure_scenario: User answers `as written` + `go`; spec still requires hashed rows; ship finds AC5 unmet.
      closure: "Closure: the amendment goes through the contract route (spec V10 row line and AC5 edited, `Contract: amended:` recorded, plan AC copy updated) and PK27 asserts the `<test path> | <case id> | <new case title>` grammar; or the user keeps hashed rows and Q5's producer closure applies."
      status: new
quality:
  score: 74
  findings:
    - id: N6
      severity: Major
      p1_class: b
      kind: demonstrated
      claim: The record hook hard-codes `feat/<slug>`; tracks.md prefixes branches by commit type (feat/, fix/, chore/); spec allows "feat/<slug> or the plan's naming".
      evidence: .claude/commands/loop/tracks.md:145-146, docs/work/loop-to-pr/plan.md:45-50, docs/specs/loop-to-pr.md:15
      failure_scenario: A `fix/inbox-1.2` track records branch feat/inbox-1.2 with base fix/inbox-1.2; base_ok false; ship pushes a new feat/ branch; the PR asks and fails.
      closure: "Closure: the record hook takes `branch` = HEAD when HEAD matches `(feat|fix|chore)/<slug>` (base from its reflog), with an LP case `git worktree add <wt> -b fix/s1 audit/x` → branch fix/s1, base audit/x; or step 8 removes the type prefix from tracks.md with a PK needle; it passes."
      status: new
    - {id: V1, severity: Minor, kind: vigilance, claim: "Single track: an abandoned pass's record stays valid while HEAD is its base and base_sha an ancestor; rows authorise .tdd-unfrozen adds until the next go.", status: new}
    - {id: V2, severity: Minor, kind: vigilance, claim: "In an EnterWorktree session the freeze hooks read ${CLAUDE_PROJECT_DIR}/.claude/.tdd-unfrozen (main tree) while the record is per tree; which .tdd-unfrozen rows mode reads is unstated.", evidence: ".claude/hooks/tdd-freeze-tests.sh:147, addons/fastapi/hooks/tdd_py_lib.py:168-169", status: new}
    - {id: V3, severity: Minor, kind: vigilance, claim: "ExitWorktree remove on a git-worktree-add tree unverified; `git worktree add` not allow-listed (one prompt).", status: new}
    - {id: V4, severity: Minor, kind: vigilance, claim: "rules/branches sees rulesets only: classic protection reads barrier false (safe ask) and a classic-protected feature base reads base_ok true.", status: new}
    - {id: V5, severity: Minor, kind: vigilance, claim: "Needles test-workflow-contracts.sh:350-355 and :450-451 may break under the deny-text rewrite; not in the Gate-amendments list.", status: new}
    - {id: V6, severity: Minor, kind: vigilance, claim: "Title hash = text between the quotes: escaped quotes/template literals hash source escapes; a Plan gate go next to a free-text contract amendment in the same call still writes the record.", status: new}
```
