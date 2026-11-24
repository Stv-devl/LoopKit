# Plan: kit fixes from the EcoCrew agent-ia-2.2 / 4.4 runs   (entry: docs/specs/agent-ia-trial-fixes.md · research: docs/work/agent-ia-trial-fixes/research.md · design: n/a)
Token profile: critical
Base: 1c3ddb27fd12864d7f92bfc41e337172a07124ba

## Skips
- DB, Backend, Front, Wiring, UI tests : SKIP — kit hooks, scripts and prompts only (INTERFACE SKIP).
- Test-first TS/Python layers : none — kit tests are shell fixture suites under `.claude/hooks/`, outside the
  freeze matcher. Each step is still test-first: its cases are written and observed red before the code.
- Worktree support variant (spec item 2, preferred) : SKIP for the fallback — see answer 1.

## Proposed answers to research's open questions
1. Worktree variant → **detect + refuse** (the user's fallback "si compliqué"): support would touch the settings
   allow-list, every prompt that runs a kit script by relative path, `kit-audit-surface.py:153`,
   `kit-pr-assets.py:317`, the per-tree `.tdd-unfrozen`/marker split, and still could not lift Claude Code's
   native cross-tree write refusal. (Cases DW1-DW4, WT1-WT3, IW1-IW2.)
2. Copy-back → tracked `docs/` travel with the branch; story/board are step-5 main-tree writes by design. The
   remaining check: ship `4bis-local`, before `git worktree remove`, lists files under `docs/` that are
   untracked-or-modified (refuse, name them) and the ignored `docs/work/<slug>/` files that will be lost
   (handoff, pr-body: named, not refused — they are the pass's trace, the PR carries the body). (WT3.)
3. Detection points → all three, plus a deterministic hook refusal (critic F5): `enforce-git-workflow.sh` denies
   `git worktree add .claude/worktrees/…` on such a project (G22.15); `/loop:tracks` refuses to fork, `/kit:doctor` names the worktree consequence,
   `install.sh` prints one warning (no write) on a bare `.claude/` / `.claude` / `/.claude/` line. (WT1, DW*, IW*.)
4. Handoff → orchestrate's checkpoint list names the plan-critic pass, the test-plan gate and each review round;
   `plan.md` step 6/7 and `review.md` stage 3 each gain one pointer line. (HF1-HF3.)
5. pr-assets image list in `auto` → the recorded run's images are published as-is (no ask); `moi` keeps the
   **Ask**. The human control is the PR review. (HF4 pins github.md wording.)
6. The (d) ask (`cd <root> && comm … <(git -C <relative worktree> …)`) → one probe fixture (G22.12) recording
   today's verdict; no code change for it in this pass: a cross-tree `-C` read stays the guard's business.
7. Auto conversion also covers `gh` asks and every non-pass push/merge → yes, that is the auto contract
   (`orchestrate.md` "Validation mode"); they become blocked stops, never allows.
8. `fetch` after `cd <root>` → read-only only in the forms `git fetch [-q] [--no-tags] <remote> [<branch>...]`
   with no `:` in any refspec and no `--upload-pack`/`--update-head-ok`/`--prune*`/`--refmap`/`--recurse*`;
   every other fetch keeps `fetch_rule`'s verdict.

## Write chain (sequential)
1. **Python case bounds (item 1).** Cases PW1-PW9 red first (`test-hooks.sh`, beside RV16-RV23, `pv_addon` /
   `rv2_pair` / `pv_expect`). New `case_header_end(lines, i)` in `addons/fastapi/hooks/tdd_py_lib.py`: from the
   `def test_…(` line, scan characters with a bracket depth counter and a string-literal state (`'`, `"`,
   triple quotes, escapes, `#` comments outside strings) until the `:` at depth 0; the header spans those
   lines. `_py_cases` and `tdd-freeze-tests-py.py` `enclosing_case_indent` both use it: indentation only
   counts after the header line. One shared helper; `enclosing_case_indent` imports it (the hook already
   imports the lib at :40). Docstrings of both updated.
2. **Git guard (item 4).** Cases G22.1-G22.14 (`git-guard.jsonl`) and AM65-AM70 (`test-hooks.sh`, `am_push`-style)
   red first. In `.claude/hooks/enforce-git-workflow.sh`:
   - `record_allow` push_form accepts an optional `git -C <abs path> ` prefix; the tree is resolved from that
     path (`git -C <path> rev-parse --show-toplevel`) and must equal `BASE_DIR`'s toplevel (the hook input
     cwd's tree) only; every later check unchanged.
   - new `pr_assets_form='^(git -C <abs> )?git push origin refs/heads/pr-assets$'`: valid unblocked, unreleased
     record with barrier, HEAD on the record's branch, local `refs/heads/pr-assets` exists, no tag
     `pr-assets`, same push-config refusals (:2176-2181), and `origin/pr-assets` absent on the remote
     (`ls-remote` exit 2) or an ancestor of the local tip (`merge-base --is-ancestor` after the ls-remote sha
     is known locally; unknown sha → no allow). Then `decide allow`.
   - `read_only_call` accepts the fetch forms of answer 8.
   - `ask()` (:128): when `cwk_auto_mode` holds for the toplevel of the **hook input cwd** (`BASE_DIR`, captured
     before any `-C` reassignment of `CWD` at :166/:1891), falling back to `CLAUDE_PROJECT_DIR`'s toplevel, `deny
     "auto mode — blocked stop: $1"`; else unchanged. Never keyed on `CWD` (the `-C` target): a `-C` to another
     repo or worktree in an auto pass is a blocked stop, not a plain ask (F3). Pattern:
     `prevent-destructive-commands.sh:220-231` (GUARD_BASE) + `:667-671`.
3. **Prompts, cwd and pr-assets (item 4).** `orchestrate.md` "Shell discipline" + `ship.md` step 0 +
   `github.md` + `e2e-tester.md`: the session cwd stays at the project root; a subfolder tool runs as
   `pnpm --dir <sub> …` / `git -C …` / one `(cd <sub> && …)` subshell, never a bare `cd <sub> && …` that
   persists; the pass's own push stays the bare exact form. `github.md:198-199`: in `auto` the image list is
   not asked. Contract cases CW1-CW6 red first (`test-workflow-contracts.sh`).
4. **Worktree detect + refuse (item 2).** `kit-doctor.py` `check_ignored_loop_paths`: probe `.claude/` itself
   (`git check-ignore -q .claude/probe` and `.claude/worktrees/probe`), a finding naming "worktrees will have no
   kit" (DW1-DW4, `test-kit-doctor.sh`); `.claude/commands/kit/doctor.md:64` row. `tracks.md` step 4: before
   any fork, `git check-ignore -q .claude/hooks/probe` succeeding → refuse, naming the `.gitignore` line to
   remove; same check in `orchestrate.md` Phase 0.5. **Deterministic refusal (F5):** `enforce-git-workflow.sh`
   denies `git worktree add <path under .claude/worktrees/> …` when `git check-ignore -q .claude/hooks/probe`
   succeeds in the tree, the reason naming the ignoring `.gitignore` line (`git check-ignore -v`) and the fix;
   every other `worktree add` keeps today's verdict. The same probe path `.claude/hooks/probe` is used by
   tracks, orchestrate and the doctor. `ship.md` `4bis-local`: the docs check of answer 2.
   `10-worktrees.md` "Three things": the refusal replaces "if versioned". `install.sh` `ensure_gitignore`:
   one warning line when the existing `.gitignore` holds a bare `.claude/` pattern (IW1-IW2, `test-install.sh`).
   Cases G22.15 (`git-guard.jsonl`, setup `wtignored`) and WT1-WT3 red first.
5. **Handoff freshness (item 3).** HF1-HF4 red first; orchestrate.md:92-94 list extended; plan.md and
   review.md pointer lines.
6. **Refactor** under a green suite: no case edited.

## Parallel lots (inside this track, same tree)
none — fully sequential (steps 3-5 share `orchestrate.md` / `ship.md` / `test-workflow-contracts.sh`).

## Track isolation
- Worktree: none, single track, main tree, branch `feat/agent-ia-trial-fixes` from main 1c3ddb2.
- Shared foundations touched: kit guard hooks (`enforce-git-workflow.sh`, fastapi freeze), `install.sh`.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| addons/fastapi/hooks/tdd_py_lib.py | Edit | `case_header_end`, `_py_cases` |
| addons/fastapi/hooks/tdd-freeze-tests-py.py | Edit | `enclosing_case_indent` uses the helper |
| .claude/hooks/enforce-git-workflow.sh | Edit | push `-C`, pr-assets allow, fetch read-only, auto `ask()` |
| .claude/hooks/fixtures/_harness/git-guard.jsonl | Edit | G22.* |
| .claude/hooks/test-hooks.sh | Edit | PW*, AM65-AM70, setups `lpassets*`, `wtignored` |
| .claude/hooks/kit-doctor.py, .claude/commands/kit/doctor.md | Edit | `.claude/` ignored probe |
| .claude/hooks/test-kit-doctor.sh | Edit | DW* |
| install.sh, .claude/hooks/test-install.sh | Edit | warning, IW* |
| .claude/commands/loop/{orchestrate,ship,tracks,plan,review}.md | Edit | cwd, worktree refusal, docs check, handoff |
| .claude/agents/{github,e2e-tester}.md | Edit | cwd, pr-assets auto |
| .claude/guides/10-worktrees.md | Edit | refusal |
| .claude/hooks/test-workflow-contracts.sh | Edit | CW*, WT*, HF* |
| docs/specs/agent-ia-trial-fixes.md | — | entry (already written) |

## Contracts
- `case_header_end(lines: list[str], start: int) -> int`: index of the line holding the header's closing `:`;
  `start` when the def is one line; on an unterminated header, `len(lines) - 1` (the case runs to EOF, never
  shorter than today).
- `record_allow` forms: `git push -u origin <b>`, `git -C <abs> push -u origin <b>`,
  `git push origin refs/heads/pr-assets`, `git -C <abs> push origin refs/heads/pr-assets`, the PR form unchanged.
- Auto blocked-stop reason prefix: exactly `auto mode — blocked stop: ` (same as `ask_or_block`).

## Test plan (gate — validated before EXECUTE)

### Test-first — none (no TS/Python test-first layer); kit fixture cases, each observed red before its code

#### .claude/hooks/test-hooks.sh — Python rows freeze (`pv_addon`, verdict on a rows-mode file with an unfreeze verdict for B1 unless said)
**Reproduction**
- [ ] PW1 an Edit to the body of `async def test_b1_x(\n    db: Session,\n) -> None:` (closing `)` at the def column) is allowed under B1's unfreeze verdict (EcoCrew U1/B352) — denied today "outside every case"
- [ ] PW2 an insertion indented into the body of a wrapped-signature case (anchor = its last assert, block at body indent, own assert) is denied "INSIDE a case" — allowed today
**Core behaviour**
- [ ] PW3 the same body Edit as PW1 without any verdict or row is denied
- [ ] PW4 an Edit touching a module-level line between two wrapped-signature cases is denied even with B1 unfrozen
- [ ] PW5 a new case appended after a wrapped-signature case (dedented to column 0, own assert) is allowed
**Edge cases**
- [ ] PW6 a header whose default holds `{"a": (1, 2)}` and annotation `-> dict[str, int]:` bounds the case at its real `:` (body Edit allowed under the verdict)
- [ ] PW7 a header with a `#` comment containing `)` and `:` and a string default `"):"` is bounded at the real `:`
- [ ] PW8 a decorated `@pytest.mark.parametrize(...)` wrapped case and a class method `    def test_b2_y(\n        self,\n    ) -> None:` keep their bounds: body Edit allowed under the verdict, Edit on the decorator line still denied
- [ ] PW9 single-line `def test_b1_x() -> None:` cases: RV2/RV4, RV16-RV23 and LP cases unchanged and green

#### .claude/hooks/fixtures/_harness/git-guard.jsonl — record forms (setup `lp` = valid record on feat/s1)
**Reproduction**
- [ ] G22.1 allow `git -C __FEAT_TREE__ push -u origin feat/s1` (EcoCrew 2.2 push from `frontend/`) — asks today
- [ ] G22.2 allow `git push -u origin feat/s1` with `cwd` = a subfolder of the feat tree
- [ ] G22.3 allow `git push origin refs/heads/pr-assets`, setup `lpassets` (local pr-assets, remote absent)
**Core behaviour**
- [ ] G22.4 allow `git -C __FEAT_TREE__ push origin refs/heads/pr-assets`, setup `lpassetsff` (origin/pr-assets ancestor of local)
- [ ] G22.5 ask `git -C <another repo> push -u origin feat/s1` ("pushes to a remote")
- [ ] G22.6 ask `git push origin refs/heads/pr-assets`, setup `lpassetsdiv` (diverged)
- [ ] G22.7 ask `git push --force origin refs/heads/pr-assets` and `git push origin +refs/heads/pr-assets`
- [ ] G22.8 ask `git push origin refs/heads/pr-assets`, setup `lpassets` + `lpblocked`-style blocked record
- [ ] G22.9 allow-as-read `cd __FEAT_TREE__ && git fetch origin audit/x` (no ask)
- [ ] G22.10 ask `cd __FEAT_TREE__ && git fetch origin audit/x:refs/heads/audit/x`, and `cd /tmp && git fetch origin`
**Edge cases**
- [ ] G22.11 ask `git push -u origin feat/s1` with `-C` pointing at a second worktree of the same repo on another branch
- [ ] G22.12 probe: `cd __FEAT_TREE__ && comm -12 <(git diff --name-only HEAD | sort) <(git -C .claude/worktrees/x diff --name-only | sort)` — today's verdict recorded as-is (answer 6)
- [ ] G22.13 ask `git push origin refs/heads/pr-assets:refs/heads/main`, setup `lpassets` (renamed refspec)
- [ ] G22.14 ask `git push origin refs/heads/pr-assets2`, setup `lpassets` (another ref)
- [ ] G22.15 deny `git worktree add .claude/worktrees/x -b feat/x main`, setup `wtignored` (`.gitignore` holds `.claude/`), reason naming that `.gitignore` line; the same command with `.claude/` not ignored keeps today's verdict

#### .claude/hooks/test-hooks.sh — auto conversion (`am_*` helpers, auto record)
- [ ] AM65 in auto, `git push --force origin feat/s1` is denied with a reason opening `auto mode — blocked stop:`
- [ ] AM66 in auto, `gh pr merge 1` is denied `auto mode — blocked stop:`
- [ ] AM67 in auto, the pass's exact push and PR (AM-existing helpers) are still allowed
- [ ] AM68 in moi (no record / released record), the same force push still asks
- [ ] AM69 in auto, `git -C __OUT_TREE__ push -u origin feat/s1` (another repository) is denied `auto mode — blocked stop:`
- [ ] AM70 in auto, `git -C <second worktree of the repo, on another branch> push -u origin feat/s1` is denied `auto mode — blocked stop:`

#### .claude/hooks/test-kit-doctor.sh
- [ ] DW1 a project whose `.gitignore` holds `.claude/` gets a finding naming worktrees without the kit
- [ ] DW2 `.claude/worktrees/` alone ignored: no such finding
- [ ] DW3 `/.claude` and `.claude` spellings detected like `.claude/`
- [ ] DW4 the kit repo itself: no finding

#### .claude/hooks/test-install.sh
- [ ] IW1 installing into a target whose `.gitignore` has `.claude/` prints the warning and leaves that line untouched
- [ ] IW2 no warning when only `.claude/worktrees/` is listed

#### .claude/hooks/test-workflow-contracts.sh
- [ ] CW1 orchestrate.md states the session cwd stays at the project root (`pnpm --dir`, `git -C`, subshell)
- [ ] CW2 github.md: the push runs as the bare exact form from the project root, never with `-C`
- [ ] CW3 e2e-tester.md: Playwright runs via `pnpm --dir <app root>` (no persisting `cd`)
- [ ] CW4 github.md: in auto, the pr-assets image list is not asked; moi keeps **Ask**
- [ ] CW5 ship.md step 0 states the session cwd stays at the project root (subfolder commands via `pnpm --dir`, `git -C` or a one-call subshell)
- [ ] CW6 github.md states the same cwd-at-root rule for every command it runs, besides the push form
- [ ] WT1 tracks.md refuses to fork when `.claude/hooks` is git-ignored, naming the `.gitignore` line
- [ ] WT2 orchestrate.md Phase 0.5 carries the same refusal; 10-worktrees.md no longer says "if `.claude/` is versioned" as a supported case
- [ ] WT3 ship.md `4bis-local` lists untracked/modified `docs/` files before `git worktree remove` and refuses while any remain
- [ ] HF1 orchestrate.md's checkpoint list names the plan-critic pass, the test-plan gate and each review round
- [ ] HF2 plan.md points to the handoff refresh after step 6 and step 7
- [ ] HF3 review.md points to the handoff refresh after each round
- [ ] HF4 the full suite ends green

### Test-after
- none beyond running every `.claude/hooks/test-*.sh`.

## Vigilance (carried from research)
- The insertion path was permissive on wrapped signatures: PW2 must be seen red first.
- Both parsers share one helper; no second copy of the header scan.
- Header scan ignores `:`/brackets inside strings and comments; unterminated header never shortens a case.
- Decorators and methods keep their bounds.
- `-C` push allow: same repo, same tree, every first-push check kept; another worktree or repo asks.
- pr-assets allow: that ref only, fast-forward only, no force/`+`, no tag, push-config refusals kept.
- Auto `ask()` conversion never turns an ask into an allow; `moi` verdicts byte-identical.
- `fetch` read-only forms are a closed list; `fetch_rule` keeps every other verdict.
- No fix makes a worktree session write the main tree's per-pass state.
- Prompt wording and its contract test land in the same step.
- (critic F6) Single-line `async def`, decorated and method cases keep their bounds — check a one-line case of each shape.
- (critic F7) install warning covers `.claude`, `.claude/`, `/.claude`, `/.claude/`.
- (critic F8) an unterminated wrapped header bounds the case to EOF, never shorter than today.
- (critic F9) the handoff refresh wording says the state line is rewritten, and names the contract gate.
- (critic F10) each acceptance criterion traces to its cases in the PR's criteria table.
- (critic Q1) auto keyed on the hook input cwd / CLAUDE_PROJECT_DIR, never the `-C` target.
- (critic Q2) the `-C` push allow requires the `-C` toplevel to equal the hook input cwd's toplevel only; a
  worktree session never pushes another tree's recorded branch.
- (critic Q3) the jsonl ids are written `G22.1nn` (plan G22.1 → `G22.101` … G22.15 → `G22.115`) so they never read as the existing `G22.0nn`.
- (critic N3) the worktree-add deny does not cover native `EnterWorktree`: tracks/orchestrate's prose check is the guard there; `git check-ignore` runs only on a directory that passes `project_repo`.
- (critic N4) the fetch cd-target comparison is with the hook input cwd's toplevel (the session tree), not `CLAUDE_PROJECT_DIR`.
- (critic N5) AM69/AM70 build their own out-of-repo tree and second worktree (`__OUT_TREE__` is jsonl-only).
- (critic Q4) G22.12's expected verdict is `ask` (cross-tree relative `-C` into a worktree), from research — not read off the code.
- (critic Q5) the fetch allow is a separate predicate requiring the cd target to equal the session tree's toplevel;
  `cd <root>/frontend && git fetch …` still asks; `read_only_call`'s "runs no program" invariant untouched.
- (critic Q6) github.md :192 and :201 rewritten to match the allow; the drop/clean-up push stays asking.
- (critic Q7) the fetch defect's reproduction is the observed piped form `cd <root> && git fetch origin <base> 2>&1 | tail -1`; G22.2 already passes today (not a reproduction).
- (critic Q8) answer 5's pin is CW4.
- (critic Q9) one probe path (`.claude/hooks/probe`) for tracks, orchestrate, doctor and the hook.

## Plan critic
- completeness: 88 (pass 2; pass 1: 68 — F1, F2, F3 confirmed by a verifier, F4 refuted, F5 rewritten as a deterministic refusal)
- quality: 85 (pass 1: 78)
- surviving blockers: none
- vigilance appended: F6-F10, Q1-Q9, N1-N5 (N1/N2 also narrowed in place)

## Gate
- 2026-11-24 go (user, moi)
- Contract: as written (spec amended earlier in the pass by the user's own words: item 4 added; recorded as contract failure 1/3, then `as written` at this gate)
- Open questions 1-8 → answers taken as proposed in `## Proposed answers` (1: worktree detect + refuse; 2: docs check before worktree removal; 3: four detection points incl. the deterministic `worktree add` deny; 4: handoff refresh points; 5: pr-assets images not asked in auto; 6: G22.12 probe expects ask; 7: auto conversion covers gh and every non-pass push; 8: closed fetch list, cd target = session tree)
- Frozen cases to amend: none

## Acceptance criteria (carried from the entry artifact)
- [ ] With an unfreeze verdict on Python case C whose signature wraps over several lines and closes with `) -> None:` at the `def` column, an Edit to C's body is allowed; the same Edit without a verdict is denied; an Edit touching a line between two cases is still denied.
- [ ] Single-line signatures, `async def`, decorated cases and class-method cases keep today's case bounds (existing freeze fixtures unchanged and green).
- [ ] A case whose signature holds a default containing `:` or parentheses (e.g. `x: dict = {"a": (1, 2)}`) is bounded by its real closing `:`.
- [ ] Support variant: in a fixture project whose `.gitignore` lists `.claude/`, a track prepared by `/loop:tracks` has the kit hooks and scripts reachable from the worktree, and a `kit-attempts.py fail` run there writes under the worktree's state, never the main tree's. Fallback variant: `/loop:tracks` refuses to fork on that fixture with the `.gitignore` fix named, and `/kit:doctor` reports it.
- [ ] Shipping a worktree track leaves the main tree's `docs/` holding the track's story, research-cache and architecture changes before the worktree is removed (automatic in the support variant, a checked step in the fallback); the step refuses rather than overwrites when the main-tree copy changed since the fork.
- [ ] Orchestrate/plan prompts require the handoff state to be rewritten at each passed gate; a contract test pins the wording.
- [ ] With a valid auto record on `feat/<slug>`, `git push -u origin feat/<slug>` is allowed from the tree root, from a subfolder of it, and as `git -C <tree root> push -u origin feat/<slug>`; the same with `-C` pointing at another repository, a different branch, `--force`, or a second push once the remote branch exists still asks (`moi`) / is denied as a blocked stop (`auto`).
- [ ] Under the same record, the `pr-assets` publish push in the form `kit-pr-assets.py`/the `github` agent prescribes is allowed when it fast-forwards `origin/pr-assets` (or creates it); a non-fast-forward, a force, or another ref still asks / blocks.
- [ ] `cd <abs project root> && git fetch origin <base>` and `cd <abs project root> && git diff …` (read-only git, the cd target being the project root literally) no longer ask; a `cd` to any other directory before git still asks.
- [ ] In `auto`, no `enforce-git-workflow.sh` ask reaches the user: every remaining ask is denied with a reason opening `auto mode — blocked stop:`; in `moi` the asks are unchanged.
- [ ] Orchestrate/ship/github prompts state that the session cwd stays at the project root (subfolder commands use `pnpm --dir`, `git -C`, or a one-call subshell), pinned by a contract test.
- [ ] All existing kit test scripts (`.claude/hooks/test-*.sh` and the fastapi addon tests) pass.
