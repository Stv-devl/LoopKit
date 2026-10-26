---
topic: zustand-v5
checked: 2026-08-19
stability: pinned
sources:
  - https://api.github.com/repos/pmndrs/zustand/contents/docs
  - https://api.github.com/repos/pmndrs/zustand/contents/docs/reference
  - https://api.github.com/repos/pmndrs/zustand/contents/docs/learn
  - https://api.github.com/repos/pmndrs/zustand/contents/docs/reference/migrations
  - https://raw.githubusercontent.com/pmndrs/zustand/main/docs/reference/migrations/migrating-to-v5.md
  - https://raw.githubusercontent.com/pmndrs/zustand/v5.0.15/src/middleware/devtools.ts
  - https://unpkg.com/zustand@5/package.json
  - https://unpkg.com/zustand@5/react/shallow.js
  - https://unpkg.com/zustand@5/shallow.js
  - https://unpkg.com/zustand@5/react.d.ts
  - https://unpkg.com/zustand@5/?meta
  - https://vite.dev/guide/env-and-mode
---

Checked 2026-08-19 against zustand `5.0.15`.

- **No equality-function 2nd argument, in any overload** (`react.d.ts`):
  `useStore(api)` / `useStore(api, selector)`; bound hook `()` / `(selector)`.
  `useUIStore(selector, shallow)` is a compile error under strict TS (`TS2554:
  Expected 0-1 arguments, but got 2`), not a runtime no-op and not an automatic
  re-render loop. Fix: `useShallow(selector)`. (This corrects the earlier
  "re-render loop" wording in `.claude/skills/patterns/zustand.md`.)
- **`useShallow` paths**: `zustand/react/shallow` (direct, narrower) and
  `zustand/shallow` (barrel re-exporting `shallow` and `useShallow`, pulls in
  React) are both valid and not deprecated. A vanilla consumer wanting only
  `shallow` should use `zustand/vanilla/shallow`.
- **`devtools` `enabled` default** (`src/middleware/devtools.ts`, v5.0.15):
  `(enabled ?? import.meta.env?.MODE !== 'production') &&
  window.__REDUX_DEVTOOLS_EXTENSION__`. It keys on Vite `MODE`, not `NODE_ENV`
  (an earlier claim of `NODE_ENV` was wrong). `enabled: false` returns the
  undecorated initializer; the connector is never acquired. `vite build` forces
  `NODE_ENV='production'` whatever `--mode`, but `MODE` follows `--mode`: under
  `--mode staging` an unconditional `devtools()` stays enabled and streams state
  to a listening extension (source: `vite.dev/guide/env-and-mode`).
- **Curried `create<T>()(...)`** is still needed in v5 when composing middleware
  (TS issue #10571); `combine` and `redux` build the state type themselves and
  do not need it. Moderate confidence: from the Advanced TypeScript guide via web
  search, not fetched; TS 6 strict not independently verified.
- **`persist` `version` mismatch with no `migrate`**: logs `console.error` and
  falls back to the store's initial state (payload discarded, no throw, no
  merge). The kit ships `version: 1` without `migrate`, so a bump silently resets
  the persisted slice. Moderate confidence: DeepWiki summary, `persist.ts` not
  read.

## Not settled

- `devtools(persist(...))` vs `persist(devtools(...))` order: no primary source
  found (community consensus: devtools outermost).
- `persist` `partialize` and v5 `merge` default behaviour.
- React 19 / `useSyncExternalStore` and React Compiler interaction with
  selectors.
- Removal of the `import create from 'zustand'` default export (one read of
  `unpkg.com/zustand@5/index.js` would settle it).

## Also settled (kept from the long form)

- Vite statically replaces bare `process.env.NODE_ENV` at build time (`define`).
- Not fetched: the Advanced TypeScript guide,
  `zustand.docs.pmnd.rs/learn/guides/advanced-typescript`.
