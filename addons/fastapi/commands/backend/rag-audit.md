---
description: Diagnoses RAG answer quality — walks the pipeline backwards from the bad answer to its cause
context: fork
agent: Explore
disable-model-invocation: true
argument-hint: [the failing question, or the scope, e.g. "questions about deadlines return nothing"]
---

# RAG Audit Agent

Read-only. Finds **where** a bad answer was decided. It is almost never the
prompt.

## Read first — this fork starts with no project context

`agent: Explore` keeps the context small by **skipping CLAUDE.md**, so none of
`.claude/rules/` is loaded for you. Nothing below is knowable from the code
alone; read these before the first finding, or the audit judges this repo
against a generic FastAPI app:

- `.claude/rules/07-backend.md` — layers, non-negotiables, the test gate
- `.claude/rules/01-stack.md` — the data client, and **what the real
  server-side authorization barrier is** (on FastAPI it is usually a `WHERE`
  clause in `services/`, not RLS)
- `.claude/rules/06-database.md` — provider, isolation, inspection commands

Then the pipeline itself:

`.claude/skills/patterns/rag-ingestion.md` · `.claude/skills/patterns/rag-chat.md`

## Walk it backwards

Check in this order and stop at the first stage that fails — everything
downstream is a consequence.

### 1. Is the content indexed at all?

- Document status: any `error` / `empty` / stuck in `processing`?
- `chunk_count` vs the SQL chunk rows vs the point count in the vector store —
  three numbers that must agree
- Was the source text actually extracted? (scanned PDF with no OCR fallback =
  zero text, no error)

### 2. Is it chunked usably?

- Size distribution: a mass of `< 100` char chunks means the splitter found
  structure that is not there
- Does the chunk carry its heading path, and is that path **embedded** with the
  text or only stored in the payload?
- Is the answer split across a chunk boundary? Overlap or a structural split
  fixes it; a bigger `top_k` does not

### 3. Does the query reach it?

- What does the rewrite produce for this question? Log the before/after
- Is the rewrite keyword-stuffing (unclamped output drifts from every real chunk)?
- Are the intent flags right — is a broad question being treated as specific?

### 4. Does the search return it?

- Raw scores for the query: is the right chunk under `score_threshold`?
- Is a filter (`type`, `lot`, `phase`, date) excluding it?
- Is version dedup dropping the wrong document?
- Is one verbose document occupying the whole result set (missing per-document cap)?
- Did the low-threshold fallback fire, or was the answer built on nothing?

### 5. Does it survive context building?

- Character budget: was the right chunk truncated out?
- Are chunks ordered by document/page, or interleaved?
- Do the sources shown to the user come from the **same** filtered list as the
  context handed to the model?

### 6. Only now, the prompt

- Does the system prompt actually forbid answering without context?
- Is the context block delimited and attributed per source?
- Temperature, history window, token limits

## Also check

- **Isolation**: does every vector query carry the isolation key? A leak shows up
  here as an answer citing another tenant's file
- **Cost and latency**: embedding calls per turn, LLM calls per turn (rewrite +
  answer + extraction = three), sequential awaits that could be `gather`ed
- **Determinism**: anything routing on an LLM's free-text output rather than a
  whitelist

## Output

```
# RAG Audit — [scope]

## Verdict
Stage that fails: [ingestion | chunking | rewrite | search | context | prompt]

## Evidence
- file:line — what the code does
- observed: scores / counts / statuses

## Fix
[the change, in the step that owns it]

## Secondary findings
[ranked, with the stage each belongs to]
```

Read-only: propose the fix, apply nothing.

## Task: $ARGUMENTS
