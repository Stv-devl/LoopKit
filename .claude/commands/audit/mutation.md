---
description: Mutation audit — does the frozen test suite actually constrain the code, or does it only run it?
argument-hint: [a path under src/, or "everything"]
---

# /audit:mutation — do the tests actually bite?

Out of the loop, on the codebase **as it stands**. You write **nothing** to the
source here: the output is a report, and the fixes go back through the normal
loop with their tests.

## Why this exists and the other gates do not replace it

The whole architecture rests on one claim — *a frozen test file is a
specification, and the implementation obeys it*. Nothing in the loop verifies
that claim:

| Gate | What it proves |
| --- | --- |
| `tdd-prove-red.sh` | the test failed once, before the code existed |
| `pnpm lint` (`expect-expect`) | the test contains an assertion |
| `pnpm test:coverage` | the line was executed |
| **mutation score** | **removing the behaviour makes a test fail** |

A surviving mutant is an assertion that does not constrain anything: the code
under it can be changed, and the suite stays green. On a **frozen** file that is
worse than a missing test, because the freeze grants that file authority it has
not earned.

## Setup (once)

```bash
pnpm add -D @stryker-mutator/core @stryker-mutator/vitest-runner
```

```json
// stryker.conf.json
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "vitest",
  "reporters": ["html", "clear-text", "progress"],
  "mutate": [
    "src/**/*.{utils,mapper,repository,services}.ts",
    "src/**/{utils,mapper,repository,services}.ts",
    "shared/**/*.{utils,mapper,repository,services}.ts",
    "shared/**/{utils,mapper,repository,services}.ts"
  ],
  "incremental": true,
  "thresholds": { "high": 85, "low": 70, "break": null }
}
```

<!-- FILL: adjust the globs to this repo's real layout, cf. 02-architecture.md. -->

- **`break: null` on purpose.** This is not a gate. Past ~80 % the returns
  collapse, and a threshold nobody reaches is a threshold somebody disables —
  the same reasoning that keeps `--max-warnings=0` credible by keeping it
  reachable.
- **The scope is the three test-first layers**, not the repo. They are pure
  logic, they carry the freeze, and they are small. Widen to `*.gateway.ts` only
  once those tests exist (`05-testing.md`) — never to components.
- **TypeScript only.** Stryker mutates JS/TS and runs vitest. On a repo carrying
  the FastAPI addon, `app/services/` is frozen too (`07-backend.md`) and this
  command does **not** reach it — that layer holds specification-grade tests
  that nothing verifies. Covering it means `mutmut` or `cosmic-ray` and a second
  section here; say the gap out loud in the report rather than letting a green
  score read as whole-repo.
- **Both roots, `src/` and `shared/`.** The TDD hooks key on the filename and on
  nothing else — no root appears in `CWK_TDD_IMPL_RE` — so
  `shared/schemas/order.utils.ts` is frozen exactly like its `src/` counterpart,
  and a frozen file is precisely what this audit exists to interrogate: it was
  granted the authority of a specification and nothing else checks it deserves
  it. Scoping to `src/` alone leaves the `shared/` ones unchallenged.
  These globs must stay aligned with the coverage floor's
  (`templates/tooling-config.md`, `TEST_FIRST`) — same set, two runners.
- **Two globs per layer word**, as in the coverage floor: `*.utils.ts` does not
  match a bare `utils.ts`, and the bare spelling is frozen just the same. A
  frozen file outside `mutate` is precisely the one this audit exists to check.
- `.stryker-tmp/` and `reports/` go in `.gitignore`.

### Constraints of the Vitest runner

- **`coverageAnalysis` is not configurable** — the runner ignores the property
  and always uses `perTest`, which is the fastest mode. So the runtime figures
  quoted for mutation testing do apply here; on the three test-first layers
  expect roughly one test per mutant. **Measure the first full run anyway** and
  write the number down: it is the input to deciding full vs incremental later.
- **`threads: true` only.** If this repo's Vitest config sets another pool, the
  runner will not start. Say so rather than silently switching the project's
  pool to please an audit.
- **Browser Mode is not supported.** Irrelevant while the scope is the three
  pure-logic layers, and one more reason not to widen it to components.

## Process

### 1. Decide the scope, and say it

`$ARGUMENTS` is a path, or `everything`. Then decide **full or incremental**, and
announce which:

> **Incremental has a blind spot that this architecture walks into.** Stryker only
> detects changes in *mutated files* and *test files*. In a layered repo the
> meaning often lives elsewhere: change `types/types.ts` or `shared/schemas/*`
> and a mapper's contract changes without either file being mutated or a test.
> The incremental run then reports a **stale score, in green**.
>
> So: **force a full run** when the diff since the last audit touches
> `types/`, `shared/schemas/`, or `src/lib/`. Otherwise incremental is fine.

### 2. Run it

```bash
pnpm exec stryker run                       # everything in `mutate`
pnpm exec stryker run --mutate "<path>"     # one scope
```

Report the real output. A run that crashed is a result, not a reason to skip the
audit — the two constraints above are the first things to check.

### 3. Read the survivors, and classify them

A survivor is only interesting once you know *why* it survived. Three kinds, and
they do not get the same treatment:

| Kind | What it means | What to do |
| --- | --- | --- |
| **Uncovered behaviour** | a real case nobody asserts | a case to add — the valuable one |
| **Equivalent mutant** | the mutation changes nothing observable (a defaulted value, an unreachable guard) | not a defect. Name it, don't "fix" it |
| **Tautological assertion** | the test runs the code without constraining it — typically `toHaveBeenCalled` where a return value existed | rewrite the assertion: `05-testing.md`, "Assert the behaviour, not the call" |

Rank by **what the surviving mutant would let ship**, not by file or by count.

### 4. The fix path goes through the freeze, and it fits

A survivor on a frozen file almost always means **a missing case**, and the
freeze allows exactly that: appending a new `it()` is a pure insertion, permitted
without ceremony (`tdd-freeze-tests.sh`). Say which behaviour it covers and why
the `/loop:plan` test plan missed it.

Only a survivor caused by a **wrong** assertion needs `.claude/.tdd-unfrozen` —
tell the user, with which case and why, before touching anything.

Propose. Apply nothing here.

## Output

```
## Mutation audit: <scope> — score <n>% (<n> killed / <n> survived / <n> timeout)
- Run: full | incremental (<reason>) · <duration>
### Survivors that matter
- path:line — <mutation applied>
  Ships: <what could be shipped broken with the suite green>
  Fix: <the case to append, in `it()` words>
### Tautological assertions found
- path:line — <the assertion, and what it should assert instead>
### Equivalent mutants (not defects)
- path:line — <why nothing observable changes>
### Not covered by this run
- <what was out of `mutate`, and why> (components, gateway, anything skipped)
```

## Rules

- **Never a gate.** No `/loop:ship` step, no `/loop:review` dimension: a Stryker run cannot
  report alongside the parallel reviewers, and its findings are not about a diff.
- Read-only on the source. Stryker sandboxes its mutations; if you find a mutated
  file in the working tree, stop — something went wrong.
- A score with no survivor analysis is a number, not an audit. The percentage is
  the least useful line of the report.
- State what was **not** mutated. An audit that quietly excluded half the repo
  reads as a clean bill of health.

## Task: $ARGUMENTS
