# Research: Ship audit armed by what the diff touches   (entry: docs/specs/ship-audit-surface.md)
Token profile: standard

## Pattern to follow
- **Kit script with a JSON contract:** `.claude/hooks/kit-gate-route.py`. It uses argparse subcommands (`main()` :549-570), takes a JSON input file in `route` mode (:507-523), prints JSON to stdout and refuses through `refuse()` (:87). It is the closest analogue to a script called from a command that returns a decision. `kit-attempts.py:1-30` shows the header (`# cwk-guard-api: 1`), the strict load and `write_atomic`.
- **Config read:** `project_config.py`. `load_strict` (:300-314) is fail-closed: 3 = malformed, 4 = absent, 5 = no absolute dir. `load` (:316-325) maps 4 and 5 to `EMPTY` and fails open. `shell_targets.py:32-58` is an example of import plus `load_strict` plus recording the `ConfigError` status.
- **Test suite:** `test-attempts.sh:2-40`. It uses `set -euo pipefail`, `mktemp -d` plus a trap, hand-written fixtures, `jq -e` / `grep -Fq`, and `set +e; CODE=$?` for expected non-zero exits. Suites that need a real git repo use `git -C "$SCRATCH" init -q` (`test-kit-doctor.sh:31`).
- **Ship diff file set:** `review.md:153-160` already defines it. `<base>` is `git merge-base HEAD <plan Base:, else default branch>`, and the set is `git diff --name-only <base>` plus `git ls-files --others --exclude-standard` (:160). `review.md:157-158` warns that `<base>...HEAD` is empty before the ship commit. Ship has no diff computation of its own today; its only base uses are the rebase at `ship.md:143` and the small-lane `Base:` at `ship.md:218`.
- **Doctor pair check:** `kit-doctor.py:116-136` `check_protected_dirs` → `compare("protected-dirs", ("CLAUDE.md", declared), (PROJECT_JSON, actual))`, registered in the `twins` tuple at :1383.

## Wiring points
- `ship.md:76-92`: step 1bis. Heading at :76, intro at :78-80 ("one surface — one `security-auditor`"), reason table at :82-88, Critical stop and "ask" line at :90-92. Verified by reading.
- `ship.md:236`: report line `Audit: <surface> — <n> Critical / <n> Major   (or "not armed — profile <economy|standard>")`. Minors are not printed. Verified by reading.
- `ship.md:148-149` and `:241`: read `follow-ups.md` (count and path at merge, `Follow-ups:` output line).
- `follow-ups.md` writer: `kit-gate-route.py` `append_follow_ups` :455-466 (dedupes exact lines, appends), called from `route_review` :469-502. The path is `directory / "follow-ups.md"` (:70-71). Only `plan` and `review` modes exist; there is no audit mode.
- Line format (review-convergence C2, `docs/specs/review-convergence.md:66`), as implemented at `kit-gate-route.py:486-487`: `- [{dimension}] {path}:{line} — {problem} ({label})`, with label `minor` or `out of scope` (:429-452).
- Registration of a new suite or script, mirroring `test-attempts.sh` / `kit-attempts.py`:
  - `install.sh:283-288` (allow list `Bash(bash .claude/hooks/test-attempts.sh)`)
  - `.github/workflows/kit-ci.yml:63-64` (a step per suite). Lint covers new files automatically: `shellcheck` :36 and `ruff` :43.
  - `.claude/settings.json:57-58`
  - `kit-doctor.py:838-841` `NON_HOOKS`. `check_hook_wiring` (:898-931) fails if a `.sh`/`.py` in `.claude/hooks/` is in neither `settings.json` nor `NON_HOOKS`.
  - `test-workflow-contracts.sh:797` `k2_suite` list.
- `/kit:init`: `commands/kit/init.md:108-113` does one Edit to `app_roots`, `codegen_commands`, `tdd_layers` and `fastapi`. A server-roots key would be filled there.
- Install migration: `install.sh:244-262` `migrate_config` → `project_config.py migrate` (:256). Addon `wire`: `install.sh:502` (fastapi), `:546` (supabase), and `project_config.py:401-425` (`ADDON_DIRS`, `wire()`).

## Reusable
- `merge-base` plus `ls-files --others --exclude-standard` (`review.md:153-160`; also `small-scope.sh:41-43`). Do not invent a second spelling.
- `append_follow_ups` in `kit-gate-route.py:455-466`: the only existing `follow-ups.md` writer, with dedupe. A1/A5 can reuse it, through a new mode or by importing it, instead of writing a second appender.
- The `project_config.py` loader (`load_strict`) and its `KEYS`/defaults (:24, :37-62). A new key follows the `schema_version` + `migrate` path.
- `compare(...)` in kit-doctor for the A6 rule-copy/enforced-copy pair.
- `security-auditor` already takes several surfaces with separate headings (`agents/security-auditor.md:10-11`). `audit/security.md:33` already allows one agent to own several surfaces (A3).

## Blast radius
- **Uncommitted kit-boundary work in the same tree.** `git status` shows `shell_targets.py`, `hook-guarded.sh`, `test-hooks.sh`, `enforce-git-workflow.sh`, `prevent-destructive-commands.sh` and `protect-files.sh` as modified, plus `docs/work/kit-boundary/*`. This spec touches none of those files directly. But `test-hooks.sh` is a gate in AC10, and `test-hooks.sh` (:795, :876, :897, :931) copies every `*.sh`/`*.py` of `.claude/hooks/` into its fixtures, so the new script is picked up there. A track for this spec should branch from a base without kit-boundary's dirty edits (a separate worktree).
- `project.json` schema: adding a key means a bump of `schema_version` (currently 2, `project_config.py:24/37-62`), plus `migrate`, the defaults, `/kit:init`, `kit-doctor check_project_config` (:586-604) and the installed copies in downstream projects (migrated by `install.sh:244-262`).
- `security.md:17-18` says `11-token-budget.md` is "the only copy" of what makes a profile critical, but the `ship.md:82-88` table is a second copy of those reasons. A2 keeps that table, so the duplication remains (OUT: what makes a profile critical).
- Other places that state the current one-surface / profile-reason wording and will read stale after D1:
  - `docs/Claude_Workflows.md:246`, `:599-600`
  - `.claude/guides/ship.md:37-45` (lines 43-44: "One surface is one `security-auditor`")
  - `.claude/commands/loop/orchestrate.md:312-313`
  - `.claude/guides/orchestrate.md:49`
  - `.claude/commands/loop/spec.md:141`
  - `.claude/commands/audit/security.md:15-17`
  - `.claude/rules/11-token-budget.md:8-9` ("arms ship security"). This one remains true and is OUT.

## Live DB state
n/a. Kit tooling, no data.

## External surface
n/a. No third party. Git behaviour used here is already in the repo (`kit-gate-route.py:43` `diff --no-renames`, `review.md:160`).

## Traps (points of vigilance for the review)
- **The spec says FastAPI `backend/`; the addon uses `app` and `alembic`** (`project_config.py:401-402` `ADDON_DIRS`; `addons/fastapi/README.md`). The ecocrew evidence counts `backend/`, which is that project's own layout. Server roots must come from the declaration, never from a hard-coded `backend/`.
- **Renames:** with `--no-renames` (the repo convention, `kit-gate-route.py:43`, `small-scope.sh:41-42`), a rename into a server root appears as a delete plus an add, so S2's rename case fires on the add side. A rename *out of* a root shows the root path only as a delete. The plan must say whether a delete under a root arms `authz` (S2 is silent).
- **`<base>...HEAD` is empty before the ship commit** (`review.md:157-158`). Step 1bis runs before the commit, so it must diff the working tree against the merge-base, untracked files included, as `review.md:160` does.
- **A Minor has no `Path:` line** (`security-auditor.md:163-179`), while Critical and Major items do. Whatever turns the audit report into follow-up lines must accept both shapes.
- **Label vocabulary:** C2's labels are `minor` and `out of scope`. An audit Major has no label in that set, and A5 does not name one. If the `(label)` set changes, `test-gate-route.sh` (:111-160, :284-293), which asserts exact lines, must stay green.
- **Multi-surface argument:** `audit/security.md:60` defines one surface, `everything`, or nothing. A list (already used by the `ship.md:85` row) is undefined and falls through to all six (`docs/audits/workflow.md:84`, W-R2). Passing several selected surfaces to one auditor (A3) must not route through that undefined argument and accidentally run six.
- **Fail-open loader:** `project_config.load()` maps absent or invalid config to `EMPTY` (:316-325). For the script, "no server root declared" (S7, no `authz` from paths) must be distinct from "project.json unreadable". The second should be a refusal, not a silent no-audit.
- **Trigger in a comment or a removed line (S5):** only added (`+`) lines count, and comment detection is per language. A naive grep on the whole diff fails S5.
- **Report line change:** `ship.md:236` today prints `not armed — profile <…>` for economy/standard (AC9 keeps that). A4 adds a second "not armed" variant for `critical`. Both must appear in the template.
- **Test IDs collide:** the spec's wording cases T1 and T2 already exist in `test-workflow-contracts.sh` (T1-T13 at :1044-1084). The new cases need fresh IDs. The helpers to use are `rc_has` (:1033-1039) and `section` (:287).
- **Every new hooks file must be registered:** `check_hook_wiring` fails otherwise (`kit-doctor.py:898-931`). That means `NON_HOOKS`, the `k2_suite` list, the install allow list, kit-ci and settings.

## Open questions
1. **Where are server roots declared (A6)?** Options: a new `project.json` key (for example `server_roots`, mirrored by a line in `02-architecture.md ## Backend` and checked by `kit-doctor compare`), or reuse `app_roots`. `app_roots` is only checked for existence on disk (`kit-doctor.py:598`); what else consumes it was not verified, and it may include front roots. The recommendation is a dedicated key, but the decision is for the plan gate.
2. **FastAPI default roots:** `app/` + `alembic/` (the addon's actual dirs, `ADDON_DIRS`) or `backend/` as the spec says? Supabase is `supabase/`.
3. **Does a deleted file under a server root arm `authz`?** For example, dropping an RLS policy file or a route.
4. **Follow-up writer for A5:** a new `kit-gate-route.py` mode (`audit`), or a function in `kit-audit-surface.py` that imports `append_follow_ups`? Which label do Majors and Minors carry (`(major)` / `(minor)`, outside the C2 set today)?
5. **Multi-surface handoff:** does ship launch `security-auditor` directly with the surface list (bypassing `/audit:security`'s argument parsing), or does the plan define the list argument in `audit/security.md` (which is OUT of scope)?
6. **Session trigger scope:** "client caches or persisted per-user state" also matches benign `localStorage` reads anywhere. Should the trigger be restricted to writes, clears or resets on added lines, or is any added mention enough? The exact trigger list is the plan's to fix (spec A1).
