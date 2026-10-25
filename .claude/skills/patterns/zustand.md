# Zustand Patterns

## Where a store lives

| The state belongs to… | File |
| --- | --- |
| One feature (a selection, a form flag, an **ephemeral** filter — a shareable one goes to the URL, `patterns/url-state.md`) | `features/<name>/stores/store.ts` |
| The whole app, no single feature owns it (theme, sidebar, density) | `src/stores/<name>.store.ts` |

`src/stores/` is **shared leaf code**: it must never import a feature
(`enforce-architecture.py` denies it, `.claude/rules/02-architecture.md`). A
feature store is covered by the cross-feature rule. **Neither may import the data
client**: a store is not a place where I/O happens (last section).

## Store with persist

A value the **user** owns and the client persists goes here, not in a Context:
`persist` handles serialisation, the boot-time read and versioning
(`.claude/rules/04-state.md`).

```typescript
import { create } from 'zustand';
import { persist, devtools } from 'zustand/middleware';

interface UIStore {
  sidebarOpen: boolean;
  theme: 'light' | 'dark' | 'system';
  toggleSidebar: () => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
}

/** App-level UI preferences, persisted to localStorage (`src/stores/ui.store.ts`). */
export const useUIStore = create<UIStore>()(
  // `enabled: import.meta.env.DEV`, not the default MODE check: a
  // `vite build --mode staging` keeps MODE === 'staging', so the default would
  // attach the Redux DevTools bridge and stream every transition.
  devtools(
    persist(
      (set) => ({
        sidebarOpen: true,
        theme: 'system',

        /** Toggles sidebar open/closed state. */
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
components no single parent sits above (`.claude/rules/04-state.md`). This is the
shape most feature stores take.

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

/** UI state for the catalog feature. Client state only — items come from React Query. */
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

`selectedId` holds an **id**, never the row: storing the entity is the mirroring
anti-pattern (`04-state.md`). No toast queue here either: toasts go through
`useToast()` (`patterns/feedback.md`), the single mechanism.

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

A selector may compute, but must stay cheap and **pure**. **Pure is not enough**:
one returning a new object or array per call (`s.ids.filter(...)`) has a fresh
reference every time and needs `useShallow`. Primitives never do.

```typescript
/** Whether anything is selected. Derived, never stored. */
export const useHasSelection = (): boolean =>
  useCatalogUIStore((s) => s.selectedId !== null);
```

> **Do not derive across mechanisms in a selector.** The store does not hold the
> rows, so "the selected *item*" cannot come from a selector. Read the id from
> the store and the row from React Query, in the component — two hooks, one line
> each.

## Async actions — no data client in the store

> **Rule**: a Zustand store carries only **UI state**. DB/API calls live in
> `services.ts`; orchestration (loading, invalidation) in a React Query hook. The
> store only keeps a UI flag if it is shared across components.

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
```

> **Logout has two halves.** `queryClient.clear()` empties the *server* state;
> the *client* state needs a `reset()` on every store holding user-scoped state
> (feature-owned or app-level), or the next user in the same tab inherits the
> previous one's selection — module state survives a client-side redirect.
> `security-auditor` grades both.
>
> **`clear()` does not detach mounted observers.** A query still on screen
> rebuilds its entry as `pending` and refetches with no session: one skeleton
> flash, one 401. Clear **after** the redirect has committed —
> `await navigate({ to: '/login' })`, then `queryClient.clear()` — or accept the
> flash knowingly.

If a UI flag must be **shared outside the component**, reach for a store last:
give the mutation a key (above) and read it with `useIsMutating`; no second
source of truth, nothing to reset. **Where you may read it is decided by the
layer arrow**: the key factory lives in the feature, so importing it is
importing a feature.

```typescript
// Allowed in src/routes/*, src/providers/* (wiring) or inside features/auth/.
// NOT src/components/ (layouts and guards included), src/hooks/, src/stores/,
// src/config/ — `enforce-architecture.py` denies the write.
import { useIsMutating } from '@tanstack/react-query';
import { authKeys } from '@/features/auth/hooks/hooks';

const isLoggingOut = useIsMutating({ mutationKey: authKeys.logout() }) > 0;
```

> **A shared component needs the flag? Do not import the feature, and do not
> fall through to the store.** The store import *passes* the hook, so the denial
> quietly steers you into `04-state.md`'s first anti-pattern, which `/loop:review`
> scores **Major**. Do what `02-architecture.md` prescribes: **take it as a
> parameter**. The route (wiring) reads the flag and passes it down as a plain
> prop. A layout is **not** wiring (`src/components/layouts/` is shared leaf
> code). Do **not** widen `useAuth()`: its contract is
> `{ userId, isAuthenticated, isLoading }` (`patterns/context.md`), and a
> mutation flag is not session state.

Only if that is genuinely unreachable, the store holds the boolean, never the
network call, in `src/stores/` (app-level, so shared code may import it):

```typescript
// src/stores/authUI.store.ts
interface AuthUIStore {
  isLoggingOut: boolean;
  setLoggingOut: (v: boolean) => void;
}

/**
 * Sign-out UI flag, shared outside the component tree. Prefer `useIsMutating`;
 * this is a hand-synced second copy of `isPending` — the reset is yours to place.
 */
export const useAuthUIStore = create<AuthUIStore>()((set) => ({
  isLoggingOut: false,

  /** Sets the sign-out flag. Reset it from `onSettled`, never `onSuccess`. */
  setLoggingOut: (v) => set({ isLoggingOut: v }),
}));
```

`onSettled` is not a detail: on `onSuccess`, a failed `signOut()` (offline, 500)
leaves the flag stuck at `true` and every control disabled on it stays disabled
until a reload.
