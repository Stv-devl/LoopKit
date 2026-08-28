# Snapshot Tests

Snapshot tests for stable UI components.

## When to use

| Case                                | Snapshot? |
| ----------------------------------- | ---------- |
| Design system (Button, Input, Card) | Yes        |
| Components with complex props        | Yes        |
| Components with dynamic data         | No         |
| Whole pages                          | No         |
| Components under active development  | No         |

## When NOT to use

- Text that changes (messages, labels)
- Dynamic data (dates, IDs)
- Components with server state
- Full layouts

## Recommended pattern

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from './Button';

describe('Button', () => {
  // Snapshot for structure only
  it('renders one snapshot per visual variant', () => {
    const { container: primary } = render(<Button variant="primary">_</Button>);
    const { container: secondary } = render(<Button variant="secondary">_</Button>);
    const { container: disabled } = render(<Button disabled>_</Button>);

    expect(primary).toMatchSnapshot('primary');
    expect(secondary).toMatchSnapshot('secondary');
    expect(disabled).toMatchSnapshot('disabled');
  });

  // Behavioral tests (more important)
  it('calls onClick when the user clicks it', async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>_</Button>);
    await userEvent.click(screen.getByRole('button'));
    expect(onClick).toHaveBeenCalledOnce();
  });
});
```

## Never in the three frozen layers

**No snapshot — file or inline — in `utils.ts`, `mapper.ts`,
`repository.ts`/`services.ts`.** Those files are frozen after the `/loop:plan` gate
(`.claude/rules/05-testing.md`), and a snapshot is the one assertion that
rewrites itself: `pnpm test:run -u` edits the inline snapshot in place and
regenerates the `.snap`. The writer is the **test runner**, so no Write/Edit
guardrail sees it and the frozen file quietly starts agreeing with the code —
exactly what the freeze exists to prevent. `prevent-destructive-commands.sh`
denies `-u` when the command names one of those files, but the real fix is to
not put a snapshot there.

A pure function has a value to assert. Write the value:

```typescript
// NOT this, in item.utils.test.ts — it rewrites itself under -u
expect(formatPrice(1000)).toMatchInlineSnapshot(`"10,00 €"`);

// this: the expected output is stated by a human, and -u cannot move it
expect(formatPrice(1000)).toBe("10,00 €");
```

## Inline Snapshots

For small outputs, in a **component** test:

```tsx
it("renders the badge label for each status", () => {
  const { container } = render(<StatusBadge status="draft" />);
  expect(container.firstChild).toMatchInlineSnapshot();
});
```

## Excluding from the snapshot

Property matchers (`toMatchSnapshot({ id: expect.any(String) })`) only apply to
**plain objects**, not to a DOM container. On rendered markup, normalise the
dynamic parts into the string yourself:

```typescript
// `useId()` emits a fresh id on every run — without this the snapshot fails on
// a component nobody touched.
const cleaned = container.innerHTML.replace(/id="[^"]+"/g, 'id="[id]"');
expect(cleaned).toMatchSnapshot();
```

## Updating

```bash
# Update a specific file — always prefer this form
pnpm test:run Button.test.tsx -u

# Update everything. Read the diff before committing: `-u` accepts whatever the
# code produces today, including the regression you were about to find.
pnpm test:run -u
```

## Rules

- 1 snapshot = 1 variant/visual state
- **No snapshot in a frozen layer** (`utils`, `mapper`, `repository`/`services`)
  — see the section above; it is the one assertion `-u` can rewrite unseen
- No snapshot on dynamic text
- Prefer behavioral tests
- Snapshot = safety net, not the primary test
