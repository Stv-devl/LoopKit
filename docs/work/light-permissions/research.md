# Research: Light loop without permission prompts   (entry: docs/specs/light-permissions.md)
Token profile: critical

## Pattern to follow
- **Ask emitter + segment parser**: `enforce-git-workflow.sh` — `decide/deny/ask` helpers `:52-66`, python shlex `parse_segments` `:100-289` emitting one row per git call (`sub \t dir \t alias_cfg \t force`, `:230`), deny pass `:337-361` before ask pass `:363+`. Per-flag rules slot in by adding an args column at `:230`/`:395`.
- **Shell write markers**: `prevent-destructive-commands.sh` `SRC_WRITE_RE` `:337-340` (redirect target, `tee|cp|mv|install|rsync|ln|patch|truncate`, `sed|perl -i`, interpreters `-c|-e`), Python twin `PY_WRITE_RE` `:348-351`; `decide/deny/ask` `:30-48`; segments from `hook-lib.sh` `cwk_segments` `:188-207`.
- **Fixtures**: `test-hooks.sh` discovers `fixtures/<hook>/*-{pass,deny,ask,allow}.json` (`:179-196`), placeholders `__PROJECT_ROOT__`, `__FIXTURE_ROOT__`, `__MAIN_TREE__`, `__FEAT_TREE__` (`:88`); one shared git fixture repo for `enforce-git-workflow.sh:*` (`:134-144`); per-name setup branches (`:105-121`).

## Wiring points
- `.claude/settings.json:2-31` permissions: 26 `allow` entries (read-only tools + pnpm gates), **no `deny`, no `ask`, no `defaultMode`**. Hook order: Write|Edit `:37-75` (no-any, protect-files, icons, english-comments, architecture, tdd-freeze, tdd-require-red); Bash `:77-91` (prevent-destructive, enforce-git, timeout 5 s); Read `:92-106` (protect-files, auto-approve-config).
- `protect-files.sh`: only a `deny` emitter (`:75-86`); paths used raw, no `CLAUDE_PROJECT_DIR`, no `.cwd`; Read/Grep/Glob exit at `:145-147`; write list `:149-156`; **guarded ask slot after `:162`**, Write/Edit only.
- `enforce-git-workflow.sh`: `is_force` (`:168-176`) used for push only; no rule for `commit` flags beyond `-S`/trailer (`:349-354`), none for `switch`/`checkout` flags, **no `git add` handling at all**; global options only before the subcommand (`:195-212`), so `switch -C` is unseen.
- `hook-lib.sh`: no emitter helpers (each hook defines its own); timing trap at source time unless `CWK_HOOK_TIMING=0` (`:22-47`, `__CWK_HOOK=$(basename "$0")`), so `hook-guarded.sh` must not source hook-lib (H8: log unchanged).
- TDD deny texts naming `.tdd-unfrozen`: `tdd-require-red.sh:179,185,207,217,223`; `tdd-freeze-tests.sh:387,390`.
- `install.sh:240-251` merge: `($new * $old)` (user scalars win → `defaultMode` kept when set), `permissions.allow` unioned (`:248`); **a kit `deny`/`ask` array would be replaced by the target's, never unioned**. `.gitignore` back-fill `:434-440`, heredoc `:444-470`.
- `.claude/agents/github.md:46-51` (commit "ONE LINE", no literal form), `:119-120` (staging soft: "avoid blanket `git add -A`").
- `kit-doctor.py:752-759` `NON_HOOKS` (`hook-guarded.sh` must join), `:366-404` gate-allowlist (unaffected by additions); `test-install.sh:70-73` (allow uniqueness), `:95-100` (back-fill names).

## Reusable
- `enforce-git-workflow.sh`'s parser (subcommand behind `-C`, globals, aliases, wrappers — b570fee): extend its row, never write a second git parser.
- `prevent-destructive-commands.sh` marker regexes: generalise from `.ts/.tsx` targets to the guarded set, keep target-position matching.
- Fixture runner already supports `-ask.json` and `-allow.json`.

## Blast radius
- Writers of the guarded set: `.claude/.tdd-red/` only by `tdd-prove-red.sh` (a PostToolUse hook, `:344-356`); `.claude/.size-exempt` and `.claude/.tdd-unfrozen` only by the agent/user; hook-process writes (`.hook-timings.log`, `.kit-health.jsonl`, markers) are not tool calls and never pass PreToolUse [fetched, inference] → a guarded ask cannot block the kit's own writers.
- `test-hooks.sh` writes into the real `$PROJECT_ROOT/.claude/.tdd-red` (`:106,110,175`): running it is the "running is not writing" case.
- This repo is the kit: every hook, script, settings or fixture edit will prompt after P2 (Open finding "Kit development").

## Live DB state
n/a.

## External surface (`docs/research-cache/claude-code-permissions.md`)
- `acceptEdits` auto-approves Write/Edit **and** `mkdir`, `touch`, `rm`, `rmdir`, `mv`, `cp`, `sed` inside the working dir; still prompts on protected paths (`.git`, `.claude` **except `.claude/worktrees/`**), critical-path `rm`, and every other non-read-only Bash. [fetched]
- `Bash(git add *)` never approves a compound command: every subcommand (`&&`, `||`, `;`, `|`, `&`, newline) must be allowed. `Bash(git commit -m *)` matches `git commit -m x --amend` (wildcard). [fetched; the second is inference from wildcard semantics]
- Hook decisions combine `deny` > `defer` > `ask` > `allow`; a hook `deny` (exit 2) beats an allow rule; a hook `ask` shows the prompt — **whether it overrides `acceptEdits`/an allow rule is not stated explicitly**. [fetched]
- Only exit 2 blocks; 127, crash and timeout fall through to normal permissions (fail open) unless the handler sets `"onFailure": "block"`. [fetched]
- A built-in read-only allowlist exists in every mode (`cat`, `grep`, `find`, `head`, `git` read-only forms…); `find -exec/-delete/-fprint` never approved by a prefix rule; `sed -n` / `git diff --output=` status undocumented. [fetched]

## Overlap with `docs/specs/harness-hardening.md` (name collision: its H7/H8 are not this spec's H7/H8)
| Harness | This spec | Verdict |
| --- | --- | --- |
| H1 Write/Edit ask on settings, hooks, `.tdd-unfrozen`, `.size-exempt` | P2 guarded set + protect-files ask | same; this spec is a superset (scripts, `.tdd-red`, vitest/eslint) |
| H1 `.github/workflows/**` | absent | harness-only |
| H1 `.tdd-red/**` **deny** | P2 `.tdd-red/**` **ask** | **conflict** |
| H1 shell ask on sed -i/rm/>>/tee/cp/mv | P2 marker list | this spec is a superset |
| H2 `permissions.deny` on secrets, drop `Bash(grep *)` | none | disjoint (same settings block; install merge drops a kit `deny`) |
| H3 `rm -rf src/*` **deny** | Open finding: recursive rm/mv under a protected dir **ask** | **conflict** |
| H3 git clean/reset --hard/restore/stash/branch -D | only `checkout -f` | disjoint except `checkout -f` |
| H5 auto-approve realpath/symlinks | none | disjoint |

## Traps (points of vigilance for the review)
- `Bash(git commit -m *)` / `git switch -c *` match any trailing flag: every dangerous flag needs a hook case with the flag **last** (`--amend`, `--no-verify`, `--discard-changes`), bundled (`-am`) and abbreviated (`--am`, `--forc`).
- `hook-guarded.sh` sources nothing with side effects (no hook-lib): H8 checks `.hook-timings.log` unchanged.
- The guarded matcher works on the **resolved, repo-relative** path: Write/Edit send absolute paths; a worktree path `…/.claude/worktrees/<x>/.claude/hooks/a.sh` must match `.claude/hooks/**`; `acceptEdits` does **not** prompt under `.claude/worktrees/`, so there P2 is the only guard.
- Shell operands: `cd X && sed -i …` is invisible today (no `cd` tracking); `2>&1` is split by `cwk_segments` (an fd-dup is not a redirect target); `$VAR`, `$(…)`, a glob next to a guarded dir → ask.
- Marker only in **target** position (redirect target, `cp/install/ln` destination, any `mv/rm` operand, interpreter `-c/-e`), else `python3 .claude/hooks/kit-doctor.py` or `kit-attempts.py …` would ask on every gate (H7).
- A missing/crashed hook fails open (exit 127): the shell rule that asks on `mv/rm` of a hook is what keeps it from being removed silently.
- `git add --dry-run` inside a 5 s Bash hook timeout: a timeout fails open; deny on timeout/nonzero.
- `install.sh` merge replaces arrays other than `allow`: do not ship a kit `permissions.deny`/`ask` without a union.
- The Read matcher also runs protect-files: the guarded ask stays Write/Edit only.
- `.gitignore` gains `*.pem`, `*.key`, `credentials.*` in the kit, the heredoc and the back-fill loop (and `test-install.sh:95-100`).
- `.claude/hooks/test-hooks.sh` writes into the real `.tdd-red/`: fixtures must not need a prompt to run.

## Open questions
1. **The spec's 9 Open findings** (coverage floor in `vite.config.*`; `package.json` scripts and `tsconfig*.json`; path resolution; marker operand; `git add` dry-run always; recursive rm under `src/`; `--force-create` + sed `w`/`rg --pre`/`find -fprint`; `.gitignore` on reinstall; kit development prompts) — integrate each into Scope before planning, as written there?
2. **`.tdd-red/**`: ask (this spec) or deny (harness H1)?** Only `tdd-prove-red.sh` writes it, from a hook process that PreToolUse never sees.
3. **Recursive `rm`/`mv` under a protected dir: ask (this spec) or deny (harness H3)?** `CLAUDE.md` says "without explicit user confirmation", which reads as ask.
4. **`.github/workflows/**`** (harness H1): add to the guarded set here?
5. **Does a hook `ask` override `acceptEdits`?** Undocumented; settled by one local probe before EXECUTE (a throwaway PreToolUse hook returning `ask` on a Write in `acceptEdits`). If it does not, P2's Write/Edit asks are void and the guard must be a `deny` with a "write it yourself or `!`" text.
6. **Measure**: `docs/measuring-the-loop.md:9-12` cites the "5 minutes behind one unapproved Write" with no transcript; `kit-measure.py` has no dead-time measure. Before/after measured how, or not in this pass?
