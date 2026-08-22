# Functional story gate — compact rules

This file is the complete project-rule context needed by `story-critic`. The
critic must not load the full architecture or testing rules during this early,
functional gate.

- A story is one deliverable vertical increment, not a technical layer.
- Every acceptance criterion describes an observable, falsifiable behaviour.
  Assert outcomes or observable effects, never implementation calls.
- Name every prerequisite story; dependencies must be acyclic and buildable.
- Trace every story to at least one PRD requirement. Adding untraced behaviour
  is scope creep; leaving a requirement orphaned is a failure.
- Stories must not overlap. Each must state what a reader might reasonably
  assume is included but belongs elsewhere.
- One story must fit one research → interface → plan → execute → review → ship
  loop. Split several screens/tables/independent flows; merge trivial slices.
- Stories are functional at this stage. Missing file paths, repository
  signatures, component names, or technical patterns are not findings.
- Reject an explicitly required implementation that would violate a hard
  boundary: cross-feature imports, business logic in UI, manual SQL migrations,
  or data-client calls outside the data layer. Do not invent architecture to
  perform this check.
- Security/authorization, accessibility, and user-facing language requirements
  must map to concrete stories instead of dissolving into "everywhere".
- A story must not deliver anything the same brief's `Out of product` section
  excludes. That is Major, escalated with the excluded line quoted, and never
  resolved by narrowing the story to fit: the boundary may be stale, and only the
  user moves it. This gate is that section's **only** enforcer — `/review` does
  not replay it against the code, and a feature entering by `/spec` never comes
  through here.
- A story must not contradict a `Product invariant` of `docs/product/brief.md`.
  That is Critical and it is escalated, never fixed by softening the story: the
  invariant is a product decision, and only the user changes it. This gate owns
  the **intent**; `/review`'s `correctness` owns the same invariants against the
  **code**, and neither covers the other — a feature entering by `/spec` never
  meets this gate at all.
- Trace a story to the PRD's **functional requirements**, never to its `Epics`
  block: that block is indicative and carries no story ids.
