# Plan: kit-track robustness   (entry: docs/specs/kit-track-robustness.md · research: docs/work/kit-track-robustness/research.md · design: n/a)
Token profile: standard
Base: c2a29f6

## Skips
- DB, backend, front, wiring and INTERFACE: SKIP. This is kit tooling: one Python script, prompts and shell suites.
- Test-first layers: none. Kit shell suites fall outside the freeze matcher. Each new case is written first and run against the code as it stands, then the code is written. Cases are never rewritten.

## Write chain (sequential)
1. `.claude/hooks/test-kit-track.sh`: write KT30-KT45 (below) and run them on the current script.
   - **Expected red:** KT30, KT31, KT32, KT34, KT35, KT37, KT38, KT46.
   - **Pins, expected green from the start** (they lock behaviour that already holds): KT33, KT39, KT40, KT41, KT42, KT43, KT44, KT45.
   - A red pin, or a green "red" case, stops the step for a look; the case is never rewritten.
2. `.claude/scripts/kit-track.py`, until KT1-KT45 are green:
   - **K1 rollback.** Everything after `git worktree add` (copy, hash, snapshot write, `env_slot`) runs inside one `try`.
     - On any exception: `git worktree remove <rel_tree>` (never `--force`), then `git branch -d feat/<slug>`, then `Refused("fork failed after the worktree was created: <error>; rolled back")`.
     - If either rollback command fails: `Refused("fork failed: <error>; rollback incomplete, run: git worktree remove <rel_tree> && git branch -d feat/<slug>")`.
   - **K2 symlinks, filter first.** `walk` prunes children named in `SKIP_DIRS` before any symlink check (KT46). It yields the other symlinked entries with a flag instead of refusing them, and does not descend symlinked dirs. Three callers apply the refusal:
     - `candidates` applies `skipped()` first, then the git-ignore filter (`ignored_only`), and only then refuses a symlink that survives as something to copy.
     - Tops: `.claude` and the DOC_DIRS tops are refused unconditionally when they are symlinks. `ROOT_FILES` tops (`CLAUDE.md`, `AGENTS.md`, …) go through the same filter-first rule as any file.
     - close's owned-root walk (`owned_roots`) refuses any symlink it is given, as it does today. This keeps a symlinked track session doc out of main (F8).
   - **K3 snapshot schema.** Before any write, close checks that the snapshot is a JSON object whose `files` is an object mapping relative path strings to 64 lowercase hex characters. Otherwise: `Refused("malformed .kit-snapshot: <why>")`. Key safety (`..`, absolute paths) is left as it is, since crafted keys are OUT of scope.
   - **K4 copy-back report.**
     - Each copy prints its report line as soon as it lands (flushed). That covers `copied …`, `conflict … → sidecar` and `research-cache modified … → sidecar`.
     - The non-copy lines (`snapshot change ignored`, `kit drift …`) print after the copy loop.
     - A copy OSError, or a verify mismatch, mid-loop: the lines already printed stand, and `Refused` names the failing file and says "earlier copies landed, listed above; rerun close".
     - One helper, `land(rel, dst)`, does copy + verify + print, so both failure kinds take the same path.
   - **K5 skip lists.** `SKIP_NAMES` += `project.proposed.json`, `project.snapshot.json`. `SKIP_DIRS` += `.ruff_cache`. `SKIP_PREFIXES` += `.loop-record.`.
   - **Docstring.** Reworded to what holds: a fork refusal creates nothing, or rolls back what it created; a close refusal before the copy-back writes nothing.
3. `.claude/hooks/test-small-lane.sh`: N3b, the no-snapshot control. It is a pin, green from the start. Raise the floor at :674 by one.
4. `.claude/hooks/test-workflow-contracts.sh`: pins WT16-WT24, written **before** step 5.
   - **Expected red:** WT16-WT21. They name the new wording, which does not exist yet.
   - **Pins, expected green from the start** (they lock existing wording): WT22, WT23, WT24.
5. Prompts:
   - **K6.**
     - `tracks.md:190-192` is scoped to non-kit-local tracks ("a kit-local track is never entered: see above").
     - The `tracks.md` hand-over template gains the kit-local line `cd .claude/worktrees/<track-slug> && ./workflow.sh "/loop:orchestrate <entry>"`, followed by `the local-kit-env lines fork printed`.
     - `orchestrate.md:265-266` gets the same scoping, and `docs/Claude_Workflows.md:690-692` gets it in French.
   - **K7.** orchestrate step 4 gains: "A kit-local hand-over (Phase 0.5) is not an exit: the line stays `IN LOOP`, owned by the track session."
   - **K8.** `tracks.md:38-39` mirrors `orchestrate.md:166-168`: `closed` → board `BLOCKED` "PR closed unmerged", story `Approved`; `orphaned:<b>` → say so and stop on it; `open`/`stacked`/`unknown`/`none` → one line each.
6. Every kit suite and `.claude/scripts/kit-lint.sh` pass green.

## Parallel lots (inside this track, same tree)
none: fully sequential.

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: none.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/scripts/kit-track.py` | Edit | K1-K5, docstring |
| `.claude/hooks/test-kit-track.sh` | Edit | KT30-KT46 |
| `.claude/hooks/test-small-lane.sh` | Edit | N3b + floor |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | WT16-WT24 |
| `.claude/commands/loop/tracks.md` | Edit | K6 scoping + template, K8 rows |
| `.claude/commands/loop/orchestrate.md` | Edit | K6 scoping, K7 sentence |
| `docs/Claude_Workflows.md` | Edit | K6 scoping (French) |

## Contracts
- Exit codes are unchanged: 0 means ok, 2 means `kit-track: <reason>`. No path may end in a traceback (exit 1).
- Fork rollback messages are as given in step 2 (K1).
- Close report lines keep their text, but now print as each copy lands. A mid-loop refusal says `earlier copies landed, listed above; rerun close`.
- A malformed snapshot is refused with `malformed .kit-snapshot: <why>`.

## Test plan (gate — validated before EXECUTE)

### Test-after — kit shell fixture suites (outside the freeze matcher; written first, run, never rewritten)

#### .claude/hooks/test-kit-track.sh (new ids KT30-KT45)
**Reproduction**
- [ ] KT30 (red) fork with one kit file to copy unreadable (`chmod 000`). Exit 2 with `fork failed after the worktree was created`. `no_fork` holds: no `.claude/worktrees/demo-1.1`, no `feat/demo-1.1`. Once the file is readable again, a second fork exits 0.
- [ ] KT31 (red) a project whose **tracked** `CLAUDE.md` is a symlink to `AGENTS.md` (`ln -s AGENTS.md CLAUDE.md`, `git add -f CLAUDE.md`, commit) forks with exit 0, and `.kit-snapshot` is present.

**Core behaviour**
- [ ] KT32 (red) a symlinked `.claude/settings.local.json` (a skipped name) does not block the fork: exit 0.
- [ ] KT33 (pin) a symlink inside what is copied (`.claude/hooks/evil.sh` → an outside file) is refused: exit 2, ERR names `.claude/hooks/evil.sh`, and `no_fork` holds.
- [ ] KT34 (red) close with a `.kit-snapshot` that is not JSON: exit 2 with `malformed .kit-snapshot`, no `Traceback` in ERR, nothing written in main, and the worktree is still registered.
- [ ] KT35 (red) close with a `.kit-snapshot` whose `files` maps a path to `nothex`: exit 2 with `malformed .kit-snapshot`, and nothing written in main.
- [ ] KT37 (red) a copy-back where main's `docs/research-cache/` is read-only (it is the last target in copy order). Exit 2. OUT already holds the `copied` lines for `docs/work/demo-1.1/handoff.md`, `docs/work/demo-1.1/research.md` and `docs/stories/demo/1.1.md`, and ERR names the research-cache file and says `earlier copies landed`. After `chmod u+w`, the rerun exits 0 and its OUT names the research-cache file. The two runs' OUT together name every copied file.

**Business rules**
- [ ] KT38 (red) a main tree with `.claude/project.proposed.json`, `.claude/project.snapshot.json`, `.claude/.ruff_cache/x` and `.claude/.loop-record.abc.tmp` (all git-ignored) forks without copying any of them into the track, and none of them is named in the snapshot's `files`.
- [ ] KT39 (pin) fork on a detached HEAD exits 2 with `detached`, and `no_fork` holds.
- [ ] KT40 (pin) fork run from inside a registered worktree exits 2 with `run from the main tree`.
- [ ] KT41 (pin) close on a registered worktree whose `.kit-snapshot` was deleted exits 2 with `has no .claude/.kit-snapshot`, and nothing is written.
- [ ] KT45 (pin) close when the track's `docs/work/demo-1.1/handoff.md` is a symlink to an outside file: exit 2, ERR names that path, and nothing is written in main.

**Edge cases**
- [ ] KT42 (pin) close when `git worktree remove` fails (the tree is `git worktree lock`ed): exit 2 with `rerun close once it is clean`, and the copied lines are in OUT.
- [ ] KT43 (pin) KT18's conflict close exits 0.
- [ ] KT44 (pin) KT27's and KT28's refusals, checked more strictly:
  - In both, ERR holds `symlink`.
  - For KT27, ERR also names `docs/work/demo-1.1/notes.md`, and main's `docs/work/demo-1.1/research.md` does not exist afterwards.
  - For KT28, main's `docs/stories/demo/1.1.md` is unchanged (still `Status: Approved`), and main's `docs/research-cache/x.md` does not exist.
- [ ] KT46 (red) a main tree whose `.claude/kit-backup` is a symlink to an outside dir forks with exit 0 (a symlinked SKIP_DIR leaf is pruned, not refused).

#### .claude/hooks/test-small-lane.sh
- [ ] N3b (pin) a `.claude/worktrees/inbox-1.3` project without `.kit-snapshot` is not silent: its output names `Next feature (topmost READY): feature x`.

#### .claude/hooks/test-workflow-contracts.sh (pins WT16-WT24)
- [ ] WT16 (red) tracks.md holds `a kit-local track is never entered: see above`. Only the new K6 scoping of :190 has that wording.
- [ ] WT17 (red) tracks.md: the hand-over template block (the `section` from `Track <track-slug> —` down to the line that says the two slugs must differ) holds both `cd .claude/worktrees/<track-slug> && ./workflow.sh` and `local-kit-env lines fork printed`.
- [ ] WT18 (red) orchestrate.md's Phase 0.5 `EnterWorktree` sentence names the non-kit-local case.
- [ ] WT19 (red) orchestrate.md step 4 holds `A kit-local hand-over (Phase 0.5) is not an exit`.
- [ ] WT20 (red) tracks.md section 0 holds `story `Approved`` and `orphaned:<b>`.
- [ ] WT21 (red) docs/Claude_Workflows.md: the `EnterWorktree` line names `kit-local`.
- [ ] WT22 (pin) tracks.md holds `git ls-tree -r --name-only HEAD -- .claude/hooks` (completes WT1).
- [ ] WT23 (pin) orchestrate.md holds `git ls-tree -r --name-only HEAD --` followed by `.claude/hooks` (completes WT2; the command wraps across a line there).
- [ ] WT24 (pin) ship.md 4bis-local (`pk_local`) holds `pr: none`, and lacks both `close <slug> --merged` and `loop-pr-state.sh` (completes WT13.2; the close command itself is already pinned by WT6.2).

#### Open questions (from research, proposed answers)
1. Copy-back → no pre-flight. Each line prints as its copy lands, so an interrupted run has already reported every landed file. The rerun finishes (KT37). This matches the spec's criterion exactly.
2. Rollback → `git worktree remove`, then `git branch -d`, never `--force`. A failed rollback refuses and names the two commands (KT30 covers the rollback that succeeds; the failed-rollback branch is a vigilance read).
3. **Verify mismatch: your call.** It cannot be injected without a race or a test-only seam in production code. Proposed: no seam. The shared `land()` helper sends the verify refusal down the same print-as-it-lands path that KT37 exercises. The review checks the verify branch by reading, and that is recorded in `## Gate` and `## Vigilance` as an accepted scope reduction.
4. Snapshot schema → an object whose `files` maps path strings to 64-hex. Crafted keys are left alone (spec OUT) (KT34, KT35).
5. K5 names → the four, as in step 2 (KT38).
6. docs/Claude_Workflows.md is scoped too (WT21).
7. K7 → one sentence in step 4 (WT19).
8. K8 → tracks.md mirrors orchestrate's rows (WT20).
9. Docstring → reworded to what holds.

## Vigilance (carried from research and the plan critic)
- No `--force` and no `rm -r` in the rollback. A rollback failure is a refusal naming the commands, never a traceback (critic F3: read this branch).
- The rollback removes only what this fork created. The refusals for an existing tree or branch stay ahead of `worktree add`.
- A symlink inside what is copied, a symlinked `.claude`/DOC_DIR top, or a symlink yielded to close's owned walk is still refused (KT33, KT45).
- A symlinked SKIP_DIR leaf (e.g. `.claude/kit-backup` → elsewhere) does not block a fork (KT46).
- KT38 covers "never kit drift" indirectly: drift draws from the manifest plus `candidates()`, both filtered by `skipped()`. A new drift source must be filtered the same way (critic F18).
- Snapshot validation runs before any write in main.
- The verify-mismatch branch (copy, then hash differs) goes through `land()` and leaves the landed lines printed. Checked by reading (open question 3).
- Every landed file is reported, sidecars included, even when a later copy fails. The rerun is idempotent.
- The `.loop-record.` prefix leaves `.loop-record.json`/`.lock` handling unchanged.
- WT1-WT15, KT1-KT29, N1-N3, DW6 and IW3 stay green. docs/Claude_Workflows.md stays French.
- New KT ids start at KT30. KT15 is duplicated today and is not touched. The chmod cases assume a non-root runner, which holds for GitHub's runner and for this machine.
- No path in kit-track.py may end in a traceback.

## Acceptance criteria (carried from the entry artifact)
- [ ] A fork that fails after `git worktree add` exits non-zero with one line and
      leaves no worktree, no branch and no partial copy; a second fork then works.
- [ ] A project with `CLAUDE.md -> AGENTS.md`, or a symlinked skipped file, forks;
      a symlink inside what is actually copied is still refused.
- [ ] A malformed `.kit-snapshot` makes close refuse with one line, no traceback,
      nothing written.
- [ ] A copy-back interrupted mid-way reports every file already copied; a rerun
      finishes and the union of reports names every file.
- [ ] Runtime/session files (the four names) never appear as `kit drift`.
- [ ] tracks.md and orchestrate.md tell a kit-local track to be handed over by
      `cd <track> && ./workflow.sh …`, never entered; the main session does not
      mark a handed-over line BLOCKED; closed/orphaned handling matches in both.
- [ ] Every listed test gap has a case that fails on the current code where the
      defect exists, and the contracts suite pins the new wording.

## Gate
- 2026-11-27 go
- Contract: as written
- Plan critic open F2 → accepted: no test seam. The verify-mismatch branch is checked by reading, and it shares `land()` with the KT37 path (an accepted scope reduction of the spec's "every gap has a case").
- Q1 copy-back → print as it lands, no pre-flight · Q2 rollback → remove + branch -d, never --force · Q3 → F2 · Q4 snapshot schema, crafted keys OUT · Q5 four skip names · Q6 Claude_Workflows.md scoped · Q7 step-4 sentence · Q8 tracks.md mirrors orchestrate · Q9 docstring reworded

## Plan critic
- pass 1: completeness 70, quality 62 (F1, F2, F5-F8 → rewrite; verified on the main thread)
- pass 2: completeness 84, quality 80 (F5-F8 closed. F1 needed `lacks loop-pr-state.sh` and F14 needed a new-only string for WT16: both narrowed in place. F15-F17 folded in: KT44 wording, WT17 scoped to the template block, KT46)
- surviving blockers: none. F2 (verify-mismatch scope) is an interpretation for the user at the gate (open question 3).
