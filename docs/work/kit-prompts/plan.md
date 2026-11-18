# Plan: Kit prompts, pass 2b   (entry: docs/specs/kit-prompts.md · research: docs/work/kit-prompts/research.md · design: n/a)
Token profile: critical
Base: 195d88b

## Skips
- DB: SKIP, no data. Backend: SKIP, kit tooling. INTERFACE: SKIP, no screen.
- Front test-first layers (`utils`/`mapper`/`repository`): none. The TDD hooks key on
  `src/`/`shared/`; every file here is a hook, script, suite or prompt.
  - The kit's own discipline applies: each step writes its cases into the suite first, runs
    them red, then writes the code. The main thread writes `.claude/hooks/` suites
    (test-writer's guard denies that folder, ship-audit-surface handoff).
  - Case ids continue the existing series: `KB27+` (test-hooks.sh), `G19.051+` (git harness in
    test-hooks.sh), `IN44+` (test-install.sh), `KD15+` (test-kit-doctor.sh), `PK15+`
    (test-workflow-contracts.sh).
- EXECUTE routing: `execute-green` says codex, but the Codex sandbox fails here
  (`bwrap: loopback RTM_NEWADDR`, ship-audit-surface handoff) → EXECUTE stays on Claude.
- The EcoCrew upgrade itself: OUT of this pass (spec `## Next work`, proposed after ship).
  AC4 is proved on an EcoCrew-shaped fixture (IN51), the real run is the user's go.

## Decisions taken before writing (user, 2026-11-18, AskUserQuestion)
1. **Deny scope: kit files only.** `install.sh` writes `.claude/kit-manifest`, the list of the
   prompts it ships (core + addons). The hooks deny exactly those paths in an installed
   project. A project's own skill/agent/command/guide stays writable.
2. **New homes: project.json + overlays.** A value a hook or kit-doctor checks lives in
   `.claude/project.json`; prose lives in project-owned overlays
   `.claude/overlays/<path under .claude>` (e.g. `.claude/overlays/commands/loop/ship.md`), one
   `## <slot>` section per value. One hot line in CLAUDE.md tells the agent to read a prompt's
   overlay before following it; this is also the local escape path (spec OQ2).
3. **Recipes: project folder.** In an installed project `/kit:recipe` writes
   `.claude/recipes/<name>.md` and cites it in the invoking prompt's overlay, `## Recipes`.
   In the kit repo it keeps writing `.claude/guides/<name>.md` and citing in the prompt.
4. **Upgrade: backup + guided port.** `install.sh` overwrites kit prompts (old copy in
   `.claude/kit-backup/<run>/`) and lists each adapted one; `/kit:init` ports their values into
   the overlays / project.json proposal with the user. No parser of old prose.

## Proposed answers to research's open questions (taken at `## Gate`)
- OQ1 overlay form → decision 2. No new project.json key is needed: no hook reads a branch
  prefix, a deploy command or a migration CLI. The schema stays at 3 (no migrate change).
- OQ2 deny unit → decision 1.
- OQ3 kit-repo behaviour → the manifest is NOT `CWK_KIT_CODE`: prompts are matched by a separate
  function, called only when `cwk_installed`. PK10 stays as is (it covers `CWK_KIT_CODE`); the
  kit repo keeps today's pass on prompts (no guarded ask). `.claude/kit-manifest` itself joins
  `CWK_KIT_CODE` and `CWK_GUARDED`.
- OQ4 escape path → the overlay (decision 2): a project adds `## Local rules` to a prompt's
  overlay; it never edits the prompt.
- OQ5 `/kit:recipe` → decision 3.
- OQ6 upgrade → decision 4. The four dirs move to `copy_kit`: no `.new` for a prompt any more.
- OQ7 addon prompts → kit code: listed in the manifest, overwritten with backup; the winner of
  a core/addon overlap is decided once per destination (step 5: addon chosen this run, else the
  addon whose `<ADDON>-ADDON.md` marker is in the target), `copy_override` leaves the prompts.
- OQ8 guard api → `hook-guarded.sh` `cwk-guard-api: 7 → 8` (the kit-code predicate changes;
  IN37/IN41 read the number from the kit, no pin to move).
- Manifest absent in an installed project (deleted, or a hand-copied hook set) → fail-closed:
  every path under the four dirs counts as kit code, and kit-doctor reports `MISSING kit-manifest`.
- A manifest entry from an earlier run whose file still exists stays listed (union), so an
  addon not re-chosen this run is not silently made writable.
- `doc-researcher` `tools:` (frontmatter, no overlay can reach it) → step 0 spike: if Claude Code
  loads an agent whose `tools:` names an absent MCP tool, the kit lists Context7's tools
  unconditionally; otherwise the FILL is replaced by a line saying Context7 is unavailable to
  this agent in an installed project (step 3 of its order skipped) and ADAPTATION §13 says so.
- Supabase addon: 12 `<!-- FILL` headers in 11 patterns (not in research; found while planning:
  `addons/supabase/skills/{patterns,templates}/*.md:3`, `edge-function-tests.md:180`) are
  "placeholder example names" notes → reworded as a plain note ("`example-*` names are
  placeholders: use this repo's names when applying"), no slot.

## Slot inventory (P1 → P2), the overlay each value moves to
| Prompt (kit path) | Slot | Default when the overlay section is absent |
| --- | --- | --- |
| `commands/loop/ship.md:55` | `extra-gates` (second unit runner) | none: only the fence runs |
| `commands/loop/ship.md:130` | `deploy` (commands + traps) | "no deploy known: ask the user" |
| `commands/loop/ship.md:47-50` bundle scan `src/` | none: reads `app_roots` (`<root>/src`, `src/` when empty) | — |
| `agents/github.md:27` | `branches` (prefixes) | `feat/ fix/ chore/ docs/`; protected = project.json `protected_branches` |
| `commands/loop/research.md:90` | `probes` (extra mandatory rows) | the four generic rows |
| `commands/audit/mutation.md:53` | `globs` | globs from `app_roots` + `tdd_layers` (text says so) |
| `commands/database/migration.md:12` | `migrations` (folder, CLI, apply) | stop and ask |
| `skills/templates/tooling-config.md:360` | `coverage-globs` | the 05-testing.md scope |
| `skills/templates/tooling-config.md:324` | none: "the `data_client.own_path` of project.json" | — |
| `skills/patterns/forms.md:12` | `field-schemas` (folder) | `src/features/<f>/schemas` |
| `skills/patterns/feedback.md:3` | `components` (table) | the kit table as an example |
| `skills/patterns/feedback.md:208` | `strings` | strings in the 03-conventions.md language |
| `skills/patterns/guards.md:3` | `names` (helpers, routes) | the kit names as an example |
| `skills/e2e-playwright/SKILL.md:8,15,65` | `drivers`, `harness`, `backend-case` | `backend-case` absent → stop and ask (most important section) |
| `skills/templates/feature.md:8`, `fixtures.md:82`, `patterns/react-query.md` | none: "replace `lib/client` by `data_client.module`" | — |
| `guides/review/correctness.md:15-17` | none: "the `data_client.shared_dirs` of project.json" | — |
| `guides/review/correctness.md` (EcoCrew :129-130) | `extra-checks` | none |
| `guides/review/security.md` (fastapi README §4: 07-backend.md lines) | `extra-checks` | none |
| `guides/10-worktrees.md:88` | `foundations` (extra shared foundations) | the kit list |
| `agents/doc-researcher.md:9` | step 0 spike (above) | — |

Overlay templates live in the kit at `templates/overlays/<same path>` (outside the four dirs,
so never kit-denied by name), each section holding `<!-- FILL: … -->` until filled. `install.sh`
copies them to `.claude/overlays/` with `copy_file` (project-owned: never overwritten, `.new`
when the template changed). A prompt slot is a visible line:
`**Project slot `<slot>`** — `## <slot>` in `.claude/overlays/<path>`; absent → <default>.`

## Write chain (sequential)
0. **Spike** (no file kept): an agent whose `tools:` names an absent MCP tool — loads or not.
   Settles the doc-researcher row; result written into `## Gate` as an amendment line.
1. **Manifest predicate** (`hook-guarded.sh`): `cwk_kit_prompt <rel> [--reach]` reads
   `$CLAUDE_PROJECT_DIR/.claude/kit-manifest` (one repo-relative path per line; a line outside
   `.claude/{agents,commands,skills,guides}/`, with `..`, absolute, or outside `[A-Za-z0-9._/-]`
   is ignored); absent file → every path under the four dirs matches (fail-closed). `--reach`:
   a folder above an entry matches. `cwk_is_kit_code` calls it only when `cwk_installed`.
   `CWK_KIT_CODE` += `.claude/kit-manifest`; `CWK_GUARDED` += `.claude/kit-manifest`.
   `cwk_kit_patterns` prints `CWK_KIT_CODE` then the manifest entries (or the four dir globs when
   fail-closed) for the git hook. Api stamp 7 → 8. Cases KB27-KB33.
2. **Write/Edit** (`protect-files.sh`): nothing to add if step 1 lands in `cwk_is_kit_code`;
   prove it. Cases KB34-KB36.
3. **Shell** (`prevent-destructive-commands.sh` `guard_kit_code`): same, prove it, reach
   included. Cases KB37-KB40.
4. **Git** (`enforce-git-workflow.sh:90`): `KIT_PATTERNS="$(cwk_kit_patterns)"` instead of the
   bare `CWK_KIT_CODE` (only when installed; the kit repo keeps today's list). G19.051-G19.055.
4b. **kit-doctor installed-mode gating, before any copy_kit (Q9).** `check_client_copies`,
   `check_tdd_layers`, `coverage-holes` and `coverage-floor` (`kit-doctor.py:255-276, :357-387`,
   F3) compare prompt copies in kit-source mode only (installed: those templates hold kit
   defaults by design → SKIP line naming why); `check_protected_branches` removed (its prompt
   side becomes a project.json read in step 6; the check is dropped here so no pin moves twice).
   Cases KD17, KD20, KD21. Pin moves of this step (`## Gate amendments`): `test-kit-doctor.sh:53,
   :214, :226` and the protected-branches pins; `test-install.sh:86-87` → SKIP lines;
   `test-install.sh:477` deleted (`lib/supabase` stays pinned on project.json at `:476`).
   `test-install.sh:481-482` (IN13 refuses `DIVERGENCE client-copies`) is unchanged: it holds
   with the SKIP. `test-install.sh` and `test-kit-doctor.sh` run end to end green at its close.
5. **install.sh**: `copy_tree` arm for `$TARGET/.claude/{agents,commands,skills,guides}/*` →
   `copy_kit`; addon prompt copies (`:735-767`) → `copy_kit`.
   - **One source per destination (F1, F7).** Before any prompt copy, install.sh builds the map
     destination → source: core first, then an addon replaces the core source for the same
     path (today only `commands/database/migration.md`). The winner of an addon-overlapped
     destination is, in order: (1) an addon chosen this run (both chosen: the later one in
     install.sh's addon order, today fastapi, as now); (2) else the addon whose marker
     `.claude/skills/patterns/<ADDON>-ADDON.md` exists in the target (installed by an earlier
     run; every addon run copies it, `:744`, `:778`, nothing deletes it); (3) both markers and
     no flag → the destination is left in place, not copied, and named in the summary only
     when it differs from both addon copies (identical to either → silent, Q17). Each
     destination gets at most one `copy_kit` from its winner, so one backup per path per run,
     taken from the pre-run content. `copy_override` is removed for prompts (no prompt caller
     left). A destination already byte-identical to its winner is neither backed up nor listed.
   - Record every prompt it copies; write `.claude/kit-manifest` (sorted union with surviving
     entries of the previous manifest) after the copies; summary: a block "prompts adaptés"
     listing overwritten prompts with "porte leurs valeurs avec /kit:init (étape Port)"; seed
     `templates/overlays/**` → `.claude/overlays/` with `copy_file`. Step 5 creates the first
     overlay template, `templates/overlays/commands/loop/ship.md` (Q4: IN48 runs green here);
     step 6 adds the others. Drop the `init.md.new` note (`:809-811`, init.md is now
     overwritten). Header `:24-28` and comment `:230-232` updated. The fastapi closing summary
     (`:868-872`) names `.claude/overlays/commands/loop/ship.md` and the `extra-checks` sections
     of the `correctness.md`/`security.md` overlays instead of editing those prompts (F4).
   - Cases IN44-IN53, IN55-IN58 (IN54 lands in step 7), plus the kit-boundary pin move
     `test-install.sh:660-663`; the SKIP-related pin moves already landed in step 4b.
     `test-install.sh` runs end to end green at the close of step 5 (IN13 included).
6. **Prompts (P2)**: replace every class-(a) FILL by its slot line (table above), class (b)/(c)
   by a plain reference to its home; reword prose mentions of the marker
   (`templates/ci.md:75`, `patterns/msw.md:21`, `kit/doctor.md:152,:162`, `kit/init.md:28,:133`)
   so the literal `<!-- FILL` / `— FILL>` marker appears in no prompt; supabase addon notes;
   `github.md` names project.json `protected_branches` and the `branches` slot (its sentence
   "a commit on `main`/`master`" becomes "on a branch of `protected_branches`");
   `correctness.md` names `data_client.shared_dirs`; create `templates/overlays/**` (one file per
   prompt with a slot); CLAUDE.md hot line (one line, `Kit code …` line at :34 extended:
   "Kit prompts are kit code too; a prompt's project values and local rules live in
   `.claude/overlays/<its path>`, read it before following the prompt."). `addons/fastapi/README.md`
   §3 (`:81-86`) and §4 (`:107-112`) tell to fill the `extra-gates` section of the ship overlay
   and the `extra-checks` sections of the `correctness.md`/`security.md` overlays, never to edit
   those prompts (F4). Cases PK15-PK20.
7. **kit-doctor**: `check_fill_markers` drops `.claude/commands`, `skills/templates`,
   `skills/patterns` and adds `.claude/overlays/**` (installed mode; kit mode scans
   `templates/overlays/**` — those FILLs are expected there and stay informational); new
   `check_prompt_fill` (all four dirs + `addons/*/{agents,commands,skills,guides}`, kit-source
   mode: any `<!-- FILL`/`— FILL>` → DIVERGENCE `prompt-fill`); in `check_shared_dirs` both the
   `shared-dirs (reviewer)` copy and the `shared-dirs (count)` finding that reads
   correctness.md's "six entries" (`:340-353`) are removed (Q3); (the installed-mode gating
   and `check_protected_branches` removal already landed in step 4b); shipped-paths check (`:1036-1068`) exempts the `.claude/overlays/` and `.claude/recipes/`
   prefixes (startswith) and `.claude/kit-manifest` in kit-source mode (Q1).
   **Then, in this step (the installed-mode gating is green since step 4b):** `wire_supabase` stops
   rewriting kit prompts (F2): the 4 perl edits of `templates/feature.md`,
   `patterns/react-query.md`, `templates/fixtures.md`, `templates/tooling-config.md`
   (`install.sh:494-501`) go; project.json and the `05-testing.md` twin stay. Those prompts
   already say "replace `lib/client` by `data_client.module`" (step 6). IN54 and the pin moves
   of `test-install.sh:88-89` land here. `test-install.sh` runs end to end green at the close of
   step 7. New
   `check_kit_manifest` (installed: present, every entry exists → ok; absent → MISSING
   "relance install.sh"; kit-source: absent expected → no row). `doctor.md` table rows updated.
   Cases KD15, KD16, KD18, KD19, KD22, KD23.
8. **/kit:init, /kit:recipe, ADAPTATION, README**: init steps 2, 9, 10, 12 write overlays (or
   the project.json proposal), never a path under the four dirs; new step "Port" (after an
   upgrade): read the newest `.claude/kit-backup/<run>/` copies of the prompts install.sh listed,
   show each adapted slot's old text, write the overlay section the user confirms, put
   protected branches into the proposal; `:133` audit grep targets `.claude/overlays`,
   `.claude/rules`, `CLAUDE.md`. `recipe.md`: installed → `.claude/recipes/<name>.md` + overlay
   `## Recipes` citation; kit repo → today's behaviour. ADAPTATION §2, §9, §10, §12, §13, §15 and
   the kit-code list (`:505-520`) rewritten to overlays/manifest; README kit-code paragraphs.
   Cases in PK18-PK19 cover them.
9. **Gate run**: every kit suite (`test-hooks.sh`, `test-workflow-contracts.sh`,
   `test-install.sh`, `test-kit-doctor.sh`, `test-rules-floor.sh`, `test-audit-surface.sh`,
   `test-gate-route.sh`, `test-attempts.sh`, `test-small-lane.sh`, `test-measure.sh`,
   `test-pr-assets.sh`), `python3 .claude/hooks/kit-doctor.py` (kit source: no DIVERGENCE),
   shellcheck/ruff when installed.

## Parallel lots
none — fully sequential (steps 1-5 share `hook-guarded.sh`/`test-hooks.sh`/`install.sh`; step 6
feeds 7 and 8).

## Track isolation
- Worktree: none, single track (main tree, `audit/slim`).
- Shared foundations touched: the guard hooks (`hook-guarded.sh` api 8), `install.sh`, every kit
  prompt. No other kit pass runs beside this one until it is merged.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/hook-guarded.sh` | Edit | `cwk_kit_prompt`, `cwk_kit_patterns`, manifest in lists, api 8 |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | `KIT_PATTERNS` from `cwk_kit_patterns` |
| `.claude/hooks/protect-files.sh`, `prevent-destructive-commands.sh` | Edit only if a case needs it | consumers |
| `.claude/hooks/test-hooks.sh` | Edit | KB27-KB40, G19.051-G19.055 |
| `install.sh` | Edit | copy_kit arm, manifest, overlays seed, summary |
| `.claude/hooks/test-install.sh` | Edit | IN44-IN58, pin moves (Gate amendments) |
| `.claude/hooks/kit-doctor.py`, `test-kit-doctor.sh` | Edit | checks above, KD15-KD23, pin moves |
| `addons/fastapi/README.md` | Edit | §3/§4 point at overlays |
| `.claude/guides/review/security.md` | Edit | `extra-checks` slot line |
| `.claude/commands/kit/doctor.md` | Edit | table rows |
| the 14 class-(a) prompts, `templates/feature.md`, `fixtures.md`, `patterns/react-query.md`, `templates/ci.md`, `patterns/msw.md`, `guides/review/correctness.md`, `guides/10-worktrees.md`, `agents/doc-researcher.md` | Edit | slots / references |
| `addons/supabase/skills/{patterns,templates}/*.md` (11) | Edit | FILL notes reworded |
| `templates/overlays/**` | Create | one overlay template per prompt with a slot |
| `.claude/commands/kit/init.md`, `kit/recipe.md` | Edit | new homes, Port step, recipes |
| `CLAUDE.md` | Edit | kit-code line extended (one line, floor 517 → ≤ 518 of 520) |
| `docs/ADAPTATION.md`, `README.md` | Edit | homes, manifest |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | PK15-PK20 |

## Contracts
- `.claude/kit-manifest`: UTF-8 text, one repo-relative path per line, sorted, no comment, only
  paths under `.claude/{agents,commands,skills,guides}/`. Written only by `install.sh`.
- `cwk_kit_prompt <rel> [--reach]` → exit 0 kit prompt, 1 not; never prints.
- `cwk_kit_patterns` → newline list, `CWK_KIT_CODE` first; manifest entries are literal paths
  (the charset rule makes them glob-safe for bash `[[ == ]]` and `fnmatch`).
- Overlay file: markdown, `## <slot>` sections, any order; `## Recipes` and `## Local rules`
  allowed on every overlay.

## Test plan (gate — validated by the user before EXECUTE)

### Step 1 — manifest predicate (test-hooks.sh, block KB, `kb_setup` + a `manifest` writer)
- [ ] KB27 in an installed project whose manifest lists `.claude/commands/loop/ship.md`, `cwk_is_kit_code .claude/commands/loop/ship.md` exits 0
- [ ] KB28 in the same project, a project-owned `.claude/skills/own/SKILL.md` (not listed) exits 1, and so does `.claude/overlays/commands/loop/ship.md`
- [ ] KB29 with `--reach`, `.claude/commands` and `.claude/commands/loop` exit 0 (above a listed entry); `.claude/skills/own` exits 1
- [ ] KB30 an installed project with no manifest: `.claude/skills/own/SKILL.md` and `.claude/guides/x.md` exit 0 (fail-closed); `.claude/overlays/x.md` and `.claude/recipes/r.md` exit 1
- [ ] KB31 in the kit repo (`kitlike`), `.claude/commands/loop/ship.md` exits 1 even with a manifest file present
- [ ] KB32 manifest lines `../x`, `/abs`, `.claude/hooks/y`, `src/a.ts`, `.claude/skills/*` and `.claude/skills/a b.md` are ignored (each path exits 1); a valid line after them still exits 0
- [ ] KB33 `.claude/kit-manifest` is kit code in an installed project and `cwk_is_guarded` in the kit repo
### Step 2 — Write/Edit (test-hooks.sh, `project_hook_probe` on protect-files.sh)
- [ ] KB34 installed: Write and Edit of a listed prompt are denied with the `CWK_KIT_DENY` text
- [ ] KB35 installed: Write of a project-owned skill, of `.claude/overlays/commands/loop/ship.md` and of `.claude/recipes/r.md` pass
- [ ] KB36 kit repo: Edit of `.claude/commands/loop/ship.md` passes with no ask
### Step 3 — shell (test-hooks.sh, prevent-destructive-commands.sh probes)
- [ ] KB37 installed: `sed -i s/a/b/ .claude/commands/loop/ship.md` and `printf x > .claude/agents/github.md` are denied (kit code)
- [ ] KB38 installed: `rm -r .claude/commands` and `mv .claude/agents/github.md /tmp/` are denied (reach)
- [ ] KB39 installed: `printf x > .claude/skills/own/SKILL.md` and `printf x > .claude/overlays/a.md` get no kit-code verdict
- [ ] KB40 kit repo: `sed -i s/a/b/ .claude/commands/loop/ship.md` gets no kit-code verdict
### Step 4 — git (test-hooks.sh, `kb_git` on tmp repos with the prompts committed)
- [ ] G19.051 installed: `git checkout HEAD -- .claude/commands/loop/ship.md` is denied naming the path
- [ ] G19.052 installed: `git rm .claude/agents/github.md` is denied
- [ ] G19.053 installed: `git checkout HEAD -- .claude/skills/own/SKILL.md` gets no kit verdict
- [ ] G19.054 installed with no manifest: `git restore .claude/guides/x.md` is denied (fail-closed)
- [ ] G19.055 kit repo: `git checkout HEAD -- .claude/commands/loop/ship.md` gets no kit verdict
### Step 4b — kit-doctor installed-mode gating (test-kit-doctor.sh, block KD; before any copy_kit)
- [ ] KD17 installed tmp project whose project.json has `protected_branches: ["develop"]` and `data_client.module: "lib/api"` reports no DIVERGENCE on protected-branches, client-copies or tdd-layers
- [ ] KD21 installed tmp project whose `05-testing.md` names `lib/api.ts` and a floor of 80, beside the kit `tooling-config.md`, reports no DIVERGENCE on coverage-holes nor coverage-floor (SKIP lines naming why)
- [ ] KD20 kit source with `lib/api` written in a tmp copy of `templates/fixtures.md` still reports `DIVERGENCE client-copies` (the kit-mode check survives; regression guard, green from the start)
- pin moves of this step: see `## Gate amendments to validate`; at its close `test-install.sh` (IN13 `:481-482` unchanged) and `test-kit-doctor.sh` run green
### Step 5 — install.sh (test-install.sh, block IN)
- [ ] IN44 a fresh install writes `.claude/kit-manifest`: sorted, one line per file of the kit's four dirs (same count as `find`), no line outside them
- [ ] IN45 an install with `--fastapi` also lists the addon prompts (`.claude/commands/backend/…`, `.claude/commands/database/migration.md`)
- [ ] IN46 a re-install over an edited `commands/loop/ship.md` overwrites it with the kit copy, keeps the old one byte-identical in `.claude/kit-backup/<run>/`, writes no `ship.md.new`, and lists it under the adapted-prompts block naming `/kit:init`
- [ ] IN47 a project-owned `.claude/skills/own/SKILL.md` is untouched, absent from the manifest and from the backup
- [ ] IN48 a fresh install seeds `.claude/overlays/commands/loop/ship.md` from `templates/overlays/commands/loop/ship.md` (created in step 5); a re-install keeps an edited overlay byte-identical (the template copy lands beside it, per `copy_file`)
- [ ] IN49 a manifest entry of a previous run whose file still exists stays listed after a run that did not copy it; an entry whose file is gone is dropped
- [ ] IN50 a re-install with no change prints `kit code: up to date` and rewrites an identical manifest
- [ ] IN51 an EcoCrew-shaped target (no project.json, old hooks, adapted `agents/github.md`, `commands/loop/ship.md`, `skills/e2e-playwright/SKILL.md`, `skills/templates/tooling-config.md`, `guides/review/correctness.md`, `guides/10-worktrees.md`, own `skills/patterns/snapshot-tests.md`) upgrades to: project.json v3, the six prompts in the backup byte-identical and listed as adapted, `snapshot-tests.md` untouched and unlisted
- [ ] IN52 a re-install with `--fastapi` over an adapted fastapi `commands/database/migration.md` leaves the fastapi kit copy in place (not core), keeps the adapted copy byte-identical in `.claude/kit-backup/<run>/`, writes no `migration.md.new`, and lists it once as adapted
- [ ] IN53 a second `--fastapi` re-install with no edit leaves `commands/database/migration.md` byte-identical to the fastapi copy, with no backup of it and no adapted line for it
- [ ] IN56 after a `--fastapi` install, a re-install with no addon flag (`--no-ci`) leaves `commands/database/migration.md` byte-identical to the fastapi kit copy, with no backup of it and no adapted line for it
- [ ] IN57 the same after a `--supabase` install: `commands/database/migration.md` stays byte-identical to the supabase kit copy, with no backup of it and no adapted line for it (assertions scoped to that path: until step 7 the 4 supabase-rewritten templates are still backed up)
- [ ] IN58 after `--supabase` then `--fastapi` (both markers present) and a hand edit of `commands/database/migration.md`, a re-install with no addon flag leaves it byte-identical to the edit, with no backup of it and no adapted line, names it in the summary, and keeps it in `.claude/kit-manifest`
- [ ] IN55 the fastapi closing summary names `.claude/overlays/` and no longer tells to edit `commands/ship.md`, `correctness.md` or `security.md`
- planned pin moves: see `## Gate amendments to validate`
### Step 6 — prompts (test-workflow-contracts.sh, block PK)
- [ ] PK15 no `<!-- FILL` and no `— FILL>` in `.claude/{agents,commands,skills,guides}/**` nor `addons/*/{agents,commands,skills,guides}/**`
- [ ] PK16 every `**Project slot `x`**` line names `.claude/overlays/<its own path>`, and `templates/overlays/<its own path>` holds a `## x` section; every overlay template section has a slot line pointing at it
- [ ] PK17 `github.md` names `protected_branches` of `.claude/project.json` and lists no branch name literal in its protected sentence; `correctness.md` names `data_client.shared_dirs` and lists no `src/<dir>` count
- [ ] PK18 ADAPTATION §2/§9/§10/§12/§13 and `init.md` steps 2/9/10/12 name `.claude/overlays/` or the project.json proposal, and no line tells to edit a path under the four dirs; `init.md` has a Port step naming `.claude/kit-backup/`
- [ ] PK19 `recipe.md` names `.claude/recipes/` and `## Recipes` for an installed project; CLAUDE.md's kit-code line names kit prompts and `.claude/overlays/`; README and ADAPTATION's kit-code list name `.claude/kit-manifest`
- [ ] PK20 `addons/fastapi/README.md` §3/§4 name `.claude/overlays/` and contain no instruction to edit a path under `.claude/{agents,commands,skills,guides}/`; `templates/overlays/guides/review/security.md` holds `## extra-checks`
- [ ] PK21 (added, review round 1 C1) the ship.md bundle-scan fence reads `app_roots` of `.claude/project.json`, no `test -d src/` literal; run with `app_roots: ["frontend"]` it scans `frontend/src` and prints no `SCAN NOT RUN`
- [ ] PK22 (added, review round 1 CM2) every kit prompt example importing `@/lib/client` (feature.md, fixtures.md, react-query.md) names `data_client.module`
- [ ] PK23 (added, review round 2 T3) the fence run with `app_roots: []` scans `src/` and prints its hit; a declared root whose `src` is absent prints `SCAN NOT RUN: no <root>/src`
### Step 7 — kit-doctor (test-kit-doctor.sh, block KD) then the supabase rewrite removal (test-install.sh)
- [ ] IN54 (written after this step's KD cases are green) a fresh `--supabase` install leaves `templates/feature.md`, `patterns/react-query.md`, `templates/fixtures.md` and `templates/tooling-config.md` byte-identical to the kit, and still writes `lib/supabase` into project.json and `05-testing.md`
- [ ] KD15 kit source with a `<!-- FILL` added to a tmp copy of `.claude/agents/x.md` reports `DIVERGENCE prompt-fill` and exits 1; the real kit reports `ok prompt-fill`
- [ ] KD16 installed tmp project: an overlay section still holding `<!-- FILL` is reported `FILL` naming the overlay path (exit 0); once filled, it is not listed
- [ ] KD18 installed tmp project with no `.claude/kit-manifest` reports `MISSING kit-manifest` naming install.sh; with a manifest whose every entry exists, `ok kit-manifest`; an entry whose file is gone → `MISSING` naming it
- [ ] KD19 kit source: no `kit-manifest` row
- [ ] KD22 installed tmp project whose project.json has 7 `shared_dirs` reports no `shared-dirs` count row and no DIVERGENCE on shared-dirs
- [ ] KD23 the kit source reports no `MISSING` for `.claude/overlays/…`, `.claude/recipes/` or `.claude/kit-manifest`; a fresh install (no `.claude/recipes/`) prints `No divergence.`
### Test-after
- `/kit:init` Port step and `/kit:recipe` installed route: prose, covered by PK18/PK19; exercised
  by hand on the EcoCrew upgrade (Next work).

## Gate amendments to validate (written into `## Gate` on the go)
- kit-boundary IN block `test-install.sh:660-663`: init.md moves from `.new` to overwritten (step 5).
- `check_protected_branches` (step 4b), the reviewer copy and the count finding of
  `check_shared_dirs` (step 7) are deleted, their prompt copies being gone; any kit-doctor test
  pinning those rows moves with them, in the step that deletes the check.
- Pins contradicted by the installed-mode SKIP (Q2, F2, F3), each with its replacement, all
  moved in step 4b (Q9) except `:88-89`, moved in step 7 with IN54:
  - `test-kit-doctor.sh:53` (`DIVERGENCE client-copies`) and `:226` PD3 (`DIVERGENCE
    tdd-layers`): the scratch becomes a kit-source fixture for those two cases (`install.sh`
    and `addons/` stubs in the scratch), assertions unchanged.
  - `test-kit-doctor.sh:214` (`ok tdd-layers`): becomes the SKIP line for tdd-layers.
  - `test-install.sh:86` (`ok client-copies`) and `:87` (`ok coverage-holes`): become the SKIP
    lines; `:88-89` (supabase import/mock in feature.md/fixtures.md) become "byte-identical to
    the kit" (IN54).
  - `test-install.sh:477` (IN13, `lib/supabase` in feature.md): deleted, `lib/supabase` stays
    pinned on project.json's `data_client.module` at `:476` (step 5's copy_kit reverts the
    template in IN13's second run). `:481-482` unchanged: it holds once client-copies SKIPs.
- CLAUDE.md +≤1 line (517 → ≤ 518, ceiling 520).

## Vigilance (carried from research)
- PK10 still holds: no manifest entry is added to `CWK_KIT_CODE`; the kit repo never asks on a prompt.
- `.claude` in `protected_dirs` already asks on `mv`/`rm -r` there: the kit deny must win in an
  installed project (deny before ask), and the kit repo keeps exactly today's asks.
- The manifest is written AFTER the copies of the same run and BEFORE the summary; a failed run
  never leaves a manifest that lists a file it did not install.
- No adapted prompt is lost: every overwritten prompt is in the backup byte-identical, listed.
- A project-owned prompt (Impeccable, own skill) is never denied, overwritten nor backed up
  unless the kit ships the same path. An addon prompt installed by an earlier run stays kit
  code (manifest union, IN49) even when that addon is not re-chosen (Q6).
- One source per destination: an addon prompt wins over core for the same path, one backup
  per path per run, from the pre-run content (F1).
- `github.md` also hard-codes base `main` (`:37-41`, `:153`); the `branches` slot covers
  prefixes only: check the base sentence reads project.json, not a literal (F5).
- CLAUDE.md is `copy_file`: an upgraded project gets the overlay line only in `CLAUDE.md.new`;
  the Port step must name that merge (F6).
- `copy_file` writes its copy whenever dest exists, without compare (`install.sh:98-106`) (Q5).
- An overlay section holding only `<!-- FILL` counts as absent (slot default applies);
  `## Recipes` and `## Local rules` are exempt from PK16's slot-line rule (Q7).
- Other kit-doctor twins with a prompt side (audit-flags, ci-scripts, gate-allowlist on ship.md;
  agent-models/agent-efforts on agents/*, `kit-doctor.py:458-499, :597-606, :644-670`): check each
  can always be fixed from its project-owned side, or is kit-source only (F8).
- shipped-paths `rstrip("./\`,;:)")` runs before the exemption (`kit-doctor.py:1043-1045`):
  match `.claude/overlays` / `.claude/recipes` with and without the trailing slash; the recipes
  and overlays exemptions hold in installed mode too (Q10).
- IN55/PK20 in a decidable form: every path under the four dirs named in README §3/§4 and the
  fastapi summary is prefixed by `.claude/overlays/` (Q11).
- `FASTAPI-ADDON.md` (`install.sh:778`, `copy_file`) and `SUPABASE-ADDON.md` (`:744`): decide copy
  mode + manifest so an upgraded project does not keep advice to edit a denied prompt (Q12).
- KD22's fixture lists the same 7 `shared_dirs` in 02-architecture.md and CLAUDE.md (Q13).
- The kit-source fixture replacing `test-kit-doctor.sh:53` covers the whole client-copies block
  (`:53-59`, evidence lines included) and PD3 inside `pd_run`, and its `install.sh`/`addons/`
  stubs are removed before KD12 (`:262-266`), which expects installed mode (Q15).
- "prompts adaptés" = overwritten-and-different, which includes unadapted kit changes; the
  Port step reads every backup run since the last Port, not only the newest (Q8).
- The FILL scan must not count prose mentions; PK15 and `check_prompt_fill` use the same marker.
- kit-doctor twins whose rule side was a prompt are removed or kit-mode only, never left
  comparing a kit default against a project value (false DIVERGENCE in every installed project).
- Prose values are never parsed: the port is guided (`/kit:init`), not automatic.
- EcoCrew has no project.json: IN51 runs migrate-from-absent and this pass together.
- Rules floor: CLAUDE.md grows by at most one line.
- Fail-closed when the manifest is absent, and the reader ignores (never trusts) a malformed line.

## Acceptance criteria (carried from the entry artifact)
- [ ] No kit prompt holds a per-project value; `kit-doctor.py` checks the new homes.
- [ ] Kit prompts are denied in an installed project through Write/Edit, shell and git.
- [ ] `/kit:init` and `/kit:recipe` work in an installed project with no prompt write.
- [ ] `install.sh` upgrades EcoCrew with no lost adaptation.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Plan critic
- pass 1 (2026-11-18): completeness 62 · quality 58 — full findings in
  `docs/work/kit-prompts/plan-critic-1.md` (F1 Critical; F2-F4, Q1-Q4 Major; minors + vigilance).
- verifier: F1-F4, Q1-Q4 all confirmed (closures of F1, F3, Q1 corrected); routed
  `rewrite` (`route-plan-1.json`), attempt 1/3 recorded. Minors → `## Vigilance`.
- rewritten sections (pass 1): inventory row security.md; step 5; step 6 fastapi README;
  step 7; IN48, IN52-IN55, PK20, KD21-KD23; Gate amendments pins; Vigilance.
- pass 2 (2026-11-18): completeness 84 · quality 76 — `plan-critic-2.md`. Pass-1 findings all
  fixed. New F7, Q9 (Major) confirmed by the verifier → `rewrite` (`route-plan-2.json`),
  attempt 2/3. Minors → `## Vigilance`; Q14 stale text fixed in place.
- rewritten sections (pass 2): step 5 "One source per destination" + its cases line; step 7
  supabase-removal paragraph; IN54 moved to step 7, IN56-IN57; pin-moves header; OQ7; Files.
- pass 3 (2026-11-18): completeness 88 · quality 78 — `plan-critic-3.md`. F7 fixed; Q9 not
  fixed (step 5's copy_kit arm breaks IN13 before step 7's kit-doctor gating); new F9 (rule 3
  of the winner order has no case). Both confirmed by the verifier → `blocked`
  (`route-plan-3.json`), attempt 3/3.
- **BLOCKED — plan-critic failed 3x : Q9.** No fourth rewrite in that cycle.
- 2026-11-18 user decision: "tu corriges, tu fais une passe ciblée et on lance le plan" →
  counter reset (attempts.json removed), closures applied: new step 4b (kit-doctor
  installed-mode gating + KD17/KD21 + SKIP pins + `:477` deletion) before step 5; IN58 (rule 3).
  New cycle, pass 1 targeted on Q9/F9 and the cycle-1-pass-3 rewritten sections.
- cycle 2 pass 1 (2026-11-18): Q9, F9 fixed; minors Q15-Q18 → Vigilance / fixed in place;
  route `clear` (`route-plan-4.json`), `plan-critic: cleared`.
- completeness: 93
- quality: 88
- surviving blockers: none

## Gate
- 2026-11-18 go
- Contract: as written
- OQ1 overlay form → decision 2 (project.json for hook/kit-doctor values, `.claude/overlays/<path>` `## <slot>` for prose; schema stays 3)
- OQ2 deny unit → decision 1 (`.claude/kit-manifest` entries; absent manifest → fail-closed on the four dirs)
- OQ3 kit-repo behaviour → separate predicate called only when installed; PK10 unchanged; `kit-manifest` in `CWK_KIT_CODE` + `CWK_GUARDED`
- OQ4 escape path → `## Local rules` in the prompt's overlay
- OQ5 `/kit:recipe` → decision 3 (`.claude/recipes/<name>.md` + overlay `## Recipes` when installed; kit repo unchanged)
- OQ6 upgrade → decision 4 (copy_kit + backup + adapted list + `/kit:init` Port; no `.new` for prompts)
- OQ7 addon prompts → kit code; winner per destination: addon chosen this run, else marker addon, else (both markers, no flag) left in place, named in the summary only when it differs from both addon copies
- OQ8 guard api → `cwk-guard-api` 7 → 8
- doc-researcher `tools:` → step 0 spike, result appended here as an amendment line
- amended 2026-11-18 step 0 spike (Claude Code 2.1.327, `--agents` JSON and a file agent in
  `.claude/agents/`): an agent whose `tools:` names absent MCP tools LOADS; the absent tools are
  dropped silently (it got Read, Glob only). → step 6 lists Context7's tools in doc-researcher's
  `tools:` unconditionally. Open for step 6: the exact names (prefix = the server name the
  project registered; the tool names of the current Context7 release) — checked against
  Context7's docs once, written to `docs/research-cache/`, before the edit.
  Settled 2026-11-18 (`docs/research-cache/context7.md`): server `context7`, tools
  `resolve-library-id`, `query-docs` (older `get-library-docs` kept: absent tools are dropped);
  a server registered under another name (ctx7 setup, plugin) is not reached — ADAPTATION §13 says so.
- amended 2026-11-18 IN56, IN57 (user approved): "a re-install with no addon flag
  (`--deploy=pages --no-ci`)" → "a re-install with no addon flag (`--no-ci`)" — install.sh refuses
  `--deploy` with `--no-ci`; the behaviour asserted is unchanged.
- amended 2026-11-18 PK18 (review round 1 T1, user approved): the init.md step extraction is
  scoped to `## Phase 3` and the `.claude/kit-backup/` check to the `## Phase N — Port` section
  (it read Phase 1 items and the whole file).
- amended 2026-11-18 PK18, PK20 (review round 1 T2, user approved): `kp_prompt_paths` also flags
  addon prompt paths (`addons/*/<rel>`), not only core ones.
- Amendments accepted with this go: `test-install.sh:660-663` (init.md → overwritten, step 5); `check_protected_branches` (4b) and `check_shared_dirs` reviewer copy + count (7) deleted with their pins; step 4b pins `test-kit-doctor.sh:53, :214, :226` + protected-branches pins, `test-install.sh:86-87` → SKIP, `:477` deleted, `:481-482` unchanged; step 7 `test-install.sh:88-89` → byte-identical (IN54); CLAUDE.md +≤1 line
