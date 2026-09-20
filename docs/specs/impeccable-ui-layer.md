# Spec: Impeccable as the UI expertise layer
Token profile: economy

## Objective
Plug Impeccable (pbakaus/impeccable) into the existing loop as a UI-only expertise layer: design proposals, deterministic visual review, and fix guidance for the implementer, without a new `/loop:*` command.

## Scope
- IN  :
  - **`/loop:interface`** (+ `designer` agent): load the Impeccable skill next to `frontend-design` for proposals; UI features only.
  - **`/loop:review` stage 0 (LOOK)**: run Impeccable's deterministic detector on the diff's UI files first (findings are file:line evidence, they bypass stage 2 like a screenshot), then its critique/audit pass over the captured screens. Findings enter the existing severity scale.
  - **EXECUTE / review fixes**: the implementer of a UI feature reads Impeccable's recommendations (detector output, critique) as input to fix the UI; no new agent.
  - **`PRODUCT.md` / `DESIGN.md`**: thin root pointer files only. `PRODUCT.md` -> `docs/product/brief.md`, `DESIGN.md` -> `docs/design-system.md`. Single source of truth stays in LoopKit; Impeccable's `init` must never overwrite them with a second copy.
  - **UI gate**: everything above is skipped, with a one-line announcement, when the diff has no user surface (backend, migration, cron, refactor). Same skip rule as today's stage 0.
  - Playwright (`e2e-tester`, `e2e-playwright` skill) unchanged: it stays the functional/behavioural proof; Impeccable is the design-quality lens. Neither replaces the other.
  - Docs: `docs/Claude_Workflows.md` and the command/agent files touched; a `settled.md` entry after `/loop:research` confirms install method and detector invocation.
  - Hook/doctor coverage only where a contract already exists (`test-workflow-contracts.sh`, `/kit:doctor`), if the changed files are covered there.
- OUT :
  - No new `/loop:*` command, no new agent, no new hook unless research proves an existing one must change.
  - No change to `/loop:design-system`, `/loop:product`, the `ui` reviewer dimension, or the a11y pattern (`patterns/a11y.md` stays the accessibility authority; Impeccable findings on a11y are advisory input to it, not a second rule set).
  - No use of Impeccable to generate or rewrite `docs/design-system.md`.
  - No Impeccable step in `/loop:ship` gates (it is never a ship gate).
  - No re-implementation of Impeccable's rules inside LoopKit.

## Data model
none

## Custom backend
NONE — kit tooling (markdown commands, agents, skills), no backend.

## Front surface
No app code. Files touched: `.claude/commands/loop/interface.md`, `.claude/commands/loop/review.md`, `.claude/agents/designer.md`, possibly `.claude/agents/reviewer.md` (ui dimension pointer) and the plan/orchestrate wording that hands UI recommendations to EXECUTE, `docs/Claude_Workflows.md`, root `PRODUCT.md` and `DESIGN.md` pointers, Impeccable install under `.claude/skills/` (method to be confirmed by `/loop:research`).

## Acceptance criteria
- [ ] On a feature with no UI, `/loop:interface` and review stage 0 announce a skip and invoke nothing from Impeccable.
- [ ] `/loop:interface` and `designer` reference Impeccable for UI features, alongside `frontend-design`, without changing the artifact (`docs/work/<slug>/design.md`) or the gate.
- [ ] Review stage 0 runs the Impeccable detector before the eye pass; its findings appear in the `### Visual (stage 0)` output with file:line and severity, and bypass stage 2.
- [ ] If Impeccable is not installed or the detector cannot run, the verdict reports it as a gap in the gate (same wording as "no browser tooling"), never a silent skip.
- [ ] The implementer's instructions for UI features say to consume Impeccable findings; nothing forces it on non-UI work.
- [ ] Root `PRODUCT.md` and `DESIGN.md` exist as pointers only (no duplicated content) and Impeccable's init is documented as not to overwrite them.
- [ ] Playwright/e2e wording is unchanged in behaviour; docs state the split (Impeccable = design quality, Playwright = flows).
- [ ] No new file under `.claude/commands/loop/`; `/kit:doctor` and `test-workflow-contracts.sh` pass; rules budgets (`rules-budget`) not exceeded.
- [ ] `docs/Claude_Workflows.md` describes where Impeccable plugs in.

## Business logic to cover
No TypeScript business logic. Behaviours to keep verified by the existing contract/doctor checks: the UI-only skip path, the "tool missing is a reported gap" path, and no new command file appearing. Everything else is documentation and instruction wiring.
