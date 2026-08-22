# Worktrees — isolating parallel tracks

**This file is the only copy of the fork rule.** `/plan`, `/orchestrate`,
`/bmad:flow`, `/ship` and the `github` agent read it here.

## The unit of isolation is a *track*, not a file

A **track** = one full loop pass on one artifact (one `/spec`, one story). It
owns a branch and a worktree. Inside a track nothing changes: EXECUTE stays
sequential on the main thread, and `/plan`'s parallel lots stay agents forking in
the *same* tree on disjoint files.

```
several features / different work  → several tracks → one worktree each
one feature, several lots          → one worktree, lots fork inside it
```

Forking per lot is the failure mode this rule prevents: the lots of one feature
share types, contracts and a test suite, and merging them costs more than the
wait.

## When to fork

Fork **only if all four hold**:

| # | Condition |
| --- | --- |
| 1 | **≥ 2 tracks** are being advanced in the same session (or the user asks for one in the background) |
| 2 | Their file sets are **disjoint** — declared by `/bmad:architect`'s story map, or by `/plan`'s `Files` table |
| 3 | Neither touches a **shared foundation** (list below) |
| 4 | The repo is a git repo, the current tree is **clean**, and the base branch is known |

Any condition missing → **stay in the main tree**, sequential. One track alone
never gets a worktree: the setup cost buys nothing.

## How many tracks — count them, don't assume two

`/tracks` runs everything in this section and prepares the worktrees; what
follows is the method it applies, and the authority when it is done by hand.

The four conditions answer *whether* to fork. They do not answer **how many**,
and the answer is never "two by default": it is computed from the state of the
repo at the moment you ask, and it changes after every merge.

Four steps, in this order. The first three are subtractions:

1. **Unblocked by dependency.** Every candidate whose prerequisites are all
   `Done`. A prerequisite that is `Approved`, in flight, or finished-but-not-
   merged does **not** count — a track forks from a commit, not from a working
   tree.
2. **One migration in flight, ever.** Of the survivors, at most **one** may carry
   a schema change. A worktree isolates files, not the database. This is usually
   the filter that fixes the number.
3. **One writer per shared file.** Two survivors naming the same file — the same
   feature folder, the same registry, the same route tree — collapse into one.
   Ask the *file*, not the story title: `features/x` written by two stories is
   one track, even where the story map calls them parallel.
4. **Then cost.** A track earns a worktree when its work outweighs an empty
   checkout: an install, no `.env` (the user copies it), and one session to drive
   it. A two-file story does not amortize that — it goes back into a sibling's
   queue, sequentially. Say so rather than fork it.

**Three tracks is the ceiling**, whatever survives the four steps. Not an
arithmetic limit — a driving one: one session drives one worktree, so N tracks
means N sessions the user holds open at once, N installs, N `.env` copied by
hand, and an integration barrier that stays strictly one at a time. Past three,
the merge queue is longer than the work saved and no one can follow what is in
flight. A fourth survivor is not dropped, it is **queued**: named as next in line
behind whichever track merges first.

Announce **the number and the named set**, plus the reason each excluded
candidate was excluded. An exclusion nobody wrote down comes back as a merge
conflict.

**Verify the map against the code — never trust it alone.** The `Parallel with`
and `Shared foundations` columns of `/bmad:architect`'s story map are written
once, before any of that code exists, and they drift: a helper attributed to the
story that needs it *second*, a contact point named as the file expected to hold
it rather than the one that does. Before forking, open the files those columns
name. Where the code disagrees, **the code wins**, and the story map is corrected
in the same pass.

## What never forks

| Never in a worktree | Why |
| --- | --- |
| Migrations & the live database | A worktree isolates **files, not the DB**. Two tracks migrating in parallel = two timelines on one schema. |
| `src/lib/*`, `shared/schemas/*` | Everything imports them; a change here is not disjoint by definition. |
| Router, `src/providers/*`, composition root | Every feature wires into the same files. |
| `docs/design-system.md`, `docs/product/backlog.md`, `docs/product/brief.md` | Single product-level files, written by every track. The brief joins the list because `/ship` step 5 refreshes its `Current surface` after the merge. |
| `package.json` / lockfile | Two tracks adding deps = a lockfile conflict, every time. |

**Shared foundations are done first, in the main tree, and committed — then the
tracks fork from that commit.** A track that needs a foundation change mid-flight
stops, hands it back to the main tree, and rebases.

## Layout

- Path: `.claude/worktrees/<slug>` — the harness's own convention, so both
  mechanisms below land in the same place.
- `<slug>` is the **track** slug — one per loop pass, derived from the entry
  artifact's path by `/research`'s rule (the only copy), so `docs/work/<slug>/`,
  the worktree and the branch all match. On a story that is
  `<feature>-<epic>.<story>` (`inbox-1.2`), **not** the feature folder's name:
  forking several stories of one feature under `inbox` is three tracks in one
  worktree, which the Rules below forbid outright. The fork happens before
  `/research` runs, so the rule is applied there rather than waited for.
- Branch: `feat/<slug>` (`fix/`, `chore/` follow the commit type).
- `.claude/worktrees/` **must be in `.gitignore`** before the first fork —
  `.claude/` itself is versioned, its worktrees are not.

## Which mechanism

| You want | Use | Why |
| --- | --- | --- |
| **This session** to work in the track | `EnterWorktree` (`name: "<slug>"`) | creates it, switches the session into it, and offers keep/remove on exit. One call. |
| To **pre-create** a sibling track without leaving this one | `git worktree add .claude/worktrees/<slug> -b feat/<slug>` | a session can only *be* in one worktree; this creates the others without moving you |
| To enter a worktree that already exists | `EnterWorktree` (`path: …`) | it must appear in `git worktree list` |
| To leave | `ExitWorktree` (`keep` \| `remove`) | `remove` refuses a dirty tree unless told to discard — let it refuse |
| A **mechanical, gate-free** job (wide codemod, dependency bump) | `Agent` with `isolation: "worktree"` | throwaway isolation, auto-cleaned if unchanged |

**A loop pass is never an `isolation: "worktree"` subagent.** The loop has human
gates (design judged, review findings fixed, ship validated) and a subagent
cannot hold them — a track that must be driven runs in a session.

> **Several tracks at once = several sessions.** One session is in one worktree
> at a time. This session pre-creates the sibling worktree, names it, and says
> so; it does not pretend to drive both.

```bash
git worktree list                                      # what exists right now
git worktree remove .claude/worktrees/<slug>           # after the merge, never --force
git branch -d feat/<slug>
```

### Three things to know before the first fork

- **The guardrails follow.** `.claude/` is versioned, so a worktree checkout
  carries its own hooks, rules and commands. Nothing to copy.
- **The base ref is a setting.** `worktree.baseRef` in `settings.json` decides
  what `EnterWorktree` branches from: `head` (current local HEAD) or `fresh`
  (`origin/<default>`). This kit ships `head` — a local-only repo has no origin
  to branch from. On a team repo with a remote, flip it to `fresh`.
- **The setup cost is real — announce it.** A new worktree is an empty checkout:
  **no `node_modules`** (install before any gate runs) and **no env file**. The
  env file is not copyable by an agent — `.env*` is blocked by `protect-files`
  (`CLAUDE.md`, Security); ask the user to copy it, never work around it. Two
  tracks that would each pay this for ten minutes of work are not worth forking:
  say so instead.

## Merge protocol (gated)

1. The track runs its whole loop **inside its worktree**: EXECUTE, REVIEW, and
   `/ship`'s gates (`typecheck`, `lint`, `test:run`, `build`, `audit`) — all
   green **there**.
   Gates run in the main tree prove nothing about a worktree's code.
2. `/ship` commits **in the worktree**, via the `github` agent.
3. **Barrier** — integration is one at a time, never two merges in flight.
   Rebase the track on the current base branch, re-run the gates if the rebase
   moved anything, then merge.
4. The merge back is a **user-gated action**, like a push: present the branch,
   the diff summary and the exact command, then wait.
5. After the merge: remove the worktree — `ExitWorktree` (`remove`) if the session
   is standing in it, `git worktree remove` otherwise — delete the branch, and
   only then let the next track integrate.

A track whose review fails does **not** merge. It loops on the fix in its own
worktree.

## Rules

- One track = one worktree = one branch. Never two tracks in one worktree.
- Never edit files of worktree A from worktree B — that is the whole point.
- Never `git worktree remove --force` a dirty tree: it destroys uncommitted work.
- Announce every fork in one line (slug, branch, path) and every merge, in the
  loop's conclusion. An isolated track nobody named is a branch nobody merges.
