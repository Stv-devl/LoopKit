# Research: Kit boundary   (entry: docs/specs/kit-boundary.md)
Token profile: critical

Sources: 3 explorers (adaptation values / guarded paths + cfg + redirects / kit-code deny surfaces), 2026-11-10, reconciled on the main thread; spot-checks re-read on the main thread are marked (verified).

## Pattern to follow
- Guarded-path machinery: `CWK_GUARDED` list + `cwk_is_guarded` in `.claude/hooks/hook-guarded.sh:20-39, :76-87` (root-anchored `[[ "$rel" == $pattern ]]`, `*` crosses `/`), sourced by `hook-lib.sh:60`; denied list `CWK_GUARD_DENIED` `:45-48` with `cwk_is_guard_denied` `:91` — the deny tier the kit-code deny should extend.
- Write/Edit decision: `protect-files.sh:191-255` (denied → deny `:196-198`, guarded → ask `:251-253`, else pass). Shell decision: `prevent-destructive-commands.sh` `guard_classify` `:538`, `guard_classify_tool` `:618-619`, `>` branch `:595-607`, source-writer deny `:608-617`.
- Git: `parse_segments` (`enforce-git-workflow.sh:173-1244`, one TSV row per git call) + `DESTRUCTIVE_RULES` / `destructive_verdict` `:966-986`; `checkout_rule` `:736-790` already derives the paths of `checkout -- <path>` / `restore` and checks them against the TDD regexes passed as argv `:219-221` — the template for a kit-path check.
- Kit vs installed: only `kit-doctor.py:793-794` `is_kit_source()` = `install.sh` file and `addons/` dir (verified). No guard hook distinguishes them today.
- Previous pass with the same shape (guard values + fixtures + prompts): `docs/work/fewer-asks/` (handoff, plan) — fixture series, `## Gate` amendments, suite list.

## Wiring points
Adaptation values, definition → readers (all hard-coded; none read from a file):
- `DATA_CLIENT_MODULE` `enforce-architecture.py:82`, `DATA_CLIENT_OWN_PATH` `:84`, `COMPOSITION_ROOTS` `:88`, `SHARED_DIRS` `:101`; readers same file `:192, :206-229`. kit-doctor twins: `check_data_client` `:113`, `check_client_copies` `:146`, `check_composition_roots` `:186`, `check_shared_dirs` `:202` — regexes anchored on the Python syntax (`:119, :192, :216`).
- `PROTECTED_DIRS` `prevent-destructive-commands.sh:78`; readers `:92, :486-487`; twin `check_protected_dirs` `kit-doctor.py:89-110` (regex `^PROTECTED_DIRS="…"` `:95`, CLAUDE.md "Recursive delete on:" `CLAUDE.md:42-44`).
- `PROTECTED_BRANCHES` `enforce-git-workflow.sh:94`; readers `:157, :164`; copy `.claude/agents/github.md:27-28`, `docs/ADAPTATION.md:344-345`. **No kit-doctor twin.**
- RED test command `RUN_TESTS="pnpm test:run"` `tdd-prove-red.sh:43` (readers `:182-183, :230-232`); copy `.claude/rules/00-project.md:14`, `docs/ADAPTATION.md:107-108`. **No kit-doctor twin.**
- Formatter: `format-on-save.sh:50-51` (`cwk_bin prettier`, CONFIGURE `:6`). **No twin, not in ADAPTATION.**
- `ENV_TEMPLATE_RE` `protect-files.sh:100` (reader `:146`) — **four copies, docs name two**: `prevent-destructive-commands.sh:183`, `auto-approve-config.sh:69`, `shell_targets.py:152` (`SECRET_KEEP`). No twin.
- Also hook-held, outside the spec list: `CWK_TDD_LAYERS` `hook-lib.sh:253` (twin `check_tdd_layers` `kit-doctor.py:325`); fastapi `MODULE_ROOT` twice (`addons/fastapi/hooks/enforce-backend-layers.py:59` "app/", `tdd_py_lib.py:28` "app").
- Channels hooks have today: shell hooks source `hook-lib.sh` → `hook-guarded.sh` (relative to the hook's own dir, not the project); shell → Python only through argv (`prevent-destructive-commands.sh:199`, `enforce-git-workflow.sh:174`); Python hooks read no shell value and no config file; project root from `CLAUDE_PROJECT_DIR`. No project config file exists (`.tdd-unfrozen`, `.size-exempt` are the only project files hooks read).
- `install.sh`: `copy_file` `:86-96` writes `<dst>.new` when dst exists and never touches the active file (verified); `copy_tree` `:201-212` (hooks, fixtures, test suites all copied); `hook-guarded.sh` copied verbatim; in-place perl only on files installed in the same run (`wire_fastapi` `:405-440`, `wire_supabase` `:457-501`); `.claude/INSTALL_PROFILE` rewritten every run `:664-668`; `install.sh` and `addons/` never copied into a target; `GUARD_FILES` + `# cwk-guard-api: N` stamps `:212-263` hold P1 back when a guard is behind.
- `/kit:init` (`.claude/commands/kit/init.md:67-96`) writes hooks today: `enforce-architecture.py` (`:72-73`), `no-forbidden-icons.sh` (`:91`), ENV twins in `protect-files.sh` + `prevent-destructive-commands.sh` (`:73`), plus kit prompts (templates `:74-78`, rules, guides via ADAPTATION). It asks protected branches (`:50-60`) but no step writes them. `/kit:recipe` (`recipe.md:18, :27-28`) writes `.claude/guides/<name>.md` + one citation in an **argument-chosen** file.
- cfg options: `shell_targets.py` `flag_kind` `:1086-1104`, `package_base` `:1068-1083` (walks up from cwd to the project root to the first `package.json`), rows `tool_rows` `:1375`; decision `prevent-destructive-commands.sh:526-533` (dir passes only if it is the project root; a **guarded file passes** `:529-530`; else ask "`<rel> (cfg)`" `:532`, text `:734-736`) (verified).
- Redirections: `Walker.finish` `shell_targets.py:566-576` emits `(">", target)` rows with **no command word attached** (verified); decision `>` branch `prevent-destructive-commands.sh:595-607`, TS-source ask text `:832-834` ("TypeScript source from the shell").

## Reusable
- `cwk_is_guarded` / `cwk_is_guard_denied` / `cwk_guard_rel` / `cwk_real_path` (hook-guarded.sh) — extend, do not duplicate.
- `checkout_rule` path derivation + the argv-regex channel of `parse_segments` (`enforce-git-workflow.sh:219-221, :756-760`) for kit-path checks on `checkout -- `/`restore`.
- Source-writer deny branch `prevent-destructive-commands.sh:608-617` (fewer-asks V3) — the codegen deny is its redirect sibling.
- `package_base` for "directory with its own package.json".
- Test infra: `test-hooks.sh` per-fixture `case "$hook:$fixture_name"` setups `:297-400`, shell-guard `setup` trees `:131-295` (`pkgsub` `:152-156` is the only app-subdir tree), `run_harness_reproduction` `:30-41` (copies hooks into a tmp dir: model for an installed-like tree), `guard_call` `:686`; `test-install.sh` scratch targets `:5-26` and the value-survives-rerun case `:259-269`; `test-kit-doctor.sh` divergence pattern `:44-56`.

## Blast radius
- Every guard file whose behaviour changes needs its `# cwk-guard-api:` bumped (hook-guarded 3, prevent-destructive 3, enforce-git 3, protect-files 2, shell_targets 3, hook-lib 2) and `GUARD_FILES` in install.sh kept in sync (`test-workflow-contracts.sh:765`).
- kit-doctor twin regexes (`:95, :119, :192, :216, :336`) break if the values leave the hook syntax; `check_protected_dirs` and `install.sh:437` depend on the literal CLAUDE.md "Recursive delete on:" text.
- `install.sh` addon perl (`:427, :467, :496`) targets the hook text of `PROTECTED_DIRS` / `DATA_CLIENT_*`: they must retarget the config file.
- Docs: `CLAUDE.md:42-44`, `01-stack.md:38-40`, `02-architecture.md:36-37`, `github.md:27-28`, `docs/ADAPTATION.md` §2, §2 bis, §4, §7, §14 (`:462-464` says installed projects ask only on package.json/vite.config — contradicted by the deny), upgrade `:560-567`; `kit/doctor.md:51-55`; addons `supabase/rules/01-stack.md:119-120`, `supabase/README.md:38-43`.
- Suites: `test-hooks.sh:739-742` pin `apps/web/package.json` NOT guarded with no config; `fixtures/protect-files.sh/30-w5-nested-package-pass.json` pins it pass; X32.07/X32.08/X42.05 pin `echo x > src/a.ts` / `cat >> src/a.ts <<EOF` as **ask** (frozen — the codegen deny flips them); `test-workflow-contracts.sh:440-441` (ADAPTATION §14 sentence), `:702-711` (CLAUDE.md shell-write rule needles), `:737-739` (`python3 -I` everywhere), `:63` (13 loop commands); `test-rules-floor.sh` 516/520 (verified) → 4 lines of headroom for CLAUDE.md + rules.
- Installed projects: EcoCrew carries `cwk-guard-api: 3` (verified) and no `.new` files.

## Live DB state
n/a (kit tooling).

## External surface
n/a — no third party. Claude Code hook semantics used as today (PreToolUse allow/ask/deny JSON), nothing new [settled by the existing suites].

## Traps (points of vigilance for the review)
- **The stamp is lost on re-install.** `copy_file` keeps the existing `hook-guarded.sh` and writes `.new`; a stamp written into it only by a fresh install never reaches an existing project (EcoCrew), and "no stamp" must not read as "kit repo" there — fail closed, or detect another way.
- **Stamp forgeability**: the stamp lives in a guarded/denied file, but the "kit repo" side (no stamp) must not be reachable by deleting a line; a reader that treats a missing/unreadable stamp as "installed" is the safe default only if the kit repo has its own positive marker.
- `/kit:init` writes hooks and kit prompts today; after the move it must write only the config file + rules/docs, else the "outside a pass" exception becomes a blanket bypass. `/kit:recipe`'s target is an argument: its exception cannot be a fixed path list.
- The config file is a judge (PROTECTED_BRANCHES, RUN_TESTS, APP_ROOTS, CODEGEN_COMMANDS): any read failure, parse error or missing key must fail closed (ask/deny), never fall back to permissive defaults; the Python and shell readers must parse it identically (one parser).
- `RUN_TESTS` from a file is a command the hook executes: it must not become a code-injection channel (quoting, no `eval`), and must stay guarded/denied.
- A guarded config **file** already passes as a cfg target (`prevent-destructive-commands.sh:529-530`): guarding `frontend/tsconfig*.json` through APP_ROOTS also makes `-p frontend/tsconfig.app.json` pass — acceptable only when APP_ROOTS declares `frontend`; with no APP_ROOTS the behaviour must be today's (ask).
- `apps/web/package.json` must stay unguarded when nothing is declared (`test-hooks.sh:742`, fixture 30-w5).
- Redirect rows carry no command: the codegen exemption needs the segment's command words attached to `>` rows; matching on raw text would be bypassable (`echo $(supabase gen types) > src/a.ts`, `supabase gen types; echo x > src/a.ts`).
- `.py` redirects get no verdict today (`echo x > src/a.py` passes, contrary to fewer-asks.md:52): the codegen deny on `.py` is a new verdict, not a tightening of an ask.
- ENV_TEMPLATE_RE has four copies; moving two leaves two silent ones.
- Git routes that bring kit changes with no path logic today: `git apply`, `git am`, `stash pop`, feature-branch `merge`, `cherry-pick`, `revert`, `switch` to a branch whose kit files differ; `checkout <ref> -- <kit path>` passes on a clean tree (`enforce-git-workflow.sh:786`).
- Installed projects ship the test suites and fixtures (`copy_tree`), so kit-code deny covers them too; the suites run from the kit repo only.
- Rules floor headroom 4 lines: CLAUDE.md/rules edits must be net ≤ +4 or the ceiling decision is explicit.
- Every new python call in shell needs `python3 -I` (`test-workflow-contracts.sh:737-739`).

## Open questions
1. Config file location and format (spec open question 1): `.claude/project.conf` (KEY=value, sourced by shell, parsed by Python) or JSON read by `jq` + Python? Note: hooks already need `jq`; sourcing a file from shell executes it — a KEY=value file must be parsed, not `source`d.
2. How `/kit:init` and `/kit:recipe` write in an installed project while a feature pass cannot (spec open question 2): a marker only those commands set, or they print the change for the user to apply? Given the trap above (init writes hooks today), is the target that init writes only the config file + rules/docs, and recipe prints its guide/citation for the user?
3. Installed detection on an existing install where the stamp never lands (re-install writes `.new`): should `install.sh` write the stamp into its own file (e.g. a new `.claude/.kit-installed`, written like `INSTALL_PROFILE` on every run, denied/guarded), and the kit repo be recognised positively instead (e.g. `install.sh` + `addons/` present *and* no stamp)?
4. Upgrade of an existing project: since active hooks are never rewritten, should `install.sh` overwrite guard hooks on upgrade (they become value-free) and migrate the old filled values from the active hooks into the config file, or keep writing `.new` and let `/kit:doctor` report the migration?
5. Scope of the value move: the spec lists 11 values; `CWK_TDD_LAYERS` and the fastapi `MODULE_ROOT` are hook-held adaptation values too — in or out of this pass?
6. Codegen redirect denies: does the deny apply to `.py` too (a new verdict, see Traps), and are the frozen X32.07/X32.08/X42.05 ask cases amended to deny?
7. The git kit-path deny: which routes are in this pass (spec: apply, am, checkout/restore, stash pop, merge, switch); cherry-pick/revert added? For `merge`/`switch`, deny when the incoming tree differs on a kit path (needs a diff against the target ref) or ask?
8. Rules floor: CLAUDE.md "change both together" lines will change wording; keep net ≤ +4 lines, or raise `CORE_CEILING`?
