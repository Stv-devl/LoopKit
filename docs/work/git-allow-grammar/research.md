# Research: Allow-list grammar for the P1 git commands   (entry: docs/specs/git-allow-grammar.md)
Token profile: critical

Rerun after the contract amendment of 2026-10-30 (trigger A, grammar ask last). Base: the staged `light-permissions-git` work (BLOCKED, review 3x), mapped by that pass (`docs/work/light-permissions-git/`). No explorer: no surface is unmapped. Every verdict below was measured on a throwaway copy of the staged tree (`scratchpad/gac4/` of session b95f0a01), through the real `test-hooks.sh`.

## Pattern to follow
- `ask`/`deny`/`decide` in `.claude/hooks/hook-lib.sh`, called from `enforce-git-workflow.sh`; rows in `.claude/hooks/fixtures/_harness/git-guard.jsonl`, setups selected by fixture name (`test-hooks.sh:174-204`).

## Wiring points
- Decision order in `enforce-git-workflow.sh`: protected-branch commit deny, signing and trailer denies, python floor, deny loop (parser verdicts), then asks (gh, push, merge, row asks), then the `PARSE_FAILED` floor, then the final `exit 0`. The grammar ask goes just before that final `exit 0`; measured: no existing deny or ask changes reason.
- The early exit (`grep -qE '\b(git|gh)\b'`) must also let through `xgit`, or the trigger never runs on a glued spelling.
- The dry-run secret check runs in the parser for every parsed add row, strict forms included.

## Reusable
- `decide`/`ask`/`deny`; the `_harness/git-guard.jsonl` runner; setups `-secrets-`, `-ignored-`.
- `-ignored-` creates `.feat/certs/` only in the feat tree (`test-hooks.sh:192-197`): a directory the main tree lacks, usable to prove the `-C` directory check.
- `docs/research-cache/claude-code-permissions.md`: the matcher needs every newline/separator part allowed; a hook `ask` overrides an allow rule and `acceptEdits`.

## Blast radius
- **Frozen cases that flip `pass` → `ask`** (measured, with no amendment: exactly these 20): G3.04, G3.05, G3.06, G3.07, G6.02, G8.03, G8.04, G9.14, G11.15, G11.15b, G11.19, G11.20, G13.15, G13.16, G13.17, G13.18, G13.22, G13.29, and the fixture files `13-f11-heredoc-apostrophe-pass.json`, `50-h2-heredoc-message-apostrophe-pass.json`. Trigger A flips none beyond the former trigger: the suite is green with the same 20 amendments.
- `floor_subs` no longer needs any change: reverting it to the staged text stays green (701 cases), because the trigger no longer reads it.
- **Kit flows**: `.claude/commands/loop/small.md:16` runs the fork as separate calls. `git -C <tree> commit -m …` matches no P1 allow (`.claude/settings.json:14-23`), so it prompts natively with or without a strict form (from the rules, not measured). Dropping it from the strict forms keeps the suite green.
- Docs that describe the deny-list behaviour as prompt-free: `docs/ADAPTATION.md` §15 ("peuvent le précéder"), `.claude/agents/github.md` step 2 ("git add/stage/status/diff/log"), `docs/Claude_Workflows.md`.

## Measured trigger behaviour
- Now ask (all pass with no decision on the former NORM scan): `git status x\\⏎git add -A`, `git diff --output=.gitignore -- x\\⏎git add -A`, `git status #c\⏎git add -A`, `git status x\\⏎git commit -mall`, `cat x\\⏎git commit -F msg.txt`.
- Also ask: `git\⏎ add -A`, `gi\⏎t add -A`, `git add\⏎ -A`, `git status && git a\⏎dd -A`, `/usr/bin/git add -A`, `git$x add -A`, `git<TAB>add -A`, `git -C "src/a b" add -A` (the former trigger missed this one).
- Over-match, now ask: `git log --grep add`, `git diff src/commit.ts`, `git status -- add`, `git worktree add ../x`, `git remote add o u`.
- Untouched: `grep -n commit .claude/agents/github.md`, `cat .gitignore && echo add`, `grep -rn stage .github/workflows`, `git status && git diff --stat && git log -1`, `git log --oneline -- src/address.ts`, `git branch --show-current`, `git worktree list`.
- Strict check: a `\r` passes `[[:space:]]` trimming, so `git add src/x.ts<CR>` was strict; trimming only space and tab and refusing any control character makes it ask. `git commit -m "a<CR>b"` likewise.

## Live DB state
n/a — kit tooling.

## External surface
- `git status x\\⏎git add -A` ran with no prompt on the P1 allow rules, and `git diff --output=.gitignore -- x\\⏎git add -A` ran with no prompt on them plus the former hook: `.gitignore` truncated, `ignored.txt` staged `[measured 2026-10-30, claude -p 2.1.314]`.
- `git status #c\⏎git add -A` prompted on the allow rules alone `[measured 2026-10-30, 2.1.314; undocumented, so the hook must not rely on it]`.
- The matcher strips `timeout`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, bare `xargs` before matching `[cache 2026-10-28]`: wrapped forms must ask, and do.
- Spellings with no literal `git` once normalised (`$'\x67it'`, `gi$'t'`, `gi$''t`, ``gi``t``, `gi$(true)t`, `${X:-gi}t`) get no hook decision and rely on the matcher: `gi$''t`, `$'\x67it'`, `git a$''dd`, `git $'a\x64d'`, `git a[d]d`, `git ad?`, `git a{dd,}` all prompted on the P1 allows alone `[measured 2026-10-30, 2.1.314]`. `${X:-git} add …` does trigger (`git}`).
- Allowed readers can run code `[measured 2026-10-30, 2.1.314, shipped hooks]`: `sed -n '1e …'` asks through `prevent-destructive-commands.sh` (`shell_targets.py`, unresolved write target); `sed -n -f s.sed f.txt` and `rg --hostname-bin=./s.sh …` ran a forced `git add` with no prompt and no hook decision. `find … -exec`, `rg --pre`, `cat <(…)`, `git status <(…)` prompted. `docs/work/guard-shell/plan.md:59,145` owns the first two sed/rg forms and accepts `sed -f` as a limit on writes; `rg --hostname-bin` is in no spec. Both allows date from `1365a28`.
- The matcher decodes `\` in the command head: `g\it add c.txt` and `echo x\\\\⏎g\it add a.txt` were approved under `Bash(git add *)`, while `git a\dd add` prompted `[measured 2026-10-30, 2.1.314]`. So the normalised reading is required, not optional.
- Bash regex classes follow the locale: `[A-Za-z0-9…]` matches 3266 non-ASCII code points under `fr_FR.UTF-8` (this machine's `LANG`), none under `C` `[measured 2026-10-30, glibc 2.39, bash 5.2]`. All 13064 word positions tried stayed one literal word in bash, so this is a verdict difference, not a bypass.

## Traps (points of vigilance for the review)
- Every existing deny and ask decides before the grammar ask, and keeps its reason.
- The trigger decides no statement boundary and no left boundary for `git`. It must never under-match an auto-approvable add/stage/commit/switch, in the raw reading or the normalised one, and the early exit must never stop it.
- Right boundary of `git`: a real `git` word always ends in whitespace or a separator in the raw text, and NORM only deletes quotes, `\` and `\`+newline, so this boundary cannot hide a call. The review tries to refute that.
- Strict forms match the whole text after trimming space and tab: no control character anywhere, no `;`, no comment, no second statement.
- Strict add: safe charset, no `.`/`..` component, not `-…`, not a directory in the add's tree (the `-C` tree when given).
- Strict commit: no `$`, backtick, `\`, enclosing quote, newline; non-empty; both quote classes tested.
- The parser never turns a triggered non-strict call into a pass.
- Amended cases are recorded one by one in `## Gate`; every frozen doc needle survives.

## Open questions
1. `git commit -m <word>` unquoted (`07-f05` `git commit -m x`, G8.01 `git commit -m amend`): strict? Settled by the user at the gate.
2. `git -C <dir> commit -m …`: strict, as the first research proposed for the small lane? The premise does not hold: P1 has no matching allow. Settled by the user at the gate.
3. The 20 flips: accepted as `ask`? Settled by the user at the gate.
4. Spellings with no literal `git` once normalised (`$'\x67it'`, `gi$'t'`) stay untriggered, relying on the matcher? Settled by the user at the gate; K2e measures the matcher.
5. Strict add of a path created by an earlier call: any change? Settled by the user at the gate.
6. The over-match of trigger A (`git diff src/commit.ts`, `git log --grep add`, `git worktree add ../x` prompt): accepted? Settled by the user at the gate.
