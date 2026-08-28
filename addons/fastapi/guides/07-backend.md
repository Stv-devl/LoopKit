# Backend (FastAPI) — rationale

Read when changing `.claude/rules/07-backend.md` or one of the three Python TDD
hooks. Not loaded at session start.

## The three things pytest does differently, all measured

These are why `tdd-prove-red-py.py` does not simply read an exit code.

1. **A green run can exit non-zero.** With the addon's `addopts` in force,
   running one file prints `1 passed` and exits **1**, because coverage of the
   whole package is under the floor. A prover reading "exit ≠ 0" as RED would
   record a marker for a passing test — the apparatus lit up and proving
   nothing. The hook re-runs with the coverage flags stripped via
   `--override-ini`, **not** `--no-cov`: without pytest-cov installed, `--no-cov`
   is an unknown argument and pytest exits 4.
2. **One exit code covers three outcomes.** A missing module under test, a
   missing *other* import, and a syntax error all exit **2**. Only the first is a
   legitimate red, so the discrimination is on the module name inside the
   `ModuleNotFoundError`, matched **exactly** — a project whose `app` package is
   not importable reports `No module named 'app'`, and a prefix match would read
   that packaging failure as every feature's first red.
3. **"No test collected" cannot be trusted.** pytest exits 5 for an empty suite,
   but when the module under test does not exist — precisely the run the hook
   exists to bless — collection dies on the import and nothing is ever counted.
   So the presence of a `def test_…` is checked on the **source**, like the
   assertion check, not on pytest's tally.

## Why the scope is `app/services/` and stops there

`api/` is HTTP wiring — the gateway's twin, test-after. `models/` and `schemas/`
are declarations with no branch to walk. `core/` is majority wiring (config,
database, middleware); the two modules that do carry logic, `auth` and
`security`, would have to be listed file by file, and **a list of files rots
faster than a list of layers** — so they stay mandatory-to-test, test-after.

Both spellings of the layer are covered deliberately: the `app/services/` package
the rules prescribe, and the flat `app/services.py` a small service ends up with.
Keyed on the package alone, the second would have been frozen by no hook while
the rules still called it business logic.

## Why the shell door had to be closed on Python too

The three Python hooks are registered on Write and Edit, so a single shell
redirection into a module under `app/services/` created it with no RED ever
observed — a redirection is neither a Write nor an Edit. Same hole, same fix as
the TypeScript side: `prevent-destructive-commands.sh`, `CWK_TDD_PY_TARGET_RE`.

## Two rules of `05-testing.md` that now bind a `tests/services/` file

They were written for the frozen TypeScript files and apply here unchanged, but
nothing on the Python side said so while `tests/services/` was test-after:

- **Order inside the file: core business behaviour first, edge cases last.**
  Agents invert this spontaneously — edge cases are the easy ones to enumerate —
  and the central rule ends up the least covered thing in a file that can no
  longer be reordered.
- **The test name is the spec.**
  `test_get_by_id_raises_not_found_for_another_tenant`, not `test_get_by_id_2`.
  `patterns/pytest-backend.md`'s `test_{action}_{scenario}` is the shape, not a
  licence to stop at the action.

## Why the coverage table is a review criterion and not a gate

Saying "declared here, enforced below" would be the comfortable version and it
would be false. `--cov-fail-under` is global; coverage.py has no per-path floor.
A floor that nobody applies is worse than no floor, because the number in the
table reads as a promise.

Enforcing the four numbers means a per-package run — `--cov=app/services
--cov-fail-under=90`, then a second pass for `api/` — inside `/loop:ship`. That is a
decision about gate time, taken deliberately, not a config line to slip in.
