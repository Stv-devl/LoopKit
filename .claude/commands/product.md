---
description: Product brief — frames the product (vision, users, surfaces) and opens the backlog board
argument-hint: [product or chantier description]
---

# /product — the product frame, above the features

You write the layer **above** the PRD: what the product is, who it serves, what
already exists. Everything downstream (`/bmad:pm`, `/spec`) reads this instead of
re-discovering it every time.

Run this **once per product**, then refresh it when the surface shifts.
For a single feature, skip straight to `/bmad:pm` or `/spec`.

## Process

**Decide greenfield or not before step 1, and say it in one line.** Three steps
branch on it — the screens question below, the map at step 2, `Current surface`
and `Planned surfaces` at step 3 — so deciding it three times is deciding it
three ways. It is a fact about the repo, not a judgement: is there product code
in `src/features/` (or the backend equivalent) that a user can already reach?
A scaffolded repo with a component kit and no feature is greenfield.

1. **Interview — `AskUserQuestion`, one call, 4 questions max** (that is the
   tool's ceiling, not a style rule — a fifth question makes the call fail, and
   the retry drops one at random). Only what changes the frame: who uses it, what
   problem it kills, what is deliberately not this product, what "working" means.
   Propose defaults, don't drown the user.

   **On a greenfield product the screens question below is one of the four**, and
   it displaces whichever of the others you can most afford to infer — not the
   screens. `2bis` asks the two decision sections in its own call afterwards, so
   this call does not have to carry them.

   **On a product with no code, one of them is the first screens**, and it is not
   optional: *which two or three screens does someone have to see for this product
   to exist at all?* That answer is `Planned surfaces` (step 3), and `Planned
   surfaces` is the only section `/design-system --new` can read — it picks its two
   reference screens from it, and all three directions render the same pair. Ask it
   and the pair is a product decision; skip it and step 3 writes the section from
   an interview that never mentioned a screen, which is why `/design-system` had to
   grow a fallback that infers them from `Users & jobs`. That fallback is for a
   brief written before this rule existed, not for one you are writing now.

   On a product that already has code, do not ask: `Current surface` answers, and
   `Planned surfaces` is `n/a`.

   **Use the tool, not prose.** Every answer here ends up as a durable constraint,
   and the two decision sections are re-read by a gate on every future feature —
   `Product invariants` by `story-critic` **and** by `/review`'s `correctness`,
   `Out of product` by `story-critic` alone. A closed question gets a closed
   answer the user actually chose; the same question in a paragraph gets a
   sentence that sounds like agreement, and the constraint is invented at step 3
   instead. What genuinely has no options — "what problem does it kill" — stays
   open text, and that is the exception, not the format.

   **Neither section is gated on the light path before code exists.** `/spec`
   reads them (its step 2) and is the only thing between a contract and an
   invariant it contradicts; after that `/review`'s `correctness` catches an
   invariant broken by the diff, and nothing at all catches a spec that quietly
   builds what `Out of product` excludes. Write both so somebody who was not in
   this conversation can refuse something with them.
2. **Map the existing product once** — launch one `explorer` covering:
   shipped features, backend endpoints/jobs, and the main data surface. A second
   explorer is allowed only when the live database is a remote surface requiring
   distinct tooling. Reuse this shared context; never launch one agent per axis.
   Arity declared here, the rest per `.claude/rules/11-token-budget.md`.
   Barrier: wait for the map(s).

   **Skip this step entirely on a genuinely greenfield product** — say so in one
   line and go to **step 2bis**, never straight to step 3. There is nothing to
   map, and this is the likeliest entry for a product at zero: `/design-system
   --new` requires this brief before it can run at all. But 2bis is the only step
   that *chooses* the two enforced sections, and jumping it lands you at a step 3
   forbidden to compose them — so the brief ships with no invariants at all, on
   the one path where nobody was ever asked. With no map, 2bis draws its
   candidates from the interview alone; that is a shorter list, not a skipped one.
2bis. **Ask the invariants, closed, in their own `AskUserQuestion` call.** Step 1
   frames the product and step 2 shows what it already does; the hard limits no
   future feature may break are a *decision* on top of both, and they are the one
   thing in this file that is enforced without appeal. So they are chosen, never
   inferred.

   Propose 3-4 candidates drawn from the interview and the map — the domain's hard
   limits, the authorization barrier, the copy-language split, whatever the
   answers made visible — as one `multiSelect` question, and let the user add
   their own. Same call, one more question, for anything `Out of product` that
   step 1 left implicit. A candidate the user does not select is not an invariant:
   drop it, do not soften it into the brief.

   **This is what step 3 writes from.** Reaching step 3 with nothing selected
   means the sections are empty, and empty is a legitimate answer for a product
   at day one — an invented invariant is not.

   **On a refresh, the existing lines are pre-selected and the question is what to
   add.** Carrying them over unchanged is step 3's default and the user does not
   have to re-earn them; what this call is for is the invariant the last six
   months made obvious, and the one the user now wants dropped. An invariant
   removed is a real product decision — say what it was protecting.
3. **Write `docs/product/brief.md`.** On a refresh, rewrite `Current surface`
   from the map you just gathered, and **carry `Out of product` and `Product
   invariants` over unchanged** unless the user says otherwise: those two are
   decisions, not observations, and re-deriving them from the code loses them.
   On a greenfield product, `Current surface` is "none yet" and `Planned surfaces`
   holds the screens named at step 1, one line each — that section is what
   `/design-system --new` renders, and it is the only one it can read here. Reaching
   this step with nothing to write in it means the question was skipped: go back and
   ask it rather than inventing screens the user never named.

   **`Out of product` and `Product invariants` are transcribed from step 2bis, not
   composed here.** Write each selected answer as a sentence a reviewer can hold a
   diff against; what you may add on your own is precision of wording, never a
   line the user did not choose.
3bis. **Read the two decision sections back, and wait.** Print `Out of product`
   and `Product invariants` as they now stand in the file, in a few lines, and ask
   the user to confirm or correct the **wording** — 2bis chose them, this checks
   that what landed on disk says what they meant. Nothing else in this file
   carries that weight: `story-critic` escalates a violated invariant as a
   Critical it is *forbidden* to soften and an `Out of product` crossing as a
   Major it may not resolve either, `/review`'s `correctness` replays the same
   invariants against the code, and `/bmad:pm` may not write a PRD that
   contradicts them.

   **A correction is applied to the file before you go on**, and a section the
   user strikes is emptied rather than kept "for reference": an unconfirmed line
   in either of these two sections constrains every future feature exactly as hard
   as a confirmed one. Only once they hold do you open the board — a board line
   written under a frame the user has not agreed to is a unit queued against the
   wrong product.
4. **Open `docs/product/backlog.md` — only if it does not exist.** If it does,
   **never rewrite it**: read it, add a line for anything genuinely missing, and
   report what you added. That file is written after you by `/spec`,
   `/stories:review`, `/orchestrate` and `/ship` — a `SHIPPED` history, the lines
   in flight, the state of the board. Regenerating it from the template is a
   silent data loss, and `/ship` says it in its own words: *a board that only
   records what it happened to know about is worse than none*.

   **You write `DRAFT`, and you are the only command that does** — but only for
   what the interview *named as wanted* and nothing has framed. `DRAFT` means
   "framed by nothing", and that is what makes the FEATURE READY gate able to
   refuse: `/spec` and `/stories:review` write `READY` because a contract or a
   reviewed slice exists behind their line. A board on which nothing is ever
   `DRAFT` is a journal, not a gate.

   **What step 2 found in the code is `SHIPPED`, not `DRAFT`.** The map reads the
   surface that is *already live*; writing it `DRAFT` would have the board declare
   unframed everything that is in production, and hand the FEATURE READY gate a
   refusal on work that is finished. `Shipped` takes `—` when you cannot date it
   — the state is what the gate reads, the date is history. `/ship` applies the
   same rule from the other end, for a feature that entered before the board
   existed.

   **On a refresh you may also write `DROPPED`**, for one case and only one: a
   line the user tells you, in this conversation, they no longer want. Move it and
   report it. Do not infer it from silence, from the age of the line or from the
   code — a `DRAFT` nobody has mentioned in six months is still a `DRAFT`, and
   guessing here is how a decision the user never took ends up in the history as
   one they did.

   **A dropped line that has a story file gets its `Status` in the same pass** —
   `Dropped`, with the reason in the Change Log. The board row alone is not
   enough: `/tracks` computes its candidates from `Status` and subtracts `BLOCKED`
   board lines, so a story left `Approved` is forked back the next time somebody
   asks what can run — which is the failure `/stories:review` spells out for its
   own drop.

   Every line you write follows the state machine below — its columns, its key,
   and its six states.
5. **Stop.** Suggest `/bmad:pm <first chantier>` (complex) or `/spec <feature>` (simple).

## Template `docs/product/brief.md`

```markdown
# Product: <name>

## What it is
<2-3 sentences: the product in one breath>

## Users & jobs
- <who> : <the job they hire the product for>

## Current surface (mapped <date>)
- Front: <features/* covered>
- Backend: <endpoints + scheduled jobs>
- Data: <main tables>

## Planned surfaces
<the first screens the product needs, one line each, as the user named them at
step 1's screens question. This is where `/design-system --new` picks the two
reference screens it renders in all three directions — a list/index screen and a
detail-or-form screen is the usual pair. "n/a" on a product that already has
code: `Current surface` answers instead.>

## Out of product
<what this product will never be — the durable anti scope-creep>

## Product invariants
<the rules no feature may break — the domain's hard limits, the authorization
barrier, the copy-language split…>
```

**`Product invariants` has two enforcers, and they do not overlap.**
`story-critic` checks that no **story** contradicts an invariant (Critical,
escalated to you — never fixed by softening the story); `/review`'s `correctness`
dimension checks the same invariants against the **code that was actually
written**, which is the only gate the `/spec` path ever meets. Write each
invariant so both can fail on it: a sentence a reviewer can hold a diff against,
not an intention.

**And this command is the only writer of either section.** `/ship` may refresh
`Current surface` after a feature; nothing anywhere may edit these two. So when a
gate escalates — `story-critic` through `/stories:review`, or `/spec` and
`/bmad:pm` on their own reading — the answer "then move the boundary" resolves to
one thing: a `/product` refresh, which comes back through 2bis and 3bis and asks
the user. That round trip is the point. A boundary moved inside the command that
was blocked by it is a boundary that moved itself.

**`Out of product` has one, and it sits earlier.** `story-critic` refuses a story
that delivers something this section excludes — **Major, escalated, never
resolved by rewriting the story to fit**, because the boundary may simply be
stale and only you move it. No reviewer replays it against the diff: past the
story gate, a feature building outside the product is scope creep, which
`/bmad:qa` catches against the story and nothing catches against the product. On
the `/spec` path it is read once, by `/spec` itself, at the moment the contract is
written. So a line here has to be refusable by somebody who was not in the
conversation that produced it: name what the product will not do, not what it
prefers.

## Template `docs/product/backlog.md`

```markdown
# Backlog

| Feature / story | Entry artifact | Pipeline | State | Shipped |
| --- | --- | --- | --- | --- |
| billing | docs/specs/billing.md | light | READY | — |
| checkout 1.1 — cart | docs/stories/checkout/1.1.md | full | IN LOOP | — |
| checkout 1.2 — payment | docs/stories/checkout/1.2.md | full | READY | — |
| invoice export | — | — | DRAFT | — |
| auth | — | — | SHIPPED | — |

States: DRAFT → READY → IN LOOP → SHIPPED, plus BLOCKED and DROPPED.
The state machine below is the only description of them.
`Shipped`: the date `/ship` moved the line, `YYYY-MM-DD`. `—` until then.
Order matters: among the `READY` lines, the topmost is the next one to build.
```

**One line per unit of loop**, not per feature: a spec is one line, and a full
pipeline puts **one line per story** — that is what `/stories:review` writes, and
what makes `/ship`'s "name the next `READY`" name the next *story* rather than a
feature whose stories it cannot see.

The board is the **FEATURE READY** gate: only a `READY` line may enter the loop.

**And the order of the rows is the priority**, top to bottom — the only place in
the kit where product priority is written down. `/ship` step 6 names the
**topmost** `READY` line, not "a" `READY` one: with five of them, "the next
feature" is otherwise whichever the reading happened to land on, and the decision
that should be yours gets taken by an accident of parsing.

Two rules keep it true, and they are cheap:

- **`/product` owns the order and is the only command that reorders.** Reordering
  is a product decision — say which lines moved and why, in the report.
- **Every other command appends at the end of the table and never inserts.** A
  line that changes state stays where it is: a `DRAFT` moved to `READY` by `/spec`
  keeps its rank, which is what makes the rank survive the framing. On the full
  pipeline, `/stories:review` replaces the feature's line with its per-story lines
  **at that same position, in id order** — the story order is a dependency order,
  and scattering it across the board loses it.

A board whose order means nothing is not wrong, it is just a set; say so once to
the user rather than letting `/ship` imply a priority nobody set.

## The board's state machine

**This block is the only copy.** `/spec`, `/stories:review`, `/orchestrate`,
`/bmad:dev`, `/ship` and `/tracks` all write or read this board; each of them
cites this section and none of them restates it. A second description of a state
is a second authority, and the board is the one artifact every track shares.

| Column | Rule |
| --- | --- |
| `Feature / story` | **the key of the line.** A command with something to say about a unit already listed **moves that line** — it never appends a second one. Match on this cell, never on `Entry artifact`: the artifact is exactly what changes when a `DRAFT` becomes a spec |
| `Entry artifact` | the path of the artifact that opens the loop, or `—` when none exists yet. A `DRAFT` line has none by construction — nothing has framed it. Whoever creates the artifact fills the cell, in the same pass as the state |
| `Pipeline` | `light` (a spec) or `full` (a story), `—` while unknown |
| `State` | one of the six below, and nothing else. `BLOCKED` **carries its reason in the cell**, after an em dash — `BLOCKED — waiting on the pricing decision`. It is the only state that needs one, and it has nowhere else to live: a reason kept in the session that put the line down is a reason nobody reads |
| `Shipped` | the date `/ship` moved the line, `YYYY-MM-DD`; `—` until then, and `—` on a surface that was already live when the board was opened |

| State | What it asserts | Written by |
| --- | --- | --- |
| `DRAFT` | noticed and wanted, framed by nothing — no spec, no reviewed slice | `/product`, and it alone |
| `READY` | a contract or a reviewed slice exists behind the line | `/spec` (light), `/stories:review` (full), and `/orchestrate` Phase 0 step 2 for the **one** case of an entry artifact that is on disk and on no line — it read it in full, which is what the state asserts |
| `IN LOOP` | a session holds it **right now** | `/orchestrate` 2bis, `/bmad:dev` step 2 |
| `BLOCKED` | it was taken and given back — abandoned, deprioritised, or waiting on a product answer | whoever stops the loop |
| `SHIPPED` | merged, or already live before the board existed | `/ship` step 5, `/product` step 4 |
| `DROPPED` | the unit was killed at a gate or by a product decision. Terminal, like `SHIPPED`: the id stays on the board so nobody re-proposes it, and so the history says it was decided rather than forgotten | `/stories:review` step 4 (the gate); `/product` step 4 and `/ship` step 6 (a decision the **user** just took, in front of them) |

`DRAFT → READY → IN LOOP → SHIPPED` is the nominal path. Two transitions exist
because the nominal one is not the only real one:

- **`DRAFT → READY` is a move, not an insertion.** `/product` opens the line the
  day the feature is named; `/spec` and `/stories:review` come back to it once a
  contract or a reviewed slice exists. Adding a second line instead leaves the
  `DRAFT` orphan on the board forever — it never becomes `SHIPPED`, and the gate
  keeps refusing a unit that has been ready for a month. On the full pipeline the
  granularity changes with the move: the feature's `DRAFT` line is **replaced** by
  one line per story, the story being the unit of loop (`/stories:review`, step 6).
  That is the one case where a line does not simply change state.
- **`IN LOOP → BLOCKED` is not optional.** A loop that stops without moving its
  line leaves the board claiming a session holds work nobody is doing — and that
  line *is* the anti-collision `/orchestrate` (2bis) and `/tracks` read. Whoever
  stops writes `BLOCKED` with the reason in one line: a failed gate nobody will
  resume today, an abandoned track, a product question sent back to the user.
  `BLOCKED → IN LOOP` when it is picked back up; the artifact and the pipeline
  do not change.

**Four of the six states have a twin in the story's `Status`** — `READY` ↔
`Approved`, `IN LOOP` ↔ `InProgress`/`Review`, `SHIPPED` ↔ `Done`, `DROPPED` ↔
`Dropped`. The first three are written together, by `/orchestrate` Phase 0 or by
`/bmad:dev`; the fourth is written by whoever drops the line — `/stories:review`
step 4, `/product` step 4, `/ship` step 6 — and **both halves or neither**: the
board row is what `/ship` reads, `Status` is what `/tracks` reads, and a story
dropped in one place only comes back through the other. The other two have none, for opposite reasons. `DRAFT` has no story file to carry a `Status` at all
— that is what the state means. `BLOCKED` has one and deliberately does not use
it: a story handed back goes to `Approved`, because no session holds it any more
and that is all `Status` can say. The hold lives on the board line alone, which
is why `/tracks` reads the `State` column as well and drops a `BLOCKED` candidate
its `Status` would otherwise call available.

**Two states are terminal and they are not interchangeable.** `SHIPPED` says the
unit was delivered; `DROPPED` says it was decided against, at `/stories:review`'s
gate or by the user. Deleting the line instead would make the two look like a
third thing — a unit nobody ever thought about — which is exactly what the board
exists to prevent. A `DROPPED` line keeps its id: ids are stable, and a freed id
gets reused by accident.

**A `DRAFT` or a `READY` line the user kills has two writers, and no third.**
`/stories:review` owns the gate's verdict; `/product` (on a refresh) and `/ship`
(step 6, when the user answers "not that one, and not later") write it for a
decision the user takes **in front of them, in that turn**. Nobody else, and never
inferred: a line nobody has asked about is not dropped, it is just old. Without
those two the light path had no exit at all — a killed spec could only be deleted,
which the paragraph above forbids, or left `READY`, where step 6 keeps proposing
it as the next feature.

`/ship` step 6 names the **topmost** `READY` and nothing else. `BLOCKED` is deliberately
not a candidate: it is a line waiting for a person, and proposing it as the next
feature would silently re-open a decision somebody took.

**The board is written from the main tree only** — one file, every track, a
conflict at every merge (`.claude/guides/10-worktrees.md`, "Never in a
worktree"). Inside a worktree, say so in one line and leave it alone: the story's
`Status` is the authority `/tracks` reads until `/ship` moves the line after the
merge.

## Rules

- Read-only investigation: write nothing but the two docs.
- Follow `.claude/rules/`. User messages in the user language declared by
  `03-conventions.md` ("Error Messages"), artifacts EN.
- No technical design here — that is `/bmad:architect`.

## Task: $ARGUMENTS
