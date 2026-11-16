#!/usr/bin/env bash
# cwk-guard-api: 5
#
# Hook: hook-lib (sourced, never executed)
# Purpose: three things every hook needs and none is worth re-writing per file
#          1. timing   — how long this hook actually cost, appended to a log
#          2. cwk_bin  — resolve a local CLI without paying `pnpm exec`
#          3. cwk_foreign_toolchain — is this file outside the Node toolchain?
#          4. CWK_TDD_LAYERS + its four regexes — the test-first layer words,
#             declared once for every hook that keys on them
#
# Usage, as the FIRST two lines after `set -e`:
#   source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
#
# The timing is the point. A hook that costs 4s is invisible in a transcript —
# it looks like the model thinking. The log is the only place it shows up.
# Read it with: .claude/hooks/hook-timings-report.sh
#

# ------------------------------------------------------------------- timing
# Off with CWK_HOOK_TIMING=0 once the measuring campaign is over. The cost of
# leaving it on is one append of ~80 bytes per hook call.
if [[ "${CWK_HOOK_TIMING:-1}" == "1" ]]; then

    __cwk_now_ms() {
        # EPOCHREALTIME avoids forking `date`. It honours LC_NUMERIC, so a
        # French locale hands back "1755…,123456" — normalise the separator.
        if [[ -n "${EPOCHREALTIME:-}" ]]; then
            local t=${EPOCHREALTIME/,/.}
            printf '%s' "$(( ${t%.*} * 1000 + 10#${t#*.} / 1000 ))"
        else
            date +%s%3N
        fi
    }

    __CWK_T0=$(__cwk_now_ms)
    __CWK_HOOK=$(basename "$0" .sh)
    __CWK_LOG="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.hook-timings.log"

    __cwk_record() {
        local code=$?
        [[ -n "${1:-}" ]] && code="$1"
        local ms=$(( $(__cwk_now_ms) - __CWK_T0 ))
        # FILE_PATH is set by every hook that has one; empty is fine.
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$__CWK_T0" "$__CWK_HOOK" "$ms" "$code" "${FILE_PATH:--}" \
            >> "$__CWK_LOG" 2>/dev/null || true
    }
fi

# ------------------------------------------------------------- degraded mode
# A PreToolUse hook sets CWK_DEGRADED_ASK=1. When the project's config could not be read
# (cwk_config set CWK_CFG_DEGRADED=1 in this shell), every verdict carries the config note:
# a deny stays a deny, an ask stays an ask, and a pass becomes an ask. Each hook's output
# function calls cwk_cfg_reason and marks the decision; the EXIT trap below asks for every
# exit that decided nothing, so no `exit 0` path can pass on an unreadable config.
CWK_DEGRADED_ASK=0
__CWK_DECIDED=0

# cwk_cfg_reason <reason>: sets CWK_CFG_OUT to <reason>, with the config note appended when
# degraded, and marks the hook as decided. Call it in the hook's own shell, never in `$(...)`.
cwk_cfg_reason() {
    __CWK_DECIDED=1
    CWK_CFG_OUT="$1"
    if [[ "${CWK_CFG_DEGRADED:-0}" == 1 ]]; then
        CWK_CFG_OUT+=$'\n\n'"$CWK_CFG_REASON"
    fi
}

__cwk_exit() {
    local code=$?
    if [[ "$code" == 0 && "$CWK_DEGRADED_ASK" == 1 && "$__CWK_DECIDED" != 1 \
          && "${CWK_CFG_DEGRADED:-0}" == 1 ]]; then
        jq -n --arg r "$CWK_CFG_REASON" '{hookSpecificOutput: {hookEventName: "PreToolUse",
            permissionDecision: "ask", permissionDecisionReason: $r}}' 2>/dev/null \
            || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"the project config could not be read"}}\n'
    fi
    if declare -F __cwk_record >/dev/null 2>&1; then
        __cwk_record "$code"
    fi
    return "$code"
}
trap __cwk_exit EXIT

# ------------------------------------------------------------- hook-guarded
# The guarded-path list and its resolver (cwk_guard_rel, cwk_is_guarded,
# cwk_is_guard_denied). A guard hook sets CWK_GUARD_HOOK=1 before sourcing this
# file: without the list it cannot tell a guarded path from any other, and a
# PreToolUse hook that exits 1 or 127 reads as "allow" — so it refuses (exit 2).
# Every other hook only warns: a Stop hook that exits 2 blocks the turn's end,
# again and again.
# "Loaded" means usable: the eight functions exist and both lists are non-empty,
# so an empty or half-renamed file refuses like a missing one.
if ! { source "$(dirname "${BASH_SOURCE[0]}")/hook-guarded.sh" 2>/dev/null \
        && declare -F cwk_guard_rel cwk_is_guarded cwk_is_guard_denied cwk_guard_denied_why \
                      cwk_real_path cwk_real_file cwk_real_rel cwk_app_roots >/dev/null 2>&1 \
        && [[ ${#CWK_GUARDED[@]} -gt 0 && ${#CWK_GUARD_DENIED[@]} -gt 0 ]]; }; then
    if [[ "${CWK_GUARD_HOOK:-0}" == 1 ]]; then
        echo "BLOCKED: hook-guarded.sh missing or broken — the kit's guarded-path list is unusable, so this guard refuses rather than passes. The user restores it from a terminal (git checkout -- .claude/hooks/hook-guarded.sh, or re-copy it from the kit if it was never committed); the agent cannot, every guard hook refuses." >&2
        exit 2
    fi
    echo "WARNING: hook-guarded.sh missing or broken (.claude/hooks/) — guarded paths are unprotected." >&2
fi

# -------------------------------------------------------------- cwk_require_jq
# EVERY guardrail in this directory parses its stdin with `jq`, under `set -e`.
# With jq off PATH the very first `$(… | jq …)` aborts the script at rc 127 — and
# a PreToolUse hook blocks on **exit 2 only**, so 127 reads as "allow". Measured:
# the freeze, the test-first gate and the shell-write guard were all off at once,
# with no message anywhere. `jq` is a README prerequisite that nothing verified.
#
# Fail closed instead. The absence of the parser is not the absence of the rule,
# and exit 2 is the one code that says so on both hook events (it blocks a
# PreToolUse call, and it feeds the message back to the model on a PostToolUse).
#
# Called explicitly rather than at source time: hooks that never touch jq
# (eslint-batch, hook-timings-report) have nothing to fail closed about.
cwk_require_jq() {
    command -v jq &> /dev/null && return 0
    echo "BLOCKED: this repo's guardrail hooks parse their input with jq, and jq is not on PATH." >&2
    echo "Without it the TDD freeze, the test-first gate and the shell-write guard all abort at rc 127, which a PreToolUse hook reads as 'allow'. The tool call is refused rather than silently unguarded." >&2
    echo "Install it: apt install jq  /  brew install jq  /  dnf install jq" >&2
    exit 2
}

# --------------------------------------------------------- cwk_log_health_deny
# One JSON line per REAL refusal — never per invocation, an allowed call says
# nothing a health summary needs. Feeds `.claude/.kit-health.jsonl`, gitignored,
# the same local-only status as the timing log above. Best-effort: a failure to
# append (missing jq, read-only disk) must never turn an observability probe
# into a second reason to block the call the caller already decided to deny.
# Read back, and its schema implied, by kit-doctor.py check_kit_health.
# CWK_HEALTH_LOG=0 turns it off: test-hooks.sh sets it, so fixture denies are
# not recorded as real refusals.
cwk_log_health_deny() {
    local reason="$1" root="${CLAUDE_PROJECT_DIR:-$PWD}"
    [[ "${CWK_HEALTH_LOG:-1}" == 0 ]] && return 0
    command -v jq &> /dev/null || return 0
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg hook "$(basename "$0" .sh)" \
           --arg reason "$reason" \
           --arg file "${FILE_PATH:-}" \
           '{ts: $ts, source: ("hook:" + $hook), event: "deny", reason: $reason, file: $file}' \
        >> "$root/.claude/.kit-health.jsonl" 2>/dev/null || true
}

# ------------------------------------------------------------------ cwk_bin
# `pnpm exec <tool>` costs a Node boot + a workspace resolution before the tool
# even starts — 200-500ms, paid on every single Write. The local bin shim is
# the same binary without that preamble. Falls back to `pnpm exec` so a repo
# with an unusual layout still works, and returns 1 when the tool is absent
# (the caller then skips silently: a formatter that is not installed is not an
# error, it is a repo that does not use one). The resolved argv lands in the array
# CWK_BIN; call it in the hook's own shell, never inside `$(...)`.
CWK_BIN=()
# shellcheck disable=SC2034  # read by the hooks that source this file
cwk_bin() {
    local tool="$1" root="${CLAUDE_PROJECT_DIR:-$PWD}"
    CWK_BIN=()
    [[ -n "$tool" ]] || return 1
    if [[ -x "$root/node_modules/.bin/$tool" ]]; then
        CWK_BIN=("$root/node_modules/.bin/$tool")
        return 0
    fi
    if command -v pnpm &> /dev/null && pnpm exec "$tool" --version &> /dev/null; then
        CWK_BIN=(pnpm exec "$tool")
        return 0
    fi
    return 1
}

# ------------------------------------------------------------- cwk_abs_path
# The TDD marker is named after the file path, and the two hooks that use it
# have to agree on the spelling: tdd-prove-red names it from the TEST file it
# just ran, tdd-require-red looks it up from the IMPLEMENTATION path it was
# handed. If one call carries an absolute path and the other a relative one, the
# names differ, the marker is "missing", and the denial tells the agent to
# re-save a test that was already red — advice that cannot possibly work.
#
# Lexical, never `cd`: the file often does not exist yet (that IS the case
# tdd-require-red guards), and neither does its directory.
cwk_abs_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *)  printf '%s/%s' "${CLAUDE_PROJECT_DIR:-$PWD}" "$1" ;;
    esac
}

# ----------------------------------------------------- cwk_foreign_toolchain
# True when the file belongs to a sub-tree that owns its own toolchain — today
# that means a Deno workspace (a `deno.json` above it), i.e. Supabase edge
# functions. Those files are TypeScript, so every hook keyed on `*.ts` fires on
# them, and every one of those hooks is wrong there:
#
#   - Prettier REWRITES the file, and the tree's own `deno fmt --check` gate
#     then fails on code nobody touched. Measured on the Supabase addon's
#     `_shared/` layer: 6 files of 7 rewritten, 325 lines, gate red.
#   - ESLint parses `npm:` / `jsr:` specifiers it cannot resolve, in a file no
#     tsconfig includes.
#   - The TDD hooks demand a red proved by `pnpm test:run` — vitest, which does
#     not run `Deno.test`. A `supabase/functions/<fn>/utils.ts` would be
#     unwritable until someone found `.claude/.tdd-unfrozen`.
#
# Detected, not configured: the marker file IS the declaration that this tree
# has its own check/lint/fmt/test. Nothing to wire when an addon lands.
#
# The walk is lexical, never `cd`: the file being written often does not exist
# yet — that is precisely the case tdd-require-red.sh guards — and neither does
# its directory when a new function is scaffolded.
cwk_foreign_toolchain() {
    local dir root="${CLAUDE_PROJECT_DIR:-$PWD}"

    case "$1" in
        /*) dir="$(dirname "$1")" ;;
        *) dir="$(dirname "$root/$1")" ;;
    esac

    while [[ -n "$dir" && "$dir" != "/" && "$dir" != "." ]]; do
        if [[ -f "$dir/deno.json" || -f "$dir/deno.jsonc" ]]; then
            return 0
        fi
        [[ "$dir" == "$root" ]] && break
        dir="$(dirname "$dir")"
    done
    return 1
}

# ------------------------------------------------------------- cwk_segments
# Split a command line into the individual commands it chains, WITHOUT splitting
# inside a quoted string. Prints one segment per line.
#
# The naive `tr ';&|\n' '\n\n\n\n'` this replaces was a hole, not a shortcut. An
# ordinary in-place edit carries its `|` inside the expression:
#
#     sed -i 's/(foo|bar)/baz/' features/x/services/x.utils.test.ts
#
# tr cut that into `sed -i 's/(foo` and `bar)/baz/' …x.utils.test.ts`, and every
# rule that wanted "an in-place sed naming a frozen test" then saw two halves,
# neither of which matched. Measured: `>`, `tee` and a plain `sed -i` all denied,
# while `sed -i 's/a|b/c/'`, `sed -i 's/foo/&bar/'` and `perl -pi -e` rewrote a
# frozen test with no deny and not even an `ask`.
#
# `>|` (the noclobber-override redirection) is a single operator, not a pipe, and
# is deliberately kept inside its segment for the same reason.
#
# Best-effort, like every rule that consumes it: it reads the command as text, so
# a target behind a variable is still invisible. What it closes is the split.
cwk_segments() {
    printf '%s' "$1" | awk '
    BEGIN { sq = 0; dq = 0; buf = "" }
    {
        line = $0
        n = length(line)
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (c == "\\" && dq && i < n) { buf = buf c substr(line, i + 1, 1); i++; continue }
            if (c == "'"'"'" && !dq) { sq = !sq; buf = buf c; continue }
            if (c == "\"" && !sq)    { dq = !dq; buf = buf c; continue }
            if (!sq && !dq && c == "|" && substr(buf, length(buf), 1) == ">") { buf = buf c; continue }
            if (!sq && !dq && (c == ";" || c == "&" || c == "|")) { print buf; buf = ""; continue }
            buf = buf c
        }
        if (sq || dq) { buf = buf "\n" } else { print buf; buf = "" }
    }
    END { if (buf != "") print buf }
    '
}

# --------------------------------------------------------- CWK_TDD_LAYERS
# THE FOUR TEST-FIRST LAYER WORDS, DECLARED ONCE.
# Rule: .claude/rules/05-testing.md, "Test-first — scope and rules".
#
# Before this block the list lived in seven places: three TDD hooks, two rules
# inside prevent-destructive-commands.sh, and two globs in
# templates/tooling-config.md. Six of those seven are shell and now read the
# variables below. That matters more than the tidiness: the freeze and the
# coverage floor are required to cover *the same set* of files, and a list
# retyped seven times is the one that drifts silently — a word added to the
# hooks and not to the globs produces a file that is frozen and unmeasured,
# which 05-testing.md calls the worst combination available.
#
# The seventh copy cannot be shared: tooling-config.md emits a vite config, and
# a TS file cannot read a bash variable. It is marked there as the only copy
# outside this file, and it names this constant.
#
# Two boundary classes, deliberately different:
#   - PATH form: the layer word is preceded by `/`, `.` or nothing, and the
#     path ENDS there. `a.utils.ts` and a bare `utils.ts` match; `dateutils.ts`
#     and `microservices.ts` do not.
#   - SHELL form: the same words matched inside a command line, so the class
#     also admits a space and a quote, and it cannot anchor on end-of-path.
#   The words come from `.claude/project.json` (`tdd_layers`) through cwk_tdd_load below:
#   every reader calls it before the first use. Until then all five regexes (the two PATH
#   and the three shell/python ones) match EVERYTHING: a consumer from an older kit (which
#   never calls cwk_tdd_load) then denies instead of passing silently.
CWK_TDD_LAYERS=''
# shellcheck disable=SC2034  # read by the hooks that source this file
CWK_TDD_IMPL_RE='^'
# shellcheck disable=SC2034  # read by the hooks that source this file
CWK_TDD_TEST_RE='^'
# shellcheck disable=SC2034  # read by the hooks that source this file
CWK_TDD_SHELL_TARGET_RE='^'
# shellcheck disable=SC2034  # read by the hooks that source this file
CWK_TDD_SHELL_FROZEN_TEST_RE='^'
# Any test file, TypeScript or Python, on a path relative to the project root:
# what tdd-freeze-tests.sh freezes and what a shell tool option may never write.
# shellcheck disable=SC2034  # read by the hooks that source this file
CWK_TEST_FILE_RE='\.(test|spec|test-d)\.[cm]?[jt]sx?$|(^|/)(test_[^/]*|[^/]*_test|conftest)\.py$'

# ------------------------------------------------------ CWK_TDD_PY_TARGET_RE
# The Python test-first cycle (fastapi addon), for the ONE rule that has to know
# about it: writing those files from the shell.
#
# The three Python hooks are registered on Write|Edit like their TypeScript
# twins, so a redirection bypasses all three in exactly the same way — and
# measured, it did: `cat > app/services/project.py <<EOF` created the module with
# no marker, and `echo x > tests/services/test_project.py` rewrote a frozen test,
# both silently, while the TypeScript equivalents were denied. Closing one door
# and leaving the other open is worse than leaving both open, because the rule
# reads as covered.
#
# Kept in this file rather than in the addon because the rule that consumes it is
# a core hook, and inert on a repo with no Python service layer: the paths simply
# do not occur. cwk_tdd_load fills it from `py_target_ere`, which project_config.py
# derives from `fastapi.module_root`, `tests_root` and `test_first_dirs`: one source.
# Both spellings of the layer, exactly as tdd_py_lib.py accepts them: the
# `<module_root>/<dir>/` package AND the flat `<module_root>/<dir>.py` a small service
# ends up with. Covering only the package would leave the flat one frozen by the hooks
# and writable from the shell — the mismatch is silent, which is the worst kind.
# shellcheck disable=SC2034  # read by the hooks that source this file
CWK_TDD_PY_TARGET_RE='^'
__CWK_TDD_LOADED=''

# cwk_tdd_load: refills the CWK_TDD_* regexes from `.claude/project.json` (`tdd_layers`,
# `py_target_ere`) through cwk_config, once per process. Returns 1 when the config is
# degraded: the regexes then hold the kit defaults, and the hook asks where it would pass.
# shellcheck disable=SC2034  # read by the hooks that source this file
cwk_tdd_load() {
    local rc=0
    if [[ -n "$__CWK_TDD_LOADED" ]]; then
        return "$__CWK_TDD_LOADED"
    fi
    cwk_config || rc=$?
    __CWK_TDD_LOADED=0
    [[ "$rc" == 0 ]] || __CWK_TDD_LOADED=1
    if [[ -z "$CWK_CFG_TDD_LAYERS_ERE" || -z "$CWK_CFG_PY_TARGET_ERE" ]]; then
        CWK_TDD_LAYERS=''
        CWK_TDD_IMPL_RE="$CWK_NEVER_RE"
        CWK_TDD_TEST_RE="$CWK_NEVER_RE"
        CWK_TDD_SHELL_TARGET_RE="$CWK_NEVER_RE"
        CWK_TDD_SHELL_FROZEN_TEST_RE="$CWK_NEVER_RE"
        CWK_TDD_PY_TARGET_RE="$CWK_NEVER_RE"
        __CWK_TDD_LOADED=1
        return 1
    fi
    CWK_TDD_LAYERS="$CWK_CFG_TDD_LAYERS_ERE"
    CWK_TDD_IMPL_RE="(^|[/.])(${CWK_TDD_LAYERS})\.tsx?$"
    CWK_TDD_TEST_RE="(^|[/.])(${CWK_TDD_LAYERS})\.test\.tsx?$"
    CWK_TDD_SHELL_TARGET_RE="([./[:space:]\"']|^)(${CWK_TDD_LAYERS})\.tsx?|\.test\.tsx?"
    CWK_TDD_SHELL_FROZEN_TEST_RE="([./[:space:]\"']|^)(${CWK_TDD_LAYERS})\.test\.tsx?"
    CWK_TDD_PY_TARGET_RE="$CWK_CFG_PY_TARGET_ERE"
    return "$__CWK_TDD_LOADED"
}
