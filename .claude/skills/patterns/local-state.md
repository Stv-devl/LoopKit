# Local State Patterns — `useState` and its boundary

The default mechanism of `.claude/rules/04-state.md`: state
used by **one component and its subtree**, that no other part of the app reads.
It needs no store, no provider and no cache.

This page is not about the API — `useState` has no surface worth documenting. It
is about the four decisions around it that the other four mechanisms make for
you, and that here you make yourself: where the state lives, when it stops being
state at all, when it stops being *local*, and how it resets.

## The boundary

| The value is… | Mechanism |
| --- | --- |
| Read by one component (and what it renders) | **`useState`** |
| Read by two siblings, or by a component three levels away | Lift to the nearest common parent — still `useState` |
| Read across unrelated branches of the tree (a modal opened from a header, a selection read by a toolbar and a list) | Zustand — `patterns/zustand.md` |
| A filter, a sort, a page — anything a user would share by link or expect to survive a refresh | Search params — `patterns/url-state.md` |
| Fetched | React Query — `patterns/react-query.md` |
| Set once at boot, read everywhere (session, locale) | Context — `patterns/context.md` |
| A persisted preference (theme, density) | Zustand + `persist` — `patterns/zustand.md` |

Before lifting at all, ask whether the value belongs in the **URL**: a filter or
a page number held in `useState` is lost on refresh and cannot be shared, and no
amount of lifting fixes that.

**Lift on the second reader, not on the first suspicion.** Moving state up costs
nothing to undo and is the ordinary answer; reaching for a store because it
*might* be needed elsewhere is how a repo ends up with a global for a disclosure
toggle. The store earns its place when lifting would put the state above a
component that has no business knowing it — a header and a list with a route
boundary between them, not a parent two levels up.

## It is not state if you can compute it

The most common `useState` in a codebase is one that should not exist. If a value
can be derived from props, from another state, or from query data, derive it
during render — the React Compiler handles the cost (`03-conventions.md`,
"Memoization"), and there is nothing left to keep in sync.

```tsx
// ❌ two sources of truth, and a useEffect to hold them together
const [filtered, setFiltered] = useState<Item[]>([]);
useEffect(() => {
  setFiltered(items.filter((i) => i.name.includes(query)));
}, [items, query]);
// renders once with the STALE value on every change, then again after the effect

// ✅ one source of truth, no effect, no extra render
const filtered = items.filter((i) => i.name.includes(query));
```

The test is mechanical: **can I write this value as an expression of things I
already have?** If yes, it is derived, and storing it means owning its
re-synchronisation forever. `04-state.md` lists this as one of the four ways
state placement goes wrong; this is what it looks like at the component level.

Store the **input**, derive the **output**: `query` is state, `filtered` is not.

## The two bugs the API invites

```tsx
// ❌ runs on EVERY render, result thrown away after the first
const [rows, setRows] = useState(parseCsv(rawFile));

// ✅ lazy initialiser — called once, on mount
const [rows, setRows] = useState(() => parseCsv(rawFile));
```

`useState(expensiveCall())` evaluates the argument on every render and discards
it every time but the first. Invisible in a fast function, a real cost in a parse
or a `localStorage` read — and misleading either way, since it reads as
"initialisation".

```tsx
// ❌ two clicks in one tick both read the same `count`, one increment is lost
setCount(count + 1);

// ✅ the updater receives the pending value
setCount((c) => c + 1);
```

Use the functional form whenever the next value depends on the previous one. It
is also what lets a handler be defined once and stay correct — the value form
closes over the render it was created in.

## Resetting on a prop change: `key`, not an effect

Wanting to reset local state when the thing being displayed changes is common,
and the effect version is wrong in a way that is hard to see.

```tsx
// ❌ renders once with the PREVIOUS user's draft still in the textarea
useEffect(() => {
  setDraft("");
}, [userId]);

// ✅ a new key is a new component: every useState inside it re-initialises
<ProfileEditor key={userId} userId={userId} />
```

The effect runs *after* the render that already showed stale content. `key` makes
React discard the instance and build a fresh one, so there is no intermediate
frame and no list of state variables to remember to reset. Put the `key` on the
component that owns the state, at the call site.

## `useReducer` when the transitions are the point

Reach for it when several state variables change **together** under rules, and
the invariant matters more than the individual fields — a wizard, a multi-step
form, an editor with undo. The threshold is not "how many `useState`", it is
"can two of these disagree in a way that makes no sense?"

```tsx
type Status =
  | { step: "idle" }
  | { step: "confirming"; itemId: string }
  | { step: "deleting"; itemId: string };
```

A discriminated union like this one often removes the need for a reducer
entirely: `confirming` without an `itemId` becomes unrepresentable, which is the
actual goal. Three booleans that must never be true at once are a union wearing a
disguise.

## React 19: two cases that are no longer `useState`

| Instead of | Use | Why |
| --- | --- | --- |
| `const [isPending, setIsPending] = useState(false)` around a form submit | `useActionState` | it owns the pending flag and the returned error, and cannot desynchronise from the submission |
| A local copy of a list, updated optimistically by hand | `useOptimistic` | it reverts on its own when the real value arrives — the hand-rolled version needs a rollback path that is only exercised on failure |

Both are for the **local** side of a submission. The mutation itself stays in a
React Query hook (`patterns/react-query.md`), which owns the server state, the
invalidation and the toast — these two only own what the component displays while
it is in flight.

## Anti-patterns

| Anti-pattern | Why it hurts |
| --- | --- |
| **Query data copied into `useState`** — `useEffect(() => setItems(data), [data])` | The same duplicated truth `04-state.md` flags for stores. React Query already holds it, refetches it and knows when it is stale; the copy knows none of that. Read `data` directly. |
| **A `useState` per field in a form** | Form state is React Hook Form's job (`patterns/forms.md`) — it carries validation, dirty state, submission and error wiring that hand-rolled state does not. |
| **`useState` for a value nothing renders** — a timer id, a "has already run" flag | It triggers a render for a value nobody displays. That is `useRef`. |
| **Initialising from a prop and never syncing** — `useState(props.value)` | The state ignores every later prop change. Either the value is controlled by the parent (drop the state), or the component owns it and resets by `key`. |

## Testing

Local state is tested **through the component**, never by reading the value:
render, act like a user, assert what the user sees. There is nothing to mock —
`useState` has no dependency — and asserting on the state itself would couple the
test to an implementation detail the component is free to change.

```tsx
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ItemFilter } from "./ItemFilter";

describe("ItemFilter", () => {
  it("narrows the list to the items matching what was typed", async () => {
    const user = userEvent.setup();
    render(<ItemFilter items={[{ id: "1", name: "Chaise" }, { id: "2", name: "Table" }]} />);

    await user.type(screen.getByRole("textbox", { name: /rechercher/i }), "cha");

    expect(screen.getByRole("listitem")).toHaveTextContent("Chaise");
  });

  it("shows the empty state when nothing matches", async () => {
    const user = userEvent.setup();
    render(<ItemFilter items={[{ id: "1", name: "Chaise" }]} />);

    await user.type(screen.getByRole("textbox", { name: /rechercher/i }), "zzz");

    expect(screen.getByText(/aucun élément/i)).toBeInTheDocument();
  });
});
```

Component tests are **optional** in this repo (`.claude/rules/05-testing.md`) —
but a component holding real interaction logic is exactly where the optional one
pays for itself.
