# Plan: Fewer asks   (entry: docs/specs/fewer-asks.md · research: docs/work/fewer-asks/research.md · design: n/a)
Token profile: standard

## Skips
- Interface : SKIP — kit hooks and prompts, no user surface.
- DB, Backend, Front app layers : SKIP — `Data model: none`, `Custom backend: NONE`, no `src/`. The TDD hooks do not key on `.claude/`: test-first is by hand — every case of a step is written first and **observed failing on its own verdict or reason** (`FAIL <hook> / <id>: …`) before the code it covers changes, except *(pin)* cases, green today and kept green. The failing run is pasted into the handoff.
- `11-token-budget.md` : SKIP — V6 changes when the profile is **asked**, not the `critical` list (plan-critic pass 1; gate question 4).

## Write chain (sequential)
1. **Shell-guard cases first** — append X29-X38 to `fixtures/_harness/shell-guard.jsonl`; flip X7.05 and X24.412 (Blast radius). Run `test-hooks.sh`: every non-pin new case fails; record the count.
2. **`shell_targets.py`** — (a) a live parameter expansion in a sed script raises `Unreadable`, then ARITH regions become `1`; (b) `Unreadable` exits **3**, its message rendered with the placeholders shown as `$((…))`, `$(…)`, `${…}`; crashes keep exit 1; (c) `inline-path` rows. Contracts below.
3. **`prevent-destructive-commands.sh`** — (a) anchored flag alternatives; (b) exit-code read: 3 → parse ask, and the `.tdd-red` text deny `:581-583` keys on parse failure too; (c) row **deny tier** (T for test-first targets, W otherwise) and `inline-path` deny I; (d) formatter loop: `N>&M` rejoined, redirection words skipped; (e) `mv` message. Run → X29-X38 green.
4. **`protect-files.sh`** + `run_unfrozen_removal_cases` in `test-hooks.sh` — removal-only `.tdd-unfrozen` Write/Edit passes. Cases first, observed failing.
5. **Git** — fixtures 86-87 first; `enforce-git-workflow.sh` `commit_form` with `-C`, `# cwk-guard-api: 3` → `4`; `install.sh` `P1_ALLOWS` += `Bash(git -C * commit -m *)` and the git hook's required api → 4; `settings.json` allow; `test-install.sh` "five allows" → six (`:339`, `:384`, the `P1_KIT` checks); `test-workflow-contracts.sh:461-468` names the allow. Run `test-hooks.sh`, `test-install.sh`.
6. **Prompts and rules** — contract greps C1-C9 first in `test-workflow-contracts.sh`, observed failing; then `orchestrate.md`, `ship.md`, `github.md`, `implementer.md`, `test-writer.md`, `e2e-tester.md`, `spec.md`, `bmad/pm.md`, `interface.md`, `plan.md`, `CLAUDE.md`. Run → C1-C9 green.
7. **Tests** — every `kit-ci.yml` suite (`test-hooks.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-small-lane.sh`, `test-attempts.sh`, `test-workflow-contracts.sh`, `test-rules-floor.sh`) + `python3 .claude/hooks/kit-doctor.py`; `bash -n` / `python3 -B -m py_compile` on touched sources.
8. **Refactor** — under a green suite, no case edited.

## Parallel lots (inside this track, same tree)
none — fully sequential (`test-hooks.sh` and the fixture files are shared by steps 1-5).

## Track isolation
- Worktree: none, single track (main tree, branch `audit/slim`).
- Shared foundations touched: `prevent-destructive-commands.sh` (every Bash call), `shell_targets.py`, `protect-files.sh` (every Write/Edit), `enforce-git-workflow.sh`, `install.sh`, `settings.json`, `CLAUDE.md`. No other pass in flight.
- Kit-development cost: after step 3, shell edits of `.py` in this repo are denied; edits go through Write/Edit, which they already must.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/fixtures/_harness/shell-guard.jsonl` | Edit | X29-X38; X7.05, X24.412 flipped |
| `.claude/hooks/shell_targets.py` | Edit | live expansion in sed, ARITH, exit 3 + readable message, `inline-path` rows |
| `.claude/hooks/prevent-destructive-commands.sh` | Edit | anchored flags, exit-code read, `.tdd-red` deny on parse failure, deny tier, formatter rejoin/skip, `mv` message |
| `.claude/hooks/test-hooks.sh` | Edit | `run_unfrozen_removal_cases` |
| `.claude/hooks/protect-files.sh` | Edit | removal-only `.tdd-unfrozen` pass |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | `commit_form` with `-C`; api 4 |
| `.claude/hooks/fixtures/enforce-git-workflow.sh/86-…-pass.json`, `87-…-ask.json` | Create | F14 |
| `install.sh` | Edit | `P1_ALLOWS` six entries; git hook api 4 |
| `.claude/hooks/test-install.sh` | Edit | six P1 allows; hold-back removes the new one |
| `.claude/settings.json` | Edit | `Bash(git -C * commit -m *)` |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | C1-C9; git allow list :461-468; CLAUDE.md phrase :701-704 |
| `.claude/commands/loop/orchestrate.md` | Edit | Phase 0: kit scripts from root, work artifacts with Write/Edit; `.tdd-unfrozen` one Edit, no chat re-ask |
| `.claude/commands/loop/ship.md` | Edit | step 4 subject only; `.tdd-unfrozen` clean-up in one Edit before the commit |
| `.claude/agents/github.md` | Edit | caller's body → PR body; `git -C <tree> commit -m` form |
| `.claude/agents/{implementer,test-writer,e2e-tester}.md` | Edit | no no-op probe, no redirect of gate output; e2e gets the whole Write/Edit rule |
| `.claude/commands/loop/spec.md`, `.claude/commands/bmad/pm.md` | Edit | token profile printed, asked only on a trigger |
| `.claude/commands/loop/{interface,plan}.md` | Edit | an amendment equal to the user's own words is recorded, not re-asked |
| `CLAUDE.md` | Edit | lines 50-52 rewritten (any file, auto-memory included); +1 line: no "je lance X ?", no `cd dir;` |

## Contracts

### `shell_targets.py`
- **Live expansion in sed**: in `sed_rows`, before `sed_writes`, a sed script that holds a **live** parameter expansion (`$name`, `${…}`: a `$` not hidden by `HIDE`, `:30`) raises `Unreadable("live expansion in sed script: ${…}")` — live means an unhidden `$` followed by `[A-Za-z_0-9{@*#?!-]`; a `$` before `/`, `"` or the end is a sed anchor and stays readable — and one that holds a `SUB` placeholder (`:32`) raises `Unreadable("command substitution in sed script: $(…)")`. A literal `$` (single-quoted `'$p'`) is hidden, so not live. Then every ARITH placeholder becomes `1`.
- **Exit codes**: `Unreadable` → stderr `shell_targets: <msg>`, exit **3**. Every `Unreadable` raised inside `sed_writes` renders its offending char through one helper mapping `SUB`→`$(…)`, `ARITH`→`$((…))`, a `HIDE` char → its original; no private-use char ever reaches stderr (X35 asserts the readable construct). `ValueError`/`IndexError`/`RecursionError`/any other exception → exit 1. Usage → 2.
- **`inline-path` rows**: for each `?inline:` program, every token between matching `'…'` or `"…"` that, normalised against the segment's cwd, is an **existing path** under the project root, or whose **first path segment** below the root exists (`docs/new.md` → `docs/`), emits `inline-path\t<abs path>` after the `?inline:` row. A token that is empty or normalises to the root itself (`''`, `'.'`, `'./'`) emits nothing; `print('a.ts')` with no `a.ts` emits nothing.

### `prevent-destructive-commands.sh`
- **Flags**: `(^|[[:space:]])(-[a-zA-Z]*i|--in-place)` and `(^|[[:space:]])(-c|-e|--eval|-p)\b` in `SRC_WRITE_RE` :371-372 and `PY_WRITE_RE` :382-383. Other alternatives unchanged. (Bundled `-Bc` is not matched today either; unchanged.)
- **Resolver call** `:421`: stderr captured; exit 3 → `GUARD_PARSE=<message minus prefix>`. The `.tdd-red` text deny `:581-583` fires on `GUARD_FAILED` (text unchanged) **or** `GUARD_PARSE`, the latter with its own text `the shell guard could not parse this command (<construct>) and it names .claude/.tdd-red/, which only tdd-prove-red.sh writes.` (both contain **R**). Otherwise, for any command, ask `the shell guard could not parse this command: <construct>. Show the exact command, then let the user decide.` Exit 1, missing script, no python3, sentinel mismatch → today's path and texts.
- **Deny tier** (deny pass, after every existing deny): row verb ∈ {`sed`,`perl`,`cp`,`tee`,`install`,`rsync`,`ln`,`patch`,`truncate`}, target under the project with extension `.ts`/`.tsx`/`.py`: test-first or frozen-test target (`TDD_TARGET_RE`, `TDD_FROZEN_TEST_RE`, `CWK_TDD_PY_TARGET_RE`) → the existing test-first deny text (**T**); otherwise `BLOCKED: this edits a source from the shell, around every Write/Edit guardrail. Use Write/Edit.` (**W**). Row `inline-path` → `BLOCKED: inline programs are not used here: Read/Grep to read, Write/Edit to write.` (**I**); a `.claude/.tdd-red` inline keeps **D**.
- **Formatter loop** :686-729: before counting, a segment ending `[0-9]*>` whose next segment (from `cwk_segments`' `&` split) starts with digits is rejoined with the `&` restored, the glued word `N>&M` (`2>&1`, `>&2`), and the rest of that next segment stays in the same formatter segment, its words still counted; likewise a next segment starting with `>` is rejoined as `&>…` (`&>/dev/null .`). Then: a **glued** redirection word (`^[0-9]*(>|>>|>\||&>)[^[:space:]]+$` or `N>&M`) is skipped alone; a **bare** operator word (`^[0-9]*(>|>>|>\||&>)$`) is skipped together with the one word after it. Any other word counts as today.
- **`mv`** (`:564-565`, message `:659-661`): verb `mv` → `this moves a path under a protected dir: <rel>` (**M** = `moves a path under a protected dir`); `rm-r` keeps `recursive delete/move under a protected dir`. Both contain **P** = `under a protected dir`.
- **Reason substrings**: **W**, **T** (`test-first`), **I**, **D** (`is written only by tdd-prove-red.sh`), **P**, **M**, **G** (`guarded path:`), **U** (`unresolved write target`), **K** (`kit-cwd`), **Q** (`could not parse this command:`), **F** (`shell guard unavailable`), **S** (`writes a TypeScript source`), **R** (`.claude/.tdd-red`).

### `protect-files.sh`
On `.claude/.tdd-unfrozen` only, before the guarded ask: read the current file (absent → ask); compute the resulting text (Write: `content`; Edit: `old_string` → `new_string`, first occurrence, every occurrence if `replace_all` is true; `old_string` absent → ask). Pass with no output iff each non-empty resulting line maps to a distinct current line, either identical or that line prefixed by optional spaces and `#` (empty and whitespace-only resulting lines are free). Anything else → today's guarded ask, unchanged text.

### Git
`commit_form` = `^git( -C ($safe))? commit -m ($double|$single|$word)$`; with `-C`, `grammar_add_ok`'s tree check applies to its value. The "message is not a flag" guard (`:1589-1590`) is re-indexed to the **message** group (`BASH_REMATCH[3]` with this form), never the `-C` group. Protected-branch denies (`:1314-1315`, `:1441`, `:1458`) unchanged and first. `# cwk-guard-api: 4`; `install.sh` requires api 4 for this hook and holds back all six `P1_ALLOWS` when it is missing or older.

### Prompt texts (exact needles for C1-C9)
- C1 `orchestrate.md`: `kit scripts run from the project root by relative path, never behind \`cd x;\``
- C2 `orchestrate.md`: `work artifacts are written with Write/Edit, never from the shell`
- C3 `orchestrate.md`: `all the entries a gate needs go in one Edit` and `the chat never asks again what the hook's ask asks` (the `# U2, U5:` form stays, pin)
- C4 `ship.md`: `hand the \`github\` agent the subject only` and `remove the applied \`.tdd-unfrozen\` entries in one Edit`
- C5 `github.md`: `a body asked by the caller goes into the PR body, never into the commit` and `git -C <tree> commit -m "<one line>"`
- C6 `implementer.md`, `test-writer.md`, `e2e-tester.md`: `no no-op probe` and `never redirect gate output to a file`; `e2e-tester.md` also `never by switching tools` and `node -e`
- C7 `spec.md` and `bmad/pm.md`: `printed, not asked`, `loosens a kit guard`, and no `asked alone and asked always`
- C8 `interface.md` and `plan.md`: `exactly the user's own words is recorded, not asked again`
- C9 `CLAUDE.md`: `**Never write any file from the shell**` + needles `python3 -`, `node -e`, `perl -i`, `heredoc`, `never by switching tools`, `auto-memory included`; and `je lance` + `cd dir;`

## Test plan (gate — validated by the user before EXECUTE)

Test-first by hand: every case is written and observed failing on its verdict or reason before the code it covers, except *(pin)* cases. `cwd` is `__PROJECT_ROOT__` (the LoopKit repo: it has `docs/`, `.claude/`, no `src/`) unless named. Bold letter = expected reason substring (*Contracts*).

### `fixtures/_harness/shell-guard.jsonl` via `run_shell_guard_cases`
**Core behaviour — read-only commands stop asking, shell edits of sources are sent back to Write/Edit**
- [ ] X29 (F1) pass each: `sed -n 196,262p e2e/takeoff-measurement-lines.public.spec.ts`, `sed -n 1,5p src/features/a/services/a-line.repository.ts`, `sed -n 1p app/services/a-list.py`, `node scripts/x-p.ts`.
- [ ] X30 (V3) deny **W** each: `sed -i 's/a/b/' src/a.ts`, `sed -i.bak 's/a/b/' x.ts`, `perl -pi -e 's/a/b/' x.ts`, `sed '-i' s/a/b/ src/a.ts`, `sed "-i" s/a/b/ src/a.ts`, `cp /tmp/x src/a.tsx`, `echo x | tee src/a.ts`, `cp /tmp/x app/x.py`, `time sed -i 's/a/b/' vite.config.ts` (X7.05 flipped), `cp /tmp/x workflow.py` (X24.412 flipped). Deny **T** each: `sed '-i' s/a/b/ src/features/a/services/a.utils.ts`, `sed "-i" s/a/b/ src/features/a/services/a.mapper.ts`; `sed -i 's/a/b/' src/features/a/services/a.utils.ts` *(pin)*.
- [ ] X31 (V3 inline) deny **I** each: `python3 -c "open('docs/a.md','w').write('x')"`, `node -p "require('./.claude/settings.json').permissions"`, `python3 - <<'EOF'` / `print(open(".claude/hooks/hook-lib.sh").read())` / `EOF`, `python3 - <<'EOF'` / `open('docs/work/x/plan.md','w')` / `EOF` (F11). Deny **D** *(pin)*: `python3 -c "open('.claude/.tdd-red/m','w')"`.

**Business rules — what keeps its ask or its pass**
- [ ] X32 *(pins)* ask **U** each: `python3 -c "print(1)"`, `python3 -c "print('a.ts')"`, `node -p "process.version.split('.')[0]"`, `python3 -c "print(''.join(['a']))"`, `python3 - <<'EOF'` / `print("noop")` / `EOF`, `node -e "1"`, X25.04 (`print(open("src/a.ts").read())`: no `src/` in this repo, stays ask); ask **S** each: `echo x > src/a.ts`, `cat >> src/a.ts <<'EOF'` / `x` / `EOF`; pass: `cat >> docs/work/x/plan.md <<'EOF'` / `x` / `EOF` (F11).
- [ ] X33 (V1 `mv`) ask **M**: `mv src/features/x/a.ts /tmp/`, `mv src/a.ts src/b.ts`; ask `recursive delete/move under a protected dir` *(pin)*: `rm -rf src/features/x`.
- [ ] X34 (F2) pass each: `prettier --write src/a.ts >/dev/null`, `prettier --write src/a.ts 2>&1`, `prettier --write src/a.ts > /dev/null`, `prettier --write src/a.ts >/dev/null 2>&1`, `prettier --write src/a.ts >&2`; ask `whole folder` each: `prettier --write src/a.ts 2>&1 .`, `prettier --write src/a.ts 2>&1 src/`, `prettier --write src/a.ts >&2 .`, `prettier --write src/a.ts 1>&2 src/`, `prettier --write src/a.ts > out.log .`, `prettier --write src/a.ts &>/dev/null .` (silent pass today), `prettier --write .` *(pin)*.

**Edge cases — the parser and the kit scripts**
- [ ] X35 (F9) pass: `sed -n "1,$((3+2))p" x.py`; *(pins)* `sed -n '$p' x.py`, `sed -n "/x$/p" f`, `sed "s/ *$//" f`; ask **Q** + `$(…)`: `sed -n "$(echo 1w src/a.ts)" x.py`; ask **Q** + `${…}` each: `sed -n "${n},$((n+22))p" x.py`, `sed -n "${n}" x.py` (silent pass today).
- [ ] X36 (parse failure keeps the `.tdd-red` deny) deny **R** + `could not parse` (the verdict is a pin, the reason text is new): `sed "$(true)w .claude/.tdd-red/m" x`.
- [ ] X37 (V2) pass *(pin)*: `cd __PROJECT_ROOT__ && python3 .claude/hooks/kit-attempts.py pass docs/work/x/plan.md test`; ask **K** *(pin)*: `cd __PROJECT_ROOT__; python3 .claude/hooks/kit-attempts.py pass docs/work/x/plan.md test`.
- [ ] X38 regression *(pin)*: X12 stubs (renamed, 0-byte, exit 1, garbage, no sentinel, no python3) still **F**; X24.280-285 still "could not parse".

### `protect-files.sh` — `run_unfrozen_removal_cases` (scratch project, `.tdd-unfrozen` seeded with `src/a.test.ts  # U1: r` / `src/b.test.ts  # U2: r`)
- [ ] P1 (V4) pass each: Edit `old_string` = line 1 + newline, `new_string` = `""`; Edit `old_string` = line 1 without its newline, `new_string` = `""` (blanked line); Edit line 1 → `# src/a.test.ts  # U1: r`; Edit spanning both lines → both prefixed `# `; Write with only line 2; Write empty.
- [ ] P2 *(pins)* ask **G** each: Edit adding `src/c.test.ts  # U3: r`; Edit line 1 → `src/a.test.ts  # U1: r2`; Write with lines 1, 2 and a new line; Edit whose `old_string` is not in the file; `.tdd-unfrozen` absent (Write `x`); Edit line 1 → `src/a.test.ts # commented` (path still active); Write duplicating line 1 twice.

### `fixtures/enforce-git-workflow.sh/`
- [ ] G1 (F14) `86-…-pass`: `git -C __FEAT_TREE__ commit -m "feat(x): one line"` (cwd `__FEAT_TREE__`); `87-…-ask` *(pin)* (`not a plain git call`): `git -C __FEAT_TREE__ commit -m a -m b`; `36-g2e-dash-c-commit-main-deny` stays deny *(pin)*; `88-…-ask` *(pin; guards the re-index once `-C` is accepted)* (`not a plain git call`): `git -C __FEAT_TREE__ commit -m --no-verify`.

### `test-install.sh`
- [ ] I1 hold-back with the git hook at api 3 or absent: the target's settings carry none of the six P1 allows, `Bash(git -C * commit -m *)` included; a fresh install carries all six.

### Contract greps in `test-workflow-contracts.sh`
- [ ] C1-C9 as listed in *Contracts*, each observed failing before its prompt edit; the git allow list check names `Bash(git -C * commit -m *)` and still forbids `Bash(git commit *)`, `Bash(git -C *)`.

### Regression
- [ ] Every other fixture of every hook keeps its verdict; `test-rules-floor.sh` ≤ 520; `CLAUDE.md` ≤ 140 lines; `kit-doctor.py` no divergence.

## Vigilance (carried from research and plan-critic)
- The deny tier is new classification on rows; the anchored regexes never ship without it (quoted-flag bypass, test-first included).
- Redirections (`>`, `>>`, `<>`, heredoc into a file) keep their ask in this pass.
- `inline-path` must not deny an inline program whose quoted token names no existing repo path or folder.
- Exit 3 is parse failure only; a crash still reads "shell guard unavailable"; the `.tdd-red` deny holds on both.
- Every parse-failure message names its construct in readable text, never a private-use char.
- A live `$var`/`${…}` in a sed script is unreadable; a literal `$` address is not.
- Formatter: `2>&1` is rejoined before counting; a real target after it still counts.
- Removal-only check computes the resulting file; a line kept with its path before `#` is not commented out; no MultiEdit exists (matcher `Write|Edit`).
- `git -C` commit: the hook's strict grammar is the only barrier behind the new allow; the allow is held back with the hook (api 4).
- `ship.md` never asked for a body; the fix is a positive "subject only" line.
- `CLAUDE.md` 139/140 and rules floor 515/520: rewrite in place, one new line at most; the contract grep phrase changes with it.

## Acceptance criteria (carried from the entry artifact)
- [ ] F1-F3, F9: read-only `sed`/`prettier` commands no longer ask or deny; in-place edits and inline programs naming a repo path are denied with a Write/Edit pointer, quoted flags included; unrelated inline programs and redirections keep their ask; any parse failure names its construct.
- [ ] `orchestrate.md` says kit scripts run from the root, never behind `cd x;`; `cd <root> && …` passes, `cd <root>; …` still asks.
- [ ] `implementer`, `e2e-tester`, `test-writer` state "no inline programs, no no-op probes, no redirect to keep gate output"; the main thread writes work artifacts with Write/Edit.
- [ ] A gate needing several `.tdd-unfrozen` entries asks once; the chat does not ask it again; removal-only Edits do not ask.
- [ ] A spec touching none of payment / authorisation / destructive data / kit guards asks no token-profile question; one touching them does.
- [ ] No "je lance X ?" stop when X is the next step of the user's request; a contract amendment equal to the user's own correction is not re-asked.
- [ ] F14: a one-line `git -C <tree> commit -m` runs with no ask; `ship.md` never asks the `github` agent for a commit body.
- [ ] `test-hooks.sh`, `test-workflow-contracts.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Open questions for the gate (from research and plan-critic, with proposed answers)
1. V12 route → `Bash(git -C * commit -m *)` in `settings.json`, held back with the git hook at api 4 (G1, I1).
2. Single-file `mv` under a protected dir → keep the ask, message `this moves a path under a protected dir` (X33).
3. `.tdd-unfrozen` clean-up home → `ship.md`, before the commit, one Edit (C4).
4. Token-profile trigger → `spec.md`/`pm.md` **ask** the profile only when the spec touches payment, authorisation, destructive data, or loosens a kit guard / widens what runs without a prompt; the answer still decides `critical` or not; `11-token-budget.md`'s `critical` list is unchanged (C7).

## Plan critic
- pass 1: completeness 72, quality 55 — 7 Major survived refutation (M1-M7), M8 refuted; rewritten.
- pass 2: completeness 84, quality 68 — 2 Major confirmed (`$(…)` placeholder in the parse message; formatter skip after a glued `N>&M`), 5 Minor applied; rewritten.
- pass 3: no Critical/Major; 3 Minor applied (fixture 88 pin, sed `$` anchor not live + pins, `&>` rejoin + case).
- completeness: 92
- quality: 86
- surviving blockers: none

## Gate
- 2026-11-09 go
- Contract: as written
- V12 route → `Bash(git -C * commit -m *)` in `settings.json`, held back with the git hook at api 4
- Single-file `mv` under a protected dir → keep the ask, message `this moves a path under a protected dir`
- `.tdd-unfrozen` clean-up home → `ship.md`, before the commit, one Edit
- Token-profile trigger → asked only on payment / authorisation / destructive data / kit-guard loosening; `11-token-budget.md` unchanged
- amended 2026-11-09 X1.13 (guard-shell case): `truncate -s0 vite.config.ts` ask `guarded path:` → deny `Use Write/Edit` (consequence of the deny-tier verb list in *Contracts*, which names `truncate`; same flip as X7.05)
- amended 2026-11-09 (user, EXECUTE): V12 route → the git hook emits `allow` on the strict `git -C <tree> commit -m "<one line>"` form, no settings entry (an inner `*` breaks the no-inner-wildcard contract, `test-workflow-contracts.sh:758`); `P1_ALLOWS` stays five, git hook api stays 3, I1 dropped; G1 86 becomes `86-…-allow`; `Bash(git -C * commit -m *)` added to the forbidden allows
- amended 2026-11-09 G14.14 (git-guard case): `git -C __FEAT_TREE__ commit -m "spec: small x"` ask `not a plain git call` → allow `one-line commit in another tree` (the V12 behaviour itself; `run_git_guard_cases` accepts `allow`)
- amended 2026-11-09 V12: hook allow limited to the project tree and its worktrees (user, review)
- note 2026-11-09: the parse-failure ask fires under the existing write/tool conditions (`guard_runs_tool || guard_text_writes`), so a read-only unparsable command stays silent as today
