#!/usr/bin/env bash
# Scope of a small ticket (docs/specs/small-lane.md, S5), from inside its worktree.
# Read-only. Prints `ok` and exits 0, or every refusal, one per line, and exits 1.
# The base is the parent of the first commit that added the spec, recomputed at each run.
# Usage: small-scope.sh <name>

set -euo pipefail

SMALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=small-lib.sh
source "$SMALL_DIR/small-lib.sh"

if [[ $# -ne 1 ]]; then
    echo "usage: small-scope.sh <name>" >&2
    exit 2
fi
name="$1"
if ! small_valid_name "$name"; then
    echo "invalid name: $name" >&2
    exit 2
fi
cd "$(git rev-parse --show-toplevel)"
spec="$(small_spec_file "$name")"
spec_commit="$(git log --diff-filter=A --format=%H --reverse -- "$spec" | sed -n 1p)"
if [[ -z "$spec_commit" ]]; then
    echo "no spec commit: $spec" >&2
    exit 2
fi

files="$(git show "$spec_commit:$spec" | small_spec_files -)"
excluded=(-- . ":!$spec" ":!docs/work/small-$name/")
problems=()

while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    grep -Fxq -- "$path" <<<"$files" || problems+=("scope drift: $path")
    if ! verdict="$("$SMALL_DIR/small-paths.sh" "$path")"; then
        problems+=("$verdict")
    fi
done < <({
    git diff --no-renames --name-only "$spec_commit^" "${excluded[@]}"
    git diff --cached --no-renames --name-only "$spec_commit^" "${excluded[@]}"
    git ls-files --others --exclude-standard "${excluded[@]}"
} | sort -u)

if ! git diff --quiet "$spec_commit" -- "$spec" \
    || [[ -n "$(git log --diff-filter=D --format=%H "$spec_commit..HEAD" -- "$spec")" ]]; then
    problems+=("spec edited")
fi

if [[ ${#problems[@]} -gt 0 ]]; then
    printf '%s\n' "${problems[@]}"
    exit 1
fi
echo ok
