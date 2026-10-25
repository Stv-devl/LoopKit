# Guards Patterns (TanStack Router)

<!-- FILL: this page describes a concrete implementation — helper names, provider
     names, route paths. Rewrite them to match this repo, or implement this shape
     as-is. What must not change: `beforeLoad` protects a route, guard components
     only hide UI, and the real security barrier is server-side (see
     `.claude/rules/01-stack.md`), never the client. -->

> **Routing = TanStack Router** (file-based routes in `src/routes/`,
> `routeTree.gen.ts`). **No** `react-router-dom`, **no** `createBrowserRouter`.

Two levels of protection: **`beforeLoad`** in the route (canonical, blocks before
rendering) and a **guard component** (render-side, hides a sub-part of the UI,
never protects a whole route).

## 1. `beforeLoad` (recommended for protecting a route)

Helpers live in `@/lib/route-utils`: `requireAuth`, `handleAuthRedirect`,
`redirectIfAuthenticated`, `hasPasswordResetTokens`. They `throw redirect(...)`.

> **They never touch the data client, and `src/lib/` imports no feature.** The
> auth reader is **injected**: `route-utils` takes it from the router context,
> and `src/routes/__root.tsx` (composition root, may import both) wires the auth
> feature's repository in (`.claude/rules/02-architecture.md`).
> `enforce-architecture.py` denies the write otherwise.

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
 * `returnTo` is attacker-controlled (it arrives in the URL): navigating to it
 * unchecked is an open redirect. Accepts one shape only, a path starting with a
 * single `/`. The rejections that matter are not obvious:
 * - `//evil.example` is protocol-relative: a naive `startsWith("/")` lets it through;
 * - `/\evil.example` is normalised to `//` by some browsers;
 * - `https://…`, `javascript:…` and any other scheme.
 */
export function isValidInternalRedirect(value: unknown): value is string {
  if (typeof value !== "string" || value.length === 0) return false;
  if (!value.startsWith("/")) return false;
  if (value.startsWith("//") || value.startsWith("/\\")) return false;
  return true;
}

/** The safe destination for a `returnTo`; callers never read `returnTo` directly. */
export function safeRedirectTarget(
  returnTo: unknown,
  fallback: string,
): string {
  return isValidInternalRedirect(returnTo) ? returnTo : fallback;
}

/** Throws a redirect to the login route unless a valid session exists. */
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
> `isValidInternalRedirect` is a security decision per branch. Test the
> rejections, not just the happy path: `//evil.example` is the case a
> hand-written check gets wrong.

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
    await requireAuth(context, location);
  },
  component: () => (
    <AppShell>
      <Outlet />
    </AppShell>
  ),
});
```

> `AppShell` and `PublicLayout` are the landmark skeleton (skip link, `<header>`/
> `<nav>`, single `<main>`, `<footer>`) and are wired here, once; pages rendered
> through `<Outlet />` return a fragment starting at their `<h1>`. Shape:
> `.claude/skills/templates/page.md`.

### Guest-only route (login / signup)

```tsx
// src/routes/auth/login.tsx
import { createFileRoute } from '@tanstack/react-router';
import { z } from 'zod';
import { PublicLayout } from '@/components/layouts/PublicLayout';
import { LoginPage } from '@/features/auth/pages/LoginPage'; // direct, no barrel
import { handleAuthRedirect } from '@/lib/route-utils';

// Without `validateSearch`, `Route.useSearch()` has no typed `returnTo` and the
// `useLoginRedirect` hook below does not compile.
const loginSearchSchema = z.object({
  returnTo: z.string().optional(),
});

export const Route = createFileRoute('/auth/login')({
  validateSearch: loginSearchSchema,
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

> Validating the **shape** (Zod: a string or nothing) and the **destination**
> (`isValidInternalRedirect`: stays on this origin) are two different jobs.
> `z.string().url()` would be actively wrong: it accepts `https://evil.example`
> and rejects `/app/items`.

## 2. Guard component (render fallback)

Based on `useAuth()` from `@/providers/AuthProvider` (shape in
`patterns/context.md`) and `<State>` (`feedback.md`). `AuthProvider` lives in
`src/providers/` (wiring): it may import the `auth` repository, never the data
client. The guards sit in `src/components/` (shared leaf): they may depend on the
provider, never on a feature.

> **`redirectTo` is typed `LinkProps['to']`, not `string`.** TanStack Router types
> `to` against the generated route tree, so a plain `string` does not compile
> (`pnpm typecheck` is a `/loop:ship` gate), and a typo in a default fails the
> build instead of 404ing at runtime.

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
    // `search`, not `state`. `location.pathname` is in-app by construction, so
    // it needs no validation, unlike a `returnTo` read back out of the URL.
    return <Navigate to={redirectTo} search={{ returnTo: location.pathname }} replace />;
  }
  return <>{children}</>;
}
```

`GuestGuard` is the mirror: same imports and props (`redirectTo` default
`'/app'`), same loading branch, `if (isAuthenticated) return <Navigate
to={redirectTo} replace />`, otherwise the children.

## Redirect after login (`returnTo`)

The `returnTo` search param is attacker-controlled and must pass
`isValidInternalRedirect` before anything navigates to it:

```typescript
import { useNavigate } from '@tanstack/react-router';
import { Route } from '@/routes/auth/login'; // typed route
import { safeRedirectTarget } from '@/lib/route-utils';

function useLoginRedirect(): () => void {
  const navigate = useNavigate();
  const { returnTo } = Route.useSearch();

  return () => {
    // NEVER `returnTo ?? '/app'`: that is the open redirect. The fallback must
    // be reached when `returnTo` is present-but-hostile, not only when absent.
    navigate({ to: safeRedirectTarget(returnTo, '/app'), replace: true });
  };
}
```

`handleAuthRedirect` applies the same check when it sends an already-authenticated
visitor to `returnTo` from `beforeLoad`.

## Notes

- **Prefer `beforeLoad`**: the unauthorized user never reaches the component.
- `requireAuth` already handles token expiration (auto refresh) and the
  unconfirmed email (redirects to `/auth/email-sent`). Do not duplicate it.
- **No `RoleGuard`** by default. If roles are added, read them from the
  profile/session; never make a security decision from a client-side claim. The
  real barrier is server-side (`.claude/rules/01-stack.md`).
