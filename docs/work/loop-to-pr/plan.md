# Plan: Loop to PR, pass 3 of 4   (entry: docs/specs/loop-to-pr.md · research: docs/work/loop-to-pr/research.md · design: n/a)
Token profile: critical
Base: 0fec359

## Skips
- DB: SKIP, no data. Backend: SKIP, kit tooling. INTERFACE: SKIP, no screen.
- Front test-first layers (`utils`/`mapper`/`repository`): none — every file is a hook, script,
  prompt or suite. The kit's own discipline applies: each step writes its cases into the suite
  first, runs them red, then writes the code.
- Case ids: `LP` (test-hooks.sh, new block), `G21.nnn` (`fixtures/_harness/git-guard.jsonl`),
  `KD24+` (test-kit-doctor.sh), `IN59+` (test-install.sh), `PK25+` (test-workflow-contracts.sh).
- OUT (spec): auto mode, `Contract contradiction` / `Guarded files touched` PR sections, general
  grants.

## Proposed answers to research's open questions (taken at `## Gate`)
1. **AskUserQuestion input** — settled by the spike (research Q1). Residual stated: a user typing
   exactly `go` in "Other" counts as go (it is the user's own answer). Cases LP5-LP9.
2. **Which answer opens the record**: the plan-gate `go` only — one `AskUserQuestion` question with
   header exactly `Plan gate`, answer exactly `go`. The Phase 0 go records nothing (auto-mode adds
   the contract go later). Cases LP5, LP8.
3. **Record**: one file per **tree**, `<tree>/.claude/.loop-record.json`, where `<tree>` is
   `git rev-parse --show-toplevel` of the hook input `cwd` (it follows `EnterWorktree`;
   `$CLAUDE_PROJECT_DIR` does not — `claude-code-worktrees.md:23`). Readers locate it the same way:
   the git hook from the tree the command runs in, `protect-files.sh` and the freeze hooks from the
   tree holding the file being edited. A new plan go **replaces** the whole file (spec: "the latest
   go supersedes"). Added to `CWK_GUARD_DENIED`, `.gitignore`, `install.sh`'s gitignore block and
   copy prune. Shape (version 1):
   ```json
   {"version":1,"slug":"loop-to-pr","plan":"docs/work/loop-to-pr/plan.md",
    "branch":"feat/loop-to-pr","base":"audit/slim","base_sha":"<40 hex>",
    "repo":"Stv-devl/LoopKit","default_branch":"main","barrier":true,"base_ok":true,
    "rows":[{"path":"src/a/x.utils.test.ts","id":"U2","sha256":"<64 hex of the new title>"}],
    "at":"<UTC ISO>","tool_use_id":"<id>"}
   ```
   **Validity** for every reader: `version` 1, and HEAD's branch is `branch`, or HEAD's branch is
   `base` and `base_sha` is an ancestor of HEAD (EXECUTE on the main tree before ship's
   `git switch -c`). Anything else → treated as missing (a stale record of another pass authorises
   nothing). Cases LP20, LP30.
4. **Branch and base at record time** (fixes plan-critic Q1). Every kit command that creates a pass
   branch names its base explicitly, so git's reflog says `Created from <base>`:
   - `tracks.md`, `small.md`, `orchestrate.md` Phase 0.5: `git worktree add .claude/worktrees/<slug>
     -b feat/<slug> <base>` where `<base>` is the main tree's current branch name; this session then
     enters it with `EnterWorktree` **`path`** (no more `EnterWorktree name`, whose branch name and
     `baseRef: head` start point are not `feat/<slug>` from a named base).
   - Record hook: HEAD not `feat/<slug>` (single track) → `base` = HEAD's branch, `base_sha` its sha.
     HEAD is `feat/<slug>` → `base` = `<X>` from the oldest reflog entry `branch: Created from <X>`
     where `<X>` is a local branch name (`refs/heads/<X>` exists), `base_sha` = `git merge-base HEAD <X>`.
     `Created from HEAD`, a sha, or no entry → no record (today's asks). Detached HEAD → no record.
   - `/loop:ship` on a single track creates `feat/<slug>` with `git switch -c feat/<slug>` before the
     commit (already a no-prompt grammar); the record's `branch` is already `feat/<slug>`.
   Cases LP11-LP13.
5. **Server barrier**: read **once, by the record hook at the go** (10 s total budget), stored as
   `barrier` and `base_ok`; the PreToolUse git hook never calls GitHub, except one
   `git ls-remote` for "branch not yet on the remote" (5 s, failure → ask).
   - `repo`, `default_branch`: `gh repo view --json nameWithOwner,defaultBranchRef`.
   - `barrier` = `gh api repos/<repo>/rules/branches/<default>` returns all three of `pull_request`,
     `non_fast_forward`, `deletion`. gh failure, 403, timeout, missing type → `false`.
   - `base_ok` = `base` == default branch, or `git ls-remote origin refs/heads/<base>` is non-empty
     AND `gh api …/rules/branches/<base>` is `[]`.
   - Known limits, stated in the guide, not checked: ruleset bypass actors (an admin token can
     bypass), and a rule removed between the go and the push.
   - `/kit:doctor`'s `check_github_protection` reads the default branch and names a missing type
     (INFO). Cases LP16-LP17, KD24-KD25.
6. **ci.md:16-17 is a stale citation**: no change to `templates/ci.md`; the credential rationale is
   one sentence in `.claude/guides/orchestrate.md` next to the V5 rule.
7. **LoopKit itself**: this pass ships the current way (commit on a branch, push of `audit/slim` asks
   once, per memory "push to same branch, no PR"); the record-backed flow applies from the next pass.

## Hash producer (fixes plan-critic Q5; contract kept as written — no amendment)
- V10's row grammar stays `<test path> | <case id> | sha256(<new case line>)`. The main thread
  computes each digest with **`.claude/scripts/case-hash.sh '<new case title>'`** (single quotes, so
  `$`, `` ` `` and `\` in a title reach the script unexpanded; a title holding `'` is refused in rows
  mode like an escaped one) (new, `+x`,
  allow-listed as `Bash(.claude/scripts/case-hash.sh *)`): it prints `sha256` of its single argument
  (UTF-8, no newline) in hex and nothing else, reads no stdin, writes no file — so it cannot write
  the record. Before the call, the gate prints each amended case's old line, new title and reason, so
  the user reads the title the hash stands for. Case LP48.

## Plan critic, open (arbitrate — the go accepts the proposed answer as printed)
- **N3, `/loop:small` and V5.** Spec: "`/loop:small` follows V5 too". A small pass never reaches a
  plan gate (its go is asked in the main tree before the worktree exists, and its EXECUTE asks
  nothing before ship), so it has no record. **Proposed answer**: small follows V5's **PR flow** —
  ship's Small-ticket integration opens a PR instead of the local `merge --ff-only` when a remote
  exists — but its push and PR **ask once** (no record); the no-ask path for small is deferred to
  `auto-mode.md`, which already reworks the small go. The no-remote small flow is unchanged. Cases
  PK37, G21.003 (no record → ask) covers the hook side.

## Write chain (sequential)
Each step: cases into the suite → run → observed red → code → green → next step.

1. **Guard list** (`hook-guarded.sh`): `'.claude/.loop-record.json'` in `CWK_GUARD_DENIED`;
   `cwk_guard_denied_why` gets its own branch; `cwk-guard-api: 9`. `prevent-destructive-commands.sh`:
   the `.tdd-red` text clause (`:744-748`) and both parse-failure fallbacks (`:901-905`) also cover
   `.loop-record`; a shell command that **executes** `loop-record.py` is denied, except exactly
   `python3 .claude/hooks/loop-record.py --clear`. `kit-doctor.py` `RUNTIME_PATHS` gains the file.
   `.gitignore`, `install.sh` gitignore block (`:661`) and copy prune (`:340`) gain it.
2. **Record hook** `.claude/hooks/loop-record.py` (new, `python3 -I`, stdlib only, `+x`):
   - `PreToolUse AskUserQuestion`: a question with header `Plan gate` and a non-empty
     `tool_input.answers` → deny ("the plan gate is answered by the user, never pre-filled"). If the
     input cannot be parsed and the raw stdin contains `Plan gate` → deny (fails closed for the gate
     only; any other question is untouched).
   - `PostToolUse AskUserQuestion`: `agent_id` or `agent_type` present → nothing. Else find the
     question with header exactly `Plan gate`; its text's first line must be
     `Plan go — docs/work/<slug>/plan.md` (`<slug>` = `[a-z0-9][a-z0-9.-]*`), the plan file must exist
     in the tree; the answer for that exact question text in `tool_response.answers` (fallback
     `tool_input.answers`) must be exactly `go`. Then parse the `Frozen cases to amend:` block (rows
     `<path> | <id> | <64 lowercase hex>`; or the single line `none`; a malformed row, an id not
     `[UMRB][0-9]+`, a digest not 64 hex → no record at all), store the rows verbatim, compute
     branch/base (answer 4) and barrier (answer 5), write the record atomically (tmp + rename).
     Anything else: nothing written, nothing deleted.
   - `PostToolUse Bash`: the command is the exact PR form (step 3) and `tool_response` stdout holds
     `https://github.com/<record repo>/pull/<n>` → delete the record.
   - `--clear` (CLI, reads no stdin): delete the tree's record if present; exit 0. Allow-listed in
     `settings.json` as `Bash(python3 .claude/hooks/loop-record.py --clear)`.
   - Post paths: any exception → exit 0, nothing written.
   - Wired in `.claude/settings.json`: PreToolUse `AskUserQuestion`, PostToolUse `AskUserQuestion`
     and PostToolUse `Bash`, no `onFailure`. `install.sh` core mode keeps them (IN59).
3. **Git hook** (`enforce-git-workflow.sh`), a new `record_allow` block at the **top of the ASK
   pass** (after every deny, before the `gh pr` / `git push` floor regexes and `grammar_decide`). It
   returns `decide allow` only when **all** hold, otherwise falls through unchanged to today's asks:
   - the whole `$COMMAND` (trimmed, no control char, no `\`+newline) is exactly one of
     `git push -u origin <B>` or
     `gh pr create --repo <R> --base <Ba> --head <B> --title "<t>" --body-file docs/work/<slug>/pr-body.md`
     (that order, `<t>` double-quoted with no `$` `` ` `` `\` `"`, `<B>`/`<Ba>` `[A-Za-z0-9._/-]+`
     not starting with `-`);
   - the tree = the hook input `cwd`'s toplevel; its record is valid (answer 3), `barrier` true,
     `branch` == `<B>` == HEAD's branch;
   - push: `git show-ref --verify --quiet refs/heads/<B>` succeeds, `refs/tags/<B>` does not;
     the effective config (`git config --get-regexp`, all scopes, includes resolved) matches none of
     `^remote\.origin\.(push|pushurl|mirror|receivepack)$`, `^url\..*\.pushinsteadof$`,
     `^push\.(followtags|pushoption|recursesubmodules)$`, `^core\.sshcommand$`; no `GIT_DIR`,
     `GIT_WORK_TREE`, `GIT_SSH`, `GIT_SSH_COMMAND`, `GIT_CONFIG*` in the hook's environment;
     `git ls-remote origin refs/heads/<B>` (5 s) exits 0 with empty output;
   - PR: `<R>` == record `repo`, `<Ba>` == record `base`, `base_ok` true, the body file exists.
   The attribution deny on `--body-file` runs first (deny pass). Everything the floor catches keeps
   asking: `--force*`, `gh pr merge|edit|close`, tags, releases, a second push once the branch exists
   on the remote. The parse-failure fallback never sees the two exact forms (they parse).
4. **Unfreeze allow** (`protect-files.sh`): next to `unfrozen_removal_only`, a
   `unfrozen_record_rows` check on Write/Edit of `.claude/.tdd-unfrozen` (absent file: a Write
   creating it is simulated against an empty file): every **added** non-blank line must parse as
   `<path>  # <ids>: <reason>` (ids `[UMRB][0-9]+`, comma separated), `<path>` must be a test-first
   test file (`*.test.ts`, `*.test.tsx`, or `<tests root>/**/test_*.py`), and every `(path, id)`
   must be a row of the tree's valid record. Removals plus record-backed additions may share one
   edit. Missing/invalid record, a non-test path, an id on another path → today's ask. Removal-only
   allow unchanged.
5. **Freeze hook per-case check** (`tdd-freeze-tests.sh`, `tdd_py_lib.py` +
   `tdd-freeze-tests-py.py`). The `.tdd-unfrozen` path exemption becomes two modes:
   - **No row for this path in a valid record** → today's path exemption, unchanged (LP42).
   - **Rows mode** (the tree's valid record has rows for this path): the path is **not** exempted
     early; the existing checks run first — byte-identical re-save, pure new-case insertion — and
     pass as on any frozen file (fixes Q2). Where the existing logic would deny a modification, the
     per-case check decides instead:
     - the touched cases are every case whose span in the **current** file intersects the span of
       `old_string` (TS: `anchor_scope`-style walk over `it(`/`test(` blocks; Python:
       `enclosing_case_indent`) — never only the titles inside the strings (fixes Q3);
     - each touched case's id must be either a **row** — then the title it has in the resulting file
       must hash to the row — or listed on a `.tdd-unfrozen` line for this path with that id (an
       EXECUTE batch correction the user approved through the ask) (fixes Q4);
     - a case without an id prefix, an id with neither, or a hash mismatch → deny, the reason naming
       the case id, the expected and the actual hash.
     - A Write that is not a byte-identical re-save → deny ("edit case by case with Edit").
   - **Deny texts rewritten** (fixes Q6), TS `:414`, `:417` and Python `:207`, `:315`, plus
     `.claude/agents/implementer.md:46` and `orchestrate.md:272`: a needed correction is **queued**
     (`docs/work/<slug>/unfreeze-queue.md`) and reported, the main thread stops **once** for the
     batch; the amended cases are listed in the PR body (`Frozen cases`), never "the user confirms it
     at the merge".
   - The three `.tdd-unfrozen` parsers keep reading paths identically; only the freeze hooks read
     ids and rows.
6. **Closing script** `.claude/scripts/loop-pr-state.sh [--chain] <branch>` (new, `+x`):
   `gh pr view <branch> --json state,baseRefName,mergedAt,number` (+ `gh repo view` for the default
   branch); prints exactly one of `open`, `closable` (MERGED into the default branch), `stacked:<base>`
   (MERGED into a feature branch), `closed` (CLOSED unmerged), `none`, `unknown` (gh missing/failed).
   `--chain` follows `stacked:<base>` and prints `closable` only when every hop is MERGED into the
   next **and** each hop's `mergedAt` is earlier than its base's `mergedAt` (a PR merged into a
   branch that had already merged never reaches the default branch → `orphaned:<base>`).
   Allow-listed as `Bash(.claude/scripts/loop-pr-state.sh *)`.
7. **Contract cases first** (`test-workflow-contracts.sh`, PK25-PK33), run red against today's
   prompts, then step 8.
8. **Prompts**:
   - `commands/loop/plan.md` step 7: **every** pipeline asks the gate through `AskUserQuestion`, the
     go question with header `Plan gate`, first line `Plan go — docs/work/<slug>/plan.md`, then the
     verbatim `Frozen cases to amend:` block (`<test path> | <case id> | <sha256 of the new title>`,
     each digest from `.claude/scripts/case-hash.sh`, one per case, no ranges, or `none`), options
     `go` + `amend`. The full test plan and, per amended case, the old line, new title and reason are
     printed before the call. The three questions become the
     `amend` free text. An amendment re-shows the full plan once with changed cases marked.
   - `commands/loop/orchestrate.md`: Phase 0.5 forks with `git worktree add … <base>` +
     `EnterWorktree path` (answer 4); Phase 4 queues frozen-case corrections in
     `docs/work/<slug>/unfreeze-queue.md` (id, old/new line, reason, hunk), keeps working on what does
     not depend on the blocked layer, stops **once** (nothing else can progress, or end of EXECUTE),
     writes **one** `.tdd-unfrozen` Edit for the approved subset (it asks: these ids have no row),
     appends `amended` lines to `## Gate`. Plan-recorded rows are written with no prompt (step 4).
     Replaces B7's per-correction confirmation.
   - `commands/loop/ship.md` **step 2** (fixes N1): amended cases are listed in the PR body
     (`Frozen cases`, with hunks) on `4bis-PR`, and confirmed in the merge presentation only on
     `4bis-local`. **Step 4** (fixes N1): commits on `feat/<slug>` (`git switch -c` first when on the
     base); "Anything remote (push, PR) waits for the user's explicit go-ahead" is replaced by: the
     pass's own push and PR follow `4bis-PR` with no chat confirmation; any other remote action keeps
     the go-ahead. **Step 5** (fixes N2): on `4bis-PR` the story stays `InProgress`, the board line
     stays `IN LOOP`, and the handoff is written with `phase: awaiting-merge` and `pr: <url>`;
     story `Done`, board `SHIPPED`, brief and clean-up run only when the closing check prints
     `closable` (below); `4bis-local` keeps today's step 5. **Small-ticket integration** (N3,
     proposed answer): with a remote, push `feat/small-<name>` and open a PR on its `Base` (both ask
     once); without one, today's `merge --ff-only`. 4bis split in two named subsections:
     - **`4bis-PR` (a remote exists)**: no local rebase/merge, no force-push. The `github` agent runs
       `git push -u origin feat/<slug>` then the exact `gh pr create … --body-file
       docs/work/<slug>/pr-body.md`; with a valid record and the barrier they run without a prompt
       and **without a chat confirmation**; otherwise the same two commands ask once. The amended
       cases go into the PR body (`Frozen cases`). The end-of-pass message gives the PR URL and, for
       a stacked pass, the merge order. Closing (board/story `Done`, worktree/branch clean-up,
       `/loop:tracks` recompute) is run by the **closing check** below.
     - **`4bis-local` (no remote)**: today's flow unchanged (rebase, gates re-run, amended cases with
       hunks, merge go-ahead, clean-up), then `python3 .claude/hooks/loop-record.py --clear`.
     Rules `:287-289` rewritten accordingly (fixes F1): "Never push or open a PR without an explicit
     go-ahead" becomes "the pass's own push and PR follow `4bis-PR`; any other push or PR needs an
     explicit go-ahead". The main tree stays on `feat/<slug>` after `4bis-PR` (no `git switch`: the
     board line and story status committed with the pass must stay visible). The **Output** template (`:269-272`, V10) prints, on `4bis-PR`, `PR: <url> — awaiting
     merge` and `Board: <feature> stays IN LOOP until the PR merges`.
   - **`awaiting-merge` has readers** (fixes F2):
     - `.claude/commands/handoff/codex.md:37`: the template's phase list gains `awaiting-merge`
       (`research | interface | plan | execute | review | ship | awaiting-merge`), with `pr: <url>`.
     - `commands/loop/orchestrate.md` Phase 0 step 2: `awaiting-merge` → print this pass's closing-check
       result (step 0 already ran it) and **stop**: no phase runs; `closable` already closed it.
     - `.claude/hooks/next-feature-on-clear.py`: an `IN LOOP` line whose main-tree handoff reads
       `phase: awaiting-merge` is **not** an interrupted feature: it is listed in the note as
       "awaiting PR merge: <name>", and the topmost `READY` line is proposed (LP49).
     - `commands/loop/product.md:294` (`IN LOOP` = a session holds it, **or its PR awaits merge**) and
       `:296` (the closing check writes `SHIPPED` and `BLOCKED` — F5).
   - **Closing check** (fixes N2), in `commands/loop/orchestrate.md` Phase 0 as a new step 0 and in
     `commands/loop/tracks.md`'s opening step: for each `docs/work/*/handoff.md` with
     `phase: awaiting-merge` (main tree and worktrees), run
     `.claude/scripts/loop-pr-state.sh --chain <its branch>`; `closable` → run ship step 5's closing
     (story `Done`, board `SHIPPED`, brief, worktree/branch clean-up, handoff `phase: shipped`) and say
     so; `closed` → board `BLOCKED` with "PR closed unmerged", story `Approved`; `orphaned:<b>` → say
     the commits never reached the default branch and stop on it; `open`/`stacked`/`unknown`/`none` →
     one line each, nothing moved. Then, if HEAD is the branch of a pass still `open` or `stacked`,
     it says in one line that the new pass will **stack** on it (its PR targets that branch, F13) —
     announced, never silent (V7).
   - `agents/github.md` (fixes N4): the pass's push and PR **command lines** become exactly the
     hook's forms — `git push -u origin <branch>` and `gh pr create --repo <owner/repo> --base
     <recorded base> --head <branch> --title "<title>" --body-file docs/work/<slug>/pr-body.md`
     (`github.md:84`, `:153` rewritten; owner/repo and base read from `.claude/.loop-record.json` or,
     without one, from `gh repo view` and the plan's `Base:`); description and validation gate — the
     pass's branch push and its PR run without asking when the hook allows them; everything else as
     today. **Method step 4 and step 5's last sentence** (`github.md:149`, `:154`, fixes F1): "draft
     the message, show it, ask, then run" and "Show the title + body first" become: for the pass's
     own push and PR, run the exact forms and report the URL — the hook asks when it must; any other
     remote action keeps "show it, ask, then run". **Merging a track back, small-ticket paragraph**
     (`github.md:192-196`, F6): with a remote, push `feat/small-<name>` and open its PR on `Base`
     (asks once, no record); without one, today's `merge --ff-only` on the user's go. PR template
     gains, after
     `Screenshots`, in order: `Frozen cases` (each `amended` with its hunk), `Open questions`
     (answers taken), `Review` (surviving findings), `Gates`; the test plan linked by path; sent with
     `--body-file`. No harness attribution (the hook denies it).
   - `commands/loop/small.md` (fork with explicit base; PR flow with one ask, N3),
     `commands/loop/tracks.md` (fork with explicit base; the `feat/, fix/, chore/` prose at `:145-146`
     reworded to the `feat/<track-slug>` the fork uses; merge-gated → PR-gated; closing check first,
     recompute after `closable`).
   - `.claude/guides/review/tests.md` (+ `tests-python.md`): an unfrozen case whose diff does not
     match its recorded new title, or removes an assertion beyond it → Critical; a changed frozen case
     with no row and no `amended` line → Critical.
   - `.claude/guides/orchestrate.md`: V5 rationale (server barrier vs agent code with the user's
     credentials) and the known limits (bypass actors, stale barrier, agent code via allowed gate
     commands can write any file — same class as `.tdd-red`).
   - `commands/kit/doctor.md`: the widened protection check.
9. **Docs**: `docs/Claude_Workflows.md` (146-147, 152-154, 177-178, 333-342, 395-400, 639-642,
   698-699, 741 — `git push`/`gh pr` stay, K1), `docs/specs/fast-lane.md` D4 marked superseded for
   loop passes, `small-lane.md:3` and `light-permissions.md` cross-refs to V5/V10, `docs/ADAPTATION.md`
   guard-list section if it lists denied paths.
10. **Full suites**, then **Refactor** under a green suite, no case edited.

## Parallel lots
none — fully sequential (steps 1-5 share `hook-guarded.sh`, the record format and `test-hooks.sh`;
steps 7-9 share prompt contracts).

## Track isolation
- Worktree: none, single track on `audit/slim`.
- Shared foundations touched: hooks, `settings.json`, `install.sh`, `hook-guarded.sh` — no other
  pass runs in parallel until this one is committed.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/hook-guarded.sh` | Edit | denied record path, why-text, api 9 |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | text + fallback clauses, exec deny |
| `.claude/hooks/loop-record.py` | Create | record hook (Pre/Post AskUserQuestion, Post Bash, --clear) |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | `record_allow` |
| `.claude/hooks/protect-files.sh` | Edit | `unfrozen_record_rows` |
| `.claude/hooks/tdd-freeze-tests.sh` | Edit | rows mode, per-case check, deny texts |
| `addons/fastapi/hooks/tdd_py_lib.py`, `tdd-freeze-tests-py.py` | Edit | same, Python |
| `.claude/hooks/kit-doctor.py` | Edit | RUNTIME_PATHS, protection check |
| `.claude/scripts/loop-pr-state.sh` | Create | closing rule |
| `.claude/scripts/case-hash.sh` | Create | row digest at the plan gate |
| `.claude/settings.json`, `install.sh` (incl. `PROMPT_ALLOWS` `:380`), `.gitignore` | Edit | wiring, 3 allows (`loop-record.py --clear`, `loop-pr-state.sh *`, `case-hash.sh *`), core filter, ignore/prune |
| `.claude/hooks/next-feature-on-clear.py`, `.claude/commands/handoff/codex.md`, `.claude/commands/loop/product.md` | Edit | `awaiting-merge` readers (F2, F5) |
| `.claude/hooks/test-hooks.sh`, `fixtures/**`, `fixtures/_harness/git-guard.jsonl` | Edit | LP, G21 |
| `.claude/hooks/test-kit-doctor.sh`, `test-install.sh`, `test-workflow-contracts.sh` | Edit | KD, IN, PK |
| `.claude/commands/loop/{plan,orchestrate,ship,small,tracks}.md`, `commands/kit/doctor.md` | Edit | prompts |
| `.claude/agents/github.md`, `.claude/agents/implementer.md`, `.claude/guides/review/tests.md`, `tests-python.md`, `.claude/guides/orchestrate.md` | Edit | prompts |
| `docs/Claude_Workflows.md`, `docs/specs/fast-lane.md`, `small-lane.md`, `light-permissions.md`, `docs/ADAPTATION.md` | Edit | docs |

## Contracts
- Record JSON v1 and its validity rule (answer 3). Writer: `loop-record.py` only. Readers:
  `enforce-git-workflow.sh`, `protect-files.sh`, the two freeze hooks. Unknown version → missing.
- Plan-gate question text (the grammar the hook parses), header `Plan gate`, options `go`, `amend`:
  ```
  Plan go — docs/work/<slug>/plan.md
  Frozen cases to amend:
  <path> | <id> | <sha256 hex of the new title>
  ```
  or `Frozen cases to amend:` then `none`.
- Row hash: `sha256` of the new title text as the test runner sees it (TS: the string value of the
  first argument of `it(`/`test(`, a plain-quoted literal — a title with an escape or a template
  literal, or a title holding `'`, is refused in rows mode; Python: the `def` name), UTF-8, no newline — produced at the gate
  by `case-hash.sh`, recomputed by the freeze hooks.
- `loop-pr-state.sh` output vocabulary (step 6).

## Test plan (gate — validated by the user before EXECUTE)
Main behaviour first, business rules next, edge cases last. "rec" = a valid record fixture written by
the test setup (the test writes it, the hooks under test only read it); "main" = a main-thread input
(no `agent_id`/`agent_type`). Hash literals: `sha256("U2 returns err on empty input")` =
`9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5`;
`sha256("test_b2_returns_err_on_empty")` =
`e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b` (computed once by hand, pinned).

### Step 1 — guard list (test-hooks.sh, block LP)
**Core behaviour**
- [ ] LP1 A Write and an Edit of `.claude/.loop-record.json` are denied, with the record's own reason.
- [ ] LP2 `echo x > .claude/.loop-record.json`, `cp /tmp/a .claude/.loop-record.json`,
      `rm .claude/.loop-record.json` are denied.
**Business rules**
- [ ] LP3 `python3 .claude/hooks/loop-record.py < /tmp/x.json` and
      `bash -c 'python3 .claude/hooks/loop-record.py'` are denied;
      `python3 .claude/hooks/loop-record.py --clear` is not denied by this rule.
**Edge cases**
- [ ] LP4 The parse-failure fallback denies an unparsable command naming `.claude/.loop-record.json`.

### Step 2 — record hook (test-hooks.sh, block LP; inputs are spike-shaped JSON)
**Core behaviour**
- [ ] LP5 main, header `Plan gate`, first line `Plan go — docs/work/s1/plan.md` (file exists), answer
      `go`, block `none`, HEAD on `audit/x`: the record holds slug `s1`, branch `feat/s1`, base
      `audit/x`, its sha, `rows: []`.
- [ ] LP6 Same with row `src/a/x.utils.test.ts | U2 | 9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5`:
      the stored row is that path, id `U2` and that digest.
**Business rules**
- [ ] LP7 The same input with `agent_id` set, and with `agent_type` set: no record.
- [ ] LP8 Answer `amend`, `go ` (trailing space), `Go`, a free text: no record.
- [ ] LP9 Header `Plan`, or a first line naming a plan that does not exist: no record.
- [ ] LP10 A second valid go for `s2` replaces the first: one record, slug `s2`, the `s1` rows gone.
- [ ] LP11 Branch made exactly as the kit makes it — `git worktree add <wt> -b feat/s1 audit/x`, hook
      `cwd` = `<wt>` — → base `audit/x`, base_sha = merge-base, record in `<wt>/.claude/`.
- [ ] LP12 `git worktree add <wt> -b feat/s1` (no start point: reflog `Created from HEAD`), a branch
      created from a sha, a detached HEAD → no record.
- [ ] LP13 A malformed row (missing digest, a 63-hex digest, a range `U2-U4`, id `X2`) →
      no record, and an existing record is left as it was.
- [ ] LP14 A PreToolUse `Plan gate` question carrying `answers` is denied; one without `answers`, and a
      non-gate question carrying `answers`, get no decision; unparsable stdin containing `Plan gate` →
      deny, without it → no decision.
- [ ] LP15 PostToolUse Bash, exact PR form, stdout holding `https://github.com/o/r/pull/7` (record repo
      `o/r`) → record gone; stdout without a PR URL, another repo's URL, or another command → kept.
- [ ] LP16 gh shim: rules with all three types → `barrier: true`; missing `deletion`, a 403, gh absent,
      a gh call past the budget → `barrier: false` (record still written).
- [ ] LP17 `base_ok`: base == default → true; base on the remote with `[]` rules → true; base with a
      rule, or absent from the remote → false.
**Edge cases**
- [ ] LP18 `loop-record.py --clear` removes the tree's record; with none, exits 0.
- [ ] LP19 Garbage stdin, empty stdin, a non-object JSON on the Post paths → exit 0, nothing written.
- [ ] LP20 Validity: a record for `feat/s1` read while HEAD is `feat/s2`, or HEAD on `audit/x` whose
      history no longer contains `base_sha`, is treated as missing by every reader (checked through the
      git hook: ask).

### Step 3 — git hook (fixtures/_harness/git-guard.jsonl, block G21; tmp repo with a bare `origin`)
**Core behaviour**
- [ ] G21.001 rec (barrier, branch = HEAD = `feat/s1`, not on origin): `git push -u origin feat/s1` → allow.
- [ ] G21.002 rec, base_ok: `gh pr create --repo o/r --base audit/x --head feat/s1 --title "t" --body-file docs/work/s1/pr-body.md` → allow.
**Business rules** (each → ask with today's reason)
- [ ] G21.003 no record; G21.004 `barrier: false` (push); G21.005 record branch `feat/s2`; G21.006 HEAD on another branch;
      G21.039 `barrier: false` (PR).
- [ ] G21.007 `git push -u origin HEAD:main`; G21.008 `+feat/s1`; G21.009 `feat/s1:main`; G21.010 `--tags`;
      G21.011 `--mirror`; G21.012 `--delete`; G21.013 `--force-with-lease` (force reason);
      G21.014 `--no-verify`; G21.015 `git push origin feat/s1` (no `-u`); G21.016 `git -C . push -u origin feat/s1`;
      G21.017 `GIT_SSH_COMMAND=x git push -u origin feat/s1`; G21.018 `git push -u origin feat/s1 && echo`.
- [ ] G21.019 `remote.origin.push`; G21.020 `url.x.pushInsteadOf`; G21.021 `push.followTags`;
      G21.022 `core.sshCommand`; G21.023 `remote.origin.pushurl` set in a file pulled by `include.path`;
      G21.040 `remote.origin.mirror`; G21.041 `remote.origin.receivepack`; G21.042 `push.pushOption`.
- [ ] G21.024 a tag `feat/s1` exists; G21.025 `feat/s1` already on origin (second push).
- [ ] G21.026 PR `--base main` while the record base is `audit/x`; G21.027 `--repo other/r`; G21.028 `--web`
      added; G21.029 `base_ok: false`; G21.030 body file missing; G21.031 `--body "x"` instead of
      `--body-file`; G21.032 options in another order; G21.033 a `$` in the title.
- [ ] G21.034 `Base:` edited in `plan.md` to `main`, record base `audit/x`, PR `--base main` → ask (F13).
- [ ] G21.035 with a valid record: `gh pr merge`, `gh pr edit`, `gh pr close`, `git push --force`,
      `gh release create` → ask.
**Edge cases**
- [ ] G21.036 the body file holding `Co-Authored-By` → deny (attribution), record valid.
- [ ] G21.037 `ls-remote` timing out (origin `ext::sleep 30` with `protocol.ext.allow=always` in the repo
      config) → ask within the budget.
- [ ] G21.038 an unreadable record (bad JSON, version 2) → ask.
- [ ] G21.043 `prevent-destructive-commands.sh` on G21.001's and G21.002's commands → no decision.

Execution notes (2026-11-19, no case changed): G21.035 and G21.043 are split into one row per command
(`G21.035.2-.5`, `G21.043.2`), G21.038's version-2 record is `G21.038.2`. LP20's first half is covered by G21.005
(record for another branch) and G21.006 (HEAD on another branch): the push/PR allow requires HEAD ==
the record branch, so the `base_sha` clause never allows there. LP20's second half (`HEAD on base
and base_sha an ancestor`) is covered by LP30.3 (protect-files), LP30.5 (TS freeze) and LP30.7 (py
freeze), each with a valid-record companion (LP30.2, LP30.4, LP30.6) — added at review round 1 (T1). The `ls-remote` check gets 3 s, not
5 (the git hook's own timeout is 5 s), and `remote.origin.uploadpack` joins the refused keys (it runs
on `ls-remote`, like `receivepack` on push). The G21 harness unsets the suite's `GIT_CONFIG_GLOBAL` /
`GIT_CONFIG_NOSYSTEM` for the hook (the allow refuses any `GIT_CONFIG*`), HOME empty instead.

### Step 4 — unfreeze allow (test-hooks.sh, `unfrozen_case` rows, block LP)
**Core behaviour**
- [ ] LP21 rec row `(src/a/x.utils.test.ts, U2)`: an Edit adding `src/a/x.utils.test.ts  # U2: reason` → pass.
- [ ] LP22 Two rows on two paths, one Edit adding both lines → pass.
- [ ] LP23 `.tdd-unfrozen` absent: a Write creating it with one row-backed line → pass.
**Business rules** (→ ask)
- [ ] LP24 the id is a row on another path; LP25 an id with no row; LP26 an implementation path
      (`src/a/x.utils.ts  # U2: r`) even with a row naming it; LP27 no record; LP28 a line without ids.
- [ ] LP29 One Edit removing a line and adding a record-backed line → pass; removing one and adding an
      unbacked one → ask.
- [ ] LP30 A record of another pass (branch `feat/s9`, HEAD on `feat/s1`) holding the matching row → ask.
**Edge cases**
- [ ] LP31 Existing P1.01-P2.08 rows unchanged (removal-only allow).
- [ ] LP32 `U2, U5` on one line, both rows → pass; one of them missing → ask.

### Step 5 — freeze rows mode (fixtures/tdd-freeze-tests.sh + Python RV block)
Setup: `src/a/x.utils.test.ts` with cases U1, U2, U3 frozen; `.tdd-unfrozen` lists it with `# U2`;
rec row `(src/a/x.utils.test.ts, U2, 9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5)`.
**Core behaviour**
- [ ] LP33 An Edit changing case U2's title to `U2 returns err on empty input` and its body → pass.
**Business rules** (→ deny, reason naming the case id, expected and actual hash)
- [ ] LP34 the new title is `U2 returns err on empty`; LP35 the Edit also changes U3's body;
      LP36 `old_string` starts inside U1's body and ends at U2's title, changing U1's assertion and
      U2's title to the recorded one; LP37 a Write rewriting the whole file.
**Business rules** (→ pass, frozen-file rights kept)
- [ ] LP38 a byte-identical Write of the current file; LP39 a pure insertion of a new case `U9 …`
      after U3.
- [ ] LP40 `.tdd-unfrozen` also lists the path with `# U5` (batch-approved), file has U5, no row for
      U5: an Edit of U5's body → pass; an Edit of U3 (neither) → deny.
**Edge cases**
- [ ] LP41 Python: `def test_b2_returns_err_on_empty` with row hash
      `e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b` → pass; another name → deny;
      an edit spanning into `test_b1_…` → deny.
- [ ] LP42 Path unfrozen, no row for it in the record (or no record) → today's path exemption: any
      Edit passes.
- [ ] LP43 The three `.tdd-unfrozen` parsers still agree on both spellings (with and without `#`).
- [ ] LP44 The TS and Python freeze deny texts name the queue and the single batch stop, and do not
      contain "confirms it at the merge".

Execution notes (2026-11-19, no case changed): the cases live in test-hooks.sh
(`run_loop_to_pr_step5_cases`, in `--lp-only`), not in fixtures/; the Python ones run the addon hook
like the RV block. LP50 (title forms) is run here, it reads the same code. Ids split by sub-check:
LP34.2, LP40.2, LP41.2-.4, LP42.2, LP43 require-red, LP43.py, LP44.2, LP44.py, LP50.2-.3. RED: 15/149
failing, exactly the deny cases. Python id = `test_<letter><digits>_` upper-cased, title = the def
name. Beyond the plan, both hooks also refuse in rows mode: `replace_all`, non-blank text outside every
case (old or new side), a written case whose id is not among the replaced ones, a row case that stops
being exactly one case. `implementer.md:46` and `orchestrate.md:272` deny-text echoes move to step 8
(PK28 covers them).

### Step 6 — closing script (test-hooks.sh, gh shim, block LP)
- [ ] LP45 MERGED into the default branch → `closable` (merge, squash and rebase fixtures alike).
- [ ] LP46 MERGED into `feat/a` → `stacked:feat/a`; `--chain` with `feat/a` MERGED into the default
      later → `closable`; `feat/a` OPEN → `open`; `feat/a` merged **before** the child → `orphaned:feat/a`.
- [ ] LP47 OPEN → `open`; CLOSED unmerged → `closed`; no PR → `none`; gh failing → `unknown`.

### Hash producer (test-hooks.sh, block LP)
- [ ] LP48 `.claude/scripts/case-hash.sh "U2 returns err on empty input"` prints exactly
      `9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5`; no argument or two
      arguments → exit 2, nothing printed on stdout; it creates no file (tree unchanged).

### Rows-mode title forms and the on-clear hook (test-hooks.sh, block LP)
- [ ] LP49 Board with an `IN LOOP` line whose main-tree handoff reads `phase: awaiting-merge` and a
      `READY` line below: `next-feature-on-clear.py` proposes the `READY` line and names the other as
      "awaiting PR merge"; with `phase: execute` it still proposes the interrupted feature.
- [ ] LP50 Rows mode (step 5 setup): an Edit giving U2 the title as a template literal
      `` `U2 returns err on empty input` ``, with an escaped quote, or holding `'` (`"U2 it's empty"`)
      → deny, even when the source text hashes to the row.

### kit-doctor / install (test-kit-doctor.sh KD, test-install.sh IN)
- [ ] KD24 protection check reads the default branch from `gh repo view`, not `main`.
- [ ] KD25 a missing rule type is reported (INFO) by name; all three → silent.
- [ ] KD26 `loop-record.py` wired → no "mute" finding; `.claude/.loop-record.json` known runtime path.
- [ ] IN59 core-mode install keeps the three `loop-record.py` handlers and the three new allows
      (`python3 .claude/hooks/loop-record.py --clear`, `.claude/scripts/loop-pr-state.sh *`,
      `.claude/scripts/case-hash.sh *`), in `settings.json` and in `PROMPT_ALLOWS`; react mode too.
- [ ] IN60 an installed project denies a Write to `.claude/hooks/loop-record.py` (kit-code tier).
- [ ] IN61 a `.claude/.loop-record.json` in the kit tree is not copied into the target, and the target's
      `.gitignore` gains it.

### Contracts (test-workflow-contracts.sh, block PK — written and run red before step 8)
- [ ] PK25 `github.md` no longer says it always asks for push/PR; still asks for merge, force, issue, comment.
- [ ] PK26 `ship.md` `4bis-PR` has no local merge/rebase, no "je pousse", no force-push; closes on
      `MERGED` + `baseRefName` via `loop-pr-state.sh --chain`.
- [ ] PK27 `plan.md` step 7 asks every pipeline through `AskUserQuestion` with header `Plan gate`, the
      `Plan go — ` line and the `Frozen cases to amend:` block.
- [ ] PK28 `orchestrate.md` Phase 4 queues corrections in `unfreeze-queue.md` and stops once; no
      per-correction confirmation; Phase 0.5 uses `EnterWorktree` with `path`.
- [ ] PK29 `tests.md` names the two Critical unfreeze cases.
- [ ] PK30 K1 still holds (`git push`, `gh pr` in Claude_Workflows.md).
- [ ] PK31 `ship.md` keeps a `4bis-local` subsection (no remote) with the rebase, the merge go-ahead and
      `loop-record.py --clear`.
- [ ] PK32 `github.md`'s PR template lists `Frozen cases`, `Open questions`, `Review`, `Gates` in that
      order after `Screenshots`, and `--body-file`.
- [ ] PK33 `tracks.md`, `small.md` and `orchestrate.md` fork with `-b feat/<…> <base>` (an explicit
      start point); `implementer.md` no longer says "confirms it at the merge".
- [ ] PK34 `ship.md` outside `4bis-local` no longer contains "waits for the user's explicit
      go-ahead" nor "in the merge presentation (step 4bis, which every pass reaches)"; step 2 sends the
      amended cases to the PR body.
- [ ] PK35 `orchestrate.md` Phase 0 step 0 and `tracks.md`'s opening step run
      `loop-pr-state.sh --chain` on `phase: awaiting-merge` handoffs; `ship.md` step 5 moves story/board
      on `4bis-PR` only on `closable`.
- [ ] PK36 `github.md` and `ship.md` `4bis-PR` carry the literal forms `git push -u origin <branch>` and
      `gh pr create --repo <owner/repo> --base <recorded base> --head <branch> --title "<title>"
      --body-file docs/work/<slug>/pr-body.md`; `github.md` no longer has a `gh pr create` line without
      `--repo`.
- [ ] PK37 `ship.md`'s Small-ticket integration and `github.md`'s small-ticket paragraph open a PR when
      a remote exists and keep `merge --ff-only` only for the no-remote case.
- [ ] PK38 `ship.md` outside `4bis-local` and `github.md` no longer contain "Never push or open a PR
      without an explicit go-ahead", "show it, ask, then run" for the pass's own push/PR, nor "Show the
      title + body first"; `github.md` still says "show it, ask, then run" for other remote actions.
- [ ] PK39 `handoff/codex.md`'s phase list ends with `awaiting-merge`; `orchestrate.md` Phase 0 step 2
      has an `` `awaiting-merge` → `` branch that stops; `product.md` names the closing check as a
      `SHIPPED` writer.

### Added at review round 1 (pure insertions, no existing case changed)
- [x] LP33.2/LP33.3 (TS) and LP41.5/LP41.6 (py): rows mode in a worktree with `CLAUDE_PROJECT_DIR` = main tree reads the edited file's tree (C1).
- [x] LP24.2: a row-backed `.tdd-unfrozen` line for a path that is not an existing file of the tree → ask (C2a).
- [x] LP50.6/LP50.7/LP50.8: `/* */` and regex quote in a row case body cannot swallow the next case; an unclosed span refuses (C3).
- [x] LP30.3-LP30.7: record on base with `base_sha` not an ancestor → treated as missing, protect-files / TS / py (T1).
- [x] LP50.4/LP50.5: escape and `'` titles whose digest is the row still deny, needle `not a plain-quoted literal` (T2).
- [x] G21.037.2: the hanging-origin ask returns within a 7 s cap (T3).
- [x] IN62: a target already carrying the kit block gains the record line once (SH1).
- [x] D21-D21.4, D22-D22.3 (test-small-lane.sh): a small PR MERGED counts merged; an awaiting-merge row only waits while HEAD is its branch (SH2).
- [x] PK40-PK43.2: step 0 stacks with no switch, closable switches to the default branch first, 4bis-local `ExitWorktree keep`, small `--status` reads the PR (C4, C5, C6, SH2).

### Added at review round 2 (pure insertions, no existing case changed)
- [x] LP24.3: an existing file whose line is backed only by another path's row → ask (T4; fails under the path-blind mutation).
- [x] LP51/LP51.2: a nested repo's `.claude/.tdd-unfrozen` line does not unfreeze, TS and py (N1).
- [x] LP52 (a)/LP52.2 (e)/LP52.3 (g): an ambiguous case (possible regex `/`, `\/`, unclosed span) before or in the edit refuses rows mode; LP52.4: an ambiguous case after the edit does not (C3b, N2).
- [x] PK44-PK44.7: the closing-check switch + sync apply to the main tree's handoff only, worktree handoffs skip them, default branch from `gh repo view --json defaultBranchRef` (N3).

### Added at review round 3 (pure insertions, no existing case changed)
- [x] LP53/LP53.2: a division, `<F />` and `</p>` in a row case no longer make it ambiguous (pass on a row Edit); LP53.3/LP53.4: a `/` after `=>` or `return` still does (deny) (M1).
- [x] LP54: the ambiguity deny names `loop-record.py --clear`; LP54.2: a `.tdd-unfrozen` line `<path>  # U2!: <reason>` lifts nothing, the ambiguous case (regex holding quotes) stays refused (amended round 6, U2 U3); LP54.3: that marker line still asks (protect-files); LP54.4: it never lifts a case that does not close (M1).
- [x] LP55: a `.tsx` with `render(<p>L'adresse</p>)` in row U2 and `// the user's input` in U3: the Edit of U3 is denied, a quote crossing a newline marks the case ambiguous (S2).
- [x] LP56/LP56.2: a nested repo with its own valid record, rows and a listed extra id gets the frozen deny, TS and py (TM1; red under mutants MA/PA, tree test always true).
- [x] LP57/LP57.2: a worktree whose own list names a file with no record rows gets the frozen deny, TS and py (TM1; red under mutants MB/PB, worktree list as whole-file exemption).
- [x] LP58/LP58.2: after `loop-record.py --clear` a row-backed line no longer exempts the file whole, TS and py; LP58.3: that line is commented out, a plain line stays (S3).
- [x] PK45-PK45.6: a worktree handoff's step 5 runs in the main tree on the synced default branch (else report and stop); `--clear` and `phase: shipped` come before the worktree removal, orchestrate.md and tracks.md (M2).

### Added at review round 4 (pure insertions, no existing case changed)
- [x] LP59/LP59.2/LP59.3: a case whose span holds another `it(` (raw text), or whose brackets do not nest, is ambiguous and no `U2!` marker lifts it; liftA1 shape, liftB shape (U2 last, `toThrow(/\(/)` + `beforeEach`); LP59.3: a string of U2 holding `it(` no longer makes it ambiguous, the Edit of non-listed U3 is denied as not listed (amended round 5, U1).
- [x] LP60/LP60.2: an unbalanced `(` in JSX text of a row case of a `.tsx` is refused with or without the marker, Edit of U3 and Edit adding a describe-level `beforeEach` (S4).
- [x] LP58.4/LP58.5: `--clear` comments out the `# U2!:` marker line as well as the plain one, TS and py freeze deny (N2).
- [x] LP58.6/LP58.7: the PR-url drop comments the row-backed line out, the plain line stays, Edit of U3 denied (T8; red when the drop becomes `os.unlink(target)`).
- [x] LP61-LP61.4, LP61.6: backtick regex after `=`, line start, `,`, `:`, and `"` in JSX text of a `.tsx` (the closure's shapes); LP61.5 (a `"` string crossing a line) and LP61.7-LP61.10 (plain regex after the four tokens) are the cases red under the drop-mutants: with the N1 closure a swallowed `it(` denies the backtick and JSX shapes anyway (T5).

### Added at review round 5 (pure insertions, no existing case changed)
- [x] LP62-LP62.8: a `(` in a title, string or comment above row U2, a JSX `[`, and `U1!, U2!` listed no longer refuse an Edit of U2 (FP; the raw `it(`/`test(` check and the bracket-nesting check are gone); LP62.8: a JSX `1)` in U1 is refused by the round-6 two-direction rule, accepted false positive, needle `loop-record.py --clear` (amended round 6, U4).
- [x] LP63 (lifted U2 with `L'adresse`, Edit of a trailing beforeEach), LP63.2 (lifted, Edit appends a regex holding `'` plus a beforeEach), LP63.3 (.tsx, `# U2: r` only, `<kbd>` + backtick): a case whose character span runs past its indentation span is refused, needle `loop-record.py --clear` (amended round 6, U5-U7) (SC1; red under the mutant that drops the indentation comparison).
- [x] LP64 (E: lifted U2, U3 `it.concurrent.each`), LP64.2 (.tsx backtick U2, `it.concurrent.each` U3, no lift), LP64.3 (lifted U2, `` it.each`table` `` U3): deny; LP64.4/LP64.5: a benign member-chain table and a benign tagged table with U3 listed are cases, the Edit passes (N1p; LP64.4/LP64.5 red under the one-member CALL mutant).
- [x] LP65/LP65.2: the liftA1 and liftB shapes assert `loop-record.py --clear` (amended round 6, U8 U9) and not `lifts it with` (TQ1; LP63-LP63.3 and LP65/LP65.2 red under the mutant that deletes the never-liftable text).

### Added at review round 6 (pure insertions, no existing case changed)
- [x] LP66/LP66.2 (NC): the Edit de-indents or tab-indents the call line of U2 and appends a beforeEach with a lone backtick; the character span must end on the last non-blank line of the indentation span, else ambiguous (deny). LP66.3-LP66.6: controls (timeout number, split call with options object, chained expect, wrapped arrow) pass. Red under the mutant that drops the line agreement.
- [x] LP67/LP67.2 (NA): a stray backtick in the first table of an `it.each` swallows describe-level code up to a later `.each` row case; a first-call span holding another it/test call is ambiguous (Edit of the beforeEach and of the frozen U2 body deny). LP67.3/LP67.4: plain multi-line and tagged tables pass. Red under the mutant that drops the first-call check.
- [x] LP68/LP68.2 (TQE): NL and NL10 (.tsx, `# U2: r` only, single-line U2 with a backtick) deny; LP68 red under M04 and M06, LP68.2 under M04 and M09.
- [x] LP69 (NB, accepted false positive, documented): a template literal with a column-0 line in U1 makes U1 ambiguous and refuses an Edit of U2 below it, with the `--clear` text.
- [x] LP70/LP70.2 (lift removed): a `U2!` line is parsed as the id U2 and lifts nothing; the deny names `python3 .claude/hooks/loop-record.py --clear`, never a marker.

### Test-after
- One live check at the end of EXECUTE (manual, interactive): a `Plan gate`-shaped question in this
  session writes the record in this tree; a pre-filled one is refused (LP14 in vivo).

## Gate amendments to validate (written into `## Gate` on the go)
- Existing contract needles that the rewrite changes (amended, not deleted): any `ship.md` /
  `github.md` needle asserting the local merge or the push go-ahead (`test-workflow-contracts.sh`
  470-471, 489-529, 834-835, 418-420) is rewritten to the PR wording; so are the freeze deny-text
  needles 350-355 and W12's 450-451 under step 5's rewrite; the 4bis needles 348-349, 351-353 and
  401 (`4bis.1`..`4bis.3`) under the 4bis split; and the phase-list needles 218-223 (the template
  gains `awaiting-merge`); listed by id in `## Gate` as each is touched.

## Vigilance (carried from research)
- `record_allow` sits after every deny and before the floor regexes and `grammar_decide`.
- The allow never fires on any shape the floor exists for (G21.007-G21.023, G21.035, G21.040-042).
- Subagent marker = `agent_id` **or** `agent_type` present (either one blocks the record).
- `refs/heads` vs `refs/tags` checked with `show-ref --verify`, never `kit_resolves`.
- Push config read in all scopes with includes resolved.
- `.tdd-unfrozen` record-backed allow refuses every non-test path (it would lift the RED rule).
- Rows mode keeps re-save and insertion rights; touched cases come from the current file's spans.
- Three `.tdd-unfrozen` parsers identical on paths; Python freeze gets the same rows mode.
- Every hard-coded `.tdd-red` clause in prevent-destructive extended; `cwk_guard_denied_why` branch added.
- The record hook's Post paths fail closed (write nothing); its Pre path denies a pre-filled or
  unparsable `Plan gate` question only.
- Known limit, not a guarantee: agent code run through an allowed gate command (`pnpm test:run`) can
  write any file, the record included — same class as `.tdd-red`/`.tdd-unfrozen`, spec OUT.
- Record located per tree from the hook input `cwd`, never `$CLAUDE_PROJECT_DIR`. Rows mode reads the
  record **and** the `.tdd-unfrozen` of the edited file's tree; the path exemption keeps today's
  `$CLAUDE_PROJECT_DIR` read (V2).
- The barrier sees rulesets only: classic protection reads `barrier: false` (safe ask); a
  classic-protected feature base may read `base_ok: true` (known limit, guide).
- The driving session's `git worktree add` asks once (not allow-listed); `ExitWorktree` does not
  remove a tree entered by `path`, so `4bis-local`'s clean-up uses `ExitWorktree keep` then
  `git worktree remove`.
- Known limit: handoffs are gitignored and per machine, so a pass shipped on one machine is closed by
  the closing check only on that machine (V11).
- A `Plan gate` go answered next to a free-text contract amendment in the same call still writes the
  record; the amendment re-enters an earlier phase, and the next go replaces the record.
- PR body: no harness attribution (deny), loop-PR sections in order, `--body-file`.
- The removal-only `.tdd-unfrozen` allow keeps working.
- kit-doctor: hook wired, `+x`, runtime path listed; protection check reads the default branch.
- K1 and ship.md negative needles 354, 514 hold.
- Network only in the record hook (10 s) and one `ls-remote` (5 s) in the git hook; timeouts → ask.

## Acceptance criteria (carried from the entry artifact)
- [ ] Server rule present: commit, push of `<B>` and `gh pr create` run with no ask and no chat confirmation; every refused shape of F4/F5 asks or is denied; without the server rule push + PR ask once; no remote: local flow unchanged.
- [ ] `ship.md` 4bis opens a PR instead of merging locally; board/story/worktree close on `MERGED` with `baseRefName` = the default branch; the PR body follows the loop-PR template, sent with `--body-file`.
- [ ] F13: a stacked pass opens its PR on the hook-recorded base and closes when the chain reaches the default branch, on merge, squash or rebase.
- [ ] F8: the record is written by the hook only, from main-thread `go` answers; an agent write to it is denied; missing → today's asks.
- [ ] The test plan is validated in one stop for all layers; frozen cases amended by the plan are shown as hashed rows; their `.tdd-unfrozen` entries are written with no second ask only on matching rows, never for an implementation path (F12).
- [ ] Frozen-case corrections during EXECUTE reach the user as one batch, one stop, one `.tdd-unfrozen` write; a mismatched unfreeze is Critical at review.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Plan critic
- pass 1: completeness 74, quality 48 (`plan-critic-1.md`); verifier confirmed Q1-Q6, C1, C2 →
  route `rewrite` (`route-plan-1.json`), attempt 1/3. Rewrite 1: Q1 → answer 4 (explicit base +
  `EnterWorktree path`, LP11-LP12, PK33); Q2-Q4 → step 5 rows mode (LP35-LP40); Q5 → (rewrite 2:
  `case-hash.sh`, contract as written, LP48); Q6 → deny texts (LP44, PK33); C1 → `4bis-local` (PK31);
  C2 → PK32. Minors folded: C3 (validity, LP20, LP30), C4 (allow + PK31), C5 (G21.039-042, `gh pr
  close`), Q7 (Pre fails closed for the gate), Q8 (per-tree `cwd`), Q9 (G21.043), Q10 (includes
  resolved, `recursesubmodules`, `ext::` hang), Q11 (limit named), Q12 (IN61), Q13 (limits named,
  `orphaned`), Q14 (PK before prompts, literal digests), Q15 (LP23).
- pass 2: completeness 66, quality 74 (`plan-critic-2.md`); pass-1 findings all fixed. Verifier
  confirmed N1-N5, refuted N6 (forks already use `feat/<slug>`; prose reworded anyway) → route
  `rewrite` (`route-plan-2.json`), attempt 2/3. Rewrite 2: N1 → ship steps 2 and 4 (PK34); N2 → closing
  check in orchestrate Phase 0 / tracks + ship step 5 on `closable` (PK35); N4 → github.md exact
  command lines (PK36); N5 → amendment withdrawn, contract as written, `case-hash.sh` (LP48); N3 →
  `Plan critic, open` (arbitrate, proposed answer, PK37). Minors V2-V6 folded into Vigilance and Gate
  amendments; V1 accepted (an abandoned pass's record is replaced by the next go).
- pass 3: completeness 82, quality 78 (`plan-critic-3.md`); N1, N2, N4, N5 fixed. Verifier confirmed
  F1, F2 → route `blocked` (`route-plan-3.json`); `kit-attempts.py` exit 3: **BLOCKED — plan-critic
  failed 3x : F1**. User decision 2026-11-18: fix + targeted pass + plan gate; counter reset
  (attempts.json emptied). Fixes: F1 → `github.md:149`, `:154`, ship Rules `:287` (PK38); F2 →
  `awaiting-merge` readers: template, orchestrate step 2, `next-feature-on-clear.py`, `product.md`
  (LP49, PK39); F3 → 3 allows (IN59); F4 → LP50; F5 → `product.md:296`; F6 → github small paragraph
  (PK37); V7 → `git switch <base>` after `4bis-PR`; V8 → single-quoted argument; V9 → Gate
  amendments; V10 → Output template; V11 → known limit (Vigilance).
- targeted pass (after the reset): completeness 91, quality 80; F1-F6 fixed. New Q1 (Major,
  interpretation: the V7 `git switch <base>` drops the committed board/story state from the main
  tree) and Q2 (Minor: that switch asks) → **the switch is withdrawn**; V7 is answered by an announced
  stack in the closing check instead (stacking is F13's supported shape). Q3 (Minor: `'` refusal
  untested) → Contracts row + LP50. No surviving blocker; N3 stays under `Plan critic, open`.
- completeness: 91
- quality: 80
- surviving blockers: none

## Gate
- 2026-11-18 go (AskUserQuestion, header `Plan gate`, `Frozen cases to amend: none`)
- Contract: as written (`kit-attempts.py pass` on `contract`)
- Open questions → answers taken as printed in `## Proposed answers` 1-7 (spike-settled input shape;
  plan-gate go only; per-tree record replaced by each go; explicit-base forks + `EnterWorktree path`;
  barrier read once at the go; no ci.md change; this pass ships the current way).
- Plan critic, open → N3 accepted as proposed: `/loop:small` opens a PR when a remote exists, push and
  PR ask once; its no-ask path is deferred to `auto-mode.md` (`kit-attempts.py pass` on `plan-critic`).
- Contract-needle amendments accepted in principle (`## Gate amendments to validate`); each touched
  needle is listed here by id when EXECUTE edits it.
- amended 2026-11-19 KD1 (test-kit-doctor.sh, user's choice via AskUserQuestion): input
  `[{"type":"deletion"}]` → all three types `pull_request`, `non_fast_forward`, `deletion`; same
  expectation (no github-protection finding). Reason: KD25 makes a partial ruleset an INFO.
- amended 2026-11-19 HP-B2 (test-workflow-contracts.sh): `HP_WANT` gains
  `Bash(python3 .claude/hooks/loop-record.py --clear)`, `Bash(.claude/scripts/loop-pr-state.sh *)`,
  `Bash(.claude/scripts/case-hash.sh *)`; count 29 → 32. Reason: IN59 puts the three allows in
  `PROMPT_ALLOWS`, an exact-set contract.
- amended 2026-11-19 phase-list needle (test-workflow-contracts.sh:223, accepted in principle at the
  go): `TEMPLATE_PHASES` == `research | … | ship` → `research | … | ship | awaiting-merge`. Reason:
  F2, the handoff template gains the phase (its `pr:` on its own line).
- Not amended (step 8): every other ship/github/orchestrate needle still holds as written
  (`'### 4. Commit'` `amended`, `2. Present the branch` `amended`/`test hunk`, `the .tdd-unfrozen
  write asks the user`), kept verbatim in the rewrite.
- Not amended: the freeze deny-text needles (`The main thread records it`, `rewrite the plan line
  (same id)`, `the main thread adds one line`, 2× `this write will ask the user`) are kept verbatim
  in the step-5 texts.
- Review round 2, 2026-11-19 (AskUserQuestion, user's choice): C2a closure re-scoped to the
  protect-files ask (LP24.2, delivered); `loop-record.py` refusing a non-existing row path goes to
  follow-ups; LP6 not amended. C3b fixed the conservative way: a case where a `/` could open a
  regex literal is marked ambiguous, and an ambiguous case before or inside the edited range
  refuses rows mode (frozen deny); this also answers N2.
- Review round 2 fix batch, 2026-11-19: N1 → only rows-mode entry and listed ids read the edited
  file's tree list (project dir or `.claude/worktrees/<name>` only); the whole-file exemption and
  py `is_unfrozen` read `$CLAUDE_PROJECT_DIR` again (V2). C3b/N2 → ambiguous cases as above, those
  wholly after the edit do not refuse. N3 → main-tree qualifier. T4 → LP24.3. Full test-hooks.sh
  3174 green.
- Review round 3, 2026-11-20 (AskUserQuestion, header `M1`, user's choice (a)): the conservative
  C3b refusal gets an exit. `amb` is narrowed to positions where a `/` can open a regex literal
  (division, JSX `/>` and `new_string` cases no longer ambiguous); a real lift route (a marker line
  in the record/queue) lets a listed ambiguous case through rows mode, proved by an LP case that
  walks it to pass; S3 closed: `loop-record.py --clear` never turns a row-backed line into a
  whole-file exemption. Supersedes "the deny text names `--clear`" (option b, not taken).
- Review round 3 route, 2026-11-20 (AskUserQuestion, header `Tour 3`, user's choice): verifier
  confirmed M1 (regression) M2 S2 S3 TM1; route-review-3.json → fix-batch, `attempt: fail` NOT
  recorded (review stays 2/3): the (a) arbitration counts as a re-scoped closure, as in round 2. One
  fix batch for all five, each reproduced by a failing case first; round 4 re-reviews the fix diff
  only. R6-R9 → follow-ups.md.
- Review round 4 route, 2026-11-20 (AskUserQuestion, headers `Plafond` + `Lift`, user's choices):
  verifiers confirmed N1 (Critical, regression) S4 N2 T5 T8, refuted T9; route-review-4.json →
  fix-batch, `attempt: fail` NOT recorded (review stays 2/3). Lift contract: a case whose raw span
  text after its own `(` contains another `it(`/`test(` call start, or whose `(`/`[`/`{` nesting
  mismatches, is ambiguous and never lifted (both checks). One fix batch N1 S4 N2 T5 T8, each
  reproduced by a failing case first; round 5 re-reviews the fix diff (security, tests). M1p N3
  R10-R13 → follow-ups.md.
- Review round 5 route, 2026-11-20 (AskUserQuestion, header `Round 5`, user's choice: dual check,
  fail not recorded): verifier confirmed FP (Major, regression), SC1 (Major, pre-existing), N1p
  (Major, pre-existing), TQ1 → Minor; route-review-5.json → fix-batch, `attempt: fail` NOT recorded
  (review stays 2/3). Lift contract amended (supersedes round 4's two checks): the raw-text
  `it(`/`test(` check is dropped; each case gets two spans, the character-scanner span and an
  indentation span (the case ends at the first non-blank line at or below its call line's
  indentation); a case whose two spans disagree, or that does not close, is ambiguous and never
  lifted; the call-start pattern accepts any member chain (`it.concurrent.each(`) and a tagged table
  (`` it.each`…` ``). One fix batch FP SC1 N1p, each reproduced by a failing case first; round 6
  re-reviews the fix diff (security, tests). TQ1 R14 R15 → follow-ups.md.
- Round 6 fallback, 2026-11-20 (user, in chat): if round 6 still FAILs, split instead of another
  fix round — drop the `U2!` lift (an ambiguous case stays refused, the deny text names
  `loop-record.py --clear`), ship loop-to-pr without it, and file the span scanner (SC1, the
  lift) as its own pass in follow-ups.md.
- amended 2026-11-20 U1: LP59.3 `deny … ambiguous` (raw it( check) → `deny … neither a plan-gate row
  nor listed` (the round-5 amendment drops the raw check; verdict unchanged). User go in chat
  (AskUserQuestion, header `LP59.3`); queue docs/work/loop-to-pr/unfreeze-queue.md.
- Review round 6 route, 2026-11-20 (AskUserQuestion, header `Repli`, user's choice (ii)): verifier
  confirmed NA (regression), NB (regression FP), NC (pre-existing), TQE; route-review-6.json →
  fix-batch, `attempt: fail` NOT recorded (review stays 2/3). The round-6 fallback is applied in
  its amended form (ii), one last refusal-only batch: (1) the `U2!` lift is removed — a `!` suffix
  is still parsed as its id (so a `U2!` line never becomes a whole-file exemption) but lifts
  nothing; every ambiguous case is refused and the deny text names `loop-record.py --clear` as the
  exit; (2) two-direction span agreement: the char span must end on the last non-blank line of
  the indentation span, else ambiguous (closes NC); (3) a `.each` case whose first-call span holds
  another it/test call start is refused (closes NA); (4) NL and NL10 pin the end-line conditions
  (TQE). NB (multi-line template at or below the call indent, options-object third argument) is
  an accepted false positive, exit `--clear`. The span scanner and the lift go to follow-ups.md
  as their own pass. No further fix round on this pass: round 7 FAIL → record it.
- amended 2026-11-20 U2-U9 (lift removal, user go in chat, AskUserQuestion headers `Gelés x7` and
  `LP62.8`; queue docs/work/loop-to-pr/unfreeze-queue.md): LP54 needle `U2!` → `loop-record.py
  --clear`; LP54.2 `pass` → `deny` + that needle; LP62.8 `pass` → `deny` + that needle (accepted
  false positive of the two-direction rule); LP63, LP63.2, LP63.3, LP65, LP65.2 needle `no marker
  lifts it` → `loop-record.py --clear` (absence of `lifts it with` kept).
