# Research: Project config   (entry: docs/specs/project-config.md)
Token profile: critical

Sources: 3 explorers on 2026-11-15 (the hooks and the reader / writers, twins and docs / suites
and fixtures), reconciled on the main thread. Lines marked (verified) were re-read on the main
thread. The 2026-11-10 map in `docs/work/kit-boundary/research.md` has stale line numbers, and its
plan.md reader API (`get`/`apply`/`mode`, discovery from the reader's own path, `CWK_HOOK_DIR`)
was never shipped.

## Pattern to follow
- **The reader.** `.claude/hooks/project_config.py` was shipped by `app-roots-codegen`, stamp
  `cwk-guard-api: 1`.
  - `load(project_dir)` `:97` joins `.claude/project.json` itself (`:101`). It reads neither
    `CLAUDE_PROJECT_DIR` nor its own path, so the callers pass the project dir.
  - `_read` `:75` uses O_NOFOLLOW, refuses a symlink, a non-regular file, or a file over 64 KiB.
  - Duplicate keys are refused (`_pairs`).
  - CLI `roots|check <dir>` `:132-143`. Exit 2 = usage. Exit 3 = `ConfigError` (stderr
    `project-config: …`, nothing on stdout). An absent file gives exit 0 and `EMPTY`.
- **Callers today.**
  - `hook-guarded.sh:79` runs `python3 -I -B "$__CWK_GUARD_LIB_DIR/project_config.py" roots
    "$CLAUDE_PROJECT_DIR"` once per process, from `cwk_app_roots` `:74-82`.
  - `shell_targets.py:32` imports it and loads `CLAUDE_PROJECT_DIR` at `:48`.
  - `kit-doctor.py:523-541` `check_project_config` imports it and runs `load(str(ROOT))`.
- **Analogue pass**: `app-roots-codegen` (`docs/work/app-roots-codegen/`).
  - Reader + guard values + fixtures writing a tmp `project.json`: `write_project_json`
    `test-hooks.sh:1434-1437`, `make_app_tree` `:1593-1617`, PC1-PC15 `:1453`.
  - Its `## Gate` and amendments are the shape to copy.

## Wiring points
Every value, its definition and readers (current lines):

| Value | Definition | Readers / copies |
| --- | --- | --- |
| `DATA_CLIENT_MODULE` | `enforce-architecture.py:82` `"lib/client"` | `:206` (falsy → check off), `:222` |
| `DATA_CLIENT_OWN_PATH` | `:84` `"lib/client.ts"` | `:213` |
| `COMPOSITION_ROOTS` | `:88` tuple | `:214`, `:229` (deny text) |
| `SHARED_DIRS` | `:101` 6 entries | `:192` |
| `PROTECTED_DIRS` | `prevent-destructive-commands.sh:85` (verified) `src\|shared\|\.claude\|public\|node_modules\|dist` | `:99`, `:505`, `:506` |
| `PROTECTED_BRANCHES` | `enforce-git-workflow.sh:98` (verified) `main\|master` | `:161`, `:168` (`grep -qE "^(…)$"`) |
| test command | `tdd-prove-red.sh:43` `RUN_TESTS="pnpm test:run"` | `:182` `${RUN_TESTS%% *}`, `:183` msg, `:230`, `:232` invocation |
| formatter | `format-on-save.sh:50-51` `cwk_bin prettier` → `--write` | resolver `hook-lib.sh:120` |
| linter | `eslint-batch.sh:46` `cwk_bin eslint`, cache `:51`, `--cache` `:55` | `eslint-check.sh` holds no value (`:6`) |
| env template suffixes | `protect-files.sh:100` (verified) `ENV_TEMPLATE_RE` | reader `:146`; deny texts `:147,:152` |
| ″ copy 2 | `prevent-destructive-commands.sh:190` (verified), a literal inside `sed -E` | deny texts `:192,:229` |
| ″ copy 3 | `shell_targets.py:205` (verified) `SECRET_KEEP` regex | `:1264` |
| ″ copy 4 | `auto-approve-config.sh:69` (verified) suffix regex **and** `:89` `"^\.env\.example$"`, which allows **only** `.example` | |
| ″ copy 5 | `enforce-git-workflow.sh:197` (verified) `SECRET_KEEP` Python set in the heredoc that starts at `:178` | `:426` |
| icons | `no-forbidden-icons.sh:62` (JSX) and `:66` (import), the same list twice | emoji bytes `:54-55` (comment `:50-52`) |
| `CWK_TDD_LAYERS` | `hook-lib.sh:253` | derived `:257,:260,:264,:267`. Readers: `tdd-require-red.sh:62`, `tdd-freeze-tests.sh:114`, `tdd-prove-red.sh:135`, `prevent-destructive-commands.sh:276,:282`, `enforce-git-workflow.sh:178` (argv to the parser) |
| `CWK_TDD_PY_TARGET_RE` | `hook-lib.sh:294` (mirrors fastapi, comment `:287-288`) | `prevent-destructive-commands.sh:408,:629,:710,:730` |
| fastapi `MODULE_ROOT` | `addons/fastapi/hooks/tdd_py_lib.py:28` `"app"` **vs** `enforce-backend-layers.py:59` `"app/"` | tdd_py_lib `:148…:375`, `tdd-require-red-py.py:61`; ebl `:133` |
| fastapi others | `tdd_py_lib.py:32` `TESTS_ROOT`, `:45` `TEST_FIRST_DIRS`; `enforce-backend-layers.py:69` `EXTERNAL_CLIENTS` (empty → check off), `:99` `SESSION_NAMES` | ebl `:165`, `:103` |

**Hook events and fail-closed channels** (`.claude/settings.json`):
- **PreToolUse `Write|Edit`** (`:80`): no-any-type, protect-files, no-forbidden-icons,
  english-comments, enforce-architecture, tdd-freeze-tests, tdd-require-red.
- **PreToolUse `Bash`** (`:123`): prevent-destructive, enforce-git-workflow.
- **PreToolUse `Read`** (`:140`): protect-files, auto-approve-config (allow only).
- **PreToolUse `Grep|Glob`** (`:156`): protect-files.
- **PostToolUse `Write|Edit`** (`:169`): format-on-save, eslint-check, tdd-prove-red.
- **Stop / SubagentStop**: eslint-batch.
- **Channels.**
  - PreToolUse: JSON `permissionDecision` on stdout, exit 0 (e.g. `prevent-destructive-commands.sh:44-53`,
    `enforce-architecture.py:113-119`). Exit 2 blocks (`hook-lib.sh:66`, `:84-89`; comment
    `:74-80`).
  - PostToolUse: `systemMessage` JSON (`tdd-prove-red.sh:171-175` `emit`).
  - Stop: `eslint-batch.sh:65` `systemMessage`. It never blocks (`:8-12`) and reads no stdin
    (`:14-15`).
  - The Python hooks only guard the stdin parse (`enforce-architecture.py:151-155`); any other
    exception exits 1 (= no verdict).
- **Library lookup.**
  - Shell hooks source `$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh` (e.g. PDC`:12`, EGW`:79`,
    PF`:39`).
  - `hook-lib.sh:60` → `hook-guarded.sh`, which sets `__CWK_GUARD_LIB_DIR` at `:67`.
  - Python adds its own dir to `sys.path` (`shell_targets.py:31`, `tdd-require-red-py.py:19`).
  - The addon hooks (`ruff-on-save.sh:18-19`) source `hook-lib.sh` from their own dir. No addon
    code references `project_config`, and the supabase addon has no hooks.
- **Writers.**
  - `install.sh`:
    - `copy_file` `:87-97` writes `<dst>.new` and never touches an active file.
    - `copy_tree` `:201-210` ships the kit's own `.claude/project.json`
      (`{"schema_version":1,"app_roots":[],"codegen_commands":[]}`).
    - `INSTALL_PROFILE` is overwritten on every run (`:668-672`).
    - `GUARD_FILES` `:212-214` (10 files incl. `project_config.py`), with the stamp check
      `guard_api_missing` `:247-261` → "P1 held back" `:313`.
    - `wire_supabase` `:457-508` uses perl on `enforce-architecture.py` DATA_CLIENT_* (`:465-469`)
      and `PROTECTED_DIRS` (`:494-498`). `wire_fastapi` `:405-444` uses perl on `PROTECTED_DIRS`
      (`:427`). Both edit only files installed in the same run (`:459-463`, `:407-410`) and print
      manual steps otherwise (`:484-489`, `:440-442`).
    - The fastapi CONFIGURE values are never wired (`:752-757`, manual `:829-839`).
    - **No code reads values back from active hooks**; the only hook-text read is
      `guard_api_number` `:240`.
  - `/kit:init`:
    - asks the values at `.claude/commands/kit/init.md:58-72`;
    - writes the hooks at `:82-83` (enforce-architecture + env twins) and `:101` (icons);
    - writes project.json at `:104`;
    - asks the protected branches (`:69`) but no step writes them.
- **Twins** (`kit-doctor.py`, `ROOT = argv[1] or parents[2]` `:40`). `is_kit_source()` `:814-815`
  = `install.sh` + `addons/`.
  - `check_protected_dirs` `:89`: hook regex `:95` against CLAUDE.md `:94`, unescape `\.` `:102,:108`.
  - `check_data_client` `:113`: `:119-120` against 01-stack.md `:118`.
  - `check_client_copies` `:146`: `:156` against templates.
  - `check_composition_roots` `:186`: `:192` against 02-architecture.md.
  - `check_shared_dirs` `:202`: `:216` against 3 docs `:221-226`, plus the count `:251`.
  - `check_tdd_layers` `:325`: `:333` against tooling-config `:334` and audit/mutation `:342`.
  - **No twin**: PROTECTED_BRANCHES, the test command, formatter, linter, env suffixes, icons,
    CWK_TDD_PY_TARGET_RE, the fastapi values. `check_github_protection` `:868` queries the GitHub
    API and does not read PROTECTED_BRANCHES.

## Reusable
- `project_config.py`: extend it (keys, defaults, schema migration, CLI). Do not write a second
  parser; one parser serves the shell and Python sides.
- `write_project_json` / `make_app_tree` / `pc_roots_expect` (test-hooks.sh `:1434-1617`) for
  value-per-key fixtures.
- The kit-doctor twin regexes `:95,:119-120,:192,:216,:333`: reuse them as the migration's
  readers, as the spec says, including the `\.` unescape `:108`.
- `copy_file` / `.new`, `guard_api_missing`, and the stamp + `GUARD_FILES` mechanism.
- `test-install.sh` scratch targets (`:5-26`), the re-run survival case (`:33-40`), and IN1-IN3
  (`:578-586`).
- `test-kit-doctor.sh`'s scratch copy pattern (`:12-14`, `:44-54`).

## Blast radius
- **Stamps** (line 2) to bump when a behaviour changes: hook-lib 2, hook-guarded 4,
  prevent-destructive 5 (checked by exact string at `:210`), shell_targets 5 (pinned
  `test-hooks.sh:2387`), enforce-git 3, protect-files 2, auto-approve 1, tdd-require-red 1,
  project_config 1, kit-attempts 1. No stamp today on tdd-prove-red, tdd-freeze-tests,
  enforce-architecture, format-on-save, eslint-batch, no-forbidden-icons, or the addon hooks.
  A hook that starts reading the file and is not in `GUARD_FILES` will not hold P1 back when it
  lags.
- **Suites that edit hook text** and break when the values move:
  - `test-install.sh:267-274` (sed on PROTECTED_DIRS / PROTECTED_BRANCHES, then grep);
  - `test-small-lane.sh:74` (`SELECTORS_SED` on the CWK_TDD_LAYERS line);
  - `test-kit-doctor.sh:45` (a twin `enforce-architecture.py` with `lib/api`).
- **Fixtures run with `CLAUDE_PROJECT_DIR` = the repo** (`test-hooks.sh:116`, exported at
  `:538`), so they read the repo's own `project.json`. Moving the defaults into the file must not
  change any default verdict. `run_harness_reproduction` `:591` overrides only HOOKS_DIR and
  FIXTURES_DIR.
- **Fixture counts that pin today's defaults**:
  - enforce-git 99 files, 8 contain `main`;
  - prevent-destructive 19, `docs/` in 12;
  - protect-files 42;
  - tdd-require-red 18 and tdd-freeze 20 (layer names);
  - no-forbidden-icons 2 (`Rocket`);
  - enforce-architecture 5 (path-based `rfind("src/")` `:166-169`, independent of
    CLAUDE_PROJECT_DIR);
  - tdd-prove-red 1;
  - none for format-on-save, eslint-batch or the fastapi hooks.
- **Contracts**:
  - `test-workflow-contracts.sh:853-875`: every `project_config.py` call in `.claude/hooks/*.sh`
    and install.sh uses `python3 -I`;
  - `:861`: hook-guarded.sh names `project_config.py`;
  - `:765`: GUARD_FILES;
  - `:864-869`: W5 hard-codes 516 lines.
  - `test-rules-floor.sh`: 516/520 (run 2026-11-15), so CLAUDE.md + rules have 4 lines of
    headroom.
- **Docs**:
  - `CLAUDE.md:42-44` (FILL naming PROTECTED_DIRS, read by `check_protected_dirs` and install.sh
    perl `:501,:437`); `01-stack.md:38-39`; `02-architecture.md:35`; `09-icons.md:7-8`;
    `github.md:27-28`; `00-project.md:23`;
  - `docs/ADAPTATION.md`: §1, §2 `:24-56`, §2 bis `:57-68`, §4 `:95-114`, §7 `:345`, §11
    `:371-375`, §14 `:457-464`, upgrade `:564-590`, probes `:594-611`, `:664-668`;
  - `README.md:39-51`;
  - `addons/supabase/README.md:38-43`, `addons/supabase/rules/01-stack.md:119-120`;
  - `addons/fastapi/README.md:44, :152-153`.
- **EcoCrew** (`/home/stevan/Travail/Projetperso/ecocrew`, backups `ecocrew-kit-backup-2026-10-26`
  and `-11-08`) holds these values in its active hooks:
  - `PROTECTED_BRANCHES="main"` (EGW`:94`);
  - `PROTECTED_DIRS="frontend|backend|src|shared|app|alembic|\.claude|public|node_modules|dist"`
    (PDC`:78`);
  - `DATA_CLIENT_MODULE="lib/api"` / `"lib/api.ts"`, kit-default COMPOSITION_ROOTS and
    SHARED_DIRS;
  - `RUN_TESTS="pnpm --dir frontend exec vitest run"`;
  - `MODULE_ROOT` `"app/"` / `"app"`;
  - everything else at the kit default.

  It has no `project.json`, and its stamps are older (hook-guarded 3, PDC 3, shell_targets 3,
  no `project_config.py`), so P1 is held back there today. Its line numbers differ from the
  kit's, so the migration must read through anchored regexes, never line numbers.

## Live DB state
n/a (kit tooling).

## External surface
n/a: no third party. Claude Code hook semantics (PreToolUse JSON decision, exit 2 blocks,
PostToolUse/Stop `systemMessage`) are used as today, settled by the existing suites.

## Traps (points of vigilance for the review)
- **The shipped reader fails open.**
  - `hook-guarded.sh:80-81`: exit 3 → no app roots, so the app-root guard silently drops.
  - `shell_targets.py:49-50`: ConfigError → no codegen, silently.
  - The spec requires fail closed per event. The PreToolUse callers must turn exit 3 into an ask,
    not into "no value".
- **Exact-version, all-keys schema.** `project_config.py:112-120` refuses unknown keys, missing
  keys, and any `schema_version` ≠ 1. The spec wants an older file to stay valid, with the new
  keys defaulted and no new deny. Missing keys at an older version must take defaults; an unknown
  key or a newer version must still fail closed.
- **The kit's own project.json ships to every target** (`copy_tree`). On re-install it gets a
  `.new` beside the user's file, so it is never merged. The migration writes the file; the
  `.new` path must not be how values arrive.
- **The test command is a command the hook executes** (`tdd-prove-red.sh:230-232`). From JSON it
  must be an argv list, never a shell string or `eval`. The same rule applies to the formatter
  and linter. `RUNNER_BIN="${RUN_TESTS%% *}"` `:182` assumes the first word is the binary.
- **Regex values become data.**
  - PROTECTED_BRANCHES goes into `grep -E "^(…)$"`. The spec turns branches into globs
    (`release/*`).
  - PROTECTED_DIRS goes into `GUARD_PROTECTED_RE` `:505-506`.
  - The env suffixes appear in 5 shapes (bash regex, sed literal, Python regex, Python set, an
    exact `.env.example`). One JSON list must render to each shape with escaping, or a value with
    `|`, `.` or `)` changes a verdict.
- **The env copies disagree today.** `auto-approve-config.sh:89` auto-approves only
  `.env.example`, while `protect-files.sh:100` allows example, sample and template. The spec says
  the protect-files copy wins: the migration must not widen auto-approve by accident unless the
  plan says so.
- **fastapi MODULE_ROOT is `"app"` vs `"app/"`.** One key must normalise both, and
  `CWK_TDD_PY_TARGET_RE` in hook-lib must be derived from it, not mirrored.
- **Values hard-coded outside the spec list** (the "no hook holds a project value" grep will hit
  them; in or out must be decided):
  - `shell_targets.py:190-192` `SAFE_SCRIPTS` / `SCRIPT_TOOL` (script names `test:run`,
    `test:coverage`…);
  - `prevent-destructive-commands.sh:336` (test script names) and `:927-931` (prettier, eslint,
    ruff, biome);
  - `auto-approve-config.sh:76-89` config names;
  - `hook-guarded.sh:20-40` `CWK_GUARDED`;
  - `english-comments.py:88-89,:149` (language word list);
  - `tdd-prove-red.sh:46` `RUN_TIMEOUT`;
  - `eslint-batch.sh:51` cache path;
  - `addons/fastapi/hooks/ruff-on-save.sh:58` `FROZEN_TEST_PY_RE`.
- **Latency.**
  - `protect-files.sh` runs on every Read, Grep and Glob: mean 41 ms, max 331
    (`.claude/.hook-timings.log`, 545 calls).
  - One `python3 -I -B project_config.py` start costs about 72 ms on this machine (main thread,
    `time`, absent-roots path).
  - An extra Python spawn per Read would roughly triple that hook's time. `prevent-destructive`
    is already at a 378 ms mean with two Python spawns.
  - `enforce-architecture.py`'s timer starts after the imports, so the interpreter start-up is
    not in the log.
- **Python hooks exit 1 on an uncaught exception** (no verdict). A reader error in
  `enforce-architecture.py` / the addon hooks must be caught and turned into an ask JSON, or it
  fails open.
- **Addon hooks find libs through their own dir**; the spec wants the reader found through the
  project. In an installed project both are `.claude/hooks/`, but in the kit repo the addon hooks
  live in `addons/fastapi/hooks/` (`test_imported_symbols.py` is run from there,
  `test-hooks.sh:2624-2628`).
- **The migration reads hooks that differ by install age.** EcoCrew's PDC is at stamp 3 with
  different line numbers. A value the anchored regex cannot read keeps its default with a warning
  that names the key. A regex branch alternative must become a glob, and anything that is not a
  plain alternation must be warned about, never guessed.
- **Rules floor headroom is 4 lines.** The CLAUDE.md "change both together" / FILL wording
  changes must be net ≤ +4, or the ceiling is an explicit decision. W5 also hard-codes 516.
- **Every new Python call in shell needs `python3 -I`** (`test-workflow-contracts.sh:853-875`).
- **No hook-level case covers a missing or invalid project.json today** (PC3 covers the reader
  only). Each reader's fail-closed behaviour is new coverage.

## Open questions
1. **Shell read strategy and budget** (the spec's open question). Should shell hooks get every
   key from one reader run per hook process (e.g. one `project_config.py env <dir>` printing
   NUL-separated or shell-quoted `KEY=value` lines, parsed and never `source`d), or one run per
   key? What budget applies to protect-files on Read/Grep/Glob? Today the mean is 41 ms, and one
   Python start adds about 72 ms. Is the cost accepted, or does protect-files read only the env
   suffixes through a cached or lazy path, spawning only when the path is a `.env*`?
2. **Value scope.** Are the hard-coded values outside the spec list (Traps: `SAFE_SCRIPTS`,
   PDC`:336`, `:927-931`, `CWK_GUARDED`, auto-approve config names, `english-comments` words,
   `RUN_TIMEOUT`, eslint cache path, `ruff-on-save` `FROZEN_TEST_PY_RE`) in this pass, or kit
   behaviour that stays in the hooks? The acceptance grep "no hook holds a project value" needs
   that list to be explicit.
3. **Command shape.** Are the test command, formatter and linter argv lists in JSON
   (`["pnpm","test:run"]`)? Is the formatter/linter key a binary name resolved by `cwk_bin`, or a
   full argv? Does `SAFE_SCRIPTS` follow the test command's script name?
4. **The env suffix disagreement.** Should `auto-approve-config.sh:89` (only `.env.example`) take
   the shared list, which widens the auto-approve to `.sample`/`.template`, or keep a narrower
   rule of its own?
5. **Schema evolution.** Does the reader move to `schema_version` 2, where version 1 files get
   the new keys' defaults in memory and are never rewritten by a hook? Is a newer-than-known
   version ConfigError (fail closed)? Does `install.sh` rewrite the file to the current version
   on upgrade?
6. **Migration placement.** In `install.sh` (bash + the anchored regexes through a Python
   helper, since kit-doctor's regexes are Python), or in a `project_config.py migrate <dir>`
   subcommand that kit-doctor's regexes are moved into? When an active hook is older than the
   kit (copy_file writes `.new`), the migration reads the **active** file, and the `.new` stays
   for the user to merge.
7. **Addon reader location.** In the kit repo, should the addon hooks import `project_config`
   from `$CLAUDE_PROJECT_DIR/.claude/hooks/`, or keep their own dir (which holds the reader only
   once installed)? Fail closed if neither is found?
