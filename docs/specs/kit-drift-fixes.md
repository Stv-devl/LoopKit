# Spec: kit drift fixes (server roots, pr-assets push, prompts)
Token profile: critical
Validation: moi

## Objective
Server roots are detected and kept correctly so backend authorization checks
arm, the pr-assets push carries only this pass's assets, and the kit prompts
match what the hooks actually accept.

## Context (verified 2026-11-27 at 7ebc764)
- D1 (major) enforce-git-workflow.sh:2253-2262 allows the `pr-assets` push on a
  fast-forward test only (`merge-base --is-ancestor`), while kit-pr-assets.py
  `pick_parent` (:207-217) builds on the newer of local and origin: a cleanup
  drop commit the user declined, or another pass's unpushed images, ride out
  with a later push unprompted.
- D2 (major) project_config.py:132 detects server roots at depth ≤1 only: a
  `services/api/app` backend gets no root, authz never arms.
- D3 `wire fastapi` (:477-481), called by install.sh:551 on every install, adds
  bare `app`/`alembic` to `server_roots` and `protected_dirs` even when prefixed
  roots (`backend/app`) are declared.
- D4 `_is_server_dir` (:124-129) checks markers only for `app`: any `supabase` or
  `alembic` folder is proposed.
- D5 kit-doctor `check_server_roots` (:146-172) never checks that a declared root
  exists: a moved backend silently disarms authz.
- D6 `/kit:init` step 14 runs `project_config.py detect-server-roots .`, which no
  allow list holds → a prompt every init.
- D7 worktree_kit_check (enforce-git-workflow.sh:2274) needs `git worktree`
  adjacent: `git -C <root> worktree add .claude/worktrees/x` skips it.
- D8 `/loop:small` has no up-front ignored-`.claude/` probe (deny lands after the
  user's go) and the deny says `<slug>` where small.md expects `small-<name>`.
- D9 hook-lib.sh:72 `__cwk_exit` prints a raw ask that reaches the user in auto
  (degraded config only).
- D10 github.md:149 does not say `-C` must be absolute for push / pr-assets, and
  "`cd <root> &&` cannot place" is stale for read-only git and fetch.
- D11 orchestrate.md:96 expects a `Next:` line and review.md:264 a round/verdict
  that the handoff template / `review_status` enum (handoff/codex.md:35-60) lack.
- D12 install.sh:952 ignored-`.claude` warning regex misses `.claude/*`, `.claude/**`.
- D13 kit-doctor `worktree-kit` and `ignored-loop-paths` report the same ignore
  line with different remedies.
- Sources: docs/work/agent-ia-trial-fixes, python-red-import, auto-mode-2.5-fixes
  follow-ups.

## Scope
- IN : D1-D13.
- OUT: `_server_roots` without `_check_real` (symlinked backend parent, known
  limit); SERVER_DIR_SEQUENCE/ADDON_DIRS dedupe (no failure); root-fetch env
  forms (refuted).

## Data model
none

## Custom backend
NONE — kit tooling only.

## Front surface
none (enforce-git-workflow.sh, kit-pr-assets.py, project_config.py,
kit-doctor.py, hook-lib.sh, install.sh, settings.json, github.md, small.md,
init.md, orchestrate.md, review.md, handoff/codex.md).

## Acceptance criteria
- [ ] The pr-assets push is allowed only when every commit it adds is this pass's
      assets commit; a declined cleanup commit or a foreign pass's commit under it
      makes it ask (moi) / blocked stop (auto).
- [ ] `detect-server-roots` proposes a backend at depth 2 with its markers, and no
      longer proposes a marker-less `supabase`/`alembic` folder.
- [ ] Re-installing fastapi on a project with prefixed roots leaves
      `server_roots` and `protected_dirs` unchanged.
- [ ] kit-doctor reports a declared server root missing on disk, and reports one
      remedy per ignore line.
- [ ] `/kit:init` step 14 runs without a permission prompt; the new allow is the
      exact read-only command, nothing wider.
- [ ] `git -C <abs root> worktree add .claude/worktrees/x …` on an ignored
      `.claude/` gets the same deny as the bare form.
- [ ] `/loop:small` refuses an ignored `.claude/` before the go, naming the exact
      `kit-track.py fork small-<name>` command.
- [ ] In auto, a degraded-config git ask ends as a blocked stop, not a prompt.
- [ ] The prompt wording (D10, D11) matches the hooks and the handoff template;
      the contracts suite pins it; install warns on `.claude/*`.

## Business logic to cover
- pr-assets push content check.
- server-root detection depth and markers; fastapi wire idempotence on prefixed
  roots; doctor root-exists check.
- worktree kit check on `git -C`.
- degraded ask routed through the auto-aware ask.
