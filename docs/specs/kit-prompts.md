# Spec: Kit prompts — move the per-project adaptations out of the kit prompts, then deny them in an installed project
Status: DRAFT — pass 2b of 4, split from `docs/specs/kit-boundary.md` on 2026-11-10 (user, after kit-boundary plan-critic pass 1 and its verifier, finding C1). Depends on `kit-boundary.md` shipped (the project config file, the installed check, the kit-code deny). Next: `loop-to-pr.md`, `auto-mode.md`.
Token profile: critical (it changes what is denied in every installed project and where `/kit:init` writes)

## Objective
Kit prompts (agents, commands, skills, guides) count as kit code (user, 2026-11-09): a feature never changes them outside the LoopKit repo; an agent or skill is improved in LoopKit, then reinstalled. Today they cannot be denied, because about 20 of them carry FILL markers that `/kit:init` and `docs/ADAPTATION.md` fill per project. This pass first moves every per-project adaptation out of the prompts, to the rules, the project config file or a project overlay. Only then are the prompts denied in an installed project.

## Evidence
The kit-boundary verifier (2026-11-10, `docs/work/kit-boundary/plan.md` `## Plan critic`), finding C1, lists live FILL directives in: `agents/github.md:27`, `agents/doc-researcher.md:9`, `commands/loop/ship.md:55,107`, `commands/database/migration.md:12`, `commands/loop/research.md:90`, `commands/audit/mutation.md:53`, `skills/e2e-playwright/SKILL.md:8,15,65`, `skills/patterns/feedback.md:3,208`, `skills/patterns/guards.md:3`, `skills/patterns/forms.md:12`, `skills/templates/feature.md:8`, `skills/templates/fixtures.md:82`, `skills/templates/tooling-config.md:324,360`. In addition, `docs/ADAPTATION.md` §2 makes `guides/review/correctness.md` a `SHARED_DIRS` copy, and §12 edits `10-worktrees.md` per project. `kit-doctor.py:1072` scans `commands/` and `skills/templates|patterns` for FILL.

## Scope
- IN :
  - **P1. Inventory**: every FILL marker and every ADAPTATION step that writes under `.claude/agents|commands|skills|guides`, each with its target home.
  - **P2. Move**: each adaptation goes to a hot rule, the project config file (`kit-boundary.md`) or a project overlay the prompt reads. The plan decides the home for each, and the overlay's path and format. After this step, no prompt holds a project value, and `kit-doctor.py`'s FILL scan reads the new homes.
  - **P3. Deny**: `.claude/agents/*`, `.claude/commands/*`, `.claude/skills/*`, `.claude/guides/*` join the kit-code deny of `kit-boundary.md` in an installed project. They keep today's pass in the kit repo.
  - **P4. `/kit:init` and `/kit:recipe`**: they write only the new homes. `/kit:recipe` writes a cold guide, so the plan decides whether guides stay writable through it, or whether recipes move to a project folder.
- OUT :
  - The project config file, the installed check, the kit-code deny on hooks/scripts/launchers: `kit-boundary.md`.
  - Push, PR, the record, V10: `loop-to-pr.md`.

## Open questions
- What the overlay is, if one is needed: a file per prompt, one project file the prompts read, or rules only. Decide it in the plan, after P1.
- Whether a prompt that the user wants to adapt locally gets an escape path (an override file) or must go through LoopKit.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files: the prompts listed in *Evidence*, `docs/ADAPTATION.md`, `.claude/commands/kit/{init,recipe,doctor}.md`, `kit-doctor.py`, `hook-guarded.sh`, `install.sh`, their tests.

## Business logic to cover
- In an installed project: Write/Edit, a shell write or a git write onto `.claude/commands/loop/ship.md` is denied. In the kit repo it passes.
- `/kit:init` on a fresh install fills every former FILL value through the new homes, with no write under `.claude/agents|commands|skills|guides`.
- `kit-doctor.py` reports an unfilled value in its new home, and reports no FILL left in a prompt.
- `install.sh` upgrades an existing project: values already adapted in its prompts move to their new homes with no loss.

## Acceptance criteria
- [ ] No kit prompt holds a per-project value; `kit-doctor.py` checks the new homes.
- [ ] Kit prompts are denied in an installed project through Write/Edit, shell and git.
- [ ] `/kit:init` and `/kit:recipe` work in an installed project with no prompt write.
- [ ] `install.sh` upgrades EcoCrew with no lost adaptation.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
On the next EcoCrew feature: no agent edit of a kit prompt succeeded; `/kit:doctor` clean.

## Next work
At `/loop:ship`, once the commit is done, propose this to the user as the next step (do not start it without their go): update EcoCrew with `install.sh`, then `docs/specs/loop-to-pr.md` (pass 3), after settling its open question with the user (lifting the grants parking for `.tdd-unfrozen`).
