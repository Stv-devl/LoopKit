# Spec: Fast lane, up to a draft PR (one slot first, parallel on measured go)
Status: **parked** on 2026-10-28. D4 decided: local first, `docs/specs/small-lane.md`. Reopen only for the draft PR and asynchronous merge, if `small-lane.md`'s measure shows local merging as the bottleneck.
Token profile: critical (it builds an automated path to the remote; tickets that go through the fast lane are never `critical`, F2 excludes them)
Depends on: `docs/specs/light-fewer-gates.md` shipped (case ids, B6) and `docs/specs/light-permissions.md` shipped **with its open findings settled** (P1's allow entries; P2's guarded set as `cwk_is_guarded` in the side-effect-free `.claude/hooks/hook-guarded.sh`, `.claude/scripts/**` included; P2's "running is not writing" rule with its H7 case for `kit-attempts.py`; H8). Since 2026-10-28 that spec is split: read it as `guard-writes.md` (`cwk_is_guarded`, W1), `guard-shell.md` ("running is not writing", X9) and `light-permissions-git.md` (P1).

## Objective
`/loop:fast` takes a small, low-risk ticket from a short spec to a **draft PR**, with one stop: the spec go. The state of every fast ticket is **derived from git and GitHub**, never stored in a file, and the fast lane writes nothing to the main tree's tracked files. Review keeps its counter-review: one `reviewer`, then one `verifier` that tries to refute every Critical and Major. The user's review happens on the PR, built to be read in two minutes. Merging is always the user's, on GitHub, squash only. The gain claimed is not fewer stops than the light loop: it is fewer tokens and an asynchronous merge decision; `## Measure` decides whether it is real.

Two stages. **Stage 1** runs one ticket at a time in one persistent slot. **Stage 2** (three slots in parallel, `--sync` update part) is built only if Stage 1's measurement clears the go criterion in `## Measure`. Stage 1 alone must be worth shipping.

Threat model: the guardrails below stop a **mistaken** agent (a wrong refspec, a script edited by accident, a skipped review, a `Files` list widened mid-pass). They do not claim to stop a deliberately adversarial one. Branch protection (F1) stops any direct push to `main`; it does not stop the user's own admin token from lifting the protection, which is why every `gh api` call keeps asking.

## Scope
- IN :
  - **F1. Repo prerequisites, checked by `/loop:fast --setup` and `/loop:fast --check`**, not on every ticket (each `gh api` call asks, by `enforce-git-workflow.sh`). A missing one refuses the fast lane and names it:
    - a remote `origin` and `gh auth status` green;
    - `main` protected, read from **both** `repos/{o}/{r}/branches/main/protection` and `repos/{o}/{r}/rules/branches/main`, then each returned ruleset from `repos/{o}/{r}/rulesets/{id}`: PR required, CI checks required **with the check name of `ci.yml`'s gate job**, no direct push, and no bypass for the user's own token (`enforce_admins` on, or every ruleset with `current_user_can_bypass: never`). Without it the agent, using the user's `gh` token, can push to `main`;
    - not available (private repo on GitHub Free): one explicit line, `fast lane unavailable: branch protection required (public repo or paid plan)`;
    - `.github/workflows/ci.yml` present (installed from `templates/github/ci.yml`, see `.claude/skills/templates/ci.md`);
    - squash is the **only** allowed merge method (`allow_merge_commit` and `allow_rebase_merge` false). Otherwise a merge commit clicked on GitHub brings the branch's `merge origin/main` commits into `main`.
    - "require branches to be up to date" is reported, not required: Stage 1 works either way; with it on, a stale PR is refreshed with GitHub's own "Update branch".
    Per ticket, only the cheap part re-runs: `origin` exists and `gh auth status` is green.
  - **F2. Eligibility, per ticket, in two halves.** Any hit refuses and proposes `/loop:spec`.
    - **Mechanical half**, `.claude/scripts/fast-paths.sh <path>…` (new, read-only), repo-relative paths as arguments, exits 0 or prints each refused path with its rule. Run by the dispatcher on the draft `Files` (F4) **and** by `fast-pr.sh` on the ticket diff (F7), so a rule is never judged on a description alone. It is an **allowlist**:
      - accepted: paths under `src/`, and `e2e/**` test files; everything else refused as `outside fast allowlist` (root files such as `CLAUDE.md`, `AGENTS.md`, `workflow.sh`, `install.sh`, every config, `.claude/`, `.github/`, `shared/`, `docs/`, the lockfile, `package.json`, any migrations folder);
      - refused inside `src/`, as foundations from `10-worktrees.md`, written here as globs because that guide's table is prose: `src/lib/**`, `src/main.tsx`, `src/routes/**` (router and guards), `src/providers/**`. A project with another foundation under `src/` adds its glob to `fast-paths.sh` at `/kit:init`, never by a fast ticket (F2 refuses `.claude/`);
      - refused anywhere: a path for which `cwk_is_guarded` exits 0 (`.claude/hooks/hook-guarded.sh`, `light-permissions.md` P2), sourced, never copied here: writing it prompts, so the ticket could not keep its one stop. Sourcing that file has no side effect, so `fast-paths.sh` stays read-only;
      - more than 6 paths, test files included.
    - **Judged half**, by the dispatcher on the description and the inline research, said in one line each: schema change, a `critical` trigger from `11-token-budget.md`, a new dependency, a new screen (a change to an existing screen is fine). The reviewer re-checks it on the code (F6, stage 1).
  - **F3. Spec.** `docs/specs/fast/<slug>.md`. First lines `Pipeline: fast` and `Token profile: economy`, then sections in this order:
    - `Objective` (1-2 lines);
    - `Files`: one repo-relative path per line, `- <path>`, no glob, no brace, no prose; every path the ticket may touch, test files included. A component is its file;
    - `Contracts`: repository signatures, query keys, Zod types touched, or `none`;
    - `Vigilance`: the inline research's traps, one line each, or `none`;
    - `Done when`: checkable lines;
    - `Test cases`: one `#### <test file>` block per test-first file, cases in B6 format (`- [ ] U1 <case sentence>`), or `none` when no test-first layer is touched;
    - `Verify`: commands.
    Committed on `fast/<slug>` as the branch's **first commit**, right after the lock. That commit is the **lock commit** (the first first-parent commit of `origin/main..fast/<slug>`): its copy of the spec is the only one any check reads (F7, F10). The spec is never edited after it; a ticket whose scope must change is ejected (F6).
  - **F3b. The ticket diff**, one definition used by F6, F7 and the tests: `git -c core.quotePath=false diff --no-renames --no-ext-diff --name-only -z <base>...HEAD -- . ':!docs/specs/fast/<slug>.md' ':!docs/work/<slug>/'`, `<base>` being `git merge-base HEAD origin/main`, output read NUL-separated. `--no-renames` lists both sides of a move, so a file moved out of a foundation still shows its source. The spec and the loop's own artifacts are never part of it; the spec file is checked on its own (`spec edited after lock`). The 6-path rule and the scope rule apply to the ticket diff only.
  - **F4. Dispatcher, in the main tree, in this order:**
    1. F1 cheap part;
    2. **research, inline, read-only**: `git fetch origin`, then the files the description names and their direct imports, read at `origin/main` (`git show origin/main:<path>`), never at the main tree's checkout. No fan-out. Its traps become the spec's `Vigilance`; the test cases are drafted **after** it, so the cases the go freezes have seen the code;
    3. F2 judged half; draft the spec in the session, not on disk. **The slug is never reused**: refused, with a suffixed proposal (`<slug>-2`), when any of these holds: `git cat-file -e origin/main:docs/specs/fast/<slug>.md` or `origin/main:docs/specs/<slug>.md` succeeds; `git ls-tree -d origin/main docs/work/<slug>` prints a line; a local branch `fast/<slug>` exists (`git branch --list fast/<slug>`); `git ls-remote --heads origin fast/<slug>` prints a line; `gh pr list --state all --head fast/<slug>` returns any PR. A shipped ticket's spec and `review.md` reach `main` with the squash, so a reused slug would start from them, and F10 would read the old PR's state;
    4. `fast-paths.sh` on the draft `Files`, then the overlap check against every **loop in flight** (F4b). One path in common: stop, name the ticket it waits behind. A loop in flight with no readable file list yet: stop, `waits behind <slug>: no Files list yet`. Every such refusal is logged for `## Measure` as `queued: overlap <reason>`;
    5. one `AskUserQuestion`: go, edit, or route to `/loop:spec`. On edit, back to 3;
    6. on go: F2 (both halves) and overlap re-run on the **final** `Files`;
    7. a free slot (F5) **and** slots in use plus other loops in flight below `10-worktrees.md`'s ceiling of 3, else stop, logged as `queued: no slot` (the only refusal more slots would fix);
    8. the lock, in this order: `git worktree lock --reason fast/<slug> .claude/worktrees/fast-<n>` (fails if another session holds the slot: stop, retry step 7 once), then `git -C .claude/worktrees/fast-<n> switch -c fast/<slug> origin/main` (fails if the branch exists: another session took that slug; unlock, stop);
    9. write the spec in the slot and commit it with `git -C .claude/worktrees/fast-<n> add <spec>` and `… commit -m "<one line>"` (the lock commit); `pnpm -C .claude/worktrees/fast-<n> install --frozen-lockfile` (`origin/main` may carry a newer lockfile than the slot's last install);
    10. hand over the slot command, or `EnterWorktree` into it if this session drives the ticket. From here every command runs with the slot as working directory, with no `-C`.
    The fast lane never writes the main tree's tracked files, `docs/product/backlog.md` included (F10).
  - **F4b. Loops in flight**, each with the file list the overlap reads. A loop is in flight only while it can still change code; a shipped one never counts:
    - **fast tickets** in `IN LOOP`, `IN PR`, `BLOCKED (review)` or `ORPHAN` (F10): the lock-commit `Files`;
    - **worktree loops**: each `git worktree list --porcelain` entry that is neither the main tree nor a fast slot, whose branch is **not** an ancestor of `origin/main` (`git merge-base --is-ancestor <branch> origin/main` fails): that worktree's `docs/work/<slug>/plan.md` `## Files` table, `<slug>` taken from a branch `feat/<slug>`, `fix/<slug>` or `chore/<slug>` (`10-worktrees.md`'s branch names); any other branch name blocks with `waits behind <branch>: unknown slug`;
    - **main-tree loops**: each board line in `IN LOOP` (`docs/product/backlog.md`): `docs/work/<slug>/plan.md` `## Files`, `<slug>` derived from the line's entry artifact by `/loop:research`'s rule. No board: main-tree loops are invisible, said in one line at every dispatch.
    Merged and closed-unmerged fast branches, `EJECTED` ones, merged worktree branches and board lines in any other state do not count.
  - **F5. Slots.** `.claude/worktrees/fast-<n>`, created by `/loop:fast --setup`: `git worktree add --detach … origin/main`, install, env file, a fixed dev port per slot (`5173 + n`, so stage 0 servers never collide under `strictPort`). Env file copied once by the user (`protect-files`), or by `.worktreeinclude` if D2 confirms it applies. **Stage 1 creates `fast-1` only; Stage 2 adds `fast-2` and `fast-3`.**
    - A slot is **free** when it is not locked (`git worktree list --porcelain` shows no `locked`), its HEAD is detached, and `git status --porcelain --untracked-files=all` is empty.
    - **Release** is one script, `.claude/scripts/fast-release.sh <slug>` (new), run from the slot: refuses unless the current branch is `fast/<slug>` and the tree is clean (every change committed on `fast/<slug>` first, on `BLOCKED` and `EJECTED` too: the work in progress belongs to the branch), then `git switch --detach origin/main`, then `git worktree unlock`. Called by `fast-pr.sh` once the PR is open, and by the session when it stops on `verdict: BLOCKED` or `verdict: EJECTED`. A tree that is not clean: the slot stays locked, the script prints `DIRTY: <slot>` and exits non-zero; nothing runs `git clean` or `reset --hard`, the user decides.
    - **`10-worktrees.md` gains one paragraph**, its only exception to the fork rule: fast slots are a separate category, persistent and installed once at `--setup`, so they are exempt from condition 1 (≥ 2 tracks) and from the cost step ("a two-file story does not amortize"); they count against the ceiling of 3 while locked. `/loop:tracks` counts locked `fast-<n>` slots as tracks in flight, never forks into one, and its `N < 2 → stop` ignores them.
  - **F6. Loop in the slot**, a branch of `orchestrate.md` on `Pipeline: fast`, and the **only copy** of the fast review and ship steps. Phase 0 picks it from the entry path: `docs/specs/fast/` means `fast`, checked **before** the `light` rule, and `docs/specs/fast/` is excluded from B2's light test. Phase 0 board steps do not apply (F10); the slug is the spec's file name. The attempt ceiling runs `kit-attempts.py` without `--board/--unit`; exit 3 ejects instead of "report and stop".
    - Research: done by the dispatcher (F4.2); nothing re-runs.
    - Interface, plan-critic: skip. **`docs/work/<slug>/plan.md` is generated, not planned**, by `.claude/scripts/fast-plan.sh <slug>` (new): it reads the lock-commit spec and writes every section of the plan template, so `test-writer`, `implementer` and the TDD hooks read it unchanged:
      - header `# Plan: <Objective> (entry: docs/specs/fast/<slug>.md · research: inline (dispatcher) · design: n/a)`, `Token profile: economy`;
      - `Skips`: interface, plan-critic (fast lane);
      - `Write chain`: the template's chain, each layer present or `SKIP` by file name in `Files`, first match wins: test files (`*.test.ts`, `*.test.tsx`) map to no layer; `types.ts` → types; `*.schema.ts`, `*.schemas.ts`, `schemas.ts` → schemas; `*.errors.ts` → errors; `*.gateway.ts` → gateway; `*.utils.ts` → `[utils RED→GREEN]`; `*.mapper.ts` → `[mapper RED→GREEN]`; `*.repository.ts` or `services.ts` → `[repository RED→GREEN]`; `hooks.ts`, `use*.ts` → hooks; `*.store.ts` → store; `*Form.tsx`, `*.form.tsx` → forms; other `*.tsx` → components; any other path is listed under the chain as `unmapped: <path>`. DB, backend and wiring are always `SKIP` (F2);
      - `Parallel lots`: `none — fully sequential`; `Track isolation`: `.claude/worktrees/fast-<n>` on `fast/<slug>`, shared foundations `none` (F2);
      - `Files`: one row per spec path, `Create` when `git cat-file -e origin/main:<path>` fails, else `Edit`, role `fast ticket`;
      - `Contracts` (verbatim); `Test plan`: each `#### <test file>` block verbatim, then `### Test-after` with one block per test file of `Files` that is not test-first, listing the `Done when` lines whose text names that test file's module (same base name), and a last block `unassigned` with every `Done when` line no test file claims, checked at review's acceptance walk; `Vigilance` (verbatim); `Acceptance criteria` (= `Done when`, verbatim);
      - `Plan critic`: `skipped (fast lane)`, `surviving blockers: none`;
      - `## Gate`: `<date> go`, `Contract: as written` (the fast spec go validated it).
      Before writing, it checks its own copy: every spec case id appears once, byte-identical, no case without id. Exit 0, or exit 1 printing only `missing: <id>`, `reworded: <id>`, `added: <line>`. A failure is a bug in the generator, never a reason to reword. Committed with the next commit.
    - Execute: unchanged, TDD trio unchanged, on the generated plan.
    - **Ejection.** The ticket leaves the fast lane, mid-pass, on any of: a frozen test-first case needs correcting (it would need `.tdd-unfrozen`, a guarded path, so the one stop could not hold), a path outside `Files` is needed, a size exemption is needed, a judged F2 trigger shows up in the code, a gate's attempt ceiling is hit (`kit-attempts.py` exit 3), or `fast-pr.sh` refuses (F7). Then: `review.md` in F6b's short form committed, `fast-release.sh`, no PR, the user told to re-enter with `/loop:spec --from-fast <slug>` (F6c). Research runs before the cases are drafted (F4.2), so a case correction is the rare path, and `## Measure` counts every ejection.
    - Review, writing `docs/work/<slug>/review.md` in F6b's grammar. It reuses `/loop:review`'s stage 0 and its dimension checklists, nothing else:
      - **Stage 0**, visual pass with capture, when the ticket diff holds a `.tsx`, `.jsx`, `.css` or `.html` file (`review.md`'s UI file list). The fast branch does not use the `run` skill: it starts the server itself, in the background, with `pnpm dev --port <5173+n> --strictPort`, then drives the browser. With no `design.md`, the reference is the plan's `Acceptance criteria` (`review.md` step 3 gains that fallback). As in `/loop:review`, stage 0 and Impeccable findings bypass stage 2. Captures go to `docs/work/<slug>/captures/`, **gitignored** (`.gitignore` gains `docs/work/*/captures/`): real data never reaches the remote, and an ignored file never makes a slot dirty;
      - **Stage 1, find**: one `reviewer`, dimensions `correctness`, `tests` and `security`, plus `ui` when the ticket diff holds a `.tsx` file (existing checklists, one agent, one batch; `tests` keeps the frozen-case and RED-marker checks), plus four spec checks handed inline: every case id has a test; every `Done when` line is met; the ticket diff (F3b) is a subset of the lock-commit `Files` (otherwise Major `scope drift: <file>`) and the spec file is untouched after the lock commit (otherwise Major `spec edited after lock`); no judged F2 trigger in the code (otherwise Major `F2 trigger in code: <kind>`, which ejects instead of being fixed);
      - **Stage 2, refute**: one `verifier`, one batch, on every Critical and Major of stage 1. Survivors are confirmed; the rest listed as refuted;
      - confirmed Critical/Major: fixed by one `implementer` with the findings as its fix batch, each reproduced by a failing case first (as `orchestrate.md` Phase 5), then stages 1 and 2 run **once** more. Still confirmed: `verdict: BLOCKED` committed, `fast-release.sh`, no PR. That commit is how the main tree sees it (F10);
      - `review.md` records `reviewed: <sha>`, HEAD when the verdict is written;
      - Stage 3 step 1bis (`.claude/.kit-health.jsonl`) is skipped on this branch: the findings are already committed in `review.md`, and its `jq … >>` line would prompt.
    - **Commit rule**: every commit on `fast/<slug>` includes `docs/work/<slug>/` as it stands (`plan.md`, `review.md`, `attempts.json`, which `kit-attempts.py` writes next to the plan and git does not ignore), so the tree is clean whenever the session stops.
    - Ship: the gates of `/loop:ship` step 1, run as `.claude/scripts/ship-gates.sh` (F6d), and its acceptance walk against `Done when`, nothing else of `/loop:ship` (no 4bis, 5 or 6: the merge is on GitHub, the board is untouched). A gate fix that changes a ticket-diff path after the review re-runs stages 1 and 2 once and rewrites `review.md` (new `reviewed:`); a second such fix ejects. Then one-line commits on `fast/<slug>` via the `github` agent, then the session's main thread runs `.claude/scripts/fast-pr.sh <slug>` (never the `github` agent, F8b). Session ends.
  - **F6b. `review.md` grammar**, one field per line, in this order, parsed by `fast-pr.sh` and F10.
    Full form (`PASS`, `CONCERNS`, `BLOCKED`), every field required:
    ```
    verdict: PASS | CONCERNS | BLOCKED
    reason: <one line>                      (BLOCKED only)
    reviewed: <40-hex sha>
    confirmed: <c> critical, <M> major, <m> minor
    - <C|M|m> <path>:<line> — <one line>    (zero or more, one per confirmed finding)
    refuted: <n>
    cases: U1=<test file> U2=<test file> …  (or `cases: none`)
    scope: <d> declared, <t> touched
    capture: <path> | none
    ```
    Short form, written on ejection, possibly before any review: exactly `verdict: EJECTED` then `reason: <one line>`.
    Any other shape is malformed: `fast-pr.sh` refuses it, F10 reads it as `ORPHAN`. Mapping to `/loop:review`'s vocabulary: fast `PASS` = no confirmed finding; fast `CONCERNS` = confirmed Minors only (a confirmed Major is never CONCERNS here, unlike `/loop:review`); fast `BLOCKED` = a confirmed Critical or Major after the second round; `FAIL` is not used.
  - **F6c. Re-entry after ejection.** `/loop:spec --from-fast <slug>` reads the fast spec with `git show <lock commit>:docs/specs/fast/<slug>.md` and the ejection `reason:`, pre-fills a light spec (`Objective`; `Files` into `Front surface`; `Done when` into `Acceptance criteria`; each test case rewritten as a behaviour named in `Business logic to cover`, **without its id**, since the light spec carries no case list and ids are assigned by `/loop:plan`; the reason as the first interview point), then runs the normal interview. The new light spec takes the slug `<slug>-light` (the fast slug is never reused, F4.3). The fast branch is left for the user to delete.
  - **F6d. `ship-gates.sh`, the only copy of `/loop:ship` step 1's gates.** The block of `ship.md` step 1 (gates, both audits, the bundle-secrets scan with its `set -o pipefail` and `test -d`) moves **unchanged, comment included**, into `.claude/scripts/ship-gates.sh` (new); `ship.md` step 1 calls the script and keeps the comment that forbids changing a character of it, now pointing at the script. One allow entry replaces the builtins and the `$( … )` substitution, which no allow rule can match. A behaviour-preserving move: the light and full loops run the same checks, through one command.
  - **F7. `fast-pr.sh`, the only path to the remote.**
    - Refuses unless: current branch is exactly `fast/<slug>`; clean tree; `review.md` well-formed with `verdict: PASS` or `CONCERNS`; no ticket-diff path changed since `reviewed:` (`git diff --quiet <reviewed> HEAD -- <ticket diff paths>`); the lock commit holds `docs/specs/fast/<slug>.md` and no later commit touches it; the ticket diff (F3b) is a subset of that lock-commit `Files`; `fast-paths.sh` passes on the ticket diff; no secret in `git log -p <base>..HEAD` (`gitleaks git --log-opts=<base>..HEAD` when `gitleaks` is on `PATH`, else a fixed pattern set: private-key headers, `AKIA[0-9A-Z]{16}`, `gh[pousr]_[A-Za-z0-9]{36}`, `sk-[A-Za-z0-9]{20,}`, `xox[abpr]-`; a hit names commit and file). The verdict is written by the session itself: this refusal guards against a skipped or stale review, not a falsified one.
    - Runs `git push -u origin fast/<slug>` (no refspec, no force), `gh pr create --draft --base main --head fast/<slug> --title <t> --body-file <f>`, then `fast-release.sh <slug>`. **Safe to re-run**: the push is skipped when `git ls-remote --heads origin fast/<slug>` already equals HEAD, the PR creation when `gh pr list --state open --head fast/<slug>` already returns one. A push that succeeded before a failed `gh pr create` is finished by running the script again.
    - **On refusal or failure**, the script exits non-zero with one line `fast-pr: <reason>`. The session re-runs it once when the reason is a network or `gh` failure; any other reason, or a second failure, takes the ejection path (F6) with `reason: fast-pr: <reason>`, so the slot is released and never stays locked on a refused PR.
    - `--update <slug>` (Stage 2 only): plain `git push origin fast/<slug>` after F9's merge-in, same refusals, then releases the slot.
    - **Hook rule**, in `enforce-git-workflow.sh`, placed **before** its early exit on commands with no `git`/`gh` word (`enforce-git-workflow.sh:36`; `.claude/scripts/fast-pr.sh abc` contains neither). It returns `permissionDecision: "allow"` only when all hold:
      - the command is exactly `.claude/scripts/fast-pr.sh <slug>` (Stage 2 adds `.claude/scripts/fast-pr.sh --update <slug>`), `<slug>` matching `^[a-z0-9][a-z0-9-]{0,62}$` (no leading dash, so `--update` or `-x` is never a slug);
      - no `;`, `&`, `|`, `<`, `>`, backtick, `$(` or newline anywhere in the command;
      - **binding**: `.cwd` is non-empty (no fallback to `CLAUDE_PROJECT_DIR`), `git -C "$CWD" rev-parse --show-toplevel` ends in `.claude/worktrees/fast-<n>`, `git worktree list --porcelain` shows that worktree locked with reason `fast/<slug>`, and its current branch is `fast/<slug>`;
      - **integrity**, against `B = git -C "$CWD" merge-base HEAD origin/main` (blobs that were on protected `main`, so trusted, and stable when `origin/main` moves after the lock): `git hash-object` of `.claude/scripts/fast-pr.sh`, `fast-paths.sh` and `fast-release.sh` in the slot equal `git rev-parse B:<path>`; `git diff --quiet B -- .claude/` holds; and the hook checks **itself**: its own file (`${BASH_SOURCE[0]}`) and `hook-lib.sh` hash to `B:.claude/hooks/<file>`. Whichever copy runs (D2), a hook or script that differs from protected `main` never allows.
    - The integrity check trusts the local `refs/remotes/origin/main` and the remote's URL. So the hook also **asks** on `git update-ref` touching `refs/remotes/`, on `git remote add|set-url|rename|remove`, on `git fetch` from anything but `origin`, and on `git config` writing `remote.*`, `url.*`, `core.hooksPath` or `include.*`.
    - **Existing gap closed**: the hook's patterns match `git\s+push` (`enforce-git-workflow.sh:137`), so `git -C <dir> push` passes unasked today. The hook finds the **subcommand** before matching: it skips every option token before it (any token starting with `-`, plus the argument of `-C` and `-c`), so `git --no-pager push`, `git -P push`, `git -C x push` all read as `push`. It also asks on `git -c alias.*=…`, on a subcommand that `git config --get alias.<sub>` resolves to anything containing `push`, `send-pack` or `!`, and on `git send-pack`.
    - Anything else about push and PR is unchanged: `git push` in any form asks, `gh pr create|merge|ready` ask.
  - **F7b. `.claude/scripts/` is in the guarded set.** `.claude/scripts/**` is in `light-permissions.md` P2's list (owned there, H7), so `protect-files.sh` asks on its Write/Edit and `prevent-destructive-commands.sh` asks on every shell write marker naming it, with no new rule in either hook. Running a script (no write marker) is not caught by that guard; whether `fast-pr.sh` runs unasked is F7's hook rule alone. The integrity check of F7 stays: the guard stops a mistaken edit before it lands, the integrity check refuses to run a copy that differs from protected `main` however it got there.
    Work to do, not true today: `install.sh:639` chmods only `.claude/hooks/*.sh` and `*.py`, so add `.claude/scripts/*.sh` to it and `.claude/scripts/` to the copy; add `.claude/scripts/` to `kit-doctor.py`'s ignored-loop-paths probes (`check_ignored_loop_paths`), so a gitignored scripts folder (absent from every slot) is flagged.
  - **F8. PR body**, generated by `fast-pr.sh` from `review.md` (F6b). Exempt from the github agent's one-line-per-commit template. About 15 lines:
    - one-line summary;
    - `Cases: U1 U2 R1 covered` with their test files (`cases:`);
    - `Review: CONCERNS, 1 Minor` (the `verdict:` and `confirmed:` lines), each confirmed finding in one line, then `Refuted: n`;
    - `Scope: 4 files declared, 4 touched` (`scope:`);
    - stage 0 capture when there is one (`capture:`);
    - `Not run in fast lane: research fan-out, interface, plan-critic, review dimensions db and (without a .tsx file) ui`.
  - **F8b. The `github` agent's validation gate gains its one named exception.** `github.md` ("Anything that touches GitHub … requires the user's explicit go-ahead first … never try to bypass or pre-authorize it"): on `Pipeline: fast`, the spec-go `AskUserQuestion` is the go-ahead for exactly `git push -u origin fast/<slug>` and one draft PR, both run by `fast-pr.sh` from the session's main thread, never by the agent. Every other remote action keeps its preview and prompt. `CLAUDE.md`'s Workflows line ("`/loop:ship` and `/loop:tracks` decide only what leaves the machine") adds `/loop:fast` for a draft PR on `fast/<slug>`.
  - **F9. Sync, from the main tree.** Two commands, so a ship never inherits a prompt:
    - **Report**, `/loop:fast --status`, read-only, no prompt: `git fetch origin`; per `fast/*` branch, its state from F10, printed as one table with the PR link and the files; per slot, free, in use, or `DIRTY`; `EJECTED` with its reason and `re-enter: /loop:spec --from-fast <slug>`. `/loop:ship` step 6 runs only this report and prints its table under the next `READY` it names; with no `fast/*` branch and no `fast-<n>` slot it runs nothing, no fetch, no `gh` (a repo without the fast lane, or without a remote, sees no change).
    - **Cleanup**, `/loop:fast --sync`, user-invoked only (Stage 1):
      - the report, then `git pull --ff-only` only when the main tree is on `main` with a clean tree, else nothing, said in one line;
      - merged: delete the local branch with `git branch -D fast/<slug>` **only if** `gh pr view` says `MERGED` (after a squash, `-d` refuses: the branch is not an ancestor of `main`). `prevent-destructive-commands.sh` has no rule on `-D`, and no allow entry covers it, so each deletion prompts: accepted, `--sync` is user-invoked. A leftover branch would read as `ORPHAN`;
      - closed unmerged: printed as `BLOCKED — PR closed`, branch kept for the user to decide, excluded from overlap.
    - **Update part** of `--sync` (Stage 2): the head of queue only, the oldest open fast PR, gets `git merge origin/main` in a free slot (no rebase, no force push), gates re-run, `fast-pr.sh --update`. No free slot: deferred, said so. Remote commits not in the local branch (a suggestion applied on GitHub) are pulled first with `--ff-only`; failure: `BLOCKED — remote commits on PR`. Conflict: `git merge --abort`, `BLOCKED — conflict: <file>`. Red gate: `BLOCKED — gates after update: <gate>`. **Never an automatic conflict resolution.** Other PRs: `stale` in the report. With GitHub's "require branches to be up to date", every merge makes the others unmergeable; this works only if the user merges oldest first, which the report states.
  - **F10. State derived, not stored.** Fast tickets are **not board lines**: `docs/product/backlog.md` holds features and stories, the fast table holds tickets. Writing them to the board would leave the main tree dirty (`/loop:tracks` refuses to fork it) with no branch ever committing it, since slots fork from `origin/main`. Rows are evaluated **top to bottom, first match wins**:

    | State | Source of truth |
    | --- | --- |
    | `SHIPPED` / `BLOCKED — PR closed` | `gh pr list --state all --head fast/<slug> --json state,headRefOid` returns a `MERGED` / `CLOSED` PR whose `headRefOid` is the local branch tip or an ancestor of it (F4.3 already refuses a reused slug; this check makes the table robust anyway) |
    | `IN PR` | same call, an `OPEN` PR, draft or ready |
    | `EJECTED` | `git show fast/<slug>:docs/work/<slug>/review.md` is F6b's short form |
    | `BLOCKED (review)` | same file, full form, says `verdict: BLOCKED` |
    | `IN LOOP` | `fast/<slug>` checked out in a slot (`git worktree list`) |
    | `ORPHAN` | none of the above (a session died between the lock and the PR, or a malformed `review.md`); reported, counts in overlap, the user decides |
    | in-flight `Files` | the lock commit's `docs/specs/fast/<slug>.md` (F3), never the branch tip |
    | the lock | `git worktree lock` on the slot, then `git switch -c fast/<slug>` |
    | history | `gh pr list --state merged --search "head:fast/"` |

    Branches are shared by every worktree of a repo, so every session sees the same state, with no state file, no dirty main tree, no concurrent writes. `/loop:product`'s state machine (the only copy) gains one paragraph: fast tickets are off-board, their states are derived, defined by this table.
  - **F11. Permissions: the command inventory.** The **planned prompts** of a fast ticket are exactly one: the spec-go `AskUserQuestion` (F4.5). Every command run between the spec go and the PR is listed here with the entry that allows it; a command not in this table is a defect, found by the zero-prompt acceptance run. The rows citing P1 hold once `light-permissions.md` ships (Order step 0); `.claude/settings.json` does not carry them today. Built by walking, line by line, every step the fast branch runs, the reused `/loop:ship` step 1 (F6d) and `/loop:review` stage 0 included. Entries marked *new* go into `.claude/settings.json`; Stage 1 writes the slot entries for `fast-1` only, as literals, and Stage 2 adds `fast-2` and `fast-3` the same way.

    | Where | Command, exact form | Allowed by |
    | --- | --- | --- |
    | dispatcher | `git remote get-url origin`, `gh auth status` | *new*, exact |
    | dispatcher | `git fetch origin` | *new*, exact |
    | dispatcher | `git show <rev>:<path>`, `git rev-parse …`, `git log …`, `git diff …` | existing `git show *`, `git rev-parse *`, `git log *`, `git diff *` |
    | dispatcher | `git rev-list --first-parent --reverse origin/main..fast/<slug>` | *new* `git rev-list *` (read-only) |
    | dispatcher | `git branch --list fast/*`, `git branch --list fast/<slug>` | *new* `git branch --list fast/*` |
    | dispatcher | `git cat-file -e origin/main:<path>`, `git ls-tree -d origin/main <path>` | *new* `git cat-file -e *`, `git ls-tree -d origin/main *` |
    | dispatcher, slot | `git ls-remote --heads origin fast/<slug>` | *new* `git ls-remote --heads origin *` |
    | dispatcher | `git worktree list --porcelain` | *new*, exact |
    | dispatcher | `git merge-base --is-ancestor <branch> origin/main` | *new* `git merge-base *` |
    | dispatcher | `gh pr list …`, `gh pr view …` | *new* `gh pr list *`, `gh pr view *` |
    | dispatcher | `.claude/scripts/fast-paths.sh <path>…` | *new* `.claude/scripts/fast-paths.sh *` |
    | dispatcher | `git worktree lock --reason fast/<slug> .claude/worktrees/fast-1` | *new* `git worktree lock --reason *` |
    | dispatcher | `git -C .claude/worktrees/fast-1 switch -c fast/<slug> origin/main` | *new* `git -C .claude/worktrees/fast-1 switch -c *` |
    | dispatcher | `git -C .claude/worktrees/fast-1 add <path>`, `git -C .claude/worktrees/fast-1 commit -m "<one line>"` | *new* `git -C .claude/worktrees/fast-1 add *`, `… commit -m *` |
    | dispatcher | `pnpm -C .claude/worktrees/fast-1 install --frozen-lockfile` | *new*, exact |
    | dispatcher | Write of the spec under `.claude/worktrees/fast-1/` | `acceptEdits` (P1) |
    | dispatcher | `EnterWorktree` into the slot | tool permission, allowed once at `--setup`, listed in `fast.md` |
    | slot | `.claude/scripts/fast-plan.sh <slug>`, `.claude/scripts/fast-release.sh <slug>` | *new* `… fast-plan.sh *`, `… fast-release.sh *` |
    | slot | `pnpm test:run …` (`test-writer`, `implementer`, RED/GREEN runs) | existing |
    | slot, ship | `.claude/scripts/ship-gates.sh` (every gate, both audits, the bundle-secrets scan, F6d) | *new*, exact |
    | slot | `python3 .claude/hooks/kit-attempts.py fail …` / `pass …` | *new* `python3 .claude/hooks/kit-attempts.py fail *`, `… pass *`; P2 must pass it (H case in `light-permissions.md`) |
    | slot | `git add <paths>`, `git commit -m "<one line>"`, `git status …`, `git branch --show-current` | P1, existing |
    | slot, stage 0 | `pnpm dev --port 5174 --strictPort`, background (F6, no `run` skill) | *new*, exact |
    | slot, stage 0 | `pnpm dlx impeccable detect --json <files>` | *new* `pnpm dlx impeccable detect --json *` |
    | slot, stage 0 | `/impeccable critique`, `/impeccable audit` (skills) | Skill tool, allowed once at `--setup`, listed in `fast.md` |
    | slot, stage 0 | the browser tools stage 0 drives | allowed once at `--setup`, listed in `fast.md` |
    | slot | `.claude/scripts/fast-pr.sh <slug>` | F7's hook rule (allow) |

    `gh pr list|view` are not matched by the hook's `gh pr` ask list; `gh api` stays asked (F1 runs only at `--setup`/`--check`). Commands run inside `fast-pr.sh` and `fast-release.sh` are not seen by the permission system.
  - **F12. Docs and contracts.** `CLAUDE.md` Workflows block, `docs/Claude_Workflows.md`, README loop table, contract greps. Written at the end of Stage 1 for one slot, updated by Stage 2 if it ships.
- OUT :
  - No automatic merge, no auto-merge flag, no `gh pr ready`.
  - No rebase and no force push anywhere in the fast lane.
  - No conflict resolution by an agent.
  - No state file for fast tickets, no fast line on the board.
  - No correction of a frozen case inside the fast lane: it ejects.
  - No automatic cleanup of a dirty slot.
  - No change to `full`, `BUG`, light review, Codex routing. TDD hooks unchanged, except the marker keying D2 may require. `/loop:ship` changes only in step 1 (the same gates, moved into `ship-gates.sh`, F6d) and step 6 (the read-only report).
  - Stage 2 is out of this spec's delivery until `## Measure` gives the go.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/commands/loop/{fast,orchestrate,product,tracks,ship,review,spec}.md` (`fast.md` new; `review.md` only for stage 0's fallback reference; `spec.md` for `--from-fast`; `ship.md` for steps 1 and 6), `.claude/scripts/fast-pr.sh`, `fast-paths.sh`, `fast-plan.sh`, `fast-release.sh` and `ship-gates.sh` (new) and their tests, `.gitignore` (`docs/work/*/captures/`), `.claude/hooks/enforce-git-workflow.sh` and fixtures, `.claude/hooks/hook-lib.sh` (guarded set) and the `protect-files.sh`/`prevent-destructive-commands.sh` fixtures, `.claude/hooks/kit-doctor.py`, `install.sh`, `.claude/hooks/fixtures/_harness` (a `fast/x` branch, a lock commit, an `origin/main` ref that can move past the merge-base, a lockable slot at `.claude/worktrees/fast-1`), `.claude/settings.json`, `.claude/agents/{github,reviewer,verifier}.md`, `.claude/guides/10-worktrees.md`, `.claude/hooks/test-workflow-contracts.sh`, `CLAUDE.md`, `README.md`, `docs/Claude_Workflows.md`. **D2-dependent**, in Stage 1 if D2 finds the current keying unsafe with one slot plus one main-tree loop, else in Stage 2: `hook-lib.sh`, `token-statusline.py`, `tdd-prove-red.sh`, `tdd-require-red.sh`, `tdd-freeze-tests.sh`, `eslint-check.sh`, `eslint-batch.sh`.

## Acceptance criteria
Stage 1:
- [ ] Each F1 prerequisite missing refuses the fast lane at `--setup`/`--check` and names it, a ruleset the user can bypass included; a private Free repo gets the explicit unavailable line.
- [ ] Each F2 trigger refuses and proposes `/loop:spec`; the mechanical ones refuse from `fast-paths.sh` both at dispatch and in `fast-pr.sh`, including `CLAUDE.md`, `.claude/scripts/fast-pr.sh`, `docs/product/backlog.md`, `vite.config.ts`, `src/routes/x.tsx`, a file moved out of `src/lib/`, and a 7th path.
- [ ] A ticket of 6 paths, with its spec, `plan.md` and `review.md` committed, passes the scope rule and the 6-path rule; a 7th source path refuses.
- [ ] The inline research runs before the cases are drafted, and its traps appear in the spec's `Vigilance`.
- [ ] A fast ticket sharing a path with a loop in flight (F4b: another fast ticket, an unmerged worktree branch's `plan.md`, a main-tree `IN LOOP` line's `plan.md`) stops before the lock and names it; a loop in flight with no `plan.md` yet blocks with `no Files list yet`. A feature already shipped (its `docs/work/<slug>/plan.md` still on disk, its board line `SHIPPED`, its branch merged) blocks nothing and takes no place under the ceiling.
- [ ] An edit changing `Files` after the first overlap check is re-checked before the lock.
- [ ] A slug already used (its spec or `docs/work/<slug>/` on `origin/main`, a local or remote `fast/<slug>`, any past PR on `fast/<slug>`) is refused at dispatch with a suffixed proposal; a new ticket never reads an old PR's state.
- [ ] `fast-pr.sh` refusing, or failing after the push, never leaves the slot locked: one re-run finishes a partial run without a second push or PR, any other refusal ejects with `reason: fast-pr: <reason>`.
- [ ] `/loop:ship` step 1 runs `ship-gates.sh` and reports the same results as before the move, on the light and full loops.
- [ ] A stage 0 capture is written under `docs/work/<slug>/captures/`, never committed, and leaves the slot clean.
- [ ] Two sessions racing on one slug: the second `switch -c` fails, it stops. Two sessions racing on one slot with different slugs: the second `git worktree lock` fails, it stops.
- [ ] A second ticket with `fast-1` in use stops, queued.
- [ ] An eligible ticket, UI change included, goes from the spec go to an open draft PR with no prompt other than the spec go, recorded on a real run.
- [ ] `docs/specs/fast/<slug>.md` enters orchestrate as `Pipeline: fast`, never `light`.
- [ ] The generated `plan.md` carries every section of the plan template with the values F6 lists, and `test-writer`, `implementer` and the TDD hooks run on it unchanged; review and ship run as `orchestrate.md`'s fast branch.
- [ ] After the PR, the slot is unlocked, detached and clean, and the next ticket can take it; a slot left with uncommitted changes is reported `DIRTY` and not reused.
- [ ] A diff touching a path outside the lock-commit `Files` produces a confirmed Major `scope drift` and no PR; a spec edited after the lock commit produces `spec edited after lock` and no PR, even if the new `Files` covers the diff.
- [ ] A code commit after `reviewed:` makes `fast-pr.sh` refuse; a gate fix after review re-runs stages 1 and 2 and rewrites `reviewed:`.
- [ ] A frozen case needing correction, a judged F2 trigger found in the code, or a gate's third failure leaves F6b's short form, a released slot, no PR; `/loop:fast --status` shows `re-enter: /loop:spec --from-fast <slug>`, and that command pre-fills a light spec from the fast one.
- [ ] A finding refuted by the `verifier` shows under `refuted` and does not block; one confirmed twice leaves `verdict: BLOCKED`, a released slot and no PR; confirmed findings are fixed by `implementer`, not inline.
- [ ] `fast-pr.sh`, `fast-paths.sh`, `fast-release.sh`, `enforce-git-workflow.sh` or `hook-lib.sh` differing from the merge-base, a command run outside a locked fast slot or on another branch, `origin/main` moved by `update-ref`, or the remote URL rewritten by `git config`: the hook asks instead of allowing. `origin/main` advanced by a normal fetch after the lock, `.claude/` changed there: the hook still allows.
- [ ] `git -C <dir> push …`, `git --no-pager push`, `git -P push` and a `push` alias ask, like `git push`.
- [ ] A secret pattern in any commit of the branch makes `fast-pr.sh` refuse and name the commit and file.
- [ ] Writing `.claude/scripts/fast-pr.sh`, by Write/Edit or by any shell write marker, prompts; running it does not trigger that guard.
- [ ] `github.md` and `CLAUDE.md` carry the F8b exception; `10-worktrees.md` and `/loop:tracks` carry the fast-slot paragraph (F5).
- [ ] `/loop:fast --status` and `/loop:ship` step 6 show every fast ticket's state and every slot's with no prompt and no write; `--sync` deletes merged branches only, fast-forwards a clean `main` only; a PR marked ready still reads `IN PR`.
- [ ] A branch with no slot, no PR and no verdict shows as `ORPHAN` and blocks overlapping tickets.
- [ ] `## Measure` filled with Stage 1's numbers and a go or no-go written under it.
- [ ] All kit tests pass.
Stage 2 (only on go):
- [ ] Three slots in parallel: distinct dev ports; token, RED, `.tdd-unfrozen`, eslint-queue and hook-timing files do not cross sessions (D2).
- [ ] Four tickets, or three plus one other loop in flight: the last stops, queued.
- [ ] `fast-pr.sh --update` allowed by the hook; `--sync` update part merges `origin/main` into the head of queue only, and on conflict aborts and pushes nothing.

## Business logic to cover
Hook fixtures, Stage 1 (harness provides `fast/x` with a lock commit, `origin/main`, a slot `.claude/worktrees/fast-1` locked with reason `fast/abc` on `fast/abc`):
- G1 `.claude/scripts/fast-pr.sh abc` from the slot, scripts and hook identical to the merge-base: allow (the rule fires although the command has no `git`/`gh` word).
- G2 `.claude/scripts/fast-pr.sh abc && git push origin main`, `… abc & git push origin HEAD:main`: ask.
- G3 `.claude/scripts/fast-pr.sh 'a;b'`, `.claude/scripts/fast-pr.sh -x`, `.claude/scripts/fast-pr.sh --update abc` (Stage 1): ask.
- G4 `git push origin fast/x:main`: ask.
- G5 `git push origin +fast/x`: ask.
- G6 `git push` with no argument: ask.
- G7 `git push --delete origin fast/x`, `--all`, `--mirror`, `--tags`: ask.
- G8 `gh pr create --draft` typed directly: ask.
- G9 `gh pr merge`, `gh pr ready`: ask.
- G12 G1 with the slot's `fast-pr.sh` differing from the merge-base: ask; same with `fast-paths.sh` and `fast-release.sh`.
- G13 G1 with any other diff under `.claude/` against the merge-base: ask.
- G14 `git update-ref refs/remotes/origin/main <sha>`: ask.
- G15 `git remote set-url origin /tmp/x`, `git remote add evil …`: ask.
- G16 `gh pr list --head fast/x`, `gh pr view 3 --json state`: pass (no ask from the hook).
- G17 Write or Edit on `.claude/scripts/fast-pr.sh`: `protect-files` asks.
- G18 `cp x .claude/scripts/fast-pr.sh`, `sed -i s/a/b/ .claude/scripts/fast-pr.sh`, `echo x >> .claude/scripts/fast-pr.sh`, `rm .claude/scripts/fast-pr.sh`: `prevent-destructive-commands` asks each.
- G19 `.claude/scripts/fast-pr.sh abc`: `prevent-destructive-commands` passes (the decision is G1's).
- G20 `git config remote.origin.url /tmp/x`, `git config url.x.insteadOf y`, `git config core.hooksPath x`: ask.
- G21 G1 with the running `enforce-git-workflow.sh` or `hook-lib.sh` differing from the merge-base: ask.
- G22 G1 after `origin/main` advanced past the merge-base with a `.claude/` change: allow.
- G23 `python3 .claude/hooks/kit-attempts.py fail docs/work/abc/plan.md test "x"`: `prevent-destructive-commands` passes.
- G24 `git -C /tmp/x push origin main`, `git -c a=b push`, `git --git-dir=/tmp/x/.git push`: ask.
- G25 G1 from the main tree, from an unlocked slot, from a slot locked for `fast/other`, or with an empty `.cwd`: ask.
- G26 `git --no-pager push origin main`, `git -P push`, `git -c alias.p=push p`, `git p` with `alias.p=push` in the fixture config, `git send-pack x`: ask.
Hook fixtures, Stage 2:
- G10 `.claude/scripts/fast-pr.sh --update abc`: allow.
- G11 `.claude/scripts/fast-pr.sh --update 'a;b'`: ask.
Path tests (`fast-paths.sh`):
- P1 `src/features/a/a.utils.ts`, `src/features/a/a.utils.test.ts`: exits 0.
- P2 `CLAUDE.md`, `.claude/hooks/x.sh`, `install.sh`, `docs/product/backlog.md`, `pnpm-lock.yaml`, `supabase/migrations/1.sql`: each refused `outside fast allowlist`.
- P3 `src/lib/x.ts`, `src/routes/x.tsx`, `src/main.tsx`: each refused as a foundation.
- P4 a path for which `cwk_is_guarded` exits 0 (`.claude/scripts/a.sh`): refused, the rule naming `hook-guarded.sh`; the run leaves `.claude/.hook-timings.log` unchanged.
- P5 seven valid paths: refused, `more than 6 paths: 7`.
Script tests (`fast-pr.sh`, `fast-release.sh`, `gh` stubbed):
- S1 on `feat/x`: refuses.
- S2 dirty tree: refuses.
- S3 ticket diff outside the lock-commit `Files`: refuses, names the file.
- S4 `review.md` with a confirmed Major: refuses.
- S5 eligible: push and draft PR run, body holds cases, review, scope, not-run.
- S6 after S5: slot unlocked, HEAD detached on `origin/main`, tree clean.
- S7 spec edited in a later commit, its new `Files` covering the diff: refuses, `spec edited after lock`.
- S8 ticket diff holding `vite.config.ts` while `Files` lists it: refuses, from `fast-paths.sh`.
- S9 `review.md` missing `scope:` or `reviewed:`, or in the short form: refuses.
- S10 six `Files` paths touched, plus the spec, `plan.md` and `review.md` committed: passes.
- S11 a code commit after `reviewed:`: refuses, `changed since review: <path>`.
- S12 `git mv src/lib/x.ts src/features/a/x.ts` with only the destination in `Files`: refuses, naming `src/lib/x.ts`.
- S13 a commit adding then removing `-----BEGIN PRIVATE KEY-----`: refuses, naming the commit.
- S14 `fast-release.sh` on a dirty tree: exits non-zero, `DIRTY: fast-1`, slot still locked.
- S15 `gh pr create` stubbed to fail after a successful push: exits non-zero `fast-pr: gh pr create failed`; re-run with `gh` working: no second push (remote already at HEAD), one PR created, slot released.
- S16 re-run when the PR already exists: no push, no `gh pr create`, slot released, exit 0.
Slug tests (dispatcher's slug check, `git`/`gh` stubbed):
- L1 `docs/specs/fast/abc.md` on `origin/main`, or `docs/work/abc/` there, or a merged PR on `fast/abc`, or a remote `fast/abc`: `abc` refused, `abc-2` proposed.
Gates test:
- R1 `ship-gates.sh` on a fixture repo with a `VITE_SERVICE_ROLE_KEY` in `src/`: the scan reports it; with no `src/`: prints `SCAN NOT RUN: no src/`; its gate list is byte-identical to `ship.md` step 1's block before the move.
Generator tests (`fast-plan.sh`):
- Q1 a fast spec with two `#### <test file>` blocks, a `*.utils.ts`, a `*.tsx`, a `*.test.tsx`, a `*.errors.ts` and an existing path in `Files`: the generated `plan.md` holds every template section with F6's values (Write chain marks utils, errors and components present, the rest `SKIP`, the test file under no layer; the existing path is `Edit`), and its cases are byte-identical to the spec's.
- Q2 a spec whose case line the generator would alter (a fixture forcing a rewrap): exit 1, `reworded: <id>` only.
Contract greps:
- K1 `fast.md` holds F1, F2 (both halves, the allowlist, `fast-paths.sh`, the guarded set read from `hook-lib.sh`), the F4 order with research before the draft and the re-check, F4b's three sources of loops in flight, "never resolve a conflict", the ejection triggers, the single planned prompt.
- K2 `/loop:product`'s state machine names fast tickets as off-board and derived, pointing to F10's table.
- K3 `orchestrate.md` Phase 0 maps `docs/specs/fast/` to `Pipeline: fast` before the light rule; its fast branch has stage 1 and stage 2, one batch each, fixes through `implementer`, `fast-plan.sh`, and F6b's literal field names `verdict:`, `reason:`, `reviewed:`, `confirmed:`, `refuted:`, `cases:`, `scope:`, `capture:`.
- K4 `github.md` names the fast exception with `fast-pr.sh` and `fast/<slug>`; `10-worktrees.md` and `tracks.md` name fast slots; `ship.md` step 6 calls `/loop:fast --status`, never `--sync`.

## Order
Stage 1:
0. `light-permissions.md` shipped with its open findings settled, `hook-guarded.sh` and `cwk_is_guarded` in place, H7 and H8 green; D2 researched and written in this spec's research (it decides whether the marker keying joins Stage 1).
1. `fast-paths.sh`, `fast-release.sh`, F6d `ship-gates.sh` (R1), F7 script and hook with binding, integrity (merge-base, self-check), ref and config checks, the subcommand parsing (G24, G26), install and doctor; fixtures G1-G9, G12-G26, P1-P5, S1-S16, L1 first.
2. F1, F2, F11 (the table's *new* entries), F8b.
3. F10 derived state, F4/F4b dispatcher with inline research, F5 with `fast-1` only (lock, release, `DIRTY`, the `10-worktrees.md` paragraph), F6 with `fast-plan.sh` (Q1-Q2), the `Pipeline: fast` detection, ejection and F6c, F6b, F8.
4. F9 report and `--sync` cleanup, then F12 for one slot.
5. `## Measure`. Go or no-go written.
Stage 2, only on go:
6. `fast-2`, `fast-3` with ports and their F11 literals, D2's marker keying if not already done; 3 real tickets in parallel.
7. F9 update part, `--update` with G10-G11, F12 updated.

## Measure
Same instruments as `docs/measuring-the-loop.md` (`kit-measure.py --out docs/measurements/fast-lane-<n>.md`, transcript timestamps), sessions launched with `./workflow.sh`, model and effort pinned, no model switch mid-run. Per ticket, the dispatcher session and the slot session are summed (`kit-measure.py --session` on each).
- **Same tickets through both lanes.** Three tickets that pass F2, chosen and written down (description, base commit) before any run. Each runs through the light loop (`/loop:spec`) and through `/loop:fast` from the **same base commit**, the light run in a scratch worktree discarded afterwards, the order of the two lanes alternated from one ticket to the next. A paired comparison, ticket by ticket, so ticket-to-ticket variance does not swamp the effect.
- **Endpoints.** Primary: the branch ready to integrate (light: `/loop:ship` step 4's commit, before the merge go; fast: the draft PR opened). Secondary, recorded for both: merged on `main`, CI wall time, PR or 4bis reading time.
- **Records per run**: tokens (API-price equivalent), wall time to each endpoint, **active human time** (time spent answering or reading, from transcript timestamps), stops, permission prompts, ejections and blocks (an ejected or blocked fast ticket counts at its full cost plus its light rerun), `queued: overlap` and `queued: no slot` refusals, counted apart (F4.4, F4.7). A slot session's transcripts may live in another project folder than the dispatcher's (D2): `kit-measure.py` is run with `--root` on each folder, and active human time is read from transcript timestamps (gaps between an `AskUserQuestion` or a final message and the next user turn), since `kit-measure.py` has no such column.
- **Go criterion for Stage 2**, all of: fast tokens at most 70 % of light tokens on at least 2 of the 3 pairs; fast active human time no higher than light's on at least 2 of the 3 pairs; no prompt other than the planned one (F11) between spec go and PR; at most one fast ticket of three ejected or blocked; and at least one `queued: no slot` refusal over the Stage 1 period, since parallel slots only pay when tickets wait for a slot (an overlap refusal is not fixed by more slots).
- **Revert criterion for Stage 1**: fast tokens above 90 % of light on 2 of the 3 pairs, or a defect found in a merged fast PR that a dropped dimension (`db`, or `ui` on a ticket without `.tsx`) would have caught. Detection: one `/audit:part` on the 3 tickets' squash commits, run once after the third merge. Then `/loop:fast` is removed and small tickets go through the light loop.

## Open decisions
- **D2. Per-slot isolation, settled in research before step 1:**
  - does `.worktreeinclude` apply to a `git worktree add` run by the dispatcher, or only to worktrees Claude Code creates itself;
  - with a session entered by `EnterWorktree`, or launched inside a slot, is `CLAUDE_PROJECT_DIR` the slot or the main tree? `token-statusline.py` writes its markers under `<project>/.claude/`, `tdd-prove-red.sh` writes `$PROJECT_DIR/.claude/.tdd-red`, `eslint-check.sh:37` appends to `.claude/.eslint-queue` and `eslint-batch.sh` claims it whole, `hook-lib.sh:37` logs to `.claude/.hook-timings.log`, `tdd-freeze-tests.sh` and `tdd-require-red.sh` read `.claude/.tdd-unfrozen` and compute paths against that root. These are untracked files, so "writes nothing to the main tree's tracked files" holds either way; but if it is the main tree, sessions share all of them: session A at 95% stops session B's agents, RED markers mix, one session lints another's queue. Fix by keying them on the worktree root (`git rev-parse --show-toplevel`). The keying joins Stage 1 unless D2 shows the current keying is safe with one slot plus one main-tree loop (Front surface, D2-dependent);
  - which copy of the hooks runs in a slot session: the slot's or the main tree's. F7's self-check makes the allow safe either way; the answer still decides which copy enforces the TDD hooks in the slot.
- **D3. Review on GitHub too** (Claude Code GitHub Action commenting the PR), or the in-slot review alone. In-slot alone first; measure PR reading time before adding the Action.
- **D4. Order and shape, deferred by the user on 2026-10-28** (second audit, Majors 4 and 5; raised again, as Minors, by the third):
  - measure before building: the paired measurement of `## Measure`, run with the fast lane's settings by hand through the existing loop (interface skipped, plan-critic skipped, one reviewer plus a verifier, push and draft PR typed by hand), needs no new code and could precede step 1;
  - a local `Pipeline: small` on `/loop:orchestrate` (`fast-paths.sh` eligibility, plan-critic skipped, local merge with one go) may capture most of the token gain without the remote machinery; the remote fast lane would then be justified only by asynchronous merge and parallelism.
