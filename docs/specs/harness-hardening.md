# Spec index: Harness hardening
Source: harness audit of 2026-10-27; prompt audit, review and refutation of 2026-10-29 (3 reviewers, 3 verifiers). The single spec was not plannable as written: its baseline no longer matched the code, and its Phase 4 opened holes. It is split into four specs, each a loop pass of its own.

| Spec | Profile | Needs |
| --- | --- | --- |
| `docs/specs/harness-hooks.md` | critical | `light-permissions-git` shipped |
| `docs/specs/harness-prompts.md` | critical | `light-permissions-git`, `harness-hooks` A0/A2/A4/A5 shipped |
| `docs/specs/harness-cd.md` | critical | — |
| `docs/specs/harness-kit-ci.md` | standard | `harness-cd` DC1 (cached SHAs) |

Order: `harness-hooks` → `harness-prompts` → `harness-cd` → `harness-kit-ci`.

Second review and refutation on 2026-10-30 (3 reviewers, 3 verifiers), corrected in place:
- `harness-hooks`:
  - A0 is new: the install hold-back.
  - A2 now covers `--refmap`, `branch -M/-C`, globs, `clone -u` and restores of frozen tests.
  - A4 now covers targets outside the project, the resolution base, tsc and configs.
  - A6 is rewritten: glob expansion and the grep wrapper.
  - A7 gets a new resolver; `SECRET_RE` is left untouched.
- `harness-prompts`: tsc, playwright and suite forms, the `uv` allows moved to the addon, a static measure, and `HP-` contract labels.
- `harness-cd`: the dispatch path and exact contracts.
- `harness-kit-ci`: one proof per K1 branch, `kit` no longer required in targets, and a named `--lefthook` option.

## Open follow-ups
- From `git-allow-grammar` (OQ4, plan pass of 2026-10-31): `sed -n -f`, `sed -n --expr='1e …'` and `rg --hostname-bin` run a file or a command with no decision from either hook. Fix: `shell_targets.py` asks on them, or the `Bash(sed -n *)`/`Bash(rg *)` allows narrow. Not a regression: both allows are in HEAD since `1365a28`.
- From `git-allow-grammar` review (2026-10-31), for `harness-hooks` A3: `git log --output=.git/refs/heads/main` and `--output=.git/config` run with no prompt (`git log *` allowed, `.git/` outside the shell guard lists, while `protect-files.sh` denies Write there). Measured: `main` moved with no reflog entry, a replaced config ran a script on the next `git status`. With P1's free commit, a feature commit can land on `main` this way, no prompt until the push. Pre-existing in HEAD. Fix measured on a copy: `'.git/*'` in `CWK_GUARD_DENIED` plus a general deny text; `rm -rf .git` then goes from ask to deny.
- From the same review, re-check before running: the grammar asks last on any call naming `git` and `add`, so `harness-hooks` A2 (`:95`, fixture `pass` for `git worktree add .claude/worktrees/x -b feat/x`; `:239`) cannot go green, and the `harness-prompts` allow `Bash(git worktree add .claude/worktrees/*)` (`:52`) removes no prompt, a hook ask overrides an allow. Frozen G14.70 pins the ask. Line citations of `enforce-git-workflow.sh` in `harness-hooks` (`:67`, `:191`) moved too.
- Accepted limits of the same review: a `.gitignore` edit in an earlier call makes a later strict add of the once-ignored file pass (same power as Write under `acceptEdits`, the secret list holds); `git add <tracked dir removed from disk>` passes; `is_secret` is case-sensitive and reads the basename.
- From the re-review of the same pass (2026-10-31), the hook-timeout fail-open that `docs/work/light-permissions-git/prior-gate.md:13` says was carried here and never was: `enforce-git-workflow.sh` scans `\bgit\b[^|;&]*\bcommit\b` and `\bgh\b[^|;&]*\bcomment\b` are quadratic under a UTF-8 locale (60 KB: 5.4 s, 0.002 s under `LC_ALL=C`), so past about 55 KB the hook is killed at its 5 s timeout with no decision. Measured on 2.1.316: a timed-out hook does not block (a stand-in hook sleeping 12 s let `git add -f ignored.txt` run with no prompt), and the shipped config is saved only by the matcher, which refuses over 10000 characters before an allow applies, an undocumented constant (a padded call prompts, or is denied in `-p`). It degrades a deny to a generic prompt today, and staged with no prompt under `--dangerously-skip-permissions` or a whole-tool `Bash` allow. A later Claude Code raising that limit reopens it. Fix: `LC_ALL=C` on both scans (speed measured, matching not), and `"onFailure": "block"` on the guard handlers.
- From the `/audit:security` of the same pass (2026-11-01): **the re-audit of `readable_git_dir` did not conclude** (a safety classifier stopped it); its premise, that a git dir under a `.git` segment cannot be written with no prompt, rests on `protect-files.sh` for Write. `mv`, `cp -r` and `mkdir -p` into a new `x/.git` pass `prevent-destructive-commands.sh`; only Claude Code's protected-path prompt would stop them, not driven. `git status` and `git diff` in a planted repository still run its config (reviewer measured the real call, pre-existing). `--git-dir` and `--work-tree` values with shell characters are not covered by the `-C` deny. `"onFailure": "block"` closes the timeout fail-open above for the guard hooks on 2.1.316; `LC_ALL=C` on the two scans is still open, a padded call now blocks instead of prompting.
- From the same re-review: the 4000-character cut in `decide` adds no truncation marker, so a long secret list or alias reason ends mid-word with its advice gone (the verdict holds); no case covers a long reason on `ask`; G10.03 relies on Linux's per-argument limit, so a bound on the reason is not asserted elsewhere.

## Where each old item went
Older docs cite these ids (`docs/work/small-lane/plan.md`, `docs/specs/light-permissions.md`, `docs/work/light-permissions-git/prior-gate.md`).

| Old | Status |
| --- | --- |
| H1 guarded paths ask, `.tdd-red` denied | shipped (d6839cb, 1a92ff0) |
| H2 secrets | `harness-hooks` A6. Dropping `Bash(grep *)` is removed because it has no effect. `grep -r KEY .` is covered by Claude Code's grep wrapper (measured); its bypass forms ask. Bare `set` asks. |
| H3 destructive git and shell | git → `harness-hooks` A2; `.git` deny → A3; `rm -rf src/*`, `docs`, `curl \| bash` already ask; `docs` not added to `PROTECTED_DIRS` |
| H4 RED marker digest | `harness-hooks` A1 |
| H5 auto-approve paths | `..` shipped (bc11dea); open part → `harness-hooks` A7 |
| H6, H7, H8, H9 | `harness-cd` C1, C2, C3, C4 |
| H10, H11, H12 | `harness-kit-ci` K3, K2, K4 |
| H13 allowlist | `harness-prompts` B2, exact forms only |
| H14 `.kit-dev` exemption | dropped (`harness-prompts` B3) |
| H15 no interpreter writes | rule → `harness-prompts` B1; TDD deny on heredocs → `harness-hooks` A5 |
| D1 | `harness-hooks` DA1 |
| D2, D3 | `harness-cd` DC1, DC2 |
| D4 (OQ7) | `harness-kit-ci` K1 / DK1 |
| D5 | answered by `docs/research-cache/claude-code-permissions.md`; remaining → `harness-prompts` DB1, DB2 |

Found by the review, not in the old spec: tool flags that delete or write folders through today's allows (`pnpm build --outDir src`, `--coverage.reportsDirectory`, `--outputFile`, `pnpm lint --fix`) → `harness-hooks` A4.
