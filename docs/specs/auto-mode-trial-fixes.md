# Spec: auto-mode trial fixes (EcoCrew agent-ia-1.4)
Token profile: critical
Validation: auto

## Objective
Remove the 15 manual approvals of the EcoCrew auto-mode run that came from kit defects, cascades and agent command shapes, without widening any guard beyond the cases named here.

Source: `docs/work/auto-mode-trial-fixes/handoff.md` (session bf6cf1fd, 2026-11-22). Branch: one, off `main` (c3d557d).

## Scope
- IN :
  1. **Rows-mode unfreeze accepts import additions.** When an arbiter per-case unfreeze verdict exists for a frozen test file, a pure addition of `import` lines in the file's top import block is allowed alongside the unfrozen case. Nothing else outside the case: no import removal or rewrite, no other top-level line.
  2. **No self `--clear` on an auto blocked stop.** Prompts (`/loop:orchestrate`, `/loop:ship`, any other place telling the agent to run `loop-record.py --clear`) forbid clearing the record to get past a blocked stop in `auto`; a blocked stop ends the turn with the record intact. `--clear` stays only where the pass is finished (ship/tracks after commit).
  3. **Read-only gh forms run without ask.** `enforce-git-workflow.sh` stops asking "writes to GitHub" for a closed list: `gh repo view`, `gh pr view|list|diff|checks`, `gh issue view|list`, `gh release view|list`, `gh run view|list`. `gh api` keeps asking, whatever its arguments. Every other gh form keeps its current verdict; the attribution deny and the `gh pr create` exact-form path are unchanged.
  4. **Agent command shapes.** `test-writer` and `e2e-tester` prompts: read a file range with Read offset/limit, never a `for … sed -n "${n}p"` loop; no `cd … && git apply --check` probes; Playwright runs with the project config plus `--grep`, never an agent-written temp config (`-c`).
  5. **`app_roots` drives UI and audit-surface detection.** `kit-pr-assets.py` classifies a path as UI when it sits under `src/` or `<root>/src/` for each `app_roots` entry of `.claude/project.json` (via `project_config.py`). `kit-audit-surface.py` uses the same roots wherever it assumes a literal `src/`. Orchestrator prompt: when the diff plainly holds `*.tsx` under an app root and the script says `none`, decide `ui` anyway; the e2e tester saves shots through `PR_SHOTS`, never a fixed review folder. `/kit:init` detects a front-end app root (a directory holding `src/` and its own `package.json`) and fills `app_roots`.
  6. **Ignore Codex output.** `.gitignore` gains `docs/work/*/codex-last-message.txt`.
- OUT :
  - EcoCrew's own `project.json` (`app_roots: ["frontend"]`): fixed in that repo, outside this pass.
  - `gh api` read-only detection (method/flag parsing): later, if measured stops justify it.
  - Any other unfreeze widening (import removal, helper functions, fixtures outside a case).
  - Guarded-path grants (parked, see memory/project notes).

## Data model
none

## Custom backend
NONE — kit hooks, scripts and prompts only.

## Front surface
none (kit repo; no app UI)

## Acceptance criteria
- [ ] With an unfreeze verdict on case C of a frozen test, an Edit adding C's body plus a new `import` line in the top block is allowed; the same Edit without a verdict is denied; an Edit that removes or rewrites an existing import, or adds a non-import top-level line, is denied even with a verdict.
- [ ] No kit prompt tells the agent to run `loop-record.py --clear` on a blocked stop; the orchestrate/ship prompts state that in `auto` a blocked stop ends the turn with the record kept. A contract test pins it.
- [ ] Each listed read-only gh form (with or without `-R owner/repo`, `--json`, `--web` excluded) passes the git hook without ask; `gh api repos/x/y`, `gh pr create` (non-exact form), `gh pr merge`, `gh issue create`, `gh release create`, `gh repo create|delete|edit` still ask or deny as today. A form chained with a write (`gh pr view 1 && gh pr merge 1`) still asks.
- [ ] `test-writer.md` and `e2e-tester.md` carry the three command-shape rules; a contract test pins them.
- [ ] `kit-pr-assets.py ui` on a diff touching `frontend/src/X.tsx` with `app_roots: ["frontend"]` answers `ui`; with `app_roots: []` it answers `none`; `src/X.tsx` stays `ui` in both.
- [ ] `kit-audit-surface.py` on a diff under `frontend/src/` with `app_roots: ["frontend"]` returns the same surfaces as the same diff under `src/` with no roots.
- [ ] `/kit:init` proposes `app_roots: ["frontend"]` on a tree with `frontend/package.json` + `frontend/src/`, and `[]` on a root-level `src/`.
- [ ] `git check-ignore docs/work/x/codex-last-message.txt` succeeds.
- [ ] All existing kit test scripts (`.claude/hooks/test-*.sh`) pass.

## Business logic to cover
- Unfreeze rows mode: import-only additions accepted only under a verdict, every other out-of-case change still refused.
- gh classifier: the closed read-only list is allowed, everything else keeps its verdict, chains are judged by their most dangerous segment.
- UI path classification and audit-surface mapping per `app_roots`, including the empty-roots default.
- `/kit:init` app-root detection.
- Prompt contracts: no self-clear on blocked stop, agent command shapes, `ui` override when the script says `none`.
