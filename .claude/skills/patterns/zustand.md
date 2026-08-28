# Zustand Patterns

## Where a store lives

| The state belongs to… | File |
| --- | --- |
| One feature (a selection, a form flag, an **ephemeral** filter — a shareable one goes to the URL, `patterns/url-state.md`) | `features/<name>/stores/store.ts` |
| The whole app, no single feature owns it (theme, sidebar, density) | `src/stores/<name>.store.ts` |

`src/stores/` is **shared leaf code**: like `src/lib/` and `src/hooks/`, it must
never import a feature — `enforce-architecture.py` denies it, because a theme
store that names one feature is a store the others cannot read
(`.claude/rules/02-architecture.md`). A feature store is covered by the
cross-feature rule instead.

**Neither may import the data client.** That is enforced too, at both paths: a
store is not a place where I/O happens (last section of this page).

## Store with persist

```typescript
import { create } from 'zustand';
import { persist, devtools } from 'zustand/middleware';

interface UIStore {
  sidebarOpen: boolean;
  theme: 'light' | 'dark' | 'system';
  toggleSidebar: () => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
}

/**
 * App-level UI preferences, persisted to localStorage.
 * Lives in `src/stores/ui.store.ts` — no single feature owns the theme.
 *
 * Why Zustand and not a Context: this is a value the **user** owns and the
 * client persists. `persist` handles serialisation, the boot-time read and
 * versioning; a Context would mean writing all three by hand
 * (`.claude/rules/04-state.md`).
 */
export const useUIStore = create<UIStore>()(
  // `devtools` defaults to `enabled ?? import.meta.env.MODE !== 'production'`,
  // so a plain `vite build` already disables it. `DEV` is stricter, and that is
  // the whole reason for the flag: `vite build --mode staging` leaves
  // MODE === 'staging', so the default WOULD attach the Redux DevTools bridge
  // and stream every state transition to any extension listening. `enabled` is
  // the middleware's own flag — the call shape stays identical either way.
  devtools(
    persist(
      (set) => ({
        sidebarOpen: true,
        theme: 'system',

        /**
         * Toggles sidebar open/closed state.
         */
        toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),

        /**
         * Updates theme preference.
         * @param theme - The theme to apply
         */
        setTheme: (theme) => set({ theme }),
      }),
      {
        name: 'ui-store',
        version: 1, // increment + `migrate` if the persisted shape changes
        partialize: (state) => ({ sidebarOpen: state.sidebarOpen, theme: state.theme }),
      }
    ),
    { name: 'UI Store', enabled: import.meta.env.DEV }
  )
);
```

## Store without persist — the canonical case

A **selection**, an **open/closed flag**, an ephemeral filter: UI state shared by
components that no single parent sits above. This is
`.claude/rules/04-state.md`'s "a **selection or an open/closed flag** is UI state
and belongs in Zustand", and it is the shape most feature stores take.

```typescript
// features/catalog/stores/store.ts
import { create } from 'zustand';
import { devtools } from 'zustand/middleware';

interface CatalogUIState {
  selectedId: string | null;
  isFormOpen: boolean;
}

interface CatalogUIActions {
  select: (id: string | null) => void;
  openForm: () => void;
  closeForm: () => void;
  reset: () => void;
}

const initialState: CatalogUIState = {
  selectedId: null,
  isFormOpen: false,
};

/**
 * UI state for the catalog feature. Client state only — the items themselves
 * come from React Query (`patterns/react-query.md`).
 */
export const useCatalogUIStore = create<CatalogUIState & CatalogUIActions>()(
  devtools(
    (set) => ({
      ...initialState,

      /** Selects a row, or clears the selection with `null`. */
      select: (id) => set({ selectedId: id }),

      /** Opens the create/edit form. */
      openForm: () => set({ isFormOpen: true }),

      /** Closes the form. */
      closeForm: () => set({ isFormOpen: false }),

      /** Back to the initial state — when leaving the feature, and on sign-out. */
      reset: () => set(initialState),
    }),
    { name: 'Catalog UI', enabled: import.meta.env.DEV },
  ),
);
```

`selectedId` holds an **id**, never the row: the row lives in the React Query
cache and is read with it. Storing the entity would be the mirroring
anti-pattern (`04-state.md`) — an id is not the row.

Note what is **not** here: no toast queue. Toasts go through `useToast()`
(`patterns/feedback.md`), which is the single mechanism for them — a store of
notifications would be a second one, and that page says so explicitly.

## Selectors (CRITICAL)

```typescript
// ❌ Re-renders on every change
const store = useUIStore();

// ✅ Re-renders only when theme changes
const theme = useUIStore((s) => s.theme);

// ✅ Any non-primitive return (object, array) → useShallow
// ⚠️ v5: the 2nd argument (equalityFn) is gone from EVERY overload, so
//         useUIStore(selector, shallow) does not compile:
//         "Expected 0-1 arguments, but got 2". Always useShallow.
//         (ledger: `docs/research-cache/settled.md`)
import { useShallow } from 'zustand/react/shallow';
const { theme, sidebarOpen } = useUIStore(
  useShallow((s) => ({ theme: s.theme, sidebarOpen: s.sidebarOpen }))
);
```

## Derived selectors

A selector may compute — that is the point of having one. It runs on every store
change, so keep it cheap and keep it **pure**.

**Pure is not enough.** A selector returning a new object or array on each call
— `s.ids.filter(...)` — has a fresh reference every time and must be wrapped in
`useShallow`, exactly like the multi-value case above. Primitives never need it.

```typescript
/** Whether anything is selected. Derived, never stored. */
export const useHasSelection = (): boolean =>
  useCatalogUIStore((s) => s.selectedId !== null);

/** The selected id, or null. */
export const useSelectedId = (): string | null =>
  useCatalogUIStore((s) => s.selectedId);
```

> **Do not derive across mechanisms in a selector.** A selector that reaches for
> query data to return "the selected *item*" cannot: the store does not hold the
> rows. Read the id from the store and the row from React Query, in the
> component — two hooks, one line each. That separation is the whole reason the
> store keeps an id (`.claude/rules/04-state.md`).

## Async actions — no data client in the store

> **Rule**: a Zustand store carries only **UI state**. DB/API calls live in
> `services.ts`; orchestration (loading, invalidation) in a React Query hook.
> The store only keeps the UI flag if it is shared across components.

```typescript
// ❌ DO NOT call the data client in the store
// logout: async () => { await client.auth.signOut(); }   // violates rules/02 + rules/04

// ✅ The loading flag lives in the mutation (server state → React Query)
//    features/auth/hooks/hooks.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { UseMutationResult } from '@tanstack/react-query';
import { unwrap } from '@/lib/result';
import * as authRepository from '../services/auth.repository';

export const authKeys = {
  all: ['auth'] as const,
  /** Mutation key — what `useIsMutating` matches on (`patterns/react-query.md`). */
  logout: () => [...authKeys.all, 'logout'] as const,
};

export function useLogout(): UseMutationResult<void, Error, void> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationKey: authKeys.logout(),
    mutationFn: async () => unwrap(await authRepository.signOut()),
    // Placement is deliberate — see the note below before copying this.
    onSuccess: () => queryClient.clear(),
  });
}
// const { mutate: logout, isPending: isLoggingOut } = useLogout();
```

> **Logout has two halves.** `queryClient.clear()` empties the *server* state;
> the *client* state needs a `reset()` on every store holding user-scoped state
> — feature-owned or app-level — or the next user in
> the same tab inherits the previous one's selection — module state survives a
> client-side redirect, there is no reload. `security-auditor` grades both.
>
> **And `clear()` does not detach mounted observers.** A query still on screen
> rebuilds its entry as `pending` on the next render and refetches with no
> session: one skeleton flash, one 401, on the screen being left. Clear **after**
> the redirect has committed — `await navigate({ to: '/login' })`, then
> `queryClient.clear()` — or accept the flash knowingly.

If a UI flag must be **shared outside the component**, reach for a store last.
React Query already publishes mutation status globally: give the mutation a key
(above) and read it with `useIsMutating`, with no second source of truth and
nothing to reset.

**Where you may read it is decided by the layer arrow, not by convenience.** The
key factory lives in the feature, so importing it is importing a feature:

```typescript
// src/routes/*, src/providers/* (wiring — they may import a feature), or
// anywhere inside features/auth/ itself. NOT src/components/ (layouts and
// guards included), src/hooks/, src/stores/, src/config/ — shared leaf code
// may not name a feature, and `enforce-architecture.py` denies the write.
import { useIsMutating } from '@tanstack/react-query';
import { authKeys } from '@/features/auth/hooks/hooks';

const isLoggingOut = useIsMutating({ mutationKey: authKeys.logout() }) > 0;
```

> **A shared component needs the flag? Do not import the feature — and do not
> fall through to the store either.** Both roads are wrong, and only one of them
> is blocked: the store import *passes* the hook, so the denial quietly steers
> you into `04-state.md`'s first anti-pattern, which `/loop:review` scores **Major**.
>
> Do what `02-architecture.md` prescribes for every shared file that needs
> feature behaviour: **take it as a parameter**. `src/routes/*` and
> `src/providers/*` are the wiring — those two, and nothing else — so the route
> reads the flag and passes it down as a plain prop. A layout is **not** wiring:
> it lives in `src/components/layouts/`, which is shared leaf code like any
> other, and the hook denies it exactly as it denies a component. The shared component stays feature-agnostic, the hook stays
> happy, and there is no second copy of anything. Do **not** widen `useAuth()`
> for this: its contract is `{ userId, isAuthenticated, isLoading }`
> (`patterns/context.md`), and a mutation flag is not session state.

Only if that is genuinely not reachable — and it is rarer than it looks — the
store holds the boolean, never the network call. It lives in `src/stores/`
(app-level: no feature owns a sign-out flag), which is what makes it importable
from shared code in the first place:

```typescript
// src/stores/authUI.store.ts
interface AuthUIStore {
  isLoggingOut: boolean;
  setLoggingOut: (v: boolean) => void;
}

/**
 * Sign-out UI flag, shared outside the component tree.
 * Prefer `useIsMutating` above; this is the fallback, and it is a hand-synced
 * second copy of `isPending` — the reset is yours to place.
 */
export const useAuthUIStore = create<AuthUIStore>()((set) => ({
  isLoggingOut: false,

  /** Sets the sign-out flag. Reset it from `onSettled`, never `onSuccess`. */
  setLoggingOut: (v) => set({ isLoggingOut: v }),
}));
```

`onSettled` is not a detail: wired to `onSuccess`, a failed `signOut()` (offline,
500) leaves the flag stuck at `true` and every control disabled on it stays
disabled until a full reload — the user cannot retry the logout.
