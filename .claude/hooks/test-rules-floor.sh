#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_CEILING=520

# budget_of <file> / addon_of <file>: the header's `budget: N lines` and `addon +N`.
budget_of() { sed -n '1s/^<!-- budget: \([0-9][0-9]*\) lines.*/\1/p' "$1"; }
addon_of() { sed -n '1s/^<!-- budget: [0-9]* lines · addon +\([0-9][0-9]*\) ·.*/\1/p' "$1"; }

# In the kit, each addon rule's `addon +N` is its budget minus the budget of the
# core rule it replaces (0 when it replaces none): the allowance cannot drift.
if [[ -d "$ROOT/addons" ]]; then
    for f in "$ROOT"/addons/*/rules/*.md; do
        [[ -e "$f" ]] || continue
        rel="${f#"$ROOT"/}"
        extra="$(addon_of "$f")"
        [[ -n "$extra" ]] || { echo "addon rule without an 'addon +N' allowance: $rel" >&2; exit 1; }
        core="$ROOT/.claude/rules/$(basename "$f")"
        core_budget=0
        [[ -f "$core" ]] && core_budget="$(budget_of "$core")"
        want=$(( $(budget_of "$f") - ${core_budget:-0} ))
        [[ "$extra" -eq "$want" ]] || {
            echo "$rel: addon +$extra, expected +$want (its budget minus the core rule's)" >&2
            exit 1
        }
    done
fi

ALLOWANCE=0
for f in "$ROOT"/.claude/rules/*.md; do
    extra="$(addon_of "$f")"
    ALLOWANCE=$(( ALLOWANCE + ${extra:-0} ))
done
CEILING=$(( CORE_CEILING + ALLOWANCE ))
TOTAL="$(wc -l "$ROOT/CLAUDE.md" "$ROOT"/.claude/rules/*.md | tail -1 | awk '{print $1}')"
[[ "$TOTAL" -le "$CEILING" ]] || {
    echo "session floor regression: $TOTAL lines (ceiling $CEILING = core $CORE_CEILING, ratcheted down from 622 by the 2026-10 slimming, + addon allowances $ALLOWANCE)" >&2
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

echo "rules floor fixture: $TOTAL lines (ceiling $CEILING), green."
