# Context Patterns — the wiring layer

Context is the narrowest mechanism of `.claude/rules/04-state.md`: what comes
from **outside the client** and is read across the whole tree — the session, the
locale, config injected at the composition root. **Not the theme**: a preference
the user owns and the client persists goes to Zustand (`patterns/zustand.md`).
Context and Zustand split on the origin of the value, not on how widely it is read.

> **A provider is wiring** (`.claude/rules/02-architecture.md`): `src/providers/`
> may import a feature, which is why the auth session lives here rather than in a
> shared hook. It reads through the feature's **repository**, never the data
> client (`enforce-architecture.py` denies it outside the data layer and the
> composition root).

## When Context, and when not

| Need | Mechanism |
| --- | --- |
| Locale, feature flags, injected config — set once, read everywhere | **Context** |
| The auth session, exposed as a feature-agnostic contract | **Context** (`AuthProvider`) |
| Server data | React Query — `patterns/react-query.md` |
| Shared UI state (a modal, a selection), and any persisted preference | Zustand — `patterns/zustand.md` |
| A filter, a sort, a page — anything shareable by link | Search params — `patterns/url-state.md` |
| State used by one subtree only | `useState`, passed as props |

**Context is not a state manager.** It has no selector: every consumer
re-renders on any change. Fine for a locale or session; wrong for anything that
changes on input. Avoiding prop drilling on data that moves is Zustand's job.

## Shape

The context holds a **contract**, not a feature, and the hook **throws** outside
its provider instead of returning a plausible default.

`AuthProvider` sits inside `QueryClientProvider`: the repository call it makes may
end up cached. `useContext` stays valid; React 19 `use` is the one that also takes a
promise.

```tsx
// src/providers/AuthProvider.tsx
import { createContext, use, useEffect, useState } from "react";
import * as authRepository from "@/features/auth/services/auth.repository";

interface AuthContextValue {
  userId: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}

// No default value. `undefined` lets the hook tell "outside the provider" from
// "inside, not logged in" — a default object makes every un-wrapped component
// look logged out, surfacing as a redirect loop nobody can locate.
const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({
  children,
}: {
  children: React.ReactNode;
}): React.ReactElement {
  const [state, setState] = useState<AuthContextValue>({
    userId: null,
    isAuthenticated: false,
    isLoading: true,
  });

  useEffect(() => {
    let cancelled = false;

    void authRepository.getSession().then((result) => {
      if (cancelled) return;
      const session = result.success ? result.data : null;
      setState({
        userId: session?.userId ?? null,
        isAuthenticated: session !== null,
        isLoading: false,
      });
    });

    return () => {
      cancelled = true;
    };
  }, []);

  return <AuthContext value={state}>{children}</AuthContext>;
}

/**
 * The auth session. Throws outside `<AuthProvider>`: a missing provider is a
 * wiring bug, and failing loudly beats every component behaving as logged out.
 */
export function useAuth(): AuthContextValue {
  const value = use(AuthContext);
  if (value === undefined) {
    throw new Error("useAuth must be used inside <AuthProvider>");
  }
  return value;
}
```

> **React 19**: render `<AuthContext>` directly (`<AuthContext.Provider>` is
> deprecated) and read with `use(AuthContext)`; templates are written against 19
> (`.claude/rules/01-stack.md`).

## The contract is the point

`useAuth()` returns `{ userId, isAuthenticated, isLoading }` — **not** the
feature's `Session` entity, and not the repository. That lets
`src/components/guards/AuthGuard.tsx` depend on the provider without naming a
feature (`patterns/guards.md`). A provider re-exporting its feature's types has
moved the coupling, not removed it.

## Composition

Providers are wired once, in one file, outermost-first; a provider needing
another one's value goes **inside** it.

```tsx
// src/providers/AppProviders.tsx
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "@/lib/queryClient"; // templates/lib-core.md
import { AuthProvider } from "./AuthProvider";
import { LocaleProvider } from "./LocaleProvider";

export function AppProviders({
  children,
}: {
  children: React.ReactNode;
}): React.ReactElement {
  return (
    <QueryClientProvider client={queryClient}>
      <LocaleProvider>
        <AuthProvider>{children}</AuthProvider>
      </LocaleProvider>
    </QueryClientProvider>
  );
}
```

## Two mistakes

| Anti-pattern | Why it hurts |
| --- | --- |
| **Server data in a Context** | No cache, invalidation, refetch or `isFetching`: React Query reimplemented badly. `04-state.md` names this anti-pattern. |
| **One Context for everything** (`AppContext` with session + locale + UI flags) | Every consumer re-renders on every change; untestable in isolation. One context per concern. |

## Testing

The provider is wiring, so **test-after** and optional
(`.claude/rules/05-testing.md`). What is worth a test is the throw:

```tsx
import { describe, it, expect, vi } from "vitest";
import { renderHook } from "@testing-library/react";
import { useAuth } from "./AuthProvider";

describe("useAuth", () => {
  it("throws when rendered outside the provider", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});

    expect(() => renderHook(() => useAuth())).toThrow(/inside <AuthProvider>/);
  });
});
```

Test a consumer inside the real provider with the repository mocked — never by
mocking `useAuth` itself (`.claude/rules/05-testing.md`, "Assert the behaviour,
not the call").
