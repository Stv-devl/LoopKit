# Plan: Impeccable UI layer   (entry: docs/specs/impeccable-ui-layer.md · research: docs/work/impeccable-ui-layer/research.md · design: n/a)
Token profile: economy

## Skips
- INTERFACE : SKIP — kit tooling, no user surface.
- DB, Backend, TS front layers (types/schemas/gateway/utils/mapper/repository/hooks/UI) : SKIP — markdown and bash only, nothing under `src/` or `shared/`, so no test-first hook applies.
- Playwright / e2e : unchanged.

## Write chain (sequential)
1. **Contract greps first** — append the `grep -Fq` / line-order checks listed in the Test plan to `.claude/hooks/test-workflow-contracts.sh`; run it: it must fail because the phrases do not exist yet.
2. `.claude/commands/loop/review.md` — stage 0: a `Skip first` sentence, then the detector step, then critique/audit, then the gap sentence; findings bypass stage 2.
3. `.claude/agents/designer.md` — load `impeccable` next to `frontend-design` (UI proposals only), reading root `PRODUCT.md`/`DESIGN.md`.
4. `.claude/commands/loop/interface.md` — one line: Impeccable is used through `designer`; skip line unchanged.
5. `.claude/commands/loop/orchestrate.md` Phase 4 and `.claude/commands/loop/plan.md` (UI features only) — one line each: read the stage 0 Impeccable findings when fixing UI. Layered on the uncommitted edits.
6. Root `PRODUCT.md`, `DESIGN.md` — pointers, each <= 10 lines.
7. `docs/Claude_Workflows.md` (layered on uncommitted edits) and `docs/ADAPTATION.md` — placement, the Impeccable/Playwright split, install step (manual copy of the skill only, no hooks, no `init` over the pointers), Node >= 22.18 note.
8. Gates: `bash .claude/hooks/test-workflow-contracts.sh`, `/kit:doctor`, `git diff --stat -- .claude/settings.json .claude/settings.local.json` shows no change.

Not vendored: the kit does not ship Impeccable's files; it references the skill by name, as it does `frontend-design`. Absent -> reported gap. No `settled.md` row: Impeccable is volatile and unrelated to a pinned version, so its facts stay in `docs/research-cache/impeccable.md` (already written); this deviates from the spec's "settled.md entry" line on purpose.

## Decisions taken from research's Open questions (confirm at the gate)
1. Detector input: run `npx impeccable detect --json` on the diff's UI source directory; when that exits 1 (cannot read the sources), retry on the running app URL from the `run` skill; still failing -> gap.
2. Critique/audit: invoked from the main thread on the captured screens; if not runnable non-interactively -> gap, not a blocker.
3. Root files: pointers (asked to the user).
4. Install: documented, manual, skill only; kit never runs `npx impeccable install`.
5. Contract greps: yes (below).

## Parallel lots (inside this track, same tree)
none — fully sequential.

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: none of the listed ones.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| .claude/hooks/test-workflow-contracts.sh | Edit | new contracts |
| .claude/commands/loop/review.md | Edit | stage 0 detector, critique, gap |
| .claude/agents/designer.md | Edit | load Impeccable |
| .claude/commands/loop/interface.md | Edit | one-line pointer |
| .claude/commands/loop/orchestrate.md, plan.md | Edit | UI findings line (preserve uncommitted edits) |
| PRODUCT.md, DESIGN.md | Create | pointers |
| docs/Claude_Workflows.md, docs/ADAPTATION.md | Edit | placement, split, install, Node floor |

## Contracts
- `npx impeccable detect --json <target>`: exit 0 clean, 2 findings, 1 / missing / Node < 22.18 = gap in the verdict, never clean.
- Order in review.md stage 0: `Skip first` line number < `npx impeccable detect` line number.
- Advisory only: never a ship gate; `patterns/a11y.md` stays the a11y authority.

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — front / backend
None: nothing under `src/` or `shared/`, the TDD hooks do not apply. The contracts below are added first and shown failing.

#### .claude/hooks/test-workflow-contracts.sh
**Core behaviour**
- [ ] review.md contains `Skip first` and it appears on an earlier line than `npx impeccable detect` (`grep -n` line comparison).
- [ ] review.md contains `an Impeccable failure is a gap in the gate, never clean`.
- [ ] review.md contains `Impeccable findings bypass stage 2`.
- [ ] designer.md contains `impeccable` and `frontend-design`.
**Business rules**
- [ ] review.md contains `Impeccable is never a ship gate` and `Playwright stays the flow proof`.
- [ ] interface.md contains `no user surface` skip wording still and `Impeccable` exactly through `designer`.
- [ ] orchestrate.md and plan.md contain `only on a UI feature` next to the Impeccable findings line.
- [ ] `ls .claude/commands/loop/*.md | wc -l` equals 12.
- [ ] PRODUCT.md and DESIGN.md are each <= 10 lines and contain their pointer target path.
- [ ] docs/Claude_Workflows.md contains `Impeccable`; docs/ADAPTATION.md contains `22.18` and `impeccable init`.
**Edge cases**
- [ ] Distinctive pre-existing lines of orchestrate.md, Claude_Workflows.md and codex-handoff.sh (the uncommitted edits) are still present: `git diff --numstat` deletions for those three files stay 0 beyond the pre-edit baseline recorded in step 1.
- [ ] `git diff --stat -- .claude/settings.json .claude/settings.local.json` is empty.

### Test-after — hooks, gateway, UI
n/a. `/kit:doctor` and `test-rules-floor.sh` stay green.

## Vigilance (carried from research)
- Do the diffs keep the skip-before-Impeccable order in review.md?
- Is a non-0/2 detector exit or old Node reported as a gap, never "clean"?
- Are PRODUCT.md/DESIGN.md pointers only, and does the doc forbid `impeccable init` overwriting them?
- Is any Impeccable hook install in `settings.local.json` avoided or documented?
- Were the user's uncommitted edits in orchestrate.md, Claude_Workflows.md, codex-handoff.sh preserved?
- No new `/loop:*`, no ship gate, a11y authority unchanged.

## Acceptance criteria (carried from the entry artifact)
- [ ] On a feature with no UI, `/loop:interface` and review stage 0 announce a skip and invoke nothing from Impeccable.
- [ ] `/loop:interface` and `designer` reference Impeccable for UI features, alongside `frontend-design`, without changing the artifact (`docs/work/<slug>/design.md`) or the gate.
- [ ] Review stage 0 runs the Impeccable detector before the eye pass; its findings appear in the `### Visual (stage 0)` output with file:line and severity, and bypass stage 2.
- [ ] If Impeccable is not installed or the detector cannot run, the verdict reports it as a gap in the gate (same wording as "no browser tooling"), never a silent skip.
- [ ] The implementer's instructions for UI features say to consume Impeccable findings; nothing forces it on non-UI work.
- [ ] Root `PRODUCT.md` and `DESIGN.md` exist as pointers only (no duplicated content) and Impeccable's init is documented as not to overwrite them.
- [ ] Playwright/e2e wording is unchanged in behaviour; docs state the split (Impeccable = design quality, Playwright = flows).
- [ ] No new file under `.claude/commands/loop/`; `/kit:doctor` and `test-workflow-contracts.sh` pass; rules budgets (`rules-budget`) not exceeded.
- [ ] `docs/Claude_Workflows.md` describes where Impeccable plugs in.

## Plan critic
- completeness: 62 -> revised (first pass; Majors fixed: open questions decided, install/settled.md handled, literals + order check added)
- quality: 68 -> revised
- surviving blockers: none after rewrite (re-run not launched on economy; the critic claims were verified directly)
