#!/usr/bin/env bash
# kit-lint.sh — the kit repo's local twin of the lint steps in .github/workflows/kit-ci.yml.
#
# /loop:ship runs it from the kit repo's `extra-gates` (.claude/overlays/commands/loop/ship.md),
# so a pass cannot ship green and then fail CI on lint. Same tools, versions, flags and paths
# as kit-ci.yml (test-workflow-contracts.sh K4a/K4b pin the pair), through pinned uvx runners
# so nothing has to be installed system-wide.
#
# Every step runs, even after a failure; one line per step:
#   kit-lint: <step> ok | FAIL (the tool's output above it) | MISSING: <reason>
# MISSING comes only from the runner probe (`--version`), FAIL only from a lint run after a
# passing probe. Exit 0 when every step is ok, 1 otherwise, 2 outside the kit source.
set -uo pipefail

ROOT="${KIT_LINT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SHELLCHECK_RUNNER=(--from shellcheck-py==0.11.0.1 shellcheck)
RUFF_RUNNER=(ruff@0.17.4)
ACTIONLINT_RUNNER=(--from actionlint-py==1.7.12.24 actionlint)

if [[ ! -e "$ROOT/install.sh" || ! -d "$ROOT/addons" || -e "$ROOT/.claude/INSTALL_PROFILE" ]]; then
    echo "kit-lint: kit source only (root install.sh and addons/, no .claude/INSTALL_PROFILE): $ROOT" >&2
    exit 2
fi
cd "$ROOT" || exit 2

STATUS=0
WORK="$(mktemp -d)"
trap 'rm -r "$WORK"' EXIT

# probe <step> <runner...>: prints the MISSING line and returns 1 when the runner cannot run.
probe() {
    local step="$1" out
    shift
    if ! command -v uvx >/dev/null 2>&1; then
        echo "kit-lint: $step MISSING: uvx not found"
        return 1
    fi
    if ! out="$(uvx "$@" --version 2>&1)"; then
        printf '%s\n' "$out"
        echo "kit-lint: $step MISSING: runner failed ($(head -n 1 <<<"$out"))"
        return 1
    fi
    return 0
}

# report <step> <rc> <output>
report() {
    if [[ "$2" -eq 0 ]]; then
        echo "kit-lint: $1 ok"
    else
        printf '%s\n' "$3"
        echo "kit-lint: $1 FAIL"
        STATUS=1
    fi
}

out=""
rc=0
if probe shellcheck "${SHELLCHECK_RUNNER[@]}"; then
    out="$(uvx "${SHELLCHECK_RUNNER[@]}" -S warning .claude/hooks/*.sh .claude/scripts/*.sh 2>&1)"
    rc=$?
    report shellcheck "$rc" "$out"
else
    STATUS=1
fi

if probe ruff "${RUFF_RUNNER[@]}"; then
    out="$(uvx "${RUFF_RUNNER[@]}" check --select E4,E7,E9,F .claude/hooks .claude/scripts 2>&1)"
    rc=$?
    report ruff "$rc" "$out"
else
    STATUS=1
fi

ACTIONLINT_OK=0
if probe actionlint "${ACTIONLINT_RUNNER[@]}"; then
    ACTIONLINT_OK=1
    out="$(uvx "${ACTIONLINT_RUNNER[@]}" .github/workflows/*.yml 2>&1)"
    rc=$?
    report actionlint "$rc" "$out"
else
    STATUS=1
fi

for f in templates/github/publish/*.yml; do
    t="$(basename "$f" .yml)"
    if [[ "$ACTIONLINT_OK" -ne 1 ]]; then
        echo "kit-lint: actionlint-targets:$t MISSING: actionlint runner unavailable"
        continue
    fi
    d="$(mktemp -d "$WORK/target.XXXXXX")"
    if ! out="$(./install.sh "$d" --deploy="$t" </dev/null 2>&1)"; then
        report "actionlint-targets:$t" 1 "$out"
        continue
    fi
    out="$(uvx "${ACTIONLINT_RUNNER[@]}" "$d"/.github/workflows/*.yml 2>&1)"
    rc=$?
    report "actionlint-targets:$t" "$rc" "$out"
done

exit "$STATUS"
