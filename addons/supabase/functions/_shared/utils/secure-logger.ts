/**
 * Structured logger that redacts credentials before they reach the log drain.
 *
 * Edge function logs are readable by anyone with dashboard access and are
 * retained; a token logged once is a token leaked.
 *
 *   secureLogger.info("job accepted", { operation: "example-api", jobId });
 *
 * `operation` is expected on every call — it is what makes a log searchable.
 */

export interface LogContext {
  /** The function or unit of work emitting the log. */
  operation: string;
  [key: string]: unknown;
}

const SENSITIVE_KEY =
  /(token|secret|password|passwd|api[-_]?key|authorization|cookie|credential|signature)/i;
const JWT_LIKE = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
const SUPABASE_KEY_LIKE = /\bsb_(publishable|secret)_[A-Za-z0-9_-]{8,}/g;
const EMAIL_LIKE = /\b[\w.+-]+@([\w-]+\.)+[\w-]{2,}\b/g;

const REDACTED = "[redacted]";
const MAX_DEPTH = 4;

/** Fields the envelope owns. A context key of the same name cannot claim them. */
const RESERVED_FIELDS = ["level", "message", "timestamp"] as const;

function redactString(value: string): string {
  return value
    .replace(JWT_LIKE, REDACTED)
    .replace(SUPABASE_KEY_LIKE, REDACTED)
    .replace(EMAIL_LIKE, (m) => `${m[0]}***@${m.split("@")[1]}`);
}

/**
 * Unpacks an Error into loggable fields.
 *
 * `Object.entries(new Error("boom"))` is `[]` — `name`, `message` and `stack`
 * are non-enumerable, so the generic object branch would serialise the single
 * most common call in this file, `secureLogger.error("failed", { operation,
 * error })`, as `"error":{}` and discard the only thing worth logging.
 */
function redactError(error: Error, depth: number): Record<string, unknown> {
  return {
    name: error.name,
    message: redactString(error.message),
    ...(error.stack ? { stack: redactString(error.stack) } : {}),
    ...(error.cause !== undefined ? { cause: redact(error.cause, depth + 1) } : {}),
  };
}

function redact(value: unknown, depth = 0): unknown {
  if (depth > MAX_DEPTH) return REDACTED;
  if (typeof value === "string") return redactString(value);
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map((v) => redact(v, depth + 1));
  if (value instanceof Error) return redactError(value, depth);
  if (value instanceof Date) return value.toISOString();

  const out: Record<string, unknown> = {};
  for (const [key, val] of Object.entries(value as Record<string, unknown>)) {
    out[key] = SENSITIVE_KEY.test(key) ? REDACTED : redact(val, depth + 1);
  }
  return out;
}

/**
 * Moves any context key that collides with an envelope field to `ctx.<key>`.
 *
 * Spread last, a context key called `level` used to overwrite the envelope's:
 * the line went to the error sink while claiming `"level":"info"`, and a log
 * drain filtering on that field believed the line, not the sink. The envelope
 * wins now, and the colliding value is kept rather than dropped.
 */
function withoutReservedFields(context: Record<string, unknown>): Record<string, unknown> {
  const out = { ...context };
  for (const field of RESERVED_FIELDS) {
    if (field in out) {
      out[`ctx.${field}`] = out[field];
      delete out[field];
    }
  }
  return out;
}

type Level = "info" | "warn" | "error";

function emit(level: Level, message: string, context: LogContext): void {
  const line = JSON.stringify({
    level,
    message: redactString(message),
    timestamp: new Date().toISOString(),
    ...withoutReservedFields(redact(context) as Record<string, unknown>),
  });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

export const secureLogger = {
  info: (message: string, context: LogContext): void => emit("info", message, context),
  warn: (message: string, context: LogContext): void => emit("warn", message, context),
  error: (message: string, context: LogContext): void => emit("error", message, context),
} as const;
