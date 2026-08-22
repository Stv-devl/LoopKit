---
name: e2e-playwright
description: Write and run end-to-end Playwright tests against the web app. Use when a review needs to prove a user flow actually works in a browser, when adding an E2E spec, or when a Playwright run fails and needs diagnosing. Covers the harness (config, projects, mock mode), the safety rules around real data, and the selector conventions.
---

# E2E Playwright — the web app

<!-- FILL: if this repo also drives a browser for something else (a scraper, a
     worker), say so here and state that it shares nothing with this harness.
     Two Playwright setups in one repo is how a test suite ends up running with
     a production session. -->

## The harness

<!-- FILL: the real paths and scripts. -->

| Piece | Where |
| --- | --- |
| Runner | `@playwright/test` (devDependency) |
| Config | `playwright.config.ts` (root) |
| Specs | `e2e/` |
| Report | `playwright-report/`, traces retained on failure only |

```bash
pnpm exec playwright test                      # everything runnable
pnpm exec playwright test e2e/<file>           # one spec
pnpm exec playwright test --project=public     # no session needed
pnpm exec playwright show-report               # after a failure
```

The config starts the dev server itself and reuses one that is already running.
Don't start it by hand.

> **`e2e/` must be excluded from Vitest**, in the `test` key of
> **`vite.config.ts`** (`templates/tooling-config.md` — a separate
> `vitest.config.ts` takes priority and does NOT merge `vite.config.ts`, so the
> plugins and the `@`/`@shared` aliases would vanish during tests).
>
> The shipped config already narrows `include` to `**/*.test.{ts,tsx}`, so a
> `*.spec.ts` under `e2e/` is not collected by it — the `exclude` line is the
> belt, and it is what protects a repo that widens `include` later, or that
> already had its own config when the kit landed. Check it before writing the
> first spec.

### Two projects

- **`public`** — files named `*.public.spec.ts`. No session. Login screen, guards,
  redirects, anything reachable logged out. **Always runnable.**
- **`authed`** — files named `*.authed.spec.ts`. Registered **only if the stored
  session exists** (`e2e/.auth/user.json`); otherwise the suite still runs, it
  just covers less. Say so rather than reporting green.

  Producing that session, once:
  1. set the test credentials in env — a **dedicated test account**, never a real
     user's
  2. write `e2e/auth.setup.ts` (fills the login form, then
     `page.context().storageState({ path: "e2e/.auth/user.json" })`)
  3. `pnpm exec playwright test --project=setup`

  From the next run on, `authed` registers itself and refreshes the session via
  the `setup` dependency. The session file is gitignored.

## Which backend does the suite hit? (the hazard)

<!-- FILL — this is the most important section of the file, and the one an agent
     will act on. State exactly one of:

     A. Disposable local stack, reset per run → mutation allowed, each spec
        seeds and cleans its own data.
     B. Seeded test project, shared → mutation allowed on data the suite owns;
        never touch anything else.
     C. The real project, partially mocked → READ-ONLY by default. Name what the
        mock layer actually covers, and state that everything else reaches
        production data. List the actions that must never fire (anything with an
        external side effect: emails, payments, third-party API calls).

     Case C is the dangerous default when a mock layer runs with "bypass unhandled
     requests" — it looks mocked and isn't. If you are not sure which case you are
     in, you are in case C. -->

Consequences, whichever case applies:

- Never assert on a specific row that happens to exist today ("the item Dupont is
  row 3"). Assert on structure and behaviour: the list renders, the filter reduces
  the count, the empty state appears when the filter matches nothing.
- A flow that must mutate on a read-only surface needs a mocked handler first.
  Add it to the mock layer; don't write the spec against live data and hope.

### The mock layer is MSW, and it is not the default

`@msw/playwright` routes the **same handlers as the gateway tests**
(`src/test/msw/handlers.ts`, see `.claude/skills/patterns/msw.md`) through
Playwright's `page.route()`. One source of truth for the fake API instead of two.

```bash
pnpm add -D @msw/playwright
```

Two rules, and they are what keep case C from becoming a lie:

- **`onUnhandledRequest: "error"`, never `"bypass"`.** Under bypass, a route
  nobody declared silently reaches the real backend — the suite looks mocked and
  is not. That is the hazard named above, and this setting is its cure.
- **Mock the flow, not the suite.** A fully mocked E2E proves nothing about
  integration: it drives your app against your own fiction. Turn it on for the
  specs that would otherwise mutate real data or fire an external side effect,
  and say in the spec's name or a comment that it runs mocked.

`playwright-msw` (community) is the older approach and maintains its own mirror
of the MSW API. Use the official `@msw/playwright`.

## Writing a spec

```typescript
import { expect, test } from "@playwright/test";

test.describe("items list", () => {
  test("filtering narrows the list", async ({ page }) => {
    await page.goto("/app/items");

    const rows = page.getByRole("row");
    const before = await rows.count();

    await page.getByLabel("Rechercher").fill("dev");
    await expect(rows).not.toHaveCount(before);
  });
});
```

**Selectors, in this order.** `getByRole` → `getByLabel` → `getByText` →
`getByTestId`. Never a CSS class: utility classes change on every restyle, and a
spec pinned to `.bg-muted` is a spec that will fail for no reason. Accessible
names are in the **user language** of the product (`.claude/rules/03-conventions.md`)
— which makes this a free a11y check: if `getByRole` can't find your control, a
screen reader can't either.

**Waiting.** Never `waitForTimeout`. Use web-first assertions (`toBeVisible`,
`toHaveURL`, `toHaveCount`) — they retry on their own. A spec that needs a sleep
is a spec hiding a race.

**Isolation.** One `test` = one user-visible outcome. No shared state between
tests; `fullyParallel` is on, so two specs may run at the same time.

## What E2E is for, and what it isn't

E2E is slow and brittle relative to the unit runner. Use it only for what unit
tests cannot reach: **a real flow across several screens, in a real browser**.

| Question | Where it belongs |
| --- | --- |
| Does this mapper transform the row correctly? | Unit (`.claude/rules/05-testing.md`) |
| Does the repository return a `Result` failure? | Unit |
| Does the hook refetch on invalidation? | Unit |
| Does the guard redirect a logged-out visitor? | E2E `public` |
| Does the empty state appear when the filter matches nothing? | E2E |
| Does the user reach the result in three clicks? | E2E |

E2E **never replaces** the mandatory unit tests on business logic. It is a layer
on top, not a substitute — a green E2E with no unit test still fails the gate.

## When a run fails

1. Read the actual error, not the summary. `pnpm exec playwright show-report`
   opens the trace: DOM snapshot, network, console, at the failing step.
2. Separate the two causes: **the app is broken** (a real finding) or **the spec
   is wrong** (bad selector, missing wait, stale assumption about data). Say which.
3. A spec that fails intermittently is a defect in the spec. Don't retry it into
   green — keep `retries` at 0 on purpose.
