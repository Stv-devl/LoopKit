# React Query Patterns

## Unwrap Result\<T\>

Repositories return `Result<T>`. Hooks **unwrap** so React Query handles the
errors. `unwrap` lives in `src/lib/result.ts`, scaffolded once from
`.claude/skills/templates/lib-core.md`. **Import it, never redefine it.**

```typescript
import { unwrap } from "@/lib/result";
import type { UseQueryResult } from "@tanstack/react-query";

export function useItems(): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.lists(),
    queryFn: async () => unwrap(await repository.getAll()),
  });
}
```

## Query keys — one factory per feature

**Never type a key literal twice.** A key retyped one character differently is an
invalidation that silently does nothing ("it updates everywhere except here").
Declare them once, next to the hooks:

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

- `as const` is required: a typo becomes a type error, not a query that never
  matches.
- Invalidation matches by **prefix**: `all` hits every item query, `lists()`
  every list whatever its filter (details untouched), `detail(id)` one row.
- **A mutation gets a key only when something outside the component must read
  its status.** Add a member to the same factory and read it with
  `useIsMutating({ mutationKey: itemKeys.remove() }) > 0` instead of copying
  `isPending` into a store (`patterns/zustand.md`, "Async actions"). Otherwise
  a mutation needs no key.

## Config by data type

Pick a `staleTime` from what the data **is**, not by habit. Every example either
names its profile or deliberately inherits the floor from
`src/lib/queryClient.ts` (`templates/lib-core.md`); silence is never the third
option.

| Data | `staleTime` | `gcTime` | Also |
| --- | --- | --- | --- |
| Static (config, enums) | `Infinity` | `Infinity` | `refetchOnWindowFocus: false` |
| User-owned (profile, preferences) | 5 min | 1 h | |
| Collaborative (anything another user can change) | 30 s | 5 min | |
| Realtime-backed | `Infinity` | 5 min | the subscription invalidates; polling on top is waste |

`queryClient.ts` sets the floor (the **collaborative** row, declared there and
not re-typed here) **and the retry predicate**. Without the floor, a hook that
forgets a line falls back to refetch-on-every-mount (`staleTime: 0`). Without
the predicate, `unwrap` throwing `not_found` is retried three times before
`isError` renders.

A hook overrides the floor from the table; it never re-states it. **Both numbers
of the profile, not only `staleTime`**: a hook copying the `staleTime` line alone
has applied half a profile and silently kept the floor's `gcTime`.

## When the key changes

`isFetching` keeps data visible for a refetch on the **same key**. When the key
carries a filter, a sort or a page (`04-state.md` routes all three to the URL),
typing one character mounts a **different** query: `data` is `undefined` and
`isPending` is `true` again, so the list collapses to a spinner on every
keystroke. That contradicts the "keep data on refetch" line of `CLAUDE.md`, and
no `isFetching` handling in the component fixes it. The fix belongs to the
**hook** — a component cannot hold the previous key's rows:

```typescript
export function useItems(search: ItemsSearch): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.list(search),
    queryFn: async () => unwrap(await repository.getAll(search)),
    // Inherits the collaborative floor from queryClient.ts (profile table above).
    // Previous key's rows stay on screen while the new key loads
    // (`keepPreviousData` from the lib is the same, with an import).
    placeholderData: (previous) => previous,
  });
}
```

| On a key change | Without | With `placeholderData` |
| --- | --- | --- |
| `data` | `undefined` | the previous key's rows |
| `isPending` | `true` — full loading state | `false` |
| what marks the load | nothing | `isFetching` → discreet indicator |
| what says the rows are stale | nothing | `isPlaceholderData` — dim the list, `aria-busy`, never a spinner |

**`isPlaceholderData` is a display state, not a debug flag**: previous-filter rows
shown as if they answered the current one is a lie the user acts on
(`patterns/feedback.md`). A query whose key never changes needs none of this
(`08-feedback.md`).

## Standard query

```typescript
import * as repository from "../services/item.repository";
import type { UseQueryResult, UseMutationResult } from "@tanstack/react-query";

export function useItems(): UseQueryResult<Item[]> {
  return useQuery({
    queryKey: itemKeys.lists(),
    queryFn: async () => unwrap(await repository.getAll()),
    staleTime: 5 * 60 * 1000, // user-owned profile — both lines
    gcTime: 60 * 60 * 1000,
  });
}

export function useItem(id: string): UseQueryResult<Item> {
  return useQuery({
    queryKey: itemKeys.detail(id),
    queryFn: async () => unwrap(await repository.getById(id)),
    // Inherits the collaborative floor (profile table above).
    // `enabled: false` stays `status: 'pending'` / `fetchStatus: 'idle'` forever,
    // so a caller branching on `isPending` shows a spinner that never ends.
    // Branch on `isLoading` and give "no id yet" its own branch (`08-feedback.md`).
    enabled: !!id,
  });
}
```

> For small features (single `services.ts`), replace `repository.*` with `services.*`.

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

> **The logout mutation must also empty the cache**: `queryClient.clear()`, or the
> next account in the same tab reads the previous user's rows. The worked example
> (and the `reset()` half, and where `clear()` fires relative to the redirect) is
> in `patterns/zustand.md` ("Async actions"); `agents/security-auditor.md` grades
> its absence.

## Optimistic mutation

> **The fourth generic is not optional.** `UseMutationResult<TData, TError,
> TVariables>` leaves `TContext` at `unknown`, so `onMutate`'s return never
> reaches `onError`'s `context` and `context.previous` is a compile error.
> `03-conventions.md` requires explicit return types, so fill the fourth slot by
> hand (`MutationContext` below).

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
      // Merge, and drop keys carried as an explicit `undefined`: a spread does
      // NOT skip them, so a form submitting `{ description: undefined }` blanks
      // the field for the whole flight, then the refetch restores it ("it
      // flickers"; TypeScript sees nothing).
      queryClient.setQueryData<Item>(itemKeys.detail(updated.id), (old) =>
        old ? { ...old, ...definedOnly(updated) } : old,
      );
      return { previous };
    },
    onError: (err, updated, context) => {
      if (context?.previous)
        queryClient.setQueryData(itemKeys.detail(updated.id), context.previous);
    },
    // The two surfaces touched, not `itemKeys.all` (it would refetch every OTHER
    // open detail; `templates/feature.md`, "`lists()` and `detail(id)`, not
    // `all`"). No `void`, on purpose: the awaited promise keeps the mutation
    // `isPending` until the refetch lands, so the optimistic value does not read
    // as confirmed early (`templates/feature.md`, "The two shapes above are not
    // interchangeable either").
    onSettled: (_data, _error, updated) =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: itemKeys.detail(updated.id) }),
        queryClient.invalidateQueries({ queryKey: itemKeys.lists() }),
      ]),
  });
}

/** Drops keys a partial input carries as an explicit `undefined`. The cast is unavoidable: `Object.entries` erases key types. */
function definedOnly<T extends object>(patch: T): Partial<T> {
  return Object.fromEntries(
    Object.entries(patch).filter(([, value]) => value !== undefined),
  ) as Partial<T>;
}
```

## Real-time subscription

> **Rule (`rules/04-state.md` + `rules/02`)**: the subscription is raw I/O, so it
> lives in the **gateway** (or `services.ts` if unsplit), never in the hook. The
> repository maps the raw payload to a domain entity; the hook only **wires**
> mapped events to the cache. **Never** `payload.new as Item`.
> `enforce-architecture.py` allows the data client in `*.gateway.ts` and
> `services.ts` only: an `items.service.ts` importing it is denied.
>
> The transport below is **Server-Sent Events**; swap it for a WebSocket or BaaS
> channel and only the gateway changes. Supabase channels:
> `addons/supabase/skills/patterns/realtime.md`.

```typescript
// features/items/services/items.gateway.ts — raw I/O, no mapping, no Result
import { client } from "@/lib/client";

/**
 * Opens the item change stream, emitting payloads exactly as they arrive.
 * `onReconnect` fires when the stream comes back after a drop (transport
 * knowledge); what to do about it is not decided here.
 * @returns Unsubscribe function.
 */
export function subscribeToItemPayloads(
  onPayload: (payload: unknown) => void,
  onReconnect: () => void,
): () => void {
  const source = new EventSource(client.streamUrl("/items"));
  let hasConnected = false;

  source.onopen = () => {
    // Fires on first connect AND every reconnect; only the latter means missed events.
    if (hasConnected) onReconnect();
    hasConnected = true;
  };
  source.onmessage = (event) => onPayload(JSON.parse(event.data));

  return () => source.close();
}
```

The gateway interprets **nothing**, not even which kind of change arrived.

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
 * Subscribes to item changes, validated and mapped to domain entities.
 * Malformed payloads are logged and dropped: realtime is untrusted input.
 * @returns Unsubscribe function.
 */
export function subscribeToItems(
  onChange: (change: ItemChange) => void,
  onReconnect: () => void,
): () => void {
  return gateway.subscribeToItemPayloads((payload) => {
    // Validate before mapping: the mapper takes a typed row, never `unknown`
    // or an `as` cast (rules/02-architecture.md).
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
      // `setQueriesData`, not `setQueryData`: `lists()` is a **prefix**. Once a
      // list takes a filter the real entries are `list(search)`, and
      // `['items', 'list']` is never populated, so `setQueryData` would write a
      // key nobody reads.
      queryClient.setQueriesData<Item[]>({ queryKey: itemKeys.lists() }, (old) => {
        // A matched entry can hold no data (fetch in flight or cancelled).
        // Writing anyway would stamp it fresh with one row and suppress the
        // refetch for a whole `staleTime`. `undefined` leaves it untouched.
        if (old === undefined) return undefined;

        // Blind spots an invalidation does not have: the row is appended at the
        // END (ordering is the server's), and written into EVERY list key, so an
        // upsert lands in `list({ status: 'archived' })` whether archived or not
        // and an item that stopped matching a filter stays in it. This is why
        // invalidation is the default (note below).
        if (change.type === "delete") return old.filter((i) => i.id !== change.id);
        const exists = old.some((i) => i.id === change.item.id);
        return exists
          ? old.map((i) => (i.id === change.item.id ? change.item : i))
          : [...old, change.item];
      });

      // The same event owns the DETAIL entry too, or a rename by another user
      // leaves an open detail sheet showing the old name.
      if (change.type === "delete") {
        queryClient.removeQueries({ queryKey: itemKeys.detail(change.id) });
        return;
      }
      // `undefined` updater result: never CREATES a detail nobody opened.
      queryClient.setQueryData<Item>(itemKeys.detail(change.item.id), (old) =>
        old === undefined ? undefined : change.item,
      );
    }, () => {
      // Back up after a drop: the gap is not replayed. Refetch rather than guess.
      void queryClient.invalidateQueries({ queryKey: itemKeys.all });
    });
  }, [queryClient]);
}
```

> **Mount it once.** Nothing dedupes the connection: two components calling
> `useItemsRealtime()` mean two `EventSource`s and duplicated updates nobody traces
> to the mount count. Call it in the single component owning the screen it feeds
> (page, or the layout above if several pages share the stream), never in a list
> item or a shared component; two independent screens needing the same stream
> means hoisting the call into the layout.
>
> **A dropped connection loses every undelivered event**, and neither
> `EventSource` nor a BaaS channel replays the gap, so the cache stays
> confidently wrong. **Invalidate on reconnect**, not only on event (the gateway
> forwards it as its own callback). This is why the `Realtime-backed` row's
> `staleTime: Infinity` is a real decision: with it, the reconnect invalidation is
> the *only* thing that can repair the cache. Take `Infinity` only once the
> reconnect path exists; the collaborative floor is the safer default until then.
>
> **Writing into the cache is the optimisation, not the default.** For a list,
> `invalidateQueries({ queryKey: itemKeys.lists() })` is correct, costs one
> refetch and cannot desynchronise — take it unless a refetch per event is absurd
> (cursor, presence badge, high-frequency counter). Same verdict in
> `addons/supabase/skills/patterns/realtime.md`.

## A query with a second caller — `queryOptions`

Prefetching or a route loader names the same query twice. Retyping `queryKey` +
`queryFn` is the retyped-key defect one level up: the copies drift and the
prefetch fills an entry the hook never reads. The moment a query has a
**second** caller, hoist its definition:

```typescript
// features/items/hooks/hooks.ts
import { queryOptions } from "@tanstack/react-query";

/**
 * The one definition of "the item detail query".
 * No explicit return type: the one exception `03-conventions.md` names.
 * `queryOptions` brands the key with the `queryFn` return type and a
 * hand-written annotation erases that brand. Annotate the hooks, not this.
 */
export function itemDetailQuery(id: string) {
  return queryOptions({
    queryKey: itemKeys.detail(id),
    queryFn: async () => unwrap(await repository.getById(id)),
  });
}

export function useItem(id: string): UseQueryResult<Item> {
  // Same `enabled` trap as above: a disabled query never leaves `isPending`.
  return useQuery({ ...itemDetailQuery(id), enabled: !!id });
}

export function useItemName(id: string): UseQueryResult<string> {
  return useQuery({ ...itemDetailQuery(id), select: (data) => data.name });
}
```

```tsx
// `to` + `params`, never a template literal: TanStack Router types `to` against
// the route tree (a built string fails `pnpm typecheck`) and skips param
// encoding, so an id holding `/` or `#` silently points elsewhere.
<Link
  to="/items/$id"
  params={{ id }}
  onMouseEnter={() => queryClient.prefetchQuery(itemDetailQuery(id))}
>
  View
</Link>
```

It also types `getQueryData(itemDetailQuery(id).queryKey)` as `Item`, and is what a
router loader takes: `queryClient.ensureQueryData(itemDetailQuery(params.id))`.
**A query with exactly one caller does not need it** (`useItems` stays inline).
