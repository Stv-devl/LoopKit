# Follow-ups: auto-mode trial fixes
Token profile: critical

Out of this pass, recorded so nothing is dropped silently.

1. **Python freeze twin.** `addons/fastapi/hooks/tdd_py_lib.py:596-622` (`rows_refusal`) refuses any
   change outside a case, so an `unfreeze` verdict on a frozen pytest file still cannot add
   `from x import y`. Same rule as fix 1, for Python imports (plan answer 8, critic F4).
2. **`shared/schemas/` under an app root.** `kit-audit-surface.py:81` matches the literal prefix
   `shared/schemas/`; `frontend/shared/schemas/` is not a boundary schema (plan answer 6).
3. **Native `Bash(gh …)` allow entries.** The hook no longer asks for the read-only gh forms, but no
   `permissions.allow` entry exists for them (`settings.json`, `install.sh`); `test-install.sh` pins that
   no `Bash(gh pr` allow exists. Measure whether Claude Code's own prompt still fires before adding any
   (plan answer 3).
4. **A pass that edits kit code cannot run in `auto`.** Auto mode denies every write to kit code
   (`.claude/hooks/*`, auto-mode V8), so this pass hit a blocked stop at its first EXECUTE write. The
   framing (`/loop:spec` step 1) should say so when the spec's files are kit code, before `auto` is chosen.
5. **`gh pr list --search merge` / `gh issue list --label comment` still ask** through the unanchored pr
   (`enforce-git-workflow.sh` :2171) and comment (:2179) regexes; false asks, left as they were (research Trap).
6. **Collision rule order (critic G7).** An import whose name the case body already uses is refused;
   the deny text and `arbiter.md` name the import-first order. If agents still hit it, check the collision
   against the file minus the verdict cases' spans.
- [correctness] .claude/hooks/tdd-freeze-tests.sh:228 — BRACES accepts `import {} from './setup'`, a side-effect import in disguise; decl_names drops bindings spelled type/as from the collision check; an accepted import may be inserted before the module-under-test import (minor)
- [correctness] .claude/hooks/tdd-freeze-tests.sh:239 — head_split cuts on \n only: a CRLF or BOM file has an empty head, so AC1's combined Edit is refused there (fails closed) (minor)
- [correctness] .claude/hooks/tdd-freeze-tests.sh:284 — a collision refusal falls to the generic 'outside every case' deny instead of a collision-specific text (critic G7); an import-only Edit is allowed with the stock 'amended case(s) edited' notice, and under an unfreeze verdict whose case was later refused (minor)
- [correctness] .claude/hooks/tdd-freeze-tests.sh:419 — the 'never closes' refusal is also an ambiguity the queue cannot lift, but got no blocked-stop exit in auto (only :420 did) (minor)
- [security] .claude/hooks/tdd-freeze-tests.sh:303 — p -= 1 can make p = -1 when the current head is empty and the insertion is at offset 0 (fails closed, wrong index) (minor)
- [tests] .claude/hooks/test-hooks.sh:5364 — stale comments (:5364 'the deny names --clear', :5812 'refused with the --clear text'); AM ids renumbered vs plan (plan AM58.2 written as AM58.4/AM58.5); A43 fixture differs from the plan's; '26 chemins' literal not tied to the heredoc; AMC21 does not pin the specifier class; no G18 case for gh pr view --web pass or for ( & backtick splits; the needle change to 'blocked stop (record kept)' is missing from the handoff's PR deviations (minor)
- [correctness] .claude/commands/loop/review.md:160 — the prescribed `{ git diff …; git ls-files …; } | python3 .claude/hooks/kit-pr-assets.py ui` is always denied by the kit-cwd guard (pre-existing); the new app-roots and exit-2 lines describe a command that cannot run as written; `<<< "$(…)"` passes (minor)
- [correctness] .claude/agents/arbiter.md:43 — arbiter.md (shared with the FastAPI addon) says the freeze hook accepts import additions, but the Python freeze twin (tdd_py_lib.py:607-616) still refuses them; the arbiter's hunk does not bound which imports a verdict lets in (minor)
- [correctness] docs/work/auto-mode-trial-fixes/plan.md:1 — plan Contracts says every other refusal text is unchanged except :340, but rows_verdict's deny text changed too (required by Vigilance G7); follow-ups.md untracked must be committed with the pass (minor)
- [correctness] .claude/hooks/enforce-git-workflow.sh:2184 — the -w regex needs whitespace or end after the letters: gh repo view -w=true, -cw=1, -w>/dev/null and "-w" still pass (pflag accepts them) (minor)
- [security] README.md:119 — 'you take over' next to 'auto stays … a new gate go lifts the mark' mixes who resumes; no --clear instruction to take over in moi (minor)
- [security] .claude/hooks/loop-record.py:632 — --block exits 0 silently with no tree, a non-v1 record or a lock/write failure, and marks the cwd's tree (main tree while the pass runs in a worktree); the mark is set only if the agent obeys the prompt, no blocked-stop deny sets it (minor)
- [tests] .claude/hooks/test-hooks.sh:6398 — no case needs the flatten loop's second pass (nested $(echo $(…))); AM59.2/AM59.3 share one literal needle; AM58.6/AM58.7 assert deny with no reason needle (minor)
- [security] .claude/hooks/enforce-git-workflow.sh:2201 — contorted forms still hide a gh write (threat model: careless agent, contortions are known limits): a duplicated -R/--repo before the substituted one, a space before $( inside the -R value, and a substitution as its own word between gh and the verb (gh $(… >/dev/null) repo delete --yes); base c3d557d asked on all, fix-base passed them; G18.56.7 does not pin R1 (flatten loop catches it) and the --repo, attached -R"$(", --repo=, backtick and <( alternatives of the new regex have no red case (minor)
- [correctness] .claude/hooks/test-workflow-contracts.sh:1528 — auto-mode.md has no positive pin; AMC24.3 does not pin --clear/moi; AMC23.2 'the only lift' is generic; orchestrate's 'stops before any phase, writes nothing' vs Phase 0 step 0 order unstated; plan.md:20-21 still says ./workflow.sh resumes in auto (minor)

## Next pass: blocked-record lifecycle (review R6 + R7, gate BLOCKED 3/3, user's design 2026-11-23)
- **R6, open Major.** No resume step reaches the blocked-record stop: Phase 0 step 2 branches on `phase:`,
  `--mode` prints `auto` on a blocked record, orchestrate.md:42/:209 and auto-mode.md:64/:70 lead to an auto
  resume whose push then asks with nobody there. Fix: `loop-record.py --mode` prints a third state `blocked`;
  orchestrate Phase 0 step 2 opens with `--mode` and on `blocked` stops before any phase, telling the user to
  lift it; step 3's "else take it back" excludes it.
- **R7, open Major (data-integrity).** `--clear` drops `verdicts`/`guarded`, so a cleared blocked pass's PR loses
  `Decided without you` and `Guarded files touched`. Fix: a user-only `loop-record.py --release` (off every
  allowlist: denied to the agent in auto) becomes the lift: mode → `moi`, `blocked` dropped, `released_at` set,
  `verdicts`/`guarded`/`rows` and their `.tdd-unfrozen` lines kept; `--guarded-block` and the github agent's
  `Decided without you` also emit for a released record; `record_allow` refuses a released record (push/PR ask,
  the user is there). `--clear` stays the full delete (closing check).
- Route files: `route-review-2.json`, `route-review-3.json`.
