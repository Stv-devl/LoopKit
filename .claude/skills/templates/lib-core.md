# Core Template — `Result<T>`, `ServiceError`, `unwrap`

> **This file is the single source of truth for the error/result spine.**
> `02-architecture.md`, `templates/feature.md`, `patterns/react-query.md`,
> `patterns/feedback.md`, `patterns/context.md` and `patterns/tests.md` all
> describe code that imports from here. If you change a shape, change it **here
> first**, then propagate.

Every other pattern in the kit assumes these **three** files already exist. They
do not, until someone writes them. **Scaffold them first, in a new repo, before
the first feature** — otherwise each feature invents its own error shape and the
`Result<T>` boundary stops meaning anything.

`queryClient.ts` is here rather than in `patterns/react-query.md` for one
reason: it is the only file that turns a `ServiceError` **code** into a
transport decision, so it belongs with the spine it reads, not with the hooks
that never see it.

---

## `src/lib/errors.ts`

```typescript
/**
 * Canonical error codes shared by every feature.
 * Features add their own codes on top (see `{name}.errors.ts`).
 */
export type ServiceErrorCode =
  | "unauthorized"
  | "not_found"
  | "validation_failed"
  | "conflict"
  | "db_error"
  | "network_error"
  | "unknown_error";

/**
 * The error every repository returns inside `Result<T>`.
 *
 * - `code`    : stable, machine-readable, used for branching.
 * - `message` : technical, English, for logs. Never rendered to a user.
 * - `cause`   : the raw underlying error, for debugging. Never rendered.
 *
 * Deliberately **no** `userMessage`: the UI layer picks that string from `code`,
 * in the user language. See `03-conventions.md` and `patterns/feedback.md`.
 */
export interface ServiceError {
  code: ServiceErrorCode | (string & {});
  message: string;
  cause?: unknown;
}

/**
 * Builds a `ServiceError` and logs it (English, technical).
 * The only place a `console.error` for a service failure belongs.
 */
export function serviceError(
  code: ServiceError["code"],
  message: string,
  cause?: unknown,
): ServiceError {
  console.error(`[${code}] ${message}`, cause ?? "");
  return { code, message, cause };
}

/**
 * Formats a `ServiceError` for a log line. **Logging only** — this never
 * produces a string meant for a user.
 */
export function formatServiceError(error: ServiceError): string {
  return `[${error.code}] ${error.message}`;
}

/**
 * Narrows an unknown value to a `ServiceError`.
 * Used in React Query `onError`, where the callback receives `unknown`.
 */
export function isServiceError(value: unknown): value is ServiceError {
  return (
    typeof value === "object" &&
    value !== null &&
    "code" in value &&
    "message" in value
  );
}
```

---

## `src/lib/result.ts`

```typescript
import { isServiceError, type ServiceError } from "./errors";

/**
 * The value every repository returns. Never throws — the failure is data.
 */
export type Result<T, E = ServiceError> =
  | { success: true; data: T }
  | { success: false; error: E };

/** Builds a success result. */
export function ok<T>(data: T): Result<T> {
  return { success: true, data };
}

/** Builds a failure result. */
export function err<T = never>(error: ServiceError): Result<T> {
  return { success: false, error };
}

/**
 * Error thrown by `unwrap`. Carries the `ServiceError` so React Query's
 * `error` stays typed and the UI can branch on `error.code`.
 */
export class ServiceFailure extends Error {
  readonly serviceError: ServiceError;

  constructor(error: ServiceError) {
    super(error.message);
    this.name = "ServiceFailure";
    this.serviceError = error;
  }
}

/**
 * Unwraps a `Result<T>` for React Query: returns the data, or throws so that
 * `isError` / `error` fire.
 *
 * This is the **one** sanctioned throw in the codebase, and it lives in the
 * hook layer — repositories still never throw.
 */
export function unwrap<T>(result: Result<T>): T {
  if (result.success) return result.data;
  throw new ServiceFailure(result.error);
}

/**
 * Extracts the `ServiceError` from whatever React Query hands `onError`.
 */
export function toServiceError(error: unknown): ServiceError {
  if (error instanceof ServiceFailure) return error.serviceError;
  if (isServiceError(error)) return error;
  return {
    code: "unknown_error",
    message: error instanceof Error ? error.message : String(error),
    cause: error,
  };
}
```

---

## `src/lib/queryClient.ts`

The per-query profiles in `patterns/react-query.md` say what each hook overrides.
This file says what every hook gets **when it overrides nothing** — and the
answer matters, because React Query's own defaults are wrong for a codebase built
on `Result<T>`:

| Default out of the box | What it does here |
| --- | --- |
| `staleTime: 0` | every mount refetches, including a list the user navigates in and out of |
| `retry: 3`, exponential backoff | `unwrap` throws on `not_found`, `unauthorized`, `validation_failed`, `conflict` — decisions the server already made. Retrying one changes nothing and delays `isError` by seconds, on a screen `08-feedback.md` requires to show an error state |

```typescript
// src/lib/queryClient.ts
import { QueryClient } from "@tanstack/react-query";
import { toServiceError } from "./result";

/**
 * Codes that describe a decision, not an incident. Retrying one of them cannot
 * change the answer — it only postpones the error state the UI has to show.
 *
 * **A feature code that describes a decision belongs here too.** Every
 * `{name}.errors.ts` declares its own codes (`templates/feature.md`), and this
 * set cannot see them: a `feature_not_found` retried is exactly the failure the
 * predicate exists to prevent. The `*_not_found` shape is covered by
 * `isNonRetryable` below; anything else — `quota_exceeded`, `already_imported`
 * — gets a line here, the same way it gets one in `src/lib/userMessages.ts`
 * (`patterns/feedback.md`, which documents the same extension trap).
 */
const NON_RETRYABLE: ReadonlySet<string> = new Set([
  "unauthorized",
  "not_found",
  "validation_failed",
  "conflict",
]);

/** A decision the server already made: a canonical code, or any `*_not_found`. */
function isNonRetryable(code: string): boolean {
  return NON_RETRYABLE.has(code) || code.endsWith("_not_found");
}

/**
 * The app-wide client, created once and injected at the composition root
 * (`patterns/context.md`, `patterns/guards.md`).
 *
 * These defaults are a **floor**, not a policy: every hook still picks its own
 * `staleTime` / `gcTime` from the profile table in `patterns/react-query.md`.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // The "collaborative" profile, the safe middle of the four. A hook that
      // knows its data is static or user-owned says so, per query.
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      // One retry on a transport incident, then the error surfaces.
      // `failureCount` is **0** on the first call — React Query increments it
      // AFTER the predicate returns — so `< 1` is one retry, two requests total.
      // `< 2` would be two retries and three requests (`01-stack.md`, "Settled
      // external facts").
      retry: (failureCount, error) =>
        failureCount < 1 && !isNonRetryable(toServiceError(error).code),
    },
    // An explicit restatement of the v5 default (`retry: 0`), not a change to
    // it: a retried POST or PATCH is a duplicate nobody asked for. Written out
    // so that opting one genuinely idempotent mutation back in is a visible
    // edit on this line rather than an invisible reliance on a default.
    mutations: { retry: false },
  },
});
```

> **No test file, on purpose.** `src/lib/queryClient.ts` is one of the three
> wiring files excluded from the coverage floor (`05-testing.md`, "Floor scope";
> the enforced copy is in `templates/tooling-config.md`) — a test on it would
> restate the object. The `retry` predicate is the one thing here that *is*
> logic; if it grows past this list, move it to a `*.utils.ts`, where the floor
> and the test-first rule both apply.

---

## Contract summary (what the rest of the kit relies on)

| Symbol | Lives in | Used by |
| --- | --- | --- |
| `Result<T>`, `ok`, `err` | `src/lib/result.ts` | repositories, `services.ts` |
| `unwrap`, `ServiceFailure` | `src/lib/result.ts` | `hooks.ts` only |
| `toServiceError` | `src/lib/result.ts` | anywhere an `unknown` error is narrowed: `hooks.ts`, `queryClient.ts` above, and the UI layer (`patterns/feedback.md`, `patterns/forms.md`) |
| `ServiceError`, `serviceError`, `isServiceError` | `src/lib/errors.ts` | repositories, feature `errors.ts` |
| `formatServiceError` | `src/lib/errors.ts` | logs only, never the UI |
| `queryClient` | `src/lib/queryClient.ts` | the composition root (`src/main.tsx`, `src/routes/__root.tsx`, per `02-architecture.md`) and the provider tree it mounts (`AppProviders`). **Never a `hooks.ts`**: a hook takes its client from `useQueryClient()`, or it writes to the app singleton while its test asserts on the injected one (`templates/fixtures.md`) |

**Import them, never redefine them locally.** A feature that declares its own
`Result` or its own error shape breaks every pattern downstream.

## Tests (`src/lib/result.test.ts`)

`result.ts` and `errors.ts` are pure logic — `.claude/rules/05-testing.md` makes
them mandatory to cover, and `src/lib/**` sits **inside the coverage floor**
(90 lines / 90 functions / 85 branches). These two files hold eight exported
functions between them, so **one uncovered function is already 87.5 %** — below
the floor, on a fresh repo, before a single feature exists. The suite below
touches all eight on purpose; `formatServiceError` is the one that gets
forgotten, because nothing else in the kit calls it outside a log line.

```typescript
import { describe, it, expect, vi } from "vitest";
import { ok, err, unwrap, toServiceError, ServiceFailure } from "./result";
import { formatServiceError, isServiceError, serviceError } from "./errors";

describe("unwrap", () => {
  it("returns the data on success", () => {
    expect(unwrap(ok(42))).toBe(42);
  });

  it("throws a ServiceFailure carrying the error on failure", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const failure = err(serviceError("not_found", "Item missing"));

    expect(() => unwrap(failure)).toThrow(ServiceFailure);

    // The caught error is read OUTSIDE the catch: `vitest/no-conditional-expect`
    // is an error in this repo's lint gate (`01-stack.md`, "The lint on the
    // tests"), and an `expect()` inside a `catch` asserts nothing on the run
    // where nothing was thrown.
    let caught: unknown;
    try {
      unwrap(failure);
    } catch (e) {
      caught = e;
    }
    expect(toServiceError(caught).code).toBe("not_found");
  });
});

describe("toServiceError", () => {
  it("returns the ServiceError carried by a ServiceFailure", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const original = serviceError("conflict", "Already modified");

    expect(toServiceError(new ServiceFailure(original))).toBe(original);
  });

  it("passes a bare ServiceError-shaped object through untouched", () => {
    const shaped = { code: "not_found", message: "Item missing" };

    expect(toServiceError(shaped)).toEqual(shaped);
  });

  it("falls back to unknown_error on a plain Error", () => {
    expect(toServiceError(new Error("boom")).code).toBe("unknown_error");
  });

  it("stringifies a thrown non-Error value", () => {
    expect(toServiceError("boom")).toEqual({
      code: "unknown_error",
      message: "boom",
      cause: "boom",
    });
  });
});

describe("serviceError", () => {
  it("returns the code, message and cause it was given", () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const cause = new Error("underlying");

    expect(serviceError("db_error", "Insert failed", cause)).toEqual({
      code: "db_error",
      message: "Insert failed",
      cause,
    });
  });
});

describe("formatServiceError", () => {
  it("renders the code and the technical message on one line", () => {
    expect(
      formatServiceError({ code: "db_error", message: "Insert failed" }),
    ).toBe("[db_error] Insert failed");
  });
});

describe("isServiceError", () => {
  it("accepts an object carrying a code and a message", () => {
    expect(isServiceError({ code: "not_found", message: "gone" })).toBe(true);
  });

  it("rejects null, which is typeof object", () => {
    expect(isServiceError(null)).toBe(false);
  });

  it("rejects a plain Error, which has no code", () => {
    expect(isServiceError(new Error("boom"))).toBe(false);
  });
});
```

> **`ok` and `err` are covered by the tests above**, which is why they get no
> `describe` of their own — a test asserting `ok(1)` equals `{ success: true,
> data: 1 }` restates the function body. `formatServiceError` and
> `isServiceError` do get one: nothing else exercises the first, and the second
> is only ever reached down one of its four branches by `toServiceError`.
