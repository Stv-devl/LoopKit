---
description: Computes which stories can run in parallel right now (3 max), verifies the story map against the code, then prepares their worktrees
argument-hint: [path docs/stories/<slug>/ — or nothing, inferred from the board]
---

# /loop:tracks — how many stories can run at once, and set them up

Answers one question, against the state of the repo **at the moment you ask**:
which stories can be built in parallel right now, and how many. Then it prepares
the worktrees for them.

The answer is not a property of the backlog, it is a property of today's commit:
it changes after every merge. `.claude/guides/10-worktrees.md` ("How many tracks")
is the authority for the method and the ceiling — this command runs it.

Callable alone at any time. `/bmad:flow` calls it before each story.

## Process

### 0. Inputs and state

Stories: the directory passed as argument, else the one named by
`docs/product/backlog.md`. Read each story's **Status** and **Depends on** — those
two fields, not the whole file.

**A candidate is a story whose `Status` is `Approved`, and only that.**
`InProgress` and `Review` mean a session already has it; `Done` is finished;
`Dropped` was decided against and never comes back by a fork; `Draft` never
passed its gate. Drop them before computing anything, and name what
you dropped and why — the whole point of this command is that no two sessions
receive the same story, and `Status` is the only place that fact is written down.
A story being built shows `InProgress` whichever path drives it (`/loop:orchestrate`
Phase 0 step 2bis, `/bmad:dev` step 2). One that does not is a bug in that path,
not a story you may fork.

**And drop the `BLOCKED` ones.** A story handed back mid-loop returns to
`Approved` — no session holds it any more, which is what that field means — while
its board line goes to `BLOCKED` with the reason. So `Status` alone reads it as
available: when `docs/product/backlog.md` exists, read the `State` column too and
drop every candidate whose line is `BLOCKED` **or `DROPPED`**, naming it and its
reason among what you dropped. `DROPPED` is there as a belt: the story's `Status`
should already say `Dropped`, and a candidate where the two disagree is a
bookkeeping miss upstream — report it in one line rather than forking it. It comes back by a decision, not by a fork. States and transitions:
`/loop:product`, "The board's state machine" — the only copy.

Architecture: `docs/architecture/<feature>.md` — the **PRD's** slug, which is the
directory name of `docs/stories/<feature>/`, never a story's loop slug. The story
map columns `Layers touched`, `Depends on`, `Parallel with`, `Shared foundations`.

Repo state — ONE message, they are independent and write nothing:

```bash
git status --short        # condition 4: a dirty tree forks nothing
git worktree list         # what is already in flight
git log --oneline -1      # the commit the tracks would fork from
```

Plus the migrations already applied (the folder named by `06-database.md`). You
need them for step 1.2 — a story does **not** carry a migration if the schema it
needs already exists.

### 1. Compute

The four steps of `10-worktrees.md`, in order. The first three are subtractions:

1. **Unblocked by dependency** — every prerequisite is `Done`. `Approved`, in
   flight, or finished-but-not-merged is **not** `Done`: a track forks from a
   commit. Name the unmet prerequisite for each story you drop here.
2. **One migration in flight** — at most one survivor may carry a schema change.
   Decide it against the applied migrations, not against the story map: a table,
   a column or an enum value that already exists is not a migration. This is the
   step the map gets wrong most often, and it is usually the step that fixes the
   number.
3. **One writer per shared file** — two survivors naming the same file collapse
   into one. Ask the file, not the story title.
4. **Cost** — a story too small to amortize an empty checkout (an install, an
   `.env` the user copies by hand, a session to drive it) goes back into a
   sibling's queue rather than forking.

**Ceiling: 3.** A fourth survivor is not dropped, it is **queued** — named as
next in line behind whichever track merges first.

### 2. Verify against the code — never skipped

The story map was written before any of that code existed and it drifts. For
each survivor, open the files its row names.

- **economy / standard**: inline, on the main thread.
- **more than three survivors, or an unfamiliar codebase**: one `explorer` per
  survivor, ONE message. Each returns: which named files exist, which do not,
  the real contact points it found, and any helper the map attributes to the
  wrong story. Nothing else — no code dump.

Three drifts, by name, because they are the recurring ones:

| Drift | Shape |
| --- | --- |
| Helper attributed to the story that needs it **second** | the map gives a shared guard/util to story B; story A, earlier, needs the same containment and will either duplicate it or force B to refactor A's files |
| Contact point named by **module** instead of file | the map says "the registry"; the line actually added lives in a composition file — possibly one that does not exist yet |
| Migration **assumed** | the map lists a schema change the applied migrations already cover, and the story is excluded from parallelism for nothing |

Where the code disagrees, **the code wins**. Correct the story map in the same
pass, and say which row changed.

### 3. Report — before touching anything

```
Runnable now : N tracks — <ids + one-line surface each>
Queued       : <id> (behind <track>)
Blocked      : <id> ← <unmet prerequisite, with its current Status>
Excluded     : <id> — <which of the four steps excluded it>
Map vs code  : <the row corrected, or "no drift">
Preconditions: <clean tree | dirty: what> · base <sha> <branch>
```

**N < 2 → stop here.** One line: "single track, main tree, no worktree", name the
story, and prepare nothing. The setup buys nothing and the rule forbids it.

### 4. Prepare — user-gated

Creating worktrees and branches mutates the repo. Present the exact commands and
**wait for an explicit go**.

Before the first fork ever: `.claude/worktrees/` must be in `.gitignore` —
`.claude/` is versioned, its worktrees are not. Check it, add the line if it is
missing, and say so.

On go, per track:

```bash
git worktree add .claude/worktrees/<track-slug> -b feat/<track-slug>
```

**`<track-slug>` is not the slug in this command's argument.** Two different
values are in play, and writing both `<slug>` is how every story of one feature
ends up forking onto one branch:

| | value | example |
| --- | --- | --- |
| the argument, the story folder, the architecture file | the **feature** slug | `docs/stories/inbox/` → `inbox` |
| the worktree, the branch, `docs/work/` | the **track** slug, one per story | `docs/stories/inbox/1.2.md` → `inbox-1.2` |

The derivation is `/loop:research`'s two-line rule (the only copy) and it is a pure
function of the story's path, so you apply it here even though `/loop:research` has
not run yet — it is what records the slug, not what invents it. The commit type
prefixes the branch (`feat/`, `fix/`, `chore/`).

Forking under the feature slug is a **loud** failure and that is the good case:
the second `git worktree add` refuses with "already exists". The bad case is
succeeding — two tracks in one worktree, the first thing `10-worktrees.md`
forbids.

This session enters **at most one** — `EnterWorktree` with
`name: "<track-slug>"`. The others are created and handed over: a session is in
one worktree at a time, and this one does not pretend to drive them all.

### 5. Hand over

One pasteable block per track the user will drive elsewhere:

```
Track <track-slug> — .claude/worktrees/<track-slug> on feat/<track-slug>, from <sha>
  1. copy your env file into it — an agent cannot (`protect-files`)
  2. install: <the install command; a fresh checkout has no node_modules>
  3. /loop:orchestrate docs/stories/<feature-slug>/<n>.md
```

Line 1 and line 3 carry **different** slugs — `inbox-1.2` and `inbox`. Writing
the same placeholder in both is what this command's readers get wrong, so spell
both out in the block you actually hand over.

Close with the fork announcement required by `10-worktrees.md`: one line per
track (slug, branch, path), and the integration order — **one merge at a time**,
rebase, gates re-run in the worktree, go-ahead, merge, remove, then the next.

## Rules

- **Three is the ceiling.** Never prepare a fourth; queue it and name it.
- **Recompute, never remember.** A count is valid until the next merge. Ending a
  turn with "we said three" is how a merged prerequisite goes unnoticed.
- A **foundation** never forks — migrations and the live DB, `src/lib/*`,
  `shared/*`, router, providers, composition root, design system, backlog,
  lockfile. It is done first, in the main tree, and the tracks fork from that
  commit.
- **Never fork a dirty tree.** Report it as a precondition failure, do not
  stash it away yourself.
- Never drive more than one track from this session.
- This command **reads and prepares**. It does not run a loop pass, does not
  merge, and does not commit — `/loop:orchestrate` and `/loop:ship` own those, inside each
  worktree.

## Task: $ARGUMENTS
