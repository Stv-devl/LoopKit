# Spec: kit fixes from the EcoCrew agent-ia-2.2 / agent-ia-4.4 runs
Token profile: critical
Validation: moi

## Objective
Remove the user stops and manual workarounds that came from kit defects in the EcoCrew agent-ia-2.2 (main tree) and agent-ia-4.4 (worktree) runs of 2026-11-24, without widening any guard beyond the cases named here.

Source evidence (read-only, EcoCrew repo): `docs/work/agent-ia-2.2/{handoff.md,unfreeze-queue.md,plan.md}` and `.claude/worktrees/agent-ia-4.4/docs/work/agent-ia-4.4/{handoff.md,plan.md}`. Branch: one, off `main` (1c3ddb2).

## Scope
- IN :
  1. **Python rows-mode freeze bounds a case by its body, not its signature.** `addons/fastapi/hooks/tdd_py_lib.py` `_py_cases` ends a case at the first non-blank line at or below the `def` column; a wrapped signature whose closing `) -> None:` sits at that column ends the case there, so every body line is "outside every case" and an arbiter unfreeze verdict can never be applied (EcoCrew 2.2 U1/B352: two user stops — switch to `moi`, then a second Contract gate to re-arm `auto`). A case spans its whole signature (up to the `:` that closes the `def`, parentheses balanced) plus its indented body. Decorators keep their current treatment.
  2. **Worktree tracks work when the project git-ignores `.claude/` as a whole** (EcoCrew `.gitignore` line 2). Today the worktree checkout has no `.claude/` at all: no kit scripts, the agent runs them by main-tree absolute path, `kit-attempts.py` resolves its root from `CLAUDE_PROJECT_DIR` (main tree) so state may land in the wrong tree, and `docs/` written in the worktree (story Status, research cache, `settled.md`, stories, architecture rows) must be copied back by hand before the worktree is removed; a Status write to the main-tree story was refused from the worktree.
     - **Preferred (support):** `/loop:tracks` prepares a worktree so the kit is present and its per-pass state (loop record, attempts, tdd markers) resolves to the worktree, and `/loop:ship` of a worktree track brings its `docs/` changes back to the main tree before the worktree is removed, with no hand copy.
     - **Fallback (detect + refuse), if research shows the support variant touches too many hooks or cannot keep per-tree state separate:** `/loop:tracks` refuses to fork while `.claude/` is not versioned, naming the `.gitignore` fix; `/kit:doctor` reports the case; the ship of a worktree track has an explicit, checked copy-back step for `docs/`. The choice between the two is made at the plan gate, with research in hand.
  3. **Handoff kept current at each gate.** The 4.4 handoff still read "plan-critic pass 1 running" after pass 2 and the arbiter go. The orchestrate/plan prompts require the handoff's state line to be rewritten when a gate passes (contract, plan-critic passes, test-plan gate, review rounds), pinned by a contract test.
  4. **Ship reaches the PR without a user prompt in `auto`** (EcoCrew 2.2: four asks after the contract go, all answered by hand — transcript a81e6351, 14:33-14:38Z):
     - the pass's own push was written `git -C <root> push -u origin feat/agent-ia-2.2`, outside `record_allow`'s exact form (`enforce-git-workflow.sh:2137`), because the `github` agent's cwd had drifted to `frontend/` (the main thread's `cd frontend && pnpm exec playwright …` persisted);
     - the screenshot push `git -C <root> push origin refs/heads/pr-assets` (`kit-pr-assets.py` publish) has no record-backed form;
     - `cd <abs project root> && git fetch origin main` and `cd <abs project root> && … git diff …` asked "follows a cd earlier in the same call";
     - in `auto` those asks reached the user instead of ending as a blocked stop, contrary to `/loop:orchestrate` "Validation mode".
     Fix so that, under a valid auto record, the pass's own push (exact form, also from a subfolder of the tree or as `git -C <tree root>`), its `pr-assets` publish push (fast-forward, that branch only), and read-only git after a lone `cd <abs project root> &&` run without asking; every other remote write still asks (in `moi`) or is a blocked stop (in `auto`); and prompts keep the cwd at the project root (subfolder tools via `--dir`/`-C`, never a persisting `cd`).
- OUT :
  - Any other unfreeze widening (fixtures or helpers outside a case, import changes beyond what `auto-mode-trial-fixes` allowed).
  - EcoCrew's own `.gitignore` / repo state: fixed in that repo, outside this pass.
  - The 2.2 product questions (N7 manual restore, N8 older-then-newer undo) and its Minor follow-ups.
  - Guarded-path grants (parked).

## Data model
none

## Custom backend
NONE — kit hooks, scripts and prompts only.

## Front surface
none (kit repo; no app UI)

## Acceptance criteria
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

## Business logic to cover
- Python case boundary: multi-line signatures, return annotations, defaults with brackets/colons, decorators, async, nested classes; out-of-case edits still refused.
- Worktree kit resolution: which root each kit script and per-pass state file resolves to, from a worktree and from the main tree.
- `docs/` copy-back at ship of a worktree track, including the conflict refusal.
- Prompt contracts: handoff updated at each gate.
- Git guard: record-backed push forms (root, subfolder, `-C <root>`), `pr-assets` fast-forward push, read-only git after `cd <root> &&`, and the `auto` conversion of every remaining ask to a blocked stop.
