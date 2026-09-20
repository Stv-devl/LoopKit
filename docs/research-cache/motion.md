---
topic: motion
checked: 2026-09-20
stability: volatile
sources:
  - https://registry.npmjs.org/motion/latest
  - https://motion.dev/docs/react-reduce-bundle-size
  - https://motion.dev/docs/react-accessibility
  - https://github.com/framer/motion/issues/2668 (search-result snippet only, not opened)
---

## 1. Current stable version, package name / import path, React 19 support
npm `motion` latest = 13.4.0 (registry, 2026-09-20). React bindings import from `motion/react` (exports also: `motion/react-m`, `motion/react-mini`, `motion/react-client`, `motion/react-animate-view`). peerDependencies: `react ^18.0.0 || ^19.0.0`, `react-dom` same, both optional. No `engines` field. Formerly `framer-motion`; new code imports `motion/react`.

## 2. Licence
MIT (registry `license` field).

## 3. Bundle-size approach
Per motion.dev bundle-size page: `motion` component 34kb, not tree-shakable. `m` component under about 4.6kb initial. `LazyMotion` with `domAnimation` = +15kb (animations, variants, exit, tap/hover/focus); `domMax` = +25kb (adds drag/pan and layout animations). Recommended: use `m` instead of `motion`, wrap in `LazyMotion` with a feature package, optionally load features via dynamic import. (Figures quoted from a page summary, not the raw page.)

## 4. prefers-reduced-motion
`<MotionConfig reducedMotion="user">` disables transform and layout animations automatically, keeps opacity/backgroundColor animations. Also `"always"` and `"never"`. `useReducedMotion()` returns a boolean for custom handling (swap transforms for opacity, disable parallax/autoplay). Source: motion.dev/docs/react-accessibility (summary).

## 5. React Compiler / StrictMode
No React Compiler issue found. StrictMode: historical issues (drag jumping in React 18 #1533, #392); a React 19 report #2668 titled "Incompatible with React 19" appeared in search results (snippet only, likely pre-13 era; the current peer range includes 19). Not verified against current release.

## Not found
- No official statement on React Compiler compatibility located.
- Issues #2668/#1533/#392 not opened; their resolution state is unknown.
