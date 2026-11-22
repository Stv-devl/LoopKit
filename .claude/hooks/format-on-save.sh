#!/usr/bin/env bash
#
# Hook: format-on-save
# Event: PostToolUse (Write|Edit)
# Purpose: Auto-format files with Prettier after modification
# Configure: `formatter` in .claude/project.json (see cwk_bin in hook-lib.sh).
#
# Stays synchronous, unlike eslint-check.sh: the formatter REWRITES the file,
# so anything reading it afterwards — the next hook, the next Edit, the model
# re-reading its own work — must see the formatted bytes. Batching it at Stop
# would hand the model stale content for the whole turn.
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
if ! declare -F cwk_config cwk_bin >/dev/null 2>&1; then
    printf '%s\n' '{"systemMessage":"format-on-save: hook-lib.sh is older than this hook (no cwk_config/cwk_bin), so nothing was formatted. The user re-copies the kit hooks files from a terminal."}'
    exit 0
fi

# Read JSON from stdin
INPUT=$(cat)

# Extract file path. The tool_response is deliberately not read: the file's
# existence is checked below, which is the only thing this hook needs to know.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only format certain file types
if [[ ! "$FILE_PATH" =~ \.(ts|tsx|js|jsx|json|css|md)$ ]]; then
    exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# A tree with its own toolchain formats itself (`deno fmt`). Prettier here
# rewrites the file and turns that tree's own `fmt --check` gate red — measured,
# 6 files of 7. See cwk_foreign_toolchain in hook-lib.sh.
if cwk_foreign_toolchain "$FILE_PATH"; then
    exit 0
fi

# Run Prettier via the local bin shim. `pnpm exec` boots Node and resolves the
# workspace before Prettier starts — 200-500ms paid on every single write, for
# nothing. cwk_bin skips that preamble, and returns 1 when the repo has no
# formatter installed (not an error: a repo may simply not use one).
#
# The formatter is `.claude/project.json` `formatter`, an argv prefix: its first word
# is resolved by cwk_bin, the rest is passed as is, the file comes last. `[]` formats
# nothing. An unreadable config formats nothing and says why.
cwk_config || true
if [[ "${CWK_CFG_DEGRADED:-0}" == 1 ]]; then
    jq -n --arg m "format-on-save: $FILE_PATH was not formatted: $CWK_CFG_REASON" '{systemMessage: $m}'
    exit 0
fi
FORMATTER=(${CWK_CFG_FORMATTER[@]+"${CWK_CFG_FORMATTER[@]}"})
if [[ "${#FORMATTER[@]}" -gt 0 ]] && cwk_bin "${FORMATTER[0]}"; then
    "${CWK_BIN[@]}" "${FORMATTER[@]:1}" "$FILE_PATH" 2>/dev/null || true
fi

exit 0
