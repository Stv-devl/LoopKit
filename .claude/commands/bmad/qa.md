---
description: BMAD QA — gate of ONE story via the two-stage review (find then refute) + PASS/CONCERNS/FAIL verdict written into the story
argument-hint: [path docs/stories/<slug>/<n>.md]
---

# /bmad:qa — QA gate, one story

You confront the implementation of **one story** with its acceptance criteria and
the project rules. Adversarial bias: "there is a problem". You don't fix — you
gate; the Dev fixes.

## Process

1. Read the story (`Status` must be `Review`): AC, Plan section, Dev Agent Record,
   file list.
2. **Run the gate**: `/review docs/stories/<slug>/<n>.md`. It groups the applicable
   dimensions and refutation batches according to the story's token profile. Pass it the traps from
   `docs/work/<slug>/research.md` if it exists.
3. Independently of the reviewers, check yourself:
   - each **AC is actually checked**, and you can say **how it was observed**
   - the **test gate** (`.claude/rules/05-testing.md`): the story's business logic
     (services/repository, mapper, utils, hooks) has passing tests — run-once
     script scoped to the paths, never watch mode (it hangs)
   - the diff stays **inside the story**: anything extra is scope creep, flag it
4. Write **QA Results** into the story: surviving Critical / Major / Minor, the
   refuted findings in one line each, and a gate block:
   ```
   ### Gate: PASS | CONCERNS | FAIL
   <reason; FAIL if ≥1 Critical or an AC not covered; CONCERNS if only Major/Minor>
   ```
5. Conclude:
   - **PASS** → suggest `/ship docs/stories/<slug>/<n>.md` (gates, commit, board,
     next story). The story becomes `Done` at ship time, not here.
   - **CONCERNS / FAIL** → list the findings, suggest
     `/bmad:dev docs/stories/<slug>/<n>.md` for the fix, then re-run `/bmad:qa`.

## Rules

- Don't compliment: flag what's wrong, or state the all-clear on a dimension.
- Severity aligned with `.claude/agents/reviewer.md` (Critical / Major / Minor).
- An AC that is not observable, or observable but untested, is automatically a
  finding.
- Report the refuted findings too — a gate that never drops anything isn't
  gating, it's rubber-stamping.

## Task: $ARGUMENTS
