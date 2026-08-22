---
description: Creates an SSE streaming endpoint (LLM tokens, job progress, live events)
context: fork
disable-model-invocation: true
argument-hint: [stream, e.g. "RAG chat streaming" or "ingestion progress"]
---

# SSE Stream Agent

Creates a FastAPI Server-Sent Events endpoint.

## Read first

`.claude/skills/patterns/rag-chat.md` (Streaming section) ·
`.claude/skills/patterns/fastapi-architecture.md`

## Process

1. **Parse**: what streams — LLM tokens, progress, events
2. **Inspect**: existing SSE routes in `app/api/`, the streaming services, and
   the client module in `app/core/`
3. **Write** the route + the generator service
4. **Test** with `curl -N` and with a unit test that collects the yielded events

## Endpoint

```python
@router.post("/{project_id}/stream")
async def stream_chat(
    project_id: str,
    data: ChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> StreamingResponse:
    return StreamingResponse(
        chat_service.stream(db, current_user.tenant_id, project_id, data),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
```

## Service

```python
async def stream(...) -> AsyncGenerator[str, None]:
    try:
        ...
        async for token in self._stream_llm(prompt):
            answer += token
            yield f"data: {json.dumps({'type': 'token', 'content': token})}\n\n"

        yield f"data: {json.dumps({'type': 'sources', 'content': sources})}\n\n"
        await self._persist(...)          # after the stream, not during
    except Exception:
        logger.exception("Stream failed")
        yield f"data: {json.dumps({'type': 'error', 'content': '<user message>'})}\n\n"

    # Terminal event on both paths — and NOT in a `finally`. See below.
    yield f"data: {json.dumps({'type': 'done'})}\n\n"
```

### Never `yield` from a `finally`

It is the obvious way to guarantee the terminator, and it breaks the one case it
was written for. When the client hangs up, Starlette closes the generator:
`GeneratorExit` is raised at the suspended `yield`, the `finally` runs, and a
`yield` there gets you

```
RuntimeError: async generator ignored GeneratorExit
```

— an exception in the server logs on every cancelled stream, for a frame nobody
is listening to any more. Put the terminator on both normal paths instead, as
above. A `finally` is still the right place for **cleanup that does not yield**:
closing a session, releasing a lock, cancelling a side task.

## Progress variant

```python
for i, step in enumerate(STEPS):
    yield f"data: {json.dumps({'type': 'progress', 'step': step, 'pct': i / len(STEPS) * 100})}\n\n"
    await run_step(step, ...)
yield f"data: {json.dumps({'type': 'done', 'pct': 100})}\n\n"
```

## Rules

- `media_type="text/event-stream"`, and the three anti-buffering headers —
  without `X-Accel-Buffering: no`, nginx holds the tokens and delivers the whole
  answer at once
- Wire format `data: {json}\n\n` — the double newline is the frame delimiter
- Return type `AsyncGenerator[str, None]`
- **A terminal event on every path**, error included: a client waiting for a
  terminator it never receives spins forever — emitted from the normal paths,
  never from a `finally` (see above)
- Once the first byte is sent the status is 200 — an exception can no longer
  become a 4xx/5xx. Catch it and emit an `error` event
- Persist after the stream completes, never per token
- Parallel side work: `asyncio.create_task` **before** the stream loop, awaited
  after — sequentially the user pays for both
- Never share the request `AsyncSession` across concurrent tasks: it is not
  concurrency-safe, and it fails under load, not in dev
- Isolation filtering happens in the service, not in the route
- No `Any`

## Checklist

- [ ] `StreamingResponse` + `text/event-stream` + anti-buffering headers
- [ ] Generator typed `AsyncGenerator[str, None]`
- [ ] `data: {"type": …}\n\n` frames — the same envelope as
      `patterns/rag-chat.md`, documented for the frontend
- [ ] Terminal event on success **and** on error, and no `yield` in a `finally`
- [ ] Errors caught inside the generator
- [ ] Persistence after completion
- [ ] Auth dependency on the route
- [ ] A test that collects the event sequence

> Respects `.claude/rules/`.

## Task: $ARGUMENTS
