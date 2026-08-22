/**
 * Auth helpers that do NOT need a Supabase round-trip.
 *
 * For user authentication, use `AuthService.authenticateRequest`
 * (`../services/auth.service.ts`) — it actually validates the token.
 */

/** Constant-time string comparison. Never `===` on a secret. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function bearer(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (!header?.toLowerCase().startsWith("bearer ")) return null;
  return header.slice(7).trim() || null;
}

/** Decodes a JWT payload WITHOUT verifying the signature. */
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const json = atob(padded.padEnd(padded.length + ((4 - (padded.length % 4)) % 4), "="));
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export interface ServiceRoleResult {
  authorized: boolean;
  error?: string;
}

export interface ServiceRoleOptions {
  /**
   * Also accept a JWT whose `role` claim is `service_role`, WITHOUT verifying
   * its signature.
   *
   * ⚠️ Only safe when the platform gateway verified the JWT first — i.e. the
   * function is deployed with JWT verification ON. On a function deployed with
   * `--no-verify-jwt` (webhooks, most cron targets) this claim is attacker-
   * controlled and anyone can forge it. Default: off.
   */
  trustRoleClaim?: boolean;
}

/**
 * Authenticates a server-to-server caller (pg_cron via pg_net, function →
 * function). Compares the bearer against the secret / service-role key in
 * constant time.
 */
export function authenticateServiceRole(
  req: Request,
  options: ServiceRoleOptions = {},
): ServiceRoleResult {
  const token = bearer(req);
  if (!token) return { authorized: false, error: "Missing bearer token" };

  const secrets = [
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    Deno.env.get("SUPABASE_SECRET_KEY"),
  ].filter((v): v is string => Boolean(v));

  if (secrets.some((secret) => timingSafeEqual(token, secret))) {
    return { authorized: true };
  }

  if (options.trustRoleClaim) {
    const payload = decodeJwtPayload(token);
    if (payload?.role === "service_role") return { authorized: true };
  }

  return { authorized: false, error: "Service role required" };
}

/**
 * Reads the `sub` claim without verifying the signature.
 *
 * ONLY for keying a rate limiter before full authentication. Never as proof of
 * identity — the caller controls this value.
 */
export function extractUserIdFromToken(req: Request): string | null {
  const token = bearer(req);
  if (!token) return null;
  const sub = decodeJwtPayload(token)?.sub;
  return typeof sub === "string" ? sub : null;
}

const PRIVATE_IP =
  /^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|::1$|fc00:|fe80:|0\.0\.0\.0$)/i;

/**
 * Best-effort client IP, for rate limiting and abuse logging.
 *
 * `x-forwarded-for` is a client-supplied header that the platform appends to,
 * so the leftmost entries can be forged. We skip private and loopback ranges,
 * which stops the cheapest spoofing — it is not an identity.
 */
export function extractClientIp(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const candidate = forwarded
      .split(",")
      .map((ip) => ip.trim())
      .find((ip) => ip.length > 0 && !PRIVATE_IP.test(ip));
    if (candidate) return candidate;
  }
  return req.headers.get("cf-connecting-ip") ?? req.headers.get("x-real-ip");
}
