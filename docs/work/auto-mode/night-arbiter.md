# Night arbiter — rules for the unattended auto-mode run (user, 2026-11-20)

Token profile: critical

The user validates every question up to and including the `Plan gate` go, then sleeps. After that
go, every decision that would come back to the user is taken by an **arbiter agent**, never by the
main thread and never by the agent that raised it. The user reviews the PR in the morning.

## When to call the arbiter
Any stop that `/loop:orchestrate`, `/loop:review` or `/loop:ship` would hand to the user after the
plan-gate go:
- a frozen-case correction (unfreeze queue, plan-level or EXECUTE);
- a review route `fail` (whether to record the attempt or not record it and run a fix batch), and the
  design choice a fix batch needs;
- a plan-critic / reviewer `interpretation` finding, an open question, a contract contradiction;
- an audit Major at ship (fix now vs follow-up), a red gate after its fix budget;
- any `AskUserQuestion` the loop would ask, except the `Plan gate` itself.

## How
- Launch a **fresh `reviewer` agent** (read-only, effort `high`), one per decision, never resumed
  for another decision, never the agent that asked. Hand it: the question as it would be asked to
  the user (options, recommendation), the paths to read (spec `docs/specs/auto-mode.md`, plan,
  route file, the hunk from `git diff` for a frozen case), and these rules.
- It returns: the chosen option, a 2-4 line reason, and the alternative it rejected.
- The main thread applies the verdict as if the user had answered, then records it.

## Limits (the arbiter refuses → blocked stop: handoff `blocked: <cause>`, no PR)
- A choice that changes the meaning of an acceptance criterion or the spec's Scope.
- A merge, a force-push, a history rewrite, a write to secrets: never, whatever it says.
- One verdict per frozen case id; `refuse` is final.
- **A review route `fail`** (any round, including the one that would be the 3rd recorded failure):
  the arbiter picks one of
  1. **fix + full re-review** — the attempt is NOT recorded; one `implementer` fix batch, then the
     affected dimensions re-reviewed on the fix diff (reviewers + verifier), as orchestrate Phase 5;
  2. **fix + targeted check** — the attempt is NOT recorded; one `implementer` fix batch, then ONE
     `verifier` checks only each blocking finding's `Closure:` on the fix diff (no fresh reviewers);
     for findings whose closure is a test case that fails before / passes after. If the verifier
     confirms every closure and the fix batch is refusal-only or test-only, the gate clears;
     otherwise it counts as a full round;
  3. **split** — the failing part is removed or narrowed (fail-closed), filed as its own pass in
     `follow-ups.md`, then option 1 or 2 on what remains (what loop-to-pr did at round 6);
  4. **record** — `kit-attempts.py fail … review`; at 3 recorded failures the pass is BLOCKED.
  The arbiter must pick 3 (split) or 4 (record) when two consecutive rounds each produced a new
  confirmed fix-introduced Major in the same mechanism (non-convergence).
- Hard cap: **4** fix batches decided by the arbiter after the user's last answer, all options
  together; the next route `fail` is recorded and the pass stops BLOCKED.

## Trace (mandatory)
- Every verdict is appended to `docs/work/auto-mode/night-decisions.md`: time, question, options,
  verdict, reason, rejected alternative.
- The PR body opens with a `Decided without you` block listing every verdict (one line each, link to
  that file), before every other section. A plan-gate `amended` line decided by the arbiter is
  marked as such in `Frozen cases`.
