---
topic: testing-tooling
checked: 2026-08-19
stability: pinned
sources:
  - https://registry.npmjs.org/@vitest/eslint-plugin/latest
  - https://registry.npmjs.org/msw/latest
  - https://registry.npmjs.org/typescript-eslint/latest
  - https://registry.npmjs.org/vitest/latest
  - https://raw.githubusercontent.com/vitest-dev/eslint-plugin-vitest/main/README.md
  - https://raw.githubusercontent.com/vitest-dev/eslint-plugin-vitest/main/docs/rules/no-disabled-tests.md
  - https://raw.githubusercontent.com/vitest-dev/eslint-plugin-vitest/main/src/rules/no-disabled-tests.ts
  - https://vitest.dev/config/coverage
  - https://vitest.dev/config/update
  - https://vitest.dev/guide/cli
  - https://vitest.dev/guide/migration.html
  - https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/
  - https://eslint.org/docs/latest/use/configure/configuration-files
  - https://eslint.org/docs/latest/use/configure/configuration-files#specifying-files-and-ignores
  - https://unpkg.com/eslint-plugin-react-hooks@latest/index.js
  - https://unpkg.com/eslint-plugin-react-hooks@latest/cjs/eslint-plugin-react-hooks.production.js
  - https://api.github.com/repos/facebook/react/contents/packages/eslint-plugin-react-hooks/src
  - https://raw.githubusercontent.com/facebook/react/main/packages/eslint-plugin-react-hooks/src/index.ts
  - https://typescript-eslint.io/getting-started/
  - https://vitest.dev/api/vi.html
  - https://vitest.dev/guide/mocking/modules
  - https://raw.githubusercontent.com/pytest-dev/pytest/main/src/_pytest/config/__init__.py
  - https://raw.githubusercontent.com/pytest-dev/pytest/main/src/_pytest/main.py
  - https://github.com/pytest-dev/pytest/issues/6370
  - https://github.com/vitest-dev/eslint-plugin-vitest/blob/main/docs/rules/expect-expect.md
  - https://mswjs.io/docs/runbook
  - https://mswjs.io/docs/faq/
  - https://github.com/mswjs/msw/blob/main/src/core/utils/handleRequest.ts
---

Checked 2026-08-19 (R1) and 2026-08-20 (R2). Most rows are also in `settled.md`.

## Vitest 4

- **`coverage.all` removed** (not deprecated). Default is now files loaded during
  the run; an untested file is in the report only if `coverage.include` names its
  glob. A never-loaded include-matched file counts in the aggregate at 0 % on
  every metric (with `perFile` at its default), so `templates/tooling-config.md`'s
  explicit `include` (four layer globs in `*.word.ts` and bare spellings, plus
  `src/lib/**/*.ts`) is load-bearing. Stale advice to also set `all: true` must
  be ignored (`vitest.dev/guide/migration.html`, `config/coverage`).
- **`coverage.thresholds` is nested only** (`.lines/.functions/.branches/
  .statements`); the flat `coverage.lines` is unrecognized and never fails.
  `thresholds.perFile` is `boolean | function`, default `false`: the floor is an
  aggregate over the whole `include` set.
- **`test.update`** (`boolean | 'new' | 'all' | 'none'`, default `false`; unset
  resolves to `'new'` locally and `'none'` when `CI` is truthy). `update: true |
  'all'` in the config rewrites snapshots on a plain `vitest run` with no `-u`
  ever on a command line, invisible to a Bash-hook match on `-u`/`--update`. Not
  checked: whether `vitest.config.ts` is protected by another hook.
- **`vi.restoreAllMocks()` does not affect `vi.mock()` automocks**; it restores
  only `vi.spyOn` spies and does not clear history or reset implementations. A
  `mockResolvedValue` on an automocked gateway leaks across tests; use
  `vi.resetAllMocks()` or per-mock `.mockReset()` (`vitest.dev/api/vi.html`).
  Not checked: whether the kit's `msw.md`/`tests.md` exemplars use the wrong one.
- **`vi.spyOn` on an ESM namespace import, no `vi.mock()`**: works under the
  default module runner (jsdom, as `tooling-config.md` sets). "Cannot redefine
  property" is Browser-Mode-only, where the namespace is sealed
  (`guide/mocking/modules`).

## ESLint and typescript-eslint

- **`@vitest/eslint-plugin` 1.6.27**: rules `vitest/expect-expect`,
  `no-focused-tests`, `no-disabled-tests`, `no-conditional-expect`,
  `no-identical-title`, plugin key `vitest`. `no-disabled-tests` matches `.skip`,
  `x`-prefixed names and bare `pending()`; `.todo()` is never flagged (rule
  source). `expect-expect` flags a test whose only assertion is `expectTypeOf`
  unless `settings: { vitest: { typecheck: true } }` (exact key, boolean).
- **Flat config cascade**: an object with no `files`/`ignores` applies only to
  files matched by another object in the array (ESLint docs, no `**/*.{js,mjs,cjs}`
  fallback for this case).
- **`eslint-plugin-react-hooks` v6**: `configs.flat.recommended` is `{ plugins,
  rules }` with no `files`. With the cascade rule, a config array lacking a plain
  `**/*.{ts,tsx}` target silently excludes `hooks.ts`, `*.repository.ts`,
  `*.mapper.ts`, `*.utils.ts`, `src/lib/*.ts` from `rules-of-hooks` and
  `exhaustive-deps`. This was true of the `eslint.config.js` shipped in
  `tooling-config.md` at check time (only `**/*.tsx` and test globs).
- **ESLint 10 default parser (espree) on `.ts`/`.tsx`** is a hard `Parsing error`,
  not a skip, so a config with no TS parser cannot lint any typed file. The
  shipped config then had no `typescript-eslint`/`languageOptions.parser`.
- **`tseslint.configs.recommended` has no `files`**; scope it:
  `defineConfig({ files: ['**/*.{js,jsx,ts,tsx}'], extends: [js.configs.recommended,
  tseslint.configs.recommended] })` (`typescript-eslint.io/getting-started`; the
  `.jsx/.tsx` extension is ours).
- **`typescript-eslint` 8.67.0**: peer `typescript >=4.8.4 <6.1.0`. TS 7.0 GA
  2026-07-08 with no stable programmatic API (expected 7.1, ~Oct 2026);
  typescript-eslint's TS-7 request closed "not planned". Interim shim from
  Microsoft: `@typescript/typescript6` (`tsc6`), attributed via secondary write-ups.

## MSW

- **v2 is current (2.15.0)**: `http`/`HttpResponse`; the v1 `rest`/`res(ctx.json())`
  idiom does not exist. `msw.md` already uses v2.
- **A resolver that throws, under `setupServer`/Node** (`src/core/utils/
  handleRequest.ts`): emits `unhandledException` and re-throws; no inline 500
  `Response`, so no assertable `response.status === 500`. The "throw becomes 500"
  framing is v1 Service-Worker-specific. Client-observed symptom reported in
  `mswjs/msw#400`, `#971`: `TypeError: Network request failed`; the error
  surfaces at the caller's `await`, not in `handlers.ts`. Unresolved: whether
  `@mswjs/interceptors` re-synthesizes a 500 downstream (two guessed source URLs
  404'd).

## pytest 9.x

- **Collection-time import error exits `2`** (`ExitCode.INTERRUPTED`, banner
  `Interrupted: 1 error during collection`), never `5` (`NO_TESTS_COLLECTED`)
  nor `1` (`_pytest/config/__init__.py`).
- **`ImportError: cannot import name 'X' from 'Y'` vs `ModuleNotFoundError: No
  module named 'Y'`** are different CPython branches; the phrase "No module named"
  is absent from the first, so a classifier grepping it misclassifies the failure.
  Exit code alone catches both. Consequence of the two message templates, not a
  documented pytest sentence; pytest reprints the exception message verbatim.

## Also settled (kept from the long form)

- Vitest 4: `-u` and `--update` are aliases, both accept `=false|=new|=none`;
  bare, they mean `all` (rewrite every changed snapshot, delete obsolete ones).
  Bare `vitest` runs in watch mode outside CI.
- Vitest 4 coverage: `exclude` wins over `include` on a file matched by both.
- `@vitest/eslint-plugin` peers: `eslint >=8.57.0` required; `vitest`,
  `typescript >=5.0.0`, `@typescript-eslint/eslint-plugin` optional.
- pytest `ExitCode`: `OK=0, TESTS_FAILED=1, INTERRUPTED=2, INTERNAL_ERROR=3,
  USAGE_ERROR=4, NO_TESTS_COLLECTED=5, MAX_WARNINGS_ERROR=6`. docs.pytest.org was
  rate-limited (429) on both attempts; the source file settled it.
- Snapshots: property matchers (`toMatchSnapshot({ id: expect.any(String) })`)
  apply to plain objects only, not to a DOM container; `useId()` emits a fresh id
  each run — normalise `id="[^"]+"` before snapshotting markup.
