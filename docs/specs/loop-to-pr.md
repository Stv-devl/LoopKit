# Spec: Loop to PR — push and open the PR without asking, the hook-written record, tests validated in one read
Status: DRAFT — pass 3 of 4, split from `docs/specs/fewer-validations.md` on 2026-11-09 (V5, V7's *Record*, V10, as reviewed 2026-11-08). Depends on `fewer-asks.md` and `kit-boundary.md` shipped. Next: `auto-mode.md`.
Token profile: critical (it widens what runs without a prompt: push, PR, the freeze escape hatch)

## Objective
The loop goes all the way to an open PR without asking; the user's validation is reading and merging the PR. The frozen tests a pass amends are validated in one read at the plan gate and never asked again. Both rest on a record written by hooks from the user's literal answers, which the agents it frees cannot write.

## Evidence
Shared with `docs/specs/fewer-asks.md` (*Evidence*). Owned here: push/PR asked 3 + 4 times plus confirmed in chat ("Je pousse et j'ouvre la PR ?"); `.tdd-unfrozen` additions asked in bursts (07:39, 07:50, 07:58, 10:00-10:03, plus once in chat at 16:13), including C1-C10 already approved in the 14:20 plan go then asked at 14:22 and rejected by mistake.

## Scope
- IN :
  - **V5. The loop goes to the PR, the user validates the PR** (user, 2026-11-08). The agent commits on the pass's feature branch, pushes it and opens the PR it wrote, with no ask and no chat confirmation.
    - **Server-side barrier first.** Allowed gate commands (`pnpm lint`, `pnpm test:run`) run agent-written code that could push or merge with the user's credentials (`skills/templates/ci.md:16-17`). Before the first automatic push of a repo, `/kit:doctor` (or Phase 0) checks through `gh api` that the default branch requires a PR and blocks force-push and deletion. Without that rule, push + PR keep one ask (today's behaviour). No remote: today's local flow, unchanged.
    - **The branch comes from the record** (below), must match `feat/<slug>` or the plan's naming, and must not exist on the remote before the first push (`git ls-remote origin refs/heads/<B>` empty).
    - **Exact grammar, effective destination.** `enforce-git-workflow.sh` (today it asks on every push, `:1482-1488`, and every `gh pr …`, `:1470-1471`) lets through, without an ask: exactly `git push -u origin <B>`, with no global option, no env assignment, no refspec `:`/`+`, nothing after it; `<B>` resolves to `refs/heads/<B>` and no `refs/tags/<B>` exists; `git config --get-regexp` finds none of `remote.origin.(push|pushurl|mirror|receivepack)`, `url.*.pushinsteadof`, `push.(followtags|pushoption)`, `core.sshcommand`; and exactly `gh pr create --repo <recorded owner/repo> --base <recorded Base> --head <B> --title … --body-file <file>`, no `--web`. Anything else keeps today's ask; `--force*`, `gh pr merge`, PR edit/close, tags and releases are asked always. Fixtures cover each refused shape (`HEAD:main`, `+feat/x`, `feat/x:main`, `--tags`, `--mirror`, `--delete`, `--force-with-lease`, `--no-verify`, a `remote.origin.push` mapping, another branch, a wrong `--base`, `--repo` elsewhere).
    - **Stacked passes.** Parts B and C forked from unmerged feature branches (#23 ← #24 ← #25). The base is captured by the record hook itself (`git rev-parse --abbrev-ref HEAD` and its sha) as `Base`; `Base:` in `plan.md` is an informational copy. `gh pr create --base` must equal the recorded base, which must exist on the remote and be the default branch or an unprotected feature branch. **Closing**: a pass closes (board/story `Done`, branch clean-up) when its PR reads `MERGED` and its `baseRefName` is the default branch; a stacked PR merged into a feature branch closes when the PR of that branch does (follow the chain). Works with merge, squash and rebase merges. The end-of-pass message gives the merge order.
    - **Pushes after the PR is open** keep the ask.
    - **`/loop:ship` 4bis is rewritten** (`ship.md:124-151`): no local rebase-then-merge into main, no force-push ever; the PR replaces the local merge. Board `Done`, story `Done`, worktree and branch clean-up run on the next session once the closing rule holds (`gh pr view --json state,baseRefName`), and `/loop:tracks` recomputes after it. `ship.md:119-122` and `:237-238` are rewritten: the amended cases go into the PR body. `fast-lane.md` D4 ("local first") is superseded for loop passes; `/loop:small` follows V5 too.
    - **The `github` agent** (`github.md:3`, `:99-112`) pushes the pass's branch and opens its PR without asking; everything else as today. Its body template gains the loop-PR shape: the summary line, then fixed sections in this order — `Frozen cases` (every `amended`, with its hunk), `Open questions` (answers taken), `Review` (surviving findings), `Gates`; the full test plan stays in `plan.md`, linked by path. Sent with `--body-file`. (`auto-mode.md` adds `Contract contradiction` and `Guarded files touched`.)
    - **Since `pr-screenshots.md`** the template already opens with the summary, `Where to look`, `Uncertain`, one line per commit and `Screenshots`, written to `docs/work/<slug>/pr-body.md`. The loop-PR sections are appended after those, and the `pr-assets` publish and cleanup pushes keep their ask.
  - **Record — written by hooks, never by the agents it frees** (from V7). A hook captures, from **main-thread** `AskUserQuestion` results only (PostToolUse; calls carrying `agent_type` are ignored), the user's literal answers: the plan-gate go with its `Frozen cases to amend` rows (V10). It writes them, with the slug, the branch `<B>`, the `Base` it reads itself and `owner/repo`, into a record under a `CWK_GUARD_DENIED` path (same class as `.claude/.tdd-red/`, `hook-guarded.sh:45-48`). Hooks read only that record. **Missing or mismatched → no record-backed allow at all**: push, PR and every unfreeze ask, as today. The latest plan-gate go supersedes earlier ones. Copies in `plan.md` and the handoff are informational. The record is cleared when the PR is created and at a local-only ship. A 97% restart or a Codex handover resumes from it. Which answer opens the record (branch and base captured) is decided in the plan; `auto-mode.md` adds the mode and the contract go to it.
  - **V10. The tests are validated in one read, not sent back several times** (user, 2026-11-08).
    - **The plan gate shows everything once:** the open questions with proposed answers, the whole test plan for every layer, the expected values' sources, **and the existing frozen cases the pass will amend** (case id, old and new line, reason). One `go`. An amendment re-shows the full plan once, changed cases marked.
    - **A correction approved in the plan go is not asked again.** An entry exempts a whole **path** (the ids are a comment, `tdd-freeze-tests.sh:124-140`) and also lifts the RED requirement on an implementation path (`:34-35`), so an id alone authorises nothing:
      - Every plan gate goes through `AskUserQuestion` with a fixed header (today full and BUG passes ask in chat, `plan.md:88-89`, `:125`) and prints, verbatim, a `Frozen cases to amend` block: one row `<test path> | <case id> | sha256(<new case line>)` per case, no ranges. What the user reads is what gets recorded.
      - The record hook stores the rows only when the answer is the exact `go` option label (free text records nothing).
      - `protect-files.sh` allows a `.tdd-unfrozen` Edit without a prompt only when every added line's path and ids match recorded rows and the path is a test file; an implementation path, an id on another path, or an id from an earlier pass's go keeps the ask. The spike (`docs/product/spikes/safetycheck-tdd-unfrozen.md`) shows Claude Code adds no prompt of its own there.
      - `tdd-freeze-tests.sh` (and `addons/fastapi/hooks/tdd-freeze-tests-py.py`) then accepts the edited case only if its new line hashes to the row; otherwise deny.
    - **Frozen-test corrections during EXECUTE are queued, then validated once.** The main thread records each (case id, old and new line, reason, hunk) and keeps working on what does not depend on the blocked layer (`05-testing.md`'s layer order holds). It stops **once**, when nothing else can progress or at the end of EXECUTE before review, shows the whole batch, and applies the user's answer (all, some, none) in **one** `.tdd-unfrozen` Edit. This replaces `light-fewer-gates.md` B7's per-correction confirmation; B7's recording in `## Gate` and its listing (now in the PR body) stay.
    - **Reviewer:** an unfrozen test whose diff does not match its recorded new line, or removes an assertion beyond it, is **Critical** (FAIL); a changed frozen case with no row is Critical.
- OUT :
  - Auto mode, the dedicated agent, the guarded-path split, the `Guarded files touched` block: `docs/specs/auto-mode.md`.
  - General grants (`project-grants-parked-real-feature-trial`): stay parked; V10's record-backed allow is the only one (`.tdd-unfrozen`, rows the user read, test paths only).
  - Executed test or script code acting with the user's credentials (the server-side barrier is the answer).

## Open questions (to settle before it is scheduled)
- **User to confirm**: V10's record-backed allow is a narrow guarded-path grant, which `project-grants-parked-real-feature-trial` parked until stops were measured; part C (11/33) is that measure. Lift the parking for `.tdd-unfrozen` only?
- Answered by the review: subagent calls are distinguishable in the hook input (`agent_type`, already read by `tdd-freeze-tests.sh:84-85`).

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- Hooks: `enforce-git-workflow.sh`, `protect-files.sh`, `tdd-freeze-tests.sh`, `addons/fastapi/hooks/tdd-freeze-tests-py.py`, a new record hook (PostToolUse `AskUserQuestion`), `hook-guarded.sh`, `kit-doctor.py`, their fixtures, `test-hooks.sh`; `.claude/settings.json` wiring.
- Commands: `.claude/commands/loop/{plan,orchestrate,ship,small,tracks}.md`, `.claude/commands/kit/doctor.md`.
- Agents: `github`, `reviewer` / `.claude/guides/review/tests.md`.
- Docs: `docs/Claude_Workflows.md`, `docs/specs/light-fewer-gates.md` and `docs/specs/fast-lane.md` (cross-references to V5/V10).

## Business logic to cover
- F4 `git push -u origin <B>` with the record and the server rule: pass; each refused shape listed in V5: ask/deny; no server rule: ask.
- F5 `gh pr create` exact form: pass; `--repo` elsewhere, wrong `--base`, `--web`: deny/ask.
- F8 record: an agent Write/Edit/shell write to the record path: deny; missing record → push, PR and unfreeze all ask; a subagent's `AskUserQuestion` and a free-text answer record nothing; a second plan go drops the first go's rows; the record is gone after the PR and after a local-only ship.
- F12 recorded plan go with rows: `.tdd-unfrozen` Edit whose paths and ids match rows: pass; a matching id on another path, an implementation path, an id from an earlier pass: ask; the edited case's new line hashing differently from its row: deny.
- F13 `gh pr create --base <B'>` where the record holds `Base <B'>`: pass; another base: ask; a base edited into `plan.md` only: ask.

Contract greps (`test-workflow-contracts.sh`): `github.md` no longer says "always asks" for push/PR; `ship.md` 4bis has no local merge, no "je pousse", and closes on `MERGED` + `baseRefName`; `plan.md` asks every plan gate through `AskUserQuestion` with the `Frozen cases to amend` block.

## Acceptance criteria
- [ ] Server rule present: commit, push of `<B>` and `gh pr create` run with no ask and no chat confirmation; every refused shape of F4/F5 asks or is denied; without the server rule push + PR ask once; no remote: local flow unchanged.
- [ ] `ship.md` 4bis opens a PR instead of merging locally; board/story/worktree close on `MERGED` with `baseRefName` = the default branch; the PR body follows the loop-PR template, sent with `--body-file`.
- [ ] F13: a stacked pass opens its PR on the hook-recorded base and closes when the chain reaches the default branch, on merge, squash or rebase.
- [ ] F8: the record is written by the hook only, from main-thread `go` answers; an agent write to it is denied; missing → today's asks.
- [ ] The test plan is validated in one stop for all layers; frozen cases amended by the plan are shown as hashed rows; their `.tdd-unfrozen` entries are written with no second ask only on matching rows, never for an implementation path (F12).
- [ ] Frozen-case corrections during EXECUTE reach the user as one batch, one stop, one `.tdd-unfrozen` write; a mismatched unfreeze is Critical at review.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Measure after
On the next EcoCrew feature: no push/PR ask, no chat confirmation before the PR; `.tdd-unfrozen` additions: one ask per EXECUTE batch at most, none for plan-approved rows. Expected total ~3-5 prompts.

## Next work
At `/loop:ship`, propose `docs/specs/auto-mode.md` (pass 4 of 4) only after one real feature has gone through this pass's flow, and with that measure in hand.
