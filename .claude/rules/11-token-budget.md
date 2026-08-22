<!-- budget: 90 lines · /kit:doctor rules-budget -->
# Token budget

The loop carries one profile in every `docs/work/<slug>/` artifact.

- **economy** (default): combine tasks that read the same PRD, diff, or code
  surface. Prefer main-thread synthesis. Cap optional design and E2E branches.
- **standard**: split only genuinely independent surfaces or review dimensions.
- **critical**: maximum independent challenge, reserved for payment,
  authorization, destructive data changes, or explicit user request.

**This block is the only copy of what the three profiles mean, and of the list
that justifies `critical`.** Each command declares its own *arity* — how many
explorers, reviewers, auditors, designers — and cites this file for the rest.
A new trigger for `critical` is added here, once. Never silently upgrade a
profile.

**`critical` is not only a budget.** Those four triggers are, word for word, the
features where a missing server-side barrier is not a Minor, so the same flag
**arms a one-surface `/audit:security` at `/ship`** (that command, step 1bis,
maps surface to trigger). One `security-auditor` agent on those four, zero
everywhere else. Downgrading a feature to `economy` to skip it is a security
decision wearing a budget costume: say it out loud if you do it.

Parallel execution reduces elapsed time, not token usage. A separate agent is
justified by independent context, a required isolation boundary, or a distinct
tool surface — never merely by a separate output file.

## The model tier is the fourth axis, and this is its only rule

Profile, arity and grouping decide *how many* agents. The `model:` line of each
agent decides *how good* each one is, and it is a budget decision like the others
— so it is declared here rather than left to whoever created the file.

| Tier | For | Agents |
| --- | --- | --- |
| `inherit` | anything that **judges**: a gate, a refutation, a proposal, a written test | `reviewer`, `verifier`, `story-critic`, `security-auditor`, `test-writer`, `designer`, `e2e-tester`, `github` |
| `haiku` | bounded **extraction or transcription** from a source already decided | `explorer`, `story-writer` |
| `sonnet` | one exception: `doc-researcher`, which reads untrusted external prose and must judge relevance — but under a hard network budget that caps what it can spend | `doc-researcher` |

**The enforced copy is the `model:` line of each `.claude/agents/*.md`** — change
both together, never one alone. `/kit:doctor`'s `agent-models` compares them, and
it is the only thing that does: an agent started by copying its neighbour
inherits that neighbour's tier in silence.

**A gate never runs below the session's model.** Downgrading a judge to save
tokens is a quality decision wearing a budget costume; say it out loud if you
do it.

Always run the deterministic typecheck, lint, test, coverage, build and
**dependency-audit** gates: they cost compute, not model context. Persist compact
findings on disk; downstream steps read artifacts instead of replaying
conversation.

## Never sleep to wait

Waiting by sleeping gives back everything parallelism bought, and every poll is
a billed turn. No exception:

- **Never `sleep` to wait for a subagent.** You are re-invoked when it finishes.
- **Never `sleep` to wait for a build, a file, a server or a migration.** Run the
  blocking command and let it block — its exit code is the signal.
- **Waiting on something outside the machine** — a human answer, a remote deploy,
  an external queue — means saying so and **stopping the turn**. A turn that ends
  is free; a turn that sleeps is billed twice, in tokens and in wall-clock.

## Automatic threshold behaviour

The status line creates `.token-warning` at 90%, `.token-stop-agents` at 95%,
and `.codex-ready` at 97% context use. At 95%, start no new subagent; finish the
current atomic operation and update `handoff-codex.md`. At 97%, start no new
phase. These percentages measure context-window use, **not** the user's
subscription allowance.

**The enforced copy is `.claude/hooks/token-statusline.py`** — change the numbers
there and here together. The supervisor acts on `.codex-ready` alone; the other
two markers are written for the status line and for you, and nothing enforces
them.

> `workflow.py` carries its own 90 and 95 in a fourth marker, `.quota-warning`:
> same numbers, *subscription* usage, unrelated meaning. Any report must say
> which of the two it is talking about.

Rationale, the measured failure mode, and how to audit the loop:
`.claude/guides/11-token-budget.md`.
