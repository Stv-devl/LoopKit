<!-- budget: 300 lines · /kit:doctor rules-budget -->
# Testing

## Required (gate)

All **new or modified business-logic code** must be covered by tests
**that pass**. This is a gate criterion (`/orchestrate`, `/review`, `/bmad:qa`):
no test = **FAIL**.

| Layer | Tests | Level | Order |
| --- | --- | --- | --- |
| `repository.ts` / `services.ts` (logic, `Result<T>`) | **Required** | mandatory | **test-first** |
| `mapper.ts`, `utils.ts` (pure functions) | **Required** | mandatory | **test-first** |
| `hooks.ts` (React Query orchestration) | **Required** | mandatory | after |
| `gateway.ts` (raw client calls) | **Required** once it does more than one plain call | mandatory | after |
| `components/`, `pages/` (UI) | optional | optional | after |

`pnpm test:run` must stay **green** (anti-regression) AND the diff must **add** the
tests for the new logic.

For anything returning `Result<T>`, "covered" means **both branches asserted**:
a happy-path-only repository test proves nothing about the boundary the whole
architecture is built on.

## Test-first — scope and rules

**This section is the only copy of the ordering rule.** `/plan`, `/orchestrate`,
`/review`, the `test-writer` agent and the three `tdd-*` hooks read it here.

Three layers are written **test-first**: `utils.ts`, `mapper.ts`,
`repository.ts` / `services.ts`. Everything else stays test-after, unchanged.

> **The FastAPI addon adds a second, twin cycle** — `app/services/**`
> test-first and frozen, its own three hooks, its own runner. Its scope, and
> only what differs, is in `rules/07-backend.md` (shipped by that addon).
> Everything below is shared, `.claude/.tdd-unfrozen` included.

| Excluded from the ordering | Why |
| --- | --- |
| Snapshots | written *from* the output — ordering one first is incoherent (`patterns/snapshot-tests.md`) |
| `src/lib/result.ts`, `src/lib/errors.ts` | scaffolded verbatim from `templates/lib-core.md`, which ships their test file. The coverage floor still applies in full. |

**No snapshot inside the three frozen files** — neither `toMatchSnapshot` nor
`toMatchInlineSnapshot`. `vitest -u` rewrites them in place and the writer is the
**test runner**, so `tdd-freeze-tests.sh` (registered on Write and Edit) never
sees it: the file ends up agreeing with the code, which is what the freeze exists
to stop. `prevent-destructive-commands.sh` denies `-u` when the command names one
of these files. Assert the value.

### How the hooks key on the name

The hooks key on the **filename**, not on the directory, and the layer word must
sit on a **boundary** — preceded by a `/`, a `.`, or nothing. `a.utils.ts`,
`services.ts` and a bare `utils.ts` match; `dateutils.ts` and `microservices.ts`
do not. No hook contains the string `src/`, so `shared/schemas/order.utils.ts`
is frozen exactly like `features/x/services/x.utils.ts`.

Two consequences worth knowing before you name a file:

- A shared helper carrying real logic under `src/lib/` is covered by the rule and
  by **nothing else** unless you name it `<something>.utils.ts`. `format.ts` is
  the file that slips through.
- **A bare `src/lib/utils.ts` matches**, so creating it is denied until a red is
  proved — and that is exactly where shadcn/ui drops `cn()`. Two honest answers,
  no third: `src/lib/utils/cn.ts` (what `templates/component.md` imports, and it
  does not match), or the path in `.claude/.tdd-unfrozen`.

### The cycle

| Phase | What happens | Proof |
| --- | --- | --- |
| **RED** | the test file is written from `docs/work/<slug>/plan.md`'s `Contracts` + `Test plan`, then run | it **fails**, and `tdd-prove-red.sh` recorded that failure |
| **GREEN** | just enough implementation to pass | the suite is green |
| **REFACTOR** | clean the logic, extract, rename | still green, **no test edited** |

If a test passes before the behaviour it names exists, **the test is wrong** —
rewrite it. A green RED phase means it asserts nothing.

**One layer at a time**: `utils` RED→GREEN, then `mapper`, then
`repository`/`services` — never three REDs batched then one GREEN. The dependency
order gives the sequence for free.

The *test list* is the opposite: written whole, up front, at the `/plan` gate.
Listing the behaviours first is the analysis; writing all the test **files**
first is the mistake.

### A bugfix opens with the test that reproduces the bug

**At every layer, test-first or not** — this is not the ordering rule above,
which says *which* layers start with a test. This says a correction starts by
making the defect visible, wherever it lives, a component included.

Write the case that fails **because the bug is there**, watch it fail, then fix.
A test written after the fix passes on the first run: it proves the code does
something, never that it does the right thing, and the regression it was meant to
guard is guarded by nothing.

In one of the three frozen layers the reproduction case is a **pure insertion**,
which the freeze allows — and the bug report *is* its specification, so the plan
is not reopened for it. A fix whose diff carries no new failing-then-passing case
is a fix nobody can prove: `/review`'s `tests` dimension scores it as such.

### What the hooks refuse

Four hooks, and **their deny texts are the specification** — each one names the
file, the rule and the exact way out, at the moment it fires. They are not
restated here: a description of a refusal is paid by every session to prevent an
attempt the hook stops for free.

| Hook | Event | Guards |
| --- | --- | --- |
| `tdd-prove-red.sh` | Post | that a red is a **real** red, and drops the marker |
| `tdd-require-red.sh` | Pre | **creating** the implementation module without that marker |
| `tdd-freeze-tests.sh` | Pre | editing a frozen test file (table below) |
| `prevent-destructive-commands.sh` | Pre, Bash | the same **files**, written from the shell — the three above are registered on Write/Edit only, so a redirection, an `rm` + fresh Write, or `vitest -u` would walk straight past them |

The last row is the one to internalise, because nothing announces it in advance:
**never write a test or a layer file from the shell.** It matches literal paths,
so a target behind a variable slips through — that gap is yours to not use.

**All four fail closed when `jq` is absent.** `/kit:doctor`'s
`hook-prerequisites` says so before it fires mid-edit.

### The test is frozen

Once written and validated at the `/plan` gate, a test file of those three layers
is **immutable for the rest of the feature**. The implementation bends to the
test, never the reverse.

| Edit | Verdict |
| --- | --- |
| **Adding a case** | allowed as a pure insertion — outside every case body, carrying its own `expect(`. Say which behaviour it covers and why the plan missed it |
| **Landing inside an existing case** | **denied**, though it rewrites nothing: one `return;` in an `it()` body kills every assertion below it and the lint cannot see it |
| **Shadowing the module under test** | **denied**. `const total = () => 5` at describe scope is a mock without the word — no `vi.mock`, no assertion touched, every case now running against a stub |
| **Re-saving it byte-for-byte identical** | allowed, and the only way to ask for a fresh RED verdict when the red was observed inside the `test-writer` and no marker landed |
| **Correcting a case** | rewriting an assertion, renaming an `it()`, deleting a case — **denied**. It is a plan-level correction: say which case and why, add the path to `.claude/.tdd-unfrozen`, then edit |

`.claude/.tdd-unfrozen` is the single visible exception list for the whole TDD
apparatus — it also exempts an implementation file from `tdd-require-red.sh`, for
the one case that deserves it: moving existing code into a new module. **An entry
is a path with a `/` in it and a reason**; a bare basename is skipped in silence
and would unfreeze every feature's `utils.ts` at once. The deny text that sent
you there prints the exact line to write.

### Isolate the context that writes the test

The test is written by the **`test-writer` agent**, one per file, at the RED leg
of its layer, from the `Contracts` and `Test plan` blocks — and it is forbidden
from opening the module under test. The freeze stops a test from being *edited*
into agreeing with the code; the isolation stops it from being *written* that way.

Everything after RED stays inline on the main thread (`/orchestrate`, Phase 4).

### The test name is the spec

`it()` reads as the behaviour in plain words — `it('returns err(not_found) when
the gateway finds no row')`, not `it('works')`. Written first, the test **is** the
prompt the implementation is generated against, so its precision is the
implementation's precision.

### Order inside the file

High-value business behaviour **first**, edge cases **last**. Agents spontaneously
invert this, and the core rule ends up the least covered thing in the file.

### The sentence that precedes every skipped RED

Every RED that got skipped in practice was skipped after one of these seven
sentences:

> "too simple to fail" · "I'll write the test right after" · "already checked it
> by hand" · "deleting what I wrote is a waste" · "I'll keep it aside as a
> reference" · "I need to explore first" · "the test is hard to write"

**Reading one of them in your own reasoning is the signal, not the argument.**
Stop, write the failing test. If you still believe the exception is real, say it
to the user and name the file — `.claude/.tdd-unfrozen` exists for exactly one
honest case, and it is written down, never assumed. Why each one is wrong:
`.claude/guides/05-testing.md`, "The excuses, in full".

## Assert the behaviour, not the call

Applies to every layer, test-first or not. A test asserts the **value returned**
or the **effect observable from outside**, never that a mock was called:

```typescript
// proves the test called the code, and nothing else
expect(gateway.fetchAll).toHaveBeenCalledWith('u1');

// proves the behaviour
expect(result).toEqual({ success: true, data: [] });
```

`toHaveBeenCalled*` is legitimate for exactly one thing: an effect with no return
value and no other observable trace — a mutation actually dispatched, a
subscription actually torn down. Everywhere else it is a tautology that survives
any refactor of the logic and fails on every refactor of the plumbing.

- **Never mock a pure function.** `utils.ts` and `mapper.ts` have no dependency
  worth faking; mocking them turns the test into a test of the mock.
- **Mock the layer directly below, never further.** The gateway for a repository,
  the repository for a hook.

### The expected value comes from somewhere the code cannot reach

`toHaveBeenCalled*` is the tautology everyone recognises. These two are the same
defect wearing a passing assertion, and **nothing automated sees either**: the
lint reads shape, coverage reads lines, and both are satisfied.

**Before writing a case body, name the change to the implementation that would
make this case fail.** Cannot name one → the case constrains nothing, whatever it
asserts. Name only a deliberate decision (a constant's value, the exact wording
of a message) → it is a **change detector**: it fires on the next redesign and
sleeps through every bug. `expect(MAX_RETRIES).toBe(3)` is one; "the fourth
attempt never happens" is the behaviour it was standing in for.

```typescript
// mirror: the same transformation on both sides, so it cannot disagree —
// it agrees with the code by construction, including when the code is wrong
expect(toDomain(row)).toEqual({ id: row.id, createdAt: new Date(row.created_at) });

// independent: a literal, hand-derived from the fixture
expect(toDomain(row)).toEqual({ id: 'u1', createdAt: new Date('2026-01-15T00:00:00Z') });
```

The expected value is a **literal**, a hand-checked fixture, or a worked example
from the plan's `Contracts`. Never the output of the module under test, never the
output of a helper that shares its logic — and on a mapper, never the raw row's
own fields read back through the same field names.

This is what `/audit:mutation` surfaces *after the fact*: a mirror assertion
keeps every mutant alive while showing 100 % coverage. Writing the literal is how
you avoid needing the audit to tell you.

### The gateway is the exception, and it needs MSW

One layer *is* the transport, so mocking the module below means mocking the
**network**: `patterns/msw.md`. A hand-written chainable stub
(`from().select().eq()`) does not test the gateway, it re-states it — it cannot
fail when the query changes.

The threshold in the table above is deliberate: a function forwarding one call
with no filter, no pagination and no error branch has nothing to assert that the
repository test does not already cover. As soon as it **builds a query**, that
construction is logic, and untested logic fails the gate like any other.

## The three things that check the suite itself

| | Catches | Where |
| --- | --- | --- |
| **Lint** (`pnpm lint`) | no assertion, `it.only`, `it.skip`, `expect` in an `if`/`catch`, two `it()` sharing a name — `test:run` stays **green** on all five | `01-stack.md`, "The lint on the tests" |
| **Coverage floor** | the untested branch — **lines 90 / functions 90 / branches 85** | numbers declared here, enforced by `templates/tooling-config.md` — **change both together** |
| **Mutation score** (`/audit:mutation`) | the assertion that never constrained anything | out of the loop, on demand, never a gate |

**Floor scope**: the four layer words in **both spellings** (`*.utils.ts` *and*
a bare `utils.ts`, same for mapper/repository/services), **under `src/` and under
`shared/`**, plus `src/lib/**`, minus three wiring files and only three —
`lib/client.ts`, `lib/queryClient.ts`, `lib/utils/cn.ts`. A test on any of those
restates the file; everything else under `src/lib/` stays in. Adding a fourth
exclusion is a decision that names the file and the reason, not a way to make a
red gate go green.

**The floor covers what the freeze covers, and nothing more.** A file frozen but
outside the floor is the worst combination available: its test can never be
corrected, and no number says whether it walked the branches. `hooks.ts` and
`gateway.ts` sit outside on purpose — a percentage on a React Query
orchestration measures plumbing; their gate is `/review`'s `tests` dimension.

A floor is a floor, not a target. The lint catches the *shape* of a bad test,
never a wrong one, and `it.todo` is caught by nothing except `/review`.


## Stack, naming, location

**Vitest** + **Testing Library**. In a gate or a subagent, always the run-once
script (`pnpm test:run`, see `00-project.md`) — watch mode never exits and hangs
the agent.

Tests are **colocated** with their source files:
`services.test.ts`, `hooks.test.tsx`, `{ComponentName}.test.tsx`.

## Patterns (read IF creating)

- Repository / mapper / hook / component tests → `.claude/skills/patterns/tests.md`
- Gateway tests + the E2E mock layer → `.claude/skills/patterns/msw.md`
  (and `msw-supabase.md` if that addon is installed)
- Fixtures & factories → `.claude/skills/templates/fixtures.md`
- `Result` / `ServiceError` themselves → `.claude/skills/templates/lib-core.md`

Rationale — why these three layers, why the freeze, why mutation testing:
`.claude/guides/05-testing.md`.
