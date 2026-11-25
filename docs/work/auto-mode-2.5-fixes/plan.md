# Plan: kit fixes from the EcoCrew agent-ia-2.5 / 4.6 auto runs   (entry: docs/specs/auto-mode-2.5-fixes.md · research: docs/work/auto-mode-2.5-fixes/research.md · design: n/a)
Token profile: economy
Base: 1a99f7c

## Skips
- DB, Backend, Front, Wiring, UI tests: SKIP. Kit hooks, scripts and prompts only (INTERFACE SKIP).
- Test-first TS/Python layers: none. Kit tests are shell suites under `.claude/hooks/`, outside the freeze matcher. Each step is still test-first: its cases are written and observed red before the code.
- `kit-gate-route.py` routing: SKIP. Item 9 is a prompt fix (`review.md:213-214` forbids a sixth dimension); the router only gains a clearer refusal text.
- Freeze hooks and `.tdd-unfrozen` id grammar (`tdd-freeze-tests.sh`, `addons/fastapi/hooks/*`, `UNFROZEN_LINE_RE`): SKIP. Item 4 changes the guarded block's report and plan-gate rows only.

## Proposed answers to research's open questions
1. Inline read of the record: yes. Case X43.07 is written red on the observed EcoCrew command first, and the fix targets whichever branch fires. The deny stays (inline programs are banned); only the text changes.
2. Narrow the loop-record match: **no** (plan-critic Q1). Narrowing loosens the guard (`timeout`, `env`, `xargs`, `$(…)` and direct exec are all denied today), which the spec forbids (OUT: loosenings go to a `critical` pass). Item 2 changes deny **texts** only. A grep quoting the script path stays denied, a known limit carried to the critical pass. Cases X44.06-X44.10 pin today's denies.
3. `drop` input: `drop --branch <b> --body-file <path>`. The agent writes the body with `gh pr view <n> --json body -q .body > <scratchpad>/pr-<n>-body.md` (a write outside the project, still allowed), then runs the script alone. Stdin stays accepted for the existing tests.
4. Health probe: a kit script, `.claude/hooks/kit-health.py finding --dim <d> --verdict <v> --summary <s>`, which appends the same JSON line `review.md:224-229` writes today. No exemption from item 7.
5. Item 4 scope, **an entry amendment asked at the gate** (plan-critic F3): the full-name fallback is **Python only**. The spec names the TS twin and "TS title", but a TS title holds spaces and quotes that the row grammar (`<path> | <id> | <sha>`) and the arbiter's `case:` field cannot carry without a new escaping rule. A TS collision needs two `it('S27 …')` titles, a shape no kit prompt produces (test-first ids are `[UMRB][0-9]+`, test-after TS titles carry none). TS behaviour stays unchanged (GB5). If you refuse, the plan adds a TS collision case and a quoted-title id form.
6. Auto write path for item 5 (plan-critic F1): a new arbiter verdict `kind: declared-rewrite` (`path`, `case` = `[UMRB][0-9]+` or `test_[A-Za-z0-9_]+`, `sha256` of the new title, `verdict: accept | refuse`), ledgered by `subagent_stop`. In `auto`, `/loop:plan` step 7 launches one fresh `arbiter` per declared rewrite, as `orchestrate.md` Phase 4 does per frozen case. `guarded_block` counts `declared-rewrite`/`accept` entries as allowed. `protect-files.sh` and the freeze hooks keep matching `kind: frozen-case` only, so a `declared-rewrite` never unfreezes anything (GB10). In `moi` the user's plan-gate rows carry the same ids (widened `ROW_RE`).
7. "Registered worktree" in item 7 (plan-critic F2) means the kit's worktrees under `.claude/worktrees/` (`10-worktrees.md`, Phase 0.5), which `cwk_guard_rel` already maps inside the project (`hook-guarded.sh:547-550`). They get the new deny (X43.13). A sibling worktree outside the root keeps today's ask (`guard_classify_outside`), which is stricter than a pass, so nothing is loosened.

## Write chain (sequential)
Each step: its cases first, observed red, then the code, then its suite green.
1. **Item 9, shadow dimension.** `review.md` Stage 2.5 says each item carries the `dimension` of the surface the shadowed dependency belongs to, one of the five. Stage 3bis names the same list. `kit-gate-route.py` refuses an unknown dimension with a text naming the five and the Stage 2.5 rule. Cases PK49, G30, G31.
2. **Item 6, agent prompts.** One "Refused shapes" block in `implementer.md` and `test-writer.md` (each line: shape → tool instead). `orchestrate.md` Phase 0 "Shell discipline" gains the `git -C` line, the `sed -i`/`perl -i` line and the `python3 -`/`-c` line. Case PK50.
3. **Item 1, no pipe into a kit script.**
   - `kit-pr-assets.py`: `ui --base <ref>` builds the list itself (`git -c core.quotePath=false diff --name-only <ref>` ∪ `git ls-files --others --exclude-standard`, run in cwd); `drop --body-file <path>` reads the body from that file.
   - Stdin kept for both when the option is absent.
   - Prompts: `review.md:160` and `github.md:222` rewritten to the alone forms.
   - Cases K31-K36, PK51, PK52.
4. **Item 8, prune-local.** `kit-pr-assets.py prune-local --slug <slug> --keep <run-dir>`: deletes `*.png` in the slug's other run dirs under `.pr-shots/<slug>/`, then removes each emptied run dir with `os.rmdir`. It refuses a `--keep` that is not an existing direct child dir of `.pr-shots/<slug>/` (the slug dir itself, a nonexistent or mistyped run, anything outside), a symlinked dir or file, and a slug that is not `[a-z0-9.-]+`. `ship.md` 4bis-PR gains step 4: after `gh pr create` returns its URL, the main thread runs `prune-local` alone on the shipped run (`plan.md` `Screenshots run:`). Cases K37-K43, PK53.
5. **Item 2, loop-record deny texts (texts only, no verdict changes).**
   - `prevent-destructive-commands.sh` (around 972-977): the deny condition is unchanged. When one segment of the denied command (split on `;`, `&&`, `||`, `|`, newline) is exactly a manual form (`python3 .claude/hooks/loop-record.py --clear|--block|--mode|--guarded-block`), the text becomes "run `python3 .claude/hooks/loop-record.py <flag>` alone, in its own Bash call". Every other denied shape keeps today's text.
   - The inline branch (around 772-800 and 868-874) names `Read` and `loop-record.py --mode` when the inline program's path is `.claude/.loop-record.json`.
   - Cases X44.01-X44.10, X43.07.
6. **Item 7, no shell write into the project, plus the health script.**
   - First `kit-health.py`; `review.md:224-229` switches to it (cases KH1-KH3, PK54).
   - Then `prevent-destructive-commands.sh`: `>`, `>>`, `&>`, `tee [-a]`, `sed -i`, `perl -i` whose resolved target is inside the project root or a registered worktree are denied: "shell write into the project: <rel> written by <verb>. Write files with the Write/Edit tool."
   - Existing branches keep precedence where they fire today: codegen allow, `.ts(x)`/`.py` test-first/codegen texts, guarded asks, protected-root denies. Outside-project rules are unchanged.
   - An in-project glob target (`sed -i … docs/*.md`) is denied like a resolved one.
   - Existing pass fixtures flipped to deny with reason "shell write into the project" (plan-critic Q2): X6.16 (`shell-guard.jsonl:87`), X9.11 (:121), X32.09 (:844). This is a planned fixture change, recorded here, not a case edit at refactor.
   - Cases X43.01-X43.06, X43.08-X43.14, PK55.
7. **Item 4, precise Python case ids.**
   - `loop-record.py`: per Python test file, when an id from `PY_CASE_RE` names ≥2 `def test_` in the base or in HEAD, each changed case with that id is reported by its full function name (the name found in the base).
   - Unique ids keep their `B517` form.
   - `ROW_RE` also accepts a Python test function name (`test_[A-Za-z0-9_]+`) as the id. `allowed` matches a row's id against the reported id, exact string.
   - `ledger_entry` gains `kind: declared-rewrite` (answer 6), with its own id grammar `[UMRB][0-9]+|test_[A-Za-z0-9_]+`. `CASE_RE` for `frozen-case` is unchanged. `guarded_block`'s `allowed` takes `declared-rewrite`/`accept`. The first `declared-rewrite` verdict per (path, id) is final, as for frozen cases.
   - Cases GB1-GB7, GB9-GB11.
8. **Item 5, declared rewrites.**
   - `plan.md` step 7: a plan that rewrites existing cases of test-after files lists each one in `Frozen cases to amend:` (path | id or full name from item 4 | hash of the new title). Such a row writes no `.tdd-unfrozen` line, because the file is not frozen.
   - `orchestrate.md` Phase 4 says the same in one line.
   - In `auto`, step 7 launches one fresh `arbiter` per declared rewrite with `kind: declared-rewrite`. `arbiter.md` gains that block form next to `frozen-case`. Frozen files keep their `kind: frozen-case` rule.
   - Cases PK56, PK58.
9. **Item 3, block on the shipped HEAD.**
   - `ship.md` 4bis-PR step 2 opens with: "only after the `github` agent reported the commit and the push; never in parallel with them". `github.md` step 5 names `--guarded-block` in the same order.
   - `loop-record.py --guarded-block` prints a final line `<!-- guarded-files head:<40-hex> -->` after the block. It is outside the hashed body and outside the string the hook compares.
   - `enforce-git-workflow.sh` `guarded_block_check` strips the trailing `head:` line from the script's stdout before the substring compare, so the compared string is header, digest and body, as today. On a mismatch, when the body carries a `head:` line whose sha differs from HEAD, the deny says "the block in the body was computed on <short>, HEAD is now <short>: rerun --guarded-block after the push and paste it".
   - `test-hooks.sh` `am_expected_block` (:6714-6719) appends the head line, its value from `git -C <tree> rev-parse HEAD` (plan-critic Q3). This is a planned helper change: G22.009 (:6798), G22.010 (:6846) and AM64 keep their assertions and stay green through it.
   - Cases AM71-AM74, PK57.
10. **Docs and refactor.** `docs/Claude_Workflows.md:344` and the `e2e-playwright` SKILL prose follow the alone forms. Run `/kit:doctor`, the full suites, and refactor under green with no case edited.

## Parallel lots (inside this track, same tree)
none — fully sequential. Items 2 and 7 share `prevent-destructive-commands.sh` and `shell-guard.jsonl`; items 1, 4 and 8 share `kit-pr-assets.py` / `test-pr-assets.sh`; items 4, 5 and 3 share `loop-record.py` / `test-hooks.sh`.

## Track isolation
- Worktree: none, single track (branch `feat/auto-mode-2.5-fixes` from main 1a99f7c, created at the plan gate).
- Shared foundations touched: kit hooks (`prevent-destructive-commands.sh`, `enforce-git-workflow.sh`, `loop-record.py`) and loop prompts. No other kit pass runs beside this one until it is merged.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/commands/loop/review.md` | Edit | Stage 2.5 dimension (9); `ui --base` (1); health via kit-health.py (7) |
| `.claude/hooks/kit-gate-route.py` | Edit | refusal text for an unknown dimension (9) |
| `.claude/hooks/test-gate-route.sh` | Edit | G30 |
| `.claude/agents/implementer.md`, `.claude/agents/test-writer.md` | Edit | refused-shapes block (6) |
| `.claude/commands/loop/orchestrate.md` | Edit | shell discipline lines (6); declared rewrites line (5) |
| `.claude/hooks/kit-pr-assets.py` | Edit | `ui --base`, `drop --body-file` (1); `prune-local` (8) |
| `.claude/hooks/test-pr-assets.sh` | Edit | K31-K42 |
| `.claude/agents/github.md` | Edit | drop alone form (1); `--guarded-block` order (3) |
| `.claude/commands/loop/ship.md` | Edit | prune-local step (8); block order (3) |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | loop-record texts (2); in-project shell-write deny (7) |
| `.claude/hooks/shell_targets.py` | Edit | only if the executed-script test or the target kinds need it (2, 7) |
| `.claude/hooks/fixtures/_harness/shell-guard.jsonl` | Edit | X43.*, X44.*; X6.16, X9.11, X32.09 flipped to deny (Q2); LP3.01/LP3.02 texts if their command is a chained manual form |
| `.claude/agents/arbiter.md` | Edit | `kind: declared-rewrite` block (5) |
| `.claude/hooks/kit-health.py` | Create | health probe append (7) |
| `.claude/hooks/test-hooks.sh` | Edit | KH1-KH3, GB1-GB7, GB9-GB11, AM71-AM74; `am_expected_block` head line (Q3) |
| `.claude/hooks/loop-record.py` | Edit | full-name fallback, ROW_RE (4); head line (3) |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | stale-head deny text (3) |
| `.claude/commands/loop/plan.md` | Edit | declared rewrites at step 7 (5) |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | PK49-PK57 |
| `.claude/settings.json` / install manifests | Edit if needed | register `kit-health.py` wherever kit scripts are listed (kit-doctor command refs) |
| `docs/Claude_Workflows.md`, `.claude/skills/e2e-playwright/SKILL.md` | Edit | prose forms (1) |

## Contracts
- `python3 .claude/hooks/kit-pr-assets.py ui --base <ref>` → stdout `ui` | `none`, exit 0. Exit 2 on invalid project.json, unknown ref, or not a git tree.
- `python3 .claude/hooks/kit-pr-assets.py drop --branch <b> --body-file <path>` → same output and effects as today's stdin form.
- `python3 .claude/hooks/kit-pr-assets.py prune-local --slug <s> --keep <dir>` → stdout lists the deleted run dirs (or `none`), exit 0; exit 2 with a one-line reason on refusal. Deletes only `*.png` in `.pr-shots/<s>/<other-run>/` and those emptied run dirs.
- `python3 .claude/hooks/kit-health.py finding --dim <d> --verdict confirmed|refuted|minor --summary <text>` → appends `{"ts","source":"review:<d>","event":"finding","verdict","summary"}` to `.claude/.kit-health.jsonl`. Exit 0 even when the file cannot be written (best-effort, as today); exit 2 on a bad verdict.
- `--guarded-block` output: `### Guarded files touched` / `<!-- guarded-files sha256:<digest of body> -->` / body / `<!-- guarded-files head:<sha> -->`. The digest and the hook's substring compare cover the first three parts only.
- Plan-gate row: `<test path> | <[UMRB][0-9]+ or test_[A-Za-z0-9_]+> | <64-hex>`.

## Test plan (gate — validated before EXECUTE)

### Test-first — none (no TS/Python test-first layer); kit cases, each observed red before its code

#### .claude/hooks/test-gate-route.sh — item 9
**Reproduction**
- [ ] G30 a route entry with `dimension: "shadow"` (EcoCrew 4.6 K8) exits 2 with a reason naming the five dimensions and "Stage 2.5" — today's reason names the five only
**Core behaviour**
- [ ] G31 a Stage 2.5 item written as review.md now tells (`dimension: "correctness"`, its other fields as Stage 3bis lists) routes with exit 0 and its follow-up line shows `correctness`

#### .claude/hooks/test-pr-assets.sh — items 1 and 8
**Reproduction**
- [ ] K31 `ui --base <base>` in a `mkrepo` tree with a tracked change to `src/X.tsx` prints `ui`, with nothing on stdin — today argparse refuses `--base` (exit 2)
**Core behaviour**
- [ ] K32 `ui --base <base>` with only an untracked `src/New.tsx` (not ignored) prints `ui`
- [ ] K33 `ui --base <base>` with only a change to `docs/x.md` prints `none`
- [ ] K34 `ui --base <base>` with an ignored `src/Ignored.tsx` only prints `none`
- [ ] K35 `ui --base <unknown-ref>` exits 2, nothing on stdout; `ui --base <base>` with an invalid `.claude/project.json` exits 2
- [ ] K36 `drop --branch feat/x --body-file <file>` gives the same tree as the stdin form of K26's setup; a missing body file exits 2
- [ ] K37 `prune-local --slug s --keep .pr-shots/s/r2` with runs `r1`, `r2`, `r3` holding PNGs deletes the PNGs of `r1` and `r3`, removes both dirs, and leaves `r2` byte-identical
**Business rules**
- [ ] K38 a run dir holding a non-PNG file (`notes.txt`) keeps that file and its dir; its PNGs are deleted
- [ ] K39 another slug's dir `.pr-shots/t/` is untouched
**Edge cases**
- [ ] K40 `--keep` outside `.pr-shots/s/` (`.pr-shots/t/r1`, `../x`, an absolute path elsewhere) exits 2 and deletes nothing
- [ ] K41 a run dir that is a symlink, or a PNG that is a symlink, is not followed: exit 2, nothing deleted
- [ ] K42 no `.pr-shots/s/` dir prints `none`, exit 0
- [ ] K43 `--keep .pr-shots/s` (the slug dir) and `--keep .pr-shots/s/r9` (no such run) exit 2 and delete nothing

#### .claude/hooks/fixtures/_harness/shell-guard.jsonl — items 2 and 7
**Reproduction**
- [ ] X44.01 deny `cat x; python3 .claude/hooks/loop-record.py --mode`, reason contains "alone, in its own Bash call" (EcoCrew 4.6 13:43) — today "only Claude Code runs"
- [ ] X43.07 deny `python3 -c "import json;d=json.load(open('.claude/.loop-record.json'));print(d)"`, reason contains "Read" and not "written by" (EcoCrew 2.5 11:50)
- [ ] X43.01 deny `sed -i 's/a/b/' docs/work/x/plan.md`, reason contains "shell write into the project" (EcoCrew 4.6 13:55) — passes today
**Core behaviour**
- [ ] X44.02 deny `grep -n x a.md && python3 .claude/hooks/loop-record.py --guarded-block` with the same "alone" text
- [ ] X44.03 deny `cat x; python3 .claude/hooks/loop-record.py` (no flag): reason still "only Claude Code runs loop-record.py"
- [ ] X44.04 pass `python3 .claude/hooks/loop-record.py --mode` alone (LP3.03 unchanged)
- [ ] X44.05 deny `grep -rn "python3 .claude/hooks/loop-record.py --mode" .claude/commands` (pinned: today's deny stays, text unchanged)
- [ ] X44.06 deny `env python3 .claude/hooks/loop-record.py --mode` (pinned)
- [ ] X44.07 deny `timeout 5 python3 .claude/hooks/loop-record.py` (pinned)
- [ ] X44.08 deny `.claude/hooks/loop-record.py < x.json` (pinned)
- [ ] X44.09 deny `x=$(python3 .claude/hooks/loop-record.py --mode)` (pinned)
- [ ] X44.10 deny `echo x | xargs python3 .claude/hooks/loop-record.py` (pinned)
- [ ] X43.02 deny `echo x > docs/work/x/a.md`
- [ ] X43.03 deny `echo x >> docs/notes.md`
- [ ] X43.04 deny `printf x | tee docs/work/x/a.md`, `tee -a README.md` and `printf x | tee src/a.ts` (the last keeps today's test-first/codegen reason if one fires)
- [ ] X43.05 deny `perl -i -pe 's/a/b/' docs/x.md`
- [ ] X43.06 deny `cmd &> build.log` (project root)
**Business rules**
- [ ] X43.08 pass `cmd > /dev/null 2>&1` and `cmd 2>/dev/null`
- [ ] X43.09 pass `cmd > /tmp/claude-1000/x/scratchpad/out.txt`
- [ ] X43.10 keep today's verdict and reason for `echo x > src/a.ts` (test-first/codegen text) and for a guarded path (`echo x >> .claude/.size-exempt` → ask "guarded path:", X1.03)
**Edge cases**
- [ ] X43.11 deny `sed -i.bak 's/a/b/' docs/x.md` and `sed --in-place 's/a/b/' docs/x.md`
- [ ] X43.12 pass `sed -n '1,5p' docs/x.md` and `grep x docs/x.md > /dev/null`
- [ ] X43.13 deny `sed -i 's/a/b/' .claude/worktrees/t1/docs/x.md` and `echo x > .claude/worktrees/t1/a.md` (a kit worktree path), reason "shell write into the project"
- [ ] X43.14 flipped fixtures: X6.16, X9.11 (`sed -i … docs/*.md`, glob target) and X32.09 (`cat >> docs/work/x/plan.md <<'EOF'`) become deny, reason "shell write into the project"

#### .claude/hooks/test-hooks.sh — kit-health (item 7)
- [ ] KH1 `kit-health.py finding --dim tests --verdict confirmed --summary "a b"` appends one line whose JSON has `source` `review:tests`, `event` `finding`, `verdict` `confirmed`, `summary` `a b` and an ISO-8601 `ts`
- [ ] KH2 `--verdict maybe` exits 2 and appends nothing
- [ ] KH3 an unwritable `.claude/.kit-health.jsonl` (a directory at that path) exits 0 and prints one English line on stderr

#### .claude/hooks/test-hooks.sh — guarded block (items 4, 5; `am_*` helpers, auto record)
**Reproduction**
- [ ] GB1 a Python test file whose base has `def test_s27_ac5_a()` and `def test_s27_ac6_b()`, both renamed in HEAD, prints two GUARD FAILURE lines naming `test_s27_ac5_a` and `test_s27_ac6_b` (EcoCrew 2.5) — today one line `S27`
**Core behaviour**
- [ ] GB2 a file with unique ids (`def test_b517_x`, `def test_b521_y`) changed prints `B517` and `B521`, exactly as today (6822/6844 texts green)
- [ ] GB3 on a collision, an unchanged sibling (`test_s27_ac7_c` untouched) and a case added in HEAD (`test_s27_ac8_d`, absent from the base) are not reported
- [ ] GB4 an auto record whose verdicts were ledgered **through the hook** (a SubagentStop event for agent_type `arbiter` whose last message holds an `ARBITER VERDICT` block `kind: declared-rewrite`, `path`, `case: test_s27_ac5_a`, `sha256`, `verdict: accept`) prints no GUARD FAILURE for `test_s27_ac5_a`; `test_s27_ac6_b` stays reported
**Business rules**
- [ ] GB5 a TS test file is reported exactly as today (TS_CASE_RE unchanged)
- [ ] GB6 a row whose id is `test_x-y` (not `test_[A-Za-z0-9_]+`) makes the plan go's rows invalid (parse_rows None), as any malformed row today
- [ ] GB7 a row id `test_s27_ac5_a` on a file with a unique-id case `B517` changed does not silence `B517`
- [ ] GB9 a released record carrying a user plan-gate row `<path> | test_s27_ac5_a | <hash>` (moi path, widened ROW_RE) prints no GUARD FAILURE for that case; its sibling stays reported
- [ ] GB10 a `declared-rewrite`/`accept` verdict for `U3` on a frozen file does not let a `.tdd-unfrozen` line in (protect-files still asks/denies as without a verdict), and the freeze hook still denies an edit of U3
- [ ] GB11 a `declared-rewrite` block with `case: S27`, `case: test_x-y`, or `verdict: unfreeze` is not ledgered (record verdicts unchanged); a second `declared-rewrite` for the same (path, id) is not ledgered

#### .claude/hooks/test-hooks.sh — head line (item 3)
**Reproduction**
- [ ] AM71 `--guarded-block` prints `<!-- guarded-files head:<HEAD sha> -->` as its last line, and the digest equals sha256 of the body without that line — today no head line
**Core behaviour**
- [ ] AM72 `gh pr create` with a body holding the current block and head line passes (AM64/G22 unchanged)
- [ ] AM73 a body whose block was printed before a new test-file commit (block now differs) is denied with a reason naming both short shas and "rerun --guarded-block after the push" — today the generic "byte for byte" text
**Edge cases**
- [ ] AM74 a body whose block still matches but whose head line names an older sha (a commit that changed no guarded or test file) passes

#### .claude/hooks/test-workflow-contracts.sh — prompts
- [ ] PK49 review.md Stage 2.5 requires each item's `dimension` to be one of the five, and review.md's dimension list equals `DIMENSIONS` in kit-gate-route.py (parsed from both)
- [ ] PK50 implementer.md and test-writer.md each name `git -C`, `sed -i`, heredoc, `python3 -`, `Any`, and the frozen-file import rule; orchestrate.md Phase 0 names `git -C`, `sed -i` and `python3 -`
- [ ] PK51 no file under `.claude/commands`, `.claude/agents`, `.claude/skills`, `.claude/guides`, `docs/Claude_Workflows.md` pipes into a kit script (regex `\|\s*((python3?|bash|sh)(\s+-\S+)*\s+)?\.claude/(hooks|scripts)/`); the check itself fails on a fixture line for each of `| python3 .claude/hooks/x.py`, `| python3 -I .claude/hooks/x.py`, `| bash .claude/scripts/x.sh`, `| .claude/hooks/x.py`
- [ ] PK52 review.md holds `kit-pr-assets.py ui --base`; github.md holds `drop --branch` with `--body-file`; the needles at 938-939 and 941 are updated, not deleted
- [ ] PK53 ship.md 4bis-PR holds `prune-local` after `gh pr create`
- [ ] PK54 review.md holds `kit-health.py finding` and no `>> .claude/.kit-health.jsonl`
- [ ] PK55 no kit prompt prescribes a shell write into the project (`>`/`>>`/`tee`/`sed -i`/`perl -i` into a relative project path, in commands/agents/skills/guides; `/dev/null` and absolute `/tmp` excluded)
- [ ] PK56 plan.md step 7 names test-after rewrites in `Frozen cases to amend:`, and orchestrate.md Phase 4 says such a row writes no `.tdd-unfrozen` line
- [ ] PK57 ship.md 4bis-PR step 2 says `--guarded-block` runs after the commit and push are reported, never in parallel; github.md names `--guarded-block`
- [ ] PK58 arbiter.md documents the `kind: declared-rewrite` block (fields `path`, `case`, `sha256`, `verdict: accept | refuse`), and plan.md step 7's auto paragraph launches one arbiter per declared rewrite

### Test-after
- `/kit:doctor` passes; `bash .claude/hooks/test-hooks.sh`, `test-workflow-contracts.sh`, `test-pr-assets.sh`, `test-gate-route.sh`, `test-install.sh`, `test-kit-doctor.sh` all green.

## Vigilance (carried from research)
- Block digest and the hook's substring compare cover the body only. The head line is informative, so a no-op amend never turns a correct body into a deny (AM74).
- `ROW_RE` widening is exact: one more alternative (`test_[A-Za-z0-9_]+`). `allowed` matches path and id exactly, a row never silences another case (GB7), and a malformed row still voids the rows (GB6).
- Freeze hooks, the `-py` twins and `UNFROZEN_LINE_RE` keep `[A-Za-z][0-9]+` ids, untouched.
- In-project shell-write deny: existing codegen, test-first, guarded and protected-root branches keep precedence and texts (X43.10). Outside-project rules (`/dev/null`, fd, `/tmp`) are byte-identical in behaviour (X43.08-09).
- `review.md:224-229` moves to `kit-health.py` in the same step as the deny (PK54 before X43.*).
- `github.md:222` pipe is fixed with item 1 (PK51 covers it).
- `test-pr-assets.sh` stdin cases K1-K3, K26-K30 stay green; `--base` cases use `mkrepo`.
- `prune-local` never deletes a non-PNG, never follows a link, never leaves `.pr-shots/<slug>/`, never `rmtree` (K38-K41).
- Item 2 changes texts only: every command denied today stays denied (X44.03-X44.10, LP3.02 `bash -c`), and no verdict in `shell-guard.jsonl` flips for item 2.
- Changed deny texts: update LP3.01/LP3.02 only if their command is a chained manual form; otherwise they stay byte-identical.
- `declared-rewrite` never reaches the freeze: `protect-files.sh` (:380-415) and `tdd-freeze-tests.sh` keep keying on `kind: frozen-case` with verdict `unfreeze` (GB10). `guarded_block`'s `allowed` must test `kind == "declared-rewrite" and verdict == "accept"` explicitly, never through the frozen-case defaults (:745-746).
- `guarded_block_check` strips only a final line matching `^<!-- guarded-files head:[0-9a-f]{40} -->$`; any other line difference still denies.
- (F4) The PR's gate section lists every suite run (`test-hooks.sh`, `test-workflow-contracts.sh`, `test-pr-assets.sh`, `test-gate-route.sh`, `test-install.sh`, `test-kit-doctor.sh`). The ACs' "test-hooks.sh" is read as the kit's suites.
- (Q6) New shell-guard ids use `X44.*`, never `LP5.*`, which `test-hooks.sh:4599,4725` already uses.
- (F6) "10-worktrees.md" in answer 7 is `.claude/guides/10-worktrees.md`.
- (Q8) `am_expected_block` takes the tree as its first argument; each caller passes the tree after its last `am_commit` (G22.010 :6841-6842 included).
- (Q9) PK55 matches prescriptions, not prohibitions: a line inside a "Refused shapes"/"Never" block, or one starting with `no `/`never`, is not a prescription, so PK50's blocks stay green under PK55.
- (Q10) X43.04's `tee src/a.ts` sub-case pins the reason observed at its RED run, written into the fixture, not left conditional.
- (Q11) An id that collides only in HEAD (base holds one `test_s27_a`, HEAD adds `test_s27_b`) reports the changed base case by its base name. An added case is not a rewrite and is never reported (the guard keeps `case_ids(before)` as its scope). A case for it: GB3 extended with an added sibling.
- (Q5) `prune-local` resolves `--keep` with `realpath` and requires `dirname(keep) == realpath(.pr-shots/<slug>)` and `isdir(keep)` (K43).

## Acceptance criteria (carried from the entry artifact)
- [ ] `python3 .claude/hooks/kit-pr-assets.py ui --base <sha>` run alone from the project root prints `ui` for a working tree changing `src/X.tsx` and `none` for one changing only `docs/x.md`, untracked files included; an invalid `project.json` still exits 2.
- [ ] `review.md` holds no pipe into a kit script, and `test-hooks.sh` checks that no kit prompt pipes into `.claude/hooks/*.py`.
- [ ] `cat x; python3 .claude/hooks/loop-record.py --mode` is denied with a text that tells to run the form alone; `python3 .claude/hooks/loop-record.py --mode` alone still prints the mode; running it with no flag is still denied with the current text.
- [ ] A `python3 -c` that reads `.claude/.loop-record.json` is denied with a text naming `Read` / `--mode`, not "written by".
- [ ] `--guarded-block` prints the HEAD sha it ran on. A body whose block was computed on an older HEAD is denied with a text saying HEAD moved. A fresh block passes as today.
- [ ] In a test file with `test_s27_ac5_x` and `test_s27_ac6_y` both changed, the block lists both full names; a file whose ids are unique (`test_b517_…`) still prints `B517`.
- [ ] An `amended` row recorded at the plan gate for a non-frozen test case removes its `GUARD FAILURE` line; an undeclared rewrite of another case in the same file still prints one.
- [ ] `sed -i 's/a/b/' docs/work/x/plan.md`, `echo x > docs/work/x/a.md` and `… | tee src/a.ts` are denied; `cmd > /dev/null` and a write to the session scratchpad pass.
- [ ] No kit prompt or script in the repo prescribes a shell write into the project (grep proof in the PR).
- [ ] `prune-local` keeps the shipped run dir intact, deletes the PNGs of the slug's older runs, removes their emptied dirs, and refuses a `--keep` outside `.pr-shots/<slug>/`.
- [ ] A route file holding a Stage 2.5 shadow finding, written exactly as `review.md` tells, routes with exit 0 and keeps its dimension, and a test checks that `review.md`'s dimension list and `DIMENSIONS` agree.
- [ ] `implementer.md` and `test-writer.md` carry the refusal block of item 6, and `/kit:doctor` passes.
- [ ] `bash .claude/hooks/test-hooks.sh` passes with a case per criterion above.

## Plan critic
- pass 1: completeness 70, quality 60. F1, F2, F3, Q1, Q2, Q3 confirmed by verifier → rewrite. Minors F4, F5, Q4-Q7 → Vigilance or folded in (GB8 dropped: green before and after).
- pass 2: completeness 90, quality 86. F1, F2, Q1, Q2, Q3 fixed. F3 → arbitrate (Plan critic, open, at the gate). Minors F6, Q8-Q11 → Vigilance.
- completeness: 90
- quality: 86
- surviving blockers: none (F3 open for the user at step 7)

## Gate
- 2026-11-25 go (user, Plan gate; Frozen cases to amend: none)
- Contract: as written
- Contract: amended: item 4's full-name fallback is Python only; TS_CASE_RE and TS reporting unchanged (GB5) — user's answer to plan-critic F3 (Plan critic, open), 2026-11-25
- Open question 1 (inline read text) → reproduce X43.07 first, deny kept, text names Read / --mode
- Open question 2 (narrow loop-record match) → no; texts only, X44.05-X44.10 pin today's denies
- Open question 3 (drop input) → `drop --branch <b> --body-file <path>`, stdin kept
- Open question 4 (health probe) → `kit-health.py finding`, no exemption from item 7
- Answer 6 (auto path for item 5) → arbiter `kind: declared-rewrite`, never unfreezes
- Answer 7 (registered worktree) → `.claude/worktrees/*` denied; sibling worktree keeps today's ask
- amended 2026-11-25 (user, EXECUTE step 6): 13 existing control fixtures in test-hooks.sh that expected `pass` for an ordinary in-project shell write now expect `deny` with reason "shell write into the project" — CG13 (`echo x > docs/a.md`), CG29[`sed -i s/a/b/ docs/*.md`], CG29[`echo x > docs/*.md`], CG33[`echo x > docs/*.md`], CG33[`echo x > docs/*.json`], CG33[`sed -i s/a/b/ docs/*.md`], CG44, CG44b, CG53, CG93[`echo x > docs/a.md`], KB18[`echo x > docs/a.md`], KB19[`echo x > .claude/INSTALL_PROFILE`], KB19[`echo x >> a`]. Commands unchanged; the reason keeps each control's value (no other guard fires). `cp`/`mv` entries in the same loops keep `pass`.
