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

Scope: verification of the kit's own claims in `patterns/react-query.md`,
`templates/lib-core.md` (`src/lib/queryClient.ts`), `templates/feature.md`
(hooks) and `templates/fixtures.md` (`createTestQueryClient`).

## 1. Does a promise returned by `onSuccess` / `onSettled` of `useMutation` delay the settle, keeping `isPending` true? (feature.md, "The two shapes above are not interchangeable")

**VRAI.** Reference: "If a promise is returned, it will be awaited and resolved
before proceeding" — on both `onSuccess` and `onSettled`
(`docs/framework/react/reference/useMutation`). The docs never name `isPending`,
so the consequence was settled in the source: in `Mutation.execute()`
(query-core `mutation.ts`), the cache `onSuccess`, the options `onSuccess`, the
cache `onSettled` and the options `onSettled` are all **awaited before**
`#dispatch({ type: 'success', data })`, and observers are notified only inside
that dispatch. So the mutation stays `status: 'pending'` — hence `isPending`
true, hence the button stays disabled — for as long as the returned
`invalidateQueries()` promise is unresolved. The `void` form settles at once.

**Caveat the kit does not state:** this holds for callbacks declared in the
`useMutation` **options**. Callbacks passed per call to `mutate(vars, {
onSuccess })` are observer-side and run after the dispatch, so returning a
promise from those does not hold the pending state.

## 2. Does `retry: (failureCount, error) => failureCount < 2 && …` produce one retry? What is `failureCount` at the first call?

**FAUX.** `failureCount` is **0** at the first call of the predicate. Source,
`query-core/src/retryer.ts`, catch block, verbatim order:

```
const shouldRetry =
  retry === true ||
  (typeof retry === 'number' && failureCount < retry) ||
  (typeof retry === 'function' && retry(failureCount, error))

if (isRetryCancelled || !shouldRetry) { reject(error); return }

failureCount++
```

`let failureCount = 0` is initialised outside, and the increment happens
**after** the predicate. So `failureCount < 2` returns true for failures 1 and 2
(counts 0 and 1) and false for failure 3 (count 2): **two retries, three
attempts total**, not one retry / two attempts. It is consistent with the
built-in `retry: 3` meaning three retries (four attempts).

To actually get one retry, the predicate must read `failureCount < 1`.

## 3. Is `placeholderData: (previous) => previous` equivalent to `keepPreviousData`, and does it give `isPending: false` + `isPlaceholderData: true` on a key change?

**VRAI.** Placeholder guide: "When we use `placeholderData`, our Query will not
be in a `pending` state - it will start out as being in `success` state, because
we have `data` to display" and "we will also have the `isPlaceholderData` flag
set to `true` on the Query result". The function form is documented as
`placeholderData: (previousData, previousQuery) => previousData`. The paginated
guide presents `(previousData) => previousData` and the exported
`keepPreviousData` as the two spellings of the same thing.

Not verified (no source read): that `keepPreviousData` is *literally* the
identity function in `query-core/utils.ts`. Behaviourally the docs treat them as
interchangeable.

Nuance for the kit's table: this only applies **on a key change**. On the very
first mount there is no previous data, the placeholder resolves to `undefined`,
and the query is genuinely `pending` — the kit's table is headed "On a key
change", so it is correct as written.

## 4. `setQueriesData(filters, updater)`: does an updater returning `undefined` leave the entry intact, and is the match by prefix?

**VRAI on both counts.**

- QueryClient reference, `setQueryData`: "If the updater function returns
  `undefined`, the query data will not be updated. If the updater function
  receives `undefined` as input, you can return `undefined` to bail out of the
  update and thus _not_ create a new cache entry." `setQueriesData` applies the
  same updater to every matched entry: "Only queries that match the passed
  queryKey or queryFilter will be updated - no new cache entries will be
  created."
- Filters guide: matching is inclusive by default — "If you don't want to search
  queries inclusively by query key, you can pass the `exact: true` option to
  return only the query with the exact query key you have passed." So `exact`
  defaults to `false` and `{ queryKey: itemKeys.lists() }` matches
  `['items','list', …]` by prefix, which is what the realtime pattern relies on.

## 5. Does a hand-written return-type annotation destroy `queryOptions`' key branding?

**VRAI**, and the mechanism is in the signature itself. Every overload of
`queryOptions` (react-query `queryOptions.ts`) returns
`<TheOptionsType> & QueryKeyWithDataTag<TQueryKey, TQueryFnData, TError>`. The
brand is an intersection member of the **return type**, so any annotation
written by hand that does not repeat that intersection replaces the inferred
type and the `DataTag` is gone — after which
`getQueryData(itemDetailQuery(id).queryKey)` comes back `unknown` again. The
docs do not state this in those words; the signature does.

## 6. Does `mutations: { retry: false }` in `defaultOptions` change anything vs the v5 default?

**Non — c'est un no-op.** useMutation reference, `retry`: "Defaults to `0`. If
`false`, failed mutations will not retry." `0` and `false` produce the same
behaviour, so the line in `src/lib/queryClient.ts` and the same line in
`createTestQueryClient` restate the default. Legal and harmless, but the comment
above it ("A retried POST or PATCH is a duplicate nobody asked for") describes a
protection React Query already gives for free — mutations never retry unless you
opt in.

## 7. `useIsMutating` + `mutationKey` — does the kit's `useIsMutating({ mutationKey: someKeys.remove() }) > 0` snippet hold? (NEW, shipped 2026-08-18)

**Mostly VRAI, with one precondition the kit's snippet does not state.**

- **(a) Accepts a `mutationKey` filter — yes.** `useIsMutating(filters?:
  MutationFilters, queryClient?)`, docs example:
  `useIsMutating({ mutationKey: ['posts'] })`
  (`reference/useIsMutating`).
- **(b) Matches by prefix, not exact — confirmed in source.**
  `query-core/src/utils.ts`, `matchMutation()`:
  ```ts
  if (mutationKey) {
    if (!mutation.options.mutationKey) return false
    if (exact) {
      if (hashKey(mutation.options.mutationKey) !== hashKey(mutationKey)) return false
    } else if (!partialMatchKey(mutation.options.mutationKey, mutationKey)) {
      return false
    }
  }
  ```
  `mutationCache.find()` defaults `exact: true`; `findAll()` (the one behind
  `useMutationState`/`useIsMutating`) does **not** force `exact`, so an unset
  `exact` in the filters passed to `useIsMutating` falls through to
  `partialMatchKey` — the same prefix semantics as query-key filters. So
  `mutationKey: someKeys.remove()` matches any in-flight mutation whose own
  `mutationKey` **starts with** that array, exactly like a query filter.
- **(c) What it returns — a count, and it is pre-filtered to in-flight
  mutations.** `react-query/src/useMutationState.ts`:
  ```ts
  export function useIsMutating(filters?, queryClient?): number {
    const client = useQueryClient(queryClient)
    return useMutationState({ filters: { ...filters, status: 'pending' } }, client).length
  }
  ```
  `useIsMutating` **always** injects `status: 'pending'` into the filter,
  overriding anything the caller passed for `status`. So the number is exactly
  "how many mutations matching this key-prefix are currently pending" — not a
  count of everything the cache still holds (settled mutations are also subject
  to their own `gcTime` and are not counted regardless, since `status` is forced
  to `'pending'`).
- **(d) `mutationKey`'s only other documented purpose.** The mutations guide
  shows it used to attach preset options via
  `queryClient.setMutationDefaults(mutationKey, options)`, read back by a later
  `useMutation({ mutationKey })` call — i.e. the second and only other reason to
  add one. `mutationKey` is otherwise optional; a mutation runs fine without it.

**The precondition the kit's snippet leaves implicit:** `mutationKey` is opt-in
per `useMutation` call — `useIsMutating({ mutationKey: someKeys.remove() })`
counts nothing unless the mutation(s) it is meant to observe were themselves
declared with `useMutation({ mutationKey: someKeys.remove(), ... })`. If the
kit's pattern shows the `useIsMutating` call site without also showing that same
`mutationKey` on the corresponding `useMutation`, the snippet is incomplete
rather than wrong.

## 8. `gcTime: Infinity` — is it legal, and is it the documented way to say "never collect"?

**VRAI, and it is source-special-cased, not just tolerated.**

- Docs (`reference/useQuery`, already in this file's sources): "If set to
  `Infinity`, will disable garbage collection" — no warning documented.
- Source, `query-core/src/removable.ts`, `scheduleGc()`: the timer is only
  armed `if (isValidTimeout(this.gcTime))`, and `isValidTimeout` is the guard
  that excludes `Infinity` — so the library never calls
  `setTimeout(fn, Infinity)`; it skips scheduling entirely. There is no broken
  timer, no NaN delay, no warning.
- Incidental finding worth keeping: `updateGcTime()`'s fallback is
  `newGcTime ?? (isServer() ? Infinity : 5 * 60 * 1000)` — **on the server, the
  default `gcTime` is already `Infinity`**, independent of anything a test
  fixture sets.

`gcTime: Infinity` in `createTestQueryClient` is exactly the documented,
source-supported way to say "never garbage-collect this client's cache" — no
alternative spelling exists (there is no separate `disableGc` flag).

## 9. The `status` / `fetchStatus` / `isPending` of a query with `enabled: false` that has never fetched

**Settled from `guides/disabling-queries`:**

| Flag | Value |
| --- | --- |
| `status` | `'pending'` |
| `fetchStatus` | `'idle'` |
| `isPending` | `true` |

A disabled, never-fetched query is `pending` **forever** — nothing about
`enabled: false` changes `status`, and the kit's rule ("always handle
`isPending`") is correct but insufficient on its own: rendering a full loading
state on `isPending` alone shows a permanent spinner for any query that is
intentionally disabled (a dependent query waiting on its parent's id, for
instance).

**What a UI should branch on instead:** `isLoading`, the docs' own named
composite — "It's a derived flag that is computed from: `isPending &&
isFetching`, so it will only be true if the query is currently fetching for the
first time." For a disabled query, `isFetching` is `false` (nothing is in
flight), so `isLoading` is `false` even while `isPending` stays `true`. A
dependent-query example should gate its full-page loading state on `isLoading`,
not on `isPending` alone, and treat the `enabled: false` / `fetchStatus ===
'idle'` state as its own explicit branch ("waiting on X") rather than folding it
into either the loading or the error state.

## 10. `DefaultError` vs a custom error type — the `Register` interface

**Settled from `docs/framework/react/typescript`:**

- The default type of `error` in `useQuery`/`useMutation` results is `Error`
  ("The type for error defaults to `Error`, because that is what most users
  expect").
- To set a project-wide error type without repeating a generic at every call
  site, the documented mechanism is module augmentation of the `Register`
  interface:
  ```ts
  import '@tanstack/react-query'

  declare module '@tanstack/react-query' {
    interface Register {
      defaultError: ServiceError // this repo's own error type, in place of `unknown`
    }
  }
  ```
  Declared once (e.g. in `src/lib/queryClient.ts` or a `*.d.ts` next to it), this
  changes the inferred `error` type across every `useQuery`/`useMutation` in the
  codebase with no per-hook generic. The docs' own example sets `defaultError:
  unknown` to force explicit narrowing at every call site; setting it to this
  repo's `ServiceError` is the direct v5-supported way to make `error` be that
  class repo-wide.

## 11. `refetchOnReconnect` — v5 default, exact behaviour, and whether it makes the kit's manual `onReconnect → invalidateQueries` redundant

**Default: `true`.** `tanstack.com/query/v5/docs/framework/react/reference/useQuery`,
`refetchOnReconnect`: "If set to `true`, the query will refetch on reconnect if
the data is stale. If set to `false`, the query will not refetch on reconnect.
If set to `\"always\"`, the query will always refetch on reconnect… If set to a
function, the function will be executed with the query to compute the value."

**What it actually does, per source** (`query-core/src/queryObserver.ts`,
`shouldFetchOnReconnect()` → `shouldFetchOn(query, options,
options.refetchOnReconnect)`): it is evaluated **per mounted observer**, on the
`onlineManager`'s online transition, and — at the `true` default — only
triggers a refetch if that query's data is currently **stale**. It does nothing
for queries with no active observer (nothing mounted to ask the question), and
nothing for a mounted-but-fresh (`staleTime` not elapsed) query unless the
option is `"always"`.

**Does this make the kit's `onReconnect → invalidateQueries(...)` plumbing
(RQ-07) redundant? Not in general, only in one narrow overlap.**

- `refetchOnReconnect` fires on the **browser's** online/offline transition
  (`onlineManager`, backed by `navigator.onLine` / the `online`/`offline`
  events). The kit's `onReconnect` plumbing fires on the **realtime channel's**
  own reconnect signal (e.g. Supabase's `SUBSCRIBED` after `CHANNEL_ERROR` /
  `TIMED_OUT`), which can happen with **no browser network drop at all** — a
  server-side channel error, an auth token refresh, a backend restart. In that
  case `refetchOnReconnect` never fires, because the browser was never
  "offline"; the manual `invalidateQueries` is the only mechanism that
  resynchronises the gap.
- Even in the case where a real network outage causes both signals together,
  `refetchOnReconnect` at its default only refetches **mounted, stale**
  queries. `invalidateQueries(all)` additionally covers queries still inside
  their `staleTime` window (events during the gap should not wait for staleness
  to elapse) and marks entries stale for the **next** mount of a currently
  inactive query.
- Conclusion: **not at all redundant as a replacement**; at most **partially
  overlapping**, and only for the subset of drops that are also real network
  outages, on the subset of queries that are both mounted and already stale.
  The manual plumbing stays necessary for the general (channel-level) case
  RQ-07 was written for.

## Not found

- The docs never mention `isPending` in the description of `onSuccess` /
  `onSettled`; the pending-until-awaited behaviour is only readable in
  `query-core/src/mutation.ts`.
- The QueryClient reference page does not restate prefix-vs-exact matching for
  `setQueriesData`; the Filters guide is the only page that settles it, and its
  method examples list `cancelQueries`, `removeQueries`, `refetchQueries` —
  not `setQueriesData`.
- No documentation page states that a hand-written return type erases the
  `DataTag` brand. Only the exported signature shows it.
- `keepPreviousData`'s implementation was not read; only its documented
  equivalence with `(previousData) => previousData`.
- `reference/useIsMutating`'s prose does not itself state prefix-vs-exact
  matching ("mutations matching the posts prefix" is the only hint); the source
  (`matchMutation`, `findAll`) is what actually settles it.
- No documentation page states that `useIsMutating` forces `status: 'pending'`
  internally; only `useMutationState.ts` shows it.
- `important-defaults` does not itself state the default or precise mechanics
  of `refetchOnReconnect`; the versioned `reference/useQuery` page and
  `queryObserver.ts` are what settle it.
- Devtools grouping by `mutationKey` was not checked and is not claimed above.
