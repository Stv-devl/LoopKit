# Spec: Auto mode — the user validates the contract after research, agents take the gates, the PR shows what they decided
Status: DRAFT — pass 4 of 4, split from `docs/specs/fewer-validations.md` on 2026-11-09 (V7, V8, as reviewed 2026-11-08). Depends on `fewer-asks.md`, `kit-boundary.md`, `loop-to-pr.md` shipped, and on one real feature run through `loop-to-pr`.
Token profile: critical (agents take gates that are the user's today)

## Objective
Let the user choose, once per pass, an `auto` mode: they validate the contract with research in hand, then leave; agents take every gate until the PR. Every real decision stays with the user: the framing, the contract, and the merge. What an agent decides is written in the PR, from records the agent cannot write. Anything that would still stop the run ends it as a blocked stop, with nothing pushed.

## Evidence
Shared with `docs/specs/fewer-asks.md` (*Evidence*). Expected in `auto` mode: the framing, the contract stop after research, then nothing until the PR.

## Scope
- IN :
  - **V7. Auto mode: who takes the gates, chosen once.**
    - **The mode question** is asked at the framing, with the spec interview's questions (no extra stop): `Validation : moi | auto`. Full/BMAD entry: asked at `/loop:orchestrate` Phase 0. Never asked again in the pass, never switched by it. The record hook (`loop-to-pr.md`) stores it with the contract go; missing or mismatched → `moi`.
    - **`moi`**: the flow after `loop-to-pr.md` (`light-fewer-gates.md` B1/B3 plus V10).
    - **`auto` — option B** (user, 2026-11-08): `/loop:orchestrate` stops once at the end of Phase 1: it prints the spec's Objective, Scope IN/OUT and Acceptance criteria verbatim under `Contract (validated by this go)` and research's `Traps`, and asks `as written` or free text to amend (B3's amendment rules apply). Full/BMAD entry: the stories, after `/stories:review`, are the contract; same stop after research. After that stop, every gate goes to an agent:

      | Gate after the contract | `moi` | `auto` |
      | --- | --- | --- |
      | Interface: pick a mock-up (UI only) | the user picks | the main thread's front-runner from step 3 (economy, 2 alternatives), or the `designer` judge on a `critical` profile (3 proposals, `interface.md:39-45`, `designer.md:172-176`); reasons in `design.md`; the canvas render (step 4) is skipped |
      | Contract question at the first gate (B3) | asked | already taken at the stop after research |
      | Plan-critic `interpretation` findings (`review-convergence.md` P4) | the user | the dedicated agent |
      | Open questions + test plan | the user | the dedicated agent |
      | Frozen-test correction (plan or EXECUTE) | the user (V10) | the dedicated agent (`unfreeze` / `refuse`) |
      | Commit, push, PR | the agent (V5) | the agent (V5) |
      | Merge of the PR | the user | the user |

    - **The dedicated agent** (new, read-only, tier `inherit`, added to the existing `inherit` row of `11-token-budget.md`, which is at its 42-line budget):
      - **Test plan:** checks the cases against the spec's acceptance criteria and business logic, the expected values' sources and the order; answers the open questions; `go` or corrections, bounded rounds. Its `go` never counts as the user's plan go: each frozen-case amendment needs its own verdict row.
      - **Frozen case:** reads the case id, old and new case line and reason, and **the hunk itself from `git diff`**; answers `unfreeze` or `refuse`. One verdict per case id per pass; `refuse` is final; the requester cannot relaunch it for the same case.
      - Never the agent that wrote the plan, nor the one asking for the correction.
      - May not decide alone a correction that changes the meaning of an acceptance criterion → blocked stop.
    - **Verdict ledger.** A `SubagentStop` hook writes each dedicated-agent verdict (path, case id, sha256 of the new case line, verdict) into the record (`loop-to-pr.md`). `protect-files.sh` allows a `.tdd-unfrozen` entry only on a matching ledger row, with no prompt. The reviewer rule of `loop-to-pr.md` applies to ledger rows.
    - **A contract contradicted mid-run:** the agent never rewrites the contract. It continues on the contract as written when it can and puts the contradiction first in the PR (`Contract contradiction` section); when it cannot build anything coherent → blocked stop.
    - **Blocked stop.** A remaining ask, plan-critic `BLOCKED`, an attempts cap, a red gate after the fix budget, an undecidable case, a correction that changes an acceptance criterion's meaning — ends the run: handoff `blocked: <cause>`, board line `BLOCKED`, local commits kept, **no push, no PR**, record cleared. `./workflow.sh` resumes it. Auto mode does not start without the server-side barrier of `loop-to-pr.md`.
  - **V8. Guarded paths, split in two** (auto mode only):
    - **Denied:** `.claude/settings.json`, `.claude/settings.local.json`, `.github/workflows/*`, `.github/actions/*`, `.github/CODEOWNERS`, the kit code and the project config file (`kit-boundary.md`). A pass that needs one ends in a blocked stop.
    - **Written without an ask, then flagged in the PR:** `.claude/.tdd-unfrozen` (only on a ledger row), `.claude/.size-exempt`, `vitest.config.*`, `eslint.config.*`, `vite.config.*`, `playwright.config.*`, `package.json`, `tsconfig*.json` — at the root and under every `APP_ROOTS` entry — and `lefthook.yml`, `.npmrc`, `pnpm-workspace.yaml`, vitest setup files; the same for their shell-write asks. CI replays the gates from the committed configs.
    - **Always as today, every mode:** every deny (secrets, `.claude/.tdd-red/`, `.git/`, destructive commands, the TDD hooks' denies); every non-guarded ask (destructive git, `gh pr merge`).
    - **The `Guarded files touched` section is computed by the hook.** When `enforce-git-workflow.sh` is about to allow `gh pr create`, it fetches, builds `git diff --no-renames --name-status origin/<base>...HEAD`, adds the ledger of guarded writes allowed during the pass (path, sha256 before/after — catches a guarded edit reverted before the commit), and denies unless the `--body-file` contains that exact block (checked by hash). Changed existing test files are listed; a changed frozen case with no ledger row is printed first, as a guard failure.
- OUT :
  - `moi` mode's contract placement: unchanged, `docs/specs/light-fewer-gates.md`.
  - The plan-critic / review cap: `docs/specs/review-convergence.md`.

## Open questions
- The dedicated agent's name and its round bound on the test plan: decide in the plan.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- Hooks: the record hook (mode + contract go, `SubagentStop` verdicts), `protect-files.sh`, `enforce-git-workflow.sh` (`Guarded files touched`), `hook-guarded.sh`, their fixtures, `test-hooks.sh`; `.claude/settings.json` wiring.
- Commands: `.claude/commands/loop/{spec,orchestrate,interface,plan,review,ship}.md`.
- Agents: the new dedicated agent, `designer`, `github` (two new PR sections), `.claude/guides/review/tests.md`.
- Rules and docs: `.claude/rules/11-token-budget.md` (agent name in the `inherit` row, no new line), `CLAUDE.md` (`/loop:interface` and `/loop:plan` "never proceed on silence" holds in `moi` only; agent count 13 → 14), `README.md`, `docs/Claude_Workflows.md`, `docs/specs/light-fewer-gates.md`.

## Business logic to cover
- F6 auto mode: `settings.json`, `.github/workflows/x.yml` write: deny; `vite.config.ts` and `frontend/vite.config.ts` write: pass + ledger row; `.tdd-unfrozen` with/without a ledger row: pass/ask.
- F8b mode record: an agent write is denied; missing record → mode `moi`; a subagent's `AskUserQuestion` records nothing; the record is gone after a blocked stop; a restart resumes in the recorded mode.
- F15 `gh pr create` body without the computed `Guarded files touched` block: deny; with it: pass; a guarded edit reverted before the commit still appears.

Contract greps: `orchestrate.md` carries the V7 table and the blocked-stop rule; `CLAUDE.md` scopes "never proceed on silence" to `moi`.

## Acceptance criteria
- [ ] The mode is asked once at the framing; it lives only in the hook-written record; an agent write to the record is denied; a restart resumes in the recorded mode.
- [ ] Auto mode: one stop after research (contract + traps); then the mock-up pick, plan-critic interpretations, the test plan and every frozen-case verdict are taken by agents with no stop; a `refuse` keeps the test frozen; a mismatched or unrecorded unfreeze is Critical at review.
- [ ] Auto mode: any blocked-stop cause ends the run `BLOCKED`, commits local, no push, no PR.
- [ ] F6: auto mode denies `settings*.json`, workflows, CODEOWNERS, kit code, the project config file; allows and ledgers the other guarded paths; the PR's `Guarded files touched` block is the hook's, including reverted guarded edits.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass; `11-token-budget.md` stays within its budget.

## Measure after
On the first EcoCrew feature in `auto` mode: stops (expected: framing + contract), blocked stops by cause, guarded files flagged in the PR, verdicts `unfreeze` / `refuse`.
