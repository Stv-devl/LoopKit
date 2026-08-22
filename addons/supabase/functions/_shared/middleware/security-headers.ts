/**
 * Security headers for edge function responses.
 *
 * You rarely call this directly: `createJsonResponse` / `createErrorResponse`
 * (`../utils/http.ts`) already inject `SECURITY_PRESETS.API`.
 */

export type SecurityPreset = Readonly<Record<string, string>>;

const BASE: SecurityPreset = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
};

export const SECURITY_PRESETS = {
  /** JSON APIs called by the front end. */
  API: {
    ...BASE,
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Cache-Control": "no-store",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  },
  /** Responses that may be rendered as HTML in a mail client. */
  EMAIL: {
    ...BASE,
    "Content-Security-Policy": "default-src 'none'; img-src https:; style-src 'unsafe-inline'",
  },
  /** Server-to-server webhook acks: no caching, nothing to render. */
  WEBHOOK: {
    ...BASE,
    "Cache-Control": "no-store",
  },
  /** Bare minimum, for responses that must stay embeddable. */
  MINIMAL: BASE,
} as const satisfies Record<string, SecurityPreset>;

/** Returns the headers of a preset as a plain, mutable object. */
export function buildSecurityHeaders(
  preset: SecurityPreset = SECURITY_PRESETS.API,
): Record<string, string> {
  return { ...preset };
}

/** Adds a preset's headers to an existing Response without replacing it. */
export function applySecurityHeaders(
  response: Response,
  preset: SecurityPreset = SECURITY_PRESETS.API,
): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(preset)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
