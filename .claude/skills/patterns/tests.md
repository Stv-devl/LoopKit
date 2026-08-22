# Tests Patterns

## Imports

**Every test file starts with these.** The kit runs with `globals: false`
(`templates/tooling-config.md`), so `describe`, `it`, `expect`, `vi` and the
lifecycle hooks are **not** ambient — a file that omits the import fails on
`describe is not defined`, not on its assertions. The examples further down are
excerpts and do not repeat this header; a real file always carries it.

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor, renderHook, act } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { toServiceError } from "@/lib/result";
```

The jest-dom matchers (`toBeDisabled`, `toHaveTextContent`, `toBeInTheDocument`)
are **not** imported per file: the setup file registers them once on `expect`
(`templates/fixtures.md`).

## Mandatory vs optional

`.claude/rules/05-testing.md` makes **repository / services, mapper, utils and
hooks** mandatory, and components optional. The examples are ordered accordingly:
the mandatory layers first.

## Test-first vs test-after

The same rules file makes three layers **test-first** — `utils.ts`, `mapper.ts`,
`repository.ts` / `services.ts`. The first three sections below are therefore
written **before** the code they cover; everything from `React Query Hook`
onwards is written after. Read `05-testing.md` for the cycle, the freeze and the
scope; this file only shows the shapes.

Two consequences for how you write the code in those three sections:

- **The `it()` name is the spec.** `it('returns err(not_found) when the gateway
  finds no row')` — a sentence a non-developer could check. Written first, the
  test is the prompt the implementation is generated against. The rule holds in
  every section below, test-first or not: no `it('works')`, and no `should`
  padding a name that reads better without it.
- **Order the file business-value first**, edge cases last. Not the reverse,
  however tempting the edge cases are to enumerate.

Those three files are written by the **`test-writer` agent**, one per layer, at
the RED leg of that layer — and one layer is taken RED→GREEN before the next one
starts (`.claude/rules/05-testing.md`). Once written and validated they do not
move: a new case may be **appended**, an existing one is corrected only through
`.claude/.tdd-unfrozen`.

## Assert the behaviour, not the call

Applies to every example below.

```typescript
// tautology: proves the test called the code
expect(gateway.fetchAll).toHaveBeenCalledWith('u1');

// proves the behaviour
expect(result).toEqual({ success: true, data: [] });
```

`toHaveBeenCalled*` earns its place only for an effect with no return value and
no other observable trace. Never mock a pure function (`utils`, `mapper`), and
mock the layer directly below the one under test — never further.

## Repository / services (mandatory)

The repository is where `Result<T>` is produced. **Both branches must be
asserted** — a repository test that only covers the happy path proves nothing
about the boundary. Mock the gateway, not the data client.

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as gateway from './item.gateway';
import * as repository from './item.repository';

vi.mock('./item.gateway');

const ROW = { id: '1', name: 'Item 1', user_id: 'u1', created_at: '2024-01-01T00:00:00Z' };

describe('repository.getAll', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(console, 'error').mockImplementation(() => {}); // serviceError logs
  });

  it('returns mapped entities on success', async () => {
    vi.mocked(gateway.fetchAll).mockResolvedValue({ data: [ROW], error: null });

    const result = await repository.getAll();

    expect(result.success).toBe(true);
    // narrow before reading .data — the union is the point of Result<T>
    if (!result.success) throw new Error('expected success');
    expect(result.data[0]).toEqual({
      id: '1',
      name: 'Item 1',
      userId: 'u1',
      createdAt: new Date('2024-01-01T00:00:00Z'),
    });
  });

  it('returns a failure Result — never throws — when the gateway errors', async () => {
    vi.mocked(gateway.fetchAll).mockResolvedValue({ data: null, error: new Error('boom') });

    const result = await repository.getAll();

    expect(result.success).toBe(false);
    if (result.success) throw new Error('expected failure');
    // `db_error`, not `feature_not_found`: the CALL failed, so whether the row
    // exists is unknown. `feature_not_found` belongs to the `{ data: null,
    // error: null }` branch below (`templates/feature.md`).
    expect(result.error.code).toBe('db_error');
  });

  it('maps an empty payload to an empty list, not an error', async () => {
    vi.mocked(gateway.fetchAll).mockResolvedValue({ data: null, error: null });

    const result = await repository.getAll();

    expect(result).toEqual({ success: true, data: [] });
  });
});
```

## Mapper / utils (mandatory)

Pure functions: no mocks, no async, no React. The cheapest tests in the repo and
the ones that catch the most regressions.

```typescript
import { describe, it, expect } from 'vitest';
import { toEntity } from './item.mapper';

describe('toEntity', () => {
  it('converts snake_case columns to the domain shape', () => {
    expect(
      toEntity({ id: '1', name: 'A', user_id: 'u1', created_at: '2024-01-01T00:00:00Z' }),
    ).toEqual({ id: '1', name: 'A', userId: 'u1', createdAt: new Date('2024-01-01T00:00:00Z') });
  });

  it('parses the date into a Date, not a string', () => {
    const entity = toEntity({ id: '1', name: 'A', user_id: 'u1', created_at: '2024-01-01T00:00:00Z' });
    expect(entity.createdAt).toBeInstanceOf(Date);
  });
});
```

## React Query Hook (mandatory, with Result\<T\>)

Hooks call `repository.*` which returns `Result<T>`. Mock the repository, not the gateway.

> **The wrapper is imported, never rebuilt.** `createQueryWrapper` lives in
> `src/test/utils/render.tsx` (`templates/fixtures.md`) with the client factory
> it uses — retries off, `staleTime: 0` so a failure surfaces at once, and
> `gcTime: Infinity` so a seeded cache entry survives until the client is thrown
> away with the test. A wrapper rewritten in the test file is a
> second copy of that config, and the reason it exists — `client={new
> QueryClient()}` inline rebuilds the client on every re-render, throws the cache
> away and lets the query refetch forever — is already handled there.

```tsx
import { createQueryWrapper } from '@/test/utils/render';
import * as repository from '../services/item.repository';

describe('useItems', () => {
  beforeEach(() => vi.restoreAllMocks());

  it('returns the mapped items when the repository succeeds', async () => {
    vi.spyOn(repository, 'getAll').mockResolvedValue({
      success: true,
      data: [{ id: '1', name: 'Item 1', userId: 'u1', createdAt: new Date() }],
    });

    const { result } = renderHook(() => useItems(), { wrapper: createQueryWrapper() });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toHaveLength(1);
  });

  it('surfaces a repository failure as an error state', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(repository, 'getAll').mockResolvedValue({
      success: false,
      error: { code: 'not_found', message: 'Failed to fetch items' },
    });

    const { result } = renderHook(() => useItems(), { wrapper: createQueryWrapper() });

    await waitFor(() => expect(result.current.isError).toBe(true));
    // unwrap throws a ServiceFailure carrying the original ServiceError
    expect(toServiceError(result.current.error).code).toBe('not_found');
  });
});
```

> **Note**: For small features with a single `services.ts`, mock `services.*` instead of `repository.*`.
> `ServiceError` is `{ code, message, cause? }` — see `.claude/skills/templates/lib-core.md`.

## Mutation hook (mandatory too, and the assertion is the trap)

A mutation hook is `hooks.ts`, so `05-testing.md` makes it mandatory. The reflex
assertion — `expect(queryClient.invalidateQueries).toHaveBeenCalledWith(...)` —
is the tautology this file forbids two sections up: an invalidation **has** an
observable trace, so the carve-out for "an effect with no other trace" does not
apply. Assert the trace.

```tsx
import { createQueryWrapper } from '@/test/utils/render';
import { createTestQueryClient } from '@/test/utils/query-client';
import { itemKeys, useCreateItem } from './hooks';
import * as repository from '../services/item.repository';

describe('useCreateItem', () => {
  beforeEach(() => vi.restoreAllMocks());

  it('marks the lists stale so the next reader refetches them', async () => {
    const queryClient = createTestQueryClient();
    queryClient.setQueryData(itemKeys.lists(), []);
    vi.spyOn(repository, 'create').mockResolvedValue({
      success: true,
      data: { id: '2', name: 'Item 2', userId: 'u1', createdAt: new Date() },
    });

    const { result } = renderHook(() => useCreateItem(), {
      wrapper: createQueryWrapper(queryClient),
    });
    await act(async () => {
      result.current.mutate({ name: 'Item 2' });
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    // The behaviour: that cache entry is no longer trusted. Which React Query
    // call produced it is the implementation's business — this assertion
    // survives a rewrite from `invalidateQueries` to `resetQueries` and fails
    // the day the key is retyped one character differently.
    expect(queryClient.getQueryState(itemKeys.lists())?.isInvalidated).toBe(true);
  });

  it('surfaces a repository failure as an error state carrying the code', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(repository, 'create').mockResolvedValue({
      success: false,
      error: { code: 'validation_failed', message: 'Name already taken' },
    });

    const { result } = renderHook(() => useCreateItem(), {
      wrapper: createQueryWrapper(),
    });
    await act(async () => {
      result.current.mutate({ name: 'Item 2' });
    });

    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(toServiceError(result.current.error).code).toBe('validation_failed');
  });
});
```

> **Why the client is built in the test and passed in.** `createQueryWrapper()`
> makes its own when you don't — fine for a query. Here the assertion reads the
> cache, so the test needs the same instance the hook writes to. A hook that
> imports the app singleton from `@/lib/queryClient` instead of calling
> `useQueryClient()` defeats exactly this, silently: the test passes on an
> injected client nobody wrote to. `templates/lib-core.md` names that import as
> forbidden outside the composition root.

## Form

```tsx
describe('LoginForm', () => {
  it('submits the typed values when the form is valid', async () => {
    const onSubmit = vi.fn();
    render(<LoginForm onSubmit={onSubmit} />);

    await userEvent.type(screen.getByLabelText(/email/i), 'test@example.com');
    await userEvent.type(screen.getByLabelText(/password/i), 'password123');
    await userEvent.click(screen.getByRole('button', { name: /submit/i }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({
      email: 'test@example.com',
      password: 'password123',
    }));
  });

  it('shows a validation message when the email is malformed', async () => {
    render(<LoginForm onSubmit={vi.fn()} />);

    await userEvent.type(screen.getByLabelText(/email/i), 'invalid');
    await userEvent.click(screen.getByRole('button', { name: /submit/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/email invalide/i);
  });
});
```

## Component (optional)

```tsx
describe('Button', () => {
  it('calls onClick when the user clicks it', async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Click me</Button>);

    await userEvent.click(screen.getByRole('button', { name: /click me/i }));

    expect(onClick).toHaveBeenCalledOnce();
  });

  it('is disabled while loading', () => {
    render(<Button loading>Submit</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

## Gateway (mandatory as soon as it builds a query)

The gateway is the only layer that **is** the transport, so it is the only one
mocked at the network: **MSW**, real client running, request inspectable.
Full pattern → `.claude/skills/patterns/msw.md`.

```typescript
import { describe, it, expect } from 'vitest';
import { http, HttpResponse } from 'msw';
import { server } from '@/test/msw/server';
import { fetchAll } from './item.gateway';

const ROW = { id: '1', name: 'Item 1', user_id: 'u1', created_at: '2024-01-01T00:00:00Z' };

it('returns the rows the API sends, untouched', async () => {
  server.use(http.get('*/items', () => HttpResponse.json([ROW])));

  const { data, error } = await fetchAll('u1');

  expect(error).toBeNull();
  expect(data).toEqual([ROW]);
});

it('surfaces a server error instead of throwing', async () => {
  server.use(http.get('*/items', () => new HttpResponse(null, { status: 500 })));

  const { data, error } = await fetchAll('u1');

  expect(data).toBeNull();
  expect(error).not.toBeNull();
});
```

> **Do not hand-roll a chainable client fake** (`from().select().eq()` with
> `mockReturnThis()`). It accepts any chain, so it survives a change of table,
> filter or ordering — it re-states the gateway instead of testing it. It stays
> the answer only for a transport MSW cannot reach (realtime/WebSocket):
> `templates/fixtures.md`.

## Priority queries

```typescript
// 1. getByRole (accessibility)
screen.getByRole("button", { name: /submit/i });
screen.getByRole("textbox", { name: /email/i });

// 2. getByLabelText (forms)
screen.getByLabelText(/password/i);

// 3. getByText (content)
screen.getByText(/bienvenue/i);

// 4. findBy* (async)
await screen.findByText(/success/i);

// 5. getByTestId (last resort)
screen.getByTestId("custom-element");
```

## Async

```typescript
// waitFor for assertions
await waitFor(() => expect(result.current.isSuccess).toBe(true));

// findBy for elements
const element = await screen.findByText(/loaded/i);

// act for manual state updates
await act(async () => {
  result.current.mutate(data);
});
```
