---
description: Creates a FastAPI middleware (CORS, rate limiting, logging, timing, size limit)
context: fork
disable-model-invocation: true
argument-hint: [middleware, e.g. "rate limiting" or "request logging"]
---

# Middleware Agent

Creates and registers a FastAPI middleware.

## Process

1. **Inspect** `app/main.py` (what is already registered, in which order) and
   `app/core/config.py`
2. **Write** it in `app/core/middleware.py` (or a dedicated module if large)
3. **Register** it in `main.py` at the right position
4. **Verify** the order with a request that exercises every layer

## Shapes

### CORS

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,   # never ["*"] in production
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
```

`allow_origins=["*"]` with `allow_credentials=True` is rejected by browsers —
and the error surfaces as a generic CORS failure that looks like a server bug.

### Request logging

```python
class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Logs method, path, status and duration."""

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        logger.info(
            "%s %s → %d (%.1fms)",
            request.method, request.url.path, response.status_code,
            (time.perf_counter() - start) * 1000,
        )
        return response
```

Never log the `Authorization` header, a body that may hold credentials, or a
full query string on an auth route.

### Rate limiting

```python
class RateLimitMiddleware(BaseHTTPMiddleware):
    """Sliding-window rate limit per tenant."""

    def __init__(self, app, requests_per_minute: int = 60) -> None:
        super().__init__(app)
        self.rpm = requests_per_minute
        self.windows: dict[str, list[float]] = defaultdict(list)

    async def dispatch(self, request: Request, call_next) -> Response:
        key = self._identity(request)
        now = time.time()
        self.windows[key] = [t for t in self.windows[key] if now - t < 60]

        if len(self.windows[key]) >= self.rpm:
            return JSONResponse(
                status_code=429,
                content={"error": {"code": "RATE_LIMITED", "message": "Too many requests"}},
                headers={"Retry-After": "60"},
            )

        self.windows[key].append(now)
        return await call_next(request)
```

Two caveats this shape carries: the dict is **per process** (useless behind
several workers — that wants Redis), and it grows unbounded until something
evicts idle keys. Ship it knowingly, or ship the Redis version.

Rate limit on the **authenticated identity**, not the IP, in a multi-tenant app.

### Body size limit

```python
if (length := request.headers.get("content-length")) and int(length) > MAX_BODY_SIZE:
    return JSONResponse(status_code=413, content={"error": {"code": "PAYLOAD_TOO_LARGE", ...}})
```

`content-length` is client-supplied. It stops honest large uploads; it does not
stop a chunked-encoding attacker. The real ceiling belongs to the reverse proxy.

## Registration order

`add_middleware` **prepends**: the last one added runs first.

```python
app.add_middleware(RequestLoggingMiddleware)     # runs last
app.add_middleware(TimingMiddleware)
app.add_middleware(RateLimitMiddleware, requests_per_minute=100)
app.add_middleware(RequestSizeLimitMiddleware)
app.add_middleware(CORSMiddleware, ...)          # runs first
```

CORS must run first, or a 429 returned by the rate limiter arrives without CORS
headers and the browser reports it as a network error instead of a rate limit.

`BaseHTTPMiddleware` also breaks streaming responses in some versions — for an
SSE-heavy app, prefer pure ASGI middleware and test a stream through the stack.

## Rules

- Middleware is the hot path: keep it short, allocate nothing large
- `async def dispatch`, never a blocking call inside
- No secrets in logs
- No `Any`, explicit return types

## Checklist

- [ ] In `core/middleware.py`, registered in `main.py`
- [ ] Order verified (CORS first, logging last)
- [ ] CORS origins from settings
- [ ] Rate limit keyed on identity, its process-local limitation stated
- [ ] No secrets logged
- [ ] Streaming routes still stream

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
