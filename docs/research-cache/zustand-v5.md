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

## 1. `useStore(selector, equalityFn)` — was the 2nd argument removed, and what is the failure mode?

**Fully settled, from source** (fetched `unpkg.com/zustand@5/react.d.ts`,
package `5.0.15`, 2026-08-19). The type declarations are:

```ts
useStore<S>(api: S): ExtractState<S>
useStore<S, U>(api: S, selector: (state: ExtractState<S>) => U): U
```

and `UseBoundStore`'s callable signature:

```ts
(): ExtractState<S>
<U>(selector: (state: ExtractState<S>) => U): U
```

**No overload declares a second, equality-function parameter — at any
arity.** `useUIStore(selector, shallow)` (2 arguments on the *bound* hook,
whose callable type only ever accepts 0 or 1) does **not** typecheck under
strict TypeScript: it is `error TS2554: Expected 0-1 arguments, but got 2`
(no overload matches a 2-argument call). This is a **compile-time rejection**,
not a runtime no-op.

**Correction to the earlier version of this entry and to
`.claude/skills/patterns/zustand.md`**: the previous wording ("re-render
loop") described a *plausible downstream symptom if the type system were
bypassed* (`as any`, plain JS, `// @ts-expect-error`), not what actually
happens in this repo's strict-TS-6 codebase. The correct, code-against lesson
is: **the compiler rejects the call outright** — a developer cannot even ship
the mistake. Teach it as a type error, with `useShallow(selector)` as the
fix, not as a runtime hazard.

## 2. `useShallow` import path — `zustand/react/shallow` vs `zustand/shallow`

**Settled from source** (fetched `unpkg.com/zustand@5/shallow.js` and
`.../react/shallow.js`, package version `5.0.15`, 2026-08-19):

- `zustand/react/shallow` exports `useShallow` directly (the React hook
  itself, `useRef`-based, delegating comparison to `zustand/vanilla/shallow`).
- `zustand/shallow` (root) is a **barrel that re-exports both**: `shallow`
  (from `zustand/vanilla/shallow`) **and** `useShallow` (from
  `zustand/react/shallow`), via getters.
- Both paths are **valid, live entry points in v5** — neither is deprecated
  nor removed. `zustand/shallow` is not React-only: importing from it pulls
  in the React re-export too, so a non-React (vanilla) consumer that only
  needs `shallow` and wants to avoid a React dependency should prefer
  `zustand/vanilla/shallow` or `zustand/react/shallow` explicitly rather than
  the root barrel. The pattern file's `zustand/react/shallow` is correct and
  is the narrower, more precise import; `zustand/shallow` is an equally valid
  alternative, not a deprecated one.

## 3. `create<T>()(...)` curried form — still required in v5?

**Settled with moderate confidence, via a web-search synthesis of the
official "Advanced TypeScript" guide** (`zustand.docs.pmnd.rs/learn/guides/advanced-typescript`,
mirrored at `github.com/pmndrs/zustand/blob/HEAD/docs/learn/guides/advanced-typescript.md`
— **not fetched directly**): the curried `create<T>()(...)` syntax is still
required in v5 for correct TypeScript inference **when composing middleware**,
because plain `create<T>()` cannot propagate the middleware's mutator types
otherwise (the same TS limitation as v4, TS issue #10571). Exception carried
over from v4: middleware that itself constructs the state (`combine`,
`redux`) doesn't need the curried form because the state type is inferred
from the middleware's return. TypeScript 6 strict compatibility specifically
was not independently verified against this repo's toolchain — no reported
incompatibility found, but treat as unconfirmed rather than settled.

## 4. `devtools` middleware `enabled` option

**Fully settled, from source** (fetched `raw.githubusercontent.com/pmndrs/zustand/v5.0.15/src/middleware/devtools.ts`,
2026-08-19). **Correction to the previous version of this entry**, which
claimed the default keyed off `process.env.NODE_ENV` — that was wrong,
sourced from a secondary/community snippet. The actual source line is:

```ts
extensionConnector =
  (enabled ?? import.meta.env?.MODE !== 'production') &&
  window.__REDUX_DEVTOOLS_EXTENSION__
```

**(a) Literal default expression**: `import.meta.env?.MODE !== 'production'`
— **not** `process.env.NODE_ENV`, and not `import.meta.env.DEV`. It compares
Vite's `MODE` string directly against the literal `'production'`.

**(b) `enabled: false` behaviour**: the connector is **never acquired at
all**, not acquired-then-silenced. When the guard resolves falsy,
`extensionConnector` is falsy, and the middleware takes:

```ts
if (!extensionConnector) {
  return fn(set, get, api)
}
```

— it returns the **undecorated** store initializer. No
`window.__REDUX_DEVTOOLS_EXTENSION__.connect(...)` call happens, no bridge
object is created.

**(c) The decisive question — `vite build --mode staging`, unconditional
`devtools()`, does it leak.** Confirmed via Vite's own docs
(`vite.dev/guide/env-and-mode`, fetched 2026-08-19): `NODE_ENV` and `mode`
are independent. `vite build` always sets `process.env.NODE_ENV = 'production'`
**regardless of `--mode`**; only `import.meta.env.MODE` follows `--mode`.

| Command | `NODE_ENV` | `import.meta.env.MODE` |
| --- | --- | --- |
| `vite build --mode staging` | `production` | `staging` |

Since `devtools()` keys its default on `import.meta.env.MODE`, not
`NODE_ENV`, a staging build has `MODE = 'staging'`, so
`'staging' !== 'production'` is **true** — the default `enabled` resolves to
**true**, the extension connector **is** attached, and an unconditional
`devtools(...)` call **does leak store state to a listening Redux DevTools
browser extension in a staging build.** The other lane's finding
(`enabled ?? import.meta.env.MODE !== 'production'`, and that it leaks in
staging) is **confirmed correct** — my earlier NODE_ENV-based claim in this
file was wrong and has been corrected above. The finding ships.

**Vite/`process.env` general note (still true, but not the relevant
variable here)**: Vite does statically replace bare `process.env.NODE_ENV`
occurrences at build time via its `define` mechanism, so code that *does*
read `process.env.NODE_ENV` works under Vite despite `process.env` not being
polyfilled as a whole object — this just isn't what `devtools.ts` reads.

## 5. `persist` + `devtools` composition order

**Skipped at the coordinator's direction — left unsettled in this cache.**
No pmndrs documentation page reachable in the first pass stated a mandated
order; only community blog consensus (`devtools(persist(...))`, devtools
outermost) was found, unconfirmed against primary source.

## 6. `persist` `version` + no `migrate` — hydration behaviour

**Settled with moderate confidence, via DeepWiki's zustand persist-middleware
page (a source-code-derived summary, not the official docs — primary
`src/middleware/persist.ts` was not fetched directly)**: when the
deserialized storage payload's version does not match the configured
`version` and **no** `migrate` function is supplied, zustand logs a
`console.error` and **falls back to the store's initial state** — the stale
persisted payload for that version mismatch is discarded, not thrown as an
exception, not merged. This is the exact shape the kit ships (`version: 1`,
no `migrate`): a bump from an unversioned/`version: 0` payload with no
`migrate` silently resets the persisted slice to its initial value on next
load, logging an error to the console only. Not re-verified against primary
source in the follow-up pass (out of the coordinator's requested scope).

## Not found / not attempted

- Question 5 — **skipped at coordinator's direction**, left unsettled.
- Question 7 (`persist` `partialize` merge behaviour with initial state, v5
  `merge` default changes) — **not attempted, over budget / out of scope**.
- Question 8 (React 19 / `useSyncExternalStore` v5-specific caveats, React
  Compiler interaction with selectors) — **not attempted, out of scope**.
- Question 9 (`import create from 'zustand'` default export removed in v5) —
  **not attempted, out of scope**. Likely a single cheap source read
  (`unpkg.com/zustand@5/index.js`) for whoever picks it up next.
- `src/middleware/persist.ts` source itself — not read directly; question 6
  rests on a secondary source (DeepWiki).
