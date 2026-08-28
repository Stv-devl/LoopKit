# Tooling config — the files you write once

> Read this when **scaffolding the repo** or when a gate is missing a rule.
> These blocks are setup, not contract. The contract — which gate must fail, on
> what, with which threshold — lives in `.claude/rules/` and stays loaded in
> every session. This file is the implementation of that contract, and it is
> read on demand.

**Two files, three gates**: `vite.config.ts` (the compiler, the aliases and the
whole test runtime) and `eslint.config.js` (the lint). The test block is a key
of the first file, not a config of its own — the reason is under it, and it is
the kind of mistake that costs an afternoon.

## `vite.config.ts` — the compiler, the aliases, the test runtime

The compiler is a **Babel** plugin, so it goes through `@vitejs/plugin-react`
(not `@vitejs/plugin-react-oxc`, still `0.4.x` and without compiler support —
see `01-stack.md`).

```ts
import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vitest/config"; // NOT "vite" — see below
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react({ babel: { plugins: ["babel-plugin-react-compiler"] } })],
  resolve: {
    // The aliases `00-project.md` declares. Nothing else configures them, and
    // every example in this kit imports `@/lib/...` — without this block none
    // of them resolve. `tsconfig.json` needs the matching `paths` entry so the
    // editor and `tsc` agree with the bundler; the two are separate mechanisms
    // and setting only one is the classic "works in the IDE, fails at build".
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      "@shared": fileURLToPath(new URL("./shared", import.meta.url)),
    },
  },
  test: {
    /* the block below */
  },
});
```

**`defineConfig` comes from `vitest/config`, and the `test` key lives in this
same file.** Both halves matter:

- Importing from `vitest/config` is what types the `test` key. From `"vite"` it
  is a type error.
- Putting `test` here rather than in a separate `vitest.config.ts` is not a
  style choice. **A `vitest.config.ts` takes priority and does not merge
  `vite.config.ts`** — it replaces it. The plugins and the aliases above would
  simply not exist during tests, and the failure reads as "cannot resolve
  `@/lib/result`" in a file nobody touched. One config file, no merge to get
  wrong. If you genuinely need two, the second must `mergeConfig` the first;
  never re-declare.

On React 19 there is **no runtime package to install**: the compiler emits
`react/compiler-runtime`, which ships with React. `react-compiler-runtime` is
the back-port for 17/18 only — installing it here is a mistake.

## `eslint.config.js` — the ship gate

Four plugins, four jobs: `typescript-eslint` supplies the **parser** and the base
TypeScript rules, `eslint-plugin-react-hooks` carries the compiler diagnostics,
`eslint-plugin-jsx-a11y` turns the accessibility rules into build failures,
`@vitest/eslint-plugin` carries part of the TDD contract.

```bash
pnpm add -D eslint typescript-eslint @eslint/js \
            eslint-plugin-react-hooks eslint-plugin-jsx-a11y @vitest/eslint-plugin
```

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import jsxA11y from "eslint-plugin-jsx-a11y";
import vitest from "@vitest/eslint-plugin";

export default [
  { ignores: ["dist/**", "coverage/**", "e2e/**", "supabase/functions/**"] },

  // THE BASE OBJECT, and it is not optional in either of its two halves.
  //
  // 1. The PARSER. ESLint 10's default parser is espree, which does not read a
  //    type annotation: on one `.ts` file it is a hard `Parsing error` that
  //    FAILS the run — and `pnpm lint --max-warnings=0` is a /loop:ship gate, so the
  //    gate goes with it. `tseslint.configs.recommended` is what supplies it.
  //
  // 2. The `files` KEY. A flat-config object with no `files` applies only to
  //    files matched by some OTHER object in the array — there is no fallback
  //    to `**/*.{js,mjs,cjs}` for that case, and `reactHooks.configs.flat
  //    .recommended` carries no `files` of its own. With only `**/*.tsx` and
  //    `**/*.test.ts{,x}` targeted below, `hooks.ts`, `*.repository.ts`,
  //    `*.mapper.ts`, `*.utils.ts` and `src/lib/*.ts` were linted by NOTHING:
  //    `rules-of-hooks` and `exhaustive-deps` evaluated zero of them, while
  //    `00-project.md` calls lint the only thing that stops exactly those two.
  //
  // `tseslint.configs.recommended` carries no `files` either, which is why it is
  // extended from inside a scoped object rather than spread at top level.
  ...tseslint.config({
    files: ["**/*.{js,jsx,ts,tsx}"],
    extends: [js.configs.recommended, tseslint.configs.recommended],
  }),

  // The compiler + hooks diagnostics, on the same set. Files-less by design in
  // the plugin, so the scope has to come from here.
  {
    ...reactHooks.configs.flat.recommended,
    files: ["**/*.{js,jsx,ts,tsx}"],
  },

  // The a11y rules. `patterns/a11y.md` documents the shapes; without this
  // plugin nothing checks that anyone followed it — same asymmetry the compiler
  // has, and the same cure. Scoped to JSX files.
  {
    // Spread FIRST, then narrow: the other order lets the plugin's own `files`
    // (if a version ever adds one) silently replace this scoping.
    ...jsxA11y.flatConfigs.recommended,
    files: ["**/*.tsx"],
  },
  {
    // Scope it: these rules only mean something inside a test file.
    files: ["**/*.test.ts", "**/*.test.tsx"],
    plugins: { vitest },
    // `expectTypeOf(...)` is the only assertion in a type-level test, and
    // without this exact key `expect-expect` reads that test as empty and fails
    // the gate. Documented one paragraph down and absent from the block, which
    // is the same thing as absent.
    settings: { vitest: { typecheck: true } },
    rules: {
      ...vitest.configs.recommended.rules,
      // Already in `recommended`, restated at `error` so a version bump
      // cannot quietly downgrade them. Why these: 05-testing.md.
      "vitest/expect-expect": "error",
      "vitest/no-focused-tests": "error",
      "vitest/no-disabled-tests": "error",
      "vitest/no-conditional-expect": "error",
      "vitest/no-identical-title": "error",
    },
  },
];
```

Six things that bite:

- **No parser, no gate.** `typescript-eslint` is in the stack table of
  `01-stack.md` and was missing from this block: as shipped, `pnpm lint` could
  not run on a single `.tsx` file. Loud, not silent — but a gate that cannot
  start is a gate nobody keeps.
- **A config object with no `files` lints nothing on its own.** It applies only
  where another object already matched. That one sentence is why the base object
  above names `**/*.{js,jsx,ts,tsx}` explicitly, and why the react-hooks config
  is re-scoped rather than spread bare.
- The package is **`@vitest/eslint-plugin`**. `eslint-plugin-vitest` is the old
  one — do not install it.
- `eslint-plugin-react-compiler` is **dead**. The compiler diagnostics ship as
  `react-hooks/*` rules in `eslint-plugin-react-hooks` v6+.
- `flat.recommended` already carries the compiler rules (`purity`,
  `immutability`, `refs`, `set-state-in-render`, `preserve-manual-memoization`,
  `static-components`) on top of `rules-of-hooks` and `exhaustive-deps`.
  `flat['recommended-latest']` swaps in the experimental set — not the default
  here.
- **TypeScript 6, not 7**: `typescript-eslint` caps its peer at `<6.1.0`
  (`01-stack.md`, "Version floors that are not cosmetic"). On TS 7 the linter
  does not degrade — it fails to run, and takes the ship gate with it.

### What `jsx-a11y` actually catches here

It is a **static** check on JSX, so it sees the mistakes that are visible in the
markup — and misses everything about behaviour. Worth knowing which is which
before trusting it:

| Caught by the plugin | Not caught — `patterns/a11y.md` and review own these |
| --- | --- |
| An icon-only `<button>` with no accessible name | Focus not returned to the trigger when a menu closes |
| `<img>` without `alt`, a redundant `alt="image of…"` | Arrow-key navigation inside a `role="menu"` |
| `onClick` on a `<div>` with no role and no key handler | A live region mounted at the same moment as its text |
| `<label>` not associated with a control | A heading hierarchy that skips from `h2` to `h4` |
| An invalid or misspelled ARIA attribute or role | Whether the accessible name says something useful |

Two consequences. First, a green lint is not an accessible component — it is a
component with no *syntactic* a11y defect. Second, the rules it does carry are
cheap and absolute, which is why they belong in the gate: `jsx-a11y` fires on
markup an agent writes by reflex, and `--max-warnings=0` turns every one of them
into a build failure rather than a review comment nobody has time to write.

For the behavioural half, `jest-axe` runs the same engine at test time on a
rendered tree (`patterns/a11y.md`). It is **optional and not a gate**: it needs a
test per component, and axe itself only detects a documented fraction of real
barriers. Keyboard flows are proved in E2E (`skills/e2e-playwright/SKILL.md`) —
`getByRole` failing to find a control *is* the a11y failure.

Two compiler rules ship at **`warn`**: `incompatible-library` and
`unsupported-syntax`. Under `--max-warnings=0` a warning fails the gate, which
is intended for `unsupported-syntax` — it names code the compiler skips. If
`incompatible-library` turns out to be noise from a dependency, silence *that
rule* explicitly, with a comment saying which library and why. **Never raise
`--max-warnings`**: it disables the whole gate to fix one rule.

`no-focused-tests`, `no-identical-title` and `valid-expect` are auto-fixable —
`eslint-batch.sh` does **not** pass `--fix`, so nothing is silently stripped
from a test file behind your back.

## The `test` block — the runtime, what Vitest collects, the coverage floor

This is the `test: { … }` key of the `vite.config.ts` above, expanded. Thresholds
and scope are the contract (`05-testing.md`, "The three things that check the
suite itself"); this is where they are written down.

`coverageConfigDefaults` is an extra import on that file:
`import { defineConfig, coverageConfigDefaults } from 'vitest/config';`

And one module-level constant, above `defineConfig` — the four test-first layer
words, written **once** in this file:

```ts
// The four test-first layers (.claude/rules/05-testing.md), as a brace
// expansion reused by every coverage glob below.
//
// This is the ONLY copy outside `.claude/hooks/hook-lib.sh`, where the same
// four words are `CWK_TDD_LAYERS` and every hook that freezes or gates a file
// reads them from there. The two cannot be shared — one is bash, one is TS —
// so they are kept to one declaration each and this comment is the link.
// They must cover the same set: a word in the hooks and not here produces a
// file that is frozen and unmeasured, which `05-testing.md` calls the worst
// combination available.
const TEST_FIRST = '{utils,mapper,repository,services}';
```

```ts
  test: {
    // THE RUNTIME. Two lines, and without them nothing in this kit runs.
    // Vitest's default environment is `node`: `render()` dies on
    // `document is not defined`. And with no `setupFiles`, the setup file is
    // never loaded at all — no `cleanup()` between tests, no factory reset, and
    // no jest-dom matchers, so `toBeDisabled()` is not a function.
    // Both need a dependency: `pnpm add -D jsdom @testing-library/jest-dom`.
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'], // the ONE setup file → templates/fixtures.md

    // No `globals: true`, deliberately. Every test file in this kit opens with
    // an explicit `import { describe, it, expect } from 'vitest'`
    // (`patterns/tests.md`, "Imports"), and so does the setup file. Turning
    // globals on makes both styles valid at once, and the explicit imports rot
    // within a month. It also has a cost worth knowing: Testing Library's
    // auto-cleanup keys on a global `afterEach`, so `cleanup()` becomes the
    // setup file's job — which is why `templates/fixtures.md` calls it.

    // WHAT VITEST COLLECTS. Not optional, and not the default.
    // Vitest's default `include` is `**/*.{test,spec}.?(c|m)[jt]s?(x)`, and its
    // default `exclude` covers `node_modules`/`dist`/`cypress` — not `e2e/`, not
    // `supabase/functions/`. This repo produces test files for two OTHER runners:
    //   - Playwright specs in `e2e/*.{public,authed}.spec.ts`
    //     (`skills/e2e-playwright/SKILL.md`)
    //   - Deno tests under `supabase/functions/` (the Supabase addon ships one)
    // Left at the default, `pnpm test:run` collects them, fails on a `jsr:` or a
    // `@playwright/test` import, and the ship gate goes red on code nobody broke.
    // `include` is the real fix — it says where the vitest suite lives. `exclude`
    // is the belt, and it REPLACES Vitest's default exclude rather than extending
    // it, which is why node_modules/dist are restated here: widen `include` one
    // day without them and the runner walks into node_modules.
    // `shared/` is in `include` because `shared/schemas/*` is code this repo owns
    // (`02-architecture.md`); drop that line if the folder does not exist.
    include: ['src/**/*.test.{ts,tsx}', 'shared/**/*.test.ts'],
    exclude: ['**/node_modules/**', 'dist/**', 'e2e/**', 'supabase/functions/**'],

    coverage: {
      provider: 'v8',
      // Scoped to the layers where a percentage means something. A global
      // number over a repo full of UI goes up on its own.
      //
      // TWO globs per root, and the second one is the one that gets forgotten:
      // `*.utils.ts` does NOT match a bare `utils.ts`. The bare spelling is not
      // hypothetical — the TDD hooks freeze it (`CWK_TDD_IMPL_RE` in
      // `hook-lib.sh` anchors the word on `/`, `.` or start-of-path, so
      // `src/lib/utils.ts` and `features/x/utils.ts` are test-first), and
      // `services.ts` bare is the file the simple feature variant uses
      // (`templates/feature.md`). A file
      // that is frozen but outside the floor is the worst of both: the test can
      // never be corrected, and nothing checks it walked the branches.
      //
      // AND `shared/` IS IN, for exactly that reason. The hooks' regex is
      // anchored on the path, not on a root — nothing in it says `src/`, and
      // `cwk_foreign_toolchain` only exempts a Deno sub-tree. So
      // `shared/schemas/order.utils.ts` is test-first and frozen like any other,
      // while a floor scoped to `src/**` would never measure it. That is not a
      // hypothetical corner: `02-architecture.md` ends its import rules with
      // "if two features share code -> move it into shared/", so the prescribed
      // destination is the one the floor used to miss. The suite already
      // collects `shared/**/*.test.ts` in `include` above — this is the same
      // scope, one key down.
      //
      // `TEST_FIRST` is the module-level constant declared above this block —
      // the four layer words, once. `shared/` is `.ts` only: it holds schemas
      // shared with the backend, never JSX (`02-architecture.md`).
      include: [
        `src/**/*.${TEST_FIRST}.{ts,tsx}`,
        `src/**/${TEST_FIRST}.{ts,tsx}`,
        `shared/**/*.${TEST_FIRST}.ts`,
        `shared/**/${TEST_FIRST}.ts`,
        'src/lib/**/*.ts',
      ],
      // THE ONLY SANCTIONED HOLE IN THE FLOOR, and it is three files.
      // `src/lib/**` is in `include` above, which sweeps in wiring that carries
      // no branch to walk: the client INSTANCE, the QueryClient config object,
      // the vendor `cn()` helper copied verbatim. A test on those restates the
      // file; leaving them in drags a fresh repo under 90 on day one, for
      // nothing. Everything else under `src/lib/` stays in — `userMessages.ts`
      // has a fallback branch, and `route-utils.ts` holds the open-redirect
      // check, which is exactly the kind of code a floor exists for.
      // Adding a line here is a decision: name the file and the reason.
      // `coverageConfigDefaults.exclude` is spread because this key REPLACES
      // the defaults too — without it, the test files themselves get measured.
      //
      // THE FIRST LINE IS NOT A CONSTANT, and hardcoding it is how this hole
      // opened: the data client is whatever row 1 of `01-stack.md`'s "The data
      // client" table names. On a Supabase repo that is `src/lib/supabase.ts` —
      // swept in by `src/lib/**/*.ts` above, excluded by nothing, reported at
      // 0 % on a fresh scaffold and dragging the aggregate under the floor, on
      // the one file the rule declares excluded. Read the row, write the path.
      exclude: [
        ...coverageConfigDefaults.exclude,
        'src/lib/client.ts',      // FILL: the data client INSTANCE — `01-stack.md`,
                                  // "The data client", row 1. `supabase.ts` here
                                  // if the Supabase addon is installed.
        'src/lib/queryClient.ts',
        'src/lib/utils/cn.ts',
      ],
      thresholds: { lines: 90, functions: 90, branches: 85 },
    },
  },
```

**Three dependencies come with this block**, and none is optional:

```bash
pnpm add -D jsdom @testing-library/jest-dom @vitest/coverage-v8
```

- `jsdom` — the `environment`. Missing it, the failure reads as
  `document is not defined`, not as a config problem.
- `@testing-library/jest-dom` — the matchers `toBeDisabled` /
  `toHaveTextContent` / `toBeInTheDocument`, registered by the setup file.
  Missing it, `expect(...).toBeDisabled is not a function` on a test that is
  perfectly correct.
- `@vitest/coverage-v8` — **`provider: 'v8'` above does not ship with the Vitest
  core.** Missing it, `pnpm test:coverage` dies before collecting a single file,
  and the CI's coverage gate goes with it. This is the one that was missing from
  the list: nothing else in the kit installed it, and `ci.yml` used to run
  `test:coverage` as its *only* test invocation, so an absent provider took the
  mandatory run-once-tests role down too. `ci.yml` now runs `test:run` and
  `test:coverage` as separate steps for that reason (`templates/ci.md`).

`hooks.ts` and `gateway.ts` are **mandatory to test** (`05-testing.md`) and
deliberately **outside this floor**: a percentage on a React Query orchestration
or on a one-line transport call measures rendering plumbing, not logic. The gate
on those two is the review's `tests` dimension, not a number.

<!-- FILL: adjust the include/exclude globs to this repo's real layout. -->
