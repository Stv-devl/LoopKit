#!/usr/bin/env bash
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
        local ms=$(( $(__cwk_now_ms) - __CWK_T0 ))
        # FILE_PATH is set by every hook that has one; empty is fine.
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$__CWK_T0" "$__CWK_HOOK" "$ms" "$code" "${FILE_PATH:--}" \
            >> "$__CWK_LOG" 2>/dev/null || true
    }
    trap __cwk_record EXIT
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
# Schema and rationale: docs/codex-claude-split-plan.md, "Sonde kit-health".
cwk_log_health_deny() {
    local reason="$1" root="${CLAUDE_PROJECT_DIR:-$PWD}"
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
# error, it is a repo that does not use one).
cwk_bin() {
    local tool="$1" root="${CLAUDE_PROJECT_DIR:-$PWD}"
    if [[ -x "$root/node_modules/.bin/$tool" ]]; then
        printf '%s' "$root/node_modules/.bin/$tool"
        return 0
    fi
    if command -v pnpm &> /dev/null && pnpm exec "$tool" --version &> /dev/null; then
        printf 'pnpm exec %s' "$tool"
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
CWK_TDD_LAYERS="repository|services|mapper|utils"

# Implementation module, matched on a path (Write|Edit hooks).
CWK_TDD_IMPL_RE="(^|[/.])(${CWK_TDD_LAYERS})\.tsx?$"
# Frozen test file, matched on a path (Write|Edit hooks).
CWK_TDD_TEST_RE="(^|[/.])(${CWK_TDD_LAYERS})\.test\.tsx?$"
# Any test-first target named inside a shell command (Bash hook). The trailing
# alternative keeps every *.test.ts* in scope, whatever its layer word.
CWK_TDD_SHELL_TARGET_RE="([./[:space:]\"']|^)(${CWK_TDD_LAYERS})\.tsx?|\.test\.tsx?"
# A frozen test file named inside a shell command (Bash hook).
CWK_TDD_SHELL_FROZEN_TEST_RE="([./[:space:]\"']|^)(${CWK_TDD_LAYERS})\.test\.tsx?"

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
# do not occur. The layer names mirror TEST_FIRST_DIRS / MODULE_ROOT in
# addons/fastapi/hooks/tdd_py_lib.py — change them together.
# Both spellings of the layer, exactly as tdd_py_lib.py accepts them: the
# `app/services/` package AND the flat `app/services.py` a small service ends up
# with. Covering only the package would leave the flat one frozen by the hooks
# and writable from the shell — the mismatch is silent, which is the worst kind.
CWK_TDD_PY_TARGET_RE="(^|[/[:space:]\"'])(app/services(/[A-Za-z0-9_./-]*)?\.py|tests/(services/[A-Za-z0-9_./-]*)?test_[A-Za-z0-9_]*\.py)"
