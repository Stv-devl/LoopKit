# Research: blocked-record lifecycle   (entry: docs/specs/blocked-record-lifecycle.md)
Token profile: critical

## Pattern to follow
- `mark_blocked` (`.claude/hooks/loop-record.py:632-644`): locked, atomic `write_record` (:260), no-op on an absent
  or non-v1 record. `--release` copies it.
- `--block` wiring in `main()` (:735-740), and its tests: AM60-AM60.5 (`.claude/hooks/test-hooks.sh:5976-5991`,
  :6042-6045), `lpblocked` setup in `lp_git_setup` (:4509, :4522, record JSON :4550-4560), git-guard
  G21.002b/c (`.claude/hooks/fixtures/_harness/git-guard.jsonl:599-600`).

## Wiring points
- `loop-record.py main()` :727-790: argv dispatch `--clear`, `--block`, `--mode` (:741-751, prints `auto` when
  `auto_mode`, else `moi`), `--guarded-block`; any other argv falls through to `sys.stdin.read()` (:765).
- `auto_mode` :154-165: version 1, mode auto, contract_go object, branch/base/base_sha strings, HEAD == branch;
  never reads `blocked`. `guarded_block` :682-686 returns "" when not `auto_mode`.
- `post_plan_go` :318 keeps `KEPT_ON_PLAN_GO` (:40: mode, contract_go, verdicts, guarded) → drops
  `blocked`/`released_at`, keeps mode `moi`. `post_contract_go` :353-378 rebuilds: mode auto, verdicts [], guarded [].
- `enforce-git-workflow.sh` `record_allow` :2122-2168: jq select :2140 excludes only `blocked == true`, no mode
  check (a moi plan-go record allows push/PR today); `cwk_auto_mode && guarded_block_check` :2151 (check at
  :2108-2120, denies on mismatch); `decide allow` :2152 (PR), :2167 (push).
- `hook-guarded.sh cwk_auto_mode` :590-608 (callers protect-files.sh:245, prevent-destructive-commands.sh:229,
  enforce-git-workflow.sh:2151, tdd-freeze-tests.sh:499): ignores `blocked`; a released record (mode moi) is not auto.
- Shell guard `prevent-destructive-commands.sh:967-970`: `LOOP_RECORD_CLEAR_RE` allows exactly `--clear|--block|
  --mode|--guarded-block`; any other run is a hard `deny` in **both** modes (no ask, no GUARD_AUTO test).
  Fixtures `shell-guard.jsonl:904-910`.
- Allow lists: `.claude/settings.json:51-54`, `install.sh:385-386` (same four forms).
- Launcher: `workflow.sh:3-4` execs `python3 -I workflow.py`; `workflow.py main()` :410-428 (session args :345-360,
  `run_claude` :209, saturation restarts :387-419 via `restart_arguments` :371-384, Codex fallback :421-427,
  `fallback_artifact` :70-90). Stdlib only, never reads the record. Installed verbatim (`install.sh:803-804`, :901).
  Tests only in `test-workflow-contracts.sh` (`sup()` :151, fake claude in a scratch dir with no git; cases from :178).
- Docs naming the lift: `orchestrate.md:42-48`, :77-86, Phase 0 step 2 :189-203 (no `--mode` check), step 3
  :209-210, :266-267; `ship.md:186-188`; `github.md:70, :83, :101-102, :136-141`; `docs/specs/auto-mode.md:36, :64,
  :70`; `README.md:118-121`. Prompts that branch on `--mode` = `auto`: `plan.md:116`, `interface.md:63`,
  `review.md:260`, `orchestrate.md:42-44`.

## Reusable
`write_record`, `locked`, `read_record`, `now`, `guarded_block`'s body, `guarded_block_check`, the `lp_*` test
helpers and `lp_git_setup` variants, contract helpers `pk has lacks has_in lacks_in section in_order`
(`test-workflow-contracts.sh:287, :1331-1336`).

## Blast radius
- Readers of the record: hook-guarded.sh, protect-files.sh (rows in any mode via `unfrozen_record_rows` ~:404;
  verdicts only with `CWK_AUTO_VERDICTS=1`, set at :421 under auto), tdd-freeze-tests.sh (rows any mode,
  verdicts only when FREEZE_AUTO), `addons/fastapi/hooks/tdd_py_lib.py:486-510` (rows any mode, verdicts only
  in `loop_auto`), enforce-git-workflow.sh, prevent-destructive-commands.sh (:226-232, :784-790, :955-970,
  :1052-1054), `kit-doctor.py:848` (path only), github.md (owner/base from the record).
- Tests pinning today's behaviour: AM12 (:5972-5974, `--mode` auto), AM60.2 (:5986, `--mode` auto after `--block`
  → becomes `blocked`), AM19 (:6041, moi after `--clear`), AM18 manual forms (:6047-6058), G21.001/002/002b/002c,
  IN59_ALLOWS (`test-install.sh:948-957`, :1008), HP_WANT exact set of 35 (`test-workflow-contracts.sh:716-731`),
  AMC2.inv (:1521-1523), AMC20.3, AMC23.2, AMC23.3, AMC24.3 (:1526-1537, the `--clear` lift wording).

## Live DB state
n/a (no database).

## External surface
n/a.

## Traps (points of vigilance for the review)
- Auto mode denies every write to kit code (auto-mode V8): every file of this pass is kit code, so EXECUTE's
  first write ends in a blocked stop (as `auto-mode-trial-fixes` did); the agent runs `--block`, never `--clear`.
- `--mode` is branch-sensitive (`auto_mode` needs HEAD == record branch): from the main tree on `main` a blocked
  record prints `moi`. The launcher check must read the JSON itself, not call `--mode`.
- `--mode` consumers branch on the literal `auto`: `blocked` falls into their `moi` branch (asks a user who is not
  there); each needs an explicit stop, and Phase 0 step 2 must stop before branching on `phase:`.
- `--release` is a hard deny in both modes from the shell guard; it must NOT join `LOOP_RECORD_CLEAR_RE`, any
  allow list or HP_WANT (AC5); the deny text must name it.
- An unknown argv in `loop-record.py` reads stdin: `--release` needs its own branch before that.
- `record_allow` has no mode check: a released record (no `blocked`) would allow push/PR unless the :2140 select
  also excludes `released_at`.
- `guarded_block_check` runs only under `cwk_auto_mode` and denies on mismatch: for a released record it must run
  too, and `guarded_block` must emit for it, else a "" block → deny.
- `post_contract_go` wipes verdicts/guarded: a contract go on a released record would lose the ledger the spec keeps.
- `--release` must not call `comment_row_lines` (only `drop_locked` does); released rows keep granting
  `.tdd-unfrozen` writes in moi, verdicts stay inert outside auto.
- Launcher check: tolerate no git and no record (the `sup()` scratch tests); the saturation restart and Codex
  fallback paths bypass a check placed only before the first launch.
- AMC2.inv fails if the blocked-stop section quotes the full `python3 .claude/hooks/loop-record.py --clear`.
- A grep holding `loop-record.py` after `|` or `;` is denied by the shell guard (LOOP_RECORD_HEAD_RE).

## Open questions
1. `--release` from the shell guard: keep the hard deny in both modes (the user runs it in their own terminal),
   or add an ask branch in moi as the spec's Scope 4 says? Settles AC5's test and the deny text.
2. Does a user's `! python3 .claude/hooks/loop-record.py --release` (Claude Code `!` prefix) pass through the
   PreToolUse hooks? If yes, a hard deny blocks the user too; settled by a probe or Claude Code docs.
3. `--mode` on a blocked record viewed from another branch: print `blocked` whenever the tree's record is blocked
   (branch-independent), or only when HEAD == branch like `auto`?
4. Launcher: check only before the first launch, or also before each saturation restart and the Codex fallback?
   Exit code and message?
5. A contract go on a released record: refuse it, keep the ledger, or accept the wipe (out of scope)?
6. The prompts that branch on `--mode` = `auto` (plan.md:116, interface.md:63, review.md:260): add an explicit
   `blocked` stop, or rely on Phase 0 step 2 stopping first?
7. AM60.2 (`--mode` auto after `--block`) changes to `blocked`: kit test files are outside the TS/Python freeze
   matcher, so no `.tdd-unfrozen` exception; confirm.
