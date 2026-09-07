# Codex guidance

This project uses a disk-backed Claude/Codex workflow.

- Read `CLAUDE.md` for the constitution, then only the rules, patterns, and
  templates relevant to the current task.
- When a handoff is supplied, read it first and resume its `Current phase`.
  Do not repeat completed research, design, planning, or verification.
- Refresh `docs/work/<slug>/handoff-codex.md` after each completed step or
  test-first layer, the same way Claude's own "Automatic checkpoints" do —
  including its frontmatter (`phase`/`execute_status`/`review_status`), not
  only the prose: that block is what a resuming Claude session parses to pick
  the right resume branch, so a stale one sends it to the wrong phase.
- Artifacts in `docs/work/<slug>/` are durable truth; conversation history is not.
- Preserve the artifact's `Token profile` (`economy` by default).
- Translate Claude slash-command steps into concrete actions.
- Never read or expose `.env*`, credentials, private keys, or secrets.
- Respect `.claude/rules/05-testing.md` when touching test-first layers.
- Run deterministic gates required by the plan before claiming completion.
- **Only during a full relay** (Claude hit its limit, `workflow.py` handed you
  the whole rest of the loop, not just `execute-green`/`review-fixes`): match
  reasoning effort to what each task actually is, not one level for
  everything. `docs/codex-claude-split-plan.md`, "Économie côté Codex" has the
  full reasoning; the mapping (`inherit → high`, `sonnet → low`,
  `haiku → minimal`, taken from that document's own Claude agent tiers):

  | Task you're covering | Effort |
  | --- | --- |
  | Read-only mapping/cartography (`explorer`'s job) | `minimal` |
  | External-doc research (`doc-researcher`'s job) | `low` |
  | Interface proposal(s) (`designer`'s job) | `low` |
  | Plan critique before EXECUTE (`plan-critic`'s job) | `high` |
  | Finding + refuting REVIEW findings (`reviewer`/`verifier`'s job) | `high` |
  | Playwright spec from acceptance criteria (`e2e-tester`'s job) | `low` |
  | Git staging/commit/messages (`github`'s job) | `low` |
  | Security audit, `critical` profile (`security-auditor`'s job) | `high` |
  | Story critique (`story-critic`'s job) | `high` |
  | Story writing from a PRD (`story-writer`'s job) | `low` |
  | EXECUTE-GREEN implementation, REVIEW fix-up | `low` |
  | Bookkeeping: checkpoint, board, running gates | `minimal` |

  Values are a starting point, not settled — see that document's own caveat
  before treating them as final. During a **deliberate** hand-off
  (`execute-green`/`review-fixes` while Claude is still driving the rest), use
  `codex_effort` from `.claude/workflow-routing.yml` instead — that one stays
  fixed for the whole invocation, this table is for a relay that moves you
  through several different roles in one session.
