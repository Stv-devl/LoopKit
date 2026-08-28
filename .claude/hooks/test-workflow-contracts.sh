#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEBUG="$ROOT/.claude/commands/loop/debug.md"
PLAN="$ROOT/.claude/commands/loop/plan.md"
CRITIC="$ROOT/.claude/agents/plan-critic.md"
PRODUCT="$ROOT/.claude/commands/loop/product.md"
ORCHESTRATE="$ROOT/.claude/commands/loop/orchestrate.md"
REVIEW="$ROOT/.claude/commands/loop/review.md"
SPIKE="$ROOT/.claude/commands/loop/spike.md"
RECIPE="$ROOT/.claude/commands/kit/recipe.md"

grep -Fq 'No fix is written or' "$DEBUG"
grep -Fq 'least two candidate causes' "$DEBUG"
grep -Fq 'LOOPKIT_DEBUG' "$DEBUG"
grep -Fq 'Pipeline` = `BUG`' "$DEBUG"

grep -Fq 'model: inherit' "$CRITIC"
grep -Fq 'completeness:' "$CRITIC"
grep -Fq 'quality:' "$CRITIC"
grep -Fq 'Never average' "$CRITIC"
grep -Fq 'PLAN CRITIC GATE' "$PLAN"
grep -Fq 'Critical/Major claim to a `verifier`' "$PLAN"

grep -Fq '`BUG` (a reproduced defect)' "$PRODUCT"
grep -Fq 'BLOCKED — <gate> failed 3x : <reason>' "$ORCHESTRATE"
grep -Fq 'never start a fourth attempt' "$ORCHESTRATE"

grep -Fq 'at most **3** items' "$REVIEW"
grep -Fq 'On `economy`, stay silent' "$REVIEW"
grep -Fq 'answer: indeterminate' "$SPIKE"
grep -Fq 'one search and two' "$SPIKE"
grep -Fq 'no board line' "$SPIKE"
grep -Fq 'exactly one citation' "$RECIPE"
grep -Fq 'automatic' "$RECIPE"

echo 'workflow contract fixtures: green.'
