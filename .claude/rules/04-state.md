<!-- budget: 35 lines · /kit:doctor rules-budget -->
# State Management

| Origin/behaviour | Owner |
| --- | --- |
| Server data | TanStack Query in feature hooks |
| Shareable filter/sort/page/tab | route search params |
| Shared client UI/preferences | feature or app Zustand store |
| Local UI | component `useState`; non-rendered mutable value → `useRef` |
| Session, locale, injected config | one-purpose Context provider |
| Realtime transport | gateway → repository → Query cache |

Never mirror server data into Zustand, Context or `useState`; never store a
derived value. Providers do not fetch server data except the session. A selection
id/open flag is client UI state, not a copied row. Context carries outside wiring;
Zustand carries client-owned state and persisted preferences.

Read the matching pattern only when creating that mechanism:
`patterns/react-query.md`, `url-state.md`, `zustand.md`, `local-state.md`, or
`context.md`. Placement rationale: `.claude/guides/04-state.md`.
