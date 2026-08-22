#!/usr/bin/env bash
#
# Hook: format-on-save
# Event: PostToolUse (Write|Edit)
# Purpose: Auto-format files with Prettier after modification
# CONFIGURE: swap `prettier` for this repo's formatter (see cwk_bin in hook-lib.sh).
#
# Stays synchronous, unlike eslint-check.sh: the formatter REWRITES the file,
# so anything reading it afterwards — the next hook, the next Edit, the model
# re-reading its own work — must see the formatted bytes. Batching it at Stop
# would hand the model stale content for the whole turn.
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

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
if PRETTIER=$(cwk_bin prettier); then
    $PRETTIER --write "$FILE_PATH" 2>/dev/null || true
fi

exit 0
