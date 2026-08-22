# Measuring the loop before optimising it

Read this when you want to make the loop cheaper or faster. It is deliberately
**not** a rule file: it is needed once per audit, not once per session. The rule
it serves is `.claude/rules/11-token-budget.md`.

## Guessing has a poor record

Three hypotheses in one audit, three wrong: the write hooks cost 1.6 mn out of
400, the doc-research fan-out turned out to be a one-off bootstrap rather than a
per-feature cost, and the 34-minute migration was 5 minutes of work behind one
unapproved `Write`.

## Where the numbers are

- **Hook cost**: `.claude/hooks/hook-timings-report.sh` (`--reset` before a run).
  Every hook records its own duration in `.claude/.hook-timings.log`;
  `CWK_HOOK_TIMING=0` turns the recording off.
- **Everything else**: the session transcript is timestamped, per turn and per
  agent. Gaps between a `tool_use` and its `tool_result` separate real work from
  blocking, and the per-agent files separate work from waiting on children.

## How to read them

Read the **TOTAL** column, never the average, and compare a cumulated figure to
a calendar one before calling something the biggest cost: agents that ran in
parallel do not add up.

The measurement that pays for itself first is dead time, not token count — an
agent asleep on a `sleep` looks identical to an agent working, in every view
except the timestamps. That failure mode, and the rule that forbids it, are in
`.claude/rules/11-token-budget.md`.
