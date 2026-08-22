#!/usr/bin/env bash
#
# Hook: eslint-batch
# Event: Stop, SubagentStop
# Purpose: lint everything written during the turn, in ONE ESLint process.
# CONFIGURE: swap `eslint` for this repo's linter (see cwk_bin in hook-lib.sh).
#
# The twin of eslint-check.sh: that one enqueues, this one lints. Non-blocking,
# exactly as before — it emits a count and exits 0. It never returns
# {"decision": "block"}, and that is deliberate: the blocking lint is
# `pnpm lint --max-warnings=0` in /ship (00-project.md), and a lint hook that
# can hold the turn open is a lint hook that argues with the /plan gate.
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"

# stdin is deliberately NOT read. This hook needs nothing from the payload,
# and a blocking read on a stdin the caller never closes hangs the whole turn
# for the length of the hook timeout.

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
QUEUE="$ROOT/.claude/.eslint-queue"

# Keep the timing log from growing without bound. Once per turn is the right
# frequency for this; doing it in the per-write hook would be a stat per Write.
TIMING_LOG="$ROOT/.claude/.hook-timings.log"
if [[ -f "$TIMING_LOG" ]] && [[ $(wc -c < "$TIMING_LOG") -gt 2000000 ]]; then
    tail -n 5000 "$TIMING_LOG" > "$TIMING_LOG.trim" && mv "$TIMING_LOG.trim" "$TIMING_LOG"
fi

if [[ ! -s "$QUEUE" ]]; then exit 0; fi

# Claim the queue atomically: several subagents can stop at the same instant,
# and each must lint its own slice rather than all of them racing on one file.
CLAIM="$QUEUE.$$"
mv "$QUEUE" "$CLAIM" 2>/dev/null || exit 0

mapfile -t FILES < <(sort -u "$CLAIM" | while IFS= read -r f; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
done)
rm -f "$CLAIM"

if [[ ${#FILES[@]} -eq 0 ]]; then exit 0; fi

ESLINT=$(cwk_bin eslint) || exit 0

# --cache pays off here and only here: a batch re-lints files that other batches
# already saw this session. Same reason the cache dir is under node_modules —
# it is disposable and already ignored by git.
CACHE_DIR="$ROOT/node_modules/.cache/eslint"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

ESLINT_OUTPUT=$($ESLINT "${FILES[@]}" --format compact \
    --cache --cache-location "$CACHE_DIR/.eslintcache" 2>/dev/null || true)

if [[ -z "$ESLINT_OUTPUT" ]]; then exit 0; fi

ERROR_COUNT=$(grep -c ", Error - " <<< "$ESLINT_OUTPUT" || true)
WARNING_COUNT=$(grep -c ", Warning - " <<< "$ESLINT_OUTPUT" || true)

if [[ "${ERROR_COUNT:-0}" -eq 0 ]] && [[ "${WARNING_COUNT:-0}" -eq 0 ]]; then exit 0; fi

jq -n --arg msg "ESLint: ${ERROR_COUNT} error(s), ${WARNING_COUNT} warning(s) across ${#FILES[@]} file(s) written this turn. Not a gate — /ship runs the blocking one." \
    '{systemMessage: $msg}'

exit 0
