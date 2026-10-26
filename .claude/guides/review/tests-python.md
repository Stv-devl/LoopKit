# Review checklist — `tests`

Read by a `reviewer` assigned `tests` (`.claude/agents/reviewer.md`). Python half: read with `tests.md` when the diff touches `app/` or `tests/`.

**If the diff touches Python** (`app/`, `tests/`), the checks of `tests.md` are written
for vitest and do not transfer as written. Read
`.claude/rules/07-backend.md`, "Tests — order, freeze, floor" — it is the only
copy — and apply these instead of the vitest-specific rows:

- [ ] `app/services/**` is **test-first and frozen**, everything else in `app/`
      is test-after. So the same freeze findings apply, in pytest terms: a case
      dropped, weakened or renamed against `plan.md`'s test plan is a **Major**;
      a frozen file edited without an entry in `.claude/.tdd-unfrozen` is a
      **Critical**; a marker missing from `.claude/.tdd-red/` means the RED was
      never observed — say whether the hooks are wired in this tree before
      calling it a finding on the diff.
- [ ] **`@pytest.mark.skip` / `xfail` / `pytest.skip()` in a frozen service
      test: Major.** There is **no lint behind this one** — ruff has no
      equivalent of `no-disabled-tests`, so unlike `it.skip` on the front end
      nothing else in the pipeline sees it. The freeze refuses one introduced by
      an insertion; one that was in the file from the start reaches only you.
- [ ] **Every service taking an isolation key has its cross-tenant case.** Not
      "the tenant filter is in the query" — a test that fails when the filter is
      removed. Isolation is a `WHERE` clause in Python, with no database barrier
      behind it: **Critical** when absent, and worse than usual here because the
      file is frozen, so the hole ships sealed.
- [ ] `asyncio_mode = "auto"` (or an explicit `pytestmark`) is configured.
      Without it every `async def` test fails on `async def functions are not
      natively supported` — no assertion runs. If the suite is green anyway, the
      async tests are not the ones proving it: say so.
- [ ] Mocks patch **where the name is looked up** (`app.services.x.embed`), never
      the defining module — patching the origin leaves the service holding the
      real client, the test passes and the network call happens: **Major**. A
      patch on a name the module under test *defines* is the other error and the
      freeze denies it.
- [ ] Assertions are on the outcome, not on the mock: `embed.assert_called_once()`
      where a returned value or a DB row was available is the same tautology as
      `toHaveBeenCalled` — **Major** on `app/services/`, Minor elsewhere. The one
      sanctioned exception (a filter sent to a store this suite does not run) is
      argued in `patterns/pytest-backend.md`.
- [ ] Run the touched tests with **`python -m pytest <paths>`** — `-m`, never the
      bare `pytest` script, which does not put the project root on `sys.path` and
      fails on `No module named 'app'` before running anything. Report the real
      output.
