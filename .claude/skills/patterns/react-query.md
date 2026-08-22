# React Query Patterns

## Unwrap Result\<T\>

Repositories return `Result<T>`. Hooks **unwrap** so React Query handles
the errors. `unwrap` lives in `src/lib/result.ts` — scaffolded once from
`.claude/skills/templates/lib-core.md`. **Import it, never redefine it.**

```typescript
import { unwrap } from "@/lib/result";
import type { UseQueryResult } from "@tanstack/react-query";

// Usage in queryFn / mutationFn
export function useItems(): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.lists(),
    queryFn: async () => unwrap(await repository.getAll()),
  });
}
```

## Query keys — one factory per feature

**Never type a key literal twice.** A key retyped one character differently is an
invalidation that silently does nothing, and the bug reads as "it updates
everywhere except here" — the exact failure `.claude/rules/04-state.md` names.
Declare them once, next to the hooks that use them:

```typescript
// features/items/hooks/hooks.ts
export const itemKeys = {
  all: ['items'] as const,
  lists: () => [...itemKeys.all, 'list'] as const,
  list: (search: ItemsSearch) => [...itemKeys.lists(), search] as const,
  details: () => [...itemKeys.all, 'detail'] as const,
  detail: (id: string) => [...itemKeys.details(), id] as const,
};
```

**A mutation gets a key only when something outside the component must read its
status.** The factory is the same one — add a member for it — and the reader uses
`useIsMutating({ mutationKey: itemKeys.remove() }) > 0` instead of copying
`isPending` into a store (`patterns/zustand.md`, "Async actions"). Without that
need, a mutation needs no key at all.

The nesting is what makes invalidation expressive, because React Query matches
by **prefix**:

| Call | Invalidates |
| --- | --- |
| `invalidateQueries({ queryKey: itemKeys.all })` | every item query |
| `invalidateQueries({ queryKey: itemKeys.lists() })` | every list, whatever the filter — leaves the details alone |
| `invalidateQueries({ queryKey: itemKeys.detail(id) })` | that one row |

`as const` is not decoration: it makes the tuples readonly and the key types
literal, so a typo is a type error rather than a query that quietly never
matches.

## Config by data type

Pick a `staleTime` from what the data **is**, not by habit. These are the four
profiles this repo uses. Every example below either names the one it applies
or deliberately inherits the floor from `src/lib/queryClient.ts` — silence is
never the third option, because "by habit" is exactly what this section forbids.

| Data | `staleTime` | `gcTime` | Also |
| --- | --- | --- | --- |
| Static (config, enums) | `Infinity` | `Infinity` | `refetchOnWindowFocus: false` |
| User-owned (profile, preferences) | 5 min | 1 h | |
| Collaborative (anything another user can change) | 30 s | 5 min | |
| Realtime-backed | `Infinity` | 5 min | the subscription invalidates; polling on top is waste |

`staleTime: 0` — React Query's own default — means every mount refetches. That
is rarely what you want and never what you want on a list a user navigates in and
out of, which is why this repo does not run on it: `src/lib/queryClient.ts`
(`templates/lib-core.md`) sets the floor — the **collaborative** row of the
table above, declared there and deliberately not re-typed here — **and the retry
predicate**. Both matter here:

- without the floor, the table above is advisory and any hook that forgets a
  line silently falls back to refetch-on-every-mount;
- without the predicate, `unwrap` throwing `not_found` is retried three times
  with backoff before `isError` ever renders. A decision the server already made
  is not an incident to retry.

A hook overrides the floor from the table; it never re-states it. **Both
numbers of the profile, not only `staleTime`**: three of the four rows carry a
`gcTime` the floor does not, so a hook that copies the `staleTime` line alone has
applied half a profile and kept the floor's retention without saying so.

## When the key changes

`isFetching` is the "keep the data visible" mechanism for a refetch **on the same
key**. It is not the frequent case. As soon as the key carries a filter, a sort or
a page — and `04-state.md` routes all three to the URL — typing one character
mounts a **different** query: `data` is `undefined` again, `isPending` is `true`
again, and the list collapses to a spinner on every keystroke. That is the exact
opposite of the "keep data on refetch" line `CLAUDE.md` calls non-negotiable, and
no amount of `isFetching` handling in the component fixes it.

The fix is one line, and it belongs to the **hook** — a component cannot hold the
previous key's rows:

```typescript
export function useItems(search: ItemsSearch): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.list(search),
    queryFn: async () => unwrap(await repository.getAll(search)),
    // Inherits the collaborative floor from queryClient.ts — deliberate for a
    // list another user can change (profile table above).
    // The previous key's rows stay on screen while the new key loads.
    // `placeholderData: keepPreviousData` (imported from the lib) is the same
    // thing with an import; this form needs none.
    placeholderData: (previous) => previous,
  });
}
```

| On a key change | Without | With `placeholderData` |
| --- | --- | --- |
| `data` | `undefined` | the previous key's rows |
| `isPending` | `true` — full loading state | `false` |
| what marks the load | nothing is left to mark | `isFetching` → discreet indicator |
| what says the rows are stale | nothing | `isPlaceholderData` — dim the list, `aria-busy`, never a spinner |

**`isPlaceholderData` is a display state, not a debug flag**: rows from the
previous filter shown as if they answered the current one is a lie the user acts
on. Dim them, or mark the region `aria-busy` (`patterns/feedback.md`).

A query whose key never changes does not need any of this — there `isFetching`
alone is the whole story (`08-feedback.md`).

## Standard query

```typescript
import * as repository from "../services/item.repository";
import type { UseQueryResult, UseMutationResult } from "@tanstack/react-query";

export function useItems(): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.lists(),
    queryFn: async () => unwrap(await repository.getAll()),
    staleTime: 5 * 60 * 1000, // user-owned profile, table above — both lines
    gcTime: 60 * 60 * 1000,
  });
}

// With parameter
export function useItem(id: string): UseQueryResult<Item> {
  return useQuery({
    queryKey: itemKeys.detail(id),
    queryFn: async () => unwrap(await repository.getById(id)),
    // Inherits the collaborative floor (profile table above).
    // `enabled: false` does NOT resolve to a loading state that ends: the query
    // stays `status: 'pending'` / `fetchStatus: 'idle'` forever, so a caller
    // branching on `isPending` shows a spinner that never goes away. Branch on
    // `isLoading` and give "no id yet" its own branch (`08-feedback.md`).
    enabled: !!id,
  });
}

// With select (avoids re-renders)
export function useItemName(id: string): UseQueryResult<string> {
  return useQuery({
    queryKey: itemKeys.detail(id),
    queryFn: async () => unwrap(await repository.getById(id)),
    // Inherits the collaborative floor (profile table above).
    select: (data) => data.name,
  });
}
```

> **Note**: For small features (single services.ts), replace `repository.*` with `services.*`.

## Simple mutation

```typescript
export function useCreateItem(): UseMutationResult<Item, Error, CreateItemInput> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: CreateItemInput) =>
      unwrap(await repository.create(input)),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: itemKeys.lists() }),
  });
}
```

> **The logout mutation is the one that must also empty the cache** —
> `queryClient.clear()`, or the next account served in the
> same tab reads the previous user's rows out of a cache nothing invalidated.
> The worked example lives in `patterns/zustand.md` ("Async actions"), and
> `agents/security-auditor.md` grades its absence.
>
> Two things that page owns and this one does not restate: `clear()` is only the
> **server** half of a logout — the client half is a `reset()` on every app store
> — and `clear()` does not detach mounted observers, so where it fires relative
> to the redirect decides whether the user sees a skeleton and a 401 on the way out.

## Optimistic mutation

> **The fourth generic is not optional here.** `UseMutationResult<TData, TError,
> TVariables>` leaves `TContext` at `unknown`, and that annotation is what types
> the `useMutation` call below — so `onMutate`'s return value never reaches
> `onError`'s `context`, which arrives as `unknown` and makes `context.previous`
> a compile error. The rollback is exactly what an optimistic mutation is for, so
> the type that carries it is named: `MutationContext` below. Without the
> annotation the inference works on its own; with it — and
> `03-conventions.md` requires explicit return types — the fourth slot has to be
> filled by hand.

```typescript
/** What `onMutate` hands to `onError` — the snapshot to roll back to. */
interface MutationContext {
  previous: Item | undefined;
}

export function useUpdateItem(): UseMutationResult<
  Item,
  Error,
  { id: string } & UpdateItemInput,
  MutationContext
> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: { id: string } & UpdateItemInput) =>
      unwrap(await repository.update(id, input)),
    onMutate: async (updated): Promise<MutationContext> => {
      await queryClient.cancelQueries({ queryKey: itemKeys.detail(updated.id) });
      const previous = queryClient.getQueryData<Item>(itemKeys.detail(updated.id));
      // Merge: `updated` is partial, do not overwrite the full entity — and
      // drop the keys it carries as an explicit `undefined`. A spread does NOT
      // skip those: a form that submits `{ description: undefined }` for a field
      // it never mounted blanks the description for the whole flight of the
      // mutation, then the refetch brings it back. The bug is reported as
      // "it flickers", and TypeScript sees nothing.
      queryClient.setQueryData<Item>(itemKeys.detail(updated.id), (old) =>
        old ? { ...old, ...definedOnly(updated) } : old,
      );
      return { previous };
    },
    onError: (err, updated, context) => {
      if (context?.previous)
        queryClient.setQueryData(itemKeys.detail(updated.id), context.previous);
    },
    // The two surfaces this mutation touched, not `itemKeys.all` — that one
    // also refetches every OTHER detail the user has open (`templates/feature.md`,
    // "`lists()` and `detail(id)`, not `all`").
    // No `void` here, on purpose: the returned promise is awaited, so the
    // mutation stays `isPending` until the refetch lands. On an optimistic
    // update that is the point — the optimistic value must not read as confirmed
    // before the server's answer is in (`templates/feature.md`, "The two shapes
    // above are not interchangeable either").
    onSettled: (_data, _error, updated) =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: itemKeys.detail(updated.id) }),
        queryClient.invalidateQueries({ queryKey: itemKeys.lists() }),
      ]),
  });
}

/**
 * Drops the keys a partial input carries as an explicit `undefined`, so a merge
 * cannot blank a field nobody edited. The cast is unavoidable: `Object.entries`
 * erases the key types and `fromEntries` cannot give them back.
 */
function definedOnly<T extends object>(patch: T): Partial<T> {
  return Object.fromEntries(
    Object.entries(patch).filter(([, value]) => value !== undefined),
  ) as Partial<T>;
}
```

## Real-time subscription

> **Rule (`rules/04-state.md` + `rules/02`)**: the subscription is raw I/O, so it
> lives in the **gateway** (or `services.ts` if the feature is not split) — never
> in the hook. The repository maps the raw payload → domain entity; the hook only
> **wires** the mapped events to the React Query cache. **Never**
> `payload.new as Item`.
>
> Those two filenames are not cosmetic: `enforce-architecture.py` allows the data
> client in `*.gateway.ts` and `services.ts` only. A `items.service.ts` importing
> the client is denied at write time.
>
> The transport below is **Server-Sent Events** — the one every stack has without
> an SDK. Swap it for a WebSocket, a long-poll or a BaaS channel: only this file
> changes, which is the whole claim of the layering. Using Supabase? Its realtime
> channels are in `addons/supabase/skills/patterns/realtime.md` — that API does
> not belong in a vendor-neutral pattern.

```typescript
// features/items/services/items.gateway.ts — raw I/O, no mapping, no Result
import { client } from "@/lib/client";

/**
 * Opens the item change stream. Emits payloads exactly as they arrive —
 * parsing, validating and mapping are all the repository's job.
 *
 * `onReconnect` fires when the stream comes back up after a drop. Reporting the
 * gap is transport knowledge, so it belongs here; deciding what to do about it
 * does not.
 * @returns Unsubscribe function.
 */
export function subscribeToItemPayloads(
  onPayload: (payload: unknown) => void,
  onReconnect: () => void,
): () => void {
  const source = new EventSource(client.streamUrl("/items"));
  let hasConnected = false;

  source.onopen = () => {
    // Fires on the first connect AND on every automatic reconnect. Only the
    // second kind means events were missed.
    if (hasConnected) onReconnect();
    hasConnected = true;
  };
  source.onmessage = (event) => onPayload(JSON.parse(event.data));

  return () => source.close();
}
```

> The gateway interprets **nothing** — not even which kind of change arrived.
> Discriminating is already a decision about the domain, and it belongs behind the
> validation, one layer up.

```typescript
// features/items/services/items.repository.ts — maps, exposes a domain event
import * as gateway from "./items.gateway";
import { toItem } from "./items.mapper";
import { itemChangeSchema } from "../types/schemas";
import type { Item } from "../types/types";

export type ItemChange =
  | { type: "upsert"; item: Item }
  | { type: "delete"; id: string };

/**
 * Subscribes to item changes, already validated and mapped to domain entities.
 * Payloads that don't match the schema are logged and dropped — a realtime
 * payload is untrusted input like any other.
 *
 * `onReconnect` is forwarded untouched: there is nothing to map about a gap.
 * @returns Unsubscribe function.
 */
export function subscribeToItems(
  onChange: (change: ItemChange) => void,
  onReconnect: () => void,
): () => void {
  return gateway.subscribeToItemPayloads((payload) => {
    // Validate before mapping: the mapper takes a typed row, never `unknown`,
    // and never an `as` cast (rules/02-architecture.md).
    const parsed = itemChangeSchema.safeParse(payload);
    if (!parsed.success) {
      console.error("Dropped malformed realtime payload:", parsed.error);
      return;
    }
    if (parsed.data.op === "delete") {
      onChange({ type: "delete", id: parsed.data.id });
      return;
    }
    onChange({ type: "upsert", item: toItem(parsed.data.row) });
  }, onReconnect);
}
```

```typescript
// features/items/hooks/hooks.ts — wiring only, zero direct client access
import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { subscribeToItems } from "../services/items.repository";
import type { Item } from "../types/types";

export function useItemsRealtime(): void {
  const queryClient = useQueryClient();

  useEffect(() => {
    return subscribeToItems((change) => {
      // `setQueriesData`, not `setQueryData`: `itemKeys.lists()` is a
      // **prefix**. The moment a list takes a filter, the real entries are
      // `list(search)` (key factory above, and `patterns/url-state.md`) and
      // `['items', 'list']` is never populated — `setQueryData` would target a
      // key nobody reads, so the change never reaches the `list(search)`
      // entries actually on screen. The filter form is
      // the one that gets added later, which is why the prefix form is the
      // default here even for a list that has none yet.
      queryClient.setQueriesData<Item[]>({ queryKey: itemKeys.lists() }, (old) => {
        // A matched entry can still hold no data (fetch in flight, or cancelled).
        // Writing anyway would stamp it fresh with this single row, so the next
        // mount reads a one-item list from cache and does not refetch for a
        // whole `staleTime`. Returning undefined leaves it untouched; the fetch
        // in flight carries this change anyway.
        if (old === undefined) return undefined;

        // Two blind spots this write has and an invalidation does not, both
        // visible on screen: the row is appended at the END (the ordering is the
        // server's, not ours), and it is written into EVERY list key — filters
        // included — so an upserted item lands in `list({ status: 'archived' })`
        // whether or not it is archived, and an item that just stopped matching
        // a filter stays in it. This is the price named in the note below, and
        // the reason invalidation is the default.
        if (change.type === "delete") return old.filter((i) => i.id !== change.id);
        const exists = old.some((i) => i.id === change.item.id);
        return exists
          ? old.map((i) => (i.id === change.item.id ? change.item : i))
          : [...old, change.item];
      });

      // The same event owns the DETAIL entry too. Without these two lines a
      // rename by another user updates the row in the list and leaves the detail
      // sheet open beside it showing the old name — two truths on one screen,
      // until `staleTime` expires or the window regains focus.
      if (change.type === "delete") {
        queryClient.removeQueries({ queryKey: itemKeys.detail(change.id) });
        return;
      }
      // Same bail-out as above: an updater returning `undefined` leaves the
      // entry untouched, so this never CREATES a detail nobody has opened.
      queryClient.setQueryData<Item>(itemKeys.detail(change.item.id), (old) =>
        old === undefined ? undefined : change.item,
      );
    }, () => {
      // Back up after a drop: whatever happened during the gap was not
      // delivered and will not be replayed. Refetch rather than guess.
      void queryClient.invalidateQueries({ queryKey: itemKeys.all });
    });
  }, [queryClient]);
}
```

> **Mount it once, and say where.** `useItemsRealtime()` opens a connection per
> mount and nothing dedupes it: two components calling it means two
> `EventSource`, two sets of events applied to the same cache, and a symptom —
> duplicated updates — that nobody traces back to the mount count. Call it in the
> **single** component that owns the screen the subscription feeds (the page, or
> the layout above it if several pages share the stream), never in a list item,
> never in a shared component. If two independent screens genuinely need the same
> stream at the same time, the subscription belongs one level up: hoist the call
> into the layout and let both read the cache it feeds.
>
> **A dropped connection loses every event it did not deliver.** The transport
> reconnects on its own (`EventSource` does, a BaaS channel does), and neither
> replays what happened during the gap unless the server implements it — so the
> cache stays confidently wrong. **Invalidate on reconnect**, not only on event:
> the gateway forwards the reconnection as its own callback, and the hook calls
> `invalidateQueries({ queryKey: itemKeys.all })` on it. This is also why the
> `Realtime-backed` row's `staleTime: Infinity` is a real decision: with it, a
> reconnect invalidation is the *only* thing that can repair the cache — nothing
> else ever refetches. Take the row's `Infinity` only once the reconnect path
> exists; the collaborative floor is the safer default until then.
>
> **Writing into the cache is the optimisation, not the default.** For a list,
> `invalidateQueries({ queryKey: itemKeys.lists() })` in the callback is correct,
> costs one refetch and cannot desynchronise — take it unless a refetch per event
> is absurd (a cursor, a presence badge, a high-frequency counter). Same verdict
> in `addons/supabase/skills/patterns/realtime.md`, which invalidates.

## A query with a second caller — `queryOptions`

Prefetching, or loading in a route loader, means naming the same query twice:
once in the hook, once at the other call site. Retyping the pair `queryKey` +
`queryFn` is the same defect as retyping a key literal, one level up — the two
copies drift, and the prefetch quietly fills a cache entry the hook never reads.

The moment a query has a **second** caller, hoist its definition:

```typescript
// features/items/hooks/hooks.ts
import { queryOptions } from "@tanstack/react-query";

/**
 * The one definition of "the item detail query".
 *
 * No explicit return type: this is the one exception `03-conventions.md` names.
 * `queryOptions` brands the key with the type its `queryFn` returns, and any
 * annotation written by hand erases that brand — which is the only reason the
 * helper exists. Infer it here; annotate the hooks, as below.
 */
export function itemDetailQuery(id: string) {
  return queryOptions({
    queryKey: itemKeys.detail(id),
    queryFn: async () => unwrap(await repository.getById(id)),
  });
}

// The same two hooks as in "Standard query" — same behaviour, one definition
// of the query instead of one per hook.
export function useItem(id: string): UseQueryResult<Item> {
  // Same `enabled` trap as above: a disabled query never leaves `isPending`.
  return useQuery({ ...itemDetailQuery(id), enabled: !!id });
}

export function useItemName(id: string): UseQueryResult<string> {
  return useQuery({ ...itemDetailQuery(id), select: (data) => data.name });
}
```

```tsx
// `to="/items/$id"` + `params`, never a template literal: TanStack Router types
// `to` against the route tree, so a built string is `string` and fails
// `pnpm typecheck` — and it skips the param encoding, so an id holding `/` or
// `#` silently points somewhere else.
<Link
  to="/items/$id"
  params={{ id }}
  onMouseEnter={() => queryClient.prefetchQuery(itemDetailQuery(id))}
>
  View
</Link>
```

`queryOptions` is not a formatting helper: it ties the key to the function that
fills it, so `getQueryData(itemDetailQuery(id).queryKey)` comes back typed as
`Item` instead of `unknown`. It is also what a TanStack Router loader takes —
`queryClient.ensureQueryData(itemDetailQuery(params.id))`.

**A query with exactly one caller does not need it.** `useItems` above is
written inline on purpose — hoisting it would add a layer for a duplication that
does not exist. The detail query earns the helper because three call sites want
it: the hook, the `select` variant, and the prefetch.
