# Plan: Kit boundary, pass 2a   (entry: docs/specs/kit-boundary.md · research: docs/work/kit-boundary/research.md · design: n/a)
Token profile: critical
Rewrite 2 (2026-11-10): the spec was split, and kit prompts moved to `docs/specs/kit-prompts.md`. This version answers every Critical and Major that survived the verifier (`## Plan critic`); each fix is tagged with the finding it closes.

## Skips
- DB : SKIP. There is no data model (spec `## Data model` none).
- Backend : SKIP. This is kit tooling (spec `## Custom backend` NONE).
- Front / UI / INTERFACE : SKIP. No app code, no screen.
- Codex routing : SKIP. This is guard code, so every step stays on Claude.
- TS test-first layers : none are touched. The kit's own cycle applies instead:
  - Every case below is a fixture or a suite assertion.
  - It is written first, **observed failing** on the current code, then made green.
  - A case already green before the change is marked `(guard)` and must stay green.

## Decisions (validated at `## Gate`)
- **Q1 config file.** `.claude/project.json`, in JSON.
  - **Reader.** Only `.claude/hooks/project_config.py` reads it. It finds the file **from its own path** (`<hooks dir>/../project.json`), never from the cwd or `CLAUDE_PROJECT_DIR` [M9, M16]. The hooks live in `<project>/.claude/hooks`, so this always names the project, including on a manual run with no env (X23).
  - **Python hooks** import the reader through an explicit `sys.path` insert of their own dir.
  - **Shell hooks** call `python3 -I -B "$CWK_HOOK_DIR/project_config.py" get <key> --regex|--nul|--lines` once per run. The path is absolute [M9]. The file is never `source`d and never `eval`ed.
  - **Validation.** Each value is checked against its own character class before any output:
    - paths: no `..` segment, never absolute;
    - branch names: `^[A-Za-z0-9._/*-]+$`, where `*` is a glob [M13];
    - suffixes: alphanumeric;
    - argv items: non-empty, no NUL.
  - **Keys.**
    - `schema_version` (int).
    - Data client: `data_client_module` (string or null), `data_client_own_path`, `composition_roots[]`, `shared_dirs[]`.
    - Guards: `protected_dirs[]`, `protected_branches[]`.
    - Commands, as argv lists: `test_command[]`, `formatter[]`, `linter[]` [M1].
    - Lists: `env_template_suffixes[]`, `forbidden_icons[]` [M1], `tdd_layers[]` [M1].
    - `addons` (object). It holds the fastapi CONFIGURE values when that addon is installed [M1].
    - New: `app_roots[]`, `codegen_commands[][]` (argv prefixes).
  - **Schema [M11].**
    - An unknown key is invalid.
    - A key missing from a file whose `schema_version` is below the reader's own gets its default from the reader's table, and the file is still valid. A kit upgrade therefore never fails closed on a key it introduced.
    - A missing key at the current version is invalid.
    - `install.sh` rewrites the file additively on upgrade: new keys are added with their defaults and the version is bumped.
  - **Fail closed [M3, M9].** A missing, unreadable or invalid file makes every reader fail closed through **its own deny channel**:
    - shell hooks print a deny/ask JSON;
    - Python hooks catch `ConfigError` and print their usual JSON deny with exit 0, never a bare non-zero exit, which Claude Code treats as non-blocking;
    - the verdict is ask in the kit repo and deny in an installed project.
    - The message gives a remedy the user can run: "run `install.sh` again (it recreates `.claude/project.json`), then `/kit:init`" [M10].
  - **The kit repo** commits its own `.claude/project.json` holding today's hard-coded values, so its behaviour does not change.
- **Q2 `/kit:init` in an installed project.** No in-session exception exists.
  - `/kit:init` writes its proposal to `docs/work/kit-init/project.json` (an unguarded path).
  - It then prints one command for the user to run **in their own terminal**: `python3 .claude/hooks/project_config.py apply docs/work/kit-init/project.json`.
  - The shell guard denies that `apply` from a tool call in an installed project and asks in the kit repo [M12]. The deny text says to run it in a terminal.
  - In the kit repo, `/kit:init` keeps writing the file directly, with an ask on the guarded file.
  - `/kit:recipe` is unchanged in this pass, because it writes prompts (pass 2b).
  - *Amends the contract* (`## Gate` A1).
- **Q3 installed check [C2].** Installed ⇔ `.claude/.kit-installed` exists **OR** the project root lacks `install.sh` or `addons/`.
  - Paths are resolved from the hook's own dir, like Q1.
  - `install.sh` writes the stamp on every run.
  - Dropping the stamp (`git rm`, `git stash -u`, a lost file) never downgrades the deny in a tree without the kit markers. In an installed project, creating `install.sh` or `addons/` is denied (K5), so the kit repo cannot be faked.
  - The stamp file is kit code and is also listed in `CWK_GUARDED` [m7].
  - `/kit:init` and `kit-doctor.py` get the mode from `project_config.py mode` (`kit-repo` | `installed`) [m2].
  - *Amends the contract*, which wanted a line inside `hook-guarded.sh`. That line is lost on re-install (research Traps) (`## Gate` A2).
- **Q4 upgrade.** When `install.sh` runs on a project that already has `.claude/hooks/`:
  1. **`project.json`.**
     - Absent: the filled values are extracted from the **active** hooks, with the same anchored regexes and the same `\.` unescape as `kit-doctor.py:106` [M13]. A regex branch such as `release/.*` becomes the glob `release/*` [M13]. A value that cannot be read gets the kit default, with a printed warning naming the key.
     - Present: it is migrated additively (Q1) [M11].
  2. **Kit code.** In this pass that means hooks, scripts and root launchers, *not* prompts [C1, M14]. Old copies that differ go to `.claude/.kit-backup/<UTC stamp>/` (gitignored), then the kit's copy overwrites them. This removes the "P1 held back" path for kit code (`## Gate` A3).
  3. **Prompts, rules, `CLAUDE.md`, `settings.json`, docs** keep today's `.new` / merge behaviour.
     - The `wire_supabase` template rewrite therefore keeps working on prompts [M14].
     - `wire_supabase` / `wire_fastapi` write their values into `project.json` instead of into hook text.
- **Q5 values moved [M1, M2].** Every project value held by a hook moves, because a denied hook can no longer be adapted:
  - the spec's 11 values;
  - the linter (`eslint-batch.sh`);
  - the icon list (`no-forbidden-icons.sh`);
  - `CWK_TDD_LAYERS`;
  - the fastapi CONFIGURE values (`enforce-backend-layers.py`, `tdd_py_lib.py`).

  The env-template value has **five** copies, and all of them read the config: `protect-files.sh`, `prevent-destructive-commands.sh:183`, `shell_targets.py:152`, `auto-approve-config.sh:89`, `enforce-git-workflow.sh:197` `SECRET_KEEP`.
- **Q6 codegen deny.**
  - Applies to `.ts`, `.tsx` **and** `.py`; `.py` is a new verdict.
  - Amends six frozen rows, mapped by their real ids [M4]: X32.07, X32.08, X42.04, X42.05, X28.79 (all ask → deny), and X24.413 (a guarded `.py` target: guarded ask → kit-code deny when installed, unchanged in the kit repo).
  - The X23 no-base case (`echo x > app/api/routes.py` with no env) is re-measured at RED and listed in `## Gate` A4 if it flips.
- **Q7 git routes [M6, M7, M18, m4].** These rules apply only in an installed project.
  - **Path normalisation [M18].** Every git path operand is first normalised to project-relative: it is joined to the call's `-C` directory and cwd, then made relative to the project's top level.
  - **Deny** when a call writes a kit path:
    - `checkout [<ref>] -- <paths>`, which covers the index route [M7];
    - `restore [--source] <paths>`;
    - `rm` and `mv` [M7];
    - `apply` / `am`. Paths are read from the patch's `diff --git` headers. A `-p<n>` other than 1, `--directory`, stdin, or an unreadable patch → ask [M7];
    - `stash pop|apply`, reading `git stash show --include-untracked --name-only` [M7]. If that read fails → ask.
  - **Ask** ("this brings kit changes from <ref>") on a ref-moving call whose incoming change touches kit paths:
    - `merge`, `pull`, `switch`/`checkout <branch>`, `reset --hard <ref>` read `git diff --name-only HEAD...<ref>` (three-dot) [m4];
    - `cherry-pick`/`revert <sha>` read `git diff-tree --no-commit-id --name-only -r <sha>` [m4];
    - `rebase` reads three-dot against its upstream.
  - Every diff runs under the existing `deadline_git`, in the project repo only (e4837f2). A failure → ask.
  - *Amends the contract*: spec V9 says deny for merge/switch/stash pop. Here only `stash pop` keeps the deny; merge and switch ask, so that merging `main` after a kit upgrade stays possible (`## Gate` A5).
- **Q8 symlink alias [M8].** The kit-code check resolves the target through `cwk_real_rel` (symlinks followed), in `protect-files.sh` and in the shell guard. `ln -s <kit path> <x>` in an installed project is denied as a kit-code write, because its source is resolved too.
- **Q9 rules floor.** Net ≤ 0 lines in `CLAUDE.md` + `.claude/rules/*.md`.

## Write chain (sequential)
**Step gate [M15].** Each step follows the same cycle:
1. Write its cases, run them, and **observe the new cases fail** (paste the count into the handoff).
2. Implement.
3. The step's cases go green and every previously green case stays green, **except** the rows `## Gate` lists for that step.
4. Then the next step.

Every suite runs at step 9.

1. **Config reader.** Creates `project_config.py` (`# cwk-guard-api: 1`) with `get`/`check`/`apply`/`mode`, the kit's `.claude/project.json`, and the `hook-lib.sh` helpers `cwk_conf_regex`, `cwk_conf_argv` and `CWK_HOOK_DIR`. Cases J1-J16.
2. **Values move, with their twins.** Every value in Q5 moves.
   - Retargeted **in the same step** so that no suite goes red between steps [M15]:
     - `kit-doctor.py` twins (`check_protected_dirs`, `check_data_client`, `check_client_copies`, `check_composition_roots`, `check_shared_dirs`, new `check_project_config`, the `protected_branches` twin vs `github.md`);
     - `install.sh`'s writers of those values (`wire_supabase`/`wire_fastapi` write `project.json`; `test-install.sh:262-268` is retargeted);
     - the formatter, which still resolves through `cwk_bin` [m7].
   - Cases V1-V16, Q1-Q5.
3. **Installed check + kit-code deny (Write/Edit + shell).**
   - `hook-guarded.sh` gets `cwk_installed` (Q3), `CWK_KIT_CODE` (`.claude/hooks/*`, `.claude/scripts/*`, `.claude/project.json`, `.claude/.kit-installed`, `install.sh`, `addons`, `addons/*`, `workflow.py`, `workflow.sh`, `codex-handoff.sh`) and `cwk_is_kit_code`, which uses the real path (Q8).
   - The stamp joins `CWK_GUARDED`.
   - `protect-files.sh` and `prevent-destructive-commands.sh` call the check before the guarded ask.
   - The `project_config.py apply` rule is added.
   - Cases K1-K18.
4. **Kit-code deny (git).**
   - `enforce-git-workflow.sh` receives the kit-code pattern list and the installed flag as argv.
   - It normalises operands to project-relative.
   - It adds rules for `apply`, `am`, `rm`, `mv` and `stash pop|apply`, extends `checkout_rule`/restore, and asks on ref-moving calls (Q7).
   - Cases G19.01-G19.22.
5. **APP_ROOTS.** `hook-guarded.sh` guards `<app root>/<root config pattern>` for each declared root, and the cfg branch lets a declared app root pass. Cases A1-A10.
6. **CODEGEN_COMMANDS.** `shell_targets.py` emits `>cg` rows. The `>` branch denies `.ts`/`.tsx`/`.py` targets and asks on codegen. Cases D1-D10.
7. **install.sh upgrade.** Writes the stamp on every run, copies `project.json` on a fresh install, then runs the Q4 migration, backup and kit-code overwrite. Also updates `.gitignore`, `GUARD_FILES` and the api bumps. Cases I1-I12.
8. **Commands and docs.**
   - `kit/init.md`: Q2 and the mode via `project_config.py mode`.
   - `kit/doctor.md`: the check table.
   - Pointers in `CLAUDE.md`, `01-stack.md`, `02-architecture.md` and `github.md`.
   - `docs/ADAPTATION.md` (§2, §2 bis, §4, §7, §11, §14, upgrade section) and `README.md`.
   - The supabase addon docs.
   - The `harness-hardening.md` follow-ups (m5).
   - Cases W1-W8, Q6-Q7.
9. **Refactor + gates.**
   - Every suite and `kit-doctor.py`.
   - Replay the EcoCrew prompts with an EcoCrew-shaped `project.json`.

## Parallel lots
None: the chain is fully sequential (steps 2-6 share `hook-guarded.sh`, `prevent-destructive-commands.sh` and `test-hooks.sh`).

## Track isolation
- Worktree: none. This is a single track on the main tree, `audit/slim`.
- Shared foundations touched: every guard hook, `install.sh`, `CLAUDE.md`, `.claude/rules/*`, `kit-doctor.py`. No other kit pass runs beside this one.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/project_config.py` | Create | the single reader and validator, plus a CLI (`get`, `check`, `apply`, `mode`) |
| `.claude/project.json` | Create | kit defaults with `schema_version: 1` |
| `.claude/hooks/hook-lib.sh`, `hook-guarded.sh` | Edit | conf helpers, `CWK_HOOK_DIR`, `cwk_installed`, `CWK_KIT_CODE`, app-root patterns, guarded additions, api bumps |
| `.claude/hooks/protect-files.sh`, `prevent-destructive-commands.sh`, `shell_targets.py` | Edit | kit-code deny via the real path, values from config, cfg app-root pass, `>`/`>cg`, `apply` rule |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | branches and `SECRET_KEEP` from config, kit-path git rules, operand normalisation |
| `.claude/hooks/enforce-architecture.py`, `tdd-prove-red.sh`, `format-on-save.sh`, `auto-approve-config.sh`, `eslint-batch.sh`, `no-forbidden-icons.sh` | Edit | values from config, fail closed through their own channel |
| `addons/fastapi/hooks/enforce-backend-layers.py`, `tdd_py_lib.py` | Edit | CONFIGURE values from `project.json` `addons.fastapi` |
| `.claude/hooks/kit-doctor.py` | Edit | twins from config, config check, mode |
| `.claude/hooks/test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-workflow-contracts.sh`, fixtures | Edit/Create | cases below |
| `install.sh` | Edit | stamp, `project.json`, migration, backup, overwrite, addon wiring, gitignore, `GUARD_FILES` |
| `.claude/commands/kit/{init,doctor}.md`, `.claude/agents/github.md` | Edit | Q2, check table, branches pointer |
| `CLAUDE.md`, `.claude/rules/01-stack.md`, `02-architecture.md`, `docs/ADAPTATION.md`, `README.md`, supabase addon docs, `docs/specs/harness-hardening.md` | Edit | pointers and docs |

## Contracts
- **`project_config.py`.**
  - `load() -> dict`, path from `__file__`. On error it raises `ConfigError(<english reason>)`. Defaults are filled for keys added after the file's `schema_version`.
  - CLI:
    - `get <key> --regex|--nul|--lines`;
    - `check` → exit 0, or exit 3 with the reason;
    - `mode` → `kit-repo` | `installed`;
    - `apply <proposal>` → validates, writes atomically, exit 3 on any error with nothing written.
- **Hook verdicts.**

  | Target | kit repo | installed |
  | --- | --- | --- |
  | `.claude/hooks/*`, `.claude/scripts/*`, root launchers, `addons/*` | ask (today) | **deny** |
  | `.claude/project.json`, `.claude/.kit-installed` | ask | **deny** |
  | `install.sh`, `addons` created | ask (today) | **deny** |
  | `.claude/agents\|commands\|skills\|guides/*` | today | today (pass 2b) |
  | `<app root>/<root config pattern>` (declared) | ask | ask |
- **Deny texts.**
  - Kit code: `kit code changes in the LoopKit repo, then install.sh: <rel>`.
  - Missing config: `.claude/project.json is missing or invalid (<reason>): run install.sh again, then /kit:init.`
  - Codegen: a redirection onto `*.ts|*.tsx|*.py` → deny `This writes a source from the shell. Use Write/Edit (a generator listed in .claude/project.json codegen_commands keeps its ask).` From a listed command → ask `codegen: <cmd> writes <rel>`.

## Test plan (gate — validated by the user before EXECUTE)
Every case states the verdict expected **after** the change. RED means it fails on the current code. Setups:
- `installed`: a tmp project with the stamp and no `install.sh`/`addons/`.
- `kitrepo`: with `install.sh` + `addons/`.

### Step 1 — `project_config.py` (block J)
- [ ] J1 the kit's `project.json` loads; `get protected_branches --regex` prints `main|master`
- [ ] J2 `get test_command --nul` prints `pnpm\0test:run\0`
- [ ] J3 `get protected_dirs --regex` escapes a dot
- [ ] J4 missing file exits 3; the reason names `install.sh` and `/kit:init`
- [ ] J5 invalid JSON exits 3
- [ ] J6 unknown key exits 3 naming it
- [ ] J7 missing key at the current `schema_version` exits 3 naming it
- [ ] J8 a key added after the file's `schema_version` is missing → valid, default returned [M11]
- [ ] J9 a branch holding `|` exits 3; `release/*` loads
- [ ] J10 app root `../x` or `/abs` exits 3
- [ ] J11 `test_command` as a string exits 3
- [ ] J12 a symlinked `project.json` pointing outside the project exits 3
- [ ] J13 `apply` with an invalid proposal writes nothing (old file byte-identical)
- [ ] J14 run from another cwd (`cd /tmp`) with `CLAUDE_PROJECT_DIR` unset, the reader still finds the file next to its hooks [M16]
- [ ] J15 `mode` prints `installed` with the stamp; `installed` with no stamp and no `install.sh`; `kit-repo` with no stamp and `install.sh` + `addons/` [C2]
- [ ] J16 `mode` on the kit repo itself prints `kit-repo`

### Step 2 — values from the config (block V, kit-doctor Q1-Q5)
- [ ] V1 `protected_branches: ["main","release/*"]`: a commit on `release/1` is denied (RED)
- [ ] V2 `protected_dirs` + `docs`: `rm -rf docs` asks (RED)
- [ ] V3 `data_client_module: "lib/api"`: a component importing `@/lib/api` is denied (RED)
- [ ] V4 `composition_roots: ["app.tsx"]`: `src/app.tsx` may import the client (RED)
- [ ] V5 `test_command: ["true"]`: `tdd-prove-red.sh` runs it (RED)
- [ ] V6 `formatter` argv runs on the saved file through `cwk_bin` (RED)
- [ ] V7 `env_template_suffixes: ["dist"]`: `.env.dist` is a template in all **five** readers, `.env.example` is not (RED)
- [ ] V8 `linter` argv is what `eslint-batch.sh` runs (RED) [M1]
- [ ] V9 `forbidden_icons` drives `no-forbidden-icons.sh` (RED) [M1]
- [ ] V10 `tdd_layers` drives the TDD matcher (RED) [M1]
- [ ] V11 `addons.fastapi` values drive `enforce-backend-layers.py` and `tdd_py_lib.py` (RED) [M1]
- [ ] V12 missing `project.json`, kit repo, every reader asks naming `install.sh`: Write `src/a.ts`; `git commit`; `tdd-prove-red.sh`; `enforce-architecture.py` (JSON + exit 0, never a bare non-zero exit); `format-on-save.sh`; `auto-approve-config.sh`; `eslint-batch.sh`; `no-forbidden-icons.sh`; `rm -rf src` (RED) [M3, M9]
- [ ] V13 the same with setup `installed` → deny (RED)
- [ ] V14 (guard) with the kit's default `project.json`, the existing suites stay green
- [ ] V15 no hook file holds a project value (`test-workflow-contracts.sh` grep over the old constant names)
- [ ] V16 Python readers locate the config via `__file__`, not the cwd: run from `frontend/` (RED) [M9]
- [ ] Q1-Q5 kit-doctor twins read `project.json`: protected-dirs, client-copies, composition-roots, project-config invalid, protected-branches vs `github.md`

### Step 3 — kit-code deny, Write/Edit and shell (block K)
- [ ] K1 installed: Edit `.claude/hooks/x.sh` → deny (RED)
- [ ] K2 installed: Edit `.claude/commands/loop/ship.md` → today's pass (guard, pass 2b) [C1]
- [ ] K3 installed: Write `.claude/scripts/x.sh`, `workflow.py` → deny (RED)
- [ ] K4 installed: Edit `.claude/project.json` → deny (RED)
- [ ] K5 installed: Write `install.sh`, `addons/x`, `mkdir addons` → deny (RED)
- [ ] K6 kitrepo: Edit `.claude/hooks/x.sh` → ask (guard); Edit `.claude/project.json` → ask (RED)
- [ ] K7 installed shell writes → deny (RED):
  - `echo x > .claude/hooks/x.sh`
  - `sed -i s/a/b/ .claude/hooks/x.sh`
  - `cp /tmp/x .claude/scripts/x.sh`
  - `echo {} > .claude/project.json` [m1]
  - `mv a .claude/hooks/x.sh`
- [ ] K8 installed: `rm .claude/.kit-installed`, Write `.claude/.kit-installed` → deny (RED)
- [ ] K9 installed, stamp deleted out of band (no `install.sh`/`addons/`): Edit `.claude/hooks/x.sh` → still deny [C2]
- [ ] K10 installed: Edit `src/a.ts`, `.claude/rules/03-conventions.md`, `CLAUDE.md` → today's verdict (guard)
- [ ] K11 installed: a symlinked stamp → installed
- [ ] K12 installed: `.claude/worktrees/w/.claude/hooks/x.sh` → deny
- [ ] K13 installed: `./.claude/hooks/../hooks/x.sh` → deny
- [ ] K14 installed: unresolved target `echo x > $F` keeps today's ask (guard)
- [ ] K15 installed: Read/Grep of kit code passes (guard)
- [ ] K16 installed: `ln -s .claude/hooks/x.sh foo` → deny; with a pre-existing link `foo` → `.claude/hooks/x.sh`, Edit `foo` → deny (RED) [M8]
- [ ] K17 installed: `python3 .claude/hooks/project_config.py apply p.json` → deny naming the terminal; kitrepo → ask (RED) [M12]
- [ ] K18 installed: `.claude/.kit-installed` is in `CWK_GUARDED`; in the kit repo an Edit of it asks [m7]

### Step 4 — kit-code deny, git (G19.*, setup `installed` in the git fixture repo)
- [ ] G19.01 `git checkout main -- .claude/hooks/x.sh` → deny (RED)
- [ ] G19.02 `git restore --source=main .claude/hooks/x.sh` → deny (RED)
- [ ] G19.03 `git apply p.diff` touching `.claude/scripts/x.sh` → deny (RED)
- [ ] G19.04 `git apply p.diff` touching only `src/a.ts` → pass (guard)
- [ ] G19.05 `git apply < p.diff`, `cat p.diff | git apply`, `git apply -p2 p.diff`, `git apply --directory=.claude p.diff` → ask (RED) [M7]
- [ ] G19.06 `git am m.mbox` touching `.claude/hooks/x.sh` → deny (RED)
- [ ] G19.07 `git stash pop`, stash touching `.claude/hooks/x.sh` → deny (RED)
- [ ] G19.08 `git stash pop` after `git stash -u` whose untracked part holds `.claude/hooks/new.sh` → deny (RED) [M7]
- [ ] G19.09 `git stash pop` touching only `src/` → pass (guard)
- [ ] G19.10 `git merge feat/x`, the branch changing `.claude/hooks/x.sh` since the merge base → ask (RED)
- [ ] G19.11 `git merge old/x`, a branch cut before a kit upgrade on main with no kit change of its own → pass (three-dot) (RED for the two-dot design) [m4]
- [ ] G19.12 `git switch feat/x` with the G19.10 diff → ask (RED)
- [ ] G19.13 `git cherry-pick <sha>` / `git revert <sha>` whose own commit touches a kit path → ask; a commit touching only `src/` → pass (RED) [m4]
- [ ] G19.14 `git reset --hard <ref>`, `git pull` bringing a kit path → ask (RED)
- [ ] G19.15 `git checkout main -- src/a.ts` → today's verdict (guard)
- [ ] G19.16 unknown ref `git merge nope` → ask
- [ ] G19.17 kitrepo: G19.01, G19.03, G19.10 → today's verdict (guard)
- [ ] G19.18 `git rm .claude/hooks/x.sh`, `git rm --cached .claude/.kit-installed`, `git mv .claude/hooks/x.sh y` → deny (RED) [M7, C2]
- [ ] G19.19 `git checkout -- .claude/hooks/x.sh` (index route, no ref) → deny (RED) [M7]
- [ ] G19.20 `git -C .claude checkout main -- hooks/x.sh` → deny (operand normalised) (RED) [M18]
- [ ] G19.21 `git -C .claude/hooks restore x.sh` → deny (RED) [M18]
- [ ] G19.22 `git rm src/a.ts` → today's verdict (guard)

### Step 5 — APP_ROOTS (setup `approots`: `frontend/{package.json,tsconfig.json,vite.config.ts}`, `other/package.json`, `app_roots: ["frontend"]`)
- [ ] A1 Edit `frontend/vite.config.ts` → ask (RED)
- [ ] A2 Edit `frontend/package.json`, `frontend/tsconfig.app.json`, `frontend/eslint.config.js` → ask (RED)
- [ ] A3 `echo x > frontend/package.json` → ask (RED)
- [ ] A4 cwd `frontend/`: `pnpm exec tsc --noEmit -p .` → pass (RED)
- [ ] A5 root: `pnpm exec tsc --noEmit -p frontend` → pass (RED)
- [ ] A6 cwd `other/`: `tsc -p .` → ask (guard)
- [ ] A7 `app_roots: []`: Edit `apps/web/package.json` → pass, `tsc -p frontend` → ask (guard)
- [ ] A8 `app_roots: []`: `-p frontend/tsconfig.app.json` → ask (guard)
- [ ] A9 Edit `frontend/src/a.ts` → pass (guard)
- [ ] A10 `vitest --config frontend/vite.config.ts` from root → pass

### Step 6 — CODEGEN_COMMANDS (setup `codegen`: `[["supabase","gen","types"],["pnpm","supabase","gen","types"]]`)
- [ ] D1 `echo x > src/a.ts` → deny (amends X32.07) [M4]
- [ ] D2 `cat >> src/a.ts <<'EOF'` → deny (amends X32.08)
- [ ] D3 `echo x >src/App.ts`, `echo x >src/App.t's'` → deny (amends X42.05, X42.04) [M4]
- [ ] D4 `echo 'export const a = 1' > src/b.ts` → deny (amends X28.79) [M4]
- [ ] D5 `echo x > src/a.py` → deny (RED)
- [ ] D6 `pnpm supabase gen types > src/types/database.types.ts` → ask "codegen"
- [ ] D7 `supabase gen types; echo x > src/a.ts` → deny
- [ ] D8 `echo $(supabase gen types) > src/a.ts` → deny
- [ ] D9 `env supabase gen types > src/types/db.ts` → ask
- [ ] D10 `echo x > docs/a.md` → pass (guard)

### Step 7 — install.sh (block I)
- [ ] I1 a fresh install writes the stamp and the default `project.json`
- [ ] I2 a re-install rewrites the stamp and never resets a filled `project.json`
- [ ] I3 upgrade from a previous-layout install, **built in the test** from today's hook text with filled values (not read from git history: CI checks out at depth 1) [m6]. The filled values are `PROTECTED_BRANCHES="main|release"`, `PROTECTED_DIRS="src|shared|docs"`, `DATA_CLIENT_MODULE = "lib/api"`, `RUN_TESTS="pnpm vitest run"`, and a `\.claude` entry. The resulting `project.json` holds exactly those values, with `.claude` unescaped [M13]
- [ ] I4 an upgrade with `PROTECTED_BRANCHES="main|release/.*"` produces `["main","release/*"]` [M13]
- [ ] I5 the upgrade overwrites hooks/scripts/launchers and backs up the differing old ones
- [ ] I6 the upgrade leaves prompts, `CLAUDE.md` and rules untouched (`.new` written) [C1, M14]
- [ ] I7 an unreadable value prints a warning naming the key and keeps the default
- [ ] I8 `--supabase` writes `data_client_module: "lib/supabase"`, adds `supabase` to `protected_dirs`, and still rewrites the skill templates [M14]; `--fastapi` fills `addons.fastapi`
- [ ] I9 `.gitignore` gains `.claude/.kit-backup/`
- [ ] I10 a `project.json` at `schema_version` 0 (a fixture missing one key) gets the key added and the version bumped [M11]
- [ ] I11 (guard) `kit-doctor.py` prints `No divergence.` on a fresh install
- [ ] I12 the "P1 held back" cases (`test-install.sh:147-250`) are rewritten for the overwrite: a stripped api line is overwritten and backed up instead of being held back (`## Gate` A3) [M5]

### Step 8 — commands and docs (blocks W, Q6-Q7)
- [ ] W1 `kit/init.md` names `.claude/project.json`, `docs/work/kit-init/project.json`, `project_config.py apply` and `project_config.py mode`, and names no hook as an edit target
- [ ] W2 `CLAUDE.md`, `01-stack.md`, `02-architecture.md`, `github.md` point to `.claude/project.json`
- [ ] W3 `docs/ADAPTATION.md` §14 states the installed-project deny of kit code; §11 points icons to `project.json`
- [ ] W4 every `python3` in a hook or `install.sh` is `python3 -I` (guard)
- [ ] W5 `install.sh` `GUARD_FILES` lists `project_config.py`
- [ ] W6 `test-rules-floor.sh` total ≤ 516
- [ ] W7 `kit/doctor.md` lists `project-config`, `protected-branches`, `install-stamp`
- [ ] W8 `harness-hardening.md` follow-ups name tar/unzip/curl -o writers and the case-insensitive fs (m5, pre-existing)
- [ ] Q6 a tree with no stamp and no `install.sh`/`addons/` → `mode: installed project` plus `DIVERGENCE  install-stamp` naming `install.sh`
- [ ] Q7 a stamped tree prints `mode: installed project`

### Test-after
- Replay the 15 EcoCrew prompts of session `878efbee` with an EcoCrew-shaped `project.json`, and report the result in the handoff.

## Vigilance
- The config is a judge. Every load error fails closed through the hook's own channel. One parser serves shell and Python. Values are validated before they reach a regex or a command line.
- Paths come from the hook's own dir, never from the cwd.
- Installed = stamp OR missing kit markers. No marker, env var or path lets a feature pass write kit code.
- `test_command`, `formatter` and `linter` run as argv arrays.
- The app-root guard applies only to declared roots (A7, A8).
- Codegen reads the redirect's own segment command (D7, D8).
- Git rules:
  - path-writing calls deny; ref-moving calls ask;
  - operands are normalised;
  - any unreadable input → ask.
- Upgrades:
  - no value is lost (I3, I4, I7);
  - every change is backed up (I5);
  - additive schema (I10);
  - prompts are untouched (I6).

## Gate
Amendments to validate. Each one changes the contract or a frozen row:
- **A1 (Q2).** `/kit:init` gets no in-session exception: it writes a proposal plus a terminal command. Spec V9's "only exception" line is dropped for this pass.
- **A2 (Q3).** The stamp is the file `.claude/.kit-installed`, not a line in `hook-guarded.sh`. Installed = stamp OR missing kit markers.
- **A3 (Q4, I12).** On upgrade, kit code is overwritten (with a backup) instead of held back. The `test-install.sh` "P1 held back" cases `:147-250` are rewritten.
- **A4 (Q6).** Frozen shell rows X32.07, X32.08, X42.04, X42.05 and X28.79 go from ask to deny. X24.413 is a kit-code deny when installed. The X23 no-base row is re-measured at RED.
- **A5 (Q7).** Merge and switch bringing kit changes **ask**, against the spec's deny. `stash pop`, `apply`, `am`, `checkout --`, `restore`, `rm` and `mv` deny.
- **Open questions 1-8** of `research.md` are answered by Q1-Q9 above.

## Acceptance criteria (carried from the entry artifact)
- [ ] F7: kit code (hooks, scripts, launchers, installed addon hooks) is denied in an installed project through Write/Edit, shell and git. The installed check is the stamp OR the missing kit markers. The kit repo keeps today's behaviour. Kit prompts are unchanged (pass 2b).
- [ ] Adaptation values are read from the project config file. No hook holds a project value. `kit-doctor.py` checks the twins against the file.
- [ ] F10: app-root configs are guarded, and a `cfg` option on a declared app root passes. The project config file is guarded and denied in an installed project.
- [ ] F3b: shell redirections onto `.ts`/`.tsx`/`.py` are denied, except from a listed codegen command, which keeps its ask.
- [ ] `install.sh` upgrades an existing project (EcoCrew) with no lost value.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Plan critic
- **Pass 1** (2026-11-10, effort high): completeness 52, quality 38.
- **Verifier** (2026-11-10, effort high, against HEAD e4837f2); `attempts.json` plan-critic 1/3.
  - Survive: C1 (a contract conflict), C2, M1-M8, M11, M12, M14, M16, M18.
  - Partial: M9, M10, M13, M15.
  - Refuted: M17, M19.
  - Minors survive: m1, m2, m4, m5; partial: m3, m6, m7.
  - Outcome: the user split the spec on 2026-11-10 (pass 2b `kit-prompts.md`). This rewrite 2 tags each fix with its finding id.
- **Pass 2** (2026-11-10, effort high): completeness 68, quality 42, **not yet verified**.
  - Critical: the test setups contradict Q1/Q3. Fixtures run the kit's own hooks with a tmp `CLAUDE_PROJECT_DIR`, so a config and kit markers found from the hook's own dir always see the kit repo (`test-hooks.sh:538`).
  - Majors:
    - Install and frozen rows:
      - 9 frozen "P1 held back" blocks of `test-install.sh` beyond `:147-250` flip with the overwrite but are missing from `## Gate`, as are `test-kit-doctor.sh:44-58` and (d) `:259-269`;
      - the hold-back becomes dead code while W5 extends it;
      - the upgrade migration is specified for only 4 of the keys.
    - Values and readers:
      - `hook-lib.sh:287-294` still holds the fastapi mirror (`CWK_TDD_PY_TARGET_RE`);
      - the fastapi addon hooks cannot find the reader from `addons/fastapi/hooks/` in the kit repo;
      - fail closed is undefined for the PostToolUse/Stop hooks (`format-on-save`, `tdd-prove-red`, `eslint-batch`);
      - the `kit-doctor.py <root>` argument breaks.
    - `/kit:init`: APP_ROOTS and CODEGEN detection/proposal are not planned.
    - Git routes:
      - three-dot is wrong for switch/checkout `<branch>`;
      - apply misses unified `---`/`+++` patches and the `-C` prefix of patch paths;
      - git `rm`/`mv` miss directory and pathspec-magic operands;
      - `merge-file`, `checkout-index`, `read-tree -u` and `reset --keep|--merge` are unruled.
    - The `apply` deny is a text match only.
  - Minors:
    - V13 needs step 3; G19.11 is not RED;
    - Q3 can be partly faked by `cp -r … .`;
    - no latency budget for the per-key python spawns;
    - X23 surely flips;
    - `check_tdd_layers` twin;
    - older-schema "denies nothing new" untested.
