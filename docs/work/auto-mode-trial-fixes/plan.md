# Plan: auto-mode trial fixes   (entry: docs/specs/auto-mode-trial-fixes.md · research: docs/work/auto-mode-trial-fixes/research.md · design: n/a)
Token profile: critical
Base: c3d557d (`main`)

## Skips
- DB, backend, INTERFACE: SKIP, kit tooling only, no screen.
- Front test-first layers (`utils`/`mapper`/`repository` under `src/`): none. Every file is a hook, script,
  prompt or suite. Kit discipline (as in auto-mode, loop-to-pr): each step writes its cases into the suite
  first, runs them and observes the new ones red, then writes the code.
- Python freeze twin (`addons/fastapi/hooks/tdd_py_lib.py:596-622`, same "outside every case" refusal): OUT,
  written to `follow-ups.md` (open question 8).
- Native `Bash(gh …)` allow entries: OUT (open question 3; `test-install.sh:107-111` pins that no
  `Bash(gh pr` allow exists).
- Case ids (new, none reused): `IN65+` (test-install.sh), `G18.42+` (`fixtures/_harness/git-guard.jsonl`),
  `K27+` (test-pr-assets.sh), `A43` (test-audit-surface.sh), `AM48+` (test-hooks.sh auto block),
  `AMC20+` and `PK46+` (test-workflow-contracts.sh).

## Proposed answers to research's open questions (taken at `## Gate`)
1. **Blocked stop keeps the record.** `orchestrate.md:74-80`: a blocked stop ends the run with the record
   kept; the agent never runs `loop-record.py --clear` on it. `./workflow.sh` resumes it in auto on the
   kept record (the user resolves the cause first); the user, not the agent, runs `--clear` to resume in
   `moi`. `ship.md:187` gains "record kept". Cases AMC2 (inverted), AMC20.
2. **`tdd-freeze-tests.sh:340` drops the `--clear` option**, in both modes: the text ends "correct it through
   the unfreeze queue; in auto, if the queue cannot lift it, end the run with a blocked stop (record kept)"
   (the queue cannot lift an ambiguity refusal, :336-340 refuse before ids/rows/verdicts are read). Every
   suite case whose needle is `loop-record.py --clear` on that text changes needle to `unfreeze queue`, with
   `--clear` as the absent needle: LP54, LP54.2, LP62.8, LP63, LP63.2, LP63.3, LP65, LP65.2 and the `$clr`
   cases LP66, LP66.2, LP67, LP67.2, LP68, LP68.2, LP69, LP70, LP70.2 (`clr=` at test-hooks.sh:5742, plus the
   comments :5646, :5739, :5813). Kit suite, not a frozen src test; recorded here as a pin change.
3. Native gh allow entries: OUT (above).
4. **`--web`**: a `gh repo|issue|release view|list` call carrying `--web` keeps today's ask; `gh pr view
   --web` and `gh run view --web` keep today's pass. Case G18.50.
5. **Invalid `project.json` in `kit-pr-assets.py ui`**: refuse (exit 2, empty stdout, as `kit-audit-surface.py`
   does). Absent → roots `()`. `review.md:160` gains: exit 2 → report the refusal and stop that leg (in auto,
   a blocked stop). Cases K29, K30.
6. **Audit surface**: no code change; A43 pins the criterion. `shared/schemas/` (`kit-audit-surface.py:81`)
   under an app root stays OUT (follow-up).
7. **`/kit:init`**: a front-end app root is a directory ≤2 levels below the root (root itself excluded,
   `node_modules`/`.git`/`.claude` skipped) holding its own `package.json` and either a `src/` directory
   (new) or one root config (today's rule, kept so an `e2e/`-style package is not dropped); the
   pyproject rule is unchanged. `init.md` prose is the only implementation (no script): the criterion is pinned
   by text (PK47).
8. Python twin: OUT, follow-up.

## Write chain (sequential)
Each step: write its cases, run the suite, observe the new cases red (or record why a case is a pin of
behaviour that already holds: G18.42-G18.44, A43), then the code, then the suite green.

Pins (hold on today's code, run to confirm green, not red): G18.42-G18.44, G18.48-G18.52, G18.53 first half,
G18.54 first half, A43, K28, K29, AM49.2, AM50-AM53, AM55-AM58.2, the e2e half of PK46 (`e2e-tester.md:77`
already says images only under `PR_SHOTS_DIR`). Red today: G18.45-G18.47, G18.53 second half, G18.54 second
half, AM48, AM49, AM54, AM59, AMC2 inverted, AMC20, AMC21, K27, K30, PK46 review half, PK47, PK48, IN65, IN66,
and the 17 LP needle changes once :340 changes (they are red after the hook edit, green after the needle edit:
needles are written first, observed red against today's :340, then the hook). Every acceptance criterion keeps
at least one red case.

1. **Fix 6 — codex output ignored.** `.gitignore` (after `handoff-codex.md`, :120) gains
   `docs/work/*/codex-last-message.txt`; `install.sh` `ensure_gitignore()`: the top-up list (:639-641) and the
   fresh heredoc (after :677); the count text (:940) set to the real number of lines in the block.
   Cases IN65, IN66.
2. **Fix 3 — read-only gh.** `enforce-git-workflow.sh`: replace the whole-command test at :2175 by a per-segment
   judgement. First join `\<newline>` continuations (as `gh_scan` :1972), then split the command on newline,
   `;`, `&`, `|`, `(`, `)`, backtick (as `gh_scan` :1975-1976 do together); in each segment
   apply today's :2175 regex unchanged (so `\bgh` still matches `\gh`, `-R/--repo` forms as today). A matching
   segment asks, unless the words after `gh` and its repo flags are `repo view`, `issue view|list` or
   `release view|list` and the segment holds no `--web`. `gh api` always asks. The read-only segments fall
   through (no `allow` emitted). The pr ask (:2171), comment ask (:2179), attribution deny and `record_allow`
   stay as they are. Cases G18.42-G18.54.
3. **Fix 5 — app_roots.** `kit-pr-assets.py`: import `project_config` as `kit-audit-surface.py:21-23` does;
   `is_ui_path(path, roots)` tests `src/` and `<root>/src/` per root with the existing suffix rule;
   `run()` `ui` loads `project_config.load(os.getcwd())`; `ConfigError` → `Refused` (exit 2). `review.md:160-164`:
   exit 2 rule (answer 5) and the override "the script says `none` but the diff holds `*.tsx` under `src/` or an
   app root's `src/` → decide `ui`". `e2e-tester.md`: shots only under `PR_SHOTS_DIR`, never a fixed review
   folder. `kit/init.md:46-56`: answer 7. Cases K27-K30, A43, PK46, PK47.
4. **Fix 1 — import additions under a verdict.** `tdd-freeze-tests.sh` `freeze_rows()` (check mode), Edit only
   (a Write keeps today's :215-216 refusal).
   - **Import head**: from offset 0, a run of blank lines, `//` or `/* */` comment lines, and static import
     declarations; it ends at the first other line.
   - **Static import declaration** (the only accepted added statement), matched as a whole, possibly over
     several lines: `import` [`type`] *clause* `from` *quoted specifier* [`;`], then only whitespace to end of
     line. *Clause* = an identifier, `* as` identifier, `{ … }` of identifiers / `x as y` / `type x`, or
     identifier `, { … }`. The specifier is quoted and holds only `[A-Za-z0-9@._/-]`. Not accepted: a
     side-effect `import 'x'`, a dynamic `import(`, `import.meta`, any text after the specifier on the same
     line (`; vi.mock(…)`), a binding whose imported or local name is `describe`, `it`, `test`, `expect`, `vi`,
     `suite`, `bench`, `beforeEach`, `afterEach`, `beforeAll`, `afterAll`, and a binding whose local name already
     occurs as an identifier anywhere in the current file (closes `assert`, `Date` and any other rebinding of
     a name the frozen cases read). A declaration is inserted only between whole head lines, never inside a
     `/* */` comment.
   - **Accept rule**: in auto, the file listed in `.tdd-unfrozen`, the record holding at least one `unfreeze`
     verdict for this path, and head(result) = head(current) with only whole accepted declarations inserted
     (no head line removed or changed). Then the body (result with its head replaced by the current head) is
     judged: unchanged → the Edit is an import-only Edit, allowed by its own path with a notice (it does not
     reach the :341 "touches no case" refusal); changed → the existing checks run on it as today (rows,
     verdict hash, out-of-case).
   - Any other head change keeps today's refusal. The insertion path's :593 refusal is untouched: an import
     Edit already reaches rows mode through :675 (`ROWS_MODE=1`).
   - `arbiter.md:40-46`: the hunk may also add whole static import declarations to the top import block, under
     the same exclusions; it still removes no assertion.
   Cases AM48-AM58, AMC21.
5. **Fix 2 — no self clear.** `orchestrate.md:74-80` (answer 1); `ship.md:187` record kept;
   `tdd-freeze-tests.sh:340` (answer 2). Cases AMC2 inverted, AMC20, and the 17 needle changes of answer 2.
6. **Fix 4 — agent command shapes.** `test-writer.md` and `e2e-tester.md`: (a) read a range with Read
   `offset`/`limit`, never a `for … sed -n "${n}p"` loop; (b) no `cd … && git apply --check` probe;
   (c) e2e-tester only: Playwright with the project config and `--grep`, never an agent-written config or
   `-c`/`--config`. Case PK48.
7. **Suites.** Run every `.claude/hooks/test-*.sh` and the fastapi `test_imported_symbols.py` as before; all green.
8. **Refactor** under a green suite, no case edited.

## Parallel lots
none — fully sequential (steps 2, 4 and 5 share `test-hooks.sh`/`test-workflow-contracts.sh`).

## Track isolation
- Worktree: none, single track (main tree on `feat/auto-mode-trial-fixes`).
- Shared foundations touched: kit hooks (`enforce-git-workflow.sh`, `tdd-freeze-tests.sh`), `install.sh`. No other
  pass runs beside this one until merged.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.gitignore` | Edit | fix 6 |
| `install.sh` | Edit | fix 6 (block, top-up, count) |
| `.claude/hooks/test-install.sh` | Edit | IN65-IN66 |
| `.claude/hooks/enforce-git-workflow.sh` | Edit | fix 3 |
| `.claude/hooks/fixtures/_harness/git-guard.jsonl` | Edit | G18.42-G18.54 |
| `.claude/hooks/kit-pr-assets.py` | Edit | fix 5 |
| `.claude/hooks/test-pr-assets.sh` | Edit | K27-K30 |
| `.claude/hooks/test-audit-surface.sh` | Edit | A43 |
| `.claude/commands/loop/review.md` | Edit | fix 5 (exit 2, ui override) |
| `.claude/commands/kit/init.md` | Edit | fix 5 (app root rule) |
| `.claude/hooks/tdd-freeze-tests.sh` | Edit | fix 1, fix 2 (:340) |
| `.claude/hooks/test-hooks.sh` | Edit | AM48-AM59; needles of LP54, LP54.2, LP62.8, LP63, LP63.2, LP63.3, LP65, LP65.2, LP66-LP70.2 (`clr=`) |
| `.claude/agents/arbiter.md` | Edit | fix 1 |
| `.claude/commands/loop/orchestrate.md` | Edit | fix 2 |
| `.claude/commands/loop/ship.md` | Edit | fix 2 |
| `.claude/agents/test-writer.md` | Edit | fix 4 |
| `.claude/agents/e2e-tester.md` | Edit | fix 4, fix 5 (PR_SHOTS_DIR) |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | AMC2, AMC20, AMC21, PK46-PK48 |
| `docs/work/auto-mode-trial-fixes/follow-ups.md` | Create | Python twin, shared/schemas, native gh allows |

## Contracts
- `kit-pr-assets.py ui` stdin: one path per line; stdout `ui` | `none`, exit 0; invalid `.claude/project.json`
  → exit 2, stderr `kit-pr-assets: …`, stdout empty. `is_ui_path(path: str, roots: tuple) -> bool`.
- `enforce-git-workflow.sh` verdicts: unchanged except the read-only gh calls listed in step 2 (no decision).
- Freeze hook rows mode: an import head change is accepted only on the conditions of step 4; every other
  refusal text unchanged except :340.

## Test plan (gate — validated before EXECUTE)
Main behaviour first, business rules next, edge cases last. "auto rec" = a valid record with `mode: "auto"`
and `contract_go` (as `am_freeze_rec`), the file `src/a/x.utils.test.ts` built by `lp_freeze_project` and
listed in `.tdd-unfrozen` as `$x  # U3: r` (else rows mode never starts, tdd-freeze-tests.sh:420-423);
"verdict U3" = `am_v` frozen-case `unfreeze` for U3 with the sha256 of its unchanged title "U3 keeps three",
`1cfe4c2a210df3bd4c64546e6559ba3f73cdde543d48719e08e6488972e34697` (`printf '%s' 'U3 keeps three' | sha256sum`,
checked by the verifier 2026-11-23). Expected verdicts are literals from the contract, never computed by the hook.

### Step 1 — install (test-install.sh, block IN)
- [ ] IN65 A fresh install's `.gitignore` holds `docs/work/*/codex-last-message.txt` exactly once, and the
      kit repo's own `.gitignore` makes `git check-ignore docs/work/x/codex-last-message.txt` succeed.
- [ ] IN66 An older block without that line gets it back-filled once on reinstall (top-up), not twice.

### Step 2 — read-only gh (git-guard.jsonl, block G18)
**Core behaviour**
- [ ] G18.42 `gh pr view 1`, `gh pr list`, `gh pr diff 1`, `gh pr checks 1` pass (pin: already pass).
- [ ] G18.43 `gh run view 5`, `gh run list`, `gh run view 5 -R o/r`, `gh -R o/r run list` pass (pin).
- [ ] G18.44 `gh pr view 1 --json title -R o/r` passes (pin).
- [ ] G18.45 `gh repo view` passes; `gh repo view o/r --json name` passes.
- [ ] G18.46 `gh issue view 3`, `gh issue list`, `gh issue list -R o/r --json number` pass.
- [ ] G18.47 `gh release view v1`, `gh release list`, `gh --repo o/r release list` pass.
**Business rules**
- [ ] G18.48 `gh api repos/o/r` asks ("writes to GitHub"); `gh api repos/o/r --jq .name` asks.
- [ ] G18.49 `gh issue create -t x -b y`, `gh release create v1`, `gh repo create x`, `gh repo delete x`,
      `gh repo edit --description x` ask, with the same reason as today.
- [ ] G18.50 `gh repo view --web`, `gh issue view 3 --web` ask (answer 4).
**Edge cases**
- [ ] G18.51 `gh repo view && gh repo delete o/r` asks; `gh issue list; gh issue create -t x -b y` asks.
- [ ] G18.52 `gh pr view 1 && gh pr merge 1` asks (pr ask, :2171); `gh -R o/r issue view 3 | gh issue edit 3 --add-label x` asks.
- [ ] G18.53 `\gh repo delete o/r` asks; `\gh repo view` passes.
- [ ] G18.54 `gh repo view` NEWLINE `gh repo delete o/r` (one Bash command, two lines) asks; `gh repo view \`
      NEWLINE `--json name` (a continuation) passes.

### Step 3 — app_roots
**Core behaviour**
- [ ] K27 `app_roots: ["frontend"]`, stdin `frontend/src/X.tsx` → `ui`.
- [ ] K28 `app_roots: []`, stdin `frontend/src/X.tsx` → `none`; `src/X.tsx` → `ui` with `[]` and with `["frontend"]`.
**Business rules**
- [ ] K29 No `.claude/project.json`: `src/X.tsx` → `ui`, `frontend/src/X.tsx` → `none`.
- [ ] K30 Invalid `.claude/project.json` (not JSON): exit 2, empty stdout (refused, not widened).
- [ ] A43 A diff adding `frontend/src/form.tsx` and `frontend/src/auth.ts` with the same content as the existing
      `src/form.tsx`/`src/auth.ts` fixtures, `app_roots: ["frontend"]`, selects the same surfaces as that diff
      under `src/` with no roots (pin).
- [ ] PK46 `review.md` holds the exit-2 rule and the `*.tsx` override (`none` + `*.tsx` under an app root → `ui`);
      `e2e-tester.md` says shots go only under `PR_SHOTS_DIR`.
- [ ] PK47 `kit/init.md` app-root rule names `package.json` with `src/` as an alternative to one root config,
      and excludes the root itself.

### Step 4 — freeze, import additions (test-hooks.sh, block AM, `lp_freeze_project` file with `import { f } from './x.utils'`)
**Core behaviour**
- [ ] AM48 auto rec + verdict U3: an Edit whose old string is the import line and new string is that line plus
      `import { g } from './y.utils'` passes.
- [ ] AM49 auto rec + verdict U3: one Edit whose old string runs from the import line through U3's body, adding
      `import { g } from './y.utils'` and changing U3's assertion to `expect(f(3)).toBe(4)`, title unchanged, passes.
**Business rules**
- [ ] AM49.2 auto rec + verdict U3: a Write of the whole file adding that import is denied with today's
      "a Write replaces the whole frozen file" text (pin).
- [ ] AM50 auto rec, no verdict: the AM48 Edit is denied, and the AM49 combined Edit (import added plus U3
      assertion changed) is denied (pin).
- [ ] AM51 auto rec + verdict U3: an Edit removing the existing import is denied (pin).
- [ ] AM52 auto rec + verdict U3: an Edit rewriting the existing import to `import { f, h } from './x.utils'` is denied (pin).
- [ ] AM53 auto rec + verdict U3: an Edit adding `const k = 1` after the import is denied (pin).
**Edge cases**
- [ ] AM54 auto rec + verdict U3: adding a multi-line `import {\n  g,\n  h,\n} from './y.utils'` and an
      `import type { T } from './t'` passes.
- [ ] AM55 auto rec + verdict U3: an import statement added after `describe(` (outside the head) is denied; a
      `refuse` verdict for U3 (no `unfreeze`) denies the AM48 Edit.
- [ ] AM56 auto rec + verdict U3: adding the single line `import { g } from './y.utils'; vi.mock('./x.utils')` is denied.
- [ ] AM57 auto rec + verdict U3: adding a head line `import('./y.utils')` is denied; adding `import.meta.x = 1` is denied.
- [ ] AM58 auto rec + verdict U3: adding `import { expect } from './e'` is denied; adding `import { it as t } from './n'`
      is denied; adding the side-effect `import './setup'` is denied.
- [ ] AM58.2 auto rec + verdict U3: adding `import { f as g2, f2 as f } from './z'` (local `f` already used by the
      frozen cases) is denied; adding `import { g } from "./y'; vi.mock('x')"` (specifier outside the allowed
      characters) is denied.
- [ ] AMC21 `arbiter.md` allows whole static import declarations added to the top import block, names the
      exclusions (side-effect, dynamic, trailing statement, test globals), and still says the hunk removes no assertion.

### Step 5 — no self clear (test-workflow-contracts.sh, test-hooks.sh)
- [ ] AMC2 (inverted) the blocked-stop paragraph of `orchestrate.md` no longer contains `loop-record.py --clear`.
- [ ] AMC20 that paragraph says the record is kept and that the user clears it to resume in `moi`; `ship.md`'s
      blocked-stop line says the record is kept; PK31/PK45.3/PK45.6 (finished-pass `--clear`) still pass.
- [ ] LP54, LP54.2, LP62.8, LP63, LP63.2, LP63.3, LP65, LP65.2, LP66, LP66.2, LP67, LP67.2, LP68, LP68.2, LP69,
      LP70, LP70.2: needle `unfreeze queue` (was `loop-record.py --clear`); the existing absent needle
      (`lifts it with`, via `nol`) stays; `--clear` absent is a second check on the same output (a `grep -F`
      on the captured deny, added after each `lp5_edit`/`$clr` call, or one helper wrapping it).
- [ ] AM59 auto rec: the ambiguity deny (LP54 shape) names the blocked stop and the kept record.

### Step 6 — command shapes (test-workflow-contracts.sh)
- [ ] PK48 `test-writer.md` and `e2e-tester.md` each name Read `offset`/`limit` over a `sed -n` loop and forbid
      `git apply --check` probes; `e2e-tester.md` requires the project config with `--grep` and forbids `-c`/`--config`.

### Acceptance criteria → cases
AC1 → AM48-AM58.2, AMC21 · AC2 → AMC2, AMC20, AM59, LP needles · AC3 → G18.42-G18.54 · AC4 → PK48 · AC5 → K27-K30 ·
AC6 → A43 · AC7 → PK47 (prose rule; no script) · AC8 → IN65 · AC9 → step 7.

### Test-after
none.

## Vigilance (carried from research)
- gh: the exemption is judged per gh call; a chain holding a write still asks (G18.51, G18.52).
- gh: read-only calls fall through, no `allow` emitted (first-hit `decide()` would skip later asks).
- gh: `-R/--repo` before the subcommand is accepted in every form.
- gh: no write form (create/edit/delete/comment/merge, `api` any method) loses its ask.
- Freeze: no verdict, removal, rewrite, non-import line, or import outside the head passes; multi-line and
  `import type` handled; a line that looks like an import inside a template literal does not open the gate
  (the head ends at the first non-import line).
- Freeze: `arbiter.md` and the hook accept the same hunk.
- Python twin: OUT, written to follow-ups, never silently.
- `--clear`: removed only from the blocked-stop path and :340; the finished-pass sites keep it.
- `kit-pr-assets.py`: invalid project.json refuses, absent keeps `src/` only.
- `kit-audit-surface.py`: unchanged; A43 is a pin.
- Fix 6: `.gitignore` and both `install.sh` copies plus the count text move together.
- (critic F4) Python freeze twin keeps the refusal; listed in `follow-ups.md`, not silently dropped.
- (critic F6) the insertion path's :593 refusal is not cleared; a describe-scope `vi.mock` insertion stays refused.
- (critic F7) the import-only Edit has its own accept path; it never reaches :341 "touches no case".
- (critic F8) the AM fixtures list the path in `.tdd-unfrozen`, or the block tests nothing.
- (critic F9) the gh per-segment test keeps today's `\bgh` regex, so `\gh repo delete` still asks (G18.53).
- (critic F10) an added import cannot rebind a test global nor be a side-effect import (AM58).
- (critic F11) the :340 text names the blocked stop in auto; the queue cannot lift an ambiguity.
- (critic F12) `/kit:init` keeps today's "package.json + one root config" rule beside the new `src/` rule.
- (critic F5, G4) the cases labelled pin are run green first, never claimed red.
- (critic G1) the gh split joins `\<newline>` then splits on newline too (G18.54).
- (critic G2) the LP cases keep their `lifts it with` absent pin; `--clear` absent is an extra check.
- (critic G3) an added binding cannot reuse any identifier already in the file (AM58.2); identifiers are whole
  tokens, so the AM48/AM49/AM54 names (`g`, `h`, `T`) must be absent from the `lp_freeze_project` fixture text —
  the test-writer checks it, else picks unused names.
- (critic G5) AM49's combined Edit is judged on the minimal changed region of the body (head restored), not on
  its original old_string span (which covers `describe(` and U1/U2).
- (critic G7) the collision rule refuses body-first order (body uses `g`, then `import { g }`): the collision
  deny text and `arbiter.md` name the import-first order (or one combined Edit), so an agent is never left
  with a revert as its only exit.
- (critic G6) the specifier character class excludes quotes, `*`, spaces and `;`; no insertion inside a comment.

## Acceptance criteria (carried from the entry artifact)
- [ ] With an unfreeze verdict on case C of a frozen test, an Edit adding C's body plus a new `import` line in the top block is allowed; the same Edit without a verdict is denied; an Edit that removes or rewrites an existing import, or adds a non-import top-level line, is denied even with a verdict.
- [ ] No kit prompt tells the agent to run `loop-record.py --clear` on a blocked stop; the orchestrate/ship prompts state that in `auto` a blocked stop ends the turn with the record kept. A contract test pins it.
- [ ] Each listed read-only gh form (with or without `-R owner/repo`, `--json`, `--web` excluded) passes the git hook without ask; `gh api repos/x/y`, `gh pr create` (non-exact form), `gh pr merge`, `gh issue create`, `gh release create`, `gh repo create|delete|edit` still ask or deny as today. A form chained with a write (`gh pr view 1 && gh pr merge 1`) still asks.
- [ ] `test-writer.md` and `e2e-tester.md` carry the three command-shape rules; a contract test pins them.
- [ ] `kit-pr-assets.py ui` on a diff touching `frontend/src/X.tsx` with `app_roots: ["frontend"]` answers `ui`; with `app_roots: []` it answers `none`; `src/X.tsx` stays `ui` in both.
- [ ] `kit-audit-surface.py` on a diff under `frontend/src/` with `app_roots: ["frontend"]` returns the same surfaces as the same diff under `src/` with no roots.
- [ ] `/kit:init` proposes `app_roots: ["frontend"]` on a tree with `frontend/package.json` + `frontend/src/`, and `[]` on a root-level `src/`.
- [ ] `git check-ignore docs/work/x/codex-last-message.txt` succeeds.
- [ ] All existing kit test scripts (`.claude/hooks/test-*.sh`) pass.

## Plan critic
- pass 1: completeness 78, quality 62 — F1, F2, F3 confirmed (verifier), rewritten.
- pass 2: completeness 90, quality 74 — G1 confirmed (verifier), rewritten.
- pass 3: completeness 92, quality 85 — G7 (Minor, interpretation) → Vigilance.
- completeness: 92
- quality: 85
- surviving blockers: none

## Gate
- 2026-11-23 arbiter go (auto; round 1 corrections: AM50 also denies the AM49 combined Edit without a verdict,
  G18.43 adds `gh run` with `-R`; round 2 go)
- Contract: as written (Contract gate, 2026-11-23)
- Frozen cases to amend: none
- Open questions → answers 1-8 as printed under `## Proposed answers to research's open questions`
- Note (round 2): PK48 pins rule (c) Playwright in `e2e-tester.md` only; `test-writer.md` never runs Playwright.
