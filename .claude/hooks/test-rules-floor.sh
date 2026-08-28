#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOTAL="$(wc -l "$ROOT/CLAUDE.md" "$ROOT"/.claude/rules/*.md | tail -1 | awk '{print $1}')"
[[ "$TOTAL" -le 622 ]] || {
    echo "session floor regression: $TOTAL lines (must stay at or below half of 1,245 = 622)" >&2
    exit 1
}

ROUTER="$ROOT/.claude/skills/project-rules/SKILL.md"
grep -Fq 'name: project-rules' "$ROUTER"
for path in \
    .claude/skills/templates/lib-core.md \
    .claude/skills/templates/feature.md \
    .claude/skills/templates/component.md \
    .claude/skills/templates/page.md \
    .claude/skills/patterns/react-query.md \
    .claude/skills/patterns/a11y.md \
    .claude/skills/patterns/tests.md \
    .claude/skills/patterns/msw.md \
    .claude/guides/05-testing.md; do
    [[ -f "$ROOT/$path" ]] || { echo "router target missing: $path" >&2; exit 1; }
done

echo "rules floor fixture: $TOTAL lines, green."
