---
description: BMAD Dev — runs the build loop for ONE story and keeps its bookkeeping (Status, Dev Agent Record)
argument-hint: [path docs/stories/<slug>/<n>.md]
---

# /bmad:dev — Dev, one story

You implement **a single story**. The build is the shared loop, minus its last
step: you run research → interface → plan → execute → review and **hand back before
SHIP**. What this command adds on top is the story's **bookkeeping** — status,
plan section, record, change log — so a session that resumes tomorrow knows
exactly where it stopped.

## Process

1. Read the story **in full**. If `Status` is not `Approved`, ask before coding
   (a `Draft` story hasn't passed `/stories:review`).
2. Set `Status` to `InProgress`, and move the story's line on
   `docs/product/backlog.md` to `IN LOOP` — the board **only from the main tree**,
   never from a worktree (`10-worktrees.md`, "Never in a worktree"); no board →
   one line, move on. Both, for the same reason: `/loop:tracks` reads `Status` to
   decide what may fork now, and `/loop:ship` reads the board to name what comes next.
   This path does not go through `/loop:orchestrate`'s Phase 0, so it carries that step
   itself — including the way back: you hand back before the commit, so if the
   story is not going to `/loop:ship` today, its line moves to **`BLOCKED`** with the
   reason rather than staying `IN LOOP`, which asserts a session holds it right
   now. Columns, states and transitions: `/loop:product`, "The board's state machine"
   — the only copy.
3. **Run the loop steps yourself, stopping before SHIP.** Do not call
   `/loop:orchestrate` here: it ships at the end, and the whole point of `/bmad:dev` is
   to hand back before the commit. Chain them:
   ```
   /loop:research docs/stories/<slug>/<n>.md
   /loop:interface   docs/work/<slug>/research.md    (SKIP if the story has no UI)
   /loop:plan     …                                → also fills the story's ## Plan
   EXECUTE inline, in the plan's order
   /loop:review   docs/work/<slug>/plan.md
   ```
   Fix the surviving Critical/Major findings inline before handing over.
   If the story's own notes leave a product question open, ask the user; don't
   guess and don't widen the scope.
4. Stop before SHIP: fill the **Dev Agent Record** (model, completion notes,
   exhaustive **file list**), set `Status` to `Review`, add a Change Log line.
5. **Stop.** Suggest `/bmad:qa docs/stories/<slug>/<n>.md`.

> Calling `/loop:orchestrate` directly on a story does the same build and also ships.
> Use `/bmad:dev` when you want the dev/QA separation (fix loop before the gate),
> `/loop:orchestrate` when you want the story to go all the way in one pass.

## Rules

- **One story, nothing more.** Anything discovered but out of scope goes in the
  completion notes, not in the diff.
- Follow `.claude/rules/`: no cross-feature import, no business logic in
  pages/components, data client only in gateway/services, `Result<T>`, no `any`.
- React Query states (`isPending`/`isError`/empty/`isFetching`), **plus
  `isPlaceholderData` as soon as the key carries a filter, a sort or a page** —
  `/loop:review` grades that fifth one (`patterns/react-query.md`, "When the key
  changes"), so the brief names it too. And the copy language split
  (`.claude/rules/03-conventions.md`).
- Tests for the story's business logic are part of the story, not a follow-up.
  For `utils` / `mapper` / `repository`-`services` they come **first**, written by
  a `test-writer` agent from the test plan the user validated, one layer taken
  RED→GREEN before the next one starts, and frozen once green
  (`.claude/rules/05-testing.md`). `tdd-require-red.sh` will refuse to create
  those modules until their RED run has been observed — a denial means the
  ordering was skipped, never that the hook needs working around.
- Never touch protected files (`.env*`, lock files…). The guardrail hooks fire on
  every write — respect them, don't work around them.

## Task: $ARGUMENTS
