#!/usr/bin/env bash
# cwk-guard-api: 1
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

# The message is built by jq below, not by hand: ruff's output carries ANSI escapes and
# tabs, and one raw control character makes the whole JSON unparseable — the message is
# then dropped in silence, which is the one failure mode a feedback hook must not have.

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
# The set is `tdd_py_lib.is_frozen_test`, line for line, over `.claude/project.json`
# (`fastapi.module_root`, `tests_root`, `test_first_dirs`): a `test_*.py` whose mirrored
# implementation is a test-first module, found by path SEGMENT so a monorepo or worktree
# prefix does not matter. `tests/api/test_*.py` and `tests/test_main.py` are test-after
# and stay formatted. Only the formatting needs the config: `ruff check` always runs.

# split_root <rel path> <root>: sets SPLIT_PREFIX and SPLIT_INNER around the LAST `<root>/`
# segment, returns 1 when there is none (tdd_py_lib._split_root).
split_root() {
    local re="^(.*)/${2//./\\.}/(.*)\$"
    if [[ "/$1" =~ $re ]]; then
        SPLIT_PREFIX="${BASH_REMATCH[1]#/}"
        SPLIT_INNER="${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# is_frozen_test <path> <project dir> <module root> <tests root> <test-first dir>...
# (tdd_py_lib.is_frozen_test: rel_path, impl_for_test, is_test_first_impl).
is_frozen_test() {
    local path="$1" project="${2%/}" module_root="$3" tests_root="$4" rel base impl dir head=""
    shift 4
    if [[ "$path" == "$project"/* ]]; then
        rel="${path#"$project"/}"
    else
        rel="${path#/}"
    fi
    base="${rel##*/}"
    [[ "$base" == test_* && "$rel" == *.py ]] || return 1
    split_root "$rel" "$tests_root" || return 1
    [[ "$SPLIT_INNER" != */* ]] || head="${SPLIT_INNER%/*}/"
    impl="${SPLIT_PREFIX:+$SPLIT_PREFIX/}$module_root/$head${base#test_}"
    [[ "${impl##*/}" != __init__.py ]] || return 1
    split_root "$impl" "$module_root" || return 1
    for dir in "$@"; do
        dir="${dir%/}"
        [[ "$SPLIT_INNER" == "$dir"/* || "$SPLIT_INNER" == "$dir.py" ]] && return 0
    done
    return 1
}

MESSAGE=""
FORMAT=true
if ! declare -F cwk_config >/dev/null 2>&1; then
    MESSAGE="ruff-on-save: hook-lib.sh is older than this hook (no cwk_config), so $FILE_PATH was not formatted. The user re-copies the kit hooks files from a terminal."
    FORMAT=false
else
    cwk_config || true
    if [[ "${CWK_CFG_DEGRADED:-0}" == 1 ]]; then
        MESSAGE="ruff-on-save: $FILE_PATH was not formatted: $CWK_CFG_REASON"
        FORMAT=false
    fi
fi

# Format first, then report what formatting could not fix.
if $FORMAT; then
    mapfile -t TEST_FIRST_DIRS < <(jq -r '.fastapi.test_first_dirs[]?' "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/project.json" 2>/dev/null)
    if ! is_frozen_test "$FILE_PATH" "${CLAUDE_PROJECT_DIR:-$PWD}" "$CWK_CFG_MODULE_ROOT" "$CWK_CFG_TESTS_ROOT" \
        ${TEST_FIRST_DIRS[@]+"${TEST_FIRST_DIRS[@]}"}; then
        ruff format "$FILE_PATH" &> /dev/null || true
    fi
fi

if ! LINT_OUTPUT=$(ruff check "$FILE_PATH" 2>&1); then
    # Non-blocking, but it has to actually reach the agent: a PostToolUse hook
    # that prints bare text writes to the transcript, not to the model. The kit's
    # convention for "say something without blocking" is a systemMessage — see
    # eslint-batch.sh, its front-end twin.
    BREAK=$'\n\n'
    MESSAGE="${MESSAGE:+$MESSAGE$BREAK}Ruff reported issues in $FILE_PATH:$BREAK$(echo "$LINT_OUTPUT" | tail -20)"
fi

if [[ -n "$MESSAGE" ]]; then
    jq -n --arg m "$MESSAGE" '{systemMessage: $m}'
fi

exit 0
