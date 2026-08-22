/**
 * User authentication for edge functions.
 *
 * `authenticateRequest` asks Supabase to validate the token — it does not
 * decode it locally. That round-trip is the point: a decoded JWT proves
 * nothing on a function deployed with `--no-verify-jwt`.
 */
import { createClient, type User } from "npm:@supabase/supabase-js@2";

export type AuthErrorCode =
  | "INVALID_TOKEN"
  | "EXPIRED_TOKEN"
  | "INVALID_SESSION"
  | "NO_USER"
  | "AUTH_ERROR";

export type AuthResult =
  | { success: true; user: User; userId: string }
  | { success: false; error: string; code: AuthErrorCode };

function publicKey(): string {
  return (
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      Deno.env.get("SUPABASE_ANON_KEY") ??
      ""
  );
}

export class AuthService {
  /**
   * Validates the caller's JWT and returns the authenticated user.
   *
   * Usage:
   *   const auth = await AuthService.authenticateRequest(req);
   *   if (!auth.success) return createErrorResponse("Non autorisé", 401, corsHeaders);
   */
  static async authenticateRequest(req: Request): Promise<AuthResult> {
    const header = req.headers.get("authorization");
    if (!header?.toLowerCase().startsWith("bearer ")) {
      return { success: false, error: "Missing bearer token", code: "INVALID_TOKEN" };
    }
    const token = header.slice(7).trim();
    if (!token) {
      return { success: false, error: "Empty bearer token", code: "INVALID_TOKEN" };
    }

    const url = Deno.env.get("SUPABASE_URL");
    const key = publicKey();
    if (!url || !key) {
      return { success: false, error: "Auth is not configured", code: "AUTH_ERROR" };
    }

    const client = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    try {
      const { data, error } = await client.auth.getUser(token);

      if (error) {
        const message = error.message.toLowerCase();
        const code: AuthErrorCode = message.includes("expired")
          ? "EXPIRED_TOKEN"
          : message.includes("session")
          ? "INVALID_SESSION"
          : "INVALID_TOKEN";
        return { success: false, error: error.message, code };
      }

      if (!data.user) {
        return { success: false, error: "No user for this token", code: "NO_USER" };
      }

      return { success: true, user: data.user, userId: data.user.id };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error.message : "Unknown auth error",
        code: "AUTH_ERROR",
      };
    }
  }
}
