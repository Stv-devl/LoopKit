/**
 * Response helpers. Every edge function returns through these, so the error
 * shape stays flat and the security headers are never forgotten.
 *
 * Error shape, everywhere: `{ "error": "message" }` — a string, not an object.
 */
import {
  buildSecurityHeaders,
  SECURITY_PRESETS,
  type SecurityPreset,
} from "../middleware/security-headers.ts";

/** JSON response with security headers + whatever CORS headers you pass. */
export function createJsonResponse(
  data: unknown,
  status = 200,
  headers: Record<string, string> = {},
  preset: SecurityPreset = SECURITY_PRESETS.API,
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...buildSecurityHeaders(preset),
      ...headers,
      "Content-Type": "application/json",
    },
  });
}

/**
 * Error response in the flat shape. `message` reaches the client — keep it
 * free of internals; the detail belongs in `secureLogger.error`.
 */
export function createErrorResponse(
  message: string,
  status = 500,
  headers: Record<string, string> = {},
  preset: SecurityPreset = SECURITY_PRESETS.API,
): Response {
  return createJsonResponse({ error: message }, status, headers, preset);
}

/** 204, for handlers with nothing to return. */
export function createEmptyResponse(
  headers: Record<string, string> = {},
): Response {
  return new Response(null, {
    status: 204,
    headers: { ...buildSecurityHeaders(SECURITY_PRESETS.API), ...headers },
  });
}
