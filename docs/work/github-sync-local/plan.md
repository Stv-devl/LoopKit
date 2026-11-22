# Plan: the github agent keeps the local repository up to date   (entry: docs/specs/github-sync-local.md · research: docs/work/github-sync-local/research.md · design: n/a)
Token profile: economy
Base: 98d00ba

## Skips
- DB, Backend, Front, Wiring : SKIP — kit prompt + shell suites only.
- INTERFACE : SKIP — no user surface.
- Hook change : SKIP — research shows no sync command is denied (`git fetch origin` allowed,
  `merge --ff-only` default prompt / merge ask on a protected branch, `fetch <b>:<b>` ask).

## Write chain (sequential)
1. RED — append GS1-GS6 to `.claude/hooks/test-workflow-contracts.sh` (after PK24, before the
   final echo) and fixture rows G20.001-G20.002 to `.claude/hooks/fixtures/_harness/git-guard.jsonl`;
   run the contracts suite, observe GS1 fail (section absent). G20.001-002 pass at once (they pin
   current hook behaviour; no hook change). `git fetch origin` → pass is already pinned by
   G16.073 (cited for AC5, no duplicate row).
2. GREEN — Edit `.claude/agents/github.md`:
   - new section `### Keeping local in sync` after "Merging a track back" (:216), before
     `## Output format`, with the pinned phrases of "Contracts" verbatim;
   - Output format block gains the `- Local:` line of "Contracts" between `- Remote:` and `- PR:`;
   - "Merging a track back" step 6 gets the clause "then Keeping local in sync" right after
     `git branch -d feat/<slug>` (before the **Exception** paragraph), and `pr-assets` Clean up
     step 3 ends with the same clause (one clause each, no new step).
3. Run contracts, test-hooks, kit-doctor, rules floor.

## Parallel lots (inside this track, same tree)
none — fully sequential.

## Track isolation
- Worktree: none, single track (main tree, audit/slim).
- Shared foundations touched: none (a kit prompt and two test files).

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/agents/github.md` | Edit | the duty + `Local:` line |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | GS1-GS6 |
| `.claude/hooks/fixtures/_harness/git-guard.jsonl` | Edit | G20.001-G20.002 hook verdict pins |

## Contracts
Text of the new section. The implementer may reword around them, but the **pinned phrases**
(in «») are written verbatim, each on ONE line, and are what GS1-GS6 grep for:

```
### Keeping local in sync

The remote moved, so local follows — never left behind, never forced.

When:
- «after a merge you ran» (a track or small branch merged back);
- «after a PR you merged or found `MERGED`» on GitHub;
- «at the start of a task, when origin is ahead» of the current branch (the fetch says so).

1. «`git fetch origin`».
2. Current branch strictly behind → «`git merge --ff-only origin/<branch>`».
3. A PR merged into a base branch that is not checked out → «`git fetch origin <base>:<base>`».
   The hook asks on it (it moves a local branch): that ask is the user's, expected here —
   never route around it with `update-ref` or `branch -f`.
4. «Diverged or blocked: report it, change nothing.» Diverged = local commits origin lacks;
   blocked = «a dirty tree the fast-forward would overwrite» (never stashed).
«Never `--force`, `reset --hard`, `pull --rebase` or a rebase to make the sync fit.»

Report it in the `Local:` line.
```

Output line (one line, verbatim): `- Local: <branch> <old>..<new> fast-forwarded   (or "up to date" / "diverged: <branch> — <n> local / <m> remote commits, not touched")`

## Decisions for the gate (research open questions)
- Q1 start-of-task sync: every github task starts with `git fetch origin` (allowed, no prompt);
  the fast-forward runs only when the current branch is strictly behind; a commit request on a
  diverged branch is reported, never merged. → decides GS3 (third trigger).
- Q2 "after a push": dropped as a trigger — after a push local == origin by construction; the
  `Local:` line still reports `up to date`. → AC1 amended to "the three triggers" (spec line
  updated on the go). Decides GS3.

## Test plan (gate — validated by the user before EXECUTE)

No test-first layer (no `utils`/`mapper`/`repository`/`services` file). The contract cases
are the frozen tests of this pass.

#### `.claude/hooks/test-workflow-contracts.sh` (appended block, after PK24)
**Core behaviour**
"The section" = the lines from `### Keeping local in sync` to the next `##`/`###` heading.
- [ ] GS1 github.md has a `### Keeping local in sync` section placed before `## Output format`
- [ ] GS2 the section contains the three command phrases `` `git fetch origin` ``,
      `` `git merge --ff-only origin/<branch>` `` and `` `git fetch origin <base>:<base>` ``
- [ ] GS3 the section contains the three trigger phrases `after a merge you ran`,
      `after a PR you merged or found` and `at the start of a task, when origin is ahead`
**Business rules**
- [ ] GS4 the section contains `Diverged or blocked: report it, change nothing.`,
      `a dirty tree the fast-forward would overwrite`, and the one-line
      sentence `Never `--force`, `reset --hard`, `pull --rebase` or a rebase to make the sync fit.`
- [ ] GS5 between `## Output format` and the end of the file (the fenced report opens with its
      own `## Git` line, so no heading bound) a line starting `- Local:` contains
      `<old>..<new>`, `up to date` and `diverged:`
**Edge cases**
- [ ] GS6a inside the section, every line matching `--force|reset --hard|rebase` is the Never
      sentence line or the "never route around it" line (which names none of the three) —
      i.e. any other section line naming them fails
- [ ] GS6b file-wide, `reset --hard` and `pull --rebase` occur only on the Never sentence line
- [ ] GS7 (added, review round 1 R1) the section defines diverged as `commits on both sides`, and
      the `- Local:` line carries `ahead:` (a branch only ahead is not diverged)

#### `.claude/hooks/fixtures/_harness/git-guard.jsonl` (hook verdict pins, AC5)
- [ ] G20.001 `git fetch origin main:main` → ask, reason contains `local branch`
- [ ] G20.002 `git merge --ff-only origin/main` → pass (fixture feature tree, not on a protected
      branch)
- (existing) G16.073 `git fetch origin` → pass

## Vigilance (carried from research)
- The base-branch update `fetch origin <base>:<base>` asks; github.md treats the ask as the
  user's and never routes around it (`update-ref`, `branch -f`).
- The current branch always takes `merge --ff-only`; `fetch <b>:<b>` is only for a branch not
  checked out (git refuses the checked-out one).
- A dirty tree blocking the ff is reported, never stashed.
- Start-of-task sync never turns a commit request into a merge of diverged history: ff only
  when strictly behind.
- No sentence suggests `--force`, `reset --hard`, `pull --rebase` or a rebase for the sync.
- In an installed project the ff may bring kit files → `kit_bring` ask; github.md reports it,
  never avoids it.
- No per-project value (branch names) enters github.md; protected branches stay read from
  `protected_branches`.
- (critic F7) The "then Keeping local in sync" clause of track-back step 6 sits right after
  `git branch -d feat/<slug>`, never after the **Exception** paragraph (no sync while the
  worktree is still active), and does not join the `never --force` sentence.
- (critic F6) Pinned phrases stay on one line each, verbatim; rewording them is a frozen-test
  correction, not a style edit.

## Acceptance criteria (carried from the entry artifact)
- [ ] `github.md` names the three triggers, the fetch + ff-only commands, and the
      diverged / dirty-tree report-not-fix rule.
- [ ] `github.md`'s Output format has a `Local:` line with its three forms.
- [ ] No sentence of `github.md` allows `--force`, `reset --hard` or a rebase to make the sync fit.
- [ ] A contract case fails when any of the above is removed from `github.md`.
- [ ] `enforce-git-workflow.sh` does not deny `git fetch origin`, `git merge --ff-only origin/<b>`
      or `git fetch origin <base>:<base>` (observed by a hook run or an existing case).
- [ ] `test-workflow-contracts.sh`, `test-hooks.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Gate
- 2026-11-18 go
- Contract: as written (Q2 applied: spec trigger list and AC1 now "three triggers")
- Q1 start-of-task sync → every github task fetches; ff only when strictly behind
- Q2 after a push → dropped as a trigger

## Plan critic
- pass 1: completeness 68, quality 70 — F1, F2, F4 Major → rewrite
- pass 2: completeness 92, quality 86 — F1, F2, F4 fixed; Minors F8-F11 (F8, F9, F10 applied
  before the gate; F11: G20.001 near-duplicates G17.26, G20.002 is a weak pin since origin/main
  does not resolve in the fixture repo — kept, watched at RED)
- surviving blockers: none
