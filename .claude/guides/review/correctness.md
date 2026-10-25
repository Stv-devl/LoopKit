# Review checklist — `correctness`

Read by a `reviewer` assigned `correctness` (`.claude/agents/reviewer.md`). Also covers clean architecture.

- [ ] **The diff breaks no `Product invariant`.** Read
      `docs/product/brief.md`'s `Product invariants` section if that file exists
      — that section only, it is short. Those are the product's hard limits, and
      this dimension is the **only** thing that checks them against real code: a
      story gate can catch one contradicted in intent (`story-critic`), nothing
      catches one introduced at implementation, and a feature entering by `/loop:spec`
      never meets a story gate at all. Breaking one is a **Critical** — name the
      invariant. No brief, or no such section → skip it in one line, do not infer
      invariants from the code.
- [ ] No cross-feature import (`features/A` → `features/B`)
- [ ] No shared **leaf** code depending on a feature: `src/components`, `src/hooks`,
      `src/lib`, `src/types`, `src/stores`, `src/config` — the full `SHARED_DIRS`
      of `enforce-architecture.py`, six entries — must not import `features/*`.
      `src/routes` and `src/providers` are wiring and may. You are the backstop
      that matters here: the hook inspects only the **inserted delta** of an
      Edit, so an import already sitting elsewhere in the file reaches you and
      nothing else.
- [ ] No business logic in pages/components
- [ ] DB/API calls only in `gateway.ts`/`services.ts`; `hooks.ts` never touches the
      data client. The **only** other file allowed to import it is the composition
      root listed in `02-architecture.md` — a provider, guard or route helper that
      reads `client.*` is a Major, even if the hook let it through on an Edit delta.
- [ ] Repositories return `Result<T>`, never an implicit `throw`; hooks `unwrap()`.
      No local redefinition of `Result`, `unwrap` or `ServiceError` — they come from
      `src/lib/` (`templates/lib-core.md`), and a second shape is a Major.
- [ ] State in the place `04-state.md` assigns it: server data in React Query,
      never mirrored into a Zustand store (`setItems(data)` in a `useEffect`, a
      store field fed from a query = **Major**); no derived value stored instead
      of computed. A selection or an open/closed flag IS UI state and
      belongs in the store — an id is not the row. **The carrier does not change
      the verdict**: query data copied into a store, into a `useState` or into a
      Context value is the same Major, and the `useEffect(() => setX(data),
      [data])` shape is how all three are written. A provider that *fetches* is
      that Major with no cache at all — **except the session**, which
      `04-state.md` explicitly allows to be read by a repository call in a
      provider, and which `patterns/context.md` ships that way. Scoring the
      scaffolded `AuthProvider` is a false positive, not a find. A single
      `AppContext` carrying unrelated concerns is a Minor — it re-renders every
      consumer on any change.
- [ ] A **filter, sort, page or active tab kept in a store or in `useState`**
      instead of the URL (`04-state.md`, `patterns/url-state.md`) = **Minor**,
      Major if the feature's own spec asks for a shareable or refresh-proof
      view. Check the search schema too: `validateSearch` present, defaults via
      `.catch()` rather than `.optional()`.
- [ ] **Query keys come from a factory**, never a literal typed twice
      (`patterns/react-query.md`). A second literal for the same query is a
      **Major** — it is an invalidation that silently does nothing, and it
      surfaces as "it updates everywhere except here".
- [ ] **No `import { queryClient } from '@/lib/queryClient'` outside the
      composition root** (`templates/lib-core.md`, contract summary). In a
      `hooks.ts` it is a **Major**: the hook writes to the app singleton while
      its test asserts on the client `createQueryWrapper` injected, so the test
      passes on an empty cache and proves nothing. Inside a hook the client comes
      from `useQueryClient()`. No hook and no gate catches this one — it is
      checked here or nowhere.
- [ ] No user-facing copy inside a `ServiceError` — the UI maps `code` → message
- [ ] No `any`; explicit return types — the single exception is a
      `queryOptions(...)` factory (`03-conventions.md`); Zod schemas aligned with
      the types
- [ ] No conditional hook: a hook behind `??`, `||`, `&&` or a ternary is a
      Critical (React throws on the next render), not a style issue
- [ ] No hand-written `useMemo` / `useCallback` / `memo` — the React Compiler is
      on (`03-conventions.md`, "Memoization"). A new one in the diff is a
      **Major** unless a `// memo: <reason>` right above it names which of the
      two exceptions it is (identity contract, or measured non-render cost).
- [ ] A hook that sets `staleTime` without the `gcTime` of the **same profile
      row** has applied half a profile and silently kept the floor's retention
      (`patterns/react-query.md`, "Config by data type") = **Minor**. An example
      that names no profile at all is the same finding
- [ ] A query that can be disabled (`enabled: false`) whose consumer branches on
      `isPending` rather than `isLoading` = **Minor**: a disabled query stays
      `pending` forever, so that branch is a spinner that never resolves
      (`08-feedback.md`, the fourth row)
- [ ] A Zustand store read whole (`const s = useStore()`) instead of through a
      selector, or a selector returning a new object/array without `useShallow`,
      is a **Minor** — the same defect as the `AppContext` line above
      (`patterns/zustand.md`, "Selectors"). No hook and no lint sees this one.
- [ ] No `forwardRef` in new code: React 19 takes `ref` as a plain prop
      (`templates/component.md`). Minor, Major if it was added to a file the diff
      already rewrites.
- [ ] Files within the size thresholds in `02-architecture.md` ("File size
      thresholds" — read the table there, do not trust a copy); over threshold = Minor,
      unless the exact path is listed in `.claude/.size-exempt`, which is read
      before reporting
- [ ] **The same logic written twice.** Two features, or two files, carrying the
      same rule — a duplicated date/price/permission computation, a second
      hand-rolled version of something in `src/lib/`, a validation restated in
      the component after the Zod schema already ran. `02-architecture.md` ends
      its import rules with "if two features share code, move it into `shared/`
      or `src/`" — **you are the only thing that checks it**, and it is the one
      DRY rule with a mechanical consequence, since the copy that is not
      exercised is the one that silently keeps the old behaviour. **Major** when
      the two copies can disagree, **Minor** when they are literal and adjacent.
      Not a finding: the deliberate copies this repo declares (the enforced
      twins of a rule, `templates/lib-core.md` scaffolded verbatim).
- [ ] **SOLID, the three parts nothing else covers** (`03-conventions.md`, the
      table there gives the shape of each). S and D are already carried by the
      layering and by `enforce-architecture.py` — do not re-report them from
      here. What is yours:
      **O** — a `switch`/`if` ladder on a *kind* that grows a branch per case
      (a mapper on `row.type`, a variant ladder in a component): **Minor**, Major
      when the diff itself adds a branch to an existing ladder.
      **L** — a variant that narrows the contract it claims: a `ServiceError`
      subclass whose `code` leaves the union, a component taking `ButtonProps`
      that ignores `disabled`, a test double whose failure branch cannot return
      `err()`. **Major** — it is a lie the type system accepted.
      **I** — a props or service interface with fields its callers do not use;
      the tell is at the call site (`{...{} as Props}`, `null as never`, a run of
      `undefined` arguments): **Minor**.
      And the DIP idiom: an interface + injection added *inside* a feature, where
      `templates/feature.md` imports the repository as a module, is a **Minor** —
      injection is for crossing a boundary the arrow forbids, not for decoupling
      within a layer.
- [ ] **Backend code** (if the diff touches it): conforms to the Backend section
      of `.claude/rules/02-architecture.md` — layout, handler style, validation,
      where auth/CORS/rate-limit are applied, error shape. Section empty = no
      backend in this repo, so backend code in the diff is itself a finding.
- [ ] The feature covers **all** the spec's acceptance criteria
- [ ] **Relevancy and residue:** the diff still answers the entry need after its
      implementation choices, and leaves no obsolete branch, duplicate path,
      temporary diagnostic (`LOOPKIT_DEBUG`), dead export, or superseded file
      behind. Major when the stale path can still run or contradict the new one;
      Minor when it is inert residue. This is not a request for unrelated cleanup:
      report only rot created or made obsolete by this diff.
