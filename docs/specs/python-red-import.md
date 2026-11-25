# Spec: Python RED on a package import, monorepo server roots, inline-program line for read-only agents
Token profile: critical
Validation: moi

## Objective
An EcoCrew-style auto pass reaches its PR without a user stop when its first Python RED imports the module under test as `from <package> import <module>`. The ship security audit arms `authz` on a monorepo backend, and the read-only agents stop reaching for inline programs. No guard is loosened beyond the exact case named in item 1.

Source evidence (read-only), EcoCrew story agent-ia-4.1 (2026-11-25, PR #52 merged), transcript `~/.claude/projects/-home-stevan-Travail-Projetperso-ecocrew/928747b9-…`:
- At 15:00 `tdd-prove-red-py` recorded no RED for `backend/tests/services/agent/test_choice.py`, which imports `from app.services.agent import choice` before `choice.py` exists. pytest reports `cannot import name 'choice' from 'app.services.agent'`.
- The test file was already frozen by the plan gate, and the arbiter cannot unfreeze a header line. This ended in an auto blocked stop at 15:02.
- The user then ran `--release` in a terminal and, in `moi`, approved a `.tdd-unfrozen` line and the screenshot publish. That is 3 user stops, all from this one defect.
- At ship, `kit-audit-surface.py select` kept only `input-output` and the orchestrator added `authz` by hand. The same happened on 2.5.
- The plan-critic hit "inline programs are not used here".

Branch: one, off `main` once `auto-mode-2.5-fixes` is merged. Both touch kit hooks, so they never run in parallel.

## Scope
- IN :
  1. **The prover reads `from <package> import <module under test>` as a legitimate RED.**
     - In `addons/fastapi/hooks/tdd-prove-red-py.py` (classification :192-240), a `cannot import name '<n>' from '<p>'` whose `<p>.<n>` is **exactly** the dotted module under test is classed like the module itself missing (`missing-module`). So is the same error with `partially initialized module`.
     - Every other `cannot import name` keeps today's class: a name absent from a different module stays `unresolved-name`, and a name absent from the module under test stays `missing-module`, as today.
     - Nothing else in the prover changes. The marker is written only on the same conditions as for a `No module named '<dotted>'`.
  2. **Server roots may be multi-segment paths.**
     - `project_config.py` `_server_roots` (:112-118) accepts a relative POSIX path of one or more segments (`backend/app`). It refuses `..`, absolute paths, empty segments and `.`.
     - `kit-audit-surface.py select` (:166-171) arms `authz` when a changed path equals a root or starts with `<root>/`.
     - Single-segment roots behave exactly as today.
     - `/kit:init` (and `kit-doctor` if it checks the key) detects a backend app nested in a subdirectory (`backend/app`, `backend/alembic`) and proposes the prefixed form.
  3. **Read-only agents never run inline programs.** `reviewer.md`, `verifier.md`, `plan-critic.md`, `story-critic.md`, `explorer.md` and `security-auditor.md` each carry one line: no `python3 -`/`-c`, `node -e` or heredoc program; Read/Grep, `git -C`, or a kit script instead. Same wording style as the "Refused shapes" block of `implementer.md` (pass auto-mode-2.5-fixes, item 6).
- OUT :
  - EcoCrew's own `server_roots` value (`["app","alembic"]` → `["backend/app","backend/alembic"]`): EcoCrew config, the user's, applied in that repo after this pass ships.
  - Header edits in a frozen test file without a RED marker (the 4.1 catch-22 itself), and import-only insertions in frozen files: they loosen the freeze and go to their own `critical` pass. Item 1 removes the trigger seen in 4.1.
  - The TS prover (`tdd-prove-red.sh`): no equivalent defect was observed.
  - The `moi`-mode screenshot ask (by design in `moi`).

## Data model
none

## Custom backend
NONE — kit hooks, kit config reader and agent prompts only.

## Front surface
none

## Acceptance criteria
- [ ] A Python test-first file importing `from app.services.agent import choice` while `app/services/agent/choice.py` does not exist (package `app/services/agent/__init__.py` present) gets a RED marker on save, and the module write is then allowed (EcoCrew 4.1 reproduction).
- [ ] The same with `from app.services.agent import choice` failing as `partially initialized module` records the marker.
- [ ] `from app.services.agent import helpers` (not the module under test, absent) still records no marker with the `unresolved-name` text; `from app.services.agent.choice import missing_fn` with `choice.py` present still records the marker as today.
- [ ] `server_roots: ["backend/app"]` is accepted; `["../x"]`, `["/abs"]`, `["a//b"]`, `["."]` are refused with a ConfigError naming the entry; `["app"]` behaves exactly as today.
- [ ] `kit-audit-surface.py select --base <rev>` on a diff touching `backend/app/api/routes/account.py` with `server_roots: ["backend/app"]` prints `authz` with its reason; with `["app"]` on the same diff it prints no `authz` (today's behaviour, unchanged).
- [ ] `/kit:init` on a fixture repo with `backend/app/main.py` and `backend/alembic/` proposes `["backend/app","backend/alembic"]`.
- [ ] The six read-only agent files carry the inline-program line, and a contract test checks it.
- [ ] All kit suites pass (`test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `test-kit-doctor.sh`, the addon's Python hook tests) and `/kit:doctor` passes.

## Business logic to cover
- Prover classification: exact `<package>.<name> == module under test` → RED recorded; any other unresolved name → no marker, same text as today; existing missing-module, missing-symbol, async-not-configured and skip branches unchanged.
- Server-root parsing (accept and refuse rules) and prefix matching in the audit surface selection, including the unchanged single-segment behaviour.
- `/kit:init` nested-backend detection.
