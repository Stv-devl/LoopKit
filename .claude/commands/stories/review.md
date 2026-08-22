---
description: Stories review gate — token-aware review of the complete slice before architecture work
argument-hint: [path docs/stories/<slug>/]
---

# /stories:review — kill a bad slice before it costs an architecture

You gate the story set produced by `/bmad:sm`, **before** `/bmad:architect`.
A badly sliced story is cheap to rewrite now and expensive to unwind after the
architecture, the plan and half the code have been built on it.

This step reviews the **set**, not isolated files. Cross-story coverage,
overlaps, and dependency cycles are part of every review batch.

## Process

1. List the stories in the directory passed as argument (`docs/stories/<slug>/`).
   Read the PRD (`docs/prd/<slug>.md`) — you need it for the coverage pass.
2. **Token-aware review** — the arity is declared here, the rest per
   `.claude/rules/11-token-budget.md`. Choose from the story count:
   - **1–6 stories:** launch 1 `story-critic` in mode `set`, with every story.
   - **7–12 stories:** launch exactly 2 critics in ONE message, with balanced,
     disjoint batches.
   - **13+ stories:** launch at most 3 critics, using balanced batches.

   Every critic receives the PRD, its assigned story paths, and the complete
   catalog of story ids/titles/dependencies/PRD traces prepared by the caller.
   It audits its stories in detail and the complete catalog for coverage,
   overlaps, and cycles. Do not add a separate coverage critic. Barrier: gather
   every verdict.
3. **Synthesis (first pass)**: aggregate by severity (Critical / Major / Minor),
   and settle a provisional verdict:
   - **FAIL** if ≥1 Critical, or a PRD requirement covered by no story
   - **CONCERNS** if only Major/Minor
   - **PASS** otherwise
4. **Apply the fixes** to the story files (rewrite the slice, split, merge, drop,
   reorder, sharpen the AC). This command owns the story files — unlike `/review`,
   you fix here rather than only reporting.

   **Two classes of finding are escalated, never fixed here, and they are the ones
   this step would otherwise silently resolve.** Both come from
   `docs/product/brief.md`, and in both the story is the messenger:

   | Finding | What you do |
   | --- | --- |
   | **Critical — a story contradicts a `Product invariant`** | do not touch the story. Report it to the user with the invariant quoted, and the verdict stays **FAIL** until they either change the invariant in the brief or drop the story. `story-critic` is explicitly forbidden from softening it; softening it *for* the critic at this step is the same act, one layer down |
   | **Major — a story delivers something `Out of product` excludes** | same: report, quote the excluded line, and let the user answer. Narrowing the story until it fits inside the boundary is not a fix, it is a scope decision taken by an agent |

   The tell that you are about to do it anyway: the fix you are considering makes
   the finding disappear **without anything about the product having changed**.
   That is not a slice being corrected, it is a gate being cleared. Everything
   else on the list — verticality, sizing, AC wording, dependencies, overlaps,
   coverage — is yours to fix outright, and that is the normal case.

   **Ids are stable.** A split *appends* (`2.3` becomes `2.3` + `2.7`), it never
   renumbers. After any structural fix, re-read every `Depends on` in the **whole**
   set — including the stories you did not rewrite: they reference ids by hand, and
   step 5 does not re-open them.

   **A dropped story keeps its id and gets a state, in two places.** Its `Status`
   becomes `Dropped` — terminal, and the reason on one line in the Change Log; the
   file stays on disk. And it gets a board line reading `DROPPED`: the row it
   already had if this gate has run before, **a new one at step 6 otherwise** —
   which is the normal case, since on a first pass the board holds one `DRAFT`
   line for the whole feature and no per-story line exists yet. Both halves, or it
   comes back: `/tracks` reads `Status` and would fork a story left `Approved`,
   `/ship` step 6 would name a line left `READY` as the next feature — and a story
   with no row at all is the "unit nobody ever thought about" the board exists to
   make impossible. Neither is a state to invent — see `/product`, "The board's
   state machine".
5. Re-run step 2 **only on the stories you rewrote**, in one critic batch (not
   the whole set). Include the updated complete catalog so global checks remain
   possible.
5bis. **Re-settle the verdict**, on the re-run's returns — never on step 3's.
   Step 3 judged the slice *before* you rewrote it; carrying its value into step 6
   either freezes a fixed slice at its old verdict or ships an unrechecked one.

   **Plus the step-3 findings you chose not to fix.** The re-run only covers the
   stories you rewrote, so a Major you decided to leave — on a story step 4 never
   touched — is in neither input and vanishes from the verdict. It has to be
   carried by hand: list those findings explicitly, at their original severity,
   and settle on *re-run returns + carried-over findings*. Step 3's **value** is
   what 5bis refuses; its **unfixed findings** are what nothing else holds.
   A Critical is never in that list — step 4 fixes it or the verdict is FAIL.
   The two escalated classes above **are** in it, at their original severity: step 4
   deliberately did not touch them, so nothing else carries them into the verdict.
6. Branch on the verdict of 5bis, and on nothing else:
   - **PASS or CONCERNS** — no Critical survived: mark each story **you did not
     drop at step 4** `Approved`, put **one `READY` line per surviving story** and
     **one `DROPPED` line per story you dropped** on `docs/product/backlog.md`
     (that board is the FEATURE READY gate — skip in one line if the file doesn't
     exist), list the residual Minor in your report, and suggest
     `/bmad:architect docs/prd/<slug>.md`. A Minor is reported, it does not hold
     the slice: `Draft` blocks `/bmad:architect` and `/tracks` outright, so leaving
     the set there over a wording finding deadlocks the pipeline.

     > **The feature's `DRAFT` line, if `/product` opened one, is replaced — not
     > kept beside yours.** The board holds **one line per unit of loop**, and on
     > the full pipeline that unit is the story: a feature-level line names
     > something no `/orchestrate` can ever take, and it would sit `DRAFT` forever
     > while its stories ship. Match it on the `Feature / story` cell (the feature
     > name your story ids extend), replace it with the per-story lines **at that
     > same position and in id order** — the dropped ids included, at their rank,
     > carrying `DROPPED` — and say so in your report. The rank is the
     > priority (`/product`, "the order of the rows is the priority") and the id
     > order is the dependency order — appending the stories at the bottom instead
     > loses both at once. Columns, states and transitions: `/product`, "The board's
     > state machine" — the only copy.
     > **An escalated `Out of product` finding is presented, and you wait.** It is
     > a Major, so it does not fail the slice — but it is the one Major whose
     > answer is not yours and not the critic's. State it in two lines (the story,
     > the excluded line it crosses), and ask: move the boundary in the brief, or
     > drop the story. **You do not edit the brief either way** — `docs/product/brief.md`
     > has one writer, `/product`, and its two decision sections are chosen by the
     > user in that command's closed question. "Move the boundary" means a
     > `/product` refresh, and you say so. Suggest `/bmad:architect` only after the
     > answer. Marking the
     > stories `Approved` and listing the finding among the residual Minor is how a
     > product boundary gets crossed with everyone's signature on it.
   - **FAIL** — a Critical survived the fix pass: name it, leave every story
     `Draft`, and stop. That is the one state that must block the architecture.
     A `Product invariant` contradicted is always in this branch: step 4 may not
     fix it, so it always survives.

## What a story must survive

- **Vertical**: a deliverable increment, not a technical layer ("the migration" is
  not a story).
- **Independent enough**: its dependencies are named and acyclic.
- **Testable**: every AC is observable; a reviewer can prove it false.
- **Sized**: one story = one loop pass. Too big → split, too thin → merge.
- **Covered**: every PRD requirement, functional and non-functional, lands in at
  least one story, and no two stories claim the same ground. The non-functional
  half is the one that dissolves into "everywhere" — security/authorization,
  a11y and the copy language must name a story (`story-gate-summary.md`).
- **Feasible**: nothing that `.claude/rules/` forbids outright (cross-feature
  import, business logic in a page, manual SQL, data client outside the data layer).
- **Inside the product**: nothing it delivers is excluded by
  `docs/product/brief.md`'s `Out of product`, and nothing it asks for contradicts a
  `Product invariant`. These two are the only checks on this list you may not
  settle by rewriting the story — see step 4.

> At this stage the stories are **functional**. They carry no architecture context
> yet — that is normal, `/plan` injects it per feature. Do not flag a missing
> file path as a finding.

## Rules

- Adversarial bias: the default is "this slice is wrong".
- Never widen the PRD scope to make a story fit — flag the gap instead.
- Report what you rewrote, story by story, in one line each.

## Task: $ARGUMENTS
