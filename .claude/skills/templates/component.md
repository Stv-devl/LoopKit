# Component Template

> **Colours and spacing come from tokens, never from raw palette classes.** The
> classes below (`bg-surface`, `text-muted`, `border-danger`) are **placeholders
> for this repo's own token names** — `/loop:design-system` writes the real ones into
> the `@theme` block, and `docs/design-system.md` is their single source of
> truth. Rewrite them once, here, when that file exists. A raw `bg-white` /
> `text-gray-500` / `border-red-500` in a diff is what `/loop:review`'s `ui`
> dimension flags: it survives a theme change, a dark mode and a rebrand by
> quietly looking wrong.


## Prerequisite: `cn()`

Every component below imports it, and **nothing in the kit creates it** — write
it once, at scaffolding, alongside `templates/lib-core.md`:

```bash
pnpm add clsx tailwind-merge
```

```typescript
// src/lib/utils/cn.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Merges class names, letting a later Tailwind class win over an earlier one
 * in the same group — `cn("p-2", "p-4")` yields `"p-4"`, which plain string
 * concatenation cannot do.
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
```

> **The path matters: `src/lib/utils/cn.ts`, not `src/lib/utils.ts`.** A bare
> `utils.ts` matches the TDD hooks' pattern, so it would be test-first and frozen
> — and shadcn/ui drops this exact helper at that exact path by default. The
> nested path does not match, which is why it is the one the kit imports
> (`.claude/rules/05-testing.md`). It is also excluded from the coverage floor:
> it is vendor code copied verbatim.

## Simple component

```tsx
import { cn } from "@/lib/utils/cn";

interface CardProps {
  children: React.ReactNode;
  variant?: "default" | "outlined";
  className?: string;
}

/**
 * Card container with optional variant styling.
 */
export function Card({
  children,
  variant = "default",
  className,
}: CardProps): React.ReactElement {
  return (
    <article className={cn(styles.base, styles[variant], className)}>
      {children}
    </article>
  );
}

const styles = {
  base: "rounded-lg p-4",
  default: "bg-surface shadow",
  outlined: "border border-default",
};
```

## Component with slots

```tsx
interface CardWithSlotsProps {
  children: React.ReactNode;
  header?: React.ReactNode;
  footer?: React.ReactNode;
}

/**
 * Card with optional header and footer slots.
 */
export function Card({
  children,
  header,
  footer,
}: CardWithSlotsProps): React.ReactElement {
  return (
    <article className="rounded-lg bg-surface shadow">
      {header && <header className="border-b border-default px-4 py-3">{header}</header>}
      <div className="p-4">{children}</div>
      {footer && <footer className="border-t border-default px-4 py-3">{footer}</footer>}
    </article>
  );
}
```

> **The body is a `<div>`, not a `<section>`.** `03-conventions.md` writes
> `<section>` **(with a heading)**, and that parenthesis is the whole rule: a
> `<section>` with no heading and no `aria-label` is not a landmark — the
> accessibility tree exposes it as a generic container, i.e. a `<div>` that
> claimed otherwise. `<header>` and `<footer>` here are different: they are
> landmarks by position inside the `<article>`, named by their own content.
> Reach for `<section>` when you have a heading to put in it; otherwise the
> honest wrapper is a `<div>`.

## Component that forwards a ref

```tsx
import { cn } from "@/lib/utils/cn";
import { Spinner } from "@/components/loading/Spinner";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary";
  loading?: boolean;
  ref?: React.Ref<HTMLButtonElement>;
}

/**
 * Button with variant styling and loading state.
 */
export function Button({
  variant = "primary",
  loading,
  children,
  disabled,
  className,
  ref,
  ...props
}: ButtonProps): React.ReactElement {
  return (
    <button
      ref={ref}
      disabled={disabled || loading}
      className={cn(styles.base, styles[variant], className)}
      {...props}
    >
      {loading && <Spinner className="mr-2" aria-hidden />}
      {children}
    </button>
  );
}
```

> **No `forwardRef`.** Since React 19 `ref` is an ordinary prop on function
> components: declare it in the props interface and destructure it. `forwardRef`
> still runs, but it is deprecated, it costs a wrapper component, and it forces
> the `displayName` line that the plain function does not need. The stack pins
> React 19 — see `.claude/rules/01-stack.md`.

## List component

```tsx
interface ListProps<T> {
  items: T[];
  renderItem: (item: T) => React.ReactNode;
  keyExtractor: (item: T) => string;
  emptyMessage?: string;
}

/**
 * Generic list with empty state handling.
 */
export function List<T>({
  items,
  renderItem,
  keyExtractor,
  emptyMessage = "Aucun élément",
}: ListProps<T>): React.ReactElement {
  if (items.length === 0) {
    return <p className="text-muted">{emptyMessage}</p>;
  }

  return (
    <ul role="list" className="space-y-2">
      {items.map((item) => (
        <li key={keyExtractor(item)}>{renderItem(item)}</li>
      ))}
    </ul>
  );
}
```

## Input component

```tsx
import { useId } from "react";
import { cn } from "@/lib/utils/cn";

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
  error?: string;
  ref?: React.Ref<HTMLInputElement>;
}

/**
 * Accessible input with label and error display.
 */
export function Input({
  label,
  error,
  id,
  className,
  ref,
  ...props
}: InputProps): React.ReactElement {
  // useId() is called unconditionally — `id ?? useId()` would skip the hook
  // whenever a caller passes an id, and React would throw on the next render.
  const generatedId = useId();
  const inputId = id ?? generatedId;
  const errorId = `${inputId}-error`;

  return (
    <div className={className}>
      <label htmlFor={inputId} className="block text-sm font-medium">
        {label}
      </label>
      <input
        ref={ref}
        id={inputId}
        aria-invalid={!!error}
        aria-describedby={error ? errorId : undefined}
        className={cn(
          "mt-1 block w-full rounded border border-default px-3 py-2",
          error && "border-danger",
        )}
        {...props}
      />
      {error && (
        <p id={errorId} role="alert" className="mt-1 text-sm text-danger">
          {error}
        </p>
      )}
    </div>
  );
}
```

> **Why a `<div>` here.** `03-conventions.md` says "never a `<div>` when a
> semantic tag exists" — no semantic tag exists for *one* labelled field. A
> `<fieldset>` is for a **group** of related controls and needs a `<legend>`;
> wrapping a single input in one makes a screen reader announce a group that
> isn't there. Use `<fieldset>` + `<legend>` for a radio group or a real section
> of a form, and a plain `<div>` for a single field.

## Hook rules in a component

Two mistakes the templates above are written to avoid:

```tsx
// ❌ conditional hook — useId() is skipped when `id` is provided
const inputId = id ?? useId();
// ❌ same shape, same bug
const value = props.value ?? useDefaultValue();

// ✅ call the hook unconditionally, then choose
const generatedId = useId();
const inputId = id ?? generatedId;
```

`??`, `||`, `&&` and ternaries all short-circuit: a hook on their right-hand side
is a conditional hook. `eslint-plugin-react-hooks` catches this — which is why
`pnpm lint` is a ship gate (`.claude/rules/00-project.md`).

## No memoization in these templates

None of the components above wrap anything in `useMemo`, `useCallback` or
`memo`, and that is deliberate: the React Compiler is on and does it at build
time (`.claude/rules/03-conventions.md`, "Memoization"). Note what the
templates do instead — `styles` is declared **outside** the component, as a
module constant. That is not an optimization, it is the shape that keeps a
component compilable: an object rebuilt in the body is fine, one mutated in the
body makes the compiler skip the whole component.
