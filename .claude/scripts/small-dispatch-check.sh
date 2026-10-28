#!/usr/bin/env bash
# Dispatch preconditions of a small ticket (docs/specs/small-lane.md, S4), from any
# worktree of the repo. Read-only. Prints `ok` and exits 0, or one refusal line and exits 1.
# Usage: small-dispatch-check.sh <name> <repo-relative path>...

set -euo pipefail

SMALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=small-lib.sh
source "$SMALL_DIR/small-lib.sh"

MAX_TRACKS=3

if [[ $# -lt 2 ]]; then
    echo "usage: small-dispatch-check.sh <name> <path>..." >&2
    exit 2
fi
name="$1"
if ! small_valid_name "$name"; then
    echo "invalid name: $name" >&2
    exit 2
fi
shift
files=("$@")

refuse() {
    echo "$1"
    exit 1
}

main_tree="$(small_main_tree)"
cd "$main_tree"

in_loop_slugs() {
    [[ -f docs/product/backlog.md ]] || return 0
    python3 -B - "$SMALL_DIR/../hooks/next-feature-on-clear.py" docs/product/backlog.md <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("next_feature_on_clear", sys.argv[1])
board = importlib.util.module_from_spec(spec)
spec.loader.exec_module(board)
for row in board.board_rows(Path(sys.argv[2])):
    entry = row.get("Entry artifact", "")
    if row.get("State") == "IN LOOP" and entry not in ("", "—"):
        print(board.loop_slug(entry))
PY
}

plan_files() {
    local line cell part
    local -a parts
    while IFS= read -r line; do
        [[ "$line" == \|* ]] || continue
        cell="${line#|}"
        cell="${cell%%|*}"
        if [[ "$cell" == *\`* ]]; then
            while [[ "$cell" =~ \`([^\`]+)\` ]]; do
                printf '%s\n' "${BASH_REMATCH[1]}"
                cell="${cell#*"${BASH_REMATCH[0]}"}"
            done
            continue
        fi
        IFS=, read -ra parts <<<"$cell"
        for part in "${parts[@]}"; do
            part="${part#"${part%%[![:space:]]*}"}"
            part="${part%"${part##*[![:space:]]}"}"
            [[ -n "$part" && "$part" != Path && "$part" != -* ]] && printf '%s\n' "$part"
        done
    done < <(small_section "$1" Files)
    return 0
}

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || refuse "main tree detached"
dirty=""
IFS= read -r -d '' dirty < <(git status --porcelain -z --untracked-files=all -- src/) || true
[[ -z "$dirty" ]] || refuse "main tree dirty: ${dirty:3}"
for path in "${files[@]}"; do
    [[ -z "$(git status --porcelain -- "$path")" ]] || refuse "main tree dirty: $path"
done

board_slugs="$(in_loop_slugs)" || refuse "board unreadable"
while IFS= read -r slug; do
    [[ -z "$slug" || -d ".claude/worktrees/$slug" ]] || refuse "waits behind main-tree loop $slug"
done <<<"$board_slugs"

if git show-ref --verify --quiet "refs/heads/feat/small-$name" \
    || [[ -e ".claude/worktrees/small-$name" ]] \
    || git cat-file -e "HEAD:$(small_spec_file "$name")" 2>/dev/null; then
    refuse "exists: propose $name-2"
fi

flight_names=()
flight_files=()
for dir in .claude/worktrees/*/; do
    [[ -d "$dir" ]] || continue
    dir="${dir%/}"
    track="${dir##*/}"
    if [[ "$track" == small-* ]]; then
        ticket="${track#small-}"
        spec="$(small_spec_file "$ticket")"
        ref="refs/heads/feat/small-$ticket"
        spec_commit=""
        if git show-ref --verify --quiet "$ref"; then
            spec_commit="$(git log --diff-filter=A --format=%H -n1 "$ref" -- "$spec")"
        fi
        if [[ -z "$spec_commit" ]]; then
            flight_names+=("$track")
            flight_files+=("!no spec commit (failed dispatch)")
            continue
        fi
        base="$(git show "$ref:$spec" | small_spec_base - | awk '{ print $1 }')"
        target="refs/heads/$base"
        git show-ref --verify --quiet "$target" || target="refs/heads/$branch"
        if [[ -n "$base" ]] && git merge-base --is-ancestor "$ref" "$target" 2>/dev/null; then
            continue
        fi
        flight_names+=("$track")
        flight_files+=("$(git show "$ref:$spec" | small_spec_files -)")
    else
        plan="$dir/docs/work/$track/plan.md"
        flight_names+=("$track")
        if [[ -f "$plan" ]]; then
            flight_files+=("$(plan_files "$plan")")
        else
            flight_files+=("!no Files list yet")
        fi
    fi
done

[[ $((${#flight_names[@]} + 1)) -le $MAX_TRACKS ]] || refuse "queued"

for i in "${!flight_names[@]}"; do
    theirs="${flight_files[$i]}"
    [[ "$theirs" != "!"* ]] || refuse "waits behind ${flight_names[$i]}: ${theirs#!}"
    for path in "${files[@]}"; do
        if grep -Fxq -- "$path" <<<"$theirs"; then
            refuse "waits behind ${flight_names[$i]}: $path"
        fi
    done
done

for path in "${files[@]}"; do
    if small_needs_test "$(small_layer "$path")"; then
        printf '%s\n' "${files[@]}" | grep -Fxqf <(small_test_of "$path") || refuse "no test file: $path"
    fi
done

echo ok
