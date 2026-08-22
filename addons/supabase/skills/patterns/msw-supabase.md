# MSW × Supabase — handlers for `supabase-js`

Read `.claude/skills/patterns/msw.md` first: it decides **where** MSW belongs
(`gateway.ts` and the E2E mock layer, nowhere else). This file only covers what
changes because the client is `supabase-js`.

## Prove the interception before writing any handler

`supabase-js` does not always go through the `fetch` MSW patched. There is an
[open, unresolved issue](https://github.com/supabase/supabase/issues/27656) where
the SDK's requests never reach the handlers, and it is labelled `external-issue`
— nobody is going to fix it for you.

The cause is a captured reference: if the SDK resolved a `fetch` at module load,
MSW patching `globalThis.fetch` afterwards changes nothing. The fix is to make
the client resolve it at **call** time:

```typescript
// src/lib/supabase.ts
export const supabase = createClient<Database>(url, anonKey, {
  // Resolved per call, so whatever patched the global (MSW, a proxy) is used.
  global: { fetch: (...args) => fetch(...args) },
});
```

**Write this one test before anything else.** If it fails, MSW is not an option
on this repo and the fallback below applies — better to know in ten minutes than
after twenty handlers.

```typescript
it("routes supabase-js through the mock layer", async () => {
  server.use(http.get("*/rest/v1/items*", () => HttpResponse.json([{ id: "1" }])));

  const { data } = await supabase.from("items").select("*");

  expect(data).toEqual([{ id: "1" }]);   // red here = the SDK bypassed MSW
});
```

**Fallback if it stays red**: keep the stubbed client for `gateway.ts`
(`templates/fixtures.md`) and put the real coverage in E2E against a disposable
local stack (`supabase start`). Say so in `05-testing.md` rather than leaving the
gateway silently untested.

## The URL shapes

`supabase-js` is HTTP for everything except realtime. Handlers match the path,
with a `*` prefix so the project URL does not have to be hardcoded:

| Call | Path to match |
| --- | --- |
| `.from('items').select()` | `*/rest/v1/items*` |
| insert / update / delete on the same table | same path, `http.post` / `http.patch` / `http.delete` |
| `.rpc('fn')` | `*/rest/v1/rpc/fn` |
| `auth.signInWithPassword()` | `*/auth/v1/token*` |
| `auth.getUser()` | `*/auth/v1/user` |
| Storage | `*/storage/v1/object/*` |
| **Realtime** | **`wss://…/realtime/v1/websocket` — out of scope** |

The query lives in the **search params**, not the path: `select`, `order`, and
one param per filter (`?id=eq.1`). That is what makes a handler able to prove the
query the gateway actually built:

```typescript
server.use(
  http.get("*/rest/v1/items*", ({ request }) => {
    const url = new URL(request.url);
    expect(url.searchParams.get("user_id")).toBe("eq.u1");   // the real filter
    return HttpResponse.json([ROW]);
  }),
);
```

## Three shapes to get right

- **`.single()` / `.maybeSingle()`** send `Accept: application/vnd.pgrst.object+json`
  and expect **an object, not an array**. Return `HttpResponse.json(ROW)`; a
  one-element array fails in a way that reads like a mapper bug.
- **The error shape is PostgREST's**, not a generic message:
  `HttpResponse.json({ message, details, hint, code }, { status: 400 })`.
  `supabase-js` turns it into `{ data: null, error }`, which is exactly what the
  repository maps to `err(...)`. Returning a bare 500 with no body tests a path
  your code never sees in production.
- **`.select('*', { count: 'exact' })`** reads the count from the `Content-Range`
  response header, not the body: `{ headers: { "Content-Range": "0-0/1" } }`.

## Realtime does not go through this

`04-state.md` routes the subscription to `gateway.ts`, and it is a WebSocket
speaking Realtime's own protocol. Reimplementing it costs far more than it
returns. Those gateway functions stay on a stubbed channel
(`templates/fixtures.md` ships `channel: vi.fn(...)`), and the real proof is an
E2E spec — or nothing, stated as nothing.

## RLS is not tested here

MSW replaces the server. Every authorization answer it gives is one you wrote
yourself, so **a green gateway suite says nothing about RLS**. The barrier is
proved where `06-database.md` and `patterns/rls.md` say, against a real database.
Never let a mocked test stand in for a policy test — that is how a table ships
world-readable with a full green suite.
