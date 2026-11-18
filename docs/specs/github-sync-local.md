# Spec: the github agent keeps the local repository up to date
Token profile: economy

## Objective
Whenever the remote moved, the `github` agent fast-forwards the local branches it concerns and
reports what moved, so the local tree is never left behind origin.

## Scope
- IN  : `.claude/agents/github.md` (kit prompt) gains one duty, "Keep local in sync":
  - triggers: after a merge it ran (track or small branch merged back), after a PR it merged
    or found `MERGED` on GitHub, and at the start of any task when origin is ahead of the
    current branch (no "after a push" trigger: local == origin by construction — user go
    2026-11-18);
  - action: `git fetch origin`; fast-forward only the current branch
    (`git merge --ff-only origin/<branch>`); when a PR merged into a base branch that is not
    checked out, update that local branch with `git fetch origin <base>:<base>` (git refuses
    a non-fast-forward there);
  - never `--force`, never a rebase or reset to make it fit; a diverged branch, or a dirty tree
    that blocks the fast-forward, is reported to the user, not fixed;
  - the Output format gains a `Local:` line: what moved (`<branch> <old>..<new>`), or
    `up to date`, or `diverged: <branch> — <n> local / <m> remote commits, not touched`.
- IN  : contract case(s) in `.claude/hooks/test-workflow-contracts.sh` pinning the duty, its
  ff-only / no-force wording and the `Local:` report line.
- IN  : check that `enforce-git-workflow.sh` handles those exact commands (ask or allow, never
  deny); no hook change expected — if one is needed, the plan says so and the user decides.
- OUT : loop-to-pr, auto-mode, any change to push/PR behaviour or to the validation gate,
  any new permission allow.

## Data model
none

## Custom backend
NONE — kit prompt and its contract suite only.

## Front surface
none

## Acceptance criteria
- [ ] `github.md` names the three triggers, the fetch + ff-only commands, and the
      diverged / dirty-tree report-not-fix rule.
- [ ] `github.md`'s Output format has a `Local:` line with its three forms.
- [ ] No sentence of `github.md` allows `--force`, `reset --hard` or a rebase to make the sync fit.
- [ ] A contract case fails when any of the above is removed from `github.md`.
- [ ] `enforce-git-workflow.sh` does not deny `git fetch origin`, `git merge --ff-only origin/<b>`
      or `git fetch origin <base>:<base>` (observed by a hook run or an existing case).
- [ ] `test-workflow-contracts.sh`, `test-hooks.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Business logic to cover
- The sync duty is stated with its triggers, its ff-only commands, and its refusal to force.
- A diverged or blocked branch is reported in the `Local:` line, never rewritten.
- The git hook's verdict on the three sync commands (not deny).
