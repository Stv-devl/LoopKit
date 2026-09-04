#!/usr/bin/env bash
#
# Hook: tdd-prove-red
# Event: PostToolUse (Write|Edit)
# Purpose: The RED phase is proved, not declared. Runs the test file that was
#          just written, decides whether that run is a GENUINE red, and — when it
#          is — drops a marker that `tdd-require-red.sh` requires before the
#          implementation may be created.
#
# Why a marker and not just a message: a PostToolUse message is a reminder, and a
# reminder loses to an agent under pressure to look finished. The marker is what
# turns "the RED phase is documented" into "the implementation cannot be written
# without it".
#
# What counts as a genuine RED. Not "the file does not exist yet" — that is only
# true for the first file of a feature, and every later function lands in a file
# that already exists. The real question is whether the SYMBOLS the test exercises
# already exist. A test that passes against symbols that are all already exported
# asserts what the code happens to do: it cannot prove anything, and saying
# "GREEN, go refactor" there is exactly the test-after this hook exists to catch.
#
# And a failure is not a proof either, on its own. Two things are checked before
# the marker is written, because both produce a red that proves nothing:
#
#   - the file contains no assertion at all. `expect-expect` catches that, but
#     only at the `pnpm lint` gate in /loop:ship — long after this marker unlocked the
#     implementation and the freeze closed the file.
#   - the run died before reaching any assertion. An unresolved import OF THE
#     MODULE UNDER TEST is the legitimate first red and stays accepted; a syntax
#     error, an empty suite, or a missing helper/fixture is a broken test file.
#   - the file exercises nothing the hook can read. A four-line test with no
#     import of the module under test and one `expect(1).toBe(2)` fails, and
#     unlocked the implementation for years' worth of nothing.
#
# CONFIGURE: swap `pnpm test:run` for this repo's run-once test script
#            (never watch mode — it does not exit).
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

RUN_TESTS="pnpm test:run"
# Below the harness timeout in settings.json, so a slow suite reports instead of
# being killed silently. A hook that dies without a word looks like a green gate.
RUN_TIMEOUT=150

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# A tree with its own toolchain runs its own tests; `$RUN_TESTS` would report a
# red that says nothing about it. See cwk_foreign_toolchain in hook-lib.sh.
cwk_foreign_toolchain "$FILE_PATH" && exit 0

# Only the test-first layers (.claude/rules/05-testing.md). The other test files
# are written after their code — a red run there means nothing.
if [[ ! "$FILE_PATH" =~ $CWK_TDD_TEST_RE ]]; then
    exit 0
fi

[[ -f "$FILE_PATH" ]] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
RED_DIR="$PROJECT_DIR/.claude/.tdd-red"

# Same two functions as tdd-require-red.sh — change one, change both.
# The path is normalised first (cwk_abs_path): the two hooks must derive the
# same marker name for the same file, and they do not always receive the same
# spelling of its path.
marker_path() {
    printf '%s/%s' "$RED_DIR" "$(cwk_abs_path "$1" | tr -c 'A-Za-z0-9._-' '_')"
}

# The marker records WHICH test file was seen failing, not just that one was.
# Without it a marker outlives the test it proved: delete the test, write a new
# one at the same path, and the module could be created on a red nobody observed.
file_digest() {
    if command -v sha256sum &> /dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf 'unavailable'
    fi
}

# jq builds the envelope, so a path or a runner tail carrying a `"` cannot make
# the JSON unparseable — an unparseable message is dropped, and a TDD hook that
# says nothing reads exactly like a passing gate.
# The runner tail is spliced in raw: jq escapes the tabs, quotes and ANSI escapes
# it carries. Pre-escaping it by hand (the old json_escape) then re-escaping here
# would double every backslash in a stack trace.
emit() {
    local msg
    msg="${1//\\n/$'\n'}"
    jq -n --arg m "$msg" '{systemMessage: $m}'
    exit 0
}

# The runner binary itself is missing (npm/yarn/bun project, or no Node at all).
# This used to `exit 0` in silence — and since tdd-require-red has no such
# escape, every module creation was then denied forever, with a message advising
# a re-save that could not possibly help. Say it instead.
RUNNER_BIN="${RUN_TESTS%% *}"
command -v "$RUNNER_BIN" &> /dev/null || emit "TDD hook: '$RUNNER_BIN' is not on PATH, so the RED phase could NOT be proved for $FILE_PATH and no marker was recorded — tdd-require-red.sh will refuse to create the implementation module. Point RUN_TESTS in .claude/hooks/tdd-prove-red.sh at this repo's run-once test script (.claude/rules/00-project.md)."

# ---------------------------------------------------------------- implementation

# Strip the test suffix rather than replacing the first `.test.` in the path —
# a directory called `x.test.y` upstream would otherwise rewrite the wrong part.
BASE="${FILE_PATH%.test.ts}"
[[ "$BASE" == "$FILE_PATH" ]] && BASE="${FILE_PATH%.test.tsx}"

IMPL_PATH=""
for ext in ts tsx; do
    [[ -f "$BASE.$ext" ]] && IMPL_PATH="$BASE.$ext" && break
done

MODULE_BASE=$(basename "$BASE")
MODULE_RE=$(printf '%s' "$MODULE_BASE" | sed 's/\./\\./g')

# ---------------------------------------------------------------------- symbols

# Flattened, so a multi-line `import { a, b } from './x'` is still one match.
FLAT=$(tr '\n' ' ' < "$FILE_PATH")

SYMBOLS=""

# import { toEntity, fromEntity } from './item.mapper'
NAMED=$(printf '%s' "$FLAT" \
    | grep -oE "import[[:space:]]+(type[[:space:]]+)?\{[^}]*\}[[:space:]]+from[[:space:]]+['\"][^'\"]*${MODULE_RE}['\"]" \
    || true)
if [[ -n "$NAMED" ]]; then
    SYMBOLS+=$(printf '%s' "$NAMED" \
        | sed 's/.*{\([^}]*\)}.*/\1/' \
        | tr ',' '\n' \
        | sed 's/[[:space:]]*type[[:space:]]\+//; s/[[:space:]]\+as[[:space:]]\+.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' || true)
    SYMBOLS+=$'\n'
fi

# import * as repository from './item.repository'  → collect `repository.<name>`
ALIAS=$(printf '%s' "$FLAT" \
    | grep -oE "import[[:space:]]+\*[[:space:]]+as[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+from[[:space:]]+['\"][^'\"]*${MODULE_RE}['\"]" \
    | sed -E 's/.*as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+from.*/\1/' \
    || true)
if [[ -n "$ALIAS" ]]; then
    SYMBOLS+=$(printf '%s' "$FLAT" \
        | grep -oE "\b${ALIAS}\.[A-Za-z_][A-Za-z0-9_]*" \
        | cut -d. -f2 \
        | sort -u || true)
    SYMBOLS+=$'\n'
fi

SYMBOLS=$(printf '%s' "$SYMBOLS" | sed '/^[[:space:]]*$/d' | sort -u)

# Does the file assert anything at all? A run that fails without asserting is a
# broken file, not a RED phase — and it is the exact shape of a "red" an agent
# produces when it is in a hurry.
HAS_ASSERTION=""
if grep -qE '\b(expect|expectTypeOf)[[:space:]]*\(|\bassert[[:space:]]*[.(]' "$FILE_PATH"; then
    HAS_ASSERTION=1
fi

# A symbol is "already there" only if the implementation module exports it.
MISSING=""
if [[ -z "$IMPL_PATH" ]]; then
    MISSING="$SYMBOLS"
else
    while IFS= read -r sym; do
        [[ -z "$sym" ]] && continue
        if grep -qE "export[[:space:]]+(async[[:space:]]+)?(function|const|let|var|class|type|interface|enum)[[:space:]]+${sym}\b" "$IMPL_PATH" \
           || grep -qE "export[[:space:]]*\{[^}]*\b${sym}\b" "$IMPL_PATH"; then
            continue
        fi
        MISSING+="$sym"$'\n'
    done <<< "$SYMBOLS"
fi
MISSING=$(printf '%s' "$MISSING" | sed '/^[[:space:]]*$/d')

# ------------------------------------------------------------------- test run

set +e
if command -v timeout &> /dev/null; then
    TEST_OUTPUT=$(timeout "$RUN_TIMEOUT" $RUN_TESTS "$FILE_PATH" 2>&1)
else
    TEST_OUTPUT=$($RUN_TESTS "$FILE_PATH" 2>&1)
fi
TEST_EXIT=$?
set -e

TAIL=$(echo "$TEST_OUTPUT" | tail -15)

if [[ $TEST_EXIT -eq 124 ]]; then
    emit "TDD hook: the runner exceeded ${RUN_TIMEOUT}s on $FILE_PATH — the RED phase was NOT proved. Run it yourself and report the outcome, or raise RUN_TIMEOUT in .claude/hooks/tdd-prove-red.sh."
fi

# The runner never actually ran (missing script, no project, nothing matched).
# Say so — a hook that fails silently is worse than one that is noisy, because
# it looks like a passing gate.
if echo "$TEST_OUTPUT" | grep -qiE "ERR_PNPM_|Missing script|Command \"[^\"]*\" not found|No test files found"; then
    emit "TDD hook: could not run the test runner on $FILE_PATH — the RED phase was NOT proved. Configure the run-once script in .claude/hooks/tdd-prove-red.sh (see 00-project.md).\\n\\n$TAIL"
fi

# Vitest exits non-zero when a test fails. The exit code is the signal — parsing
# the output for failure strings misreads a runner that never started.
if [[ $TEST_EXIT -eq 0 ]]; then STATE="GREEN"; else STATE="RED"; fi

# WHY it failed. The exit code cannot tell an assertion that fired from a file
# that never loaded, and only one of the two proves anything.
#
#   assertion        — the test ran and an expectation failed. The real thing.
#   missing-module   — the import of the module under test does not resolve. The
#                      legitimate first red of a feature: the module is what the
#                      GREEN leg is about to create.
#   unresolved-other — some OTHER import does not resolve: a helper, a fixture, a
#                      dependency. Nothing about the behaviour under test.
#   broken-file      — syntax/transform error, or no suite in the file at all.
# The discrimination is on the SPECIFIER that failed, never on the whole line.
# Vite writes the importing file on that same line — `Failed to load url
# ./item.gateway ... in /…/item.repository.test.ts` — and for a colocated test
# that path always contains the module name. Matching the line therefore made
# every unresolved import read as `missing-module`, which retired this check
# entirely: a broken fixture import was recorded as the legitimate first red.
UNRESOLVED_RE="Failed to load url|Failed to resolve import|Cannot find module|Cannot find package"

# Did the runner reach the cases at all? Vitest prints its `Tests  N failed` line
# only once a suite has been collected and run. Without this, `broken-file` was
# decided on the WHOLE output and the word `SyntaxError` anywhere in it — a
# `toThrow(SyntaxError)` diff, or an `it()` title carrying it, which Vitest
# echoes in its FAIL line — permanently deadlocked a legitimate RED: no marker,
# so tdd-require-red refused the module forever, and re-saving reproduced it.
# A run that reached its assertions is not a broken file, whatever it printed.
TESTS_RAN=""
if echo "$TEST_OUTPUT" | grep -qE "^[[:space:]]*Tests[[:space:]]+[0-9]+[[:space:]]+(failed|passed|skipped|todo)"; then
    TESTS_RAN=1
fi

FAILURE_KIND="assertion"
if [[ -z "$TESTS_RAN" ]] && echo "$TEST_OUTPUT" | grep -qE "SyntaxError|Transform failed|No test suite found"; then
    FAILURE_KIND="broken-file"
elif echo "$TEST_OUTPUT" | grep -qE "$UNRESOLVED_RE"; then
    # Keep only what follows the marker phrase, up to the first quote or space.
    FAILED_SPECS=$(printf '%s' "$TEST_OUTPUT" \
        | grep -oE "($UNRESOLVED_RE)[[:space:]]+[\"']?[^\"'[:space:]]+" \
        | sed -E "s/^($UNRESOLVED_RE)[[:space:]]+[\"']?//" \
        | sed '/^[[:space:]]*$/d' || true)

    # EVERY unresolved specifier has to be the module under test, not merely one
    # of them. `grep -q` is an ANY test where the rule needs ALL — and on the
    # first RED of a feature the module is absent by construction, so a broken
    # fixture import travelled alongside it and was recorded as the legitimate
    # first red. That is exactly the failure the `unresolved-other` check exists
    # to catch, defeated in the one situation it was written for.
    OTHER_SPECS=$(printf '%s\n' "$FAILED_SPECS" \
        | grep -vE "(^|/)${MODULE_RE}(\.tsx?)?$" | sed '/^[[:space:]]*$/d' || true)

    if [[ -n "$OTHER_SPECS" ]]; then
        FAILURE_KIND="unresolved-other"
    elif printf '%s\n' "$FAILED_SPECS" | grep -qE "(^|/)${MODULE_RE}(\.tsx?)?$"; then
        FAILURE_KIND="missing-module"
    else
        FAILURE_KIND="unresolved-other"
    fi
fi

# ------------------------------------------------------------------- verdict

MISSING_LIST=$(printf '%s' "$MISSING" | tr '\n' ' ')

if [[ "$STATE" == "RED" ]]; then

    # ---- the red has to be the right red, or no marker is written -----------
    # No marker means tdd-require-red keeps refusing to create the module. That
    # is the intended outcome: a noisy block beats a TDD that believes it is on.

    if [[ -z "$HAS_ASSERTION" ]]; then
        emit "TDD: $FILE_PATH failed, but it contains no assertion — no expect(), no assert. A run that fails without asserting anything proves nothing about the behaviour it names, so NO marker was recorded and the module still cannot be created. Write the cases from the /loop:plan test plan, then save again.\\n\\n$TAIL"
    fi

    if [[ "$FAILURE_KIND" == "broken-file" ]]; then
        emit "TDD: $FILE_PATH did not fail on an assertion — the runner could not load it (syntax or transform error, or no test suite in the file). That is a broken test file, not a RED phase: NO marker was recorded. Fix the file and save again.\\n\\n$TAIL"
    fi

    if [[ "$FAILURE_KIND" == "unresolved-other" ]]; then
        OTHER_LIST=$(printf '%s' "${OTHER_SPECS:-}" | tr '\n' ' ')
        emit "TDD: $FILE_PATH failed on an import that is NOT the module under test ($MODULE_BASE) — a helper, a fixture or a dependency that does not resolve${OTHER_LIST:+: $OTHER_LIST}. An unresolved import of the module under test is a legitimate red; this one only says the test file is broken. NO marker was recorded.\\n\\n$TAIL"
    fi

    # The red has to exercise SOMETHING. The GREEN branch below already refuses
    # when it cannot tell what the file exercises — the RED branch had no such
    # guard, so a four-line file with no import of the module under test and a
    # single `expect(1).toBe(2)` wrote the marker and unlocked module creation.
    # A failure that names nothing proves nothing, in either direction.
    if [[ -z "$SYMBOLS" ]]; then
        emit "TDD: $FILE_PATH failed, but this hook cannot tell what it exercises — it carries no import of '$MODULE_BASE' that can be read. A red that names nothing about the module under test proves nothing about the behaviour it claims, so NO marker was recorded and the module still cannot be created. Import the symbols from the /loop:plan Contracts block and save again.\\n\\n$TAIL"
    fi

    mkdir -p "$RED_DIR"
    # Self-ignoring: the markers are session state, never versioned.
    [[ -f "$RED_DIR/.gitignore" ]] || printf '*\n' > "$RED_DIR/.gitignore"
    # The `missing:` line is what lets tdd-require-red.sh gate a symbol added
    # to a module that already exists, not only the module's first write — see
    # that hook for why the file-exists case needed more than a marker's mere
    # presence. Empty is a legitimate value: it means every symbol this test
    # exercises already exists, i.e. this red is a new case on old behaviour.
    {
        date -u +%Y-%m-%dT%H:%M:%SZ
        printf 'sha256:%s\n' "$(file_digest "$FILE_PATH")"
        printf 'missing:%s\n' "$MISSING_LIST"
    } > "$(marker_path "$FILE_PATH")"

    if [[ -z "$IMPL_PATH" ]]; then
        emit "TDD: RED confirmed for $FILE_PATH — no implementation module yet. Now write just enough code to pass; the test does not move.\\n\\n$TAIL"
    elif [[ -n "$MISSING" ]]; then
        emit "TDD: RED confirmed for $FILE_PATH — not yet in $IMPL_PATH: $MISSING_LIST. Write just enough code to pass; the test does not move.\\n\\n$TAIL"
    else
        emit "TDD: RED confirmed for $FILE_PATH — every symbol already exists in $IMPL_PATH, so this is a new case on existing behaviour. Fix the implementation, not the test — it is frozen (.claude/rules/05-testing.md).\\n\\n$TAIL"
    fi
fi

# GREEN. The only question left is whether it proves anything.
if [[ -z "$SYMBOLS" ]]; then
    emit "TDD: $FILE_PATH is GREEN, but this hook could not tell what it exercises (no import of $MODULE_BASE it can read). The RED phase is NOT proved — say so, or restate the test against the module under test."
fi

if [[ -n "$MISSING" ]]; then
    emit "TDD: $FILE_PATH PASSES while $MISSING_LIST is not exported by ${IMPL_PATH:-$BASE.ts} — the test asserts nothing about the behaviour it names. Rewrite it before writing any implementation (.claude/rules/05-testing.md)."
fi

emit "TDD: $FILE_PATH is GREEN and every symbol it exercises already exists in ${IMPL_PATH:-the module} — the RED phase could NOT be proved for it. Legitimate only if this write was an unfreezing correction (.claude/.tdd-unfrozen). Otherwise the test was written after the code and proves nothing: say which one it is."
