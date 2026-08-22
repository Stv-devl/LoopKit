---
description: PLAN step — merge research + design into an executable plan with an explicit parallelisation map
argument-hint: [path docs/work/<slug>/research.md or design.md]
---

# /plan — the write order, decided once and written down

Third step of the loop. You merge the entry artifact + research + design (+ the
architecture, in the full pipeline) into **one executable plan**. This is where
the technical context finally lands on the story: the stories were written
functional on purpose, `/plan` injects the paths, contracts and pitfalls at the
moment they are freshest.

You **do not write code here**.

## Process

1. Read, in this order: `docs/work/<slug>/research.md`, `docs/work/<slug>/design.md`
   (if it exists), the entry artifact (spec or story), and
   `docs/architecture/<feature>.md` if the full pipeline produced one.

   > **Two slugs, and they are not the same string.** `<slug>` above is the
   > **loop** slug, and for a story it carries the story number:
   > `docs/stories/inbox/1.2.md` → `inbox-1.2` (`/research`, "The slug", the only
   > copy of the rule). The architecture is written **once per PRD**, so its file
   > is `docs/architecture/inbox.md` — the loop slug without its `-<epic>.<story>`
   > suffix. Look it up under the loop slug and you find nothing, and this step
   > plans the story **without its architecture, silently**. Same failure the loop
   > already guards for the research folder, one directory over.

   > From `design.md`, two columns are **obligations on this step**, not
   > decoration. `To build first?` marks a primitive the design system declares
   > but nobody has coded: it goes into the write chain **before** the screen that
   > consumes it, or that screen is planned against a component that does not
   > exist. `New?` marks a primitive being invented — check it was argued against
   > `docs/design-system.md` before you schedule it.
2. Build the **dependency graph**: DB → backend → front → wiring → tests. The
   test-first layers carry their tests *inside* their chain, not at the end, and
   each one is walked RED→GREEN before the next one starts — see the write chain
   below.

   > **Which layers those are depends on the repo, and there may be two sets.**
   > Front: `utils`, `mapper`, `repository`/`services` (`05-testing.md`).
   > Backend, when this repo carries the FastAPI addon: `app/services/**`
   > (`07-backend.md`) — a *separate* cycle, its own hooks, its own runner, and
   > `tests/` mirrors `app/` so the test path is derivable from the module path.
   > A plan that schedules the front legs and leaves the backend service as a
   > plain "write the service" line sends EXECUTE into a hook that will deny the
   > module: the RED was never scheduled, so it was never proved.

   > **`errors.ts` and `gateway.ts` are written before the first RED**, right
   > after the schemas. They are test-after layers (`.claude/rules/05-testing.md`)
   > but they are **imported by** the repository, so its test file cannot resolve
   > without them — the RED leg would then fail on a missing gateway instead of on
   > the behaviour it names, and `tdd-prove-red.sh` refuses that as
   > `unresolved-other`. Writing them early costs nothing: their own tests still
   > come later, in step 5.
3. Decide and **announce in one line each**:
   - what is **SKIP** (e.g. "Backend: NONE per the spec")
   - the **sequential write chain** (who writes what the next one reads)
   - the **parallelisable lots**: branches that write disjoint files. Two lots are
     parallel only if no file appears in both. Lots fork as agents in **this**
     tree — a lot never gets its own worktree (`.claude/guides/10-worktrees.md`).
   - the **shared foundations** this feature touches (migrations, `src/lib/*`,
     `shared/*`, router, providers, lockfile). They are what forbids another
     feature from running beside this one in parallel — name them, they are the
     input of the worktree decision.
4. **Write** `docs/work/<slug>/plan.md`. Take `<slug>` from the path you were
   handed — `/research` already recorded it by creating that folder, so reading it
   off the path cannot disagree with it. Deriving it again from the entry artifact
   would.
5. **If the entry artifact is a story**, fill its `## Plan` section with a
   condensed version (files, contracts, pitfalls) and a link to the full plan.
   This is where the architecture context finally lands on the story — the reason
   `/bmad:sm` deliberately left it empty. Skip for a `/spec` entry (the spec has
   no such section).
6. **TEST PLAN GATE — stop and ask the user.** Print the `Test plan` section in
   full and wait for an explicit go.

   **First, clear research's `Open questions`.** That section holds what no probe
   could settle, and this gate is the last moment it is free to settle them: after
   the go, those cases are frozen. Print each open question with what would settle
   it, and either answer it from the work done since, or put it to the user
   alongside the three questions below. An open question carried past this point
   silently becomes an assumption baked into a frozen test — which is exactly the
   failure this gate exists to prevent. If research left none, say so in one line.

   **And if this plan corrects a defect** — a bug report, a `/review` finding, a
   regression — check that the `Test plan` opens with the case that **reproduces
   it**, at whatever layer the defect lives, component included
   (`.claude/rules/05-testing.md`, "A bugfix opens with the test that reproduces
   the bug"). If it is missing, add it before printing: it is not an edge case
   appended at the end, it is the first case, and the bug report is its
   specification. A fix planned without it is a fix nobody can prove — and if the
   file is already frozen, the case is a pure insertion, so nothing about the
   freeze excuses its absence. Say in one line which case reproduces the defect,
   or say the plan corrects nothing.

   Then ask exactly three questions:
   1. Is this the right definition of "correct"? A missing case here becomes a
      bug that passes every downstream gate.
   2. Is the order right — core business behaviour before edge cases?
   3. Is any case simply wrong?

   This is the **last moment where fixing is free**: after the go, those files are
   frozen (`.claude/rules/05-testing.md`) and the implementation is written
   against them. Amend the plan from the answer, then continue. Do not start
   EXECUTE on silence.

7. **Stop.** Suggest `/orchestrate docs/work/<slug>/plan.md` (which executes,
   reviews and ships), or execute inline if the caller already asked for it.

## Template `docs/work/<slug>/plan.md`

```markdown
# Plan: <feature>   (entry: <path> · research: <path> · design: <path|n/a>)
Token profile: economy | standard | critical

## Skips
- <step> : SKIP — <why>

## Write chain (sequential)
1. DB — <migration via /database:migration, objects touched> | SKIP
2. Backend — models → schemas → **[services RED→GREEN]** → api routes →
   registration | SKIP
   <The RED→GREEN leg is there only if this repo carries a backend whose service
   layer is test-first — with the FastAPI addon it is `app/services/**`
   (`.claude/rules/07-backend.md`). On a backend without that cycle, drop the
   brackets and say so: "test-after, per <rule>".>
3. Front — types → schemas → **errors → gateway** → then one layer at a time,
   never batched:
   **[utils RED→GREEN]** → **[mapper RED→GREEN]** → **[repository RED→GREEN]**
   → hooks → store → components → forms
4. Wiring — routes, guards, providers
5. Tests — <the test-after layers: hooks, gateway if needed, UI if any>
6. Refactor — <clean the logic under a green suite, no test edited>

## Parallel lots (inside this track, same tree)
| Lot | Files owned | Depends on |
| --- | --- | --- |
<disjoint file sets only. If nothing is disjoint, write "none — fully sequential".>

## Track isolation
- Worktree: <`.claude/worktrees/<slug>` on `feat/<slug>` — because N tracks in flight | none, single track>
- Shared foundations touched: <migrations / src/lib / shared / router / lockfile / none>
  <If any: no other feature runs in parallel with this one until they are merged.>

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |

## Contracts
<repository signatures returning Result<T>, query keys, routes, Zod types,
backend request/response shape>

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — front: `utils.ts`, `mapper.ts`, `repository.ts`/`services.ts`
###              backend (if the addon is installed): `tests/services/test_*.py`
<One block per test file. Inside each block, ordered: main business behaviour
first, business rules next, edge cases last. Every case is a sentence that could
be the case name verbatim — an `it()` on the front, a `def test_…` on the
backend. Every `Result<T>` has both branches; every backend service that takes an
isolation key has its cross-tenant case, because nothing else enforces isolation
and the file freezes after this gate.>

<If this plan corrects a defect, the **Reproduction** block below is mandatory and
comes first — in the block of whatever file owns the defect, test-first or
test-after. One case, phrased as the bug: it must fail on the current code.
Delete the block when the work introduces new behaviour only.>

#### <path/to/x.repository.test.ts>
**Reproduction** <only when this plan fixes something>
- [ ] <the case that fails on the pre-fix code>
**Core behaviour**
- [ ] <case>
**Business rules**
- [ ] <case>
**Edge cases**
- [ ] <case>

### Test-after — hooks, gateway, UI
<*.test.ts(x) files + the cases that must exist. A defect living here gets its
**Reproduction** case too — no hook proves it, which is why it is planned.>

<Business logic without a test = FAIL, cf. .claude/rules/05-testing.md>

## Vigilance (carried from research)
- <each trap from research.md, restated as something the review must check>

## Acceptance criteria (carried from the entry artifact)
- [ ] <verbatim, they are the final gate>
```

## Rules

- The plan must be executable by someone who never read this conversation.
- **No parallel lot that shares a file.** When in doubt, sequential — a merge
  conflict inside a feature costs more than the wait.
- A worktree isolates a **track** (this whole plan), never a lot. Declaring one
  is `/orchestrate`'s Phase 0.5 call; the plan only records it.
- No manual SQL: any migration goes through `/database:migration`.
- Copy the acceptance criteria **verbatim**; do not rephrase them softer.
- The test plan's **test-first** block is the deliverable the user actually
  validates. Write its cases as `it()` sentences, ordered business-value first —
  not as a list of filenames. It is the spec the implementation is generated
  against (`.claude/rules/05-testing.md`).

## Task: $ARGUMENTS
