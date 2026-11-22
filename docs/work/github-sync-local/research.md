# Research: the github agent keeps the local repository up to date   (entry: docs/specs/github-sync-local.md)
Token profile: economy

Probes run inline on the main thread (one prompt file, one hook, one suite: an explorer would
cost more than the reads).

## Pattern to follow
- `.claude/agents/github.md` (232 lines) already carries procedural sections with numbered
  steps that start with `git fetch origin`: "PR screenshots on `pr-assets`" Publish (:163-172)
  and Clean up (:176-182), and "Merging a track back" (:188-216). The new duty is one more
  section of the same shape, placed after "Merging a track back" (:216) and before
  "Output format" (:218).
- Output format block `.claude/agents/github.md:220-230` (`## Git` with `- Tree:`,
  `- Committed:`, `- Merge:`, `- Remote:`, `- PR:`, `- Notes:`): the `Local:` line joins it.
- Contract pins on github.md live in `.claude/hooks/test-workflow-contracts.sh`: `:834-835`
  (`grep -Fq` on exact sentences), `:1184-1188` (PK17, kit-prompts). Variable
  `GITHUB_AGENT` at `:15`.

## Wiring points
- The agent is invoked by `/loop:ship` step 4/4bis (`.claude/commands/loop/ship.md`, "Commit",
  "Integrate") and by any user "commit/push/PR" request (agent description, github.md:3).
  Nothing parses the agent's report mechanically (grep for `- Remote:` / `## Git` in
  commands/guides: no consumer found) → adding a `Local:` line breaks no reader.

## Reusable
- `.claude/hooks/enforce-git-workflow.sh` already rules on every sync command; no hook change.

## Blast radius
Verdicts observed by piping each command through `enforce-git-workflow.sh` (kit repo, branch
audit/slim, 2026-11-18):
- `git fetch origin` → no decision from the hook; `.claude/settings.json` allows
  `Bash(git fetch)` / `Bash(git fetch *)` → runs without a prompt.
- `git merge --ff-only origin/audit/slim` (current branch not protected) → no decision; not in
  the allow list → default permission prompt. On a protected current branch the merge ask
  `merge_reason` (`enforce-git-workflow.sh:152`) applies.
- `git fetch origin main:main` → **ask**: "This git fetch writes 'main', a local branch: it moves
  or force-rewinds it outside the merge ask. Fetch into refs/remotes/ instead."
  (`enforce-git-workflow.sh:959-960`).
- In an installed project, a `git merge` whose range brings kit files → **ask** `kit_bring`
  (`enforce-git-workflow.sh:1159-1162`, rule `:1467-1476`), never deny.
No command of the duty is denied; every move of a local branch other than a fetch prompts.

## Live DB state
n/a

## External surface
n/a (git semantics: `merge --ff-only` refuses a non-fast-forward; `fetch <src>:<dst>` refuses a
non-fast-forward update of `<dst>` without `+`/`--force`, and refuses to update the checked-out
branch) [git documentation, stable behaviour, not fetched].

## Traps (points of vigilance for the review)
- `git fetch origin <base>:<base>` asks with a reason that says "fetch into refs/remotes/
  instead": github.md must say this ask is expected for the base-branch update and that the
  user answers it — never route around it with `update-ref` / `branch -f` (both ask or rewrite).
- `fetch <b>:<b>` on the checked-out branch is refused by git: the current branch always takes
  `merge --ff-only`, the other branch the fetch refspec.
- A dirty tree can block `merge --ff-only` only when the incoming change touches a modified
  file; the duty must report that refusal, not stash.
- "origin is ahead at the start of a task" must not turn every commit request into a merge:
  the sync is a fast-forward of the current branch only, after `git fetch`, and only when
  local has no commit origin lacks (else it is "diverged", reported).
- No sentence may suggest `--force`, `reset --hard`, `pull --rebase` or a rebase to make it fit
  (existing rebase of a track branch in "Merging a track back" is a different, user-gated step).
- Installed project: the ff may bring kit files → `kit_bring` ask; github.md should not tell the
  agent to avoid it, only to report it.
- github.md is a kit prompt: no per-project value (protected branch names) may enter the new
  text — it reads `protected_branches` like `:154` does since kit-prompts.

## Open questions
1. Does the start-of-task sync run before **every** github task (commit included), or only
   before push/merge/PR tasks? (Default proposed: every task does `git fetch origin` + reports
   ahead/behind; the ff itself only when the current branch is strictly behind.)
2. After a push, is a sync needed at all? (After a push local == origin by construction; the
   spec lists it — proposed: drop "after a push" as a trigger, keep the `Local:` line
   `up to date`.)
