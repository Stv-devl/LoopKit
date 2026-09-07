---
description: Prepare a compact disk handoff so Codex can resume without replaying Claude's conversation
argument-hint: [entry/story/research/design/plan artifact path]
---

# /handoff:codex — persist the current state for Codex

Use this before the Claude allowance is exhausted, or whenever the user asks to
continue the active track with Codex. Do **not** launch Codex inside Claude Code:
write the handoff, stop, and give the user the external command.

`/loop:orchestrate` also writes this file itself, using the same template, at
two deliberate hand-off points when `.claude/workflow-routing.yml` names
`codex` for the role and Codex is on the `PATH`: the PLAN→EXECUTE boundary
(role `execute-green`) and after the REVIEW judgment pass (role
`review-fixes`). Same file, same frontmatter, same resume rules — this command
is not only a manual saturation fallback any more.

## Process

1. Resolve the artifact and its `docs/work/<slug>/` directory. Read only the
   entry, latest workflow artifacts, current story record, `git status --short`,
   `git diff --stat`, and deterministic results already recorded on disk.
2. Write `docs/work/<slug>/handoff-codex.md` using the template below. Never
   paste source code, full diffs, conversation, secrets, or complete rule files.
3. Stop and print:
   `./codex-handoff.sh docs/work/<slug>/handoff-codex.md`

## Template

```markdown
---
phase: execute        # research | interface | plan-gate | execute | review | ship
execute_status: in-progress   # in-progress | done — only meaningful when phase: execute
review_status: judgment       # judgment | fixes-handed-to-codex | fixes-done — only meaningful when phase: review
token_profile: economy
---

# Codex handoff: <feature>
Token profile: economy | standard | critical
Entry: <path>
Current phase: research | interface | plan-gate | execute | review | ship
Worktree/branch: <path + branch, or main tree>

## Objective and acceptance criteria
<compact list; link to the source instead of duplicating long prose>

## Completed
- <durable result + artifact/file path>

## In progress
- <exact current task; RED/GREEN state if relevant>

## Remaining
1. <next concrete action>
2. <following actions through ship>

## Changed files
- <path — purpose>

## Decisions and traps
- <decision/trap — source artifact section>

## Verification
- <command — last known result, or NOT RUN>

## Resume rules
- Read `AGENTS.md`, `CLAUDE.md`, this handoff, then only relevant rules.
- Preserve the token profile and existing artifacts.
- Never read `.env*`, credentials, keys, or secrets.
- Do not redo completed phases. Update this handoff when the phase changes —
  the frontmatter (`phase`/`execute_status`/`review_status`), not only the
  prose below it: that block is what a resuming session parses, the prose is
  for a human or Codex reading it directly.
```

If no work directory exists, create it using the slug rules from `/loop:research`.
The handoff is a checkpoint, not a second plan.

## Task: $ARGUMENTS
