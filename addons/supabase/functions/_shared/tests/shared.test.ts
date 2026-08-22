/**
 * Smoke tests for the shared infra. Run from `supabase/functions`:
 *   deno test --allow-env --allow-net _shared/tests/
 */
import { assertEquals, assertExists, assertStringIncludes } from "jsr:@std/assert";

import { createEmptyResponse, createErrorResponse, createJsonResponse } from "../utils/http.ts";
import {
  buildCorsHeaders,
  handleCorsPreflight,
  isAllowedOrigin,
  resolveAllowedOrigin,
} from "../utils/cors.ts";
import {
  authenticateServiceRole,
  extractClientIp,
  extractUserIdFromToken,
} from "../utils/auth-helpers.ts";
import {
  applySecurityHeaders,
  buildSecurityHeaders,
  SECURITY_PRESETS,
} from "../middleware/security-headers.ts";
import { AuthService } from "../services/auth.service.ts";
import { secureLogger } from "../utils/secure-logger.ts";

const req = (init?: RequestInit) => new Request("https://fn.example.com/", init);

/** A syntactically valid JWT with the given payload and no real signature. */
const fakeJwt = (payload: Record<string, unknown>) =>
  `eyJhbGciOiJIUzI1NiJ9.${btoa(JSON.stringify(payload)).replace(/=+$/, "")}.not-a-signature`;

/** Runs `fn` with one console sink captured, and returns what it emitted. */
function capture(level: "log" | "warn" | "error", fn: () => void): string[] {
  const lines: string[] = [];
  const original = console[level];
  console[level] = (line: string) => void lines.push(line);
  try {
    fn();
  } finally {
    console[level] = original;
  }
  return lines;
}

Deno.test("createErrorResponse uses the flat error shape", async () => {
  const res = createErrorResponse("Non autorisé", 401);
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(typeof body.error, "string");
  assertEquals(body.error, "Non autorisé");
});

Deno.test("createJsonResponse injects security headers", async () => {
  const res = createJsonResponse({ ok: true });
  assertEquals(res.headers.get("X-Content-Type-Options"), "nosniff");
  assertEquals(res.headers.get("Content-Type"), "application/json");
  await res.body?.cancel();
});

Deno.test("buildSecurityHeaders returns a mutable copy", () => {
  const headers = buildSecurityHeaders(SECURITY_PRESETS.WEBHOOK);
  headers["X-Test"] = "1";
  assertEquals("X-Test" in SECURITY_PRESETS.WEBHOOK, false);
});

Deno.test("handleCorsPreflight answers OPTIONS and only OPTIONS", () => {
  const preflight = handleCorsPreflight(req({ method: "OPTIONS" }));
  assertExists(preflight);
  assertEquals(preflight.status, 204);
  assertEquals(handleCorsPreflight(req({ method: "POST" })), null);
});

Deno.test("buildCorsHeaders always allows the required headers", () => {
  const headers = buildCorsHeaders(req());
  assertStringIncludes(headers["Access-Control-Allow-Headers"], "authorization");
});

Deno.test("authenticateServiceRole refuses a request with no bearer", () => {
  assertEquals(authenticateServiceRole(req()).authorized, false);
});

Deno.test("authenticateServiceRole accepts the secret key", () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "sb_secret_test_value");
  const result = authenticateServiceRole(
    req({ headers: { Authorization: "Bearer sb_secret_test_value" } }),
  );
  assertEquals(result.authorized, true);
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
});

Deno.test("authenticateServiceRole ignores an unverified role claim by default", () => {
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "sb_secret_test_value");
  // header.payload.signature where payload = {"role":"service_role"}
  const forged = `eyJhbGciOiJIUzI1NiJ9.${
    btoa('{"role":"service_role"}').replace(/=+$/, "")
  }.not-a-signature`;

  const strict = authenticateServiceRole(req({ headers: { Authorization: `Bearer ${forged}` } }));
  assertEquals(strict.authorized, false);

  const lax = authenticateServiceRole(
    req({ headers: { Authorization: `Bearer ${forged}` } }),
    { trustRoleClaim: true },
  );
  assertEquals(lax.authorized, true);
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
});

Deno.test("extractClientIp skips private and loopback addresses", () => {
  assertEquals(
    extractClientIp(req({ headers: { "x-forwarded-for": "127.0.0.1, 10.0.0.5, 203.0.113.7" } })),
    "203.0.113.7",
  );
});

Deno.test("extractUserIdFromToken reads the sub claim without verifying anything", () => {
  const token = fakeJwt({ sub: "user-42", role: "authenticated" });
  assertEquals(
    extractUserIdFromToken(req({ headers: { Authorization: `Bearer ${token}` } })),
    "user-42",
  );
});

Deno.test("extractUserIdFromToken returns null when there is no sub to read", () => {
  assertEquals(extractUserIdFromToken(req()), null);
  assertEquals(
    extractUserIdFromToken(req({ headers: { Authorization: "Bearer not-a-jwt" } })),
    null,
  );
  assertEquals(
    extractUserIdFromToken(req({ headers: { Authorization: `Bearer ${fakeJwt({ role: "x" })}` } })),
    null,
  );
});

// --- AuthService: the branches that must never reach the network ------------

Deno.test("authenticateRequest refuses a request with no bearer token", async () => {
  const result = await AuthService.authenticateRequest(req());
  assertEquals(result.success, false);
  if (result.success) throw new Error("expected failure");
  assertEquals(result.code, "INVALID_TOKEN");
});

Deno.test("authenticateRequest refuses a bearer header with nothing after it", async () => {
  const result = await AuthService.authenticateRequest(
    req({ headers: { Authorization: "Bearer    " } }),
  );
  assertEquals(result.success, false);
  if (result.success) throw new Error("expected failure");
  assertEquals(result.code, "INVALID_TOKEN");
});

Deno.test("authenticateRequest fails closed when auth is not configured", async () => {
  // The branch that matters on a misconfigured deploy: no URL, no publishable
  // key, so the function must refuse rather than call out (or hang).
  const saved = ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"]
    .map((name) => [name, Deno.env.get(name)] as const);
  for (const [name] of saved) Deno.env.delete(name);

  try {
    const result = await AuthService.authenticateRequest(
      req({ headers: { Authorization: `Bearer ${fakeJwt({ sub: "u1" })}` } }),
    );
    assertEquals(result.success, false);
    if (result.success) throw new Error("expected failure");
    assertEquals(result.code, "AUTH_ERROR");
  } finally {
    for (const [name, value] of saved) {
      if (value !== undefined) Deno.env.set(name, value);
    }
  }
});

// --- secureLogger: the whole point is what does NOT come out -----------------

Deno.test("secureLogger redacts a context key that names a credential", () => {
  const [line] = capture("log", () =>
    secureLogger.info("token issued", {
      operation: "auth",
      access_token: "sb_secret_abcdefghijkl",
      userId: "u1",
    }));
  const entry = JSON.parse(line);
  assertEquals(entry.access_token, "[redacted]");
  assertEquals(entry.userId, "u1");
  assertEquals(entry.operation, "auth");
});

Deno.test("secureLogger redacts a JWT that reached the message itself", () => {
  const jwt = fakeJwt({ sub: "u1" });
  const [line] = capture(
    "log",
    () => secureLogger.info(`rejected bearer ${jwt} from caller`, { operation: "auth" }),
  );
  const entry = JSON.parse(line);
  assertStringIncludes(entry.message, "[redacted]");
  assertEquals(entry.message.includes("eyJ"), false);
});

Deno.test("secureLogger keeps an email traceable without printing it", () => {
  const [line] = capture(
    "log",
    () => secureLogger.info("bounce", { operation: "mail", to: "alice@example.com" }),
  );
  assertEquals(JSON.parse(line).to, "a***@example.com");
});

Deno.test("secureLogger stops recursing past its depth cap", () => {
  const [line] = capture("log", () =>
    secureLogger.info("deep", {
      operation: "x",
      a: { b: { c: { d: { e: "past the cap" } } } },
    }));
  assertStringIncludes(line, "[redacted]");
  assertEquals(line.includes("past the cap"), false);
});

Deno.test("secureLogger keeps an Error's name, message and stack", () => {
  const [line] = capture("error", () =>
    secureLogger.error("job failed", {
      operation: "worker",
      error: new Error("connection refused"),
    }));
  const entry = JSON.parse(line);
  assertEquals(entry.error.name, "Error");
  assertEquals(entry.error.message, "connection refused");
  assertStringIncludes(entry.error.stack, "Error");
});

Deno.test("secureLogger redacts the credentials an Error carries in its message", () => {
  const [line] = capture("error", () =>
    secureLogger.error("refused", {
      operation: "auth",
      error: new Error(`bad token ${fakeJwt({ sub: "u1" })}`),
    }));
  const entry = JSON.parse(line);
  assertStringIncludes(entry.error.message, "[redacted]");
  assertEquals(entry.error.message.includes("eyJ"), false);
});

Deno.test("secureLogger renders a Date instead of emptying it", () => {
  const [line] = capture(
    "log",
    () => secureLogger.info("scheduled", { operation: "cron", at: new Date(0) }),
  );
  assertEquals(JSON.parse(line).at, "1970-01-01T00:00:00.000Z");
});

Deno.test("a context key cannot overwrite the envelope it travels in", () => {
  const [line] = capture("error", () =>
    secureLogger.error("the real message", {
      operation: "x",
      level: "info",
      message: "hijacked",
    }));
  const entry = JSON.parse(line);
  assertEquals(entry.level, "error");
  assertEquals(entry.message, "the real message");
  assertEquals(entry["ctx.level"], "info");
  assertEquals(entry["ctx.message"], "hijacked");
});

Deno.test("secureLogger.error writes to the error sink, not the info one", () => {
  const info = capture("log", () => {
    const errors = capture("error", () => secureLogger.error("boom", { operation: "x" }));
    assertEquals(errors.length, 1);
  });
  assertEquals(info.length, 0);
});

// --- responses ---------------------------------------------------------------

Deno.test("createEmptyResponse is a 204 that still carries the security headers", () => {
  const res = createEmptyResponse({ "Access-Control-Allow-Origin": "*" });
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("X-Content-Type-Options"), "nosniff");
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("applySecurityHeaders hardens a response without replacing it", async () => {
  const original = new Response("hello", { status: 201, headers: { "X-Kept": "1" } });
  const hardened = applySecurityHeaders(original);

  assertEquals(hardened.status, 201);
  assertEquals(hardened.headers.get("X-Kept"), "1");
  assertEquals(hardened.headers.get("X-Frame-Options"), "DENY");
  assertEquals(await hardened.text(), "hello");
});

// --- CORS: both branches, because the module reads the env per call ---------

/** Runs `fn` with ALLOWED_ORIGINS set to `value`, restoring it afterwards. */
function withAllowedOrigins(value: string | null, fn: () => void): void {
  const saved = Deno.env.get("ALLOWED_ORIGINS");
  if (value === null) Deno.env.delete("ALLOWED_ORIGINS");
  else Deno.env.set("ALLOWED_ORIGINS", value);
  try {
    fn();
  } finally {
    if (saved === undefined) Deno.env.delete("ALLOWED_ORIGINS");
    else Deno.env.set("ALLOWED_ORIGINS", saved);
  }
}

Deno.test("with no ALLOWED_ORIGINS configured, any origin is allowed", () => {
  withAllowedOrigins(null, () => {
    assertEquals(isAllowedOrigin("https://anything.example"), true);
    assertEquals(isAllowedOrigin(null), true);
    assertEquals(
      resolveAllowedOrigin(req({ headers: { Origin: "https://anything.example" } })),
      "*",
    );
  });
});

Deno.test("a configured allow-list refuses an origin that is not on it", () => {
  withAllowedOrigins("https://app.example.com, https://staging.example.com", () => {
    assertEquals(isAllowedOrigin("https://app.example.com"), true);
    assertEquals(isAllowedOrigin("https://attacker.example"), false);
    assertEquals(isAllowedOrigin(null), false);
  });
});

Deno.test("a configured allow-list never answers with a wildcard", () => {
  withAllowedOrigins("https://app.example.com,https://staging.example.com", () => {
    assertEquals(
      resolveAllowedOrigin(req({ headers: { Origin: "https://staging.example.com" } })),
      "https://staging.example.com",
    );
    const refused = resolveAllowedOrigin(req({ headers: { Origin: "https://attacker.example" } }));
    assertEquals(refused, "https://app.example.com");
    assertEquals(refused === "*", false);
  });
});

Deno.test("Vary: Origin is set exactly when the origin is echoed back", () => {
  withAllowedOrigins("https://app.example.com", () => {
    assertEquals(
      buildCorsHeaders(req({ headers: { Origin: "https://app.example.com" } }))["Vary"],
      "Origin",
    );
  });
  withAllowedOrigins(null, () => {
    assertEquals("Vary" in buildCorsHeaders(req()), false);
  });
});
