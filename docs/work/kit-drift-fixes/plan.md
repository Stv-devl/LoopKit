# Plan: kit drift fixes   (entry: docs/specs/kit-drift-fixes.md · research: docs/work/kit-drift-fixes/research.md · design: n/a)
Token profile: critical
Base: c2a29f6

## Skips
- DB: SKIP. There is no schema; this is kit tooling only.
- Backend: SKIP. Kit hooks and scripts only. No test-first layer: the freeze matcher covers `utils`, `mapper`, `repository` and `services` under `src/` or `shared/`, none here.
- INTERFACE: SKIP. No user surface.
- Worktree: none, single track. PR #26 is open on its own branch from the same base.

## Write chain (sequential)
Kit shell suites are test-after fixtures, outside the freeze. Each new case is written first and seen red on the current code. Pins (marked *pin*) are expected green from the start. No existing case is rewritten, except the fixture setups named below (their verdicts stay the same) and one named contract exception: HP-B2 (test-workflow-contracts.sh:771-772). Its `HP_WANT` gains `Bash(python3 .claude/hooks/project_config.py detect-server-roots .)` and its length goes from 37 to 38, because step 10 adds that allow to `PROMPT_ALLOWS` by contract.

1. **Fixture cases, written first and run once before any fix** (records red and pin results):
   - `fixtures/_harness/git-guard.jsonl` + `test-hooks.sh`:
     - `lp_assets_setup` rebuilt (D1);
     - G22.124-G22.133;
     - DG1-DG4;
     - SR10-SR14;
     - SR1/2/4/8/9 fixtures get their markers.
   - `test-install.sh`: IN73, IN74, IW4-IW6.
   - `test-kit-doctor.sh`: KD29, KD30, DW7, DW8, DW9.
   - `test-small-lane.sh`: D23, D23.2.
   - `test-workflow-contracts.sh`: PK70-PK70.3, WT25-WT25.2, CW7-CW7.3, HF4-HF4.2. The HP-B2 amendment lands with step 10, not before: it is the named exception, and it goes red only once `PROMPT_ALLOWS` changes.
2. **D1 — `enforce-git-workflow.sh` `record_allow`, assets branch.**
   - After the fast-forward test (:2258), walk `git rev-list remote_sha..refs/heads/pr-assets` on the live remote sha.
   - The allow holds only when every commit in that range:
     - has exactly one parent. The one exception is a parentless commit when no remote ref exists: it is accepted only as the root of the range, which is how `kit-pr-assets.py` makes the first publish (`pick_parent` returns None);
     - has a message equal to `chore(pr-assets): add <record branch> <sha7>`, with a 7-hex `<sha7>`;
     - adds paths only, every one under `<record branch>/`: `git diff-tree --root --no-commit-id -r --name-status <c>` shows only `A` lines, all with that prefix (`--root`, so a root commit lists its paths).
   - Any other commit returns without an allow, so the ordinary ask runs (moi), or `ask()`'s blocked stop (auto). `record_allow` emits no ask of its own.
   - With no remote ref (G22.103), the range is every commit reachable from the local ref.
3. **D7 — `worktree_kit_check`.**
   - Both existing regexes (:2274, the path; :2276, the `-b/-B`) get an optional `-C[[:space:]]+[^[:space:]]+[[:space:]]+` group inserted between `git[[:space:]]+` and `worktree`. Nothing else changes. They stay unanchored, matching after start, whitespace, `;`, `&` or `|`, with options before the path, and with absolute `…/.claude/worktrees/` paths, so today's denies all survive.
   - The probe runs against the `-C` path (taken from the match, made absolute against `$BASE_DIR` when relative), else `$BASE_DIR`.
   - The deny text stays unchanged.
4. **D9 — `hook-lib.sh` `__cwk_exit`.**
   - Before printing the raw degraded ask:
     - if `CLAUDE_PROJECT_DIR` is absolute and `cwk_auto_mode "$CLAUDE_PROJECT_DIR"` succeeds, print a `deny` whose reason opens `auto mode — blocked stop: ` followed by `CWK_CFG_REASON`;
     - otherwise print the raw ask, as today.
   - `cwk_auto_mode` is guarded with `declare -F`, so a hook that did not source hook-guarded keeps the raw ask.
5. **D2 / D4 — `project_config.py`.**
   - `_is_server_dir` checks a marker per kind:
     - `app`: `main.py` or `__init__.py`;
     - `alembic`: `env.py` inside it;
     - `supabase`: `config.toml` inside it.
   - `detect_server_roots` walks two folder levels below the root. At every level it skips RESERVED, hidden and symlinked dirs, plus `.venv`/`venv`, and it does not descend further.
   - Output order: root level first, then depth 1, then depth 2. Within each, alphabetical, then by `SERVER_DIR_SEQUENCE`.
6. **D3 — `project_config.py` `wire fastapi`.**
   - For each kind (`app`, `alembic`), a declared server root ending in `/<kind>` suppresses adding the bare kind to both `server_roots` and `protected_dirs`.
   - Bare roots keep the current behaviour: IN29 and IN13 unchanged.
7. **D5 — `kit-doctor.py` `check_server_roots`.** After the compare, one MISSING finding per declared root that is not a directory under the project root, with one evidence line naming it. doctor.md:55 row updated.
8. **D13 — `kit-doctor.py`.**
   - The decision belongs to `check_worktree_kit`, in one place.
   - When `worktree-kit` reports its DIVERGENCE (the probe is ignored and no `.claude/hooks` is tracked), `check_ignored_loop_paths` asks `git check-ignore -v` for each probe and drops the probes whose matching pattern is a whole-`.claude` line (`.claude`, `.claude/`, `/.claude[/]`, `.claude/*`, `.claude/**`, `**/.claude[/]`). Its OK summary then says `the whole-.claude line is reported by worktree-kit` instead of claiming the folders are tracked.
   - When `worktree-kit` is OK (a tracked kit), `ignored-loop-paths` keeps reporting every ignored probe as today. Either way the line is reported exactly once.
   - The two worktree-kit remedies stay as the user's choice.
   - doctor.md rows :64/:65 say so.
9. **D12 — `install.sh` (:955-960).** The regex covers `.claude`, `.claude/`, `.claude/*` and `.claude/**`, each with or without a leading `/` or `**/`. The same warning text.
10. **D6 — allows.**
    - `.claude/settings.json` gets `"Bash(python3 .claude/hooks/project_config.py detect-server-roots .)"`, exact, no `*` form.
    - `install.sh` `PROMPT_ALLOWS` mirrors it.
    - HP-B2's `HP_WANT` gains it and goes to length 38 (the named exception).
11. **D8 — `small-dispatch-check.sh` + `small.md`. A refusal, as the entry writes it.**
    - The check uses the same predicate as tracks.md and orchestrate.md Phase 0.5: `git check-ignore -q .claude/hooks/probe` succeeds and `git ls-tree -r --name-only HEAD -- .claude/hooks` prints nothing.
    - It runs right after `cd "$main_tree"`, before any other check, so the predicate judges the main tree, the same one `kit-track.py fork` judges (`kit_local` on `main_root()`). When it holds, the script calls `refuse` (exit 1) with the line `kit-local project: a bare worktree would hold no kit; fork with python3 .claude/scripts/kit-track.py fork small-<name> alone from the project root`.
    - small.md step 4 already stops on a refusal before the go. Step 4 gains one sentence: on a kit-local project the check refuses and names that exact fork. Step 7 is unchanged.
12. **D10 — `github.md` :146-151.**
    - The pass's push and the pr-assets push take the bare form, or `git -C <absolute tree> …` naming the session tree.
    - `gh pr create` is bare only.
    - After `cd <project root> &&`, read-only git and `git fetch <remote> [branch]` pass, while a push asks and `git add` is denied.
    - The stale "which the hook cannot place" goes. CW2's phrase stays.
13. **D11 — `handoff/codex.md` + `review.md`.**
    - The template's `## In progress` gains `- Next: <the next action>` (orchestrate.md:96 already names it).
    - review.md:263-265: "`review_status` in the frontmatter, the round and its verdict on the `## In progress` `Next:` line".
14. **Gates.**
    - Every kit suite green: test-hooks (background), install, kit-doctor (+ `kit-doctor.py`), small-lane, workflow contracts, pr-assets, gate-route, attempts, audit-surface, measure, rules-floor, kit-lint fixtures.
    - Then `.claude/scripts/kit-lint.sh`.

## Parallel lots
none: fully sequential (one main thread; several steps edit the same suites).

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: hook-lib.sh (sourced by 6 hooks), enforce-git-workflow.sh, settings.json allow list. No other kit pass runs beside this one until it merges, except PR #26 (already shipped).

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| .claude/hooks/enforce-git-workflow.sh | Edit | D1 assets content check, D7 `-C` |
| .claude/hooks/hook-lib.sh | Edit | D9 trap |
| .claude/hooks/project_config.py | Edit | D2, D4, D3 |
| .claude/hooks/kit-doctor.py | Edit | D5, D13 |
| install.sh | Edit | D12 regex, D6 PROMPT_ALLOWS |
| .claude/settings.json | Edit | D6 allow |
| .claude/scripts/small-dispatch-check.sh | Edit | D8 kit-local refusal |
| .claude/commands/loop/small.md | Edit | D8 |
| .claude/agents/github.md | Edit | D10 |
| .claude/commands/handoff/codex.md | Edit | D11 template |
| .claude/commands/loop/review.md | Edit | D11 |
| .claude/commands/kit/doctor.md | Edit | D5, D13 rows |
| .claude/hooks/fixtures/_harness/git-guard.jsonl | Edit | G22.124-133 |
| .claude/hooks/test-hooks.sh | Edit | lp_assets_setup, DG1-4, SR10-14, SR markers |
| .claude/hooks/test-install.sh | Edit | IN73, IN74, IW4-6 |
| .claude/hooks/test-kit-doctor.sh | Edit | KD29-30, DW7-9 |
| .claude/hooks/test-small-lane.sh | Edit | D23, D23.2, floor +2 |
| .claude/hooks/test-workflow-contracts.sh | Edit | PK70, WT25, CW7, HF4; HP-B2 amended (named exception) |

## Contracts
- pr-assets push allow:
  - `git [-C /abs] push origin refs/heads/pr-assets` is allowed iff the existing conditions hold and every commit in `<live remote sha>..pr-assets` (or every commit reachable, when there is no remote ref) passes three checks:
    - it is single-parent, except a parentless root when there is no remote ref;
    - it has the message `chore(pr-assets): add <record branch> <7 hex>`;
    - it only adds paths under `<record branch>/` (`diff-tree --root`).
  - Otherwise no allow: the ordinary path asks.
- Degraded trap: with auto proven on `CLAUDE_PROJECT_DIR`, the output is `{"permissionDecision":"deny"}` with the reason `auto mode — blocked stop: <cfg reason>`. Otherwise the raw ask, unchanged.
- `project_config.py detect-server-roots <dir>`: the output format is unchanged (a JSON array, project_config.py:770). Roots reach depth 2 and need markers.
- kit-doctor `server-roots`: MISSING with the evidence `<root>: not a directory`.
- `small-dispatch-check.sh` on a kit-local project: exit 1 with the line `kit-local project: a bare worktree would hold no kit; fork with python3 .claude/scripts/kit-track.py fork small-<name> alone from the project root`. Otherwise unchanged.

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — none
No `utils`/`mapper`/`repository`/`services` file under `src/` or `shared/`. Kit fixtures are test-after, written first and seen red as below.

### Test-after — kit fixture suites
Red = must fail on c2a29f6 for the named defect; *pin* = must pass on c2a29f6 and after.

**git-guard (test-hooks.sh, git-guard.jsonl) — D1**
- `lp_assets_setup` builds real add commits, as `kit-pr-assets.py` makes them. The first is an orphan (no parent), with a tree holding `feat/s1/abc1234/a-1-light-desktop.png` (`feat/s1` is the lp fixtures' record branch) and the message `chore(pr-assets): add feat/s1 abc1234`. The second has the first as parent, adds `feat/s1/def5678/…` and carries the message `… def5678`.
- G22.103 (no remote, an orphan add commit), G22.104 and G22.104.2 stay `allow` (*pin*, on the rebuilt setup; G22.103 is the case that proves the root exception).
- The other assets asks (G22.106-G22.121) keep their verdicts (*pin*).
- G22.124 `ask`: a declined drop. A commit `chore(pr-assets): drop <record branch>` that removes the folder sits on top of an add, one ahead of origin. Red: allowed today.
- G22.125 `ask`: a foreign pass. An add commit for `feat/other`, with paths under `feat/other/`, sits under the pass's add commit. Red.
- G22.126 `ask`: the pass's message, but one path outside `<record branch>/`. Red.
- G22.127 `allow`: two of the pass's own add commits ahead of origin (*pin*).

**git-guard — D7**
- G22.128 `deny`, reason `kit-track.py fork`: `lpwtignored` with `git -C __FEAT_TREE__ worktree add .claude/worktrees/x -b feat/x2 main`. Red: no deny today.
- G22.129: `lpwttracked`, the same `-C` form gets the same verdict as G22.117 (*pin*: the tracked kit is not denied).
- G22.130 `deny`, reason `kit-track.py fork`: `lpwtignored`, option-first bare form `git worktree add -b feat/x2 .claude/worktrees/x main` (*pin*: denied today, must stay).
- G22.131 `deny`, reason `kit-track.py fork`: `lpwtignored`, absolute path bare form `git worktree add __FEAT_TREE__/.claude/worktrees/x -b feat/x2 main` (*pin*).
- G22.132 `deny`, reason `kit-track.py fork`: `lpwtignored`, option-first with `-C`: `git -C __FEAT_TREE__ worktree add -b feat/x2 .claude/worktrees/x main`. Red.
- G22.133 `deny`, reason `kit-track.py fork`: `lpwtignored`, after `;`: `true; git -C __FEAT_TREE__ worktree add .claude/worktrees/x -b feat/x2 main`. Red, the unanchored `-C` form.
- G22.128w (review round 1 F1): `git -C <foreign repo> worktree add .claude/worktrees/x -b y` asks, and the foreign repo's fsmonitor never runs.
- G22.134 `ask` (F6): `lpassetsmsg`, a valid add whose message is `wip`. G22.135 `ask`: `lpassetsmerge`, a merge commit. G22.136 `ask`: `lpassetssha`, a non-hex sha7.
- G22.137 `ask` (review round 2 F6): `lpassetsbare`, a valid add under `feat/s1/` whose message is exactly `def5678`. Turns `allow` with the message-prefix check removed.

**degraded trap (test-hooks.sh) — D9**
- DG1: no project.json, with a valid auto record on its branch. `enforce-git-workflow.sh` on `git add x` gives `deny`, and the reason opens `auto mode — blocked stop:`. Red: raw ask today.
- DG2: no project.json, no record. The same command gives the raw `ask` (*pin*).
- DG3: `CLAUDE_PROJECT_DIR` relative (status 5), with an auto record. The result is `ask` (*pin*: fails safe).
- DG4: `protect-files.sh`, degraded with an auto record, on a command that passes. It gives `deny` with a reason opening `auto mode — blocked stop:`. Red. This covers the shared trap, not just enforce.

**server-root detection (test-hooks.sh SR) — D2, D4**
- SR1, SR2, SR4, SR8, SR9: the fixtures gain `alembic/env.py` / `supabase/config.toml`. Expectations unchanged (*pin*).
- SR10: `services/api/app/main.py` is proposed as `services/api/app`. Red.
- SR11: a marker-less `supabase/` is not proposed. Red.
- SR12: a marker-less `alembic/` is not proposed. Red.
- SR13: `node_modules/x/app/main.py`, `.venv/x/app/main.py` and `.hidden/x/app/main.py` are not proposed (*pin*).
- SR14: depth 3, `a/b/c/app/main.py`, is not proposed (*pin*).

**install (test-install.sh) — D3, D6, D12**
- IN73: server_roots `["backend/app","backend/alembic"]`, protected_dirs without `app`. The fastapi reinstall leaves `server_roots` and `protected_dirs` byte-identical. Red.
- IN29, IN13 (bare roots, idempotent) stay (*pin*).
- IN74: an installed target's settings.json holds the exact allow `Bash(python3 .claude/hooks/project_config.py detect-server-roots .)` and no `project_config.py` allow ending in `*`. Red.
- IW4 `.claude/*`, IW5 `/.claude/**`, IW6 `**/.claude/`: install prints the ignored-`.claude` warning. Red.
- The quiet case `.claude/worktrees/` stays quiet (*pin*).

**kit-doctor (test-kit-doctor.sh) — D5, D13**
- KD29: `server_roots` declares `backend/app` and the rule line matches, but no `backend/app` dir exists. `server-roots` reports MISSING, naming `backend/app`. Red.
- KD30: the same with the dir present gives no MISSING for server-roots (*pin*).
- DW7: `.gitignore` = `.claude/`, no tracked kit. `worktree-kit` reports DIVERGENCE once. `ignored-loop-paths` is `ok` with the summary `the whole-.claude line is reported by worktree-kit`, and lists no ignored probe. Red: 8 rows today.
- DW8: `.gitignore` = `.claude/agents/`. `ignored-loop-paths` still reports `.claude/agents` (*pin*).
- DW9: tracked `.claude/hooks/x` and `.gitignore` = `.claude/` (the DW5 state). `worktree-kit` is `ok`, and `ignored-loop-paths` still reports the ignored probes, so the line is reported once, not zero times (*pin*: true today, must stay).
- DW10 (review round 1 F3): `settings.json` then `!.claude/settings.json`: a negated re-include is not an ignored probe, `ignored-loop-paths` ok.
- DW11 (F4a): a lone `.claude/hooks/` line is reported by `worktree-kit` only.
- DW12 (F4b): `.claude/*` then `.claude/hooks/`: `.claude/rules/` stays under `ignored-loop-paths`, `.claude/hooks/` is not reported twice.
- DW13 (review round 2 N1): `*`, `!*/`, `!src/**` over an untracked kit: `worktree-kit` reports the `*` line and `ignored-loop-paths` still lists `docs/work/`. Red before the fix.
- DW14 (N2): `*`, `!*/`, `!.claude/**`, nothing tracked: `worktree-kit` ok. Fails with the `!` branch of `kit_ignore_state` removed.

**small lane (test-small-lane.sh) — D8**
- D23: a kit-local fixture (`.gitignore` = `.claude/`, no tracked `.claude/hooks`). `small-dispatch-check.sh b <files>` exits 1 and prints `python3 .claude/scripts/kit-track.py fork small-b`. Red: today it prints `ok`.
- D23.2: a tracked-kit fixture with `.gitignore` = `.claude/` gives `ok`, exit 0 (*pin*).
- The floor rises from 91 to 93.

**contracts (test-workflow-contracts.sh) — D6, D8, D10, D11**
- PK70: settings.json has the exact allow. Red.
- PK70.2: settings.json lacks `project_config.py detect-server-roots *` (*pin*).
- PK70.3: `PROMPT_ALLOWS` in install.sh has it. Red.
- HP-B2 (amended, the named exception): `HP_WANT` includes the exact allow, length 38.
- WT25: small.md step 4 has `kit-track.py fork small-<name>`. Red.
- WT25.2: in small.md, `kit-track.py fork small-<name>` comes before the step-5 `AskUserQuestion` (in_order). Red.
- The small-lane pins (:408-425) and PK33 stay (*pin*).
- CW7: github.md has `git -C <absolute tree>`. Red.
- CW7.2: github.md lacks `which the hook cannot place`. Red.
- CW7.3: github.md has `read-only git and \`git fetch\``. Red.
- CW2 stays (*pin*).
- HF4: the handoff/codex.md template has `- Next:` under `## In progress`. Red.
- HF4.2: review.md has `on the \`## In progress\` \`Next:\` line`. Red.
- HF3 and T10 stay (*pin*).

## Vigilance (carried from research)
- D1:
  - only this record branch's single-parent add commits pass, judged on the live remote range;
  - every existing assets ask keeps its verdict;
  - no-remote allow (G22.103) still allows a legitimate add.
- D7:
  - the probe runs on the `-C` tree;
  - both regexes keep today's unanchored forms (after `;`/`&`/`|`, options first, absolute path) and gain only the `-C` group;
  - a tracked kit is not denied.
- D9:
  - the deny is issued only when `cwk_auto_mode` proves auto on an absolute `CLAUDE_PROJECT_DIR`;
  - otherwise the raw ask stays;
  - all 6 hooks behave unchanged outside auto.
- D2:
  - the walk skips RESERVED, hidden, symlinked and venv dirs at every level;
  - never beyond depth 2.
- D3: bare roots stay idempotent (IN29, IN13); prefixed roots suppress only their own kind.
- D6: an exact allow, no `*`; it reaches targets through settings.json, not RETIRED_ALLOWS.
- D8:
  - the `kit_local` predicate, not a bare check-ignore;
  - a refusal (exit 1) at step 4, before the go, naming `kit-track.py fork small-<name>`;
  - one AskUserQuestion;
  - step 7 unchanged.
- From plan-critic pass 1 (vigilance):
  - D1: the auto half relies on falling through to `ask()`; `record_allow` must never emit its own ask.
  - D7: the probe must read the `-C` tree, not `$BASE_DIR`. Check by reading, since G22.128 uses the cwd tree.
  - D3: suppression is per kind. `["backend/app"]` alone still adds a bare `alembic`: check by reading or add a case.
  - D13: DW7's ok summary must not claim the folders are tracked.
  - D9: the trap reads auto from `CLAUDE_PROJECT_DIR` only, while enforce's `ask()` reads the session tree first. Say so in the trap's comment, which is a known limit.
  - D2: depth order (root, depth 1, depth 2), the non-hidden `venv` skip and depth-2 symlinked parents are checked at review.
  - SR cases parse the JSON array output.
- D10: CW2 phrase kept.
- D13: one remedy per ignore line; a `.claude/agents/` line is still reported.
- PR #26 ids (WT16-24, N3b, KT30-50) not reused. Known textual overlaps with #26: the small-lane floor line, and the contracts block near HF1. They are resolved at whichever rebase comes second.
- A `critical` profile arms the ship security-auditor on the touched surfaces (the git hook allow, the degraded trap).

## Acceptance criteria (carried from the entry artifact)
- [ ] The pr-assets push is allowed only when every commit it adds is this pass's assets commit. A declined cleanup commit, or a foreign pass's commit under it, makes it ask (moi) / blocked stop (auto).
- [ ] `detect-server-roots` proposes a backend at depth 2 with its markers, and no longer proposes a marker-less `supabase`/`alembic` folder.
- [ ] Re-installing fastapi on a project with prefixed roots leaves `server_roots` and `protected_dirs` unchanged.
- [ ] kit-doctor reports a declared server root missing on disk, and reports one remedy per ignore line.
- [ ] `/kit:init` step 14 runs without a permission prompt. The new allow is the exact read-only command, nothing wider.
- [ ] `git -C <abs root> worktree add .claude/worktrees/x …` on an ignored `.claude/` gets the same deny as the bare form.
- [ ] `/loop:small` refuses an ignored `.claude/` before the go, naming the exact `kit-track.py fork small-<name>` command.
- [ ] In auto, a degraded-config git ask ends as a blocked stop, not a prompt.
- [ ] The prompt wording (D10, D11) matches the hooks and the handoff template. The contracts suite pins it. install warns on `.claude/*`.

## Plan critic
- pass 1: completeness 78, quality 58. Six Majors, all rewritten in place:
  - CF1: D8 is now a literal refusal.
  - CF2: D13 is now conditional on the worktree-kit DIVERGENCE, plus DW9.
  - QF1: the root-commit exception, `--root`.
  - QF2: HP-B2 is the named exception.
  - QF3: both regexes stay unanchored with a `-C` group, plus G22.130-133.
  - QF5: PK70.2 is a pin, and the output is a JSON array.
  - The 7 vigilance findings are folded into Vigilance.
- pass 2: completeness 92, quality 88. 6/6 Majors fixed. QF8 (the Files table) and QF9 (the D8 check runs after `cd "$main_tree"`) fixed in place. Route clear.
- surviving blockers: none

## Gate
- 2026-11-27 go
- Contract: as written
- Q1 D1 pass's assets commit → single-parent (root allowed with no remote ref), message `chore(pr-assets): add <record branch> <sha7>`, adds only under `<record branch>/`
- Q2 depth 2 → two folder levels below the root
- Q3 markers → `alembic/env.py`, `supabase/config.toml`
- Q4 D3 → a prefixed root of a kind suppresses that bare kind in `server_roots` and `protected_dirs`
- Q5 D12 → a regex, not check-ignore
- Q6 D13 → worktree-kit owns the whole-`.claude` line when it reports DIVERGENCE
- Q7 D8 → refusal in small-dispatch-check.sh (not kit-track.py)
- Q8 D11 → `- Next:` added to the handoff template
- Q9 D9 → fixed in the shared trap, fail-safe ask without proven auto
- Exception recorded: HP-B2 `HP_WANT` length 37 → 38 (test-after contract, not frozen)
- EXECUTE deviation 2026-11-27 (D6): the existing PK2 invariant requires every reader call to run `python3 -I`, and the plain allow string tripped it. So the init.md step-14 command and its exact allow become `python3 -I .claude/hooks/project_config.py detect-server-roots .`: the same read-only command, isolated, nothing wider. PK70/PK70.3/IN74/HP-B2 use that form. The acceptance criterion is unchanged in meaning.
- Review round 1 amendment 2026-11-28 (user), Q4 re-decided on the corrected fact (a bare `app` in protected_dirs does protect `backend/app` through PROTECTED_TARGET's `/`-suffix match): a prefixed root of a kind suppresses that bare kind in `server_roots` only; `wire` still adds bare `app`/`alembic` to `protected_dirs`. Exception recorded: IN73's `protected_dirs` expectation changes accordingly (test-after, not frozen); `server_roots` stays byte-identical.
- Review round 1 amendment 2026-11-28 (user), Q6 widened: worktree-kit owns the exact `file:line` it names when it reports DIVERGENCE, whatever the pattern; ignored-loop-paths drops only probes whose `check-ignore -v` source equals that line, and never counts a negated (`!`) match as ignored.
- Review round 2 N1 / round 3, 2026-11-28 (user): AC4 read as one remedy per folder. The hand-over covers only the `.claude/` probes of the line worktree-kit names; a broad line (`*`) that also ignores `docs/work/` gets a second row under ignored-loop-paths for that folder (DW13). The kit-doctor docstring and `/kit:doctor` table say so (M1 closed).
