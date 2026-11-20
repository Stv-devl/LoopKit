# Plan critic, targeted pass (after BLOCKED + user's "fix + targeted pass") — docs/work/loop-to-pr/plan.md
Token profile: critical
Scores: completeness 91 (was 82), quality 80 (was 78). Saved by the main thread from the critic's report.
F1-F6 fixed (checked against the real files: ship.md:287, github.md:149/:154/:192-196, codex.md:37, next-feature-on-clear.py:71-77, test-workflow-contracts.sh:222-223, product.md:294-296, install.sh:380).

```yaml
quality:
  score: 80
  findings:
    - id: Q1
      severity: Major
      p1_class: c
      kind: interpretation
      status: new
      claim: "The fix round's `git switch <base>` after 4bis-PR drops what the pass committed from the main tree (board IN LOOP, story InProgress, docs/work/<slug>/), so /clear proposes the pass again."
      evidence: "docs/work/loop-to-pr/plan.md:216-218, .claude/commands/loop/orchestrate.md:131-133, .claude/agents/github.md:132-134, .gitignore:113-120"
      resolution: "Main thread: the switch is withdrawn (the sentence that caused it); V7 answered by an announced stack in the closing check."
    - {id: Q2, severity: Minor, kind: demonstrated, status: new, claim: "`git switch <base>` is not a strict form and asks once per pass.", resolution: "moot, switch withdrawn"}
completeness:
  score: 91
  missing:
    - {id: Q3, severity: Minor, kind: demonstrated, status: new, claim: "The `'` refusal in the Hash producer is untested and absent from the Contracts row.", resolution: "Contracts row + LP50 extended"}
```
