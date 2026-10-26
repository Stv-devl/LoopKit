---
topic: tanstack-query-v5
checked: 2026-08-19
stability: pinned
sources:
  - https://tanstack.com/query/latest/docs/framework/react/reference/useMutation
  - https://tanstack.com/query/latest/docs/framework/react/reference/useQuery
  - https://tanstack.com/query/latest/docs/reference/QueryClient
  - https://tanstack.com/query/latest/docs/framework/react/guides/filters
  - https://tanstack.com/query/latest/docs/framework/react/guides/placeholder-query-data
  - https://tanstack.com/query/latest/docs/framework/react/guides/paginated-queries
  - https://raw.githubusercontent.com/TanStack/query/main/packages/query-core/src/retryer.ts
  - https://raw.githubusercontent.com/TanStack/query/main/packages/query-core/src/mutation.ts
  - https://raw.githubusercontent.com/TanStack/query/main/packages/react-query/src/queryOptions.ts
  - https://tanstack.com/query/latest/docs/framework/react/reference/useIsMutating
  - https://raw.githubusercontent.com/TanStack/query/main/packages/query-core/src/mutationCache.ts
  - https://tanstack.com/query/latest/docs/framework/react/guides/disabling-queries
  - https://tanstack.com/query/latest/docs/framework/react/typescript
  - https://tanstack.com/query/latest/docs/framework/react/guides/important-defaults
  - https://raw.githubusercontent.com/TanStack/query/main/packages/query-core/src/utils.ts
  - https://tanstack.com/query/latest/docs/framework/react/guides/mutations
  - https://raw.githubusercontent.com/TanStack/query/main/packages/query-core/src/queryObserver.ts
  - https://tanstack.com/query/v5/docs/framework/react/reference/useQuery
  - https://raw.githubusercontent.com/TanStack/query/main/packages/react-query/src/useMutationState.ts
  - https://raw.githubusercontent.com/TanStack/query/main/packages/query-core/src/removable.ts
---

Scope: version-specific traps behind `patterns/react-query.md`,
`templates/lib-core.md` (`src/lib/queryClient.ts`), `templates/feature.md`
(hooks) and `templates/fixtures.md` (`createTestQueryClient`). Checked 2026-08-19
against the docs and `query-core` source linked above.

## Mutations

- **Promise returned by `onSuccess`/`onSettled` in `useMutation`'s options is
  awaited before `#dispatch({ type: 'success' })`** (`mutation.ts`,
  `Mutation.execute()`): `isPending` stays true until it resolves, so returning
  `invalidateQueries()` keeps the button disabled; the `void` form settles at
  once. Callbacks passed to `mutate(vars, { onSuccess })` are observer-side, run
  after the dispatch, and are not awaited. The docs never name `isPending`; only
  the source settles it.
- **Mutation `retry` defaults to `0`** (same as `false`). `mutations: { retry:
  false }` in `defaultOptions` (queryClient and `createTestQueryClient`) restates
  the default; mutations never retry unless opted in.
- **`useIsMutating(filters)`** (`useMutationState.ts`) forces `status: 'pending'`
  over any caller-supplied `status` and returns a count. `matchMutation`
  matches `mutationKey` by prefix (`partialMatchKey`) unless `exact`; the
  reference page does not say so. Precondition: it counts nothing unless the
  observed `useMutation` declares the same `mutationKey`. The only other use of
  `mutationKey` is `setMutationDefaults`.

## Queries

- **`retry: (failureCount, error) => ...`**: `failureCount` is `0` at the first
  call; the increment happens after the predicate (`retryer.ts`). `< 1` = one
  retry (two requests), `< 2` = two retries (three requests). Built-in `retry: 3`
  = three retries.
- **Disabled, never-fetched query** (`enabled: false`): `status: 'pending'`,
  `fetchStatus: 'idle'`, `isPending: true` forever. Branch a loading UI on
  `isLoading` (`isPending && isFetching`), and treat `fetchStatus === 'idle'`
  as its own "waiting on X" branch.
- **`placeholderData: (previous) => previous`** and the exported
  `keepPreviousData` are documented as the same thing: `status: 'success'`,
  `isPlaceholderData: true`, `isPending: false`. Only on a key change; on first
  mount the placeholder is `undefined` and the query is genuinely pending.
  (`keepPreviousData` implementation not read.)
- **`setQueryData`/`setQueriesData` updater returning `undefined`** bails out: no
  update, no new cache entry. `setQueriesData` only updates matched entries.
  Filter matching is inclusive by default (`exact: false`), so
  `{ queryKey: itemKeys.lists() }` matches `['items','list', ...]` by prefix.
  Only the Filters guide settles this.
- **`queryOptions` return type** is `<Options> & QueryKeyWithDataTag<...>`. A
  hand-written return annotation drops the `DataTag` brand and
  `getQueryData(...queryKey)` returns `unknown` again. Stated nowhere in the
  docs; only the signature shows it.
- **`gcTime: Infinity`** is source-special-cased (`removable.ts`: `scheduleGc`
  arms no timer when `isValidTimeout` fails) and is the only spelling of "never
  collect". Server-side `gcTime` already defaults to `Infinity`.
- **`refetchOnReconnect`** defaults to `true`: refetches only mounted observers
  whose data is stale, on the browser's `onlineManager` transition
  (`queryObserver.ts`, `shouldFetchOnReconnect`). It never fires for a realtime
  channel reconnecting with no network drop, and skips fresh queries unless
  `"always"`. The `onReconnect` -> `invalidateQueries` plumbing (RQ-07) stays
  necessary.
- **Default `error` type is `Error`.** Project-wide override:
  `declare module '@tanstack/react-query' { interface Register { defaultError:
  ServiceError } }`, declared once (`src/lib/queryClient.ts` or a `*.d.ts`).

## Not verified

- Devtools grouping by `mutationKey`.
- `keepPreviousData` as literally the identity function in `utils.ts`.

## Also settled (kept from the long form)

- `mutationCache.find()` defaults `exact: true`; `findAll()` (behind
  `useMutationState` / `useIsMutating`) does not force `exact`.
- `invalidateQueries` on a prefix also covers queries still inside their
  `staleTime` window, and marks inactive ones stale for their next mount.
- The `Register` docs' own example sets `defaultError: unknown`.
- `important-defaults` does not state the default or mechanics of
  `refetchOnReconnect` (checked, not found there).
