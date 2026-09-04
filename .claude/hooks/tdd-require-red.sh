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
# Two cases, two different questions:
#
#   FILE DOES NOT EXIST YET — the whole module needs a proved red. Unchanged
#   from the original version of this hook.
#
#   FILE ALREADY EXISTS — most edits are GREEN or REFACTOR and must go
#   through untouched, or every bugfix and every internal helper would
#   deadlock on a rule meant for new behaviour. But an edit that makes the
#   file EXPORT a symbol it did not export before is indistinguishable from
#   a brand-new module glued onto an old file — and nothing here used to
#   look at that. tdd-prove-red.sh already computes, on every red, exactly
#   which symbols the test names that the implementation does not yet
#   export (`MISSING`) — this hook now reads that same list from the marker
#   and requires every newly-exported symbol in the edit to appear in it.
#   An edit that exports nothing new is unconditionally GREEN/REFACTOR and
#   skips this check entirely — it was never the case this closes.
#
# Known limit, stated rather than hidden: a pure rename (old export removed,
# new one added in the same edit) reads as a brand-new symbol and is denied
# without a fresh red — the hook cannot tell a rename from new behaviour
# wearing an old name. That is a plan-level correction: `.claude/.tdd-unfrozen`.
# A behaviour change that adds no new export (editing an existing function's
# body) is also out of scope here — the frozen test that already exercises it
# is what catches a regression, not this hook.
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

# Mirrors the SYMBOLS extraction in tdd-prove-red.sh, on arbitrary text rather
# than a file on disk — change one, change both. Two forms:
#   export const/function/class/type/interface/enum NAME
#   export { a, b as c }
extract_exported_symbols() {
    local flat
    flat=$(printf '%s' "$1" | tr '\n' ' ')
    {
        printf '%s' "$flat" \
            | grep -oE 'export[[:space:]]+(async[[:space:]]+)?(function|const|let|var|class|type|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
            | sed -E 's/^export[[:space:]]+(async[[:space:]]+)?(function|const|let|var|class|type|interface|enum)[[:space:]]+//' \
            || true
        printf '%s' "$flat" \
            | grep -oE 'export[[:space:]]*\{[^}]*\}' \
            | sed 's/.*{\([^}]*\)}.*/\1/' | tr ',' '\n' \
            | sed -E 's/^[[:space:]]*type[[:space:]]+//; s/[[:space:]]+as[[:space:]]+.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
            | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' \
            || true
    } | sed '/^[[:space:]]*$/d' | sort -u
}

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

is_unfrozen() {
    local target="$1" list="$PROJECT_DIR/.claude/.tdd-unfrozen" line
    [[ -f "$list" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        # First field = the path, rest = the reason. Same parser as
        # tdd-freeze-tests.sh and tdd_py_lib.py — change all three together.
        line="${line%%[[:space:]]*}"
        # Path match only — never a bare basename, or one entry would exempt
        # every `utils.ts` in the repo at once.
        [[ "$line" == */* ]] && [[ "$target" == *"$line"* ]] && return 0
    done < "$list"
    return 1
}

BASE="${FILE_PATH%.ts}"
[[ "$BASE" == "$FILE_PATH" ]] && BASE="${FILE_PATH%.tsx}"

TEST_PATH=""
for ext in ts tsx; do
    [[ -f "$BASE.test.$ext" ]] && TEST_PATH="$BASE.test.$ext" && break
done

# ------------------------------------------------------------ already exists
if [[ -f "$FILE_PATH" ]]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    CANDIDATE_TEXT="$NEW_STRING"
    [[ -n "$CONTENT" ]] && CANDIDATE_TEXT="$CONTENT"

    # No content to scan (e.g. old_string/new_string both empty) → nothing to
    # add, nothing to check.
    [[ -z "$CANDIDATE_TEXT" ]] && exit 0

    OLD_EXPORTED=$(extract_exported_symbols "$(cat "$FILE_PATH")")
    NEW_EXPORTED=$(extract_exported_symbols "$CANDIDATE_TEXT")

    ADDED=""
    while IFS= read -r sym; do
        [[ -z "$sym" ]] && continue
        printf '%s\n' "$OLD_EXPORTED" | grep -qx -- "$sym" || ADDED+="$sym"$'\n'
    done <<< "$NEW_EXPORTED"
    ADDED=$(printf '%s' "$ADDED" | sed '/^[[:space:]]*$/d')

    # Nothing newly exported: GREEN or REFACTOR on behaviour a frozen test
    # already covers. Let it through — this is the case the original version
    # of this hook let through unconditionally, and still does.
    [[ -z "$ADDED" ]] && exit 0

    is_unfrozen "$FILE_PATH" && exit 0

    ADDED_LIST=$(printf '%s' "$ADDED" | tr '\n' ' ')

    if [[ -z "$TEST_PATH" ]]; then
        deny "Test-first: this edit to '$FILE_PATH' exports $ADDED_LIST, which the file did not export before, and '$BASE.test.ts' does not exist (.claude/rules/05-testing.md).\n\nA newly-exported symbol on an existing module is a new module in every way that matters here. Write the test first, from the Test plan the user validated at the /loop:plan gate. Run it, see it fail — the tdd-prove-red hook records that failure — then come back and write this.\n\nIf this is a pure rename (the old export is gone from the same edit), that is a plan-level correction, not new behaviour: add one line to .claude/.tdd-unfrozen, exactly in this shape:\n\n    $FILE_PATH  # <one-line reason>"
    fi

    MARKER="$(marker_path "$TEST_PATH")"

    if [[ ! -f "$MARKER" ]]; then
        deny "Test-first: this edit to '$FILE_PATH' exports $ADDED_LIST, which the file did not export before, but '$TEST_PATH' has never been observed FAILING on it (.claude/rules/05-testing.md).\n\nWrite or extend the test for $ADDED_LIST first, from the /loop:plan test plan, then save it — the tdd-prove-red hook runs it and records the failure. Only then come back and write this.\n\nGenuine exception (pure rename, adoption on a legacy module): add one line to .claude/.tdd-unfrozen, exactly in this shape:\n\n    $FILE_PATH  # <one-line reason>"
    fi

    MARKED_DIGEST=$(grep -m1 '^sha256:' "$MARKER" 2>/dev/null | cut -d: -f2)
    CURRENT_DIGEST=$(file_digest "$TEST_PATH")
    if [[ -n "$MARKED_DIGEST" && "$MARKED_DIGEST" != "unavailable" && "$CURRENT_DIGEST" != "unavailable" \
          && "$MARKED_DIGEST" != "$CURRENT_DIGEST" ]]; then
        deny "Test-first: the RED marker for '$TEST_PATH' was recorded on a different version of that file, so it proves nothing about $ADDED_LIST as things stand now (.claude/rules/05-testing.md).\n\nRe-save the test file: tdd-prove-red runs it again and records a fresh verdict. Read that verdict before writing '$FILE_PATH' — anything other than 'RED confirmed' means the red was not real."
    fi

    # What was actually proved missing at that red. Absent on a marker written
    # before this check existed — treated as nothing proved, so an upgrade
    # fails closed rather than trusting a marker that never recorded symbols.
    MISSING_AT_RED=$(grep -m1 '^missing:' "$MARKER" 2>/dev/null | cut -d: -f2-)

    UNPROVEN=""
    while IFS= read -r sym; do
        [[ -z "$sym" ]] && continue
        printf '%s\n' "$MISSING_AT_RED" | tr ' ' '\n' | grep -qx -- "$sym" || UNPROVEN+="$sym "
    done <<< "$ADDED"

    if [[ -n "$UNPROVEN" ]]; then
        deny "Test-first: this edit to '$FILE_PATH' exports ${UNPROVEN% } — the most recent proved RED for '$TEST_PATH' did not name ${UNPROVEN% } as missing, so it proves nothing about it (.claude/rules/05-testing.md).\n\nSave '$TEST_PATH' with a case that exercises ${UNPROVEN% } and let tdd-prove-red observe it fail, then come back and write this.\n\nGenuine exception (pure rename, adoption on a legacy module): add one line to .claude/.tdd-unfrozen, exactly in this shape:\n\n    $FILE_PATH  # <one-line reason>"
    fi

    exit 0
fi

# --------------------------------------------------------------- brand new
is_unfrozen "$FILE_PATH" && exit 0

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
