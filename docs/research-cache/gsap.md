---
topic: gsap
checked: 2026-09-20
stability: volatile
sources:
  - https://registry.npmjs.org/gsap/latest
  - https://registry.npmjs.org/@gsap/react/latest
  - https://gsap.com/community/standard-license/
  - https://gsap.com/resources/React/
  - https://gsap.com/docs/v3/GSAP/gsap.matchMedia()/
  - https://github.com/greensock/gsap
---

## 1. Version, packages, React 19 support
`gsap` latest = 3.15.0. `@gsap/react` latest = 2.1.2, peers `gsap ^3.12.5`, `react >=17` (so React 19 is within range). `useGSAP` is exported from `@gsap/react`. No `engines` field on either.

## 2. Licence
Registry `license`: "Standard 'no charge' license" (https://gsap.com/standard-license); `@gsap/react`: "SEE LICENSE AT https://gsap.com/standard-license". Page read: https://gsap.com/community/standard-license/ (summarised by the fetch tool, not verbatim). Content: GSAP and all plugins (ScrollTrigger, ScrollSmoother, ScrollTo, DrawSVG, MorphSVG, MotionPath, Flip, Draggable, Observer, SplitText, ScrambleText) free, commercial use permitted. Restriction quoted: no use "in tools that allow users to build visual animations without code that encourages, induces, or materially assists in creating a solution that competes with Webflow's visual animation building capabilities"; no reverse engineering to build Competitive Products. Repo copyright line: "2008-2026, GreenSock". Full licence text should be read directly before shipping a no-code/visual-builder product.

## 3. React integration
Per gsap.com/resources/React (summary): `useGSAP()` is a drop-in for useEffect/useLayoutEffect; animations, ScrollTriggers, Draggables and SplitText created during the hook are reverted on unmount via internal `gsap.context()`. `scope` (a ref) constrains selector strings to a container. Animations created later (event handlers) need `contextSafe()` to be registered for cleanup. Dependency array/config object controls re-run; `revertOnUpdate` decides revert on each dep change vs only on unmount. Handles StrictMode double effects. SSR-safe (isomorphic layout effect); needs a client component in Next app router (n/a for Vite).

## 4. prefers-reduced-motion
`gsap.matchMedia().add({ reduceMotion: "(prefers-reduced-motion: reduce)", ... }, (context) => { const { reduceMotion } = context.conditions; ... })`. Callback runs when any condition matches; animations and ScrollTriggers created inside auto-revert when conditions stop matching; `mm.revert()` for manual cleanup. matchMedia creates a gsap.context internally. Optional returned cleanup function.

## 5. Bundle size
Not found in any source read (repo README states none; search returned nothing). Not asserted.

## Not found
- No lazy/dynamic-import guidance found on the React page (summary mentioned none).
- Bundle size for core + ScrollTrigger: unverified; would need bundlephobia/pkg-size or a local `vite build` measurement.
- Interaction with React Compiler not researched.
