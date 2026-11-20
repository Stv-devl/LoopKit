#!/usr/bin/env bash
# Usage: loop-pr-state.sh [--chain] <branch>
#
# The closing rule of a pass whose PR awaits merge (docs/specs/loop-to-pr.md, step 6). Prints
# exactly one word and exits 0:
#   open              the PR is open
#   closable          merged into the default branch
#   stacked:<base>    merged into another feature branch (without --chain)
#   closed            closed unmerged
#   none              no PR for the branch
#   unknown           gh missing, unauthenticated or failing
#   orphaned:<base>   (--chain) merged into <base> after <base> itself had merged: the commits
#                     never reached the default branch
# --chain follows each stacked hop and prints `closable` only when every hop merged into the next
# before that next one merged. Reads only; writes nothing.

set -u

chain=0
if [[ "${1:-}" == --chain ]]; then
    chain=1
    shift
fi
if [[ $# -ne 1 || -z "$1" || "$1" == -* ]]; then
    echo "usage: loop-pr-state.sh [--chain] <branch>" >&2
    exit 2
fi

command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo unknown; exit 0; }

default="$(gh repo view --json defaultBranchRef 2>/dev/null | jq -r '.defaultBranchRef.name // empty' 2>/dev/null)"
[[ -n "$default" ]] || { echo unknown; exit 0; }

# pr_fields <branch>: "<state>\t<base>\t<mergedAt>", `none`, or `unknown`.
pr_fields() {
    local out err rc
    err="$(mktemp)"
    out="$(gh pr view "$1" --json state,baseRefName,mergedAt,number 2>"$err")"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        if grep -qi 'no pull requests found' "$err"; then echo none; else echo unknown; fi
        rm -f "$err"
        return
    fi
    rm -f "$err"
    out="$(jq -r 'select((.state | type) == "string" and (.baseRefName | type) == "string")
        | [.state, .baseRefName, (.mergedAt // "")] | @tsv' <<<"$out" 2>/dev/null)"
    [[ -n "$out" ]] && echo "$out" || echo unknown
}

branch="$1"
merged_at=""
hops=0
while :; do
    fields="$(pr_fields "$branch")"
    if [[ "$fields" == none || "$fields" == unknown ]]; then
        [[ $hops -eq 0 ]] && echo "$fields" || echo "stacked:$branch"
        exit 0
    fi
    IFS=$'\t' read -r state base at <<<"$fields"
    case "$state" in
        OPEN) echo open; exit 0 ;;
        CLOSED) echo closed; exit 0 ;;
        MERGED) ;;
        *) echo unknown; exit 0 ;;
    esac
    if [[ $hops -gt 0 && ( -z "$at" || -z "$merged_at" || ! "$merged_at" < "$at" ) ]]; then
        echo "orphaned:$branch"
        exit 0
    fi
    if [[ "$base" == "$default" ]]; then
        echo closable
        exit 0
    fi
    if [[ $chain -eq 0 ]]; then
        echo "stacked:$base"
        exit 0
    fi
    hops=$((hops + 1))
    if [[ $hops -gt 20 ]]; then
        echo unknown
        exit 0
    fi
    merged_at="$at"
    branch="$base"
done
