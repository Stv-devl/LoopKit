# Test Fixtures & Mocks

## Structure

```
src/test/
├── setup.ts              # Global Vitest setup
├── mocks/
│   └── client.ts         # Mock data client
├── factories/
│   ├── index.ts          # Exports + resetAll
│   ├── user.factory.ts
│   └── item.factory.ts
├── msw/
│   ├── handlers.ts       # the default world (patterns/msw.md)
│   └── server.ts         # setupServer, registered in the setup file
└── utils/
    ├── render.tsx         # renderWithProviders + createQueryWrapper
    └── query-client.ts    # createTestQueryClient
```

## Data Factory

```typescript
// src/test/factories/user.factory.ts
import type { User } from "@/features/users/types/types";

let counter = 0;

const defaults = (): User => ({
  id: `user-${++counter}`,
  email: `user${counter}@test.local`,
  createdAt: new Date("2024-01-01T00:00:00Z"),
});

export const userFactory = {
  build: (overrides: Partial<User> = {}): User => ({
    ...defaults(),
    ...overrides,
  }),

  buildMany: (count: number, overrides: Partial<User> = {}): User[] =>
    Array.from({ length: count }, () => userFactory.build(overrides)),
};

export const resetUserFactory = (): void => {
  counter = 0;
};
```

## Centralized index

```typescript
// src/test/factories/index.ts
export { userFactory, resetUserFactory } from "./user.factory";
export { itemFactory, resetItemFactory } from "./item.factory";

export const resetAllFactories = (): void => {
  resetUserFactory();
  resetItemFactory();
};
```

## Mock the data client — last resort only

> **Read this before copying the block below.** It fakes the client's fluent API,
> which means it **re-states the gateway instead of testing it**: `mockReturnThis()`
> accepts any chain, so it stays green when the query changes table, filter or
> ordering. It certifies a request nobody checked.
>
> The default for `gateway.ts` is **MSW** — the real client runs, only the network
> is mocked, and the query it built is inspectable (`patterns/msw.md`).
>
> This stub is still the right answer for exactly two things:
>
> - transports MSW cannot reach — a **realtime/WebSocket** subscription
>   (`channel` below), which `04-state.md` routes to the gateway;
> - a client whose SDK provably bypasses MSW's interception (see the smoke test
>   in `msw-supabase.md`) — in which case say so in `05-testing.md` instead of
>   leaving the layer silently untested.

<!-- FILL: shape this like the client declared in `.claude/rules/01-stack.md`.
     The example below mimics a chainable query-builder SDK; a fetch-based
     client mocks with a single `vi.fn()` per verb instead. -->

```typescript
// src/test/mocks/client.ts
import { vi } from "vitest";

export const createMockClient = () => ({
  from: vi.fn(() => ({
    select: vi.fn().mockReturnThis(),
    insert: vi.fn().mockReturnThis(),
    update: vi.fn().mockReturnThis(),
    delete: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    single: vi.fn().mockResolvedValue({ data: null, error: null }),
  })),
  auth: {
    getUser: vi.fn().mockResolvedValue({ data: { user: null }, error: null }),
    getSession: vi
      .fn()
      .mockResolvedValue({ data: { session: null }, error: null }),
    signOut: vi.fn().mockResolvedValue({ error: null }),
  },
  channel: vi.fn(() => ({
    on: vi.fn().mockReturnThis(),
    subscribe: vi.fn(),
    unsubscribe: vi.fn(),
  })),
});

// Usage
vi.mock("@/lib/client", () => ({
  client: createMockClient(),
}));
```

## Test QueryClient

```typescript
// src/test/utils/query-client.ts
import { QueryClient } from "@tanstack/react-query";

export const createTestQueryClient = (): QueryClient =>
  new QueryClient({
    defaultOptions: {
      // `gcTime: Infinity`, not 0. Isolation comes from building a fresh
      // client per test, never from the garbage collector: with `gcTime: 0` any
      // entry without an observer is dropped on the next tick, so a test that
      // seeds the cache (`setQueryData`) and then awaits a render finds it gone
      // — `onMutate` reads `previous === undefined`, the optimistic merge does
      // nothing, and the failure points at code that is correct.
      queries: { retry: false, gcTime: Infinity, staleTime: 0 },
      mutations: { retry: false },
    },
  });
```

## Render with Providers

> **Routing = TanStack Router**, not `react-router-dom`. The test wrapper embeds
> **only** the `QueryClientProvider`. For a component that consumes the router
> (`Navigate`, `useNavigate`, `useLocation`, `Link`), **mock** `@tanstack/react-router`
> per test (see below) — there is no router provider in the tests.

```tsx
// src/test/utils/render.tsx
import { QueryClientProvider, type QueryClient } from '@tanstack/react-query';
import { render, type RenderResult } from '@testing-library/react';
import { createTestQueryClient } from './query-client';

interface RenderOptions {
  queryClient?: QueryClient;
}

export const renderWithProviders = (
  ui: React.ReactElement,
  options: RenderOptions = {},
): RenderResult & { queryClient: QueryClient } => {
  const { queryClient = createTestQueryClient() } = options;

  // `wrapper`, never a provider wrapped around `ui` by hand: RTL re-applies the
  // **wrapper option** on `rerender`, and nothing else. Inlining the provider
  // means the second render has no client in context and `useQuery` throws
  // "No QueryClient set" — a failure with no relation to the code under test.
  return {
    ...render(ui, { wrapper: createQueryWrapper(queryClient) }),
    queryClient,
  };
};

/**
 * The same providers for `renderHook` — the hook tests of `hooks.ts`
 * (`patterns/tests.md`), which render no UI.
 *
 * The client is built **once, here, outside the returned component**: writing
 * `client={new QueryClient()}` inline builds a fresh one on every re-render,
 * throwing the cache away each time and letting the query refetch forever.
 */
export const createQueryWrapper = (
  queryClient: QueryClient = createTestQueryClient(),
): (({ children }: { children: React.ReactNode }) => React.ReactElement) =>
  ({ children }) => (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
```

> **One helper, not one per test file.** These three are the whole test-provider
> surface — `createTestQueryClient`, `renderWithProviders`, `createQueryWrapper`.
> A test file that rebuilds its own wrapper is a second copy of a config that
> already exists (`retry: false`, `gcTime: Infinity`, `staleTime: 0`), and it is
> the copy that drifts.

### Component that depends on the router → mock TanStack Router

```tsx
import { vi } from 'vitest';

// Stub the router APIs used by the component under test
vi.mock('@tanstack/react-router', () => ({
  Navigate: ({ to }: { to: string }) => <div data-testid="navigate" data-to={to} />,
  useLocation: () => ({ pathname: '/app/dashboard' }),
  useNavigate: () => vi.fn(),
  Link: ({ children, to }: { children: React.ReactNode; to: string }) => (
    <a href={to}>{children}</a>
  ),
}));
```

## Global setup — the single `src/test/setup.ts`

**This file is the only declaration of `src/test/setup.ts`.** It is loaded by
`setupFiles` in the `test` key of **`vite.config.ts`**
(`templates/tooling-config.md` — never a separate `vitest.config.ts`, which
replaces `vite.config.ts` instead of merging it), and there is
exactly one of it: `patterns/msw.md` adds its three lines *to this file* rather
than declaring a second one. Two setup files is not a merge conflict, it is a
silent overwrite — whichever agent scaffolds last wins, and the loser's
`cleanup()` or `server.listen()` simply stops happening.

```typescript
// src/test/setup.ts
import { afterEach, beforeEach } from "vitest";
import { cleanup } from "@testing-library/react";
// Registers toBeInTheDocument / toBeDisabled / toHaveTextContent on `expect`.
// Without this line those matchers do not exist, and a correct test fails with
// "expect(...).toBeDisabled is not a function" — see `patterns/tests.md`.
// `pnpm add -D @testing-library/jest-dom`
import "@testing-library/jest-dom/vitest";
import { resetAllFactories } from "./factories";

beforeEach(() => {
  resetAllFactories();
});

afterEach(() => {
  cleanup();
});
```

`cleanup()` is explicit here because the kit runs **without `globals`**
(`templates/tooling-config.md`): Testing Library only auto-cleans when it can
see a global `afterEach`, which is exactly what turning globals off removes.

### The MSW block, when MSW is installed

Appended to the same file — never a second setup file. Why
`onUnhandledRequest: "error"` rather than `"bypass"`, and why `resetHandlers`
matters, are in `patterns/msw.md`.

```typescript
// src/test/setup.ts — continued
// `afterAll` and `beforeAll` ONLY: `afterEach` is already imported at the top of
// the file. Re-importing it here is `Identifier 'afterEach' has already been
// declared` — a syntax error in `setupFiles`, which means EVERY test in the
// project errors before collection. The block reads as self-contained and is
// not; it is a continuation, and this line is where that shows.
import { afterAll, beforeAll } from "vitest";
import { server } from "./msw/server";

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

## Usage

```typescript
import { userFactory, resetUserFactory } from "@/test/factories";

beforeEach(() => {
  resetUserFactory();
});

it("displays the user email", () => {
  const user = userFactory.build({ email: "custom@test.com" });
  // ...
});

it("lists every user returned", () => {
  const users = userFactory.buildMany(5);
  // ...
});
```
