#!/usr/bin/env bash
#
# Hook: eslint-check
# Event: PostToolUse (Write|Edit)
# Purpose: enqueue the written file for the end-of-turn lint pass.
# CONFIGURE: nothing here. The linter itself lives in eslint-batch.sh.
#
# Why this file no longer runs ESLint.
#   It used to, on every single Write. ESLint with type-aware rules builds a
#   TypeScript program before it lints one line: 3-8s, per file, per write. An
#   EXECUTE phase writes twenty-odd files, so that is minutes of wall-clock —
#   spent on a hook that is NON-BLOCKING by design and stops nothing (the real
#   gate is `pnpm lint --max-warnings=0` in /ship, see 00-project.md).
#   Same signal, one process instead of twenty: enqueue here, lint at Stop.
#
# What it costs: the count now lands at the END of the turn instead of right
# after each write. On a long EXECUTE that is later feedback. It is the honest
# price of the trade, and it is cheap precisely because nothing gated on it.
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then exit 0; fi
if [[ ! "$FILE_PATH" =~ \.(ts|tsx|js|jsx)$ ]]; then exit 0; fi
if [[ ! -f "$FILE_PATH" ]]; then exit 0; fi
# A tree with its own toolchain lints itself (`deno lint`); ESLint cannot even
# resolve its `npm:`/`jsr:` specifiers. See cwk_foreign_toolchain in hook-lib.sh.
if cwk_foreign_toolchain "$FILE_PATH"; then exit 0; fi

# O_APPEND on a line this short is atomic, so concurrent subagents can share the
# queue without a lock.
printf '%s\n' "$FILE_PATH" \
    >> "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.eslint-queue" 2>/dev/null || true

exit 0
