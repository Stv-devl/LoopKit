---
description: Bug entry — reproduce first, rank candidate causes, validate with temporary logs, then route the bounded fix through the loop
argument-hint: "<symptom or bug artifact>"
---

# /loop:debug — symptom to proved cause, then bounded fix

A bug starts from a symptom, not a proposed solution. No fix is written or
recommended before a failing reproduction exists.

## 1. Record the unit

Derive a short slug from the symptom and create `docs/work/<slug>/debug.md` with
`Token profile`, the exact symptom, reproduction environment, expected/actual
behaviour, and OUT scope. If the product board exists, append or move its one
line with `Entry artifact` = this path, `Pipeline` = `BUG`, `State` = `READY`.
The `BUG` unit uses the existing six states; it creates no seventh state.

## 2. Reproduce before diagnosing

Find the narrowest layer where the symptom is externally observable. Launch one
`test-writer` in isolated context with the bug artifact and the one reproduction
file. It may read the bug contract, not the implementation module. The case must:

- fail on the current code for the reported symptom;
- reach an assertion (a syntax/import/config failure is not reproduction);
- pass after the fix without changing the assertion.

If the normal `test-writer` input needs a plan path, first write a minimal
`plan.md` containing only Contracts and the Reproduction case, obtain the user's
test-plan go, then launch it. No reproduction → stop `BLOCKED` with the exact
missing evidence. Never compensate with a manual fix.

## 3. Rank candidate causes

Read the smallest code surface that can explain the reproduced path. Write at
least two candidate causes into `debug.md`, ordered by likelihood, each with:

- evidence for and against;
- one observation that would falsify it;
- the exact validation point before/after the suspect boundary.

Do not select a root cause yet.

## 4. Validate before committing to a hypothesis

Add the minimum temporary diagnostic logs at those validation points. Logs and
errors are English, contain no secret or personal data, and carry a distinctive
`LOOPKIT_DEBUG` prefix so the diff can prove they were all removed. Run the
reproduction once, record the observed values in `debug.md`, then remove every
temporary log before writing the fix.

Only a candidate whose predicted observation occurred may become `Root cause`.
If none survives, update/rerank the candidates; do not bend code around the
symptom. Three failed diagnostic gates use the loop attempt counter and return
the board line as `BLOCKED`.

## 5. Fix through the shared loop

Complete the plan with the proved root cause, bounded file set, regression test,
and acceptance criteria. Run `/loop:orchestrate docs/work/<slug>/plan.md` from
Phase 4. The reproduction stays frozen; just enough implementation makes it
green. `/loop:review` must reject unrelated cleanup and any remaining
`LOOPKIT_DEBUG` occurrence.

## Required close

Persist in `debug.md`: failing-before/passing-after output, proved root cause,
fix boundary, removed diagnostics, and regression test path. A commit message or
ticket note can link this artifact; it does not copy the investigation.

## Task: $ARGUMENTS
