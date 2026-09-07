#!/usr/bin/env bash
#
# Hook: no-any-type
# Event: PreToolUse (Write|Edit)
# Purpose: Block usage of 'any' type in TypeScript files
#
# NOTE: on Edit, only the inserted delta (new_string) is inspected, not the whole
#       file. An 'any' already present elsewhere in the file passes through here —
#       backstop = reviewer agent (correctness dimension).
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

# Read JSON from stdin
INPUT=$(cat)

# Extract file path and content
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty')

# Skip if no file path or not a TS/TSX file
if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ \.(ts|tsx)$ ]]; then
    exit 0
fi

# Skip if no content
if [[ -z "$CONTENT" ]]; then
    exit 0
fi

# Strip what is not code before matching, so a JSDoc `@returns {any}` or a
# string literal does not trigger a denial:
#   1. line comments   //...
#   2. JSDoc/block continuation lines starting with *
#   3. single-line block comments /* ... */
#   4. string literals — all three quotings. Missing ' and ` here meant a rule
#      written as 'no `as any`' in a message string denied its own file.
CODE=$(printf '%s\n' "$CONTENT" \
    | sed -E 's://.*$::' \
    | sed -E '/^[[:space:]]*\*/d' \
    | sed -E 's:/\*.*\*/::g' \
    | sed -E 's:"[^"]*"::g' \
    | sed -E "s:'[^']*'::g" \
    | sed -E 's:`[^`]*`::g')

# Check for 'any' type usage (but not 'company', 'many', etc.)
# Every pattern ends on `any\b`, so an identifier merely STARTING with "any"
# (`anyOf`, `anything`) never matches — the boundary is what keeps this cheap.
# Patterns to detect:
# - : any        (annotation, incl. `: any[]`, `: any)`)
# - as any       (cast)
# - satisfies any
# - <any>  <any, (first generic argument: Promise<any>, Array<any>)
# - , any>  , any,  (later generic argument: Record<string, any>, Map<K, any>)
# - extends any
# - | any  & any (union/intersection member — `string | any` collapses the whole
#                 union to any, which is the sneakiest of the lot)
# - = any        (generic default: `type T<X = any>`, and `<X extends Y = any>`)
ANY_RE=':[[:space:]]*any\b'
ANY_RE="$ANY_RE|as[[:space:]]+any\b"
ANY_RE="$ANY_RE|satisfies[[:space:]]+any\b"
ANY_RE="$ANY_RE|<[[:space:]]*any[[:space:]]*[>,]"
ANY_RE="$ANY_RE|,[[:space:]]*any[[:space:]]*[>,]"
ANY_RE="$ANY_RE|extends[[:space:]]+any\b"
ANY_RE="$ANY_RE|[|&][[:space:]]*any\b"
ANY_RE="$ANY_RE|=[[:space:]]*any[[:space:]]*[>,;]"

if echo "$CODE" | grep -qE "$ANY_RE"; then
    cwk_log_health_deny "Type 'any' detected"
    cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Type 'any' detected. Use 'unknown', generics, or proper types instead.\n\nAlternatives:\n• unknown - for truly unknown types\n• generic T - for type parameters\n• specific interface/type - for known structures\n• Record<string, unknown> - for object with unknown values"
  }
}
EOF
    exit 0
fi

exit 0
