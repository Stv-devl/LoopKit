# Context Patterns — the wiring layer

React Context is the narrowest mechanism of `.claude/rules/04-state.md`: what
comes from **outside the client** and is read across the whole tree — the
session, the locale, config injected at the composition root.

**Not the theme.** A theme is a preference the user owns and the client
persists, so it goes to Zustand, where `persist` already handles serialisation,
the boot-time read and versioning (`patterns/zustand.md`). Context and Zustand
split on the origin of the value, not on how widely it is read.

> **A provider is wiring** (`.claude/rules/02-architecture.md`): `src/providers/`
> may import a feature, which is exactly why the auth session lives here rather
> than in a shared hook. It reads through the feature's **repository** — never
> the data client, which `enforce-architecture.py` denies outside the data layer
> and the composition root.

## When Context, and when not

| Need | Mechanism |
| --- | --- |
| Locale, feature flags, injected config — set once, read everywhere | **Context** |
| The auth session, exposed as a feature-agnostic contract | **Context** (`AuthProvider`) |
| Server data (a list, an entity, anything fetched) | React Query — `patterns/react-query.md` |
| Shared UI state (a modal, a selection), and any persisted preference | Zustand — `patterns/zustand.md` |
| A filter, a sort, a page — anything shareable by link | Search params — `patterns/url-state.md` |
| State used by one subtree only | `useState`, passed as props |

**Context is not a state manager.** It has no selector: every consumer re-renders
when the value changes, whatever part of it they read. That is fine for a locale
or a session, which change once or twice in a visit, and wrong for anything that
changes on input. If you are reaching for Context to avoid prop drilling on data
that moves, the answer is Zustand — it has selectors, and that is the whole
difference.

## Shape

Two rules make the difference between a provider that helps and one that becomes
a dependency nobody can remove: the context holds a **contract**, not a feature,
and the hook **throws** outside its provider instead of returning a plausible
default.

```tsx
// src/providers/AuthProvider.tsx
import { createContext, use, useEffect, useState } from "react";
import * as authRepository from "@/features/auth/services/auth.repository";

interface AuthContextValue {
  userId: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}

// No default value. `undefined` is what lets the hook below tell "outside the
// provider" from "inside, not logged in" — a default object silently makes
// every un-wrapped component look logged out, and the bug surfaces as a
// redirect loop nobody can locate.
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
 * The auth session. Throws outside `<AuthProvider>` — a missing provider is a
 * wiring bug, and failing loudly at the first render beats every component
 * quietly behaving as logged out.
 */
export function useAuth(): AuthContextValue {
  const value = use(AuthContext);
  if (value === undefined) {
    throw new Error("useAuth must be used inside <AuthProvider>");
  }
  return value;
}
```

> **React 19: `<AuthContext>` is the provider.** `<AuthContext.Provider>` still
> works and is deprecated; the context object renders directly. Consumers read it
> with `use(AuthContext)` — `useContext` remains valid, `use` is the one that
> also accepts a promise and is what 19 documents. Same reasoning as
> `forwardRef` in `templates/component.md`: the stack pins 19
> (`.claude/rules/01-stack.md`), so the templates are written against 19.

## The contract is the point

`useAuth()` returns `{ userId, isAuthenticated, isLoading }` — **not** the
feature's `Session` entity, and not the repository. That is what lets
`src/components/guards/AuthGuard.tsx` depend on the provider without naming a
feature (`patterns/guards.md`): swap the `auth` feature underneath and no
component changes. A provider that re-exports its feature's types has moved the
coupling, not removed it.

## Composition

Providers are wired once, in one file, ordered outermost-first. A provider that
needs another one's value goes **inside** it.

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

`AuthProvider` sits inside `QueryClientProvider` because a repository call it
makes may end up cached; nothing above it needs the session.

## Two mistakes

| Anti-pattern | Why it hurts |
| --- | --- |
| **Server data in a Context** — fetching a list in a provider and handing it down | Context has no cache, no invalidation, no refetch, no `isFetching`. You end up reimplementing React Query badly, and `04-state.md` routes it to a hook — it names this exact anti-pattern. |
| **One Context for everything** — a single `AppContext` carrying the session + the locale + UI flags | Every consumer re-renders on every change, and the provider becomes impossible to test in isolation. One context per concern. |

## Testing

The provider is wiring, so it is **test-after** and optional
(`.claude/rules/05-testing.md`). What is worth a test is the throw:

```tsx
import { describe, it, expect, vi } from "vitest";
import { renderHook } from "@testing-library/react";
import { useAuth } from "./AuthProvider";

describe("useAuth", () => {
  it("throws when rendered outside the provider", () => {
    // The error is expected, so React's own console.error is silenced.
    vi.spyOn(console, "error").mockImplementation(() => {});

    expect(() => renderHook(() => useAuth())).toThrow(/inside <AuthProvider>/);
  });
});
```

A component that consumes the context is tested by rendering it inside the real
provider, with the repository mocked — never by mocking `useAuth` itself, which
proves only that the mock returns what it was told to
(`.claude/rules/05-testing.md`, "Assert the behaviour, not the call").
