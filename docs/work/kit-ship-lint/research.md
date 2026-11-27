# Research: kit ship runs the CI lint locally   (entry: docs/specs/kit-ship-lint.md)
Token profile: economy

## Pattern to follow
- Project gates extend `/loop:ship` only through the overlay slot `## extra-gates` in
  `.claude/overlays/commands/loop/ship.md` (`.claude/commands/loop/ship.md:68`); the fence
  (:35-66) is pnpm-only and run as parallel tool calls by the model (:32), no runner script.
- Kit suites are `.claude/hooks/test-*.sh` scripts, already allowed as
  `bash .claude/hooks/test-*.sh` in `.claude/settings.json` (allow list :18-86) and run one per
  CI step (kit-ci.yml:55-80).
- Parity pins: `.claude/hooks/test-workflow-contracts.sh:833-841` (K2a harness-kit-ci) already
  greps kit-ci.yml for `args: check --select E4,E7,E9,F` (:836) and the actionlint run line (:838).

## Wiring points
- CI lint (`.github/workflows/kit-ci.yml`): tool install :21-32 (shellcheck v0.11.0, actionlint
  v1.7.12, sha256-checked); shellcheck :35-36 `shellcheck -S warning .claude/hooks/*.sh
  .claude/scripts/*.sh`; ruff :37-43 ruff-action v4.1.0, `version: 0.17.4`, `args: check --select
  E4,E7,E9,F`, `src: .claude/hooks .claude/scripts`; actionlint :44-45 on `.github/workflows/*.yml`;
  assembled targets :46-54 (`./install.sh "$d" --deploy="$t" </dev/null` per
  `templates/github/publish/*.yml`, then actionlint on `$d/.github/workflows/*.yml`).
- Kit-source detection: `is_kit_source()` kit-doctor.py:927-931 (root `install.sh` + `addons/`, no
  `.claude/INSTALL_PROFILE`); `kit_source_only()` :116-121. No kit-source branch in ship.md.
- install.sh `copy_tree` :329-345 prunes `__pycache__ .tdd-red worktrees kit-backup`, excludes
  `settings.json` and top-level `project.json` (:343); everything else under the kit's `.claude/`
  is copied (`*)` → copy_file :338-341). `seed_overlays` :217-226 seeds targets from
  `templates/overlays/` only, never from the kit's `.claude/overlays/`.
- kit-doctor `CHECKS` table :1516-1531; `check_gate_allowlist` :433-487 and `check_ci_scripts`
  :489-599 parse `pnpm` lines only and never read kit-ci.yml.

## Reusable
- The `extra-gates` overlay slot (no ship.md change needed to add a gate).
- The `bash .claude/hooks/test-*.sh` allow (a lint suite under that name runs without a prompt, no
  settings widening).
- Pinned runners, verified on this machine 2026-11-27: `uvx ruff@0.17.4`,
  `uvx --from shellcheck-py==0.11.0.1 shellcheck` (prints 0.11.0),
  `uvx --from actionlint-py==1.7.12.24 actionlint` (prints 1.7.12; current workflows pass) [fetched].
- K2a pin block in test-workflow-contracts.sh for the parity cases.
- `docs/research-cache/ci-lint-tools.md:18-55` (tool notes, ruff 0.16 default-set change → explicit
  `--select`) [cache].

## Blast radius
- A kit-repo `.claude/overlays/commands/loop/ship.md` **would be shipped to every target** by
  copy_tree unless `overlays` is pruned (install.sh:338-341); targets get their own from
  `templates/overlays/`.
- A new `.claude/hooks/test-*.sh` is copied into targets like every kit suite (copy_kit), harmless
  but present.
- `uvx`/`ruff`/`shellcheck`/`actionlint` appear in no allow entry and no guard rule
  (prevent-destructive-commands.sh: package runners :1064 exclude uvx; ruff write checks
  :1162 don't match `uvx ruff@… check`) → a bare uvx gate line prompts natively each ship.
- Assembled-targets actionlint runs install.sh into mktemp dirs (writes under /tmp).

## Live DB state
n/a

## External surface
- PyPI wrappers `shellcheck-py==0.11.0.1`, `actionlint-py==1.7.12.24` ship the same binaries as
  CI's pinned releases [fetched 2026-11-27, version output above]. uvx needs network on first run,
  cached afterwards.

## Traps (points of vigilance for the review)
- Kit-only gate wiring must not reach installed projects (overlay pruned, no lint lines in a
  target's ship gates, no settings.json allow widening shipped to targets).
- Flags/paths/versions must equal kit-ci.yml's; a drift must fail a kit check, not be found by CI.
- A runner that cannot run (no uvx, offline first run) is a red gate reported "missing", never a
  skip or a PR-body note.
- The suite must exit non-zero on any lint finding (no `|| true`, `set -e` traps in loops), and
  name file + rule.
- The new script must itself pass shellcheck.
- Assembled-targets step: temp dirs cleaned, install.sh stdin closed (CI uses `</dev/null`).

## Open questions
1. Placement: kit-repo overlay `.claude/overlays/commands/loop/ship.md` `## extra-gates` + prune
   `overlays` in install.sh copy_tree (recommended: existing slot, one prune), or a kit-source
   branch in ship.md?
2. Runner shape: one suite `.claude/hooks/test-kit-lint.sh` (all three tools + assembled targets,
   covered by the existing `bash .claude/hooks/test-*.sh` allow, no new permission) — recommended —
   or three `uvx …` gate lines with new allow entries?
3. Parity check: pins in test-workflow-contracts.sh comparing the suite's commands to kit-ci.yml
   (recommended, next to K2a), or a new kit-doctor `kit_source_only` check?
4. Does CI switch to calling the same suite? Spec OUT says CI lint stays as is → keep CI unchanged
   (recommended), parity pin guards drift.
