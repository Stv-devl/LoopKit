# Plan: Auto mode, pass 4 of 4   (entry: docs/specs/auto-mode.md · research: docs/work/auto-mode/research.md · design: n/a)
Token profile: critical
Base: 8313de2 (`audit/slim`)

## Skips
- DB: SKIP, no data. Backend: SKIP, kit tooling. INTERFACE: SKIP, no screen.
- Front test-first layers (`utils`/`mapper`/`repository`): none — every file is a hook, script,
  prompt or suite. Kit discipline as in loop-to-pr: each step writes its cases into the suite first,
  runs them red, then writes the code.
- Case ids (new, none reused): `AM` (test-hooks.sh, new block `run_auto_mode_cases`), `G22.nnn`
  (`fixtures/_harness/git-guard.jsonl`), `AMC` (test-workflow-contracts.sh), `KD27+`
  (test-kit-doctor.sh), `IN63+` (test-install.sh).
- OUT (spec): `moi`'s contract placement (unchanged), the plan-critic/review cap. Also OUT here:
  the night-arbiter protocol of this very run (`docs/work/auto-mode/night-arbiter.md`, main tree) is
  an operator rule for this pass, not a deliverable.

## Proposed answers to research's open questions (taken at `## Gate`)
1. **Verdict channel (Q1).** The spike could not run from this worktree-isolated session (worktree
   `settings.local.json` is not loaded; the main tree's is outside the isolation). Observed instead:
   every `Agent` launch here returns `async_launched` even with `run_in_background: false`, so
   PostToolUse `Agent` never carries the verdict text — **SubagentStop, as the spec says**. The hook
   reads the verdict from `last_assistant_message`; when that holds no verdict block it reads the last
   assistant text of `agent_transcript_path`, then the last `SubagentHandback` `message` in that
   transcript. No block found anywhere → **nothing recorded** (fail closed: the unfreeze keeps its ask,
   which in `auto` is a blocked stop). Residual, stated in the PR: the first real `auto` run measures
   which field carried it (AM40 proves each of the three sources on fixtures). Cases AM20-AM27, AM40.
2. **Hash domain (Q2).** sha256 of the new case **title**, as plan-gate rows and
   `.claude/scripts/case-hash.sh` today. The spec's "new case line" is read as "the case's new
   title line" — one domain, so the freeze hook checks a verdict row exactly as it checks a plan row.
   Cases AM22, AM31.
3. **New guarded paths (Q3).** `.github/actions/*`, `.github/CODEOWNERS`, `lefthook.yml`, `.npmrc`,
   `pnpm-workspace.yaml`, `vitest.setup.*`, `vitest.workspace.*`, `src/setupTests.*`, `src/test/setup.*`
   (root and each `app_roots` entry for the last five) join `CWK_GUARDED` **for every mode**: an ask in
   `moi`, like the other configs. Cases AM1-AM3.
4. **Mode record (Q4; rewritten for plan-critic Q1, Q7).** Two sources, each with one job:
   - **Before the contract go — the request.** The framing asks `Validation : moi | auto`
     (`/loop:spec` step 1, in the same call; `/loop:orchestrate` Phase 0 for a full/BMAD entry) and
     writes `Validation: <mode>` in the spec header (full/BMAD: `validation: <mode>` in the handoff
     frontmatter). This line **grants nothing**: its only effect is that the end of Phase 1 opens the
     `Contract gate` stop instead of the `moi` flow. A restart in phase `research` re-reads it.
   - **From the contract go on — the record.** The `Contract gate` is a main-thread `AskUserQuestion`
     with header exactly `Contract gate`, whose text opens
     ```
     Contract go — docs/work/<slug>/research.md
     Validation: auto
     ```
     answered exactly `as written`. The user reads `Validation: auto` in the question they answer, so
     what is recorded is what the user validated (same principle as the plan rows); the question is
     asked in the pass's own tree (worktree included), so branch/base/barrier are captured where the
     pass runs. Only `Validation: auto` opens a record (`moi` never opens this stop; a `Validation: moi`
     line records nothing). After the go, `loop-record.py --mode` is the only source: a restart in any
     later phase reads it; `moi` there (record missing, cleared by a blocked stop, mismatched) → the pass
     continues in `moi` whatever the spec line says. Cases AM10-AM19, AMC3, AMC15.
5. **Dedicated agent (spec open question).** Name `arbiter`, `.claude/agents/arbiter.md`, tools
   `Read, Grep, Glob, Bash`, `model: inherit`, no `effort:` line. Test-plan round bound: **2** (round 1
   `go` or corrections → main thread rewrites → round 2 `go`, else blocked stop). Case AMC5.
6. **light-fewer-gates B1/B3 (Q6).** No surviving file defines them; `moi` = the flow shipped by
   `loop-to-pr` (PR #12) — the spec is read that way, no contract edit.
8. **The frozen-case hunk before the verdict (plan-critic Q4).** The spec's "the hunk itself from
   `git diff`" is read as: the proposed change in **git diff format**, checked by the arbiter against the
   working tree — the change cannot be in the working tree yet, the freeze hook denies it until the
   verdict. The requester writes, per case, a fenced ```` ```diff ```` hunk against the current test file
   into `docs/work/<slug>/unfreeze-queue.md` (with case id, old line, new title, reason, as today). The
   arbiter extracts that hunk and runs `git apply --check -` on it (stdin, writes nothing): it must apply
   to the current file; it reads the current file and the hunk itself, never the requester's summary
   alone; it computes the new title's digest with `.claude/scripts/case-hash.sh`; a hunk that does not
   apply, touches another case, or removes an assertion beyond the title → `refuse`. The freeze hook then
   checks the real edit against that digest (AM37). Cases AMC5, AM37.
9. **Asks in `auto` (plan-critic C4).** A prompt nobody answers is not a stop. In `auto`, every
   **guarded** ask of `protect-files.sh` and `prevent-destructive-commands.sh` (the `CWK_GUARDED`
   fallthrough, `.tdd-unfrozen` without a matching verdict) becomes a **deny** whose reason opens
   `auto mode — blocked stop:`. The non-guarded asks stay asks (spec V8, "Always as today"):
   `orchestrate.md` forbids the main thread and its agents from issuing them in `auto` (destructive git,
   `gh pr merge`, a second push), and any deny opening `auto mode — blocked stop:` makes the main thread
   run the blocked stop. Cases AM30, AM43, AMC16.
7. **This pass ships the loop-to-pr way**: the user's Plan go writes the record; push of
   `feat/auto-mode` and `gh pr create --base audit/slim` go through `record_allow`. The hooks this pass
   adds run only from the worktree's `.claude/settings.json` in a later session; this session keeps
   running the main tree's hooks.

## Write chain (sequential)
Each step: cases into the suite → run → observed red → code → green → next step.

1. **Guard classes** (`hook-guarded.sh`, `cwk-guard-api` +1):
   - `CWK_GUARDED` gains the Q3 paths; `CWK_APP_ROOT_PATTERNS` gains `lefthook.yml`, `.npmrc`,
     `pnpm-workspace.yaml`, `vitest.setup.*`, `vitest.workspace.*`, `src/setupTests.*`, `src/test/setup.*`.
   - New `cwk_auto_class <rel>` → `denied` | `ledgered` | `none`:
     `denied` = `.claude/settings.json`, `.claude/settings.local.json`, `.github/workflows/*`,
     `.github/actions/*`, `.github/CODEOWNERS`, every `CWK_KIT_CODE` pattern (`.claude/project.json`
     and the snapshot included), and kit prompts when `cwk_installed`;
     `ledgered` = `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.*`, `eslint.config.*`,
     `vite.config.*`, `playwright.config.*`, `package.json`, `tsconfig*.json`, `lefthook.yml`, `.npmrc`,
     `pnpm-workspace.yaml`, the vitest setup files — at the root and under each `app_roots` entry.
   - New `cwk_auto_mode <tree>` (bash, jq): true only when `<tree>/.claude/.loop-record.json` is a
     regular file, `version` 1, `mode == "auto"`, `contract_go` present, and the loop-to-pr validity rule
     holds (HEAD is `branch`, or HEAD is `base` with `base_sha` an ancestor). Anything else → false.
2. **Record hook** (`loop-record.py`), all writes atomic, all Post paths exit 0 on error:
   - Every read-modify-write of the record (Contract gate, Plan go merge, verdict, guarded row, drop)
     holds an exclusive `fcntl.flock` on `<tree>/.claude/.loop-record.lock` (created by the hook, in
     `CWK_GUARD_DENIED` and `.gitignore` too) around read + `write_record`: concurrent appends from an
     async arbiter's SubagentStop and a protect-files row never lose one (plan-critic Q6).
   - `post_ask`, new header `Contract gate` (main thread only, same filter as `Plan gate`): first line
     `Contract go — docs/work/<slug>/research.md` (file exists in the tree), second line exactly
     `Validation: auto`, answer exactly `as written` → record with the plan-go
     fields (`plan` = `docs/work/<slug>/plan.md`, may not exist yet; branch/base/barrier as today),
     `rows: []`, `mode`, `contract_go: {at, tool_use_id}`, `verdicts: []`, `guarded: []`. Free text,
     another answer, a missing/other `Validation:` line → nothing written or deleted.
   - `pre_ask` also denies a pre-filled `Contract gate`.
   - Plan go: when a record exists with the same `slug` and `branch`, keep its `mode`, `contract_go`,
     `verdicts`, `guarded`; replace the rest as today. Another slug/branch → replaced whole (today).
   - New `SubagentStop` path: `hook_event_name == "SubagentStop"` and `agent_type == "arbiter"`
     exactly; tree from `cwd`; `cwk_auto_mode` equivalent in Python (same rule) else nothing. Verdict
     source per answer 1. A block is the **last** fenced block of the form
     ```
     ARBITER VERDICT
     kind: frozen-case
     path: <test path, tree-relative>
     case: <[UMRB][0-9]+>
     sha256: <64 lowercase hex of the new title>
     verdict: unfreeze | refuse
     ```
     or `kind: decision` with `question: <one line>` and `verdict: <one line>` (trace only, gates
     nothing). A frozen-case verdict is appended to `verdicts` as
     `{path, id, sha256, verdict, agent_id, at}` **only if no row exists for that (path, id)**: the first
     verdict per case is final (`refuse` cannot be overturned by a relaunch). Malformed → nothing.
     `stop_hook_active` true → nothing. Never returns a `decision` (record only).
   - `--mode` (CLI, no stdin): prints `auto` when the tree's record satisfies `cwk_auto_mode`, else
     `moi`; exit 0.
   - `--guarded-row <path> <before|-> <after|->` is **not** a CLI; guarded rows are appended through
     the stdin path `{"loop_record_op":"guarded", ...}` that only `protect-files.sh` and
     `prevent-destructive-commands.sh` send (they run it as a hook child; the shell guard keeps denying a
     model-run `loop-record.py` other than `--clear`, `--mode`, `--guarded-block`).
   - `--guarded-block` (CLI): prints the canonical `Guarded files touched` block (step 5) for the tree.
   - `--clear` and the PR-URL drop: drop everything, `verdicts`/`guarded` included; `comment_row_lines`
     now takes its (path, id) pairs from `rows` **and** every `kind: frozen-case` verdict (either
     verdict), so no verdict-backed `.tdd-unfrozen` line outlives the record as a whole-file exemption
     (plan-critic Q3). Case AM42.
3. **Write guard** (`protect-files.sh`), after the existing denies, before the `.tdd-unfrozen` allows:
   in `auto` (`cwk_auto_mode` on the edited file's tree): `denied` → deny ("auto mode: <path> is not
   written in auto mode; a pass that needs it ends in a blocked stop"); `ledgered` other than
   `.tdd-unfrozen` → append a guarded row `{path, before: sha256|absent, after: sha256|unknown, tool,
   at}` (Write: `after` = sha of `content`; Edit: `old_string`→`new_string` applied once, or all with
   `replace_all`, on the current file; not applicable → `unknown`) then allow; the row write failing →
   deny. `.tdd-unfrozen` in `auto`: allow with no prompt only when every added line's (path, ids) has an
   `unfreeze` verdict row and **no** `refuse` row, path a test file (same parse as
   `unfrozen_record_rows`); plus a guarded row. Otherwise, in `auto`, **deny** `auto mode — blocked stop:
   no unfreeze verdict for <path> <ids>` (answer 9). Any other `CWK_GUARDED` path that would ask → deny
   `auto mode — blocked stop: <path> would ask`. `moi`: no change at all.
   Shell guard (`prevent-destructive-commands.sh`): in `auto`, a resolved write target in `denied` →
   deny; `.claude/.tdd-unfrozen` → deny `auto mode — blocked stop: .tdd-unfrozen is written only
   through Edit on an unfreeze verdict` (the Write/Edit path above is its only route, plan-critic Q9);
   in `ledgered` (other than `.tdd-unfrozen`) → guarded row with `tool: "shell"`, `after: unknown`, and
   **no guarded ask** for that target (spec V8: "the same for their shell-write asks"); the command's
   other checks unchanged (a deny elsewhere in it still applies). **Every other shell-guard ask** in
   `auto` becomes a deny opening `auto mode — blocked stop:` — named: the guarded-target ask
   (`GUARD_ASK_G`, `:851-866`, `:992`), the unresolved-target ask (`GUARD_ASK_U`, `:1025`), the
   tool-option ask (`:998`) and the protected-dir asks (`GUARD_ASK_M`/`GUARD_ASK_P`) (plan-critic Q10). `LOOP_RECORD_*` allows exactly `--mode` and `--guarded-block`
   besides `--clear`.
   Known limit (Vigilance): the guarded row is written in PreToolUse; a sibling hook running in
   parallel may still deny the same write, leaving a row for a write that never landed. The block shows
   it as a ledger line whose `after` differs from the committed file — visible, never hidden.
4. **Freeze hook** (`tdd-freeze-tests.sh`, `tdd_py_lib.py`/`tdd-freeze-tests-py.py`): in `auto`, rows =
   plan rows ∪ `unfreeze` verdict rows for the path; a case whose (path, id) has a `refuse` row is
   refused (frozen deny, reason names the refusal) even if `.tdd-unfrozen` lists it; title hash checked
   exactly as plan rows. In `auto` the `listed` fallback (`:350-356`: a listed id with no row passes
   unhashed) and the whole-file exemption without rows (`:367`, `:402-403`) are **off**: an id with
   neither a plan row nor an `unfreeze` verdict is refused, whatever `.tdd-unfrozen` holds. In `moi`, no
   change (verdicts ignored, fallbacks as today).
5. **Git hook** (`enforce-git-workflow.sh`, `record_allow`, PR branch, after the body-file check
   `:2092-2093`, before `decide allow` `:2094`): when `cwk_auto_mode`:
   - **One** fetch: `timeout -k 1 8 git fetch --no-tags origin <base>`; failure → deny ("cannot compute
     Guarded files touched"). The hook then runs `python3 -I loop-record.py --guarded-block --no-fetch`
     (same code as the CLI, no second fetch). The hook's wired timeout goes 5 → 20 s (step 6), above
     the worst case: ls-remote 3 + fetch 8+1 + block computation (plan-critic Q2). Case AMC17.
   - block built from `git diff --no-renames --name-status origin/<base>...HEAD`: the lines whose path is
     `ledgered` or `denied` or an existing test file with status `M` or `D`, plus every `guarded` row (path,
     before, after) even when the path no longer differs (reverted edit); first, one line
     `GUARD FAILURE: <path> <id> changed with no ledger row` for each test file changed whose touched
     frozen case ids have no plan row and no `unfreeze` verdict (case ids read from the diff's `-`/`+`
     `it(`/`test(`/`def test_` titles). Format:
     ```
     ### Guarded files touched
     <!-- guarded-files sha256:<hex of the lines below> -->
     - GUARD FAILURE: …
     - `<status> <path>` (diff)
     - `<path>` before `<12 hex|absent>` after `<12 hex|unknown>` (ledger, <tool>)
     ```
     or `- none`.
   - The body file must contain the block byte for byte (substring) → else deny ("the PR body must
     carry the hook's Guarded files touched block: run `python3 .claude/hooks/loop-record.py
     --guarded-block`").
   `moi`: unchanged. Every other `gh pr create` form: unchanged (ask).
6. **Wiring** (`.claude/settings.json`): PreToolUse Bash `enforce-git-workflow.sh` `timeout` 5 → 20
   (`install.sh` merge carries it; IN63); SubagentStop gains `{matcher: "^arbiter$", command:
   python3 -I $CLAUDE_PROJECT_DIR/.claude/hooks/loop-record.py}` beside `eslint-batch.sh`; allows
   `Bash(python3 .claude/hooks/loop-record.py --mode)` and
   `Bash(python3 .claude/hooks/loop-record.py --guarded-block)`; `install.sh` `PROMPT_ALLOWS` gains both,
   its hook merge keeps the SubagentStop entry (IN63). `kit-doctor.py`: no new check (KD27 proves
   the arbiter row/model check passes).
7. **Contract cases first** (`test-workflow-contracts.sh`, AMC1-AMC14), run red against today's prompts.
8. **Prompts**:
   - `.claude/agents/arbiter.md` (new): read-only arbiter, never the plan's author nor the requester;
     inputs per decision; for a frozen case it reads the current test file and the queued diff hunk
     itself, runs `git apply --check -` on it, computes the digest with `case-hash.sh` (answer 8);
     one decision per launch; final message is
     the verdict block (step 2), nothing after it; may not decide a change to an acceptance criterion's
     meaning → `verdict: blocked` (kind decision) → the main thread does a blocked stop; test-plan
     check (cases vs acceptance criteria and business logic, expected values' sources, order), 2 rounds.
   - `orchestrate.md`: the V7 table verbatim; mode sources per answer 4 (Phase 0: the spec's
     `Validation:` line, or the `Validation` question asked for a full/BMAD entry, decides only whether
     Phase 1 ends on the `Contract gate`; after it, `loop-record.py --mode` alone; a restart in a phase
     after `research` reads `--mode`); after the contract go, auto requires the record's server barrier
     (`barrier: true`, else blocked stop before Phase 2); end of Phase 1 in `auto`: the `Contract gate`
     stop (Objective, Scope IN/OUT, Acceptance criteria verbatim under `Contract (validated by this go)`,
     research `Traps`, `as written` or free text → B3 amendment rules); every later gate → a fresh
     `arbiter`, plan-critic `arbitrate` included; EXECUTE unfreeze queue in `auto` → one fresh arbiter per
     case id, with the queued diff hunk (answer 8), then one `.tdd-unfrozen` Edit for the `unfreeze` ones;
     **Blocked stop** rule (causes, a deny opening `auto mode — blocked stop:`, handoff `blocked: <cause>`,
     board `BLOCKED`, local commits, no push, no PR, `loop-record.py --clear`, `./workflow.sh` resumes);
     in `auto` never issue a command that asks (answer 9); `Contract contradiction` handling;
     `:197` and `:206` "on silence" sentences kept verbatim (pinned by `test-workflow-contracts.sh:317`)
     with "in `moi`" appended.
   - `spec.md`: frame asks `Validation : moi | auto` with the other questions (no extra call), writes
     `Validation: <mode>` in the spec header (informational), step 5 line per mode; "nothing proceeds on
     silence" scoped to `moi`.
   - `interface.md`: in `auto`, step 3 front-runner (economy, 2 alternatives) or `designer` judge
     (critical), reasons in `design.md`, step 4 render and step 5 gate skipped.
   - `plan.md`: in `auto`, step 7 is the `arbiter` (test plan, open questions, `Plan critic, open`),
     2 rounds, `## Gate` records `arbiter go` (never a user go), each plan-time frozen-case amendment
     needs its own `kind: frozen-case` verdict; "Do not start EXECUTE on silence" scoped to `moi`.
   - `review.md`: in `auto`, step 5 fixes apply without asking; a route needing a user choice goes to
     the arbiter; non-convergence → blocked stop.
   - `ship.md`: in `auto`, PR body gets `Contract contradiction` first (when any) and `Guarded files
     touched` from `--guarded-block`; a red gate after its fix budget → blocked stop, no push.
   - `github.md`: body template order `Contract contradiction` (first, when any) … `Screenshots` <
     `Guarded files touched` < `Frozen cases` < `Open questions` < `Review` < `Gates`.
   - `designer.md`: judge mode also serves `auto` (no canvas).
   - `guides/review/tests.md`: in `auto`, an unfrozen case with no matching `unfreeze` verdict row, or
     whose diff does not hash to its row, is Critical; a `refuse`d case changed is Critical.
   - `11-token-budget.md:18`: `arbiter` in the `inherit` row's last cell, no new line.
   - `CLAUDE.md`: `:106-107` "never proceed on silence" → "never proceed on silence in `moi`" within the
     same two lines; `:112` `(13)` → `(14)`. No line added.
9. **Docs**: `README.md:3`, `:141` (13 → 14 subagents, auto mode one line where the loop is
   described, no new section), `docs/Claude_Workflows.md` agent table (`arbiter`, plus the three
   missing rows) and the V7 table reference.
10. **Full suites**, then **Refactor** under a green suite, no case edited.

## Parallel lots
None — fully sequential (steps 1-5 share `hook-guarded.sh`/`loop-record.py`; prompts depend on the
final texts).

## Track isolation
- Worktree: `.claude/worktrees/auto-mode` on `feat/auto-mode` (user asked).
- Shared foundations touched: kit hooks and `.claude/settings.json`, `install.sh` — no other pass runs
  beside this one until merged.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/hook-guarded.sh` | Edit | Q3 paths, `cwk_auto_class`, `cwk_auto_mode` |
| `.claude/hooks/loop-record.py` | Edit | Contract gate, merge, SubagentStop verdicts, guarded rows, `--mode`, `--guarded-block` |
| `.claude/hooks/protect-files.sh` | Edit | auto deny / ledger / verdict-backed `.tdd-unfrozen` |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | auto shell deny / ledger; two new exact CLI allows |
| `.claude/hooks/tdd-freeze-tests.sh`, `.claude/hooks/tdd_py_lib.py`, `addons/fastapi/hooks/tdd-freeze-tests-py.py` | Edit | verdict rows, refuse |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | `Guarded files touched` check |
| `.claude/settings.json`, `install.sh`, `.gitignore` | Edit | SubagentStop wiring, 2 allows, git hook timeout 20, `.loop-record.lock` ignored (repo + install ignore block + copy prune) |
| `.claude/hooks/test-hooks.sh`, `fixtures/_harness/git-guard.jsonl`, `fixtures/protect-files.sh/46-*` | Edit/Create | AM, G22 |
| `.claude/hooks/test-workflow-contracts.sh`, `test-kit-doctor.sh`, `test-install.sh` | Edit | AMC, KD27, IN63; HP_WANT 32 → 34 |
| `.claude/agents/arbiter.md` | Create | dedicated agent |
| `.claude/commands/loop/{spec,orchestrate,interface,plan,review,ship}.md`, `.claude/agents/{github,designer}.md`, `.claude/guides/review/tests.md` | Edit | V7/V8 prompts |
| `.claude/rules/11-token-budget.md`, `CLAUDE.md`, `README.md`, `docs/Claude_Workflows.md` | Edit | agent row, silence scope, counts |

(`tdd_py_lib.py`'s exact location is checked at step 4; the file the py freeze hook imports is the one edited.)

## Contracts
- Record (version 1, additive fields): `mode` (`"auto"` only — written solely by the auto Contract
  gate), `contract_go` `{at, tool_use_id}`, `verdicts`
  `[{kind: "frozen-case", path, id, sha256, verdict, agent_id, at} | {kind: "decision", question, verdict, agent_id, at}]`
  (every guard filters on `kind: "frozen-case"`), `guarded`
  `[{path, before, after, tool, at}]`. Readers treat a missing field as empty / `moi`.
- `loop-record.py --mode` → stdout `auto\n` | `moi\n`, exit 0. `--guarded-block` → the block, exit 0
  (it runs `git fetch` as the hook does; fetch failure → message on stderr, exit 1); `moi` or no record
  → prints nothing, exit 0.
- Arbiter verdict block: step 2 grammar, last block wins within one message.

## Test plan (gate — validated by the user before EXECUTE)
Main behaviour first, business rules next, edge cases last. "auto rec" = a valid record fixture with
`mode: "auto"` and `contract_go` written by the test setup (`lp_git_setup` style); "moi rec" = the same
without `mode`; "main" = no `agent_id`/`agent_type`. Pinned literal: `sha256("U2 returns err on empty
input")` = `9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5` (from loop-to-pr, hand-checked).

### Step 1 — guard classes (test-hooks.sh, block AM)
**Core behaviour**
- [ ] AM1 With no record, Write of `lefthook.yml`, `.npmrc`, `pnpm-workspace.yaml`, `.github/CODEOWNERS`,
      `.github/actions/x/action.yml`, `vitest.setup.ts` asks (guarded), as `vite.config.ts` does.
- [ ] AM2 `app_roots: ["frontend"]`: Write of `frontend/lefthook.yml` and `frontend/vitest.setup.ts` asks;
      `frontend/src/a.ts` does not.
**Business rules**
- [ ] AM3 `cwk_auto_class`: `.claude/settings.json`, `.claude/settings.local.json`,
      `.github/workflows/ci.yml`, `.github/actions/x/action.yml`, `.github/CODEOWNERS`,
      `.claude/project.json`, `.claude/hooks/x.sh` → `denied`; `vite.config.ts`, `frontend/vite.config.ts`,
      `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `package.json`, `eslint.config.js`,
      `playwright.config.ts`, `tsconfig.app.json`, `vitest.config.ts`, `lefthook.yml`, `.npmrc`,
      `pnpm-workspace.yaml`, `vitest.setup.ts`, `src/test/setup.ts` → `ledgered`; `src/a.ts` → `none`.
- [ ] AM4 `cwk_auto_mode` true on an auto rec with HEAD on `branch`; false with no record, a moi rec, an
      auto rec without `contract_go`, an auto rec for another branch, a symlinked record.

### Step 2 — record hook (test-hooks.sh, block AM; spike-shaped AskUserQuestion inputs)
**Core behaviour**
- [ ] AM10 main, header `Contract gate`, lines `Contract go — docs/work/s1/research.md` (exists) and
      `Validation: auto`, answer `as written`, worktree made as the kit makes it → record slug `s1`,
      branch `feat/s1`, base, `mode: "auto"`, `contract_go.tool_use_id`, `rows: []`, `verdicts: []`.
- [ ] AM11 Same with `Validation: moi` → no record (only `auto` opens one); `--mode` prints `moi`.
- [ ] AM12 `loop-record.py --mode` prints `auto` for AM10's tree, `moi` with no record, `moi` when HEAD
      is another branch.
**Business rules**
- [ ] AM13 The AM10 input with `agent_id`, or with `agent_type`: no record (a subagent records nothing).
- [ ] AM14 Answer `amend`, a free text, `As written`: no record; an existing record untouched.
- [ ] AM15 Missing `Validation:` line, `Validation: Auto`, a research path that does not exist: no record.
- [ ] AM16 A later valid `Plan gate` go for the same slug and branch keeps `mode`, `contract_go`,
      `verdicts`, `guarded`, and sets the new rows; for another slug it replaces the record whole.
- [ ] AM17 PreToolUse `Contract gate` carrying `answers` → deny.
- [ ] AM18 Agent Write/Edit of `.claude/.loop-record.json` stays denied (LP1 still green) and
      `python3 .claude/hooks/loop-record.py --mode` / `--guarded-block` are not denied by the shell guard,
      while `python3 .claude/hooks/loop-record.py < x.json` still is.
**Edge cases**
- [ ] AM19 `--clear` after AM10 removes the record; `--mode` then prints `moi` (a blocked stop leaves `moi`).

### Step 2b — verdict ledger (test-hooks.sh, block AM; SubagentStop inputs)
**Core behaviour**
- [ ] AM20 auto rec; SubagentStop `agent_type: "arbiter"`, `last_assistant_message` ending with a
      frozen-case block (`src/a/x.utils.test.ts`, `U2`, the pinned digest, `unfreeze`) → one verdict row
      with those values and the input's `agent_id`.
- [ ] AM21 Same with `verdict: refuse` → one row `refuse`.
**Business rules**
- [ ] AM22 A second block for the same (path, U2), any verdict, from another `agent_id` → rows unchanged
      (first verdict final).
- [ ] AM23 `agent_type: "reviewer"`, `"implementer"`, empty, or absent → nothing recorded.
- [ ] AM24 moi rec, or no record → nothing recorded (no record created).
- [ ] AM25 Malformed block (63-hex digest, id `X2`, verdict `maybe`, missing path) → nothing.
- [ ] AM26 `stop_hook_active: true` → nothing; the hook's stdout carries no `decision` in every AM20-AM27 run.
**Edge cases**
- [ ] AM27 `kind: decision` block → a trace entry in `verdicts` with `kind: "decision"`, which no guard
      reads (AM30 with only that entry is still denied as "no unfreeze verdict").
- [ ] AM40 The block found only in the transcript's last assistant text, and only in a `SubagentHandback`
      `message` of the transcript (fixture JSONL), is recorded; found nowhere → nothing.

### Step 3 — write guard (test-hooks.sh, block AM; protect-files.sh + prevent-destructive-commands.sh)
**Core behaviour**
- [ ] AM28 auto rec: Write `.claude/settings.json`, Write `.claude/settings.local.json`, Edit
      `.github/workflows/x.yml`, Write `.github/actions/x/action.yml`, Write `.github/CODEOWNERS`,
      Edit `.claude/project.json` → deny with the auto-mode reason.
- [ ] AM29 auto rec: Write `vite.config.ts` and `frontend/vite.config.ts` (`app_roots: ["frontend"]`) →
      pass, and one guarded row each with `before` = sha of the old file (or `absent`) and `after` = sha
      of the written content.
- [ ] AM30 auto rec + `unfreeze` verdict (src/a/x.utils.test.ts, U2): Edit adding
      `src/a/x.utils.test.ts  # U2: reason` to `.tdd-unfrozen` → pass + guarded row; without the verdict
      → deny, reason opening `auto mode — blocked stop:` (moi: ask, AM33).
**Business rules**
- [ ] AM31 auto rec + `refuse` verdict for U2 (and an `unfreeze` one for U3 on the same path): the line
      `src/a/x.utils.test.ts  # U2, U3: r` → deny `auto mode — blocked stop:`.
- [ ] AM32 auto rec + `unfreeze` verdict for U2: a line naming an implementation path
      (`src/a/x.utils.ts  # U2: r`), or the id on another test path → deny `auto mode — blocked stop:`.
- [ ] AM33 moi rec: AM28's writes ask (not deny), AM29's write asks with no guarded row, AM30's line
      without a plan row asks.
- [ ] AM34 Edit of `vite.config.ts` in auto: `after` = sha of the file with the replacement applied;
      a non-matching `old_string` → `after: "unknown"`, still pass.
- [ ] AM35 Shell, auto rec: `cp /tmp/a .claude/settings.json` → deny; `cp /tmp/a package.json` → no
      decision (no ask) and a guarded row `tool: "shell"`, `after: "unknown"`; moi rec: the same `cp` asks,
      no row.
- [ ] AM43 auto rec, `app_roots: ["frontend"]`: a guarded match outside both auto classes — a Write whose
      path is the app-root folder itself (`frontend`, guarded by `cwk_is_guarded`) → deny `auto mode —
      blocked stop: frontend would ask`; moi rec → ask.
**Edge cases**
- [ ] AM36 The guarded-row write failing (record made read-only after the auto check) → deny, never a
      silent allow.
- [ ] AM42 auto rec with an `unfreeze` verdict (U2) and a `refuse` verdict (U3) on `src/a/x.utils.test.ts`,
      `.tdd-unfrozen` holding `src/a/x.utils.test.ts  # U2, U3: r`: `loop-record.py --clear` leaves that line
      commented out (`# ` prefix) and the record gone; same after the PR-URL drop (PostToolUse Bash).
- [ ] AM45 auto rec, no verdict: `printf 'src/a/x.utils.test.ts  # U2: r\n' >> .claude/.tdd-unfrozen` →
      deny opening `auto mode — blocked stop:`, no guarded row; moi rec → ask (today).
- [ ] AM46 auto rec, `app_roots: ["frontend"]`: `cp /tmp/a frontend` (guarded target, `GUARD_ASK_G`),
      `cp /tmp/a "$X"` (unresolved target, `GUARD_ASK_U`), `rm -r src/a` (protected dir, `GUARD_ASK_P`),
      `mv src/a.ts /tmp/b` (protected dir, `GUARD_ASK_M`), `npx tsc --init` (tool option) → each a deny
      opening `auto mode — blocked stop:`; moi rec → each asks as today (the last three verified asking on
      the current hook, 2026-11-20).
- [ ] AM44 Two concurrent appends (a SubagentStop verdict and a protect-files guarded row, started together
      20 times) → every run ends with both rows present.

### Step 4 — freeze hook (fixtures/tdd-freeze-tests.sh + test-hooks.sh lp_freeze helpers, block AM)
**Core behaviour**
- [ ] AM37 auto rec, `unfreeze` verdict U2 with the pinned digest, `.tdd-unfrozen` lists U2: an Edit
      changing U2's title to `U2 returns err on empty input` passes; to any other title → deny.
**Business rules**
- [ ] AM38 auto rec, `refuse` verdict U2, `.tdd-unfrozen` lists U2 (written before): any Edit of U2 →
      deny, reason names the refusal.
- [ ] AM39 moi rec carrying a verdicts array: verdicts ignored (behaviour = LP rows-mode cases).
- [ ] AM47 auto rec, no plan row and no verdict for U2, `.tdd-unfrozen` (fixture-written) listing
      `src/a/x.utils.test.ts  # U2: r`, and separately a whole-file line `src/a/x.utils.test.ts reason`:
      an Edit of U2 → deny in both; moi rec → pass in both (today's fallbacks).
- [ ] AM41 Python service test (`tests/services/test_b.py`), auto rec, `unfreeze` verdict B2 with
      `sha256("test_b2_returns_err_on_empty")` = `e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b`
      → the renamed `def test_b2_returns_err_on_empty` passes; `refuse` → deny.

### Step 5 — git hook (fixtures/_harness/git-guard.jsonl, block G22; tmp repo + bare origin, setup `am`)
**Core behaviour**
- [ ] G22.001 auto rec, barrier, diff touching `vite.config.ts` (ledger row before/after), body file holding
      the exact block → allow.
- [ ] G22.002 Same, body without the block → deny naming `--guarded-block`.
- [ ] G22.003 Same, body with the block altered by one character (an `after` hash) → deny.
**Business rules**
- [ ] G22.004 A guarded edit reverted before the commit (row present, path absent from the diff): the block
      lists it from the ledger; the body without that line → deny.
- [ ] G22.005 A test file changed whose touched case U2 has neither plan row nor `unfreeze` verdict: the block
      opens with `GUARD FAILURE: src/a/x.utils.test.ts U2 …`; the body carrying it → allow (the PR shows it).
- [ ] G22.006 moi rec, body without any block → allow (loop-to-pr G21 behaviour unchanged).
- [ ] G22.007 `git fetch` failing (origin removed after the record) → deny.
**Edge cases**
- [ ] G22.008 auto rec, no guarded path touched and no ledger row: block `- none`; body carrying it → allow.
- [ ] G22.009 `--guarded-block` CLI output equals the block the hook computes (same tree, byte for byte).

### kit-doctor / install (test-kit-doctor.sh KD, test-install.sh IN)
- [ ] KD27 `arbiter.md` with `model: inherit`, no `effort:`, named in the `inherit` row → no agent-model /
      agent-effort / agent-reference finding; with `effort: high` → finding.
- [ ] IN63 Install (core mode) keeps the `^arbiter$` SubagentStop entry, the `eslint-batch.sh` one, and the
      two new allows; `arbiter.md` lands in the manifest.

### Contracts (test-workflow-contracts.sh, block AMC — written and run red before step 8)
- [ ] AMC1 `orchestrate.md` carries the V7 table header `| Gate after the contract | \`moi\` | \`auto\` |` and
      its seven rows' first cells.
- [ ] AMC2 `orchestrate.md` names the blocked-stop causes, `blocked: <cause>`, "no push, no PR" and
      `loop-record.py --clear`.
- [ ] AMC3 `orchestrate.md` end of Phase 1 in `auto`: header `Contract gate`, `Contract go — `,
      `Validation: auto`, `as written`, `Contract (validated by this go)`.
- [ ] AMC4 `CLAUDE.md` (lines joined) scopes "never proceed on silence" to `moi`; agent count `(14)`.
- [ ] AMC5 `arbiter.md` exists, `model: inherit`, tools without Write/Edit, names the verdict block lines,
      "2 rounds", "never the agent that wrote the plan", "acceptance criterion" → blocked, `unfreeze-queue.md`,
      `git apply --check -` and `case-hash.sh`.
- [ ] AMC6 `11-token-budget.md` inherit row contains `` `arbiter` `` and the file is still 42 lines.
- [ ] AMC7 `spec.md` frame asks `Validation : moi | auto`; no separate call for it.
- [ ] AMC8 `plan.md` step 7 in `auto` hands the test plan to `arbiter`, 2 rounds, `## Gate` `arbiter go`.
- [ ] AMC9 `interface.md` in `auto`: no canvas render, no gate, reasons in `design.md`.
- [ ] AMC10 `github.md` order `**Contract contradiction**` < `**Screenshots**` < `**Guarded files touched**`
      < `**Frozen cases**` < `**Open questions**` < `**Review**` < `**Gates**` (PK32 extended, not replaced).
- [ ] AMC11 `ship.md` in `auto` runs `loop-record.py --guarded-block` into the body, and a blocked stop pushes
      nothing.
- [ ] AMC12 `guides/review/tests.md` names the auto-mode Critical cases (no `unfreeze` verdict, hash
      mismatch, `refuse`d case changed).
- [ ] AMC13 `review.md` in `auto` applies fixes without asking and routes a user choice to `arbiter`.
- [ ] AMC14 `README.md` says 14 subagents (both places).
- [ ] AMC15 `orchestrate.md`: the spec's `Validation:` line (or the full/BMAD `Validation` answer) only opens
      the `Contract gate`; after it `loop-record.py --mode` alone decides, a restart after `research` reads
      `--mode`, and `moi` there continues in `moi`.
- [ ] AMC16 `orchestrate.md` in `auto`: no command that asks; a deny opening `auto mode — blocked stop:`
      runs the blocked stop; `barrier` required before Phase 2, else blocked stop.
- [ ] AMC17 `.claude/settings.json`: the PreToolUse Bash `enforce-git-workflow.sh` entry has `timeout` ≥ 20.
- [ ] AMC18 `plan.md` in `auto` routes `arbitrate` / `Plan critic, open` to `arbiter`; `orchestrate.md`
      EXECUTE in `auto` launches one fresh `arbiter` per queued case id with its diff hunk.
- [ ] AMC19 `orchestrate.md:197` and `:206` keep "on silence" verbatim with "in `moi`" (existing needle at
      `test-workflow-contracts.sh:317` still green).

### Acceptance criteria → cases
- AC1 (mode once, record only, agent write denied, restart): AM10-AM19, AMC7, AMC15, LP1 (still green).
- AC2 (one stop; agents take mock-up, interpretations, test plan, frozen cases; refuse; Critical):
  AMC3, AMC8, AMC9, AMC18, AM20-AM27, AM30-AM32, AM37, AM38, AM40, AM41, AM45, AM47, AMC5, AMC12.
- AC3 (blocked stop, local, no push, no PR): AMC2, AMC16, AM19, AM30, AM43, AM46, G21 no-record cases.
- AC4 (F6 deny/ledger, block incl. reverted): AM3, AM28, AM29, AM34, AM35, AM43, G22.001-G22.009.
- AC5 (suites, budget): full suites at step 10, AMC6, AMC4, `test-rules-floor.sh`.

### Test-after
None beyond the above: every hook path is covered test-first through the suites.

## Gate amendments to validate (written into `## Gate` on the go)
- HP-B2 (test-workflow-contracts.sh `:716-729`): `HP_WANT` gains
  `Bash(python3 .claude/hooks/loop-record.py --mode)` and
  `Bash(python3 .claude/hooks/loop-record.py --guarded-block)`; count 32 → 34. Reason: step 6, exact-set contract.
- PK32 (`:1361`): extended to the AMC10 order (new headings inserted, the existing five kept in order).
- Any existing case pinning the `enforce-git-workflow.sh` hook timeout at 5 (e.g. `test-install.sh`'s
  settings merge check) is amended to 20, listed by id here when EXECUTE finds it. Reason: plan-critic Q2.
- Any loop-to-pr LP/G21 case whose fixture record now lacks a field read by the new code: none expected
  (all new fields optional); if EXECUTE finds one, it goes through the unfreeze queue (arbiter at night).

## Vigilance (carried from research)
- Record merges: every new field survives a later same-pass Plan go and is read before `drop_record` (AM16).
- One hash domain: the case title (AM22, AM37); a verdict never checked on another domain.
- The verdict hook ignores every agent but `arbiter`, the main thread, `moi`, a second verdict on a case
  (AM22-AM26) and decides nothing (`decision` never returned).
- The record and its new fields stay unwritable by agents through Write/Edit/shell (AM18); guarded rows
  enter only through the hooks' stdin op, never a model-run CLI.
- `auto` denies never leak into `moi` (AM33); the Q3 paths become asks in `moi` (AM1, AM2) — said in the PR.
- `git fetch` in a PreToolUse hook: one fetch, bounded (8+1 s) under the 20 s wired timeout, fail closed
  (G22.007, AMC17).
- In `auto`, `.tdd-unfrozen` has one route (Edit on a verdict): shell writes denied (AM45), freeze
  fallbacks off (AM47); every shell-guard ask is a blocked-stop deny (AM46).
- Shell asks in `auto` (plan-critic Q13): step 3 converts the five named asks (G, U, P, M, tool option);
  the hook's other asks (`GUARD_ASK_S/K/W/Q/F/T/O/R/CG`, the two `GUARD_FAILED` asks) stay asks, and
  AMC16 forbids issuing them in `auto`; so do `SECRET_ASK` (`:968`), `GUARD_PARSE` (`:983`),
  `FORMAT_WIDE` (`:1113`) and `SRC_WRITE_SEEN` (`:1121`) (targeted pass Q14) — the prompt names all of them. The review checks the code converts exactly the named five and
  that the prompt names the rest as "never issued in auto".
- `.claude/.loop-record.lock` is gitignored (repo `.gitignore` and `install.sh` ignore block) and in
  `CWK_GUARD_DENIED`.
- The PR-body check runs only on the exact `pr_form` in `auto`; other forms keep asking.
- Budgets: `11-token-budget.md` 42 lines, core floor ≤ 520, `CLAUDE.md` ≤ 140 (AMC4, AMC6, rules-floor).
- `CLAUDE.md:106-107` phrase wraps: AMC4 joins lines.
- PK32 order lock and the 13-loop-command count: no new loop command; PK32 extended.
- Blocked stop: record cleared, so `record_allow` can grant neither push nor PR (AM19 + G21 no-record cases).
- The verdict channel on 2.1.329 is unmeasured live (answer 1): fail closed, residual named in the PR.
- Guarded rows are written in PreToolUse; a parallel sibling hook may deny the write: the row stays,
  visible in the block (step 3 known limit), never a hidden edit.
- Record read-modify-write under `flock` (AM44); no writer bypasses the lock.
- No `.tdd-unfrozen` line outlives the record (AM42): verdict-backed lines are commented out on drop.
- In `auto`, a guarded ask is a deny (`auto mode — blocked stop:`); a non-guarded ask is never issued.
- `Guarded files touched` lists test files with status `D` as well as `M`.

## Acceptance criteria (carried from the entry artifact)
- [ ] The mode is asked once at the framing; it lives only in the hook-written record; an agent write to the record is denied; a restart resumes in the recorded mode.
- [ ] Auto mode: one stop after research (contract + traps); then the mock-up pick, plan-critic interpretations, the test plan and every frozen-case verdict are taken by agents with no stop; a `refuse` keeps the test frozen; a mismatched or unrecorded unfreeze is Critical at review.
- [ ] Auto mode: any blocked-stop cause ends the run `BLOCKED`, commits local, no push, no PR.
- [ ] F6: auto mode denies `settings*.json`, workflows, CODEOWNERS, kit code, the project config file; allows and ledgers the other guarded paths; the PR's `Guarded files touched` block is the hook's, including reverted guarded edits.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass; `11-token-budget.md` stays within its budget.

## Plan critic
- pass 1: completeness 66, quality 58; verifier confirmed C1-C4, Q1-Q4 → route `rewrite`
  (`route-plan-1.json`), attempt 1/3. Rewrite 1: C1 → AMC15-AMC18 + AC map; C2 → AM3, AM28; C3 → step 3
  shell, AM35; C4 → answer 9, AM30-AM32, AM43, AMC16; Q1/Q7 → answer 4, AM11, AMC15; Q2 → one fetch,
  timeout 20, AMC17; Q3 → `comment_row_lines` + AM42; Q4 → answer 8, AMC5. Minors folded: C5 (AC map), C6
  (AM3 all patterns), C7 (`D` status), Q5 (known limit), Q6 (`flock`, AM44), Q8 (AMC19, `kind`).
- pass 2 (rerun): completeness 88, quality 80; C1-C4, Q1-Q4 fixed. New Q9, Q10 (Major, in the rewritten
  shell paragraph), verifier confirmed both → route `rewrite` (`route-plan-2.json`), attempt 2/3.
  Rewrite 2 (narrowed to that paragraph + step 4): Q9 → shell `.tdd-unfrozen` deny in auto (AM45) and
  freeze fallbacks off in auto (AM47); Q10 → every shell-guard ask named and denied in auto (AM46).
  Minor Q11 folded (Vigilance 8+1 s, lock gitignored, Files table).
- pass 3 (rerun): completeness 93, quality 82; Q9, Q10 fixed. New Q12 (Major: AM46 input `rm src/a.ts`
  asks nothing today), verifier confirmed by running the hook → route `blocked` (`route-plan-3.json`);
  `kit-attempts.py` exit 3: **BLOCKED — plan-critic failed 3x : Q12**. User decision 2026-11-20
  (AskUserQuestion, header `Blocked`): fix + targeted pass + plan gate; counter reset (attempts.json
  emptied). Fix: AM46 inputs `rm -r src/a` (P), `mv src/a.ts /tmp/b` (M), `npx tsc --init` (tool option),
  each verified asking today. Minor Q13 → Vigilance (which shell asks become denies in auto).
- targeted pass (after the reset): completeness 95, quality 87; Q12 fixed (four inputs run on the hook,
  `cp /tmp/a frontend` read through `shell_targets.py`/`cwk_is_guarded`). Minor Q14 → Vigilance (four
  more never-issued asks). `kit-attempts.py pass` on `plan-critic`.
- completeness: 95
- quality: 87
- surviving blockers: none

## Gate
- 2026-11-20 go (AskUserQuestion, header `Plan gate`, `Frozen cases to amend: none`); loop record
  written by `loop-record.py` (slug `auto-mode`, branch `feat/auto-mode`, base `audit/slim` @ 8313de2,
  barrier true, base_ok true).
- Contract: as written (`kit-attempts.py pass` on `contract`).
- Open questions → answers taken as printed in `## Proposed answers` 1-9 (SubagentStop fail closed;
  title hash domain; new guarded paths in every mode; Validation line opens the Contract gate, record
  from it; `arbiter`, 2 rounds; moi = loop-to-pr flow; ships the loop-to-pr way; queued diff hunk +
  `git apply --check -`; guarded asks → blocked-stop denies in auto).
- Gate amendments accepted in principle (`## Gate amendments to validate`): HP-B2 32 → 34, PK32
  extended, any git-hook timeout pin 5 → 20 — each listed here by id when EXECUTE edits it.
- From this go on: the user sleeps; `docs/work/auto-mode/night-arbiter.md` (main tree) applies — every
  decision that would come back to the user is taken by a fresh `reviewer` arbiter and traced in
  `docs/work/auto-mode/night-decisions.md`. Never merge.
- amended 2026-11-21 AM35 (**decided by the arbiter**, night-decisions.md #1): `cp /tmp/a vite.config.ts`
  → `cp /tmp/a package.json` (both halves). Reason: a shell write to a `.ts` file is denied today by the
  source-writer rule, so the moi "asks" half could never pass. Test edit done
  (`test-hooks.sh` run_auto_mode_step3_cases, the auto lines and the moi line).
- amended 2026-11-21 HP-B2 32 → 34 (the two loop-record allows); PK32 extended to
  `Contract contradiction` < `Screenshots` < `Guarded files touched` < … (in principle above).
- amended 2026-11-21 AM12, AM20, AM21, AM22, AM27, AM40 (**decided by the arbiter**, night-decisions.md #3,
  after review R3 option A, #2): one setup line `git -C "$r" switch -q -c feat/s1 audit/x` after each
  fixture's Contract go; no assertion or title changed.
- amended 2026-11-21 G14.136 (**decided by the arbiter**, night-decisions.md #5, after review N1 option A, #4):
  `git switch -c x main` → `git switch -c x origin/main`; verdict `ask` and reason kept.
