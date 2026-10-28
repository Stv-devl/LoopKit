#!/usr/bin/env bash
# Mechanical eligibility of a small ticket's paths (docs/specs/small-lane.md, S2).
# Read-only. Prints `ok` and exits 0, or prints the first refusal and exits 1.
# Usage: small-paths.sh <repo-relative path>...

set -euo pipefail

# Project foundations refused on top of the built-in ones: bash globs, `*` spans `/`.
FOUNDATIONS=(
)

BUILTIN_FOUNDATIONS=("src/lib" "src/lib/*" "src/main.tsx" "src/routes" "src/routes/*" "src/providers" "src/providers/*")
MAX_PATHS=6

if [[ $# -eq 0 ]]; then
    echo "usage: small-paths.sh <path>..." >&2
    exit 2
fi

if [[ $# -gt $MAX_PATHS ]]; then
    echo "more than $MAX_PATHS paths: $#"
    exit 1
fi

# Whether <path> matches a foundation glob, ignoring case.
is_foundation() {
    local glob found=1
    shopt -s nocasematch
    for glob in "${BUILTIN_FOUNDATIONS[@]}" "${FOUNDATIONS[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$1" == $glob ]]; then
            found=0
            break
        fi
    done
    shopt -u nocasematch
    return "$found"
}

for path in "$@"; do
    if [[ "$path" != src/* || "$path" == *//* || "$path" == */ || "/$path/" == */../* || "/$path/" == */./* ]]; then
        echo "outside small allowlist: $path"
        exit 1
    fi
    if is_foundation "$path"; then
        echo "foundation: $path"
        exit 1
    fi
done

echo ok
