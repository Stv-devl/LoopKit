# Guards Patterns (TanStack Router)

<!-- FILL: this page describes a concrete implementation — helper names, provider
     names, route paths. Rewrite them to match this repo, or implement this shape
     as-is. What must not change: `beforeLoad` protects a route, guard components
     only hide UI, and the real security barrier is server-side (see
     `.claude/rules/01-stack.md`), never the client. -->

> **Routing = TanStack Router** (`@tanstack/react-router`, file-based routes in `src/routes/`,
> `routeTree.gen.ts`). **No** `react-router-dom`, **no** `createBrowserRouter`.

Two levels of protection coexist:

1. **`beforeLoad` in the route** (canonical) — blocks **before** rendering, ideal for auth.
2. **Guard component** (`<AuthGuard>` / `<GuestGuard>`) — render-side fallback, based on
   `useAuth()`. Useful to hide a sub-part of the UI, not to protect a whole route.

## 1. `beforeLoad` (recommended for protecting a route)

The helpers live in `@/lib/route-utils`: `requireAuth`, `handleAuthRedirect`,
`redirectIfAuthenticated`, `hasPasswordResetTokens`. They read the session via
the **auth feature's repository** and `throw redirect(...)`.

> **They never touch the data client.** `route-utils` sits in `src/lib/`, above
> the data layer: it calls `authRepository.getSession()`, which returns
> `Result<Session | null>`. The only file allowed to hold the client instance is
> the composition root (`src/routes/__root.tsx` / `src/main.tsx`) — see the
> "composition root" table in `.claude/rules/02-architecture.md`.
> `enforce-architecture.py` denies the write otherwise.
>
> Because `src/lib/` must not depend on a feature either, the auth reader is
> **injected**: `route-utils` takes it as a parameter (or reads it from the router
> context), and `__root.tsx` — which may import both — wires the two together.

```typescript
// src/lib/route-utils.ts — no client import, no feature import
import { redirect } from "@tanstack/react-router";
import type { Result } from "@/lib/result";

export interface SessionReader {
  getSession: () => Promise<Result<{ userId: string } | null>>;
}

/** Router context, built in `__root.tsx`. */
export interface RouterContext {
  auth: SessionReader;
  queryClient: import("@tanstack/react-query").QueryClient;
}

/**
 * Whether a `returnTo` value is a safe in-app destination.
 *
 * `returnTo` is attacker-controlled: it arrives in the URL, so anyone can send
 * a victim to `/auth/login?returnTo=https://evil.example`. Navigating to it
 * unchecked is an open redirect — the victim lands on a copy of the login page
 * having crossed a domain they trusted.
 *
 * Accepts one shape only: a path starting with a single `/`. Everything else is
 * rejected, and the three rejections that matter are not obvious:
 * - `//evil.example` is **protocol-relative** — a browser reads it as a full
 *   URL, so a naive `startsWith("/")` check lets it straight through;
 * - `/\evil.example` is normalised to `//` by some browsers;
 * - `https://…`, `javascript:…` and any other scheme.
 */
export function isValidInternalRedirect(value: unknown): value is string {
  if (typeof value !== "string" || value.length === 0) return false;
  if (!value.startsWith("/")) return false;
  // Rejects `//host` and `/\host` — both leave the origin.
  if (value.startsWith("//") || value.startsWith("/\\")) return false;
  return true;
}

/**
 * The safe destination for a `returnTo`, falling back when it is missing or
 * hostile. Callers use this instead of reading `returnTo` directly.
 */
export function safeRedirectTarget(
  returnTo: unknown,
  fallback: string,
): string {
  return isValidInternalRedirect(returnTo) ? returnTo : fallback;
}

/**
 * Throws a redirect to the login route unless a valid session exists.
 */
export async function requireAuth(
  context: RouterContext,
  location: { href: string },
): Promise<void> {
  const result = await context.auth.getSession();
  if (!result.success || !result.data) {
    throw redirect({ to: "/auth/login", search: { returnTo: location.href } });
  }
}
```

> **`route-utils.ts` is inside the coverage floor** (`05-testing.md`) and
> `isValidInternalRedirect` is exactly the kind of function it exists for: four
> branches, each one a security decision. Test the rejections, not just the happy
> path — `//evil.example` is the case a hand-written check gets wrong.

```tsx
// src/routes/__root.tsx — the composition root: the ONE place that wires the
// concrete repository into the abstract context.
import { createRootRouteWithContext } from "@tanstack/react-router";
import type { RouterContext } from "@/lib/route-utils";

export const Route = createRootRouteWithContext<RouterContext>()({
  component: RootLayout,
});
```

### Protected route

```tsx
// src/routes/app.tsx
import { createFileRoute, Outlet, redirect } from '@tanstack/react-router';
import { AppShell } from '@/components/layouts/AppShell';
import { requireAuth, hasPasswordResetTokens } from '@/lib/route-utils';

export const Route = createFileRoute('/app')({
  beforeLoad: async ({ context, location }) => {
    if (hasPasswordResetTokens()) {
      throw redirect({ to: '/auth/reset' });
    }
    // Validates session + expiration (auto refresh) + confirmed email, otherwise throw redirect
    await requireAuth(context, location);
  },
  component: () => (
    <AppShell>
      <Outlet />
    </AppShell>
  ),
});
```

> **`AppShell` and `PublicLayout` are the landmark skeleton**, and this is the
> one place they are wired: they carry the skip link, the `<header>`/`<nav>`,
> the single `<main>` and the `<footer>`, so the pages rendered through
> `<Outlet />` return a fragment starting at their `<h1>`. Their shape is
> `.claude/skills/templates/page.md`.

### Guest-only route (login / signup)

```tsx
// src/routes/auth/login.tsx
import { createFileRoute } from '@tanstack/react-router';
import { z } from 'zod';
import { PublicLayout } from '@/components/layouts/PublicLayout';
import { LoginPage } from '@/features/auth/pages/LoginPage'; // direct, no barrel
import { handleAuthRedirect } from '@/lib/route-utils';

// `validateSearch` is what makes `Route.useSearch()` return a typed `returnTo`.
// Without it the search params are not part of the route's type, and the
// `useLoginRedirect` hook below does not compile.
const loginSearchSchema = z.object({
  returnTo: z.string().optional(),
});

export const Route = createFileRoute('/auth/login')({
  validateSearch: loginSearchSchema,
  // Redirects the already-authenticated user to `returnTo` (validated) or `/app`
  beforeLoad: async ({ context, location }) => {
    await handleAuthRedirect(context, location);
  },
  component: () => (
    <PublicLayout>
      <LoginPage />
    </PublicLayout>
  ),
});
```

> Validating the **shape** here (a string or nothing) and the **destination** in
> `isValidInternalRedirect` are two different jobs. Zod says it is a string; only
> the redirect check says it is a string that stays on this origin. A schema of
> `z.string().url()` would be actively wrong — it would accept
> `https://evil.example` and reject `/app/items`.

> `context` comes from `createRootRouteWithContext<RouterContext>()` (see
> `src/routes/__root.tsx`): `{ auth, queryClient }` — an injected `SessionReader`,
> **not** the data client. `requireAuth` returns the valid session or
> `throw redirect({ to: '/auth/login', search: { returnTo } })`.

## 2. Guard component (render fallback)

Based on `useAuth()` from `@/providers/AuthProvider` (`{ isAuthenticated, isLoading, ... }`,
shape in `patterns/context.md`)
and the unified state component `<State>` (see `feedback.md`).

> `AuthProvider` lives in `src/providers/` — **wiring**, so it may import the
> `auth` feature's repository. It must not import the data client: reading a
> session is a repository call like any other. The guard components below sit in
> `src/components/`, which is shared **leaf** code and may therefore depend on the
> provider, never on a feature (`.claude/rules/02-architecture.md`).

> **`redirectTo` is typed `LinkProps['to']`, not `string`.** TanStack Router
> types `to` against the generated route tree, so a plain `string` does not
> compile — and `pnpm typecheck` is a `/ship` gate. Taking the router's own type
> also means a typo in a default value fails the build instead of producing a
> 404 at runtime.

```tsx
// src/components/guards/AuthGuard.tsx
import { Navigate, useLocation, type LinkProps } from '@tanstack/react-router';
import { State } from '@/components/states/State';
import { useAuth } from '@/providers/AuthProvider';

interface AuthGuardProps {
  children: React.ReactNode;
  redirectTo?: LinkProps['to'];
}

export function AuthGuard({
  children,
  redirectTo = '/auth/login',
}: AuthGuardProps): React.ReactElement {
  const { isAuthenticated, isLoading } = useAuth();
  const location = useLocation();

  if (isLoading) {
    return <State type="loading" message="Vérification de l'authentification..." />;
  }
  if (!isAuthenticated) {
    // TanStack Router: `search`, not `state`. `location.pathname` is in-app by
    // construction, so it needs no redirect validation — unlike a `returnTo`
    // read back out of the URL, which does.
    return <Navigate to={redirectTo} search={{ returnTo: location.pathname }} replace />;
  }
  return <>{children}</>;
}
```

```tsx
// src/components/guards/GuestGuard.tsx
import { Navigate, type LinkProps } from '@tanstack/react-router';
import { State } from '@/components/states/State';
import { useAuth } from '@/providers/AuthProvider';

interface GuestGuardProps {
  children: React.ReactNode;
  redirectTo?: LinkProps['to'];
}

export function GuestGuard({
  children,
  redirectTo = '/app',
}: GuestGuardProps): React.ReactElement {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return <State type="loading" message="Vérification de l'authentification..." />;
  }
  if (isAuthenticated) {
    return <Navigate to={redirectTo} replace />;
  }
  return <>{children}</>;
}
```

## Redirect after login (`returnTo`)

The `returnTo` travels through the **search param**, so it is attacker-controlled
and must pass `isValidInternalRedirect` before anything navigates to it. After a
successful login:

```typescript
import { useNavigate } from '@tanstack/react-router';
import { Route } from '@/routes/auth/login'; // typed route
import { safeRedirectTarget } from '@/lib/route-utils';

function useLoginRedirect(): () => void {
  const navigate = useNavigate();
  const { returnTo } = Route.useSearch();

  return () => {
    // NEVER `returnTo ?? '/app'` — that is the open redirect. The fallback has
    // to be reached when `returnTo` is present-but-hostile, not only when it is
    // absent, and `??` cannot express that.
    const to = safeRedirectTarget(returnTo, '/app');
    navigate({ to, replace: true });
  };
}
```

The same check belongs in `handleAuthRedirect`, which sends an
already-authenticated visitor to `returnTo` from `beforeLoad` — the identical
parameter, read on a path where no component is involved.

## Notes

- **Prefer `beforeLoad`** to protect a route: the unauthorized user never reaches
  the component. Guard components are for partial UI hiding.
- `requireAuth` already handles token expiration (auto refresh) and the unconfirmed email
  (redirects to `/auth/email-sent`). Do not duplicate this logic.
- **No `RoleGuard`** by default. If roles are added, read them from the
  profile/session — and never make a security decision from a client-side claim.
  The real barrier is server-side (`.claude/rules/01-stack.md`).
