<!-- budget: 55 lines · /kit:doctor rules-budget -->
# Code Conventions

## TypeScript

- No `any`: use `unknown`, generics or a real type.
- Explicit return types, except `queryOptions(...)` factories whose branded type
  must be inferred. Zod validates runtime boundaries.
- Technical logs/errors/comments are English; user-facing messages use the
  language declared below.

## Documentation

JSDoc exported services, hooks, stores, shared utilities and shared components.
No implementation comments. The comment hook's deny text owns syntax details.

## Memoization

No new `useMemo`, `useCallback` or `memo`: React Compiler is on. Only identity as
an external correctness contract, or a measured expensive non-render computation,
qualifies; name the exception in a one-line comment. Fix compiler lint bail-outs.

## Semantic HTML and Accessibility

Use landmarks, buttons for actions, links for navigation, real lists/tables and
ordered headings. A `section` needs a heading or label. Page/layout ownership is
in `templates/page.md`; interactive behaviour is in `patterns/a11y.md` and is
mandatory when creating an interactive component.

## Error Messages

| Context | Language |
| --- | --- |
| Technical errors, logs | English |
| User-facing messages | French |

UI maps `ServiceError.code` to copy; error objects carry technical English only.

## SOLID

S is the layer split and size limits; D is the enforced dependency arrow. O/L/I
have one enforcer: `/loop:review` correctness. Flag growing kind ladders, variants
that narrow their contract, and interfaces callers cannot satisfy cleanly.
Injection crosses a forbidden dependency boundary; inside one feature the module
boundary is already the seam.

Detailed shapes and rationale: `.claude/guides/03-conventions.md`.
