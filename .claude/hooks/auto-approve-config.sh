#!/usr/bin/env bash
# cwk-guard-api: 1
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
if [[ "$PROJECT_DIR" != /* ]]; then
    exit 0
fi
if [[ "$FILE_PATH" =~ (^|/)\.\.(/|$) ]]; then
    exit 0
fi

# No resolver (hook-guarded.sh missing or stale) → no approval.
declare -F cwk_real_rel __cwk_guard_norm >/dev/null 2>&1 || exit 0

# A relative path is read from the session's cwd, else the project dir.
BASE=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -n "$BASE" ]] || BASE="$PROJECT_DIR"

# A main-tree session must not auto-approve files of a sibling worktree. Read
# lexically first (`$P//.claude/worktrees/…`, `$P/./.claude/worktrees/…`), then
# physically below, where a symlink into a worktree lands.
LEXICAL="$FILE_PATH"
[[ "$LEXICAL" == /* ]] || LEXICAL="$BASE/$LEXICAL"
LEXICAL="$(__cwk_guard_norm "$LEXICAL")"
if [[ "$LEXICAL" == "$(__cwk_guard_norm "$PROJECT_DIR")"/.claude/worktrees/* ]]; then
    exit 0
fi

# The file the path opens, symlinks followed. Outside the project, nothing is
# approved: a link inside it may name ~/.ssh/id_rsa.
REL_PATH=$(cwk_real_rel "$FILE_PATH" "$BASE") || exit 0
if [[ "$REL_PATH" == .claude/worktrees/* ]]; then
    exit 0
fi

# Never pre-approve a secret, by the name given or by the file it opens.
# protect-files.sh denies these on the same event and a deny outranks an allow,
# but two hooks of one event returning opposite decisions is a contradiction
# waiting to be resolved the wrong way by a later refactor. Keep the lists agreed.
for probe in "$FILE_PATH" "$REL_PATH"; do
    BASENAME="${probe##*/}"
    if [[ "$BASENAME" =~ ^\.env(\..+)?$ ]] && [[ ! "$BASENAME" =~ \.(example|sample|template)$ ]]; then
        exit 0
    fi
    if [[ "$probe" =~ \.pem$|\.key$|(^|/)\.?credentials(\.|$) ]]; then
        exit 0
    fi
done

# Patterns for auto-approved files
AUTO_APPROVE_PATTERNS=(
    "\.md$"                     # Markdown files
    "^tsconfig[^/]*\.json$"     # TypeScript config (project root)
    "^\.eslintrc"               # ESLint config
    "^eslint\.config\."         # ESLint flat config
    "^vite\.config\."           # Vite config
    "^vitest\.config\."         # Vitest config
    "^tailwind\.config\."       # Tailwind config
    "^postcss\.config\."        # PostCSS config
    "^\.prettierrc"             # Prettier config
    "^package\.json$"           # Package manifest
    "^\.env\.example$"          # Example env file
    "^\.claude/"                # Claude config files
    "CLAUDE\.md$"               # Claude instructions
)

for pattern in "${AUTO_APPROVE_PATTERNS[@]}"; do
    if [[ "$REL_PATH" =~ $pattern ]]; then
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
