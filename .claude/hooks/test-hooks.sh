#!/usr/bin/env bash
# Replay the hook fixtures exactly as Claude Code sends them on stdin.

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
FIXTURES_DIR="${FIXTURES_DIR:-$HOOKS_DIR/fixtures}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$HOOKS_DIR/../.." && pwd)}"
FAILURES=0
CASES=0

fail() {
    printf 'FAIL %s / %s: %s\n' "$1" "$2" "$3" >&2
    FAILURES=$((FAILURES + 1))
}

semantic_verdict() {
    local code="$1" stdout_file="$2"
    if [[ "$code" -eq 2 ]]; then
        printf deny
        return
    fi
    if [[ "$code" -ne 0 ]]; then
        printf crash
        return
    fi
    python3 - "$stdout_file" <<'PY'
import json
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if not text:
    print("pass")
else:
    try:
        payload = json.loads(text)
        print(payload.get("hookSpecificOutput", {}).get("permissionDecision", "pass"))
    except json.JSONDecodeError:
        print("invalid")
PY
}

deny_has_reason() {
    python3 - "$1" "$2" <<'PY'
import json
import pathlib
import sys

stdout = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
stderr = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
if stderr:
    raise SystemExit(0)
try:
    reason = json.loads(stdout).get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
except json.JSONDecodeError:
    reason = ""
raise SystemExit(0 if reason.strip() else 1)
PY
}

# A fixture may carry "_expect_reason": the decision's reason must contain it.
reason_has_expected() {
    python3 - "$1" "$2" <<'PY'
import json
import pathlib
import sys

expected = json.loads(sys.argv[1]).get("_expect_reason")
if not expected:
    raise SystemExit(0)
try:
    reason = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")).get(
        "hookSpecificOutput", {}).get("permissionDecisionReason", "")
except json.JSONDecodeError:
    reason = ""
raise SystemExit(0 if expected in reason else 1)
PY
}

run_case() {
    local hook="$1" fixture="$2" expected="$3"
    local tmp input stdout_file stderr_file code verdict fixture_name extra_marker="" project_dir="$PROJECT_ROOT"
    tmp="$(mktemp -d)"
    fixture_name="$(basename "$fixture")"
    stdout_file="$tmp/stdout"
    stderr_file="$tmp/stderr"
    input="$(sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g; s|__FIXTURE_ROOT__|$tmp|g; s|__MAIN_TREE__|$tmp|g; s|__FEAT_TREE__|$tmp/.feat|g" "$fixture")"

    case "$hook:$fixture_name" in
        # Edits an EXISTING item.utils.ts to add a never-before-exported
        # symbol. Deny case: no test file for it at all, so the symbol-level
        # check in tdd-require-red.sh has nothing to read a proved red from.
        tdd-require-red.sh:06-existing-new-export-deny.json)
            mkdir -p "$tmp/src"
            printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
            ;;
        # Same edit, pass case: a marker exists for item.utils.test.ts, its
        # digest matches the test file on disk, and its `missing:` line names
        # the symbol this edit adds — exactly what a real tdd-prove-red run
        # would have left behind. The marker lives under the REAL project's
        # .claude/.tdd-red/ (RED_DIR is derived from CLAUDE_PROJECT_DIR, which
        # run_case pins to $PROJECT_ROOT, never $tmp) — same reason
        # marker_path() is replicated below rather than sourcing hook-lib.sh.
        tdd-require-red.sh:07-existing-new-export-pass.json)
            mkdir -p "$tmp/src" "$PROJECT_ROOT/.claude/.tdd-red"
            printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
            printf '%s\n' "import { bonus } from './item.utils'; it('doubles', () => { expect(bonus()).toBe(2) })" \
                >"$tmp/src/item.utils.test.ts"
            extra_marker="$PROJECT_ROOT/.claude/.tdd-red/$(printf '%s' "$tmp/src/item.utils.test.ts" | tr -c 'A-Za-z0-9._-' '_')"
            {
                date -u +%Y-%m-%dT%H:%M:%SZ
                printf 'sha256:%s\n' "$(sha256sum "$tmp/src/item.utils.test.ts" | cut -d' ' -f1)"
                printf 'missing:%s\n' "bonus"
            } >"$extra_marker"
            ;;
        # The session runs inside a worktree: its project dir is the worktree.
        auto-approve-config.sh:0[12]-worktree-*)
            project_dir="$tmp/.claude/worktrees/small-a"
            mkdir -p "$project_dir"
            ;;
        *)
            case "$hook:$expected" in
                tdd-freeze-tests.sh:deny)
                    mkdir -p "$tmp/src"
                    printf '%s\n' "it('keeps the contract', () => { expect(1).toBe(1) })" >"$tmp/src/item.utils.test.ts"
                    ;;
                tdd-require-red.sh:pass)
                    mkdir -p "$tmp/src"
                    printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
                    ;;
                # Every git-hook fixture gets the same repo: __MAIN_TREE__ on
                # main, __FEAT_TREE__ a worktree on feat/x, and two aliases.
                enforce-git-workflow.sh:*)
                    git -C "$tmp" init -q -b main
                    git -C "$tmp" config user.email fixture@loopkit.invalid
                    git -C "$tmp" config user.name Fixture
                    git -C "$tmp" config alias.p push
                    git -C "$tmp" config alias.q '!sh -c x'
                    git -C "$tmp" config alias.a p
                    git -C "$tmp" config alias.ci commit
                    git -C "$tmp" commit -q --allow-empty -m seed
                    git -C "$tmp" worktree add -q "$tmp/.feat" -b feat/x
                    ;;
            esac
            ;;
    esac

    set +e
    printf '%s' "$input" | CLAUDE_PROJECT_DIR="$project_dir" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
        "$HOOKS_DIR/$hook" >"$stdout_file" 2>"$stderr_file"
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" "$stdout_file")"
    CASES=$((CASES + 1))

    if [[ "$verdict" != "$expected" ]]; then
        fail "$hook" "$(basename "$fixture")" \
            "expected $expected, got $verdict (process exit $code)"
    fi
    if [[ "$verdict" == invalid ]]; then
        fail "$hook" "$(basename "$fixture")" "hook output is not valid JSON"
    fi
    if [[ "$verdict" == crash ]]; then
        fail "$hook" "$(basename "$fixture")" \
            "unexpected non-zero exit $code (only 2 is a legacy deny)"
    fi
    if [[ "$verdict" == deny ]] && ! deny_has_reason "$stdout_file" "$stderr_file"; then
        fail "$hook" "$(basename "$fixture")" "deny has no actionable reason"
    fi
    if ! reason_has_expected "$input" "$stdout_file"; then
        fail "$hook" "$(basename "$fixture")" "reason does not contain the fixture's _expect_reason"
    fi

    [[ -n "$extra_marker" ]] && rm -f "$extra_marker"
    rm -r "$tmp"
}

run_fixture_sweep() {
    local directory hook fixture expected count
    while IFS= read -r directory; do
        hook="$(basename "$directory")"
        [[ "$hook" == _harness || "$hook" == install ]] && continue
        count=0
        while IFS= read -r fixture; do
            count=$((count + 1))
            case "$(basename "$fixture")" in
                *-pass.json) expected=pass ;;
                *-deny.json) expected=deny ;;
                *-ask.json) expected=ask ;;
                *-allow.json) expected=allow ;;
                *) fail "$hook" "$(basename "$fixture")" "name must end in -pass.json, -deny.json, -ask.json or -allow.json"; continue ;;
            esac
            run_case "$hook" "$fixture" "$expected"
        done < <(find "$directory" -maxdepth 1 -type f -name '*.json' | sort)
        [[ "$count" -gt 0 ]] || fail "$hook" "(none)" "hook directory is uncovered"
    done < <(find "$FIXTURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
}

run_harness_reproduction() {
    local tmp fixture output code
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/fixtures/always-pass.sh"
    cp "$FIXTURES_DIR/_harness/01-deny.json" "$tmp/fixtures/always-pass.sh/01-deny.json"
    cp "$FIXTURES_DIR/_harness/always-pass.sh" "$tmp/always-pass.sh"
    chmod +x "$tmp/always-pass.sh"
    set +e
    output="$(HOOKS_DIR="$tmp" FIXTURES_DIR="$tmp/fixtures" PROJECT_ROOT="$PROJECT_ROOT" \
        "$0" --fixtures-only 2>&1)"
    code=$?
    set -e
    if [[ "$code" -eq 0 ]]; then
        fail _harness 01-deny.json "broken hook was not detected"
    elif [[ "$output" != *"always-pass.sh / 01-deny.json"* ]] || \
         [[ "$output" != *"expected deny, got pass"* ]]; then
        fail _harness 01-deny.json "failure does not name hook, fixture, and expected/actual verdict"
    fi
    rm -r "$tmp"
}

run_harness_edges() {
    local tmp output code
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/fixtures/empty.sh"
    cp "$FIXTURES_DIR/_harness/always-pass.sh" "$tmp/empty.sh"
    chmod +x "$tmp/empty.sh"
    set +e
    output="$(HOOKS_DIR="$tmp" FIXTURES_DIR="$tmp/fixtures" PROJECT_ROOT="$PROJECT_ROOT" \
        "$0" --fixtures-only 2>&1)"
    code=$?
    set -e
    if [[ "$code" -eq 0 || "$output" != *"hook directory is uncovered"* ]]; then
        fail _harness empty "zero-fixture hook was not reported as uncovered"
    fi
    rm -r "$tmp"

    tmp="$(mktemp -d)"
    mkdir -p "$tmp/fixtures/crash.sh"
    cp "$FIXTURES_DIR/_harness/01-deny.json" "$tmp/fixtures/crash.sh/01-deny.json"
    cp "$FIXTURES_DIR/_harness/crash.sh" "$tmp/crash.sh"
    chmod +x "$tmp/crash.sh"
    set +e
    output="$(HOOKS_DIR="$tmp" FIXTURES_DIR="$tmp/fixtures" PROJECT_ROOT="$PROJECT_ROOT" \
        "$0" --fixtures-only 2>&1)"
    code=$?
    set -e
    if [[ "$code" -eq 0 || "$output" != *"unexpected non-zero exit 1"* ]]; then
        fail _harness crash "non-deny process failure was not reported as a crash"
    fi
    rm -r "$tmp"
}

run_missing_jq_cases() {
    local tmp hook code output
    tmp="$(mktemp -d)"
    for command in env bash dirname basename date; do
        ln -s "$(command -v "$command")" "$tmp/$command"
    done
    for hook in no-any-type.sh protect-files.sh no-forbidden-icons.sh \
                tdd-freeze-tests.sh tdd-require-red.sh tdd-prove-red.sh \
                prevent-destructive-commands.sh enforce-git-workflow.sh; do
        set +e
        output="$(printf '{}' | PATH="$tmp" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/$hook" 2>&1)"
        code=$?
        set -e
        CASES=$((CASES + 1))
        if [[ "$code" -ne 2 ]]; then
            fail "$hook" jq-absent "expected fail-closed exit 2, got $code"
        elif [[ "$output" != *"jq is not on PATH"* ]]; then
            fail "$hook" jq-absent "exit 2 did not explain the missing prerequisite"
        fi
    done
    rm -r "$tmp"
}

# tdd-prove-red.sh runs the real suite, so its import reader is driven alone:
# one tab-separated case per line, title, test file content (`\\n` for a line
# break), expected symbols.
run_prove_red_symbols() {
    local tmp title content expected actual
    tmp="$(mktemp -d)"
    while IFS=$'\t' read -r title content expected; do
        [[ -z "$title" ]] && continue
        CASES=$((CASES + 1))
        printf '%b\n' "$content" > "$tmp/item.mapper.test.ts"
        actual="$("$HOOKS_DIR/tdd-prove-red.sh" --symbols "$tmp/item.mapper.test.ts" | tr '\n' ' ' | sed 's/ $//')"
        [[ "$actual" == "$expected" ]] \
            || fail tdd-prove-red.sh "symbols: $title" "expected '$expected', got '$actual'"
    done < "$FIXTURES_DIR/_harness/prove-red-symbols.tsv"
    rm -r "$tmp"
}

# hook-guarded.sh: one case = one function call in a fresh bash, run from the
# project root and again from .claude/hooks/ (the result may not depend on $PWD).
guard_call() {
    local dir="$1"; shift
    (cd "$dir" && bash -c 'source "$1" || exit 99; shift; "$@"' _ "$HOOKS_DIR/hook-guarded.sh" "$@" 2>&1)
}

guard_expect() {
    local want="$1" out code dir; shift
    for dir in "$PROJECT_ROOT" "$HOOKS_DIR"; do
        CASES=$((CASES + 1))
        set +e
        out="$(CLAUDE_PROJECT_DIR="$PROJECT_ROOT" guard_call "$dir" "$@")"
        code=$?
        set -e
        [[ "$code" -eq "$want" ]] \
            || fail hook-guarded.sh "$* (from ${dir#"$PROJECT_ROOT"})" "expected exit $want, got $code"
        [[ -z "$out" ]] || fail hook-guarded.sh "$* (from ${dir#"$PROJECT_ROOT"})" "printed '$out'"
    done
}

guard_rel_expect() {
    local want="$1" want_code="$2" project="$3" out code; shift 3
    CASES=$((CASES + 1))
    set +e
    out="$(CLAUDE_PROJECT_DIR="$project" guard_call "$HOOKS_DIR" cwk_guard_rel "$@")"
    code=$?
    set -e
    [[ "$out" == "$want" && "$code" -eq "$want_code" ]] \
        || fail hook-guarded.sh "cwk_guard_rel $*" "expected '$want' exit $want_code, got '$out' exit $code"
}

run_guarded_cases() {
    local p="$PROJECT_ROOT" tmp rel out code hook before after
    # W1 the set, folders above it, and the denied set
    for rel in .claude/scripts/a.sh .claude/hooks .github .claude . package.json tsconfig.app.json; do
        guard_expect 0 cwk_is_guarded "$rel"
    done
    for rel in src/x.ts src docs/x.md apps/web/package.json; do
        guard_expect 1 cwk_is_guarded "$rel"
    done
    for rel in .claude/.tdd-red/m .claude/.tdd-red; do
        guard_expect 0 cwk_is_guard_denied "$rel"
    done
    for rel in .claude .claude/hooks/a.sh; do
        guard_expect 1 cwk_is_guard_denied "$rel"
    done

    # W1 sourcing it has no side effect: no log line, no output, no trap, no shopt
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/.claude"
    printf 'seed\n' > "$tmp/.claude/.hook-timings.log"
    before="$(sha256sum "$tmp/.claude/.hook-timings.log")"
    CASES=$((CASES + 1))
    set +e
    out="$(CLAUDE_PROJECT_DIR="$tmp" CWK_HOOK_TIMING=1 bash -c \
        'source "$1" || exit 99; trap -p; shopt -p extglob || true' _ "$HOOKS_DIR/hook-guarded.sh" 2>&1)"
    code=$?
    set -e
    after="$(sha256sum "$tmp/.claude/.hook-timings.log")"
    [[ "$code" -eq 0 && "$out" == "shopt -u extglob" && "$before" == "$after" ]] \
        || fail hook-guarded.sh side-effects "expected exit 0, no trap, extglob off, log unchanged; got exit $code, '$out'"

    # W2 cwk_guard_rel
    ln -s "$p" "$tmp/alias"
    guard_rel_expect .claude/hooks/a.sh 0 "$p" "$p/.claude/worktrees/x/.claude/hooks/a.sh"
    guard_rel_expect vite.config.ts 0 "$p" "$p/src/../vite.config.ts"
    guard_rel_expect package.json 0 "$p" "$p//package.json"
    guard_rel_expect package.json 0 "$p" "$p/./package.json"
    guard_rel_expect package.json 0 "$p" ../package.json "$p/src"
    guard_rel_expect package.json 0 "$p" package.json
    guard_rel_expect vite.config.ts 0 "$p" "$tmp/alias/vite.config.ts"
    guard_rel_expect vite.config.ts 0 "$tmp/alias" "$p/vite.config.ts"
    guard_rel_expect "" 1 "$p" "$p/../y"
    guard_rel_expect "" 1 "$p" /etc/passwd
    rm -r "$tmp"

    # W6 hook-guarded.sh missing: the guard hooks fail closed, the Stop hook does not
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    rm -f "$tmp/hook-guarded.sh"
    for hook in protect-files.sh prevent-destructive-commands.sh enforce-git-workflow.sh \
                tdd-require-red.sh tdd-freeze-tests.sh; do
        CASES=$((CASES + 1))
        set +e
        out="$(printf '{}' | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$tmp/$hook" 2>&1)"
        code=$?
        set -e
        [[ "$code" -eq 2 && "$out" == *"BLOCKED: hook-guarded.sh missing"* ]] \
            || fail "$hook" guarded-missing "expected exit 2 with 'BLOCKED: hook-guarded.sh missing', got $code"
    done
    mkdir -p "$tmp/root/.claude"
    CASES=$((CASES + 1))
    set +e
    out="$(CLAUDE_PROJECT_DIR="$tmp/root" CWK_HOOK_TIMING=0 "$tmp/eslint-batch.sh" </dev/null 2>&1)"
    code=$?
    set -e
    [[ "$code" -eq 0 && "$out" == *"WARNING: hook-guarded.sh missing"* ]] \
        || fail eslint-batch.sh guarded-missing "expected exit 0 with 'WARNING: hook-guarded.sh missing', got $code"
    rm -r "$tmp"
}

guard_hook_run() {
    local dir="$1" hook="$2" input="$3"
    printf '%s' "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$dir/$hook" 2>&1
}

# W8-W11 hardening of the guarded set: a broken list fails closed like a missing
# one, a half-upgraded kit does not pass, a newline in a path does not escape.
run_guarded_hardening_cases() {
    local p="$PROJECT_ROOT" tmp hook out code variant
    # W8 hook-guarded.sh present but empty, or CWK_GUARDED emptied: the five guard hooks refuse
    for variant in empty guarded-empty; do
        tmp="$(mktemp -d)"
        cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
        if [[ "$variant" == empty ]]; then
            : > "$tmp/hook-guarded.sh"
        else
            printf 'CWK_GUARDED=()\n' >> "$tmp/hook-guarded.sh"
        fi
        for hook in protect-files.sh prevent-destructive-commands.sh enforce-git-workflow.sh \
                    tdd-require-red.sh tdd-freeze-tests.sh; do
            CASES=$((CASES + 1))
            set +e
            out="$(guard_hook_run "$tmp" "$hook" '{}')"
            code=$?
            set -e
            [[ "$code" -eq 2 && "$out" == *"hook-guarded.sh missing or broken"* ]] \
                || fail "$hook" "guarded-$variant" "expected exit 2 with 'hook-guarded.sh missing or broken', got $code"
        done
        rm -r "$tmp"
    done

    # W9 half-upgraded kit: the previous hook-lib.sh (no source of hook-guarded.sh) + the current protect-files.sh
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    sed '/^# -* hook-guarded$/,/^# -* cwk_require_jq$/{/cwk_require_jq/!d;}' "$HOOKS_DIR/hook-lib.sh" > "$tmp/hook-lib.sh"
    for rel in package.json .claude/.tdd-red/x; do
        CASES=$((CASES + 1))
        set +e
        out="$(guard_hook_run "$tmp" protect-files.sh \
            "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$p/$rel\",\"content\":\"x\"}}")"
        code=$?
        set -e
        [[ "$code" -eq 2 || "$out" == *'"permissionDecision":"deny"'* || "$out" == *'"permissionDecision": "deny"'* ]] \
            || fail protect-files.sh "old-hook-lib $rel" "expected deny, got exit $code '$out'"
    done
    rm -r "$tmp"

    # W10 a newline inside a path segment stays inside it
    guard_rel_expect package.json 0 "$p" "$p/x"$'\n'"/../package.json"
    guard_rel_expect .claude/.tdd-red/m 0 "$p" "$p/a"$'\n'"/../.claude/.tdd-red/m"

    # W11 near-prefix folders are not guarded; sourcing changes no shell option at all
    guard_expect 1 cwk_is_guarded .git
    guard_expect 1 cwk_is_guarded .claude/hook
    CASES=$((CASES + 1))
    set +e
    out="$(bash -c 'a="$(shopt -p; set +o)"; source "$1" || exit 99; b="$(shopt -p; set +o)"; [[ "$a" == "$b" ]] && echo same || echo changed' _ "$HOOKS_DIR/hook-guarded.sh" 2>&1)"
    set -e
    [[ "$out" == same ]] || fail hook-guarded.sh side-effects-full "shopt/set output changed after sourcing: '$out'"
}

set -e
run_fixture_sweep
if [[ "${1:-}" != --fixtures-only ]]; then
    run_harness_reproduction
    run_harness_edges
    run_missing_jq_cases
    run_guarded_cases
    run_guarded_hardening_cases
    run_prove_red_symbols
    ADDON_TEST="$HOOKS_DIR/../../addons/fastapi/hooks/test_imported_symbols.py"
    if [[ -f "$ADDON_TEST" ]]; then
        CASES=$((CASES + 1))
        python3 "$ADDON_TEST" || fail tdd-prove-red-py imported_symbols "parser cases failed"
    fi
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2
    exit 1
fi
printf 'Hook fixtures: %d case(s), all green.\n' "$CASES"
