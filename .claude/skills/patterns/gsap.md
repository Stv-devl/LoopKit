# GSAP Patterns

**GSAP is on demand.** The default is CSS or Motion (`patterns/motion.md`). Use
GSAP only when the spec declares it, in one line under `Front surface`:

```
Motion: gsap - <the need Motion cannot cover>
```

Good reasons: a timeline of several coordinated steps, a scroll-driven sequence
(ScrollTrigger), SVG or text choreography. "GSAP is nicer" is not one. Versions
and licence text live in `docs/research-cache/gsap.md`, never here.

## Licence

GSAP ships under the Standard no charge licence: all plugins are free and
commercial use is allowed. There is a restriction: it may not be used inside
no-code visual animation builders that compete with Webflow, nor reverse
engineered for competing products. That does not touch a portfolio or an app, but
read the licence page before building anything resembling a visual builder.

## One component, one tool

GSAP is never in the same component as Motion. Scope it to **one section** of the
page, in its own file, so the rest of the app never imports it.

## Load it lazily

GSAP is not free in bytes, and its size with ScrollTrigger was not measured here:
measure it in your app. Keep it out of the main bundle with a dynamic import of
the component that owns it, and give the fallback the complete static content.

`HeroStatic` below stands for your own static version of the section, complete
without any animation.

```tsx
import { lazy, Suspense } from 'react';
import type { JSX } from 'react';

const HeroTimeline = lazy(() => import('./HeroTimeline.gsap'));

export function Hero(): JSX.Element {
  return (
    <Suspense fallback={<HeroStatic />}>
      <HeroTimeline />
    </Suspense>
  );
}
```

## useGSAP, scope and cleanup

`useGSAP` replaces `useEffect` for GSAP code: it reverts what the hook created
when the component unmounts. Always pass a `scope` ref so selectors stay inside
the component, and wrap handlers created later in `contextSafe`.

```tsx
import { useRef } from 'react';
import type { JSX } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { useGSAP } from '@gsap/react';

gsap.registerPlugin(useGSAP, ScrollTrigger);

export default function HeroTimeline(): JSX.Element {
  const scope = useRef<HTMLDivElement>(null);

  useGSAP(
    () => {
      const mm = gsap.matchMedia();
      mm.add({ noPreference: '(prefers-reduced-motion: no-preference)' }, () => {
        gsap.from('.reveal', {
          opacity: 0,
          y: 16,
          stagger: 0.1,
          scrollTrigger: { trigger: scope.current, start: 'top 80%' },
        });
      });
    },
    { scope },
  );

  return <div ref={scope}>{/* .reveal children */}</div>;
}
```

## Reduced motion

`gsap.matchMedia()` runs the animation only when the condition matches and
reverts it when the condition stops matching. Under
`prefers-reduced-motion: reduce` nothing runs, so the static content must already
be complete (`patterns/a11y.md`, "Motion and reduced motion").

## React specifics

- React 19 and the Compiler: not verified here, check it in your app.
- StrictMode double mounting is handled by `useGSAP`'s automatic revert; do not
  add manual `kill()` calls next to it.
- No `useMemo` around GSAP objects (`.claude/rules/03-conventions.md`).

## What review can and cannot see

`/loop:review` flags GSAP that no spec asked for, and both libraries in one
component, as Major. It cannot judge timing or feel from still captures; someone
has to watch the page.
