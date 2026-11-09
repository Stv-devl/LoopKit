# Spike: does Claude Code prompt on `.claude/.tdd-unfrozen` on its own?
Date: 2026-11-09 · Token profile: economy · Source spec: `docs/specs/fewer-validations.md` (V7, V10)

## Question
When the kit hook does not ask (no decision, or `allow`), does Claude Code still raise its own `safetyCheck` prompt on a Write/Edit to `.claude/.tdd-unfrozen`?

## Method
Read-only scan of local transcripts `~/.claude/projects/*/*.jsonl` (worktrees excluded). For each Edit/Write result on a `/.claude/` path, join the PreToolUse hook outputs of the same `tool_use_id` (`ask` / `allow` / none) with the recorded `permissionDecision` (`source`, `reasonCode`). Commands: `python3 -I -c` over the jsonl, run 2026-11-09, Claude Code 2.1.319.

## Evidence
| Path | Kit hook | Final decision | Count |
| --- | --- | --- | --- |
| `.tdd-unfrozen` | ask | `user_temporary` / `safetyCheck` | 18 (all on 2.1.319, EcoCrew `8b64b672`) |
| `.tdd-unfrozen` | none | `config` (no prompt) | 184 (2.1.296 → 2.1.319, 5 on 2.1.319) |
| `agents`, `commands`, `guides`, `skills`, `rules` | none | `config` (no prompt) | 73 |
| `hooks`, `scripts`, `settings.json` | ask | `safetyCheck` / `hook:PreToolUse` / `unknown` | prompts |

Every `safetyCheck` on a `.claude/` write followed a kit-hook `ask`; none occurred without one. The EcoCrew asks start with `d6839cb` (2026-10-28), which made `.tdd-unfrozen` a guarded path.

## Answer
```yaml
answer: decided
decision: no — Claude Code raises no prompt of its own on .claude/.tdd-unfrozen; the 18 asks are the kit hook's ask, labelled safetyCheck
evidence: [~/.claude/projects/*/*.jsonl scan above, .claude/hooks/hook-guarded.sh:25, commit d6839cb]
confidence: medium
```
Medium, not high: a hook `allow` on a `.claude/` write was never observed (only no-decision), and every observation runs under this machine's permission settings (Claude Code `auto` mode / allow rules). V7/V10's first pass confirms it in the measure.

## Consequence
`.tdd-unfrozen` stays at `.claude/.tdd-unfrozen`; no move. V7/V10 rely on the kit hook's record-backed allow alone.
