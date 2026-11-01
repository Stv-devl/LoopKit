# Spec: Allow-list grammar for the P1 git commands
Token profile: critical (it decides which git calls run without a prompt — authorization — and guards against staging secrets)
Supersedes the deny-list decision path of `docs/specs/light-permissions-git.md` (BLOCKED 2026-10-30, review failed 3x; the Critical forms are in `docs/work/light-permissions-git/handoff.md`). Base: that spec's staged work (P1 allows, `acceptEdits`, hold-back with removal, `rm -r` ask, dry-run secret check, guard api), kept as is.

## Objective
A Bash call containing `git add`, `git stage`, `git commit` or `git switch` runs without a prompt only when the **whole call** is exactly one plain form; any other spelling asks, so no shell construct the hook misreads can reach an auto-approved git call.

## Scope
- IN :
  - **Strict forms** (the whole call, one line, leading/trailing spaces and tabs ignored, no control character, nothing else in it):
    - `git add [--] <path>…` and `git stage [--] <path>…`, optionally `git -C <dir> add|stage …`. Each `<path>`/`<dir>` matches `^[A-Za-z0-9._/@+-]+$`, does not start with `-`, is not `.` or `..`, and `<path>` is not a directory in the target tree.
    - `git commit -m "<msg>"` or `git commit -m '<msg>'`: `<msg>` non-empty, one line, without `$`, backtick, `\` or the enclosing quote character (accents, and an apostrophe inside double quotes, allowed).
    - `git switch -c <branch>`: `<branch>` matches `^[A-Za-z0-9._/-]+$` and does not start with `-`.
    - `git branch --show-current` and `git worktree list` stay exact allows (no hook change).
  - **Trigger.** The hook reads the command text twice: raw, and with quotes, `\` and `\`+newline removed. The call is *triggered* when, in either reading, `git` appears at the end of a word (`git`, `xgit`, `/usr/bin/git`; not `.gitignore` or `github`) and `add`, `stage`, `commit` or `switch` appears as a whole word, in any order. The trigger decides no statement boundary and no left boundary for `git`. A triggered call that is not exactly one strict form → **ask** ("not a plain git call: run it alone as `git add <paths>`, `git commit -m \"<one line>\"` or `git switch -c <branch>`"). Over-matching (`git log --grep add`, a message or an argument naming `git add`) only asks.
  - **Denies keep precedence.** Before the ask, the existing denies still decide: `git add`/`git stage` force, a secret listed by the dry-run of a strict add, a commit on a protected branch, a signed commit, an attribution trailer. The existing deny-list parser is kept **only** to produce those denies and their reasons; it never turns a triggered non-strict call into a pass.
  - **Order.** The grammar ask is the last decision of the hook: every existing deny and ask decides first and keeps its reason.
  - **Frozen cases.** Every frozen `light-permissions-git` case whose command is triggered but not a strict form and expects `pass` becomes `ask` (e.g. `git add -A`, `git add -u`, `git add src/x.ts 2>&1`, `git status && git add …`, `git commit -mall`); each is recorded as an `amended` line in the new plan's `## Gate`. Deny and ask cases keep their verdict; their reason may change only where the plan lists it.
  - `.claude/agents/github.md`, `docs/ADAPTATION.md` §15, `docs/Claude_Workflows.md`: the plain forms are the only prompt-free ones; anything else prompts.
- OUT :
  - `docs/specs/harness-prompts.md` (other allows on the same deny-list premise — re-checked against this lesson before it runs, not here).
  - A full shell parser; reading what a non-strict call would do.
  - Paths with spaces or non-ASCII characters (they prompt).
  - The accepted follow-ups of `docs/work/light-permissions-git/prior-gate.md` and its plan `## Gate` that this grammar does not already close.

## Data model
none

## Custom backend
NONE — kit tooling.

## Front surface
No app code. Files: `.claude/hooks/enforce-git-workflow.sh` (strict-form check and trigger, the last decision), `.claude/hooks/fixtures/_harness/git-guard.jsonl` (new rows; amended verdicts per `## Gate`), `.claude/hooks/test-workflow-contracts.sh`, `.claude/agents/github.md`, `docs/ADAPTATION.md`, `docs/Claude_Workflows.md`.

## Acceptance criteria
- [ ] None of the Critical forms of the three failed reviews passes without a decision — each is denied or asked: `git add \⏎ -f .env.local`, `mv .gitignore g && git add -A`, `git diff --output=.gitignore && git add -A`, `git status > .gitignore; git add -A`, `git status <(mv .gitignore g) ; git add -A`, `git add -A & mv .gitignore g`, `git add -A | mv .gitignore g`, `echo $'\'' ; git add -f .env.local ; echo \'`, `echo \ # ; git add -f .env.local`, `true\;# ; git add -f .env.local`, `echo \ # ; git commit -m x --amend`, `echo $'\'' ; git commit -m x -a ; echo \'`.
- [ ] The strict forms pass: `git add src/x.ts`, `git add -- src/x.ts`, `git -C <tree> add src/x.ts`, `git stage src/x.ts`, `git commit -m "feat: x"`, `git commit -m "fix: it's done"`, `git switch -c feat/x`; `git add .env.local` (untracked) and `git add -f x` stay denied.
- [ ] On a real light pass (smoke, installed P1): no prompt for edits, `git add <paths>`, `git commit -m "<one line>"`, gates; `git push`, `gh pr *`, `git commit -m x --amend`, `git switch -c x --discard-changes`, and `git status && git add src/x.ts` prompt.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-install.sh`, `test-workflow-contracts.sh` pass.

## Business logic to cover
- Strict-form recognition: each accepted form, and each near-miss rejected (extra option, second statement, redirection, quote/escape/`#`/`$` in a path or message, newline, `.`, a directory, a leading `-`).
- The trigger finds add/stage/commit/switch through every spelling of the review findings (continuations, quotes, `$'…'`, escapes before `#`, `<(`, `&`, `|`, globals with values) and of the plan-critic's (`git status x\\⏎git add -A`, `git diff --output=.gitignore -- x\\⏎git add -A`, `git status #c\⏎git add -A`), and leaves git calls naming none of the four words (`git status`, `git log`, `git diff`) untouched.
- Deny precedence over the ask: force, dry-run secret on a strict add, protected-branch commit, signing, trailer.
- The amended frozen verdicts, and every other frozen case unchanged.
