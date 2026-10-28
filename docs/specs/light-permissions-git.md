# Spec: Git rules and the narrow permissions (light loop without prompts)
Token profile: critical (it widens what the agent may do without a prompt)
Split from: `docs/specs/light-permissions.md` (2026-10-28, pass 3 of 3). Needs `docs/specs/guard-writes.md` and `docs/specs/guard-shell.md` shipped. Research reused: `docs/work/light-permissions/research.md`; plan-critic findings: `docs/work/light-permissions/plan.md`. Ships before `docs/specs/fast-lane.md`.

## Objective
Permission prompts disappear for edits, `git add <paths>`, `git commit -m "<one line>"` and the gates, because the hooks now police the dangerous forms of those commands. Evidence for the gain: `docs/measuring-the-loop.md`, "5 minutes of work behind one unapproved `Write`".

Threat model: a **mistaken** agent in `acceptEdits` with the allow list below. P1 never ships without P2 — in this repo and in any project `install.sh` upgrades.

## Scope
- IN :
  - **P2 git, in `enforce-git-workflow.sh`.** The parser row gains an args column (tab-safe). Long flags by unique prefix, short flags unbundled, matched anywhere in the call:
    - `git commit` with `--amend`, `--no-verify`/`-n`, `--all`/`-a`: ask.
    - `git switch`/`git checkout` with `--discard-changes`, `--force`/`-f`, `--force-create`/`-C`: ask.
    - **Deny pass** (before every ask): `git add` with `--force`/`-f`; with `$(`, backtick, `$`, `--pathspec-from-file`, `--pathspec-file-nul`. Then every other `git add` runs a dry-run **inside the python block**: `subprocess.run(["git","-C",dir,"add","--dry-run",*args], timeout=2)` — the user's arguments in their order, no inserted `--`, no coreutils `timeout` (absent on macOS); deny on timeout, nonzero exit, or a listed path matching `.env*` (except `.env.example`, `.env.sample`, `.env.template`), `*.pem`, `*.key`, `credentials.*`. PARSE_FAILED and a line has `add` in subcommand position (after `git` and its global options) → deny `unreadable git add`.
    - The text at `enforce-git-workflow.sh:70` names `git switch -c`, not `git checkout -b`.
  - `.gitignore`, the `install.sh` heredoc and its back-fill loop gain `*.pem`, `*.key`, `credentials.*`.
  - **Install hold-back.** Each of the six guard files (`hook-lib.sh`, `hook-guarded.sh`, `shell_targets.py`, `protect-files.sh`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`) carries a `# cwk-guard-api: 1` line. `install_settings` holds P1 back when, in the target, any of the six is missing, lacks that line or carries a lower number, or `hook-lib.sh` does not source `hook-guarded.sh`. Held back = the kit's `permissions.defaultMode` and the five P1 allows are **not added**; nothing the target already has is removed. It prints `P1 held back: <files> — merge their .new copies, then re-run install.sh`. A target's own edits (`PROTECTED_DIRS`, `PROTECTED_BRANCHES`, the fastapi addon's patch) never hold P1 back.
  - **P1, last.** `.claude/settings.json`: `permissions.defaultMode: "acceptEdits"`; allow += `Bash(git add *)`, `Bash(git commit -m *)`, `Bash(git switch -c *)`, `Bash(git branch --show-current)`, `Bash(git worktree list)`. `git branch *`, `git switch *`, `git commit *`, `git push *` stay unlisted. `.claude/agents/github.md`: commit exactly `git commit -m "<one line>"` (no heredoc, no `$(...)`, no `-a`); staging `git add <explicit paths>` (never `.`, `-A`, `--all`, `-u`, a directory or a glob).
  - **Smoke, before merge.** Scratch target: `git init -b main`, a `package.json` with `"test:run": "true"`, a seed commit, `git switch -c feat/x`, then `install.sh` into it. Headless `claude -p --output-format json --max-turns 2 --tools <Write|Bash>` (no `--allowedTools`, no `--permission-mode`: the installed mode applies), one call each, in order: Write `src/x.ts`; `git add src/x.ts`; `git commit -m "x"`; `pnpm test:run` → absent from `permission_denials`, effect observed; `git push`, `gh pr list`, `git commit -m x --amend`, `git switch -c y --discard-changes` → present, the last two with the hook's own ask reason. No remote, no gh auth.
  - **Docs.** `docs/ADAPTATION.md`: `install.sh` unions `allow` and keeps the user's `defaultMode`; the hold-back and how to clear it; the measure method — permission-prompt dead time on a light pass, from the session transcript: the gaps between a `tool_use` and its `tool_result` on calls that prompted (`docs/measuring-the-loop.md:28-30`), summed per pass, "before" from an existing light-pass transcript, "after" from the next one. `docs/Claude_Workflows.md` (French): the prompts left on a light pass (`git push`, `gh pr`, `--amend`, `--discard-changes`, guarded paths).
- OUT :
  - No change to the loop's human gates (`docs/specs/light-fewer-gates.md`). No kit `permissions.deny`/`ask` array (the install merge would replace a target's).

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/hooks/{enforce-git-workflow.sh,test-hooks.sh,test-install.sh,test-workflow-contracts.sh}` and the git fixtures, the `# cwk-guard-api: 1` line in the six guard files, `.claude/settings.json`, `.claude/agents/github.md`, `.gitignore`, `install.sh`, `docs/ADAPTATION.md`, `docs/Claude_Workflows.md`.

## Acceptance criteria
- [ ] On a real light pass: no prompt for edits, `git add <paths>`, `git commit -m "<one line>"`, gates; `git push`, `gh pr *`, `git commit -m x --amend`, `git switch -c x --discard-changes` still prompt. (Proved before merge by the smoke; re-observed on the next light pass.)
- [ ] `git add -f .env`, `git add --forc .env.local`, and `git add .` with an untracked `certs/a.pem` are denied; `git add .env.example` and `git add src/x.ts` pass.
- [ ] An upgrade over hooks without the guard api gets no `defaultMode` and no new allow; a customised but current install gets both.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-install.sh`, `test-workflow-contracts.sh` pass.

## Business logic to cover
No TypeScript. Git fixtures (`cwd` `__FEAT_TREE__`; the fixture tree holds tracked `src/x.ts`, `.env.example`, and, for G4/G5 only, untracked `certs/a.pem`, `.env.local`):
- G1 ask each: `git commit -m x --amend`, `git commit --am -m x`, `git commit -am x`, `git commit -m x --no-verify`, `git commit -m x -n`; pass: `git commit -m "x"`.
- G2 ask each: `git switch -c x --discard-changes`, `git checkout -f main`, `git switch -C x`, `git switch --force-create x`, `git switch --force-c x`; pass: `git switch -c y`.
- G3 pass each, on a tree without untracked secrets: `git add src/x.ts`, `git add .env.example`, `git add -- src/x.ts`, `git add -A`, `git add -u`.
- G4 deny each: `git add -f x`, `git add --forc x`, `git add -Af`, `git add .env.local`, `git add certs/a.pem`, `git add .` (untracked `certs/a.pem`).
- G5 deny each: `git add $(cat list)`, ``git add `x` ``, `git add $F`, `git add --pathspec-from-file=l`, `git add missing.ts`, `git add src/x.ts` with a `git` shim first on PATH that sleeps 3 s, `git add -f .env.local <<'EOF'` / `it's` / `EOF`.
- G6 deny: `git push origin feat/x && git add -f .env.local` (deny before ask). Pass: `git commit -F - <<'EOF'` / `add the user's flag` / `EOF`.
- G7 existing git fixtures keep their verdicts.
- I1 `test-install.sh`: a fresh and an upgraded install ignore `*.pem`, `*.key`, `credentials.*`.
- I2 hold-back: (a) upgrade over an `enforce-git-workflow.sh` without the api line, settings without `defaultMode` → neither `defaultMode` nor `Bash(git add *)`, output `P1 held back: .claude/hooks/enforce-git-workflow.sh`; (b) after its `.new` copies are moved in, re-run → both present; (c) fresh install, re-run → both kept; (d) current api line plus an edited `PROTECTED_DIRS` → both present, `PROTECTED_DIRS` kept.
- K1 `test-workflow-contracts.sh`: `settings.json` holds `defaultMode == "acceptEdits"`, the five allows verbatim, and none of `Bash(git commit *)`, `Bash(git switch *)`, `Bash(git branch *)`, `Bash(git push *)`, `Bash(git *)`; `github.md` holds `git commit -m "<one line>"` and forbids `git add .`; `ADAPTATION.md` names the hold-back and the measure method; `Claude_Workflows.md` lists the prompts left on a light pass.
- K2 smoke results recorded in the plan's `## Gate`.
