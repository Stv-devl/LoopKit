<!-- budget: 55 lines · /kit:doctor rules-budget -->
# Token budget

Persist one profile in every work artifact:

- `economy` default: grouped reads, main-thread synthesis, bounded optional fan-out.
- `standard`: split genuinely independent surfaces.
- `critical`: maximum independent challenge, only for payment, authorization,
  destructive data changes, or explicit user request; it also arms ship security.

Parallelise independent context, never merely separate outputs. Deterministic
gates always run: compute is not model context.

## Model tiers

| Tier | For | Agents |
| --- | --- | --- |
| `inherit` | gates: judgement that can stop the loop | `reviewer`, `verifier`, `story-critic`, `plan-critic`, `security-auditor` |
| `sonnet` | bounded production from a validated entry, and external-doc relevance | `doc-researcher`, `story-writer`, `test-writer`, `e2e-tester`, `designer`, `github` |
| `haiku` | bounded extraction/transcription | `explorer` |

A gate never runs below the session model. Agent `model:` lines are the enforced
copy and must move with this table.

## Never sleep to wait

Never sleep/poll for agents, builds, servers or migrations. Run a blocking
command and use its exit. Waiting on a human or external system ends the turn.

## Automatic thresholds

`.token-warning` at 90%, `.token-stop-agents` at 95%, `.codex-ready` at 97%.
At 95 start no agent; finish the atomic operation and checkpoint. At 97 start no
phase; the supervisor hands off. These measure context, unlike `.quota-warning`.
Keep the thresholds synchronized with `token-statusline.py`.

Measurement and rationale: `.claude/guides/11-token-budget.md`.
