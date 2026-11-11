# Plan: App roots and codegen, pass 2a-1   (entry: docs/specs/app-roots-codegen.md · research: docs/work/app-roots-codegen/research.md · design: n/a)
Token profile: critical

## Skips
- DB : SKIP. No data model.
- Backend : SKIP. This is kit tooling.
- Front / UI / INTERFACE : SKIP. No app code and no screen.
- Codex routing : SKIP. This is guard code, so every step stays on Claude.
- TS test-first layers : none touched. The kit's own cycle applies instead:
  - every case is a fixture or a suite assertion;
  - each is written first, and **observed failing** on the current code;
  - then it is made green;
  - `(guard)` marks a case that is green before and must stay green.
- Reproduction case : none. This plan corrects no defect, apart from the "subdir configs unguarded" hole, which AR1 reproduces first.

## Proposed answers to research's open questions (taken at `## Gate`)
- **Q1 reader → one Python reader, `.claude/hooks/project_config.py`.**
  - Stdlib only, `# cwk-guard-api: 1`.
  - `load(project_dir)` returns `Config(app_roots, codegen_commands)` or raises `ConfigError(<english reason>)`.
    - An empty or relative `project_dir` → `Config((), ())`: no project, no file read relative to the cwd.
  - The file is `<project_dir>/.claude/project.json`:
    - read with the `kit_cwd_ok` idiom (refuse a symlink, bounded read of 64 KB);
    - **every** read or parse exception (`OSError`, `UnicodeDecodeError`, `ValueError`, `RecursionError`) maps to `ConfigError`;
    - the top level must be an object;
    - an unknown key is invalid;
    - `schema_version` must be the int `1` (type checked exactly: `true` and `1.0` are invalid).
  - **Value checks, canonical form only.**
    - An app root is one or more segments `[A-Za-z0-9._-]+` joined by single `/`. Rejected:
      - a `.` or `..` segment, an empty segment;
      - a leading or trailing `/`;
      - glob or shell characters;
      - a backslash, `\n`, `\t` or NUL.
    - Duplicates are rejected.
    - A codegen entry is a non-empty list of non-empty strings with no NUL or newline.
  - **Absent file → empty config. Invalid file → empty config in every hook**, and the reason goes to `kit-doctor.py` only (Q7).
    - `shell_targets.py` catches `ConfigError` → empty config. It never crashes, so the shell guard never shows "shell guard unavailable".
    - `roots` exits 3 with **nothing on stdout**. `cwk_app_roots` reads stdout only on exit 0.
  - Callers:
    - `shell_targets.py` imports it (same directory, explicit `sys.path` insert);
    - `hook-guarded.sh` `cwk_app_roots` runs `python3 -I -B "<hook dir>/project_config.py" roots "$CLAUDE_PROJECT_DIR"` **at most once per process**, on the first `cwk_is_guarded` call. That call happens on every Write/Edit and every shell write row, never on Read/Grep/Glob. Cost is one Python start-up (≈65 ms) per such hook run, bounded by AR23.
    - `roots` prints the validated roots **one per line**. A canonical root cannot hold a newline (PC7). `cwk_app_roots` reads them with a bash-3.2 loop, `while IFS= read -r r || [[ -n "$r" ]]; do …; done < <(python3 -I -B …)`. It never uses `mapfile` (bash 4) and never reads through `$(...)`.
  - No `jq` parse, so there is a single validator.
  - `kit-doctor.py` imports it from its own directory and calls `load(ROOT)` with ROOT from its argv. An `ImportError` → `DIVERGENCE  project-config` "project_config.py missing next to kit-doctor.py".
  - `project_config.py` joins kit-doctor's `NON_HOOKS` (`kit-doctor.py:752-757`) in step 1. Otherwise it reads as an installed-but-mute hook.
- **Q2 codegen classification → (b), in the resolver.**
  - `shell_targets.py` gives a redirect the **verb** `>cg` instead of `>` when the words of its own segment, after `strip_prefixes`, start with a listed argv prefix.
  - Targets and `kind()` are unchanged: `kind()` keys on the target's `?prefix`, not on the verb.
  - Every consumer that tests the verb for `>`/`>>` also accepts `>cg`: `prevent-destructive-commands.sh:595`, `guard_classify`, the `/tmp` and `/dev` short-cuts at `:576-579`.
  - The docstring exception list names `>cg` beside `kit_cwd_rows`.
  - The bash side never sees the command text.
  - **`>cg` behaves exactly like `>` on every target**, with one exception: a non-TDD, unguarded `.ts`/`.tsx`/`.py` under the project gets the codegen ask instead of the codegen deny.
    - TDD denies keep priority and their own text.
    - A guarded target denies (Q4).
    - `.md`, `/tmp` and `/dev` keep their verdicts.
    - `package.json` keeps the guarded ask.
  - **Ask order.** The codegen ask uses a new slot, `GUARD_ASK_CG`. It is reported **last** among the `GUARD_ASK_*` slots (after R, `:710-745`) and just before the final SRC ask (`:832`). Every riskier ask (P, O, U…) in the same command keeps its place and its reason (CG20). CG6 still shows "codegen", because nothing else asks there.
  - **The codegen deny has its own slot, `GUARD_DENY_CG`.** The first codegen row fills it. It is reported after `GUARD_DENY` and `GUARD_DENY_RAW` (`:641-642`), so a TDD deny anywhere in the same command keeps its own text, whatever the row order (CG21).
  - **The text loop** (`:405-415`) is unchanged. It runs on every command, still denies TDD targets, and still sets `SRC_WRITE_SEEN`, which keeps today's final ask for `mv`/`install`… onto `.ts` (CG15) and for a redirect onto `/tmp/*.ts` (CG13).
  - **Delete the row-side setter at `:603`.** Redirects onto sources under the project now get their deny or codegen ask from the row. Add no new `SRC_WRITE_SEEN` setter for any verb.
  - **User-facing reasons show `>`**, never the internal verb `>cg`. The plan maps the verb once, at the top of `guard_classify`, to a display variable that every text uses: `:556`, `:561`, `:580`, `:589`, `:605`, `:621` (CG18, CG22).
- **Q3 scope → `>`/`>>` (every redirect operator) only.**
  - `gen | tee src/x.ts` stays denied by the source-writer rule.
  - The deny text says "a listed generator may redirect with `>`".
- **Q4 a guarded `.ts`/`.py` target → the codegen deny wins** ("Use Write/Edit"; a Write/Edit there still asks as guarded). This amends X24.413 ask → deny.
- **Q5 pyproject → out of this pass.**
  - App-root patterns are exactly the 6 root patterns.
  - A follow-up line in `docs/specs/harness-hardening.md` covers guarding `pyproject.toml` at the root and at app roots when the fastapi addon is installed.
- **Q6 patterns → the same 6:** `vitest.config.*`, `eslint.config.*`, `vite.config.*`, `playwright.config.*`, `package.json`, `tsconfig*.json`.
- **Q7 an invalid file → silent fallback in the hooks** (no roots, no codegen: never a wider pass). `kit-doctor.py` reports `DIVERGENCE  project-config` with the reason. A hook never asks because of the config.

## Write chain (sequential)
Each step follows the same cycle:
1. Write its cases.
2. Run them and **observe the new cases fail** (paste the count into the handoff).
3. Implement.
4. Run the step's cases and every earlier suite case: they must be green, except the rows listed in `## Gate`.
5. Go to the next step.

Every suite runs at step 6.

1. **Reader + file.**
   - Create `.claude/hooks/project_config.py`.
   - Create the kit's `.claude/project.json` (`{"schema_version":1,"app_roots":[],"codegen_commands":[]}`).
   - Add `.claude/project.json` to `CWK_GUARDED`.
   - `install.sh` `GUARD_FILES` gains `project_config.py`.
   - `kit-doctor.py` `NON_HOOKS` gains `project_config.py`.
   - Cases PC1-PC10, PC12-PC15.
2. **APP_ROOTS guard.**
   - `hook-guarded.sh`: `cwk_app_roots` loads lazily, on the first call per process. Sourcing has no side effect.
   - `cwk_is_guarded` also matches `<root>/<one of the 6 patterns>` (with the folder rule for `<root>` itself) for each declared root.
   - `protect-files.sh` and the shell guard use it unchanged.
   - Test infra:
     - a new `run_app_roots_cases` in `test-hooks.sh` runs `protect-files.sh` and `prevent-destructive-commands.sh` with `CLAUDE_PROJECT_DIR=<tmp>` (the pattern of `git_hook_probe`);
     - new shell-guard setups in the `SHELL_SETUP` case (`test-hooks.sh:131-294`), each a tmp project with `project_dir=$tmp`:
       - `approots`: the tree below, `app_roots: ["frontend"]`;
       - `approots-none`: the same tree, no `project.json`;
       - `approots-bad`: the same tree, an invalid `project.json` that still names `frontend` (an extra unknown key);
       - `approots-apps`: `apps/web/…` with `app_roots: ["apps/web"]`;
       - `approots-link`: `approots` plus `fe -> frontend`;
       - `approots-two`: `approots` with `app_roots: ["frontend","other"]`;
       - `codegen`;
       - `codegen-none`: no `project.json`;
       - `codegen-bad`: invalid, listing `supabase gen types`.
     - Every new shell-guard row carries `"cwd": "__FIXTURE_ROOT__"` (or a subdir of it), because the default cwd is the kit (`test-hooks.sh:959`).
   - Cases AR1-AR12, AR23, AR25, PC11.
3. **APP_ROOTS cfg pass.**
   - `prevent-destructive-commands.sh` cfg branch (`:527`): a **dir** target whose real path equals the real path of `<project>/<declared root>` passes.
   - The pass keys on the resolved target only, never on the cwd (`package_base` trap).
   - Cases AR13-AR22, AR24, AR26.
4. **CODEGEN.**
   - `shell_targets.py` `finish`: `>cg` rows (Q2), using `project_config.load`.
   - `prevent-destructive-commands.sh` `>` branch, in this order:
     1. the existing TDD denies keep priority and text;
     2. any other `.ts`/`.tsx`/`.py` target under the project:
        - `>cg` → ask `codegen: <rel>` (it still goes through the guarded check: a guarded target denies, Q4);
        - `>` → deny "Use Write/Edit".
   - Ordering and the text loop as in Q2.
   - Cases CG1-CG22.
5. **`/kit:init`, `kit-doctor.py`, `install.sh`, docs.**
   - `kit/init.md`:
     - Phase 1 gains a detection row: a directory under the root, at most 2 levels deep (`node_modules`/`.git`/`.claude` excluded), holding its own `package.json` **and** one of the 6 config patterns, or its own `pyproject.toml` (the Python app's config). This is the spec's "manifest and a root config".
     - Phase 2 gains one closed question.
     - Phase 3 writes `.claude/project.json` (guarded ask).
     - **Codegen proposals.** A `package.json` script whose text holds `gen types`, `generate`, `codegen` or `openapi` proposes the argv prefix of the generator's command words up to its first option or redirect. Example: `supabase gen types --local > src/x.ts` → `["supabase","gen","types"]`. The user picks.
   - `kit-doctor.py`: `check_project_config` (import from its own dir, `load(ROOT)`; invalid → DIVERGENCE with the reason; a declared root missing on disk → DIVERGENCE; ImportError → DIVERGENCE), registered in `CHECKS`.
   - `test-kit-doctor.sh` scratch setup copies `project_config.py` beside `kit-doctor.py`. This is a setup insertion (`## Gate` G3).
   - `install.sh`: ships `project.json` through `copy_tree` (fresh install copies it; a re-install writes `.new`, so a filled file is never reset).
   - Docs:
     - `docs/ADAPTATION.md` gets a new section "App roots et codegen" and an update to §14 `:462-464`;
     - `kit/doctor.md` check table;
     - `README.md`;
     - the `harness-hardening.md` follow-ups:
       - Q5;
       - `eslint -c` not recognised;
       - the lexical app-root guard against a symlinked alias (`ln -s frontend fe`, then Edit `fe/vite.config.ts`). This is the same pre-existing gap as root configs;
       - case-insensitive filesystems;
       - the shell guard runs `shell_targets.py` under `python3 -B` without `-I` (`prevent-destructive-commands.sh:438`), so a `PYTHONPATH` plant reaches its imports.
   - Cases KD1-KD4, IN1-IN3, W1-W5.
6. **Refactor + gates.**
   - Every suite plus `kit-doctor.py`.
   - Replay the 3 EcoCrew `tsc -p .` prompts with an EcoCrew-shaped `project.json` (`app_roots: ["frontend","backend"]`).

## Parallel lots
None: the chain is fully sequential. Steps 2-4 share `hook-guarded.sh`, `prevent-destructive-commands.sh` and `test-hooks.sh`.

## Track isolation
- Worktree: none. Single track on the main tree, branch `audit/slim`.
- Shared foundations touched: the guard hooks, `install.sh`, `kit-doctor.py`. No other kit pass runs beside this one.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/project_config.py` | Create | reader/validator, CLI `roots`, `check` |
| `.claude/project.json` | Create | kit default, empty lists |
| `.claude/hooks/hook-guarded.sh` | Edit | `project.json` guarded, `cwk_app_roots`, app-root patterns, api 3→4 |
| `.claude/hooks/protect-files.sh` | Edit | none expected beyond the api stamp if behaviour moves through `cwk_is_guarded` only |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | cfg dir pass for declared roots, `>`/`>cg` verdicts, api bump |
| `.claude/hooks/shell_targets.py` | Edit | `>cg` rows, import of the reader, api bump |
| `.claude/hooks/kit-doctor.py` | Edit | `check_project_config` |
| `.claude/hooks/test-hooks.sh`, `fixtures/_harness/shell-guard.jsonl`, `test-kit-doctor.sh`, `test-install.sh`, `test-workflow-contracts.sh` | Edit | cases below, `approots`/`codegen` setups |
| `install.sh` | Edit | `GUARD_FILES` + `project_config.py` |
| `.claude/commands/kit/init.md`, `kit/doctor.md` | Edit | detection, question, write; check table |
| `docs/ADAPTATION.md`, `README.md`, `docs/specs/harness-hardening.md` | Edit | docs, follow-ups |

## Contracts
- `project_config.load(project_dir: str) -> Config`; raises `ConfigError`. `Config.app_roots: tuple[str, ...]`, `Config.codegen_commands: tuple[tuple[str, ...], ...]`. A missing file gives `Config((), ())`.
- CLI `python3 -I -B project_config.py roots <project_dir>`:
  - valid file → exit 0, one root per line;
  - absent → exit 0, empty;
  - invalid → exit 3, reason on stderr.
- CLI `check <project_dir>`:
  - valid or absent → exit 0;
  - invalid → exit 3 with the reason.
- Row `>cg\t<abs target>` from `shell_targets.py`.
- Verdict texts:
  - deny: `This writes a source from the shell, around every Write/Edit guardrail. Use Write/Edit; a generator listed in .claude/project.json codegen_commands may redirect with >.`
  - ask: `codegen: <rel> is written by a listed generator.`
  - The cfg pass reason is none (pass).

## Test plan (gate — validated by the user before EXECUTE)
Every case states the verdict expected **after** the change. RED means it fails on the current code.
- Setup `approots`: a tmp project with `frontend/{package.json,tsconfig.json,tsconfig.app.json,vite.config.ts,eslint.config.js,src/a.ts}`, `other/package.json`, and `.claude/project.json` with `app_roots: ["frontend"]`.
- Setup `codegen`: the same tmp project with `codegen_commands: [["supabase","gen","types"],["pnpm","supabase","gen","types"]]`.

### Step 1 — `project_config.py` (suite block PC, `test-hooks.sh`)
**Core behaviour**
- [ ] PC1 a valid file with `app_roots: ["frontend","backend"]` → `roots` prints `frontend\nbackend\n`, exit 0
- [ ] PC2 a valid file with a codegen entry → `load` returns it as a tuple of argv tuples
- [ ] PC3 no `project.json` → `roots` prints nothing, exit 0; `check` exit 0
**Business rules (never a wider pass)**
- [ ] PC4 invalid JSON → `roots` exit 3, reason names the file; `check` exit 3
- [ ] PC5 an unknown key → exit 3 naming the key
- [ ] PC6 `schema_version` 2 or missing → exit 3
- [ ] PC7 app root `../x`, `/abs`, `.`, `a/../b`, `./frontend`, `frontend/`, `front//end`, `front*`, `a\b`, or one holding a newline → exit 3 (canonical form only)
- [ ] PC8 codegen entry as a string, an empty list, or an empty word → exit 3
- [ ] PC13 duplicate app roots → exit 3
**Edge cases**
- [ ] PC9 `project.json` a symlink → exit 3 (refused, never followed)
- [ ] PC10 a file over the read bound (64 KB) → exit 3
- [ ] PC15 `[[[…]]]` nested past the recursion limit (under 64 KB), `schema_version: true`, `schema_version: 1.0`, a top-level list → exit 3; `shell_targets.py` on that file still emits rows (no crash)
- [ ] PC12 in the kit repo, an Edit of `.claude/project.json` → ask "guarded path", and `echo {} > .claude/project.json` → ask "guarded path" (RED: both pass today)
- [ ] PC14 `roots ""` and `roots relative/dir` → exit 0, empty: no file read relative to the cwd

### Step 2 — app-root guard (block AR; protect-files through `run_app_roots_cases`, shell rows through setup `approots`)
**Reproduction**
- [ ] AR1 `approots`: Edit `frontend/vite.config.ts` → ask "guarded path" (RED: pass today, the hole)
**Core behaviour**
- [ ] AR2 `approots`: Write `frontend/package.json`, Edit `frontend/tsconfig.app.json`, Edit `frontend/eslint.config.js` → ask (RED)
- [ ] AR3 `approots` shell: `echo {} > frontend/package.json` → ask "guarded path" (RED)
- [ ] AR4 `approots` shell: `sed -i s/a/b/ frontend/vite.config.ts` → the source-writer deny, as on a root `vite.config.ts` (guard)
- [ ] AR5 `approots`: Edit `frontend/src/a.ts` → pass (guard)
**Business rules**
- [ ] AR6 `approots`: Write `other/package.json` (undeclared) → pass (guard)
- [ ] AR7 `approots-none`: `cwk_is_guarded apps/web/package.json` and `frontend/vite.config.ts` → 1, not guarded (guard). Fixture `30-w5` and `test-hooks.sh:744-745` stay green: the kit's own `project.json` has empty lists (guard)
- [ ] AR8 `approots-bad`: an Edit of `frontend/vite.config.ts` passes as today, because no root is read from a bad file (guard)
- [ ] AR9 `approots`: `rm -r frontend` → ask with the reason "guarded path", because the folder holds guarded files (RED: today the ask reason is "This rm deletes recursively")
**Edge cases**
- [ ] AR10 `approots-apps`: an Edit of `apps/web/vite.config.ts` → ask (RED). An Edit of `apps/web/sub/vite.config.ts` → pass (guard: the pattern's `*` is the only part that may cross `/`, as at the root)
- [ ] AR11 `approots`: Read/Grep of `frontend/vite.config.ts` → pass (guard)
- [ ] AR12 `approots`: sourcing `hook-guarded.sh` alone runs no python. A `python3` shim on PATH that writes a marker stays unused (guard)
- [ ] AR23 `approots`: a protect-files Edit of `frontend/vite.config.ts` answers in under 2000 ms, the X14 bound (budget)
- [ ] AR25 setup `approots-two` (`app_roots: ["frontend","other"]`): an Edit of `frontend/vite.config.ts` and a Write of `other/package.json` both ask. Every root of a multi-root list is guarded, so the roots never fuse into one string (RED)
- [ ] PC11 (step 2) `approots` with `PYTHONPATH=<dir with a planted json.py>`: an Edit of `frontend/vite.config.ts` **asks**, which proves the roots were read, and the marker stays absent, which proves `cwk_app_roots` runs `-I` (RED: the ask does not exist before step 2)

### Step 3 — app-root cfg pass (shell rows X43.*, setup `approots`)
- [ ] AR13 cwd `frontend/`: `pnpm exec tsc --noEmit -p .` → pass (RED: ask `frontend (cfg)`)
- [ ] AR14 cwd root: `pnpm exec tsc --noEmit -p frontend` → pass (RED)
- [ ] AR15 cwd root: `pnpm exec tsc -p frontend/tsconfig.app.json` → pass (guarded file, declared root) (RED)
- [ ] AR16 cwd root: `pnpm vitest --root frontend` and `pnpm exec vite build --config frontend/vite.config.ts` → pass (RED)
- [ ] AR17 cwd `other/` (undeclared, own package.json): `pnpm exec tsc -p .` → ask `other (cfg)` (guard)
- [ ] AR18 cwd `frontend/src` (no package.json there): `pnpm exec tsc -p .` → pass. The pre-existing `package_base` rule (`shell_targets.py:1068-1083`) resolves the relative value against `frontend`, a declared root (RED). Cwd `other/src`: `pnpm exec tsc -p .` → ask `other (cfg)` (guard: undeclared)
- [ ] AR19 cwd root: `pnpm exec tsc -p frontend/../other` → ask (real-path compare) (guard)
- [ ] AR20 `approots-link`: `pnpm exec tsc -p fe` → pass (same real path) (RED)
- [ ] AR21 `approots-none`: `pnpm exec tsc -p frontend` → ask (guard, today's rows X24.055/059 unchanged)
- [ ] AR24 `approots-bad`: `pnpm exec tsc -p frontend` → ask `frontend (cfg)` (guard: a bad file never widens a pass)
- [ ] AR26 `approots-two`: `pnpm exec tsc -p other` → pass, with the second root of the list declared (RED: today it asks `other (cfg)`)
- [ ] AR22 (guard) every existing cfg row in shell-guard.jsonl (X24.043 … X24.254, research Blast radius) keeps its verdict with no `project.json`

### Step 4 — codegen (shell rows X43.*, setup `codegen`; amended frozen rows)
**Core behaviour**
- [ ] CG1 `echo x > src/a.ts` → deny "Use Write/Edit" (amends X32.07)
- [ ] CG2 `cat >> src/a.ts <<'EOF'` … `EOF` → deny (amends X32.08)
- [ ] CG3 `echo x >src/App.ts` → deny (amends X42.05); `echo x >src/App.t's'` → deny (amends X42.04)
- [ ] CG4 `echo 'export const a = 1' > src/b.ts` → deny (amends X28.79)
- [ ] CG5 `echo x > app/a.py` → deny (RED: pass today)
- [ ] CG6 `pnpm supabase gen types --local > src/types/database.types.ts` → ask "codegen" (RED: today ask with the TS text)
- [ ] CG7 `supabase gen types > src/types/db.ts` → ask "codegen" (RED)
**Business rules**
- [ ] CG8 `supabase gen types; echo x > src/a.ts` → deny (the redirect's own segment is `echo`)
- [ ] CG9 `echo $(supabase gen types) > src/a.ts` → deny
- [ ] CG10 `env FOO=1 supabase gen types > src/types/db.ts` → ask "codegen" (prefixes stripped) (RED)
- [ ] CG11 `supabase gen types | tee src/types/db.ts` → deny, the source-writer rule (guard)
- [ ] CG12 `echo x > addons/fastapi/hooks/tdd_py_lib.py` → deny "Use Write/Edit" (amends X24.413, guarded ask → deny, Q4); `supabase gen types > vite.config.ts` → deny (a guarded target takes no codegen ask)
**Edge cases**
- [ ] CG13 `echo x > docs/a.md`, `echo x > /tmp/a.py`, `echo x >/dev/null` → pass (guard); `echo x > /tmp/a.ts` → today's final ask "TypeScript source from the shell", from the unchanged text loop (guard); `echo x > src/a.utils.ts` → the TS_TDD deny text (guard); `echo x > app/services/x.py` → the PY_TDD deny text (guard)
- [ ] CG14 `codegen-none`: CG6 → deny, no generator listed (RED). The X23 no-base row stays pass (guard: with no project dir, nothing is classified)
- [ ] CG16 `echo x > src/App.tsx` → deny (RED)
- [ ] CG17 `>cg` onto TDD targets keeps their own deny texts (guard on the texts):
  - `supabase gen types > src/features/a/a.utils.t's'` and `supabase gen types > src/a.test.ts` → TS_TDD;
  - `supabase gen types > app/services/x.py` → PY_TDD.
- [ ] CG18 `>cg` onto non-sources, same as `>`:
  - `supabase gen types > docs/x.md` → pass (guard);
  - `supabase gen types > package.json` → the guarded ask, whose reason says `>` and never `>cg` (guard).
- [ ] CG20 `pnpm supabase gen types --local > src/types/db.ts && rm -rf node_modules/x` → ask with the reason "recursive delete/move under a protected dir: node_modules/x" (GUARD_ASK_P), not "codegen": the codegen ask never hides a riskier ask (guard)
- [ ] CG22 `codegen`: `supabase gen types > "$P/.claude/.tdd-red/x"` (an unresolved target) → the deny text shows `>`, never `>cg` (guard on the verdict, RED on the text)
- [ ] CG21 `echo x > src/b.ts; echo y > src/a.utils.t's'` → deny with the TS_TDD text, not "Use Write/Edit" (guard: the TS_TDD text shows today, and the new deny must not displace it)
- [ ] CG19 `codegen-bad`: `supabase gen types > src/types/db.ts` → deny (a bad file lists no generator), and `echo x > docs/a.md` → pass. The guard never shows "shell guard unavailable" (RED for the deny)
- [ ] CG15 `mv /tmp/x app/a.ts` → today's final ask "TypeScript source from the shell": the text loop is unchanged (guard)

### Step 5 — init, doctor, install, docs
- [ ] KD1 `test-kit-doctor.sh`: an invalid `project.json` → `DIVERGENCE  project-config` naming the reason
- [ ] KD2 a declared root missing on disk → `DIVERGENCE  project-config` naming the root
- [ ] KD3 a valid file whose roots exist → `ok          project-config`
- [ ] KD4 no `project.json` → `ok` (absent is today's behaviour)
- [ ] IN1 `test-install.sh`: a fresh install copies `.claude/project.json` equal to the kit default
- [ ] IN2 a re-install over a filled `project.json` leaves it byte-identical and writes `.claude/project.json.new`
- [ ] IN3 `GUARD_FILES` lists `project_config.py` with its api stamp; `kit-doctor.py` prints `No divergence.` on a fresh install (guard)
- [ ] W1 `test-workflow-contracts.sh`: `kit/init.md` names `.claude/project.json`, `app_roots` and `codegen_commands`, and the subdir detection step
- [ ] W2 `kit/doctor.md` lists `project-config`
- [ ] W3 `docs/ADAPTATION.md` names `.claude/project.json`; the §14 sentence on installed projects now names the app-root configs
- [ ] W4 (guard, written at step 5 over code from step 2) `test-workflow-contracts.sh`: `hook-guarded.sh` holds at least one `project_config.py` invocation, and every such invocation in a hook, `hook-guarded.sh` or `install.sh` is preceded by `python3 -I` (new needle: the existing `:738-740` check only sees `-c`/`-`)
- [ ] W5 `test-rules-floor.sh` total stays ≤ 516 (no rule line added)

### Test-after
- Replay the 3 EcoCrew `tsc -p .` prompts from `frontend/` with an EcoCrew-shaped `project.json`: all pass. Report the result in the handoff.

## Vigilance (carried from research)
- **One list, two meanings.** App-root patterns make `-p frontend/tsconfig.app.json` pass. Only declared roots get them; with nothing declared, nothing moves (AR7, AR21, AR22).
- **The dir pass compares real paths of the target** to declared roots, never the cwd (AR18-AR20).
- **Codegen reads the redirect's own segment, from rows**, never raw text (CG8, CG9). The text fallback keeps today's ask only when parsing fails.
- **Row protocol.** `>cg` is in `kind()`/`order`; no KeyError path; `MAX_ROWS` unchanged; the dedupe stays per (verb, target).
- **Resolver contract.** The docstring names the `>cg` classification exception.
- **Writer verbs stay denied** (CG11). TDD deny texts keep priority (CG13).
- **The `.py` deny is new** (CG5).
- **Never a wider pass from a bad or absent file** (PC3-PC10, AR8, CG14). Invalid → `kit-doctor` only.
- **`project.json` is guarded** (PC12). The reader refuses symlinks (PC9). `cwk_app_roots` runs it under `-I` (PC11). Through `shell_targets.py` it runs under the resolver's existing `python3 -B` (`prevent-destructive-commands.sh:438`). That gap already exists for the resolver's own imports, and is recorded as a `harness-hardening.md` follow-up.
- **Sourcing `hook-guarded.sh` stays side-effect free** (AR12). The reader runs at most once per hook run.
- **Guard api bumps and `GUARD_FILES` sync** (IN3). `project_config.py` is in kit-doctor's `NON_HOOKS`.
- **Roots are canonical**, so the lexical guard and the real-path pass name the same directory (PC7).
- **A bad file never crashes the resolver** (CG19), and `roots` prints nothing on failure.

## Acceptance criteria (carried from the entry artifact)
- [ ] F10: app-root configs are guarded; a `cfg` option on a declared app root passes; an invalid or absent file never widens a pass.
- [ ] F3b: shell redirections onto `.ts`/`.tsx`/`.py` are denied except from a listed codegen command, which keeps its ask.
- [ ] `/kit:init` detects and proposes app roots and codegen entries.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Gate amendments to validate (written into `## Gate` on the go)
- **G1, frozen shell rows ask → deny:**
  - X28.79, X32.07, X32.08, X42.04, X42.05;
  - X24.413, which goes from guarded ask to deny.

  The critic swept `shell-guard.jsonl`, `git-guard.jsonl`, the prevent-destructive and protect-files fixtures, the inline `test-hooks.sh` cases and `test-install.sh`, and found nothing else that flips.
- **G2, the shell-guard runner** gains the setups `approots*` and `codegen*` (`test-hooks.sh:131-294`), all insertions.
- **G3, the `test-kit-doctor.sh` scratch setup** copies `project_config.py` beside `kit-doctor.py`, an insertion.

## Plan critic
- **Pass 1** (2026-11-10, effort high): completeness 66, quality 52. Recorded fail 1/3.
  - The main thread verified the central claims (`kit-doctor.py:752-757`, `test-kit-doctor.sh:12-13`, `shell_targets.py:1068-1083`, `prevent-destructive-commands.sh:405-415`). All 8 Majors were accepted.
  - Fixes in this rewrite:
    - `NON_HOOKS`;
    - kit-doctor imports the reader with `load(ROOT)`, and its test copies it;
    - invalid-file hook cases AR24, CG19;
    - `>cg` onto TDD targets, CG17;
    - AR18 aligned with `package_base`;
    - canonical roots, PC7 and PC13;
    - the text loop unchanged, CG15;
    - `>cg` same as `>` on non-sources, CG18, plus the ask slot order;
    - AR9 asserts its reason;
    - PC11 tests through `PYTHONPATH`;
    - W4 gets a new needle;
    - latency AR23;
    - empty/relative `project_dir` PC14;
    - named setups;
    - `.tsx` CG16;
    - the init detection rule;
    - the codegen proposal shape;
    - the follow-ups.
- **Pass 2** (2026-11-10): completeness 86, quality 68. All 8 pass-1 fixes were confirmed closed. Recorded fail 2/3.
  - The main thread verified the 3 Majors (`prevent-destructive-commands.sh:369` SRC_WRITE_RE matches `/tmp/a.ts`; `:481` strength order).
  - Fixes:
    - roots are newline-separated, read with `mapfile`, plus a 2-root case AR25;
    - CG13 is corrected (`/tmp/a.ts` keeps today's text ask);
    - the codegen ask is reported last (CG20) and its deny takes the raw slot (CG21).
    - Minors:
      - every parse exception maps to `ConfigError` (PC15);
      - PC11 and W4 now get existence assertions;
      - reasons show `>`, never `>cg`;
      - "delete `:603`" is stated plainly;
      - fixture cwd is `__FIXTURE_ROOT__`.
- **Pass 3** (2026-11-10): completeness 90, quality 58. Recorded fail 3/3, so **BLOCKED** at the ceiling. No 4th rewrite without the user's decision.
  - The fixes from pass 2 are confirmed closed: CG13, deleting `:603`, PC15, the fixture cwd. CG21's premise is verified live.
  - Five Majors remain, all mechanical:
    1. CG20's `rm -rf node_modules` is a hard deny at `:104`, which runs before the ask order. Use `rm -rf node_modules/x` (verified to give a GUARD_ASK_P ask).
    2. The codegen deny cannot share `GUARD_DENY_RAW`, because the first row wins (`:599-601`). It needs its own slot, reported after `GUARD_DENY_RAW`.
    3. `## Contracts` still says NUL-separated. It must say one root per line.
    4. `mapfile` is bash 4, but `hook-guarded.sh` is sourced into a bash-3.2-compatible guard. Use a `while IFS= read -r` loop over a process substitution.
    5. PC11 belongs to step 2, and AR25's `tsc -p other` clause to step 3.
  - Minors:
    - `:556` leaks `>cg` into the `.tdd-red` text;
    - W4 is a guard case, not RED;
    - the claim "the reader always runs under `-I`" does not hold through `shell_targets.py`, which runs `python3 -B` (`:438`). This is pre-existing; narrow the claim and add a follow-up.
- **Ceiling lifted by the user** (2026-11-10), with no 4th critic. All 5 Majors and the Minors are fixed:
  1. CG20 uses `node_modules/x`;
  2. `GUARD_DENY_CG` is its own slot;
  3. Contracts say one root per line;
  4. roots are read with a bash-3.2 `while read` loop;
  5. PC11 moves to step 2, and AR26 (step 3) takes the `tsc -p other` clause.
  - Minors: CG22 (`:556`); W4 is a guard case; the `-I` claim is narrowed, with a follow-up.
  - Live checks on the main thread:
    - CG20's command asks "recursive delete/move under a protected dir: node_modules/x";
    - CG21's command denies with the TS_TDD text;
    - `:556` builds the `.tdd-red` text from `$verb`.
- surviving blockers: none (user override of the ceiling; `attempts.json` plan-critic stays at 3/3 as the record).

## Gate
- 2026-11-10 go (user). The plan-critic ceiling was lifted by the user, with no 4th critic.
- Contract: as written.
- Q1 → one Python reader, `project_config.py`; roots one per line, read with a bash-3.2 `while read`.
- Q2 → `>cg` emitted by the resolver.
- Q3 → `>`/`>>` only; `tee` stays denied.
- Q4 → on a guarded target, the codegen deny wins (X24.413).
- Q5 → pyproject is out, added as a follow-up.
- Q6 → the same 6 patterns.
- Q7 → an invalid file falls back silently in the hooks; `kit-doctor` reports it.
- G1 → frozen rows X28.79, X32.07, X32.08, X42.04, X42.05, X24.413 go from ask to deny (accepted).
- G2 → shell-guard setups `approots*`/`codegen*` added (accepted).
- G3 → `test-kit-doctor.sh` scratch copies `project_config.py` (accepted).
