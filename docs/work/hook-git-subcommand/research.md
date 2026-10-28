# Research: The git hook reads the real subcommand   (entry: docs/specs/hook-git-subcommand.md)
Token profile: standard

Probes: one surface (one hook, its fixture harness), read inline on the main thread: two files, 425 lines in all, smaller than an `explorer` brief.

## Pattern to follow
- **Rules that need no tree run before the tree guard**: the `gh` asks sit above `rev-parse` on purpose, so a non-repo cwd cannot skip them (`.claude/hooks/enforce-git-workflow.sh:61-81`, comment `:64-68`). The push, `send-pack` and alias asks of the spec follow the same placement.
- **`decide`/`ask`/`deny` through `jq -n`**, never a heredoc (`enforce-git-workflow.sh:43-59`): every new reason goes through `ask`.
- **python3 inside a shell hook** has a precedent: `tdd-freeze-tests.sh` (`grep -l python3 .claude/hooks/*.sh`). A shell-quoting-aware tokenizer (`shlex`) is available that way; `jq` stays the only prerequisite checked first (`cwk_require_jq`, `enforce-git-workflow.sh:25`), and the jq-absent harness case runs with a PATH holding only `env bash dirname basename date` (`test-hooks.sh:217-236`), so the hook must keep failing on `jq` before it reaches python3.

## Wiring points
- Registered once, PreToolUse Bash, `timeout: 5` (`.claude/settings.json:87-88`). A `git config --get` or `git --list-cmds` call per segment fits that budget; nothing network-bound may be added.
- Input: `.tool_input.command` and `.cwd` (`enforce-git-workflow.sh:29-30`); empty cwd falls back to `CLAUDE_PROJECT_DIR` (`:33`).
- Early exit when the command has no `git`/`gh` word (`:36`).
- Today's tree resolution: one regex picks the **first** `git -C <x>` placed right after `git` (`:88`), overrides `CWD` (`:89`), then `rev-parse` failing exits 0 (`:91`); `BRANCH`/`HAS_COMMITS` computed once for the whole command (`:93-98`).
- Rules after the guard: commit deny on a protected branch (`:108-113`, regex `\bgit\b[^|;&]*\bcommit\b`, already tolerant of globals), signature and trailer deny (`:119-126`), push asks (`:133-139`, `\bgit\s+push\b`), merge/rebase ask on a protected branch (`:145-147`, `\bgit\s+(merge|rebase)\b`).

## Reusable
- `on_protected_branch`, `PROTECTED_BRANCHES` (`:39`, `:100-102`): keep, call per segment with that segment's branch.
- Harness: `run_case` builds a git repo on `main` with one empty commit for `enforce-git-workflow.sh:deny` only (`test-hooks.sh:108-113`); placeholders `__PROJECT_ROOT__`, `__FIXTURE_ROOT__` substituted by `sed` (`:69`); verdict from the filename suffix `-pass|-deny|-ask.json` (`:151-156`); one JSON per file.
- `git --list-cmds=builtins` exists on the installed git (2.43.0, 140 entries, includes `push`, `merge`, `send-pack`): the builtin check H2 needs, read-only and offline.

## Blast radius
- Consumers of the hook: `.claude/settings.json:87`, `install.sh` (copy), `.claude/hooks/test-hooks.sh`, docs naming it (`docs/RATIONALE.md:259`, `docs/ADAPTATION.md`, `.claude/agents/github.md`, `.claude/commands/loop/ship.md`, `prevent-destructive-commands.sh:47,316` comments). No other hook sources it. `test-workflow-contracts.sh` and `kit-doctor.py` do not grep it.
- Existing fixtures: only two (`fixtures/enforce-git-workflow.sh/01-deny.json` commit on `main`, `02-pass.json` `git status --short`). Every other current rule (push asks, merge ask, signature deny, `gh` asks) has **no fixture**: a refactor of the rule flow can regress them unseen.
- Specs in flight that touch the same hook later: `docs/specs/light-permissions.md` P2 (commit/switch/add flags), `docs/specs/small-lane.md` S6 (relies on `git -C <main-tree> merge --ff-only` being gated). Neither is implemented.

## Live DB state
n/a

## External surface
- git global-option grammar on 2.43.0, verified in the earlier audit's scratch runs and here: `--attr-source <v>` takes a separate value; `-C a -C b` combines to `a/b`; `git worktree list --porcelain` shows a worktree mid-rebase as `detached`. `[local git 2.43.0]`
- No third-party API. No research-cache entry needed.

## Traps (points of vigilance for the review)
- The current push and merge rules have no fixture: add plain-form fixtures (`git push`, `git merge` on `main`, `gh pr create`, signed commit) **before** refactoring, or a regression of a plain form passes every new test.
- Splitting on `&` must not split `&&`, and a `|` inside quotes (a commit message) must not create a segment: tokenize with quoting awareness, not with a regex.
- A quoted `-C "path"` must resolve without its quotes (`:88-89` keeps them today, so `git -C "<main>" push` passes).
- Alias resolution reads config from the segment's directory; an unresolvable directory must not make the alias check pass silently.
- The hook must still exit 2 with the jq message when `jq` is absent (harness `run_missing_jq_cases`), before any python3 call.
- `on_protected_branch` must use the segment's branch, not one computed for the whole command: `git -C feat log && git -C main merge x` is the regression case.
- `git -C /nonexistent status` must keep passing (read-only), while `merge|rebase|commit|reset|switch|checkout` on an unresolved directory ask.
- Exit within the 5 s timeout: one python3 start and a few `git` calls; no loop over all aliases.

## Open questions
1. The spec splits segments on `;`, `&&`, `||`, `|`, `&`, newline. Is a `git` call inside `$(…)` or backticks (`echo $(git push)`) in scope? Proposed answer: yes, ask on any `git` word inside a substitution whose subcommand cannot be parsed, fail closed. Settles case set G1.
2. The spec says "plain forms keep their current decision". Today `git merge x` from a non-repo cwd passes (`:91`). With H1, a non-repo cwd for `merge` is an unresolved directory and asks. Proposed answer: accept the change for `merge|rebase|commit|reset|switch|checkout` only, as H1 states; it is the fail-closed direction.
