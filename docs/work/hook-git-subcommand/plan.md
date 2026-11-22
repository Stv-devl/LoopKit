# Plan: The git hook reads the real subcommand   (entry: docs/specs/hook-git-subcommand.md · research: docs/work/hook-git-subcommand/research.md · design: n/a)
Token profile: standard

## Skips
- Interface: SKIP — a shell hook, no user surface.
- DB, backend, front, wiring: SKIP — kit tooling, one bash hook and its fixture harness.
- TypeScript test-first layers: none. The hook is a foreign toolchain (`05-testing.md`, "Foreign toolchains use their own cycle"): its cycle is fixtures first, observed failing, then the hook. The TDD hooks do not key on `.sh`, so the RED is proved by the harness run, recorded in the handoff.

## Write chain (sequential)
1. Harness — `test-hooks.sh` `run_case`: for **every** `enforce-git-workflow.sh` fixture (not only `-deny`), build the fixture repo: `$tmp` initialised on `main` with one empty commit (as today), a worktree `$tmp/.feat` on a new branch `feat/x`, repo-local config `alias.p=push` and `alias.q=!sh -c x`; substitute `__MAIN_TREE__` → `$tmp` and `__FEAT_TREE__` → `$tmp/.feat` next to the existing placeholders. A fixture may carry an optional top-level `"_expect_reason": "<substring>"` key: when present, `run_case` fails unless `permissionDecisionReason` contains it (the hook ignores the key).
2. Plain-form fixtures (regression guards, green before and after): F01-F15 below.
3. New-form fixtures: G1-G5 below. **Run the harness, observe the G cases marked RED failing** (each currently `pass` where `ask` is expected), record the failing list in the handoff. That is the RED. G1j and G2e already hold today (the existing regexes catch them): they are guards, not RED.
4. Hook — `enforce-git-workflow.sh`: the segment parser and the **additive** rule flow (Contracts). GREEN: the whole harness green.
5. Tests — none beyond the harness (the harness is the test).
6. Refactor — under a green harness, no fixture edited: dedupe the reason strings, keep comments English and minimal (`03-conventions.md`).

## Parallel lots (inside this track, same tree)
none — fully sequential.

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: none (`.claude/hooks/enforce-git-workflow.sh` is kit tooling, not an app foundation). `light-permissions.md` P2 will later edit the same hook: not in flight.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/test-hooks.sh` | Edit | fixture repo for every git-hook fixture, two placeholders |
| `.claude/hooks/fixtures/enforce-git-workflow.sh/03-…json` … `NN-…json` | Create | F01-F15, G1-G5, one JSON per command |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | segment parser and rule flow |

## Contracts
**Principle: additive.** Every current rule stays as it is, on the whole command text, with today's tree resolution (`:87-126` and `:133-147`): it is the floor, so every plain form keeps its decision, wrappers included (`(git push)`, `env git push`, `bash -c "git push"` ask today through `\bgit\s+push\b` and keep asking). The parser only **adds** decisions the regexes miss. One deliberate change: today's `rev-parse` failure at `:91` exits 0; it now skips only the floor's branch-dependent rules, so the added rules and the floor's push asks still run.

**Segment parser**, inline `python3 - "$COMMAND" "$BASE_DIR" <<'PY'` in the hook, after `cwk_require_jq` and the `gh` asks. Its failure (python3 missing, crash, non-zero exit) is caught (`|| PARSE_FAILED=1`), never left to `set -e`.
- Tokenizer: `shlex.shlex(command, posix=True, punctuation_chars='();<>|&\n')`, `whitespace=' \t\r'`, `whitespace_split=True`, so a newline is a separator token and quoted text stays one token. A separator is **any token made only of the characters `;&|()` and newline** (shlex merges adjacent punctuation: `&&\n`, `;\n\n`, `)&&` are single tokens, probed). Redirection tokens (`<`, `>`, `>>`) are not separators.
- A segment's git call is found after skipping prefix tokens: `VAR=value` assignments, `env`, `command`, `exec`, `time`, `nice`, `nohup`, `{`. The program token is `git` or ends in `/git`. A `bash`/`sh`/`zsh` token followed by `-c` and a string: that string is parsed recursively as a command.
- Globals skipped: every token starting with `-` before the subcommand, plus the next token after `-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, `--config-env`, `--exec-path`, `--attr-source`. Every `-C` value is joined in order onto the base dir (`.cwd`, else `CLAUDE_PROJECT_DIR`), an absolute value resetting it.
- Output, one line per git segment, tab-separated, no free text: `<subcommand>\t<dir>\t<alias_cfg 0|1>\t<force 0|1>`. `alias_cfg` is 1 when a global is `-c alias.*`, `--config-env alias.*` or `--config-env=alias.*`. `force` is 1 when a `push` segment carries `-f`, `--force`, `--force-with-lease`, `--force-if-includes`, or a `+refspec`. A tokenizer error prints the single line `UNPARSABLE`.

**Rule flow**, in two passes over all segments, so a deny is never pre-empted by an ask:
1. **Deny pass**: the floor's denies (`:108-126`: commit on a protected branch for today's tree, signature, attribution trailer, on the whole text), then, per segment, `commit` whose `<dir>` resolves to a protected branch with commits (`HAS_COMMITS` kept per dir: the first commit of an unborn repo stays allowed) → deny, today's reason.
2. **Ask pass**: the floor's asks (`:133-147`), then per segment, left to right, first match:
   - `alias_cfg` 1 → ask ("alias defined on the command line");
   - `push` or `send-pack` → ask, the force reason when `force` is 1;
   - subcommand empty (`git --version`, `git --help`) → no rule here;
   - subcommand not in `git --list-cmds=builtins` → `git -C <dir> config --get alias.<sub>` (needs an existing directory, not a work tree: outside a repo it reads global config); directory missing, or value containing `push`, `merge`, `rebase`, `send-pack` or starting with `!` → ask;
   - `<dir>` unresolved and subcommand in `merge|rebase|commit|reset|switch|checkout` → ask, the reason naming the path;
   - `merge|rebase` whose `<dir>` is on a protected branch with commits → ask, today's reason.
3. **Unparsable**: `UNPARSABLE` or `PARSE_FAILED`, and the text matches `\b(push|send-pack|merge|rebase)\b|alias\.` → ask ("could not read which git command runs here"); otherwise pass as today (a heredoc commit message with an apostrophe stays a pass).
- Calls per segment: at most five (`--list-cmds`, `config --get`, `rev-parse`, `branch --show-current`, `rev-parse --verify HEAD`), well inside the 5 s timeout.

**Decisions that change, all toward asking, accepted as fail-closed (Gate):** a mutating subcommand (`merge|rebase|commit|reset|switch|checkout`) on a directory that does not resolve, including a plain `git merge x` from a non-repo cwd, goes from pass to ask; a push hidden behind `-C`, `--no-pager`, `-c`, `--git-dir`, `--namespace`, `--attr-source`, an alias or `send-pack` goes from pass to ask; a plain `git push` from a non-repo cwd goes from pass to ask (the floor's push asks no longer stop at `:91`); a commit with `-S` or an attribution trailer from a non-repo cwd goes from pass to **deny** (those denies do not depend on the branch); an unparsable command (a heredoc with an apostrophe) containing `push|send-pack|merge|rebase|alias.` goes from pass to ask; a non-builtin, non-alias subcommand (`git lfs …`) from a missing directory goes from pass to ask. No current ask or deny becomes weaker. Known open route, not a regression: wrappers that take options (`nice -n 5 git …`, `env -i git …`, `sudo git …`) are not unwrapped; the floor decides them as today.

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — hook fixtures (foreign toolchain, ids `F`/`G`)
One JSON per case in `.claude/hooks/fixtures/enforce-git-workflow.sh/`, verdict from the filename suffix. `cwd` is `__MAIN_TREE__` (on `main`) unless stated.

#### Plain forms, current decision kept (regression guards, green before and after)
- [ ] F01 `git push origin feat/x` asks.
- [ ] F02 `git push --force origin feat/x` asks, reason containing `FORCE`.
- [ ] F03 `git merge feat/x` on `main` asks.
- [ ] F04 `git merge main` from `__FEAT_TREE__` (on `feat/x`) passes.
- [ ] F05 `git commit -m x` from `__FEAT_TREE__` passes.
- [ ] F06 `git commit -S -m x` from `__FEAT_TREE__` is denied.
- [ ] F07 `gh pr create --title t --body b` asks.
- [ ] F08 `git rebase feat/x` on `main` asks.
- [ ] F09 `git log --oneline` passes.
- [ ] F10 `git commit -m "x\n\nCo-Authored-By: a <a@b>"` from `__FEAT_TREE__` is denied (trailer).
- [ ] F11 `git commit -F - <<'EOF'` / `It's done` / `EOF` (three lines) from `__FEAT_TREE__` passes (unparsable, nothing dangerous).
- [ ] F12 `(git push)` asks.
- [ ] F13 `git push && git commit -m x` on `main` is denied (deny beats ask).
- [ ] F14 `git merge-base main HEAD` on `main` asks (today's regex decision kept).
- [ ] F15 `git status` then, on the next line, `git push` asks.
(existing `01-deny` commit on `main` and `02-pass` `git status --short` stay.)

#### New forms (marked RED: must fail before the hook change)
- [ ] G1a RED `git -C __MAIN_TREE__ push origin main` asks.
- [ ] G1b RED `git -C /nonexistent push` asks.
- [ ] G1c RED `git -C "__MAIN_TREE__" push` asks.
- [ ] G1d RED `git --no-pager push` asks.
- [ ] G1e RED `git -P push` asks.
- [ ] G1f RED `git -c a=b push` asks.
- [ ] G1g RED `git --git-dir /tmp/x/.git push` asks.
- [ ] G1h RED `git --namespace n push` asks.
- [ ] G1i RED `git --attr-source HEAD push` asks.
- [ ] G1j guard `echo "$(git push)"` asks.
- [ ] G1k RED `env FOO=1 git -C __MAIN_TREE__ push` asks.
- [ ] G1l RED `git status` then, on the next line, `git -C __MAIN_TREE__ push` asks.
- [ ] G1m RED `git -C __MAIN_TREE__ push --force-with-lease` asks, reason containing `FORCE`.
- [ ] G1n RED `git log &&` then, on the next line, `git -C __MAIN_TREE__ push` asks (merged separator token).
- [ ] G2a RED from `__FEAT_TREE__`: `git -C __MAIN_TREE__ merge --ff-only feat/x` asks.
- [ ] G2b RED from `__FEAT_TREE__`: `git --no-pager -C __MAIN_TREE__ merge feat/x` asks.
- [ ] G2c RED from `__FEAT_TREE__`: `git -C __FEAT_TREE__ log && git -C __MAIN_TREE__ merge feat/x` asks.
- [ ] G2d RED `git -C /nonexistent merge x` asks, reason containing `/nonexistent`.
- [ ] G2e guard from `__FEAT_TREE__`: `git -C __MAIN_TREE__ commit -m x` is denied.
- [ ] G2f RED from `__FEAT_TREE__`: `bash -c "git -C __MAIN_TREE__ merge feat/x"` asks.
- [ ] G2g RED from `__FEAT_TREE__`: `git -C __FEAT_TREE__ log && git -C __MAIN_TREE__ commit -m x` is denied.
- [ ] G3a RED `git -c alias.p=push p` asks.
- [ ] G3b RED `git p` (repo alias `p=push`) asks.
- [ ] G3c RED `git q` (repo alias `q=!sh -c x`) asks.
- [ ] G3d RED `git send-pack x` asks.
- [ ] G3e RED `git --config-env=alias.p=E p` asks.
- [ ] G4a from `__FEAT_TREE__`: `git -C __FEAT_TREE__ status` passes.
- [ ] G4b `git --no-pager log` passes.
- [ ] G4c `git -C /nonexistent status` passes.
- [ ] G4e `git --version` from `/` passes.
- [ ] G4d `git commit -m "a | b; c && d"` from `__FEAT_TREE__` passes (separators inside quotes are not segments).
- [ ] G5 `test-hooks.sh` runs every other hook's fixtures unchanged, and the jq-absent case still exits 2 with the jq message.

### Test-after
none: the harness is the test.

## Vigilance (carried from research)
- F01-F15 exist and are green **before** the hook is touched; a plain-form regression shows there first.
- Quote-aware tokenizing: G4d proves a `|`, `;` or `&&` inside quotes is not a separator; `&&` is never split into two `&`.
- `-C "path"` resolves without quotes (G1c).
- Alias resolution uses the segment's directory; an unresolved directory asks, never passes.
- Additive: no floor rule edited or removed; a deny is never pre-empted by an ask (F13, G2g); the trailer deny keeps running on the whole text (F10).
- Newline is a separator (F15, G1l); a heredoc message with an apostrophe stays a pass (F11).
- A python3 failure is caught, the floor still decides (`PARSE_FAILED`).
- jq-absent still exits 2 before any python3 call (G5).
- Branch per segment, never one branch for the whole command (G2c, G2e).
- `git -C /nonexistent status` passes (G4c); `merge|rebase|commit|reset|switch|checkout` on an unresolved directory ask (G2d).
- Runs inside the 5 s hook timeout: one python3 start, at most five `git` calls per segment.

## Acceptance criteria (carried from the entry artifact)
- [ ] Every form below asks exactly as its plain form does; every plain form keeps its current decision.
- [ ] `test-hooks.sh` passes, existing cases unchanged.

## Plan critic
- completeness: 88 (pass 2; its two Minors applied after)
- quality: 80 (pass 2); its one Major (adjacent separators merged by shlex) confirmed by probe, fixed in Contracts, guarded by G1n; the fix verified by probe (`git log &&\n…` → `['git','log','&&\n',…]`, now a separator by character class)
- surviving blockers: none

## Gate
- 2026-10-28 go
- Contract: as written
- git inside `$(…)`/backticks → floor regexes keep deciding (G1j); an unparsable command with `push|send-pack|merge|rebase|alias.` asks
- plain forms that change → accepted, all fail-closed, as listed under Contracts "Decisions that change"
- amended 2026-10-28 G3a: `git -c alias.p=push p` → `git -c alias.z=push z`; G3e: `git --config-env=alias.p=E p` → `git --config-env=alias.z=E z` (the fixture repo defines `alias.p=push`, so `p` would ask through the repo alias and never prove the command-line alias detection; written this way before the first run)
- note 2026-10-28 G1g already asked before the change (the floor regex matches `.git push` inside the `--git-dir` path): a guard, not RED
- review 2026-10-28 round 3 PASS; user ruled the remaining Major out of contract (a readable `git -C <feat>` first, then a git call behind a wrapper with options: the `?unread` fallback checks one tree; pre-existing, Gate "known open route"). Carried to a follow-up spec with: pull/cherry-pick/reset/update-ref/fetch into main, checkout-then-commit in one command, `g""it`, `gh workflow/secret/variable`, read-only `git config --get alias.*` false ask, heredoc lines starting `git config alias`/`git [skip ci]` false ask
