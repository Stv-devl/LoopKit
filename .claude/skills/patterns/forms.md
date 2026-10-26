# Forms Patterns

> **Zod v4** (`zod ^4`). Use the v4 idioms: `z.email()` (top-level, **not**
> `z.string().email()`); a required checkbox is `z.boolean().refine(v => v === true,
> { message })` (no `errorMap`).
>
> **Version trap**: `zodResolver` must come from a `@hookform/resolvers` release
> that supports Zod v4. An older resolver typechecks against the v3 schema type
> and fails on a v4 schema — the error surfaces as an unrelated resolver type
> mismatch. Check the installed version before debugging the schema.
>
> <!-- FILL: where this repo keeps its reusable field schemas, e.g.
> `src/lib/schemas/auth.ts` exposing `emailField`, `strongPasswordField`. -->

Reuse the shared fields (`import { emailField, strongPasswordField } from
'@/lib/schemas/auth'`) rather than redeclaring them — `emailField` already trims
and lowercases. Zod v4: `z.email()` top-level, messages via `{ message }` or a
shorthand string. A confirmation field is a `.refine(…, { path:
['confirmPassword'] })` on the object, so the error lands on that field.

## Basic setup

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { loginSchema, type LoginFormData } from '@/lib/schemas/auth';

function LoginForm({ onSubmit }: { onSubmit: (data: LoginFormData) => void }): React.ReactElement {
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="email">Email</label>
        <input
          id="email"
          type="email"
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? 'email-error' : undefined}
          {...register('email')}
        />
        {errors.email && <p id="email-error" role="alert">{errors.email.message}</p>}
      </div>
      <Button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Envoi...' : 'Envoyer'}
      </Button>
    </form>
  );
}
```

The field wrapper is a `<div>` on purpose (one labelled field is not a group);
when `<fieldset>` + `<legend>` is right: `templates/component.md` ("Why a `<div>`
here").

## With mutation

The server error is surfaced via **toast** (`feedback.md`); the mutation hook
already handles it in `onError`. The form only disables repeat submission and
resets on success.

```tsx
function CreateForm(): React.ReactElement {
  const { mutate, isPending } = useCreateItem();
  const form = useForm<CreateItemInput>({ resolver: zodResolver(createItemSchema) });

  return (
    <form onSubmit={form.handleSubmit((data) => mutate(data, { onSuccess: () => form.reset() }))}>
      {/* fields */}
      <Button type="submit" disabled={isPending}>
        {isPending ? 'Enregistrement...' : 'Enregistrer'}
      </Button>
    </form>
  );
}
```

## Backend errors displayed inline (not as a toast)

Same mechanism, different placement. The string still comes from
`userMessageFor(code)` — there is **exactly one** table mapping a code to user
copy (`patterns/feedback.md`); inline display is not a reason to open a second.

```tsx
import { toServiceError } from '@/lib/result';
import { userMessageFor } from '@/lib/userMessages';

// inside the form, with `const { mutate, isPending, error } = useLogin();`
{error && <p role="alert">{userMessageFor(toServiceError(error).code)}</p>}
```

> **Never match on the backend's message text.**
> `error.message.includes('invalid login credentials')` couples the UI to an
> English string the backend may reword, breaks silently when it does, and is a
> second mapping mechanism competing with `userMessageFor`. If the distinction
> matters to the user (bad credentials vs. rate limited), the **repository**
> turns it into a `code` (`{name}.errors.ts`) and that code gets a line in
> `src/lib/userMessages.ts`. The mapping happens once, where the transport is
> still visible.
