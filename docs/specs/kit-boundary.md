# Spec: Kit boundary — kit code off-limits in an installed project
Status: DRAFT. This is pass 2a-3.
- **Origin.** Split from `docs/specs/fewer-validations.md` on 2026-11-09 (V9, as reviewed 2026-11-08).
- **Narrowed twice on 2026-11-10 (user).**
  - The kit prompts moved to `kit-prompts.md` (2b), because about 20 of them still carry per-project FILL adaptations (verifier C1).
  - After plan-critic pass 2, `APP_ROOTS`/`CODEGEN_COMMANDS` moved to `app-roots-codegen.md` (2a-1), and the move of the values to `project-config.md` (2a-2).
- **Depends on** 2a-1 and 2a-2 being shipped: by then no hook holds a project value, so a hook can be denied without blocking an adaptation.
- **Next:** `kit-prompts.md`, then `loop-to-pr.md`, then `auto-mode.md`.
- **The earlier plan** (`docs/work/kit-boundary/plan.md`, plan-critic 2/3, both passes recorded there) is superseded. Its findings on git routes and the installed check carry over to this pass's plan.

Token profile: critical (it changes what is denied in every installed project)

## Objective
A project built with the kit never changes the kit's code. Hooks, scripts and launchers change in the LoopKit repo and reach a project through `install.sh`. In an installed project, every tool the hooks see is denied a write to kit code and to `.claude/project.json`. Those files change only through `install.sh`, or through a `/kit:init` proposal that the user applies in their own terminal.

## Evidence
Shared with `docs/specs/fewer-asks.md` (*Evidence*). Plan-critic passes 1 and 2 of 2026-11-10 (`docs/work/kit-boundary/plan.md` `## Plan critic`) list which routes write kit code today.

## Scope
- IN :
  - **V9. Kit code is off-limits in an installed project, in every mode** (user, 2026-11-08). `install.sh` edits with `perl -pi` outside Claude Code, so it is unaffected.
    - **What counts as kit code:**
      - `.claude/hooks/*` (hooks, `hook-lib.sh`, `hook-guarded.sh`, `shell_targets.py`, fixtures, suites);
      - `.claude/scripts/*`;
      - `addons/*/hooks/*` once installed;
      - `workflow.py`, `workflow.sh`, `codex-handoff.sh`, `install.sh`;
      - `.claude/project.json` and the stamp.
      - The prompts count as kit code too (user, 2026-11-09), but they wait for `kit-prompts.md`.
    - **What is denied** in an installed project (today: an ask). A write to kit code is denied through Write/Edit, through the shell resolver (symlinks followed, `ln -s` included), and through every git command that writes the work tree or the index at a kit path:
      - `apply` and `am`: unified and git patches, with paths prefixed by `-C`/cwd; unreadable or ambiguous input asks;
      - `checkout [<ref>] -- <path>` and `restore`;
      - `rm` and `mv`, including directory operands and pathspec magic;
      - `stash pop|apply`, untracked part included;
      - `merge-file`, `checkout-index`, `read-tree -u`, `reset --keep|--merge`;
      - for any other git subcommand that writes the work tree, the plan proves that it is covered.

      Deny text: "kit code changes in the LoopKit repo, then `install.sh`". Creating `install.sh` or `addons/` is denied too, including a copy into `.`.
    - **Calls that bring kit changes ask:** `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `reset --hard`, `switch`/`checkout <branch>`.
      - Each one reads the change it brings. A switch compares the whole tree; a merge compares since the merge base.
      - This amends the 2026-11-08 deny for merge and switch: a deny would block merging `main` after a kit upgrade. The user confirms it at the plan gate.
    - **Installed vs kit repo.** `install.sh` writes the stamp on every run.
      - **Installed** = the stamp is present, **OR** `install.sh` and `addons/` are not both present (verifier C2). A dropped stamp never downgrades the deny.
      - The check must be testable: a fixture points the hooks at a tmp project, with the same base as `project-config.md`.
      - In the LoopKit repo nothing changes.
  - **`/kit:init` in an installed project** writes a proposal outside kit code. It prints one command for the user to run in their own terminal, and that command applies the proposal. The agent is denied running that command, however the command is spelled (the resolved script path, not the text).
  - **`install.sh` upgrade.** Kit code is overwritten from the kit, after a backup of the files that differ. Prompts, rules, `CLAUDE.md` and settings keep their `.new` / merge path. The "P1 held back" logic that the overwrite makes dead is removed, together with **every** test row that depends on it. Those rows are listed at the gate.
- OUT :
  - App roots and codegen: `app-roots-codegen.md`. Values and migration: `project-config.md`.
  - Kit prompts: `kit-prompts.md`.
  - Push, PR, the record, V10: `loop-to-pr.md`. Auto mode: `auto-mode.md`.

## Open questions
- The stamp's form (a file under `.claude/`, written every run): confirm in the plan. A line in `hook-guarded.sh` is lost on re-install.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- `hook-guarded.sh`, `protect-files.sh`, `prevent-destructive-commands.sh`, `shell_targets.py`, `enforce-git-workflow.sh`;
- `install.sh`, `kit-doctor.py`;
- `.claude/commands/kit/{init,doctor}.md`, `docs/ADAPTATION.md`, `README.md`;
- the suites and fixtures.

## Business logic to cover
- F7 in an installed project: each of the following on `.claude/hooks/x` is denied: a Write, a shell write, a symlink alias, `git apply` (git and unified patches), `checkout --`, `rm -r .claude/hooks`, `mv`, `stash pop -u`, `merge-file`.
- Creating `install.sh`, or copying it into `.`, is denied.
- With the stamp dropped and no `install.sh` + `addons/`, every write is still denied.
- The same calls in the kit repo ask.
- `switch` to a branch cut before a kit upgrade asks.
- Running `/kit:init`'s apply command from a tool call is denied, whatever the spelling.
- An upgrade overwrites kit code, backs it up, and leaves prompts and rules on `.new`.

## Acceptance criteria
- [ ] F7: kit code is denied in an installed project through Write/Edit, shell and git. The installed check is the stamp OR the missing kit markers, and it is tested through a fixture project. The kit repo keeps today's behaviour.
- [ ] `install.sh` overwrites kit code with a backup. No dead hold-back path is left.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
On the next EcoCrew feature, no agent edit of kit code succeeded.

## Next work
At `/loop:ship`, once the commit is done, propose this to the user as the next step (do not start it without their go):
1. Update EcoCrew with `install.sh`, and check `/kit:doctor` there (stamp present).
2. Then `docs/specs/kit-prompts.md` (2b).
