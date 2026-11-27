# Spec: kit-track robustness
Token profile: standard
Validation: moi

## Objective
`kit-track.py fork/close` leaves no half-built state on failure, accepts normal
project layouts, and the track prompts tell the agent exactly what a kit-local
track session does.

## Context (verified 2026-11-27 at 7ebc764, reproduced in a throwaway repo)
- K1 (major) fork has no rollback after `git worktree add` (kit-track.py:202-210):
  an unreadable kit file → PermissionError traceback, worktree + branch + partial
  `.claude/` left, no `.kit-snapshot`; re-fork says "already exists", close says
  "no .kit-snapshot". Contradicts the docstring (:8 "a refusal creates and
  removes nothing").
- K2 symlinks are refused before the skip/ignore filters (:107-121): a
  `CLAUDE.md -> AGENTS.md` link, or a symlinked `.claude/settings.local.json`
  (never copied), blocks every fork.
- K3 a malformed `.kit-snapshot` gives a JSONDecodeError traceback on close (:307).
- K4 copy-back is not atomic (:339-347): files already copied before a failure
  are in main but never reported; a rerun reports only the rest.
- K5 SKIP_NAMES (:34-38) misses `project.proposed.json`, `project.snapshot.json`,
  `.ruff_cache/`, `.loop-record.*.tmp` → spurious `kit drift` lines.
- K6 tracks.md:190-203 and orchestrate.md:262-266 say "enters with EnterWorktree"
  unscoped, and the hand-over template has no `cd … && ./workflow.sh` /
  `local-kit-env` lines for a kit-local track.
- K7 orchestrate step 4 "any other exit gives it back → BLOCKED" makes the main
  session block the kit-local line it just handed over.
- K8 tracks.md:38-39 `closed`/`orphaned` handling differs from orchestrate.md:166-167.
- Test gaps: test-kit-track.sh (detached HEAD, run from a worktree, missing
  snapshot, verify mismatch, remove failure, KT18 exit code, KT27/28 assertions
  too loose), test-small-lane.sh N3 has no no-snapshot control,
  test-workflow-contracts.sh WT13.2 / WT1 / WT2 pins incomplete.
- Source list: docs/work/local-kit-tracks/follow-ups.md (+ loop-to-pr #10,
  agent-ia-trial-fixes #14).

## Scope
- IN : K1-K8 and the listed test gaps.
- OUT: TOCTOU, crafted snapshot keys, symlinked `docs/` (careless-agent threat
  model, refuted); moving the session-file list to one shared copy beyond what K5
  needs (note it, do not refactor kit-doctor/install.sh in this pass).

## Data model
none

## Custom backend
NONE — kit tooling only.

## Front surface
none (`.claude/scripts/kit-track.py`, tracks.md, orchestrate.md, kit suites).

## Acceptance criteria
- [ ] A fork that fails after `git worktree add` exits non-zero with one line and
      leaves no worktree, no branch and no partial copy; a second fork then works.
- [ ] A project with `CLAUDE.md -> AGENTS.md`, or a symlinked skipped file, forks;
      a symlink inside what is actually copied is still refused.
- [ ] A malformed `.kit-snapshot` makes close refuse with one line, no traceback,
      nothing written.
- [ ] A copy-back interrupted mid-way reports every file already copied; a rerun
      finishes and the union of reports names every file.
- [ ] Runtime/session files (the four names) never appear as `kit drift`.
- [ ] tracks.md and orchestrate.md tell a kit-local track to be handed over by
      `cd <track> && ./workflow.sh …`, never entered; the main session does not
      mark a handed-over line BLOCKED; closed/orphaned handling matches in both.
- [ ] Every listed test gap has a case that fails on the current code where the
      defect exists, and the contracts suite pins the new wording.

## Business logic to cover
- fork rollback on every failure after the worktree exists.
- symlink check applied only to what is copied.
- snapshot validation on close.
- copy-back reporting under partial failure.
- skip list completeness.
