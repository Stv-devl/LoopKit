# Plan critic, pass 3 (rerun after rewrite 2) — docs/work/loop-to-pr/plan.md
Token profile: critical
Scores: completeness 82 (was 66), quality 78 (was 74). Saved by the main thread from the critic's report.
N1, N2, N4, N5 fixed. N3 open (arbitrate), proposed answer sound in principle (gap F6). Digests verified.

```yaml
completeness:
  score: 82
  missing:
    - {id: N1, status: fixed, evidence: "plan.md:192-197, plan.md:450-452"}
    - {id: N2, status: fixed, evidence: "plan.md:213-220, plan.md:197-200, plan.md:453-455"}
    - {id: N4, status: fixed, evidence: "plan.md:221-226, plan.md:456-459"}
    - {id: N5, status: fixed, evidence: "plan.md:69-75, plan.md:181, plan.md:421-423"}
    - id: F1
      severity: Major
      p1_class: b
      kind: demonstrated
      status: new
      claim: "Two chat-confirmation instructions survive with no PK needle: ship.md Rules :287 ('Never push or open a PR without an explicit go-ahead') — rewrite scheduled but PK34 only greps 'waits for the user's explicit go-ahead' — and github.md Method step 4 :149 ('If push/PR was requested: draft the message, show it, ask, then run'), not in step 8's github.md rewrites."
      evidence: ".claude/commands/loop/ship.md:287, .claude/agents/github.md:149, docs/work/loop-to-pr/plan.md:212, docs/work/loop-to-pr/plan.md:221-227, docs/work/loop-to-pr/plan.md:450-452"
      failure_scenario: "The hook allows both commands, but the github agent follows Method step 4 ('show it, ask') and the main thread obeys Rules :287 and asks 'Je pousse et j'ouvre la PR ?'; AC1 fails while PK25, PK34-PK36 pass."
      closure: "Closure: step 8 names github.md:149 among its rewrites, and PK34 (or a new PK) asserts that ship.md outside 4bis-local and github.md no longer contain 'Never push or open a PR without an explicit go-ahead' or 'show it, ask, then run' for the pass's push/PR; it passes."
    - {id: F3, severity: Minor, p1_class: b, kind: demonstrated, status: new, claim: "Third allow (case-hash.sh): Files row says 2 allows, IN59 'both'; install.sh PROMPT_ALLOWS (:380) copy not asserted.", closure: "Closure: the Files row says 3 allows and IN59 names loop-record --clear, loop-pr-state.sh and case-hash.sh; it passes."}
    - {id: F4, severity: Minor, p1_class: b, kind: demonstrated, status: new, claim: "Escaped/template-literal title refusal in rows mode has no LP case.", closure: "Closure: an LP case where a row-backed Edit gives U2 a template-literal or escaped title is denied; it passes."}
quality:
  score: 78
  findings:
    - id: F2
      severity: Major
      p1_class: c
      kind: demonstrated
      status: new
      claim: "phase: awaiting-merge has no reader: next-feature-on-clear.py proposes any IN LOOP line with a main-tree handoff as 'Interrupted feature … run /loop:orchestrate <handoff>' ahead of every READY line; orchestrate Phase 0 step 2 branches only on the six template phases (handoff/codex.md:37, pinned by test-workflow-contracts.sh:222-223); product.md:294 defines IN LOOP as 'a session holds it right now'. None scheduled."
      evidence: ".claude/hooks/next-feature-on-clear.py:71-77, .claude/commands/loop/orchestrate.md:110-124, .claude/commands/handoff/codex.md:37, .claude/hooks/test-workflow-contracts.sh:222-223, .claude/commands/loop/product.md:294, docs/work/loop-to-pr/plan.md:197-200"
      failure_scenario: "After a single-track pass opens its PR, /clear proposes the awaiting-merge pass instead of the topmost READY; Phase 0 meets an unknown phase; the feature chain stalls until the PR merges."
      closure: "Closure: the plan schedules next-feature-on-clear.py to skip a phase: awaiting-merge handoff (case: IN LOOP line + awaiting-merge handoff → topmost READY), an orchestrate Phase 0 step 2 branch for awaiting-merge (closing-check result only, then stop) with a PK needle, and either the template phase list and needle :222-223 updated or the state kept outside phase:; the cases pass."
    - {id: F5, severity: Minor, p1_class: d, kind: demonstrated, status: new, claim: "Closing check writes SHIPPED/BLOCKED; product.md:296 writer table not updated.", closure: "Closure: step 8 edits product.md:296 to add the closing check as a SHIPPED writer."}
    - {id: F6, severity: Minor, kind: interpretation, status: new, claim: "N3's answer relies on the github agent, whose small-ticket section (github.md:192-196 rebase + merge --ff-only) is not in step 8.", closure: "Closure: step 8's github.md bullet rewrites :192-196 to push plus PR when a remote exists, with a PK37 needle on github.md."}
    - {id: V7, severity: Minor, kind: vigilance, status: new, claim: "Single track: after 4bis-PR nothing returns the main tree to its base; the next pass silently stacks on feat/<previous>; branch -d fails while checked out."}
    - {id: V8, severity: Minor, kind: vigilance, status: new, claim: "case-hash.sh \"<title>\" in double quotes expands $, backtick, \\ — single-quote the argument."}
    - {id: V9, severity: Minor, kind: vigilance, status: new, claim: "Gate amendments omit needles :348-349, :351-353, :401 touched by the 4bis split."}
    - {id: V10, severity: Minor, kind: vigilance, status: new, claim: "ship Output template (:269-272) still prints 'Board → SHIPPED' and 'merged | awaiting your validation' on 4bis-PR."}
    - {id: V11, severity: Minor, kind: vigilance, status: new, claim: "The handoff is gitignored and per machine (.gitignore:115): on another machine the pass never closes."}
```
