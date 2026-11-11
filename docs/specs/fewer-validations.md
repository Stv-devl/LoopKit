# Spec index: Fewer validations — split into four passes (2026-11-09)
The spec reviewed on 2026-11-08 (3 reviewers + 2 verifiers, then 2 reviewers on the part C additions, findings applied) is split into four passes, run in this order, each shipped and measured before the next. The item numbers V1-V11 are kept inside each pass.

| # | Spec | Items | Token profile |
| --- | --- | --- | --- |
| 1 | `docs/specs/fewer-asks.md` | V1 (minus `APP_ROOTS`), V2, V3 (minus `CODEGEN_COMMANDS`), V4, V6, V11, V12 (one-line `git -C` commit, from V5) | standard |
| 2a-1 | `docs/specs/app-roots-codegen.md` | `APP_ROOTS` (V1), `CODEGEN_COMMANDS` (V3), `.claude/project.json` created | critical |
| 2a-2 | `docs/specs/project-config.md` | V9's prerequisite: every hook value moved into `project.json` | critical |
| 2a-3 | `docs/specs/kit-boundary.md` | V9 minus the prompts: kit code denied in an installed project (re-split 2026-11-10, user) | critical |
| 2b | `docs/specs/kit-prompts.md` | V9's prompts: FILL adaptations moved out, then denied (split 2026-11-10, user) | critical |
| 3 | `docs/specs/loop-to-pr.md` | V5, the hook-written record (V7), V10 | critical |
| 4 | `docs/specs/auto-mode.md` | V7, V8 | critical |

Between 1 and 2: measure on a real EcoCrew feature. Before 3: the user settles the grants parking for `.tdd-unfrozen`. Before 4: one real feature through pass 3.

Settled: the `safetyCheck` and auto-memory spikes (`docs/product/spikes/`), kit prompts count as kit code (V9, user 2026-11-09).
