# Research: kit drift fixes   (entry: docs/specs/kit-drift-fixes.md)
Token profile: critical

All 13 claims re-checked at main c2a29f6 (3 explorers: git hook; config/doctor/install; prompts). Line numbers are those of c2a29f6. The spec's numbers were taken at 7ebc764.

## Pattern to follow
- Git-guard fixtures: `.claude/hooks/fixtures/_harness/git-guard.jsonl`, run by `run_git_guard_cases` (test-hooks.sh:1010-1052). Fields: id `G22.<n>`, verdict, setup, command, optional cwd, and a reason for anything other than `pass`. A setup named `-lp<variant>-` dispatches to `lp_git_setup` (test-hooks.sh:4733-4802) or `lp_assets_setup` (:4717-4731).
- Server-root detection cases: SR1-SR9, run by `sr_detect_expect` / `run_detect_server_roots_cases` (test-hooks.sh:2357-2430).
- Install cases: IN* and IW* (test-install.sh). Doctor cases: KD* and DW* (test-kit-doctor.sh). Prompt pins: `pk`/`has`/`has_in`/`section` (test-workflow-contracts.sh:328, :1411-1416).
- Allows: the exact form `"Bash(<cmd>)"` sits beside the `*` form in settings.json (:50-51), and is mirrored in `PROMPT_ALLOWS` (install.sh:384-400, read by the suites only).

## Wiring points
- D1: `record_allow` in enforce-git-workflow.sh:2189-2266.
  - `assets_form` (:2195) is `^git (-C /abs )?push origin refs/heads/pr-assets$`.
  - The record checks run at :2215-2233. The assets branch runs at :2240-2262: local ref, no tag, no redirecting config, live `ls-remote` (:2251), then `merge-base --is-ancestor remote local` (:2258), then allow.
  - The allow never reads the commit messages or the tree paths in `remote..local`.
  - kit-pr-assets.py:
    - `pick_parent` (:207-217) takes the newer of the local ref and `refs/remotes/origin/pr-assets` (the cached ref).
    - `cmd_commit` (:243-259) adds only `<branch>/<sha7>/*.png` paths, with the message `chore(pr-assets): add <branch> <sha7>`.
    - `cmd_drop` (:346-358) removes the published folders, with the message `chore(pr-assets): drop <branch>`.
- D7: `worktree_kit_check` (enforce:2272-2284).
  - The regex at :2274 needs the literal `git worktree add`, so the `-C` form returns 0 and is never checked.
  - The probe at :2277-2281 runs `check-ignore` on `.claude/hooks/probe` and finds no tracked `.claude/hooks`, against `$BASE_DIR`.
  - The deny at :2282 names `kit-track.py fork <slug>`.
- D9: `__cwk_exit` (hook-lib.sh:70-82, trap :83).
  - On exit 0 with `CWK_DEGRADED_ASK=1`, no decision taken and `CWK_CFG_DEGRADED=1`, it prints a raw `ask` with `CWK_CFG_REASON`.
  - Six hooks set `CWK_DEGRADED_ASK=1`:
    - enforce:82
    - tdd-require-red:48
    - tdd-freeze-tests:45
    - no-forbidden-icons:18
    - prevent-destructive:15
    - protect-files:46
  - The auto-aware ask is `ask()`, local to enforce (:131-143). It calls `cwk_auto_mode <tree>` (hook-guarded.sh:590-603, available in the trap because hook-lib sources hook-guarded at :94) and emits `deny "auto mode — blocked stop: …"`.
  - Degraded statuses come from `cwk_config` (hook-guarded.sh:300-322): 4 = no project.json, 5 = CLAUDE_PROJECT_DIR not absolute, 6 = python3 or project_config.py missing, other = invalid.
- D2 and D4: project_config.py.
  - `SERVER_DIR_SEQUENCE` (:121) is `app`, `alembic`, `supabase`.
  - `_is_server_dir` (:124-129) checks a marker only for `app` (`main.py` or `__init__.py`).
  - `detect_server_roots` (:132-144) looks at the root and one level down. It skips RESERVED (`.claude`, `.git`, `node_modules`), hidden and symlinked parents.
  - Markers the kit already documents:
    - supabase: `supabase/config.toml` (addons/supabase/rules/06-database.md:18).
    - alembic: `alembic/env.py` (addons/fastapi/rules/06-database.md:55).
  - Depth convention: init.md:46 for app_roots, "at most 2 levels below the root".
- D3: `wire fastapi` (project_config.py:461-481), called from install.sh:554.
  - It appends bare `app` and `alembic` to `server_roots` and `protected_dirs` unless that exact string is already present.
  - `protected_dirs` entries are single segments (`_segment` :239, :332-334).
  - `migrate()` leaves a v3 file untouched (:692-693).
- D5: kit-doctor `check_server_roots` (:146-172) compares the `Server roots:` rule line with config as sets and never stats the roots.
  - A path missing on disk is already reported as MISSING by shipped-paths (:1074-1110).
  - The output line is `label check summary` (:1557). FAILING = DIVERGENCE / MISSING / OVER (:38).
  - The doc row is doctor.md:55.
- D6: init.md:118-120 runs `python3 .claude/hooks/project_config.py detect-server-roots .`. No allow matches it, in settings.json or in install.sh.
- D8: small.md:
  - step 4 (:13): draft, then `small-paths.sh` and `small-dispatch-check.sh`. No ignore probe.
  - step 5 (:14): the one AskUserQuestion.
  - step 6 (:15): the re-check.
  - step 7 (:16): the bare `git worktree add .claude/worktrees/small-<name> -b feat/small-<name> <base>`, then spec, add and commit in the worktree.
  - `kit-track.py fork small-<name>` is accepted (SLUG_RE :25). Its `kit_local` predicate (:77-80) is "ignored AND no tracked `.claude/hooks`".
- D10: github.md:146-151.
  - The hook allows push / pr-assets only bare or with an absolute `-C` equal to the session toplevel (enforce:2194-2214). `gh pr create` is allowed bare only (:2196).
  - Read-only git after `cd <literal root> &&` passes (cd_proven :580-583, :1717-1719). `git fetch` after a cd to the root passes (root_fetch :562-575). A push after a cd asks. `git add` after a cd is denied.
- D11: orchestrate.md:90-96 asks for the `phase:` and the `## In progress` / `Next:` line. review.md:263-265 asks for `review_status`, the round and the verdict.
  - The template (handoff/codex.md:37-42) has `review_status: judgment|fixes-handed-to-codex|fixes-done`, no `Next:` line and no round/verdict field.
  - Only `fixes-handed-to-codex` is pinned (T10, test-workflow-contracts.sh:1156). No script reads `review_status`.
- D12: install.sh:955-960. The regex `^\s*/?\.claude/?\s*$` misses `.claude/*`, `.claude/**` and `**/.claude[/]`. It checks the root `.gitignore` only.
- D13: kit-doctor, both run on the same `.claude/` line, with conflicting remedies:
  - `check_ignored_loop_paths` (:660-689) gives 8 rows, each "remove its .gitignore entry".
  - `check_worktree_kit` (:692-719) gives 1 DIVERGENCE with two remedies: remove the line, or keep it and fork with kit-track.

## Reusable
- `ask()` / `cwk_auto_mode` for D9. The `push_form` optional `-C (/abs)` group style for D7.
- `kit_local` semantics for the D8 probe; the kit-track fork already exists.
- The MISSING status and the shipped-paths style for D5.
- Marker knowledge from the addon rules for D4.

## Blast radius
- hook-lib.sh `__cwk_exit` is shared by 6 hooks.
- enforce-git-workflow.sh is the most fixture-heavy hook (git-guard.jsonl, 681 lines).
- The SR fixtures SR1, SR2, SR4, SR8 and SR9 rely on marker-less `alembic`/`supabase` folders and change with D4: their fixture gets the marker file.
- The G22.103 and G22.104(.2) assets allows are built on messageless empty-tree commits (`lp_assets_setup`). D1 flips them unless the setup makes real add commits.
- Allow lists: PK60 (the `*` forms), IN59, IN72.
- Doc rows: doctor.md:55, :64, :65. The addon READMEs tell users to write `Server roots: app, alembic` (fastapi README:134, supabase README:92).
- `kit-audit-surface.py:162-177` consumes `server_roots`, with a prefix match, so prefixed roots are fine there.
- PR #26 (open, branch from the same base) holds the ids WT16-WT24, N3b and KT30-KT50, and edits orchestrate.md:239/:265 and tracks.md. This pass must not reuse those ids.

## Live DB state
n/a

## External surface
n/a

## Traps (points of vigilance for the review)
- D1: the allow must reject any commit in `remote..local` that is not this record's branch's assets commit. That includes a declined `drop` commit and another branch's `add` commit. It must keep the existing asks (force, `+`, tag, config, released, blocked, other HEAD) and still allow a legitimate add.
- D1: the hook reads the remote sha from live `ls-remote`; kit-pr-assets reads the cached ref. The content check must run on the live range.
- D7: the `-C` widening must check the tree that `-C` names, not `$BASE_DIR`. The regex must stay specific to `worktree add` under `.claude/worktrees/`. Tracked-kit projects keep passing (G22.117).
- D9: the trap has no `BASE_DIR`/`CWD`. When there is no usable tree (status 5), it must fail safe to the raw ask. A blocked-stop deny happens only when `cwk_auto_mode` proves auto. All 6 hooks keep their current behaviour outside auto.
- D2: the depth-2 walk must skip RESERVED, hidden and symlinked dirs at every level, and must not walk into `node_modules` or `.venv`.
- D3: wire must not add bare roots when a prefixed root of the same kind is declared. It must stay idempotent on bare roots (IN29, IN13).
- D6: the new allow is the exact read-only command, with no `*`.
- D8: the probe uses the `kit_local` predicate, not a bare check-ignore (a tracked kit passes). It runs before the single AskUserQuestion (small-lane pins test-workflow-contracts.sh:408-425 stay true). The fork replaces step 7(a) only; (b)-(d) still apply.
- D10: CW2 ("the bare exact form from the project root") stays.
- D13: one remedy per ignore line. A `.claude/` line is reported once, by worktree-kit, not 8 times.
- Every kit suite, plus kit-lint.sh, stays green. New ids avoid those of PR #26.

## Open questions
1. D1: how is "this pass's assets commit" identified? Proposed: every commit in `remote..local` has exactly one parent, a message `chore(pr-assets): add <record branch> <sha7>`, and adds only paths under `<record branch>/`. A drop, or another branch's commit, makes it ask.
2. D2: what does "depth 2" mean? Proposed: two folder levels below the root (`services/api/app`), the same as init.md's app_roots rule.
3. D4: which alembic marker? Proposed: `alembic/env.py` inside the folder, the one the addon rule cites. supabase uses `supabase/config.toml`.
4. D3: when a prefixed root is declared, should wire also skip bare `app` in `protected_dirs`? Proposed: skip both `server_roots` and `protected_dirs` for that kind. `protected_dirs` cannot hold a prefixed path, and a bare `app` protects a folder that doesn't exist.
5. D12: regex or `git check-ignore`? Proposed: a regex covering `.claude`, `.claude/`, `.claude/*`, `.claude/**`, `**/.claude[/]`, with or without a leading `/` (a target may not be a git repo at install time).
6. D13: which remedy wins for a `.claude/` line? Proposed: worktree-kit owns it, and ignored-loop-paths skips probes whose only ignore source is a `.claude` line. Both remedies stay listed, as the user's choice.
7. D8: where does the probe go, and how? Proposed: a read-only `python3 .claude/scripts/kit-track.py local` subcommand (exit 0 kit-local, 1 not), run at step 4 with the other checks, plus a step-7 branch to `kit-track.py fork small-<name>`. The deny text stays generic (`<slug>`), and small.md names the exact command.
8. D11: add `Next:` to the template, or reword the prompts? Proposed: the template's `## In progress` gets a `- Next: …` line, and `review_status` gains `round-<n>: <verdict>` documentation. Or reword review.md to "the round and its verdict in `## In progress`". The second is smaller.
9. D9: fix it in the trap or in enforce? Proposed: in the trap, using `cwk_auto_mode "$CLAUDE_PROJECT_DIR"`. It covers all 6 hooks. A status-5 config keeps the raw ask.
