/**
 * CORS for edge functions.
 *
 * Origins come from the `ALLOWED_ORIGINS` secret (comma-separated). Unset, the
 * helpers fall back to `*` — acceptable while wiring a function up, never in
 * production for anything that reads a user's session.
 *
 *   supabase secrets set ALLOWED_ORIGINS=https://app.example.com,https://staging.example.com
 */

/**
 * The configured allow-list, or an empty list when the secret is unset.
 *
 * Read per call, not once at module load: read at load, the configured branch —
 * the only one that enforces anything — could not be exercised by any test in a
 * process that imported this module with the variable unset.
 */
function allowedOrigins(): readonly string[] {
  return (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean);
}

const ALLOWED_HEADERS = [
  "authorization",
  "x-client-info",
  "apikey",
  "content-type",
] as const;

/** True if the origin is explicitly allowed (or no allow-list is configured). */
export function isAllowedOrigin(origin: string | null): boolean {
  const allowed = allowedOrigins();
  if (allowed.length === 0) return true;
  return origin !== null && allowed.includes(origin);
}

/** The value to echo back in `Access-Control-Allow-Origin`. */
export function resolveAllowedOrigin(req: Request): string {
  const allowed = allowedOrigins();
  const origin = req.headers.get("origin");
  if (allowed.length === 0) return "*";
  return origin !== null && allowed.includes(origin) ? origin : allowed[0];
}

/**
 * CORS headers for this request. Pass the result to every response the handler
 * returns — including the error ones, or the browser hides the error.
 *
 * `Vary: Origin` is added only when an origin is echoed back: on a wildcard the
 * response does not depend on the request's origin, so the header would tell
 * caches to split on nothing.
 */
export function buildCorsHeaders(req: Request): Record<string, string> {
  const allowOrigin = resolveAllowedOrigin(req);
  const headers: Record<string, string> = {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": ALLOWED_HEADERS.join(", "),
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
  if (allowOrigin !== "*") headers["Vary"] = "Origin";
  return headers;
}

/**
 * Answers the CORS preflight. Returns a 204 Response for OPTIONS, `null`
 * otherwise — call it first, return its result when it is not null.
 */
export function handleCorsPreflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
}
