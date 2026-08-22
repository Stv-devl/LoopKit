#!/usr/bin/env bash
#
# Hook: tdd-freeze-tests
# Event: PreToolUse (Write|Edit)
# Purpose: Once written and validated at the /plan gate, a test file of the three
#          test-first layers is immutable for the rest of the feature. The
#          implementation bends to the test, never the reverse.
#          Scope + rationale: .claude/rules/05-testing.md ("Test-first").
#
# Creating the file is always allowed (that IS the RED phase). Only editing an
# existing one is blocked.
#
# One edit is NOT blocked: appending a new case. Canon TDD keeps the test list
# alive — you add to it as you learn — and a freeze that forbids growth pushes
# the agent to either drop the case silently or work around the freeze. So a pure
# insertion that touches no existing assertion goes through, and is announced.
# Everything else — rewriting an assertion, renaming an `it()`, deleting a case,
# overwriting the file wholesale — is denied.
#
# "Touches no existing assertion" is not enough on its own, and that is the whole
# subtlety of this hook. Anchoring on the `it(...) => {` line of an existing case
# and inserting `return;` leaves every assertion byte-for-byte intact and kills
# the case anyway — and the lint does not see it either, since `expect-expect` is
# lexical and the now-unreachable `expect()` is still there. So an insertion must
# also: land outside every case body (computed, not inferred from the anchor's
# first line), carry its own assertion, introduce no control flow that can skip
# what already runs, and shadow nothing the file imports from the module under
# test — a `const total = () => 5` at describe scope is a mock without the word.
#
# Escape hatch: list the path in .claude/.tdd-unfrozen, one per line, as
# `<path>  # <reason>`. The reason may also follow the path with no `#` — both
# spellings are read, because both are prescribed by the deny texts below.
# Making the exception visible is the point — it is a plan-level correction, not
# a silent edit. The same list exempts an implementation file from
# tdd-require-red.sh.
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

# Read JSON from stdin
INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# A tree with its own toolchain never entered the cycle (tdd-require-red and
# tdd-prove-red both skip it), so there is nothing to freeze — and freezing it
# would lock a file no red ever validated. See hook-lib.sh.
if cwk_foreign_toolchain "$FILE_PATH"; then
    exit 0
fi

# Only the three test-first layers. hooks.test.tsx, *.gateway.test.ts and
# component tests are written AFTER the code — they are not frozen.
if [[ ! "$FILE_PATH" =~ $CWK_TDD_TEST_RE ]]; then
    exit 0
fi

# The file does not exist yet: this is the RED phase, let it through.
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Explicitly unfrozen?
UNFROZEN_LIST="${CLAUDE_PROJECT_DIR:-.}/.claude/.tdd-unfrozen"
if [[ -f "$UNFROZEN_LIST" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"          # strip comment
        line="${line#"${line%%[![:space:]]*}"}"   # trim leading space
        line="${line%"${line##*[![:space:]]}"}"   # trim trailing space
        [[ -z "$line" ]] && continue
        # The FIRST field is the path; anything after it is the reason. Both
        # spellings are accepted because both are prescribed: this hook's own
        # deny text says "add '<path>' + a one-line reason", with no `#`, and
        # before this line that exact spelling was parsed as a path containing a
        # space and matched nothing — silently. A guardrail whose escape hatch
        # only works in a spelling it never mentions is an escape hatch nobody
        # can use.
        line="${line%%[[:space:]]*}"
        # Path match only — never a bare basename. Every feature owns a
        # `services.test.ts`; matching on the basename would unfreeze all of
        # them at once.
        if [[ "$line" == */* ]] && [[ "$FILE_PATH" == *"$line"* ]]; then
            exit 0
        fi
    done < "$UNFROZEN_LIST"
fi

# An identical re-save changes nothing and is the only way to ask tdd-prove-red
# for a fresh verdict — needed when the RED was observed in a subagent whose
# context the hook did not run in. Refusing it would deadlock the cycle on a
# no-op.
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
if [[ -n "$CONTENT" && "$CONTENT" == "$(cat "$FILE_PATH")" ]]; then
    jq -n --arg m "TDD: identical re-save of the frozen test '$FILE_PATH' — allowed, nothing changed. tdd-prove-red is re-running it; read its verdict before writing any implementation." '{systemMessage: $m}'
    exit 0
fi

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

# The module under test, needed by three of the conditions below.
MODULE_BASE="${FILE_PATH%.test.ts}"
[[ "$MODULE_BASE" == "$FILE_PATH" ]] && MODULE_BASE="${FILE_PATH%.test.tsx}"
MODULE_BASE=$(basename "$MODULE_BASE")
MODULE_RE=$(printf '%s' "$MODULE_BASE" | sed 's/\./\\./g')

# Where does the anchor SIT? Conditions 1 and 3 below read the anchor and the
# added text as strings, and that is not enough: anchoring on the second line of
# a case body passes both ("the anchor is not an `it(` line", "the added block
# does not OPEN with return") while `if (1) return;` lands inside a case that
# already runs and kills every assertion under it. The lint cannot see it either
# — `expect-expect` is lexical and the now-unreachable `expect()` is still there.
#
# So the position is computed, not inferred: everything before the anchor is
# walked, tracking brace depth from the most recent `it(`/`test(`. Depth still
# open at the anchor = the insertion point is inside a case body.
anchor_scope() {
    printf '%s' "$1" | awk '
    function scan(s,   i, n, ch) {
        n = length(s)
        for (i = 1; i <= n; i++) {
            ch = substr(s, i, 1)
            if (ch == "{") { if (pending >= 0) pending++ }
            else if (ch == "}") { if (pending > 0) { pending--; if (pending == 0) pending = -1 } }
        }
    }
    BEGIN { pending = -1 }
    {
        line = $0; pos = 0; off = 0; s = line
        while (match(s, /(^|[^A-Za-z0-9_$])(it|test)[ \t]*(\.[A-Za-z]+)?[ \t]*\(/)) {
            off += RSTART + RLENGTH - 1
            s = substr(s, RSTART + RLENGTH)
            pos = off
        }
        if (pos > 0) { scan(substr(line, 1, pos)); pending = 0; scan(substr(line, pos + 1)) }
        else { scan(line) }
    }
    END { print (pending > 0) ? "inside" : "outside" }
    '
}

# What the added block does AT ITS OWN TOP LEVEL — i.e. in the `describe` scope,
# outside any function it introduces. Two things are reported:
#
#   CTRL        a `return`/`throw` at depth 0. Inside the new case body it is
#               ordinary code and depth is >= 1, so it is not reported; at
#               describe scope it returns from the describe callback and every
#               case below it is never registered. That is the same defect as an
#               inserted `return;`, and the old line-start-only regex missed
#               `if (1) return;` completely.
#   DECL <name> a top-level const/let/var/function/class binding. Compared
#               against what this file imports from the module under test: a
#               `const total = () => 5` in the describe scope shadows the import
#               for every case in the block — a pure insertion, anchored outside
#               every case, carrying its own expect(), that makes the whole
#               frozen file run against a stub. Condition 4 never saw it: there
#               is no `vi.mock` anywhere in it.
added_shape() {
    printf '%s' "$1" | awk '
    BEGIN { depth = 0; ctrl = 0 }
    {
        line = $0
        sub(/\/\/.*$/, "", line)
        n = length(line)
        for (i = 1; i <= n; i++) {
            ch = substr(line, i, 1)
            if (ch == "{" || ch == "(" || ch == "[") { depth++; continue }
            if (ch == "}" || ch == ")" || ch == "]") { depth--; continue }
            if (depth > 0) continue
            prev = (i > 1) ? substr(line, i - 1, 1) : " "
            if (prev ~ /[A-Za-z0-9_$.]/) continue
            rest = substr(line, i)
            if (match(rest, /^(return|throw)([^A-Za-z0-9_$]|$)/)) { ctrl = 1; continue }
            if (match(rest, /^(const|let|var|function|class)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
                d = substr(rest, RSTART, RLENGTH)
                sub(/^(const|let|var|function|class)[ \t]+/, "", d)
                print "DECL " d
            }
        }
    }
    END { if (ctrl) print "CTRL" }
    '
}

# The conditions of an insertion. The first three say nothing existing was
# rewritten or made unreachable; the last three say what is added is a real case
# rather than a way in.
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')

# WHERE the addition lands inside the anchor, and what exactly it is.
#
# `${NEW_STRING/"$OLD_STRING"/}` looks like the answer and is not: it removes the
# FIRST occurrence, and on the one anchor the deny text prescribes — the previous
# case's closing `});` — that occurrence is at the END of new_string, so the
# addition came back with the anchor's own closing brace glued in front of it and
# the insertion point read as "inside the case that just closed". The append the
# hook documents was denied.
#
# What is actually added is what sits between the longest common prefix and the
# longest common suffix of old_string and new_string. The prefix length is also
# the offset, inside the anchor, where the addition lands.
common_affix_len() {   # $1 a, $2 b, $3 = "prefix" | "suffix"
    local a="$1" b="$2" hi=${#1} i=0
    (( ${#b} < hi )) && hi=${#b}
    if [[ "$3" == "prefix" ]]; then
        while (( i < hi )) && [[ "${a:i:1}" == "${b:i:1}" ]]; do ((i++)); done
    else
        while (( i < hi )) && [[ "${a: -i-1:1}" == "${b: -i-1:1}" ]]; do ((i++)); done
    fi
    printf '%s' "$i"
}

if [[ -n "$OLD_STRING" && "$OLD_STRING" != *"expect("* && "$NEW_STRING" == *"$OLD_STRING"* ]]; then
    AFFIX_P=$(common_affix_len "$OLD_STRING" "$NEW_STRING" prefix)
    AFFIX_S=$(common_affix_len "$OLD_STRING" "$NEW_STRING" suffix)
    (( AFFIX_P + AFFIX_S > ${#OLD_STRING} )) && AFFIX_S=$(( ${#OLD_STRING} - AFFIX_P ))
    ADDED="${NEW_STRING:AFFIX_P:${#NEW_STRING} - AFFIX_S - AFFIX_P}"

    REFUSED=""

    # 1. The anchor must not open an existing case. Anchoring on `it(... => {`
    #    keeps every assertion intact and still lets a statement slip in at the
    #    top of the body. Appending a case never needs that anchor: a new case
    #    goes after the closing `});` of the previous one.
    if [[ "$OLD_STRING" =~ (^|[^A-Za-z0-9_])(it|test)[[:space:]]*(\.[A-Za-z]+)?[[:space:]]*\( ]]; then
        REFUSED="the anchor opens an existing it()/test() block, so the insertion lands INSIDE a case that already runs"
    fi

    # 1bis. The INSERTION POINT must not sit inside a case body, not merely the
    #    anchor's first line. Condition 1 reads the anchor as a string and passes
    #    on the second body line of the same case.
    #
    #    The point is computed from the resulting file, never from the anchor
    #    alone: what lands where is `<file up to the anchor> + <the part of
    #    new_string that precedes the addition>`. That is what makes the
    #    documented append work — anchoring on the previous case's closing `});`
    #    puts the addition AFTER it, i.e. outside — while `if (1) return;` glued
    #    under the second line of a body is refused.
    if [[ -z "$REFUSED" && -n "$ADDED" ]]; then
        CURRENT_CONTENT=$(cat "$FILE_PATH")
        if [[ "$CURRENT_CONTENT" == *"$OLD_STRING"* ]]; then
            INSERT_PREFIX="${CURRENT_CONTENT%%"$OLD_STRING"*}${NEW_STRING:0:AFFIX_P}"
            if [[ "$(anchor_scope "$INSERT_PREFIX")" == "inside" ]]; then
                REFUSED="the insertion point sits INSIDE the body of an existing it()/test() block, so what is added lands in a case that already runs"
            fi
        fi
    fi

    # 2. What is added must assert something. A case that asserts nothing is not
    #    a case — and it is what `expect-expect` would only report at /ship.
    if [[ -z "$REFUSED" && "$ADDED" != *"expect("* && "$ADDED" != *"expectTypeOf("* ]]; then
        REFUSED="the inserted block carries no expect() of its own"
    fi

    # 3 + 5. What the added block does at describe scope: control flow that skips
    #    the cases below it, and a binding that shadows the module under test.
    #    Both are read from the walked shape, never from a line-start regex —
    #    `if (1) return;` opens no line with `return`.
    ADDED_SHAPE=""
    if [[ -z "$REFUSED" ]]; then
        ADDED_SHAPE=$(added_shape "$ADDED")
    fi

    if [[ -z "$REFUSED" ]] && printf '%s\n' "$ADDED_SHAPE" | grep -qx 'CTRL'; then
        REFUSED="the inserted block carries a return/throw at describe scope, which skips every case declared below it"
    fi

    # 4. No mocking the module under test. This is the hole conditions 1-3 left
    #    wide open: `vi.mock('./x.utils', () => ({ a: () => 1 }))` is a pure
    #    insertion, anchors outside every case, carries its own expect() — and
    #    every assertion in the frozen file now runs against the mock instead of
    #    the implementation. The file passes whatever the code does, which is
    #    exactly the "adjust the test until it agrees" the freeze exists to stop,
    #    achieved without editing a single existing assertion.
    #
    #    BOTH call forms are matched. `vi.mock(import('./x.repository'))` is the
    #    type-safe spelling Vitest documents since 2.1, so it is what an agent
    #    reading current docs writes — and anchoring the specifier on a quote
    #    immediately after the `(` let it through while the string form was
    #    denied. A guardrail that only stops the older spelling is a guardrail
    #    that stops nobody.
    #
    #    Limit, stated rather than hidden: this catches the vi/jest mock calls.
    #    A `vi.spyOn` on a namespace import of the module under test is not
    #    matched, and neither is a specifier behind a variable — /review's
    #    `tests` dimension owns those.
    #
    #    utils/mapper are pure, so 05-testing.md forbids mocking them at all —
    #    any mock added there is refused. A repository/services test legitimately
    #    mocks the gateway below it, so only a mock naming the module under test
    #    is refused.
    if [[ -z "$REFUSED" ]] && printf '%s' "$ADDED" | grep -qE '\b(vi|jest)\.(do)?[Mm]ock[[:space:]]*\('; then
        if [[ "$FILE_PATH" =~ (utils|mapper)\.test\.tsx?$ ]]; then
            REFUSED="the inserted block mocks a module, and this is a pure layer (utils/mapper) where 05-testing.md forbids mocking outright — a mocked pure function tests the mock"
        elif printf '%s' "$ADDED" | grep -qE "\b(vi|jest)\.(do)?[Mm]ock[[:space:]]*\([[:space:]]*(import[[:space:]]*\([[:space:]]*)?['\"][^'\"]*${MODULE_RE}['\"]"; then
            REFUSED="the inserted block mocks '$MODULE_BASE', the module under test — every assertion in this frozen file would then run against the mock and pass whatever the implementation does"
        fi
    fi

    # 5. No SHADOWING the module under test. Condition 4 matches the vi/jest mock
    #    calls, and that is the hole it leaves: a plain
    #    `const total = () => 5` at describe scope shadows the import for every
    #    case in the block. No mock, no rewritten assertion, a pure insertion
    #    carrying its own expect() — and the whole frozen file now runs against
    #    the stub. Same outcome as condition 4, reached with ordinary JavaScript.
    #
    #    Only names this file actually imports FROM THE MODULE UNDER TEST are
    #    refused. A helper, a fixture or a local builder introduced by the new
    #    case shares none of them and goes through untouched.
    if [[ -z "$REFUSED" ]]; then
        IMPORTED_SYMS=$(tr '\n' ' ' < "$FILE_PATH" \
            | grep -oE "import[[:space:]]+[^;]*from[[:space:]]*['\"][^'\"]*${MODULE_RE}['\"]" \
            | sed -E "s/^import[[:space:]]+//; s/[[:space:]]+from[[:space:]]*['\"].*//" \
            | tr -d '{}' | tr ',' '\n' \
            | sed -E 's/^[[:space:]]*type[[:space:]]+//; s/.*[[:space:]]as[[:space:]]+//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
            | grep -E '^[A-Za-z_$][A-Za-z0-9_$]*$' | sort -u || true)

        if [[ -n "$IMPORTED_SYMS" ]]; then
            while IFS= read -r decl; do
                [[ "$decl" == DECL\ * ]] || continue
                name="${decl#DECL }"
                if printf '%s\n' "$IMPORTED_SYMS" | grep -qx -- "$name"; then
                    REFUSED="the inserted block declares '$name' at describe scope, and this file imports '$name' from '$MODULE_BASE' — the declaration shadows the module under test for every case in the block, so they would all run against the stub"
                    break
                fi
            done <<< "$ADDED_SHAPE"
        fi
    fi

    if [[ -z "$REFUSED" ]]; then
        jq -n --arg m "TDD: new case appended to the frozen test '$FILE_PATH' — allowed (the test list grows as you learn), nothing existing was touched. Say in your next message which behaviour it covers and why the /plan test plan missed it; /review compares this file against that plan." '{systemMessage: $m}'
        exit 0
    fi

    deny "Frozen test: this edit to '$FILE_PATH' looks like an insertion, but $REFUSED (.claude/rules/05-testing.md).\n\nAdding a case is allowed; opening a way into a case that already runs is not — an inserted 'return;' leaves every assertion intact and kills the case anyway, and the lint cannot see it.\n\nA real append: anchor on a line outside any case body (the closing '});' of the previous one), keep that anchor verbatim, and let the added block carry its own 'expect('. Add its fixtures in the same edit.\n\nIf you genuinely need to change what an existing case asserts, that is a plan-level correction: tell the user which case and why, add one line to .claude/.tdd-unfrozen in this shape:\n\n    $FILE_PATH  # <one-line reason>\n\nthen edit."
fi

deny "Frozen test: '$FILE_PATH' is a test-first file (.claude/rules/05-testing.md).\n\nIt was validated at the /plan gate and the implementation is written against it. Adjusting a test so it agrees with the code is exactly what the freeze prevents. The fix is almost always in the implementation, not here.\n\nTwo different situations, and this edit is neither:\n\n  ADDING a case — allowed without any ceremony, but only as a pure insertion: anchor the edit on a line outside any case body and carrying no 'expect(', keep that anchor verbatim, and let the added block carry its own 'expect('. Rewriting an 'it()' title is not an insertion.\n\n  CORRECTING an assertion — a plan-level correction, so:\n    1. say so to the user, with which case and why\n    2. add one line to .claude/.tdd-unfrozen, in this shape:\n         $FILE_PATH  # <one-line reason>\n    3. then edit"
