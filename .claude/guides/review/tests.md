# Review checklist — `tests`

Read by a `reviewer` assigned `tests` (`.claude/agents/reviewer.md`). On a diff touching Python, read `tests-python.md` instead of the vitest-specific rows.

- [ ] Any new/modified business logic (services/repository, mapper, utils, hooks)
      has tests **that pass** (`.claude/rules/05-testing.md`). Business logic
      without a test = **Critical** (FAIL). UI (components/pages) = optional.
- [ ] The tests added actually test the new logic — a test that would pass before
      the diff proves nothing. Name it if you find one.
- [ ] **Behaviour, not calls.** An assertion on `toHaveBeenCalled*` where a
      returned value or an observable effect was available is a tautology: it
      survives any refactor of the logic. **Major** on a test-first layer, Minor
      elsewhere. Legitimate only for an effect with no other trace (a dispatch, a
      teardown) — `.claude/rules/05-testing.md`, "Assert the behaviour, not the
      call". A mocked pure function (`utils`, `mapper`) is a Major on the same
      grounds.
- [ ] **Where the expected value came from.** An expected value computed the way
      the code computes it — a `toEqual` whose right-hand side re-spells the
      mapper's own transformation, an `expected` built by the module under test or
      by a helper sharing its logic — agrees by construction and cannot fail:
      **Major** on a test-first layer. Its twin, an assertion pinned to a
      deliberate decision rather than a behaviour (`expect(MAX_RETRIES).toBe(3)`,
      a user-facing string asserted verbatim), is a **Minor**. Nothing automated
      sees either — `.claude/rules/05-testing.md`, "The expected value comes from
      somewhere the code cannot reach". Ask the question the rule asks: which
      change to the implementation would make this case fail?
- [ ] **A fix without its reproduction.** If the diff corrects a defect — a
      changed condition, an added guard, a corrected mapping — it carries a case
      that fails on the pre-diff code. No such case = **Major**, at every layer
      including components (`.claude/rules/05-testing.md`, "A bugfix opens with
      the test that reproduces the bug"). On a frozen file the case is a pure
      insertion, so "the file was frozen" is not an excuse; check whether the
      insertion is there.
- [ ] Each layer mocks the one directly below it — gateway for a repository,
      repository for a hook. A test reaching past a layer to the data client is a
      Major.
- [ ] A `gateway.ts` in the diff that **builds a query** (filter, ordering,
      pagination, count, a second call) has a test, and that test goes through
      MSW (`patterns/msw.md`). A hand-rolled chainable client fake
      (`mockReturnThis()`) is a **Major**: it accepts any chain, so it cannot fail
      when the query changes. Exception: a transport MSW cannot reach
      (realtime/WebSocket) — then the stub is correct and the coverage gap must be
      stated, not implied.
- [ ] Error and empty paths covered, not just the happy path; `Result<T>` failure
      branches asserted.
- [ ] For each test-first file in the diff, a marker exists in `.claude/.tdd-red/`
      (the RED phase was actually observed). Missing → say whether the hooks are
      wired in this tree at all before calling it a finding on the diff.
- [ ] Run the suite for the touched files with the **run-once** script
      (`pnpm test:run <paths>`) — never watch mode, it hangs. Report the real output.
- [ ] Hook tests build the `QueryClient` **outside** the render (a factory), not
      inline in the provider's `client=` prop — inline means a new client per
      render, a dead cache and a test that proves nothing.
- [ ] No test disabled, skipped or loosened to make the diff green. `it.only`,
      `it.skip` and an assertion-free test are caught by `@vitest/eslint-plugin`
      in the `pnpm lint` gate — if you find one here, the gate is not wired: say
      so, it is a finding about the repo.
- [ ] An **`it.todo`** in one of the three test-first files: the lint lets it
      through on purpose, and it means a case validated at the `/loop:plan` gate was
      never written. **Major** — you are the only check that sees it, because you
      are the only one reading `plan.md`'s test plan.
- [ ] A **snapshot** (`toMatchSnapshot` / `toMatchInlineSnapshot`) inside one of
      the three frozen files: **Major**. It is the only assertion that rewrites
      itself — `vitest -u` edits it in place, the runner is the writer, and no
      Write/Edit hook sees the frozen file change
      (`.claude/rules/05-testing.md`).
- [ ] Your own job is what no lint can see: a well-formed test asserting the
      **wrong** behaviour.
