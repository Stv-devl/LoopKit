---
description: Spec-first — interview then write a feature's contract in docs/specs/<x>.md
argument-hint: [feature description]
---

# /loop:spec — write the contract before coding

Produce a **spec on disk** that will serve as the single source of truth for
`/loop:orchestrate` and the subagents (they don't have access to this conversation).

## Process

1. **Frame — `AskUserQuestion`, 3-4 questions max.** Only ask questions whose
   answer changes the implementation: in/out scope, data model, edge function
   need, front surface, acceptance criteria. Propose reasonable defaults, don't
   overwhelm.

   **The token profile is a question of its own, asked alone and asked always.**
   Does this feature touch payment, authorization, or a destructive data change?
   Yes → `Token profile: critical`. Three of the four triggers are here; the
   fourth is the user asking for it outright, which needs no question.
   `11-token-budget.md` holds the only copy of that list, and `/loop:ship` reads the
   profile off this file to arm one `/audit:security` surface before the commit.

   It gets its own `AskUserQuestion` call, with the two answers spelled out, and
   it is not folded into a paragraph with the four others. This interview is the
   only moment the fact is known — nothing downstream can re-derive it, and
   defaulting to `economy` disarms the audit **silently**. A closed answer is what
   makes that impossible to do by accident.
2. **Read `docs/product/brief.md` if it exists**, before anything else — the
   product frame `/loop:product` wrote: `Current surface` says what already exists,
   `Out of product` is the boundary this spec may not cross, and `Product
   invariants` are rules it may not contradict. It is cheaper than re-deriving any
   of it. Then **investigate read-only if useful** (read existing code, don't
   write) — only what the brief does not already answer.

   **Both sections are checked here, and here is where the checking stops.** The
   full pipeline hands them to `story-critic`, which is adversarial and reads the
   slice with fresh eyes; this path has you, writing the contract and checking it
   at the same time. Downstream, `/loop:review`'s `correctness` replays the
   **invariants** against the diff — and nothing, anywhere, replays `Out of
   product`. So do it explicitly rather than by feel: quote the excluded line or
   the invariant you are about to cross, and **stop to ask** — move the boundary in
   the brief, or narrow the feature. Deciding it yourself, inside the contract, is
   the one product decision this command is not allowed to take. And you do not
   edit the brief to record the answer: those two sections have one writer,
   `/loop:product`, where the user chooses them outright — "move the boundary" means a
   `/loop:product` refresh first, then this spec.
3. **Write** `docs/specs/<slug>.md` with the template below (slug in kebab-case).
4. **Register it** in `docs/product/backlog.md` as a `READY` line (light pipeline).
   That board is the FEATURE READY gate `/loop:orchestrate` checks. If the file doesn't
   exist, skip this in one line — don't create a board for a single spec.

   **Look for the line before you write one.** `/loop:product` opens a `DRAFT` line the
   day a feature is named; yours is the contract it was waiting for, so you *move*
   that line to `READY` and fill its `Entry artifact` with the spec path. The key
   is the `Feature / story` cell, never the artifact — that cell is `—` on a
   `DRAFT` line by construction. Appending a second line leaves the `DRAFT` orphan
   on the board forever and the gate keeps refusing a spec that exists. Columns,
   states and transitions: `/loop:product`, "The board's state machine" — the only copy.

   **The line does not move rank, only state.** The row order is the priority and
   `/loop:ship` takes the topmost `READY`; a line you re-rank while framing it promotes
   the feature you happen to be holding. Genuinely new — nothing on the board names
   it — goes at the **end** of the table, `READY`. Reordering is `/loop:product`'s, and
   the user's.
5. **Don't implement.** Once the spec is written, stop and propose
   `/loop:orchestrate docs/specs/<slug>.md` — which runs the loop:
   research → interface → plan → execute → review → ship.

> This is the **light entry** into the shared loop. Don't do the research here:
> `/loop:research` does it in parallel, with the live DB and blast-radius probes this
> interview can't run. Frame the contract, stop.

> **Why this path has no adversarial gate, and that is a decision.** The full
> pipeline puts `/stories:review` — two stages, adversarial critics — between the
> slice and the architecture. Here there is one small feature and no slice to get
> wrong, so the equivalent spend would buy a critic re-reading a contract the user
> just dictated. What replaces it is downstream and human: the user re-reads the
> acceptance criteria before anything starts, `/loop:interface` gates the screen and
> `/loop:plan` gates the test plan — and it is the **test plan**, not this file, that
> the frozen tests are written from. What nothing catches on this path is the
> **product** half: a spec contradicting a `Product invariant` is caught later, by
> the reviewer's `correctness` dimension, against code already written — and a
> spec crossing `Out of product` is caught by nobody at all. Step 2 is that check,
> and it is the reason it is written as a stop-and-ask rather than a reading.

## Template `docs/specs/<slug>.md`

```markdown
# Spec: <title>
Token profile: <economy | standard | critical>

## Objective
<one sentence: the expected result>

## Scope
- IN  : <what is done>
- OUT : <what is explicitly deferred>

## Data model
<tables/columns/RLS/triggers involved, or "none">

## Custom backend
<backend handlers/endpoints needed, or "NONE — <why>">

## Front surface
<features/<x> : services, hooks, store, forms, pages, routes, guards>

## Acceptance criteria
- [ ] <observable, testable>
- [ ] ...

## Business logic to cover
<the behaviours that must end up tested — services/repository, mapper, utils,
hooks. Behaviours in plain words, not files and not cases. UI optional.>
```

> **This is not the test plan.** The test plan is written by `/loop:plan`, from real
> research, and it is the one the user validates at the gate, the `test-writer`
> reads, and `/loop:review` compares the frozen files against
> (`.claude/rules/05-testing.md`). A second list of cases here would sit in a file
> nobody re-reads and drift from the only one that binds. Name the behaviours,
> stop there.

## Rules

- Acceptance criteria must be **observable and testable** (this is the final gate).
- The `Token profile` line is not decoration: `/loop:orchestrate` Phase 0 inherits it
  instead of defaulting to `economy`, and `/loop:ship` step 1bis arms its security
  audit on it. Write it even when the answer is `economy`.
- Explicitly mark what is OUT (avoids agents' scope creep).
- Respect the repo conventions (`.claude/rules/`, `.claude/skills/templates/feature.md`).

## Task: $ARGUMENTS
