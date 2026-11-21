# Research: Auto mode   (entry: docs/specs/auto-mode.md)
Token profile: critical

Probes 2026-11-20: 3 `explorer` (record/freeze, git/PR/guards, prompts) + 1 `doc-researcher`
(SubagentStop). Key claims re-checked on the main thread (marked ✓). Base `audit/slim` @ 8313de2.

## Pattern to follow
- The shipped `loop-to-pr` pass is the direct analogue: same record, same hooks, same fixture style.
  Spec `docs/specs/loop-to-pr.md`, plan `docs/work/loop-to-pr/plan.md` (cases LP1-LP71, G21.001-042).
- Record hook `.claude/hooks/loop-record.py` (370 l., stdlib): PreToolUse `AskUserQuestion`
  (`pre_ask` :90-106, denies a pre-filled `Plan gate`), PostToolUse `AskUserQuestion` (`post_ask`),
  PostToolUse `Bash` (`post_bash` :265-288, drops the record on the pass's own PR URL). Wiring
  `.claude/settings.json:175-226`.
- Record `<tree>/.claude/.loop-record.json`, fields built at `loop-record.py:255-261` ✓: version 1, slug,
  plan, branch, base, base_sha, repo, default_branch, barrier, base_ok, rows `{path,id,sha256}`, at,
  tool_use_id. Gate detection: header `Plan gate` exact (:22, :229), first line
  `Plan go — docs/work/<slug>/plan.md` (:23), answer exactly `go` (:236-240), rows after
  `Frozen cases to amend:` (:24, :242), row regex `^(\S+) \| ([UMRB][0-9]+) \| ([0-9a-f]{64})$` (:25).
  Subagent filter: `agent_id`/`agent_type` present → ignored (`:221-222`), in `post_ask` only.
- New read-only `inherit` agent template: `reviewer.md:1-5` / `plan-critic.md:1-5` / `verifier.md:1-5`
  (`tools: Read, Grep, Glob, Bash`, `model: inherit`, **no** `effort:` line).

## Wiring points
- `.claude/settings.json:239-249` SubagentStop: one entry, `eslint-batch.sh`, no matcher. A verdict hook
  is a second entry (matcher on the new agent's name).
- `.claude/hooks/protect-files.sh:379-385`: `.tdd-unfrozen` record-backed allow
  (`unfrozen_removal_only` :241-282 or `unfrozen_record_rows` :290-377), else the guarded ask.
  Kit-code deny only when installed (`:207-234`, `cwk_installed` `hook-guarded.sh:131-137`).
- `.claude/hooks/hook-guarded.sh`: `CWK_GUARDED` :20-42 (ask), `CWK_GUARD_DENIED` :165-169
  (`.tdd-red/*`, `.loop-record.json`, `.git/*`), `CWK_KIT_CODE` :47-60, app roots `cwk_app_roots` +
  `CWK_APP_ROOT_PATTERNS` (config key is `app_roots`, not `APP_ROOTS`).
- `.claude/hooks/prevent-destructive-commands.sh`: shell writes to the record denied (:744-752,
  :827-829, :911-925; `--clear` exact allowed :921); kit-code shell writes :607-616.
- `.claude/hooks/enforce-git-workflow.sh` `record_allow` :2062-2115 ✓: the PR allow is at :2094 after the
  body-file existence check :2092-2093 — the slot for the `Guarded files touched` hash check. `gh_scan`
  :1931 collects `--body-file` (:1956-1957); body read bounded `head -c 1048576` (:1991), checked today
  only for attribution (:1980-1995). No `git fetch`/`git diff` in the hook; only network call is
  `timeout -k 1 3 git ls-remote` (:2106).
- `.claude/hooks/tdd-freeze-tests.sh` `freeze_rows` :152-355: row digest = sha256 of the case **title**
  (:347 ✓), helper `.claude/scripts/case-hash.sh`.
- Commands (user stops to route in `auto`): `spec.md:13-23` (frame, where `Validation : moi | auto` goes),
  `:65-71` ("nothing proceeds on silence"); `orchestrate.md:196-198` (Phase 2 gate), `:204-211` (Phase 3
  gate, light contract), `:289-298` (EXECUTE unfreeze queue); `interface.md:59` (front-runner),
  `:40-45` (critical: 3 designers + judge), `:63-67` (canvas render), `:68-87` (gate + contract question),
  `:105-106`; `plan.md:105` (`arbitrate`), `:115-130` (Plan gate, rows), `:138-163` (open questions),
  `:152-158` (contract question), `:173-177` (`Plan critic, open`), `:203-204`; `review.md:243`
  (`fail` → attempts), `:253-255` ("don't apply fixes without agreement"); `ship.md:120-122` (Critical
  stop), `:135-142` (deploy ask), `:170-184` (4bis-PR), `:197-205` (4bis-local go).
- PR body: `.claude/agents/github.md:67-86` (summary :68, Where to look :70, Uncertain :72, commits
  :74-75, Screenshots :77, Frozen cases :79, Open questions :81, Review :83, Gates :85, drop-empty :94);
  `ship.md:129-132`, `:176-180`.
- `CLAUDE.md:106-107` ✓ "`/loop:interface` and `/loop:plan` fix **what is built** and never proceed on
  silence" (wrapped over two lines — a single-line grep misses it); `CLAUDE.md:112` "(13)".

## Reusable
- `loop-record.py`: atomic `write_record` (:201-216), `toplevel`, `branch_and_base`, `server_facts`,
  `drop_record`/`comment_row_lines` (:294-328), `--clear`. Extend, do not fork.
- `case-hash.sh` (title digest), `unfrozen_record_rows` (path/id matching), `cwk_real_file`/`cwk_real_rel`,
  `kit-attempts.py`, `kit-gate-route.py` (`arbitrate` route for `interpretation`, :324-330).
- Test helpers `test-hooks.sh`: `lp_git_setup` :4477-4531, `lp_repo` :4560, `lp_ask` :4581-4598,
  `lp_bash` :4599, `lp_run` :4607, `lp_verdict` :4643, `lp_unfrozen_repo` :4824-4843, `lp_freeze*`
  :4937-4955. Contract helpers `test-workflow-contracts.sh:1330-1335` (`pk`, `has`, `lacks`, `in_order`).

## Blast radius
- `write_record` replaces the whole file (✓ :201-216, :262): a mode / contract-go / ledger written
  elsewhere is erased by the next Plan go unless merged.
- `drop_record` on `--clear` and on the pass's PR URL (:287-288) erases everything: the
  `Guarded files touched` block and verdict rows must be read before the drop.
- `protect-files.sh:345-375` checks (path, id) only, never sha256 (✓ no `sha256` in the file). The ledger
  requirement (spec V7: row = path, id, sha256, verdict) has no hook today.
- `tdd-freeze-tests.sh:355`: an id listed in `.tdd-unfrozen` with no row passes with no hash.
- Freeze path matching is substring (`tdd-freeze-tests.sh:197`, `:96-101`).
- `test-workflow-contracts.sh:1361` (PK32) `in_order` Screenshots < Frozen cases < Open questions <
  Review < Gates: new PR headings must be added there. `:63` pins 13 **loop commands** (no new loop
  command). No test asserts the agent count; `kit-doctor.py:734-836` (`check_agent_models`/`efforts`)
  requires the new agent in the `inherit` row's last cell and no `effort:` line; `:1197-1222` resolves
  "`name` agent" references.
- Budgets: `11-token-budget.md` 42/42 (header budget 42, `kit-doctor.py:1388-1415`); core floor
  517/520 (`test-rules-floor.sh:4-5,31-41`); `CLAUDE.md` 139/140.
- Docs stating 13 agents: `CLAUDE.md:112`, `README.md:3`, `README.md:141`. `docs/Claude_Workflows.md:718-731`
  agent table is stale (no plan-critic/implementer/doc-researcher), untested.
- V8 lists vs today: `.claude/settings*.json`, `.github/workflows/*` are **asked** (not denied);
  `.github/actions/*`, `.github/CODEOWNERS`, `lefthook.yml`, `.npmrc`, `pnpm-workspace.yaml`, vitest setup
  files are **not guarded** at all. Shell writes to guarded paths are not covered by the Write|Edit
  hooks; only `prevent-destructive-commands.sh` covers the record and `.tdd-red`.

## Live DB state
n/a (kit tooling).

## External surface
- SubagentStop input `[fetched 2026-11-20, docs/research-cache/claude-code-hook-input.md §7]`:
  `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, plus
  common fields. Matcher filters on `agent_type` (frontmatter `name`). Fires also for internal agents
  (empty `agent_type`; a named matcher does not match them). Exit 0 / no `decision` = record only.
- **Caveat, Claude Code ≥ 2.1.271** (installed: 2.1.329 ✓): a subagent with the `SubagentHandback` tool
  delivers its report through it; `last_assistant_message` then holds only closing text. The report is
  `tool_input.message` of a `PostToolUse` matched on `SubagentHandback`. Which agents run with it:
  not found `[fetched]`.
- Ordering SubagentStop vs the parent's next tool call: not documented `[fetched]`. Firing on background
  agents and on SendMessage resumes: not documented (unofficial issue snippets only).
- PostToolUse matcher `Agent` `[fetched]`: `tool_input.subagent_type`; foreground `tool_response`
  `{status:"completed", agentId, content:[{type:"text",text}], …}`; background → `async_launched`, no text.
  A sync PostToolUse runs before the result is recorded (§5).
- `agent_type` spoofing: not documented; it comes from the agent definition's name (inference). Whoever
  writes `.claude/agents/` controls it; agent files are kit prompts (`hook-guarded.sh:65-70`).
- Codex: `codex-cli 0.154.0` present; routing sends execute-green / review-fixes to Codex
  (`.claude/workflow-routing.yml`).

## Traps (points of vigilance for the review)
- Record merges: every new field (mode, contract go, ledgers) must survive a later Plan go and be read
  before `drop_record`; a test proves a second Plan go keeps `mode`.
- Hash domain: plan-gate rows hash the case **title**; the spec's ledger says "the new case line". One
  domain, the existing one, or the freeze hook and the ledger never agree.
- The verdict hook must read the verdict from where 2.1.329 actually puts it (`SubagentHandback`
  vs `last_assistant_message`) and must ignore every agent but the dedicated one (matcher + in-script
  check), the main thread, and a resumed agent's second verdict on the same case (`refuse` final).
- The record must stay unwritable by agents through every channel (Write/Edit/shell), including the new
  ledger fields; a hook-only write path, as `.loop-record.json` today.
- `auto` denies (`settings*.json`, workflows, actions, CODEOWNERS, kit code, project config) must not
  change `moi` (asks stay asks); the new guarded paths (`lefthook.yml`, `.npmrc`, `pnpm-workspace.yaml`,
  vitest setup, `.github/actions/*`, CODEOWNERS) change `moi` too — decide explicitly.
- `Guarded files touched` needs `origin/<base>`: a `git fetch` inside a PreToolUse hook is a new network
  side effect; bound it like `ls-remote` (:2106) and fail closed (deny) on a fetch failure.
- The PR-body hash check runs only on the exact `pr_form`; any other `gh pr create` already asks — keep
  it that way, never a silent allow.
- Rule budgets have zero headroom (11-token-budget 42/42, core 517/520, CLAUDE.md 139/140): the agent
  name goes into the existing `inherit` row; the CLAUDE.md "silence" scoping must not add a line.
- `CLAUDE.md:106-107` wraps the "never proceed on silence" phrase over two lines: the contract grep must
  join lines or target one line.
- PK32 order lock and the 13-loop-command count: new PR headings in `in_order`, no new loop command.
- The blocked stop must leave no push and no PR: the record cleared, so `record_allow` can no longer
  grant either.

## Open questions
1. **Where does the verdict text land on 2.1.329?** `last_assistant_message` (SubagentStop) or a
   `SubagentHandback` call's `tool_input.message`, and does a sync SubagentStop finish before the main
   thread's next tool call? Settled by a spike (temporary hook dumping stdin, one foreground and one
   background launch of a read-only agent), or by choosing PostToolUse `Agent` on a **foreground**
   launch, whose `tool_response.content` is documented and synchronous. Which mechanism does the plan
   use?
2. **Hash domain of a ledger row:** sha256 of the new case **title** (as plan-gate rows and
   `case-hash.sh` today) rather than the spec's "new case line"? (Proposed: title, one domain.)
3. **New guarded paths in `moi`:** `.github/actions/*`, `.github/CODEOWNERS`, `lefthook.yml`, `.npmrc`,
   `pnpm-workspace.yaml`, vitest setup files are unguarded today. Does the pass add them to `CWK_GUARDED`
   for every mode (ask in `moi`, deny/ledger in `auto`), or only act on them in `auto`?
4. **Mode record without a framing question in this repo's own flow:** the mode is "asked at the framing
   with the spec interview" (`spec.md:13-23`) — which hook-visible answer opens the record before a plan
   exists (the record today is created only by the Plan go, with a plan path that must exist,
   `loop-record.py:249`)? A separate `Validation` header captured into a record keyed by slug, merged
   later by the Plan go?
5. **Dedicated agent name and test-plan round bound** (spec's own open question).
6. **Light-fewer-gates B1/B3** are cited by the spec but no surviving file defines them (removed spec,
   `364f906`); `moi` = "the flow after loop-to-pr" is the working reading. Confirm.
