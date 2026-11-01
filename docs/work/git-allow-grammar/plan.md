# Plan: Allow-list grammar for the P1 git commands   (entry: docs/specs/git-allow-grammar.md · research: docs/work/git-allow-grammar/research.md · design: n/a)
Token profile: critical

## Skips
- DB, Backend, Front, Wiring, INTERFACE : SKIP — kit tooling, no screen.
- TypeScript test-first layers : none; fixture rows are the RED legs, observed failing before the code. Freeze = plan rule (`## Gate` `amended …`).
- Install, shell guard, P1 settings : SKIP — unchanged base (staged `light-permissions-git` work). `test-hooks.sh` needed no edit for the plan's rows; review added G10.03 there (`## Gate`).
- `# cwk-guard-api` bump : SKIP — api 1 unshipped.
- `floor_subs` : SKIP — unchanged; the trigger does not read it.

## Write chain (sequential)
1. **Rows RED** — G14 rows appended to `.claude/hooks/fixtures/_harness/git-guard.jsonl` → run `test-hooks.sh` directly, observe each Reproduction and near-miss case fail.
2. **Amended frozen cases** — the 20 flips listed under "Amended" (18 jsonl rows edited in place: verdict `pass` → `ask`, reason `not a plain git call`; 2 fixture files renamed `…-pass.json` → `…-ask.json` with `"_expect_reason":"not a plain git call"`), each recorded in `## Gate` as an `amended` line, edited by the main thread only.
3. **GREEN `enforce-git-workflow.sh`** — normalised text, early exit, strict-form check, trigger, the grammar ask **last** (just before the final `exit 0`); header text.
4. **Docs** — K1e RED → `docs/ADAPTATION.md` §15, `docs/Claude_Workflows.md`, `.claude/agents/github.md` GREEN.
5. **Refactor** — clean the grammar block with the suite green; no case edited.
6. **Full gates** — `test-hooks.sh` (run directly), `kit-doctor.py`, `test-install.sh`, `test-workflow-contracts.sh`.
7. **Smoke** — K2 (8 calls of `docs/work/light-permissions-git/prior-gate.md`), K2d, K2e, K2f, K2g.

Every step edits a guarded path (asks the user). Probe strings with `git add -f`: the Write tool, never a Bash heredoc (the session's own hook reads heredoc bodies).

## Parallel lots
none — one hook, one fixture file.

## Track isolation
- Worktree: none, single track (main tree, `audit/slim`). Shared foundations: kit hooks. No other pass beside.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | normalised text, early exit, grammar, header |
| `.claude/hooks/fixtures/_harness/git-guard.jsonl` | Edit | G14 appended; 18 amended rows |
| `.claude/hooks/fixtures/enforce-git-workflow.sh/{13-f11-heredoc-apostrophe,50-h2-heredoc-message-apostrophe}-pass.json` | Rename → `-ask.json` + `_expect_reason` | amended |
| `.claude/hooks/test-workflow-contracts.sh` | Edit (append) | K1e |
| `.claude/hooks/test-hooks.sh` | Edit (append, review) | G10.03, G15 |
| `.claude/hooks/tdd-freeze-tests.sh` | Edit (audit) | `python3 -I` |
| `.claude/settings.json` | Edit (audit) | `onFailure` |
| `docs/specs/harness-hardening.md` | Edit (review) | follow-ups |
| `docs/ADAPTATION.md`, `docs/Claude_Workflows.md`, `.claude/agents/github.md` | Edit | strict forms are the only prompt-free ones |

## Contracts — `enforce-git-workflow.sh` (bash, no python dependency)
- **Normalised text** `NORM`: `$COMMAND` with every `\`+newline removed, then every `'`, `"` and `\` character removed. `NORM` serves the early exit and the trigger only.
- **Early exit**: replaces `echo "$COMMAND" | grep -qE '\b(git|gh)\b' || exit 0` with a grep of `$COMMAND` and `NORM` for `git|\bgh\b`, with no boundary on `git`.
- **Trigger**, on each of `$COMMAND` and `NORM`: the text matches `git($|[^A-Za-z0-9_])` and matches `(^|[^A-Za-z0-9_])(add|stage|commit|switch)($|[^A-Za-z0-9_])`. Either reading triggers. Nothing else is read: no statement, no global option, no order.
- **Locale**: the trigger, the strict check and the ask live in one function that starts with `local LC_ALL=C`, because `[A-Za-z0-9]` under bash `=~` matches 3266 non-ASCII code points under `fr_FR.UTF-8` and none under `C` (measured). Accents in a quoted message still pass under `C`. Accepted: `[[:cntrl:]]` under `C` does not see U+0080-U+009F, U+2028, U+2029, harmless in a quoted message.
- **Strict forms**, matched on `$COMMAND` (raw) after trimming leading/trailing spaces and tabs; the trimmed text holds **no control character** at all (`[[:cntrl:]]`, newline and `\r` included; a leading newline asks; a trailing newline never reaches this check, `$(...)` strips it, and it is the same call):
  - `SAFE='[A-Za-z0-9._/@+-]+'`, `WORD='[A-Za-z0-9._/@+:-]+'`, `BRANCH='[A-Za-z0-9._/-]+'`; no path, dir, branch or unquoted `<WORD>` starts with `-` (a quoted message may: frozen G8.02 `git commit -m "-n"`); no `<dir>` or `<path>` is `.` or has a `..` component. The rule reads the spelling: `./src/x.ts` and `-C ./` stay strict (same tree, harmless).
  - add: `^git( -C <SAFE>)? (add|stage)( --)?( <SAFE>)+$`; each path is not a directory: test `-d` on the path as is when it starts with `/`, else joined to the add's tree — the `-C` dir if absolute, else the base cwd joined to it, else the base cwd.
  - commit: `^git commit -m ("[^"$`\\]+"|'[^'$`\\]+'|<WORD>)$`.
  - switch: `^git switch -c <BRANCH>$`.
- **Decision**: the grammar ask is the **last** decision, just before the final `exit 0`, after every existing deny and ask: triggered and not strict → `ask "This is not a plain git call: only \`git add <paths>\`, \`git commit -m \"<one line>\"\` and \`git switch -c <branch>\` run without a prompt, each alone in its call. Show the exact call, then let the user decide."`. Every existing deny and ask keeps its reason (it decides first).
- The deny-list parser is unchanged; it never decides a pass for a triggered call any more.
- Header: the grammar is the pass rule; the parser keeps the denies and the specific asks.

## Test plan (gate — validated by the user before EXECUTE)

### Git fixtures — append to `.claude/hooks/fixtures/_harness/git-guard.jsonl` (cwd `__FEAT_TREE__` unless named; reason substrings in parentheses; setups as in the file; `⏎` is a real newline, `<CR>` a real carriage return)
**Reproduction** (each passes on the staged hook today)
- [ ] G14.50 ask: `git status x\\⏎git add -A` (`not a plain git call`) — the blocker of plan-critic pass 3: an even backslash run keeps the newline a separator.
- [ ] G14.51 ask, `-ignored-`: `git diff --output=.gitignore -- x\\⏎git add -A` (`not a plain git call`) — measured to stage an ignored file with no prompt.
- [ ] G14.52 ask: `git status #c\⏎git add -A`; G14.53 ask: `git status x\\⏎git commit -mall` (`not a plain git call` each).
- [ ] G14.01 ask, `-ignored-`: `git diff --output=.gitignore && git add -A` (`not a plain git call`).
- [ ] G14.02 ask, `-ignored-`: `git status > .gitignore; git add -A` (`not a plain git call`).
- [ ] G14.03 ask, `-ignored-`: `git status <(mv .gitignore g) ; git add -A` (`not a plain git call`).
- [ ] G14.04 ask, `-ignored-`: `git add -A & mv .gitignore g`; G14.05 ask, `-ignored-`: `git add -A | mv .gitignore g` (`not a plain git call` each).
- [ ] G14.06 ask, `-secrets-`: `echo $'\'' ; git add -f .env.local ; echo \'` (`not a plain git call`).
- [ ] G14.07 ask, `-secrets-`: `echo \ # ; git add -f .env.local`; G14.08 ask, `-secrets-`: `true\;# ; git add -f .env.local` (`not a plain git call` each).
- [ ] G14.09 ask: `echo \ # ; git commit -m x --amend`; G14.10 ask: `echo $'\'' ; git commit -m x -a ; echo \'` (`not a plain git call` each).
- [ ] G14.29 ask, `-ignored-`: `g\⏎it add -A & mv .gitignore g` (`not a plain git call`) — continuation inside the word.
- [ ] G14.30 ask: `g\it add src/x.ts`; G14.31 ask: `gi''t add src/x.ts`; G14.32 ask: `g"i"t add src/x.ts` (`not a plain git call` each) — clean path, so no parser deny decides first.
- [ ] G14.33 ask, `-ignored-`: `git -C . add -A & mv .gitignore g` (`not a plain git call`).
- [ ] G14.73 ask: `git status && git a\⏎dd -A` (`not a plain git call`) — continuation inside the subcommand.
- [ ] G14.76 ask: `xgit add -A`; G14.77 ask: `echo x\\⏎g\it commit -m x` (`not a plain git call` each) — no left boundary on `git`, and the early exit reads the normalised text.
- [ ] G14.78 deny: `echo x\\⏎g\it add src/x.ts` (`unreadable git add`) — the early exit must let the parser see it.
**Core behaviour** (strict forms pass)
- [ ] G14.11 pass `git commit -m "feat: x"`; G14.12 pass `git commit -m "fix: it's done"`; G14.54 pass `git commit -m 'feat: x'`; G14.13 pass `git switch -c feat/y`; G14.15 pass `git stage -- src/x.ts`; G14.34 pass `git stage src/x.ts`; G14.55 pass `  git add src/x.ts  ` (surrounding spaces).
- [ ] G14.35 pass `git -C __FEAT_TREE__ add src/x.ts`.
- [ ] G14.81 pass `git commit -m "été"` — accents in a message, per the spec.
- [ ] G14.91 pass `git add src/x.ts .env.example` — several paths, the form `.claude/agents/github.md` uses.
**Business rules** (near misses ask; denies keep precedence)
- [ ] G14.14 ask `git -C __FEAT_TREE__ commit -m "spec: small x"` (`not a plain git call`) *(OQ2)*.
- [ ] G14.16 ask `git add src` — a directory; G14.36 ask `git -C __FEAT_TREE__ add src` — a directory in the `-C` tree (`not a plain git call` each).
- [ ] G14.74 ask, `-ignored-`, cwd `__MAIN_TREE__`: `git -C __FEAT_TREE__ add certs`; G14.75 ask, `-ignored-`, cwd `__MAIN_TREE__`: `git -C .feat add certs` (`not a plain git call` each) — `certs` is a directory only in the `-C` tree, absolute and relative `-C`.
- [ ] G14.92 ask `git add .env.example src`; G14.93 ask, `-ignored-`: `git add src/x.ts certs` (`not a plain git call` each) — the directory check does not stop at the first path.
- [ ] G14.97 ask `git add src src/x.ts`; G14.98 ask `git add .env.example src src/x.ts` (`not a plain git call` each) — nor read only the last path (a `BASH_REMATCH` capture of `( <SAFE>)+` holds only the last one).
- [ ] G14.99 ask `git add src/../src/x.ts .env.example`; G14.100 ask `git add .env.example src/../src/x.ts` (`not a plain git call` each) — the `..` rule reads every path.
- [ ] G14.94 ask `git commit -m "a\b"`; G14.95 ask `git commit -m 'a\b'`; G14.96 ask `git commit -m -n` (`not a plain git call` each). In the jsonl, G14.94/95 are written `a\\b`: a JSON `\b` is U+0008 and would ask through the control-character rule, hiding a build that accepts `\`.
- [ ] G14.17 ask `git add src/x.ts;`; G14.18 ask `git add 'src/x.ts'`; G14.19 ask `git add src/x.ts # c`; G14.37 ask `git add src/x.ts --`; G14.38 ask `git add -v src/x.ts`; G14.39 ask `git -C .. add src/x.ts`; G14.40 ask `git add src/../src/x.ts`; G14.64 ask `git add src/x.ts<CR>`; G14.63 ask `git stage -A` (`not a plain git call` each).
- [ ] G14.47 deny `git add -- -x` (`could not confirm`); G14.48 deny `git add src/$x.ts` (`hides what it stages`); G14.49 ask `git add __FEAT_TREE__/src` (`not a plain git call`) — an absolute directory path. G14.47/48 are regression guards (deny today, deny after: a parser deny decides before the grammar).
- [ ] G14.20 ask `git commit -m "a $HOME"`; G14.21 ask `git commit -m "a\"b"`; G14.41 ask `git commit -m "a⏎b"`; G14.42 ask ``git commit -m "a `b`"``; G14.60 ask `git commit -m ""`; G14.65 ask `git commit -m "a<CR>b"` (`not a plain git call` each).
- [ ] G14.56 ask `git commit -m 'a$b'`; G14.59 ask `git commit -m 'it's'`; G14.61 ask `git commit -m ''`; G14.57 ask `git commit -m 'a' & mv .gitignore g & echo 'b'`; G14.58 ask `git commit -m "a" & mv .gitignore g & echo "b"` (`not a plain git call` each) — the two message classes refuse their own quote.
- [ ] G14.22 ask `git switch -c -x`; G14.62 ask `git switch -c a@b`; G14.23 ask `timeout 5 git commit -m "x"`; G14.28 ask `git \⏎commit -m "x"` (`not a plain git call` each).
- [ ] G14.84 ask `git commit -m x;id`; G14.85 ask `git commit -m $x`; G14.86 ask ``git commit -m 'a`b'``; G14.87 ask `git switch -c x;id`; G14.88 ask `git add src/*`; G14.89 ask `git add src/x.t?` (`not a plain git call` each) — the `WORD`, single-quote, `BRANCH` and `SAFE` classes refuse a separator, `$`, a backtick or a glob.
- [ ] G14.79 ask `git switch -c é`; G14.80 ask `git commit -m é` (`not a plain git call` each) — ASCII classes in any locale. These two only fail under a UTF-8 locale; the suite runs under this machine's `fr_FR.UTF-8`. `git add é.ts` asks too (measured with the file present; no setup holds that file, so no row).
- [ ] G14.90 ask `echo \ # ; git $x'add' -A` (`not a plain git call`) — only the raw reading triggers: `NORM` glues `$xadd`.
- [ ] G14.24 deny, `-secrets-`: `git add -f .env.local & echo x` (`--force`) — a deny precedes the grammar ask.
- [ ] G14.25 deny, cwd `__MAIN_TREE__`: `git commit -m "x"` (`never commit on 'main'`) — a strict form keeps its deny.
- [ ] G14.43 ask `git commit -m x --amend && echo y` (`uses --amend`) — an existing ask keeps its reason (the grammar ask is last).
**Edge cases**
- [ ] G14.26 ask `git log --grep "git add"`; G14.69 ask `git diff src/commit.ts`; G14.70 ask `git worktree add ../x` (`not a plain git call` each) — over-match accepted *(OQ6)*.
- [ ] G14.71 ask `/usr/bin/git add -A`; G14.72 ask `git$x add -A` (`not a plain git call` each) — `git` ending a longer word.
- [ ] G14.27 pass `git status && git diff --stat && git log -1`; G14.68 pass `git log --oneline -- src/address.ts`; G14.66 pass `grep -n commit .claude/agents/github.md`; G14.67 pass `cat .gitignore && echo add` — not triggered.
- [ ] G14.82 pass `$'\x67it' add -A`; G14.83 pass `gi$'t' add src/x.ts` — no literal `git`, no hook decision: the accepted residue of OQ4, the prompt comes from the matcher (K2e).
- [ ] G14.44 ask `git commit -F - <<'E'⏎it's the git add fix⏎E` (`not a plain git call`) — a heredoc commit body is not read as a `git add` (no deny).
- [ ] G14.45 deny, `-secrets-`: 50× `git status; ` then `bash -c 'git stage -f .env.local'` (`unreadable git add`); G14.46 deny, `-secrets-`: `bash -c 'git stage -f .env.local' <<'E'⏎it's⏎E` (`unreadable git add`) — guards of the parser's raw `stage` scan (deny before the grammar ask).

### Amended frozen cases (verdict `pass` → `ask`, reason `not a plain git call`; one `## Gate` line each) *(OQ3)*
jsonl (18): G3.04 `git add -A`, G3.05 `git add -u`, G3.06 `git add src/x.ts 2>&1`, G3.07 `git add src/x.ts > /dev/null`, G6.02 heredoc `-F -` commit, G8.03 `git commit -mall`, G8.04 `git commit -m x -uno`, G9.14 `timeout 5 git switch -c feat/add-x`, G11.15 `git commit -F msg.txt`, G11.15b `git commit --author "A <a@b>" -m x`, G11.19 `git add src/x.ts && cd src`, G11.20 heredoc then commit, G13.15 `git status && git add src/x.ts`, G13.16 `git -C . add src/x.ts` (spec: a `-C` dir is not `.`), G13.17 `git add src/x.ts && git commit -m x`, G13.18 `git diff && git log -1 && git add src/x.ts`, G13.29 `bash -c 'git add src/x.ts'`, G13.22 `git commit -m x # note`.
fixture files (2): `13-f11-heredoc-apostrophe`, `50-h2-heredoc-message-apostrophe` (renamed `-ask`).
Kept `pass` by *(OQ1)*: `07-f05-commit-on-feat` `git commit -m x`, G8.01 `git commit -m amend`.

### Contracts — append to `.claude/hooks/test-workflow-contracts.sh`
- [ ] K1e `ADAPTATION.md` §15 holds `formes strictes` and no longer holds `peuvent le précéder`; `github.md` holds `strict forms` and no longer holds `git add/stage/status/diff/log`; `Claude_Workflows.md` holds `formes strictes`.

### Regression
- [ ] Every other existing case unchanged and green: git fixtures, G1-G13 rows not amended, X1-X22, every other hook's fixtures, I1-I3, K1-K1d. The doc rewrite keeps every frozen needle: ADAPTATION `P1 held back`, `tool_use`, `tool_result`, `retirés`, `settings.local.json`, §15 `seul dans son appel`, `git stage`; github.md `git commit -m "<one line>"`, ``never `.`, `-A`, `--all`, `-u` ``, `git -C <tree> add`, `--include`; enforce-git-workflow.sh `git switch -c feat/<scope>` present and `git checkout -b` absent; Claude_Workflows `git push`, `gh pr`, `--amend`, `--discard-changes`, `chemins gardés`, `rm -r`, `pathspec`, `--patch`.
- [ ] Acceptance criterion 1 is also covered by frozen G11.01 (`git add \⏎ -f .env.local`) and G13.01 (`mv .gitignore g.old && git add -A`).

### Smoke (step 7)
Every K2 row checks that `tool_use.input.command` equals the probe byte for byte (a model can double a backslash); a different string is resent, never read as a verdict.
- [ ] K2 rerun (same 8 calls and expectations as `prior-gate.md`).
- [ ] K2d `git status && git add src/x.ts` → in `permission_denials`, reason `not a plain git call`.
- [ ] K2e `$'\x67it' add src/x.ts` and `gi$'t' add src/x.ts` → hook silent when piped (G14.82, G14.83) **and** in `permission_denials`: the matcher alone prompts on them *(OQ4)*.
- [ ] K2g `sed -n '1e gi$(true)t add src/x.ts' f.txt` → in `permission_denials`, reason `unresolved write target`: the allow approves the head, and `prevent-destructive-commands.sh` prompts *(OQ4)*.
- [ ] K2f `git status x\\⏎git add -A` → in `permission_denials`, reason `not a plain git call`; the blocker of plan-critic pass 3, measured unprompted before this hook.

## Research open questions — proposed answers, decided at the gate
- OQ1 `git commit -m <word>` unquoted is strict (`<WORD>` charset) → `07-f05`, G8.01 stay pass.
- OQ2 `git -C <dir> commit -m …` is **not** strict: the spec does not list it, and P1 has no matching allow, so it prompts either way → G14.14 ask; no frozen case flips.
- OQ3 the other flips are accepted as `ask` (18 jsonl rows + 2 fixture files above, G13.16 included by the spec's `-C` rule).
- OQ4 the grammar leaves two residues, accepted here (measured on claude 2.1.314, shipped hooks):
  - **A spelling hiding `git` or the subcommand behind an expansion** (`$'\x67it'`, `gi$'t'`, `gi$''t`, ``gi``t``, `gi$(true)t`, `${X:-gi}t`, and `git a$''dd` behind a prefix the parser cannot read): no hook decision from this hook. At the head of a call the matcher prompts (K2e); inside an allowed head, `sed -n '1e …'`, `prevent-destructive-commands.sh` prompts (K2g), except an abbreviated long option (`sed -n --expr='1e …'`): both hooks stay silent, because `sed_rows` reads only the full `--expression` (GNU sed 4.9 ran it; the matcher on this spelling is unmeasured). Same power as the second residue, same follow-up. A Claude Code update could change the first; K2e detects it. `${X:-git}` does trigger.
  - **Code run from a file by an allowed reader**: `sed -n -f s.sed f.txt` and `rg --hostname-bin=./s.sh …` ran a forced `git add` with no prompt and no git-hook decision. The call names no git word and nothing is misread, so it is outside this grammar (spec lines 6 and 22), like `pnpm test:run *` running agent-written tests. Not a regression: both allows are in HEAD since `1365a28`. Follow-up, not in this pass: `shell_targets.py` asks on `sed -f`, `sed --expr` and `rg --hostname-bin`, or the allows narrow; owned by `docs/specs/harness-hardening.md`, "Open follow-ups".
- OQ5 no change for a strict add of a path created by an earlier call (separate call; a missing path keeps its `failed` deny).
- OQ6 the over-match of the trigger is accepted: a `git` call naming one of the four words as a whole word prompts (`git diff src/commit.ts`, `git log --grep add`, `git worktree add ../x`) → G14.26, G14.69, G14.70.

## Vigilance (carried from research)
- Every existing deny and ask decides before the grammar ask (it is last): their reasons are unchanged.
- The trigger decides no statement boundary and no left boundary for `git`; it must never under-match an auto-approvable add/stage/commit/switch, in either reading, and the early exit must never stop it.
- The right boundary of `git`: a real `git` word ends in whitespace or a separator in the raw text, and `NORM` only deletes quotes, `\` and `\`+newline. The review tries to refute this.
- Strict = the whole text after trimming space and tab, no control character anywhere, no `;`, no comment, no second statement.
- Strict add: safe charset, no `.`/`..` component, not `-…`, not a directory in the add's tree (absolute `-C` used as is).
- Strict commit: no `$`, backtick, `\`, enclosing quote, newline; non-empty; both quote classes tested.
- The parser never turns a triggered non-strict call into a pass.
- Amended cases are recorded one by one in `## Gate`; every frozen doc needle survives.

## Plan critic
Pass 3 of the rewritten plan, limited to the changes since pass 2: completeness 93, quality 80. Surviving blockers: none. The one Major (no directory row before the last path) survived the verifier as a Minor: the contract is right, the gap is a row. All Minors are closed in this plan: G14.97-100, K2g in step 7, the `a\\b` encoding, `sed --expr` in OQ4, an owner for the follow-up. Measured on a throwaway build, 230 git cases: green on the correct build; `-d` on the last path only fails G14.97/98, on the first only G14.92/93/98; `..` on the last only fails G14.99, on the first only G14.100.

## Gate
2026-10-31: go.
Contract: as written.
OQ1-OQ6: the proposed answers above, accepted as printed; OQ4 with its two residues, `sed --expr` included.
Frozen-case amendments, verdict `pass` → `ask`, reason `not a plain git call`, each from this go (OQ3):
- amended 2026-10-31 G3.04: pass → ask
- amended 2026-10-31 G3.05: pass → ask
- amended 2026-10-31 G3.06: pass → ask
- amended 2026-10-31 G3.07: pass → ask
- amended 2026-10-31 G6.02: pass → ask
- amended 2026-10-31 G8.03: pass → ask
- amended 2026-10-31 G8.04: pass → ask
- amended 2026-10-31 G9.14: pass → ask
- amended 2026-10-31 G11.15: pass → ask
- amended 2026-10-31 G11.15b: pass → ask
- amended 2026-10-31 G11.19: pass → ask
- amended 2026-10-31 G11.20: pass → ask
- amended 2026-10-31 G13.15: pass → ask
- amended 2026-10-31 G13.16: pass → ask
- amended 2026-10-31 G13.17: pass → ask
- amended 2026-10-31 G13.18: pass → ask
- amended 2026-10-31 G13.22: pass → ask
- amended 2026-10-31 G13.29: pass → ask
- amended 2026-10-31 13-f11-heredoc-apostrophe: pass → ask, file renamed `-ask`
- amended 2026-10-31 50-h2-heredoc-message-apostrophe: pass → ask, file renamed `-ask`
RED 2026-10-31: 77 G14 rows failed on the staged hook, every Reproduction row among them; no existing case broke. GREEN: `test-hooks.sh` 726 cases.
Gates 2026-10-31: `test-hooks.sh` 726 green, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` exit 0.
Smoke 2026-10-31 (claude 2.1.316, `--model sonnet`, `--settings <target>/.claude/settings.json`, core install: `acceptEdits`, 31 allows, nothing held back), each command checked byte for byte: Write `src/x.ts`, `git add src/x.ts`, `git commit -m "x"`, `pnpm test:run` → no denial, commit `x` on `feat/x`. `git push`, `gh pr list`, `git commit -m x --amend`, `git switch -c y --discard-changes`, K2d, K2e (both spellings), K2g, K2f → in `permission_denials`, K2d and K2f with `not a plain git call`, K2g with `unresolved write target`. K2 re-sent none. The target tree stayed clean.
Review 2026-10-31, attempt 1/3, verdict CONCERNS, 0 Critical. Added cases, pure insertions:
- G10.03 (`test-hooks.sh`, `run_git_add_long_reason_case`): 560 long `.env.*` names, `git add -A` denied naming secrets; failed first with rc=126, then green through `reason="${reason:0:4000}"` in `decide`.
- G14.101-118: one row per (class, character) for `&`, `|`, `<`, `>`, backtick, `$`, `*`, `?` where a single-character mutant stayed green.
- G14.119-130: tab trim, leading newline, two spaces, tab in a message, end-of-text trigger boundaries, the `.git` over-match, pass-side charset and word boundaries.
Sent to `docs/specs/harness-hardening.md`, "Open follow-ups": `git log --output=.git/…` (S2, pre-existing), the `harness-hooks`/`harness-prompts` contradiction with G14.70, three accepted limits.
Review 2026-10-31, attempt 2/3, on the fixes only (`tests`, `security` on `decide`). `security`: the argv fail-open is closed; two findings refuted by the verifier (a padded call past the 5 s timeout still prompts, the matcher refuses over 10000 characters; past 131072 bytes the command cannot run on Linux); the rest sent to `harness-hardening`. `tests`: Major confirmed, four one-character class widenings stayed green. Added cases, pure insertions, each red under its own mutant and only that one, 765 green on the hook:
- G14.131-134: `git add "-A"`, `git add "."`, `git add \-A`, `git add \.` (`SAFE` + `"`, `SAFE` + `\`).
- G14.135 `git add :/` (`SAFE` + `:`); G14.136 `git switch -c x main` (`BRANCH` + space).
- G14.137 `git add src/x.t[s]` (`SAFE` + `[` and `]`); G14.138 `git -C __FEAT_TREE__&id add src/x.ts` (the `-C` slot alone).
Review 2026-10-31, attempt 3/3, `tests` on G14.131-138: BLOCKED. Major confirmed: `WORD` + `[` `]` stays green, `git commit -m src/[xy].ts` then commits an unstaged file with no prompt on the mutant; the real hook asks. Minors: `WORD` + `{` `}`, `BRANCH` + `{` `}`, `SAFE` + space. Refuted: the `-C` slot with its own class, not a one-character edit today.
User's decision 2026-10-31 on the block: add the rows, no further review, then ship with `/audit:security`. `review` cleared on that decision, not on a clean pass. G14.139-142 added as pure insertions: `git commit -m src/[xy].ts`, `git commit -m src/{x..y}.ts`, `git switch -c v{1..2}`, `git -C __FEAT_TREE__ --no-pager add src`. Kit gates after them: `test-hooks.sh` 769 green, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` exit 0.
Ship step 1bis, `/audit:security` `authz`, 2026-11-01: 2 Critical confirmed by the verifier, ship stopped, `security` 1/3. M1 (regression): `enforce-git-workflow.sh` `add --dry-run` runs `core.fsmonitor` from an agent-written bare-layout config before any verdict. M2 (pre-existing mechanism, reach widened by `acceptEdits`): `python3 -` imports a planted `shlex.py` from the cwd, payload ran on an auto-approved `git status`. Files planted by hand in both, the Write under `acceptEdits` not driven. Refuted: `cp -s` + `git log --output`, hidden `--output` spellings.
User's decision 2026-11-01: fix both. Fix batch: `python3 -I -` (hook, `tdd-freeze-tests.sh`), `readable_git_dir` before any `add --dry-run` (only a git dir ending in `/.git` or `/.git/worktrees/<name>`, else `ask` naming the directory, `.git/modules/x` asks too). Added cases, pure insertions, each failing first (10 failures on the old hook, G15.06 green before and after as the no-regression guard), 776 green after: G15.01-05 untrusted repository, G15.06 linked worktree, G15.07 planted `shlex.py`. Behaviour change: a `git add` aimed at a directory outside any repository goes from `could not confirm` deny to this ask.
Re-audit of that fix NOT COMPLETED: a safety classifier stopped the auditor before any experiment, no verdict, not relaunched. Its review (`tests` + `correctness`, no verifier run) reported a timeout fail-open on a roughly 1 KB `[include]` tree (not driven through Claude Code), a secret deny lost in a submodule, expanded `-C` values read literally, test gaps.
User's decision 2026-11-01: tightened batch, local commit, no agent re-audit. **Gate `security`: NOT CONCLUDED** (`attempts.json` 1/3, not cleared); the user reviews the premise of `readable_git_dir` before any push. Batch: `.git/modules/<path>` accepted; on an unsafe row a named secret denies from the argument text, everything else asks with a warning that nothing was checked; a `-C` value starting with `~` or holding `` $ ` * ? [ { } `` takes the `could not confirm` deny (`--git-dir`/`--work-tree` not covered); `"onFailure": "block"` on the 5 handlers of `protect-files.sh`, `prevent-destructive-commands.sh`, `enforce-git-workflow.sh`; header.
- Added cases, pure insertions: G15.08-14 submodule, bare-clone worktree, `--separate-git-dir`; G15.15-22 `-C` expansions; G15.23-26 layouts; G15.27 rev-parse timeout (`PATH` shim); G15.28-29 deny kept; G15.30-31 outside a repository; K1f in `test-workflow-contracts.sh`. Failing first except G15.22, G15.27-29 (test gaps, each red under its mutant). Two needles of its own G15.12/14 rows were fixed with `sed -i` by the implementer, a shell write the rules forbid; no frozen case involved.
- `onFailure` measured on 2.1.316 (stub, n=1 each): a hook past its timeout, `exit 1` and a missing script block with the key and run without it; silent `exit 0` runs; non-JSON stdout with `exit 0` still runs. So a crash of these hooks now blocks the tool call.
Gates 2026-11-01: `test-hooks.sh` 800 green, `test-workflow-contracts.sh`, `test-install.sh`, `kit-doctor.py` exit 0. K2 rerun on a fresh core install, real Claude Code 2.1.316 against the local stub API instead of a model (byte-exact on all 12): `git add src/x.ts`, `git commit -m "x"`, `pnpm test:run` no denial (the last then fails, no `package.json`); `git push`, `gh pr list`, `--amend`, `--discard-changes`, K2d, K2e (both), K2g, K2f denied, K2d and K2f with `not a plain git call`, K2g with `unresolved write target`. Write `src/x.ts` not driven by the stub (driven by the real-model smoke before these batches).

## Acceptance criteria (carried from the entry artifact)
- [ ] None of the Critical forms of the three failed reviews passes without a decision — each is denied or asked: `git add \⏎ -f .env.local`, `mv .gitignore g && git add -A`, `git diff --output=.gitignore && git add -A`, `git status > .gitignore; git add -A`, `git status <(mv .gitignore g) ; git add -A`, `git add -A & mv .gitignore g`, `git add -A | mv .gitignore g`, `echo $'\'' ; git add -f .env.local ; echo \'`, `echo \ # ; git add -f .env.local`, `true\;# ; git add -f .env.local`, `echo \ # ; git commit -m x --amend`, `echo $'\'' ; git commit -m x -a ; echo \'`.
- [ ] The strict forms pass: `git add src/x.ts`, `git add -- src/x.ts`, `git -C <tree> add src/x.ts`, `git stage src/x.ts`, `git commit -m "feat: x"`, `git commit -m "fix: it's done"`, `git switch -c feat/x`; `git add .env.local` (untracked) and `git add -f x` stay denied.
- [ ] On a real light pass (smoke, installed P1): no prompt for edits, `git add <paths>`, `git commit -m "<one line>"`, gates; `git push`, `gh pr *`, `git commit -m x --amend`, `git switch -c x --discard-changes`, and `git status && git add src/x.ts` prompt.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-install.sh`, `test-workflow-contracts.sh` pass.
