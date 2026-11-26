# Research: Python RED on a package import, monorepo server roots, inline-program line   (entry: docs/specs/python-red-import.md)
Token profile: critical

Three `explorer` maps (prover; server_roots; agents + allow lists), reconciled here. HEAD 02911b5, branch `feat/python-red-import`.

## Pattern to follow

- **Item 1, prover.** `addons/fastapi/hooks/tdd-prove-red-py.py:207-212` already classes a `cannot import name 'n' from [partially initialized module] 'm'` by comparing `m` against `dotted` (the module under test, `tdd_py_lib.py:303-317`), with `other_bad_names = [(n, m) … if m != dotted]` (:212). The fix is in that one comprehension: also keep out a pair where `m + "." + n == dotted`. Then the existing `elif bad_names:` branch (:236-240) classes it `missing-module`, and the marker is written at :365 through the same denies as `No module named` (:230-231).
  `partially initialized module` is already in the regex (:208). The spec's "so is the same error with `partially initialized module`" needs no regex change, only the same exact-dotted rule.
- **Item 2, server roots.** The only server_roots validator is `.claude/hooks/project_config.py:112-121` (`_server_roots`). It already calls `_root` (:124-133), which accepts multi-segment canonical paths: it refuses `""`, `.`, `..` and empty segments (so `a//b`), and also a leading `-` and reserved first segments. Then :117-118 refuses any `/` ("is not one path segment"). Absolute `/abs` fails in `_root` on its empty first segment.
  Error text: `_root` says `app root {value!r} …` even when called for server_roots (wording leak).
- **Item 2, audit select.** `.claude/hooks/kit-audit-surface.py:165-170` arms authz on `PurePosixPath(path).parts[0] in roots`. The reason is ``server root `<first>`: <path>``.
- **Item 3, wording model.** `.claude/agents/implementer.md:56-62`, the "Refused shapes" block (`no `python3 -`/`-c`: Read/Grep, or a kit script;`). Twin in `test-writer.md:139-146`.
- **Item 4, allow list.** `.claude/settings.json:46-54` (kit-script entries) and `install.sh:381` `PROMPT_ALLOWS` (35 entries).

## Wiring points

- Prover registered by `install.sh:515` (PostToolUse, timeout 180). Its require twin is `addons/fastapi/hooks/tdd-require-red-py.py:81-102`, which reads `lib.marker_is_fresh` (`tdd_py_lib.py:401-411`). Marker: `.claude/.tdd-red/<mangled abs path>`, content stamp + `sha256:<digest>` (`tdd_py_lib.py:360-398`).
- pytest runner: `tdd_py_lib.py:816-853` `run_pytest`, through `pytest_cmd` (:799-813). **`CWK_PYTEST` env override** (:799-803) replaces the pytest command. It is the seam a fixture can use to feed canned pytest output without pytest installed.
- server_roots: parsed at `project_config.py:313-315` (v2 derives from protected_dirs `derived_server_roots` :102-109; v3 requires the key). Consumers:
  - `kit-audit-surface.py:162-170, :205`;
  - `kit-doctor.py:146-172` `check_server_roots` (whole-string set compare with backticked names of `02-architecture.md` `Server roots:`, already multi-segment safe), registered :1516;
  - `project_config.py:416` (document), :454-458 (`wire` appends `app`/`alembic`/`supabase` by equality), :696 (migrate).
- `/kit:init`: `.claude/commands/kit/init.md`, a prompt, no script. Step 9 :46-56 detects **app roots** (package.json/pyproject). Step 14 :112-118 writes `server_roots` "the server folders" **with no detection rule at all**. Writes go through `.claude/project.proposed.json` + `kit-apply.sh` (:119-125).
- review.md prescriptions:
  - :230 `python3 .claude/hooks/kit-health.py finding --dim … --verdict … --summary …` (step 1bis, one Bash call per finding);
  - :247 `kit-gate-route.py route …`;
  - :266 `loop-record.py --mode`;
  - :160 `kit-pr-assets.py ui …`, deliberately NOT allowed: `test-install.sh:109-112` asserts its absence.

## Reusable

- `_root` (`project_config.py:124-133`) already holds every refusal rule the spec lists for multi-segment roots. `_relpath` (:204-213) is the other canonical-path validator (data_client keys).
- `imported_symbols` (`tdd-prove-red-py.py:76-121`) already reads `from <parent> import <leaf>` as an alias, then `<leaf>.<name>` usages (:101-119). So `from app.services.agent import choice` + `choice.f()` yields `{f}` and passes the "names nothing" deny (:355-362).
- Test fixtures:
  - `test-audit-surface.sh:32-53` `new_repo '<server_roots json>'` (temp git repo), assertions `surfaces`/`ok`/`refused`;
  - `test-hooks.sh:2272-2290` `pv_addon_project` / `pv_addon` (runs a real addon hook on a temp project);
  - `test-hooks.sh:1496-1511` `write_project_json` / `pc_roots_expect`;
  - `test-kit-doctor.sh:316-334` KD14 `kd_roots`;
  - `test-workflow-contracts.sh:1372-1375` `pk`/`has`/`lacks`/`has_in`, HP-B2 (~:752-776).

## Blast radius

- `_server_roots` relax: feeds `kit-audit-surface.select`, `kit-doctor check_server_roots`, `document`, `wire`, `migrate`. Only `select` compares by first segment. `wire` adds single names by equality (unchanged).
- `test-audit-surface.sh:243-246` **A36 pins the refusal of a multi-segment root (exit 2)**, with the comment "a server root is one path segment". This case contradicts the spec and must be amended, not deleted: it is a kit shell suite, not a frozen TDD file. Record it in the plan as a declared rewrite.
- Allow lists are copied 4×:
  - `.claude/settings.json`;
  - `install.sh` `PROMPT_ALLOWS`;
  - `test-workflow-contracts.sh` HP-B2 `HP_WANT`, with the **exact count `length == 35`**;
  - `test-install.sh:293-` `HP_ALLOWS` (plus IN59 :965-989 extracting PROMPT_ALLOWS).
  Adding kit-health makes 36: all four copies and the count move together.
- Prover change: the addon copy is the only source (no `.claude/hooks/tdd-prove-red-py.py` in this repo). `test-install.sh:716` byte-compares only `tdd_py_lib.py`, which is untouched.
- Agent files: no line cap (only `commands/loop/*.md` ≤ 10 lines, `test-workflow-contracts.sh:63-65`). No second copy of the six read-only agents. `test-workflow-contracts.sh:748-751` pins `node -e` for implementer/test-writer only.

## Live DB state
n/a: kit hooks, config reader and prompts only.

## External surface
- CPython `ImportError` texts:
  - `cannot import name 'choice' from 'app.services.agent' (<path>/__init__.py)`;
  - `cannot import name 'x' from partially initialized module 'p' (most likely due to a circular import)`.
  [spec evidence, EcoCrew 4.1 transcript + regex already in HEAD :208]. No fetch needed.
- pytest is **not installed** in this environment (`python3 -m pytest` → `No module named pytest`), and `kit-ci.yml:56` runs `test-hooks.sh` with no pytest step found. [measured 2026-11-26]

## Traps (points of vigilance for the review)
- The exact rule is `m + "." + n == dotted`, never a prefix and never `n == leaf` alone. `from app.services.agent import helpers` (absent, not under test) must stay `unresolved-name` with today's text, unchanged byte for byte.
- `dotted` drops the monorepo prefix (`tdd_py_lib.py:303-317` via `module_root`). The comparison happens in pytest's dotted space (`app.services.agent`), never in path space (`backend/app/...`).
- Mixed output: one exact-dotted pair plus a genuinely foreign `cannot import name` must still be `unresolved-name`. Only the exact pair is excluded from `other_bad_names`.
- `dotted == ""` (a test file not named `test_*`, `:139-140`): `m + "." + n` can never equal `""`. Check that no new branch keys on an empty dotted.
- The marker is written only where it is written today (:365), after every deny (skip, assertionless, empty parser). No new write site.
- Relaxing `_server_roots` alone silently disarms authz for `backend/app`: `parts[0]` never equals `backend/app`. Validator and `select` change together. Match `path == root or path.startswith(root + "/")`; `backend/appx/…` must NOT arm `backend/app`.
- The authz reason must name the matched root (today ``server root `<first>`: …``). A multi-segment root changes the backticked value; any test pinning the reason string for single-segment (`test-audit-surface.sh:65-69` A2) must stay byte-identical.
- `_root`'s messages say "app root" on a server_roots refusal. The AC asks for "a ConfigError naming the entry", which the `{value!r}` already does. Rewording is optional and has a blast radius on any test grepping "app root".
- `[".."]`, `["/abs"]`, `["a//b"]`, `["."]` are refused today too, but by `_root`. Removing :117-118 must not remove them. Each AC case gets its own assertion.
- Allow-list count `35` → `36` in HP-B2, and `HP_ALLOWS` in test-install. Missing one copy makes a red suite, which shows up; adding a wider pattern (e.g. `kit-*.py *`) would be a silent widening. Exactly `Bash(python3 .claude/hooks/kit-health.py *)`.
- `kit-pr-assets.py` stays out of the allow list (its absence is asserted). The new contract test "every kit script review.md prescribes on its own is in both lists" must scope to the three named scripts, or explicitly exclude `kit-pr-assets.py`, or it fails on HEAD's deliberate choice.
- Agent line: same style as implementer's block. plan-critic has no honour-system blockquote, so pick a placement consistent across the six, and pin it with one contract check per file.
- Prover tests: no existing fixture exercises any failure class (PX7 covers only the config-failure path). New cases need pytest output; pytest is absent locally and in CI → `CWK_PYTEST` stub (see Open questions).

## Open questions
1. **Prover test seam:** cover AC1-AC3 with `CWK_PYTEST` pointed at a stub that prints the exact CPython/pytest text and exits 2 (runs everywhere, today's CI included), or with a real pytest in a temp venv (needs network/pip, skipped when absent)? Recommended: stub, with the canned texts copied from the 4.1 transcript.
2. **`/kit:init` detection (AC6):** init.md is a prompt with no script, so "on a fixture repo … proposes" can only be proven by a contract check on the prompt's rule text, unless a small detection helper script is added (new kit code + its test). Which one?
3. **A36** (`test-audit-surface.sh:243-246`) pins today's refusal of `apps/api`. Rewrite it to assert acceptance + prefix arming, with the declared rewrite recorded in the plan. Confirm.
4. **`_root` wording:** leave "app root …" in server_roots refusals (the AC only needs the entry named), or pass a key label so the message says "server root"? Recommended: leave it, a follow-up.
