# Plan critic, pass 1 (2026-11-18, profile critical, effort high) — NOT yet verified, NOT routed
Scores: completeness 62 · quality 58. Verdict: not executable yet (1 Critical + 3 Major completeness, 4 Major quality).
The four user decisions were not re-opened by the critic.

## Found sound
- Steps 2-3 need no code: both consumers go through `cwk_is_kit_code` (`protect-files.sh:213-234`,
  `prevent-destructive-commands.sh:598-622` called `:787`); shell kit deny runs before the
  protected-dir asks (`:863-868`).
- Git needs exactly step 4: `KIT_PATTERNS` `enforce-git-workflow.sh:90`; `git rm -r` expanded by
  ls-files before `is_kit` (`:1440-1447`); checkout of a dir falls to `diff --name-only`; no kit
  prompt path holds a glob char.
- PK10 keeps passing (manifest read only when `cwk_installed`).
- Install order safe for fail-closed (hooks + prompts in one `copy_tree` `install.sh:686`, manifest after).
- Rules floor holds (line count only, `test-rules-floor.sh:35`). Supabase count 12/11 right.

## Completeness
- **F1 Critical, demonstrated** — addon override of `commands/database/migration.md` on re-install:
  `copy_override` looks only in `INSTALLED`, `copy_kit` records in `KIT_OVERWRITTEN`
  (`install.sh:114-127,134-143`). Fallback copy_file → core replaces fastapi/supabase migration.md,
  addon to `.new`; fallback copy_kit → second backup to same `$KIT_BACKUP/<rel>` clobbers the
  adapted backup. No re-install-with-addon case (IN45 fresh only, IN51 no addon).
  Closure: copy_override precedence also covers a file copy_kit overwrote this run; backup taken
  once per path (pre-run content); new case: re-install `--fastapi` over adapted fastapi
  migration.md → addon file in place, backup byte-identical to pre-run, no `.new`; IN51 runs with `--fastapi`.
- **F2 Major, demonstrated** — `wire_supabase` perl-writes the data client into 4 kit prompts
  (`install.sh:494-504`: templates/feature.md, patterns/react-query.md, templates/fixtures.md,
  templates/tooling-config.md); not in inventory/step 5. IN13 (`test-install.sh:466-477`) and
  `:86-89` would go red. Closure: step 5 removes those rewrites (keeps project.json + 05-testing
  twin); case: fresh `--supabase` leaves the 4 templates byte-identical to the kit; pins
  `test-install.sh:86-89,:477` listed as planned moves.
- **F3 Major, demonstrated** — coverage-floor/coverage-holes twin (`kit-doctor.py:373-387`) compares
  project-owned 05-testing.md with kit-owned tooling-config.md exclude; plan step 7 forgot it →
  EcoCrew (`05-testing.md:61` lib/api.ts) DIVERGENCE after upgrade, unfixable.
  Closure: coverage-holes compares tooling-config side in kit-source mode only; KD case: installed
  project with lib/api.ts in 05-testing.md + kit tooling-config → no DIVERGENCE.
- **F4 Major, interpretation** — fastapi addon README §3/§4 (`addons/fastapi/README.md:81-114`,
  installed as `skills/patterns/FASTAPI-ADDON.md`) and install.sh closing summary tell to edit
  ship.md, correctness.md AND `guides/review/security.md` (no slot for security.md).
  Closure: inventory gets a security.md slot; README §3/§4 and install summary name overlays;
  PK case: README + install.sh name `.claude/overlays/` and no edit under the four dirs.
- F5 Minor — github.md hard-codes base `main` (`:37-41`, `:153`); ADAPTATION §12 edits it; `branches`
  slot covers prefixes only.
- F6 Minor — CLAUDE.md overlay line never reaches an upgraded project (CLAUDE.md is copy_file →
  `.new`, `install.sh:693`); neither Port nor kit-doctor checks it.

## Quality
- **Q1 Major, demonstrated** — shipped-paths check (`kit-doctor.py:1036-1068`, exemptions
  RUNTIME_PATHS `:855-861`) would MISSING `.claude/overlays/…`, `.claude/recipes/`,
  `.claude/kit-manifest` → kit-doctor exit 1 (test-kit-doctor.sh:7, test-install.sh:26).
  Closure: step 7 exempts those three; KD case: kit source no shipped-paths MISSING, fresh install `No divergence.`.
- **Q2 Major, demonstrated** — the test-kit-doctor scratch counts as installed (`is_kit_source`
  `:908-912`); existing pins contradict KD17: `test-kit-doctor.sh:53` (DIVERGENCE client-copies),
  `:214` (ok tdd-layers), `:226` PD3 (DIVERGENCE tdd-layers), `test-install.sh:86` (ok client-copies).
  Closure: `## Gate amendments` lists each pin + replacement (kit-source fixture with install.sh +
  addons/ in scratch, or SKIP assertion).
- **Q3 Major, demonstrated** — `check_shared_dirs` also reads correctness.md's written count ("six
  entries", `kit-doctor.py:340-355`) → MISSING once removed. Closure: delete the `shared-dirs (count)`
  finding too; KD case: installed project with 7 shared_dirs → no count row.
- **Q4 Major, demonstrated** — IN48 (step 5) needs `templates/overlays/**`, created in step 6.
  Closure: step 5 creates `templates/overlays/commands/loop/ship.md`, or IN48 moves after step 6.
- Q5 Minor — `copy_file` writes `.new` whenever dest exists, no compare (`install.sh:98-106`) vs IN48 "only if it differs".
- Q6 Minor — Vigilance "addon not chosen this run never denied" contradicts the union rule / IN49.
- Q7 Minor — a seeded section holding only `<!-- FILL` : absent or not for the slot default? PK16
  conflicts with `## Recipes` / `## Local rules` (no slot line).
- Q8 Minor — "prompts adaptés" = KIT_OVERWRITTEN (includes unadapted kit changes, every upgrade);
  Port reads only the newest backup run → misses adapted copies after a second install.
- V1 — `--reach` subshell per manifest entry (~110) × operands × 2 vs 5 s hook timeout.
- V2 — enforce-git-workflow `declare -F` list (`:83`) must include `cwk_kit_patterns`.
- V3 — manifest write atomic (tmp + mv)? committed or gitignored? worktree reads its own copy.
- V4 — FASTAPI-ADDON.md (`install.sh:778`), SUPABASE-ADDON.md (`:744`) copy mode + manifest
  undecided; recipe.md "update the single authority" points to a denied prompt when installed.
