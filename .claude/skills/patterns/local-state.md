# Local State Patterns — `useState` and its boundary

The default mechanism of `.claude/rules/04-state.md`: state used by **one
component and its subtree**. This page covers the decisions around `useState`:
where state lives, when it is not state, when it stops being *local*, and how it
resets.

## The boundary

| The value is… | Mechanism |
| --- | --- |
| Read by one component (and what it renders) | **`useState`** |
| Read by two siblings, or a component three levels away | Lift to the nearest common parent — still `useState` |
| Read across unrelated branches (a modal opened from a header, a selection read by a toolbar and a list) | Zustand — `patterns/zustand.md` |
| A filter, a sort, a page — anything shareable by link or surviving a refresh | Search params — `patterns/url-state.md` |
| Fetched | React Query — `patterns/react-query.md` |
| Set once at boot, read everywhere (session, locale) | Context — `patterns/context.md` |
| A persisted preference (theme, density) | Zustand + `persist` — `patterns/zustand.md` |

Check the **URL** before lifting: a filter or page number in `useState` is lost on
refresh and cannot be shared. **Lift on the second reader, not on the first
suspicion**: a store earns its place when lifting would put the state above a
component with no business knowing it (a header and a list across a route
boundary), not a parent two levels up.

## It is not state if you can compute it

If a value can be written as an expression of props, other state or query data,
derive it during render (React Compiler handles the cost, `03-conventions.md`,
"Memoization"). Store the **input**, derive the **output**: `query` is state,
`filtered` is not.

```tsx
// ❌ two sources of truth, and a render with the STALE value on every change
const [filtered, setFiltered] = useState<Item[]>([]);
useEffect(() => {
  setFiltered(items.filter((i) => i.name.includes(query)));
}, [items, query]);

// ✅ one source of truth, no effect
const filtered = items.filter((i) => i.name.includes(query));
```

## The two bugs the API invites

```tsx
// ❌ evaluated on EVERY render, discarded after the first
const [rows, setRows] = useState(parseCsv(rawFile));
// ✅ lazy initialiser — called once, on mount
const [rows, setRows] = useState(() => parseCsv(rawFile));

// ❌ two clicks in one tick read the same `count`, one increment is lost
setCount(count + 1);
// ✅ the updater receives the pending value
setCount((c) => c + 1);
```

## Resetting on a prop change: `key`, not an effect

```tsx
// ❌ renders once with the PREVIOUS user's draft still in the textarea
useEffect(() => {
  setDraft("");
}, [userId]);

// ✅ a new key is a new component: every useState inside it re-initialises
<ProfileEditor key={userId} userId={userId} />
```

Put the `key` on the component that owns the state, at the call site.

## `useReducer` when the transitions are the point

Several variables that change **together** under rules (wizard, multi-step form,
undo). The threshold is "can two of these disagree in a way that makes no
sense?", not the count of `useState`. A discriminated union often removes the
need for a reducer: three booleans that must never be true at once are a union in
disguise.

```tsx
type Status =
  | { step: "idle" }
  | { step: "confirming"; itemId: string }
  | { step: "deleting"; itemId: string };
```

## React 19: two cases that are no longer `useState`

| Instead of | Use |
| --- | --- |
| `useState(false)` for `isPending` around a form submit | `useActionState` |
| A local copy of a list, updated optimistically by hand | `useOptimistic` (reverts on its own) |

Both own only the **local** side of a submission; the mutation stays in a React
Query hook (`patterns/react-query.md`).

## Anti-patterns

| Anti-pattern | Why it hurts |
| --- | --- |
| **Query data copied into `useState`** — `useEffect(() => setItems(data), [data])` | The duplicated truth `04-state.md` flags for stores. Read `data` directly. |
| **A `useState` per field in a form** | Form state is React Hook Form's job (`patterns/forms.md`). |
| **`useState` for a value nothing renders** (timer id, "has run" flag) | Triggers a render for nothing. Use `useRef`. |
| **`useState(props.value)` never synced** | Ignores later prop changes. Either the parent controls it (drop the state), or the component owns it and resets by `key`. |

## Testing

Test through the component, never by reading the value: render, act like a user,
assert what the user sees. Nothing to mock; asserting on the state couples the
test to an implementation detail. Component tests are **optional**
(`.claude/rules/05-testing.md`) but pay off on real interaction logic.

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
});
```
