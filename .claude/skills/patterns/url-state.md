# URL State Patterns — search params as state

The second mechanism of `.claude/rules/04-state.md`, and the one most often
missed: a filter, a sort, a page number or an active tab is **state the user
expects to own**. In the URL it survives a refresh, travels in a shared link,
and the back button undoes it for free. In a store it does none of that, and
nothing tells you it was the wrong choice.

> **Routing = TanStack Router** (`.claude/rules/01-stack.md`). Search params here
> are **typed and validated** — `validateSearch` is what makes `Route.useSearch()`
> return something other than `unknown`, and `pnpm typecheck` is a `/loop:ship` gate.
> An untyped `useSearchParams()` string bag is the other ecosystem's answer.

## When the URL, and when not

| The value | Where |
| --- | --- |
| Filter, search text, sort, page, active tab, opened detail id | **URL** |
| A modal's open/closed flag, a hover state, an unsaved draft | Zustand / `useState` — `patterns/zustand.md`, `patterns/local-state.md` |
| Anything secret, or long (a token, a blob, a full form) | Never the URL — it lands in history, in logs and in the referrer |
| The rows the filter selects | React Query — the URL holds the **question**, the cache holds the answer |

The test: **would a user be annoyed to lose it on refresh, or want to send it to
a colleague?** Yes → URL. A filter passes that test; a hover state does not.

## Declaring the schema

The schema lives on the route and is the single declaration of the shape. Zod
gives the parsing, the defaults and the rejection of garbage in one place.

```tsx
// src/routes/app/items.tsx
import { createFileRoute } from '@tanstack/react-router';
import { z } from 'zod';

// `.catch()` on each field, not `.optional()`: a hand-edited URL is untrusted
// input like any other, and a bad `page=abc` should fall back to page 1 rather
// than throw the user onto an error boundary.
const itemsSearchSchema = z.object({
  // NOT `z.coerce.string()`: coercion runs String(input) first, so an ABSENT
  // `q` becomes the literal "undefined" — a valid string, so `.catch('')` never
  // fires and the list filters on garbage. Widen the input instead: Router
  // parses each value with JSON.parse, so `?q=2024` from a shared or hand-typed
  // link arrives as the NUMBER 2024, which plain `z.string()` would reject and
  // `.catch('')` would then swallow into the unfiltered list.
  q: z.union([z.string(), z.number().transform(String)]).catch(''),
  sort: z.enum(['name', 'recent']).catch('name'),
  page: z.number().int().min(1).catch(1),
});

export type ItemsSearch = z.infer<typeof itemsSearchSchema>;

export const Route = createFileRoute('/app/items')({
  validateSearch: itemsSearchSchema,
  component: ItemsPage,
});
```

**Give every field a default and never a `?`.** A schema of optionals pushes an
`undefined` check into every consumer and makes "absent" and "empty" two
different states of the same thing. With defaults, `useSearch()` returns a
complete object and the component reads `search.q` without a guard.

## Reading and writing

```tsx
import { Route } from '@/routes/app/items';

function ItemsToolbar(): React.ReactElement {
  const { q, sort } = Route.useSearch();
  const navigate = Route.useNavigate();

  return (
    <search>
      <label htmlFor="q">Rechercher</label>
      <input
        id="q"
        value={q}
        onChange={(e) =>
          navigate({
            // The updater form receives the current search — it merges instead
            // of replacing, so changing `q` does not silently reset `sort`.
            search: (prev) => ({ ...prev, q: e.target.value, page: 1 }),
            replace: true,
          })
        }
      />
    </search>
  );
}
```

> **Navigating on every keystroke is one request and one history entry per
> character.** `q` is part of the query key, so typing "chaussures" mounts ten
> queries against the list endpoint — and `placeholderData` hides the flicker,
> which is exactly what lets it ship unnoticed until a rate limit or an invoice
> says otherwise. Keep the raw input in `useState`, push it to the URL on a
> debounced effect (~300 ms) with `replace: true`, and the URL still owns the
> state without owning every keystroke. The two are not in tension: what must
> survive a refresh is the *settled* query, not the half-typed one.

Two things in that call are the whole pattern:

- **`search: (prev) => …`**, never a literal object. Passing `{ q }` drops every
  other param, and the bug reads as "changing the search resets my sort".
- **`replace: true` while typing.** Every keystroke is a history entry
  otherwise, and the back button becomes unusable — thirty presses to leave the
  page. Use `replace` for continuous input, and a normal push for a discrete
  action the user would expect to undo (changing page, switching tab).

Resetting `page: 1` when the filter changes is not incidental: page 7 of a
result set that now has two pages is an empty screen with no explanation.

## The pairing with React Query

The URL holds the question, the cache holds the answer, and the **search object
is the query key**.

```tsx
function ItemsPage(): React.ReactElement {
  const search = Route.useSearch();
  const { data, isPending, isError, error, isFetching, isPlaceholderData } =
    useItems(search);

  // `placeholderData` (the hook below) keeps the PREVIOUS filter's rows on
  // screen. Showing them unmarked is a lie the user clicks on, so the two
  // display states that come with it are not optional: `aria-busy` while the
  // new key loads, dimmed while the rows answer the old question.
  //
  // The four states are a ternary chain INSIDE the section, never early
  // returns: an early return escapes the wrapper, and the empty branch is the
  // one that escapes it in practice — `placeholderData` hands back the previous
  // key's `[]`, so a search following a zero-result search renders "Aucun
  // résultat" for a question nobody has answered yet, unmarked.
  // Same block as `templates/page.md`, which owns the landmark and the heading
  // contract — including the single <h1> below: a page that opens on <h2> skips
  // a level (`03-conventions.md`), and page.md's own shipped test asserts the
  // level-1 heading. `relative` is load-bearing, not styling: GlobalLoadingBar
  // positions against it.
  return (
    <>
      <h1>Éléments</h1>
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

```typescript
// features/items/hooks/hooks.ts
/**
 * The URL-keyed item list. The search object IS the query key, so every filter
 * change is a new cache entry — hence `placeholderData` below.
 * @param search - Validated search params from the route's `validateSearch`.
 */
export function useItems(search: ItemsSearch): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.list(search),
    queryFn: async () => unwrap(await repository.getAll(search)),
    // Inherits the collaborative floor from queryClient.ts — deliberate for a
    // list another user can change (`patterns/react-query.md`, profile table).
    // The previous page stays on screen while the next one loads, instead of
    // the whole list collapsing to a spinner on every keystroke. This is not
    // optional on a URL-keyed list — `patterns/react-query.md`, "When the key
    // changes", and the `isPlaceholderData` row of `08-feedback.md`.
    placeholderData: (previous) => previous,
  });
}
```

Because the search object is part of the key (`patterns/react-query.md`, key
factories), going back re-renders from cache with no network call — the browser
history becomes a free cache of previous result sets. That is the property a
Zustand filter throws away.

## Anti-patterns

| Anti-pattern | Why it hurts |
| --- | --- |
| **The filter in a store *and* in the URL** | Two sources for one question, and they desynchronise on the first back button. Pick the URL; read it with `useSearch()` wherever the store was read. |
| **`useEffect` syncing search params into `useState`** | The classic mirroring defect (`04-state.md`), with an extra render showing the stale value. `useSearch()` already re-renders on change. |
| **`z.object({ q: z.string().optional() })`** (or `z.coerce.string()`, which turns an absent value into `"undefined"`) | Makes "absent" and "empty" distinct for no reason, and pushes a guard into every consumer. Use the union + `.catch()` shown in the schema above — and note it widens **numbers** only: `?q=true` or `?q=null` still arrive as `boolean`/`null` through `JSON.parse` and fall back to `''`. Widen the union the day a field can legitimately receive one. |
| **A whole entity in the URL** | The URL carries the **id**; the entity comes from the cache. A serialised object in a query string breaks on the first apostrophe and shows up in logs. |
| **`navigate({ search: { q } })`** | Drops every other param. Always the updater form. |

## Testing

The schema is pure logic and worth testing directly — it is the part that faces
hand-edited URLs:

```typescript
import { describe, it, expect } from 'vitest';
import { itemsSearchSchema } from './items';

describe('itemsSearchSchema', () => {
  it('falls back to page 1 when the page is not a number', () => {
    expect(itemsSearchSchema.parse({ page: 'abc' }).page).toBe(1);
  });

  it('fills every field when the URL carries none', () => {
    expect(itemsSearchSchema.parse({})).toEqual({ q: '', sort: 'name', page: 1 });
  });
});
```

The component side belongs to E2E, where a real URL exists
(`.claude/skills/e2e-playwright/SKILL.md`): navigate with a query string, assert
the list reflects it, go back, assert it reverts. That round trip is precisely
what unit tests cannot reach and what the mechanism exists for.
