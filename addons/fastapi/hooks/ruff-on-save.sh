#!/usr/bin/env bash
#
# Hook: ruff-on-save
# Event: PostToolUse (Write|Edit)
# Purpose: Format Python files with Ruff after modification, and surface lint
#          errors to the agent that just wrote them.
#
# Python twin of format-on-save.sh + eslint-batch.sh (which cover JS/TS only).
#
# Not batched at Stop the way eslint-batch.sh is: Ruff boots in milliseconds,
# so the per-write cost that made ESLint worth queuing does not exist here.
#

set -e
# Guarded: the addon ships this file into .claude/hooks/, next to hook-lib.sh.
# Run straight out of addons/fastapi/hooks/ the lib is not there, and an
# unguarded `source` under `set -e` would kill the hook instead of the timing.
__lib="$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
[[ -f "$__lib" ]] && source "$__lib"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ \.py$ ]]; then
    exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

if ! command -v ruff &> /dev/null; then
    exit 0
fi

# jq, not sed: ruff's output carries ANSI escapes and tabs, and one raw control
# character makes the whole JSON unparseable — the message is then dropped in
# silence, which is the one failure mode a feedback hook must not have.
# Same idiom as tdd-prove-red.sh.
json_escape() {
    jq -Rs . | sed -e 's/^"//' -e 's/"$//'
}

# A FROZEN test is never formatted. This hook is PostToolUse and writes the file,
# so no Pre hook sees the edit — and once ruff has normalised a quote or a blank
# line, the byte-identical re-save (the ONE documented way to ask for a fresh RED
# verdict when the red was observed inside a subagent) no longer matches what is
# on disk and falls to the freeze's blanket deny. The escape hatch of the freeze
# was being closed by the formatter, silently.
#
# Linting it is still useful and changes nothing on disk, so only the write is
# skipped. Twin of the same carve-out in `.claude/hooks/format-on-save.sh`.
#
# The set mirrors `is_frozen_test()` in tdd_py_lib.py — `tests/` mirroring
# `app/`, and TEST_FIRST_DIRS = ("services/",) plus its flat spelling. Change
# them together; a `tests/api/test_*.py` is test-after and stays formatted.
FROZEN_TEST_PY_RE='(^|/)tests/(services/([A-Za-z0-9_-]+/)*test_[A-Za-z0-9_]+\.py|test_services\.py)$'

# Format first, then report what formatting could not fix.
if [[ ! "$FILE_PATH" =~ $FROZEN_TEST_PY_RE ]]; then
    ruff format "$FILE_PATH" &> /dev/null || true
fi

if ! LINT_OUTPUT=$(ruff check "$FILE_PATH" 2>&1); then
    # Non-blocking, but it has to actually reach the agent: a PostToolUse hook
    # that prints bare text writes to the transcript, not to the model. The kit's
    # convention for "say something without blocking" is a systemMessage — see
    # eslint-batch.sh, its front-end twin.
    TAIL=$(echo "$LINT_OUTPUT" | tail -20 | json_escape)
    cat << EOF
{
  "systemMessage": "Ruff reported issues in $FILE_PATH:\\n\\n$TAIL"
}
EOF
fi

exit 0
