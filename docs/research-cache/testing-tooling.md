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
---

## 1. `@vitest/eslint-plugin` — rule IDs, prefix, `it.todo` exemption, flat config shape

Latest published: `1.6.27` (npm), repo `vitest-dev/eslint-plugin-vitest`.
Peer deps: `eslint >=8.57.0` (required); `vitest`, `typescript >=5.0.0`,
`@typescript-eslint/eslint-plugin` are all **optional** peers.

The five rules named in `01-stack.md` all exist under the `vitest/` prefix, in
the `recommended` config: `vitest/expect-expect`, `vitest/no-focused-tests`,
`vitest/no-disabled-tests`, `vitest/no-conditional-expect`,
`vitest/no-identical-title`.

Flat config (ESLint 9/10) from the README:
```js
import { defineConfig } from 'eslint/config'
import vitest from '@vitest/eslint-plugin'

export default defineConfig({
  files: ['tests/**'],
  plugins: { vitest },
  rules: { ...vitest.configs.recommended.rules },
})
```
Plugin key is `vitest`. The `files:` glob is shown in the example but is a
consumer choice (scope the recommended rules to test files), not something the
plugin enforces or requires — omitting it just means the rules apply
repo-wide.

**`it.todo` is confirmed NOT flagged by `no-disabled-tests`**, read directly
from the rule's source (`src/rules/no-disabled-tests.ts`, main branch): the
rule's AST checks match `.skip` (`skipMember`/`skipProperty`), any
`x`-prefixed test-fn name (`xit`, `xtest`, `xdescribe`, …), and a bare
`pending()` call. `.todo()` is not one of the matched patterns — the string
"todo" appears only inside the rule's own error messages, which explicitly
recommend `.todo()` as the alternative to a disabled test. The kit's doctrine
("`it.todo` is deliberately not caught") is correct.

**VERIFIED.**

## 2. Vitest 4 coverage — `include`/`exclude`, `thresholds` shape, `all`

`coverage.include` and `coverage.exclude` both still exist; `exclude` wins
over `include` on a file matched by both (standard glob-exclusion precedence,
`vitest.dev/config/coverage`).

`coverage.thresholds` is a **nested object**:
`thresholds.lines` / `.functions` / `.branches` / `.statements`. The old flat
spelling (`coverage.lines` at the top level) is not documented and not
supported — current docs and CLI shortcuts (`--coverage.thresholds.lines 100`)
only use the nested form. A config using the flat spelling would be silently
ignored (unknown key), exactly the "gate never fails" risk flagged in the
task.

**`coverage.all` was removed outright in Vitest v4** (not deprecated — gone).
Previously `all` defaulted to `true` with `include` defaulting to `**`, so
every matching file appeared in the report whether or not a test touched it —
that is what let the floor catch a module with *zero* tests. In v4, the
default is now "only files loaded during the test run are included"; an
untested file is invisible to the report **unless `coverage.include` is set
explicitly** to the source globs (`vitest.dev/guide/migration.html`,
corroborated by `vitest.dev/config/coverage`).

Consequence for this repo: `.claude/skills/templates/tooling-config.md`
already sets `coverage.include` explicitly (the four test-first-layer globs,
in both `*.word.ts` and bare `word.ts` spellings, plus `src/lib/**/*.ts`) and
`thresholds: { lines: 90, functions: 90, branches: 85 }` in the current
nested shape — so the template is already correct for Vitest 4's new default,
not decorative. The floor only covers what those `include` globs name, which
is the scope `05-testing.md` already declares — this is not a gap, just the
mechanism the removal of `all` now requires explicitly rather than by default.

**VERIFIED**, with the `coverage.all` removal being the material finding.

## 3. `vitest run` vs `vitest`, and `-u` / `--update`

`vitest run` is the non-watch, one-shot invocation (`pnpm test:run` in
`00-project.md` is exactly this); bare `vitest` defaults to watch mode outside
CI. `-u` and `--update` are aliases, both accepting `=false|=new|=none`; used
bare they mean `true`/`'all'` (rewrite every changed snapshot and delete
obsolete ones).

**A second, non-CLI mechanism exists and would slip past a flag-name check**:
the `update` **config key** (`test.update` in `vitest.config.ts`,
`vitest.dev/config/update`) is the programmatic equivalent of `-u`. Type is
`boolean | 'new' | 'all' | 'none'`, default `false`. When unset, Vitest
resolves the *effective* default itself: behaves like `'new'` locally
(writes snapshots that don't exist yet, never overwrites) and like `'none'`
in CI (`process.env.CI` truthy — refuses to write, fails on mismatch). Setting
`update: true` or `update: 'all'` **in the config file** rewrites snapshots on
a plain `vitest run`, with `-u` never appearing on any command line — so
`prevent-destructive-commands.sh`'s literal match on `-u`/`--update` in a Bash
command cannot see it. Whether `vitest.config.ts` is itself protected by a
different hook was not checked (out of this agent's scope/budget) — flagging
the mechanism, not the repo's exposure to it.

**VERIFIED** (CLI shape) **+ one gap named** (config-level `update` key).

## 4. MSW major

Latest published: `2.15.0` (npm, `mswjs/msw`) — MSW v2 is current.
`.claude/skills/patterns/msw.md` already uses exclusively v2-only API:
`import { http, HttpResponse } from "msw"`, `http.get(...)`,
`HttpResponse.json(...)`, `new HttpResponse(null, { status: 500 })`. None of
these exist in v1, which used `rest.get(...)` and
`(req, res, ctx) => res(ctx.json(...))`. The kit's template is **not** stale —
it already ships the current-major idiom.

**VERIFIED.**

## 5. `typescript-eslint` 8 peer range vs TypeScript 6/7

Latest published: `8.67.0`. `peerDependencies.typescript`:
`">=4.8.4 <6.1.0"` — confirms `01-stack.md`'s claim exactly: TS 6.0.x is
supported, TS 6.1 and anything beyond (including all of TS 7) is outside the
declared peer range.

Extended by a live, dated fact `01-stack.md` didn't have: **TypeScript 7.0
reached GA on 2026-07-08** with no stable programmatic API — that lands only
in 7.1, expected around October 2026. typescript-eslint's own TS-7 support
request was closed **"not planned"** on GA day, because type-aware rules are
built against the stable API and the blocker is on Microsoft's side.
Microsoft ships a compatibility shim, `@typescript/typescript6` (a `tsc6`
executable re-exporting the TS 6.0 API), as the interim workaround for tools
like typescript-eslint that need it (`devblogs.microsoft.com`, and the
digitalapplied.com / dev.to pieces tracking the breakage — attributed, not
official, but consistent across independent write-ups).

**VERIFIED**, and stronger than the rule currently states: it is not merely
"TS 7 ships no stable API" as a risk, it is **the current, GA, dated state of
the ecosystem** as of 2026-08-19.

## 6. `eslint-plugin-react-hooks` v6 — does `flat.recommended` carry its own `files` key, and what does a files-less config object match?

Two independent mechanisms, both checked at the primary source, and they
compound into a confirmed defect.

**(a) `configs.flat.recommended` has NO `files` key.** Read directly from
`packages/eslint-plugin-react-hooks/src/index.ts` (`facebook/react`, `main`
branch):
```
configs.flat.recommended = {
  plugins: { 'react-hooks': plugin },
  rules: configs.recommended.rules,
}
```
No `files`, no `ignores` — on any of `configs.recommended`,
`configs['recommended-latest']`, or `configs.flat.recommended`.

**(b) A flat-config object with no `files` and no `ignores` applies ONLY to
files matched by some OTHER config object in the array — never to "all
default JS extensions".** Quoted verbatim from ESLint's own docs
(`eslint.org/docs/latest/use/configure/configuration-files`, confirmed on two
separate fetches of the same page): *"Configuration objects without `files`
or `ignores` are automatically applied to any file that is matched by any
other configuration object."* There is no fallback to `**/*.{js,mjs,cjs}` —
that fallback applies to a config object that *does* have keys other than
`files`/`ignores` in some other contexts, not to this cascade rule.

**Compounded, this confirms the lane's claim exactly.** In the kit's shipped
`eslint.config.js` (`templates/tooling-config.md:67-98`), the only two other
config objects in the array name `files: ["**/*.tsx"]` (jsx-a11y) and
`files: ["**/*.test.ts", "**/*.test.tsx"]` (vitest). `reactHooks.configs.flat
.recommended` therefore cascades onto `.tsx` and `*.test.ts(x)` files only.
**No object in the array targets a plain `**/*.ts`**, so `hooks.ts`,
`*.repository.ts`, `*.mapper.ts`, `*.utils.ts` and `src/lib/*.ts` are never
matched by ANY config object — react-hooks (`rules-of-hooks`,
`exhaustive-deps`) never runs on them, and `pnpm lint --max-warnings=0` stays
green on a conditional hook inside `hooks.ts`, which is exactly the file this
kit's own testing rules call the mandatory-to-test orchestration layer.

**VERIFIED** (the lane's claim, both halves — (a) confirmed in plugin source,
(b) confirmed in ESLint's own docs, twice).

## 7. ESLint 10 with default espree parser on `.ts`/`.tsx` — hard error or skip? And the correct minimal `typescript-eslint` incantation

**Local fact first**: grepped the entirety of `templates/tooling-config.md`'s
`eslint.config.js` section — zero occurrences of `typescript-eslint`,
`tseslint`, `languageOptions`, or `parser`. The shipped config never sets a
TS-aware parser.

**Espree (ESLint's default parser) raises a hard parsing error on TypeScript
syntax** — not a silent skip. Any `.ts`/`.tsx` file containing a type
annotation, an `interface`, a generic, etc. fails with a `Parsing error`,
which under `--max-warnings=0` fails the whole gate (`eslint.org/docs/latest
/use/configure/parser`, corroborated by `typescript-eslint/typescript-eslint`
issue threads). This is the opposite failure mode from §6: §6 is silent
(lint passes, nothing was checked); this one is loud (lint dies outright) —
meaning the shipped config as written could not even complete a run over a
single `.ts` file with a type annotation, which is every file in this repo.
That in turn means claim 6's "green gate" framing needs one caveat: the
config would likely never get this far without *also* being given a
TS-capable parser somewhere the kit's docs don't show — worth the audit
lane flagging as "config as pasted does not run", not only "under-lints".

**The correct minimal incantation**, from `typescript-eslint.io/getting-
started/` (current docs):
```js
import { defineConfig } from 'eslint/config';
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default defineConfig({
  files: ['**/*.{js,ts}'],
  extends: [js.configs.recommended, tseslint.configs.recommended],
});
```
**`tseslint.configs.recommended` does NOT carry its own `files` key** — the
docs are explicit that the outer `defineConfig({ files, extends })` call is
what restricts the extended configs to the named globs; the config objects
inside `tseslint.configs.recommended` have no file-targeting of their own,
same shape as react-hooks' in §6. For this repo (React + `.tsx`), the glob
needs `.tsx` added: `files: ['**/*.{js,jsx,ts,tsx}']` — a direct extension of
the documented pattern, not a separately sourced claim.

**VERIFIED**, both the hard-error behaviour and the paste-able fix.

## 8. Vitest 4 — `coverage.thresholds.perFile` default

**`perFile` is the exact key** (`coverage.thresholds.perFile`), type
`boolean | function`, **default `false`**, available for both the `v8` and
`istanbul` providers (`vitest.dev/config/coverage`, corroborated by
`vitest.dev/guide/cli`'s `--coverage.thresholds.perFile` flag form). Default
`false` means thresholds are evaluated as an **aggregate across the whole
`coverage.include` set** — one heavily-tested majority can carry one wholly
untested new module under the 90/90/85 floor undetected, exactly the lane's
claim. Setting `perFile: true` (or the CLI form) is what makes the same
thresholds apply to every individual file.

**VERIFIED.**

## 9. Vitest 4 mock-reset semantics

**(a) `vi.restoreAllMocks()` after `vi.mock('./item.gateway')` (automock) —
does NOT reset it.** Quoted verbatim from `vitest.dev/api/vi.html`:
*"This restores all original implementations on spies created with
`vi.spyOn`. … WARNING: This method also does not affect mocks created during
automocking. Note that unlike `mock.mockRestore`, `vi.restoreAllMocks` will
not clear mock history or reset the mock implementation"* [for automocks].
So `beforeEach(() => vi.restoreAllMocks())` restores manually-created
`vi.spyOn` spies only — a `mockResolvedValue` set on an automocked gateway
method in one test **leaks into the next test** under that reset strategy.
The correct call for an automocked module is `vi.resetAllMocks()` (clears
history and resets implementations) or per-mock `.mockReset()`, not
`vi.restoreAllMocks()`. This is a genuine behavioural fact to check the
kit's own `msw.md` / `tests.md` exemplars against — not verified here
whether the kit's shipped repository-test example relies on the wrong one
(out of this question's scope).

**(b) `vi.spyOn(namespaceImport, 'fn')` on an ESM namespace import with no
`vi.mock()` — works fine in the kit's actual environment.** The "Cannot
redefine property" / "Module namespace is not configurable" failure is
**Browser-Mode-specific**, quoted from `vitest.dev/guide/mocking/modules`:
*"This will not work in the Browser Mode because it uses the browser's
native ESM support to serve modules. The module namespace object is sealed
and can't be reconfigured."* Outside Browser Mode (i.e. under `environment:
'jsdom'`, which is what this kit's `vite.config.ts` sets —
`templates/tooling-config.md`), Vitest's module runner "hook[s] into the
module evaluation and replace[s] it with the mock," explicitly stated to
"allow… users to call `vi.spyOn` on a seemingly ES Module." The kit's
hook-test exemplar (`vi.spyOn` on a namespace import, no `vi.mock`) runs as
written.

**(a) VERIFIED as a real leak risk** (the exact opposite reset call is
needed for automocks) — **(b) REFUTED** (the failure mode the lane worried
about is Browser-Mode-only; this kit never runs Browser Mode).

## Not found
- Nothing across either round — all nine claims settled within budget.
  Two are load-bearing defects confirmed in primary source (§6 silent
  under-linting of the four test-first-layer file spellings; §7 the same
  config cannot parse a single `.ts` file at all without a parser, which is
  the more urgent of the two since it fails loud rather than silent) rather
  than under-lints alone. §9(a) is a real leak risk in the mock-reset
  strategy; §9(b) is a false alarm specific to a mode this kit never uses.

---

## R2 — 2026-08-20 (audit:part testing, lane D)

New sources fetched this round (added to the running set; the frontmatter
`sources:` list above stays as the R1 list per the "append, never rewrite"
rule — the full source set for R2 is listed in each numbered answer below).

### 10. pytest 9.x — exit code and stdout/stderr phrase for a collection-time `ImportError: cannot import name 'X' from 'Y'`

**Exit code: `2` (`ExitCode.INTERRUPTED`).** Read from
`_pytest/config/__init__.py` (`pytest-dev/pytest`, `main` branch): the
`ExitCode` IntEnum is `OK=0, TESTS_FAILED=1, INTERRUPTED=2,
INTERNAL_ERROR=3, USAGE_ERROR=4, NO_TESTS_COLLECTED=5,
MAX_WARNINGS_ERROR=6`. A collection failure (any error raised while
importing a test module, including `ImportError`) makes pytest raise
`Session.Interrupted` and print the banner
`!!!!!!!!!! Interrupted: 1 error during collection !!!!!!!!!! ` before
exiting `2` — not `5` (`NO_TESTS_COLLECTED`, which is reserved for a clean
run that matched zero test items, no error involved) and not `1`
(`TESTS_FAILED`, reserved for collected tests that ran and failed).
Corroborated independently by a general search result describing pytest's
actual banner text for this exact scenario ("Interrupted: 1 errors during
collection").

**"No module named" does NOT appear for this specific error text.**
`ImportError: cannot import name 'X' from 'Y'` and
`ModuleNotFoundError: No module named 'Y'` are two different branches of
CPython's import machinery: the former fires when module `Y` **is found**
on the path but does not define name `X` (a stale/circular import, a typo'd
export, a partially-applied refactor); the latter fires when module `Y`
itself cannot be located. `ModuleNotFoundError` is a subclass of
`ImportError`, but the *message text* differs by branch, and pytest reprints
the exception's own message verbatim inside its
`ImportError while importing test module '<path>'.` banner — it does not
inject a generic "No module named" string of its own. Corroborated by two
independent general-audience sources describing this exact distinction
(GeeksforGeeks, and cross-checked against the well-known CPython
`_bootstrap.py` `_find_and_load` / `_call_with_frames_removed` code paths
that raise each exception with its own literal string). No official pytest
or CPython doc page was fetched stating "the phrase 'No module named' is
absent from a name-not-found ImportError" as a single sentence — this is a
straightforward consequence of the two exceptions carrying different
f-string templates, not a documented pytest behaviour, so it is reported
with that caveat.

**Confirms TS-15 exactly**: a classifier that greps failure output for the
literal phrase `No module named` will **not** match a collection failure
whose root cause is `ImportError: cannot import name 'X' from 'Y'` — that
phrase only appears for the *different* error class
(`ModuleNotFoundError: No module named`). The exit code is `2` either way,
so a classifier keying on exit code alone would still catch it; one keying
on the phrase would not.

Sources read this round: `https://raw.githubusercontent.com/pytest-dev/pytest/main/src/_pytest/config/__init__.py`, `https://raw.githubusercontent.com/pytest-dev/pytest/main/src/_pytest/main.py`, `https://github.com/pytest-dev/pytest/issues/6370` (general corroboration only, describes a different — `ModuleNotFoundError` — variant), general search results (GeeksforGeeks on `ImportError` vs `ModuleNotFoundError`; no docs.pytest.org fetch succeeded — 429 rate-limited both attempts).

**VERIFIED**, with the "not a single documented sentence, but a direct consequence of two distinct exception branches" caveat noted above.

### 11. `@vitest/eslint-plugin` `expect-expect` + `expectTypeOf` + `settings.vitest.typecheck`

**Confirmed required, and the setting key is `settings.vitest.typecheck` (boolean).**
Quoted verbatim from the rule's own docs
(`github.com/vitest-dev/eslint-plugin-vitest/blob/main/docs/rules/expect-expect.md`):
*"If you're using Vitest's type-testing feature and have tests that only
contain `expectTypeOf`, you will need to enable `typecheck` in this plugin's
settings."* The plugin's own docs use "you will need to enable" — normative
language for a requirement, not an optional nicety — and no alternative
mechanism (e.g. adding `expectTypeOf` to `assertFunctionNames` manually) is
offered in the same section, so this is the one documented path. Version:
current published is `1.6.27` (per R1 cache row above, still fresh — no
release in the one day since), plugin key `vitest`, so the full config
shape is:
```js
{
  plugins: { vitest },
  rules: { 'vitest/expect-expect': 'error' },
  settings: { vitest: { typecheck: true } },
}
```
Without `settings.vitest.typecheck: true`, a test whose only line is
`expectTypeOf(fn).returns.toEqualTypeOf<string>()` is flagged by
`expect-expect` as having no assertion (it does not recognize
`expectTypeOf` as an assertion call by default) — matching TS-39's premise.

Sources read this round: `https://github.com/vitest-dev/eslint-plugin-vitest/blob/main/docs/rules/expect-expect.md`, general search results (GitHub issue `#524`, "Feature request: support typecheck in rule valid-expect" — corroborates the setting exists and is the documented lever, attributed only).

**VERIFIED.**

### 12. MSW v2 (2.15.x) — a resolver that throws

**Not a clean "turns into a 500" in v2's core path — REFUTED as stated, one caveat.**
Read directly from `github.com/mswjs/msw`, `src/core/utils/handleRequest.ts`
(`main` branch): when the matched handler's resolver throws or rejects, the
code does
```
emitter.emit('unhandledException', { error: lookupError, request, requestId })
throw lookupError
```
— it **emits an event and re-throws**, it does not construct and return an
`HttpResponse(..., { status: 500 })` inline. This is the v2, Node-side
(`setupServer`) code path used under Vitest/jsdom. The "resolver throw ⇒
graceful 500" description that shows up in general search results is
attributed to **MSW v1's Service Worker interception**, where a real browser
Service Worker has no choice but to answer the `fetch` event with *some*
Response, so v1 synthesized a 500 there specifically. Corroborated by
independent GitHub issue reports (`mswjs/msw#400`, `#971`) of the actual
client-observed symptom for a throwing/misbehaving handler under Node/jsdom:
`TypeError: Network request failed` — a rejected/failed fetch, not a
`response.status === 500` that a test could assert on.

**What this means for the audit claim**: the second half — "the failure
surfaces at the client call site, not inside the handler file, in the
Vitest report" — **holds**: the thrown error propagates up through the
`fetch()`/`axios` call in application code (or the test's own `await`), so
the stack trace and the failing assertion both point at the caller, not at
`handlers.ts`. The first half — "as a 500" — does **not** hold for the
current v2 core path; the more accurate description is "an uncaught
exception / rejected fetch (`TypeError: Network request failed` under
Node), plus an `unhandledException` event," not a literal HTTP 500 status
code observable via `response.status`.

**Not settled**: whether some interceptor layer further downstream (in
`@mswjs/interceptors`, which `setupServer` delegates to) catches that
re-thrown error and converts it into a synthetic 500 `Response` object
before it reaches `fetch()`'s caller, which would partially rehabilitate the
original claim. Two more source reads (the specific Node `ClientRequest`/
`fetch` interceptor's error handling in `@mswjs/interceptors`) would settle
this outright; both attempts this round 404'd on guessed file paths and the
fetch budget ran out before a working path was found.

Sources read this round: `https://github.com/vitest-dev/eslint-plugin-vitest/blob/main/docs/rules/expect-expect.md` (see §11), `https://mswjs.io/docs/runbook` (no relevant content), `https://mswjs.io/docs/faq/` (no relevant content — both 404/empty on the exact "response resolver" concept page), `https://github.com/mswjs/msw/blob/main/src/core/utils/handleRequest.ts` (primary, decisive), general search results (`mswjs/msw#400`, `#971` — attributed, not official docs).

**AMBIGUOUS below the `handleRequest.ts` layer** — the re-throw/event-emit behavior at that layer is confirmed and contradicts a literal-500 reading for v2; full resolution needs the interceptor-layer source, not fetched this round.

### 13. Vitest 4 `coverage.thresholds` + `include` — does an include-matched, never-loaded file count as 0% in the aggregate?

**This is already answered by the R1 cache entry (§2 above, `checked:
2026-08-19`, `stability: pinned`) — re-read, not re-fetched.** §2 states,
sourced from `vitest.dev/guide/migration.html` and `vitest.dev/config/coverage`:
*"an untested file is invisible to the report **unless** `coverage.include`
is set explicitly to the source globs."* Read the contrapositive: **when
`coverage.include` names a file's glob, that file is visible in the report
— including one no test ever loaded — which is the only way `coverage.all`'s
removal preserves the pre-v4 "floor catches a zero-test module" property at
all.** Combined with the already-settled §8 fact (`perFile` default `false`
→ thresholds are an aggregate over "the whole `include` set"), an
include-matched-but-never-loaded file **is** counted into that aggregate,
at 0% for every metric, dragging the aggregate down exactly like any other
under-covered file — it does not get silently dropped from the denominator.

One general-audience source read this round corroborates the mechanism in
different words (attributed, not official): Vitest v4 "scans the file
system using the `include` glob and checks if a file matches
`coverage.include` and is not excluded" to surface never-imported files.
The same source's suggestion to additionally set `coverage.all: true`
is **stale** — `coverage.all` was removed outright in v4 (already-settled
§2/§8 fact) — and is flagged here so it is not mistaken for current advice
if re-surfaced later.

**Consequence for `templates/tooling-config.md`**: the shipped
`coverage.include` globs (the four test-first-layer spellings +
`src/lib/**/*.ts`) do therefore make the 90/90/85 floor catch a wholly
untested new `*.repository.ts` at 0%, dragging the aggregate below the
floor — the mechanism the R1 §2 finding already described works the way
`05-testing.md` assumes it does.

Sources: none newly fetched — answered from the existing R1 cache entry
(§2, §8) plus one general search corroboration (not counted against the
per-question fetch budget, since no fetch was spent; the search was spent
before recognizing the cache already settled it).

**VERIFIED — answered by existing cache, R1 §2 + §8 combined; no new
primary-source fetch needed or spent.**

## R2 — Not found
- §12 (MSW resolver-throw mechanism) is confirmed only down to
  `handleRequest.ts`'s re-throw/`unhandledException` emit; whether
  `@mswjs/interceptors` re-synthesizes a literal 500 `Response` further
  downstream is unresolved — budget exhausted before a working source path
  was found (two guessed raw/GitHub URLs 404'd).
