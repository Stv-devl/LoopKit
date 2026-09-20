# Motion Patterns

Read this when a feature creates an animation. The default is **plain CSS** or
**Motion** (`motion/react`). GSAP is a different tool for a different need and
only enters when the spec declares it (`patterns/gsap.md`). Versions and licence
terms live in `docs/research-cache/motion.md`, never here.

## Which tool

| The need | Use |
| --- | --- |
| Hover, focus, small state transitions | CSS `transition` (Tailwind), nothing to install |
| Enter/exit, layout change, gestures, a simple scroll reveal | Motion |
| Timelines, scroll-driven sequences, SVG or text choreography | GSAP, only if the spec says `Motion: gsap - <reason>` |

Motion and GSAP are **never in the same component**: one tool owns one component,
or two clocks fight over the same element.

## Motion with LazyMotion

Mount one provider in `src/providers/` (wiring, so it may name the library) and
use the light `m` component everywhere else. The full `motion` component is not
tree-shakable; `m` with `LazyMotion` is the small path.

```tsx
import type { JSX, ReactNode } from 'react';
import { LazyMotion, MotionConfig, domAnimation } from 'motion/react';

export function MotionProvider({ children }: { children: ReactNode }): JSX.Element {
  return (
    <MotionConfig reducedMotion="user">
      <LazyMotion features={domAnimation}>{children}</LazyMotion>
    </MotionConfig>
  );
}
```

```tsx
import type { JSX, ReactNode } from 'react';
import { m } from 'motion/react';

export function Reveal({ children }: { children: ReactNode }): JSX.Element {
  return (
    <m.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.2 }}>
      {children}
    </m.div>
  );
}
```

Drag and animated layout need the heavier feature set; take it only for the
component that needs it. No `useMemo` to stabilise animation objects: the React
Compiler is on (`.claude/rules/03-conventions.md`).

## Reduced motion

`prefers-reduced-motion` is an accessibility rule, not a polish item
(`patterns/a11y.md`, "Motion and reduced motion").

- Motion: `<MotionConfig reducedMotion="user">` turns transform and layout
  animations off, but it still animates opacity and colour. Do not describe it as
  "all motion off"; pick the values you animate accordingly.
- CSS: `motion-reduce:transition-none` in Tailwind, or a
  `@media (prefers-reduced-motion: reduce)` block that sets `transition` and
  `animation` to `none`.
- Custom handling: `useReducedMotion()` returns a boolean.

## Rules of thumb

- Animate `transform` and `opacity`; avoid animating layout properties.
- An animation never carries a state change alone: keep the text or icon that
  says it, the animation only eases it in.
- The page must be complete and usable with animation off or before it runs.

## Not verified here

Motion with React 19, the React Compiler and StrictMode was **not** verified when
this guide was written (`docs/research-cache/motion.md`, open items). Check it in
your own app before relying on it, and record the result in the cache file.

## What review can and cannot see

`/loop:review` stage 0 takes still captures: it does not judge animation feel,
timing or smoothness, and Impeccable's detector only catches known code patterns
(for example bounce easing). Someone has to watch the page.

## Acceptance criteria for animated features

Copy these into the spec of any feature that animates; `/loop:review` (`ui`
dimension, "Animation conformance") checks the diff against them.

- [ ] With `prefers-reduced-motion: reduce`, the feature works and stays readable, and no transform or layout animation runs.
- [ ] No state change is signalled by animation alone: the text or icon is there without it.
- [ ] The UI is complete with animation disabled or not yet loaded.
- [ ] The animation library is Motion or CSS, unless the spec declares `Motion: gsap - <reason>`.
