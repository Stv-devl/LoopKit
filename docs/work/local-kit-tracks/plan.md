# Plan: Local-kit tracks   (entry: docs/specs/local-kit-tracks.md · research: docs/work/local-kit-tracks/research.md · design: n/a)
Token profile: critical
Base: 689b9ba8b2e3e54d6ec28518e8eb2bc824087ccf

## Skips
- DB, Backend, Front, Wiring, UI : SKIP — kit script, hook text, prompts, guide only (INTERFACE SKIP).
- Test-first TS/Python layers : none — kit tests are shell fixture suites under `.claude/hooks/`, outside the
  freeze matcher. Each step is still test-first: its cases are written and observed red before the code.
- `resync`, env export / per-track DB provisioning, `/loop:small` kit-local, versioned-kit path : OUT per spec.

## Proposed answers to research's open questions
1. Location → keep the spec's `.claude/scripts/kit-track.py` (the guard's `kit_path` covers `.claude/scripts/`,
   `install.sh` `copy_tree` ships it, invoked as `python3 …` so the `.sh` exec-bit check does not apply; no
   `NON_HOOKS` entry needed). No contract amendment.
2. Permission → `python3 .claude/scripts/kit-track.py fork *` in the settings allow list and `install.sh`
   `PROMPT_ALLOWS`; `close` stays prompting (it removes a tree).
3. `.claude/.tdd-unfrozen` → not copied; each track starts with none and records its own corrections.
4. Copy-back conflict → a file the track changed is copied back only when the main-tree copy still matches the
   fork manifest (or is absent); otherwise main is kept and the track's version is written beside it as
   `<file>.from-<slug>`, reported. Same rule for the story file, `docs/work/<slug>/` and `research-cache`
   (a modified `research-cache` file is always reported + sidecar, never overwritten, per spec).
5. Ordering → **one kit-local closing order**, from a main-tree session (a track session's toplevel is the
   worktree, where `close` is refused): (a) `python3 .claude/scripts/kit-track.py close <slug> --merged` — copies
   back `docs/work/<slug>/` (handoff included, still `awaiting-merge`), the story and new research-cache files, then
   removes the tree; the worktree's `.loop-record.json` is an ignored file and goes with it, so no
   `loop-record.py --clear` runs for a kit-local worktree; (b) `/loop:ship` step 5 in the main tree (story `Done`,
   board); (c) the **main-tree** copy of `docs/work/<slug>/handoff.md` → `phase: shipped` (Edit); (d)
   `git branch -d feat/<slug>`. Written in the three copies of the closing order: `orchestrate.md` Phase 0 step 0,
   `tracks.md` step 0, `ship.md` (4bis-PR closing sentence and 4bis-local item 3). `--merged` is passed only after
   `loop-pr-state.sh` printed `closable` (a squash-merged PR is not a git ancestor); `close` stays a prompted call,
   so the user sees it (spec: "unless the user names it explicitly").
6. `/kit:doctor` → keep `worktree-kit` as DIVERGENCE (spec: "names the script"), its detail now offering
   `kit-track.py fork` beside versioning; `ignored-loop-paths` unchanged (OUT, follow-up).
- Interpretation flagged for the gate: `/loop:ship` `4bis-local` item 3 gets one line routing a kit-local
  worktree to `close` (the closing check calls item 3; without it the bare `remove` still deletes the copies).

## Write chain (sequential)
1. `test-kit-track.sh` fork cases KT1-KT13 → observed red → `kit-track.py` `fork` (+ shared detection, copy set,
   manifest) → green.
2. `test-kit-track.sh` close cases KT14-KT25 → red → `kit-track.py` `close` → green.
3. `git-guard.jsonl` G22.122-G22.123 + one `shell-guard.jsonl` row (next free id) for the fork call → red →
   `enforce-git-workflow.sh:2273` deny text → green (G22.115-117 stay).
4. `test-kit-doctor.sh` DW6, `test-install.sh` IW3 → red → `kit-doctor.py:697-718` detail, `install.sh:951-956`
   warning (keep the phrase `ignore .claude/ lui-même`) → green.
5. `test-workflow-contracts.sh` WT4-WT12 → red → `tracks.md` (step 0 closing order + step 4), `orchestrate.md`
   (Phase 0 step 0 + Phase 0.5), `ship.md` (4bis-PR closing sentence + 4bis-local item 3), `10-worktrees.md`, `templates/overlays/guides/10-worktrees.md`, `kit/doctor.md:65`,
   `.claude/settings.json`, `install.sh` `PROMPT_ALLOWS`, `.github/workflows/kit-ci.yml` → green.
6. Refactor under the green suites (`test-hooks.sh`, `test-kit-doctor.sh`, `test-install.sh`,
   `test-workflow-contracts.sh`, `test-kit-track.sh`, `/kit:doctor`), no case edited.
7. Manual EcoCrew trial (after the pass merges, the user installs the kit into EcoCrew): the post-install gate
   in Test-after, its result recorded in `docs/work/local-kit-tracks/follow-ups.md` as `EcoCrew trial: pass |
   fail: <what>`; the PR body states it as pending until then.

## Parallel lots (inside this track, same tree)
none — fully sequential (steps 3-5 are small and share `install.sh` / the contracts suite).

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: the git guard hook, `settings.json`, `install.sh` — no other kit pass in parallel.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/scripts/kit-track.py` | Create | `fork` / `close` |
| `.claude/hooks/test-kit-track.sh` | Create | KT cases, fixture repo |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | deny text names the script |
| `.claude/hooks/fixtures/_harness/git-guard.jsonl` | Edit | G22.122-123 |
| `.claude/hooks/fixtures/_harness/shell-guard.jsonl` | Edit | row: `python3 .claude/scripts/kit-track.py fork x` passes |
| `.claude/hooks/kit-doctor.py`, `.claude/commands/kit/doctor.md` | Edit | `worktree-kit` detail |
| `.claude/hooks/test-kit-doctor.sh`, `.claude/hooks/test-install.sh` | Edit | DW6, IW3 |
| `install.sh` | Edit | warning text, `PROMPT_ALLOWS` |
| `.claude/settings.json` | Edit | allow `fork` |
| `.claude/commands/loop/tracks.md` | Edit | step 0 kit-local closing order, step 4 kit-local fork |
| `.claude/commands/loop/orchestrate.md` | Edit | Phase 0 step 0 kit-local closing order, Phase 0.5 |
| `.claude/commands/loop/ship.md` | Edit | 4bis-PR closing sentence + 4bis-local item 3: kit-local `close` |
| `.claude/guides/10-worktrees.md` | Edit | "Kit-local projects" + slot `local-kit-env` |
| `templates/overlays/guides/10-worktrees.md` | Edit | `## local-kit-env` FILL |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | WT4-WT12 |
| `.github/workflows/kit-ci.yml` | Edit | run `test-kit-track.sh`; ruff also on `.claude/scripts` |

## Contracts
`python3 .claude/scripts/kit-track.py fork <slug>` / `close <slug> [--merged]`, run from the project root
(cwd = `git rev-parse --show-toplevel`, else refused). Exit 0 done, 2 refused (stderr `kit-track: <reason>`),
nothing created or removed on a refusal.
- slug: `[a-z0-9][a-z0-9.-]*`, no `..`; path `.claude/worktrees/<slug>`, branch `feat/<slug>`, start point = the
  main tree's current branch.
- kit-local: `git check-ignore -q .claude/hooks/probe` succeeds and `git ls-tree -r --name-only HEAD -- .claude/hooks`
  is empty.
- Copy set (only paths git-ignored in the main tree, regular files, symlink anywhere in the set → refused before the
  worktree is created): `.claude/**` minus `worktrees/`, `kit-backup/`, `.tdd-red/`, `.tdd-unfrozen`,
  `.loop-record.*`, `.token-*`, `.restart-ready`, `.codex-ready`, `.quota-warning`, `.kit-health.jsonl`,
  `.hook-timings.log`, `.eslint-queue*`, `settings.local.json`, `.kit-snapshot`, `__pycache__/`, `*.pyc`;
  root `CLAUDE.md`, `AGENTS.md`, `PRODUCT.md`, `DESIGN.md`, `workflow.py`, `workflow.sh`, `codex-handoff.sh` when
  present; `docs/stories/`, `docs/prd/`, `docs/architecture/`, `docs/product/`, `docs/work/`, `docs/specs/`,
  `docs/research-cache/`, `docs/design-system*` minus `docs/work/*/handoff.md`, `codex-last-message.txt`,
  `pr-body.md`. Never `.env*`, `*.pem`, `*.key`, `credentials.*` (the `protect-files` secret/env patterns).
- Manifest `<worktree>/.claude/.kit-snapshot` (JSON): `slug`, `base`, `base_sha`, `files: {path: sha256}`.
- `close` order: refusals (slug, registered worktree, merged = ancestor of the main tree's current branch or
  `--merged`, worktree `status --porcelain` empty) → copy-back (owned: `docs/work/<slug>/**`, the story file
  `docs/stories/<feature>/<epic>.<story>.md` derived from the slug; `docs/research-cache/` new files) with the
  conflict rule of answer 4 → verify each copied file's sha256 in main → drift report → `git worktree remove`
  (no `--force`) → print `next: /loop:ship step 5, main-tree handoff → phase: shipped, then git branch -d feat/<slug>`. Any
  copy-back or verify failure exits 2 before `remove` (copies already landed stay; a rerun is idempotent). An owned
  destination tracked in main is refused before any copy-back. `ship.md:256` ("4bis-local runs this step right after
  the merge") gains "after `close` for a kit-local worktree".
- Report lines: `copied <path>`, `conflict <path> → <path>.from-<slug>`, `research-cache modified <path>`,
  `snapshot change ignored <path>`, `kit drift track-changed <path>`, `kit drift main-changed <path>`.

## Test plan (gate — validated before EXECUTE)

### Test-first — none (no TS/Python test-first layer); kit fixture cases, each observed red before its code

#### .claude/hooks/test-kit-track.sh — fork (fixture: repo whose `.gitignore` ignores `.claude/`, root kit files and the loop `docs/` folders; kit = a copy of this repo's `.claude/` + fake runtime files, `.env`, `.env.local`, `x.pem`, `settings.local.json`, `.tdd-unfrozen`, `docs/work/old/handoff.md`)
**Core behaviour**
- [ ] KT1 `fork demo-1.1` creates `.claude/worktrees/demo-1.1` registered in `git worktree list`, on a new branch `feat/demo-1.1` whose start point is the main tree's current branch
- [ ] KT2 the worktree holds byte-identical copies of `.claude/hooks/enforce-git-workflow.sh`, `.claude/project.json`, `.claude/INSTALL_PROFILE`, `.claude/kit-manifest`, `.claude/overlays/guides/10-worktrees.md`, `CLAUDE.md`, `AGENTS.md`, `workflow.py`, `workflow.sh`, `codex-handoff.sh`, `docs/stories/demo/1.1.md`, `docs/research-cache/settled.md`
- [ ] KT3 `git -C <worktree> status --porcelain` prints nothing after the fork (the copies are ignored there)
- [ ] KT4 a real copied hook fires from the worktree's kit: `protect-files.sh` run from `<worktree>/.claude/hooks/` with `CLAUDE_PROJECT_DIR=<worktree>` denies a Read of `<worktree>/.env`
- [ ] KT5 `.claude/.kit-snapshot` in the worktree is JSON naming `demo-1.1`, the base branch and sha, and a sha256 for every copied file (checked on three files against `sha256sum`)
- [ ] KT6 the output names the env file to copy by hand, the install, `cd .claude/worktrees/demo-1.1 && ./workflow.sh`, and prints the main tree's `## local-kit-env` overlay section verbatim
**Business rules**
- [ ] KT7 none of `.claude/worktrees/`, `.loop-record.json`, `.tdd-red/`, `.token-warning`, `.restart-ready`, `.kit-health.jsonl`, `settings.local.json`, `.tdd-unfrozen`, `docs/work/old/handoff.md`, `.env`, `.env.local`, `x.pem` exists in the worktree
- [ ] KT8 a project that tracks `.claude/hooks` (versioned kit) is refused `not kit-local`, no worktree, no branch
- [ ] KT9 a dirty tracked file in the main tree is refused, no worktree, no branch
- [ ] KT10 an existing `.claude/worktrees/demo-1.1` path or `feat/demo-1.1` branch is refused, the existing one untouched
**Edge cases**
- [ ] KT11 slugs `../x`, `A B`, `-x`, `` are refused
- [ ] KT12 a symlink inside the copy set is refused, naming it, before any worktree is created
- [ ] KT13 run from a subfolder of the project is refused (cwd must be the toplevel)

#### .claude/hooks/test-kit-track.sh — close (fixture: KT1's fork, then commits on `feat/demo-1.1` merged with `git merge --ff-only` into the base unless said)
**Core behaviour**
- [ ] KT14 `close demo-1.1` copies `docs/work/demo-1.1/research.md` and `handoff.md` created in the track into the main tree byte-identical, then the worktree is gone from `git worktree list` and from disk, and `feat/demo-1.1` still exists
- [ ] KT15 the story `docs/stories/demo/1.1.md` changed in the track and unchanged in main is copied back
- [ ] KT16 a new `docs/research-cache/x.md` from the track is copied back
- [ ] KT17 a kit file changed in the track is reported `kit drift track-changed <path>`; a kit file changed in main since the fork is reported `kit drift main-changed <path>`; neither file is overwritten
**Business rules**
- [ ] KT18 the story changed in both trees keeps main's content; the track's is written to `docs/stories/demo/1.1.md.from-demo-1.1` and reported `conflict`
- [ ] KT19 `docs/research-cache/settled.md` modified in the track leaves main's untouched, is reported `research-cache modified`, sidecar written
- [ ] KT20 `docs/product/backlog.md` changed in the track is not copied back, reported `snapshot change ignored`
- [ ] KT21 an uncommitted tracked change in the worktree is refused before any copy-back: main unchanged, worktree intact
- [ ] KT22 an unmerged branch is refused without `--merged`; the same call with `--merged` completes as KT14
- [ ] KT24 a copy-back that cannot land (a regular file standing at main's `docs/work/demo-1.1`) exits 2 naming it; the worktree is still registered and on disk with its `docs/work/demo-1.1/` intact, `feat/demo-1.1` untouched
- [ ] KT25 an owned destination tracked in main (`docs/stories/demo/1.1.md` committed in main) is refused before any copy-back, worktree intact
**Edge cases**
- [ ] KT23 an unknown slug, or a `.claude/worktrees/<slug>` directory not registered as a worktree, is refused

#### .claude/hooks/fixtures/_harness/git-guard.jsonl
- [ ] G22.122 deny, setup `lpwtignored`, `git worktree add .claude/worktrees/x -b feat/x2 main`, reason contains `kit-track.py fork`
- [ ] G22.123 pass, setup `lpwtignored`, `python3 .claude/scripts/kit-track.py fork x` (the git guard does not deny the script)

#### .claude/hooks/test-kit-doctor.sh
- [ ] DW6 on a `.claude/`-ignored fixture, the `worktree-kit` DIVERGENCE detail names `kit-track.py fork`

#### .claude/hooks/test-install.sh
- [ ] IW3 the install warning for a target ignoring `.claude/` names `kit-track.py fork` (IW1-IW2 unchanged)

#### .claude/hooks/test-workflow-contracts.sh
- [ ] WT4 `tracks.md` step 4 names `python3 .claude/scripts/kit-track.py fork <track-slug>` for a kit-local project and no longer says "Refuse to fork"; it keeps the `check-ignore -q` probe (WT1)
- [ ] WT5 `orchestrate.md` Phase 0.5 names `kit-track.py fork` (below the `## Phase 0.5 —` heading); Phase 0 step 0, for a kit-local worktree, names in this order `kit-track.py close <slug> --merged`, then step 5, then the main-tree handoff → `phase: shipped`, then `git branch -d`, and says no `loop-record.py --clear` runs for it
- [ ] WT6 `ship.md` 4bis-PR closing sentence and 4bis-local item 3 name `kit-track.py close` for a kit-local worktree, run from a main-tree session, before step 5
- [ ] WT12 `tracks.md` step 0 states the same kit-local order as WT5 (`close --merged` before step 5, main-tree handoff → `shipped`, then `git branch -d`)
- [ ] WT7 `10-worktrees.md` has a `Kit-local projects` section naming `kit-track.py fork`, `kit-track.py close`, `./workflow.sh` from the worktree, `EnterWorktree` excluded, and the migration/test-DB limit; the "Three things" bullet no longer says such a project "never forks"
- [ ] WT8 `10-worktrees.md` declares `**Project slot \`local-kit-env\`**` and the overlay template carries `## local-kit-env` (PK16 green)
- [ ] WT9 `.claude/settings.json` allows `python3 .claude/scripts/kit-track.py fork *` and has no `close` allow; `install.sh` `PROMPT_ALLOWS` carries the same fork entry
- [ ] WT10 `.github/workflows/kit-ci.yml` runs `test-kit-track.sh`
- [ ] WT11 `kit/doctor.md` `worktree-kit` row names `kit-track.py fork`

### Test-after
- `/kit:doctor` run on the repo at the end.
- **Post-install manual gate (spec's last criterion, run by the user on EcoCrew after merge + install):**
  (1) `/loop:tracks` on `docs/stories/agent-ia/` forks `agent-ia-3.7` and `agent-ia-3.2` with `git ls-files .claude`
  still empty in EcoCrew; (2) a `./workflow.sh` session started in one worktree shows its hooks firing (statusline
  present, a guarded write asked) and runs `/loop:orchestrate` to the PR; (3) `close <slug> --merged` from the main
  tree brings `docs/work/<slug>/` back and removes the tree without `--force`. Result recorded in
  `docs/work/local-kit-tracks/follow-ups.md` (`EcoCrew trial: pass | fail: <what>`).

## Vigilance (carried from research)
- The copy set excludes every runtime/session/secret path listed in Contracts, and includes `project.json`,
  `kit-manifest`, `INSTALL_PROFILE`, `VERSION`, `workflow-routing.yml`, `.size-exempt`, `overlays/` and the root kit files.
- Copies are regular files; a symlink is refused, never recreated or followed.
- Copy-back never overwrites a main-tree file changed since the fork (manifest compare); conflicts go to `.from-<slug>`.
- `close` verifies every copy-back before `git worktree remove`; `remove` never gets `--force`; a refusal removes nothing.
- The script's own git calls are invisible to the hooks: every refusal (dirty, existing, unmerged, not root, not
  kit-local) lives in the script and is tested.
- The bare `git worktree add … -b` stays denied on a kit-local project; only its text changes (G22.115 still green).
- Phase 0.5 text stays below its heading (contract slice `test-workflow-contracts.sh:354`); WT1/WT2/WT2.3 probe
  strings kept; WT2.2's forbidden phrase not reintroduced.
- `EnterWorktree` is never the way into a kit-local track; the session starts with the worktree's own `./workflow.sh`.
- Slot name is `local-kit-env` (PK16 regex `[a-z-]+`).
- Secrets: the script never opens a `.env*` or protected file, even to skip it by content.
- (critic F3) The story file derives from the slug by a **last-hyphen** split (`agent-ia-3.7` →
  `docs/stories/agent-ia/3.7.md`); the close fixture uses a hyphenated feature too.
- (critic F4) KT7's fixture creates every excluded path of the Contracts list (incl. `kit-backup/`,
  `.loop-record.lock`, `.codex-ready`, `.quota-warning`, `.hook-timings.log`, `.eslint-queue*`, `*.key`,
  `credentials.*`, `codex-last-message.txt`, `pr-body.md`) and asserts each absent.
- (critic F7) The secret exclusion is the `protect-files` secret/env patterns, **not** `cwk_is_guarded` (a write
  guard list that covers the kit files that must be copied).
- (critic F8) KT4 proves resolution, not a fail-closed deny: the deny reason is the `.env` one, and the hook is run
  through the worktree's `settings.json` command string with `CLAUDE_PROJECT_DIR=<worktree>`.
- (critic F9) KT8's fixture ignores `.claude/` **and** force-tracks `.claude/hooks/x`, so the `ls-tree` half is tested alone.
- (critic F10) The ship.md line says `close` runs from a main-tree session; a track session never falls back to a bare `git worktree remove`.
- (critic F11) Phase 0.5 hands a kit-local track over as `cd <worktree> && ./workflow.sh "…"`, never `EnterWorktree`.
- (critic F12) Copy-back of a file absent from the manifest but present in main → sidecar `.from-<slug>`, never
  overwrite; new files in snapshot folders → `snapshot change ignored`; an owned destination tracked in main → refused before removal.
- (critic F13) CI's ruff step covers `.claude/scripts/*.py`; a shell-guard row shows `python3 .claude/scripts/kit-track.py fork x`
  passes; the KT fixture creates `INSTALL_PROFILE`, `kit-manifest` and the overlay it asserts.

## Acceptance criteria (carried from the entry artifact)
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

## Plan critic
- pass 1: completeness 72, quality 68 — F1, F2, F5, F6 Major (verified, rewritten); 9 Minors → Vigilance
- pass 2: completeness 93, quality 86 — Majors fixed; F7, F14-F16 Minor fixed in place
- surviving blockers: none

## Gate
- 2026-11-26 go
- Contract: as written
- Open question 1 (location) → `.claude/scripts/kit-track.py`, spec path kept
- Open question 2 (permission) → `fork` allowed, `close` prompts
- Open question 3 (`.tdd-unfrozen`) → not copied
- Open question 4 (copy-back conflict) → main kept unless unchanged since fork; track version as `<file>.from-<slug>`
- Open question 5 (closing order) → close --merged (main-tree session) → step 5 → main-tree handoff shipped → git branch -d
- Open question 6 (doctor) → `worktree-kit` stays DIVERGENCE naming the script; `ignored-loop-paths` unchanged
- Interpretation: ship.md 4bis routes a kit-local worktree to `close` — accepted
- amended 2026-11-26 KT17: the prefix check compared `$(cat …)` output (trailing newline stripped) and could never pass → replaced by a grep on the reported line, before GREEN, case title and intent unchanged (kit shell suite, outside the freeze matcher)
- Review: round 1 FAIL (S1 S2 C1 T1 T2 SH2 fixed, cases KT7.2 KT26-KT29 WT13-WT14.2 N3), round 2 FAIL (C2 fixed, WT15 WT15.2), round 3 PASS (C3 refuted)
