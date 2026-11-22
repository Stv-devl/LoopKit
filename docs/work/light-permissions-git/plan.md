# Plan: Git rules and the narrow permissions — amendment 2   (entry: docs/specs/light-permissions-git.md · research: docs/work/light-permissions-git/research.md · design: n/a)
Token profile: critical

Re-entry after amendment 2 (re-review FAIL). Amendment 1 is implemented and staged;
its cases (G11, G12, X22, I3, I1b, K1b, K1c) and the first pass's (G1-G10, I1-I2, K1)
are **frozen and green**; decisions of both earlier gates: `prior-gate.md`. Every case
below is a **pure addition**. This plan also fixes the in-contract re-review Majors
(each opens with its reproduction case).

## Skips
- DB, Backend, Front, Wiring, INTERFACE : SKIP — kit tooling, no screen.
- TypeScript test-first layers : none; fixture rows are the RED legs, observed failing before the code. Freeze = plan rule (`## Gate` `amended …`).
- Install, shell guard : SKIP — no change (re-review cleared both).
- `# cwk-guard-api` bump : SKIP — api 1 unshipped.

## Write chain (sequential)
1. **Rows RED** — G13 + G11.13c/G11.09i/G12.04-05 into `fixtures/_harness/git-guard.jsonl`, `-ignored-` and `-envkeep-` setups in `test-hooks.sh` → run, observe each Reproduction case fail.
2. **GREEN `enforce-git-workflow.sh`**, rerunning `test-hooks.sh` after each:
   a. `#` comment test on the last emitted char (G13.14);
   b. `git stage` = add everywhere: main parse, alias deny, floor, unread fallback, cap (G13.04-05, G13.23, G13.25-27);
   c. commit `-p`/`--patch`/`--interactive` (G13.06-08);
   d. "add alone" rule (G13.01-03, G13.09, G13.19-20, G13.28, G13.28b; G13.15-18, G13.29 pass);
   e. raw sub scan for the cap, the floor and the UNPARSABLE path (G13.10-13, G13.24);
   f. header and `ADD_UNREADABLE_REASON` text.
3. **Harness** — `test-hooks.sh`: drop the `HOME` move (keep `XDG_CONFIG_HOME` scratch); `run_git_guard_cases` and setup comments list every setup.
4. **Docs** — K1d RED → `docs/ADAPTATION.md` §15, `docs/Claude_Workflows.md`, `.claude/agents/github.md` GREEN.
5. **Refactor** — under a green suite; no case edited.
6. **Full gates** — `test-hooks.sh` (run directly), `kit-doctor.py`, `test-install.sh`, `test-workflow-contracts.sh`.
7. **Smoke K2** rerun (same 8 calls as `prior-gate.md`) + K2c: `echo x > src/x.ts && git add src/x.ts` (tracked path: the dry-run says `ok`, so the add-alone rule is what denies) → in `permission_denials` with the hook's `unreadable git add` reason.

Every step edits a guarded path (asks the user). Probe strings with `git add -f`: `printf` escapes.

## Parallel lots
none — fully sequential (one hook, one harness).

## Track isolation
- Worktree: none, single track (main tree, `audit/slim`). Shared foundations: kit hooks. No other pass beside.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | step 2 |
| `.claude/hooks/fixtures/_harness/git-guard.jsonl` | Edit (append) | G13, G11.13c, G11.09i, G12.04-05 |
| `.claude/hooks/test-hooks.sh` | Edit | `-ignored-`, `-envkeep-`, `-stalias-` setups; HOME line; comments |
| `docs/specs/light-permissions-git.md` | Edit | G12 harness wording (R2-OQ6), after the go |
| `.claude/hooks/test-workflow-contracts.sh` | Edit (append) | K1d |
| `docs/ADAPTATION.md`, `docs/Claude_Workflows.md`, `.claude/agents/github.md` | Edit | amendment-2 behaviour, `git -C` hint, asks list |

## Contracts — `enforce-git-workflow.sh`
- **Comment test.** `strip_comments` treats `#` as a comment only when nothing was emitted yet or the last emitted char is in `WORD_START`.
- **`git stage`.** `parse_git` computes the add verdict for `sub in ("add", "stage")`; `fallback_rows` and `raw_subs` emit `?fb-add` for `stage`; the floor denies `stage` like `add`; the deny loop's alias rule becomes `SUB ∉ {add, stage}` and `EFF_SUB ∈ {add, stage}` → `ADD_HIDDEN_REASON`.
- **Commit flags.** `COMMIT["dangerous"]` += `patch: --patch`, `interactive: --interactive`; `short` += `p: --patch`. Rendered in the existing ask (`uses --patch`).
- **Add alone.** A segment, after prefix stripping, that is not a git call whose subcommand is `add`, `stage`, `status`, `diff` or `log` (global options skipped as in `parse_git`) marks `state["prior"] = True` **once the segment is done** (its own nested walks included): `walk` keeps the mark pending, applies it at the start of the next segment, **and applies any mark still pending when the walk ends** (a nested walk's last segment marks prior for what follows), so a segment's own nested add sees only earlier segments. Prefix-only segments do not count; an assignment-only segment counts. `PREFIXES` unchanged (a `builtin cd` segment is a prior statement). In `parse_git`, for `add`/`stage`: `cd` first (unchanged), else `addv = add_verdict(...)`, then `if addv == "ok" and state["prior"]: addv = "prior"`. `add_reason prior` → `ADD_UNREADABLE_REASON`. A statement **after** the add never counts.
- **Raw sub scan** (cap, floor, UNPARSABLE). Python `raw_subs(text)`: `\`+NL removed, then every quote, backtick, `$(`, `(`, `)`, `;`, `&`, `|`, newline is a separator; at each `git`/`*/git` word skip global options (`WITH_VALUE` with their value, other `-…`), read the subcommand. When capped, after the strict logical-line rows, append `?fb-add` for each raw `add`/`stage` and `?fb-cap\t…\t<sub>:\t-` for each raw `commit|switch|checkout` (items empty: the earlier strict rows keep the flag list first). On the UNPARSABLE (shlex failure) path, append `?fb-add` for each raw `add`/`stage` found in the **heredoc-free** text (adds only: a heredoc commit body is never scanned). Bash `floor_subs` replaces `"`, `'`, `` ` ``, `$` with spaces before splitting. Accepted, degraded paths only: a commit message naming `git add` is denied there.
- **Texts.** `ADD_UNREADABLE_REASON`, whole string: "BLOCKED: unreadable git add — the hook could not read this call (a wrapper such as timeout, stdbuf or xargs, a cd before it, another command before it, or a parse failure). Run `git add <paths>` alone, as its own call, with literal paths (`git -C <tree> add …` for another tree)." It keeps `cd before` (frozen G11.17, G11.18). Header: the add-alone rule, `git stage`, `--patch`.

## Test plan (gate — validated by the user before EXECUTE)

### Git fixtures — append to `.claude/hooks/fixtures/_harness/git-guard.jsonl`, cwd `__FEAT_TREE__` unless named
`-ignored-` setup: the feat tree gets an untracked `.gitignore` holding `.env*`, `*.pem`, `!.env.example`, plus the `-secrets-` files (untracked `.env.local`, `certs/a.pem`). `-envkeep-` setup: untracked `.env.sample`, `.env.template` in the feat tree. `-stalias-` setup: the repo config gains `alias.st stage`. Reason substrings in parentheses.
**Reproduction** (each measured passing on the staged hook — the re-review FAIL)
- [ ] G13.01 deny, `-ignored-`: `mv .gitignore g.old && git add -A` (`another command before`).
- [ ] G13.02 deny, `-ignored-`: `sed -i '/pem/d' .gitignore && git add .` (`another command before`).
- [ ] G13.03 deny `echo x > src/y.ts && git add src/x.ts` (`another command before`).
- [ ] G13.04 deny, `-secrets-`: `git stage -f .env.local` (`--force`); G13.05 deny, `-secrets-`: `git stage .env.local` (`.env.local`).
- [ ] G13.06 ask `git commit -m x -p` (`uses --patch`); G13.07 ask `git commit --interactive -m x` (`uses --interactive`); G13.08 ask `git commit -m x --pat` (`uses --patch`).
- [ ] G13.10 deny, `-secrets-`: 50× `git status; ` then `bash -c 'git add -f .env.local'` (`unreadable git add`); G13.11 ask: 50× `git status; ` then `bash -c 'git commit -m x --amend'` (`more than 50`).
- [ ] G13.12 deny, `-nopy-`: `bash -c 'git add -f .env.local'` (`unreadable git add`); G13.13 ask, `-nopy-`: `sh -c 'git commit -m x --amend'` (`could not run its parser`).
- [ ] G13.14 deny, `-secrets-`: `ls x\⏎# ; git add -f .env.local` (`--force`).
- [ ] G13.23 deny, `-stalias-`: `git st src/x.ts` (`hides`) — alias to `stage`.
- [ ] G13.24 deny, `-secrets-`: `bash -c 'git add -f .env.local' <<'E'⏎it's⏎E` (`unreadable git add`) — UNPARSABLE path.
- [ ] G13.25 deny, `-nopy-`: `git stage -f .env.local` (`unreadable git add`); G13.26 deny, `-secrets-`: `timeout 5 git stage .` (`unreadable git add`); G13.27 deny, `-secrets-`: 50× `git status; ` then `git stage -f .env.local` (`unreadable git add`).
**Business rules**
- [ ] G13.15 pass `git status && git add src/x.ts`; G13.16 pass `git -C . add src/x.ts`; G13.17 pass `git add src/x.ts && git commit -m x`; G13.18 pass `git diff && git log -1 && git add src/x.ts`.
- [ ] G13.09 deny, `-secrets-`, cwd `__FEAT_TREE__/src`: `builtin cd .. && git add .` (`unreadable git add`) — a prior statement.
- [ ] G13.19 deny `X=1; git add src/x.ts` (`unreadable git add`); G13.20 deny `printf x | git add src/x.ts` (`unreadable git add`).
- [ ] G13.28 deny, `-ignored-`: `git status "$(mv .gitignore g)" && git add -A` (`another command before`); G13.28b deny, `-ignored-`: ``git diff "`mv .gitignore g`" && git add -A`` (`another command before`) — a nested walk's last statement counts (kills "pending mark dropped at the end of a walk").
- [ ] G13.29 pass `bash -c 'git add src/x.ts'` — a segment's own nested add sees only earlier segments.
**Edge cases / guards** (pass or already right today; mutant named)
- [ ] G11.13c ask `git commit -\⏎am $'it\'s'` (`--all`) — kills "fallback join removed" (only the `split_only` path needs it).
- [ ] G11.09i deny, `-nopy-`, cwd `__MAIN_TREE__`: `git \⏎commit -m x` (`never commit on 'main'`) — kills "floor without its pass (2)".
- [ ] G12.04 pass, `-envkeep-`: `git add .env.sample`; G12.05 pass, `-envkeep-`: `git add .env.template` — kill `SECRET_KEEP` shrunk to `.env.example`.
- [ ] G13.21 pass `git commit -m "fix # 12"` and G13.22 pass `git commit -m x # note` — the comment rule still strips a real comment and keeps a quoted `#`.

### Contracts — append to `.claude/hooks/test-workflow-contracts.sh`
- [ ] K1d `ADAPTATION.md` §15 (sliced from `## 15.` to the next `## `) holds `seul dans son appel` and `git stage`; `github.md` holds `git -C <tree> add` and `--include`; `Claude_Workflows.md` holds `--patch`.

### Regression
- [ ] Every existing case unchanged and green: git fixtures 01-85, G1-G12 rows, X1-X22, every other hook's fixtures, I1-I3, K1-K1c.

### Smoke (step 7)
- [ ] K2 rerun, same 8 calls and expectations as `prior-gate.md`.
- [ ] K2c `echo x > src/x.ts && git add src/x.ts` → in `permission_denials`, the hook's `unreadable git add` reason in the transcript.

## Research open questions — proposed answers, decided at the gate
- R2-OQ1 `git -C <dir> add` first in the call is alone → pass (G13.16).
- R2-OQ2 status/diff/log before the add are allowed (G13.15, G13.18).
- R2-OQ3 an assignment-only statement before the add counts → deny (G13.19).
- R2-OQ4 a pipe into the add counts → deny (G13.20).
- R2-OQ6 amendment-1 spec text says fixtures run with an empty `XDG_CONFIG_HOME` and `HOME`; the harness keeps a scratch `XDG_CONFIG_HOME` only → amend that spec line to "a scratch `XDG_CONFIG_HOME`" after the go.
- R2-OQ5 minors in: github.md hint + asks list, harness comments, HOME→XDG only, G12.04-05. Follow-ups (out): floor/cap over-deny of a message naming `git add` (documented), `git -c core.hooksPath=…` commit, `g\it` prefilter, `export GIT_WORK_TREE=…`, `.env*` back-fill into old `.gitignore` blocks, a nested `bash -c`/`$()` string shlex cannot read (`?unread`: not allow-listed, prompts); plus the earlier follow-ups in `prior-gate.md`.

## Plan critic
- completeness: 95
- quality: 93
- surviving blockers: none
- passes: 1 FAIL (72/60), 2 FAIL (90/80), 3 clear; pass-3 Minor (G13.28b in step 2d) folded in.

## Vigilance (carried from research)
- "Alone": only add/stage/status/diff/log before; prefix-only segments ignored; nested `$()` before counts; nothing after counts.
- The add-alone rule applies only to an `ok` verdict: frozen reasons `--force`, `same call`, `cd before` unchanged.
- `git stage` gets every add rule (force, hidden, nodry, cd/prior, dry-run, alias, floor, unread fallback, cap, UNPARSABLE scan), one case per path.
- `prior` is applied once a segment is done: nested statements before the add count, a segment's own nested add does not see itself.
- Raw scans treat quotes, `$(`, backticks as separators; their over-deny is confined to the degraded paths.
- Comment test reads the last emitted char.
- `-p` maps to `--patch` only in the commit family.
- Every new case is an append; no existing case body, id or reason changes; `-secrets-`, `-envmod-` setups untouched.
- Earlier vigilance (`prior-gate.md`, frozen behaviour) still holds.

## Acceptance criteria (carried from the entry artifact)
- [ ] On a real light pass: no prompt for edits, `git add <paths>`, `git commit -m "<one line>"`, gates; `git push`, `gh pr *`, `git commit -m x --amend`, `git switch -c x --discard-changes` still prompt. (Proved before merge by the smoke; re-observed on the next light pass.)
- [ ] `git add -f .env`, `git add --forc .env.local`, and `git add .` with an untracked `certs/a.pem` are denied; `git add .env.example` and `git add src/x.ts` pass.
- [ ] An upgrade over hooks without the guard api gets no `defaultMode` and no new allow; a customised but current install gets both.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-install.sh`, `test-workflow-contracts.sh` pass.

## Gate
- 2026-10-30 go
- Contract: as written (amendment 2: `git add`/`git stage` alone, `git stage` = add, commit `-p`/`--patch`/`--interactive` ask); R2-OQ6 applied after the go: spec G12 line "an empty `XDG_CONFIG_HOME` and `HOME`" → "a scratch `XDG_CONFIG_HOME`".
- Earlier gates (OQ1-OQ8, R-OQ1-R-OQ8, K2 method) carried from `prior-gate.md`.
- R2-OQ1 `git -C <dir> add` first in the call → pass (G13.16).
- R2-OQ2 status/diff/log before the add allowed (G13.15, G13.18).
- R2-OQ3 assignment-only statement before the add → deny (G13.19).
- R2-OQ4 pipe into the add → deny (G13.20).
- R2-OQ5 minors in (github.md hint + asks list, harness comments, HOME→XDG only, G12.04-05); follow-ups out as listed in the plan.
- R2-OQ6 → spec wording amended as above.
- 2026-10-30 EXECUTE (amendment 2) done: G13 rows + `-ignored-`/`-envkeep-`/`-stalias-` setups RED (22 verdicts + the G13.08 reason) → hook GREEN; harness HOME move dropped (scratch XDG only), comments; K1d RED → docs GREEN; refactor: nothing left (`ADD_SUBS`, `QUIET_SUBS`, `raw_rows`, `quiet_git` already shared). Gates green: `test-hooks.sh` 626 cases, `kit-doctor.py` no divergence, `test-install.sh`, `test-workflow-contracts.sh`.
- 2026-10-30 K2 rerun green (same 8 verdicts and reasons); K2c `echo x > src/x.ts && git add src/x.ts` → in `permission_denials`, reason "BLOCKED: unreadable git add — … another command before it …", tree unchanged.
