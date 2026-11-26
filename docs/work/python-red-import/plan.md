# Plan: Python RED on a package import, monorepo server roots, inline-program line   (entry: docs/specs/python-red-import.md · research: docs/work/python-red-import/research.md · design: n/a)
Token profile: critical
Base: 02911b50861239bd0ae17afbb4d4dfc96d11639f

## Skips
- DB: SKIP. The spec names no data model.
- Backend: SKIP. Kit hooks, config reader and prompts only.
- INTERFACE: SKIP. No user surface.
- TS/Python test-first layers: none. Kit code lives outside `src/`/`shared/`, so no TDD hook guards it. Each step writes its kit cases **first** in the shell suites and observes them red (failure output recorded in the handoff) before the code changes. This is the convention of the passes before this one.

## Write chain (sequential)
1. **Item 1, prover.**
   - Write cases RP1-RP11 (test-hooks.sh) and observe the non-pin cases red.
   - Then edit `addons/fastapi/hooks/tdd-prove-red-py.py:212` so `other_bad_names` also drops a pair with `m + "." + n == dotted`, and reword the comment block at :195-206 to name the package-import form.
   - Nothing else in the prover moves.
2. **Item 2a, server-root parsing.**
   - Write PC36-PC40 (test-hooks.sh) and observe them red where they encode new behaviour (PC36, PC38). PC37/PC39/PC40 pin refusals that already hold; they are regression pins, not red.
   - Then remove the single-segment refusal (`project_config.py:117-118`). `_root` keeps every other refusal.
3. **Item 2b, audit select.**
   - Rewrite A36 and add A44-A46 (test-audit-surface.sh); observe the non-pin cases red (A45 is a pin).
   - Then change `kit-audit-surface.py:165-170` to the prefix match `path == root or path.startswith(root + "/")`. The reason names the matched root.
4. **Item 2c, nested-backend detection.**
   - Write SR1-SR7 (test-hooks.sh) and PK61 (test-workflow-contracts.sh); observe them red (the subcommand does not exist, so every SR case fails on HEAD).
   - Then add the subcommand `project_config.py detect-server-roots <dir>` and a step-14 line in `.claude/commands/kit/init.md` that calls it and proposes its output as `server_roots`.
   - Write KD28 (test-kit-doctor.sh) as a pin: the doctor's check is already whole-string.
5. **Item 3, agents.** Write PK59 (test-workflow-contracts.sh) and observe it red. Then add one line to each of the six read-only agents.
6. **Item 4, allow list.**
   - Write PK60 and update HP-B2 (`HP_WANT` + count 35→36) in test-workflow-contracts.sh; observe them red.
   - Then add `"Bash(python3 .claude/hooks/kit-health.py *)"` to `.claude/settings.json` (after `kit-gate-route.py`, :47) and to `install.sh` `PROMPT_ALLOWS` (:382, next to `kit-attempts.py`).
   - `test-install.sh` `HP_ALLOWS` (a 29-entry subset, `length == 29`) gains the same entry and moves to 30. IN59 extracts PROMPT_ALLOWS itself and needs no change.
7. **Refactor.** Under a green suite, no test edited. Candidate: the `_root` messages stay "app root …" (Q4).
8. **Full kit run:**
   - `test-hooks.sh` (full mode: it runs `test_imported_symbols.py` too);
   - `test-workflow-contracts.sh`, `test-install.sh`, `test-kit-doctor.sh`, `test-audit-surface.sh`;
   - `python3 .claude/hooks/kit-doctor.py`.

## Parallel lots (inside this track, same tree)
None: fully sequential. Steps 2-6 each touch `test-hooks.sh` or `test-workflow-contracts.sh`, and the overhead of one critical pass on a shared suite file outweighs the gain.

## Track isolation
- Worktree: none, single track (main tree, branch `feat/python-red-import`).
- Shared foundations touched:
  - kit config reader `project_config.py`;
  - `settings.json` / `install.sh` allow list;
  - the fastapi addon prover.
  No other kit pass runs beside this one until it is merged.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| addons/fastapi/hooks/tdd-prove-red-py.py | Edit | :212 exact package-import rule, comment :195-206 |
| .claude/hooks/project_config.py | Edit | drop :117-118; add `detect-server-roots` subcommand + usage line |
| .claude/hooks/kit-audit-surface.py | Edit | :165-170 prefix match |
| .claude/commands/kit/init.md | Edit | step 14: server_roots from `detect-server-roots` |
| .claude/agents/{reviewer,verifier,plan-critic,story-critic,explorer,security-auditor}.md | Edit | one inline-program line each |
| .claude/settings.json | Edit | + kit-health allow |
| install.sh | Edit | + kit-health in PROMPT_ALLOWS |
| .claude/hooks/test-hooks.sh | Edit | RP1-RP11, PC36-PC40, SR1-SR7 |
| .claude/hooks/test-audit-surface.sh | Edit | A36 rewritten (declared), A44-A46 |
| .claude/hooks/test-kit-doctor.sh | Edit | KD28 |
| .claude/hooks/test-workflow-contracts.sh | Edit | PK59-PK61, HP-B2 count/list |
| .claude/hooks/test-install.sh | Edit | HP_ALLOWS + kit-health, 29→30 |

## Contracts
- **Prover:**
  - `other_bad_names = [(n, m) for n, m in bad_names if m != dotted and f"{m}.{n}" != dotted]`.
  - When `bad_names` holds only such pairs (and no foreign one), the existing `elif bad_names:` → `missing-module` → marker at :365, after the unchanged denies.
  - A `No module named` list takes precedence as today (:229).
- **`_server_roots(path, value)`:** list; each item through `_root` (refuses non-string/empty, `.`, `..`, empty segment, non-`SEGMENT` chars, a reserved first segment, a leading `-`); duplicates refused; returns a tuple of the strings as given.
- **`kit-audit-surface.py select`:**
  - for the first changed path (diff order) with some root `r` such that `path == r or path.startswith(r + "/")`: `reasons["authz"] = f"server root `{r}`: {path}"`;
  - single-segment roots give byte-identical reasons to today (`r == parts[0]`).
- **`project_config.py detect-server-roots <dir>`:**
  - Output: stdout one JSON array of relative POSIX paths; exit 0. Missing dir → exit 2 with usage.
  - Order (one rule): the root's own candidates first, then the parents `x` in sorted order. Within one parent, the names follow the fixed sequence `app`, `alembic`, `supabase` (written out in the code, never iterated from `ADDON_DIRS`, which lists `supabase` first). So `["backend/app","backend/alembic"]` and `["app","alembic"]`.
  - Candidates are the names in `ADDON_DIRS` (`app`, `alembic`, `supabase`), at `<dir>/<name>` or `<dir>/<x>/<name>` (one level, `x` not in `RESERVED`, not hidden).
  - `app` counts only when it holds `main.py` or `__init__.py`, so a front `app/` folder (Next.js, React) is not a server root. `alembic` and `supabase` count as directories.
  - A symlinked candidate is skipped.
- **Agent line** (identical in all six, placed as the last line of the opening honour-system blockquote, or in `plan-critic.md`, which has none, right after its line :13 "Bash is read-only …"):
  `> Never run an inline program: no \`python3 -\`/\`-c\`, \`node -e\` or heredoc program — Read/Grep, \`git -C\`, or a kit script instead.`
  plan-critic's version has no `> ` prefix.
- **Allow entry:** exactly `Bash(python3 .claude/hooks/kit-health.py *)`.

## Test plan (gate: validated by the user before EXECUTE)

No test-first TS/Python file (kit code). Every case below is a kit shell case, written first and observed red unless marked **pin** (the behaviour already holds; it guards against a regression in this pass). Expected values are hand-written literals from the spec and the CPython texts, never computed by the code under test.

### Prover: `.claude/hooks/test-hooks.sh`, new `run_prove_red_package_cases` (called next to `run_project_values_step5_cases`, :7407)
Fixture:
- `pv_addon_project`, plus `app/__init__.py`, `app/services/__init__.py`, `app/services/agent/__init__.py`;
- test file `tests/services/agent/test_choice.py` holding `from app.services.agent import choice` + `def test_pick(): assert choice.pick() == 1`;
- `CWK_PYTEST` pointed at a stub script under the case's tmp dir that prints a canned pytest output and exits with a given code (Q1). The canned texts are copied from CPython's message forms:
  - `ImportError: cannot import name 'choice' from 'app.services.agent' (/x/app/services/agent/__init__.py)`
  - `ImportError: cannot import name 'choice' from partially initialized module 'app.services.agent' (most likely due to a circular import) (/x/…)`

**Reproduction**
- [ ] RP1 a test importing `from app.services.agent import choice` while `choice.py` does not exist (stub prints the first text, exit 2) gets a RED marker and the "RED confirmed … does not exist yet" message, and `tdd-require-red-py.py` then lets `Write app/services/agent/choice.py` through (the EcoCrew 4.1 reproduction, AC1).

**Core behaviour**
- [ ] RP2 the same import failing as `cannot import name 'choice' from partially initialized module 'app.services.agent'` records the marker (AC2).

**Business rules**
- [ ] RP3 **pin**: `from app.services.agent import helpers` (stub prints `cannot import name 'helpers' from 'app.services.agent'`) records no marker, and the message is today's `unresolved-name` text: holds `failed at COLLECTION on` and `` `helpers` from `app.services.agent` `` (AC3, first half).
- [ ] RP4 **pin**: `from app.services.agent.choice import missing_fn` with `choice.py` present (stub prints `cannot import name 'missing_fn' from 'app.services.agent.choice'`) records the marker and names `missing_fn` as "not yet in" (AC3, second half).
- [ ] RP5 **pin**: the exact package pair plus a foreign `cannot import name 'x' from 'app.lib'` in the same output records no marker, with the `unresolved-name` text naming `` `x` from `app.lib` ``: one exact pair never masks a broken helper.
- [ ] RP8 the exact package pair (RP1's stub) in a test file carrying `@pytest.mark.skip` records no marker, and the message is the skip text (`carries \`@pytest.mark.skip\``) (spec:57, the skip branch unchanged on the new path). Red on HEAD, where the `unresolved-name` text answers first.
- [ ] RP9 **pin**: the exact package pair in a test file with no `assert` and no `pytest.raises` records no marker, no-assertion text (`contains no assertion`) (spec:22).
- [ ] RP10 **pin**: RP1's test file with the stub printing `async def functions are not natively supported` records no marker, async text (`no async plugin claimed`) (spec:57).

**Edge cases**
- [ ] RP6 **pin**: `from app.services import agent` (a package import one level up, `cannot import name 'agent' from 'app.services'`, dotted `app.services.agent.choice`) records no marker: a prefix of the module under test is not the module.
- [ ] RP7 **pin**: `No module named 'app.services.agent.choice'` (the `from app.services.agent.choice import pick` form) still records the marker as today.
- [ ] RP11 the monorepo layout (`fastapi.module_root` left at its default `app`, a single segment; the `backend/` prefix is found by `_split_root`; test `backend/tests/services/agent/test_choice.py`, package files under `backend/app/…`), with the RP1 stub, records the marker; the comparison is in dotted space (`app.services.agent.choice`), never `backend.…` (the EcoCrew 4.1 path).
- [ ] RP12 **pin** (review round 1, T1): a test file importing `from app.lib import choice as c` and `from app.services.agent import choice`, the stub printing only `cannot import name 'choice' from 'app.lib'`, records no marker, `failed at COLLECTION on` and `` `choice` from `app.lib` ``: a same-named symbol in another module is not the module under test (kills a classifier comparing the bare name).

### Server-root parsing: `.claude/hooks/test-hooks.sh`, `run_project_config_cases` (PC36-PC40, via `project_config.py check <dir>`)
- [ ] PC36 `server_roots: ["backend/app"]` is accepted (`check` exit 0) (AC4).
- [ ] PC37 **pin**: `["../x"]`, `["/abs"]`, `["a//b"]`, `["."]` are each refused, exit 3, stderr naming the entry (`'../x'`, `'/abs'`, `'a//b'`, `'.'`) (AC4). One assertion per entry.
- [ ] PC38 `["backend/app","backend/alembic"]` is accepted (`check` exit 0). The value reaching a consumer unchanged is proven by A44 (select) and KD28 (doctor), since `shell` records carry no server_roots line.
- [ ] PC39 **pin**: `["app"]` is accepted as today (AC4, last clause).
- [ ] PC40 **pin**: `["backend/app","backend/app"]` is refused, "lists a server root twice".

### Audit select: `.claude/hooks/test-audit-surface.sh`
- [ ] A36 **(declared rewrite of the existing case)**:
  - old: "A36 a server root is one path segment: apps/api … refused (exit 2)";
  - new: "A36 a multi-segment server root `apps/api` is accepted and arms authz on `apps/api/routes/x.py`", reason ``server root `apps/api`: apps/api/routes/x.py``.
- [ ] A44 `server_roots: ["backend/app"]` with `backend/app/api/routes/account.py` changed prints `authz` with reason ``server root `backend/app`: backend/app/api/routes/account.py`` (AC5).
- [ ] A45 **pin**: `["app"]` on the same diff (`backend/app/api/routes/account.py`) prints no `authz`, reason `no server root touched, …` (AC5, unchanged behaviour).
- [ ] A46 `["backend/app"]` with only `backend/appx/main.py` changed prints no `authz`: a sibling sharing the prefix is not under the root.
- Existing A2 (single-segment reason byte-identical) stays as is: it is the pin of "single-segment unchanged".

### Nested-backend detection: `.claude/hooks/test-hooks.sh`, new `run_detect_server_roots_cases`
- [ ] SR1 a fixture repo with `backend/app/main.py` and `backend/alembic/` → `detect-server-roots` prints exactly `["backend/app","backend/alembic"]` (AC6).
- [ ] SR2 a root-level `app/__init__.py` + `alembic/` → `["app","alembic"]` (single-segment layout, the fixed `app`, `alembic`, `supabase` sequence).
- [ ] SR3 a front `frontend/app/page.tsx` (no `main.py`/`__init__.py`) and `node_modules/app/main.py` (one level, a RESERVED parent) → `[]`.
- [ ] SR4 `supabase/` at the root → `["supabase"]`.
- [ ] SR5 `.hidden/app/main.py` → `[]` (a hidden parent is not searched).
- [ ] SR6 `backend/app` a symlink to a directory holding `main.py` → `[]` (a symlinked candidate is skipped).
- [ ] SR7 `detect-server-roots <missing dir>` → exit 2, stderr holds `usage:` and names `detect-server-roots` (red on HEAD, whose generic usage line at :753 lacks it).
- [ ] SR8 **pin** (review round 1, T2): root `app/__init__.py`, `zz/alembic/`, `aa/app/main.py`, `aa/supabase/` → exactly `["app","aa/app","aa/supabase","zz/alembic"]` (root list first, then the `app`, `alembic`, `supabase` sequence within a parent; it does not pin the parent sort, SR9 does).
- [ ] SR9 **pin** (review round 2, T2): 12 one-letter parents created in reverse order each with `alembic/` → exactly `a/alembic` … `l/alembic`: pins the parent sort.

### Doctor: `.claude/hooks/test-kit-doctor.sh`
- [ ] KD28 **pin**: `server_roots: ["backend/app"]` with `02-architecture.md` `Server roots: \`backend/app\`.` reports `ok server-roots`; with `Server roots: \`app\`.` reports `DIVERGENCE server-roots`.

### Contracts: `.claude/hooks/test-workflow-contracts.sh`
- [ ] PK59 each of the six read-only agents (`reviewer`, `verifier`, `plan-critic`, `story-critic`, `explorer`, `security-auditor`) holds `Never run an inline program`, `python3 -`, `node -e` and `heredoc` (AC7).
- [ ] PK60:
  - `.claude/settings.json` `.permissions.allow` and install.sh `PROMPT_ALLOWS` both contain exactly `Bash(python3 .claude/hooks/kit-health.py *)` (AC8);
  - each of the three named scripts `kit-health.py`, `kit-gate-route.py`, `kit-attempts.py` (a fixed list, never extracted from review.md, which names `kit-attempts.py` bare) is named in `review.md` and has a `Bash(python3 .claude/hooks/<x>.py *)` entry in both lists;
  - neither list holds a wider `kit-*.py` glob.
  `kit-pr-assets.py` is outside the checked set: its absence is asserted by test-install.sh:109-112.
- [ ] PK61 `kit/init.md` step 14 names `project_config.py detect-server-roots` as the source of `server_roots`.
- HP-B2 (existing): `HP_WANT` + the kit-health entry, count `35` → `36`. This is an amendment of an existing check, listed as a declared rewrite.

### Install: `.claude/hooks/test-install.sh`
- HP-B2 `HP_ALLOWS` + the kit-health entry, `length == 29` → `30`. This is an amendment of an existing check, listed as a declared rewrite.

## Vigilance (carried from research)
- The exact rule is `m + "." + n == dotted`, never a prefix, never `n == leaf` alone. `from app.services.agent import helpers` keeps today's `unresolved-name` text byte for byte.
- The comparison happens in dotted space (`dotted` strips the monorepo prefix), never in path space.
- Mixed output (exact pair + foreign `cannot import name`) stays `unresolved-name`.
- `dotted == ""`: no new branch keys on it.
- The marker is written only at :365, after every unchanged deny. No new write site.
- Validator and `select` change together. `backend/appx/…` never arms `backend/app`.
- Single-segment authz reason is byte-identical (A2).
- `..`, `/abs`, `a//b`, `.` stay refused after :117-118 goes, each with its own assertion.
- Allow list: exactly the kit-health form. Count and every copy (settings.json, install.sh, HP_WANT, HP_ALLOWS) move together. `kit-pr-assets.py` stays out.
- Agent line: same wording in all six, pinned per file.
- Prover tests use `CWK_PYTEST` stubs: pytest is absent locally and in CI.
- (critic F7) RP11 pins the monorepo layout: dotted space, never path space.
- (critic F8, follow-up, outside this entry) `project_config.py wire <dir> fastapi` (install.sh:550) re-adds `app`/`alembic` by equality to a monorepo's `["backend/app","backend/alembic"]` on reinstall. Goes to follow-ups.md at review.
- (critic F5) `shell` records carry no server_roots; PC38 asserts acceptance only.
- (critic F6) PK60 checks a fixed list of three scripts, never one extracted from review.md.
- `detect-server-roots` never proposes a front `app/` (no `main.py`/`__init__.py`) and never descends into `node_modules`/`.git`/`.claude`/hidden dirs or symlinks.

## Acceptance criteria (carried from the entry artifact)
- [ ] A Python test-first file importing `from app.services.agent import choice` while `app/services/agent/choice.py` does not exist (package `app/services/agent/__init__.py` present) gets a RED marker on save, and the module write is then allowed (EcoCrew 4.1 reproduction).
- [ ] The same with `from app.services.agent import choice` failing as `partially initialized module` records the marker.
- [ ] `from app.services.agent import helpers` (not the module under test, absent) still records no marker with the `unresolved-name` text; `from app.services.agent.choice import missing_fn` with `choice.py` present still records the marker as today.
- [ ] `server_roots: ["backend/app"]` is accepted; `["../x"]`, `["/abs"]`, `["a//b"]`, `["."]` are refused with a ConfigError naming the entry; `["app"]` behaves exactly as today.
- [ ] `kit-audit-surface.py select --base <rev>` on a diff touching `backend/app/api/routes/account.py` with `server_roots: ["backend/app"]` prints `authz` with its reason; with `["app"]` on the same diff it prints no `authz` (today's behaviour, unchanged).
- [ ] `/kit:init` on a fixture repo with `backend/app/main.py` and `backend/alembic/` proposes `["backend/app","backend/alembic"]`.
- [ ] The six read-only agent files carry the inline-program line, and a contract test checks it.
- [ ] `.claude/settings.json` and the settings `install.sh` installs both allow `python3 .claude/hooks/kit-health.py *`, exactly that form, and a contract test checks that every kit script `review.md` prescribes on its own (`kit-health.py`, `kit-gate-route.py`, `kit-attempts.py`) is in both lists.
- [ ] All kit suites pass (`test-hooks.sh`, `test-workflow-contracts.sh`, `test-install.sh`, `test-kit-doctor.sh`, the addon's Python hook tests) and `/kit:doctor` passes.

## Open questions (proposed answers, decided at the gate)
1. Prover test seam → `CWK_PYTEST` stub with canned CPython texts (RP1-RP11). Real pytest is absent locally and in CI.
2. `/kit:init` proof → a deterministic `project_config.py detect-server-roots` subcommand (SR1-SR7) that init.md step 14 calls (PK61). init.md alone, as a prompt, is untestable on a fixture.
3. A36 → rewritten to assert acceptance + prefix arming (declared rewrite).
4. `_root` wording "app root …" on server_roots refusals → left as is (the entry is named, which is what AC4 asks), and filed as a follow-up.

## Plan critic
- completeness: 95
- quality: 92
- surviving blockers: none
- history: pass 1 78/62 (F1-F4 Major, rewrite), pass 2 93/80 (F9 Major, rewrite), pass 3 95/92 clear.

## Gate
- 2026-11-26 go (user, Plan gate)
- Contract: as written
- Frozen cases to amend: none (kit shell suites, outside the freeze)
- Q1 prover test seam → CWK_PYTEST stub with canned CPython texts (RP1-RP11)
- Q2 /kit:init proof → `project_config.py detect-server-roots` subcommand called by init.md step 14 (SR1-SR7, PK61)
- Q3 A36 → rewritten: multi-segment root accepted and arms authz by prefix (declared rewrite)
- Q4 `_root` "app root" wording → left as is, follow-up
