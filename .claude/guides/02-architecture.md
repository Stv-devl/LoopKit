# Architecture — rationale

Read when changing `.claude/rules/02-architecture.md`, or when arguing about
whether a given import is legitimate. Not loaded at session start.

## Who checks the duplication rule: the reviewer, and nothing else

"If two features share code, move it into `shared/`" has no hook behind it.
Duplication is not decidable from an Edit delta, and `/refactor:clean` is the
wrong tool — `knip` finds code that is **dead**, which is the opposite problem:
a rule written twice is used twice.

So it is a review checkbox on `/review`'s `correctness` dimension, and it is
worth the seat: of the two copies, only one ever gets fixed, and nothing fails
until the day they disagree.

Moving it has a second consequence worth knowing before you do it. The four layer
words are test-first and frozen under `shared/` exactly as under `src/`, so a
shared schema helper needs its RED like any other, and it is inside the coverage
floor. `.claude/guides/05-testing.md` has the story of how that drifted.

## Why the arrow is only checked on the direct edge

The chain guards → providers → features passes the hook, and that is a deliberate
choice rather than a loophole.

The provider is a **seam**: it exposes a feature-agnostic contract (`useAuth()`),
so swapping the feature behind it changes no component. What the rule actually
forbids is a shared file **naming a feature itself** — that is the edge that
makes shared code unusable by a second feature.

When the transitive guarantee is wanted too, the answer is injection, not a
stricter hook: `patterns/guards.md` ships both shapes, and `beforeLoad` with an
injected `SessionReader` is the version with no feature anywhere in the chain.
Checking transitively would ban the provider seam along with the real defect.

## Why the un-split services file is spelled bare

Three mechanisms key on these names and they do not agree by construction:

- the TDD hooks and the coverage glob match the prefixed spelling — it is
  test-first and inside the floor;
- `enforce-architecture.py` allows the data client only in a gateway file and in
  the **exact basename** `services.ts`.

So the prefixed spelling is frozen, measured, and denied the one import it exists
to hold. The bare spelling is the only one all three agree on.
