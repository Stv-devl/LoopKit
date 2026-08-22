# Edge Function Tests

<!-- FILL: `example-*` are placeholder function names. What must not change:
     `deno test` is the runner, the error shape is flat, and business logic in a
     function is covered like any other business logic (`05-testing.md`). -->

> See `edge-function.md` for the main pattern (helpers, plain/Hono styles).

**Native Deno** runner (`deno test`). Two levels:

1. **Unit** (default) — test the exported pure logic (helpers, mappers,
   Zod schemas) without network or Supabase.
2. **App** — for a Hono function, exercise the routes via `app.request(path, init)`.

Assertions from `jsr:@std/assert` (+ `jsr:@std/testing/bdd` for
`describe`/`it`, `jsr:@std/testing/mock` for `stub`).

> **Actual error shape**: `{ "error": "message" }` (string, flat). The
> assertions test `body.error` directly — never `body.error.code` nor
> `body.error.requestId`.

---

## Structure

Tests are colocated or grouped in a `tests/` folder per function:

```
supabase/functions/
├── _shared/tests/shared.test.ts          # the infra helpers
├── example-api/tests/handlers.test.ts    # grouped
├── example-batch/tests/orchestrator.test.ts
└── example-worker/prompts/greeting.test.ts   # colocated
```

---

## Unit — pure logic (the default)

We test a helper exported from the function; if the logic is not exported, we
pin its contract locally rather than reaching into the handler.

```typescript
import { assertEquals } from "jsr:@std/assert";
import { describe, it } from "jsr:@std/testing/bdd";
import { resolveAssignment } from "../orchestrator.ts";

describe("resolveAssignment", () => {
  it("falls back when the LLM omitted the item", () => {
    const r = resolveAssignment(undefined, new Set(["dest-A"]), "fallback-id");
    assertEquals(r.folder_id, "fallback-id");
    assertEquals(r.confidence, 0);
  });

  it("keeps a valid high-confidence pick", () => {
    const r = resolveAssignment(
      { item_id: "l1", folder_id: "dest-A", confidence: 80, reason: "x" },
      new Set(["dest-A"]),
      "fallback-id",
    );
    assertEquals(r.folder_id, "dest-A");
  });
});
```

---

## Unit — Zod schema

```typescript
import { assertEquals } from "jsr:@std/assert";
import { createItemSchema } from "./schema.ts";

Deno.test("createItemSchema rejects missing name", () => {
  const result = createItemSchema.safeParse({ description: "no name" });
  assertEquals(result.success, false);
});

Deno.test("createItemSchema accepts valid input", () => {
  const result = createItemSchema.safeParse({ name: "Item" });
  assertEquals(result.success, true);
});
```

---

## App Hono — `app.request()`

For a Hono function (`example-api`, `example-api`). Import the `app` and send it
simulated requests. Mock the env before the import if the function reads them
at load time.

```typescript
import { assertEquals, assertExists } from "jsr:@std/assert";

Deno.env.set("SUPABASE_URL", "http://localhost:54321");
Deno.env.set("SUPABASE_ANON_KEY", "test-anon-key");

const { app } = await import("./app.ts");

Deno.test("GET /example-api/health returns ok", async () => {
  const res = await app.request("/example-api/health");
  assertEquals(res.status, 200);
});

Deno.test("POST /example-api without service role returns 401", async () => {
  const res = await app.request("/example-api/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  assertEquals(res.status, 401);
  const body = await res.json();
  assertExists(body.error); // string, flat shape
});

Deno.test("POST /example-api with invalid body returns 400", async () => {
  const res = await app.request("/example-api/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer service-role-key",
    },
    body: JSON.stringify({ bad: "data" }),
  });
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(typeof body.error, "string");
});
```

> The `basePath('/example-api')` is part of the path: `app.request("/example-api/...")`.

---

## Stubbing an existing module (`jsr:@std/testing/mock`)

When a handler calls a real module (e.g. `llm.ts`, a service), we `stub` it
instead of touching the network. Always `restore()` in a `finally`.

```typescript
import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";
import * as llm from "../llm.ts";

Deno.test("handler uses LLM output", async () => {
  const llmStub = stub(llm, "callJson", () =>
    Promise.resolve({ messages: ["accroche A"] }),
  );
  try {
    const out = await buildOpportunity(/* … */);
    assertEquals(out.messages.length, 1);
  } finally {
    llmStub.restore();
  }
});
```

---

## Webhook — assertions on the flat shape

```typescript
import { assertEquals, assertExists } from "jsr:@std/assert";

Deno.test("webhook without signature returns 401", async () => {
  const res = await app.request("/provider-webhook/", { method: "POST", body: "{}" });
  assertEquals(res.status, 401);
  const body = await res.json();
  assertExists(body.error);            // OK: string
  assertEquals(typeof body.error, "string");
  // NO body.error.code / body.error.requestId — the shape is flat
});
```

---

## Commands

<!-- FILL: replace the task names with this repo's real ones (`deno task` with
     no argument lists them). A gate cannot call a task that does not exist. -->

Declare one task per function in `supabase/functions/deno.json`, so a gate has a
name to call rather than a path to guess:

```jsonc
// supabase/functions/deno.json
{
  "tasks": {
    "test": "deno test --allow-env --allow-net",
    "test:shared": "deno test --allow-env --allow-net _shared/tests/",
    "test:example-api": "deno test --allow-env --allow-net example-api/tests/"
  }
}
```

```bash
# From supabase/functions
deno task test:example-api

# A specific file
deno test --allow-env --allow-net example-batch/tests/orchestrator.test.ts

# Everything
deno task test
```

> A test that only runs when a key is present (an integration block gated on
> `OPENAI_API_KEY`, say) is **skipped silently** without it. A green run proves
> nothing about the blocks that never executed — log which ones were skipped.

---

## Available assertions (`jsr:@std/assert`)

```typescript
import {
  assertEquals, assertNotEquals, assertExists, assertStrictEquals,
  assertThrows, assertRejects, assertMatch, assertArrayIncludes,
} from "jsr:@std/assert";
```
