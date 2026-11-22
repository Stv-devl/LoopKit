# Plan: Small lane, small tickets in parallel, merged one at a time   (entry: docs/specs/small-lane.md · research: docs/work/small-lane/research.md · design: n/a)
Token profile: standard

## Skips
- Interface : SKIP — kit tooling, no user surface.
- DB, Backend : SKIP — `Data model: none`, `Custom backend: NONE`.
- Front app layers (types → repository) : SKIP — no `src/` code; the TDD hooks do not key on `.claude/` shell. The test-first discipline is applied by hand: every `test-small-lane.sh` case is written first, each script exists first as a **stub that prints nothing and exits 2**, and every case is observed failing on its own assertion against that stub before the script is written.
- `## Measure` (Order step 4) : deferred to a follow-up session, Open question 1 (needs real paired runs on fresh clones).

## Write chain (sequential)
1. DB — SKIP
2. Backend — SKIP
3. Kit scripts, fixture-first, one script at a time (Order step 1):
   - `test-small-lane.sh` harness skeleton (counted, `test-hooks.sh` style) + fixture-repo builder
   - **[P cases RED → `small-lib.sh` + `small-paths.sh` GREEN]**
   - **[Q cases RED → `small-plan.sh` GREEN]**
   - **[D cases RED → `small-dispatch-check.sh` GREEN]**
   - **[C cases RED → `small-scope.sh` GREEN]**
   - **[N1, N2 RED → `next-feature-on-clear.py` silence + `loop_slug` small line GREEN]**
   - **[X1 RED in `test-kit-doctor.sh` → `kit-doctor.py` `.claude/worktrees/` prefix exemption GREEN]**
   - install / doctor / CI lines: `chmod +x` on every new `.sh` (the five scripts and `test-small-lane.sh`) (committed mode 100755), `install.sh` chmod, `test-install.sh` I1, `kit-doctor.py` probe + `NON_HOOKS`, `kit-ci.yml` step
4. Commands and docs (Order steps 2, 3, 5), contract greps first:
   - **[K1-K5 greps added to `test-workflow-contracts.sh` (count 12 → 13) RED]**
   - `small.md` (S1-S4, template S3, `--status` S9) → `research.md` slug line → `10-worktrees.md` paragraph + 142-146 rewrite → `tracks.md` exception → `orchestrate.md` small branch (S5-S8) → `review.md` stage 0 fallback → `ship.md` small lines → `github.md` small merge branch → **K GREEN**
   - S10: `CLAUDE.md`, `README.md`, `docs/Claude_Workflows.md` (French)
5. Tests — whole kit: every `.claude/hooks/test-*.sh` in `kit-ci.yml` + `python3 .claude/hooks/kit-doctor.py` (No divergence).
6. Refactor — `small-lib.sh` dedup across the four scripts under a green suite; no case edited.

## Parallel lots (inside this track, same tree)
none — fully sequential (every script shares `small-lib.sh` and the one test file).

## Track isolation
- Worktree: none, single track (main tree, branch `audit/slim`).
- Shared foundations touched: `.claude/commands/loop/*`, `.claude/guides/10-worktrees.md`, `.claude/hooks/kit-doctor.py`, `install.sh`, `CLAUDE.md` (kit foundations). No other loop runs beside this one.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/scripts/small-lib.sh` | Create | shared, sourced: spec parsing (`Files`, `Base:`, blocks), path → layer mapping, test-file name of a module, main-tree path; sources `hook-lib.sh` with `CWK_HOOK_TIMING=0` (deviation: not in the spec's list, avoids four copies of the mapping) |
| `.claude/scripts/small-paths.sh` | Create | S2 mechanical eligibility |
| `.claude/scripts/small-dispatch-check.sh` | Create | S4 preconditions |
| `.claude/scripts/small-scope.sh` | Create | S5 scope |
| `.claude/scripts/small-plan.sh` | Create | S6 plan generator + `--check` |
| `.claude/hooks/test-small-lane.sh` | Create | P/D/C/Q/N cases on fixture repos |
| `.claude/hooks/next-feature-on-clear.py` | Edit | silent in `.claude/worktrees/small-*`; `loop_slug` gains the small line |
| `.claude/hooks/kit-doctor.py` | Edit | `.claude/scripts/probe.sh` probe (569-572), `test-small-lane.sh` in `NON_HOOKS` (751), `check_shipped_paths` (851-863) skips any captured path under `.claude/worktrees/` (runtime, like `RUNTIME_PATHS` 742-747: today `.claude/worktrees/small-<name>` captures `.claude/worktrees/small-` → MISSING) |
| `.claude/hooks/test-kit-doctor.sh` | Edit | X1 |
| `install.sh` | Edit | `chmod +x "$TARGET/.claude/scripts/"*.sh` after 639 |
| `.claude/hooks/test-install.sh` | Edit | I1 |
| `.github/workflows/kit-ci.yml` | Edit | `test-small-lane.sh` step (Open question 3) |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | K1-K5, loop command count 12 → 13 |
| `.claude/commands/loop/small.md` | Create | `/loop:small` dispatch, template, `--status` |
| `.claude/commands/loop/research.md` | Edit | slug line `docs/specs/small/<name>.md → small-<name>`, before the generic rule; `<x>` = one path segment |
| `.claude/commands/loop/orchestrate.md` | Edit | Phase 0 pipeline pick (small first, reads handoff body `Entry:`), small branch S6, S7 (review), S8 (ejection), kit-attempts line 61-62 replacement |
| `.claude/commands/loop/review.md` | Edit | stage 0 step 3 fallback to `Acceptance criteria` |
| `.claude/commands/loop/ship.md` | Edit | small lines in 4, 4bis.1-3, 5, 6, closing line |
| `.claude/commands/loop/tracks.md` | Edit | dirty-tree exception for small tickets, unmerged `small-*` count as tracks |
| `.claude/agents/github.md` | Edit | small-ticket branch of "Merging a track back" |
| `.claude/guides/10-worktrees.md` | Edit | small paragraph, 142-146 rewritten |
| `CLAUDE.md`, `README.md`, `docs/Claude_Workflows.md` | Edit | third entry |

## Contracts
- All scripts: bash, `set -euo pipefail`, mode 100755, run from any cwd inside the target repo (the kit's copy is called by path, cwd = the repo examined); libraries found from `$(dirname "${BASH_SOURCE[0]}")` (`small-lib.sh` beside, `../hooks/hook-lib.sh`); output on stdout; 1 = refusal; 2 = usage. Read-only: no write anywhere, no `.hook-timings.log` — except `small-plan.sh`, which writes its one `plan.md` and nothing else.
- `small-paths.sh <path>…` → `ok` | first refusal, one line: `more than 6 paths: <n>` (checked first), `outside small allowlist: <path>` (not under `src/`, absolute, or containing `..`), `foundation: <path>` (`src/lib/*`, `src/main.tsx`, `src/routes/*`, `src/providers/*` + `FOUNDATIONS=( … )` array at the top of the script, bash `[[ == ]]` globs).
- `small-dispatch-check.sh <name> <path>…` → `ok` | one of, in S4 order: `main tree detached`, `main tree dirty: <path>`, `waits behind main-tree loop <slug>`, `exists: propose <name>-2`, `queued`, `waits behind small-<n>: no spec commit (failed dispatch)`, `waits behind <dir>: no Files list yet`, `waits behind <slug>: <path>`, `no test file: <path>`. Main tree = first `worktree` of `git worktree list --porcelain`. Board rows and loop slug read through `next-feature-on-clear.py`'s `board_rows`/`loop_slug` (imported by path with `importlib`, one code copy). Spec commit of `feat/small-<n>` = `git log --diff-filter=A --format=%H -n1 feat/small-<n> -- docs/specs/small/<n>.md`; merged = spec commit present and `git merge-base --is-ancestor feat/small-<n> refs/heads/<base>`.
- `small-scope.sh <name>` → `ok` | every refusal, one line each: `scope drift: <path>`, `<small-paths.sh line>` (`small-paths.sh` called **once per diff path**, so the 6-path count never hides a foundation line), `spec edited`. Base = `<spec commit>^`; diff = `git diff --no-renames --name-only <base> -- . ':!docs/specs/small/<name>.md' ':!docs/work/small-<name>/'` ∪ `git ls-files --others --exclude-standard` (same exclusions); `spec edited` = `git diff --quiet <spec commit> -- docs/specs/small/<name>.md` fails.
- `small-plan.sh small-<name>` → writes `docs/work/small-<name>/plan.md` (S6 layout), runs the self-check, and only if it passes prints `plan: <path>`, exit 0. `small-plan.sh --check small-<name>` runs the self-check alone on the plan on disk (`ok`, exit 0). Self-check failure: exit 1, prints only these lines, nothing else. The check compares, per `#### <file>` block, the spec's case lines with the plan's:
  - `no block: <file>` — a test file of `Files` with no block in the spec or the plan;
  - `reworded: <spec line>` — a test-first line whose **case id** (`U1`, `M2`…) is present in the plan's block with different text;
  - `missing: <spec line>` — a spec line absent from the plan's block byte-for-byte, and not a `reworded:` (a test-after line, which has no id, is always `missing:` + `added:` when changed);
  - `added: <plan line>` — a plan case line absent from the spec's block.
- Small spec layout (`small.md` template): `# Small: <title>`, `Pipeline: small`, `Token profile: economy`, `Base: <branch> <sha>`, then `## Objective`, `## Files` (`- <path>`), `## Contracts`, `## Vigilance`, `## Done when`, `## Test cases` (`#### <test file>` blocks; test-first `- [ ] U1 <case>`, test-after `- [ ] <case>`), `## Verify`.
- Path → layer (first match): `*.test.ts(x)` none; `types.ts`/`*.types.ts` types; `*.schema(s).ts`/`schemas.ts` schemas; `*.errors.ts` errors; `*.gateway.ts` gateway; `CWK_TDD_IMPL_RE` its layer word (`utils`, `mapper`, `repository`, `services`); `hooks.ts`/`use*.ts(x)` hooks; `*.store.ts` store; `*Form.tsx`/`*.form.tsx` forms; other `.tsx` components; else `unmapped: <path>`. Test file of a module `<dir>/<base>.<ext>` = `<dir>/<base>.test.<ext>`.

## Test plan (gate — validated by the user before EXECUTE)

All in `.claude/hooks/test-small-lane.sh`, counted harness, each case on its own fixture repo under `mktemp -d` (git init, one commit with `.gitignore` holding `.claude/worktrees/`, `package.json` and `src/` files; a `.claude/worktrees/` worktree when the case needs one). Scripts are called from the kit by path with cwd in the fixture, never copied into it (except P3). Ids are the spec's; P6, Q3, N1, N2, I1, X1, K4, K5 are added.

### Test-first — kit scripts (written and observed failing before each script)

#### `.claude/hooks/test-small-lane.sh` — `small-paths.sh`
**Core behaviour**
- [ ] P1 `src/features/a/a.utils.ts` and `src/features/a/a.utils.test.ts` give `ok`, exit 0.
**Business rules**
- [ ] P2 `package.json`, `vite.config.ts`, `.claude/hooks/x.sh`, `docs/x.md`, `CLAUDE.md`, `pnpm-lock.yaml`: each alone gives `outside small allowlist: <path>`, exit 1.
- [ ] P3 `src/lib/x.ts`, `src/routes/x.tsx`, `src/main.tsx`, `src/providers/x.tsx`, and `src/features/core/x.ts` with a scratch kit copy (`<scratch>/.claude/scripts/` holding `small-paths.sh` whose `FOUNDATIONS` holds `src/features/core/*` and `small-lib.sh`, `<scratch>/.claude/hooks/hook-lib.sh`): each gives `foundation: <path>`, exit 1.
- [ ] P4 seven `src/` paths give `more than 6 paths: 7`, exit 1; six give `ok`.
**Edge cases**
- [ ] P5 after P1-P4, the fixture's `git status --porcelain --ignored` is byte-identical to before and no `.claude/.hook-timings.log` exists.
- [ ] P6 `src/../package.json` and `/etc/passwd`: `outside small allowlist: <path>`. (added)

#### `.claude/hooks/test-small-lane.sh` — `small-plan.sh`
**Core behaviour**
- [ ] Q1 a spec (`Base: main <sha>`) with test-first blocks `src/features/a/utils.test.ts` and `src/features/a/a.mapper.test.ts` and test-after blocks `src/features/a/useA.test.ts` and `src/features/a/Card.test.tsx`, `Files` holding `src/features/a/utils.ts`, `src/features/a/a.mapper.ts`, `src/features/a/useA.ts`, `src/features/a/Card.tsx` and the four test files, `a.mapper.ts` present at `<sha>`: the plan's first line is exactly `# Plan: <Objective> (entry: docs/specs/small/a.md · research: inline (dispatch) · design: n/a)`, followed by `Pipeline: small` and `Token profile: economy`; it has every template section heading (`## Skips`, `## Write chain`, `## Parallel lots`, `## Track isolation`, `## Files`, `## Contracts`, `## Test plan`, `### Test-first`, `### Test-after`, `## Vigilance`, `## Acceptance criteria`, `## Plan critic`, `## Gate`); `## Skips` names interface and plan-critic (small lane); Write chain marks utils, mapper, hooks, components present and types, schemas, errors, gateway, repository, store, forms, DB, backend, wiring `SKIP`; test files under no layer; `a.mapper.ts` row `Edit`, the others `Create`; the test-first blocks under `### Test-first`, the test-after ones under `### Test-after`, each byte-identical; `Plan critic: skipped (small lane)`, `surviving blockers: none`; `Contract: as written`.
**Business rules**
- [ ] Q2 a generated plan whose `U1` line the fixture rewords, then `--check`: exit 1, output exactly `reworded: <spec's U1 line>`. A spec whose `Files` holds a test file with no block: exit 1, output exactly `no block: <file>`, no `plan:` line.
**Edge cases**
- [ ] Q3 a path outside the mapping (`src/features/a/data.json`) is listed `unmapped: <path>` in the Write chain. (added)

#### `.claude/hooks/test-small-lane.sh` — `small-dispatch-check.sh`
**Core behaviour**
- [ ] D1 `a` then `b` on disjoint files, each forked (worktree + spec commit) after its check: both `ok`, main tree `git status --porcelain` empty after each.
- [ ] D2 `b` sharing a file with unmerged `a`: `waits behind small-a: <path>`.
- [ ] D3 `a` merged (ff) into its base, worktree directory still present: `b` on the same file is `ok`, and `a` does not count toward the ceiling (with two other unmerged tickets, `b` is still `ok`).
- [ ] D4 three unmerged `small-*` worktrees: `queued`.
**Business rules**
- [ ] D5 `feat/small-a` exists: `exists: propose a-2`.
- [ ] D6 a dirty `src/` file → `main tree dirty: <path>`; a detached main tree → `main tree detached`; a board `IN LOOP` light line with no worktree → `waits behind main-tree loop <slug>`. A dirty `docs/product/backlog.md` (no `IN LOOP` line) and an untracked `docs/specs/x.md`: `ok`.
- [ ] D7 a fresh non-small worktree, no commit, no `plan.md`: `waits behind <dir>: no Files list yet`; with two other unmerged worktrees: `queued`.
- [ ] D8 `src/features/a/a.utils.ts` in `Files` without `a.utils.test.ts`: `no test file: src/features/a/a.utils.ts`.
**Edge cases**
- [ ] D9 a `small-a` worktree detached mid-rebase (`git -C <wt> checkout --detach`): still resolved as `feat/small-a`, in flight (`b` on a shared file waits behind `small-a`).
- [ ] D10 an `IN LOOP` light line whose worktree exists with a `docs/work/<dir>/plan.md` `## Files` table: no main-tree-loop refusal; `b` sharing a path with that table gets `waits behind <dir>: <path>`.
- [ ] D11 a `small-a` worktree whose branch has no spec commit: `b` on any file gives `waits behind small-a: no spec commit (failed dispatch)`; counted in flight.
- [ ] D12 `small-a` merged into its `Base:` branch while the main tree has another branch checked out: `a` reads merged (`b` on the same file is `ok`).

#### `.claude/hooks/test-small-lane.sh` — `small-scope.sh`
**Core behaviour**
- [ ] C1 uncommitted edits to files inside `Files` only: `ok`, exit 0.
**Business rules**
- [ ] C2 an uncommitted edit outside `Files` → `scope drift: <path>`; an untracked new file outside it → `scope drift: <path>`; `package.json` changed → a line naming `package.json`. Each exit 1.
- [ ] C3 `git mv src/lib/x.ts src/features/a/x.ts` with only the destination in `Files`: exit 1, a line naming `src/lib/x.ts`.
- [ ] C4 the spec file edited after its commit: `spec edited`, exit 1.
**Edge cases**
- [ ] C5 the ticket rebased onto a base that gained another ticket's merged file: `ok`.

#### `.claude/hooks/test-small-lane.sh` — `next-feature-on-clear.py` (added)
- [ ] N1 `source: clear` with `CLAUDE_PROJECT_DIR` = a `.claude/worktrees/small-a` directory holding a board with a `READY` line: empty stdout, exit 0; the same board in a non-small root still names the feature.
- [ ] N2 `loop_slug('docs/specs/small/a.md')` is `small-a`; `loop_slug('docs/specs/x.md')` stays `x`, `loop_slug('docs/stories/inbox/1.2.md')` stays `inbox-1.2`.

#### `.claude/hooks/test-kit-doctor.sh` (added)
- [ ] X1 a kit doc naming `.claude/worktrees/small-<name>` and `.claude/worktrees/small-*` gives no `MISSING` line from `check_shipped_paths`; a doc naming `.claude/nonexistent-x.md` still does.

### Test-after — install, contracts
#### `.claude/hooks/test-install.sh`
- [ ] I1 after install, every `.claude/scripts/*.sh` in the target is executable. (added)
#### `.claude/hooks/test-workflow-contracts.sh`
- [ ] K1 `small.md` holds exactly one `AskUserQuestion` and the four judged S2 kinds (schema change, `critical` trigger, new dependency, new screen), and S1's order: research before the draft, `small-paths.sh` and `small-dispatch-check.sh` before and after the go, the `./workflow.sh "/loop:orchestrate docs/specs/small/<name>.md"` hand-over, and no `EnterWorktree`.
- [ ] K2 `orchestrate.md`'s small branch holds no `AskUserQuestion`; it maps `docs/specs/small/`, a plan header `Pipeline: small` and a small handoff `Entry:` to the small branch, before the light rule; the branch names `small-plan.sh`, one `reviewer`, one `verifier`, `implementer` fixes, `small-scope.sh` before ship's commit.
- [ ] K3 `10-worktrees.md` holds the small-ticket paragraph and no longer says "What lives in the main tree only"; `ship.md` holds the small lines of 4, 4bis.1-3, 5, 6 and the closing line, with `merge --ff-only`.
- [ ] K4 `research.md` maps `docs/specs/small/<name>.md` to `small-<name>` before the generic spec rule; loop command count is 13. (added)
- [ ] K5 S7-S9 present (added): `orchestrate.md` names `docs/work/small-<name>/ejected`, `re-enter: /loop:spec`, `S2 trigger:`, `review FAIL:`, and on a small ticket `kit-attempts.py` without `--board`; `small.md` holds `--status` and its three entry kinds (in flight, ejected, to clean); `review.md` stage 0 falls back to the plan's `Acceptance criteria` when there is no `design.md`; `github.md` has the small-ticket merge (`merge --ff-only`, no copy of `docs/work/`); `tracks.md` holds the small-ticket dirty-tree exception and counts unmerged `small-*` worktrees; `ship.md` closing names `close this terminal` and `/loop:small --status`.

## Vigilance (carried from research)
- The slug line for `docs/specs/small/<name>.md` precedes the generic rule, and the generic `<x>` is one path segment; `loop_slug` in `next-feature-on-clear.py` agrees.
- No copy of the TDD layer words/regexes in `.claude/scripts/`: `hook-lib.sh` is sourced with `CWK_HOOK_TIMING=0`.
- The `git -C <main-tree> merge --ff-only` asks through `enforce-git-workflow.sh` only on `main`/`master`; elsewhere the default permission prompt asks. `ship.md` and `github.md` must say so, not over-claim.
- `git worktree add`, `git branch -d/-D`, plain `git worktree remove` have no hook rule (default prompts); `--force` stays denied.
- `.claude/scripts/` is guarded by no hook; `FOUNDATIONS` edits prompt only through the default permission mode.
- `token-statusline.py:42` reads `workspace.project_dir` before `CLAUDE_PROJECT_DIR`: D2 stays open for the measure.
- `orchestrate.md` Phase 0 reads the handoff body `Entry:` for a small restart.
- `test-small-lane.sh` in `NON_HOOKS` and `kit-ci.yml`; `.claude/scripts/` in the doctor probe, install chmod, `test-install.sh`.
- `test-workflow-contracts.sh:57` count 12 → 13.
- Every script read-only (P5); `small-scope.sh` covers working tree + untracked, `--no-renames`.
- Docs naming `.claude/scripts/*.sh` are written after the scripts exist (`check_shipped_paths`); docs naming `.claude/worktrees/small-…` pass only once X1's exemption is in.

## Acceptance criteria (carried from the entry artifact)
- [ ] A small ticket goes from `/loop:small <description>` to a branch ready to merge with one question (the spec go); its session asks nothing until `/loop:ship`'s merge go, apart from permission prompts that `light-permissions.md` removes.
- [ ] Three tickets on disjoint files run at once, each in its worktree and its own `./workflow.sh` session; a fourth stops, `queued`; they merge one at a time through `/loop:ship` 4bis.
- [ ] A ticket sharing a file with an unmerged ticket or worktree stops before the fork and names it; a merged ticket blocks nothing, its directory removed or not; a freshly created light worktree with no commit counts in flight; a loop running in the main tree blocks dispatch; an uncommitted board, brief or spec in the main tree does not.
- [ ] A merged small ticket's session ends with the cleanup commands and "close this terminal", never "`/clear` then `go`"; the merge ran as `git -C <main-tree> merge --ff-only`.
- [ ] The research runs before the cases are drafted; its traps are in `Vigilance`.
- [ ] Each S2 trigger refuses and proposes `/loop:spec`: `src/lib/x.ts`, `src/routes/x.tsx`, `package.json`, `.claude/x`, `vite.config.ts`, a 7th path, a described schema change.
- [ ] The main tree stays clean through dispatch: the spec exists only on `feat/small-<name>`.
- [ ] The generated `plan.md` carries every template section, a block for every test file of `Files`, cases byte-identical to the spec's; `test-writer` (test-first and after-the-code) and `implementer` run on it unchanged.
- [ ] An uncommitted edit outside `Files`, a new untracked file outside it, or a file moved out of `src/lib/` makes `small-scope.sh` refuse, at review and before ship's commit; an edited spec gives `spec edited`.
- [ ] A frozen case needing correction, a review `FAIL`, or a gate failing 3 times ejects: the reason committed in `ejected`, the re-entry and cleanup commands printed.
- [ ] A session restarted at 97 % on its handoff stays on the small branch.
- [ ] After a merge, `/loop:ship` prints the cleanup commands; `/loop:small --status` lists in-flight, ejected and to-clean tickets and offers the cleanup.
- [ ] `## Measure` filled and a keep or remove decision written under it.
- [ ] All kit tests pass, `test-small-lane.sh` included.

### Proof map (which case or gate proves each criterion)
| AC | Proof |
| --- | --- |
| 1 one question, nothing asked until merge go | K1 (one `AskUserQuestion`) + K2 (no human gate in the small branch); runtime proof **deferred to `## Measure`** ("no stop between the spec go and the merge go") — left unchecked at ship |
| 2 three at once, fourth `queued`, merged one at a time | D4, D7 (`queued`), K3 (4bis merge); concurrent sessions **deferred to `## Measure`** batch — left unchecked at ship |
| 3 overlap, merged blocks nothing, fresh worktree, main-tree loop, dirty board ok | D2, D3, D6, D7, D10, D11, D12 |
| 4 cleanup + close this terminal, `merge --ff-only` | K3, K5, N1 |
| 5 research before cases, traps in Vigilance | K1 |
| 6 each S2 trigger refuses | P2, P3, P4; schema change (judged): K1 grep on `small.md`'s judged list |
| 7 main tree clean through dispatch | D1 |
| 8 generated plan sections, blocks, byte-identical | Q1, Q2, Q3 |
| 9 scope refusals | C1-C5 |
| 10 ejection | K5 (grep only; runtime **deferred to `## Measure`**) |
| 11 restart stays on small branch | K2 (`Entry:` read in Phase 0); runtime **deferred to `## Measure`** — left unchecked at ship |
| 12 cleanup printed, `--status` | K3, K5 |
| 13 `## Measure` | **deferred** (Open question 1) |
| 14 all kit tests | every `kit-ci.yml` step + doctor `No divergence` |

## Open questions for the gate (from research, with proposed answers)
1. `## Measure` cannot run in this pass → ship Order 1-3 and 5; AC 1, 2, 10 (runtime), 11 (runtime), 13 stay unchecked, recorded at ship as the follow-up.
2. Merge ask on a non-main base → accept the default permission prompt; `ship.md`/`github.md` say "asks through `enforce-git-workflow.sh` on main/master, through the default prompt otherwise" (no hook change).
3. CI → add the `test-small-lane.sh` step to `kit-ci.yml`.
4. Harness shape → counted (`test-hooks.sh` style).

## Plan critic
- completeness: 92 (pass 1: 76)
- quality: 89 (pass 1: 70)
- surviving blockers: none (pass 1: 5 Major confirmed by verifier, rewritten; pass 2: 3 Minor, fixed)

## Gate
- 2026-10-28 go
- Contract: as written
- `## Measure` in this pass → deferred: Order 1-3 and 5 ship; AC 1, 2, 10 (runtime), 11 (runtime), 13 stay unchecked as the follow-up
- Merge ask on a non-main base → default permission prompt; `ship.md`/`github.md` say so, no hook change
- CI → `test-small-lane.sh` step in `kit-ci.yml`
- Harness → counted (`test-hooks.sh` style)
- 2026-10-28 review decisions (user): `auto-approve-config.sh` fixed in this pass (out of the spec's file list); fix batches by `implementer`, not Codex; the symlink gap and 4 Minors of that hook deferred to `docs/specs/harness-hardening.md` H5.
- To confirm at the merge — S5 tightened beyond its letter: the base is the parent of the **first** commit that added the spec (spec says `-n1`), a spec deleted after it gives `spec edited`, and the index is diffed too (security review, round 1). `small-plan.sh` still reads the working-tree spec (Q1's frozen fixture never commits it).
- Cases added after the go (pure insertions, reproduction or guard): P7, Q4, Q5, D13-D20, C6-C9, the 92-case floor; hook fixtures `auto-approve-config.sh/01-07`; `test-install.sh` ignore-block assertions.
