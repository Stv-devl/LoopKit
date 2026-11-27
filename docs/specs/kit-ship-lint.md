# Spec: kit ship runs the CI lint locally
Token profile: economy
Validation: moi

## Objective
A pass shipped from the LoopKit repo itself runs, before the commit, the same
three lint steps as `.github/workflows/kit-ci.yml`, so a "green" ship can no
longer fail CI on lint.

## Context (verified 2026-11-27 at 7ebc764)
- CI lints with `shellcheck -S warning .claude/hooks/*.sh .claude/scripts/*.sh`
  (kit-ci.yml:35-36), `ruff check --select E4,E7,E9,F .claude/hooks .claude/scripts`
  at ruff 0.17.4 (:37-43), and `actionlint` on `.github/workflows/*.yml` plus the
  assembled `templates/github/publish/*.yml` (:44-54).
- `/loop:ship`'s gate fence is pnpm-only (ship.md:30-63); the only kit-repo
  extension point is `## extra-gates` in `.claude/overlays/commands/loop/ship.md`
  (ship.md:68), absent in this repo → no lint runs.
- Incidents: PR #22 (shellcheck SC2010, fixed 79e65b5) and PR #24 (shellcheck
  SC1010 e4ea468, then ruff F841 33e0c07). Both passes reported every kit suite
  green. The ruff skip was not even recorded; shellcheck/actionlint were noted
  "not installed (CI runs them)" in PR bodies, i.e. silently accepted, against
  `rules/00-project.md` "a gate with no real script is reported missing, never
  invented or silently skipped".
- None of the three tools is installed on the dev machine; `uvx ruff@0.17.4` and
  `uvx --from shellcheck-py shellcheck` work; actionlint has no runner yet.
- `install.sh` `copy_tree` (:329-341) copies every file under the kit's `.claude/`
  that is not pruned: a kit-repo `.claude/overlays/...` would be shipped to
  installed projects.

## Scope
- IN : the kit repo's ship gates gain the three CI lint commands, at the same
  versions/flags/paths as kit-ci.yml, through runners that work without a
  system install; a tool that cannot run is a **red** gate reported missing,
  never a PR-body note; installed projects receive none of it; a check that the
  local list and kit-ci.yml stay in step (kit-doctor or the contracts suite).
- OUT: changing what CI lints or the lint rules themselves; fixing existing lint
  debt beyond what the new gate turns red; installed projects' own gates.

## Data model
none

## Custom backend
NONE — kit tooling only.

## Front surface
none (kit prompts, install.sh, kit-doctor / contracts suite).

## Acceptance criteria
- [ ] Shipping a pass in the kit repo with a shellcheck warning, a ruff E4/E7/E9/F
      finding, or an actionlint error in a workflow stops at the gate batch,
      before the commit, naming the file and rule.
- [ ] The three commands match kit-ci.yml's flags, paths and ruff version; a drift
      between the two is reported by a kit check, not found by CI.
- [ ] A lint tool that cannot be run makes the gate red with the reason "missing",
      it is not skipped and not downgraded to a note.
- [ ] `install.sh` into a fresh project and into an existing one ships none of the
      kit-repo-only gate wiring (no kit overlay, no lint lines in the target's
      ship gates).
- [ ] The kit's own suites stay green and the gate batch passes on current main.

## Business logic to cover
- Where the kit-repo gate list lives and that installed projects never get it.
- The kit-ci.yml ↔ local gate list parity check (green on equal, red naming the
  drifting step).
- A missing runner is a failing gate, not a skip.
