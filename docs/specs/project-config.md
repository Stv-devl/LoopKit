# Spec: Project config — move every project value out of the hooks into `.claude/project.json`
Status: DRAFT — pass 2a-2, split from `docs/specs/kit-boundary.md` on 2026-11-10 (user). Depends on `app-roots-codegen.md` shipped, which creates the file and its reader. Next: `kit-boundary.md` (2a-3).
Token profile: critical (the file becomes a judge: protected branches, the RED test command)

## Objective
No hook holds a project value. Every value a project adapts lives in `.claude/project.json`, and the hooks read it from there. After this pass, `/kit:init` and the addons write only that file, never a hook, so the next pass can deny the hooks in an installed project.

## Evidence
- `/kit:init` and `docs/ADAPTATION.md` edit hook text today.
- `install.sh` `wire_supabase` / `wire_fastapi` do the same with `perl -pi`.
- `kit-doctor.py` compares twins against that text.
- The kit-boundary critics (2026-11-10, `docs/work/kit-boundary/plan.md` `## Plan critic`) listed the values and their copies. They also listed what moving them breaks: fail-closed channels, the migration, fixtures that run the kit's hooks against a tmp project, and the addon hooks' own directory.

## Scope
- IN :
  - **Values.**
    - Data client: `DATA_CLIENT_MODULE`, `DATA_CLIENT_OWN_PATH`, `COMPOSITION_ROOTS`, `SHARED_DIRS`.
    - Guards: `PROTECTED_DIRS`, `PROTECTED_BRANCHES`.
    - Commands: the test command, the formatter, the linter (`eslint-batch.sh`).
    - The env template suffixes, every copy:
      - `protect-files.sh`, `prevent-destructive-commands.sh`, `shell_targets.py`;
      - `auto-approve-config.sh` (both lines);
      - `enforce-git-workflow.sh` `SECRET_KEEP`.
    - The forbidden icon list.
    - `CWK_TDD_LAYERS`.
    - The fastapi CONFIGURE values (`enforce-backend-layers.py`, `tdd_py_lib.py`, and the `CWK_TDD_PY_TARGET_RE` mirror in `hook-lib.sh`).
  - **The reader finds the file from `CLAUDE_PROJECT_DIR`**, as `app-roots-codegen.md` does. That way a fixture can point a kit hook at a tmp project. The addon hooks find the reader through the project, not through their own directory.
  - **Fail closed, per event.** A missing or invalid file never makes a hook pass what it would block with a valid file.
    - PreToolUse hooks ask (deny once `kit-boundary.md` makes the project installed) through their own JSON channel.
    - PostToolUse hooks (`format-on-save`, `tdd-prove-red`) report the reason and do nothing they would not do anyway. `tdd-prove-red` writes no RED marker.
    - The Stop hook (`eslint-batch`) stays non-blocking and reports the reason.
    - The message names `install.sh` and `/kit:init`.
  - **Schema version.** A kit upgrade adds new keys with their defaults. A file at an older version stays valid and denies nothing it did not deny before.
  - **Migration.** `install.sh` on an existing install reads **every** moved value from the active hooks, using the anchored regexes `kit-doctor.py` already uses (with their `\.` unescape). A regex branch (`release/.*`) becomes a glob (`release/*`). An unreadable value keeps the default, with a warning naming the key. If the env-suffix copies disagree, the protect-files copy wins and the others are reported.
  - **Twins.** `kit-doctor.py` checks every twin against the file, `CWK_TDD_LAYERS` and the test command included. The `kit-doctor.py <project root>` argument reads that root's file.
  - **Writers.** `/kit:init`, `wire_supabase` and `wire_fastapi` write the file, not the hooks.
- OUT :
  - The deny on kit code and the installed check: `kit-boundary.md`.
  - Kit prompts: `kit-prompts.md`.

## Open questions
- Python hooks read JSON natively. Should shell hooks call the reader once per run (one start-up for all keys) or per key? Set a latency budget for the hooks that run on every Read/Grep. Decide in the plan.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- every hook that holds a value, the fastapi addon hooks, `hook-lib.sh`;
- `kit-doctor.py`, `install.sh`;
- `.claude/commands/kit/{init,doctor}.md`;
- `CLAUDE.md`, `01-stack.md`, `02-architecture.md`, `00-project.md`, `github.md`;
- `docs/ADAPTATION.md`, `README.md`, the supabase addon docs;
- the suites and fixtures.

## Business logic to cover
- Each value: changing it in `project.json` changes the hook's verdict. For example, `release/*` protected → a commit on `release/1` is denied.
- A missing or invalid file: each hook behaves as described in *Fail closed, per event*.
- An upgrade from a hook-filled install yields a `project.json` holding every filled value, regex branches included.
- An older-schema file gets the new keys and no new deny.
- No hook file holds a project value (a contract grep over every old constant and copy).

## Acceptance criteria
- [ ] No hook holds a project value; every reader fails closed as specified for its event.
- [ ] `install.sh` upgrades EcoCrew with no lost value.
- [ ] `kit-doctor.py` checks every twin against the file, for this checkout or a given root.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `test-kit-doctor.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
`install.sh` on EcoCrew: `project.json` holds its values and `/kit:doctor` is clean.

## Next work
At `/loop:ship`, once the commit is done, propose to the user (do not start it without their go): `docs/specs/kit-boundary.md` (2a-3).
