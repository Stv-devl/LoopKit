# Spec: App roots and codegen — guard app-subdirectory configs, let `tsc -p .` pass there, deny shell writes onto sources
Status: DRAFT — pass 2a-1, split from `docs/specs/kit-boundary.md` on 2026-11-10 (user, after kit-boundary plan-critic pass 2: each pass found one more layer, so 2a became three passes). Carries V1's `APP_ROOTS` and V3's `CODEGEN_COMMANDS` as reviewed 2026-11-08. Depends on `fewer-asks.md` shipped. Next: `project-config.md` (2a-2), `kit-boundary.md` (2a-3), `kit-prompts.md` (2b).
Token profile: critical (it widens a `cfg` pass and adds a deny on every shell redirection onto a source)

## Objective
The configs of app subdirectories (`frontend/`, `backend/`) get the same guard as the root configs. `tsc -p .` run from a declared app root stops asking. A shell redirection onto a `.ts`/`.tsx`/`.py` source is denied unless a declared code generator writes it. Both lists live in a new project config file, `.claude/project.json`, which this pass creates with these two keys only. Later passes add the other keys.

## Evidence
- `pnpm exec tsc --noEmit -p .` from `frontend/` asked "targets frontend (cfg)" 3 times over parts A and C of the first EcoCrew feature.
- While analysing it, a hole showed up. In EcoCrew, `frontend/vite.config.ts` (the coverage floor), `frontend/eslint.config.*`, `frontend/tsconfig*.json` and `frontend/package.json` (the gate scripts) are written with **no ask at all**, because `CWK_GUARDED` is anchored at the repo root (`hook-guarded.sh:20-38`).
- Today the shell guard **asks** on a redirection onto a TypeScript source (rows X32.07, X32.08, X42.04, X42.05, X28.79), and lets one onto a `.py` pass.

## Scope
- IN :
  - **The config file.** `.claude/project.json` is JSON with `schema_version: 1`, `app_roots: []` and `codegen_commands: []`.
    - Hooks find it from `CLAUDE_PROJECT_DIR`, the same base every guard uses today.
    - One reader validates it, used by the shell and Python hooks alike. It is never `source`d or `eval`ed.
    - An app root is a relative path with no `..`. A codegen entry is an argv prefix of non-empty strings.
    - The file joins `CWK_GUARDED`: a Write, Edit or shell write asks. The deny in an installed project comes with `kit-boundary.md`.
    - **Absent file** = no app roots and no codegen, which is today's behaviour, plus the new codegen deny.
    - **Invalid file** = the same as absent, and the reason is reported by `kit-doctor.py`. It never widens a pass.
  - **APP_ROOTS.**
    - **The hole first.** `hook-guarded.sh` guards `<app root>/<root config pattern>` (`vitest.config.*`, `eslint.config.*`, `vite.config.*`, `playwright.config.*`, `package.json`, `tsconfig*.json`) for each declared root. `protect-files.sh` and the shell guard both apply it.
    - **Then the pass.** A `cfg` option (`-p`, `--dir`, `--config` on a known config name) that resolves to a declared app root passes. Anywhere else keeps its ask. No root declared → today's behaviour.
  - **CODEGEN_COMMANDS.**
    - A redirection (`>`, `>>`, `cat >> x <<EOF`) onto a `.ts`/`.tsx`/`.py` under the project is **denied** with "use Write/Edit".
    - The exception is a redirection whose own segment command starts with a listed argv prefix (after `env`/`command` prefixes are stripped): it asks "codegen".
    - `.md` and other extensions are unchanged.
  - **`/kit:init`.**
    - Detects app roots: a subdirectory with its own `package.json` or `pyproject.toml` and a root config.
    - Proposes codegen entries from the `package.json` scripts (`gen`, `generate`, `supabase gen types`, `openapi`…).
    - Writes the file, with the guarded ask.
  - **`kit-doctor.py`.** Reports an invalid `project.json` (`DIVERGENCE  project-config`), and a declared app root that does not exist.
  - **`install.sh`.** Copies the default `project.json` on a fresh install. Never overwrites an existing one.
- OUT :
  - Moving the hook values (branches, protected dirs, test command…) into the file, the migration and the schema upgrade: `project-config.md`.
  - The installed check and the kit-code deny: `kit-boundary.md`.
  - Kit prompts: `kit-prompts.md`.

## Open questions
- Whether a `pyproject.toml` root also guards `pyproject.toml`, `ruff.toml` and `mypy.ini` (the fastapi addon's gate configs): decide in the plan.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- `.claude/project.json` (new) and its reader (new, under `.claude/hooks/`);
- `hook-guarded.sh`, `protect-files.sh`, `prevent-destructive-commands.sh`, `shell_targets.py`;
- `kit-doctor.py`, `install.sh`;
- `.claude/commands/kit/{init,doctor}.md`;
- fixtures, `test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`;
- `docs/ADAPTATION.md`, `README.md`.

## Business logic to cover
- F10 with `app_roots: ["frontend"]`:
  - Edit of `frontend/vite.config.ts` or `frontend/package.json`: ask (today: no prompt).
  - `pnpm exec tsc --noEmit -p .` with cwd `frontend/`, and `-p frontend` from the root: pass.
  - cwd an undeclared directory with its own `package.json`: ask.
  - No `app_roots`: today's ask.
  - An invalid `project.json`: today's ask (no widened pass).
- F3b:
  - A redirect onto `src/types/database.types.ts` from a listed command: ask.
  - From an unlisted command (`echo x > src/a.ts`, `echo x > app/a.py`): deny.
  - The redirect's own segment decides: `gen; echo x > src/a.ts` and `echo $(gen) > src/a.ts` deny.
- `project.json`: a Write, Edit or shell write asks; a `..` app root or a string codegen entry is invalid.
- `/kit:init` on an EcoCrew-shaped tree proposes `frontend` and `backend`, and `supabase gen types` if it is in the scripts.

## Acceptance criteria
- [ ] F10: app-root configs are guarded; a `cfg` option on a declared app root passes; an invalid or absent file never widens a pass.
- [ ] F3b: shell redirections onto `.ts`/`.tsx`/`.py` are denied except from a listed codegen command, which keeps its ask.
- [ ] `/kit:init` detects and proposes app roots and codegen entries.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
On the next EcoCrew feature: no `tsc -p .` ask from `frontend/`; any Edit of `frontend/vite.config.ts` or `frontend/package.json` asks; no shell write onto a source succeeded.

## Next work
At `/loop:ship`, once the commit is done, propose this to the user as the next step (do not start it without their go): update EcoCrew with `install.sh` and run `/kit:init` there for `app_roots`, then `docs/specs/project-config.md` (2a-2).
