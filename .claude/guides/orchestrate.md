# /loop:orchestrate — why the loop is shaped this way

Read when changing `.claude/commands/loop/orchestrate.md`, or when one of its
rules looks arbitrary. The command keeps the instructions and the traps; the
reasons live here.

## Parallelise reads, sequence writes

Parallelise what **reads** the same thing without depending on each other
(research, interface, review). Sequence what **writes** what the next step reads
(execute). Never run subagents writing concurrently on coupled files.

Two levels, don't confuse them. *Inside* one loop pass, the writes are coupled and
stay sequential in one tree. *Between* loop passes — several features, several
stories, unrelated work — each pass is a **track** and gets its own worktree.

## One slug, one spelling

The slug is a function of the entry artifact's path (`/loop:research`, the only
copy). Phase 0.5 applies the rule itself because it names the worktree and the
branch before Phase 1 has run. A second spelling means `/loop:plan` silently reads
no research at all, and a worktree nobody can match to a `docs/work/` folder.

## Taking the entry is the anti-collision

`/loop:tracks` reads a story's `Status` to decide what may fork right now, and
`/loop:ship` reads the board to name the next feature. Leave them on `Approved` /
`READY` and the work in progress reads as available: two sessions on one story,
or `/loop:ship` naming the story it just built as the next one. `/bmad:dev` does
the same (`Status` → `InProgress` at its step 2).

**What you take, you give back.** `IN LOOP` asserts that a session holds the work
right now; only `/loop:ship` step 5 clears it by shipping. Any other exit — a gate
that cannot go green today, a track abandoned, a product question sent back, a
session that simply ends — moves the line to `BLOCKED` with its reason and puts
the story's `Status` back to `Approved`. Skip that and the board claims a session
is on it forever: `/loop:tracks` will not fork it and `/loop:ship` will not name it,
so the unit disappears from the loop while looking healthy.

A line added to the board goes **at the end**: row order is the priority
`/loop:ship` reads, and a line that jumps the queue because a session happened to
open it is a priority nobody set.

## Every entry carries the profile line

`/loop:spec` and `/bmad:pm` decide it at their interview, where the triggers of
`critical` are known, and `/bmad:sm` copies it onto every story. Reaching the
default on a spec or a story means the line is missing — say so rather than
silently shipping `economy`, because `/loop:ship` step 1bis arms its security
audit on this value and nothing downstream can re-derive it.

## RESEARCH is never skipped

Reading a file in this conversation is not research: it tells you what the code
says, not what a later migration redefined, nor who consumes the symbol, nor what
the rows actually contain.

## Track isolation

Shared foundations are not a reason to fork more finely: they are done first, in
the main tree, committed, and the tracks fork from that commit. A loop pass is
never an `isolation: "worktree"` subagent: the loop has human gates, and a
subagent cannot hold them. Several tracks in flight means several sessions.

## Two human gates, two questions

INTERFACE fixes **what the screen is**; PLAN fixes **what "correct" means for the
logic**. Skipping the first and letting `/loop:review` enforce `design.md` anyway
means enforcing a choice nobody made. The plan gate is the most load-bearing one:
`typecheck`, `lint`, `test:run` and `build` are automatable because they verify a
property; "does this case describe the business rule" only verifies against the
user's intent. Every other gate judges code that exists; this one judges the
target, and the go freezes those test files.

## Codex in EXECUTE and review fixes

"Codex available" means `codex --version` succeeds, not `command -v codex`: with
npm's `optionalDependencies`, the launcher can be on `PATH` and crash on first
use because the native binary never installed (measured 2026-09-17: all six
`@openai/codex-<platform>` deps `UNMET`, `command -v` green).

`--auto` runs `codex -a never exec` (the flag must precede `exec`) inside
`-s workspace-write`: writes stay in the project, only the per-step approval pause
is skipped, never the sandbox. It is the default, not re-asked per feature:
`provider: codex` in the routing file is that decision (proven end to end on
`eval-bourrage-contexte`, 2026-09-17). `-o` writes Codex's final message to
`docs/work/<slug>/codex-last-message.txt`.

The hand-off point is right after `repository` goes green: the RED→GREEN
alternation cannot be batched, so that is the earliest point where handing off
doesn't fight it, and it keeps one handoff per feature instead of one per layer.
RED legs have no Codex equivalent (tested, failed — `docs/RATIONALE.md`).

Codex stopping itself on a protected boundary is not a failure to route around:
`-a never` removes the approval block on ordinary writes, it does not make Codex
reckless about a boundary. Resolve its question with the user, like a
`test-writer` `Blocked on`.

## Why EXECUTE is inline, and the RED leg is not

The chain is coupled and a handoff costs more than the isolation gains. The RED
leg is the exception because in one context the assertions drift toward the
implementation about to be written, and the suite ends up confirming the code
instead of the requirement. Never batch the three REDs then the three GREENs: an
implementation written against a dozen red assertions at once cannot be judged
"just enough", and a wrong assertion surfaces only after the freeze.

One `test-writer` is launched per feature and continued with `SendMessage` at
each layer, so its prefix is written to cache once. Accepted risk: the context it
keeps carries contracts inferred from earlier layers, which one launch per layer
partly avoided. If the final measurement shows no cache gain, go back to one
launch per layer.

`errors.ts` and `gateway.ts` come before the first RED because the repository
imports them: written later, its RED fails on a missing gateway rather than on
the behaviour, `tdd-prove-red.sh` classes that `unresolved-other` and records no
marker, which then blocks the module it was meant to unlock.

## Parallel lots and hooks

Lots fork as agents in the track's tree, never as extra worktrees: they share
types, contracts and one test suite, and merging them costs more than the wait.
`enforce-architecture` blocks cross-feature imports, shared code depending on a
feature and the data client outside its layer. What it does not cover — business
logic in components, `as` casts, an oversized file — is the `reviewer`'s job, and
`eslint` during EXECUTE is informational: the lint gate is `pnpm lint` at ship.

## Review hands over `Vigilance`, not `Traps`

The plan's `Vigilance` section restates research's traps as checks against this
diff ("object redefined by migration X" becomes "does the diff revert X?"). Going
back to the raw `Traps` throws that restatement away.
