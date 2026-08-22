# Feature Template

> **Prerequisite**: `src/lib/result.ts` and `src/lib/errors.ts` must already
> exist. They are scaffolded once from `.claude/skills/templates/lib-core.md`,
> which is the single source of truth for `Result<T>`, `ServiceError` and
> `unwrap`. Never redeclare them inside a feature.

<!-- FILL: the gateway bodies below use a small HTTP client (`@/lib/client`) as the
     neutral example. Swap them for this repo's data client — a BaaS SDK, a
     generated API client, an ORM. **Only the gateway changes.** The mapper,
     the repository, the `Result<T>` boundary and the hooks stay identical,
     which is the whole point of the layering. -->

## When to split

Read the threshold from `.claude/rules/02-architecture.md` → "File size
thresholds" (`services.ts` row). It is the only copy; this file deliberately
does not repeat the number.

- **under the threshold** → a single `services.ts` (simple variant below)
- **over it, or 3+ domains** → split into gateway/mapper/repository

## Full structure (over the threshold)

```
features/{name}/
├── types/
│   ├── types.ts              # Domain entities (pure, framework-agnostic)
│   └── schemas.ts            # Zod validation (if needed)
├── services/
│   ├── {name}.gateway.ts     # Data client calls (raw rows)          [test-after]
│   ├── {name}.gateway.test.ts   # once it builds a query — via MSW
│   ├── {name}.mapper.ts      # Raw row <-> domain entity             [TEST-FIRST]
│   ├── {name}.mapper.test.ts
│   ├── {name}.repository.ts  # Facade: gateway + mapper -> Result<T> [TEST-FIRST]
│   ├── {name}.repository.test.ts
│   ├── {name}.errors.ts      # Typed errors (extends ServiceError)
│   ├── {name}.utils.ts       # Pure logic (if needed)                [TEST-FIRST]
│   └── {name}.utils.test.ts
├── hooks/hooks.ts            # React Query: queryFn -> repository    [test-after]
├── hooks/hooks.test.tsx      # mandatory too — after the code, not before
├── stores/store.ts           # Zustand (if client state is needed)
├── components/
└── pages/
```

> **A page is not a component.** `pages/` returns a fragment that opens on the
> feature's single `<h1>` and renders inside the layout's `<main>` — the
> landmark and heading contract is `.claude/skills/templates/page.md`.

> **The three `[TEST-FIRST]` files cannot be created before their test has been
> observed failing** — `tdd-require-red.sh` denies it. Write order:
> `types` → `schemas` → `errors` → `gateway`, then one layer at a time,
> RED→GREEN, in the order `utils` → `mapper` → `repository`. `errors.ts` and
> `gateway.ts` come **before** the first RED because the mapper takes its row
> type from the gateway and the repository imports both;
> written later, the repository's red fails on a missing import instead of on the
> behaviour it names, and no marker is recorded. Full cycle:
> `.claude/rules/05-testing.md`.

## Simple structure (under the threshold)

```
features/{name}/
├── types/types.ts
├── services/services.ts      # Gateway + mapper + repository in one file [TEST-FIRST]
├── services/services.test.ts
├── hooks/hooks.ts            #                                          [test-after]
├── stores/store.ts
├── components/
└── pages/
```

> `services.ts` **bare** — never `{name}.services.ts`, which the data-client rule
> would reject (`02-architecture.md`). It is test-first and frozen like the three
> split files: its test comes first, RED→GREEN.

---

## types/types.ts

```typescript
export interface Feature {
  id: string;
  name: string;
  userId: string;
  createdAt: Date;
}

export interface CreateFeatureInput {
  name: string;
}

export interface UpdateFeatureInput {
  name?: string;
}
```

---

## Simple variant: services/services.ts

For small features (under the `services.ts` threshold), everything in a single
file with `Result<T>`.

```typescript
import { client } from "@/lib/client";
import { ok, err, type Result } from "@/lib/result";
import { serviceError } from "@/lib/errors";
import type {
  Feature,
  CreateFeatureInput,
  UpdateFeatureInput,
} from "../types/types";

// --- Errors ---
// `serviceError` logs in English and builds the ServiceError. The user-facing
// string is NOT decided here — the UI picks it from `code`. See lib-core.md.

// --- Mapper ---

function toEntity(row: Record<string, unknown>): Feature {
  return {
    id: String(row.id),
    name: String(row.name),
    userId: String(row.user_id),
    createdAt: new Date(String(row.created_at)),
  };
}

// --- Services ---

/**
 * Fetches all features for the current user.
 */
export async function getFeatures(): Promise<Result<Feature[]>> {
  const { data, error } = await client.get("/features", {
    order: "created_at.desc",
  });

  if (error)
    return err(serviceError("db_error", "Failed to fetch features", error));
  return ok((data ?? []).map(toEntity));
}

/**
 * Fetches a single feature by ID.
 */
export async function getFeature(id: string): Promise<Result<Feature>> {
  const { data, error } = await client.get(`/features/${id}`);

  if (error)
    return err(serviceError("not_found", `Feature ${id} not found`, error));
  // "no row" arrives as `{ data: null, error: null }` — guard it, or the mapper
  // throws and this function stops honouring `Result<T>`.
  if (!data) return err(serviceError("not_found", `Feature ${id} not found`));
  return ok(toEntity(data));
}

/**
 * Creates a new feature.
 */
export async function createFeature(
  input: CreateFeatureInput,
): Promise<Result<Feature>> {
  const { data, error } = await client.post("/features", input);

  if (error)
    return err(serviceError("db_error", "Failed to create feature", error));
  if (!data) return err(serviceError("db_error", "Insert returned no row"));
  return ok(toEntity(data));
}

/**
 * Updates an existing feature.
 */
export async function updateFeature(
  id: string,
  input: UpdateFeatureInput,
): Promise<Result<Feature>> {
  const { data, error } = await client.patch(`/features/${id}`, input);

  if (error)
    return err(serviceError("db_error", "Failed to update feature", error));
  if (!data) return err(serviceError("db_error", `Feature ${id} not found`));
  return ok(toEntity(data));
}

/**
 * Deletes a feature.
 */
export async function deleteFeature(id: string): Promise<Result<void>> {
  const { error } = await client.delete(`/features/${id}`);

  if (error)
    return err(serviceError("db_error", "Failed to delete feature", error));
  return ok(undefined);
}
```

---

## Split variant (over the threshold)

### services/{name}.errors.ts

```typescript
import { serviceError } from "@/lib/errors";
import type { ServiceError } from "@/lib/errors";

/**
 * Feature-specific codes, on top of the canonical ones in `lib/errors.ts`.
 *
 * Same casing as the canonical ones — lower snake_case — because the UI maps a
 * code to user copy through `userMessageFor` (`patterns/feedback.md`), which is
 * a plain lookup. A code in another casing is not "styled differently", it is a
 * code that never matches and always falls back to the generic message.
 * **Every code declared here gets a line in `src/lib/userMessages.ts`.**
 */
export type FeatureErrorCode =
  | "feature_not_found"
  | "feature_create_failed"
  | "feature_update_failed"
  | "feature_delete_failed";

/**
 * Creates a typed feature error from a raw client error.
 * Logging happens inside `serviceError` — do not log again at the call site.
 */
export function featureError(
  code: FeatureErrorCode,
  message: string,
  cause: unknown,
): ServiceError {
  return serviceError(code, message, cause);
}
```

### services/{name}.gateway.ts

The gateway is where the **raw row shape** is declared, and it is the reason
`FeatureRow` lives here rather than in the mapper: it describes the payload the
transport returns, not a domain concept. The mapper imports it.

```typescript
import { client } from "@/lib/client";
import type { CreateFeatureInput, UpdateFeatureInput } from "../types/types";

/** Raw row as the backend sends it (snake_case). Not a domain entity. */
export interface FeatureRow {
  id: string;
  name: string;
  user_id: string;
  created_at: string;
}

/**
 * What every call below resolves to. Explicit, because an un-annotated gateway
 * leaks an implicit `any` all the way up: the repository hands `data` to a
 * mapper typed `(row: FeatureRow)`, and either `no-any-type` denies the write or
 * `pnpm typecheck` fails — both at the wrong layer, far from the cause.
 */
export interface GatewayResponse<T> {
  data: T | null;
  error: Error | null;
}

/**
 * Raw data client calls. Returns rows as-is — no mapping, no Result.
 */
export async function fetchAll(): Promise<GatewayResponse<FeatureRow[]>> {
  return client.get("/features", { order: "created_at.desc" });
}

export async function fetchById(id: string): Promise<GatewayResponse<FeatureRow>> {
  return client.get(`/features/${id}`);
}

export async function insert(
  input: CreateFeatureInput,
): Promise<GatewayResponse<FeatureRow>> {
  return client.post("/features", input);
}

export async function update(
  id: string,
  input: UpdateFeatureInput,
): Promise<GatewayResponse<FeatureRow>> {
  return client.patch(`/features/${id}`, input);
}

export async function remove(id: string): Promise<GatewayResponse<null>> {
  return client.delete(`/features/${id}`);
}
```

### services/{name}.mapper.ts

> **`import type`, not a plain import.** TypeScript erases a type-only import, so
> the mapper still loads nothing at runtime and its test stays a pure-function
> test. Drop the `type` keyword and the mapper pulls in the gateway, which pulls
> in the data client — in a frozen, test-first file whose whole premise is that
> it has no dependency to fake.

```typescript
import type { Feature } from "../types/types";
import type { FeatureRow } from "./feature.gateway";

/**
 * Maps a raw row to a domain entity. No `as` casts.
 */
export function toEntity(row: FeatureRow): Feature {
  return {
    id: row.id,
    name: row.name,
    userId: row.user_id,
    createdAt: new Date(row.created_at),
  };
}

/**
 * Maps multiple raw rows to domain entities.
 */
export function toEntities(rows: FeatureRow[]): Feature[] {
  return rows.map(toEntity);
}
```

### services/{name}.repository.ts

```typescript
import { ok, err, type Result } from "@/lib/result";
// A transport failure is NOT a feature code: it gets one of the canonical codes
// from `lib/errors.ts`. See the note under this block.
import { serviceError } from "@/lib/errors";
import type {
  Feature,
  CreateFeatureInput,
  UpdateFeatureInput,
} from "../types/types";
import * as gateway from "./feature.gateway";
import { toEntity, toEntities } from "./feature.mapper";
import { featureError } from "./feature.errors";

/**
 * Fetches all features. Returns Result<T>, never throws.
 */
export async function getAll(): Promise<Result<Feature[]>> {
  const { data, error } = await gateway.fetchAll();
  if (error) return err(serviceError("db_error", "Failed to fetch features", error));
  return ok(toEntities(data ?? []));
}

/**
 * Fetches a feature by ID.
 */
export async function getById(id: string): Promise<Result<Feature>> {
  const { data, error } = await gateway.fetchById(id);
  // The call itself failed — the row's existence is unknown, so do NOT claim it
  // is gone. `feature_not_found` maps to "Cet élément n'existe plus."
  // (`patterns/feedback.md`): saying that on a dropped connection tells the user
  // to stop retrying, and the technical truth stays in the log where nobody
  // reads it.
  if (error)
    return err(serviceError("db_error", `Failed to fetch feature ${id}`, error));
  // `{ data: null, error: null }` is a real response — "no row", not a failure
  // of the call. Without this guard the mapper receives null and THROWS, and the
  // repository's whole contract ("never throws") is gone on the most common
  // not-found path. Same guard on every single-row read.
  if (!data)
    return err(featureError("feature_not_found", `Feature ${id} not found`, null));
  return ok(toEntity(data));
}

/**
 * Creates a feature.
 */
export async function create(
  input: CreateFeatureInput,
): Promise<Result<Feature>> {
  const { data, error } = await gateway.insert(input);
  if (error)
    return err(featureError("feature_create_failed", "Failed to create feature", error));
  if (!data)
    return err(featureError("feature_create_failed", "Insert returned no row", null));
  return ok(toEntity(data));
}

/**
 * Updates a feature.
 */
export async function update(
  id: string,
  input: UpdateFeatureInput,
): Promise<Result<Feature>> {
  const { data, error } = await gateway.update(id, input);
  if (error)
    return err(featureError("feature_update_failed", `Failed to update feature ${id}`, error));
  if (!data)
    return err(featureError("feature_update_failed", `Feature ${id} not found`, null));
  return ok(toEntity(data));
}

/**
 * Deletes a feature.
 */
export async function remove(id: string): Promise<Result<void>> {
  const { error } = await gateway.remove(id);
  if (error)
    return err(featureError("feature_delete_failed", `Failed to delete feature ${id}`, error));
  return ok(undefined);
}
```

---

## hooks/hooks.ts

The hooks unwrap the `Result<T>` so that React Query handles the errors.

```typescript
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { UseQueryResult, UseMutationResult } from "@tanstack/react-query";
import { unwrap } from "@/lib/result";
import * as repository from "../services/feature.repository";
import type { Feature, CreateFeatureInput, UpdateFeatureInput } from "../types/types";

// One factory per feature, never a literal key typed twice — the shape and the
// reason are in `patterns/react-query.md` ("Query keys").
export const featureKeys = {
  all: ["features"] as const,
  lists: () => [...featureKeys.all, "list"] as const,
  // The day the list takes a filter, a sort or a page, add the filtered form
  // HERE and key the hook on it — never on a literal built at the call site:
  //   list: (search: FeatureSearch) => [...featureKeys.lists(), search] as const,
  // It comes with `placeholderData` on the hook (`patterns/react-query.md`,
  // "When the key changes") and with the search living in the URL
  // (`patterns/url-state.md`).
  details: () => [...featureKeys.all, "detail"] as const,
  detail: (id: string) => [...featureKeys.details(), id] as const,
};

/**
 * Fetches all features.
 */
export function useFeatures(): UseQueryResult<Feature[]> {
  return useQuery({
    queryKey: featureKeys.lists(),
    queryFn: async () => unwrap(await repository.getAll()),
    // "User-owned" profile — BOTH numbers, `patterns/react-query.md`. `gcTime`
    // diverges from the floor in `lib/queryClient.ts` (5 min), so leaving it out
    // silently keeps the floor and the profile is only half applied.
    staleTime: 5 * 60 * 1000,
    gcTime: 60 * 60 * 1000,
  });
}

/**
 * Fetches a single feature by ID.
 */
export function useFeature(id: string): UseQueryResult<Feature> {
  return useQuery({
    queryKey: featureKeys.detail(id),
    queryFn: async () => unwrap(await repository.getById(id)),
    // Deliberately inherits the collaborative floor from queryClient.ts, where
    // the list above takes the user-owned row: one entity, two profiles, and
    // this is the one that is easy to leave unsaid (`patterns/react-query.md`,
    // "Config by data type"). Say which you meant.
    //
    // `enabled: false` leaves the query `status: 'pending'` / `fetchStatus:
    // 'idle'` FOREVER, so a component opening with `if (isPending) return
    // <State type="loading" />` spins forever whenever `id` is empty. Branch on
    // `isLoading`, and give "nothing selected" its own branch (`08-feedback.md`).
    enabled: !!id,
  });
}

/**
 * Creates a feature.
 */
export function useCreateFeature(): UseMutationResult<Feature, Error, CreateFeatureInput> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: CreateFeatureInput) =>
      unwrap(await repository.create(input)),
    // A new row changes the lists, not the details already in cache.
    onSuccess: () => queryClient.invalidateQueries({ queryKey: featureKeys.lists() }),
  });
}

/**
 * Updates a feature.
 */
export function useUpdateFeature(): UseMutationResult<
  Feature,
  Error,
  { id: string } & UpdateFeatureInput
> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, ...input }: { id: string } & UpdateFeatureInput) =>
      unwrap(await repository.update(id, input)),
    // Two surfaces, named: the row itself and the lists that display it.
    onSuccess: (_data, { id }) => {
      void queryClient.invalidateQueries({ queryKey: featureKeys.detail(id) });
      void queryClient.invalidateQueries({ queryKey: featureKeys.lists() });
    },
  });
}

/**
 * Deletes a feature.
 */
export function useDeleteFeature(): UseMutationResult<void, Error, string> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => unwrap(await repository.remove(id)),
    // The detail is dropped, not invalidated: refetching a deleted row is a
    // guaranteed 404 that would surface as an error state on a screen the user
    // has already left.
    // **"Has already left" is the condition, not a description.** If the delete
    // button lives ON the detail page, that query still has a mounted observer:
    // removing it makes the observer rebuild an empty query and refetch, and the
    // 404 flashes before the redirect. Navigate first, then let this run.
    onSuccess: (_data, id) => {
      queryClient.removeQueries({ queryKey: featureKeys.detail(id) });
      void queryClient.invalidateQueries({ queryKey: featureKeys.lists() });
    },
  });
}
```

> **`lists()` and `detail(id)`, not `all`.** Invalidating `featureKeys.all` on
> every mutation works and is the reflex — it also refetches every detail the
> user still has open, on a change that touched one row. The key factory is
> nested precisely so the blast radius can be named; the table in
> `patterns/react-query.md` ("Query keys") is what each of the three lines above
> applies. `all` stays legitimate for the case it describes: a change whose blast
> radius really is the whole feature.
>
> **The two shapes above are not interchangeable either.** `onSuccess: () =>
> queryClient.invalidateQueries(...)` **returns** the promise, so React Query
> awaits the refetch before the mutation settles — `isPending` stays true and the
> button stays disabled until the fresh list is in. The `void` form settles
> immediately and refetches behind. Pick the first when the user must not act on
> stale rows, the second when the wait would be felt for nothing.

> **The return types are explicit** (`03-conventions.md`) — and on a React Query
> hook that is not ceremony: `UseQueryResult<Feature[]>` is what tells a reader,
> and the compiler, that the hook hands back the **unwrapped** entity and not a
> `Result<T>`. The error slot is `Error` because `unwrap` throws a
> `ServiceFailure`, which extends it; narrow it with `toServiceError` at the use
> site (`patterns/feedback.md`).

> `unwrap` lives in `src/lib/result.ts` (`.claude/skills/templates/lib-core.md`) —
> import it, never redefine it locally. It is the one sanctioned `throw`, and it
> lives in the hook layer: the repository above still never throws.
> For the simple variant, replace the `repository.*` imports with `services.*`.

---

## stores/store.ts (optional)

```typescript
import { create } from "zustand";

interface FeatureUIState {
  selectedId: string | null;
  isFormOpen: boolean;
}

interface FeatureUIActions {
  setSelectedId: (id: string | null) => void;
  openForm: () => void;
  closeForm: () => void;
  reset: () => void;
}

type FeatureStore = FeatureUIState & FeatureUIActions;

const initialState: FeatureUIState = {
  selectedId: null,
  isFormOpen: false,
};

/**
 * UI state store for the feature.
 * Only for client state (modals, selection, ephemeral flags).
 * A filter, sort or page goes in the URL — patterns/url-state.md.
 * Server data goes through React Query (hooks.ts).
 */
export const useFeatureStore = create<FeatureStore>()((set) => ({
  ...initialState,
  setSelectedId: (id) => set({ selectedId: id }),
  openForm: () => set({ isFormOpen: true }),
  closeForm: () => set({ isFormOpen: false }),
  reset: () => set(initialState),
}));
```
