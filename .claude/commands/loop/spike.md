---
description: Answer one closed feasibility question with bounded evidence, or return indeterminate with the exact missing evidence
argument-hint: "<one closed question>"
---

# /loop:spike — one question, one bounded decision

Rewrite the request as exactly one closed question whose answer changes a product
or architecture decision. Present it and wait for the user's go; split compound
questions. Record it in `docs/product/spikes/<slug>.md` with the product brief's
token profile (economy by default).

Read local code, the brief and research cache first. Use at most one `explorer`
for a bounded code surface. If external documentation is necessary, give one
`doc-researcher` this single numbered question: at most one search and two
fetches. A disposable experiment stays outside owned source and its command and
output are recorded.

Return exactly one shape:

```yaml
answer: decided
decision: <yes/no or one closed option>
evidence: [<path, command output, cache entry or primary source>]
confidence: high|medium|low
```

```yaml
answer: indeterminate
missing: [<exact observation, access, environment or contract needed>]
attempted: [<evidence checked within budget>]
```

No “probably” as decided. Budget exhausted means indeterminate.

Add one link under `## Spikes` in `docs/product/brief.md`. A settled answer creates
no board line. If it opens implementation work, ask whether to frame it; only an
explicit yes creates or moves one `DRAFT` line. Indeterminate is never a board
unit by itself.

## Task: $ARGUMENTS
