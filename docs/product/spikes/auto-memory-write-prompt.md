# Spike: does Claude Code prompt on a Write/Edit to the auto-memory?
Date: 2026-11-09 · Token profile: economy · Source spec: `docs/specs/fewer-validations.md` (V11)

## Question
Does a Write/Edit on `~/.claude/projects/*/memory/*.md` trigger a Claude Code permission prompt?

## Method
Same read-only transcript scan as `safetycheck-tdd-unfrozen.md`: every Edit/Write result on a `/memory/` path with its `permissionDecision`.

## Evidence
318 Write/Edit on auto-memory files across projects (LoopKit, EcoCrew, CRMperso, home), versions 2.1.299 → 2.1.319 (43 on 2.1.319): all `source: config`, zero prompts. The 3 asks counted in EcoCrew were `sed -i` through Bash ("writes outside the project").

## Answer
```yaml
answer: decided
decision: no — Write/Edit on the auto-memory raises no prompt
evidence: [~/.claude/projects/*/*.jsonl scan, 318 writes, 0 prompts]
confidence: high
```

## Consequence
V11 is kept: the rule "never write any file from the shell, the auto-memory included" removes those asks.
