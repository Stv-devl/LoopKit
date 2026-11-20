# Plan critic, pass 1 — docs/work/loop-to-pr/plan.md
Token profile: critical
Scores: completeness 74, quality 48 (kept separate). Saved by the main thread from the critic's report (the critic is read-only).

## Checks asked
- `record_allow` placement sound: top of ASK pass (`enforce-git-workflow.sh:2053`), after every deny incl. attribution deny on `--body-file` (`:1980-1996`), before floor regexes (`:2061`, `:2077`) and `grammar_decide` (`:2227`). PDC has no push/gh clause, settings has no ask rule. Parse-failure fallback (`:2133`) runs after it; vigilance line overstates.
- Forging: Write/Edit/shell covered. Pre-filled `answers` is the real vector (PreToolUse deny is the only defence, fails open — Q7). Agent code via allowed gate commands can still write the record (same class as `.tdd-red`/`.tdd-unfrozen`, spec OUT — Q11). Record not excluded by install.sh/.gitignore (Q12).
- Per-case hash: title-hash matches the kit's "case line"; implementable with affix/anchor walkers; gaps Q2-Q4.
- Open-question answers: 1, 2, 3, 5, 6, 7 sound; 4 is Q1. Barrier lacks bypass-actor check and is read once (Q13).
- Expected values: literals and shims; LP29 should pin a literal digest (Q14).
- F4/F5/F8/F12/F13 mapped; F12 earlier-pass only by LP10+LP22 (C3); F8 local-ship clear only CLI (C4); F13 cannot fire (Q1).

```yaml
completeness:
  score: 74
  missing:
    - id: C1
      severity: Major
      p1_class: a
      kind: demonstrated
      claim: AC1's clause "no remote: local flow unchanged" is mapped to a write but to no case, and PK26 asserts the opposite of keeping it inside 4bis.
      evidence: docs/work/loop-to-pr/plan.md:145, docs/work/loop-to-pr/plan.md:320, .claude/commands/loop/ship.md:173-181, docs/specs/loop-to-pr.md:64
      failure_scenario: The writer keeps today's no-remote rebase plus merge go-ahead in 4bis and PK26 stays red, or deletes it and a remote-less project loses its integration step unnoticed.
      closure: "Closure: a PK case asserts ship.md keeps the no-remote local merge path (with its go-ahead) in a named subsection, and PK26 is scoped to the remote/PR branch of 4bis; both pass."
      status: new
    - id: C2
      severity: Major
      p1_class: a
      kind: demonstrated
      claim: AC2's "the PR body follows the loop-PR template" (Frozen cases, Open questions, Review, Gates, in that order after Screenshots) has no case.
      evidence: docs/work/loop-to-pr/plan.md:150-154, docs/work/loop-to-pr/plan.md:319, docs/specs/loop-to-pr.md:20, docs/specs/loop-to-pr.md:65
      failure_scenario: github.md gains the sections in another order or misses Frozen cases; every contract passes; amended cases never reach the PR.
      closure: "Closure: a PK case asserts github.md's template lists Frozen cases, Open questions, Review, Gates in that order after Screenshots, with --body-file; it passes."
      status: new
    - id: C3
      severity: Minor
      p1_class: b
      kind: demonstrated
      claim: F12's "an id from an earlier pass → ask" has no direct case; a stale record (abandoned pass) still authorises its rows until the next plan go.
      evidence: docs/specs/loop-to-pr.md:58, docs/work/loop-to-pr/plan.md:104-110
      failure_scenario: Pass s1 records a row and is abandoned; before the next go, a .tdd-unfrozen add of that line passes.
      closure: "Closure: an LP case with a record from another slug/branch than HEAD's pass adding a matching row line → ask."
      status: new
    - id: C4
      severity: Minor
      p1_class: b
      kind: demonstrated
      claim: F8's local-only-ship clear is tested only at the CLI; no contract checks ship.md calls `loop-record.py --clear`, and the call is not allow-listed.
      evidence: docs/work/loop-to-pr/plan.md:145, docs/work/loop-to-pr/plan.md:248, .claude/settings.json:18-77
      failure_scenario: ship.md omits --clear; stale rows stay live.
      closure: null
      status: new
    - id: C5
      severity: Minor
      p1_class: null
      kind: vigilance
      claim: No explicit case for PR-side no-barrier ask, pushurl/mirror/receivepack/pushoption fixtures, `gh pr close`, end-of-pass merge-order message, plan re-shown once on amendment.
      evidence: docs/work/loop-to-pr/plan.md:261-273
      failure_scenario: Regex or prompt drift unseen.
      closure: null
      status: new
quality:
  score: 48
  findings:
    - id: Q1
      severity: Critical
      p1_class: c
      kind: demonstrated
      claim: The worktree base rule needs an oldest-reflog "Created from <branch>"; every kit command that creates a pass branch omits the start point, so git logs "Created from HEAD" → no record for every worktree track, small pass and stacked pass.
      evidence: docs/work/loop-to-pr/plan.md:36-38, .claude/commands/loop/tracks.md:131, .claude/commands/loop/orchestrate.md:154, .claude/commands/loop/small.md:7 (probe - `git reflog show --format=%gs audit/slim` oldest = "branch: Created from HEAD")
      failure_scenario: A worktree track never gets a record; push and PR ask as today; F13 never fires; LP12 passes on a fixture the kit never produces.
      closure: "Closure: tracks.md/orchestrate.md/small.md create the branch with an explicit base start point (or the plan names another base source the record hook can read and an agent cannot write), and an LP case builds the branch exactly as tracks.md:131 does and gets base = that branch; it passes."
      status: new
    - id: Q2
      severity: Major
      p1_class: d
      kind: demonstrated
      claim: In rows mode step 5 denies any Write and any Edit with no case title in old_string, removing the byte-identical re-save and pure new-case insertion 05-testing.md allows on every frozen file.
      evidence: .claude/rules/05-testing.md:39, .claude/hooks/tdd-freeze-tests.sh:171-178, .claude/hooks/tdd-freeze-tests.sh:293-412, docs/work/loop-to-pr/plan.md:114-118
      failure_scenario: Appending U9 after amending U2 is denied; so is the documented re-save.
      closure: "Closure: step 5 runs the existing re-save and insertion checks before the per-case check, and two LP cases pass: identical Write on a rows path, pure insertion of U9 on a rows path."
      status: new
    - id: Q3
      severity: Major
      p1_class: b
      kind: demonstrated
      claim: Step 5 identifies touched cases only by titles present in old_string/new_string, so an edit can reach into a case with no row.
      evidence: docs/work/loop-to-pr/plan.md:115-118, .claude/hooks/tdd-freeze-tests.sh:196-219, addons/fastapi/hooks/tdd-freeze-tests-py.py:68
      failure_scenario: old_string from inside U1's body to U2's title; U1's assertion rewritten, only U2 (a row, hash ok) seen → pass.
      closure: "Closure: step 5 computes the enclosing case of the edited span in the current file (anchor_scope / enclosing_case_indent) and an LP case with old_string starting in U1's body and ending at U2's title → deny; it passes."
      status: new
    - id: Q4
      severity: Major
      p1_class: c
      kind: demonstrated
      claim: A path with plan rows cannot take a batch-approved EXECUTE correction of another case (no row for it).
      evidence: docs/work/loop-to-pr/plan.md:111-119, docs/work/loop-to-pr/plan.md:136-140, docs/specs/loop-to-pr.md:30
      failure_scenario: Row U2 recorded; batch approves U5 on the same file; U5's edit is denied; AC6 deadlocks.
      closure: "Closure: step 5 states how a .tdd-unfrozen id with no row on a rows path is honoured, and an LP case (row U2, batch line U5 on the same path, Edit of U5) passes."
      status: new
    - id: Q5
      severity: Major
      p1_class: c
      kind: demonstrated
      claim: The plan gate must print sha256(<new title>) per row but nothing named computes it without a prompt.
      evidence: docs/work/loop-to-pr/plan.md:131-133, docs/work/loop-to-pr/plan.md:62-64, .claude/settings.json:18-77
      failure_scenario: An extra ask at every plan gate with amended cases, or a made-up digest that later denies the real edit.
      closure: "Closure: the plan names one hash producer runnable without a prompt and not able to write the record, plan.md step 7 uses it, and a case asserts its output for a literal title equals a literal hex digest."
      status: new
    - id: Q6
      severity: Major
      p1_class: d
      kind: interpretation
      claim: The freeze hooks' deny texts (the specification per 05-testing.md:31) still prescribe one .tdd-unfrozen write per correction and "the user confirms it at the merge"; the plan never schedules their rewrite.
      evidence: .claude/rules/05-testing.md:31, .claude/hooks/tdd-freeze-tests.sh:414, .claude/hooks/tdd-freeze-tests.sh:417, addons/fastapi/hooks/tdd-freeze-tests-py.py:207, addons/fastapi/hooks/tdd-freeze-tests-py.py:315
      failure_scenario: The main thread follows the deny text and asks per correction; the promised merge confirmation no longer exists.
      closure: "Closure: step 5 lists the deny-text rewrite (queue, one batch stop, PR body) in both hooks, and a PK/LP needle asserts the texts name the batch and no longer say \"confirms it at the merge\"."
      status: new
    - {id: Q7, severity: Minor, kind: vigilance, claim: "PreToolUse pre-filled-answers deny is the only defence and fails open on exception.", status: new}
    - {id: Q8, severity: Minor, kind: vigilance, claim: "record_allow tree unspecified ($CLAUDE_PROJECT_DIR vs input cwd); degraded config should ask.", status: new}
    - {id: Q9, severity: Minor, kind: vigilance, claim: "No case runs prevent-destructive on the two exact forms.", status: new}
    - {id: Q10, severity: Minor, kind: vigilance, claim: "include(if) in all scopes disables V5 for most users; push.recurseSubmodules unchecked; G21.037 needs a deterministic hanging origin.", status: new}
    - {id: Q11, severity: Minor, kind: vigilance, claim: "Vigilance overstates: allowed agent code (pnpm test:run) can write the record; name it as a known limit.", status: new}
    - {id: Q12, severity: Minor, p1_class: d, kind: demonstrated, claim: "Record not in .gitignore, install.sh gitignore block, or install.sh copy prune list.", evidence: ".gitignore:63-65, install.sh:339-342, install.sh:661", status: new}
    - {id: Q13, severity: Minor, kind: vigilance, claim: "Barrier ignores bypass actors and is read once; --chain ignores mergedAt ordering.", status: new}
    - {id: Q14, severity: Minor, kind: vigilance, claim: "PK cases scheduled after prompt rewrites (never red); LP29 should pin a literal digest.", status: new}
    - {id: Q15, severity: Minor, kind: vigilance, claim: "Step 4 must handle an absent .tdd-unfrozen (first entry by Write).", status: new}
```
