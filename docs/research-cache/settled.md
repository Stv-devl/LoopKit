# Settled external facts — the ledger

**One purpose: stop the loop re-learning what it already knows.** The first time
a probe settles a question about a version pinned in `.claude/rules/01-stack.md`,
the answer is written **here**, and never researched again.

**This file is cold on purpose.** It is not loaded at session start — it grows
without bound, and a cache nobody is reading costs the same as one everybody is.
It is read at exactly one moment, by exactly two readers, both of which name it:

| Reader | When |
| --- | --- |
| `/research` (main thread) | before any fetch. A question this file answers is **not** researched — not "researched quickly", not researched |
| `doc-researcher` | before its **first** network call, together with the topic files next to it |

The three or four facts that fire **silently while code is being written**, with
no pattern file open at that moment, are the exception: they stay hot, in
`01-stack.md`'s short *Traps that stay loaded* table. Everything else lives here.

**Who writes a row:** the main thread, at the synthesis step of `/research`, in
the same pass. The `doc-researcher` agent never does — it is forbidden from
editing a rule or this ledger, and returns a `Promote to the ledger` block
instead. Deferred, it never happens.

- **One row per version-pinned behaviour**, not per library. "zod v4" is not a
  fact; "`z.string().email()` is deprecated in v4 but still works" is one.
- **A row dies with its version.** Bumping a dependency means deleting or
  rewriting its rows in the same commit — a stale row is worse than no row.
- **What moves on its own does not belong here.** A vendor API with its own
  breaking-change schedule goes to a topic file in this directory with
  `stability: volatile` and a re-check window.
- **A row is never promoted back into a rule to make it easier to find.** The
  rule names this file; that is the whole mechanism, and it is what keeps the
  session floor flat as the ledger grows.

> This file survives an addon install by construction. `addons/supabase/` and
> `addons/fastapi/` overwrite `.claude/rules/01-stack.md`; they do not touch
> `docs/`. Before this ledger existed, installing the Supabase addon silently
> deleted every answer the loop had paid to establish. `/kit:doctor`'s
> `settled-ledger` check now refuses any rule file that grows a dated table
> again.

| Fact | Answer in effect | Established |
| --- | --- | --- |
| React Query v5 — `retry: (failureCount, …)` | `failureCount` is **0** on the first call (incremented after the predicate): `< 1` = one retry / two requests, `< 2` = two retries / three requests | 2026-08-19 |
| React Query v5 — a promise returned by `onSuccess`/`onSettled` **in `useMutation`'s options** | awaited before the mutation dispatches `success`, so `isPending` stays true until it resolves. Callbacks passed to `mutate(vars, { onSuccess })` run after the dispatch and are **not** awaited | 2026-08-19 |
| React Query v5 — mutation `retry` default | `0`. `mutations: { retry: false }` in `defaultOptions` is a no-op restatement, not a protection | 2026-08-19 |
| React Query v5 — a `setQueryData`/`setQueriesData` updater returning `undefined` | bails out: the entry is left untouched and none is created | 2026-08-19 |
| React Query v5 — a disabled (`enabled: false`), never-fetched query | `status: 'pending'`, `fetchStatus: 'idle'`, `isPending: true` **forever**. Branch a loading UI on `isLoading` (= `isPending && isFetching`), never on `isPending` alone, anywhere a query can be disabled | 2026-08-19 |
| React Query v5 — `useIsMutating({ mutationKey })` | matches by **prefix** (`partialMatchKey`, same as query filters), forces `status: 'pending'` internally, returns the in-flight count. The tracked `useMutation` must carry the same `mutationKey` — nothing wires that automatically | 2026-08-19 |
| React Query v5 — `gcTime: Infinity` | legal and special-cased in source (`scheduleGc` arms no timer, `isValidTimeout` excludes it); the only documented spelling of "never collect". Already the server-side default | 2026-08-19 |
| React Query v5 — `refetchOnReconnect` | default `true`, but refetches only **mounted and stale** queries on the browser's online transition. It does **not** cover a realtime channel reconnecting with no network drop, so the `onReconnect` → `invalidateQueries` plumbing stays necessary | 2026-08-19 |
| React Query v5 — the default `error` type, and overriding it | `Error`. Project-wide override is `declare module '@tanstack/react-query' { interface Register { defaultError: ServiceError } }` | 2026-08-19 |
| Zustand v5 — `useStore` / bound-hook 2nd `equalityFn` argument | removed from **every** overload (`zustand@5/react.d.ts`: `useStore` is `(api)` / `(api, selector)`, the bound hook `()` / `(selector)`). `useUIStore(selector, shallow)` is a **TS compile error** under strict mode ("Expected 0-1 arguments, but got 2") — not a runtime no-op, and not an automatic re-render loop. Fix: `useShallow(selector)` | 2026-08-19 |
| Zustand v5 — `useShallow` import path | both `zustand/react/shallow` (direct) and `zustand/shallow` (barrel, re-exports `shallow` + `useShallow`) are valid and non-deprecated | 2026-08-19 |
| Zustand v5 — `devtools` `enabled` default | resolves as `enabled ?? import.meta.env?.MODE !== 'production'` (`src/middleware/devtools.ts`) — **not** `NODE_ENV`. `enabled: false` never acquires the connector. `vite build` forces `NODE_ENV='production'` whatever `--mode`, but `MODE` follows `--mode`: under `--mode staging` an **unconditional `devtools()` stays enabled and streams state** to any listening extension | 2026-08-19 |
| Vitest 4 — `coverage.all` | **Removed in v4.** Default is now "files loaded during the test run only"; an untested file appears in the report **only if `coverage.include` names its glob explicitly** | 2026-08-19 |
| Vitest 4 — `coverage.thresholds` shape | Nested only: `thresholds.{lines,functions,branches,statements}`. The old flat `coverage.lines` spelling is **not recognized** — a threshold written that way never fails a gate | 2026-08-19 |
| Vitest 4 — `coverage.thresholds.perFile` | `boolean \| function`, default **`false`**: the floor is an aggregate over the whole `include` set, so a partially covered file hides behind well-covered neighbours | 2026-08-19 |
| Vitest 4 — snapshot updates outside `-u` | `test.update: true \| 'all'` in the config rewrites snapshots on a plain `vitest run`, with **no CLI flag ever appearing** — a Bash-hook check on the literal `-u`/`--update` string cannot see this vector | 2026-08-19 |
| Vitest 4 — `vi.restoreAllMocks()` vs an automock | Does **not** affect modules automocked via `vi.mock()`; it restores only manual `vi.spyOn` spies. `vi.resetAllMocks()` is what resets an automock between tests | 2026-08-19 |
| Vitest 4 — `vi.spyOn` on an ESM namespace import with no `vi.mock()` | Works under the default module runner (node/jsdom/happy-dom). The "Cannot redefine property" sealed-namespace failure is **Browser-Mode-only** | 2026-08-19 |
| `@vitest/eslint-plugin` — rule IDs and `it.todo` | `vitest/expect-expect`, `vitest/no-focused-tests`, `vitest/no-disabled-tests`, `vitest/no-conditional-expect`, `vitest/no-identical-title` (plugin key `vitest`). `no-disabled-tests` matches `.skip`/`x*`/`pending()` only — **`.todo()` is never flagged**, confirmed in rule source | 2026-08-19 |
| ESLint flat config — an object with no `files`/`ignores` | Applies **only** to files matched by another config object in the same array. There is no fallback to `**/*.{js,mjs,cjs}` for this case | 2026-08-19 |
| `eslint-plugin-react-hooks` v6 — `configs.flat.recommended` scope | Carries **no `files` key**. Combined with the cascade rule above, a config array with no plain `**/*.{ts,tsx}` target silently excludes `hooks.ts`/`repository.ts`/`mapper.ts`/`utils.ts` from `rules-of-hooks` and `exhaustive-deps` | 2026-08-19 |
| ESLint 10 default parser (espree) on `.ts`/`.tsx` | Hard `Parsing error`, **fails the run** — not a silent skip. A flat config with no `languageOptions.parser` cannot lint one `.ts` file carrying a type annotation | 2026-08-19 |
| `typescript-eslint` — minimal flat-config incantation | `tseslint.configs.recommended` carries no `files` of its own; scope it — `defineConfig({ files: ['**/*.{js,jsx,ts,tsx}'], extends: [js.configs.recommended, tseslint.configs.recommended] })` | 2026-08-19 |
| `typescript-eslint` 8 — TS peer cap, and TS 7's real state | Peer is `>=4.8.4 <6.1.0`. TS 7.0 went GA 2026-07-08 with no stable programmatic API (lands ~7.1, Oct 2026); typescript-eslint's TS-7 request was closed "not planned" — a Microsoft-side blocker, not a scheduling choice | 2026-08-19 |
| MSW — current major and idiom | v2 (latest `2.15.0`). `http`/`HttpResponse` is v2-only; the v1 `rest`/`res(ctx.json())` idiom does not run on v2 | 2026-08-19 |
| MSW v2 (2.15.x) — a resolver that **throws**, under `setupServer`/Node | `handleRequest.ts` emits `unhandledException` and **re-throws**; no inline 500 `Response` is constructed at that layer, so there is no assertable `response.status === 500`. The "throw becomes a 500" framing is MSW **v1** / Service-Worker-specific. The error surfaces at the caller's `fetch`/`await`, not in `handlers.ts` | 2026-08-20 |
| Vitest 4 — `coverage.include` + a file **no test ever loaded** + `thresholds.perFile` at its `false` default | The file **is** counted in the aggregate threshold, at 0 % on every metric. This is what replaces the removed `coverage.all: true` for catching a zero-test module — so the floor does catch a wholly untested layer file | 2026-08-20 |
| `@vitest/eslint-plugin` 1.6.x — `expect-expect` on a test whose only assertion is `expectTypeOf(...)` | Requires `settings: { vitest: { typecheck: true } }` — exact key, boolean — or the test is flagged as having no assertion | 2026-08-20 |
| pytest 9.x — exit code for a **collection-time** import error | `2` (`ExitCode.INTERRUPTED`), never `5` (`NO_TESTS_COLLECTED`) or `1` — confirmed in `_pytest/config/__init__.py`'s `ExitCode` enum | 2026-08-20 |
| pytest 9.x — `ImportError: cannot import name 'X' from 'Y'` vs `ModuleNotFoundError: No module named` | Different CPython exception branches with different message text: the literal phrase **"No module named" is absent** from the "cannot import name" variant, so a classifier grepping for that phrase misclassifies it as an assertion failure | 2026-08-20 |
