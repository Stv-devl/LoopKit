---
description: BMAD Architect — technical design in docs/architecture/<slug>.md, from the PRD and the reviewed stories
argument-hint: [path docs/prd/<slug>.md]
---

# /bmad:architect — Architect

From a **PRD** and its **reviewed stories** (`Approved`), you produce the
technical design that every story's `/plan` will draw on. You don't write code —
you decide the structure, the contracts, the wiring points, and the build order.

> Runs **after** `/stories:review`. Designing against a slice that hasn't survived
> its gate means redesigning it.

## Process

1. Read `docs/prd/<slug>.md` and every story in `docs/stories/<slug>/`. If any is
   still `Draft`, **stop** and suggest `/stories:review docs/stories/<slug>/`.

   > Stopping, not mentioning. "The stories come before the architecture" is the
   > kit's own headline claim — *a bad slice is rewritten in two minutes while it
   > is functional, and costs a day once an architecture stands on it* — and this
   > is the only place anything can act on it. A command that names the risk and
   > proceeds anyway enforces nothing. Same shape as `/design-system` stopping on
   > a missing `docs/product/brief.md`.
2. **Map the existing code with bounded context.** Default to one `explorer`
   covering patterns, wiring, reuse and blast radius. Use at most two when the
   PRD spans independent frontend and backend/data surfaces. Three are allowed
   only under the `critical` token profile. Load only the architecture rule,
   feature template and patterns directly relevant to the mapped surfaces.
3. **Write** `docs/architecture/<slug>.md` (template below) — `<slug>` being the
   **PRD's**, the one you were handed. One architecture per PRD, never per story:
   a story's own loop slug adds `-<epic>.<story>` (`/research`, "The slug"), and
   `/plan` reads this file by the PRD slug precisely because it is shared by every
   story of the feature.
4. **Design system check** — if any story has a user surface and
   `docs/design-system.md` does not exist, the next step is `/design-system`, not
   the loop: without it `/interface` invents components instead of composing with the
   primitives already in `src/components/ui/`. Say so explicitly.
5. **Stop.** Suggest `/design-system` (if step 4 triggered), then
   `/orchestrate docs/stories/<slug>/1.1.md` (the first story enters the loop).

## Template `docs/architecture/<slug>.md`

```markdown
# Architecture: <title>  (PRD: docs/prd/<slug>.md)

## Key decisions
<structuring choices + 1-line justification each>

## Data model
<tables/columns/authorization/triggers — or "none". Migrations via /database:migration>

## Backend
<required handlers/endpoints, and the style they follow — or "NONE — why">

## Front surface (per feature)
features/<x>/
- types/ : <domain entities>
- schemas/ : <Zod>
- services/ : gateway + mapper + repository (Result<T>) — or a single services.ts
  under the size threshold of `02-architecture.md` ("File size thresholds")
- hooks/ : <React Query queries/mutations>
- stores/store.ts : <Zustand UI state, if needed>
- components/ + pages/ : <screens>
- wiring : routes + guards

## Contracts & wiring points
<repository signatures, query keys, routes, providers touched>

## Patterns to reuse
<existing path:line + .claude template/pattern to follow>

## Shared surfaces at risk
<objects several stories write, and the order that keeps them consistent>

## Rules compliance (reminder)
- No cross-feature import; no business logic in pages/components
- Data client only in gateway/services; hooks → repository
- No `any`; Result<T>; user language vs log language; React Query states handled
  — the five: `isPending`, `isError`, empty, `isFetching`, and
  `isPlaceholderData` on any key carrying a filter/sort/page

## Story map
| Story | Layers touched | Depends on | Parallel with | Shared foundations |
| --- | --- | --- | --- | --- |
<two stories are "parallel with" each other only if their file sets are disjoint
 AND neither touches a shared foundation (migrations/DB, src/lib, shared/,
 router, providers, lockfile). Name those foundations in the last column: they
 are sequenced first, in the main tree, and the parallel stories fork from that
 commit. This column is what /bmad:flow reads to decide the worktrees.
 Two writing rules make the last two columns checkable later:
 - name the **exact file** of each contact point, never the module it belongs to
   — `runtime/main.ts` (the array) rather than `registry.ts`, `src/features/x/
   hooks/hooks.ts` rather than `features/x`;
 - mark a file that **does not exist yet** with `(new, story N)`, so a later
   reader knows it cannot be opened rather than concluding the column is wrong.>
```

## Rules

- **No manual SQL**: every migration goes through `/database:migration`.
- Strictly follow `.claude/rules/`. No `any`, explicit contracts.
- Stay factual: contracts and paths, not full code.
- Don't re-slice the stories. If the slice is wrong, say so and send it back to
  `/stories:review` — don't silently work around it.
- The story map is the **input of the isolation decision**
  (`.claude/guides/10-worktrees.md`). "Parallel with" that ignores a shared
  foundation produces two worktrees that conflict on merge — be conservative.
- **This map is written before the code and will drift.** It is read as an
  indication, re-verified against the files at fork time, and corrected there —
  so the last two columns must name what can be opened (exact paths, `(new)`
  where it does not exist yet), not what sounds right. A shared helper attributed
  to the story that needs it *second* is the classic drift: check which story
  first needs each one, and attribute it there.

## Task: $ARGUMENTS
