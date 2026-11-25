# Research: kit fixes from the EcoCrew agent-ia-2.5 / 4.6 auto runs   (entry: docs/specs/auto-mode-2.5-fixes.md)
Token profile: economy

Base: `main` 1a99f7c. One `explorer` map plus main-thread checks. Paths are repo-relative.

## Pattern to follow
- Previous kit-fix passes from field runs: `docs/specs/agent-ia-trial-fixes.md` and `docs/specs/auto-mode-trial-fixes.md`. Each item is one bounded hook, script or prompt change, with a fixture or test case per criterion.
- Shell-guard deny texts are tested by substring in `.claude/hooks/fixtures/_harness/shell-guard.jsonl`, run by `run_shell_guard_cases()` `.claude/hooks/test-hooks.sh:960-1006`.
- kit-pr-assets has its own suite, `.claude/hooks/test-pr-assets.sh` (472 lines, run in CI by `.github/workflows/kit-ci.yml:70`). Helpers: `run_in` :35-47 (stdin here-string), `mkrepo` :66 (bare origin plus work repo), `expect_out` :53, `expect_refused` :59. The `ui` cases are K1-K3 :136-148 and K27-K30 :151-182.
- Auto-mode block tests: the AM section `.claude/hooks/test-hooks.sh:5946+` (`am_tree` :5951, `am_block` :6047, `am_expected_block` :6714-6719, `am_pr` :6721).
- Route tests: `.claude/hooks/test-gate-route.sh` (`rf` helper :27-32).

## Wiring points
- **Item 1.** `kit-pr-assets.py` `ui`: `add_parser("ui")` :293 takes no arguments. `run()` :315-321 reads `app_roots` via `project_config.load(os.getcwd())` :317, maps ConfigError to Refused (exit 2) :318-319, reads stdin :320 and decides with `is_ui_path` :64-74. Its prompt caller is `.claude/commands/loop/review.md:160`, the pipe form.
  - A second prompt pipe exists: `.claude/agents/github.md:222`, `gh pr view … | python3 .claude/hooks/kit-pr-assets.py drop`, which kit-cwd should deny too.
  - kit-cwd's deny text is in `prevent-destructive-commands.sh:1010-1012` (slot set at :780). Its rows are built in `shell_targets.py` `kit_cwd_rows` :708-721: the script must be segment 0, or segment 1 after `cd <root> &&`.
- **Item 2.**
  - `prevent-destructive-commands.sh:972-977`. `LOOP_RECORD_RUN_RE` :972 matches the script anywhere in the command. `LOOP_RECORD_CLEAR_RE` :974 is anchored `^…$`, so `cat x; python3 …loop-record.py --mode` misses the manual-form exemption and gets the :977 text "only Claude Code runs loop-record.py".
  - Inline programs: `shell_targets.py` `interpreter()` :872-898 and `inline_paths()` :2101-2125 turn every quoted project path into an `("inline-path", p)` row, whether it is read or written. In prevent-destructive, `?inline:` :772-800 handles them, :868-869 emits "$rel written by $verb", and :870-874 emits "inline programs are not used here".
- **Item 3.**
  - `loop-record.py` `guarded_block()` :726-768. The comment `<!-- guarded-files sha256:DIGEST -->` :768 hashes the body only and carries no HEAD sha.
  - The hook recomputes the block in `enforce-git-workflow.sh` `guarded_block_check()` :2156-2168 (`--guarded-block --no-fetch`), checks it as a substring of the body :2166 and denies with :2167. It is called at :2214 and :2217.
  - Order of steps: `ship.md:166-170` and 4bis-PR `:177-192`. Step 1 pushes, step 2 writes the body and runs `--guarded-block`, step 3 runs `gh pr create`. Nothing says "after the agent reported the commit, never in parallel". `github.md:186-192` never names `--guarded-block`.
- **Items 4 and 5.**
  - `loop-record.py` TS_CASE_RE :692, PY_CASE_RE :693 and `case_ids()` :698-701, whose only consumer is guarded_block :761.
  - Rows: BLOCK_HEADER :43 "Frozen cases to amend:", `ROW_RE` :44 `^(\S+) \| ([UMRB][0-9]+) \| ([0-9a-f]{64})$`, `parse_rows` :183-203, written by `post_plan_go()` :333-366 from the plan go (format in `plan.md:135-139`, hash from `.claude/scripts/case-hash.sh`, `plan.md:144`). `allowed` :743-747 defaults kind to frozen-case and verdict to unfreeze.
  - `parse_rows` does not check that the path is frozen, so a plan-gate row already silences GUARD FAILURE for any test file. Only the prompt never says to declare a test-after rewrite.
- **Item 6.**
  - `.claude/agents/implementer.md` (66 lines; Non-negotiable :41, shell rule :53-55).
  - `.claude/agents/test-writer.md` (191 lines; Non-negotiable :129, shell rule :134-138, which already bans `cd && git apply` :138).
  - No agent-size budget is enforced (kit-doctor checks only model :763 and effort :829).
- **Item 7.**
  - `prevent-destructive-commands.sh`: the `>`/`>>` branch :875-895 and the source-writer branch :896-903 deny only `.ts(x)`/`.py` (codegen/test-first), otherwise they guard only `cwk_is_guarded` paths. `guard_classify_tool` :685-700 (sed -i, flag-w) denies only protected roots and tests.
  - Result: `sed -i`, `tee` or `>` onto `docs/work/x/plan.md` passes silently.
  - Outside the project, `guard_classify_outside` :732-753 handles `/dev/null` :736, fd aliases :738-746 and `/tmp` :747-749 (the scratchpad is under /tmp).
- **Item 8.**
  - `kit-pr-assets.py` `build_parser()` :290-310 (ui, path, plan, section, commit, drop). The script never mentions `.pr-shots`; the layout `.pr-shots/<slug>/<run-id>/` lives in prose (`review.md:169`, `e2e-playwright/SKILL.md:151`).
  - Publishing is in `github.md:202-215`. `.gitignore:130` ignores `.pr-shots/`.
  - Non-recursive `rm`/`rmdir` on unguarded paths is silent (`shell_targets.py:1790`, prevent-destructive :917-918). This item uses Python `os.remove`/`os.rmdir` inside the script, not shell.
- **Item 9.**
  - `kit-gate-route.py` `DIMENSIONS` :23 is used only for validation (:370, :390, :393, :402) and the follow-up display :486. It does not route.
  - review.md Stage 2.5 :201-214 tells no dimension field and ends with "**never creates a sixth permanent review dimension**" :213-214. Stage 3bis :236-238 requires `dimension` on every route entry.
  - In EcoCrew 4.6 the orchestrator invented `shadow` and the router refused it with exit 2. The fix belongs in the prompt: a shadow item carries the dimension of the dependency it shadows. The router stays as it is; that settles the spec's "either … or" in favour of the prompt, by review.md's own rule.

## Reusable
- `test-pr-assets.sh` `mkrepo` for the `--base` cases, `run_in` for the stdin cases that must keep passing.
- `am_expected_block` / `am_pr` for the HEAD-sha and amended-row cases.
- `shell-guard.jsonl` fixture format for every deny-text and in-place-write case.
- `.claude/scripts/case-hash.sh` for row hashes.
- `project_config.py` for `app_roots`. Not re-read; the exit-2 path relies on `kit-pr-assets.py:316-319`.

## Blast radius
- Install: `install.sh:334` copies `.claude/hooks` and `.claude/scripts` unchanged, so every project gets the change on its next install.
- Addon twins: `addons/fastapi/hooks/tdd_py_lib.py` (CASE_DEF_RE :567, `_py_cases` :606) and `tdd-freeze-tests-py.py` (:46, :86). They key on the same `[A-Za-z][0-9]+` ids for freezing; item 4 must not change them.
- Contract tests on prompt text:
  - `test-workflow-contracts.sh:938-939`: review.md contains `ls-files --others --exclude-standard`.
  - `:1614-1616` (PK46): `exit 2` and "an app root's `src/`" in the review section.
  - `:931`: github.md needles.
  - `:941`: ship.md `kit-pr-assets.py drop`.
  - `:1528`: ship.md `--guarded-block`.
  - `:926-928`: PR body section order.
  - `test-hooks.sh:6250` and `test-workflow-contracts.sh:1536` assert the `--mode` lines.
- Fixtures asserting texts that change: `shell-guard.jsonl:907-908` (LP3.01/LP3.02 "only Claude Code runs loop-record.py"), X31.01 :831 and X31.04 :834 ("inline programs are not used here"), `test-hooks.sh:6822,6844` (GUARD FAILURE text), and `am_expected_block` :6714-6719 (block format).
- Shell writes into the project that item 7 would break:
  - `.claude/commands/loop/review.md:224-229`: `jq … >> .claude/.kit-health.jsonl`, a prescribed write into the project. Fix it in the same pass.
  - `addons/supabase/skills/patterns/supabase-client.md:53` and `addons/supabase/rules/06-database.md:87,119`: `supabase gen types … > src/types/database.types.ts`. This is a `.ts` target, already handled by the codegen branch :875-895 today, so its behaviour is unchanged.
  - `install.sh:644-651,796-798` and `hook-timings-report.sh:24` are run by the user or a hook, not by an agent's Bash. Out of the guard's path.

## Live DB state
n/a — no data.

## External surface
n/a — no third party.

## Traps (points of vigilance for the review)
- The block digest must keep covering the body only, and the hook keeps its substring check (`enforce-git-workflow.sh:2166`). A HEAD sha added to the comment must not make an unchanged body fail after a no-op rebase or amend the user does. Compare HEAD separately and only to explain the deny.
- `ROW_RE` :44 accepts only `[UMRB][0-9]+` ids. Item 5's declared test-after rewrites (EcoCrew: `test_s27_ac5_…`) cannot be written as rows today. Items 4 and 5 must share one id form (the full name on collision), accepted by `ROW_RE` and matched by `guarded_block`. A malformed row makes `parse_rows` return None, which rejects the whole plan go.
- `allowed` :745-746 defaults a row with no kind to `unfreeze`. Do not widen what a row silences beyond its exact path and id.
- The freeze hooks (`tdd-freeze-tests.sh`, the `-py` twins) and `.tdd-unfrozen`'s `UNFROZEN_LINE_RE` :583 keep `[A-Za-z][0-9]+` ids. Item 4 applies to the guarded block's report and the plan-gate rows only.
- Item 7 shares the `>`/source-writer branches with the codegen and test-first denies (:875-903). Their existing texts and asks must win where they apply today. The new deny only covers what passes silently now.
- Item 7 must keep `/dev/null`, `/dev/std*`, fd and `/tmp` rules exactly as they are (:736-749), and must not touch hook-internal writes (`hook-lib.sh:47,144`, `tdd-prove-red.sh:363,373`), which are not agent Bash.
- `review.md:224-229` must stop writing from the shell in the same pass, otherwise item 7 denies the review's own health probe.
- `github.md:222` pipes into `kit-pr-assets.py drop`. Item 1's no-pipe rule covers it too (`drop --pr <n>` or a body file), or item 1's new test fails on it.
- `test-pr-assets.sh` runs in a non-git temp cwd. The `--base` cases need `mkrepo`, and stdin cases K1-K3/K27-K30 must keep passing.
- In `prune-local`, `--keep` and `--slug` come from the caller. Resolve them, refuse symlinks and paths outside `.pr-shots/<slug>/` (`collect()` :105-147 already refuses symlinks and hardlinks), delete only `*.png`, and use non-recursive `os.rmdir`.
- The explorer's grep naming the literal `loop-record.py` was denied by the shell guard (LOOP_RECORD_RUN_RE matches the script name anywhere, even as a grep argument). This is the same over-match as item 2, and it hits read-only greps too.

## Open questions
1. **Item 2, inline read:** a live run (EcoCrew 2.5, 11:50) printed `.claude/.loop-record.json written by inline-path` for a `python3 -c` read, but static reading says `prevent-destructive-commands.sh:784-792` should fire first with another text. Should the plan reproduce it with a fixture first and fix whichever branch fires? Proposed answer: yes, the case is written red against the observed command.
2. **Item 2, scope of the loop-record match:** `LOOP_RECORD_RUN_RE` also denies a `grep` whose pattern names `loop-record.py` (seen during this research). Should item 2 narrow the match to an executed script (interpreter head of a segment), so read-only mentions pass? Proposed answer: yes. It is the same fix, and a grep never runs the script.
3. **Item 1, `drop` input:** `github.md:222` pipes a PR body into `drop`. Should `drop` take `--pr <n> --repo <r>` and read the body itself via `gh`, or `--body-file <path>`? Proposed answer: `--body-file`, because the script stays offline (its docstring: "Nothing is pushed or fetched") and the agent writes the body with `gh pr view --json body -q .body` into the scratchpad. That is a write outside the project, still allowed.
4. **Item 7, `.claude/.kit-health.jsonl`:** should the review's health emitter become a kit script (`kit-health.py finding --dim … --verdict … --summary …`) that appends in Python, or should `.claude/.kit-health.jsonl` be exempted from item 7? Proposed answer: a kit script, because an exemption is a hole in the rule this pass adds.
