# Spec: Small lane, small tickets in parallel, merged one at a time
Token profile: standard (no automated path to the remote; tickets that need `critical` are refused, S2)
Depends on: `docs/specs/light-fewer-gates.md` shipped (case ids, B6). `docs/specs/light-permissions.md` is not required to work, only to remove the permission prompts inside a ticket's session (P1 allows, H7 for `kit-attempts.py`).
Replaces: `docs/specs/fast-lane.md` as the next step (parked, its decision D4 taken: local first).

## Objective
`/loop:small` takes a small, low-risk ticket from a short spec to a branch ready to merge, with one question before the work: the spec go. Up to 3 tickets run at once, each in its own worktree and session; each ends on the existing `/loop:ship`, which merges them locally, one at a time, on the user's go. Compared with the light loop it removes the interface step, the plan step (authoring, `plan-critic`, test plan gate) and the research fan-out, and runs a lighter review with its counter-review kept. TDD, hooks, gates and the merge gate are unchanged.

The value is the **batch**: several tickets advancing at once, the user needed only at the spec go and the merge go. Per ticket the token saving is expected to be modest (the repo's measures put the removed phases at about 12-20 % of a light pass, `docs/measurements/`); `## Measure` judges both.

Threat model: the guardrails stop a **mistaken** agent (a ticket that grows, a file touched outside its list, a skipped review). Nothing here reaches the remote: pushing and PRs keep their existing prompts.

## Scope
- IN :
  - **S1. Dispatch, in the main session, in this order.** The user is present for every step, so a permission prompt here costs nothing.
    1. **Research, inline, read-only**: the files the description names and their direct imports, no fan-out. Its traps become the spec's `Vigilance`; the test cases are drafted **after** it.
    2. **Draft the spec** in the session (S3), not on disk.
    3. **Eligibility** (`small-paths.sh`, S2), then **`small-dispatch-check.sh`** (S4).
    4. **One `AskUserQuestion`**: go, edit (back to 2), or route to `/loop:spec`.
    5. **On go**: both scripts re-run on the final `Files`; any refusal stops with its line.
    6. **Fork**: `git worktree add .claude/worktrees/small-<name> -b feat/small-<name>` from the main tree's `HEAD`.
    7. **Write and commit the spec in the worktree**: `docs/specs/small/<name>.md`, committed alone as the branch's first commit, via `git -C .claude/worktrees/small-<name>`. Never in the main tree, which the dispatch leaves untouched.
    8. **Setup**: `pnpm -C .claude/worktrees/small-<name> install --frozen-lockfile`; the env file is copied by the user (`protect-files` forbids it to an agent), or by `.worktreeinclude` if D1 confirms it applies. Announce it.
    9. **Hand over** the exact command that starts the ticket's session: `cd .claude/worktrees/small-<name> && ./workflow.sh "/loop:orchestrate docs/specs/small/<name>.md"`, in another terminal (`workflow.py` forwards its arguments to `claude`, so the quoted command is the session's first prompt). The main session never enters the worktree (no `EnterWorktree`), so it stays in the main tree, free for the next `/loop:small`. Started this way, `workflow.py` roots its token and restart markers on the worktree (`workflow.py:17-21`) and exports it as `CLAUDE_PROJECT_DIR`, so each ticket's session has its own markers (D2).
  - **S2. Eligibility, in two halves.** Any hit refuses and proposes `/loop:spec`.
    - **Mechanical**, `.claude/scripts/small-paths.sh <path>…` (new, read-only, no side effect): an **allowlist**. Accepted: paths under `src/`. Refused inside it, as foundations (`10-worktrees.md`): `src/lib/**`, `src/main.tsx`, `src/routes/**`, `src/providers/**`, plus any glob the project lists in the script's `FOUNDATIONS` array (edited by the user: the edit prompts in the default permission mode today, and through `light-permissions.md` P2's guarded set, `.claude/scripts/**`, once it ships). Refused: anything outside `src/` (configs, `package.json`, the lockfile, `.claude/`, `.github/`, `docs/`, root files, migrations), and more than 6 paths, test files included.
    - **Judged**, by the dispatcher on the description and the research, one line each: schema change, a `critical` trigger from `11-token-budget.md` (authorization, payment, destructive data), a new dependency, a new screen (a change to an existing screen is fine). The reviewer re-checks it on the code (S7).
  - **S3. The small spec**, `docs/specs/small/<name>.md`. First lines `Pipeline: small`, `Token profile: economy`, `Base: <branch> <sha>` (the main tree's branch and `HEAD` at the fork, written by the dispatcher), then: `Objective` (1-2 lines); `Files` (one repo-relative path per line, `- <path>`, no glob, no prose, test files included); `Contracts` (signatures, query keys, Zod types touched, or `none`); `Vigilance` (traps, or `none`); `Done when` (checkable lines); `Test cases`: one `#### <test file>` block **per test file in `Files`**: a test-first file (matching `CWK_TDD_TEST_RE`, `hook-lib.sh`) holds cases with ids in B6 format (`- [ ] U1 <case>`), a test-after file holds cases without ids (`- [ ] <case>`); `Verify` (commands). Never edited after its commit: a ticket whose scope must change is ejected (S8).
    The loop slug is `small-<name>`: worktree `.claude/worktrees/small-<name>`, branch `feat/small-<name>`, artifacts `docs/work/small-<name>/`. `/loop:research`'s slug rule (the only copy) gains this line.
  - **S4. `small-dispatch-check.sh <name> <path>…`** (new, read-only): the dispatch preconditions as one testable script, one line out, exit 0 only on `ok`. In this order:
    1. the main tree is on a branch (not detached), else `main tree detached`; and nothing the fork or the later merge could trip on is dirty: `git status --porcelain -- src/` is empty and no dirty path is in this ticket's `Files`, else `main tree dirty: <path>`. Other dirty paths are expected and pass: the loop leaves the board, the brief and new specs uncommitted in the main tree on purpose (`/loop:spec`, `/loop:ship` step 5), and the worktree forks from `HEAD`, not from the working tree;
    2. no loop running in the main tree: no board line `IN LOOP` in the main tree's working copy of `docs/product/backlog.md` whose loop slug (`/loop:research`'s rule) has no `.claude/worktrees/<slug>` directory, else `waits behind main-tree loop <slug>`. An `IN LOOP` line whose track runs in a worktree is set from the main tree before the fork (`orchestrate.md` Phase 0 step 3) and is handled by 4 and 5 like any worktree. Small tickets never have a line (S9);
    3. `feat/small-<name>` and `.claude/worktrees/small-<name>` do not exist, and `docs/specs/small/<name>.md` is not on `HEAD`, else `exists: propose <name>-2`;
    4. **tickets in flight**, by kind:
       - a `small-<n>` worktree: in flight unless `feat/small-<n>` (read by name, so a worktree detached mid-rebase still resolves) holds the spec commit **and** is an ancestor of `refs/heads/<base>`, `<base>` being the branch of its spec's `Base:` line (the merge target, whatever the main tree has checked out). A branch with no spec commit (a dispatch that failed between fork and commit) is in flight. A merged one is not, even if its directory is still there (S9 cleanup);
       - any other worktree under `.claude/worktrees/`: in flight as long as its directory exists. A light or full track has no commit until `/loop:ship` step 4, so an ancestor test would read it as merged; its cleanup at 4bis.3 removes the directory, which is its merged signal.
       Their count plus this ticket above `10-worktrees.md`'s 3: `queued`;
    5. **overlap** with each ticket in flight: a `small-*` worktree's `Files` read with `git show feat/small-<n>:docs/specs/small/<n>.md`; a `small-*` worktree with no spec commit gives `waits behind small-<n>: no spec commit (failed dispatch)`; any other worktree's `docs/work/<dir>/plan.md` `## Files` table read from that worktree's disk (`<dir>` its directory name), or `waits behind <dir>: no Files list yet` when it has none. One path in common: `waits behind <slug>: <path>`;
    6. **every logic path has its test**: a path of `Files` that `small-plan.sh` maps to a RED→GREEN layer or to hooks must have its test file in `Files`, else `no test file: <path>` (untested business logic is a Critical at review, `tests.md`, so it would only end in ejection).
    `10-worktrees.md` gains one paragraph, and its lines 142-146 ("what lives in the main tree only") are rewritten: those ignored files (`.tdd-red/`, token markers, `.kit-health.jsonl`, `.hook-timings.log`; `attempts.json` is versioned under `docs/work/` and travels with the branch) follow `$CLAUDE_PROJECT_DIR`, so they live in the worktree when its session is started there with `./workflow.sh`, and are deleted with it at `git worktree remove`. The paragraph: small tickets fork even when they are the only track and with a main tree dirty outside `src/` (condition 1, condition 4 narrowed to S4.1's check, and the cost step waived; `/loop:tracks`' "a dirty tree forks nothing" gains the same exception for small tickets: the install is announced, the pnpm store keeps it short, `## Measure` records it), they count against the ceiling while unmerged, and `/loop:tracks` counts unmerged `small-*` worktrees as tracks in flight.
  - **S5. `small-scope.sh <name>`** (new, read-only): the ticket's scope, mechanically, from inside the worktree. Reads `Files` from the committed spec. The base is **recomputed at each run** as the parent of the commit that added the spec (`git log --diff-filter=A --format=%H -n1 -- docs/specs/small/<name>.md`, then `^`): that commit is the branch's first and moves with every rebase, so a run after `/loop:ship` 4bis.1 does not report other tickets' merged files; the `Base:` sha stays for information and for `small-plan.sh`'s `Create`/`Edit`. The ticket diff is the **working tree** against that base, committed or not: `git diff --no-renames --name-only <base> -- . ':!docs/specs/small/<name>.md' ':!docs/work/small-<name>/'` plus `git ls-files --others --exclude-standard` with the same exclusions (`--no-renames` shows a moved file's source). Refuses, one line each: a path not in `Files` (`scope drift: <path>`), a path `small-paths.sh` refuses, the spec file changed since its commit (`spec edited`). Run by the reviewer at stage 1 (S7) and again by the session right before `/loop:ship` step 4's commit, so a change made after review (a gate fix, an audit bump touching `package.json`) is caught too: a refusal there ejects (S8).
  - **S6. The loop in the ticket's session**, a branch of `orchestrate.md` on `Pipeline: small`, picked in Phase 0 from the entry path `docs/specs/small/` (checked before the light rule), from the plan header's `Pipeline: small`, or from a handoff whose `Entry:` is a small spec, so a restart keeps the branch:
    - Phase 0 board steps: skipped, small tickets are off-board (S9). Phase 0.5: the session already runs in its worktree.
    - Research: done at dispatch (S1.1); the spec's `Vigilance` is its output. Interface: skipped.
    - **Plan, generated**: `.claude/scripts/small-plan.sh small-<name>` (new) reads the committed spec and writes `docs/work/small-<name>/plan.md` with every section of the plan template, so `test-writer` (its `Contracts` and its file's `Test plan` block), `implementer` (`Contracts`, its `Files` row, `Vigilance`) and orchestrate's phase order read it unchanged:
      - header `# Plan: <Objective> (entry: docs/specs/small/<name>.md · research: inline (dispatch) · design: n/a)`, then `Pipeline: small`, `Token profile: economy`;
      - `Skips`: interface, plan-critic (small lane);
      - `Write chain`: the template's chain, each layer present or `SKIP` from `Files`, first match wins: test files (`*.test.ts`, `*.test.tsx`) map to no layer; `types.ts`, `*.types.ts` → types; `*.schema.ts`, `*.schemas.ts`, `schemas.ts` → schemas; `*.errors.ts` → errors; `*.gateway.ts` → gateway; a path matching `CWK_TDD_IMPL_RE` → its RED→GREEN layer (utils, mapper, repository/services, bare or prefixed, `.ts` or `.tsx`); `hooks.ts`, `use*.ts`, `use*.tsx` → hooks; `*.store.ts` → store; `*Form.tsx`, `*.form.tsx` → forms; any other `.tsx` → components; anything else listed as `unmapped: <path>`. DB, backend, wiring: `SKIP`;
      - `Parallel lots: none — fully sequential`; `Track isolation`: the worktree and branch, shared foundations `none`;
      - `Files`: one row per path, `Create` when the path is absent at `<base-sha>`, else `Edit`, role `small ticket`;
      - `Contracts`, `Vigilance` verbatim; `Test plan`: the test-first blocks verbatim under `### Test-first`, the test-after blocks verbatim under `### Test-after`; `Acceptance criteria` = `Done when`, verbatim;
      - `Plan critic: skipped (small lane)`, `surviving blockers: none`; `## Gate`: `<date> go`, `Contract: as written`.
      It checks its own copy (every case line once, byte-identical, every test file of `Files` with a block): exit 1 prints only `missing:`, `reworded:`, `added:` or `no block: <file>`, a generator bug, never a reason to reword.
    - Execute: unchanged, on the generated plan, with two replacements on a small ticket: `kit-attempts.py` is called by its path in the worktree, without `--board/--unit`, and its "report the main-tree edit and stop" rule is replaced by S8 (exit 3 ejects); the Phase 4 frozen-case correction paragraph (`.tdd-unfrozen`, `## Gate` amendment) is replaced by S8 too: an agent that hits the freeze on a case needing correction stops, and the ticket ejects. A pure insertion (a new case, a reproduction case) still applies as written.
    - Review: S7. Ship: `/loop:ship`, with S5 run before step 4's commit, and these small-ticket lines in `ship.md`: 4bis.1 rebases onto the branch named in the spec's `Base:` line; 4bis.2 first checks `git -C <main-tree> branch --show-current` equals the `Base:` branch and no main-tree loop is running (S4.2), else stops with `main tree on <x>, not <base>: merge later`; its merge command, shown then run on the go, is `git -C <main-tree> merge --ff-only feat/small-<name>`, `<main-tree>` being the first entry of `git worktree list --porcelain` (a worktree cannot check out the base branch, which the main tree holds; `--ff-only` keeps S4.4's ancestor test true after the merge); 4bis.3, 5, 6 and the closing line as S9 says. The `github` agent runs this merge: its "Merging a track back" procedure gains a small-ticket branch (this exact command, no copy of `docs/work/` into the main tree, no cleanup: S9 prints it). That `git -C … merge` form asks through `enforce-git-workflow.sh`'s per-segment merge rule (`docs/specs/hook-git-subcommand.md`, a prerequisite of Order step 3).
  - **S7. Review, lighter, counter-review kept.** Reuses `/loop:review`'s stage 0 and dimension checklists, nothing else:
    - **Stage 0** when the ticket diff holds a `.tsx`, `.jsx`, `.css` or `.html` file (`review.md`'s UI list). With no `design.md`, the reference is the plan's `Acceptance criteria` (`review.md` step 3 gains that fallback). Its findings bypass stage 2, as in `/loop:review`.
    - **Stage 1**: one `reviewer`, dimensions `correctness`, `tests`, `security`, plus `ui` under the same UI condition, in one batch, plus three checks handed inline: `small-scope.sh` exits 0 (otherwise each line is a Major); every case has a test and every `Done when` line is met; no judged S2 trigger in the code (otherwise Major `S2 trigger: <kind>`, which ejects).
    - **Stage 2**: one `verifier`, one batch, on every stage-1 Critical and Major.
    - Confirmed Critical/Major: one `implementer` fix batch, each reproduced by a failing case first (`orchestrate.md` Phase 5), then stages 1 and 2 once more. Still confirmed: verdict `FAIL`, recorded with `kit-attempts.py fail … review`, and the ticket ejects (S8) with `reason: review FAIL: <finding>`.
    - Verdict words are `/loop:review`'s (`PASS`, `CONCERNS`, `FAIL`), printed the same way.
  - **S8. Ejection.** The ticket leaves the small lane when: a frozen test-first case needs correcting (`.tdd-unfrozen`), a path outside `Files` is needed, a size exemption is needed, a judged S2 trigger is found in the code, review ends on `FAIL`, `small-scope.sh` refuses before ship's commit, or a gate fails 3 times. The restart ceiling is not an ejection: when it is reached, `workflow.py` stops Claude and starts no session (`workflow.py:398-404`), so nothing could run one; the ticket then shows in flight in `--status`, and the user decides (eject by hand, or finish in the worktree). The session commits what it has on `feat/small-<name>` with `docs/work/small-<name>/ejected` holding the one-line reason, stops, and prints: the reason; `re-enter: /loop:spec` **in the main tree**, as a new light feature with its own slug (the small spec's `Objective`, `Files` and `Done when` given as the description; the branch stays as a reference to read, never continued); and the cleanup command for an ejected ticket (S9). An ejected worktree still counts in flight (its files are likely reworked next) until the user removes it.
  - **S9. State, without the board.** Small tickets are tickets, not features: they never get a board line, because writing the board would dirty the main tree and block the next fork. Their state is read from git, locally:

    | State | Source |
    | --- | --- |
    | in flight | `small-*` worktree, in flight by S4.4's rule |
    | ejected | same, and the branch holds `docs/work/small-<name>/ejected` |
    | failed dispatch | `small-*` worktree whose branch has no spec commit |
    | merged, to clean | `feat/small-<name>` holds the spec commit and is an ancestor of `refs/heads/<base>`, worktree directory still there |
    | shipped | branch merged, worktree removed |
    | ejected, archived | worktree removed, `feat/small-<name>` kept, holding `ejected` |
    | in-flight `Files` | `git show feat/small-<name>:docs/specs/small/<name>.md` |

    - **Cleanup.** A session cannot remove the worktree it stands in, and `ExitWorktree` removes only worktrees made by `EnterWorktree` (S1 uses `git worktree add`). So on a small ticket, `/loop:ship` 4bis.3 prints, instead of acting, to run from the main session: `git worktree remove .claude/worktrees/small-<name>` and `git branch -d feat/small-<name>`. For an ejected ticket only `git worktree remove` (its branch is unmerged and stays as a reference; deleting it later is the user's `git branch -D`).
    - **The ticket session ends there.** On `Pipeline: small`, `/loop:ship` step 6 and its closing line print, instead of the next board feature and "`/clear` then `go`": the cleanup commands, then `/loop:small --status` **to run in the main session** (the worktree's board is the fork-time copy, so the session never names a next feature from it), then "close this terminal". `next-feature-on-clear.py` stays silent when its project root is a `.claude/worktrees/small-*` directory, so a `/clear` typed there anyway starts nothing.
    - **`/loop:small --status`**, from the main session: prints the table; for every "merged, to clean" entry offers the two commands, for every failed dispatch the two commands too (its branch sits at an ancestor, so `-d` works), for every ejected entry the `git worktree remove` alone (each prompts, the user chooses). A merged worktree left on disk does not count in flight (S4.4), so forgetting the cleanup blocks nothing.
    - `/loop:ship` step 5 on `Pipeline: small`: no board line to move, said in one line.
  - **S10. Docs and contracts.** `CLAUDE.md` Workflows block (`/loop:small` as a third entry), `docs/Claude_Workflows.md`, README loop table, `10-worktrees.md` paragraph (S4), contract greps.
- OUT :
  - No push, no PR, no remote access of any kind added; no hook allow rule.
  - No board line for small tickets.
  - No change to `full`, `BUG`, light, TDD hooks, `/loop:review` (stage 0 fallback aside), `/loop:ship` (the small-ticket lines of steps 4, 4bis.1-3, 5, 6 and the closing line aside).
  - No correction of a frozen case and no continuation as light inside the small lane: it ejects.
  - No automatic conflict resolution: a rebase conflict at `/loop:ship` 4bis is handed to the user, as today.
  - Two merges at once from two ticket sessions are not prevented beyond what `/loop:ship` 4bis already says ("one integration at a time"): an existing `/loop:tracks` limit, not reopened here.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/commands/loop/{small,orchestrate,research,review,ship,tracks}.md` (`small.md` new; `research.md` for the slug line; `review.md` for stage 0's fallback; `ship.md` for the small-ticket lines of steps 4, 4bis.1-3, 5, 6 and the closing line), `.claude/agents/github.md` (small-ticket merge branch), `.claude/commands/loop/tracks.md` (condition 4 exception), `.claude/hooks/next-feature-on-clear.py` (silent in a small worktree), `.claude/scripts/small-paths.sh`, `small-dispatch-check.sh`, `small-scope.sh`, `small-plan.sh` (new), `.claude/hooks/test-small-lane.sh` (new, their tests), `.claude/guides/10-worktrees.md`, `.claude/hooks/test-workflow-contracts.sh`, `install.sh` (`.claude/scripts/*.sh` chmod and copy), `.claude/hooks/kit-doctor.py` (`.claude/scripts/` in the ignored-loop-paths probes), `CLAUDE.md`, `README.md`, `docs/Claude_Workflows.md`.

## Acceptance criteria
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

## Business logic to cover
All in `.claude/hooks/test-small-lane.sh`, on a fixture git repo.
`small-paths.sh`:
- P1 `src/features/a/a.utils.ts`, `src/features/a/a.utils.test.ts`: exit 0.
- P2 `package.json`, `vite.config.ts`, `.claude/hooks/x.sh`, `docs/x.md`, `CLAUDE.md`, `pnpm-lock.yaml`: each refused `outside small allowlist`.
- P3 `src/lib/x.ts`, `src/routes/x.tsx`, `src/main.tsx`, `src/providers/x.tsx`, a path matching a `FOUNDATIONS` glob: each refused as a foundation.
- P4 seven `src/` paths: refused, `more than 6 paths: 7`.
- P5 a run leaves the tree and `.claude/` untouched.
`small-dispatch-check.sh`:
- D1 `a` then `b` on disjoint files, each forked after its check: both `ok`, main tree clean after each.
- D2 `b` sharing a file with unmerged `a`: `waits behind small-a: <path>`.
- D3 `a` merged, its worktree directory still present: `b` on the same file is `ok`, and `a` does not count toward the ceiling.
- D4 three unmerged worktrees: `queued`.
- D5 `feat/small-a` exists: `exists: propose a-2`.
- D6 a dirty `src/` file, a detached main tree, a main-tree `IN LOOP` light line: `main tree dirty: <path>`, `main tree detached`, `waits behind main-tree loop <slug>`. A dirty `docs/product/backlog.md` and an untracked `docs/specs/x.md`: `ok`.
- D7 a freshly created non-small worktree, no commit and no `plan.md`: counted in flight, `waits behind <dir>: no Files list yet`; with two others: `queued`.
- D8 `src/features/a/a.utils.ts` in `Files` without `a.utils.test.ts`: `no test file: src/features/a/a.utils.ts`.
- D9 a `small-a` worktree detached mid-rebase: still resolved as `feat/small-a`, in flight.
- D10 an `IN LOOP` light line whose track has its worktree and a `plan.md`: not a main-tree loop; the dispatch reaches the overlap check against that `plan.md`.
- D11 a `small-a` worktree whose branch has no spec commit: `waits behind small-a: no spec commit (failed dispatch)` on a shared check, counted in flight.
- D12 `small-a` merged into its `Base:` branch while the main tree has another branch checked out: `a` reads merged.
`small-scope.sh`:
- C1 uncommitted edits inside `Files` only: exit 0.
- C2 an uncommitted edit to a file outside `Files`, an untracked new file outside it, `package.json` changed: each refused with its line.
- C3 `git mv src/lib/x.ts src/features/a/x.ts` with only the destination in `Files`: refused, naming `src/lib/x.ts`.
- C4 the spec file edited after its commit: `spec edited`.
- C5 the ticket rebased onto a base holding another ticket's merged file: exit 0.
`small-plan.sh`:
- Q1 a spec with a test-first and a test-after block, a bare `utils.ts`, a `*.mapper.ts`, a `useX.ts`, a `.tsx` component, a `*.test.tsx` and a path present at `<base-sha>`: every template section, Write chain marks utils, mapper, hooks and components present and the rest `SKIP`, test files under no layer, the existing path `Edit`, both blocks verbatim, `Pipeline: small` in the header.
- Q2 a case line the generator would alter: exit 1, `reworded:` only. A test file of `Files` with no block: exit 1, `no block: <file>`.
Contract greps:
- K1 `small.md` holds S1's order with research before the draft, the two scripts before and after the go, the `./workflow.sh` hand-over command, no `EnterWorktree`.
- K2 `orchestrate.md` maps `docs/specs/small/`, a plan header `Pipeline: small` and a small handoff entry to the small branch, before the light rule; the branch names `small-plan.sh`, one reviewer, one verifier, `implementer` fixes, `small-scope.sh` before ship's commit.
- K3 `10-worktrees.md` holds the small-ticket paragraph and no longer says the ignored files live in the main tree only; `ship.md` holds the small-ticket lines of steps 4, 4bis.1-3, 5, 6 and the closing line, with `merge --ff-only`.

## Order
1. The four scripts and `test-small-lane.sh` (P, D, C, Q cases) first; install and doctor lines.
2. `small.md` dispatch (S1-S4), the `10-worktrees.md` paragraph, the slug line in `research.md`.
3. `docs/specs/hook-git-subcommand.md` shipped (the `git -C … merge` form is gated). The `orchestrate.md` small branch (S5-S8), the stage 0 fallback in `review.md`, the `ship.md` lines, `--status` (S9).
4. `## Measure`.
5. S10.

## Measure
Same instruments as `docs/measuring-the-loop.md` (`kit-measure.py`, transcript timestamps), sessions launched with `./workflow.sh`, model and effort pinned. Per ticket, the dispatch turns and the ticket's session are summed; a ticket session runs in its worktree and may write its transcripts to another project folder, read with `--root`.
- **Isolation**: every run, light or small, paired or batch, happens in its **own local clone** at the base commit (`git clone --no-hardlinks <repo> ../measure-<lane>-<n>`, base checked out as its branch), so each run merges into its own base branch and no run sees another's merge; clones are removed after their record.
- **One span for both lanes**: from the command that starts the ticket (`/loop:small <desc>` or `/loop:spec <desc>`) to the moment its base branch reaches the ticket's last commit (the timestamp of the merge command's result: an `--ff-only` merge makes no merge commit), the light runs included through their own `/loop:ship` 4bis merge.
- **Active human time**: the number of user interventions, plus the calendar time during which at least one session waits on the user (the **union** of waiting intervals, never their sum, so parallel sessions are not double-counted). An interval runs from a turn that ends on a question or a final message to the next user message, read from each session's transcript timestamps by a throwaway script kept with the measurement, not shipped.
- **Per ticket, paired**: 3 tickets that pass S2, written down (description, base commit) before any run, each through the light loop and through the small lane from the same base, the order alternated. Records: tokens (API-price equivalent), wall time over the span, active human time, stops, permission prompts, ejections, worktree setup time (install, env file).
- **Batch**: 3 comparable tickets, **new names**, dispatched together in the small lane, against the sum of the 3 paired light runs. Wall time from the first command to the third merge commit, rebases and gate reruns included, and active human time over the whole batch.
- **Logs**: each ticket's `.claude/.hook-timings.log` and `.kit-health.jsonl` live in its worktree and go with it at cleanup: before each cleanup during the measure, run `CLAUDE_PROJECT_DIR=<worktree> .claude/hooks/hook-timings-report.sh` and copy the worktree's `.claude/.kit-health.jsonl`, both into `docs/measurements/`.
- **Keep criterion**, all of: batch wall time at most 60 % of the three light runs in sequence; batch active human time no higher than the three light runs'; per-ticket tokens no higher than light's on 2 of the 3 pairs (a saving is expected, not required); no stop between the spec go and the merge go; at most one ejection of three. Otherwise `/loop:small` is removed and small tickets go through the light loop.
- **Reopen `fast-lane.md`** (draft PR, asynchronous merge) only if the small lane is kept and merging locally one at a time becomes the measured bottleneck.

## Open decisions
- **D1. The env file in a new worktree**: does `.worktreeinclude` apply to a `git worktree add` run by the dispatcher, or only to worktrees Claude Code creates? If neither, the user copies it per ticket; persistent reusable worktrees (prepared once) are the fallback, decided after the measure.
- **D2. Per-session state, to verify before the batch measure.** Sessions started with `./workflow.sh` inside their worktree root their token and restart markers there (`workflow.py:17-21`) and export it as `CLAUDE_PROJECT_DIR`, which `hook-lib.sh` and the TDD hooks read. Verify on a real run that `.tdd-red/`, `.eslint-queue`, `.hook-timings.log`, `.kit-health.jsonl`, `attempts.json` and the token markers land in each worktree, not in the main tree; any that does not is keyed on `CLAUDE_PROJECT_DIR` before the batch.
