#!/usr/bin/env bash
# Shared helpers of the small-lane scripts (docs/specs/small-lane.md). Sourced, never run.
# Read-only: every function prints to stdout and writes nothing.

SMALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWK_HOOK_TIMING=0
# shellcheck source=../hooks/hook-lib.sh
source "$SMALL_LIB_DIR/../hooks/hook-lib.sh"

# The small spec of ticket <name>, repo-relative.
small_spec_file() {
    printf 'docs/specs/small/%s.md' "$1"
}

# The body of section `## <heading>` of a markdown file (or stdin with `-`).
small_section() {
    awk -v h="## $2" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$1"
}

# The paths of a spec's `## Files` list, one per line.
small_spec_files() {
    small_section "$1" Files | sed -n 's/^- //p'
}

# The `Base:` line of a spec: `<branch> <sha>`.
small_spec_base() {
    sed -n 's/^Base: //p' "$1" | head -n1
}

# The write-chain layer of a path: test, types, schemas, errors, gateway, utils,
# mapper, repository, hooks, store, forms, components, or unmapped.
small_layer() {
    local path="$1" base="${1##*/}"
    case "$base" in
        *.test.ts | *.test.tsx) echo test; return ;;
        types.ts | *.types.ts) echo types; return ;;
        schemas.ts | *.schema.ts | *.schemas.ts) echo schemas; return ;;
        *.errors.ts) echo errors; return ;;
        *.gateway.ts) echo gateway; return ;;
    esac
    if [[ "$path" =~ $CWK_TDD_IMPL_RE ]]; then
        case "${BASH_REMATCH[2]}" in
            services | repository) echo repository ;;
            *) echo "${BASH_REMATCH[2]}" ;;
        esac
        return
    fi
    case "$base" in
        hooks.ts | use*.ts | use*.tsx) echo hooks ;;
        *.store.ts) echo store ;;
        *Form.tsx | *.form.tsx) echo forms ;;
        *.tsx) echo components ;;
        *) echo unmapped ;;
    esac
}

# The test files that cover module <path>, one per line: `<base>.test.ts` and `<base>.test.tsx`.
small_test_of() {
    printf '%s.test.ts\n%s.test.tsx\n' "${1%.*}" "${1%.*}"
}

# Whether a layer needs a test file: a test-first layer word of the hook lib, or hooks.
small_needs_test() {
    local layer="$1" word
    [[ "$layer" == hooks ]] && return 0
    for word in ${CWK_TDD_LAYERS//|/ }; do
        [[ "$word" == "$layer" ]] && return 0
    done
    return 1
}

# Whether <name> is a valid ticket name: lowercase letters, digits and dashes, no leading dash.
small_valid_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

# The main tree: the first worktree git lists.
small_main_tree() {
    git worktree list --porcelain | sed -n '1s/^worktree //p'
}
