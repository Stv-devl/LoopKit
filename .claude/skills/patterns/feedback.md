# Feedback Patterns (Loading, Error, Empty)

<!-- FILL: the table below must name the components this repo actually has. It is
     the anti-hallucination list — an agent that can't find `<State>` will invent
     a `<Spinner>`. Keep the closing "do not invent them" note pointed at whatever
     does NOT exist here. -->

## Actual infra

| Need | What to use | Where |
| --- | --- | --- |
| Loading / error / empty / unauth | Unified `<State>` component | `src/components/states/State.tsx` |
| Dedicated loaders | `SquareLoader`, `GlobalLoadingBar`, … | `src/components/loading/` |
| Toast | `useToast()` / `toast()` (shadcn) | `src/hooks/ui/useToast.ts` |
| Rendering the `<Toaster>` | mounted once | `src/routes/__root.tsx` |
| Logging a `ServiceError` (EN) | `formatServiceError(error)` | `src/lib/errors.ts` |
| Turning a `code` into user copy | `userMessageFor(code)` | `src/lib/userMessages.ts` |

> There is **no** `src/components/feedback/`, no `useToastStore`, no
> `getErrorMessage`. Do not invent them.

## `<State>` component

A single component covers all 4 states, with contextual `variant`s
(`default` | `results` | `pricing`):

```tsx
import { State } from '@/components/states/State';

function ItemList() {
  const { data, isPending, isFetching, isError, error, refetch } = useItems();

  if (isPending) return <State type="loading" variant="results" />;
  if (isError) return <State type="error" error={error} variant="results" onRetry={refetch} />;
  if (!data?.length) return <State type="empty" variant="results" />;

  return (
    <div className="relative">
      {isFetching && <GlobalLoadingBar />}
      <List items={data} />
    </div>
  );
}
```

Detail (single object):

```tsx
function ItemDetail({ id }: { id: string }) {
  // `useItem` carries `enabled: !!id` (`patterns/react-query.md`), so an empty
  // id leaves the query `pending` FOREVER. `isLoading` is the branch that ends;
  // `isPending` alone would spin with no request in flight (`08-feedback.md`).
  const { data, isLoading, isError, error } = useItem(id);

  if (!id) return <State type="empty" title="Aucun élément sélectionné" />;
  if (isLoading) return <State type="loading" message="Chargement..." />;
  if (isError) return <State type="error" error={error} />;
  if (!data) return <State type="empty" title="Élément introuvable" />;

  return <ItemCard item={data} />;
}
```

Useful props: `type` (`loading | error | empty | unauth`), `variant`, `message`,
`title`, `error`, `onRetry`, `size`, `showIcon`.

> **`<State>` is a consumer of `userMessageFor`, not a second mechanism.** Passing
> the raw `error` is enough because the component does internally what the toast
> path below does explicitly: `toServiceError(error)` → `userMessageFor(code)`.
> There is exactly **one** place a code becomes user copy
> (`src/lib/userMessages.ts`) — if `<State>` ever grows its own message table,
> the two drift and the same error reads differently on a page and in a toast.

## Toast (shadcn `useToast`)

API: `toast({ title, description?, variant? })` with `variant: 'default' | 'destructive'`.
**No** `{ type, message }`. The toast is fired in the **hook** (mutation), not
in the component.

```typescript
// features/items/hooks/hooks.ts
import type { UseMutationResult } from '@tanstack/react-query';
import { toast } from '@/hooks/ui/useToast';
import { formatServiceError } from '@/lib/errors';
import { toServiceError } from '@/lib/result';
import { userMessageFor } from '@/lib/userMessages';

export function useCreateItem(): UseMutationResult<Item, Error, CreateItemInput> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: CreateItemInput) => unwrap(await repository.create(input)),
    onSuccess: () => {
      // The key comes from the factory, never from a literal typed here — a
      // second `['items']` is an invalidation that silently does nothing
      // (`patterns/react-query.md`, "Query keys"; `/review` scores it Major).
      queryClient.invalidateQueries({ queryKey: itemKeys.lists() });
      toast({ title: 'Élément créé' });
    },
    onError: (error) => {
      // The user string is NEVER written here. It comes from the code, through
      // `userMessageFor` — the one table (below). Hardcoding it at the call
      // site is how the same error ends up worded three ways in one app.
      const serviceError = toServiceError(error);
      console.error(formatServiceError(serviceError)); // EN, technical
      toast({
        title: 'Erreur',
        description: userMessageFor(serviceError.code), // user language, from `code`
        variant: 'destructive',
      });
    },
  });
}
```

In a component (rare case, local action):

```typescript
import { useToast } from '@/hooks/ui/useToast';

const { toast } = useToast();
toast({ title: 'Lien copié' });
```

## Mutation button (anti double-submit)

```tsx
function CreateItemForm() {
  const { mutate, isPending } = useCreateItem();
  const form = useForm<CreateItemInput>({ resolver: zodResolver(schema) });

  return (
    <form onSubmit={form.handleSubmit((data) => mutate(data, { onSuccess: () => form.reset() }))}>
      {/* fields */}
      <Button type="submit" disabled={isPending}>
        {isPending ? 'Création...' : 'Créer'}
      </Button>
    </form>
  );
}
```

> The success/error toast is handled in `useCreateItem` (above), not in `onSubmit`.

## Errors: log EN, message FR

`formatServiceError(error: ServiceError)` is **reserved for logging**
(`console.error`) — it does not produce a message intended for the user. The
user-language string is picked at the component / toast level (see
`.claude/rules/08-feedback.md`), always through `userMessageFor`. **The shape is
the `onError` of the mutation above** — it is not repeated here, because two
copies of the same block is how one of them ends up wrong.

Three things about that block are worth naming explicitly:

- React Query hands `onError` an **`unknown`**, because what `unwrap` threw
  crossed a boundary that erases the type. Narrow it with `toServiceError` —
  never with an `as` cast, which asserts a shape nobody checked.
- `console.error` takes the **formatted** error, the toast takes the **code**.
  Same object, two audiences, and they never swap.
- The `title` is generic on purpose. Putting the specific wording in
  `description`, from the code, is what keeps one table in charge of the copy.

`ServiceError` is `{ code, message, cause? }` — `message` is the **technical**
English string for logs. There is deliberately **no** `userMessage` field: the
user-facing copy is picked at the UI layer from `code`, so it stays in one place
and stays translatable. Canonical codes: `unauthorized`, `not_found`,
`validation_failed`, `conflict`, `db_error`, `network_error`, `unknown_error`.

> The exact shapes live in `.claude/skills/templates/lib-core.md` — that file is
> the source of truth, this page only consumes it.

The one place user copy is mapped, so a code never leaks to the screen:

```typescript
// src/lib/userMessages.ts
// THE SEVEN CANONICAL CODES ALL GET A LINE. `lib/errors.ts` declares exactly
// seven (`templates/lib-core.md`); a missing one is not a smaller table, it is a
// code that silently renders the fallback. `db_error` is the one that gets
// forgotten, and it is the most frequent of the lot — the simple `services.ts`
// variant (`templates/feature.md`) returns it on nearly every operation.
const MESSAGES: Record<string, string> = {
  // canonical codes (lib/errors.ts) — all seven, no exception
  unauthorized: 'Vous n’avez pas accès à cette ressource.',
  not_found: 'Élément introuvable.',
  validation_failed: 'Certaines informations sont invalides.',
  conflict: 'Cet élément a déjà été modifié ailleurs.',
  // Operation-neutral on purpose: `db_error` is returned by reads as well as
  // writes (`templates/feature.md`, the `if (error)` branch of `getAll`), and
  // "L’enregistrement a échoué" on a failed list read tells the user something
  // was saved badly when nothing was written at all.
  db_error: 'L’opération a échoué. Réessayez.',
  network_error: 'Connexion impossible. Réessayez.',
  unknown_error: 'Une erreur inattendue est survenue.',
  // feature codes ({name}.errors.ts) — same lower snake_case, one line each.
  // A feature code with no line here silently shows the generic fallback.
  feature_not_found: 'Cet élément n’existe plus.',
};

/**
 * User-facing message for a ServiceError code. Falls back to a generic one —
 * a code must never reach the screen.
 */
export function userMessageFor(code: string): string {
  return MESSAGES[code] ?? 'Une erreur est survenue.';
}
```

<!-- FILL: the strings above are in French because that is this repo's user
     language (`.claude/rules/03-conventions.md`). Translate them, don't add a
     second mechanism. -->

> **`src/lib/userMessages.ts` is inside the coverage floor** (`05-testing.md`:
> `src/lib/**` is in `include`, and the three sanctioned exclusions are the
> client instance, the QueryClient config and the vendor `cn()` — not this
> file). It is scaffolded **before the first feature**, so an untested
> `userMessageFor` is an uncovered function on a repo that has nothing else to
> average it out: `lib-core.md` does the arithmetic — one uncovered function is
> already 87.5 %, below a floor of 90 — and adding this one makes it 8/9 =
> 88.9 %. A red gate on day one, on a file nobody was told to test.
>
> Write its two cases with the file, not after:
>
> ```typescript
> // src/lib/userMessages.test.ts
> import { describe, expect, it } from 'vitest';
> import { userMessageFor } from './userMessages';
>
> describe('userMessageFor', () => {
>   it('returns the message declared for a known code', () => {
>     expect(userMessageFor('feature_not_found')).toBe('Cet élément n’existe plus.');
>   });
>
>   it('falls back to the generic message for a code nobody declared', () => {
>     expect(userMessageFor('code_that_does_not_exist')).toBe('Une erreur est survenue.');
>   });
> });
> ```
>
> The second case is the one that matters: the fallback branch is what stops a
> raw `code` reaching the screen, and it is the branch a table-driven function
> never exercises on its own. Same shape as `route-utils.ts` in
> `patterns/guards.md` — inside the floor, security-adjacent, prescribed in
> place.

> **Language note**: every user-facing string in `.claude/skills/patterns/` is
> written in the user language declared by `03-conventions.md`. Change it there
> once, then translate the copy — the *structure* (log EN, show user language)
> never changes.

## React Query — states to always handle

| State | Display |
| --- | --- |
| `isPending` (initial) | `<State type="loading" />` / `SquareLoader` |
| `isError` | `<State type="error" error={error} onRetry={refetch} />` |
| empty data | `<State type="empty" />` |
| `isFetching` (refetch, same key) | keep the data visible + `<GlobalLoadingBar />` |
| `isPlaceholderData` (the key changed) | keep the **previous** key's data visible, `<GlobalLoadingBar />`, and mark the region stale (`aria-busy`, or dim it) — never a full `<State type="loading" />`. Requires `placeholderData` on the hook (`patterns/react-query.md`) |
| **disabled** (`enabled: false`, never fetched) | the "nothing asked yet" branch — an empty panel or a prompt, **never a loader**. `isPending` stays true forever with no request in flight, so branch on `isLoading` (`isPending && isFetching`) here (`08-feedback.md`) |
| `isPending` (mutation) | `disabled` on the button (anti double-submit) |
