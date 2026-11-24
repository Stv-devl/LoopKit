# Research: kit fixes from the EcoCrew agent-ia-2.2 / 4.4 runs   (entry: docs/specs/agent-ia-trial-fixes.md)
Token profile: critical

Two explorers (freeze + handoff surface; worktree surface), 2026-11-24, plus a direct read of
`addons/fastapi/hooks/tdd-freeze-tests-py.py:60-305`. Rerun after the contract amendment (item 4 added): a third
explorer on the git guard, plus the EcoCrew 2.2 transcript (session a81e6351 and its `github` subagents) read for
the permission decisions after the contract go.

## Pattern to follow
- **Case bounds by structure, not layout:** the TS freeze `anchor_scope` (`.claude/hooks/tdd-freeze-tests.sh:537`,
  comment :563-567) bounds a case by brace depth from the `it(`/`test(` head, so a wrapped header is handled.
  The Python fix follows the same idea: a case's header runs to the `:` that closes the `def`, parentheses
  balanced, before indentation starts to count.
- **Prior unfreeze widening, same file:** `auto-mode-trial-fixes` item 1 (`docs/specs/auto-mode-trial-fixes.md`)
  — rows-mode change pinned by inline `test-hooks.sh` cases, scoped to the named shape only.
- **Doctor probe:** `kit-doctor.py:661-690` `check_ignored_loop_paths` (`git check-ignore` on probe paths),
  documented in `.claude/commands/kit/doctor.md:64`.
- **Prompt contract:** `.claude/hooks/test-workflow-contracts.sh` — file variables :5-18, one-line
  `grep -Fq '<phrase>' "$FILE"` assertions (e.g. :29, :33), ordering by line numbers (:46-48), negatives (:54).

## Wiring points
- Python freeze: `addons/fastapi/hooks/tdd_py_lib.py:567-584` `_py_cases`, `:587-593` `_touched`, `:596-642`
  `rows_refusal` (only caller of both: `tdd-freeze-tests-py.py:198`).
- **Second indent-bounded parser:** `addons/fastapi/hooks/tdd-freeze-tests-py.py:68-87`
  `enclosing_case_indent`, same rule ("first non-blank line at or below the def's column", :71-73), used by the
  insertion path at :289-295.
- Hooks importing the lib: `tdd-freeze-tests-py.py:40`, `tdd-require-red-py.py:35`, `tdd-prove-red-py.py:48`,
  `enforce-backend-layers.py:42`. Installed by `install.sh:856-896` (`--fastapi`, `wire_fastapi` :528);
  lib listed as shared at `kit-doctor.py:855`.
- Worktree fork: `.claude/commands/loop/tracks.md:137-144`; ship worktree steps `.claude/commands/loop/ship.md:20-22`
  (step 0), :200-222 (`4bis-local`, cleanup), :235-236 (step 5 in the main tree after the merge).
- Guide: `.claude/guides/10-worktrees.md` "Three things" (~141-147) already says the guardrails follow only
  "if `.claude/` is versioned" and that `git worktree remove` deletes ignored files; Layout :165.
- `install.sh:620-660` `ensure_gitignore` (append-only block, call :905) — never inspects an existing bare
  `.claude/` line.
- Handoff refresh points: only `.claude/commands/loop/orchestrate.md:90-94` ("refresh it after interface, plan,
  each RED→GREEN layer, review fixes and ship gates, and on a contract amendment re-entry"). `plan.md` and
  `review.md` never mention the handoff; `handoff/codex.md:77` "Update this handoff when the phase changes".

## Reusable
- `kit-doctor.py` `check_ignored_loop_paths` already probes `.claude/{rules,agents,commands,hooks,skills,scripts,guides}/probe`
  and `.claude/settings.json`: a project ignoring `.claude/` already yields a DIVERGENCE there; only the
  worktree consequence is unnamed.
- `docs/research-cache/claude-code-worktrees.md:23` and `claude-code-hook-input.md:29` [cache]: after
  `EnterWorktree`, `CLAUDE_PROJECT_DIR` stays at the original root, hook input `cwd` follows Claude.
- `docs/refonte-loopkit.md:361` (row 14) already records the EcoCrew `.claude/`-ignored worktree issue.

## Blast radius
- Freeze parser change hits every rows-mode and insertion decision of the `-py` freeze; existing cases RV2/RV4
  (`test-hooks.sh:2391-2401`), RV16-RV23 (:2648-2760), LP (:5009-5191) — all single-line `def` at column 0;
  **no fixture covers wrapped signatures, decorators, `async def` or methods**.
- Root resolution today (worktree with no `.claude/`):

  | Consumer | Root | Effect in an ignored-`.claude/` worktree |
  | --- | --- | --- |
  | settings.json hooks | `$CLAUDE_PROJECT_DIR` (main) | fire from main ✓ |
  | `loop-record.py` hook/CLI | git toplevel of input cwd / `getcwd` (:91-98, :346, :641…) | record created in the worktree's `.claude/` (makedirs) |
  | `kit-attempts.py` | `attempts.json` cwd-relative (:126); health log `CLAUDE_PROJECT_DIR` (:37-38) | attempts in worktree, health in main |
  | `kit-audit-surface.py:153`, `kit-pr-assets.py:317` | `getcwd()` + `.claude/project.json` | **ConfigError / missing config** |
  | tdd hooks `.tdd-red/`, `-py` `.tdd-unfrozen` | `CLAUDE_PROJECT_DIR` (main) | markers in main |
  | `tdd-freeze-tests.sh` rows `.tdd-unfrozen` | edited file's tree (:461-467) | worktree file (absent) |
  | kit scripts run by relative path + settings allow-list (relative forms only) | session cwd | **not found / prompts** |

  Support means touching settings allow-list, every prompt that runs a kit script by relative path (loop/*,
  agents, skills), two cwd-based scripts, and the per-tree `.tdd-unfrozen`/markers split — and still not the
  native cross-tree write refusal (below).
- `docs/` in EcoCrew is tracked: committed worktree edits travel with the merge; the story `Status` / board are
  written by ship step 5 in the main tree after the merge by design. Lost on `git worktree remove`: ignored
  files only (`docs/work/*/handoff.md`, `pr-body.md`, `codex-last-message.txt`, `.pr-shots/`) — and uncommitted
  edits (git refuses a dirty tree for tracked files).

## Item 4 — git guard at ship (auto)

Observed in EcoCrew 2.2 after the second contract go (record `mode: auto`, barrier true), each answered by
the user (`permissionDecision accept, source user_temporary`):

| Time (Z) | Who | Command | Ask source |
| --- | --- | --- | --- |
| 14:33:24 | main | `cd <root> && git fetch origin main 2>&1 \| tail -1` | `foreign_verdict` "follows a cd" (`enforce-git-workflow.sh:549-554`); `fetch` is not in `read_only_call` (:536-540, READ_SUBS :252-255) |
| 14:33:28 | github | `git -C <root> push -u origin feat/agent-ia-2.2` | `record_allow` push_form `^git push -u origin <b>$` (:2137) misses the `-C`; segment loop asks PUSH_REASON (:2262-2263, reason :130) |
| 14:33:58 | github | `git -C <root> push origin refs/heads/pr-assets` | no record form; floor push ask (:2243-2244) |
| 14:38:19 | main | `cd <root> && comm -12 <(git diff …) <((git -C .claude/worktrees/agent-ia-4.4 diff …; git -C … ls-files …) …)` | "follows a cd"; diff is read-only so `cd_proven` (:543-546) should pass — not explained by reading (relative `-C` into a worktree in a process substitution is the likely trigger); after the PR, outside the loop |

- Why the agents used `-C`/`cd`: the main thread ran `cd <root>/frontend && … pnpm exec playwright …`; the
  harness keeps a `cd` that ends inside the working dirs, so the session cwd (and subagents launched after it)
  sat in `frontend/` (the `github` agents' transcripts show `cwd: …/ecocrew/frontend`).
- Bare `git push -u origin <b>` from a subfolder already passes `record_allow`: the tree is `BASE_DIR`'s
  toplevel (:2149) and HEAD == branch (:2159-2160). Only the `-C` broke it.
- **No auto conversion in this hook:** `ask()`/`decide()` at `enforce-git-workflow.sh:111-128` never check
  auto mode; `cwk_auto_mode` (`hook-guarded.sh:590-602`) is used here only inside the allow path (:2170). The
  pattern exists in `prevent-destructive-commands.sh:667-671` `ask_or_block` (GUARD_AUTO :227-231).
  `orchestrate.md` "Validation mode" says the kit's guarded asks are denied in `auto` — this hook breaks it.
- pr-assets: `kit-pr-assets.py commit` (:243-257, `pick_parent` :201-212) creates/fast-forwards local
  `refs/heads/pr-assets` from the newer of local and `origin/pr-assets` (diverged → refuses), CAS `update-ref`;
  never pushes (:1-7). Prompts: `github.md:197-202` (plan / **Ask** on the image list :198-199 / commit / push
  `git push origin refs/heads/pr-assets` "(asks)" :201 / section), cleanup :213; ship 4bis-PR `ship.md:170-185`.
- cwd wording today: orchestrate.md:25-27, :127 and CLAUDE.md:53 cover kit scripts only; prompts prescribe
  `git -C` for another tree (`github.md:168,174,227,240`, `ship.md:290,292`) and the bare push
  (`github.md:140`, `ship.md:175`). No `pnpm --dir` anywhere; no cwd-at-root rule in review/e2e/implementer/test-writer.
- Tests: `.claude/hooks/fixtures/_harness/git-guard.jsonl` (649 lines; `{id, verdict, setup, command, cwd?, reason}`;
  e.g. G21.001 allow `setup:lp`, G21.002b ask `lpblocked`, G21.003 `lpnorec`, G21.043 `lpreleased`; cd ask
  G16.057), runner `test-hooks.sh:1008-1048`, setups `lp_git_setup` :4520-4523; auto helpers `am_pr`/`am_push`
  :6613-6619, cases AM64 etc. :6715-6740. No fixture for `cd <root> && git fetch|diff` or `git -C <root> push`.

## Live DB state
n/a (kit repo)

## External surface
- `CLAUDE_PROJECT_DIR` after `EnterWorktree` stays at the original root; hook `cwd` follows Claude
  [cache claude-code-worktrees.md / claude-code-hook-input.md]. A CLI launched inside a manual worktree:
  UNVERIFIED in the cache.
- The refused write to `<main>/docs/stories/…` from the worktree session: no kit hook denies it
  (`hook-guarded.sh:522-550` maps it to `docs/stories/x.md`, not guarded, not kit code; `protect-files.sh:262-268`
  don't apply). Inference: Claude Code's own working-directory boundary — not fixable by the kit.

## Traps (points of vigilance for the review)
- **The insertion path is permissive today, not only strict:** with a wrapped signature closed at the def
  column, `enclosing_case_indent` returns `None` for the body, so an indented block inserted into that case's
  body (with an assert, no top-level return/raise) is ALLOWED as if it were a new case. The fix tightens this;
  a regression case must prove it.
- Fix both parsers (`_py_cases` and `enclosing_case_indent`) or share one; a single fix leaves the other path wrong.
- Header end detection must ignore `:` inside parentheses, brackets, braces and string literals (annotations,
  defaults like `{"a": (1, 2)}`, `-> dict[str, int]:`); a one-line `def f(): pass` stays one case.
- Decorators and class methods (`    def test_x(self,` inside a class) must keep today's bounds.
- `tdd_py_lib.py:409-431` / `tdd-require-red.sh:155` "change together" constraints: check whether the shared
  parser forces a copy elsewhere.
- Worktree: do not let a fix make a worktree session write the main tree's per-pass state (record, attempts).
- Prompt contract tests must be added together with the wording, or they fail on current text.
- `git -C <dir> push` allow: resolve the tree from the `-C` dir, require it to be this project's tree (not a
  sibling repo, not another worktree's branch), keep every first-push check (:2174-2186) — a `-C` to another
  repo must still ask.
- pr-assets allow: only `refs/heads/pr-assets`, only when `origin/pr-assets` is an ancestor of the local tip
  (or absent), no force/`+`/refspec rename, no tag, same push-config refusals (:2176-2181).
- Auto conversion of `ask()` also converts `gh` asks, force pushes and merges: intended by the auto contract,
  but `gh pr merge` etc. must become blocked stops, never allows; `moi` asks unchanged.
- Adding `fetch` to the read-only set after `cd <root>` must exclude `fetch` forms that write refs beyond
  remote-tracking (`<src>:<dst>`, `--update-head-ok`, `--upload-pack`, `--prune` on non-default?) — keep the
  existing `fetch_rule` (:941) verdicts.

## Open questions
1. Worktree variant: research shows the support variant touches the settings allow-list, every prompt running
   a kit script by relative path, two cwd-based scripts and the per-tree state split, and still cannot lift
   Claude Code's native cross-tree write refusal. Take the **detect + refuse** fallback (spec item 2, as the
   user allowed "si compliqué")? Proposed: yes.
2. Copy-back: since tracked `docs/` travel with the merge and story/board are step-5 main-tree writes by
   design, is the remaining need only "refuse the worktree removal while the track has uncommitted or
   ignored-but-wanted `docs/` changes, naming them"? Proposed: yes — a checked step in ship `4bis-local`
   before `git worktree remove`, listing ignored `docs/work/<slug>/` files that would be lost (handoff is the
   loop trace).
3. Detection points for the fallback: `/loop:tracks` refuses to fork, `/kit:doctor` names the worktree
   consequence, `install.sh` warns on a bare `.claude/` line in `.gitignore`. All three, or tracks + doctor only?
   Proposed: all three (install warning is one message, no write).
5. pr-assets image list: `github.md:198-199` says **Ask** before publishing the image list. In `auto`, take the
   recorded run's images as-is (no ask), the PR body listing them? Proposed: yes — the human control is the
   PR review.
6. The (d) ask (`cd <root> && comm … <(git -C <relative worktree> …)`): reproduce it as a fixture first and fix
   only if the cause is in the cd-proof; the command was outside the loop. Proposed: one probe case; if the
   cause is the relative `-C` into a worktree, keep the ask (cross-tree read is the guard's business).
4. Handoff freshness: add the refresh rule in orchestrate's checkpoint list naming the plan-critic pass,
   the test-plan gate and each review round, and a one-line pointer in `plan.md` / `review.md`? Proposed: yes.
