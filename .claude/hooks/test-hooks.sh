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

# X1-X11 of docs/work/guard-shell/plan.md: one case per line of the jsonl, each
# turned into a fixture and run through run_case, so it gets the same checks.
run_shell_guard_cases() {
    local file="$FIXTURES_DIR/_harness/shell-guard.jsonl" tmp line id verdict command cwd reason count=0
    local -A seen=()
    local -a lines=()
    if [[ ! -f "$file" ]]; then
        fail prevent-destructive-commands.sh shell-guard.jsonl "case file is missing"
        return 0
    fi
    mapfile -t lines < "$file"
    tmp="$(mktemp -d)"
    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        if ! jq -e 'type == "object" and (.id | type == "string") and (.command | type == "string")
                    and (.verdict | IN("ask", "deny", "pass"))' <<<"$line" >/dev/null 2>&1; then
            fail prevent-destructive-commands.sh shell-guard.jsonl "unparsable or incomplete line: ${line:0:60}"
            continue
        fi
        id="$(jq -r '.id' <<<"$line")"
        verdict="$(jq -r '.verdict' <<<"$line")"
        command="$(jq -r '.command' <<<"$line")"
        cwd="$(jq -r '.cwd // "__PROJECT_ROOT__"' <<<"$line")"
        reason="$(jq -r '.reason // ""' <<<"$line")"
        if [[ -n "${seen[$id]:-}" ]]; then
            fail prevent-destructive-commands.sh "$id" "duplicate case id"
            continue
        fi
        seen[$id]=1
        if [[ "$verdict" != pass && -z "$reason" ]]; then
            fail prevent-destructive-commands.sh "$id" "ask/deny case has no reason"
            continue
        fi
        count=$((count + 1))
        jq -cn --arg command "$command" --arg cwd "$cwd" --arg reason "$reason" \
            '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}
             + (if $reason != "" then {_expect_reason: $reason} else {} end)' \
            > "$tmp/$id-$verdict.json"
        run_case prevent-destructive-commands.sh "$tmp/$id-$verdict.json" "$verdict"
    done
    [[ "$count" -gt 0 ]] || fail prevent-destructive-commands.sh shell-guard.jsonl "case file holds no case"
    rm -r "$tmp"
}

# Prints the verdict on its first line, then the hook's stdout and stderr.
shell_guard_probe() {
    local dir="$1" path_override="$2" command="$3" input tmp code verdict
    tmp="$(mktemp -d)"
    input="$(jq -cn --arg command "$command" --arg cwd "$PROJECT_ROOT" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}')"
    set +e
    printf '%s' "$input" | PATH="${path_override:-$PATH}" CLAUDE_PROJECT_DIR="$PROJECT_ROOT" \
        CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$dir/prevent-destructive-commands.sh" \
        >"$tmp/stdout" 2>"$tmp/stderr"
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" "$tmp/stdout")"
    printf '%s\n' "$verdict"
    cat "$tmp/stdout" "$tmp/stderr"
    rm -r "$tmp"
}

# X12: a missing or broken shell_targets.py is not a pass.
run_shell_guard_failure_cases() {
    local state tmp bin tool out verdict want reason command path_override i
    local -a commands=("sed -i 's/a/b/' package.json" "echo x > .github/workflows/ci.yml" "touch .claude/.tdd-red/m" "ls src")
    local -a wants=(ask ask deny pass)
    for state in renamed empty exit1 garbage nosentinel no-python3; do
        tmp="$(mktemp -d)"
        cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
        path_override=""
        case "$state" in
            renamed)    rm -f "$tmp/shell_targets.py" ;;
            empty)      : > "$tmp/shell_targets.py" ;;
            exit1)      printf 'import sys\nsys.exit(1)\n' > "$tmp/shell_targets.py" ;;
            garbage)    printf 'print("garbage")\n' > "$tmp/shell_targets.py" ;;
            nosentinel) printf 'print("rm\\tpackage.json")\n' > "$tmp/shell_targets.py" ;;
            no-python3)
                bin="$tmp/bin-no-python3"
                mkdir -p "$bin"
                for tool in env bash dirname basename date jq grep sed cat tr head tail cut sort uniq \
                            mktemp rm mkdir wc readlink realpath sha256sum awk ls touch cp mv ln tee \
                            id uname sleep git; do
                    [[ -x "$(command -v "$tool" 2>/dev/null)" ]] && ln -sf "$(command -v "$tool")" "$bin/$tool"
                done
                path_override="$bin"
                ;;
        esac
        for i in 0 1 2 3; do
            command="${commands[$i]}"; want="${wants[$i]}"; reason=""
            [[ "$want" == pass ]] || reason="shell guard unavailable"
            CASES=$((CASES + 1))
            out="$(shell_guard_probe "$tmp" "$path_override" "$command")"
            verdict="${out%%$'\n'*}"
            if [[ "$verdict" != "$want" ]]; then
                fail prevent-destructive-commands.sh "resolver-$state: $command" "expected $want, got $verdict"
            elif [[ -n "$reason" && "$out" != *"$reason"* ]]; then
                fail prevent-destructive-commands.sh "resolver-$state: $command" "reason does not contain '$reason'"
            fi
        done
        rm -r "$tmp"
    done
}

# X14: a padded command stays far under the hook timeout, and the row cap keeps the deny.
run_shell_guard_budget_case() {
    local tmp operands start end elapsed_ms
    tmp="$(mktemp -d)"
    operands="$(printf 'f%d ' $(seq 1 500))"
    jq -cn --arg command "rm ${operands}package.json" --arg cwd "__PROJECT_ROOT__" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}' > "$tmp/X14.01-ask.json"
    operands="$(printf 'f%d ' $(seq 1 70))"
    jq -cn --arg command "rm ${operands}.claude/.tdd-red/m" --arg cwd "__PROJECT_ROOT__" --arg reason "is written only by tdd-prove-red.sh" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd, _expect_reason: $reason}' > "$tmp/X14.02-deny.json"
    run_case prevent-destructive-commands.sh "$tmp/X14.01-ask.json" ask
    start="$(date +%s%N)"
    sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" "$tmp/X14.01-ask.json" \
        | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
            "$HOOKS_DIR/prevent-destructive-commands.sh" >/dev/null 2>&1 || true
    end="$(date +%s%N)"
    elapsed_ms=$(((end - start) / 1000000))
    [[ "$elapsed_ms" -lt 2000 ]] \
        || fail prevent-destructive-commands.sh X14.01-ask.json "500-operand rm took ${elapsed_ms} ms, bound is 2000"
    run_case prevent-destructive-commands.sh "$tmp/X14.02-deny.json" deny
    rm -r "$tmp"
}

# X16: the hook runs on bash 3.2 constructs only (macOS /bin/bash): mapfile and
# readarray are disabled for the run, and the file holds none of the 4.x forms.
run_shell_guard_bash3_case() {
    local hook="$HOOKS_DIR/prevent-destructive-commands.sh" command input out code verdict banned
    for command in "echo x > package.json" "echo hi"; do
        input="$(jq -cn --arg command "$command" --arg cwd "$PROJECT_ROOT" \
            '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}')"
        CASES=$((CASES + 1))
        set +e
        out="$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
            bash -c 'enable -n mapfile readarray 2>/dev/null; . "$0"' "$hook" 2>&1)"
        code=$?
        set -e
        if [[ "$command" == "echo hi" ]]; then
            [[ "$code" -eq 0 && -z "$out" ]] \
                || fail prevent-destructive-commands.sh "bash3: $command" "expected exit 0 and no output, got $code '${out:0:120}'"
        else
            [[ "$out" == *"guarded path:"* && "$code" -eq 0 && "$out" == *'"permissionDecision"'*ask* ]] \
                || fail prevent-destructive-commands.sh "bash3: $command" "expected ask with 'guarded path:', got $code '${out:0:120}'"
        fi
    done
    for banned in 'mapfile' 'readarray' '[-1]' 'declare -A' 'local -A'; do
        CASES=$((CASES + 1))
        if grep -qF -e "$banned" "$hook"; then
            fail prevent-destructive-commands.sh "bash3-static" "the hook holds '$banned', a bash 4+ construct"
        fi
    done
}

# X22: the resolver-failed deny must not carry the resolver-success deny text.
run_shell_guard_reason_split_case() {
    local tmp out verdict
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    printf 'import sys\nsys.exit(1)\n' > "$tmp/shell_targets.py"
    CASES=$((CASES + 1))
    out="$(shell_guard_probe "$tmp" "" "touch .claude/.tdd-red/m")"
    verdict="${out%%$'\n'*}"
    if [[ "$verdict" != deny ]]; then
        fail prevent-destructive-commands.sh "reason-split" "expected deny, got $verdict"
    elif [[ "$out" != *"shell guard unavailable"* ]]; then
        fail prevent-destructive-commands.sh "reason-split" "reason does not contain 'shell guard unavailable'"
    elif [[ "$out" == *"is written only by tdd-prove-red.sh"* ]]; then
        fail prevent-destructive-commands.sh "reason-split" "reason holds the resolver-success deny text"
    fi
    rm -r "$tmp"
}

# X23: no .cwd and no CLAUDE_PROJECT_DIR (a manual run): the base is $PWD, not empty.
run_shell_guard_no_base_case() {
    local tmp out code
    tmp="$(mktemp -d)"
    CASES=$((CASES + 1))
    set +e
    out="$(cd "$tmp" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo x > app/api/routes.py"}}' \
        | env -u CLAUDE_PROJECT_DIR CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/prevent-destructive-commands.sh" 2>&1)"
    code=$?
    set -e
    [[ "$code" -eq 0 && -z "$out" ]] \
        || fail prevent-destructive-commands.sh "no-base" "expected exit 0 and no output, got $code '${out:0:120}'"
    rm -r "$tmp"
}

set -e
run_fixture_sweep
if [[ "${1:-}" != --fixtures-only ]]; then
    run_harness_reproduction
    run_harness_edges
    run_missing_jq_cases
    run_guarded_cases
    run_guarded_hardening_cases
    run_shell_guard_cases
    run_shell_guard_failure_cases
    run_shell_guard_budget_case
    run_shell_guard_bash3_case
    run_shell_guard_reason_split_case
    run_shell_guard_no_base_case
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
