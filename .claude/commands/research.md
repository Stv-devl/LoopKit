---
description: RESEARCH step — multi-modal parallel fan-out (code, blast radius, live DB, external docs) into docs/work/<slug>/research.md
argument-hint: [path to the entry artifact: docs/specs/<x>.md or docs/stories/<slug>/<n>.md]
---

# /research — map the ground before planning on it

First step of the feature loop. You produce **one file on disk**
(`docs/work/<slug>/research.md`) that `/interface`, `/plan` and the reviewers will
read. Nothing here is written from memory: every claim carries evidence
(`path:line`, a query result, a migration name).

> Why on disk: the subagents downstream see neither this conversation nor each
> other. The file is the shared memory of the loop.

## The slug — derived from the entry path, recorded here

**This block is the only copy of the derivation.** It is a pure function of the
entry artifact's path, so anyone holding that path gets the same answer:

- entry `docs/specs/<x>.md` → slug = `<x>`
- entry `docs/stories/<feature>/<epic>.<story>.md` → slug = `<feature>-<epic>.<story>`
  (e.g. `docs/stories/inbox/1.2.md` → `inbox-1.2`)

`/research` is the step that **records** it — by creating `docs/work/<slug>/`,
after which every later step simply reads it out of the path it was handed.
Recorded, not owned: `/tracks` and `/orchestrate`'s Phase 0.5 have to name the
worktree and the branch **before** this step ever runs, and a rule saying "only
`/research` may compute it" left them with no name to use. They apply the two
lines above; they do not invent a spelling.

> The distinction is not pedantic. One track = one worktree = one branch
> (`.claude/guides/10-worktrees.md`), and the branch is `feat/<slug>`. Two stories
> of the same feature that fork under the feature's slug instead of their own
> collide on the second `git worktree add` — and if they did not collide, they
> would be two tracks in one worktree, which is the first thing that rule
> forbids.

If `docs/work/<slug>/` already exists, you are **re-running**: read what's there,
refresh what's stale, don't silently start a second folder under a different name.

## Process

1. Read the entry artifact (scope only).
2. Read the token profile from the caller/artifact (`economy` by default):
   - **economy:** one `explorer` covers all base and triggered code probes in a
     single map. Add at most one separate agent for a genuinely different
     modality: live remote DB or external documentation.
   - **standard:** at most 2 explorers, split by independent surfaces, plus one
     external-doc agent only when needed.
   - **critical:** at most 3 explorers, for the cases `11-token-budget.md`
     reserves `critical` for — that list is the only copy, do not restate it.
   Never create one agent per probe. Pass every agent the complete list of
   questions for its surface so one repository scan answers them together.

   > **While they run, do not poll and do not `sleep`.** You are re-invoked when
   > each one finishes. A turn spent waiting is billed twice, in tokens and in
   > wall-clock, and the transcript looks busy the whole time
   > (`.claude/rules/11-token-budget.md`).

   Before launching an **external-doc** agent, `ls docs/research-cache/` and hand
   it the listing: an agent that does not know what is already cached re-fetches
   it. If the cache and its `settled.md` ledger already answer every question,
   launch no such agent at all — that is the normal case on a settled stack.
   When you do launch one, it is a **`doc-researcher`**, never a bare
   `general-purpose`: it carries the read-first discipline and the network
   ceiling, and an untyped agent carries neither. Hand it **numbered questions**,
   at most six — the ceiling is per agent, so a seventh question means a second
   agent or a question you chose to drop, and both are your call, not its.
3. Barrier: gather the maps. **Reconcile contradictions** between probes rather
   than pasting both. A `doc-researcher` returns a **Promote to the ledger**
   block: those answers are tied to a pinned version, so they belong in
   `docs/research-cache/settled.md` and must never be researched again. Writing
   them there is **your** job — the agent is forbidden from editing the ledger,
   because promoting a fact is a decision, not a probe result. Do it now, in this
   step; deferred, it never happens and the next feature pays the fetch.
4. **Write** `docs/work/<slug>/research.md`.
5. **Stop.** Suggest `/interface docs/work/<slug>/research.md` (UI feature) or
   `/plan docs/work/<slug>/research.md` (no UI).

### Base questions (always, grouped into the profile's probe batches)

- structure of a similar existing feature (the pattern to follow)
- wiring points (router, providers, data client, job registration)
- reusable code / already-existing piece

### Mandatory probes (`explorer`, triggered by surface)

<!-- FILL: keep the four generic rows, add the ones this repo's surfaces need. -->

| If the change touches…                                   | MANDATORY probe |
| --- | --- |
| a DB object redefined by migrations (function, trigger, policy, scheduled job) | "Which is the **latest** migration that (re)defines this object? List them chronologically, give the body in effect." |
| an exported util / type / constant                       | "Who consumes this symbol? Is it dead (0 usage)?" |
| a shared backend module                                  | "Which handlers import this module? Which ones to redeploy?" |
| a schema shared between front and backend                | "Do both sides use it? Risk of desync?" |
| a multi-step flow (a queue, a scheduler, a state machine) | "Which other paths (job, webhook, reaper) write the same state?" |

> **Supersession reflex**: for any object redefined by stacking migrations, the
> source of truth is NEVER the one cited by the spec — it is the **latest**
> redefinition. Source the body there.

### Extra modality — live DB state (`explorer`, when the feature reads or writes data)

Not "what the schema says" but **what the rows say**: row counts, NULL rates on
the columns the feature depends on, actual enum values in use, whether the cron
has ever succeeded. Via the read-only inspection command declared in
`.claude/rules/06-database.md` — never assume, count.

> A schema that allows NULL and a column that is NULL on 383/383 rows are two
> different features. Only the query tells them apart.

### Extra modality — external docs (`doc-researcher`, when a third-party API is involved)

Current behaviour of the third-party surface: endpoints, payload shape, limits,
breaking changes. WebSearch/WebFetch allowed. Skip entirely if the feature
touches no third party.

**Read before you fetch, write after.** This modality is the most expensive step
of the whole loop — measured on a real project: 7 such agents, 178 network
round-trips, 2 h of agent time, and six of the seven researching overlapping
surfaces in one fan-out. They ran in **parallel**, so that cost 43 min of
wall-clock and the rest was paid in tokens: the same versions established six
times, and 20-38 k characters of report returned into the main thread by each.
That is the shape of the waste — mostly context, some time.

Two mechanisms, and the agent must use both.

**1. `docs/research-cache/settled.md` first, always.** That ledger holds what
the stack has already answered — every version-pinned behaviour a probe has
settled, cold on disk so no session pays for it until this moment. A question it
answers is **not** researched — not "researched quickly", not researched. If the
answer there is wrong or outdated, say so and stop: correcting a settled fact is
a decision, not a side effect of a probe.

**2. `docs/research-cache/<topic>.md`.** One topic, one file, this frontmatter:

```markdown
---
topic: <kebab-case, one third-party surface>
checked: YYYY-MM-DD
stability: pinned | volatile
sources:
  - <url actually read>
---
```

- `pinned` — the answer follows a version pinned in `01-stack.md`. Never
  re-fetched. It goes stale when that version changes, and only then, so
  bumping a dependency means deleting its cache files in the same commit.
- `volatile` — a third-party surface that moves on its own (a vendor API, a
  hosted service). Re-fetched when `checked` is more than **30 days** old.

The protocol, in order:

1. `ls docs/research-cache/` and read every file whose topic touches this
   feature. Fresh `pinned` and fresh `volatile` entries answer the question —
   report them as cached, with their `checked` date, and do not fetch.
2. Fetch **only** what is missing or stale, and only for the questions the
   feature actually asks. A version number nobody depends on is not a question.
3. Write back: one file per topic, only what you actually read, `sources` naming
   the pages you opened. An empty result is worth caching too — "this API has no
   documented rate limit" is a fact, and re-proving it costs another agent.
4. In `research.md`, mark each external answer `[cache <date>]` or `[fetched]`.
   That line is what lets the next reader see the cache working, or not.

> The cache is a **read-through**, not an archive: it holds answers the loop
> actually consumed, never a documentation dump. A topic file nobody read in the
> last few features is noise — delete it rather than refresh it.

## Template `docs/work/<slug>/research.md`

```markdown
# Research: <feature>   (entry: <path>)
Token profile: economy | standard | critical

## Pattern to follow
<existing feature + path:line, and why it is the right analogue>

## Wiring points
<routes, providers, data client, scheduled jobs — path:line each>

## Reusable
<what exists already and must NOT be rewritten — or "none">

## Blast radius
<objects redefined by migration, symbol consumers, functions to redeploy>

## Live DB state
<counts, NULL rates, enum values actually present — with the query used. Or "n/a">

## External surface
<third-party contract in effect, limits, traps. Or "n/a">
<each answer tagged `[cache YYYY-MM-DD]`, `[fetched]` or `[01-stack.md]` — an
untagged answer is one nobody can tell apart from a guess>

## Traps (points of vigilance for the review)
- <one line each — these become review criteria in /review>

## Open questions
<what no probe could settle, and what would settle it. `/plan` clears this list
AT ITS GATE, before the user's go — so write each one as a question that can be
answered, not as a note.>
```

## Rules

- Every claim carries evidence. A probe that found nothing says "nothing found",
  it does not guess.
- Do not implement, do not design, do not decide the plan. Map only.
- The **Traps** section is not decoration: `/review` receives it verbatim.
- The **Open questions** section is not decoration either: `/plan` must clear it
  at its gate, and anything left there becomes an assumption frozen into a test.
  An empty list is a fine answer; an unanswerable one is a fact the user needs.

## Task: $ARGUMENTS
