# Plan: blocked-record lifecycle   (entry: docs/specs/blocked-record-lifecycle.md · research: docs/work/blocked-record-lifecycle/research.md · design: n/a)
Token profile: critical
Base: 3b732b0724564f1257d3a1bfdc40fe9e36d0ffc7

## Skips
- DB : SKIP — no database.
- Backend : SKIP — kit hooks, launcher and prompts only.
- Front / Wiring / UI tests : SKIP — no UI (INTERFACE SKIP).
- Test-first TS/Python layers : none — kit tests are shell fixture suites under `.claude/hooks/`, outside the
  freeze matcher (`src/`, `shared/`, `tests/services/`), so no `.tdd-unfrozen` exception for edited kit cases.
  Each step is still test-first: its cases are written and observed red before the code.

## Proposed answers to research's open questions
1. `--release` from the shell guard: **deny when `cwk_auto_mode` holds, ask otherwise** (Scope 4 as contracted:
   "denied in auto and asks in moi"). It never joins `LOOP_RECORD_CLEAR_RE`, any allow list or HP_WANT. The deny
   text names `--release` as the user's command. (Cases AM18.r, AM18.r2.)
2. The `!` prefix: not probed; the docs tell the user to run `python3 .claude/hooks/loop-record.py --release` in
   their own terminal (a blocked record is still auto, so the agent's call is denied either way).
3. `--mode` prints `blocked` for a v1 record with `"blocked": true` **whatever the branch** (checked before
   `auto_mode`), so a resume from the main tree on the base branch stops too. Invalid/absent → `moi`. (AM62.x)
4. Launcher: one `blocked_record(PROJECT)` check before **every** launch — first `run_claude`, each saturation
   restart, and the Codex fallback. It reads `PROJECT/.claude/.loop-record.json` directly (no git, no
   `loop-record.py`); absent/unreadable/invalid → no refusal. Refusal: stderr
   `loop record blocked (<blocked_at>): run python3 .claude/hooks/loop-record.py --release to resume in moi`,
   exit 2, no session started. (WF cases)
5. A contract go on a released record wipes the ledger: OUT of scope (Scope OUT "other follow-ups"); written to
   follow-ups.md and to Vigilance.
6. The `--mode` consumers (plan.md:116, interface.md:63, review.md:260): each gains "`blocked` → stop
   (`/loop:orchestrate` Phase 0)"; Phase 0 step 2 stops first anyway. (AMC25.6-25.8)
7. Kit test files are outside the freeze matcher (`tdd-freeze-tests.sh:135` freezes `*.test.ts(x)` only):
   AM60.2/AMC20.3/AMC23.2/AMC23.3/AMC24.3 are edited in place (AM12 is unchanged), each edit listed in the PR's
   deviations.
8. (critic F1) A same-pass plan go on a released record keeps it released: `released_at` joins
   `KEPT_ON_PLAN_GO`. A contract go still rebuilds the record (OUT, follow-up).
9. (critic F6) github.md gets the lift sentence too (one line under its PR template notes), pinned like the others.

## Write chain (sequential)
1. **`loop-record.py` `--mode` + `--release`.** Cases AM62-AM63 red first. `--mode`: blocked check before
   `auto_mode`. New `release_record()` modelled on `mark_blocked` (locked, atomic, no-op unless v1 and
   `blocked is True`): mode → `moi`, pop `blocked`/`blocked_at`, set `released_at`, keep everything else;
   (amended, review 1 R1) comment out the verdict-only `.tdd-unfrozen` lines. `main()` branch `--release` before the stdin fall-through. Edit AM60.2 → `blocked`.
   Write under `locked()` through `write_record` (AM63.9).
2. **`guarded_block` for a released record.** Cases AM64 red first. New `released_mode(tree, record)`: v1, mode
   `moi`, `released_at` string, `contract_go` dict, branch/base/base_sha strings, HEAD == branch.
   `guarded_block` emits when `auto_mode or released_mode`; `guarded_op`/`subagent_stop` stay auto-only.
3. **`enforce-git-workflow.sh` `record_allow`.** Cases G21.043-G21.043.4 red first (G21.003 and G21.010 are taken). The :2140
   select stops excluding only `blocked`: it reads `released_at` too, runs the same preconditions as an auto PR
   (:2145-2150: head == branch == `--head`, repo/base/slug, body file present), then for a released record
   (`released_at` string) the exact PR form runs `guarded_block_check` (deny on mismatch) and returns without
   `decide allow` (falls to the generic ask); the push form returns before its allow (ask). "Released" means
   the same thing in jq and Python: `released_at` string on a v1 record on its branch (`released_mode`).
   `lp_git_setup` gains `lpreleased` (body holding the block `--guarded-block` computes at setup) and
   `lpreleasednoblk` (body without it). The jq released test is `released_at` string alone (G21.043.5: no
   `contract_go` still asks). **Then, steps 1-3 in place:** observe AM63.8 red, and only then add
   `released_at` to `KEPT_ON_PLAN_GO` (arbiter correction 1).
4. **Shell guard.** Cases AM18.r-AM18.r3 red first (the only `--release` cases; no shell-guard.jsonl edit). `prevent-destructive-commands.sh`
   :967-970: the exact form `python3 .claude/hooks/loop-record.py --release` → `deny` under `cwk_auto_mode`
   (reason names the blocked stop and the user's terminal), `ask` otherwise; every other non-manual form keeps
   the deny; the deny text lists `--release` as the user's lift.
5. **Launcher.** WF cases red first (`test-workflow-contracts.sh` `sup()` scratch, record JSON written by the
   test): `workflow.py` `blocked_record()` + calls before the first launch, before each saturation restart
   (before `restart_after_saturation` writes the checkpoint or bumps `restarts:`), and before the Codex fallback.
6. **Docs + contract pins.** AMC25.x red first (and the edited AMC20.3/23.2/23.3/24.3). orchestrate.md
   (Validation-mode paragraph: `--mode` three states, `blocked` → stop; Phase 0 step 2 opens with `--mode`;
   step 3 excludes a blocked record from "take it back"; Blocked stop: lift = user's `--release`, `--clear`
   deletes the record and its ledger), ship.md:179-183 (4bis-PR step 2: `Decided without you` and the
   `--guarded-block` paste "in `auto` or on a released record — `--guarded-block` prints a non-empty block")
   and :186-188, github.md:70/:83/:101-102 (auto **or released**) plus one lift sentence, docs/specs/auto-mode.md:36/:64/:70
   (a restart resumes in the recorded mode, except a blocked record: it stops until the user's `--release`),
   README.md:118-121, plan.md:116, interface.md:63, review.md:260. Every one of ship.md, auto-mode.md,
   README.md, github.md says: lift = the user's `--release`; `--clear` deletes the record and its ledger.
7. **Install pin.** IN67 red first: `--release` in neither `settings.json` allow nor `install.sh` PROMPT_ALLOWS.
8. **Full suites**: every `.claude/hooks/test-*.sh` in full + `python3 addons/fastapi/hooks/test_imported_symbols.py`;
   append the out-of-scope items to `docs/work/blocked-record-lifecycle/follow-ups.md`.
9. Refactor under green suites, no case edited.

## Parallel lots (inside this track, same tree)
none — fully sequential (steps share `test-hooks.sh` / `test-workflow-contracts.sh`).

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: kit hooks shared by every installed project (loop-record.py, enforce-git-workflow.sh,
  prevent-destructive-commands.sh, workflow.py) — no other pass in flight.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| .claude/hooks/loop-record.py | Edit | `--mode` blocked, `--release`, `released_mode`, `guarded_block` |
| .claude/hooks/enforce-git-workflow.sh | Edit | `record_allow` released handling |
| .claude/hooks/prevent-destructive-commands.sh | Edit | `--release` deny in auto / ask in moi, deny text |
| workflow.py | Edit | `blocked_record` launch refusal |
| .claude/hooks/test-hooks.sh | Edit | AM60.2 edit, AM62-AM64, AM18.r, `lpreleased`/`lpreleasednoblk` |
| .claude/hooks/fixtures/_harness/git-guard.jsonl | Edit | G21.043.x |
| .claude/hooks/test-workflow-contracts.sh | Edit | WF launcher cases, AMC25.x, edited AMC needles |
| .claude/hooks/test-install.sh | Edit | IN67 |
| .claude/commands/loop/{orchestrate,ship,plan,interface,review}.md | Edit | docs |
| .claude/agents/github.md | Edit | released record blocks |
| docs/specs/auto-mode.md, README.md | Edit | docs |

## Contracts
- `python3 .claude/hooks/loop-record.py --mode` → `blocked` | `auto` | `moi` (precedence: invalid/absent → moi;
  v1 + `blocked: true` → blocked; `auto_mode` → auto; else moi).
- `python3 .claude/hooks/loop-record.py --release` → exit 0 always; on a v1 blocked record: `mode: "moi"`,
  `released_at: <ISO>`, no `blocked`/`blocked_at`, every other key unchanged; else no change.
- `--guarded-block` → the block for an auto or released record on its branch; "" otherwise.
- `record_allow`: blocked or released record → no allow; released + exact PR form + body without the
  byte-exact block → deny.
- `./workflow.sh …` on a blocked record → exit 2, stderr names `loop-record.py --release`, no claude/codex spawn.
- Every other refusal text unchanged except the shell guard's loop-record deny (names `--release`).

## Test plan (gate — validated before EXECUTE)

### Test-first — none (no TS/Python test-first layer); kit fixture cases, each observed red before its code

#### .claude/hooks/test-hooks.sh (loop-record CLI, `am_mode_cli` / `lp_*` helpers)
**Core behaviour**
- [ ] AM62 `--mode` prints `blocked` for an auto v1 record marked blocked, on its branch
- [ ] AM62.2 `--mode` prints `blocked` for the same record seen from another branch (HEAD ≠ branch)
- [ ] AM62.3 `--mode` prints `auto` for the unmarked auto record on its branch (AM12 unchanged)
- [ ] AM62.4 `--mode` prints `moi` with no record, and for a blocked record with version 2
- [ ] AM60.2 (edited) after `--block`, `--mode` prints `blocked`
- [ ] AM63 `--release` on a blocked record: mode `moi`, `released_at` set, no `blocked`/`blocked_at`, and the whole
  record with `mode`, `blocked`, `blocked_at`, `released_at` removed (`jq -S 'del(.mode, .blocked, .blocked_at,
  .released_at)'`) identical before and after
- [ ] AM63.2 (amended, review 1 R1) after `--release`, the row-backed `.claude/.tdd-unfrozen` line stays and the
  verdict-only line is commented out
- [ ] AM63.3 after `--release`, `--mode` prints `moi`
**Business rules**
- [ ] AM64 `--guarded-block` on a released record on its branch prints the block with its ledger rows (fixture
  with one guarded entry: the line `- \`vite.config.ts\` before … (ledger, Write)` present)
- [ ] AM64.2 `--guarded-block` on a moi plan-go record (no released_at) prints ""
- [ ] AM63.4 `--release` on an unblocked auto record: record byte-identical
- [ ] AM63.5 `--release` with no record: exit 0, no file created
- [ ] AM63.6 `--clear` on a released record deletes it (AC7)
**Edge cases**
- [ ] AM63.7 `--release` twice: second run is a no-op (released_at unchanged)
- [ ] AM63.8 (run at the end of step 3, red with steps 1-3 in place) release, then a same-pass plan go (`post_plan_go` hook input): `released_at` kept, `--guarded-block`
  non-empty, `--mode` `moi`; and on that rebuilt record `git push -u origin feat/s1` asks and the exact
  `gh pr create` asks (deny without the block) — observed red before the `KEPT_ON_PLAN_GO` change
- [ ] AM63.9 source pin: `release_record` writes only inside `with locked(` and through `write_record(`
- [ ] AM63.6b (guard, green from the start) `--clear` on a blocked record deletes it; `--mode` then prints `moi`
- [ ] AM18.r the agent's `python3 .claude/hooks/loop-record.py --release` under an auto record → deny, reason names
  the user's terminal
- [ ] AM18.r1 same command under an auto record marked blocked, on its branch → deny
- [ ] AM18.r2 same command with no record (moi) → ask
- [ ] AM18.r3 `python3 .claude/hooks/loop-record.py --release; git push` → deny (not the exact form)

#### .claude/hooks/fixtures/_harness/git-guard.jsonl (setups `lpreleased`, `lpreleasednoblk`)
- [ ] G21.043 released record + `git push -u origin feat/s1` → ask "pushes to a remote"
- [ ] G21.043.2 released record + exact `gh pr create` with a body holding the byte-exact block → ask "acts on a pull request"
- [ ] G21.043.3 released record + exact `gh pr create` with a body missing the block → deny (guarded block)
- [ ] G21.043.4 (guard) G21.001/G21.002 (plain plan-go record) still allow
- [ ] G21.043.5 v1 record on its branch, mode `moi`, `released_at`, no `contract_go` + `git push -u origin feat/s1`
  → ask (allows today)
(`lpreleased`/`lpreleasednoblk` records carry mode `moi`, a `contract_go` object, `released_at`, one `guarded`
entry; the block in `lpreleased`'s body is computed at setup by `--guarded-block`.)

#### .claude/hooks/test-workflow-contracts.sh (launcher, `sup()` scratch)
- [ ] WF-B1 a scratch `.claude/.loop-record.json` with `"version":1,"blocked":true` → `workflow.py` exits 2, stderr
  holds `loop-record.py --release`, the fake claude never ran (its marker file absent)
- [ ] WF-B2 no record → the fake claude runs (existing behaviour)
- [ ] WF-B3 unreadable/invalid JSON record → the fake claude runs
- [ ] WF-B4 a record marked blocked between a saturation stop and the restart → no restart, exit 2, handoff
  `restarts:` unchanged
- [ ] WF-B5 the fake claude marks the record blocked and prints the usage limit, with a fresh `codex_safe: yes`
  handoff → exit 2, stderr names `loop-record.py --release`, no `codex-calls` file
(WF-B2, WF-B3 are guards, green from the start.)

#### .claude/hooks/test-workflow-contracts.sh (contract pins)
(`p0s2` = `section "$ORCH" '2. Parse the optional profile' '3. **FEATURE READY'`.)
- [ ] AMC25 `p0s2` holds `loop-record.py --mode` before `branch on \`phase:\`` (in_order)
- [ ] AMC25.2 `p0s2` holds `` `blocked` → stop before any phase `` (absent today)
- [ ] AMC25.3 the blocked-stop section holds `loop-record.py --release` and `deletes the record and its ledger`
- [ ] AMC25.4 orchestrate step 3 excludes a blocked record from `take it back`
- [ ] AMC25.5 ship.md, auto-mode.md, README.md, github.md each hold `loop-record.py --release` and
  `deletes the record and its ledger`
- [ ] AMC25.5b lacks, from each file's current wording: ship.md `only the user's \`--clear\` lifts it`;
  auto-mode.md `only the user's \`loop-record.py --clear\` lifts it`; README.md
  `` `python3 .claude/hooks/loop-record.py --clear`, then the pass resumes in `moi` ``; orchestrate.md :47
  ``tells the user to run `python3 .claude/hooks/loop-record.py --clear` `` and :85-86
  ``only the user's `loop-record.py --clear` lifts it`` (arbiter correction 2)
- [ ] AMC25.6-25.8 plan.md, interface.md, review.md hold `` `blocked` → stop ``
- [ ] AMC25.9 github.md holds `auto mode or a released record` for Decided without you and Guarded files touched
- [ ] AMC25.10 ship.md 4bis-PR section (`pk_pr`) holds `in \`auto\` or on a released record`
- [ ] AMC25.11 auto-mode.md holds `except a blocked record` next to `a restart resumes in the recorded mode`
  (both :64 and :70 lines; lacks the unqualified sentence)
- [ ] AMC20.3, AMC23.2, AMC23.3, AMC24.3 (edited) pin `--release` instead of `--clear` as the lift
- [ ] AMC2.inv unchanged (the blocked section never quotes the full `--clear` command)

#### .claude/hooks/test-install.sh
- [ ] IN67 no `loop-record.py --release` in `.claude/settings.json` allow nor in `install.sh` PROMPT_ALLOWS; HP_WANT stays 35

## Vigilance (carried from research)
- EXECUTE in auto: the first kit-code write is denied (V8) → blocked stop: handoff `blocked:`, `--block`, never `--clear`.
- `--mode` must print `blocked` whatever the branch; the launcher reads the JSON, never `--mode`.
- `--release` stays off `LOOP_RECORD_CLEAR_RE`, settings.json, install.sh and HP_WANT; deny in auto, ask in moi.
- `--release` branch in `main()` sits before the stdin fall-through.
- `record_allow` excludes `released_at` and runs `guarded_block_check` for a released PR before falling to the ask.
- `guarded_block` emits for released; `guarded_op`/`subagent_stop` stay auto-only.
- (amended, review 1 R1) `--release` comments out the verdict-only `.tdd-unfrozen` lines (`comment_row_lines`
  with the verdicts that are not rows); row-backed lines stay.
- Launcher check before every launch (first, restart, Codex fallback); tolerant of no git / no record / bad JSON.
- A contract go on a released record still wipes the ledger (OUT, follow-up).
- AMC2.inv: the blocked section never quotes `python3 .claude/hooks/loop-record.py --clear`.
- Greps holding `loop-record.py` after `|`/`;` are denied by the shell guard.
- (critic) Guards green from the start are labelled `(guard)`: IN67, G21.043.4, WF-B2/B3, AM62.4, AM63.4/.5/.6/.6b,
  AM18.r1, AM18.r3, AM64.2, AMC2.inv; never reported as a RED (AM18.r1 still catches a guard keyed on `--mode`).
- (critic pass 2) AMC25.11's lacks needle keeps the period: `resumes in the recorded mode.`; AMC25.5b also lacks
  auto-mode.md:64 `until the user's \`loop-record.py --clear\` lifts it`; ship.md:190-191 ("1 and 3 run
  without a prompt") gains the released-record exception; WF-B1/B4/B5 run workflow.py in their own invocation
  capturing stderr and exit code (`sup()` drops stderr); AMC25.4 pins `` unless the tree's record is blocked ``
  inside step 3 (absent today).
- (critic Q4) `--mode` printing `blocked` on any branch goes beyond Scope 1's "(auto otherwise valid)": PR deviation.
- (critic Q2/Q3) "released" is one predicate in jq and Python; the released PR byte check runs after the
  auto preconditions, never before.
- (verifier) A plan go on a still-blocked record keeps mode `auto` and drops `blocked` (AM60.3): only the docs
  stop on `blocked`; no hook does (follow-up).
- (critic Q8) the restart check runs before the checkpoint write and the `restarts:` bump.

## Acceptance criteria (carried from the entry artifact)
- [ ] AC1: with a v1 auto record marked `blocked` on its branch, `loop-record.py --mode` prints `blocked`;
  unmarked it prints `auto`; no record prints `moi`.
- [ ] AC2: `./workflow.sh` on a tree whose record is blocked exits non-zero without starting a session
  and prints `loop-record.py --release`.
- [ ] AC3: `orchestrate.md` Phase 0 step 2 runs `--mode` before branching on `phase:` and stops on
  `blocked`; no kit doc still says a blocked record resumes in auto or that a gate go lifts it
  (contract greps).
- [ ] AC4: `loop-record.py --release` on a blocked record leaves a record with mode `moi`, no `blocked`,
  a `released_at`, and the same `verdicts`, `guarded` and `rows`; `.tdd-unfrozen` lines unchanged.
  (amended in `## Gate`, review 1 R1: verdict-only `.tdd-unfrozen` lines are commented out, row-backed lines kept.)
- [ ] AC5: the agent's `python3 .claude/hooks/loop-record.py --release` is denied in auto (shell guard)
  and has no allow entry in `settings.json` / `install.sh`.
- [ ] AC6: on a released record, `git push -u origin <branch>` and the exact-form `gh pr create` ask;
  `--guarded-block` prints the block with the ledger rows; a `gh pr create` body missing that block is
  refused as in auto.
- [ ] AC7: `--clear` still deletes any record, blocked or released.
- [ ] AC8: every kit suite green (`.claude/hooks/test-*.sh`, fastapi `test_imported_symbols.py`).

## Plan critic
- completeness: 88
- quality: 84
- surviving blockers: none
- pass 1: 66/78, F1-F4, F6 rewritten (route-plan-1.json); pass 2: F2, F3, F4, F6 fixed, F1 arbitrated
  (route-plan-2.json)

## Gate
- 2026-11-23 arbiter go (auto; round 1 corrections 1-5 applied: AM63.8 + KEPT change at the end of step 3,
  orchestrate.md :47/:85-86 lacks, no shell-guard.jsonl edit, AM63 full-record compare, G21.043.5; round 2 go)
- Contract: as written (Contract gate, 2026-11-23)
- amended 2026-11-23 (user's review-1 decision on R1, moi): Scope 4 / AC4 "`.tdd-unfrozen` lines kept /
  unchanged" → `--release` comments out the `.tdd-unfrozen` lines backed only by frozen-case verdicts (the
  `comment_row_lines` rule, verdicts whose (path, id) is not a plan row); row-backed lines stay; `verdicts`,
  `guarded`, `rows` stay in the record. Reason: a verdict-only line exempts the whole test file in moi (R1).
  Listed first in the PR as the contract amendment.
- Frozen cases to amend: none
- Open questions → answers 1-9 as printed under `## Proposed answers to research's open questions`; F1 as printed
- Note (round 2): the orchestrate.md :85-86 lacks needle spans two lines; search a line-joined copy
  (`tr -s ' \n' ' '`, as `cd_adapt_flat` does) or the part on :86 alone.

### Plan critic, open
- F1 (interpretation): AM63.8 checked released_at, `--guarded-block` and `--mode` on the record a same-pass plan go
  rebuilds, but not that push and PR still ask on it. Proposed answer (already written into AM63.8): AM63.8 also
  runs `record_allow` on that rebuilt record — `git push -u origin feat/s1` asks, the exact `gh pr create` asks
  (deny without the block) — observed red before the `KEPT_ON_PLAN_GO` change.
