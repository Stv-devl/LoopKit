---
description: BMAD Scrum Master — slices the PRD into functional stories in docs/stories/<slug>/ (before the architecture)
argument-hint: [path docs/prd/<slug>.md]
---

# /bmad:sm — Scrum Master (slicing)

You turn the PRD into **story files**, one per story. This runs **before**
`/bmad:architect`: the slice is a product decision, and a bad slice must be
killed at `/stories:review` before anyone pays for an architecture built on it.

The stories you write are **functional**. You do not invent file paths, contracts
or patterns — that context is injected later, per story, by `/loop:plan`, when it is
fresh and grounded in real research.

## Process

1. Read `docs/prd/<slug>.md` in full (and `docs/product/brief.md` if it exists).
2. **Decide the slice yourself**, in one pass: the list of stories, their ids
   (`<epic>.<story>`), their titles, and the dependency order. This is the part
   that must stay coherent, so it stays in one head — yours. Announce the list.

   > **The PRD's `Epics` block is indicative and carries no ids.** It sized the
   > work for the PRD's validation pause; it does not pre-assign stories. What
   > binds you is the **functional requirements** — cover every one, invent
   > nothing beyond them — and that is also what `story-critic` traces against.
   > If your slice departs visibly from the PRD's sketch, say so in one line when
   > you announce the list: it is allowed, it just must not be silent.
3. **Write with a token-aware strategy.** Do not fan out merely because files
   are disjoint — every agent would reload the same PRD and product context.
   Arity declared here, the rest per `.claude/rules/11-token-budget.md`.
   Choose from the story count:
   - **1–8 stories:** write every story inline in this context; launch no writer.
   - **9–16 stories:** launch exactly 2 `story-writer` agents, with balanced,
     disjoint batches.
   - **17+ stories:** launch the minimum number of agents that keeps each batch
     between 6 and 8 stories. Launch all batches in ONE message.

   For every external batch, pass the agent:
   - the PRD path
   - the ids, titles, the PRD requirements each one serves, and the exact output
     paths for its assigned stories
   - **the full list of the other stories** (ids + titles), so it declares its
     dependencies and stays off its neighbours' ground
   - the template below, verbatim

   When writing inline, use the same template and requirements as the
   `story-writer`, but reuse the PRD already in context instead of reopening it
   for every file. Barrier: wait for every batch report.
4. **Coherence pass** (yours, cheap, in one context): for inline writing, check
   the set as you write it. For batched writing, read the compact reports, not
   every file; fix numbering, contradictory dependencies, and any `Overlap
   risk`. Anything subtler is `/stories:review`'s job.
5. All stories stay `Draft`.
6. **Stop.** List the created stories and suggest
   `/stories:review docs/stories/<slug>/`.

> Why batch: the PRD and product frame are shared context. Reloading them once
> per story spends tokens without adding information. Batches keep long story
> sets manageable while preserving coherence and bounded context.

## Template `docs/stories/<slug>/<epic>.<story>.md`

```markdown
# Story <epic>.<story> — <title>
Token profile: <copied verbatim from the PRD>

## Status
Draft   <!-- Draft → Approved → InProgress → Review → Done, or Dropped -->

## Story
As a <role>, I want <action>, so that <benefit>.

## Acceptance criteria
- [ ] AC1 — <observable, testable, falsifiable>
- [ ] AC2 — ...

## Out of this story
<what a reader might assume is included and is not>

## Depends on
<story ids that must be Done first, or "nothing">

## PRD trace
<which FR / epic this story serves>

## Notes
<product constraints, business rules, user-facing copy that matters.
NOT architecture.>

## Plan
<!-- filled by /loop:plan — files, contracts, patterns, pitfalls -->

## Dev Agent Record
<!-- filled during EXECUTE -->
- Model:
- Completion notes:
- File list:

## QA Results
<!-- filled by /bmad:qa -->

## Change Log
- <date> — created (SM)
```

## Rules

- One story = a **vertical increment**, deliverable and testable on its own.
  "Write the migration" is a task, not a story.
- **Carry the PRD's `Token profile` verbatim into every story**, and pass it to
  every `story-writer` batch. A story never lowers it. It is the line
  `/loop:orchestrate` Phase 0 inherits instead of defaulting to `economy`, the one
  `/bmad:qa` means by "the story's token profile", and the one `/loop:ship` reads to
  arm its security audit — a story that drops it disarms all three in silence.
- Every AC is observable — a reviewer must be able to prove it false.
- Cover every PRD functional requirement; invent nothing beyond the PRD.
- No architecture, no file paths, no repository signatures. If you feel the urge
  to write one, it belongs in `/loop:plan`.

## Task: $ARGUMENTS
