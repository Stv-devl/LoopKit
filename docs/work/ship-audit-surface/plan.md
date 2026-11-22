# Plan: Ship audit armed by what the diff touches   (entry: docs/specs/ship-audit-surface.md · research: docs/work/ship-audit-surface/research.md · design: n/a)
Token profile: standard
Base: 364f906
Revision: 2. It answers critic pass 1 (72/68). Four Majors survived the verifier:
- F1: a reset inside an existing `signOut` body now arms `session` through a context rule
  (A29, A30).
- F2: one rule derives `server_roots` from `protected_dirs` for v2 files, and it is tested in
  `test-install.sh`.
- F3: T14 also pins `Audit added:` and the user-request wording.
- F4: `_parse` keeps accepting v2. `test-hooks.sh` is now an edited file (PC25a), and the step 9
  gate covers it.

The Minors F5-F9 are carried into `## Vigilance`. F6, F7 and F8 are also folded into the
contract (pins, lineless findings, the deleted Backend section).

## Skips
- DB: SKIP. Kit tooling, no schema.
- Backend: SKIP. No service layer.
- INTERFACE: SKIP. No user surface.
- Front TS layers: SKIP.
  - The two test-first layers are kit suites: `test-audit-surface.sh` against
    `kit-audit-surface.py`, and the new wording cases in `test-workflow-contracts.sh`.
  - The TDD hooks match only `src/` and `shared/`, so the RED is observed by running the suite,
    not by a marker (`05-testing.md`: "Foreign toolchains use their own cycle").

## Write chain (sequential)
1. **L0 config key (test-after, before the RED, because the script reads it).**
   - `project_config.py`: add key `server_roots`, a list of root dir names validated like
     `app_roots` by `_root`, with no duplicates and `[]` by default.
     - It is placed **last** in `DEFAULTS`, and so last in the kit's `project.json`.
     - It is **not** emitted in the `shell` records, because no shell hook reads it. So
       `project-defaults.records` and the `#end=` count do not move.
     - `SCHEMA_VERSION` goes 2 → 3.
   - **One derivation rule**, `_derived_server_roots(protected_dirs)`: for each addon in
     `ADDON_DIRS` order (`supabase`, then `fastapi`), when **every** dir of that addon is in
     `protected_dirs`, its dirs are appended. Otherwise the result is `[]`.
   - `_parse` accepts versions 1, 2 and 3:
     - v3 requires `server_roots`;
     - v2 has no such key and gets the derived value. Hooks and `migrate` keep reading an
       unmigrated v2 file, and a wired v2 project is never read as `[]`.
   - `migrate` writes v3 with `server_roots` = the parsed value: the derived one for a v2 file.
   - `wire(addon)` appends that addon's `ADDON_DIRS` to `server_roots`, beside
     `protected_dirs`, and stays idempotent.
   - The kit's own `.claude/project.json` becomes `"schema_version": 3` with `"server_roots": []`
     as its last key.
2. **L1 RED.** One `test-writer` writes `.claude/hooks/test-audit-surface.sh` (cases A1-A31
   below), runs it, and returns the failure: `kit-audit-surface.py` is absent.
3. **L1 GREEN.** The main thread writes `.claude/hooks/kit-audit-surface.py` until A1-A31 pass.
   The suite does not move.
4. **L2 RED.** The same `test-writer` (SendMessage) appends T14-T17 to
   `.claude/hooks/test-workflow-contracts.sh`, runs it, and returns the first failure.
5. **L2 GREEN.** The main thread edits the prose, in this order:
   - `ship.md` 1bis and the Output block;
   - `guides/ship.md` "Why `critical` arms an audit";
   - the stale one-surface mentions: `orchestrate.md:312-313`, `guides/orchestrate.md:49`,
     `spec.md:141`. Each gets a one-line wording fix only.
   - `docs/Claude_Workflows.md` (French, `:246`, `:599-600`).
6. **Rule twin and doctor (test-after).**
   - `02-architecture.md` `## Backend` gains the line `Server roots: none.` The file goes from
     70 to 71 lines, within its budget of 72.
   - In the addon READMEs, the Backend paste blocks gain `Server roots: \`app\`, \`alembic\``
     (FastAPI) and `Server roots: \`supabase\`` (Supabase).
   - `/kit:init` (`init.md:108-113`) names `server_roots` in its one Edit.
   - `kit-doctor.py` gains `check_server_roots`. It compares the backticked names of that line
     (`none` → `[]`) with `project.json` through `compare("server-roots", …)`, is registered in
     `twins`, and gets a row in `doctor.md`'s table.
   - New cases go in `test-kit-doctor.sh` (pair agrees, pair drifts, line missing).
7. **Registration (test-after, asserted by the existing suites).**
   - `settings.json` allows: `python3 .claude/hooks/kit-audit-surface.py *`,
     `bash .claude/hooks/test-audit-surface.sh`, and `… *`.
   - `install.sh` `PROMPT_ALLOWS` gets the same 3.
   - The count pins move +3 in `test-install.sh` and `test-workflow-contracts.sh:721-726`.
   - The `hp_suite` list in `test-install.sh` and the `k2_suite` list at
     `test-workflow-contracts.sh:797` gain the new suite.
   - `kit-ci.yml` gets a step `run: .claude/hooks/test-audit-surface.sh`.
   - `kit-doctor.py` `NON_HOOKS` gets both new files.
   - The post-migration `schema_version == 2` pins become 3: `test-install.sh:584`, `:639`,
     `:776`, `:839`.
     - The invalid-file fixtures `{"schema_version":2}` (`test-install.sh:682-684`, `:746`,
       `:809`, `test-kit-doctor.sh:240`) stay as they are. They test "invalid, left untouched",
       not a version.
   - `test-hooks.sh` PC25a (`:1699-1700` at base): the "unsupported version" literal goes from
     `3` to `4`, so it still asserts a rejection naming `schema_version`.
     - PC21, PC23, PC30, PC31 and PC32 must stay green untouched. They do, because v2 still
       parses, `server_roots` is not in the records, and the key order is the defaults'.
     - Any other PC that goes red is a plan error, reported, never patched silently.
     - The PC25a edit is a corrected expectation. It is recorded under `## Gate` as an
       amendment line.
8. **Refactor**: `kit-audit-surface.py` under a green suite, no test edited.
9. **Full gate run, last, on the final state.**
   - Suites: `test-audit-surface.sh`, `test-workflow-contracts.sh`, `test-hooks.sh`,
     `test-install.sh`, `test-kit-doctor.sh`, `test-gate-route.sh`, `test-attempts.sh`,
     `test-small-lane.sh`, `test-rules-floor.sh`.
   - `python3 .claude/hooks/kit-doctor.py`.
   - `ruff check --select E4,E7,E9,F .claude/hooks` and `shellcheck -S warning` on the new
     `.sh`, when installed; if not, say so.

## Parallel lots (inside this track, same tree)
None. The run is fully sequential:
- L1 needs L0's key;
- L2's prose names L1's CLI;
- step 7 touches the pins that L2 also edits.

## Track isolation
- Worktree: `.claude/worktrees/ship-audit-surface` on `feat/ship-audit-surface` from `364f906`,
  because the main tree carries kit-boundary's uncommitted hook edits (`git status`, research).
- Shared foundations touched:
  - `.claude/project.json` schema, a v3 bump, so every downstream install migrates;
  - `project_config.py`, `install.sh`, `.claude/settings.json`, `kit-ci.yml`;
  - the suite registration lists.
- kit-boundary edits `test-hooks.sh` and other hooks. Expect a rebase on whichever lands second.
  `project_config.py` is not in kit-boundary's dirty set today.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/hooks/kit-audit-surface.py` | Create | `select` (A1, A2 floor) and `follow-ups` (A5) |
| `.claude/hooks/test-audit-surface.sh` | Create | L1 suite, A1-A31 |
| `.claude/hooks/project_config.py` | Edit | `server_roots` key, v3, migrate, wire |
| `.claude/project.json` | Edit | v3, `server_roots: []` |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | T14-T17; pins +3; `k2_suite` |
| `.claude/commands/loop/ship.md` | Edit | 1bis rewritten; Output `Audit:` lines |
| `.claude/guides/ship.md` | Edit | "Why `critical` arms an audit" (D1) |
| `.claude/commands/loop/orchestrate.md`, `.claude/guides/orchestrate.md`, `.claude/commands/loop/spec.md` | Edit | one-line wording, "the surfaces the diff touches" |
| `docs/Claude_Workflows.md` | Edit | D1, in French |
| `.claude/rules/02-architecture.md` | Edit | `Server roots: none.` (A6 rule copy) |
| `addons/fastapi/README.md`, `addons/supabase/README.md` | Edit | Backend paste block's `Server roots:` line |
| `.claude/commands/kit/init.md` | Edit | names `server_roots` |
| `.claude/hooks/kit-doctor.py`, `.claude/commands/kit/doctor.md` | Edit | `check_server_roots`, `NON_HOOKS` |
| `.claude/hooks/test-kit-doctor.sh` | Edit | server-roots cases; v3 pin |
| `.claude/hooks/test-install.sh` | Edit | v3 pins, migration v2 → v3 (plain and wired), wire adds roots, count pin, `hp_suite` |
| `.claude/hooks/test-hooks.sh` | Edit | PC25a's unsupported-version literal 3 → 4, and nothing else (also dirty in kit-boundary: rebase conflict expected) |
| `.claude/settings.json`, `install.sh` | Edit | the 3 allows |
| `.github/workflows/kit-ci.yml` | Edit | suite step |

Not touched:
- `.claude/commands/audit/security.md` (OUT);
- `.claude/agents/security-auditor.md`;
- `.claude/rules/11-token-budget.md` (OUT; "arms ship security" stays true);
- `kit-gate-route.py`, which is imported, not edited, and `test-gate-route.sh`;
- `project-defaults.records`;
- every kit-boundary file except `test-hooks.sh` (PC25a, above).

## Contracts

### `kit-audit-surface.py` CLI
Shape:
- `#!/usr/bin/env python3`, stamp `# cwk-guard-api: 1`, argparse, pathlib, typed, no
  third-party import.
- The cwd is the project root.
- Config comes from `project_config.load_strict(os.getcwd())`. Any `ConfigError` (absent,
  malformed) exits 2 and names the file: an unreadable config is never a silent "no audit".

**`select --base <rev>`** prints one JSON object to stdout and exits 0:
```json
{"surfaces": [{"surface": "authz", "reason": "server root `app`: app/routes/orders.py"}],
 "reason": null}
```
- `surfaces` is ordered `authz`, `session`, `input-output`, each present at most once. Its
  `reason` names the first match: a root and path, or a trigger and `path:line`.
- When `surfaces` is empty, the top-level `reason` is one line,
  `no server root touched, no trigger line added (<n> files)`. When nothing is declared it reads
  `no server root declared, no trigger line added (<n> files)`.
- The changed set is the working tree against `<rev>`:
  - `git -c core.quotePath=false diff --no-color --no-ext-diff --no-renames -U0 <rev>`;
  - plus every file of `git ls-files --others --exclude-standard`, read whole as added lines.
  - Same rule as `review.md:153-160`. `<rev>...HEAD` is never used.
- `<rev>` unknown to git, or the cwd not in a git work tree: exit 2.

**`authz` (paths).** A changed path with any status (added, modified, deleted, the add side of
a rename) whose first segment is in `server_roots`.

**Trigger lines.** Only the text of added lines (`+`, never `+++`) counts.
- Lines whose trimmed text starts with `//`, `#`, `*`, `/*`, `{/*` or `<!--` are skipped.
- Files under `docs/` or `.claude/`, and files that are `*.md`, `*.test.*`, `*.spec.*`, under
  `tests/` or `e2e/` are skipped.
- Matching is case-sensitive, as written below.

**`session`** triggers:
- the identifiers `signIn`, `signOut`, `logIn`, `logOut`, `login`, `logout`, `sign_in`,
  `sign_out`, `onAuthStateChange`, `setSession`, `getSession`, `switchUser`;
- `queryClient.clear(`, `.resetQueries(`, `.removeQueries(`;
- `localStorage`, `sessionStorage`, `indexedDB`, `document.cookie`, `persist(`;
- `accessToken`, `refreshToken`, `access_token`, `refresh_token`, `Authorization`, `Bearer `.
- The bare words `token` and `reset(` are deliberately absent: design tokens and form resets.
- **Sign-out context rule (S3):** an added line containing `.reset(`, `.$reset(`, `.clear(` or
  `clearStorage(` also selects `session` when, in the working-tree file, any line from 30 lines
  above it up to that line contains one of the identifiers above. Unchanged lines count, so a
  reset added inside an existing `signOut` body is caught.

**`input-output`** triggers:
- `dangerouslySetInnerHTML`, `.innerHTML`, `outerHTML`, `insertAdjacentHTML`;
- `target="_blank"`, `target: "_blank"`, `target: '_blank'`;
- `href={` or `src={` not followed by a quote;
- `window.open(`, `location.href =`, `location.assign(`;
- `type="file"`, `FormData`, `FileReader`, `UploadFile`, `multipart`;
- `webhook` or `callback` in an added line or in a changed path;
- `.passthrough(`, `z.any(`, `z.unknown(`;
- `z.object(` in a `*.gateway.ts`, `*.schema.ts`, `schemas.ts` or `shared/schemas/**` file.

**`follow-ups docs/work/<slug>/audit-<n>.json`** reads:
```json
{"findings": [{"surface": "input-output", "severity": "Major", "path": "src/a.tsx",
               "line": 12, "problem": "…"}]}
```
- It appends one line per Major and per Minor to `docs/work/<slug>/follow-ups.md`:
  `- [audit:<surface>] <path>:<line> — <problem> (major|minor)`.
  - `line` may be `null` for a finding with no line, such as a supply-chain or header Minor.
    The line then reads `<path> — <problem>`. A line number is never invented.
  - This is review-convergence C2's format, with the dimension `audit:<surface>`.
  - Writing goes through `kit-gate-route.py`'s `append_follow_ups(GateDir(slug, dir), lines)`,
    loaded with `importlib.util.spec_from_file_location`. It has the same dedupe and the same
    atomic write. A Critical is never written as a follow-up.
- It prints
  `{"critical": n, "major": n, "minor": n, "follow_ups": "<path>", "follow_ups_added": k, "next": "stop"|"clear"}`.
  `next` is `stop` iff `critical` > 0.
- It exits 2 when:
  - the path is not `docs/work/<slug>/<file>.json` (same rule as `kit-gate-route.py`
    `gate_dir`);
  - a field is missing;
  - the severity is outside `Critical|Major|Minor`;
  - the surface is not one of the six of `audit/security.md:51-58`.

### `ship.md` 1bis (new behaviour, prose)
- `economy`/`standard` are unchanged. The script is not run, and the report prints
  `Audit: not armed — profile <economy|standard>`.
- On `critical`:
  1. `<base>` = the plan's `Base:`, else `git merge-base HEAD <default branch>`.
  2. Run `python3 .claude/hooks/kit-audit-surface.py select --base <base>`. Exit 2 stops the
     ship like a red gate.
  3. The reason table is kept as the record of *why* the profile is critical (A2). A reason's
     surface counts only when the diff touches that surface's paths or triggers, so it never
     adds a surface the script did not return. Mechanically, the selected set is the script's
     set.
  4. The main thread may add a surface the script missed, printing `Audit added: <surface> —
     <reason>`. It **never drops** one the script returned (A3).
  5. An explicit user request runs exactly the surfaces the user named, whatever the script
     returned.
  6. If the selected set is non-empty, launch **one** `security-auditor` directly (Agent tool)
     with all the selected surfaces. It gets each surface's definition from
     `audit/security.md:51-58`, the changed-file list and the script's reasons. This does not go
     through `/audit:security`'s argument (a list there falls through to all six, W-R2).
  7. If the selected set is empty, no auditor runs. The report prints `Audit: not armed — diff
     touches no audit surface (<the script's reason>); review security ran` (A4).
  8. After the audit, the main thread writes the auditor's Critical/Major/Minor items with Write
     to `docs/work/<slug>/audit-1.json` and runs `kit-audit-surface.py follow-ups` on it.
     `next: stop` stops the ship (unchanged blocking rule).
     - An exit 2 means the main thread's own JSON is wrong: it corrects the file and reruns.
       The ship neither proceeds nor stops on it, and no finding is dropped or given an
       invented line. Otherwise the report prints
     `Audit: <surfaces> — <n> Critical / <n> Major / <n> Minor → <k> in docs/work/<slug>/follow-ups.md`.

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — kit suite `.claude/hooks/test-audit-surface.sh` against `kit-audit-surface.py`
Fixtures:
- Each case builds a scratch git repo (`git init -q`, one base commit, hand-written file
  contents), then applies its change to the working tree, uncommitted.
- `.claude/project.json` is written per case: v3, `server_roots: ["server"]` unless the case
  says otherwise.
- The expected surfaces are literal JSON, compared with `jq -e`.

**Core behaviour**
- [ ] A1 a front-only change with no trigger line selects no surface, and the reason names "no server root touched, no trigger line added"
- [ ] A2 a modified file under a declared server root selects `authz`, with a reason naming the root and the path
- [ ] A3 an untracked new file under a server root selects `authz`
- [ ] A4 a file moved into a server root (uncommitted `git mv`) selects `authz`
- [ ] A5 a file deleted under a server root selects `authz`
- [ ] A6 a front-only added `signOut` function that calls `queryClient.clear()` selects `session` and not `authz`
- [ ] A7 a front-only added `localStorage.removeItem` line selects `session`
- [ ] A8 a front-only added `dangerouslySetInnerHTML` selects `input-output` and not `authz`
- [ ] A9 a front-only added `<a href={item.url}>` selects `input-output`
- [ ] A10 a front-only added `<input type="file"` selects `input-output`
- [ ] A11 a change under a server root plus an added session trigger selects `authz` and `session` in one output, each with its own reason
- [ ] A29 a `useCartStore.getState().reset()` line added inside an existing `export function signOut()` body (the `signOut` line unchanged) selects `session`
- [ ] A30 a `form.reset()` line added in a component with no session identifier in the 30 lines above selects no surface

**Business rules**
- [ ] A12 a removed line matching a session trigger (`localStorage.clear();`) selects `session`, with a reason naming the trigger, "removed" and the path; a removed line matching only an input-output trigger selects no surface
- [ ] A13 a trigger word present only in an added comment-only line (`// localStorage later`) selects no surface
- [ ] A14 with `server_roots: []`, a change under `server/` never selects `authz`, and the reason says "no server root declared"
- [ ] A15 a trigger present only in a `*.test.tsx`, a `*.md` or a `docs/` file selects no surface
- [ ] A16 an added `<a href="/about">` (string literal) selects no surface
- [ ] A17 an added `const token = theme.tokens.primary` selects no surface
- [ ] A18 an added `Authorization: \`Bearer ${t}\`` header selects `session`
- [ ] A19 an added `z.object(` in an `orders.gateway.ts` selects `input-output`, and the same line in a component file selects no surface
- [ ] A20 a new file whose path contains `webhook` selects `input-output`
- [ ] A21 several triggers of the same surface yield that surface once, and the order is always `authz`, `session`, `input-output`
- [ ] A22 a committed change on the branch since the base (not only the working tree) is seen

**Follow-ups**
- [ ] A23 one Major and one Minor are appended as `- [audit:input-output] src/a.tsx:12 — <problem> (major)` and `… (minor)`, with `follow_ups_added` 2 and `next` `clear`
- [ ] A24 a Critical is not written to `follow-ups.md`, `critical` is 1 and `next` is `stop`
- [ ] A25 running the same input twice adds 0 lines the second time, and a review line already in `follow-ups.md` is kept
- [ ] A31 a Minor with `line: null` is appended as `- [audit:supply-chain] package.json — <problem> (minor)`

**Edge cases and refusals (exit 2)**
- [ ] A26 a missing `.claude/project.json` exits 2 and stderr names `project.json`; a malformed one exits 2
- [ ] A27 an unknown `--base` rev exits 2
- [ ] A28 a `follow-ups` input outside `docs/work/<slug>/`, an unknown severity, or a surface outside the six exits 2

### Test-first — wording, `.claude/hooks/test-workflow-contracts.sh` (each fails on today's files)
- [ ] T14 `ship.md` 1bis contains `kit-audit-surface.py`, `not armed`, `follow-ups.md`, `never drops`, `review security ran`, `one \`security-auditor\``, `Audit added:` and `the surfaces the user named`
- [ ] T15 `guides/ship.md` "Why `critical` arms an audit" names `kit-audit-surface.py` and the diff as the selector, and no longer contains "One surface is one `security-auditor`"
- [ ] T16 the `ship.md` Output block carries both `not armed — profile` and `not armed — diff touches no audit surface`
- [ ] T17 `docs/Claude_Workflows.md` names `kit-audit-surface.py` and `follow-ups.md` beside `1bis`

These take the spec's wording cases T1 and T2 under fresh IDs, because T1-T13 are taken
(`test-workflow-contracts.sh:1044-1084`).

### Test-after — existing suites
- `test-kit-doctor.sh`:
  - the server-roots pair agrees (`none` ↔ `[]`, and `app`/`alembic` both sides);
  - drift is reported red;
  - a `## Backend` section with no `Server roots:` line is reported red;
  - a deleted `## Backend` section with `server_roots: []` is OK, because the rule says "fill
    or delete";
  - a deleted `## Backend` section with non-empty roots is red.
- `test-install.sh`:
  - a plain v2 file migrates to v3 with `server_roots: []`;
  - a v2 file whose `protected_dirs` holds `app` and `alembic` migrates with
    `server_roots: ["app","alembic"]`, and one holding `supabase` migrates with `["supabase"]`;
  - `wire fastapi` adds `app` and `alembic`, `wire supabase` adds `supabase`, and wiring twice
    is idempotent;
  - the post-migration v2 pins become v3.
- `test-hooks.sh`: only PC25a's literal changes (3 → 4). Everything else must stay green
  untouched. It copies every `.py` of hooks into its fixtures.

## Vigilance (carried from research)
- Server roots come only from `project.json` `server_roots`; no `backend/` hard-coded anywhere.
  FastAPI wires `app`/`alembic` (`ADDON_DIRS`).
- `--no-renames`: a rename into a root is caught on its add side (A4). A deletion under a root
  arms `authz` (A5).
- The diff is the working tree plus untracked files against the base, never `<base>...HEAD`.
  Step 1bis runs before the commit.
- A Minor has no `Path:` line in the auditor output. The JSON the main thread writes for
  `follow-ups` must carry Minors too.
- The label set grows to `minor | out of scope | major`; `test-gate-route.sh` must stay green
  untouched.
- The selected surfaces go to one `security-auditor` launched directly, never through
  `/audit:security <list>` (W-R2 falls through to six).
- `load_strict`, never `load`: absent or malformed config exits 2, never "not armed".
- Only added, non-comment lines trigger (A12, A13). Docs and tests never trigger (A15).
- The two "not armed" variants coexist in the Output block (T16, AC9).
- The new contract IDs are T14-T17, and the existing T1-T13 are untouched.
- Every new hooks file is registered: `NON_HOOKS`, `k2_suite`, `hp_suite`, the allows, kit-ci
  (`check_hook_wiring`).
- The schema v3 bump: every existing v2 pin is updated and its fixture's intent kept, and the
  migration case is added.
- The `02-architecture.md` budget is 72; it ends at 71.
- F5: load `kit-gate-route.py` with `spec_from_file_location`, then put the module in
  `sys.modules` **before** `exec_module`. Its `@dataclass` plus `from __future__ import
  annotations` crashes otherwise.
- F6: only the post-migration pins (`test-install.sh:584`, `:639`, `:776`, `:839`) move to 3.
  The `{"schema_version":2}` invalid-file fixtures stay.
- F7: a lineless finding goes in with `line: null`, never with an invented line. An exit 2 from
  `follow-ups` means the JSON is corrected and rerun.
- F8: a deleted `## Backend` section is OK when `server_roots` is `[]`.
- F9: `server_roots` is last in `DEFAULTS` and in `project.json`, and absent from the `shell`
  records. PC30 and PC32 stay green untouched.
- F10: the sign-out context rule over-selects. `.clear(` matches Set/Map clears, identifiers
  match as substrings (`loginSchema`), and comments in the window count. The cost is one
  auditor, never a miss. Count it in the post-ship measure.

## Acceptance criteria (carried from the entry artifact)
- [ ] A `critical` ship whose diff touches no server root runs no `authz` audit.
- [ ] A `critical` ship whose diff changes a route, a service, a model or a migration under a server root runs `authz`.
- [ ] A front-only diff that changes sign-out or a client-cache reset runs `session`; one that adds `dangerouslySetInnerHTML` or an upload runs `input-output`.
- [ ] A diff with no selected surface runs no auditor and the report prints `Audit: not armed — …; review security ran`.
- [ ] Several selected surfaces go to one `security-auditor`.
- [ ] The main thread can add a surface with a reason; a surface the script returned is never dropped.
- [ ] An explicit user request runs the requested surfaces regardless of the script.
- [ ] Every Major and Minor of the 1bis audit is in `follow-ups.md`; a Critical still stops the ship.
- [ ] `economy`/`standard` ships unchanged: no auditor, report `not armed — profile …`.
- [ ] `test-audit-surface.sh`, `test-workflow-contracts.sh`, `test-hooks.sh`, `kit-doctor`, `test-rules-floor.sh` pass.

## Plan critic
- pass 1: completeness 72, quality 68. F1-F4 Major, verifier-confirmed, rewritten.
- pass 2: completeness 91, quality 88. F1-F4 fixed. F10 Minor → Vigilance.
- surviving blockers: none

## Gate
- 2026-11-17 go
- Contract: as written
- Server roots declared where? → new `project.json` key `server_roots` (schema v3) + `Server roots:` line in `02-architecture.md ## Backend`, doctor-checked; `app_roots` not reused
- FastAPI default roots? → `app`, `alembic` (`ADDON_DIRS`); Supabase `supabase`
- Deletion under a server root arms `authz`? → yes (A5)
- Audit follow-up writer and labels? → `kit-audit-surface.py follow-ups`, reusing `kit-gate-route.py` `append_follow_ups`; labels `(major)` / `(minor)`
- Multi-surface handoff? → one `security-auditor` launched directly, never `/audit:security <list>`
- Session trigger scope? → the explicit list in Contracts plus the sign-out context rule; bare `token` and `reset(` excluded
- amended 2026-11-17 A12: "a trigger word present only in a removed line selects no surface" → "a removed line matching a session trigger selects `session` (reason names the trigger, 'removed', the path); a removed input-output-only line selects no surface" — user decision at review round 1 (removing a sign-out cache clear is the cross-user leak); to confirm at merge
- amended 2026-11-17 test-hooks.sh PC25a: `.schema_version = 3` (unsupported) → `.schema_version = 4`, because 3 is now the current schema (planned in step 7; to confirm at merge)
