# Spec: Kit boundary — the project config file, kit code off-limits in an installed project, app roots and codegen
Status: DRAFT — pass 2 of 4, split from `docs/specs/fewer-validations.md` on 2026-11-09 (V9, V1's `APP_ROOTS`, V3's `CODEGEN_COMMANDS`, as reviewed 2026-11-08). Depends on `fewer-asks.md` shipped. Next: `loop-to-pr.md`, `auto-mode.md`.
Token profile: critical (it moves guard values out of the hooks into a file that judges — protected branches, the RED test command — and changes what is denied in every installed project)

## Objective
A project built with the kit never changes the kit: kit code and kit prompts change in the LoopKit repo and reach a project through `install.sh`. The values a project adapts move out of the hooks into one project config file the hooks read, so no feature and no `/kit:init` run edits a hook; that file is itself a judge and is protected like kit code. With it, the configs of app subdirectories (`frontend/`, `backend/`) become guarded, `tsc -p .` from them stops asking, and shell redirections onto sources are denied except for declared codegen.

## Evidence
Shared with `docs/specs/fewer-asks.md` (*Evidence*). Owned here: `pnpm exec tsc --noEmit -p .` from `frontend/` asked "targets frontend (cfg)" 3 times over parts A and C; and the hole found while analysing it: `frontend/vite.config.ts` (the coverage floor), `frontend/eslint.config.*`, `frontend/tsconfig*.json`, `frontend/package.json` (the gate scripts) are written in EcoCrew with **no ask at all**, because `CWK_GUARDED` is anchored at the repo root (`hook-guarded.sh:20-38`).

## Scope
- IN :
  - **V9. The kit code is off-limits in an installed project, in every mode** (user, 2026-11-08). `install.sh` edits with `perl -pi` outside Claude Code, so it is unaffected.
    - **Kit code** = `.claude/hooks/*` (hooks, `hook-lib.sh`, `hook-guarded.sh`, `shell_targets.py`, fixtures, suites), `.claude/scripts/*`, `workflow.py`, `workflow.sh`, `codex-handoff.sh`, `install.sh`, and the kit's prompts: `.claude/agents/*`, `.claude/commands/*`, `.claude/skills/*`, `.claude/guides/*` (user, 2026-11-09: a feature never changes the kit outside the LoopKit repo; an agent or skill is improved in LoopKit, then reinstalled). Only exception: `/kit:init` and `/kit:recipe` write the paths they own, outside a feature pass (how the hook tells "outside a pass" is decided in the plan).
    - **Denied** in an installed project (today: an ask, or nothing for the prompts), through every tool the hooks see: Write/Edit, the shell resolver, and git commands that write kit paths (`git apply`, `git am`, `git checkout <ref> -- <kit path>`, `git restore --source`, `stash pop` / `merge` / `switch` bringing kit changes). Deny text: "kit code changes in the LoopKit repo, then `install.sh`". Creating `install.sh` or `addons/` is denied too.
    - **Installed vs kit repo** is not read from forgeable files (`kit-doctor.py:793-794` checks `install.sh` + `addons/`): `install.sh` stamps `CWK_INSTALLED=1` into `hook-guarded.sh` (kit code, so denied); present → installed. In the LoopKit repo nothing changes.
    - **Adaptation values** that live inside hooks move to the project config file: `DATA_CLIENT_MODULE`, `DATA_CLIENT_OWN_PATH`, `COMPOSITION_ROOTS`, `SHARED_DIRS` (`enforce-architecture.py:82-101`), `PROTECTED_DIRS` (`prevent-destructive-commands.sh`), `PROTECTED_BRANCHES` (`enforce-git-workflow.sh:93-94`, `github.md:28`), the test command (`tdd-prove-red.sh:35`), the formatter (`format-on-save.sh:6`), `ENV_TEMPLATE_RE` (`protect-files.sh:97`), and the new `APP_ROOTS` and `CODEGEN_COMMANDS` (below). `/kit:init`, `kit-doctor.py` twins and `CLAUDE.md`'s "change both together" lines follow.
    - **The project config file is a judge.** It holds `PROTECTED_BRANCHES`, the test command `tdd-prove-red.sh` runs, `APP_ROOTS` and `CODEGEN_COMMANDS`: one Edit could widen the `cfg` pass, fake a RED, or unprotect `main`. It is named in the plan (under `.claude/`), added to `CWK_GUARDED`, **denied** in an installed project like kit code (it changes through `/kit:init` or `install.sh`); ask in the kit repo. `install.sh` writes it on first install and migrates the values already filled in the hooks of an existing install.
  - **`APP_ROOTS`** (from V1). The project config file declares the app roots (EcoCrew: `frontend`, `backend`). **The hole first:** `hook-guarded.sh` guards `<app root>/<pattern>` for every root-level config pattern, in `protect-files.sh` and the shell guard alike. Once they are guarded, a `cfg` option (`-p`, `--dir`, `--config` on a known config name) resolving to a declared app root passes; anywhere else keeps its ask; no `APP_ROOTS` declared → today's behaviour. `/kit:init` detects and proposes them.
  - **`CODEGEN_COMMANDS`** (from V3). The project config file lists the commands that legitimately write a source through a redirection (e.g. `supabase gen types`). A redirection (`>`/`>>`, `cat >> x <<EOF`) onto a `.ts`/`.tsx`/`.py` under the project from a listed command keeps its ask; from any other command it is **denied** "use Write/Edit". `.md` redirections stay to the instruction (`fewer-asks.md` V3). `/kit:init` proposes the entries it finds in `package.json` scripts.
- OUT :
  - Push, PR, the record, V10: `docs/specs/loop-to-pr.md`.
  - Auto mode and its guarded-path split (which reuses `APP_ROOTS`): `docs/specs/auto-mode.md`.

## Open questions
- Where the project config file lives and its format (`.claude/project.conf` sourced by shell and read by Python, or JSON read by both): decide in the plan.
- How `/kit:init` and `/kit:recipe` are allowed to write kit prompts in an installed project while a feature pass cannot (a marker only those commands set, outside the agent's Write/Edit; or they print the change for the user to apply): decide in the plan.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- Hooks: `hook-guarded.sh`, `protect-files.sh`, `prevent-destructive-commands.sh`, `shell_targets.py`, `enforce-git-workflow.sh`, `enforce-architecture.py`, `tdd-prove-red.sh`, `format-on-save.sh`, `addons/fastapi/hooks/*`, `kit-doctor.py`, their fixtures, `test-hooks.sh`, `test-install.sh`.
- `install.sh` (the `CWK_INSTALLED` stamp, the project config file, migration of existing values).
- Commands: `.claude/commands/kit/{init,doctor,recipe}.md`.
- Rules and docs: `CLAUDE.md` and `01-stack.md` / `02-architecture.md` ("change both together" lines point to the config file), `docs/ADAPTATION.md`, `README.md`.

## Business logic to cover
- F3b a redirect onto `src/types/database.types.ts` from a `CODEGEN_COMMANDS` entry: ask; from an unlisted command (`echo x > src/a.ts`): deny.
- F7 installed project: write / `git apply` / `git checkout -- ` on `.claude/hooks/x` and on `.claude/commands/loop/ship.md`: deny; creating `install.sh`: deny; the same in the kit repo: ask (hooks) / pass (prompts).
- F10 with `APP_ROOTS = frontend` (which has its own `package.json`): Edit of `frontend/vite.config.ts`, `frontend/package.json`: ask (today: no prompt); `pnpm exec tsc --noEmit -p .` with cwd `frontend/`, and `-p frontend` from the root: pass; cwd an undeclared directory with its own `package.json`: ask; no `APP_ROOTS`: today's ask. The project config file: Write/Edit/shell write deny in an installed project, ask in the kit repo.
- Each adaptation value: the hook reads it from the config file; a missing file fails closed with a message naming `/kit:init`.
- `test-install.sh`: a fresh install writes the stamp and the config file; an upgrade migrates filled values without loss.

## Acceptance criteria
- [ ] F7: kit code and kit prompts are denied in an installed project through Write/Edit, shell and git; the installed check reads the `CWK_INSTALLED` stamp; the kit repo keeps today's behaviour.
- [ ] Adaptation values are read from the project config file; no hook holds a project value; `kit-doctor.py` checks the twins against the file.
- [ ] F10: app-root configs are guarded; a `cfg` option on a declared app root passes; the project config file is guarded and denied in an installed project.
- [ ] F3b: shell redirections onto `.ts`/`.tsx`/`.py` are denied except from a listed codegen command, which keeps its ask.
- [ ] `install.sh` upgrades an existing project (EcoCrew) with no lost value.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
On the next EcoCrew feature: no `tsc -p .` ask from `frontend/`; any Edit of `frontend/vite.config.ts` or `package.json` now asks; no agent edit of the kit succeeded.

## Next work
At `/loop:ship`, once the commit is done, propose this to the user as the next step (do not start it without their go):
1. **Update EcoCrew with `install.sh`** and check `/kit:doctor` there (config file filled, stamp present).
2. **Then `docs/specs/loop-to-pr.md`** (pass 3 of 4): the loop goes to the PR without asking, the hook-written record, and V10 (tests validated in one read). Before scheduling it, settle its open question with the user: lift the grants parking for `.tdd-unfrozen` only.
