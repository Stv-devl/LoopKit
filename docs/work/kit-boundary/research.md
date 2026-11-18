# Research: Kit boundary, pass 2a-3   (entry: docs/specs/kit-boundary.md)
Token profile: critical

Written 2026-11-16 from three explorers (hooks and shell, git routes, install/doctor/init), reconciled on the main thread. Key claims were re-read on the main thread and are marked [verified]. Prior critic findings: `prior-critic.md`. HEAD is 364f906.

## Pattern to follow
- **Guarded-path classification.** One hard-coded list, `CWK_GUARDED` (`.claude/hooks/hook-guarded.sh:20-41`) [verified]. It is matched as a glob where `*` crosses `/`. A folder above a pattern is guarded too, and `.` is always guarded (`cwk_is_guarded`, `:206-214`) [verified].
  - A separate list, `CWK_GUARD_DENIED` (`:47`: `.claude/.tdd-red/*`, `.git/*`), already denies with "BLOCKED: $REL is never written by hand" (protect-files.sh, around `:213`).
  - That deny tier is the analogue for an installed-only kit-code tier.
- **Installed detection.** `kit-doctor.py:878-879` defines `is_kit_source()` as `install.sh` a file and `addons/` a dir under ROOT [verified]. It is the same heuristic the spec names. Nothing equivalent exists in any hook.
- **Path checks on a git route.** `checkout_rule` (`enforce-git-workflow.sh:798-852`) already denies a TDD or frozen-test operand (`:817-822`). It receives the per-call `directory` (the `-C` target). It is the model for a kit-path check on the other git writers.

## Wiring points
- **Write/Edit.** `protect-files.sh`.
  - Guarded asks at `:266-267`: "guarded path: $REL (kit guardrail; approve only if you meant to change it)".
  - The `.tdd-unfrozen` removal-only pass is at `:258-260`.
  - Symlinks are followed through `cwk_real_file` (`hook-guarded.sh:314`, last component, 40 hops). Each probe is at `protect-files.sh:128-138`.
- **Shell.**
  - `prevent-destructive-commands.sh` runs `shell_targets.py` at `:505`, then `guard_classify` per row (`:652-790`). The guarded ask is at `:771-786`. The final ask text is at `:889-892`, with a second hard-coded copy of the launcher names at `:889`.
  - `shell_targets.py` `target()` (`:2303-2341`) resolves lexically. It follows links only for `/tmp` paths outside the project (`link_side`, `tmp_physical`) [verified].
  - `cp`/`mv` are LAST_OPERAND verbs (`shell_targets.py:128`), so `cp x .` yields target `.`. `ln -s x install.sh` yields `install.sh` (writer_rows `:1670-1690`).
- **Git.**
  - The real parser is the python heredoc `parse_segments` (`enforce-git-workflow.sh:199`, run at `:1348`). `parse_git` is at `:1082`; it reads the `-C`/`--git-dir`/`--work-tree` globals at `:1103-1123`, and an unreadable `-C` sets `dir_unread`. `walk` is at `:1174` and tracks `cd`/prior commands at `:1191`.
  - The dispatch table is `DESTRUCTIVE_RULES` (`:1059-1063`) [verified]: clean, reset, stash, branch, update-ref, checkout, restore, worktree, config, init, and the network set.
  - The grammar fallback `grammar_triggered` (`:1649`) fires on the words add/stage/commit/switch.
  - The bash floor is `floor_subs` (`:1512`).
- **Project root.**
  - Shell hooks use `CLAUDE_PROJECT_DIR` (`hook-guarded.sh:151,352`, `prevent-destructive-commands.sh:556`) and `.cwd` for the relative base. They find their libs and `project_config.py` from their own dir (`hook-guarded.sh:68,151`).
  - The git hook uses `.cwd`, then `CLAUDE_PROJECT_DIR`, then `$PWD` (`enforce-git-workflow.sh:91-94`). `project_repo` is at `:484-490`.
- **install.sh.**
  - `copy_tree` (`:201-211`) handles every `.claude/` file through `copy_file` (`:87-97`). `copy_file` writes `dst.new` whenever the dst exists, with no compare [verified].
  - `copy_override` is at `:102-111`.
  - Top-level files go through `copy_file` (`:751-760`): CLAUDE.md, AGENTS.md, codex-handoff.sh, workflow.py, workflow.sh, Claude_Workflows.md, ADAPTATION.md.
  - FastAPI addon hooks go through `copy_file` (`:830-835`).
  - Order: `copy_tree` `:743`, then `migrate_config` `:744`, then `install_settings` `:745` [verified].
  - `install.sh` and `addons/` are never copied into a project.
  - Backup logic: none.
- **Stamp candidates.**
  - `.claude/INSTALL_PROFILE` is written every run (`install.sh:746-750`: `react-ts`|`core`) [verified]. It is not tracked in the kit repo (`git ls-files` empty) [verified]. It is read by `kit-doctor.py:912`.
  - `.claude/VERSION` is kit-tracked and copied, so it is not a stamp: it exists in the kit repo too.
- **kit-doctor.py.** ROOT comes from `sys.argv[1]` (`:40`), default `parents[2]`. The reader is imported from the script's own dir (`:97-99`). The mode message is at `:1413-1418`. The CHECKS list is at `:1382-1395`.
- **`/kit:init`.** `.claude/commands/kit/init.md`.
  - Today it writes no kit code: `:84-87` says no hook is edited.
  - Step 14 (`:108-113`) edits `.claude/project.json` in one Edit, "a guarded file: the write asks". That is the write that becomes a proposal.
  - The final report is at `:124-146`.

## Reusable
- `cwk_is_guarded`, `cwk_is_guard_denied`, `cwk_real_file`, `cwk_real_rel` (`:349`) and `cwk_guard_rel` (`:367`), all in `hook-guarded.sh`.
- `checkout_rule` operand classification and its `directory` handling.
- `kit-gate-route.py:151-171` `fix_hunks`, which parses `diff --git`/`---`/`+++` headers. It does not handle `-p<n>` or `--directory`.
- `kit-gate-route.py:425`: `git diff --name-only base current`.
- `kit-pr-assets.py:191` (`merge-base --is-ancestor`), `:227` (`ls-tree --name-only`).
- `is_kit_source()` (kit-doctor.py) is the heuristic to share; do not write a second spelling.
- test-hooks.sh:
  - `run_case` (`:114`, `project_dir` defaults to the kit `:131`);
  - `seed_project` (`:1444-1451`, copies project.json, and `project_config.py` with `--reader`);
  - the fixture sweep (`:576`, decision from the `-pass|deny|ask|allow` suffix);
  - the git JSONL harness `fixtures/_harness/git-guard.jsonl`, run by `run_git_guard_cases` (`:994-1037`).

## Blast radius
- **Hard-coded duplicates of the kit list.** `hook-guarded.sh:20-41`, `prevent-destructive-commands.sh:889`, `install.sh:264` (`GUARD_FILES`, 14 names) and `test-workflow-contracts.sh:440`.
- **Fixture flips.** Existing protect-files fixtures 06, 07, 19, 20, 38-42 and PDC 18 ask on a kit path. They all use `__PROJECT_ROOT__` (the kit repo), so they stay ask under "kit repo unchanged".
  - The installed-project denies need new fixtures with a tmp project.
  - The installed flips are new cases, not edits of frozen ones.
  - Fixtures 08, 09 and 25 (settings), 10 (`.tdd-unfrozen`), 11 (`.size-exempt`) and 43 (`project.snapshot.json`) are outside the spec list.
- **Git cases at risk.**
  - Asks on uncommitted state: G16.004, G16.055-056, G16.060-062, G16.124-125, G16.129-131.
  - Passes that must not flip outside kit paths: G16.071, G16.072, G16.077 (`checkout main`), G2.07, G8.05, G14.13.
  - Not one fixture today covers `apply`, `am`, `rm`, `mv`, `stash pop`, `merge`, `reset --keep`, `cherry-pick`, `revert`, `read-tree`, `checkout-index` or `merge-file`.
- **test-install.sh rows that depend on the hold-back or on hooks written as `.new`:**
  - I2 block `:129-342`: (a) `:152-178`, A0, A2, A3, A4, A8, A9, A7 at `:180-255`, (c) `:257-262`, (d) `:264-275`, which survives, (e) `:277-286`, which flips, DA1 `:288-313`, (f) `:315-322`, (g) `:324-332`, (h) `:334-341`;
  - I3 `:343-395`;
  - HP-B2 `:446-486`;
  - A9 kit-attempts `:523-527`;
  - IN16 `:725-742`, IN18 `:750-779`, IN19 `:781-792`, IN24 `:846-855`;
  - IN23 `:827-845`, to re-check: it runs `reader_stale`;
  - IN26 `:869-881`.
  - test-kit-doctor.sh `:44-58` does not depend on it, and `:259-269` does not exist (the file ends at `:257`). That corrects the prior critic.
- **install.sh code that goes dead once kit code is overwritten.**
  - `guard_api_missing` `:307-331`, `GUARD_FILES` `:264-267`, `ADDON_GUARD_FILES` `:271-272`, `guard_api_number` `:298-301`;
  - the held branch `:374-388` and the `$held` clauses `:397-414`;
  - `reader_stale` `:220-234` and its calls at `:250`, `:500`, `:543`;
  - the `.new` branch for kit files.
  - `P1_ALLOWS`/`PROMPT_ALLOWS`/`RETIRED_ALLOWS` (`:273-294`) stay alive only if P1 becomes unconditional.
- **test-workflow-contracts.sh pins.**
  - `:495` P1_ALLOWS, `:714-727` held-back list `== 26`, `:765`/`:983` GUARD_FILES, `:984` and `:1005-1010` `cwk-guard-api` stamps, `:972-977`, `:870-877`.
  - ADAPTATION needles: `:439-442` §14, `:487-488` `P1 held back`, `:495-509` `merge <fichiers>.new, then re-run install.sh`, `:516` §15.
  - init.md needles: `:854-860`, `:987-991`.
- **Docs to rewrite.**
  - ADAPTATION §15 `:507-611`: hold-back `:564-572`, message `:582-588`, reader-stale `:590-602`; §2 `:24-28`.
  - README `:39-58`: the `.new` rule and "Updating".
  - install.sh header `:25-27`: "Ne remplace jamais".
- **Rules floor.** `test-rules-floor.sh` is at 516/520. 00, 06 and 11 are exactly at budget, so any rule line this pass adds must be paid for.
- **No per-project FILL in kit code.** `grep FILL` in hooks, scripts and launchers finds only kit-doctor's own strings. An overwrite erases no adaptation.

## Live DB state
n/a, kit tooling.

## External surface
n/a. Git's own behaviour (`apply` reading stdin, `-p<n>`/`--directory`, `stash -u`) is checked in the plan with local `git` runs, not fetched.

## Traps (points of vigilance for the review)
- **The tmp-fixture trap.** Every tmp fixture project has no `install.sh`/`addons/`, so it counts as installed. Any new deny must scope to kit paths only, and the kit-repo control cases must run against `__PROJECT_ROOT__`.
- **Where the installed check looks.** It must read `CLAUDE_PROJECT_DIR`, never the hook's own dir. Fixtures run the kit's hooks against a tmp project (prior Critical).
- **`.` is always guarded.** A deny keyed on `cwk_is_guarded` would deny every `cp x .`. "Copy install.sh into `.`" must key on the destination basename.
- **Shell symlinks.** The shell side does not follow in-project symlinks, so `ln -s install.sh a; echo >> a` passes today (found by reading). Write/Edit does follow them. The spec requires both.
- **Clean files on git checkout/restore.** `checkout_rule` passes a clean file, so `git checkout -- .claude/hooks/x` on a clean tree overwrites silently today.
- **Git route coverage today.**
  - `checkout <branch>` passes, while `switch <branch>` asks only through the grammar word.
  - `merge`/`rebase` ask only on a protected branch.
  - `pull`, `cherry-pick` and `revert` pass.
- **`git apply` input.** Patch paths depend on `-p<n>`, `--directory` and the `-C` cwd, and the input may be stdin. Unreadable input asks.
- **Path resolution under `-C`.** A git pathspec resolves against the per-call `-C` directory, not `BASE_DIR`. `cd X && git …` is not followed; it already asks.
- **Two parsers.** The bash `floor_subs` and the python `parse_git` must agree on any new subcommand.
- **Re-install never rewrites itself.** `install.sh` is not in the project, so the overwrite must not try to copy it, and must not trip over the deny when it runs under Claude Code. It runs outside, by the spec.
- **`.new` on identical files.** `copy_file` writes `.new` for byte-identical files today, so the README claim "changed ones as .new" is false today.
- **Stale doc counts.** ADAPTATION says "dix fichiers de garde" (`:558`; the code has 14) and "23 autorisations" (`:596`; the code has 26).
- **The stamp is lost if it lives inside a kit file.** It needs its own file, written every run.

## Open questions
1. **The stamp.** Reuse `.claude/INSTALL_PROFILE` (already written every run, untracked in the kit, read by kit-doctor)? Or add a dedicated `.claude/KIT_INSTALLED`? The spec's open question asks for "a file under `.claude/`, written every run".
2. **What is denied.** Kit code alone, per the spec list, or also `.claude/project.snapshot.json` (guarded today, written by `migrate`) and `.claude/INSTALL_PROFILE`/the stamp? `settings*.json`, `.tdd-unfrozen` and `.size-exempt` stay ask (not in the spec list).
3. **Where the kit-code list lives.** A second array in `hook-guarded.sh` next to `CWK_GUARDED`, or a tag on the existing entries? The duplicates at `prevent-destructive-commands.sh:889`, `install.sh:264` and `test-workflow-contracts.sh:440` either derive from it or are pinned against it.
4. **The shell symlink rule.** Is following in-project symlinks done for every shell target (a behaviour change for all guarded paths, kit repo included), or only for the installed kit-code tier?
5. **P1 after the overwrite.** P1 (`defaultMode` plus the narrow git allows) becomes unconditional on every run. Confirm that `P1_ALLOWS`/`PROMPT_ALLOWS`/`RETIRED_ALLOWS` stay as constants and only the held-back branch goes.
6. **The backup.** What form: `.claude/kit-backup/<timestamp>/` holding only the files that differ, or `<file>.bak`? Where is it kept, and is it pruned?
7. **`git apply`/`am`.** Do they parse the patch in the hook (a python reader, handling `-p<n>`/`--directory`/`-C`), or ask whenever the patch is unreadable or reaches a kit path? The spec requires git and unified patches, and asking on stdin.
8. **Kit-bringing calls.** `merge`/`pull`/`rebase`/`cherry-pick`/`revert`/`reset --hard`/`switch`/`checkout <branch>` must compute the paths they bring:
   - switch: `git diff --name-only HEAD <target>`;
   - merge: `git diff --name-only HEAD...<target>`;
   - pull: unknown before the fetch, so it always asks in an installed project?
   - cherry-pick/revert: `git diff-tree <commit>`.

   Does the call ask only when a kit path is in the set, and pass otherwise?
9. **`/kit:init`'s apply command.** What script is it (e.g. `.claude/scripts/kit-apply.sh <proposal>`), and is its denial keyed on the resolved script path in `prevent-destructive-commands.sh`? The script is itself kit code, so it is installed by `install.sh`.
