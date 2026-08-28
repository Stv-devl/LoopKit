# Page & Layout Template — where the landmarks live

`.claude/rules/03-conventions.md` ("Semantic HTML") names ten elements. Four of
them — `<header>`, `<nav>`, `<main>`, `<footer>` — and the whole `<h1>`→`<h6>`
hierarchy are **properties of the assembled page**, not of a component file. No
single component can be reviewed for "one `<main>` per page" or "no level
skipping"; that is decided here, once, and every page inherits it.

This file fixes the contract. Two files share the page, and the split is the
only thing worth memorising:

| Owns | Layout (`src/components/layouts/`) | Page (`features/*/pages/`) |
| --- | --- | --- |
| `<header>`, `<nav>`, `<footer>`, the skip link | **yes** | never |
| `<main>` | **yes**, exactly one | never — it renders *into* it |
| `<h1>` | never | **yes**, exactly one |
| `<h2>`+ | never | yes, under its `<h1>` |

> **Colours and spacing are tokens**, same as `templates/component.md` — the
> classes below are placeholders until `/loop:design-system` writes the real ones.

## The layout owns the landmarks

```tsx
// src/components/layouts/AppShell.tsx
import { Link } from "@tanstack/react-router";

/**
 * Application shell: the landmark skeleton every authenticated page renders
 * into. It carries the one `<main>` of the page — a page that adds its own
 * gives the document two, and a screen reader's "jump to main content" stops
 * being a single destination.
 */
export function AppShell({
  children,
}: {
  children: React.ReactNode;
}): React.ReactElement {
  return (
    <>
      <a href="#main-content" className="sr-only focus:not-sr-only">
        Aller au contenu principal
      </a>

      <header className="border-b border-default">
        <nav aria-label="Principale">
          <ul className="flex gap-4">
            <li>
              <Link to="/app" activeProps={{ "aria-current": "page" }}>
                Tableau de bord
              </Link>
            </li>
            <li>
              <Link to="/app/items" activeProps={{ "aria-current": "page" }}>
                Éléments
              </Link>
            </li>
          </ul>
        </nav>
      </header>

      <main id="main-content" tabIndex={-1} className="mx-auto max-w-5xl p-6">
        {children}
      </main>

      <footer className="border-t border-default p-6">
        <address className="not-italic">contact@exemple.fr</address>
      </footer>
    </>
  );
}
```

Four things in that skeleton are the pattern, and each one fails silently if
dropped:

- **`<nav aria-label="…">`.** A page with two `<nav>` (main and breadcrumb, main
  and footer) exposes two identical "navigation" landmarks and the user has to
  guess. The label is what makes them distinguishable — and it is the one case
  `03-conventions.md`'s "`aria-label` when the context is not obvious" is
  really about.
- **The `<ul>` around the links.** A group of repeated elements is a list; a
  screen reader announces "2 items" and the user knows how far the menu goes.
  A row of bare `<Link>` announces nothing.
- **`aria-current="page"`** via `activeProps`, not a CSS class. The colour tells
  a sighted user which page they are on; `aria-current` is the only thing that
  tells anyone else.
- **`tabIndex={-1}` on `<main>`.** Without it the skip link moves the scroll
  position and leaves focus behind, so the next `Tab` returns to the header —
  the link looks like it works and does nothing (`patterns/a11y.md`).

`AppShell` is wired once, in the route (`patterns/guards.md`, "Protected
route"). `PublicLayout` is the same skeleton with the authenticated `<nav>`
removed.

## The page owns the heading tree

```tsx
// features/items/pages/ItemsPage.tsx
import { State } from "@/components/states/State";
import { GlobalLoadingBar } from "@/components/loading/GlobalLoadingBar";
import { Route } from "@/routes/app/items";
import { useItems } from "../hooks/hooks";
import { ItemsToolbar } from "../components/ItemsToolbar";
import { ItemList } from "../components/ItemList";

export function ItemsPage(): React.ReactElement {
  const search = Route.useSearch();
  // `useItems` carries `placeholderData` — its key holds the search, so without
  // it every keystroke empties `data` and this block falls back to the loading
  // state (`patterns/react-query.md`, "When the key changes").
  const { data, isPending, isError, error, isFetching, isPlaceholderData } =
    useItems(search);

  return (
    <>
      <h1>Éléments</h1>

      {/* ItemsToolbar carries its own <search> element — patterns/url-state.md */}
      <ItemsToolbar />

      <section
        aria-labelledby="results-heading"
        aria-busy={isFetching}
        className={isPlaceholderData ? "relative opacity-60" : "relative"}
      >
        <h2 id="results-heading">Résultats</h2>
        {isFetching && <GlobalLoadingBar />}
        {isPending ? (
          <State type="loading" variant="results" />
        ) : isError ? (
          <State type="error" error={error} variant="results" />
        ) : data.length === 0 ? (
          <State type="empty" variant="results" />
        ) : (
          <ItemList items={data} />
        )}
      </section>
    </>
  );
}
```

**No wrapping `<div>` and no `<main>`** — the page returns a fragment, because
its container is the layout's `<main>`. A page that opens with a `<div
className="p-6">` is re-implementing the shell's padding in a second place.

**One `<h1>`, and it is the page's subject** — not the product name. The app
name belongs in the `<title>` and, if it must be visible, in the header as plain
text or a link, never as a heading: an `<h1>` reading "MonApp" on every screen
makes the heading outline useless on all of them.

**`<section>` earns its tag by having a heading.** `aria-labelledby` pointing at
that heading is what turns it into a named region; without a heading and without
`aria-label` it is exposed as a generic container — a `<div>` that claimed
otherwise (`templates/component.md`). If a wrapper has no name to give, write
`<div>` and move on.

## Choosing the tag for the body

The three decisions that actually come up, in the order they come up:

| What you are rendering | Tag |
| --- | --- |
| A list of things of the same kind | `<ul>` + `<li>`, one `<li>` per thing — even when the styling removes the bullets |
| Rows with columns that mean something across rows | `<table>` + `<thead>`/`<tbody>`/`<th scope="col">`/`<td>` |
| A self-contained unit that would still make sense lifted out — a card, a post, a detail | `<article>` |
| A supporting block beside the main content — filters, related items | `<aside>` |
| A published or scheduled instant | `<time dateTime="2026-08-18">18 août 2026</time>` |
| A wrapper that only exists to hold a class | `<div>`, and that is fine |

**A grid of cards is a list.** CSS grid on a `<ul>` works exactly as well as on
a `<div>`, and it is the difference between "liste, 12 éléments" and silence.

**A table is a table.** A `<div>` grid with `role="row"` is a re-implementation
of an element that already ships header association, column scope and keyboard
navigation. Reach for the divs only when the layout genuinely cannot be a table
— and then it probably was not tabular data.

## Heading hierarchy

The rule is "no level skipping", and it is broken by **assembly**, not by
authorship: a `<h3>` inside a section component is correct in that file and
wrong the day it is placed directly under the `<h1>`.

The way out is to not hardcode the level in a reusable block. Either the section
component takes it as a prop:

```tsx
interface PanelProps {
  title: string;
  headingLevel?: 2 | 3 | 4;
}

export function Panel({ title, headingLevel = 2, children }: PanelProps): React.ReactElement {
  const Heading = `h${headingLevel}` as const;
  return (
    <section>
      <Heading>{title}</Heading>
      {children}
    </section>
  );
}
```

…or the level stays in the page, and the component receives the rendered
heading as a slot. Both are fine; what is not fine is a `<h3>` frozen inside a
component that two pages place at two depths.

`/loop:review`'s `ui` dimension owns this check, because it is the one reader that
sees the page assembled.

## Testing

Landmarks and headings are tested the way a user reaches them — by role:

```tsx
it("exposes one main landmark and one page heading", () => {
  render(<ItemsPage />, { wrapper: withProviders });

  expect(screen.getByRole("heading", { level: 1, name: /éléments/i })).toBeInTheDocument();
  expect(screen.getByRole("region", { name: /résultats/i })).toBeInTheDocument();
});
```

`getByRole` is singular on purpose: it **throws when there are two**, which is
exactly the assertion "one `<main>` per page" and "one `<h1>` per page" need.
Page tests are optional in this repo (`.claude/rules/05-testing.md`) — this one
pays for itself the first time a page adds a second `<main>` nobody noticed.
