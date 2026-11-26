# Research: Local-kit tracks   (entry: docs/specs/local-kit-tracks.md)
Token profile: critical

## Pattern to follow
- Python subcommand kit script: `.claude/hooks/kit-pr-assets.py` — `Parser(argparse.ArgumentParser)` turning usage
  errors into `Refused` (`:361-364`), `build_parser()` + `run(argv)`, `main()` maps `Refused` → stderr
  `kit-pr-assets: <reason>`, exit 2 (`:425-431`); git via `subprocess.run(["git", "-c", "core.quotePath=false", …],
  capture_output=True, text=True)` (`:189`); `HERE`/`sys.path.insert` + `import project_config` (`:29-32`).
- Location: every Python kit script lives in `.claude/hooks/kit-*.py`; `.claude/scripts/` holds shell only
  (`kit-apply.sh`, `small-*.sh`, `loop-pr-state.sh`, `case-hash.sh`). A Python file in `.claude/hooks/` not wired in
  settings must be listed in `kit-doctor.py` `NON_HOOKS` (`:883-890`) or the doctor reports it mute (`:986`).
- Tests: one `test-<name>.sh` per script (`test-pr-assets.sh:8`, `test-attempts.sh:12-20`), fixtures built in
  `mktemp -d`, assertions `grep -Fq` / exit codes / `jq -e`; registered as a `run:` line in
  `.github/workflows/kit-ci.yml:60-77`.
- Guard cases: `fixtures/_harness/git-guard.jsonl` rows `{id,verdict,command,cwd?,reason?,setup?}` run by
  `run_git_guard_cases` (`test-hooks.sh:1010-1050`); setups `lpwtignored` (`.claude/` in `.gitignore`,
  `test-hooks.sh:4780`) and `lpwttracked` (`:4781-4787`). Existing: G22.115 deny (reason `.gitignore`,
  jsonl:668), G22.115.2, G22.116, G22.117 ask.

## Wiring points
- Guard: `enforce-git-workflow.sh:2261-2275` `worktree_kit_check` — deny text `:2273`. Matches only the literal Bash
  text `git worktree add … .claude/worktrees/… -b|-B` (`:2265`, `:2267`); hooks see only tool inputs, so a `git`
  call inside a Python subprocess is never seen (G15.07, `test-hooks.sh:1222-1232`).
- Every copy of the kit-ignored refusal (change together):
  `.claude/commands/loop/tracks.md:141-149`; `.claude/commands/loop/orchestrate.md:233-237` (Phase 0.5);
  `.claude/guides/10-worktrees.md:141-146`; `enforce-git-workflow.sh:2273`; `.claude/commands/kit/doctor.md:65`;
  `.claude/hooks/kit-doctor.py:697-718` (`worktree-kit` finding, detail = where the script name goes);
  `install.sh:951-956` (French warning, four spellings, IW1-IW2 grep `ignore .claude/ lui-même`).
- Close integration: `/loop:ship` `4bis-local` item 3 (`ship.md:227-239`) and the closing check
  (`orchestrate.md` Phase 0 step 0; `ship.md:208-211`) run the worktree clean-up — `docs/` porcelain check, list of
  ignored `docs/work/<slug>/` files lost, then `git worktree remove` + `git branch -d`. In kit-local mode this is
  where `close` replaces the bare `remove`.
- Board/story: `orchestrate.md:223-227` (board only from the main tree, story `Status` → `InProgress` always),
  `bmad/dev.md:18-21`, `ship.md:255-268` (step 5: story `Done`, board `SHIPPED`, main tree only).
- Overlay slot: prose line `**Project slot \`<name>\`** — \`## <name>\` in \`.claude/overlays/<path>\`` (example
  `10-worktrees.md:93`), template `templates/overlays/guides/10-worktrees.md`, checked by PK16
  (`test-workflow-contracts.sh:1207-1229`), name regex `[a-z-]+` (`:1208`) → the slot must be `local-kit-env`, not
  `local-kit env`.
- Permissions: `.claude/settings.json:46-61` allow list (`python3 .claude/hooks/kit-attempts.py *` …) mirrored by
  `install.sh` `PROMPT_ALLOWS` (`:385-400`). Without an entry the call prompts; the kit-cwd rule
  (`prevent-destructive-commands.sh:1032-1033`) requires segment 0 or a lone `cd <abs root> &&`.

## Reusable
- Runtime/session file lists, three copies: `install.sh:640-680` (gitignore block), `kit-doctor.py:873-880`
  `RUNTIME_PATHS` (adds `.tdd-unfrozen`, `project.snapshot.json`, `INSTALL_PROFILE`, `project.proposed.json`,
  `hooks/probe`), `install.sh:340-344` `find` exclusions (`__pycache__`, `.tdd-red`, `worktrees`, `kit-backup`,
  `*.pyc`, `.DS_Store`, `settings.json`, `.loop-record.json|.lock`, `project.json`, `.hook-timings.log`,
  `.eslint-queue*`). None is importable from Python; the copy script needs its own list, kept consistent.
- Protected paths: `hook-guarded.sh` `cwk_is_guarded` (`:356-381`) callable from Python via
  `bash -c 'source hook-guarded.sh; …'` as `loop-record.py:745-752` does. `.env*` rule: `protect-files.sh:110-113`.
- Merge state: `.claude/scripts/loop-pr-state.sh --chain <branch>` → `closable | open | stacked:<b> | closed |
  orphaned:<b> | unknown | none` (used by the closing check).
- `--force` on `git worktree remove` is denied for Bash (`prevent-destructive-commands.sh:72-74`); plain remove
  refuses a dirty tracked tree and untracked non-ignored files, deletes ignored files silently.

## Blast radius
- Launcher: `workflow.py:18` `PROJECT = Path(__file__).resolve().parent`, `:221` sets `CLAUDE_PROJECT_DIR = PROJECT`
  → the worktree's **own** copied `workflow.py`/`workflow.sh` make the worktree the project; running the main
  tree's launcher from a worktree cwd writes main-tree state (the Oct 2026 trap).
- `settings.json` hooks are all `$CLAUDE_PROJECT_DIR/...` (`:97-279`) incl. statusline → resolve in the worktree.
- Per-tree state already: `loop-record.py:96` (toplevel of hook cwd), `tdd-prove-red.sh:146` (`CLAUDE_PROJECT_DIR`),
  `token-statusline.py:53-56`, `kit-attempts.py:126` (`attempts.json` next to the artifact).
- `hook-guarded.sh:139-144` `cwk_installed`: installed when `.claude/INSTALL_PROFILE` exists → copying it keeps
  kit code denied in the worktree as in the project.
- `kit-doctor.py:660-689` `ignored-loop-paths` also DIVERGEs on every kit-local project (it ignores
  `.claude/rules/`, `agents/`, `docs/work/` …) — not only `worktree-kit`.
- Prior decision: `docs/work/agent-ia-trial-fixes/plan.md:12-15` chose detect+refuse over support, citing the
  settings allow-list, prompts running kit scripts by relative path, `kit-audit-surface.py:153`
  (`load_strict(os.getcwd())`), `kit-pr-assets.py:317` (symlink refusal), the per-tree `.tdd-unfrozen`/marker split,
  and Claude Code's native cross-tree write refusal. Re-checked: all assume a session launched in the main tree or
  symlinked docs; with regular-file copies (incl. `project.json`) and a session launched by the worktree's own
  `workflow.sh`, relative paths, `load_strict(cwd)`, the symlink check and the cross-tree refusal all resolve
  inside the worktree. The `.tdd-unfrozen` split remains a decision (open question 3).

## Live DB state
n/a — kit tooling, no database.

## External surface
n/a — no third party. Claude Code behaviour relied on: hooks see only tool inputs `[test-hooks.sh G15.07]`;
`CLAUDE_PROJECT_DIR` is what the launcher sets `[workflow.py:221]`.

## Traps (points of vigilance for the review)
- The copy set must exclude, explicitly: `worktrees/`, `kit-backup/`, `.tdd-red/`, `.loop-record.json|.lock`,
  `.token-*`, `.restart-ready`, `.codex-ready`, `.quota-warning`, `.kit-health.jsonl`, `.hook-timings.log`,
  `.eslint-queue*`, `settings.local.json`, `__pycache__/`, `*.pyc`, `docs/work/*/handoff.md`,
  `codex-last-message.txt`, `pr-body.md`, `.pr-shots/`, any `.env*`, `*.pem`, `*.key`, `credentials.*` — and must
  include `project.json`, `kit-manifest`, `INSTALL_PROFILE`, `VERSION`, `workflow-routing.yml`, `.size-exempt`,
  `overlays/`, root `CLAUDE.md`, `AGENTS.md`, `workflow.py`, `workflow.sh`, `codex-handoff.sh`.
- Copies are regular files: a symlink in the source is refused or dereferenced, never recreated (`kit-pr-assets.py:317`
  precedent; Oct 2026 symlink write failure).
- `close` copy-back must not clobber a main-tree file changed since the fork: the story file gets `Done` from ship
  step 5 in the main tree while the worktree copy says `InProgress` — compare against the fork manifest.
- `close` runs before `git worktree remove` and before `git branch -d`; `remove` deletes ignored files silently,
  so a copy-back not verified is a loss with no error.
- The `kit-track.py` git calls are invisible to the hooks: the script itself must refuse `--force`, a dirty tree,
  an existing path/branch, and must not run outside the project root.
- The deny keeps firing on the bare `-b` fork; only its text changes. Regex gaps already known: `-B`,
  `git -C d worktree add`, no trailing slash (not widened here; not in scope).
- `orchestrate.md` contract slice `:354` cuts `## Phase 0 —` … `## Phase 0.5 —`: new Phase 0.5 text must stay below
  that heading. WT1/WT2/WT2.3 pin the `check-ignore -q` probe string in tracks/orchestrate/10-worktrees; WT2.2
  forbids "if `.claude/` is versioned" in 10-worktrees.
- `EnterWorktree` creates/enters a worktree without any hook: the prompts must route kit-local tracks only through
  the script and a `./workflow.sh` session started in the worktree.
- `install.sh:28-31` checks the executable bit only for `.claude/scripts/*.sh`.

## Open questions
1. Location: `.claude/hooks/kit-track.py` (Python convention, `NON_HOOKS` entry) rather than the spec's
   `.claude/scripts/kit-track.py`? Proposed: hooks/, the spec path amended.
2. Permission: add `python3 .claude/hooks/kit-track.py *` to the settings allow list (+ `PROMPT_ALLOWS`) so
   `/loop:tracks` runs it without a prompt, or leave it prompting (the fork is user-gated in `/loop:tracks` step 4
   anyway)? Proposed: `fork` allowed, `close` left prompting (it deletes a tree).
3. `.claude/.tdd-unfrozen`: copy it to the new track (main-tree entries apply to main-tree files only) or start the
   track empty? Proposed: start empty — each track records its own corrections.
4. Copy-back conflict rule: overwrite a main-tree owned file only when it is unchanged since the fork (manifest
   hash), else report and keep both (`<file>.track`)? Proposed: yes, one rule for story file, `docs/work/<slug>/`
   and `research-cache`.
5. Ordering at close: `close` (copy-back) before ship step 5, so step 5's `Done` and board land last? Proposed: yes,
   the closing check / `4bis-local` item 3 run `close` first in kit-local mode, then step 5.
6. `/kit:doctor` on a kit-local project: keep `worktree-kit` and `ignored-loop-paths` as DIVERGENCE with the
   script named, or downgrade them to an informational "kit-local mode" line? Proposed: downgrade to an ok line
   naming the mode and the script (the mode is supported, not a divergence).
