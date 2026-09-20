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

INTERFACE="$ROOT/.claude/commands/loop/interface.md"
DESIGNER="$ROOT/.claude/agents/designer.md"
skip_line=$(grep -nF 'Skip first' "$REVIEW" | head -1 | cut -d: -f1)
detect_line=$(grep -nF 'pnpm dlx impeccable detect' "$REVIEW" | head -1 | cut -d: -f1)
[ -n "$skip_line" ] && [ -n "$detect_line" ] && [ "$skip_line" -lt "$detect_line" ]
grep -Fq 'an Impeccable failure is a gap in the gate, never clean' "$REVIEW"
grep -Fq 'Impeccable findings bypass stage 2' "$REVIEW"
grep -Fq 'any exit other than 0 or 2 is a gap' "$REVIEW"
grep -Fq 'an exit 0 that scanned nothing is not' "$REVIEW"
grep -Fq '22.18' "$REVIEW"
if grep -Fq 'impeccable install' "$REVIEW"; then exit 1; fi
if grep -Fiq 'impeccable' "$ROOT/.claude/commands/loop/ship.md"; then exit 1; fi
grep -Fq 'Impeccable is never a ship gate' "$REVIEW"
grep -Fq 'Playwright stays the flow proof' "$REVIEW"
grep -Fq 'impeccable' "$DESIGNER"
grep -Fq 'frontend-design' "$DESIGNER"
grep -Fq 'Impeccable, loaded by `designer`' "$INTERFACE"
grep -Fq 'only on a UI feature' "$ORCHESTRATE"
grep -Fq 'only on a UI feature' "$PLAN"
[ "$(ls "$ROOT"/.claude/commands/loop/*.md | wc -l)" -eq 12 ]
for f in PRODUCT.md DESIGN.md; do
  [ "$(wc -l < "$ROOT/$f")" -le 10 ]
done
grep -Fq 'docs/product/brief.md' "$ROOT/PRODUCT.md"
grep -Fq 'docs/design-system.md' "$ROOT/DESIGN.md"
grep -Fq 'Impeccable' "$ROOT/docs/Claude_Workflows.md"
grep -Fq '22.18' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'impeccable init' "$ROOT/docs/ADAPTATION.md"

PATTERNS="$ROOT/.claude/skills/patterns"
MOTION="$PATTERNS/motion.md"
GSAP="$PATTERNS/gsap.md"
REVIEWER="$ROOT/.claude/agents/reviewer.md"
STACK="$ROOT/.claude/rules/01-stack.md"
SPEC="$ROOT/.claude/commands/loop/spec.md"
[ -f "$MOTION" ] && [ -f "$GSAP" ]
grep -Fq '../patterns/motion.md' "$ROOT/.claude/skills/project-rules/SKILL.md"
grep -Fq '../patterns/gsap.md' "$ROOT/.claude/skills/project-rules/SKILL.md"
grep -Fq 'Motion: gsap - <reason>' "$SPEC"
grep -Fq 'Motion: gsap' "$STACK"
grep -Fq 'Animation conformance' "$REVIEWER"
grep -Fq 'GSAP not requested by the spec or design.md is Major' "$REVIEWER"
grep -Fq 'both libraries in one component (Motion and GSAP) is Major' "$REVIEWER"
grep -Fq 'an animated feature without `prefers-reduced-motion` handling is Major' "$REVIEWER"
grep -Fq 'prefers-reduced-motion' "$REVIEWER"
grep -Fq 'Acceptance criteria for animated features' "$MOTION"
grep -Fq 'prefers-reduced-motion' "$MOTION"
grep -Fq 'prefers-reduced-motion' "$PATTERNS/a11y.md"
grep -Fq 'still animates opacity' "$MOTION"
grep -Fq 'Standard no charge' "$GSAP"
grep -Fq 'Webflow' "$GSAP"
grep -Fq 'dynamic import' "$GSAP"
grep -Fq 'never in the same component' "$GSAP"
[ "$(wc -l < "$STACK")" -le 45 ]
if grep -Fq 'patterns/motion' "$ROOT/CLAUDE.md"; then exit 1; fi
grep -Fq 'ne juge pas le mouvement' "$ROOT/docs/Claude_Workflows.md"
grep -Fq 'motifs de code connus' "$ROOT/docs/Claude_Workflows.md"
grep -Fq 'patterns/motion.md' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'motifs de code connus' "$ROOT/docs/ADAPTATION.md"
[ ! -e "$ROOT/package.json" ]
for f in "$MOTION" "$GSAP" "$STACK"; do
  if grep -Eq 'motion@|gsap@|[0-9]+\.[0-9]+\.[0-9]+' "$f"; then exit 1; fi
done

echo 'workflow contract fixtures: green.'
