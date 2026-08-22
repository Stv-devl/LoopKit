---
description: Runs the whole feature loop — research → interface → plan → execute → review → ship. Each step is also callable alone.
argument-hint: [--economy|--standard|--critical] [path: spec, story, research/design/plan artifact]
---

# /orchestrate — the feature loop, end to end

You receive an **entry artifact** and drive it to shipped:

```
RESEARCH → INTERFACE → PLAN → EXECUTE → REVIEW → SHIP → next feature
```

Both pipelines converge here: a `/spec` contract (light) and a reviewed story
(full) enter the same loop. **You decide** what to skip, sequence or parallelise
from the real dependencies — not from a frozen script.

> Parallelisation principle: parallelise what **reads** the same thing without
> depending on each other (research, interface, review). Sequence what **writes**
> what the next step reads (execute). Never run subagents writing concurrently on
> coupled files.
>
> **Two levels, don't confuse them.** *Inside* one loop pass, the writes are
> coupled and stay sequential in one tree. *Between* loop passes — several
> features, several stories, unrelated work — each pass is a **track** and gets
> its own worktree. See Phase 0.5.

The loop's artifacts live in `docs/work/<slug>/`. The slug is **derived from the
entry artifact's path** by the two-line rule in `/research` — the only copy.
`/research` is where it gets **recorded** (it creates the folder), and every phase
after that reads it out of the path it was handed rather than re-deriving it.

**Phase 0.5 is the one exception, and it is not optional**: it names the worktree
and the branch before Phase 1 has run, so it applies the derivation rule itself.
Same rule, same spelling — that is the whole point of the rule being a function of
the path. A second spelling means `/plan` silently reads no research at all, and a
worktree nobody can match to a `docs/work/` folder.


## Token profile

Select once in Phase 0 and persist it as `Token profile: <value>` in every
`docs/work/<slug>/` artifact so a fresh session or Codex handoff keeps it.

- `economy` — default: grouped probes/reviews, main-thread synthesis, bounded E2E.
- `standard` — more independent checks for ambiguous cross-surface work.
- `critical` — maximum separation, for the cases `11-token-budget.md` reserves
  `critical` for — that list is the only copy.

A downstream command inherits the artifact profile. It must not silently upgrade
the profile. Mechanical shell gates do not consume model fan-out and always run.

## Automatic checkpoints

Maintain `docs/work/<slug>/handoff-codex.md` inline, without a subagent:

- create it once research has recorded the slug (i.e. once `docs/work/<slug>/`
  exists — before that there is no folder to put it in, even though the slug
  itself is already known from the entry path);
- refresh it after interface, plan, each completed RED→GREEN layer, review fixes,
  and ship gates;
- store only current phase, completed/in-progress/remaining work, changed paths,
  decisions/traps, and last deterministic results;
- link to source artifacts instead of copying their bodies.

Before launching any agent, check `.claude/.token-stop-agents`. If present,
launch no new agent: finish the current atomic write/test, refresh the checkpoint,
and yield. When `.claude/.codex-ready` exists, do not start another phase. The
external `workflow.sh` supervisor will stop Claude and continue with Codex.

---

## Phase 0 — Read & decide

1. Parse an optional token-profile flag, defaulting to `economy`; if the entry
   already carries a profile, inherit it unless the user explicitly overrides.
   Read the entry artifact in full. If it is a `plan.md`, jump to Phase 4.

   > **Every entry artifact carries the line**, not only a resumed `plan.md`:
   > `/spec` and `/bmad:pm` decide it at their interview, where the four triggers
   > of `critical` are known, and `/bmad:sm` copies it onto every story. Reaching
   > the default here on a spec or a story means the line is missing — say so
   > rather than silently shipping `economy`, because `/ship` step 1bis arms its
   > security audit on this value and nothing downstream can re-derive it.
2. **FEATURE READY check** — if `docs/product/backlog.md` exists, the entry must
   be a `READY` line. Not listed → add the line **as `READY`**, at the end of the
   table, `Entry artifact` = the path you were handed and `Pipeline` = `light` for
   a spec / `full` for a story, and say so: the artifact exists and you just read
   it in full, which is exactly what the state means (2bis then moves it, under
   the same main-tree rule). At the end, never inserted: the row order is the
   priority `/ship` reads, and a line that jumps the queue because a session
   happened to open it is a priority nobody set. Listed as
   `DRAFT` → stop and ask: a feature that hasn't been framed isn't ready to build.
   That state is `/product`'s — it is what that command writes for a feature it
   merely noticed — and it is the only thing this gate can refuse. Listed as
   `BLOCKED` → say so and take it back: the line is one somebody put down on
   purpose, so name the reason it carries before moving it, and stop if that
   reason is still open. `DROPPED` or `SHIPPED` → stop: those two are terminal,
   and building on one of them means someone handed you the wrong artifact.
   No board at all → skip this check in one line (the light path doesn't require one).
   Columns, states and transitions: `/product`, "The board's state machine" — the
   only copy.
2bis. **Take the entry** — mark it in flight and say so in one line:
   - the entry is a **story** → `Status` to `InProgress`. Always: the story file
     belongs to this track and to no other.
   - the board line → `IN LOOP`, **only if this session is in the main tree**. A
     worktree must never write `docs/product/backlog.md`
     (`.claude/guides/10-worktrees.md`, "Never in a worktree" — one file, every
     track, a conflict at every merge). Inside one, say so in one line and leave
     the board alone: `Status` is the authority `/tracks` reads, and `/ship` moves
     the line at step 5, after the merge, from the main tree.

   > **This is not bookkeeping, it is the anti-collision.** `/tracks` reads
   > `Status` to decide what may fork right now, and `/ship` reads the board to
   > name the next feature. Leave them on `Approved` / `READY` and the work you
   > are doing reads as available: two sessions on one story, or `/ship` naming
   > the story it just built as the next one. The `/bmad:dev` path already does
   > this (`Status` → `InProgress` at step 2) — this line is what makes the
   > one-shot path keep the same promise.

   > **What you take, you give back.** `IN LOOP` asserts that a session holds the
   > work *right now*; only `/ship` step 5 clears it by shipping. Any other exit —
   > a gate you cannot make green today, a track abandoned, a product question
   > sent back to the user, a session that simply ends the pass — moves the line
   > to **`BLOCKED`** with the reason in one line, from the main tree, and puts
   > the story's `Status` back to `Approved` — no session holds it any more, and
   > that field says exactly that. The **board line**, not `Status`, is what
   > records that it is on hold; `/tracks` reads both, and drops a `BLOCKED` line
   > from its candidates. Skip that and the board claims a session is on it
   > forever: `/tracks` will not fork it and `/ship` will not name it, so the unit
   > disappears from the loop while looking perfectly healthy. That is the failure
   > mode this state exists for.
3. Announce in one line each: which phases are **SKIP** and why.
   - No user surface (migration, scheduled job, backend-only, refactor) → **INTERFACE SKIP**
   - RESEARCH is **never** skipped. Reading a file in this conversation is not
     research: it tells you what the code says, not what a later migration
     redefined, nor who consumes the symbol, nor what the rows actually contain.

## Phase 0.5 — Track isolation (worktree or not)

Decide **once**, announce in one line, then never revisit mid-loop.

**Fork a worktree only if all of these hold** (`.claude/guides/10-worktrees.md` is
the authority — read it before forking):

1. this pass is **not the only one in flight** — the user is advancing several
   features / stories / distinct pieces of work, or asked for this one in the
   background;
2. the file sets are disjoint (architecture story map, or the other pass's
   `plan.md` `Files` table);
3. neither touches a **shared foundation** — migrations & DB, `src/lib/*`,
   `shared/*`, router, providers, composition root, design system, backlog,
   lockfile;
4. clean tree, known base branch.

When several passes qualify, **how many fork is computed, not assumed**, and
**three is the ceiling**. In a story pipeline, `/tracks` does it and prepares the
worktrees; standalone, run the four steps of `10-worktrees.md`, "How many
tracks", yourself and announce the number with the named set. One session drives
one worktree: N tracks means N sessions.

**How** (the table in `10-worktrees.md` is the reference). `<slug>` here is the
**loop slug of this pass**, derived from the entry artifact by `/research`'s rule
— `docs/stories/inbox/1.2.md` gives `inbox-1.2`, never `inbox`. Forking a story
under its feature's name puts every story of that feature on one branch:

- this session drives the track → `EnterWorktree` with `name: "<slug>"`;
- another session will drive it → create it without moving:
  `git worktree add .claude/worktrees/<slug> -b feat/<slug>`, then hand over the
  path and the branch.

Then run every phase below **inside that worktree**, and say so in the opening
line. Otherwise: main tree, one line — "single track, no worktree".

> Shared foundations are **not** a reason to fork more finely: they are done
> first, in the main tree, committed, and the tracks fork from that commit.
> The worktree is empty of `node_modules`, and `.env*` cannot be copied by an
> agent (`protect-files`) — announce both costs when you fork, ask the user for
> the env file.
>
> A loop pass is **never** an `isolation: "worktree"` subagent: the loop has human
> gates, and a subagent cannot hold them. Several tracks truly in flight means
> several sessions — one per worktree. Create the sibling, name it, hand it over.

## Phase 1 — RESEARCH (parallel)

Run `/research <entry artifact>` → `docs/work/<slug>/research.md`.
Multi-modal fan-out: code pattern, wiring, reuse, blast radius, live DB state,
external API contract. Barrier: the file exists before designing.

**Retain the `Traps` section** — Phase 3 restates it as the plan's `Vigilance`,
and that restatement is what Phase 5 hands the reviewers.

## Phase 2 — INTERFACE (parallel, skippable)

Run `/interface docs/work/<slug>/research.md` → `docs/work/<slug>/design.md`.
Competing proposals, judged into one — **how many is the token profile's call,
declared in `/interface`, not here**. On the default (`economy`) that is one
designer producing two concise alternatives, judged on the main thread with no
judge agent; three angles plus a separate judge is the `critical` arity. Skip
announced in Phase 0 if there's no UI.

**The retained proposal is rendered before the gate**, on an editable canvas
published as an Artifact — Claude Code's built-in `/design`, invoked from the main
thread. Arity and fallback are `/interface`'s call, not this file's; what matters
here is that the extra main-thread context is the canvas, not the agents.

**This phase ends on a human gate too.** `/interface` presents the options and waits
for the user to pick — retained as proposed, edited on the canvas, or grafted —
same shape as `/design-system`, capped at 3 rounds. Do not enter Phase 3 on
silence. A canvas edited **after** the gate reopens the gate: `design.md` is what
Phase 5 reviews against, and it does not follow the canvas on its own.

> Two gates, two different questions, and neither substitutes for the other: this
> one fixes **what the screen is**, Phase 3's fixes **what "correct" means for the
> logic**. Skipping this one and letting `/review` enforce `design.md` anyway
> means enforcing a choice nobody made.

## Phase 3 — PLAN

Run `/plan …` → `docs/work/<slug>/plan.md`: write chain, parallel lots, files,
contracts, test plan, acceptance criteria carried verbatim.

**This phase ends on a human gate, and it is the loop's most load-bearing one.**
`/plan` prints its `Test plan` and waits for the user's explicit go. What is
being validated is the definition of "correct" for the three test-first layers,
**before any implementation exists** — the last point where changing it is free,
since the go freezes those files (`.claude/rules/05-testing.md`).

> Why here and nowhere else: `typecheck`, `lint`, `test:run` and `build` are
> automatable because they verify a property. "Does this case actually describe
> the business rule" only verifies against the user's intent. Every other gate in
> this loop judges code that already exists; this one judges the target.

Do not enter Phase 4 on silence.

## Phase 4 — EXECUTE (sequential, inline on the main thread)

Implement **yourself**, in the plan's order. Do not delegate: the chain is
coupled and the handoff costs more than the isolation gains. **One exception, the
RED legs** — see below.

```
1. DB       → /database:migration        (schema + authorization + triggers)
2. Backend  → handlers, if the plan asks for one
3. Front    → types → schemas → errors → gateway
              then ONE LAYER AT A TIME, in dependency order:
              ├─ utils        RED → GREEN
              ├─ mapper       RED → GREEN
              ├─ repository   RED → GREEN
              └─ then  : hooks → store → components → forms
4. Wiring   → router + guards
5. Tests    → hooks.ts + the rest of the test plan (gateway, UI) — MANDATORY
6. REFACTOR → clean the logic with the suite green. No new behaviour, no test
              edited. This is the third leg of the cycle, not an optional tidy-up.
```

For each test-first layer the plan actually has:

- **RED** — launch one `Agent` (subagent_type: `test-writer`), giving it its test
  file path, the plan path and its layer. It writes that one file, runs it, and
  returns the failure output. It is forbidden from reading the module under test:
  in a single context the assertions drift toward the implementation you are
  about to write, and the suite ends up confirming the code instead of the
  requirement. If it comes back `Blocked on` a contract ambiguity, resolve it
  with the user — do not resolve it by writing the test yourself.
- **GREEN** — you, inline: just enough code in that one module to pass. The test
  does not move.

Then the next layer. **Never batch the three REDs then the three GREENs**: an
implementation generated against a dozen simultaneous red assertions cannot be
judged "just enough", and a wrong assertion surfaces only after the freeze
(`.claude/rules/05-testing.md`).

> **Why `errors.ts` and `gateway.ts` come before the first RED.** They are
> test-after layers, but the repository **imports** them (`templates/feature.md`),
> so its test file cannot resolve without them. Written later, the repository's
> RED leg fails on a missing gateway rather than on the behaviour it names — and
> `tdd-prove-red.sh` classes that as `unresolved-other` and records **no marker**,
> which then blocks the module it was supposed to unlock. Write them right after
> the schemas; their own tests still come in step 5.

Load what you need from `.claude/skills/patterns/` and `templates/`. Respect
`.claude/rules/`.

> **Both cycles, one procedure.** The hook names below are the TypeScript ones.
> On a backend service layer that is test-first (`app/services/**` with the
> FastAPI addon) the same three roles are played by `tdd-prove-red-py.py`,
> `tdd-require-red-py.py` and `tdd-freeze-tests-py.py`, against `python -m
> pytest`. Same markers, same `.claude/.tdd-unfrozen`, same verdicts — read
> `.claude/rules/07-backend.md` for what differs, and hand the `test-writer` the
> `.py` path: it reads the runtime off the path it was given.
>
> **The RED phase is proved, not declared, and it blocks.** `tdd-prove-red.sh`
> runs the test file that was just written and judges the run against the symbols
> the test exercises — a pass while the named behaviour does not exist is
> reported as asserting nothing, even when the module file already exists. On a
> genuine red it leaves a marker, and `tdd-require-red.sh` **denies the creation**
> of the implementation module until that marker exists. If you are denied, the
> answer is never to work around it: the test came after the code, or it never
> failed.
>
> One benign case of that denial: the `test-writer` reported a real red but no
> marker landed (the hook did not fire in its context). Re-save the test file
> **byte for byte identical** — the freeze lets an unchanged re-save through for
> exactly this — and read the verdict yourself. Anything other than
> `RED confirmed` means the red was not real and the denial was right.
>
> Once green, `tdd-freeze-tests.sh` holds the other side. **Adding** a case to a
> frozen file is allowed as a pure insertion — say which behaviour it covers and
> why the plan missed it. **Correcting** one is denied: list the path in
> `.claude/.tdd-unfrozen` with a reason, visibly, after telling the user.
>
> Scope is `utils` / `mapper` / `repository`-`services` only
> (`.claude/rules/05-testing.md`). Hooks, gateway and UI are written first and
> tested after, as before — their contract is still moving at this point.

> **Parallelism exception**: only the plan's **parallel lots** may fork, and only
> if their file sets are disjoint. Two lots touching the same file stay sequential.
> Lots fork as agents **in this track's tree** — never as extra worktrees: they
> share types, contracts and one test suite, and merging them costs more than the
> wait. The worktree boundary is the track (Phase 0.5), not the lot.
> The guardrail hooks (`no-any`, `protect-files`, `format`, `eslint`,
> `enforce-architecture`) fire on every write. `enforce-architecture` blocks
> cross-feature imports, shared code depending on a feature, and the data client
> outside the data layer / composition root. What it deliberately does **not**
> cover — business logic in components, `as` casts, an over-threshold file — is
> the `reviewer` agent's job, and `eslint` here is only informational: the real
> lint gate is `pnpm lint` in `/ship`.

## Phase 5 — REVIEW (parallel, two stages)

Run `/review docs/work/<slug>/plan.md`. On a UI feature it opens with a
**visual pass on the main thread**, then groups review dimensions and verifier
batches according to the token profile. Pass it the plan's **`Vigilance`**
section — research's traps already restated as things checkable against this
diff: "object redefined by migration X" became the criterion "does the diff
revert X?". That restatement is what `/plan` was asked to produce; going back to
the raw `Traps` throws it away.

Fix surviving Critical/Major findings **inline**, then re-run only the affected
dimensions.

## Phase 6 — SHIP

Run `/ship docs/work/<slug>/plan.md`: parallel gates (`typecheck`, `lint`,
`test:run`, `test:coverage`, `build`, `audit`), acceptance criteria walked one by
one, commit via the `github` agent, board advanced, next feature named.

**On a `critical` profile it also runs one `/audit:security` surface** before the
commit (`/ship`, step 1bis) — the profile you resolved in Phase 0 is what arms
it, so a feature you upgraded for the review arity is a feature you also
committed to auditing. Zero cost on the other two profiles.

On a track that forked, the gates run **in its worktree** and the merge back is
`/ship`'s last, user-gated step — one track integrated at a time.

---

## Conclusion (mandatory)

Close with: criteria met, what was SKIP and why, what stays OUT, what needs
deploying, and the next feature. If the track forked: the branch, and whether it
is merged, awaiting your go-ahead, or still open.

## Task: $ARGUMENTS
