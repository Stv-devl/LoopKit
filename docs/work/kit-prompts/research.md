# Research: Kit prompts — adaptations out, then denied   (entry: docs/specs/kit-prompts.md)
Token profile: critical

Probes 2026-11-18: 3 `explorer` (P1 inventory; deny machinery; kit-doctor + config + EcoCrew diff),
key claims re-checked on the main thread (`kit-doctor.py:1210-1231`, `install.sh:233-247`,
`hook-guarded.sh:46-58`, `recipe.md:10-35`, EcoCrew `project.json` absent).

## Pattern to follow
- **kit-boundary (dbe6285)** is the direct analogue: one list `CWK_KIT_CODE`
  (`.claude/hooks/hook-guarded.sh:46-58`), one predicate `cwk_is_kit_code` (`:75-88`, glob with
  `*` crossing `/`, `--reach` counts ancestors `:81-85`), gated by `cwk_installed` (`:64-70`:
  stamp `.claude/INSTALL_PROFILE` → installed; `install.sh` + `addons/` → kit repo), one deny text
  `CWK_KIT_DENY` (`:59`). Its three consumers read the list, so a new entry propagates:
  Write/Edit `protect-files.sh:227-234`, shell `prevent-destructive-commands.sh:598-622`
  (`guard_kit_code`, called `:787`), git `enforce-git-workflow.sh:90` (`KIT_PATTERNS` from
  `CWK_KIT_CODE`), `kit_verdict` `:1514-1518`. Git needs no edit.
- **Values moved out of code, project-config (ac3c9a4)**: a key in `.claude/project.json`, read
  by `project_config.py`; new-key checklist: `DEFAULTS` `:38-65`, a `_validator`, `_parse`
  dispatch + `Config` field `:83-99`/`:318-331`, `document()` `:397-418`, `records()` `:364-385`
  if a shell hook reads it, `_migrated` `:545-660` if a hook held it; exact key set enforced by
  `_keys` `:184-193`. Twin check pattern in kit-doctor: `compare()` `:68-76`,
  `check_protected_dirs` `:116-135`, registered in `CHECKS` `:1436-1446`.
- **Proposal route for kit-owned files in an installed project**: `/kit:init` writes
  `.claude/project.proposed.json`, the user runs `bash .claude/scripts/kit-apply.sh`
  (`.claude/scripts/kit-apply.sh`, validate → backup to `.claude/kit-backup/<stamp>/` → apply).

## Wiring points
- Deny list: `hook-guarded.sh:46-58` (`CWK_KIT_CODE`), guarded-ask list `CWK_GUARDED` `:20-41`
  (no entry for the four dirs today), api stamp `cwk-guard-api: 7` (`:2`).
- Install copy: `install.sh` `copy_tree` `:233-247` — `copy_kit` (overwrite + backup to
  `.claude/kit-backup/<UTC>/`, `:114-127`) ONLY for `.claude/hooks/*`, `.claude/scripts/*`
  (`:238`); every prompt goes through `copy_file` (`:98-106`): existing file → `<file>.new`, never
  overwritten. Addon prompts: `copy_override` for `commands/database/migration.md` (`:735`, `:752`),
  `copy_file` for addon skills/commands (`:736-767`), addon README copied as
  `skills/patterns/FASTAPI-ADDON.md` (`:778`). Summary `.new` note for init.md `:809-811`.
- kit-doctor FILL scan: `check_fill_markers` `kit-doctor.py:1210-1231` (NOT `:1072`, which is
  `check_command_references`). Scans CLAUDE.md, `rules/`, `commands/`, `skills/templates`,
  `skills/patterns`, github yml/CODEOWNERS; does NOT scan `agents/`, `guides/`,
  `skills/e2e-playwright/`. Status `FILL` is informational (`:35`, exit only on
  DIVERGENCE/MISSING/OVER `:1488-1493`). Mode: `is_kit_source()` `:908-912`.
- kit-doctor twins that read a PROMPT as their rule side (they move with the value):
  `agents/github.md` `:194,:201` (protected branches); `guides/review/correctness.md` `:309,:321`
  (shared dirs); `skills/templates/tooling-config.md` `:255-269,:358-387,:421-432`;
  `commands/audit/mutation.md` `:422,:436`; `commands/loop/ship.md` `:458,:597,:644,:659`;
  agents frontmatter `:758-845` (`agent-models`, `agent-efforts`, kit-owned, not per-project).
- `/kit:init` writes into prompts at `init.md:88-92` (data client ≠ `lib/client` → rewrites
  `templates/feature.md`, `patterns/react-query.md`, `templates/fixtures.md`, tooling-config
  exclude), `:103` (`patterns/feedback.md`, `guards.md`), `:104` (`e2e-playwright/SKILL.md`),
  `:106` (`guides/10-worktrees.md`, maybe `agents/github.md`). Audit grep over `.claude/` `:133`.
- `/kit:recipe` creates `.claude/guides/<name>.md` (`recipe.md:18`) and adds one citation to the
  invoking file (`:27-28`), which is a command/skill/pattern/template, i.e. a prompt.

## P1 inventory — FILL markers in the four dirs (24 grep lines)
Spec Evidence: 16 lines unmoved; `ship.md:107` is now `:130`.

Class (a) — a per-project value the prompt reads at runtime (14):
| Marker | Value | Existing home |
| --- | --- | --- |
| `agents/doc-researcher.md:9` | Context7 MCP tool names in `tools:` frontmatter | none (ADAPTATION §13 `:453-460`) |
| `commands/loop/ship.md:55` | second (backend) unit runner | partial: `project.json` `fastapi` block, no runner command |
| `commands/loop/ship.md:130` | deploy commands + traps | partial: `CLAUDE.md:16` Production line |
| `agents/github.md:27` | branch prefixes, protected branches | `protected_branches` in `project.json`; prefixes: none |
| `commands/loop/research.md:90` | extra mandatory probe rows | none |
| `commands/audit/mutation.md:53` | mutation globs | rule side `05-testing.md` coverage scope; `tdd_layers` |
| `commands/database/migration.md:12` | migrations folder, CLI, apply command | partial: `rules/06-database.md:7,18-19` (placeholders) |
| `skills/templates/tooling-config.md:360` | coverage include/exclude globs | `05-testing.md` "Suite integrity and coverage" |
| `skills/patterns/forms.md:12` | reusable field-schema folder | none |
| `skills/patterns/feedback.md:3` | feedback component names | none |
| `skills/patterns/feedback.md:208` | user-language strings | language: `03-conventions.md:35`; strings: none |
| `skills/e2e-playwright/SKILL.md:8` | a second browser driver or not | none |
| `skills/e2e-playwright/SKILL.md:15` | harness paths and scripts | none |
| `skills/e2e-playwright/SKILL.md:65` | backend mutation case A/B/C | none (ADAPTATION §10) |

Class (b) — template snippet: `skills/templates/tooling-config.md:324` (data-client instance in
an exclude array) — home exists: `data_client.own_path` (`project.json:6-7`).
Class (c) — instructional text only: `templates/feature.md:8`, `templates/fixtures.md:82`,
`patterns/guards.md:3` (helper/route names, ADAPTATION §9 — real adaptation, see below),
`templates/ci.md:75`, `patterns/msw.md:21`, `commands/kit/doctor.md:152,:162`,
`commands/kit/init.md:28,:133`.

Per-project content WITHOUT a FILL marker:
- `guides/review/correctness.md:15-17`: six shared dirs + count, hand-edited per ADAPTATION §2
  (`:50-52,:61-64`); home exists: `data_client.shared_dirs` in `project.json`.
- `guides/10-worktrees.md:88`: shared-foundations list, edited per ADAPTATION §12 (`:390-411`).
- ADAPTATION §9 (`:365-369`) edits `patterns/feedback.md`, `guards.md`; §10 (`:371-383`) edits
  `e2e-playwright/SKILL.md`; §13 (`:427-460`) copies the Impeccable skill INTO `.claude/skills/`
  (~`:430`) and edits `agents/doc-researcher.md` frontmatter (`:457-458`).

## EcoCrew (the upgrade target, `/home/stevan/Travail/Projetperso/ecocrew`)
- `INSTALL_PROFILE` = `react-ts`; **no `.claude/project.json`** — EcoCrew predates project-config
  and kit-boundary too; its next `install.sh` runs `migrate` from an absent file (values from its
  active hooks) on top of this pass.
- Values EcoCrew filled IN PROMPTS (lost if prompts are overwritten without extraction):
  `agents/github.md` (main only; prefixes `feat/ fix/ chore/`), `guides/review/correctness.md:129-130`
  (pointer to `rules/07-backend.md`), `skills/templates/tooling-config.md:324-325`
  (`src/lib/api.ts`), `guides/10-worktrees.md:92` (backend foundation row),
  `commands/loop/ship.md:47-49` (`frontend/src` paths) and `:55-63` (backend gate block),
  `skills/e2e-playwright/SKILL.md:8-24,:65-79` (case A).
- Still unfilled in EcoCrew (identical to LoopKit): doc-researcher, research, mutation,
  feedback, guards, forms, feature, fixtures; deploy FILL at its `ship.md:111`.
- Each diff above also carries older-kit wording: a value cannot be extracted by "diff against
  current LoopKit"; it must be read from a known slot.
- `commands/database/migration.md` = the fastapi addon override, byte-identical (not an
  adaptation). 24 addon-owned prompts present (`commands/backend/*` 13, `refactor/clean-python.md`,
  7 fastapi patterns, `templates/endpoint.md`, `guides/07-backend.md`, `FASTAPI-ADDON.md`).
- Truly project-local: `skills/patterns/snapshot-tests.md` (a leftover LoopKit deleted,
  `docs/refonte-loopkit.md:225`; unreferenced). No `.new` files, no `kit-backup/`.
- EcoCrew's own fills already sit in rules: `rules/01-stack.md`, `06-database.md`, `07-backend.md`.

## Reusable
- `CWK_KIT_CODE` + its three consumers (git included) — add entries, no new hook.
- `copy_kit` (overwrite + backup) — add an arm in `copy_tree`.
- `project_config.py` key machinery and `kit-apply.sh` proposal route.
- kit-doctor `compare()` twins and `check_fill_markers` (widen its folder list).
- Existing homes: `protected_branches`, `data_client.{module,own_path,shared_dirs}`,
  `tdd_layers`, `server_roots`, rules `03-conventions.md:35`, `05-testing.md`, `06-database.md`.

## Blast radius
- `hook-guarded.sh` (list + api stamp 7 → 8?): consumers protect-files, prevent-destructive,
  enforce-git-workflow; tests KB1-KB26, G19.*, PK10-PK14, IN37/IN41 (api number).
- `install.sh` `copy_tree`: IN30-IN40 pin which files get `.new` (incl. `commands/kit/init.md.new`,
  `test-install.sh:645-662`), PK12, summary note `:809-811`.
- kit-doctor twins whose rule side is a prompt (list above) — each changes with its value.
- `/kit:init` steps 2, 9, 10, 12 and its `:133` grep; `/kit:recipe`; `/kit:doctor` table
  (`doctor.md:49-68`, "Adding a twin" `:196-203`).
- Docs listing the kit-code set: `CLAUDE.md:34`, `README.md:39-41,:49-51,:57-61`,
  `docs/ADAPTATION.md:505-520,:526,:575-586,:30-32`, `install.sh:24-28,:230-232`,
  `hook-guarded.sh:43-45`; ADAPTATION §2, §9, §10, §12, §13 (each rewritten to the new homes).

## Live DB state
n/a (kit tooling).

## External surface
n/a (no third party). Context7 MCP tool names (doc-researcher) are a per-project fact, not researched.

## Traps (points of vigilance for the review)
- PK10 (`test-workflow-contracts.sh:1084-1101`) requires every `CWK_KIT_CODE` entry to be
  `cwk_is_guarded`; adding the four dirs that way makes the kit repo ASK on every prompt edit,
  contradicting the spec's "keep today's pass in the kit repo" — needs an explicit exemption or a
  second list, decided in the plan, with PK10 amended accordingly.
- `.claude` is already in `protected_dirs`: shell `mv`/`rm -r` on the four dirs already ask
  (`prevent-destructive-commands.sh:863-868`); only Write/Edit and the kit deny are new.
- Switching the four dirs to `copy_kit` overwrites every adapted prompt (old copy only in
  `kit-backup/`): "no lost adaptation" needs the values moved to their homes BEFORE the overwrite,
  in the same install run (the migrate-before-copy order of kit-boundary, `install.sh:685-686`).
- A whole-dir deny also denies project-owned prompts: addon prompts (24 in EcoCrew), the
  Impeccable skill copied into `skills/` (ADAPTATION §13), a project's own skill/recipe
  (`snapshot-tests.md`). The deny unit (kit-shipped files vs whole dirs) must be decided.
- `/kit:recipe` both creates a guide and edits a prompt to cite it: both are denied once the
  dirs are kit code.
- kit-doctor twins read prompts as the rule side: moving a value without moving its twin turns
  `/kit:doctor` red or makes it compare a stale constant.
- The FILL scan misses `agents/`, `guides/`, `skills/e2e-playwright/` today: "no FILL left in a
  prompt" must be checked on all four dirs, and class (c) instructional mentions must not count.
- Values in prompts are prose blocks (e2e case A section, ship backend gate block), not
  `NAME = literal` lines: `_migrated`-style extraction does not apply as is.
- EcoCrew has no `project.json`: AC4 runs migrate-from-absent + this pass together; test the
  combined upgrade, not this pass alone.
- Rules have line budgets (`.claude/guides/rules-index.md`, `test-rules-floor.sh`): moving prose
  into hot rules can break the floor.

## Open questions
1. **Overlay form** (spec OQ1): for class-(a) values with no home — `project.json` keys (only
   short values: prefixes, globs, commands), a project-owned overlay file the prompts read (e.g.
   one `.claude/project/<prompt>.md` or one `docs/kit-overlay.md`; prose blocks like e2e case A,
   deploy traps, feedback component table), or hot rules (line budgets)? Which value goes where?
2. **Deny unit**: deny the four whole dirs, or only the kit-shipped files (a manifest), leaving
   project-owned skills/agents (addons, Impeccable, a project's own skill) writable?
3. **Kit-repo behaviour**: the four dirs pass in the kit repo (spec) — exempt them from PK10's
   "kit code is guarded", or keep them out of `CWK_GUARDED` with a second list?
4. **Escape path** (spec OQ2): may a project override one prompt locally (an override file the
   prompt reads), or must every change go through LoopKit?
5. **`/kit:recipe`**: recipes move to a project folder (which? read by whom, cited from where —
   the invoking prompt can no longer take the citation), or guides stay writable for it?
6. **Upgrade of adapted prompts** (AC4): overwrite with backup after extracting each known slot
   into its new home, or keep `.new` for the four dirs and let the user merge once? If extraction:
   which slots are extracted automatically (github prefixes, data-client path, e2e case) and which
   are reported for the user?
7. **Addon prompts** (`copy_override` migration.md, fastapi skills/commands): kit code (denied,
   overwritten) or project-owned?
8. **Guard api stamp**: bump `cwk-guard-api` 7 → 8 (IN37/IN41 depend on it)?
