---
description: BMAD Orchestrator — drives a complex feature end to end (PRD → stories → stories review → architecture → loop per story)
argument-hint: [feature description, or path docs/prd/<slug>.md to resume]
---

# /bmad:flow — full pipeline orchestrator

You drive a **complex** feature end to end. You chain the personas but **stop at
validation points**: the user approves the PRD, the story set, and the
architecture before any code.

> For a small feature (one screen, a CRUD, a fix), this is oversized — use
> `/loop:spec` then `/loop:orchestrate`. Same loop, lighter entry.

```
/loop:product ─(once)─▶ /bmad:pm ─▶ /bmad:sm ─▶ /stories:review ─▶ /bmad:architect ─▶ /loop:design-system ─(once)
                                                                                            │
                                                                          per story ▼ FEATURE READY
              /loop:orchestrate = research → interface → plan → execute → review → ship
                                                                                            │
                                                                                      next story
```

## Phases

### 1. Frame (once per product, skip if done)
`docs/product/brief.md` missing → `/loop:product`. It also opens the backlog board,
which is the FEATURE READY gate the loop checks.

### 2. Planning
1. `/bmad:pm <description>` → PRD. **Pause**: the user validates.
2. `/bmad:sm docs/prd/<slug>.md` → functional stories, all `Draft`.
3. `/stories:review docs/stories/<slug>/` → parallel gate, fixes applied, stories
   moved to `Approved` and listed `READY` on the board. **Pause**: the user
   confirms the slice.
4. `/bmad:architect docs/prd/<slug>.md` → architecture + story map.
   **Pause**: validation.
5. `/loop:design-system` → `docs/design-system.md`, **if** any story has a user surface
   and the file doesn't exist yet. Written once per product, but it is a hard
   prerequisite of `/loop:interface`: without it the proposals invent components.

### 3. Build loop (story by story)
For each `Approved` story, in the architecture's dependency order:

```
/loop:orchestrate docs/stories/<slug>/<n>.md
```

which runs research → interface → plan → execute → review → ship for that story, and
names the next one.

- **Before each story, run `/loop:tracks docs/stories/<slug>/`** — it computes what can
  run in parallel *now* (method and ceiling: `.claude/guides/10-worktrees.md`,
  "How many tracks"), verifies the story map against the code, and prepares the
  worktrees. **Three tracks maximum**; a fourth is queued, not dropped. Do not
  assume the count from the last pass: it changes at every merge.
- Every story it returns runs **at the same time, one worktree each** —
  `.claude/worktrees/<feature>-<epic>.<story>` on the matching `feat/` branch,
  **never `<slug>`**: everywhere else in this file `<slug>` is the PRD's, and
  three stories forking under it is three tracks in one worktree. The derivation
  is `/loop:research`'s rule; `/loop:tracks` spells it out. Never merged into one loop
  pass, never two in one tree, and one session drives one worktree: N tracks
  means N sessions.
- Stories touching a **shared foundation** (migrations, `src/lib/*`, `shared/*`,
  router, providers, lockfile) run **first, in the main tree, sequentially**. The
  parallel stories fork from that commit — that is usually story 1 of the epic.
- Never run two stories writing coupled files concurrently.
- Integration is one at a time: rebase, gates, go-ahead, merge, remove the
  worktree, then the next.
- A story that fails its review gate loops on the fix in its own worktree, it
  does not move on and it does not merge.

### 4. Closing
When every story is `Done`:
- every track merged, `git worktree list` back to the main tree alone, no
  `feat/*` branch left dangling.
- typecheck + run-once tests + build + `pnpm audit` green (in parallel), per
  `00-project.md`. On the **merged** base branch: green in each worktree does not
  prove green once integrated — and the audit is the one that can have turned red
  *while* the epic was being built, without any story touching a dependency.
- Recap: epics delivered, feature-level AC checked, what stays OUT, what needs
  deploying.
- `docs/product/backlog.md`: **verify, don't rewrite.** `/loop:ship` moved each line
  to `SHIPPED` story by story, at step 5. What you check is that nothing was left
  behind: no line of this epic still on `IN LOOP` (a track that stopped without
  giving the line back), and every `BLOCKED` one named with its reason in the
  recap. Writing states here would be a second authority on a file `/loop:ship` already
  owns — `/loop:product`, "The board's state machine", is the only copy.

## Resume

Handed an existing `docs/prd/<slug>.md`, detect the state before doing anything:
stories present? reviewed (`Approved`)? architecture written? story statuses?
Resume at the right phase instead of redoing it.

## Task: $ARGUMENTS
