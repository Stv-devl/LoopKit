# Forms Patterns

> **Zod v4** (`zod ^4`). Use the v4 idioms: `z.email()` (top-level, **not**
> `z.string().email()`), messages via `{ message }` or shorthand string.
>
> **Version trap**: `zodResolver` must come from a `@hookform/resolvers` release
> that supports Zod v4. An older resolver typechecks against the v3 schema type
> and fails on a v4 schema — the error surfaces as an unrelated resolver type
> mismatch. Check the installed version before debugging the schema.
>
> <!-- FILL: where this repo keeps its reusable field schemas, e.g.
> `src/lib/schemas/auth.ts` exposing `emailField`, `strongPasswordField`. -->

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
        <input id="email" type="email" {...register('email')} aria-invalid={!!errors.email} />
        {errors.email && <p role="alert">{errors.email.message}</p>}
      </div>
      <Button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Envoi...' : 'Envoyer'}
      </Button>
    </form>
  );
}
```

## With mutation

The server error is surfaced via **toast** (see `feedback.md`), not via a
`getErrorMessage` function (which does not exist). We keep a `role="alert"` for the inline
validation error if needed.

```tsx
import { toast } from '@/hooks/ui/useToast';

function CreateForm(): React.ReactElement {
  const { mutate, isPending } = useCreateItem(); // already handles the error toast in onError
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

## Common Zod v4 schemas

```typescript
import { z } from 'zod';

// Email (v4: z.email top-level). The repo exposes `emailField`, already trim+lowercase.
const email = z.email('Email invalide');

// Password confirmation
export const registerSchema = z
  .object({
    email: z.email('Email invalide'),
    password: z.string().min(8, 'Minimum 8 caractères'),
    confirmPassword: z.string(),
  })
  .refine((d) => d.password === d.confirmPassword, {
    message: 'Mots de passe différents',
    path: ['confirmPassword'],
  });

// Required checkbox (v4: no `errorMap`, use refine + message)
export const termsSchema = z.object({
  acceptTerms: z.boolean().refine((v) => v === true, {
    message: 'Vous devez accepter les conditions',
  }),
});
```

> Reuse the shared fields rather than redeclaring them: `import { emailField,
> strongPasswordField } from '@/lib/schemas/auth'`.

## Backend errors displayed inline (not as a toast)

Same mechanism as the toast, different placement. The string still comes from
`userMessageFor(code)` — there is **exactly one** table mapping a code to user
copy (`patterns/feedback.md`), and inline display is not a reason to open a
second one.

```tsx
import { toServiceError } from '@/lib/result';
import { userMessageFor } from '@/lib/userMessages';

function ConnectedLoginForm(): React.ReactElement {
  const { mutate, isPending, error } = useLogin();
  const form = useForm<LoginFormData>({ resolver: zodResolver(loginSchema) });

  return (
    <form onSubmit={form.handleSubmit((data) => mutate(data))} noValidate>
      {/* fields */}
      {error && (
        <p role="alert">{userMessageFor(toServiceError(error).code)}</p>
      )}
      <Button type="submit" disabled={isPending}>Se connecter</Button>
    </form>
  );
}
```

> **Never match on the backend's message text.** A helper doing
> `error.message.includes('invalid login credentials')` is the anti-pattern this
> section replaces: it couples the UI to an English string the backend is free to
> reword, it breaks silently on the day it does, and it is a second mapping
> mechanism competing with `userMessageFor`. If the distinction matters to the
> user — bad credentials vs. rate limited — the **repository** turns it into a
> `code` (`{name}.errors.ts`), and that code gets a line in
> `src/lib/userMessages.ts`. The mapping happens once, where the transport is
> still visible.

## Accessibility

```tsx
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
```

The wrapper is a `<div>` on purpose — there is no semantic tag for *one* labelled
field, and `<fieldset>` announces a group that isn't there. The full reasoning,
and when `<fieldset>` + `<legend>` **is** right, is in `templates/component.md`
("Why a `<div>` here").
