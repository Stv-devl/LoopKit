---
description: Whole-repository security audit — parallel fan-out by surface, then refutation of every Critical/Major finding
argument-hint: [--economy|--standard|--critical] [surface or everything]
---

# /audit:security — what is exposed today

Out of the loop, on the codebase **as it stands**. Not a diff review: the code
nobody has touched in six months is exactly where this looks.

> Not to be confused with `/loop:review`'s `security` dimension, which judges a diff
> inside the loop, nor with `/backend:security` (FastAPI addon), which owns the
> Python backend in depth.

**One caller invokes this command on its own.** On a `critical` token profile,
`/loop:ship` runs it before the commit, scoped to **one** surface chosen from what
made the feature `critical` (step 1bis there; the trigger list is
`11-token-budget.md`'s and is the only copy). Nothing changes for you: same
single-auditor path as any single-surface request, same read-only contract, same
whole-repository scope — **not** diff-scoped, which is the point, since the code
the diff never touched is where this looks. What changes is downstream: a
Critical you return there stops the ship, so a finding you cannot give an
exploitation path to belongs in Minor, as always.

You write **nothing** to the codebase here. The output is a report; fixes go
through the normal loop, with their tests.

## Process

### Stage 1 — AUDIT (parallel fan-out)

Select `economy` by default, or the explicit token profile, then launch one
message of `security-auditor` agents. An agent may own several named surfaces:

Every auditor is an `Agent` with **`subagent_type: security-auditor`** — the
agent's name is not "auditor", and a bare `general-purpose` carries neither the
surface checklists nor the "never print a secret value" contract.

- **economy:** 2 `security-auditor` agents: `secrets + supply-chain + data-exposure`, and
  `authz + session + input-output`.
- **standard:** 3 `security-auditor` agents, two related surfaces each.
- **critical:** 6 `security-auditor` agents, one per surface, only by explicit request.

For a single requested surface, launch one auditor regardless of profile.

> **While they run, do not poll and do not `sleep`.** You are re-invoked when
> each one finishes. A turn spent waiting is billed twice, in tokens and in
> wall-clock, and the transcript looks busy the whole time
> (`.claude/rules/11-token-budget.md`).

| Surface | Covers |
| --- | --- |
| `secrets` | what ships in the bundle (`VITE_*` is public), hardcoded keys, `.env.example` drift, secrets in logs and storage |
| `authz` | the server-side barrier from `01-stack.md` vs every table/endpoint, IDOR, cross-user leaks, escalation |
| `input-output` | Zod at every boundary **including API responses**, injection, XSS, open redirect, upload |
| `session` | token storage, refresh, expiry, complete logout (React Query cache cleared), enumeration |
| `data-exposure` | over-fetching, PII in logs and URLs, raw errors on screen, debug surfaces left on |
| `supply-chain` | dependency audit, lockfile, lifecycle scripts, third-party scripts, CSP |

Given a single surface as `$ARGUMENTS`, run only that one. Given `everything` or
nothing, run all six.

Pass each agent only its assigned surfaces and scope restriction. It reads
shared project rules once for the batch and reports each surface separately.
**Announce a skipped surface with its reason**. Barrier: gather all reports.

### Stage 2 — REFUTE (parallel fan-out)

Group arguable Critical/Major findings by audit batch. Launch at most 2
`verifier` batches (`subagent_type: verifier`) in economy, 3 in standard, or one per surface in critical.
Each finding still receives an independent verdict inside its batch.

- `refuted: true` → drop it, keep it in the report as refuted
- `refuted: false` → confirmed, and it now carries a failure scenario

Skip stage 2 on the obvious (a literal key in the source, a missing lockfile) and
on Minor findings — refuting them costs more than reading them.

Security findings refute in a specific way: the usual counter-argument is "the
server blocks it anyway". That only holds if the verifier **names the barrier and
where it is enforced**. "There is probably a policy" is not a refutation.

### Stage 3 — SYNTHESIS

1. Aggregate the surviving findings by severity, across surfaces. Deduplicate:
   one missing barrier found by three surfaces is one finding.
2. Merge the `Checked, clean` lines — this is the coverage statement.
3. Merge `Not verifiable from here` — the deployed config, the server-side rules,
   anything behind a secret you must not read. **This section is the honest edge
   of the audit**; an empty one is a claim, not a result.
4. Order the fixes by exploitability, not by how easy they are.
5. Propose. Apply nothing.

## Output

```
## Security audit: <scope> — <n> Critical / <n> Major / <n> Minor
### Critical
- path:line — what is exposed
  Path: <who> from <where> obtains <what>
  Fix: <the direction, one line>
### Major / Minor
- path:line — what is exposed (+ path for Major)
### Refuted (dropped)
- <finding> — <the barrier that actually blocks it, and where>
### Checked, clean
- <surface> — <what was verified>
### Not verifiable from here
- <what needs the server, the deployed config, or a secret>
### Skipped surfaces
- <surface> — <reason>
```

## Rules

- **Never print a secret's value** — `path:line` and the variable name. The report
  is a file on disk; a quoted key is a new leak.
- Never read `.env*`, `*.pem`, `*.key`. The `protect-files` block is the answer,
  not an obstacle to route around.
- **Read-only, no exploitation**: nothing sent to any environment, no credential
  tested. This audit reads code and config.
- A finding with no exploitation path is Minor, and says what would raise it.
- Report the refuted findings. A gate that drops nothing is rubber-stamping.

## Task: $ARGUMENTS
