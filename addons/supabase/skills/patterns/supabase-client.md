# Supabase Client & Auth (front end)

<!-- FILL: file paths, provider and hook names. What must not change: the client
     is created once, only the data layer imports it, and the generated DB types
     are the source of truth for row shapes. -->

> The client lives in `src/lib/supabase.ts` and **only `*.gateway.ts` /
> `services.ts` may import it** (`.claude/rules/02-architecture.md`, enforced by
> the `enforce-architecture` hook). Route protection lives in `guards.md`.

## The client — created once

```typescript
// src/lib/supabase.ts
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/types/database.types';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error('Missing Supabase environment variables');
}

/** Typed Supabase client. Import only from the data layer. */
export const supabase = createClient<Database>(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
  global: { fetch: (...args) => fetch(...args) },
});
```

**That `global.fetch` line is not decoration.** Resolved per call, it means
whatever patched the global — MSW in the gateway tests — is the one used. Left
out, `supabase-js` may hold a reference captured at module load, MSW never sees
the request, and every gateway test fails for a reason nobody connects to this
file. `msw-supabase.md` opens with the one test that proves the interception:
write it before the first handler.

The key in the browser bundle is the **publishable** key (legacy name: `anon`).
The secret / `service_role` key **bypasses RLS** — it never appears in anything
Vite builds, whatever the variable is called.

## Generated types are not optional

```bash
supabase gen types --linked > src/types/database.types.ts
```

Regenerate it **in the same change as the migration**. Without it the gateway
types its rows by hand, drifts from the schema, and `any` comes back in through
the one door `03-conventions.md` closed.

```typescript
// Row shapes come from the generated types, never re-declared by hand.
type ItemRow = Database['public']['Tables']['items']['Row'];
type ItemInsert = Database['public']['Tables']['items']['Insert'];
```

The **domain entity** (`types/types.ts`) stays pure and framework-agnostic; the
mapper is what bridges `ItemRow` → `Item`.

## Gateway — raw rows, no mapping, no Result

```typescript
// features/items/services/items.gateway.ts
import { supabase } from '@/lib/supabase';
import type { Database } from '@/types/database.types';

type ItemRow = Database['public']['Tables']['items']['Row'];

/** Fetches the caller's items. RLS scopes the rows — this filter is not the barrier. */
export async function fetchItems(): Promise<ItemRow[]> {
  const { data, error } = await supabase
    .from('items')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) throw error;
  return data;
}
```

> The gateway does not add `.eq('user_id', …)` for security — RLS already
> scopes the rows server-side (`rls.md`). Add it only when you genuinely need a
> narrower set than the policy allows.

## Repository — where the error becomes a `Result`

```typescript
// features/items/services/items.repository.ts
import { fetchItems } from './items.gateway';
import { toItem } from './items.mapper';
// `toItemError`, NOT `toServiceError`: that name is taken by `src/lib/result.ts`,
// where it narrows an `unknown` thrown error. Reusing it for a PostgREST mapper
// gives one name two contracts, and `agents/reviewer.md` scores the second shape
// as a Major. The core template calls this helper `featureError`
// (`templates/feature.md`).
import { toItemError } from './items.errors';
import { ok, err, type Result } from '@/lib/result';
import type { Item } from '../types/types';

/** Returns the caller's items, or a typed error. Never throws. */
export async function getItems(): Promise<Result<Item[]>> {
  try {
    const rows = await fetchItems();
    // `ok()` / `err()`, never the object literal: one shape, one place
    // (`templates/lib-core.md`, "Import them, never redefine them locally").
    return ok(rows.map(toItem));
  } catch (error) {
    console.error('[items] fetch failed', error);   // log EN
    return err(toItemError(error));
  }
}
```

Supabase errors carry a `code`. The two worth branching on:

| Code | Means |
| --- | --- |
| `PGRST116` | No row returned where one was expected (`.single()`) |
| `42501` | `insufficient_privilege` — an RLS policy refused the write |

An empty array where you expected rows is usually **not** an error: it is RLS
returning nothing, or a missing SELECT policy. Silent by design — check
`pg_policies` before blaming the query.

## Auth session

**The client does not appear in the provider.** `02-architecture.md` names this
exact file as the counter-example — *"an `AuthProvider` reads the session via the
`auth` feature's repository, not via `client.auth`"* — and
`.claude/hooks/enforce-architecture.py` denies the import at write time outside
`main.tsx` / `routes/__root.tsx`. Auth is a feature like any other: its raw calls
live in its gateway, its `Result` in its repository.

```typescript
// features/auth/services/auth.gateway.ts — raw I/O, the only layer that sees the client
import { supabase } from '@/lib/supabase';

/** Reads the session stored in this tab. Verifies nothing — see the rules below. */
export async function fetchSession() {
  return supabase.auth.getSession();
}

/**
 * Emits on every auth state change, payload untouched — the event name and the
 * raw session, exactly as Supabase hands them over.
 * @returns Unsubscribe function.
 */
export function subscribeToAuthState(
  onChange: (event: string, session: unknown) => void,
): () => void {
  const { data } = supabase.auth.onAuthStateChange((event, session) =>
    onChange(event, session),
  );
  return () => data.subscription.unsubscribe();
}

/** Ends the session. */
export async function signOut() {
  return supabase.auth.signOut();
}

/**
 * Tears down every realtime channel. Lives here because it is a client call:
 * anywhere above the data layer `enforce-architecture.py` denies the write
 * (`realtime.md`, "What goes wrong"). Returns the per-channel promises.
 */
export async function removeAllChannels(): Promise<('ok' | 'timed out' | 'error')[]> {
  return supabase.removeAllChannels();
}
```

```typescript
// features/auth/services/auth.repository.ts — validates, maps, hides the transport
import * as gateway from './auth.gateway';
import { toAuthSession } from './auth.mapper';
import { authSessionSchema } from '../types/schemas';
import type { AuthSession } from '../types/types';

/**
 * Subscribes to "who is signed in now". The event name (`SIGNED_IN`,
 * `TOKEN_REFRESHED`, `SIGNED_OUT`) is transport vocabulary and stops here — the
 * provider needs the session, not the verb. Collapsing the two arguments into
 * one is the whole reason this layer exists: a consumer that binds a single
 * parameter to a two-argument callback silently receives the EVENT STRING and
 * stores `"SIGNED_IN"` as its session.
 * @returns Unsubscribe function.
 */
export function subscribeToAuthState(
  onChange: (session: AuthSession | null) => void,
): () => void {
  return gateway.subscribeToAuthState((_event, session) => {
    const parsed = authSessionSchema.safeParse(session);
    onChange(parsed.success ? toAuthSession(parsed.data) : null);
  });
}
```

```tsx
// src/providers/AuthProvider.tsx — wiring: it may import the feature, not the client
import { useEffect, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import * as authRepository from '@/features/auth/services/auth.repository';
import type { AuthSession } from '@/features/auth/types/types';

export function AuthProvider({ children }: { children: React.ReactNode }): React.ReactElement {
  const queryClient = useQueryClient();
  const [session, setSession] = useState<AuthSession | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  // Identity of the user the cache currently holds. A ref, not state: nothing
  // renders it (`patterns/local-state.md`).
  const cachedUser = useRef<string | null>(null);

  useEffect(() => {
    // TWO flags, because two different things can go wrong and one flag cannot
    // cover both:
    //  - `cancelled` — the component unmounted; ignore whatever arrives.
    //  - `eventLanded` — an auth event already answered, so the in-flight boot
    //    read is stale. Unmount is NOT the only losing case: an OAuth callback
    //    (`detectSessionInUrl`) delivers another user while we stay mounted, and
    //    if the stale boot result lands last it rewrites the ref, every later
    //    event then compares equal, and the cache is never cleared.
    let cancelled = false;
    let eventLanded = false;

    void authRepository.getSession().then((result) => {
      if (cancelled || eventLanded) return;
      const next = result.success ? result.data : null;
      setSession(next);
      setIsLoading(false);
      cachedUser.current = next?.userId ?? null;
    });

    const unsubscribe = authRepository.subscribeToAuthState((next) => {
      if (cancelled) return;
      // An event is the live session: it outranks the boot read, whenever it
      // arrives. Note the repository maps an unparseable payload to `null` too,
      // so a schema drift reads here as a sign-out — see the rules below.
      eventLanded = true;
      setSession(next);
      setIsLoading(false);
      // Clear on sign-out AND on user change — the two triggers rule 2 names.
      // Keyed on identity, never on the event: this layer deliberately drops the
      // verb (see the repository above), and the listener also fires on a token
      // refresh, where clearing would empty the cache for nothing.
      const nextUser = next?.userId ?? null;
      if (nextUser !== cachedUser.current) {
        cachedUser.current = nextUser;
        // `clear()` empties the cache but does not detach mounted observers —
        // where it fires relative to the redirect decides whether the user sees
        // a skeleton and a 401 on the way out (`patterns/zustand.md`).
        queryClient.clear();
      }
    });

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [queryClient]);

  // The CONTRACT, never the feature entity — the shape is declared once in
  // `patterns/context.md` and consumers destructure from it (`patterns/guards.md`).
  // Handing `session` straight through would leave `isAuthenticated` undefined
  // in every guard, so `AuthGuard` would bounce a signed-in user on every render.
  return (
    <AuthContext value={{ userId: session?.userId ?? null, isAuthenticated: session !== null, isLoading }}>
      {children}
    </AuthContext>
  );
}
```

> The `AuthContext` declaration and the contract's type live in
> `patterns/context.md` — this block shows only what changes with Supabase
> behind it: the two repository calls, and the cache reset on identity change.

Two rules:

- **The repository maps an unparseable payload to `null`, exactly like a
  sign-out.** That is the safe default — never render a session you could not
  validate — but it means a Supabase payload change reads to the whole app as
  "signed out", and the user simply lands on the login screen with nothing in
  the console. Log the parse failure in `subscribeToAuthState` before returning
  `null`, or the day the schema drifts you will be debugging the guard.
- **`getSession()` reads local storage. It does not verify anything.** It is
  fine for "is there a session in this tab", and worthless as proof of identity.
  When you need a verified user, `getUser()` (or `getClaims()`) — it asks the
  server.
- **Clear the React Query cache on sign-out and on user change.** Otherwise the
  next user reads the previous one's cached rows, and RLS never gets a say
  because no request is made.

Route-level protection: `guards.md`. The guard is UX — the barrier is RLS.

## Sign in / sign out

```typescript
// features/auth/services/auth.repository.ts — the client call is one layer down
import { ok, err, type Result } from '@/lib/result';
import * as gateway from './auth.gateway';
import { authError } from './auth.errors';

/** Signs the user in with email + password. */
export async function signIn(email: string, password: string): Promise<Result<void>> {
  const { error } = await gateway.signInWithPassword(email, password);
  // `authError` is this feature's error builder — the twin of `featureError` in
  // `templates/feature.md`. It logs in EN inside `serviceError`, so there is no
  // `console.error` here, and it returns a code; the French string is picked
  // from that code at the UI layer (`patterns/feedback.md`).
  if (error) return err(authError('invalid_credentials', 'Sign-in rejected', error));
  return ok(undefined);
}

/**
 * Signs the user out, and tears down every realtime channel with them.
 *
 * The channel teardown lives HERE and nowhere else: `removeAllChannels()` is a
 * client call, so `enforce-architecture.py` denies it in a hook or a component
 * (`realtime.md`, "What goes wrong"). Sign-out is the one moment the whole set
 * has to go — a channel left open keeps the previous user's JWT.
 */
export async function signOut(): Promise<Result<void>> {
  // Awaited, but never allowed to decide the sign-out. `removeAllChannels()` is
  // a `Promise.all` of unsubscribes: it REJECTS rather than returning an
  // `{ error }`, and an uncaught rejection here would (a) throw out of a
  // repository, which `02-architecture.md` forbids, and (b) skip
  // `gateway.signOut()` entirely — the user believes they are out while the
  // token stays valid. A dead socket also stalls it until the realtime timeout.
  await gateway.removeAllChannels().catch((error: unknown) => {
    console.error('[auth] channel teardown failed', error);
  });
  const { error } = await gateway.signOut();
  if (error) return err(authError('sign_out_failed', 'Sign-out rejected', error));
  return ok(undefined);
}
```

Never surface the raw Supabase message: it distinguishes "wrong password" from
"unknown account" and hands an enumeration oracle to whoever is asking.

## Checklist

- [ ] Client created once in `src/lib/supabase.ts`, publishable key only
- [ ] `Database` generated types imported, regenerated with every migration
- [ ] Only `*.gateway.ts` / `services.ts` import the client
- [ ] Gateway returns raw rows and throws; repository returns `Result<T>`
- [ ] Cache cleared on auth state change
- [ ] `getUser()` — not `getSession()` — wherever identity must be trusted
- [ ] Auth errors logged in English, shown to the user in French, never verbatim
