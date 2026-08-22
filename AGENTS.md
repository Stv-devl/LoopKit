# Codex guidance

This project uses a disk-backed Claude/Codex workflow.

- Read `CLAUDE.md` for the constitution, then only the rules, patterns, and
  templates relevant to the current task.
- When a handoff is supplied, read it first and resume its `Current phase`.
  Do not repeat completed research, design, planning, or verification.
- Artifacts in `docs/work/<slug>/` are durable truth; conversation history is not.
- Preserve the artifact's `Token profile` (`economy` by default).
- Translate Claude slash-command steps into concrete actions.
- Never read or expose `.env*`, credentials, private keys, or secrets.
- Respect `.claude/rules/05-testing.md` when touching test-first layers.
- Run deterministic gates required by the plan before claiming completion.
