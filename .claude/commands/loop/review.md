---
description: Review gate — parallel adversarial reviewers, then a parallel refutation pass on every finding
argument-hint: [path docs/work/<slug>/plan.md, docs/specs/<x>.md or a story]
---

# /loop:review — adversarial review gate, two stages

Confront the written code with the project rules and the acceptance criteria.

This is gate `review` under `/loop:orchestrate`'s attempt protocol. A pass clears
that key. Any surviving Critical/Major records one failed attempt; the third
returns the board line as `BLOCKED` before another fix/review cycle begins.

Two stages, because a reviewer's job is to be suspicious and a suspicious reviewer
produces false positives. Stage 1 finds, stage 2 refutes. Only what survives
refutation is worth an edit.

## Process

### Stage 0 — LOOK (UI features only, on the main thread)

The reviewers read code. Nobody in this pipeline has eyes, so a broken hierarchy,
an unreadable contrast or an overflow at 1280px passes every other gate. This
stage is the one place someone actually looks.

**You** do this — not a subagent: browser control lives on the main thread.

1. Launch the app with the **`run` skill**. If it won't start, that is a
   **blocking finding**, not a reason to skip the stage.
2. Navigate to the delivered screen and capture:
   - the **nominal** state, with real data
   - the **empty** state (no rows) and the **error** state, if reachable — these
     are the ones shipped broken, because nobody looks at them
   - a **narrow viewport** (~1280px, and mobile if the screen is meant to be)
3. Compare against `docs/work/<slug>/design.md`: screens, states, edge cases,
   user-facing copy. Divergence from the validated design is a **Major**
   (Critical if it drops an acceptance criterion). **The document is the
   reference, not the canvas it links to** — an artboard edited after the gate
   was validated by nobody (`/loop:interface`, "The canvas").
4. Look for what only the eye catches: hierarchy, alignment, contrast, overflow,
   truncation, loading flicker, layout shift when data lands.

Skip only when the diff has no user surface — and **announce the skip with its
reason**. Findings from this stage enter the same severity scale, and they
**bypass stage 2**: a screenshot is stronger evidence than a refutation argued
from code.

> **No browser tooling on this machine?** Then say exactly that, in the verdict,
> as a gap in the gate — not as a skip. This stage is the only one with eyes, so
> its absence means the review shipped a screen nobody looked at. It is a finding
> about the setup (`docs/ADAPTATION.md`, §13), and the acceptance criteria that
> depended on seeing the screen come back as **not observed**, never as met.

### Stage 1 — FIND (parallel fan-out)

Every agent below is launched with `Agent` and an explicit
**`subagent_type: reviewer`** (stage 1), `e2e-tester` (the E2E half) or
`verifier` (stage 2). Never a bare `general-purpose`: the typed agents carry the
dimension checklists, the read-only contract and the model tier the token profile
is costed against — an untyped one carries none of it and silently costs more.

Read the token profile carried by the artifact (`economy` by default), skip
irrelevant dimensions first, then group the remaining dimensions:

- **economy:** at most 2 `reviewer` agents: `correctness + tests`, and
  `security + db + ui`.
- **standard:** at most 3 `reviewer` agents: `correctness`, `tests`, and
  `security + db + ui`.
- **critical:** one `reviewer` per applicable dimension, for the cases
  `11-token-budget.md` reserves `critical` for — that list is the only copy.

A reviewer may receive several dimensions and must return separate findings
under each heading. Grouping reuses the same diff, artifact and research context.

> **While they run, do not poll and do not `sleep`.** You are re-invoked when
> each one finishes. A turn spent waiting is billed twice, in tokens and in
> wall-clock, and the transcript looks busy the whole time
> (`.claude/rules/11-token-budget.md`).

Pass each: the artifact path, **and the vigilance points** as targeted criteria —
from `plan.md`'s `Vigilance` section when the artifact is a plan, since that is
research's `Traps` already restated as something checkable against this diff.
Falling back to research's raw `Traps` is correct only when there is no plan;
doing it anyway throws away the restatement `/loop:plan` was asked to produce.
A skipped dimension is **announced with its reason**, never dropped silently.

> **`tests` carries one extra check.** The test-first files — front:
> `utils` / `mapper` / `repository`-`services`; backend, when this repo carries
> the FastAPI addon: `tests/services/test_*.py` (`07-backend.md`) — were
> validated at the `/loop:plan` gate and frozen. So the dimension compares them
> against `plan.md`'s `Test plan`
> and reports any case that was **dropped, weakened or renamed** — an assertion
> that migrated toward what the code happens to do is a **Major**, even with the
> suite green. A test edited without a matching entry in `.claude/.tdd-unfrozen`
> is a **Critical**: the freeze was worked around.
>
> A case **added** beyond the plan is the one legitimate divergence — the test
> list stays alive. It is still reported, in one line each, so the gate says what
> grew: unexplained, it is a **Minor**; explained by a behaviour the plan missed,
> it is a good sign and gets named as such.
>
> The dimension also checks that `.claude/.tdd-red/` holds a marker for each of
> those files. No marker means the RED phase was never observed — either the
> hooks are not wired in this tree, or the module was written first and the gate
> was bypassed. Say which; an unwired hook is a finding about the repo, not about
> the diff.

**In the same message**, add `e2e-tester` agents (`subagent_type: e2e-tester` —
the only command that launches this agent, and the one its own description points
at) only for flows a unit/integration test cannot prove. Economy permits 1 tester
for the highest-risk flow, standard 2, critical one per justified flow. Each
tester owns one spec file. Give each: the artifact path, its flow, and its spec
path.

Launch a tester only when the diff has a user flow that crosses screens or
depends on a guard. A pure migration, a scheduled job, an isolated component:
skip and say so. E2E is slow and brittle relative to the unit runner — it earns
its place only where a unit test cannot reach.

> Whether the tester may mutate anything is decided by the `e2e-playwright`
> skill, not here. On a read-only surface a criterion that needs a mutation comes
> back as "not coverable" — that is a legitimate result, not a gap in the review.

Barrier: gather the verdicts and the run outputs.

### Stage 2 — REFUTE (parallel fan-out)

Group arguable Critical/Major findings by reviewer dimension. Launch at most
one `verifier` per dimension, each receiving a bounded batch. Economy permits
2 verifier batches, standard 3, critical one per applicable dimension. Literal,
directly proven violations bypass refutation.

- `refuted: true` → drop the finding, note it in the synthesis
- `refuted: false` → the finding is confirmed, it carries a failure scenario now

Minor findings skip stage 2 — refuting them costs more than reading them.

> Don't run stage 2 on findings you already know are real (a missing test file, a
> literal `any`). Refutation is for the arguable ones.

### Stage 2.5 — SHADOW AREAS (standard and critical only)

On `economy`, stay silent: no heading and no skipped report. On `standard` or
`critical`, launch one final read-only `reviewer`. Ask which behaviour outside
the changed files can break through a shared contract, generated consumer,
configuration twin, cache/invalidation key, route registration, migration
supersession, or caller the main dimensions did not inspect.

Return at most **3** items ordered by plausible user impact. Each needs
`path:line`, the changed dependency it shadows and a concrete failure scenario.
Omit anything already covered by a normal finding. Refute Critical/Major items
with `verifier`; report Minors. Zero items is `Shadow areas: none found.` This
belongs to the same `review` attempt and never creates a sixth permanent review
dimension.

### Stage 3 — SYNTHESIS

1. Aggregate the **surviving** findings: Critical / Major / Minor.
2. Walk the acceptance criteria — an uncovered criterion is a Critical regardless
   of what the reviewers said.
3. Global verdict: **FAIL** if ≥1 Critical or an uncovered criterion, **CONCERNS**
   if only Major/Minor, else **PASS**.
4. Report the refuted findings in one line each — they are the proof the gate
   isn't rubber-stamping.
5. Propose the fixes. Don't apply them without agreement, unless the caller
   (e.g. `/loop:orchestrate` Phase 5) already asked for it.

## Output

```
## Review verdict: PASS | CONCERNS | FAIL
### Visual (stage 0)
- <screen/state> — what was seen vs what design.md says   (or "skipped — no UI")
### E2E
- <flow> — <n> passed / <n> failed, spec at <path>   (or "skipped — <reason>")
- Not coverable: <criterion> — <why>
### Confirmed — Critical
- path:line — problem + failure scenario
### Confirmed — Major / Minor
- path:line — problem
### Refuted (dropped)
- <finding> — <why it doesn't hold>
### Criteria
- <n>/<n> covered — <the uncovered ones>
### Skipped dimensions
- <dimension> — <reason>
```

> Alternative: native `/code-review` for a generalist off-artifact review.

## Task: $ARGUMENTS
