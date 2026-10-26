# MSW — the mock layer, and where it belongs

MSW intercepts the **network**, so the real data client runs: its URL building,
its headers, its error shape. That is worth exactly two things in this repo, and
it is actively wrong everywhere else.

| Layer | Mock with | Why |
| --- | --- | --- |
| `utils.ts`, `mapper.ts` | nothing | pure functions, no dependency to fake |
| `repository.ts` / `services.ts` | `vi.mock('./x.gateway')` | the seam is a **module boundary**; the repository does not know HTTP exists, testing it through HTTP couples it to a transport it never sees |
| `hooks.ts` | `vi.mock` on the repository | same reason, one layer up |
| **`gateway.ts`** | **MSW** | the only layer that *is* the transport; a hand-rolled client mock proves nothing about the request that goes out |
| **E2E, on a read-only surface** | **MSW** (`@msw/playwright`) | the only honest way to run a flow that must mutate |

> "`vi.mock` is brittle, use MSW" is aimed at codebases that call `fetch` from a
> component. This repo has a data layer; do not migrate the repository tests.

## Can MSW even reach your client?

Read the **data client table** in `.claude/rules/01-stack.md` (filled by the
addon). If it is still a `FILL`, stop and fill it.

| Client declared there | MSW |
| --- | --- |
| REST / GraphQL over `fetch` (FastAPI addon, generated API client) | yes, directly |
| A BaaS SDK built on `fetch` (Supabase addon) | yes, but handlers match the SDK's URL shapes → `addons/supabase/skills/patterns/msw-supabase.md` |
| A realtime subscription (WebSocket) | **no** — keep those gateway functions on a stubbed client and prove them in E2E |

## Setup

`pnpm add -D msw`

```typescript
// src/test/msw/handlers.ts — the default world: the happy path, nothing else
import { http, HttpResponse } from "msw";

export const handlers = [
  http.get("*/items", () =>
    HttpResponse.json([
      { id: "1", name: "Item 1", user_id: "u1", created_at: "2024-01-01T00:00:00Z" },
    ]),
  ),
];
```

```typescript
// src/test/msw/server.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";

export const server = setupServer(...handlers);
```

The setup file is declared once, in `templates/fixtures.md`; these lines are
**appended** to it, never a second file (it would silently overwrite the factory
reset and the Testing Library cleanup).

```typescript
// src/test/setup.ts — APPENDED to the file `templates/fixtures.md` declares.
// Import `afterAll` and `beforeAll` ONLY: that file already imports `afterEach`.
// Re-importing it is `Identifier 'afterEach' has already been declared`, a
// syntax error in `setupFiles` that errors EVERY test before collection.
import { afterAll, beforeAll } from "vitest";
import { server } from "./msw/server";

// `error`, never `bypass`: under `bypass` an undeclared request silently reaches
// the real backend and the suite looks mocked while it is not.
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers()); // per-test overrides never leak
afterAll(() => server.close());
```

Without `resetHandlers()`, a 500 declared in one test poisons every later one in
file order, a flake that is very hard to read back.

## Gateway test

Assert on what came back through the real client; let failure cases come from
the network.

```typescript
import { describe, it, expect } from "vitest";
import { http, HttpResponse } from "msw";
import { server } from "@/test/msw/server";
import { fetchAll } from "./item.gateway";

describe("item.gateway.fetchAll", () => {
  it("returns the rows the API sends, untouched", async () => {
    // `fetchAll()` takes no argument in `templates/feature.md` (the backend
    // scopes by session). The filtered variant `fetchAll(userId)` is shown
    // because a parameterless gateway builds no query, and `05-testing.md` only
    // makes the gateway mandatory to test once it does.
    const { data, error } = await fetchAll("u1");

    expect(error).toBeNull();
    expect(data).toEqual([
      { id: "1", name: "Item 1", user_id: "u1", created_at: "2024-01-01T00:00:00Z" },
    ]);
  });

  it("surfaces a server error instead of throwing", async () => {
    server.use(http.get("*/items", () => new HttpResponse(null, { status: 500 })));

    const { data, error } = await fetchAll("u1");

    expect(data).toBeNull();
    expect(error).not.toBeNull();
  });
});
```

No `toHaveBeenCalledWith`, no chained-mock bookkeeping: the gateway returns raw
rows (`.claude/rules/02-architecture.md`), that return value is the whole
contract, and mapping is the mapper's job. To assert the request itself (filter,
header, pagination), read it in the handler and return something that proves it:

```typescript
server.use(
  http.get("*/items", ({ request }) => {
    const url = new URL(request.url);
    return HttpResponse.json(url.searchParams.get("user") === "u1" ? [ROW] : []);
  }),
);
```

## The cost, stated up front

A handler directory is **a second source of truth about the API**. Three rules
keep it from drifting:

1. **`onUnhandledRequest: "error"`.** Non-negotiable.
2. **Default handlers are the happy path only.** Every failure, empty payload or
   edge case is a `server.use()` inside the test that needs it; a default
   handler returning an error makes every other test in the file lie.
3. **Handlers are written from the API contract**, not from what makes the test
   pass. Unknown response shape is a `/loop:research` question, not a guess.

## Not this

- Not on `repository.ts` / `services.ts` / `hooks.ts` — see the table.
- Not as the default for the whole E2E suite: a fully mocked E2E proves nothing
  about integration; it is for flows that would otherwise mutate real data
  (`.claude/skills/e2e-playwright/SKILL.md`, "Which backend does the suite hit?").
- Not `playwright-msw` for the browser side: the official package is
  `@msw/playwright`, which routes handlers through Playwright's `page.route()`.
