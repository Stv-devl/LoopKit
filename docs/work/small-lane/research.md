# Research: Small lane, small tickets in parallel   (entry: docs/specs/small-lane.md)
Token profile: standard

## Pattern to follow
- **Kit shell scripts + fixture suite**: `.claude/hooks/test-attempts.sh:1-21` (`set -euo pipefail`, `mktemp -d` + `trap 'rm -r "$SCRATCH"' EXIT`, `set +e; CODE=$?` around expected non-zero exits, final `echo '<name> fixtures: green.'`); `test-kit-doctor.sh:31` builds a fixture repo with `git -C "$SCRATCH" init -q`. `test-hooks.sh:8-14, 302-307` is the only counted harness (`fail()`, `CASES`, `FAILURES`) — the right shape for ~40 P/D/C/Q cases.
- **Command shape for `small.md`**: `.claude/commands/loop/spec.md` — numbered Process (AskUserQuestion at 13, write at 49, chain at 67-80 with the `./workflow.sh` exception at 77-78), `## Template` (100), `## Rules` (139-150), `## Task: $ARGUMENTS`.
- **Contract greps**: `test-workflow-contracts.sh` — named file variables (lines 5-12), `grep -Fq`, negative `if grep …; then exit 1; fi`, `section "$SHIP" '### 4. Commit' '### 4bis'` scoping, last case line 358, success echo line 360.

## Wiring points
- **Pipeline pick**: `orchestrate.md` Phase 0 (line 67) has **no entry-path → pipeline selector**; `light/full/BUG` exist only as the board column (90-91) and the "Light pass" paragraph (147). The small branch is a new step in Phase 0 between 69 and 90. The handoff's body `Entry:` line (`handoff/codex.md:46`) is written but never read by orchestrate — S6's "a handoff whose `Entry:` is a small spec" needs Phase 0 to start reading it.
- **kit-attempts in a worktree**: `orchestrate.md:61-62` (Gate attempt ceiling section, not Phase 4). Frozen-case correction paragraph: `orchestrate.md:222-233`. Fix batch: 249-254.
- **Slug rule**: `research.md:21-23`. The generic `docs/specs/<x>.md → <x>` has an unbounded `<x>`: `docs/specs/small/a.md` would give `small/a`.
- **review.md**: stage 0 at 20, UI list `.tsx .jsx .css .html` at 33-35, design.md reference at 50-51 (S7 fallback goes here), stage 1 at 80 (grouping 88-96), dimensions `reviewer.md:44-52` (`correctness`, `tests`, `db`, `security`, `ui`), stage 2 at 154, verdict rule 202-204, template 212.
- **ship.md**: step 4 at 114, 4bis at 124 (4bis.1 = 133, 4bis.2 = 135, 4bis.3 = 140-148), step 5 at 156, step 6 at 176, closing `/clear` then `go` at 212, `next-feature-on-clear.py` at 215. Ship never calls kit-attempts (line 11 only names the keys).
- **tracks.md**: condition 4 at 53 (`git status --short  # condition 4: a dirty tree forks nothing`), rule at 185.
- **github.md** "Merging a track back": 126-149 (steps 1-6; copy of `docs/work/` at step 5; cleanup at 6; gated merge rule 99-113).
- **10-worktrees.md**: fork conditions 22-34, How many tracks 36-58, "What lives in the main tree only" 142-146, merge protocol 177.
- **plan.md template**: 153-257. Sections: header (156), Token profile (157), Skips, Write chain, Parallel lots, Track isolation, Files (`| Path | Create/Edit | Role |`), Contracts, Test plan (`### Test-first — front: …` 198, `### Test-after — hooks, gateway, UI` 233, `#### <path>` blocks, `- [ ] U1 <case>` 231), Vigilance, Acceptance criteria, Plan critic, Gate. **No `Pipeline:` line** today.
- **Entries**: `CLAUDE.md:88-100` ("One loop, two entries"), `docs/Claude_Workflows.md:5-18, 122, 144` (French), `README.md:3` ("30 commands, 12 subagents"), 8-22, 41-50.
- **install.sh**: `copy_tree` at 195-204/544 already ships `.claude/scripts/` (prunes only `__pycache__`, `.tdd-red`, `worktrees`); chmod line 639 covers `hooks/` only → add a `scripts/` line after it. `test-install.sh` asserts no file mode → add `[[ -x … ]]` after 62.
- **kit-doctor.py**: ignored-loop probes 569-572 (add `.claude/scripts/probe.sh`); `NON_HOOKS` 751-756 (add `test-small-lane.sh`, else flagged mute by `check_hook_wiring` 811-844); `check_shipped_paths` 846-879 reports MISSING for a `.claude/scripts/…` named in a doc before the file exists.
- **CI**: `.github/workflows/kit-ci.yml` runs each suite as a step; no aggregator. `test-small-lane.sh` needs its own step (not in the spec's Front surface list).
- **next-feature-on-clear.py**: root at 99 (`CLAUDE_PROJECT_DIR` or cwd); silence check after 99, before 102.

## Reusable
- `hook-lib.sh:232-237`: `CWK_TDD_LAYERS`, `CWK_TDD_IMPL_RE`, `CWK_TDD_TEST_RE` — source them, never copy (`kit-doctor.py` 325-352 checks the layer words' copies). Sourcing is side-effect free only with `CWK_HOOK_TIMING=0` (else an EXIT trap at 47 appends to `.hook-timings.log` and replaces the caller's EXIT trap).
- `kit-attempts.py` (82-114): without `--board/--unit` it counts, prints JSON, still exits 3 at the ceiling; file is `artifact.parent/attempts.json` (92) — travels with the branch.
- `workflow.py`: `PROJECT = Path(__file__).resolve().parent` (17), markers 18-22, `CLAUDE_PROJECT_DIR` exported (220), args forwarded (410-411), `MAX_RESTARTS = 2` per handoff (113, 387-407). Spec claims `17-21` and `398-404` confirmed.
- Handoff body already has `Worktree/branch:` (`handoff/codex.md:48`).

## Blast radius
- `test-workflow-contracts.sh:57` hard-codes `-eq 12` loop commands → 13 with `small.md`, same edit.
- `check_shipped_paths`: write the scripts before the docs that name them (Order step 1 already does).
- `research.md` slug "only copy" (25-37): tracks and orchestrate 0.5 apply it; the new line lands there only.
- No existing `Pipeline:`, `docs/specs/small`, `/loop:small` anywhere in `.claude/` (grep: nothing found).

## Live DB state
n/a — kit tooling.

## External surface
- `.worktreeinclude` copies gitignored files matching its patterns only into worktrees Claude Code creates (`--worktree`, subagent worktrees, desktop sessions); a plain `git worktree add` is not covered, and `EnterWorktree` reportedly not either (issue #70466). A `WorktreeCreate` hook disables it. [fetched] → **D1: the user copies the env file per ticket.** Cache: `docs/research-cache/claude-code-worktrees.md`.
- Transcripts are keyed on the session cwd → a ticket session writes under the worktree's project folder (`--root` needed for `kit-measure.py`, as `## Measure` says). [fetched]
- `CLAUDE_PROJECT_DIR` for a CLI launch inside a manual worktree is undocumented [fetched], but `workflow.py:220` sets it explicitly → settled for `./workflow.sh` launches.
- "Don't ask again" approvals are saved to the **main checkout's** `.claude/settings.local.json`, shared by all worktrees. [fetched]

## Traps (points of vigilance for the review)
- The slug line for `docs/specs/small/<name>.md` must precede the generic rule, and the generic `<x>` must be a single path segment.
- `small-plan.sh` sources `hook-lib.sh` with `CWK_HOOK_TIMING=0`; no copy of the layer words or regexes in `.claude/scripts/`.
- The `git -C <main-tree> merge --ff-only` asks through `enforce-git-workflow.sh` only when the base is `main`/`master` (391-393, 420-421); on another base it falls to the default permission prompt (merge is not in the allow list). The spec's wording over-claims; the ask still happens, by another layer.
- `git worktree add` and `git branch -d/-D` have no hook rule: default prompts. `git worktree remove` without `--force` is allowed by `prevent-destructive` (only `--force|-f` denied, 59-61).
- `.claude/scripts/` is guarded by no hook (`protect-files.sh:149-156` covers lockfiles, `.git/`, `node_modules/`): the `FOUNDATIONS` edit "prompts" only in the default permission mode, as the spec says; nothing more.
- `token-statusline.py:42` reads stdin `workspace.project_dir` before `CLAUDE_PROJECT_DIR`: D2 must verify the token markers land in the worktree.
- `orchestrate.md` Phase 0 must read the handoff's body `Entry:` for a small restart; today it reads frontmatter only.
- `test-small-lane.sh` must join `NON_HOOKS` and `kit-ci.yml`; `.claude/scripts/` must join the kit-doctor probe, `install.sh` chmod and `test-install.sh`.
- `test-workflow-contracts.sh:57` count 12 → 13.
- Every script read-only: P5 asserts no write to the tree or `.claude/` (no hook-lib timing log either).
- `small-scope.sh` diffs the **working tree** (committed or not) plus untracked, `--no-renames`.

## Open questions
1. **`## Measure` (Order step 4, one acceptance criterion)** needs 6 real paired runs plus a 3-ticket batch on fresh clones; it cannot run inside this pass. Proposed: this pass ships Order 1-3 and 5, and leaves `## Measure` plus the keep/remove decision as the follow-up, recorded unchecked at ship. OK?
2. **Merge ask on a non-main base**: accept the default permission prompt as "the ask" (spec wording corrected to "asks through `enforce-git-workflow.sh` on main/master, through the default prompt otherwise"), or add a hook rule so every `merge` through `-C` asks? Proposed: accept and correct the wording (the spec's OUT says "no hook allow rule", and adding an ask rule is a hook change outside its file list).
3. **CI step**: add `test-small-lane.sh` to `.github/workflows/kit-ci.yml` (not in the spec's Front surface list)? Proposed: yes; every other kit suite has its step.
4. **Test harness shape**: counted (`test-hooks.sh` style) or abort-on-first (`test-attempts.sh` style)? Proposed: counted, ~40 cases.
