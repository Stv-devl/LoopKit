# Spec: Plan critic and review that converge
Token profile: standard

## Objective
The `plan-critic` gate stops looping to `BLOCKED` on plans that are already good: only a contract gap blocks a plan, everything the code will settle is carried to review, and what still divides after two passes is arbitrated by the user at the test-plan gate they already hold. The code review keeps its shape, with three changes: the re-review after a fix batch still stops any real bug in the feature but no longer reopens architecture or test-quality remarks on lines the fix did not touch; every blocker, of a plan or of code, states what closes it; and a defect created by a fix is answered by shrinking that fix first.

## Evidence (ecocrew, 42 sessions, 71 features with a `plan.md`, transcript grep of 2026-11-05)

| Gate | ≥ 1 failed attempt | `BLOCKED` (3 failures) |
| --- | --- | --- |
| `plan-critic` | ~63 / 71 (~89 %) | **~20 / 71 (~28 %)**, and passes 4 to 6 seen past the ceiling |
| `review` | ~50 / 71 (~70 %) | 1 / 71 (~1 %), a real bug (DXF parse memory unbounded) |

Review rounds per feature: 1 → ~30 %, 2 → ~54 %, 3 → ~15 %, `BLOCKED` → ~1 %; mean ~1.9. The review converges; the plan does not.

Blocked plans scored high (92/83, 87/80, 86/70) and were stopped by one or two Majors of three kinds:
1. **An implementation detail a plan cannot settle without the code**: "edit keys mechanism unstated (capture phase, preventDefault…)", "portal needs the selected row mounted", "two capped shelves squeeze the tree below 120 px at 280×600", "text rotation sign under Y flip undefined". Each pass raises the next one. The quality row "Contracts are precise enough to write tests without reading implementation" (`plan-critic.md`) invites it without limit.
2. **What a hook already refuses at EXECUTE**: "no test-first RED leg" for a test-first file (`tdd-require-red.sh`), a frozen file changed without its `.tdd-unfrozen` line (`tdd-freeze-tests.sh`).
3. **A real contract gap**: an acceptance criterion with no write or case, an impossible order. The rarest, and the only kind worth a stop.

Code re-reviews (76 `reviewer` reports of a round 2 or 3, ~35 with a blocker; origin read by hand from the excerpts, approximate):

| Origin of the re-review blocker | ~Count | Examples |
| --- | --- | --- |
| Regression created by the fix | 10 | the item-7 fix breaks the CCTP selection (AC6), Escape no longer swallowed, a new `tabIndex` defeats the focus-lost checks, the argon2 threadpool fix opens a memory lever |
| Original defect not or partly fixed | 9 | DXF budget still bypassable (the one `BLOCKED`), non-finite values still stored, a fix that holds for 10 minutes, a reproduction case that does not bite |
| Original defect missed in round 1 | 9 | client cache not scoped by company (Critical), sandbox reaching UNIX sockets, user-scoped reset never firing, red suite, lazy import with no `catch` |

Nearly all carry a concrete failure scenario: they are real bugs, not noise. Two consequences: a re-review scoped to the fix diff would have shipped ~6 real Majors of the third row (C1 keeps the whole feature diff for bugs); the first two rows are what a closure condition (K1) and shrink-first (K2) address.

| | Today | After |
| --- | --- | --- |
| What blocks a plan | any surviving Critical/Major | only a contract gap (P1); a detail goes to `## Vigilance`, checked by review on real code |
| Hook-guaranteed omission in a plan | a failed attempt | fixed by the main thread, no attempt (P2) |
| `plan-critic` rerun after a rewrite | the affected axis re-judged on the whole plan | its findings + the rewritten sections; criteria coverage always re-walked (P3) |
| Majors still surviving after pass 2 | rewrite 3, then `BLOCKED` | an `interpretation` Major is arbitrated by the user at the test-plan gate, with a proposed answer each; a `demonstrated` one of any class (a)-(d) goes to pass 3 then `BLOCKED` (P4) |
| Code re-review after a fix batch | "re-run only the affected dimensions", unscoped | whole feature diff for bugs (security, correctness, data integrity with a failure scenario); other kinds only on fix-diff lines (C1) |
| What closes a blocker | the next pass re-judges | the `Closure:` written with the finding, checked `fixed | not fixed` (K1) |
| Defect created by a fix | fixed by adding code | tagged `fix-introduced`, answered by shrinking the fix first (K2) |
| Confirmed Minor in code review | listed, then lost | written to `follow-ups.md` (C2) |

Rejected alternatives (discussion of 2026-11-05), not to be reopened without new evidence:
- A separate arbiter agent: the main thread keeps the verdict and the user already holds a gate after the critic; one more opinion is one more source of re-loops.
- A 2-cycle cap on code review: 84 % already pass in ≤ 2 reviews, and the third review is where the one real `BLOCKED` bug sat.
- Two or three full re-review passes before scoping: the same model, checklist and code repeat the same blind spots; extra full passes add variance, not coverage.
- More reviewers per profile (economy 3, standard 4): deferred. The review converges and no escaped bug was measured; more reviewers mean more findings on the one gate that works. Reopen with a measured escaped bug.
- Turning `verifier` into an acceptance-criteria checker: criteria are walked in review synthesis and at `/loop:ship`; refutation is what keeps the noise out.
- A code re-review scoped to the fix diff for every kind of finding (first draft of C1): ecocrew re-reviews found ~9 original defects missed in round 1, mostly Majors outside any fix hunk; scoping would have shipped them.
- Loading the external two-sided review skill as is (`liza-mas/liza`, `skills/code-review/SKILL.md`, read 2026-11-05): built for an author and a reviewer negotiating, while the kit refutes through a third party (`verifier`), which resists convergence by capitulation between two agents of the same model; its tag vocabulary, net-value gate and `TECH_DEBT.md` duplicate Critical/Major/Minor, the verdict and `follow-ups.md`. K1 and K2 are taken from it.
- From the same skill, K3-K5 are parked, written in full under `## Parked` so they can be taken without rewriting.

## Scope
- IN :
  - **P1. What can block a plan.** `plan-critic.md` and `plan.md` step 6 (`plan.md:77-87`): Critical or Major only for (a) an acceptance criterion not mapped to a write and a case, (b) a contract behaviour with no test case, (c) a dependency order or parallel lot that cannot execute, (d) a violated architecture rule or product invariant. Each such finding is tagged `demonstrated` when it carries its evidence: (a) the criterion id with no write or case, (b) the behaviour with no case, (c) the step that cannot run and why (cycle, missing input, two writes on one file in a lot), (d) the rule `path:line` or invariant and the plan line that breaks it. It is tagged `interpretation` when the violation depends on a reading of the entry artifact that the entry does not settle. The `verifier` refutes the evidence as usual; a `demonstrated` finding whose evidence is refuted drops, it is not downgraded to `interpretation`. Anything else, an implementation mechanism, a layout value, an edge the code will reveal, is reported as `vigilance`, never above Minor, and the main thread appends it to the plan's `## Vigilance` (`plan.md:239`) so `/loop:review` checks it against the code. The quality row "Contracts are precise enough to write tests without reading implementation" is kept, read as: the test-first cases are writable; it never requires the implementation mechanism.
  - **P2. No attempt for what a hook guarantees.** A finding that a test-first file has no RED leg, or that a frozen file is changed without its `.tdd-unfrozen` line, is fixed in the plan by the main thread and records no failed attempt: `tdd-require-red.sh` and `tdd-freeze-tests.sh` refuse the write at EXECUTE whatever the plan says. Condition: the hook actually runs and denies on that leg, i.e. it is registered in `settings.json` (`settings.json:119-124`) and the leg executes under Claude Code. When the plan hands the leg to Codex (`orchestrate.md:197-208`, `execute-green`), no Claude Code hook runs there: the finding counts as an ordinary critic finding.
  - **P3. Scoped rerun.** After a rewrite, the rerun of the affected axis receives the surviving findings and the rewritten sections and answers `fixed | not fixed` per finding. A new finding is admissible only if it sits in a rewritten section, or it is `demonstrated`, of any P1 class, anywhere. The `completeness` axis always re-walks the acceptance criteria against the whole plan: one list check, and a rewrite can drop coverage outside the section it touched.
  - **P4. The user arbitrates after pass 2.** All four P1 classes stay blocking once demonstrated; the user arbitrates a disagreement of reading, never a confirmed violation. When pass 2 still has surviving Majors and all of them are `interpretation`, there is no third rewrite: step 7 prints each one under `Plan critic, open`, with the critic's claim, a proposed answer, and that answer already written into the printed plan, in the same `AskUserQuestion` call as the test plan. `go` accepts them as printed and clears `plan-critic` (`kit-attempts.py pass`); any other reply amends and asks step 7 again. A surviving `demonstrated` finding of any class (a)-(d) still goes to pass 3 and `BLOCKED`; when both kinds survive, the rewrite handles the demonstrated ones and the interpretation ones go to the user at step 7. The 3-attempt ceiling is unchanged and a fourth rewrite is never attempted. All pipelines (`light`, `full`, `BUG`) take P1-P4: the critic and step 7 are shared.
  - **C1. Code re-review: bugs everywhere, the rest on the fix.** After a fix batch (implementer or Codex `review-fixes`), `orchestrate.md` Phase 5 (`orchestrate.md:280-290`) re-runs only the dimensions the fixed findings came from. Each `reviewer` receives the confirmed findings with their closure conditions (K1), the **fix diff** (what changed since the fix batch started, new files included) and the whole feature diff. It answers each prior finding `fixed | not fixed` against its closure condition, with `path:line` evidence. A new finding is admissible:
    - anywhere in the feature diff when it is a **bug**: a Critical or Major of class security, correctness or data integrity, with a concrete failure scenario (entry point, input, wrong result);
    - outside the feature diff when it is a **regression caused by the fix**: a scenario that behaves correctly at the fix-batch base and fails after it, with a fix-diff hunk on its causal path (e.g. an unchanged caller of a function the fix changed);
    - only inside a fix-diff hunk for every other kind (architecture, test quality, maintainability, a Major without a failure scenario).
    The `verifier` refutes the scenario and the causal link like any other claim. Anything not admissible goes to `follow-ups.md` as `out of scope`. The plan picks how the fix-diff base is captured; it must capture new files and pass `enforce-git-workflow.sh` without a new allow rule, or name the rule it adds. The Codex resume path (`orchestrate.md:117-118`) follows the same scoping.
  - **K1. Closure condition.** Every Critical and Major, from `plan-critic` or `reviewer`, carries `Closure:`, the observable state that closes it: a named case that passes, a line or path that no longer exists, a criterion mapped to a write and a case, a scenario that now gives the right result. The reruns of P3 and C1 answer `fixed | not fixed` **against that condition**, not by judging the area again; wanting a different closing state is a new finding, under the same admissibility rules. A Major with no closure condition is recorded as Minor (`follow-ups.md`); a Critical with none gets one written by the main thread before any fix batch. The fix batch's reproduction case (`05-testing.md`, bugfix opens with the failing case) is the usual closure.
  - **K2. Shrink before extending.** In a code re-review, a finding inside a fix-diff hunk, or a regression caused by the fix, is tagged `fix-introduced`. The next fix batch answers it first with the smaller fix that makes it disappear (revert or narrow the part of the previous fix that created it); growth beyond the files named in the findings and their tests is declared with a reason in the batch report, which the main thread prints. `implementer.md` states the rule. The same applies to a plan rewrite: a P3 finding in a rewritten section is answered by narrowing that rewrite first.
  - **R1. Routing decided by a script, not by prose.** The admissibility rules of P3, P4 and C1 are mechanical once each finding carries its fields, so they run in one deterministic script, `.claude/hooks/kit-gate-route.py`, that the main thread calls instead of applying them by hand. `plan` mode reads the surviving findings (severity, P1 class, `demonstrated | interpretation`, section, pass number, `closure`) and returns per finding `vigilance | rewrite | arbitrate | blocked`, a Major with no closure going to `vigilance` as Minor (K1). `review` mode reads the confirmed findings (severity, class, `path:line`, scenario, `regression`, `closure`) with the fix diff and the feature diff, and returns per finding `blocking | follow-up | needs-closure` plus `fix-introduced` when the finding sits in a fix-diff hunk or is a regression (K2), appending the follow-ups to `follow-ups.md` (C2). Whether a finding is a regression, or demonstrated, stays the agents' judgment, checked by the `verifier`; the script decides only what follows from it. The plan fixes the input format and how `kit-attempts.py` is called from the result.
  - **C2. Follow-ups.** Review stage 3 (`review.md:193-208`) appends each confirmed Minor and each out-of-scope finding to `docs/work/<slug>/follow-ups.md`: `- [<dimension>] path:line — <problem> (minor | out of scope)`. A Minor never starts a fix batch; a verdict with only Minors records `pass` on `review`. `/loop:ship` prints the count and the path at the merge. No board line is written from it.
  - **D1. Docs.** `docs/Claude_Workflows.md`, in French: what blocks a plan (demonstrated vs interpretation), the arbitration at the test-plan gate, the re-review (bugs everywhere, the rest on the fix), closure conditions, shrink-first, `follow-ups.md`.
- OUT :
  - Reviewer and verifier counts per profile (deferred, see rejected alternatives).
  - Small lane (already one fix batch, no fresh judgment pass, S7).
  - Code-review severity scale (`reviewer.md:55-61`), verdict PASS/CONCERNS/FAIL, attempt ceilings, `verifier`'s role, review stages 0/1bis/2.5, hooks, `/audit:*`, `.claude/rules/*`.
  - No new agent.

## Parked (not in this pass)
Taken from the same external skill, ready to add as a follow-up spec. Each has its reopen trigger; none is implemented, tested or documented by this pass.

- **K3. Divergence ledger.** Every round, plan or code, prints `Round N — blocking X→Y, files A→B, fix-introduced K`, computed by `kit-gate-route.py`. Divergence: `Y ≥ X` while `B > A`, or every blocking finding of round N is `fix-introduced`. On divergence no next fix batch: the main thread asks the user one decision (`AskUserQuestion`): one recommendation, alternatives only when genuinely competitive, never "continue as is", and the cost of not deciding in rounds and work held. The attempt counter and ceiling are unchanged. Cases: ledger 4/6 → 4/9 diverging, 4/6 → 2/9 not; a round where every blocker is `fix-introduced` diverging whatever the counts.
  - Why parked: one `BLOCKED` in 71 ecocrew features, a real bug; no divergence measured.
  - Reopen when: the measure records a round whose blockers all sat in the previous fix, or a `BLOCKED` reached through `fix-introduced` findings.
- **K4. Contest with a named harm.** The `implementer` may return a finding unfixed as `contested`, naming a concrete harm (behaviour that breaks, invariant violated, cost incurred; "complex" is not one). The reviewer that raised it answers in its rerun `accept | refute | escalate`, never a bare restatement. `accept` closes it and writes the trade-off to `follow-ups.md`; `refute` brings evidence and the finding stands; `escalate`, a second contest of the same finding, or a pair where fixing A breaks B and fixing B breaks A goes to the user (the spec is in question, not the code). A finding under contest records no failed attempt until answered. Cases: first contest → `awaiting-answer`; `accept` → closed + trade-off; second contest → `decision`; no harm named → unfixed.
  - Why parked: no ecocrew case of a requested fix that did harm; one more round-trip per finding.
  - Revert criterion if taken: two contests accepted on findings that later prove real.
  - Reopen when: a fix batch report or a re-review shows a requested fix that broke something else, or an A/B pair.
- **K5. Approach settled after round 1.** From round 2, plan or code, a finding that reopens the chosen approach (shape, library, layer split) is inadmissible unless `demonstrated` with a failure the approach causes; otherwise it goes to `follow-ups.md` as `out of scope`. Case: round 2 `reopens-approach` not demonstrated → `follow-up`; demonstrated → admitted.
  - Why parked: no approach reopened in an ecocrew re-review.
  - Reopen when: the measure records one.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/agents/plan-critic.md` (`Closure:`), `.claude/agents/reviewer.md` (re-review mode, `fixed | not fixed`, `Closure:`, `fix-introduced`), `.claude/agents/implementer.md` (shrink-first), `.claude/commands/loop/{plan,review,orchestrate,ship}.md`, `.claude/hooks/test-workflow-contracts.sh`, new `.claude/hooks/kit-gate-route.py` and its suite `.claude/hooks/test-gate-route.sh` (registered where `test-attempts.sh` is, `install.sh` and kit-ci included), `docs/Claude_Workflows.md`; `.claude/hooks/enforce-git-workflow.sh` and its fixtures only if C1's capture needs a new allow rule.

## Acceptance criteria
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

## Business logic to cover
No TypeScript. Two layers, test-first.

Behaviour, in `test-gate-route.sh` against `kit-gate-route.py` (hand-written fixtures, expected verdicts literal):
- B1 review: a correctness Major with a scenario, in the feature diff, outside every fix-diff hunk → `blocking`, one failed attempt, not `fix-introduced`.
- B2 review: an architecture or test-quality Major outside every fix-diff hunk → `follow-up`, written to `follow-ups.md`, no failed attempt, no new fix batch; the same Major inside a fix-diff hunk → `blocking`, `fix-introduced`.
- B3 review: a Major outside the feature diff, `regression` with a scenario → `blocking`, `fix-introduced`; the same with no scenario → `follow-up`; a Minor anywhere → `follow-up`.
- B4 review: a new file in the fix diff counts as one whole hunk.
- B8 closure: a Major with no `closure` → `follow-up` as Minor (review) or `vigilance` (plan); a Critical with none → `needs-closure`, no fix batch yet.
- B5 plan: pass 2, a `demonstrated` (c) or (d) Major → `blocked` path (pass 3), never `arbitrate`.
- B6 plan: pass 2, only `interpretation` Majors → `arbitrate`; a mix → `rewrite` for the demonstrated, `arbitrate` for the others.
- B7 plan: a non-P1 item at any severity → `vigilance`, no failed attempt; pass 3 failing → `blocked`, never a pass 4.

Wording, in `test-workflow-contracts.sh`, each failing on today's files:
- T1 `plan-critic.md`: contains `vigilance` as a reported kind, the four blocking classes, `demonstrated`, `interpretation`, `Closure:`; contains `fixed | not fixed`.
- T2 `plan.md`, from `6. **PLAN CRITIC GATE` to `7. **TEST PLAN GATE`: contains `rewritten sections`, `## Vigilance`, `no failed attempt` and `kit-gate-route.py`.
- T3 `plan.md`, from `7. **TEST PLAN GATE` to `8. **Stop`: contains `Plan critic, open`.
- T4 `orchestrate.md`, from `## Phase 5 —` to `## Phase 6 —`: contains `fix diff`, `follow-ups.md` and `kit-gate-route.py`.
- T5 `reviewer.md`: contains `fixed | not fixed`, `regression`, `Closure:` and `fix-introduced`; `review.md` stage 3 and `ship.md`: contain `follow-ups.md`.
- T6 `implementer.md`: contains `fix-introduced` and the shrink-first rule (`smaller fix`).

What neither layer proves: that an agent tags a real regression as one, or writes a closure condition that really closes the defect. That is the verifier's refutation at run time and the `Measure after` count.

## Measure after
First diagnosis on the next 10 ecocrew features, confirmation on 30, same grep as the evidence above. Also record, per feature, total tokens (sum of `usage` in the session transcripts, main thread + agents) and wall-clock duration (first to last transcript timestamp of the feature), with the same figures taken on the 71-feature baseline. Targets: `plan-critic` `BLOCKED` from ~28 % to under 5 %; mean `plan-critic` passes ≤ 2; review rounds not above the baseline (mean ~1.9). Also record each `## Vigilance` item from P1 that review later confirmed as a Critical/Major on the code, the re-review blockers by origin (the three rows above), `fix-introduced` counts and fix-diff growth per round, and any round whose blockers all sat in the previous fix (the signal to reopen the deferred divergence ledger). Revert criterion: a `BLOCKED` rate not lower after 10 features (diagnosis) or after 30 (confirmation), or two or more Vigilance items that turn into a Critical at review (the plan should have caught them).
