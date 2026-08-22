#!/usr/bin/env bash
#
# Hook: auto-approve-config
# Event: PreToolUse (Read)
# Purpose: Auto-approve reading of config and documentation files
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

# Read JSON from stdin
INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only inside this project. The patterns below are about *this repo's* config and
# documentation; auto-approving every .md on the machine hands away reads the
# user never agreed to (another project's notes, anything under $HOME).
#
# FAIL CLOSED. The previous guard was `[[ -n "$PROJECT_DIR" && ... ]]`, so an
# unset CLAUDE_PROJECT_DIR skipped the scoping test entirely and auto-approved
# every .md on the machine — the exact outcome this block exists to prevent.
# Not knowing where the project is means not auto-approving anything.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_DIR" ]]; then
    exit 0
fi
if [[ "$FILE_PATH" == /* && "$FILE_PATH" != "$PROJECT_DIR"/* ]]; then
    exit 0
fi

# Never pre-approve a secret. protect-files.sh denies these on the same event and
# a deny outranks an allow, so nothing was actually leaking — but two hooks of one
# event returning opposite decisions on `.claude/secrets.key` is a contradiction
# waiting to be resolved the wrong way by a later refactor. Keep the lists agreed.
BASENAME="${FILE_PATH##*/}"
if [[ "$BASENAME" =~ ^\.env(\..+)?$ ]] && [[ ! "$BASENAME" =~ \.(example|sample|template)$ ]]; then
    exit 0
fi
if [[ "$FILE_PATH" =~ \.pem$|\.key$|(^|/)credentials(\.|$) ]]; then
    exit 0
fi

# Patterns for auto-approved files
AUTO_APPROVE_PATTERNS=(
    "\.md$"                     # Markdown files
    "tsconfig.*\.json$"         # TypeScript config
    "\.eslintrc"                # ESLint config
    "eslint\.config\."          # ESLint flat config
    "vite\.config\."            # Vite config
    "vitest\.config\."          # Vitest config
    "tailwind\.config\."        # Tailwind config
    "postcss\.config\."         # PostCSS config
    "\.prettierrc"              # Prettier config
    "package\.json$"            # Package manifest
    "\.env\.example$"           # Example env file
    "\.claude/"                 # Claude config files
    "CLAUDE\.md$"               # Claude instructions
)

for pattern in "${AUTO_APPROVE_PATTERNS[@]}"; do
    if [[ "$FILE_PATH" =~ $pattern ]]; then
        cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Auto-approved: configuration/documentation file"
  }
}
EOF
        exit 0
    fi
done

exit 0
