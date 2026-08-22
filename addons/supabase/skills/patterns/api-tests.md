# API Tests (Edge Functions)

<!-- FILL: `example-*` are placeholder function names, and the `_shared/` helpers
     named here must exist in this repo before an agent imports them. Delete any
     section whose helper you did not implement — see addons/supabase/functions/. -->

> See `edge-function.md` and `edge-function-tests.md` for the basics.

Integration tests of a **Hono** function via `app.request(path, init)`. Native
Deno runner, `jsr:@std/assert` assertions.

> **Actual error shape**: `{ "error": "message" }` (string, flat). We test
> `body.error` directly — never `body.error.code` nor `body.error.requestId`.
> The `basePath('/<fn>')` is part of the path passed to `app.request`.

---

## Setup

```typescript
import { assertEquals, assertExists } from "jsr:@std/assert";

Deno.env.set("SUPABASE_URL", "http://localhost:54321");
Deno.env.set("SUPABASE_ANON_KEY", "test-anon-key");

const { app } = await import("./app.ts");
```

---

## CRUD

```typescript
Deno.test("GET / returns items for authenticated user", async () => {
  const res = await app.request("/example-api/items", {
    headers: { Authorization: "Bearer valid-token" },
  });
  assertEquals(res.status, 200);
  const data = await res.json();
  assertEquals(Array.isArray(data.items ?? data), true);
});

Deno.test("POST / creates item", async () => {
  const res = await app.request("/example-api/items", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer valid-token",
    },
    body: JSON.stringify({ name: "Test Item" }),
  });
  assertEquals(res.status, 201);
  const data = await res.json();
  assertExists(data.id);
});
```

---

## Errors (flat shape)

```typescript
Deno.test("GET / without auth returns 401", async () => {
  const res = await app.request("/example-api/items");
  assertEquals(res.status, 401);
  const body = await res.json();
  assertExists(body.error);
  assertEquals(typeof body.error, "string"); // no .code
});

Deno.test("POST / with invalid body returns 400", async () => {
  const res = await app.request("/example-api/items", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer valid-token",
    },
    body: JSON.stringify({ invalid: "data" }),
  });
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(typeof body.error, "string");
});

Deno.test("GET /nonexistent returns 404", async () => {
  const res = await app.request("/example-api/nonexistent");
  assertEquals(res.status, 404);
  const body = await res.json();
  assertExists(body.error);
});
```

---

## Rate limiting

Rate limiting is **not** a global `app.use()`: a handler manually calls
`checkRateLimit(req, endpoint, supabase, corsHeaders)`
(`_shared/middleware/rate-limiter.ts`), which returns a **429** with the headers
`X-RateLimit-*` + `Retry-After` when the quota is exceeded. So we only test the
429 and these headers for an endpoint that actually calls
`checkRateLimit`:

```typescript
Deno.test("returns 429 after exceeding limit", async () => {
  const requests = Array.from({ length: 25 }, () =>
    app.request("/<fn>/<rate-limited-endpoint>", {
      headers: { Authorization: "Bearer valid-token" },
    }),
  );
  const responses = await Promise.all(requests);
  const tooMany = responses.filter((r) => r.status === 429);
  assertEquals(tooMany.length > 0, true);
});

Deno.test("429 response carries rate limit headers", async () => {
  // on the 429 response returned by checkRateLimit
  const res = await app.request("/<fn>/<rate-limited-endpoint>", {
    headers: { Authorization: "Bearer valid-token" },
  });
  if (res.status === 429) {
    assertExists(res.headers.get("X-RateLimit-Limit"));
    assertExists(res.headers.get("Retry-After"));
  }
  await res.body?.cancel();
});
```

> Quotas live in `RATE_LIMITS[endpoint]` (`_shared/config/rate-limits.ts`).
> In tests without a Supabase client, `checkRateLimit` falls back to an in-memory counter.

---

## Commands

```bash
# From supabase/functions
deno test --allow-env --allow-net <fn>/tests/
deno task test:example-api
```
