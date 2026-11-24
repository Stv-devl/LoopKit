# Follow-ups: blocked-record lifecycle
Token profile: critical

Out of this pass, recorded so nothing is dropped silently.

1. **A contract go on a released record wipes the ledger.** `post_contract_go` (`loop-record.py:353-378`) rebuilds
   the record with `verdicts: []`, `guarded: []` (plan answer 5, Scope OUT).
2. **A plan go on a still-blocked record resumes auto.** `post_plan_go` keeps mode `auto` and drops `blocked`
   (AM60.3); only the prompts stop on `--mode` = `blocked`, no hook refuses the plan gate on a blocked record.
3. **Arbiter decision verdicts not ledgered in this pass.** The auto record showed `"verdicts": []` after two
   arbiter `kind: decision` verdicts (test-plan gate, rounds 1 and 2), although `subagent_stop`
   (`loop-record.py:509`) ledgers `decision` blocks. Either the SubagentStop hook did not fire for these agents
   (launched in the foreground / background) or it did not find the final block. `Decided without you` would
   be empty. Reproduce with a real arbiter launch and read the hook input.
4. **`guarded_block_check` deny texts say "auto mode:"** also for a released record (`enforce-git-workflow.sh`
   ~:2108-2120).
5. **`!` prefix.** Whether a user's `! python3 .claude/hooks/loop-record.py --release` passes the PreToolUse
   shell guard (which asks in moi) was not probed; the docs say "in your own terminal". In this session two
   `! … --clear` lines reached the model as plain messages and did not run.
- [correctness] .claude/commands/loop/orchestrate.md:189 — the --mode stop runs only on a handoff resume: a fresh spec/story entry, a plan.md with no handoff, or the /clear handover (next-feature-on-clear.py:101-105) starts a new pass on a blocked tree and stops at Phase 2 advising --release of the other pass (minor)
- [correctness] codex-handoff.sh:99 — the manual Codex fallback (/handoff:codex then ./codex-handoff.sh) has no blocked-record check; only the supervisor's automatic relay refuses (minor)
- [correctness] .claude/hooks/loop-record.py:785 — blocked is keyed on version 1 + blocked whatever the mode: --block on a moi plan-go record locks the launcher, and --release turns it into a released record whose push/PR ask (beyond Scope 1's 'auto otherwise valid') (minor)
- [correctness] .claude/hooks/enforce-git-workflow.sh:2149 — on a released record the byte check binds only the exact gh pr create form after barrier/base_ok; a user-approved --body/--fill PR ships without the ledger blocks; a blocked record's exact PR asks with no byte check (pre-existing) (minor)
- [correctness] workflow.py:433 — refusal message in English while every other [workflow] line is French; a refusal at the restart point leaves .claude/.restart-ready behind (minor)
- [correctness] docs/specs/loop-to-pr.md:22 — loop-to-pr.md:22 and orchestrate.md:99-100 still say a restart/relay resumes with no blocked-record carve-out (minor)
- [security] .claude/hooks/enforce-git-workflow.sh:2145 — IFS tab read collapses an empty string field, shifting columns so released comes out empty (hand-written record only); guarded_block_check deny texts say 'auto mode:' on a released record; --release from another branch asks while --mode says blocked; agent may run --clear unprompted (pre-existing) (minor)
- [tests] .claude/hooks/test-workflow-contracts.sh:1600 — AMC25.9/25.11 pin one occurrence where two were planned; AMC23.2/23.3 not edited as planned; lpreleased lacks contract_go/guarded, lpreleasednoblk absent, G21.043/.5 merged; released_mode's on-its-branch condition untested; AMC25.7/25.8 ids titled AMC25.6; WF-B cases fail silently; workflow.py version!=1 branch untested (minor)
- [tests] .claude/hooks/test-hooks.sh:6150 — the start anchor of LOOP_RECORD_RELEASE_RE (prevent-destructive-commands.sh:966) is untested: dropping the leading ^[[:space:]]* leaves --am-only 247/247 green (out of scope)
- [security] .claude/hooks/loop-record.py:678 — a mixed .tdd-unfrozen line (a row id plus a verdict-only id) stays uncommented after --release; in moi the verdict-only id lands in the listed fallback and is editable without its title hash (bounded to that id); no case covers a multi-id line (minor)
- [correctness] .claude/hooks/loop-record.py:680 — release_record catches OSError but not UnicodeDecodeError: a non-UTF-8 .tdd-unfrozen makes --release exit 0 silently with the record still blocked (fails closed, no message) (minor)
- [correctness] README.md:121 — README, orchestrate.md:85,192 and auto-mode.md:36,64 say --release keeps the ledger but not that arbiter-only unfreezes are frozen again, so the resumed moi pass meets freeze denies on cases the arbiter had unfrozen (minor)
