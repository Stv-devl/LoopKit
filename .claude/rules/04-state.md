<!-- budget: 90 lines · /kit:doctor rules-budget -->
# State Management

**This file is the only copy of the state-placement rule.** The `reviewer`'s
`correctness` dimension checks it; `patterns/react-query.md`,
`patterns/url-state.md`, `patterns/zustand.md`, `patterns/local-state.md` and
`patterns/context.md` implement it — one per mechanism, and none of them
restates the choice.

## When to Use What

| Type | Solution | Location |
|------|----------|----------|
| Server state (API/DB) | TanStack Query | `features/*/hooks/hooks.ts` |
| Filter, sort, pagination, active tab — anything a user would expect to survive a refresh or to share by link | **Search params** | the route's `validateSearch` (`patterns/url-state.md`) |
| Client state shared across components (a selection, an open/closed flag), and persisted client preferences (theme, density, sidebar) | Zustand | `features/*/stores/store.ts`, or `src/stores/` when no single feature owns it |
| Local UI state | React `useState` | Component (`patterns/local-state.md`) |
| Session, locale, injected config | React Context | `src/providers/` |
| Real-time | Client subscription | `features/*/services/*.gateway.ts` (or `services.ts`) |

**Five mechanisms, six rows.** The last one is not a sixth place to put state — a
realtime subscription is a *transport*, and the state it produces still lands in
one of the five above (in practice the React Query cache). It is listed here
because the question is asked at the same moment, and answering it elsewhere is
how it ends up in a hook. The subscription is raw I/O, so it lives in the
gateway; the repository maps the payload, the hook only wires it to the cache.

**Context and Zustand split on origin, not on scope.** Context carries what comes
from **outside the client** — a session read through a repository, a locale,
config injected at the composition root. Zustand carries what the **client**
owns: preferences the user sets and the client persists (theme, density, sidebar
folded), and UI state shared across components that no single parent sits above
(a selection, an open/closed flag). Neither of those comes from the server, which
is the whole distinction — "shared widely" is not a reason to reach for Context.

**A value nothing renders is not state.** A timeout id, a "has already run" flag,
the previous value of a prop: `useRef`. Storing it in a row above would trigger a
render for something nobody displays (`patterns/local-state.md`).

## The four ways this goes wrong

None of these fails a test or trips a hook — they are what the `correctness`
reviewer looks for. **The carrier does not change the verdict**: server data
copied into a store, into a Context or into a `useState` is one defect wearing
three costumes, and it is the most common one.

| Anti-pattern | Why it hurts |
| --- | --- |
| **Server data mirrored out of React Query** — a `setItems(data)` in a `useEffect`, whether the target is a store, a `useState` or a Context | Two caches for one truth. React Query invalidates, refetches and dedupes its copy; the copy goes stale and nothing says so. Reported as "it updates everywhere except here" |
| **Derived state stored instead of computed** — a `filteredItems` in a store, a `total` in `useState` | Re-synchronised on every input change, and the day one path forgets, the two disagree. Derive during render; the compiler handles the cost |
| **Server data *fetched* in a provider** — loaded by the provider itself | No cache, no invalidation, no dedupe, no `isFetching`, and every consumer re-rendering because a context has no selector. Legitimate for the **session** (`patterns/context.md`) and for nothing a hook could hold |
| **One Context for everything** — session + locale + UI flags in one `AppContext` | A context re-renders **all** its consumers whenever any part of the value changes. One context per concern; if you want selectors, you wanted Zustand |

A store field that is a **selection or an open/closed flag** is UI state and
belongs in Zustand even when it names server data — an id is not the row. A
**filter** is the one to think about twice: UI state, but also what a user shares
by link and expects to survive a refresh, so its default is the URL. Keep it in
the store only when it is genuinely ephemeral — a search box inside an open
modal, discarded on close.


## Key Files

- `src/lib/queryClient.ts` — React Query client: the `staleTime` floor **and the
  `retry` predicate that stops a `not_found` being retried three times**.
  Scaffolded once from `templates/lib-core.md`, like `result.ts` and `errors.ts`
- `src/providers/AppProviders.tsx` — Context providers (wiring: may import
  features), composed in `patterns/context.md`

The data client is declared by `01-stack.md` ("The data client", row 1);
`Result` / `unwrap` / `ServiceError` by `02-architecture.md`, scaffolded from
`templates/lib-core.md`.

## Patterns (read IF creating)

One per mechanism, in the order of the table. Each implements the placement
decided here and none of them restates it.

- React Query hook → `.claude/skills/patterns/react-query.md`
- URL / search params → `.claude/skills/patterns/url-state.md`
- Zustand store → `.claude/skills/patterns/zustand.md`
- Local component state → `.claude/skills/patterns/local-state.md`
- Context provider → `.claude/skills/patterns/context.md`

Rationale: `.claude/guides/04-state.md`.
