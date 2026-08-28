# Stack — rationale

Read when changing `.claude/rules/01-stack.md`, or when deciding whether to bump
a pinned version. Not loaded at session start.

## Why the settled-facts ledger exists

External documentation research is the most expensive modality of `/loop:research`.
Measured on one bootstrap: **7 agents, 178 network round-trips, 2 h of agent time
in one parallel fan-out** — 43 min of wall-clock, and six of the seven agents
establishing the same versions.

Almost all of it is stack-level and permanent: how a pinned version behaves does
not change between two features, so paying for it twice is paying for nothing.
Hence the ledger, and hence the discipline of writing the row **in the same
pass** — deferred, it never happens and the next feature pays the fetch again.

**Why the ledger is cold, and the rule only points at it.** It grows without
bound: 30 rows today, and the rule is that a settled question is never
re-researched, so it never shrinks except when a version dies. Kept inside
`01-stack.md` it was ~2 300 tokens re-read by every session and every subagent,
to be consulted by exactly two readers — `/loop:research` and `doc-researcher` — both
of which name the file explicitly at the moment they need it. That is the
textbook case for moving a whole section out. It also removed a silent failure:
`addons/supabase/` **replaces** `.claude/rules/01-stack.md` on install, and used
to delete every settled answer with it. Nothing touches `docs/`.

## TypeScript 7

TS 7 is the Go rewrite, GA July 2026. Its GA is behind us, so the two blocking
conditions are **checkable rather than forecast**:

1. a stable programmatic API (expected in TS 7.1);
2. `typescript-eslint` widening its peer range past `<6.1.0`.

When one settles, the outcome becomes a row in `docs/research-cache/settled.md`
rather than a paragraph to re-read here.

## Why the compiler bail-out is treated as a risk, not a detail

A green build says nothing about whether a component is actually memoized. The
compiler skips silently, so the failure mode is a team that believes it has
build-time memoization across the app and has it on 80% of it, with no way to
tell which 80%. `pnpm lint` naming the bail-out is the only observable, which is
why the gate is `--max-warnings=0` and why raising that number to silence one
rule is forbidden rather than discouraged.

Adding manual memoization to "help" the compiler is the reflex this produces, and
`03-conventions.md` refuses it: find out *why* it skipped instead.
