#!/usr/bin/env bash
#
# Hook: tdd-require-red
# Event: PreToolUse (Write|Edit)
# Purpose: An implementation module of the three test-first layers cannot be
#          CREATED until its test file has been observed failing. This is the
#          blocking half of the cycle; `tdd-prove-red.sh` is the half that
#          observes and leaves the marker.
#          Scope + rationale: .claude/rules/05-testing.md ("Test-first").
#
# Why creation only. Blocking every later edit would deadlock the GREEN and
# REFACTOR legs — the whole point of those is to change the implementation while
# the test does not move. The moment that decides whether a feature is TDD or
# test-after is the first write of the module; after that, `tdd-freeze-tests.sh`
# holds the line from the other side.
#
# Known limit, stated rather than hidden: adding a function to a module that
# already exists is NOT blocked here. That case is covered by the symbol-level
# verdict of `tdd-prove-red.sh` and by the `tests` dimension of /review.
#
# Escape hatch: list the path in `.claude/.tdd-unfrozen` with a one-line reason
# (same visible list as the freeze — extracting an existing function into a new
# `utils.ts` is the legitimate case). Visible, never silent.
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# The test file itself is somebody else's business.
[[ "$FILE_PATH" == *.test.ts || "$FILE_PATH" == *.test.tsx ]] && exit 0

# A tree with its own toolchain runs its own tests (`deno test`), which
# `pnpm test:run` cannot execute — no red could ever be proved there, and the
# module would be unwritable. See cwk_foreign_toolchain in hook-lib.sh.
cwk_foreign_toolchain "$FILE_PATH" && exit 0

# Only the three test-first layers.
if [[ ! "$FILE_PATH" =~ $CWK_TDD_IMPL_RE ]]; then
    exit 0
fi

# Already exists → GREEN or REFACTOR, both legitimate. Let it through.
[[ -f "$FILE_PATH" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
RED_DIR="$PROJECT_DIR/.claude/.tdd-red"

# Same two functions as tdd-prove-red.sh — change one, change both.
# The path is normalised first (cwk_abs_path): the two hooks must derive the
# same marker name for the same file, and they do not always receive the same
# spelling of its path.
marker_path() {
    printf '%s/%s' "$RED_DIR" "$(cwk_abs_path "$1" | tr -c 'A-Za-z0-9._-' '_')"
}

file_digest() {
    if command -v sha256sum &> /dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf 'unavailable'
    fi
}

# Explicitly exempted?
UNFROZEN_LIST="$PROJECT_DIR/.claude/.tdd-unfrozen"
if [[ -f "$UNFROZEN_LIST" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        # First field = the path, rest = the reason. Same parser as
        # tdd-freeze-tests.sh and tdd_py_lib.py — change all three together.
        # Both spellings are accepted because both are prescribed; see the
        # comment in tdd-freeze-tests.sh.
        line="${line%%[[:space:]]*}"
        # Path match only — never a bare basename, or one entry would exempt
        # every `utils.ts` in the repo at once.
        if [[ "$line" == */* ]] && [[ "$FILE_PATH" == *"$line"* ]]; then
            exit 0
        fi
    done < "$UNFROZEN_LIST"
fi

BASE="${FILE_PATH%.ts}"
[[ "$BASE" == "$FILE_PATH" ]] && BASE="${FILE_PATH%.tsx}"

TEST_PATH=""
for ext in ts tsx; do
    [[ -f "$BASE.test.$ext" ]] && TEST_PATH="$BASE.test.$ext" && break
done

# jq, never a heredoc: these reasons interpolate $FILE_PATH, and a path holding a
# `"` produced unparseable JSON — which the harness DROPS, so the deny vanished
# with no message at all. Only the authored `\n` is expanded; every other backslash is left alone.
deny() {
    local reason
    reason="${1//\\n/$'\n'}"
    jq -n --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

if [[ -z "$TEST_PATH" ]]; then
    deny "Test-first: '$FILE_PATH' is one of the three test-first layers (.claude/rules/05-testing.md) and '$BASE.test.ts' does not exist.\n\nWrite the test first, from the Test plan the user validated at the /loop:plan gate. Run it, see it fail — the tdd-prove-red hook records that failure — then come back and write this file.\n\nIf this write is a pure move of code that already exists elsewhere, that is the exception: add one line to .claude/.tdd-unfrozen, exactly in this shape:\n\n    $FILE_PATH  # <one-line reason>\n\n(the path first, the reason after it or behind a '#' — both are read), then write it."
fi

MARKER="$(marker_path "$TEST_PATH")"

if [[ ! -f "$MARKER" ]]; then
    deny "Test-first: '$TEST_PATH' exists but has never been observed FAILING, so the RED phase is not proved and '$FILE_PATH' cannot be created yet (.claude/rules/05-testing.md).\n\nRewrite or re-save the test file: the tdd-prove-red hook runs it and records the failure. A test that passes before its implementation exists asserts nothing — that is what this gate is looking for.\n\nIf that hook answered that it could not run the test runner, fix RUN_TESTS in .claude/hooks/tdd-prove-red.sh first — no re-save will ever produce a marker until it points at this repo's run-once script.\n\nGenuine exception (pure code move, adoption on a legacy module): add one line to .claude/.tdd-unfrozen, exactly in this shape:\n\n    $FILE_PATH  # <one-line reason>"
fi

# A marker proves a red on the file that was running THEN. If the test file has
# changed since, the red belongs to a different test — most often a file deleted
# and rewritten at the same path.
MARKED_DIGEST=$(grep -m1 '^sha256:' "$MARKER" 2>/dev/null | cut -d: -f2)
CURRENT_DIGEST=$(file_digest "$TEST_PATH")
if [[ -n "$MARKED_DIGEST" && "$MARKED_DIGEST" != "unavailable" && "$CURRENT_DIGEST" != "unavailable" \
      && "$MARKED_DIGEST" != "$CURRENT_DIGEST" ]]; then
    deny "Test-first: the RED marker for '$TEST_PATH' was recorded on a different version of that file, so it proves nothing about the test as it stands now (.claude/rules/05-testing.md).\n\nRe-save the test file: tdd-prove-red runs it again and records a fresh verdict. Read that verdict before creating '$FILE_PATH' — anything other than 'RED confirmed' means the red was not real."
fi

exit 0
