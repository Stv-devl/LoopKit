# Research: Loop to PR   (entry: docs/specs/loop-to-pr.md)
Token profile: critical

Probes: 2 explorers (git/PR ship surface; freeze/record hooks) + 1 doc-researcher (AskUserQuestion
hook input), 2026-11-18. Key claims re-checked on the main thread (marked ✓).

## Pattern to follow
- **Hook-written, tool-denied state**: `.claude/.tdd-red/` markers. Written only by the PostToolUse
  hook `tdd-prove-red.sh` (digest `:159-163`, writes `sha256:` `:371`), read by `tdd-require-red.sh`
  (`:86-90`, `:139-142`, `:212`), denied to every tool via `CWK_GUARD_DENIED`
  (`.claude/hooks/hook-guarded.sh:163-166` ✓). The record should follow the same class.
- **Removal-only `.tdd-unfrozen` allow** (fewer-asks 214459d): `protect-files.sh:241-285`,
  `unfrozen_removal_only()` simulates the Edit on the current file in `python3 -I -c` and allows
  only if every resulting line already exists. The record-backed allow is the same simulate-then-check
  shape, checking added lines against recorded rows instead.
- **Exact-form allow in the git hook**: there is none for push today. Existing exact-shape logic
  to copy from: `refspec_destination` (`enforce-git-workflow.sh:860-865`), `deadline_git`
  (`:592`), `config_rule` (`:1008-1025`).
- **Branch-rules probe**: `kit-doctor.py:975-1021` `check_github_protection` (gh api, offline/no-gh
  silent).

## Wiring points
- `.claude/settings.json`: PreToolUse `Write|Edit` (:86, protect-files, tdd-freeze-tests,
  tdd-require-red with `onFailure: block`), `Bash` (:129, prevent-destructive + enforce-git-workflow),
  PostToolUse `Write|Edit` only (:173). **No hook on `AskUserQuestion` anywhere** — new matcher.
- `install.sh:409-438` `install_settings` (react mode copies whole; core mode jq-filters — check the
  new PostToolUse entry survives core mode). `install.sh:334` copies `.claude/hooks/*` by glob.
- `kit-doctor.py`: `check_hook_wiring` `:940-972` (an on-disk hook not wired = "mute"; `+x`
  required), `NON_HOOKS` `:850-858`, `RUNTIME_PATHS` `:842-846` (a new runtime dir must be listed),
  `check_github_protection` `:975-1021` registered in group `wiring` `:1475`.
- `enforce-git-workflow.sh` floor regexes run first: `gh pr create|merge|…` ask `:2061-2062`,
  `--force` `:2073-2074`, any `git push` ask `:2077-2079` ✓ (`PUSH_REASON` `:130`), per-segment
  push ask `:2095-2097` ✓, PARSE_FAILED fallback `:2132-2139`. A V5 allow must sit **before** the
  floor (or the floor must exempt the exact form), and the parse-failure fallback must still ask.
- Emit: `decide()` `:111-126` prints the PreToolUse JSON, first verdict wins.

## Reusable
- `parse_segments` tokenizer (`:203+`, `tokens()` `:350`, `segments()` `:359`, `WITH_VALUE` `:214`,
  global-option loop `~:1584-1600`, env assignments `:372-375`, `is_force` `:377`).
- `quick_git` `:584`, `deadline_git` `:592` (2 s shared budget), `kit_resolves` `:1122` (does NOT
  distinguish heads from tags — a `show-ref --verify refs/heads/<B>` / `refs/tags/<B>` pair is new).
- `gh_scan` `:1931+` (already parses `gh … --body-file` for the attribution deny `:1992`).
- `unfrozen_removal_only()` (protect-files.sh:241-282) — extend, do not fork.
- Plan test-plan ids: `U1`, `M`, `R`, `B` per letter, title starts with the id
  (`.claude/commands/loop/plan.md:239-249`); `## Gate` amended line template `:292`.
- `check_github_protection` gh helper and the test shim `test-kit-doctor.sh:91-163`.
- Test harness: `test-hooks.sh` `run_case` `:114-200` over `fixtures/<hook>/*.json` (enforce-git
  99 fixtures, protect-files 43, tdd-freeze-tests 20); `fixtures/_harness/git-guard.jsonl` (546 rows)
  via `:991-1033`; `unfrozen_case` rows P1/P2 `:818-862`; Python freeze RV rows `:2634-2716`.
- Contract tests: `test-workflow-contracts.sh` `grep -Fq` needles, `section FILE START END` `:287`.

## Blast radius
- **`.tdd-unfrozen` parser has three copies** that must change together: `tdd-freeze-tests.sh:146-169`
  ✓, `tdd-require-red.sh:146-160` (`is_unfrozen`, also the RED-lift `:198`, `:239`),
  `addons/fastapi/hooks/tdd_py_lib.py:409-430` (docstring: "change the three together").
- An entry exempts the **whole file** by substring match (`tdd-freeze-tests.sh:165-166` ✓), before
  the re-save and insertion checks — there is **no case-id parser and no per-case hash** in any freeze
  hook (TS or Python). The per-case-line sha256 check (F12) is new code in both.
- `hook-guarded.sh`: adding a denied path needs `CWK_GUARD_DENIED` + `cwk_guard_denied_why`
  (default branch `:176-178` returns `.tdd-red` text for any non-`.git` path ✓) + bump
  `cwk-guard-api: 8` (line 2 ✓) + `prevent-destructive-commands.sh` text clause `:744-748` and parse-
  failure fallback `:901-905` (both hard-code `.claude/.tdd-red`) + `kit-doctor.py` `RUNTIME_PATHS`.
- `check_github_protection` hard-codes `main` (`kit-doctor.py:1000`, `:1009` ✓) and only checks a
  ruleset exists, not PR-required / non_fast_forward / deletion.
- ship.md (lines moved since the spec): step 1bis `83-122`, step 2 amended cases `129-134`, step 4
  commit `144-163`, **4bis `164-197`** (rebase onto base, re-run gates, go-ahead, worktree/branch
  cleanup), step 5 `199-223`, small-ticket integration `245-258`, rules `283-289` ("Never push or
  open a PR without an explicit go-ahead" `:287`).
- github.md: description `:3` ✓ ("ALWAYS asks"), hook-prompt note `20-23`, attribution ban `33-36`,
  PR template `60-111` (body in `docs/work/<slug>/pr-body.md`, `--body-file` `80-86`), validation gate
  `113-127`, pr-assets `156-186`, merge a track back `188-216`, keep-local-in-sync `218-238`.
- plan.md step 7 gate `115-184`: `AskUserQuestion` only on light passes and `Plan critic, open`;
  full/BUG ask three questions in chat (`:161`, `:175-180`). No "Frozen cases to amend" text exists.
- orchestrate.md frozen-case correction `258-272`; small branch "asks nothing before ship's merge go"
  `84-86`; forked-track merge `314-316`.
- small.md state table `26-29` ("merged, to clean" = ancestor of Base); tracks.md integration order
  `173-174`, recompute `179-180`, merge user-gated `192`.
- Reviewer: `.claude/guides/review/tests.md:64-78` (frozen cases by id; `:74` "edited with no
  `.tdd-unfrozen` entry → Critical"); Python mirror `tests-python.md:17-18`. `reviewer.md` itself has
  no freeze wording (delegates at `:48`).
- Docs: `docs/Claude_Workflows.md` 146-147, 152-154, 177-178, 333-342, 395-400, 639-642, 698-699,
  741. Contract **K1** (`test-workflow-contracts.sh:487-492`) requires `git push` and `gh pr` to stay
  in that file.
- Contracts that a rewrite must respect: github.md needles 470-471, 489-529, 834-835; PR template order
  881-889; small-ticket section 418-420; PK17 1184-1188; GS1-GS6 1290-1318; ship.md negative needles
  354, 514 and 832-848. Dropping "always asks" from github.md breaks no current needle.
- `fast-lane.md` D4 `:326-330` and status line 2; `light-fewer-gates` has no file in the tree,
  pointers at `loop-to-pr.md:30,52`, `small-lane.md:3`, `light-permissions.md:5,32`,
  `auto-mode.md:15,42,59`, `fast-lane.md:4`, `test-workflow-contracts.sh:282`.
- `.claude/kit-manifest` lists prompts only (install.sh:197-201); hooks are copied by glob, no manifest
  entry needed.

## Live DB state
n/a — kit tooling, no database.

Live remote state (`gh api repos/Stv-devl/LoopKit/rules/branches/main`, 2026-11-18 ✓): one repo
ruleset with `deletion`, `non_fast_forward`, `pull_request` (0 approvals, merge/squash/rebase
allowed). The server barrier V5 requires is present on `main` in this repo. Working branch
`audit/slim` is pushed (`origin/audit/slim`) and is the base this pass would stack on.

## External surface
- Branch rules API [cache 2026-11 `ci-lint-tools.md:37-52`]: `GET /repos/{o}/{r}/rules/branches/{b}`
  → 200 array of active rules, `[]` exit 0 on a branch with none; classic `…/protection` → 403 with
  the user's token (needs admin) — **a 403 means unknown, never unprotected**.
- AskUserQuestion hook input [fetched 2026-11-18, `docs/research-cache/claude-code-hook-input.md`]:
  - PostToolUse matcher `AskUserQuestion` is valid (same names as PreToolUse). No sentence states it
    fires for this tool; implied by the `updatedToolOutput` row.
  - `tool_input.questions[]` = `question`, `header`, `options[{label,description}]`, `multiSelect`;
    optional `tool_input.answers` `{"<question>": "<label>"}`, multi-select joined with commas, "Other"
    carries the user's own text. **`tool_response` schema is undocumented**; where TUI answers land
    is unknown.
  - Subagent marker: `agent_id` ("the subagent … the hook fires in"). `agent_type` is ALSO set on
    main-thread calls under `--agent` — not a safe subagent marker alone. SDK doc: AskUserQuestion is
    "not currently available in subagents spawned via the Agent tool" (CLI unverified).
  - `cwd` follows Claude (worktree, `cd`); use `$CLAUDE_PROJECT_DIR`.
  - PostToolUse is observation-only (exit 2 shows stderr, tool already ran); sync hooks finish
    before the result is recorded; `async: true` does not. Write-before-next-call is an inference.

## Traps (points of vigilance for the review)
- **Attribution deny vs PR body**: `ATTRIBUTION_RE` (`enforce-git-workflow.sh:1898` ✓) denies
  `Co-Authored-By|Generated with .*Claude|🤖|Claude-Session|claude\.ai/code` in commits and gh bodies
  (inline `:1984`, `--body-file` `:1992`), matching github.md:33-36. An auto-opened PR body must not
  carry the harness attribution, or the "no ask" path becomes a deny.
- The record is only as trustworthy as the subagent marker: use `agent_id` (and `agent_type`) absence,
  never `agent_type` alone (set under `--agent`).
- An exact-form push allow placed after the floor regex never fires; placed before it, it must not
  let through any shape the floor exists to catch (`--force*`, refspec `:`/`+`, `--mirror`, `--tags`,
  `--delete`, `--no-verify`, globals `-C`/`-c`, env prefixes, compound commands, alias expansion).
- `kit_resolves` matches tags as well as heads: the `refs/heads/<B>` only / no `refs/tags/<B>` check
  must use `show-ref --verify`, under the 2 s `deadline_git` budget; timeout → ask.
- Push config hijack: `remote.origin.(push|pushurl|mirror|receivepack)`, `url.*.pushinsteadof`,
  `push.(followtags|pushoption)`, `core.sshcommand` — no code reads them today; global/system config
  and `include.path` also count (`git config --get-regexp` without `--local` reads all scopes).
- `.tdd-unfrozen` exempts a whole file and also lifts the RED requirement on an implementation path:
  the record-backed allow must refuse any non-test path, and the three parser copies must stay
  identical.
- The new denied record path needs every hard-coded `.tdd-red` clause in prevent-destructive
  (`:744-748`, `:901-905`) and the `cwk_guard_denied_why` default extended, or shell writes / wrong
  deny text slip through.
- kit-doctor flags an unwired hook as "mute" and a missing runtime dir; a helper sourced by hooks goes
  in `NON_HOOKS`.
- `check_github_protection` reads `main` only; the barrier must read the **default branch**
  (`gh repo view --json defaultBranchRef` or `repos/{o}/{r}`) and the three rule types, and treat
  403/timeout/no-gh as "no barrier" → today's ask.
- Stacked base: `gh pr create --base` must equal the recorded `Base`, which must exist on the remote
  (`ls-remote`) and be the default branch or an unprotected feature branch.
- K1 contract keeps `git push`/`gh pr` in `docs/Claude_Workflows.md`; ship.md negative needles 354,
  514 must not reappear in the rewrite.
- `.tdd-unfrozen` removal-only allow (fewer-asks) must keep working unchanged next to the new
  record-backed add allow.
- Python freeze hook (`addons/fastapi`) needs the same per-case-hash check, or F12 is TS-only.

## Open questions
1. **Settled by spike 2026-11-18** [measured, `claude-code-hook-input.md` §6]: PostToolUse fires for
   `AskUserQuestion`; answers in `tool_input.answers` and `tool_response.answers`,
   `{"<question>": "<label>"}`; main-thread call has no `agent_id`/`agent_type`; a declined call fires
   nothing. Not measured: typed "Other" and multiSelect values. **Decision for the plan**: a typed `go`
   is assumed indistinguishable from the `go` label, so the spec's "free text records nothing" is
   enforced only as "the answer must equal the label `go` exactly, to the question carrying the fixed
   gate header"; the plan must state this residual (a user typing exactly `go` in Other counts as go —
   which is the user's own answer anyway).
2. **Which answer opens the record** (spec: "decided in the plan"): the plan-gate `go` alone (it
   captures branch and `Base`), or also the Phase 0 go? Proposed: the plan-gate `go` only.
3. **Record location and format**: proposed `.claude/.loop-record/<slug>.json` (one per pass, so
   parallel worktrees don't collide; each worktree has its own `.claude/`). Confirm.
4. **Branch at record time**: the plan gate runs on the main tree for a single track (this pass runs on
   `audit/slim`, not `feat/loop-to-pr`). Does the loop create `feat/<slug>` at the plan go (record
   captures `Base` = current branch, `<B>` = `feat/<slug>`), or at ship before the commit?
5. **Server barrier check placement**: kit-doctor (offline-silent today) or Phase 0 / ship, and is it
   cached in the record (one `gh api` at plan go) or re-read by the push hook (network inside a 2 s
   hook budget)? Proposed: read once at record time, stored in the record; the hook never calls the
   network.
6. **ci.md:16-17 citation is stale**: the spec's credential argument is not in `templates/ci.md`
   (closest `:12-20`, `:124-137`). Keep the barrier rationale in the spec/ADAPTATION only, or add a
   sentence to ci.md?
7. **This repo's own flow**: here `audit/slim` is a long-lived branch pushed without PR to `main`
   (memory: "push to same branch, ff only, no PR"). After this pass, does LoopKit itself switch to
   feature branch + PR per pass, or keep pushing `audit/slim` (push of a non-`<B>` branch keeps the ask)?
