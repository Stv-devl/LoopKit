# Spec: Motion layer (Motion by default, GSAP only on demand)
Token profile: economy

## Objective
Give UI features in the kit a motion convention: Motion (or plain CSS) by default, GSAP only when a spec asks for a more complex need, enforced by review, with `prefers-reduced-motion` respected.

## Scope
- IN  :
  - **Stack line** in `.claude/rules/01-stack.md` (file is at 38/45 lines, one to three lines max): names Motion and GSAP, the default, and when GSAP is allowed. Versions and GSAP licence terms come from `/loop:research` (`doc-researcher`, cached in `docs/research-cache/`), not from memory.
  - **Two cold guides**, read only when a feature creates an animation: `.claude/skills/patterns/motion.md` (default: Motion or CSS, reduced-motion, no layout-thrash) and `.claude/skills/patterns/gsap.md` (only-on-demand: lazy-loaded, refs/cleanup, scoped to one section, never in the same component as Motion).
  - **Router entry** in `.claude/skills/project-rules/SKILL.md`: a row pointing motion work at those two patterns.
  - **Declaration**: a spec asks for GSAP with one line `Motion: gsap - <reason>` under `Front surface`. Without that line the default applies. `/loop:spec` template gets that optional line documented.
  - **Review check**: `/loop:review`'s `ui` dimension flags GSAP (import or dependency) not asked by the spec or `design.md` as **Major**, and both libraries in one component as Major.
  - **Reduced motion**: a short rule in `.claude/skills/patterns/a11y.md` plus a standard acceptance criterion the review checks on any animated feature.
  - **Honest limit in the docs**: review stage 0 takes still captures and does not judge animation feel; Impeccable's detector catches known code patterns only (e.g. bounce easing). Someone has to watch the page.
  - Workflow doc mention in `docs/Claude_Workflows.md`; contract greps in `.claude/hooks/test-workflow-contracts.sh` for the new wording.
- OUT :
  - No dependency is added anywhere (this repo has no `package.json`; apps that use the kit install what they need).
  - No new `/loop:*` command, no new agent, no new hook.
  - No motion design-token schema in `docs/design-system.md` (that stays `/loop:design-system`'s).
  - No automatic performance/animation-quality gate; not a `/loop:ship` gate.
  - No third animation library (React Spring, anime.js, etc.).
  - No change to Impeccable's integration beyond a docs mention of its motion rules.

## Data model
none

## Custom backend
NONE — kit tooling (markdown and bash), no backend.

## Front surface
No app code. Files touched: `.claude/rules/01-stack.md`, `.claude/skills/patterns/{motion,gsap,a11y}.md`, `.claude/skills/project-rules/SKILL.md`, `.claude/commands/loop/spec.md` (optional `Motion:` line), `.claude/agents/reviewer.md` (`ui` dimension), `.claude/commands/loop/review.md` if a pointer is needed, `docs/Claude_Workflows.md`, `.claude/hooks/test-workflow-contracts.sh`, `docs/research-cache/` (new entries from research).

## Acceptance criteria
- [ ] `01-stack.md` names Motion (default, or CSS) and GSAP (only when a spec asks), stays within its line budget, and `/kit:doctor` `rules-budget` and `rules-loaded` stay green.
- [ ] `patterns/motion.md` and `patterns/gsap.md` exist, are routed from `project-rules/SKILL.md`, and are not imported by `CLAUDE.md` (cold, read on demand).
- [ ] A spec can request GSAP with the single line `Motion: gsap - <reason>`; the `/loop:spec` template documents it as optional, default absent.
- [ ] `reviewer.md` `ui` dimension flags GSAP not requested by the spec or `design.md`, and both libraries in one component, as Major.
- [ ] `patterns/a11y.md` states the `prefers-reduced-motion` rule, and the review's standard criterion for animated features cites it.
- [ ] Library versions and GSAP licence terms in the stack line and guides are sourced from `docs/research-cache/` (tagged `[cache]`/`[fetched]`), not written from memory.
- [ ] The docs say plainly that review stage 0 does not judge motion and Impeccable only catches known patterns.
- [ ] No new file under `.claude/commands/loop/`, no `package.json` or dependency added; `test-workflow-contracts.sh`, `kit-doctor` and `test-rules-floor.sh` pass.

## Business logic to cover
No TypeScript business logic. Behaviours kept verified by contract greps and doctor: the review check wording (GSAP without a request is Major, both libs in one component is Major), the `Motion:` declaration line in the spec template, the reduced-motion rule present, the router row present, the stack line within budget, and no new command or dependency appearing.
