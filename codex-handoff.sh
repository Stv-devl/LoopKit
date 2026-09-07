#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT="${1:-}"
ROLE="${2:-}"

if ! command -v codex >/dev/null 2>&1; then
    echo "erreur: le CLI Codex n'est pas installé ou absent du PATH." >&2
    exit 1
fi

# Optional second arg: the workflow-routing.yml role this handoff is for
# (execute-green, review-fixes — cf. docs/codex-claude-split-plan.md, "Économie
# côté Codex"). Absent role, absent file, or a role not routed to codex →
# no flag added, identical to today's command. The file's one-role-per-line
# shape is simple enough for grep/sed — no YAML parser pulled in for this.
EFFORT_FLAG=()
ROUTING_FILE="$PROJECT_DIR/.claude/workflow-routing.yml"
if [[ -n "$ROLE" && -f "$ROUTING_FILE" ]]; then
    ROLE_LINE="$(grep -E "^[[:space:]]*${ROLE}:" "$ROUTING_FILE" || true)"
    if [[ "$ROLE_LINE" == *"provider: codex"* ]]; then
        EFFORT="$(printf '%s' "$ROLE_LINE" | sed -nE 's/.*codex_effort:[[:space:]]*([A-Za-z]+).*/\1/p')"
        [[ -n "$EFFORT" ]] && EFFORT_FLAG=(-c "model_reasoning_effort=$EFFORT")
    fi
fi

if [[ -z "$ARTIFACT" ]]; then
    ARTIFACT="$(find "$PROJECT_DIR/docs/work" "$PROJECT_DIR/docs/stories" "$PROJECT_DIR/docs/specs" \
        -type f -name '*.md' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"
fi
if [[ -z "$ARTIFACT" ]]; then
    echo "usage: ./codex-handoff.sh <handoff, plan, research, story ou spec.md>" >&2
    exit 1
fi
if [[ "$ARTIFACT" != /* ]]; then ARTIFACT="$PROJECT_DIR/$ARTIFACT"; fi
if [[ ! -f "$ARTIFACT" ]]; then
    echo "erreur: artefact introuvable: $ARTIFACT" >&2
    exit 1
fi
case "$(realpath "$ARTIFACT")" in
    "$PROJECT_DIR"/*) ;;
    *) echo "erreur: l'artefact doit appartenir au projet." >&2; exit 1 ;;
esac

RELATIVE_ARTIFACT="$(realpath --relative-to="$PROJECT_DIR" "$ARTIFACT")"
PROMPT="Resume the project workflow from $RELATIVE_ARTIFACT. Read AGENTS.md, CLAUDE.md, and that artifact first. If it is not a prepared handoff, infer the current phase from adjacent docs/work artifacts, story status, and git status; do not redo completed phases. Preserve the recorded token profile (economy by default), existing user changes, security boundaries, TDD markers, and frozen tests. Continue the next concrete action through its next human gate. Keep durable progress in the existing workflow artifacts."

exec codex -C "$PROJECT_DIR" -s workspace-write -a on-request "${EFFORT_FLAG[@]}" "$PROMPT"
