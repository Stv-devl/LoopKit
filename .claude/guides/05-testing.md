# Testing — rationale

Read when changing `.claude/rules/05-testing.md`, when arguing about the scope of
the freeze, before running `/audit:mutation`, or when someone — you included — is
about to argue that this feature is the exception. Not loaded at session start.

## Why exactly three layers are test-first

`utils.ts`, `mapper.ts` and `repository.ts`/`services.ts` are pure logic — no
DOM, no `QueryClient`, no transport — so the write-run loop costs milliseconds.
On a component it costs ten times more, for a contract still moving between
`/loop:interface` and `/loop:review`. The ordering rule is priced, not doctrinal: it is
applied where it is cheap and where the contract is already settled by `/loop:plan`.

The two exclusions follow the same logic. A snapshot is written *from* the
output, so ordering one first is incoherent. `src/lib/result.ts` and
`src/lib/errors.ts` are copied verbatim from `templates/lib-core.md`, which ships
their test file — TDD against a copy-paste is theatre. Neither exclusion touches
the coverage floor, which still applies in full.

## Why the freeze needs the isolation, and vice versa

A frozen test file is granted the authority of a specification. Two distinct
failure modes attack that authority, and each mechanism covers one:

- the test gets **edited** into agreeing with a bug → the freeze
  (`tdd-freeze-tests.sh`);
- the test gets **written** that way in the first place, because the same context
  that is about to produce the implementation pulls the assertions toward what
  the code was going to do anyway → the `test-writer` isolation.

Neither substitutes for the other. That is also why "anchoring inside an existing
case" is denied even though it rewrites nothing: a `return;` at the top of an
`it()` kills the case with every assertion still lexically present, so the lint
sees a well-formed test and the freeze diff sees a pure insertion.

## The `shared/` drift, and what it teaches about scope

The hooks key on a **filename**, anchored on a path boundary and on nothing else
— no hook in the TDD trio contains the string `src/`. So
`shared/schemas/order.utils.ts` has always been test-first and frozen exactly
like `features/x/services/x.utils.ts`, while the coverage floor was scoped to
`src/**` and measured only the second.

`shared/` is the destination this very repo prescribes for code two features have
in common (`02-architecture.md`, last line of the import rules) — so the
*recommended* move was the one that landed outside the floor. Both roots are in
`templates/tooling-config.md` now.

The general lesson: **the freeze scope and the floor scope must be kept
identical**, in both spellings of each layer word and under both roots. A file
frozen but outside the floor is the worst combination available — its test can
never be corrected, and no number says whether it walked the branches.

## Why mutation testing matters here specifically

Nothing else in the loop verifies that a frozen test file deserves its authority.
Coverage says a line ran, not that removing the behaviour would fail anything —
so a file can sit at 100% and constrain nothing.

`/audit:mutation` is scoped to the three test-first layers. Read the command
before running it: the Vitest runner has two constraints, and incremental mode
has a blind spot on exactly this architecture.

A surviving mutant is usually a **missing case** — and appending one to a frozen
file is allowed without ceremony. That is how the two mechanisms fit together,
and it is why the audit is never a gate: it produces work, not a verdict.

## The excuses, in full

`05-testing.md` lists the seven sentences and one line each. The rebuttals live
here because they are an argument, not a trap — by the time you need them, you
already know the rule and you are looking for permission to leave it.

The shape they all share: each one is **locally reasonable**. None of them is
laziness, which is why "be more disciplined" has never worked on any of them.

- **"Too simple to fail."** Probably true of the code. Irrelevant to the file:
  the test written now is the one that stays frozen for the rest of the feature,
  and the version you skip is the version nobody writes later. What you are
  choosing is not "test or no test", it is "spec or no spec".
- **"I'll write the test right after."** The test that comes after the code
  passes on the first run. That single fact costs you everything the cycle buys:
  you never saw it fail, so you never proved it *can* fail; and you wrote it
  while knowing the branches, so you assert the cases you implemented rather than
  the cases the requirement has. It answers "what does this do", where the
  test-first version answers "what should this do".
- **"Already checked it by hand."** Manual checking is real evidence, and it
  expires immediately: no record of what was covered, no way to replay it on the
  next change, and the case you forgot under pressure is the one that ships.
- **"Deleting what I already wrote is a waste."** Sunk cost, exactly. That time
  is spent whichever way you choose. The live question is what you hold next: an
  implementation regenerated from a test that has been proven to fail, or the
  same implementation with a test bolted on that has been proven to do nothing.
- **"I'll keep it aside as a reference."** This is the previous excuse wearing a
  compromise. You will read it while writing the test, and the assertions will
  drift toward it — which is precisely the contamination the `test-writer`
  isolation exists to prevent (see above). Delete means delete.
- **"I need to explore first."** Legitimate, and the only one on the list that
  is. Exploration is how you find out what the interface should be. The failure
  is treating the exploration as a first draft: keep what you *learned*, throw
  away what you *typed*, then start the cycle.
- **"The test is hard to write."** Almost always a true report about the design,
  misread as a report about testing. A module that needs six mocks to observe one
  value is a module that needs six things to be called. Fix the seam.

**The pattern to notice in your own reasoning** is the sentence "this is
different because…". It is never followed by a reason that survives being written
into `.claude/.tdd-unfrozen` with a name attached — which is why that file asks
for a reason on the line, and why the exception list is short.

## Why the reproduction test is a separate rule

The ordering rule answers "which layers are written test-first". A bugfix asks
something else: the code already exists, so no hook fires, no marker is required,
and on a component nothing in the apparatus notices at all.

What the reproduction test buys is not coverage, it is a **proof of direction**.
A fix is a claim that the behaviour changed; the only evidence for it is a case
that fails before and passes after. Written after, it passes twice — once against
the fix, once against a `git stash` of the fix, and nobody runs the second.

The interaction with the freeze is the part that gets missed. On a frozen file
the reproduction case is an insertion, which the freeze table already allows, and
the justification the hook asks for ("why did the plan miss it") is answered by
the bug report itself. Reopening the plan for a bug is not required and mostly
theatre — the defect *is* the specification of the new case.

## Why the mirror assertion needed writing down

It is the only test defect in this repo that passes every automated check and
looks correct while reading the diff.

The mapper is where it appears, because the shape of the test invites it: you
have a `row` fixture, you need an expected entity, and the shortest way to write
one is to spell out the mapper's own transformation on the right-hand side. The
result is `expect(f(x)).toEqual(<f's body, inlined>)` — an identity, and identities
do not fail.

Coverage cannot see it: every line ran. The lint cannot see it: there is an
`expect` and it asserts something. Only the mutation audit sees it, and only
afterwards — a mirror assertion is the canonical way to reach 100% coverage with
a mutation score of zero. The gate question ("what change to the implementation
makes this fail?") is the cheap version of that audit, asked before the file is
frozen rather than after.

The change detector is the mirror image: it fails too easily instead of never.
Both come from the same missing step, which is deciding what the case is *for*
before deciding what to type.

## Why the gateway threshold is where it is

A function forwarding one call with no filter, no pagination and no error branch
has nothing to assert that the repository test does not already cover. As soon as
it builds a query — a filter, an ordering, a count, a second call — that
construction is logic.

And a hand-written chainable stub (`from().select().eq()`) does not test a
gateway, it re-states it: it cannot fail when the query changes, so it certifies
a request nobody checked. Hence MSW rather than a stub.
