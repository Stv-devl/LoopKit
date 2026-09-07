#!/usr/bin/env bash
#
# Hook: no-forbidden-icons
# Event: PreToolUse (Write|Edit)
# Purpose: Block forbidden icons/emojis (stars, rockets, lightning).
#          See .claude/rules/09-icons.md
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

# Read JSON from stdin
INPUT=$(cat)

# Extract file path and content
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty')

# Skip if nothing to inspect
if [[ -z "$FILE_PATH" ]] || [[ -z "$CONTENT" ]]; then
    exit 0
fi

# jq, never a heredoc. The two other hooks that still emit their JSON by hand
# (`no-any-type.sh`, `auto-approve-config.sh`) use `<< 'EOF'` — QUOTED, so their
# constant reason cannot interpolate anything and is safe by construction. This
# one was the odd `<< EOF`, unquoted, expanding `$reason` straight into a JSON
# string: the day a reason carries a `"`, the envelope stops parsing, and the
# harness DROPS unparseable output. A dropped deny is not a loud failure, it is
# a forbidden icon written with no message at all.
deny() {
    local reason
    reason="${1//\\n/$'\n'}"
    cwk_log_health_deny "$reason"
    jq -n --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

# 1) Emoji check — applies to every file type.
#    Fixed UTF-8 byte strings rather than `grep -P`: PCRE is a GNU extension and
#    BSD/macOS grep simply fails the test, which silently retires the ban.
#    The code points, written as bytes so this file itself stays clean:
#      U+2B50 star · U+2728 sparkles · U+1F31F glowing star · U+1F4AB dizzy
#      U+1F320 shooting star · U+1F680 rocket · U+26A1 high voltage
#      U+1F329 cloud with lightning
if echo "$CONTENT" | LC_ALL=C grep -qF \
    -e $'\xe2\xad\x90' -e $'\xe2\x9c\xa8' -e $'\xf0\x9f\x8c\x9f' -e $'\xf0\x9f\x92\xab' \
    -e $'\xf0\x9f\x8c\xa0' -e $'\xf0\x9f\x9a\x80' -e $'\xe2\x9a\xa1' -e $'\xf0\x9f\x8c\xa9'; then
    deny "Forbidden icon/emoji detected (star, rocket or lightning). See .claude/rules/09-icons.md.\n\nUse words for emphasis, not decorative emoji."
fi

# 2) Icon-component check — only in JS/TS source files
if [[ "$FILE_PATH" =~ \.(ts|tsx|js|jsx)$ ]]; then
    # JSX usage: <Star ... />, <Zap>, </Rocket>
    if echo "$CONTENT" | grep -qE '</?(Star|Stars|Sparkle|Sparkles|Rocket|RocketLaunch|Zap|Bolt|LightningBolt)\b'; then
        deny "Forbidden icon component used in JSX (star/rocket/lightning). See .claude/rules/09-icons.md.\n\nPick a neutral, descriptive icon from the lib already in use."
    fi
    # Named import of a forbidden icon (line mentioning lucide / heroicons)
    if echo "$CONTENT" | grep -E '(lucide-react|heroicons)' | grep -qE '\b(Star|Stars|Sparkle|Sparkles|Rocket|RocketLaunch|Zap|Bolt|LightningBolt)\b'; then
        deny "Forbidden icon imported (star/rocket/lightning). See .claude/rules/09-icons.md.\n\nPick a neutral, descriptive icon from the lib already in use."
    fi
fi

exit 0
