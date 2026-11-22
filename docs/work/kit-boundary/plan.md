# Plan: Kit boundary, pass 2a-3   (entry: docs/specs/kit-boundary.md · research: docs/work/kit-boundary/research.md · design: n/a)
Token profile: critical
Base: 364f906

## Skips
- DB: SKIP, no data.
- Backend: SKIP, kit tooling.
- INTERFACE: SKIP, no screen.
- Front test-first layers (`utils`/`mapper`/`repository`): none. The TDD hooks key on `src/`/`shared/`, and every file here is a hook, script or suite.
  - The kit's own discipline applies: each step writes its cases into the suite first, runs them red, then writes the code.
  - Case ids: `KB` (hooks, test-hooks.sh), `G19.nnn` (git JSONL harness), `IN27+` (test-install.sh), `KD11+` (test-kit-doctor.sh), `PK10+` (test-workflow-contracts.sh).
- Kit prompts: OUT, `kit-prompts.md`.

## Proposed answers to research's open questions (taken at `## Gate`)
1. **The stamp is `.claude/INSTALL_PROFILE`.**
   - `install.sh:746-750` already writes it on every run, it is untracked in the kit, and kit-doctor already reads it. No second file.
   - `install.sh` refuses a TARGET whose physical path is the kit dir (IN36), so the stamp can never land in the kit repo.
   - **Installed** = `$CLAUDE_PROJECT_DIR/.claude/INSTALL_PROFILE` exists, OR not (`install.sh` a file AND `addons/` a dir) under `$CLAUDE_PROJECT_DIR`. An unset or relative `CLAUDE_PROJECT_DIR` counts as installed (fail closed).
   - Cases: KB1-KB6.
2. **Kit code (the deny tier):**
   - `.claude/hooks/*`, `.claude/scripts/*`;
   - `workflow.py`, `workflow.sh`, `codex-handoff.sh`, `install.sh`, `addons/*`;
   - `.claude/project.json`, `.claude/project.snapshot.json` (a back door into `project.json` while it exists), `.claude/INSTALL_PROFILE`.
   - `settings*.json`, `.tdd-unfrozen`, `.size-exempt` and the app configs stay in the ask tier.
   - Cases: KB7-KB9, KB13.
3. **Where the list lives.**
   - A new array `CWK_KIT_CODE` in `hook-guarded.sh`, next to `CWK_GUARDED`. Every entry except `.claude/INSTALL_PROFILE` is also in `CWK_GUARDED`. The stamp is **not** added to `CWK_GUARDED`: in the kit repo nothing changes (spec amended 2026-11-17), and the stamp never lands there (IN36).
   - PK10 pins `CWK_KIT_CODE ∖ {.claude/INSTALL_PROFILE} ⊆ CWK_GUARDED`.
   - `cwk_is_kit_code <rel>` matches an entry or a path under it. With `--reach`, it also matches a folder above an entry other than `.`, for a removal or move operand (`.claude`).
   - `install.sh` `GUARD_FILES` goes, together with the hold-back (Q5). The `prevent-destructive-commands.sh:889` text is kept as it is.
4. **Shell symlinks: only for the kit-code tier.**
   - PDC resolves each shell write row's physical path with `cwk_real_rel` (a dangling link included). When that path is kit code: deny in an installed project.
   - The kit repo and the other tiers keep their lexical reading, so nothing changes there (Q10).
   - Cases: KB17, KB19.
5. **P1 becomes unconditional.**
   - `held`, `guard_api_missing`, `guard_api_number`, `GUARD_FILES`, `ADDON_GUARD_FILES`, `reader_stale` and the `$held` merge clauses are deleted.
   - `P1_ALLOWS`, `PROMPT_ALLOWS` and `RETIRED_ALLOWS` stay as constants and are always applied.
   - The `# cwk-guard-api:` lines stay in the hooks, inert. PK8/PK7 pins on them are amended (Gate amendments).
   - Case: IN37.
6. **The backup.**
   - Before an overwrite, each kit file whose bytes differ goes to `.claude/kit-backup/<UTC YYYYmmddTHHMMSSZ>/<same rel path>`. One folder per run, created only if something differs.
   - It is never pruned. `install.sh` prints the folder.
   - `.claude/kit-backup/` is not kit code; it is the user's to delete.
   - Cases: IN30-IN32, IN35.
7. **`git apply`/`am` ask git itself which paths they touch.**
   - The hook runs `git [-C <dir>] apply --numstat -z [-p<n>] [--directory=<d>] [--include/--exclude…] <patch…>`, read-only and from the same directory. It works for git patches, unified patches and format-patch mboxes alike, so `am` is read the same way with its own `-p`/`--directory`.
   - A kit path in the output → deny.
   - Stdin, no patch operand, a `<` redirect, an unreadable `-C`, or a non-zero `--numstat` → ask (installed project).
   - Cases: G19.001-G19.008.
8. **Kit-bringing calls ask only when a kit path is in the set they bring, and only in an installed project.** Otherwise the verdict is today's.
   - `switch`/`checkout <rev>`, and `-c`/`-b` with a start point: `git diff --name-only HEAD <rev>` (two-dot, whole tree).
   - `merge <c…>`: `HEAD...<c>` (since the merge base).
   - `rebase [<upstream>]`: `HEAD...<upstream or @{u}>`.
   - `cherry-pick`/`revert <c…>` (C-F4, `diff-tree` prints nothing for a merge): per commit, `git diff --name-only <c>^ <c>`; with `-m <m>`, `git diff --name-only <c>^<m> <c>`; a root commit, `git diff-tree --root --no-commit-id --name-only -r <c>`; a multi-parent commit without `-m` → ask. A range `A..B` takes the union over `git rev-list A..B`.
   - `reset --hard <c>`: `git diff --name-only <c>`. It already asks; only the reason gains the kit paths.
   - Mixed `reset <c>`: `--cached <c>`.
   - `pull`: always asks in an installed project, because the set is unknown before the fetch.
   - `bisect`, `sparse-checkout`, `submodule update`, `filter-branch`: always ask in an installed project.
   - Any git failure while computing a set → ask. Only a rev, stash or commit that resolves nowhere (no local rev and, for `switch`/`checkout`, no remote-tracking match at all) falls through (step 4 (b)); two or more remote-tracking matches ask (G19.033).
   - Cases: G19.020-G19.027, G19.033.
9. **`/kit:init`'s apply command.**
   - `/kit:init` writes `.claude/project.proposed.json` (not kit code) and prints `bash .claude/scripts/kit-apply.sh` for the user's own terminal.
   - The script copies the proposal to a tmp dir and validates it there with the reader's existing `check`, backs up `project.json` like Q6, then `mv`s the proposal over it (atomic on one filesystem) and the proposal is gone. No new reader subcommand (C-F5: an `adopt` would be a second, unguarded apply path).
   - PDC denies running it in **every** project, kit repo included: the agent never applies its own proposal.
   - "Running" means a command word, a `bash`/`sh`/`source`/`.` operand, an `env`/`exec`/`nohup`/`xargs` operand, or a `-c` string whose `cwk_real_rel` is `.claude/scripts/kit-apply.sh`. Each is resolved against the tracked `cd`, with symlinks followed.
   - Cases: KB20-KB21, IN27-IN29, IN41.
10. **The kit repo: nothing changes** (decided by the user 2026-11-17, spec amended: "the same calls in the kit repo ask" deleted; `:44` and AC kept).
    - Write/Edit, shell (symlinks included) and git keep today's verdicts in the kit repo. `kit_rule` and `bring_rule` run only when `cwk_installed` is 0.
    - The one new kit-repo behaviour is the new script itself: running `kit-apply.sh` is denied everywhere (spec "from a tool call is denied, whatever the spelling", KB20). No existing verdict moves.
    - Controls: KB14, KB19, G19.030 assert today's kit-repo verdicts.
11. **Index-only writers count.** `apply --cached|--index`, `restore --staged`, `rm --cached`, `reset -- <path>` and `update-index` at a kit path are denied.
    - `add` and `commit` pass: they record what is on disk, and only `install.sh` puts kit code on disk.
    - `stash`, `stash push|save|branch` revert modified tracked files to HEAD, so they are kit writers (C-F2, step 4).
    - `worktree add`, `notes`, `replace`, `tag` and `branch` write no kit content into this tree, so they pass.
    - `clean` already asks without `-n`/`-i`.
    - Case: G19.028.

## Write chain (sequential)
1. **Installed check and kit-code list** (`hook-guarded.sh`, api stamp +1).
   - Add `CWK_KIT_CODE`, `cwk_installed`, `cwk_is_kit_code [--reach]`, and the deny text constant `CWK_KIT_DENY="kit code changes in the LoopKit repo, then \`install.sh\`"`.
   - The stamp is **not** added to `CWK_GUARDED` (Q3, F1): it is the one kit-code entry outside it.
   - In `test-hooks.sh`: a `setup` family shared by protect-files, PDC and the git harness:
     - `installed`: a tmp project, `seed_project`, `.claude/INSTALL_PROFILE`, `.claude/hooks/x`, `.claude/scripts/s.sh`, `workflow.sh`, `src/a.ts`;
     - `installed-nostamp`: the same without the stamp;
     - `kitlike`: `install.sh` + `addons/` + no stamp;
     - `kitlike-stamp`: `kitlike` plus the stamp;
     - `half-install`: `install.sh` but no `addons/`, and the reverse.
   - The git variants commit the same files in a tmp repo.
   - RED KB1-KB9, then GREEN.
2. **Write/Edit** (`protect-files.sh`, api stamp +1).
   - Right after the `cwk_is_guard_denied` branch: if `cwk_installed` and `cwk_is_kit_code` on the lexical rel (`REL`, `:209`) **or** the physical rel `cwk_real_rel "$FILE_PATH" "$CWD"` (to add: `:128-138` only yields an absolute path for the secrets probe), deny with `CWK_KIT_DENY`.
   - The worktree prefix is already stripped by `cwk_guard_rel`.
   - RED KB10-KB15, then GREEN.
3. **Shell** (`prevent-destructive-commands.sh`, `shell_targets.py` untouched unless a row lacks its verb).
   - In `guard_classify`, right after the row's `rel` is computed (`:711`) and ahead of the whole `cwk_is_guarded` chain (`:591`, `:771`, `:785`), never inside one of its branches (F2: the stamp is not guarded), when installed:
     - the row's rel, and `cwk_real_rel` of its joined path, are checked with `cwk_is_kit_code` (`--reach` for removal/move rows) → deny;
     - a row whose target is a folder (`.` or an existing dir), written by `cp`/`mv`/`ln`/`rsync`/`install`, checks `<target>/<basename of each source operand>` → deny on kit code. This covers `cp /tmp/install.sh .` and `cp -r /tmp/k/.claude .`.
   - Then the kit-apply run detection (Q9), in every project.
   - RED KB16-KB21, then GREEN.
4. **Git writers** (`enforce-git-workflow.sh`, api stamp +1). This is the python `parse_segments` heredoc; the bash floor `floor_subs` gets the same subcommand names so the two parsers agree.
   - `cwk_installed` is passed on argv. A new `kit_rule(sub, args, directory)` for `apply am checkout switch restore rm mv stash merge-file checkout-index read-tree reset update-index`, and `bring_rule` (Q8), are ordered so that no existing verdict moves (Q-F1, every git fixture repo counts as installed):
     - (a) (N-Q1) both fold into the segment's `DESTR` field together with `DESTRUCTIVE_RULES`, by precedence **deny > ask > `-`**:
       - a deny from any of the three wins. An existing ask is upgraded to `CWK_KIT_DENY` when `kit_rule` denies (`git checkout -- .claude` with the hook modified asks today through `checkout_rule` `:845-848`, and is denied now, G19.010);
       - when an existing rule asks and a kit rule asks too, the existing reason is kept verbatim and the kit reason (`kit code: …` / `brings kit changes: …`) is appended after it, so every existing substring check still holds (G16.003/G16.029/G16.082 `--hard`, G19.026);
       - when `DESTRUCTIVE_RULES` gives `-`, the kit verdict stands alone;
       - the bash side is unchanged: a `DESTR` deny is read in the first loop (`:1552`), its ask at `:1617`, both before `grammar_decide` (`:1732`), so a `switch` that the grammar asks on anyway carries the kit reason (G19.020);
       - the kept rows below stay green because their fixture repos hold no kit path, so the kit sets are empty: checked at RED.
     - (b) (N-C1, N-Q2) a rev is resolved with `git rev-parse --verify -q <rev>^{commit}`. For `switch`/`checkout` a name that does not resolve is then guessed the way git does (`checkout.guess`): exactly one `refs/remotes/*/<name>` → that ref is the diff target; more than one → ask. A name that resolves nowhere, and a missing stash (`stash@{9}`) or commit, falls through to today's verdict (G19.031). The fall-through keys on that `rev-parse` failure, never on a git exit code: `apply --numstat` exits 128 on a missing or corrupt patch, which asks (G19.008, G19.029);
     - (c) every git call they make is gated by the same trust check as `worktree_clean` (`readable_git_dir`); an untrusted dir asks without spawning git, so G15.32's planted `core.fsmonitor` never runs.
     - Rows kept green, checked at RED and at GREEN: G16.025, G16.042, G16.104, G16.113, G17.13 (pull reasons), G16.029, G16.031-G16.034, G16.058, G16.127, G15.32.
   - The set a call writes is computed with read-only git, in `directory` (`-C` joined, `dir_unread` → ask). Every listing is root-relative (C-F3): `ls-files --full-name`, `ls-tree --full-tree`; `diff --name-only` and `apply --numstat` already are.
     - checkout/switch with `-f`/`--force`/`--discard-changes` (F3: they throw away local changes, and the rev-to-rev bring diff is empty when `<rev>` is the current branch): `git diff --name-only HEAD` ∪ `git diff --cached --name-only` → deny on a kit path; otherwise today's `--force` ask (`:1619-1624`) stands. The bring set of `<rev>` still applies on top.
     - checkout/restore: a literal operand that is kit code → deny. Otherwise `git diff --name-only [<src>] -- <pathspec>` ∪ `--cached` when `--staged` or a source is given. Magic, folders and `.` are handled by git itself.
     - rm: `git ls-files -z --full-name -- <pathspec>`.
     - mv: the sources' `ls-files --full-name`, plus the destination and `dest/<basename>`, joined to `-C`.
     - stash pop|apply [<s>]: `git diff --name-only <s>^1 <s>` ∪ `git ls-tree -r --full-tree --name-only <s>^3` when `^3` exists.
     - stash, stash push|save (C-F2, they revert modified tracked files to HEAD): `git diff --name-only HEAD [-- <pathspec>]`, ∪ `git ls-files --others --full-name [-- <pathspec>]` with `-u`, ∪ the same with `--ignored` under `-a`. `stash branch <b> [<s>]`: the `pop` set of `<s>`.
     - merge-file: the first file operand, none with `-p`.
     - checkout-index: `-a` → the index, `--stdin` → ask, else the operands.
     - read-tree: `git diff --cached --name-only <tree>` for each tree.
     - reset --keep|--merge <c>: `diff HEAD <c>`; `reset -- <p>`: the operands.
     - update-index: the operands of `--add|--remove|--force-remove|--chmod|--cacheinfo`; `--stdin`/`--index-info` → ask; `--refresh` passes.
   - Installed + kit path → deny `CWK_KIT_DENY`. In the kit repo neither `kit_rule` nor `bring_rule` runs (Q10): no git spawn, today's verdict.
   - Then `bring_rule` (Q8), installed only.
   - Any git error → ask, never pass.
   - RED G19.001-G19.034, then GREEN.
5. **`kit-apply.sh` and `/kit:init`.**
   - Create `.claude/scripts/kit-apply.sh`: `set -euo pipefail`; `project_config.py check` on a tmp copy of the proposal (no inline `python3 -c`, contract `:738-740`); backup; bash `mv` of the proposal onto `project.json`; then `project_config.py check` on the project itself (N-Q4: `_check_real` needs the real tree). On failure (F5): `mv` `project.json` back to `project.proposed.json`, restore the old file from the backup, delete that run's backup folder, exit 3, so the state equals IN28's. Exit codes: 0, 3 invalid, 4 no proposal.
   - Edit `kit/init.md` step 14 and the final report:
     - in an installed project, Write `.claude/project.proposed.json` and print the command;
     - in the kit repo, keep the guarded Edit.
     - The PK5 needles stay.
   - RED IN27-IN29 and IN41, then GREEN.
6. **`install.sh` overwrite.**
   - New order: `migrate_config` (reads the target's **old** hooks; the snapshot is no longer needed), then `copy_tree` with the kit-code categories routed to `copy_kit` (cmp → backup → `cp`), then `install_settings` (P1 unconditional), then the stamp.
   - `copy_kit` serves:
     - `.claude/hooks/**` and `.claude/scripts/**`, via a `copy_tree` category check on the rel path;
     - `workflow.py`, `workflow.sh`, `codex-handoff.sh`;
     - the fastapi addon hooks (`:830-835`).
   - Everything else keeps `copy_file`'s `.new`.
   - Refuse a TARGET that is the kit dir.
   - Delete the hold-back (Q5) and `reader_stale`. `wire_*` lose their `reader_stale` call.
   - In `project_config.py`, delete the `snapshot` subcommand and `_read_snapshot`/`_overlay` once unused (`migrate` no longer reads a snapshot), plus `.claude/project.snapshot.json` handling; its deny entry stays for projects that still have one.
   - Delete the frozen rows listed under Gate amendments (A).
   - Header `:25-27` and the `.new` summary text are updated.
   - RED IN30-IN40, then GREEN.
7. **`kit-doctor.py`.**
   - `is_kit_source()` becomes markers AND no stamp, the same rule as `cwk_installed`.
   - New row `stamp`: installed and no `.claude/INSTALL_PROFILE` → `DIVERGENCE stamp` ("re-run install.sh").
   - New row `kit-backup`: INFO naming the latest backup folder, if any.
   - RED KD11-KD13, then GREEN.
8. **Docs and rules** (net 0 lines on CLAUDE.md + rules: 516/520, three rules at budget).
   - `CLAUDE.md` "Protected Files": one line replaced, so kit code reads "denied in an installed project". Measured by `test-rules-floor.sh`.
   - `docs/ADAPTATION.md`:
     - §2 `:24-28`, §14 `:456-506` (the kit-code tier);
     - §15 `:507-611`: the hold-back, message and reader-stale paragraphs are removed and replaced by the overwrite + backup paragraph; the "dix fichiers"/"23 autorisations" counts are dropped with them.
   - `README.md` `:39-58`: install and Updating.
   - `kit/doctor.md`: the new rows.
   - `docs/Claude_Workflows.md`: only if it names the hold-back (grep at EXECUTE).
9. **Contracts** PK10-PK13 (`test-workflow-contracts.sh`), and the amended pins (B).
10. **Refactor** under a green suite: dead helpers left by step 6 (`copy_override`'s hook fallback, unused constants), no case edited.

## Parallel lots
None, fully sequential. Steps 1-4 share `hook-guarded.sh` and `test-hooks.sh`, and steps 5-7 share `install.sh`, `project_config.py` and `test-install.sh`.

## Track isolation
- Worktree: none, single track on `audit/slim`.
- Shared foundations touched: every PreToolUse guard hook, `hook-guarded.sh`, `install.sh`, `project_config.py`. No other pass runs beside this one.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/hook-guarded.sh` | Edit | `CWK_KIT_CODE`, `cwk_installed`, `cwk_is_kit_code`, deny text |
| `.claude/hooks/protect-files.sh` | Edit | Write/Edit deny |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | shell deny, physical rows, folder-target basenames, kit-apply run |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | `kit_rule`, `bring_rule`, floor names |
| `.claude/hooks/project_config.py` | Edit | snapshot removal |
| `.claude/scripts/kit-apply.sh` | Create | apply a `/kit:init` proposal |
| `install.sh` | Edit | `copy_kit`, backup, order, self-target refusal, hold-back removal |
| `.claude/hooks/kit-doctor.py` | Edit | installed rule, `stamp`, `kit-backup` |
| `.claude/commands/kit/init.md`, `kit/doctor.md` | Edit | proposal flow, rows |
| `.claude/hooks/test-hooks.sh`, `fixtures/**`, `fixtures/_harness/git-guard.jsonl` | Edit | KB, G19, setups |
| `.claude/hooks/test-install.sh`, `test-kit-doctor.sh`, `test-workflow-contracts.sh` | Edit | IN, KD, PK, deletions (A), amendments (B) |
| `CLAUDE.md`, `docs/ADAPTATION.md`, `README.md` | Edit | docs |

## Contracts
- `cwk_installed` → 0 installed | 1 kit repo. It reads only `$CLAUDE_PROJECT_DIR`, never the hook's dir.
- `cwk_is_kit_code <rel> [--reach]` → 0 | 1.
- Deny reason, every surface: `kit code: <rel> — kit code changes in the LoopKit repo, then \`install.sh\``.
- Bring ask reason: `brings kit changes: <up to 3 rels>[, …]`.
- `kit-apply.sh [<proposal>]`: the default is `.claude/project.proposed.json`. Exit 0 applied | 3 invalid (nothing written) | 4 no proposal. It prints the backup path.
- `install.sh`: prints `kit code: N updated, backup in .claude/kit-backup/<ts>/` or `kit code: up to date`.

## Test plan (gate — validated by the user before EXECUTE)
Main behaviour first, business rules next, edge cases last. Each line becomes the case's `fail` label or JSONL `id`. In a row, "installed" is the `installed` setup and "kit repo" is `__PROJECT_ROOT__`.

### Step 1 — installed check and kit-code list (test-hooks.sh, block KB)
**Core behaviour**
- [ ] KB1 With the stamp and no `install.sh`/`addons/`, `cwk_installed` returns 0.
- [ ] KB2 In the kit repo (`install.sh` + `addons/`, no stamp), `cwk_installed` returns 1.
**Business rules**
- [ ] KB3 Stamp dropped and neither marker: 0 (a dropped stamp never downgrades).
- [ ] KB4 `install.sh` without `addons/`, and `addons/` without `install.sh`, both without a stamp: 0.
- [ ] KB5 Both markers and the stamp: 0 (the stamp wins).
- [ ] KB6 `CLAUDE_PROJECT_DIR` unset, or relative: 0.
**Edge cases**
- [ ] KB7 `cwk_is_kit_code` is 0 for each of these:
      - `.claude/hooks/x`, `.claude/hooks/fixtures/a/b.json`, `.claude/scripts/s.sh`;
      - `workflow.py`, `workflow.sh`, `codex-handoff.sh`, `install.sh`;
      - `addons`, `addons/fastapi/hooks/x.py`;
      - `.claude/project.json`, `.claude/project.snapshot.json`, `.claude/INSTALL_PROFILE`.
- [ ] KB8 It is 1 for:
      - `.claude/settings.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`;
      - `src/a.ts`, `docs/install.sh.md`, `.claude/hooksx`;
      - `.`, `.claude`, `.claude/kit-backup/t/.claude/hooks/x`.
- [ ] KB9 With `--reach`, `.claude` is 0, `.` is still 1, and `src` is 1.

### Step 2 — Write/Edit (test-hooks.sh + fixtures/protect-files.sh)
**Core behaviour**
- [ ] KB10 Installed: a Write to `.claude/hooks/x` is denied, and the reason holds "kit code changes in the LoopKit repo, then `install.sh`".
- [ ] KB11 Installed, each denied:
      - an Edit of `.claude/project.json`;
      - a Write of `.claude/scripts/s.sh`, `workflow.sh`, `codex-handoff.sh`;
      - creating `install.sh` (absent);
      - creating `addons/fastapi/hooks/x.py` (absent);
      - a Write of `.claude/INSTALL_PROFILE`.
**Business rules**
- [ ] KB12 Installed: a Write to `a`, a symlink to `.claude/hooks/x`, is denied. So is `b`, a dangling symlink to `install.sh`.
- [ ] KB13 Installed: `.claude/settings.json` and `.claude/.tdd-unfrozen` still ask, `src/a.ts` passes, `.claude/project.snapshot.json` is denied.
- [ ] KB14 Kit repo: the existing fixtures 06, 07, 19, 38-42 still ask; a Write to `.claude/INSTALL_PROFILE` keeps today's verdict; with `a` → `.claude/hooks/x`, a Write to `a` keeps today's verdict (Q10).
**Edge cases**
- [ ] KB15 Installed: a Write to `.claude/worktrees/w/.claude/hooks/x` is denied, and so is the same under `installed-nostamp` and `half-install`.

### Step 3 — shell (test-hooks.sh, PDC setup rows)
**Core behaviour**
- [ ] KB16 Installed, each denied with the kit text:
      - `echo x > .claude/hooks/x`;
      - `sed -i s/a/b/ .claude/scripts/s.sh`;
      - `printf x | tee workflow.sh`;
      - `rm -r .claude/hooks`;
      - `mv .claude/hooks/x /tmp/y`;
      - `ln -s /tmp/x install.sh`;
      - `mkdir addons`;
      - `cp /tmp/k/install.sh .`;
      - `cp -r /tmp/k/addons .`;
      - `cp -r /tmp/k/.claude .`;
      - `echo x > .claude/INSTALL_PROFILE` and `cp /tmp/a .claude/INSTALL_PROFILE` (F2: the stamp, outside `CWK_GUARDED`).
**Business rules**
- [ ] KB17 Installed, a symlink alias:
      - with `a` → `.claude/hooks/x`, `echo x >> a` is denied;
      - with `d` → `.claude/hooks`, `echo x > d/y` is denied;
      - with `b` → `install.sh` (dangling), `echo x > b` is denied.
- [ ] KB18 Installed: `cp /tmp/notes.txt .` keeps today's verdict on `.`, an ask and not a deny. `echo x > docs/a.md` keeps today's verdict.
- [ ] KB19 Kit repo:
      - `echo x > .claude/hooks/x` and `ln -s x install.sh` ask, as today, the reason holding today's `guarded path:` text and no `kit code:` substring (F4);
      - `echo x > .claude/INSTALL_PROFILE` and `cp /tmp/a .claude/INSTALL_PROFILE` pass, as today (F2);
      - with `a` → `.claude/hooks/x`, `echo x >> a` keeps today's verdict (the lexical reading, Q10).
**Edge cases**
- [ ] KB20 Running the kit-apply script is denied, in the installed project **and** in the kit repo, for each spelling:
      - `bash .claude/scripts/kit-apply.sh`, `./.claude/scripts/kit-apply.sh`, `sh .claude/scripts/kit-apply.sh x.json`;
      - the absolute path;
      - `cd .claude/scripts && ./kit-apply.sh`;
      - `./a` with `a` → the script;
      - `source .claude/scripts/kit-apply.sh`;
      - `bash -c '.claude/scripts/kit-apply.sh'`;
      - `env X=1 .claude/scripts/kit-apply.sh`.
- [ ] KB21 Reading it is not running it: `cat .claude/scripts/kit-apply.sh` and `grep x .claude/scripts/kit-apply.sh` pass.
- [x] KB22 (review R1-a) `bash "$CLAUDE_PROJECT_DIR"/.claude/scripts/kit-apply.sh`, `${CLAUDE_PROJECT_DIR}`, `$(pwd)/…`, `$PWD/…` and `cat kit-apply.sh | bash` deny; `bash .claude/scripts/kit-appl*` and `bash < kit-apply.sh` ask; `cat kit-appl*` passes.
- [x] KB23 (review R1-e) Installed: `sed -i … .claude/hooks/*.sh`, `perl -pi … .claude/scripts/*`, `cp -R x/. .claude/hooks/`, `rsync -a x/ .claude/`, `find .claude/hooks -type f -exec sed -i … {} +`, `cp -R x/. .` and a contents copy of a folder holding `.claude/hooks` deny with `kit code:`; kitlike keeps today's verdict; benign contents copies hold no kit deny.
- [x] KB24 (review R1-C3) Installed: Write/Edit through a link outside the project to kit code deny; a plain outside file, and a link to the kitlike's hook, pass.
- [x] KB25 (review R2-N1) A contents copy from a 70-entry folder is one folder row: `rsync -a big/ dist/` and `cp -R big/. dist/` pass (installed and kitlike); `cp -R big/. .claude/hooks/` and `rsync -a big/ .claude/hooks/` deny `kit code:` (installed); kitlike control has no kit deny.
- [x] KB26 (ship audit) A shell or `env` named by path runs kit-apply.sh like the bare shell. These deny with the kit-apply reason (installed; kitlike for `/bin/bash`): `/bin/bash`, `/bin/sh`, `/usr/bin/bash`, `/usr/bin/env bash`, an absolute project path, `cd .claude/scripts && /bin/bash kit-apply.sh`, and `-o pipefail` before the script. `/bin/bash < kit-apply.sh` asks, like KB22. `/bin/bash other.sh` and `/usr/bin/env python3 x.py` have no kit verdict.

### Step 4 — git writers (fixtures/_harness/git-guard.jsonl, block G19; tmp repos with the kit files committed)
**Core behaviour (installed, kit path → deny)**
- [ ] G19.001 `git apply p.patch`, a git patch (`diff --git a/.claude/hooks/x b/.claude/hooks/x`): deny.
- [ ] G19.002 `git apply p.diff`, a unified patch (`--- a/workflow.sh` / `+++ b/workflow.sh`): deny.
- [ ] G19.003 `git apply -p0 q.patch` with paths `.claude/hooks/x`: deny. `git apply -p2 q.patch` (the same file read as `hooks/x`): passes.
- [ ] G19.004 `git apply --directory=.claude r.patch` on `hooks/x`: deny.
- [ ] G19.005 `git -C sub apply s.patch` is decided by what `git apply --numstat` in `sub` reports: deny when it names `.claude/hooks/x`.
- [ ] G19.006 `git apply --cached p.patch` and `git apply --index p.patch`: deny.
- [ ] G19.007 `git am m.mbox`, a format-patch on `.claude/hooks/x`: deny. `git am n.mbox` on `src/a.ts`: passes.
- [ ] G19.008 `git apply` (stdin), `git apply < p.patch`, `cat p.patch | git apply`, `git apply missing.patch`: ask.
- [ ] G19.009 With `.claude/hooks/x` clean, each denied:
      - `git checkout -- .claude/hooks/x`;
      - `git checkout HEAD~1 -- .claude/hooks/x`;
      - `git restore .claude/hooks/x`;
      - `git restore --source=HEAD~1 workflow.sh`;
      - `git restore --staged .claude/project.json`.
- [ ] G19.010 With `.claude/hooks/x` modified, `git checkout -- .claude/hooks/x`, `git checkout -- .claude`, `git restore .` and `git restore ':(glob).claude/**'` are denied (each asks today: the ask is upgraded, step 4 (a)).
      With only `src/a.ts` modified, `git restore .` keeps today's verdict.
- [ ] G19.011 `git rm .claude/hooks/x`, `git rm -r .claude`, `git rm --cached workflow.sh`, `git rm ':(glob)**/x'` and `git -C .claude rm -r hooks`: deny. `git rm src/a.ts`: today's verdict.
- [ ] G19.012 `git mv .claude/hooks/x a`, `git mv src/a.ts .claude/hooks/y`, `git mv src/a.ts .claude/hooks` and `git -C .claude mv hooks/x ../a`: deny. `git mv src/a.ts src/b.ts`: passes.
- [ ] G19.013 `git stash pop` and `git stash apply stash@{0}` are denied when the stash changes `.claude/hooks/x`.
      `git stash pop` and `git -C src stash pop` are denied when only the stash's untracked part creates `install.sh` (`stash -u`).
      A stash on `src/a.ts` only: passes.
- [ ] G19.014 `git merge-file .claude/hooks/x b o`: deny. `git merge-file -p .claude/hooks/x b o`: passes.
- [ ] G19.015 `git checkout-index -a` and `git checkout-index -- .claude/hooks/x`: deny. `git checkout-index --stdin`: ask. `git checkout-index -- src/a.ts`: passes.
- [ ] G19.016 `git read-tree -u -m HEAD k` (`k` changes `.claude/hooks/x`) and `git read-tree k`: deny. `git read-tree -u -m HEAD s` (`s` changes only `src/`): passes.
- [ ] G19.017 `git reset --keep k` and `git reset --merge k`: deny. `git reset --keep s`: passes.
- [ ] G19.018 `git reset -- .claude/hooks/x` and `git update-index --chmod=+x .claude/hooks/x`: deny. `git update-index --stdin`: ask. `git update-index --refresh`: passes.
- [ ] G19.019 With `.claude/hooks/x` modified, `git stash`, `git stash push`, `git stash save x` and `git stash push -- .claude` are denied. With `install.sh` untracked, `git stash -u` and `git stash push -a` are denied. `git stash branch b` on a stash changing `.claude/hooks/x`: deny. With only `src/a.ts` modified, `git stash` keeps today's verdict.
**Business rules (installed, kit-bringing → ask only when it brings kit)**
- [ ] G19.020 `git switch k` (whole-tree diff touches `.claude/hooks/x`): ask, with a reason holding `brings kit changes: .claude/hooks/x`.
- [ ] G19.021 `git checkout k`: ask, with the same reason. `git checkout s`: passes, as today.
- [ ] G19.022 `git merge k`, where k's side since the merge base changes `.claude/hooks/x`: ask.
      `git merge h`, where only HEAD's side changed the hook since the base, so the three-dot set is empty and the two-dot set is not: today's verdict.
- [ ] G19.023 `git pull` and `git pull origin main`: ask, "cannot read the kit changes before the fetch".
- [ ] G19.024 `git rebase k`: ask. `git rebase s`: today's verdict. `git rebase` with no upstream configured: ask.
- [ ] G19.025 `git cherry-pick c` and `git revert c` (c touches `workflow.sh`): ask. `git cherry-pick d` (src only): passes. `git cherry-pick a..b` takes the union.
      With `m` a merge commit whose second parent brought `.claude/hooks/x`: `git revert -m 1 m` and `git cherry-pick -m 1 m` ask; `git revert m` (no `-m`) asks. A root commit touching `workflow.sh`, cherry-picked: ask.
- [ ] G19.026 `git reset k` (mixed): ask. `git reset --hard k`: ask, the reason holding today's `--hard` text **and** the kit paths.
- [ ] G19.027 `git bisect start`, `git sparse-checkout set src`, `git submodule update` and `git filter-branch …`: ask in the installed project, and today's verdict in the kit repo.
**Edge cases**
- [ ] G19.028 Installed: `git add .claude/hooks/x`, `git commit -m x` (off a protected branch), `git stash push` with only `src/a.ts` modified, and `git worktree add ../w` keep today's verdicts.
- [ ] G19.029 Installed: `git -C "$x" apply p.patch` (unreadable `-C`) asks, and a `--numstat` failure (a corrupt patch) asks.
- [ ] G19.030 Kit repo (`kitlike`): G19.001, G19.009, G19.011, G19.012, G19.013, G19.014 and G19.019 keep today's verdicts (Q10).
      G19.020-G19.023 keep today's verdicts there.
- [ ] G19.031 Installed, a missing operand falls through to today's verdict, never asks: `git checkout nosuch`, `git stash pop stash@{9}` (no such stash), `git cherry-pick deadbeef`.
- [ ] G19.032 Installed, an untrusted git dir (G15.32's planted `core.fsmonitor`): `git checkout -- .claude/hooks/x` asks, and the fsmonitor marker file is never created.
- [ ] G19.033 Installed, a clone where `k` exists only as `origin/k`, which changes `.claude/hooks/x`: `git checkout k` and `git switch k` ask with `brings kit changes: .claude/hooks/x` (N-C1). With both `origin/k` and `up/k`: `git checkout k` asks. `git checkout nosuch` still falls through (G19.031).
- [ ] G19.034 Installed, on `main`, `.claude/hooks/x` modified: `git checkout -f`, `git checkout -f main`, `git checkout --force main` and `git switch --discard-changes main` are denied with the kit text (F3). With only `src/a.ts` modified, each keeps today's `--force`/`--discard-changes` ask.
- [x] G19.035 (review R1-b) Installed: `git mv`, `merge-file`, `checkout-index -f --`, `update-index --chmod`, `reset --` with an absolute kit operand (source or destination) deny; kitlike no kit verdict; absolute non-kit `git mv` passes.
- [x] G19.036 (review R1-c) `git rebase main k`, `--onto k main`, `--onto=k main` ask `brings kit changes`; with `s` no kit reason.
- [x] G19.037 (review R1-d) `@{-1}` = `k`: `checkout -`, `switch -`, `merge -`, `rebase -`, `cherry-pick -` ask `brings kit changes`; `@{-1}` = `s`: no kit reason.
- [x] G19.038 (review R1-T1) python3 parser failing: installed `git restore .claude/hooks/x` asks `may write kit code`; kitlike has no such reason.
- [x] G19.039 (review R2-N2) On h2 (main + hook v2), `git rebase main s` asks `brings kit changes` (the `<branch>` switch reverts kit code).
- [x] G19.040 (review R2-N2) On f3 (h2 + src), `git rebase --onto main h2` asks `brings kit changes` (the commits `--onto` drops).
- [x] G19.041 (review R2-N2) Control: `git rebase main s` from feat/x has no kit verdict.
- [x] G19.042 (review R2-N3) Nested project (git top `mono`, project `mono/app`): `git restore`, `git rm --cached`, `git update-index --chmod=+x` on `.claude/hooks/x` deny with the kit reason.
- [x] G19.043 (review R2-N3) Nested: the same three with an absolute operand deny.
- [x] G19.044 (review R2-N3) Nested: `git checkout -- .claude/hooks/x` denies.
- [x] G19.045 (review R2-N3) Nested: `git rm -r .claude` denies.
- [x] G19.046 (review R2-N3) Control: a kit-shaped path outside the project but inside the bigger repo (`../other/...` and absolute; restore, rm --cached, update-index) has no kit verdict.
- [x] G19.047 (review R2-N3) Control: nested `git restore src/a.ts` has no kit verdict.
- [x] G19.048 (review R3-2) Installed: `git -C src am m.mbox` (format-patch touching `.claude/hooks/x`) denies `kit code: .claude/hooks/x`, because am reads its paths from the work-tree top.
- [x] G19.049 (review R3-2) Installed: `git am m.mbox` with cwd `src` denies the same way.
- [x] G19.050 (review R3-2) Control: kitlike, `git -C src am m.mbox` has no kit verdict.
- The existing rows G16.025, G16.042, G16.104, G16.113, G17.13, G16.029, G16.031-G16.034, G16.058, G16.127 and G15.32 run unchanged in the installed fixture repos and stay green, reasons included (Q-F1). Not new cases: a regression there is a defect of step 4.

### Step 5 — kit-apply (test-install.sh, block IN)
- [ ] IN27 With a valid `.claude/project.proposed.json`:
      - `kit-apply.sh` exits 0;
      - `project.json` equals the proposal;
      - the old file is under `.claude/kit-backup/<ts>/.claude/project.json`;
      - the proposal is gone.
- [ ] IN28 An invalid proposal (an unknown key): exit 3, the key named, `project.json` byte-identical, the proposal kept, no backup folder.
- [ ] IN29 No proposal: exit 4, nothing written.
- [ ] IN41 A proposal whose app root is a symlink in the project (valid in the tmp copy): exit 3, `project.json` byte-identical to before, the proposal kept, no backup folder left (N-Q4, F5).

### Step 6 — install.sh overwrite (test-install.sh, block IN)
**Core behaviour**
- [ ] IN30 Re-install over a project whose `.claude/hooks/hook-lib.sh` differs:
      - the file now equals the kit's bytes;
      - the old bytes are under `.claude/kit-backup/<ts>/.claude/hooks/hook-lib.sh`;
      - no `hook-lib.sh.new`;
      - the output names the folder.
- [ ] IN31 Re-install over an up-to-date project: no `kit-backup` folder is created, no `.new` under `.claude/hooks` or `.claude/scripts`, and the output says `kit code: up to date`.
- [ ] IN32 `workflow.sh`, `workflow.py`, `codex-handoff.sh`, `.claude/scripts/small-lib.sh` and, with `--fastapi`, `tdd_py_lib.py` are each overwritten with a backup when they differ.
**Business rules**
- [ ] IN33 A differing `CLAUDE.md`, `.claude/rules/00-project.md`, `.claude/commands/kit/init.md` and `docs/ADAPTATION.md` each still get a `.new`. `settings.json` is still merged, never `.new`.
- [ ] IN34 After a fresh install and after a re-install, `.claude/INSTALL_PROFILE` exists, holding `core` (or `react-ts` with `--react-ts`).
- [ ] IN36 `./install.sh <kit dir>`, or a symlink to it: exit 1, an error naming the kit dir, and nothing written (no stamp).
- [ ] IN37 Re-install over a project whose guard hooks carry an older `cwk-guard-api`: `defaultMode` and the five P1 allows are present after the run, and the output never says `P1 held back`.
- [ ] IN40 Upgrade from a project whose hooks still hold values (`PROTECTED_BRANCHES="main|develop"` in `enforce-git-workflow.sh`, no `project.json`): after the overwrite, `project.json` has `protected_branches` `["main","develop"]`. `migrate` read them before the overwrite.
**Edge cases**
- [ ] IN35 A kit file the project deleted (`.claude/scripts/small-plan.sh`) is re-created, and nothing is backed up for it.
- [ ] IN38 A v1 `project.json` with `app_roots` `["web"]` is upgraded on re-install and keeps `web`.
- [ ] IN39 A project's own `.claude/hooks/my-hook.sh` (not in the kit) is left byte-identical and not backed up.

### Step 7 — kit-doctor (test-kit-doctor.sh, block KD)
- [ ] KD11 A tmp project with the stamp and no markers: mode "installed", no `stamp` divergence.
- [ ] KD12 A tmp project without the stamp and without the markers: `DIVERGENCE stamp`, naming `install.sh`.
- [ ] KD13 The kit repo with no stamp: mode "kit source", and no `stamp` row.

### Step 9 — contracts (test-workflow-contracts.sh, block PK)
- [ ] PK10 Every `CWK_KIT_CODE` entry except `.claude/INSTALL_PROFILE` is in `CWK_GUARDED`, the stamp is not in `CWK_GUARDED`, and `CWK_KIT_CODE` names every entry of the spec's kit-code list.
- [ ] PK11 `install.sh` holds none of `held`, `guard_api_missing`, `reader_stale`, `P1 held back`. The kit tree holds no `snapshot` subcommand.
- [ ] PK12 `kit/init.md` names `.claude/project.proposed.json` and `bash .claude/scripts/kit-apply.sh`. ADAPTATION §15 has no `P1 held back` and names `.claude/kit-backup/`.
- [ ] PK13 `protect-files.sh`, PDC and enforce-git each carry the shared deny text through `CWK_KIT_DENY`, never a literal copy.
- [x] PK14 (review R1-C5) `tdd-prove-red.sh`'s messages that send the agent to `project.json` name `/kit:init` and `bash .claude/scripts/kit-apply.sh`.

### Test-after
- `bash .claude/hooks/test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-workflow-contracts.sh`, `test-rules-floor.sh`, `test-small-lane.sh` and `python3 .claude/hooks/kit-doctor.py`: all green.
- Latency: `hook-timings-report.sh` on the git fixture sweep. `kit_rule` spawns git only on its subcommands, so `status`/`log`/`diff` keep their spawn count. Checked, not a case.

## Gate amendments to validate (written into `## Gate` on the go)
**(A) Deleted, because they test the hold-back or `.new` for kit code, which no longer exist.** All rows are in `test-install.sh`:
- I2 (`:129-342`): (a) `:152-178` including (b) `:173-178`; (A0) `:180-194`; (A2) `:196-203`; (A3) `:205-212`; (A4) `:214-223`; (A8) `:226-235`; (A9) `:237-246`; (A7) `:248-255`; (e) `:277-286`; DA1's held-back clause `:309-313` (C-F1: unbound under `set -u` once `held` goes); (f) `:315-322`; (h) `:334-341`. (g) `:324-332` is kept: it still holds once the hold-back goes (N-Q3, Q-F7).
- I3 (`:343-395`): I3a-I3d.
- HP-B2 (`:446-486`): the held-back prompt asserts `:471-485` (C-F1).
- A9 kit-attempts: `:523-529` (C-F1: fails once P1 is unconditional).
- IN16 `:725-742`, IN18 `:750-779`, IN19 `:781-792`, IN24 `:846-855`, IN26 `:869-881` (snapshot).
- (c) `:257-262` and (d) `:264-275` are kept: fresh carries P1, and target edits never hold back.

**(B) Amended.**
- `test-install.sh`:
  - IN20 `:800`: the message loses "and no saved snapshot";
  - IN23 `:827-845`: the upgrade from a8efa59 now asserts overwrite and backup, with no `reader_stale` path, and drops its `in_merge_all` call `:837` (defined in the deleted IN18 `:752-758`) (C-F1);
  - `:578-585` IN1: the comment only (the `.new` sentence), plus the `:579` comment and the `:586` `GUARD_FILES` grep, which goes with `GUARD_FILES` (C-F1).
- `test-workflow-contracts.sh` `:440-443` (W7): its needle sits in ADAPTATION §14, which step 8 rewrites; the needle moves to the rewritten §14 sentence (C-F1).
- `test-workflow-contracts.sh`:
  - `:714-727`: the "held-back list" becomes "the prompt allow list", `== 26` kept;
  - `:765`, `:983`: the `GUARD_FILES` pins go;
  - `:1005-1010` (PK7): the pins go, `cwk-guard-api` lines kept inert. `:984` is kept: it greps the inert `cwk-guard-api` line, which stays (N-Q3);
  - `:487-488`, `:495-509`: the ADAPTATION needles `P1 held back` and `merge <fichiers>.new, then re-run install.sh` are replaced by PK12.
  - Every amended line is printed old → new in EXECUTE before it is written.

## Vigilance (carried from research)
- Every new deny reads `$CLAUDE_PROJECT_DIR`, never the hook's own dir. A tmp fixture is "installed", so the kit-repo controls run on `__PROJECT_ROOT__` or `kitlike`.
- `.` and `.claude` are never denied as kit code by themselves (KB8, KB18). Only a folder target's resulting basename, or a git-computed set, is.
- A symlink to kit code is followed only in an installed project (KB12, KB17); the kit repo keeps today's lexical verdicts for Write/Edit, shell and git (Q10, KB14, KB19, G19.030).
- Each git writer uses a set git itself computes, in the `-C` directory. Any git error or unreadable input asks, never passes.
- The bash floor `floor_subs` and the python `parse_git` agree on every new subcommand.
- `install.sh` runs `migrate` **before** overwriting kit code (IN40). Otherwise the values of a pre-config project are lost. EcoCrew is the first real case.
- `install.sh` never copies itself or `addons/`, and refuses the kit dir (IN36).
- The P1 constants stay; only the hold-back branch goes (IN37, PK11).
- Rules floor: net 0 lines on CLAUDE.md + rules (516/520).
- Deleted rows (A) are only those listed. Any other failing row is a regression, never a deletion.
- A careless agent, not an adversary: a copy of `kit-apply.sh` outside `.claude/scripts` run by its new path is a known limit. Write it down in ADAPTATION §14, do not chase it.
- `git stash`/`push`/`save`/`branch` are kit writers (G19.019): they revert modified tracked kit code and, with `-u`/`-a`, remove untracked kit code.
- `kit_rule`/`bring_rule` fold into `DESTR` by deny > ask > `-`, existing ask reasons kept verbatim with the kit reason appended (N-Q1, G19.010, G19.026); a rev that resolves nowhere falls through, keyed on `rev-parse`, never on an exit code, after the `checkout.guess` remote-tracking lookup for `switch`/`checkout` (N-C1, G19.031, G19.033); every git spawn is behind `readable_git_dir` (Q-F1, G19.032).
- Plan critic Minors, pass 2 (vigilance):
  - N-Q2 exit 128 also marks a missing or corrupt patch for `apply --numstat`: those ask (G19.008, G19.029), never fall through.
  - N-Q3 (g) `:324-332` and the `:984` pin are kept, not deleted (removed from (A)/(B), see Q-F7).
  - N-Q4 `kit-apply.sh` validates in a tmp copy, so `_check_real` (`project_config.py:109-116`) does not see the project's tree: after the `mv`, run `project_config.py check` on the project itself and restore the backup on failure.
  - N-Q5 moot since the 2026-11-17 amendment (no kit-repo ask); G19.030 is a today's-verdict control.
- Plan critic Minors, pass 3 (vigilance):
  - F2 the git fixture repos commit `.claude/project.json` (kit code): pull rows, G16.029 and G15.32 get a kit ask and stay green only through the append rule of step 4 (a). Never implement "empty set → skip" in a way that drops the append.
  - F3 Q8's fall-through wording must not cover the ambiguous remote case: two remote-tracking matches ask (G19.033).
  - F4 (pass 3) moot since the 2026-11-17 amendment: there is no kit-repo kit ask; the kit repo keeps today's reasons (KB19).
- Plan critic Minors, fresh pass 1 after the amendment (vigilance):
  - F5 step 2's check sits after `REL=$(cwk_guard_rel …) || exit 0` (`protect-files.sh:209`): a Write/Edit through a link outside the project to kit code exits before it. Check `cwk_real_rel` before that exit when installed, or record it as a known limit in ADAPTATION §14.
  - F6 running `kit-apply.sh` is denied in the kit repo too (Q9, KB20), the one new kit-repo verdict: the script is new, so no existing verdict moves; named for the user at the gate.
  - F7 the python `kit_rule`/`bring_rule` take the kit-code list on argv from `CWK_KIT_CODE` (as the heredoc already takes its regexes, `enforce-git-workflow.sh:200`), never a second spelling.
  - F8 KB14/KB19 symlink controls run in the `kitlike` setup, never by creating a link in the live kit repo root.
- Plan critic Minors, pass 2 after the amendment (vigilance):
  - F9 the forced checkout/switch set is gated by `cwk_installed` like the rest of `kit_rule`: in `kitlike`, `git checkout -f` with the hook modified keeps today's `--force` ask (check at review; add it to G19.030's sample if cheap).
  - F10 an out-of-project last-component link to kit code (`/tmp/a` → `.claude/hooks/x`) returns at PDC `:712-713` before step 3's check: same class as F5, handled together (physical check before the outside return when installed, or a known limit in ADAPTATION §14).
  - F11 `switch` is dispatched to `kit_rule` for the forced set (step 4 subcommand list) and present in `floor_subs`; G19.034's switch row pins it.
  - F12 removal rows (`rm`, `unlink`, the source of `mv`) resolve with `cwk_real_path` (the link itself), writers with `cwk_real_rel`: `rm a` with `a` → `.claude/hooks/x` removes only the link and keeps today's verdict.
  - F5 step 5's post-`mv` failure path consumes the proposal and leaves a backup folder: IN41 must say so, or the check runs before the `mv` on a copy placed in the project tree.
- Plan critic Minors to check at review (pass 1, not verified):
  - C-F6 coverage: `switch --orphan`, `rebase --onto` / `rebase <up> <branch>`, `checkout -B`/`switch -C` with a start point, `stash pop --index`, `clean -f` on untracked kit code.
  - C-F7 stamp-dropped is tested for Write only: shell and git rows under `installed-nostamp` too.
  - C-F8 ADAPTATION `:66`, `:114`, `:352`, `:382` and `agents/github.md:28` still say to edit `project.json`; an upgraded `kit/init.md` arrives as `.new` and the install output must name it.
  - Q-F3 entry folders copied without `--reach` (`cp -r /tmp/k/.claude .`) are pinned by KB16, not by `--reach`.
  - Q-F4 PK11's "no `snapshot` subcommand" is scoped to `project_config.py` (`kit-gate-route.py:534` has its own).
  - Q-F5 a `cp` failure after `migrate` leaves a v2 file under the old reader: `install.sh` stops and says so.
  - Q-F6 a project left mid-hold-back by ac3c9a4 loses its snapshot values once snapshot reading goes: name it in ADAPTATION §15.
  - Q-F7 (g) `:324-332` and PK4 `:984` still pass: keep them, do not delete.
  - Q-F8 `apply --check|--stat|--numstat` (read-only) pass; `checkout-index` without `-f`, or with `--prefix=/tmp/`, is not a kit write; base64 mbox parts are read by `--numstat`.
  - Q-F9 the PDC gate `:227-230` runs `shell_targets.py` only when its api line is exactly 6 (`test-hooks.sh:3519`): a stamp bump moves both together.
  - Q-F10 `.claude/kit-backup/` is gitignored by `install.sh` (`:592-648`) and excluded from kit-doctor `scanned_docs` (`:884-889`).

## Acceptance criteria (carried from the entry artifact)
- [ ] F7: kit code is denied in an installed project through Write/Edit, shell and git. The installed check is the stamp OR the missing kit markers, and it is tested through a fixture project. The kit repo keeps today's behaviour.
- [ ] `install.sh` overwrites kit code with a backup. No dead hold-back path is left.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Plan critic
- **Pass 1** (2026-11-16, effort high): completeness 64, quality 58.
- **Verifier** (2026-11-16, effort high, scratch git 2.43 runs). No Major refuted.
- **Route pass 1** (2026-11-17, `route-plan-1.json`): C-F1 to C-F5, Q-F1, Q-F2 → `rewrite`; the 11 Minors → `## Vigilance`. `plan-critic` attempt 1/3 recorded.
- **Rewrite 1** (2026-11-17): closures below written into Q8, Q9, Q10, Q11, step 4, step 5, Files, Contracts, test plan (G19.011-G19.013, G19.019, G19.025, G19.028, G19.031, G19.032, kept rows), Gate amendments (A)/(B), Vigilance. Q-F2 is written as one proposed reading under Q10, for the user at the gate.

- **Pass 2** (2026-11-17, effort high, rerun on rewrite 1): completeness 76, quality 68. C-F1 to C-F5 and Q-F1 fixed; Q-F2 not fixed (narrowed by the verifier: Q4, step 3, Vigilance and the unscoped amendment text; KB19 and KB20 reconciled).
- **Verifier pass 2**: N-C1 partial (the `checkout` half survives; `switch` already asks through `grammar_decide`), N-Q1 survives, Q-F2 partial.
- **Route pass 2** (`route-plan-2.json`): N-C1, N-Q1 → `rewrite`; Q-F2 → `arbitrate` (step 7, `Plan critic, open`); N-Q2 to N-Q5 → `## Vigilance`. `plan-critic` attempt 2/3 recorded.
- **Rewrite 2** (2026-11-17): N-Q1 → step 4 (a) precedence deny > ask > `-` folded into `DESTR`, G19.010 (+ `checkout -- .claude/hooks/x`), G19.026; N-C1 → step 4 (b) `rev-parse` + `checkout.guess` lookup, Q8, G19.033. Q-F2's proposed answer written through Q4, Q10, step 3, KB19, Vigilance. N-Q3 fixed in (A)/(B); N-Q4 closed in step 5 + IN41.

- **Pass 3** (2026-11-17, effort high, LAST): completeness 80, quality 78. N-C1 and N-Q1 fixed. New F1 (Major, demonstrated): under Q10's proposed reading a Write/Edit through a symlink alias to kit code passes in the kit repo (`protect-files.sh:209`/`:266` lexical only; step 2 physical check installed-only), so "KB14 unchanged (Write/Edit already ask)" is false.
- **Verifier pass 3**: F1 survives (reproduced on a `kitlike` scratch project: `Write a`/`Edit a` exit 0 silent, `Write .claude/hooks/x` asks). Side note: step 2's "(`:128-138` already computes both)" is inaccurate, that block yields an absolute path for the secrets probe only.
- **Route pass 3** (`route-plan-3.json`): F1 → `blocked`; F2-F5 → `## Vigilance`. `plan-critic` 3/3: **BLOCKED — plan-critic failed 3x : F1**. No fourth rewrite.
- surviving blockers: F1 (bites only under Q10's proposed reading; the other reading makes it moot).
- **Unblocked 2026-11-17 (user): "nothing changes in the kit repo".** Spec amended (`:72` deleted), `contract` 1 recorded, `plan-critic` counter reset on the user's say. Phase 3 re-entry by edit, not a fresh write: Q10, Q4, step 3, step 4, PK10/stamp, KB14, KB19, G19.030, Vigilance rewritten to the kit repo's today's verdicts; F1 moot; F3, F5 and the step 2 physical-rel note closed in place. A fresh plan-critic pass 1 re-walks the whole plan.
- **Fresh pass 1** (2026-11-17, effort high): completeness 80, quality 70. F1, F4 confirmed from the text; verifier: F2 survives, F3 partial (today's hook already asks on `-f`/`--discard-changes`; the kit deny is missing). Route `route-plan-1.json` (overwritten): F1-F4 → `rewrite`, F5-F8 → `## Vigilance`. `plan-critic` 1/3.
- **Rewrite 1** (fresh): F1 step 1 + PK10; F2 step 3 placement + KB16/KB19 stamp rows; F3 step 4 forced checkout/switch set + G19.034; F4 Contracts kit-repo reason deleted, Vigilance F4 moot, KB19 asserts today's reason.
- **Pass 2** (2026-11-17, effort high): F1-F4 fixed; no new Critical/Major (no verifier needed). Route `route-plan-2.json` → `clear`; F9-F12 → `## Vigilance` (F11 also fixed in step 4's list). `plan-critic` cleared.
- completeness: 91
- quality: 84
- surviving blockers: none

### Survive, with the closure to write in rewrite 1
- **C-F1 (Major).** Widen (A) to `test-install.sh:309-313`, `:471-485` and `:523-529`, which are otherwise unbound under `set -u` or fail with P1 unconditional. Add `:586` (the GUARD_FILES grep) and the `:579` comment to (B).
  - The IN23 amendment must drop its `in_merge_all` call (`:837`), which is defined in the deleted IN18 (`:752-758`).
  - The W7 needle `test-workflow-contracts.sh:440-443` sits in ADAPTATION §14, which step 8 rewrites; add it to (B).
- **C-F2 (Major).** `git stash` / `stash push|save` reverts modified tracked kit files to HEAD (verified). Add them to `kit_rule` with the set `git diff --name-only HEAD`, plus `ls-files --others --full-name` with `-u`/`-a`. Also add `stash branch`. Amend G19.028.
- **C-F3 (Major, partial).** `ls-files` is cwd-relative under `-C` and `ls-tree` is cwd-limited (verified). Use `--full-name` / `--full-tree`.
  - `git diff --name-only` and `apply --numstat` are already root-relative (refuted part).
  - New cases: `git -C .claude rm -r hooks`, `git -C .claude mv hooks/x ../a`, `git -C src stash pop` (untracked install.sh) → deny.
- **C-F4 (Major).** `diff-tree` prints nothing for a merge, or a root commit without `--root` (verified). Use `git diff --name-only <c>^<m> <c>` for `-m <m>`; any multi-parent commit without `-m` asks.
  - New case: `git revert -m 1 <merge touching .claude/hooks/x>` and `cherry-pick -m 1` → ask.
- **C-F5 (Major, interpretation).** `project_config.py adopt` would be an unguarded second apply.
  - Drop `adopt`: `kit-apply.sh` validates with `check` on a tmp copy, backs up, then `mv`.
  - Contract `:738-740` forbids only `python3 -c`/stdin without `-I`, and a bash `mv` is atomic.
- **Q-F1 (Major, wider than claimed).** Every git fixture repo counts as installed (`run_case` `project_dir=$tmp`, `seed_project` adds no markers). The rewrite must state:
  - (a) `kit_rule`/`bring_rule` decide only when `DESTRUCTIVE_RULES` returns `-`; deny wins and existing reasons are kept;
  - (b) a missing rev or stash (exit 128) falls through instead of asking;
  - (c) every `kit_rule` git call is gated by the same trust check as `worktree_clean` (`readable_git_dir`), or G15.32's planted `core.fsmonitor` runs.
  - Rows to keep green: G16.025, G16.042, G16.104, G16.113, G17.13 (pull reasons), G16.029, G16.031-G16.034, G16.058, G16.127, G15.32.
- **Q-F2 (Major, interpretation).** The plan reads spec `:72` ("the same calls in the kit repo ask") for git (G19.030), but `:44`/AC `:78` ("nothing changes") for symlinks (KB19).
  - Put ONE reading to the user at the gate, as a spec amendment that also amends AC `:78`.
  - Then G19.030, KB19, KB14 and Q9's kit-repo deny all follow it.

### Minors (critic, not verified; vigilance or rewrite)
- C-F6 Coverage gaps: `switch --orphan`, `rebase --onto` / `rebase <up> <branch>`, `checkout -B`/`switch -C` with a start point, `stash pop --index`, `clean -f` on untracked kit code.
- C-F7 Stamp-dropped is only tested for Write: add shell and git rows under `installed-nostamp`.
- C-F8 ADAPTATION `:66`, `:114`, `:352`, `:382` and `agents/github.md:28` still say to edit project.json; an upgraded `kit/init.md` arrives as `.new` and the output does not name it.
- Q-F3 `cp -r /tmp/k/.claude .` vs `--reach` only for removal/move; the entry folders without `--reach` are not pinned.
- Q-F4 PK11 "no `snapshot` subcommand" must be scoped to `project_config.py` (`kit-gate-route.py:534`).
- Q-F5 A `cp` failure after `migrate` leaves a v2 file under the old reader.
- Q-F6 Dropping snapshot reading loses the values of a project left mid-hold-back by ac3c9a4.
- Q-F7 (g) `:324-332` and PK4 `:984` still pass; keep them.
- Q-F8 `apply --check|--stat|--numstat`, `checkout-index` without `-f` or with `--prefix=/tmp/`, and base64 mbox parts are over-denied or missed.
- Q-F9 The PDC gate `:227-230` runs `shell_targets.py` only when its api line is exactly 6 (`test-hooks.sh:3519`): a stamp bump needs both moved together.
- Q-F10 `.claude/kit-backup/`: gitignore it (`install.sh:592-648`) and exclude it from kit-doctor `scanned_docs` (`:884-889`).

## Gate
- 2026-11-17 go
- Contract: amended: "The same calls in the kit repo ask" deleted, the kit repo keeps today's behaviour (user's own choice, 2026-11-17); validated as written at this go.
- Q1-Q11 → the proposed answers as printed in `## Proposed answers` (Q9: running `kit-apply.sh` denied in the kit repo too, F6; Q10: nothing changes in the kit repo).
- Gate amendments (A) and (B) → accepted as listed.
- 2026-11-18 review BLOCKED (3/3, R3-2). The user granted one exception: a fix batch for R3-2 only (`git am` from a subdirectory; closure in `route-review-3.json`), then a narrow check of that fix. Round 3's 7 Minors stay in `follow-ups.md`. A failed check stops the loop: no further exception without the user.
- 2026-11-18 R3-2 closed. `kit_numstat` runs from the top for `am` only; G19.048-050 were red, then green. Narrow check, inline:
  - the diff is 8 lines;
  - G19.005 still passes;
  - `--kb-only` 329 green;
  - full hooks 2931 green;
  - install, contracts and kit-doctor green.
  The review gate clears under the exception.
- 2026-11-18 ship, step 1bis: security audit (authz/guards) found 0 Critical, 1 Major, 4 Minors.
  - The Major: kit-apply run through a shell given by an absolute path (`/bin/bash`, `/usr/bin/env bash`, `/bin/bash <`) is not denied.
  - User's choice: fix before the commit. One `implementer`, cases KB26, `fix-base` = b5780ff, then a narrow check and the gates re-run.
  - The 4 Minors are in `follow-ups.md`.
  - KB26: 17 failures (10 cases) red, then green.
  - Narrow check, inline: the diff of `run_target` and `GUARD_SHELL_WORD_RE`.
  - The stdin form asks, as the frozen KB22 pins for `bash <`. A deny would need a KB22 amendment, which was not made.
  - Suites green: `--kb-only` 341, plus 9 others; doctor reports no divergence.
