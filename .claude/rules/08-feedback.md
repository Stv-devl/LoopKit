<!-- budget: 60 lines · /kit:doctor rules-budget -->
# Feedback States

## Rules

- Always handle `isPending`, `isError`, empty states
- `isFetching` (refetch): keep data visible, discreet indicator
- Always log the technical error, then show a user message — the two languages
  are declared once, in `03-conventions.md`
- Never show raw error messages to users
- `isPending` on mutations = anti double-submit

## isPending vs isFetching

| State | Display |
|-------|---------|
| `isPending` (initial) | full loading state, no data yet |
| `isFetching` (refetch, same key) | discreet indicator, **data stays visible** |
| `isPlaceholderData` (the key changed: filter, sort, page) | the **previous** key's data stays visible, discreet indicator, and the region is marked stale (dim / `aria-busy`) |
| **disabled** (`enabled: false`, never fetched) | **not a loading state.** Render the "nothing selected yet" branch — an empty panel, a prompt — never a loader |

**The fourth row is the one that bites**, because nothing looks wrong. A disabled
query sits at `status: 'pending'` / `fetchStatus: 'idle'` **forever**, so
`isPending` is true with no request in flight and no error. A component that
opens with `if (isPending) return <State type="loading" />` — the shape every
example in this kit uses — shows a spinner that never resolves the moment `enabled` is false. Branch on **`isLoading`**
(`isPending && isFetching`) wherever a query can be disabled, and give the
not-yet-asked case its own branch.

**The third row is a property of the hook, not of the component.** A key that
carries a filter and no `placeholderData` comes back as `isPending` — full
loading state, on every keystroke. One line in the hook, and it is the only place
it can go: `patterns/react-query.md`, "When the key changes".

## Loading Strategy

<!-- FILL: the components this repo actually has. The four states are the rule;
     the component names are yours. `/design-system` writes them down, the `ui`
     reviewer gates against them, and a designer that can't find them invents
     new ones. -->

| Context | Component |
|---------|-----------|
| Page / section load | `<State type="loading" />` (`src/components/states/`) |
| Dedicated loader | `src/components/loading/` |
| Button action | `disabled={isPending}` |
| Empty / error | `<State type="empty" />` / `<State type="error" error={error} />` |

## Error Messages

Language convention: see `03-conventions.md`, "Error Messages" — that row is
the only declaration of the two languages, and this file deliberately does not
restate it. Applies here to the console log (technical language), the user
toast/alert and the form validation messages (user language).

## Patterns (read IF creating)

- Feedback component (loading/error/empty) → `.claude/skills/patterns/feedback.md`
- Toast → `.claude/skills/patterns/feedback.md`
