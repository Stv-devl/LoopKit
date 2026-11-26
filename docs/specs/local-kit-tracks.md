# Spec: Local-kit tracks — fork a loop track when the project git-ignores the kit
Token profile: critical
Validation: moi

## Objective
A project that git-ignores the kit (`.claude/`, `CLAUDE.md`, loop `docs/`) can run
parallel loop tracks in worktrees through one supported kit script, without
versioning the kit, while a bare `git worktree add -b` stays denied.

## Context
EcoCrew's `.gitignore` keeps the whole agentic workflow local ("never pushed"):
`.claude/`, `CLAUDE.md`, `AGENTS.md`, `PRODUCT.md`, `DESIGN.md`, `workflow.py`,
`workflow.sh`, `codex-handoff.sh`, and the loop folders `docs/stories/`,
`docs/prd/`, `docs/architecture/`, `docs/product/`, `docs/work/`, `docs/specs/`,
`docs/research-cache/`, `docs/design-system*`. Today `worktree_kit_check`
(`enforce-git-workflow.sh`) denies the track fork and `/loop:tracks` /
`/loop:orchestrate` refuse: the only ways are "version the kit" or "stay
sequential". Hand-made forks (Oct 2026) hit: hooks resolved against the main
tree's `$CLAUDE_PROJECT_DIR`, `kit-attempts.py` needing an absolute path, symlinked
`docs/` failing on write, `docs/work/<slug>/` lost at `worktree remove`, project
env (`DWG2DXF_PATH`, `COMPOSE_PROJECT_NAME`), and a shared test DB broken by an
unmerged migration.

## Scope
- IN :
  - `.claude/scripts/kit-track.py fork <slug>` and `close <slug>` (one script,
    run in its own Bash call per the kit-script rule).
  - `fork`: refuses unless the project is kit-local (`check-ignore` of
    `.claude/hooks/probe` succeeds and HEAD tracks nothing under `.claude/hooks`),
    the tree is clean, and the slug/branch/path are free; creates
    `.claude/worktrees/<slug>` on `feat/<slug>` from the current branch; copies
    from the main tree: `.claude/` minus `worktrees/`, `.loop-record.json`,
    `.tdd-red/`, `.token-*`, `.restart-ready` and the other per-session runtime
    files; the root kit files (`CLAUDE.md`, `AGENTS.md`, `workflow.*`,
    `codex-handoff.sh`, and `PRODUCT.md`/`DESIGN.md` when present); the loop
    `docs/` folders that exist. Never copies a `.env*` file nor any
    `protect-files` path. Copies are regular files (no symlinks). Writes a hash
    manifest of the copied kit (`.claude/.kit-snapshot` in the worktree). Prints
    the hand-over: copy the env file yourself, install, the project overlay's
    env lines, and the exact `cd <worktree> && ./workflow.sh "…"` command.
  - Docs ownership in a track: owned = `docs/work/<slug>/` (incl. `handoff.md`)
    and the track's own story file; shared append-only = `docs/research-cache/`;
    read-only snapshot = everything else (board, brief, design system, other
    stories, PRD, architecture). The track's `/loop:ship` does not advance the
    board in a kit-local worktree; the board advances in the main tree at close.
  - `close <slug>`: copies back the owned paths and new `research-cache` files
    into the main tree; reports (never overwrites) modified `research-cache`
    files; reports kit drift both ways against the manifest (files changed in
    the track, files changed in the main tree since the fork); verifies each
    copy-back landed; only then runs `git worktree remove` without `--force`
    (a dirty tracked tree makes it refuse, and close stops there). Refuses an
    unmerged branch unless the user names it explicitly.
  - Guard: `worktree_kit_check` keeps denying the bare `-b` fork; its deny text
    names `kit-track.py fork <slug>` as the supported way for a kit-local project.
  - `/loop:tracks` on a kit-local project prepares each track with
    `kit-track.py fork <slug>` instead of refusing; `/loop:orchestrate` Phase 0.5
    names the script instead of only "run in the main tree".
  - `10-worktrees.md`: a short "Kit-local projects" section (fork/close, docs
    ownership, `EnterWorktree` never used to create or enter a kit-local track,
    session launched by `./workflow.sh` from the worktree, a track carrying a
    migration needs its own test DB or does not run in parallel) and a project
    slot `## local-kit env` in `.claude/overlays/guides/10-worktrees.md` that
    `fork` prints verbatim.
  - `/kit:doctor`: the existing ignored-`.claude/` finding names the script.
- OUT :
  - `resync` (pulling a newer main-tree kit into a live track) — drift is only
    reported at close; follow-up once seen in practice.
  - Exporting env or provisioning a per-track test DB from the kit — the project
    overlay slot holds it.
  - Any change for projects that version `.claude/` (current path unchanged).
  - `/loop:small` in kit-local mode.
  - Filling EcoCrew's overlay (done in EcoCrew after install).

## Data model
none

## Custom backend
NONE — kit tooling only (Python script, bash hook, prompts, guide).

## Front surface
none (kit: `.claude/scripts/kit-track.py`, `.claude/hooks/enforce-git-workflow.sh`,
`.claude/commands/loop/tracks.md`, `.claude/commands/loop/orchestrate.md`,
`.claude/guides/10-worktrees.md`, `.claude/hooks/kit-doctor.py`, tests in
`.claude/hooks/test-*.sh`)

## Acceptance criteria
- [ ] On a fixture repo that git-ignores `.claude/` and the loop `docs/`,
      `kit-track.py fork demo-1.1` creates `.claude/worktrees/demo-1.1` on
      `feat/demo-1.1`, with the kit files present, ignored by git there
      (`git status` clean), and no `worktrees/`, session/runtime file or `.env*`
      copied.
- [ ] A session hook run with `CLAUDE_PROJECT_DIR=<worktree>` resolves and fires
      from the worktree's own `.claude/` (proved by a hook test on the fixture).
- [ ] `fork` refuses, with a reason, on: a project that versions `.claude/`, a
      dirty tree, an existing slug/branch/path.
- [ ] A bare `git worktree add .claude/worktrees/x -b feat/x` on a kit-local
      project is still denied, and the deny text names `kit-track.py fork`.
- [ ] `close demo-1.1` after the branch is merged: `docs/work/demo-1.1/`
      (with `handoff.md`), the track's story file and a new
      `research-cache` file are present in the main tree; a modified
      `research-cache` file and a kit file changed on either side are reported,
      not overwritten; the worktree is removed without `--force`.
- [ ] `close` on a worktree with uncommitted tracked changes stops before any
      removal and loses nothing.
- [ ] `/loop:tracks`, `/loop:orchestrate` Phase 0.5, `10-worktrees.md` and
      `/kit:doctor` describe the kit-local mode consistently (doctor/contract
      tests green).
- [ ] Manual trial on EcoCrew after install: `/loop:tracks` on
      `docs/stories/agent-ia/` forks `agent-ia-3.7` and `agent-ia-3.2` without
      versioning the kit; a `./workflow.sh` session in one runs
      `/loop:orchestrate` to the PR; `close` brings `docs/work/<slug>/` back.

## Business logic to cover
- Kit-local detection (ignored probe and nothing tracked under `.claude/hooks`).
- The copy set: what is included, what is excluded (worktrees, session/runtime
  files, env and protected files), regular files only.
- Manifest and drift: changed-in-track, changed-in-main, unchanged.
- Close ownership: owned paths copied back, research-cache new vs modified,
  read-only snapshot ignored; verification before removal; refusal paths
  (dirty tree, unmerged branch, unknown slug).
- Guard deny text for the bare fork in kit-local mode.
