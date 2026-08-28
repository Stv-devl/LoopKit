# Realtime

<!-- FILL: table and channel names. What must not change: the subscription lives
     in the data layer, it is always cleaned up, and RLS applies to it. -->

> `04-state.md` routes real-time to the data layer: the subscription is created
> in `*.gateway.ts` / `services.ts`, never in a component. What it feeds is the
> React Query cache, not a parallel piece of state.

## Enabling it on a table

Realtime reads the WAL through a publication. A table that is not in it emits
nothing — no error, no warning, just silence.

```sql
-- via /database:migration
ALTER PUBLICATION supabase_realtime ADD TABLE public.items;
```

**RLS applies to realtime.** A client only receives changes to rows its SELECT
policy would return. A table with RLS on and no SELECT policy is silent for
everyone. If UPDATE/DELETE payloads arrive with only the primary key, the table
needs `REPLICA IDENTITY FULL` — at a real cost in WAL volume, so only where the
old row genuinely matters.

## The subscription — in the data layer

The chain is the ordinary one, realtime changes nothing about it:
**gateway** opens the channel and emits the payload untouched, **repository**
validates and maps, **hook** wires the result to the cache. The hook never
imports the gateway — the same rule as every other read
(`.claude/rules/02-architecture.md`).

```typescript
// features/items/services/items.gateway.ts — raw I/O, no mapping, no cast
import { supabase } from '@/lib/supabase';
import type { RealtimeChannel } from '@supabase/supabase-js';

/**
 * Subscribes to changes on `items`. Emits the raw payload, exactly as it
 * arrives. Returns the unsubscribe function — the caller MUST call it.
 */
export function subscribeToItemPayloads(
  onPayload: (payload: unknown) => void,
  onReconnect: () => void,
): () => void {
  let hadError = false;
  const channel: RealtimeChannel = supabase
    .channel('items-changes')
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'items' },
      (payload) => onPayload(payload),
    )
    .subscribe((status) => {
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        console.error('[items] realtime channel failed', status);   // EN
        hadError = true;
        return;
      }
      // SUBSCRIBED again after a failure: the changes committed while the
      // channel was down were never delivered and Postgres changes are **not**
      // replayed. Logging the drop and stopping there leaves the cache
      // confidently wrong; the caller has to refetch.
      if (status === 'SUBSCRIBED' && hadError) {
        hadError = false;
        onReconnect();
      }
    });

  return () => {
    void supabase.removeChannel(channel);
  };
}
```

> **No `as` here, and that is the point.** `payload.new as ItemRow` is the cast
> the core pattern names explicitly as the one never to write
> (`patterns/react-query.md`): a realtime payload is untrusted input arriving over
> a socket, and `Database['public']['Tables']['items']['Row']` describes what the
> table *should* hold, not what came down the wire. `REPLICA IDENTITY` alone
> makes the cast a lie — on DELETE, `payload.old` carries the primary key and
> nothing else. Validate it one layer up, where the failure has somewhere to go.

Channel names are global per client. Two components subscribing to
`'items-changes'` fight over the same channel — suffix it when the subscription
is scoped (`items-changes:${projectId}`).

```typescript
// features/items/services/items.repository.ts — validates, maps, emits a domain event
import * as gateway from './items.gateway';
import { toItem } from './items.mapper';
import { itemChangeSchema } from '../types/schemas';
import type { Item } from '../types/types';

export type ItemChange =
  | { type: 'upsert'; item: Item }
  | { type: 'delete'; id: string };

/**
 * Subscribes to item changes, already validated and mapped.
 * Payloads that don't match the schema are logged and dropped.
 * @returns Unsubscribe function.
 */
export function subscribeToItems(
  onChange: (change: ItemChange) => void,
  onReconnect: () => void,
): () => void {
  return gateway.subscribeToItemPayloads((payload) => {
    const parsed = itemChangeSchema.safeParse(payload);
    if (!parsed.success) {
      console.error('Dropped malformed realtime payload:', parsed.error);  // EN
      return;
    }
    if (parsed.data.eventType === 'DELETE') {
      onChange({ type: 'delete', id: parsed.data.old.id });
      return;
    }
    onChange({ type: 'upsert', item: toItem(parsed.data.new) });
  }, onReconnect);   // nothing to map about a gap: forwarded untouched
}
```

## Wiring it to React Query

The subscription **invalidates**, it does not become state. Writing rows
straight into the cache means maintaining two orderings, two filters and two
sets of derived data.

```typescript
// features/items/hooks/hooks.ts — wiring only
import { subscribeToItems } from '../services/items.repository';

/** Keeps the items list fresh while the component is mounted. */
export function useItemsRealtime(): void {
  const queryClient = useQueryClient();

  useEffect(() => {
    const unsubscribe = subscribeToItems(
      (change) => {
        void queryClient.invalidateQueries({ queryKey: itemKeys.lists() });
        // The detail entry is exactly as stale as the lists. Without this line
        // a rename by another user updates the row in the list and leaves the
        // detail sheet open beside it showing the old value.
        const id = change.type === 'delete' ? change.id : change.item.id;
        void queryClient.invalidateQueries({ queryKey: itemKeys.detail(id) });
      },
      () => {
        // Reconnected after a gap — the details are as suspect as the lists.
        void queryClient.invalidateQueries({ queryKey: itemKeys.all });
      },
    );
    return unsubscribe;          // cleanup is not optional
  }, [queryClient]);
}
```

> **Yes, the repository still earns its place when you only invalidate.** The hook
> discards the payload here, so the validation looks like ceremony — until the
> first `setQueryData` optimisation lands and the hook is already importing the
> layer that hands it a typed `Item`. Going gateway → hook directly is what
> `/loop:review`'s `tests` and `correctness` dimensions flag as reaching past a layer;
> it costs one file to not do it.

Chatty table? Debounce the invalidation rather than dropping events — a burst of
20 inserts should cost one refetch, not twenty.

Writing directly into the cache with `setQueryData` is legitimate for a single
high-frequency entity (a cursor, a presence badge) where a refetch per event is
absurd. For a list, invalidate.

## Cleanup

Every failure mode here is a missing unsubscribe:

- A channel per mount, never removed → the client hits its channel limit and new
  subscriptions silently fail.
- A closure capturing a stale `queryClient` or a dead component → updates
  applied to nothing.
- After sign-out, a channel still open with the previous user's JWT.

`supabase.removeChannel(channel)` in the effect's cleanup. Always. On sign-out,
`supabase.removeAllChannels()` — **from the auth gateway, called by
`authRepository.signOut()`** (`supabase-client.md`, "Sign in / sign out"), never
from the hook or the component that happens to trigger the logout: it is a
client call, and `enforce-architecture.py` denies it outside the data layer.

## Presence & broadcast

For ephemeral state that never needs to be a row (who is on this page, who is
typing), use presence/broadcast instead of a table — no WAL, no policy, no
migration.

```typescript
const channel = supabase.channel('room:42', {
  config: { presence: { key: userId } },
});

channel
  .on('presence', { event: 'sync' }, () => {
    onPresence(channel.presenceState());
  })
  .subscribe(async (status) => {
    if (status === 'SUBSCRIBED') {
      await channel.track({ online_at: new Date().toISOString() });
    }
  });
```

Broadcast payloads are **not** covered by RLS — anything sent on a channel is
readable by every subscriber. Do not put data there that a policy would have
withheld.

## Checklist

- [ ] Table added to the `supabase_realtime` publication, via a migration
- [ ] SELECT policy exists (no policy = no events)
- [ ] Subscription created in the data layer, not in a component
- [ ] Gateway emits the payload raw — no `as ItemRow`, no `as eventType`
- [ ] Repository validates it before mapping; the hook imports the repository,
      never the gateway
- [ ] Unsubscribe returned and called in the effect cleanup
- [ ] Channel name unique per scope
- [ ] Events invalidate React Query; they do not become a second source of truth
- [ ] **Reconnection invalidates too**: `CHANNEL_ERROR` / `TIMED_OUT` followed by
      a new `SUBSCRIBED` means a gap with no replay — logging it is not handling it
- [ ] All channels removed on sign-out
