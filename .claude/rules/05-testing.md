<!-- budget: 95 lines · /kit:doctor rules-budget -->
# Testing

## Required gate

All new or modified business logic has passing tests; every `Result<T>` asserts
success and failure. `utils.ts`, `mapper.ts`, `repository.ts`/`services.ts` are
test-first; hooks are test-after; a gateway needs a test once it builds a query.
UI tests are optional. Run `pnpm test:run`, never watch mode.

## Test-first cycle

Work one layer at a time: RED → GREEN → REFACTOR, then the next dependency.
`test-writer` writes one test file from the user-approved plan without reading
implementation. A real failing run must be observed before creating the module.
Once validated, the test is frozen; implementation bends to it.

The matcher keys on a filename boundary, under `src/` or `shared/`: bare or
prefixed `utils`, `mapper`, `repository`, `services`. `microservices.ts` does not
match. Snapshots and the scaffolded shared Result/errors files are outside the
ordering, not outside coverage. Foreign toolchains use their own cycle.

## A bugfix opens with the test that reproduces the bug

At every layer, including UI: write a case that fails because the defect exists,
observe it fail, then fix. In a frozen file this is a pure added case. A fix with
no failing-before/passing-after case is unproved.

## What the hooks refuse

The four hook deny texts are the specification: prove a genuine RED, require its
marker before module creation, freeze approved cases, and forbid shell writes or
snapshot updates that bypass Write/Edit. Never write tests or test-first source
from the shell. `.claude/.tdd-unfrozen` is the only exception list: exact path
containing `/`, plus a reason.

## The test is frozen

Allowed: byte-identical re-save, or a pure new case outside existing bodies with
its own assertion. Denied: assertion/title rewrite, deletion, insertion inside a
case, control flow that skips it, or shadowing the module. A correction is a
plan-level exception recorded in `.tdd-unfrozen`.

## Assert the behaviour, not the call

Assert returned value or externally visible effect, not `toHaveBeenCalled*`
unless no other trace exists. Never mock a pure function; mock only the layer
directly below.

## The expected value comes from somewhere the code cannot reach

Use a literal, hand-checked fixture or worked contract example. Never compute the
expected value with the module/helper under test or mirror its transformation.
Before a case, name an implementation defect that would make it fail.

## Suite integrity and coverage

Lint forbids assertionless/focused/disabled/conditional/duplicate-title tests.
Coverage thresholds: **lines 90 / functions 90 / branches 85**. Scope is all
four layer names under `src/` and `shared/`, plus `src/lib/**`, excluding three
wiring files and only three: `lib/client.ts`, `lib/queryClient.ts`,
`lib/utils/cn.ts`. The freeze and floor cover the same surface.

## Router

Before writing tests read `.claude/skills/project-rules/SKILL.md`, then only the
pattern it selects (`patterns/tests.md`, `msw.md`, fixtures, or backend pytest).
Rationale, exceptions and mutation guidance: `.claude/guides/05-testing.md`.
