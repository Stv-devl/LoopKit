<!-- budget: 130 lines · /kit:doctor rules-budget -->
# Code Conventions

## TypeScript

- **Never use `any`** → use `unknown`, generics, or proper types
- Explicit return types on all functions. **One exception, and it is named**: a
  `queryOptions(...)` factory, whose branded return type is destroyed by any
  annotation written by hand — the whole point of the helper
  (`patterns/react-query.md`, "A query with a second caller"). The hooks built
  from it stay annotated.
- Zod for runtime validation

## Documentation

**JSDoc required:** services, React Query hooks, Zustand stores, exported
utilities in `lib/`, shared components (`components/ui/`, `components/states/`).

**JSDoc optional:** UI components internal to a feature, obvious handlers.

**Comments:** no implementation comments. Only JSDoc + type comments when
indispensable.

## Memoization

**Do not write `useMemo`, `useCallback` or `memo`.** The React Compiler is on
(`01-stack.md`) and memoizes at build time — hand-written memoization is
redundant, it hides the compiler's own decisions, and every dependency array is
a bug waiting to be written. Deleting one in a diff is a legitimate change; a
new one in a diff is a **Major** in review.

Two exceptions, and they are not about render performance:

| Case | Why the compiler doesn't cover it |
| --- | --- |
| A value whose **identity** is part of a contract — a dep of `useEffect` that must not re-fire, a key in an external cache, an object handed to a non-React library | The compiler optimizes rendering; it makes no guarantee about identity across renders, so it cannot be *relied on* for correctness |
| A genuinely expensive **non-render** computation (parsing a large payload, building a heavy index) | Worth pinning explicitly, with the measurement in the JSDoc |

An exception carries a one-line comment saying which case it is. Without that
line it reads as a leftover reflex and gets flagged. If a component is slow, find
out **why the compiler skipped it** — `pnpm lint` names the bail-out — instead of
memoizing around it.

## Semantic HTML (JSX)

**Never a `<div>` when a semantic tag exists** — `<header>`, `<nav>`, `<main>`
(one per page), `<section>` (with a heading), `<article>` (self-contained: card,
post, detail), `<aside>`, `<footer>`, `<figure>`/`<figcaption>`, `<time>`,
`<address>`, `<search>` (a filter bar), `<dialog>` (a modal — `patterns/a11y.md`).

**Rules:**

- `<button>` for actions, `<a>` for navigation
- Lists (`<ul>`, `<ol>`) for groups of repeated elements
- `<table>`, `<thead>`, `<tbody>`, `<th>`, `<td>` for tabular data
- `aria-label`, `aria-current` when the context is not obvious
- `<h1>` → `<h6>`: respect the hierarchy, no level skipping

**Two of those clauses are not decidable in a component file.** "One `<main>`
per page" and "no level skipping" are properties of the **assembled** page. The
split that makes them checkable — the layout owns the landmarks and the
`<main>`, the page owns the one `<h1>` — is written once in
`.claude/skills/templates/page.md`. Read it before writing a page or a layout.

**`<section>` means *with a heading*.** Without a heading or an `aria-label` it
is exposed as a generic container — a `<div>` that claimed otherwise, and a
`<div>` is the right answer for a wrapper with no name to give. The lint cannot
see this one: `jsx-a11y` checks accessibility defects, not the choice of tag.

## Accessibility

Semantic HTML above is the floor, not the whole rule. The patterns — icon-only
buttons, modals, dropdowns, live regions, skip links, focus management — are in
`.claude/skills/patterns/a11y.md`, and they are **read when building any
interactive component**, not only when a reviewer asks.

Two mechanisms back it, and neither covers the other: `eslint-plugin-jsx-a11y`
fails the build on static defects (`00-project.md`, the lint gate), and
`/review`'s `ui` dimension owns the behavioural half — focus, keyboard, live
regions, heading order.

## Error Messages

| Context                | Language |
| ---------------------- | -------- |
| Technical errors, logs | English  |
| User-facing messages   | French   |

**This row is the single declaration of the user language.** `CLAUDE.md`, the
commands and the agents all say "the user language" and mean exactly this cell —
change it here, then translate the copy in `.claude/skills/patterns/`.

The user-facing string is chosen **at the UI layer**, from the `ServiceError`
`code` — never carried inside the error object. `ServiceError.message` is
technical English, for logs only. See `patterns/feedback.md` (`userMessageFor`)
and `templates/lib-core.md`.

## SOLID

**S** is already carried by `02-architecture.md` (one job per layer, the size
thresholds) and **D** by `enforce-architecture.py` (the layer arrow, in the
direction it already points). They are listed for the seam, not for a second
check. The other three are `/review`'s `correctness` dimension and nothing else:

| Principle | The shape it takes in this repo |
| --- | --- |
| **O** — open/closed | a `switch`/`if` chain on a *kind* that grows a branch every time a case is added: a mapper switching on `row.type`, a badge variant with a ladder of `if`s. Extend through a lookup table, a map of handlers, composition |
| **L** — substitutability | a variant that *narrows* what its contract promised: a `ServiceError` subclass whose `code` leaves the union, a component accepting the full props type but ignoring `disabled`, a mock repository whose failure branch cannot return `err()` |
| **I** — small interfaces | a props type or service interface where a caller passes fields it has no use for; the tell is the call site — `null as never`, three `undefined` arguments in a row. Split along the actual callers |

**D has two legitimate idioms, and the principle does not pick between them.**
Adding an interface and an injection container in front of every repository is a
real failure mode, so: **injection is for crossing a boundary the arrow forbids,
not for decoupling inside a layer.** Inside one feature, downward (hook →
repository → gateway/mapper), the module boundary *is* the seam and `vi.mock`
swaps it in tests — do not add an interface there. Parameter injection is for
shared leaf code or a route helper needing feature behaviour: a narrow interface
named for what it *reads* (`SessionReader` in `patterns/guards.md`), handed in by
the wiring layer.

Rationale: `.claude/guides/03-conventions.md`.
