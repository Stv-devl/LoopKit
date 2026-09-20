# Research: Impeccable UI layer   (entry: docs/specs/impeccable-ui-layer.md)
Token profile: economy

## Pattern to follow
Existing UI-only skip + gap wording in `.claude/commands/loop/review.md` stage 0 (skip announced with reason; missing browser tooling = "a gap in the gate, not a skip"). The Impeccable-missing case reuses that wording. Skill loading pattern: `designer.md` invokes `frontend-design` / `dataviz` by name (designer.md:38-40); Impeccable joins that list.

## Wiring points
- `.claude/agents/designer.md:38-40` — skills loaded before proposing; add Impeccable, UI only.
- `.claude/commands/loop/interface.md:20,110` — proposals step; no skill list there, designer owns it.
- `.claude/commands/loop/review.md` stage 0: app launch (~l.28-29) -> [detector slot] -> capture (~l.30-34); skip rule ~l.43-46; gap wording ~l.48-52.
- `.claude/agents/reviewer.md` `ui` dimension (~l.296-336): unchanged; detector findings enter as stage 0 evidence and bypass stage 2.
- EXECUTE: orchestrate Phase 4 and plan.md/templates have no "read UI recommendations" step. Slot: one line in Phase 4 for UI features + `templates/component.md` / `page.md` pointer.
- Line numbers come from an explorer summary; re-read before editing.

## Reusable
- `docs/design-system.md` and `docs/product/brief.md` are the authorities (read by designer, reviewer `ui`). Nothing to rewrite.
- Playwright: `e2e-playwright` skill + `e2e-tester` agent, untouched.
- No skill-declaration mechanism exists in the kit for `frontend-design`; skills are referenced by name. Impeccable installs to `.claude/skills/impeccable/`.

## Blast radius
- Files to edit: interface.md (wording only, optional), designer.md, review.md, orchestrate.md, docs/Claude_Workflows.md, root PRODUCT.md/DESIGN.md.
- No contract test covers these edits: test-workflow-contracts.sh does not check stage 0 or designer wording, kit-doctor.py does not check PRODUCT/DESIGN.md or skills dirs. Passing them proves little; the new behaviours (UI skip, missing-tool gap) have no coverage. Consider adding a contract grep.
- Uncommitted user changes already in the tree: orchestrate.md, codex-handoff.sh, docs/Claude_Workflows.md. Edits to orchestrate.md and Claude_Workflows.md must layer on those, not overwrite.

## Live DB state
n/a

## External surface
Impeccable, Apache-2.0, skill 4.3.1 (2026-09-09), npm `impeccable` 4.1.0. Full notes: `docs/research-cache/impeccable.md`. [fetched, volatile, summarised page reads, not verbatim]
- Install: `/plugin marketplace add pbakaus/impeccable` (user scope), or `npx impeccable install` (skill + hook manifest into project or user `.claude/`), or manual copy. [fetched]
- Commands: `/impeccable <cmd>`: init, critique (UX review), audit (a11y/perf/responsive), polish, etc. [fetched]
- Detector: `npx impeccable detect <dir|html|url> [--json]`; exit 0 clean, 1 unscannable, 2 findings; URLs need a Chromium browser. [fetched]
- Requires Node >= 22.18 for the npm package, above this repo's floor (20.19+ / 22.12+). [fetched]
- `init` writes root `PRODUCT.md` (marker `<!-- impeccable:product-schema 1 -->`, 10 sections) and never silently overwrites an existing one; `DESIGN.md` comes from `/impeccable document`, root. Pointer files are not documented as valid. [fetched]
- Visitor modes replaced brand/product register in v4; chosen per surface. [fetched]

## Traps (points of vigilance for the review)
- The spec's "thin pointer" PRODUCT.md/DESIGN.md may not satisfy Impeccable's schema; unverified. Do not ship pointers that Impeccable rejects or that make `init` rewrite them.
- `npx impeccable install` edits `.claude/settings.local.json` hooks; possible interaction with kit hooks, unverified. The kit must not run it blindly.
- Detector needs Node >= 22.18; `npx` on an older Node must produce a reported gap, not a false "clean".
- Exit code 1 (unscannable) must not be read as clean; only 0 is clean, 2 is findings.
- Whether `detect` parses JSX/TSX source directly is unknown; it may only see rendered HTML/URL, which changes the review step (run against the dev server URL).
- Skip on non-UI diffs must come before any Impeccable call.
- The uncommitted edits in orchestrate.md / Claude_Workflows.md must be preserved.
- No new `/loop:*` file; no ship gate; a11y authority stays `patterns/a11y.md`.

## Open questions
1. Does `detect` accept JSX/TSX source, or only built HTML / a running URL? (decides "run on diff files" vs "run on the dev server URL" in stage 0)
2. Do `critique`/`audit` run non-interactively from an agent, or only in an interactive session? (decides whether stage 0 can call them or only suggest them)
3. Does Impeccable hard-fail without a schema-valid PRODUCT.md, and does a pointer satisfy it? If not: keep pointers anyway, or generate full files from brief.md?
4. Install method to document: project-scoped `npx impeccable install` (touches settings.local.json) or manual copy of the skill only, without its hooks?
5. Do we add a contract-test grep for the UI skip / missing-tool gap wording?
