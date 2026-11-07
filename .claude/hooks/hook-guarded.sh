#!/usr/bin/env bash
# cwk-guard-api: 3
#
# Library: hook-guarded (sourced, never executed)
# Purpose: the ONE list of paths the kit's guardrails rely on — their own files,
#          their escape hatches, the RED markers, the gate configs — and the
#          resolver that turns whatever a tool names into a repo-relative path.
#
# Who reads it: hook-lib.sh sources it for every hook; protect-files.sh asks on a
# Write/Edit of a guarded path and denies one under .claude/.tdd-red/. Any other
# reader (a shell hook, a .claude/scripts/ tool) calls cwk_is_guarded — it never
# copies the list, or the two copies drift and one door stays open.
#
# No side effect when sourced: variables and functions only. No trap, no log, no
# output, no shopt/set change — scripts that must stay read-only source it too.
#
# Matching is plain `[[ $rel == $pattern ]]`: `*` crosses `/`, so a pattern can
# over-match (`tsconfig*.json` also takes `tsconfig/x.json`), never under-match.

CWK_GUARDED=(
    '.claude/hooks/*'            # every hook, hook-lib, this file, the fixtures
    '.claude/scripts/*'          # kit scripts
    '.claude/settings.json'
    '.claude/settings.local.json'
    '.claude/.tdd-unfrozen'      # the freeze's escape hatch
    '.claude/.size-exempt'       # the size limits' escape hatch
    'vitest.config.*'
    'eslint.config.*'            # the lint that forbids assertionless tests
    'vite.config.*'              # the coverage floor lives here
    'playwright.config.*'        # where the e2e gate runs and writes
    'package.json'               # the gate scripts
    'tsconfig*.json'
    '.github/workflows/*'        # CI repeats the gates
    'install.sh'                 # the kit-dev suites run these root files
    'workflow.py'
    'workflow.sh'
    'codex-handoff.sh'
    'addons/*'                   # the allowed test-hooks.sh runs addons/fastapi/hooks/*.py
)

# Never written by a tool call, whoever asks. Only tdd-prove-red.sh writes a RED
# marker, from a hook process PreToolUse never sees: a hand-written one lets a
# module in with no observed failing test. `.git` is git's own store: only git
# commands change it, and a delete or overwrite loses the history.
CWK_GUARD_DENIED=(
    '.claude/.tdd-red/*'
    '.git/*'
)

# cwk_guard_denied_why <repo-relative path>: why a denied path is never written by hand.
cwk_guard_denied_why() {
    case "$1" in
        .git | .git/*)
            printf '%s' ".git is git's own store: history, refs and config, changed only by git commands; deleting or overwriting it loses the history."
            ;;
        *)
            printf '%s' ".claude/.tdd-red/ is written only by tdd-prove-red.sh: the marker proves a RED, a test that failed before its module existed; a hand-written one lets a module in with no observed failure (.claude/rules/05-testing.md)."
            ;;
    esac
}

# The folder a pattern lives in: its text up to the first glob character, cut
# back to the last `/` (`.claude/hooks/*` → `.claude/hooks`, `vite.config.*` → `.`).
__cwk_guard_dir() {
    local fixed="${1%%[*?[]*}"
    if [[ "$fixed" == */* ]]; then
        printf '%s' "${fixed%/*}"
    else
        printf '.'
    fi
}

# cwk_is_guarded <repo-relative path>: exit 0 when the path is guarded, 1 otherwise.
# A folder that holds a guarded pattern, or any folder above one (`.claude`,
# `.github`, `.`), is guarded too: removing or overwriting it reaches the files.
cwk_is_guarded() {
    local rel="$1" pattern dir
    [[ -n "$rel" ]] || return 1
    [[ "$rel" == . ]] && return 0
    for pattern in "${CWK_GUARDED[@]}"; do
        # shellcheck disable=SC2053  # the pattern is a glob on purpose
        [[ "$rel" == $pattern ]] && return 0
        dir="$(__cwk_guard_dir "$pattern")"
        [[ "$rel" == "$dir" || "$dir" == "$rel"/* ]] && return 0
    done
    return 1
}

# cwk_is_guard_denied <repo-relative path>: exit 0 for `.claude/.tdd-red`, `.git`
# and everything under them. Their ancestors (`.claude`, `.`) are guarded, not denied.
cwk_is_guard_denied() {
    local rel="$1" pattern
    [[ -n "$rel" ]] || return 1
    for pattern in "${CWK_GUARD_DENIED[@]}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $pattern || "$rel" == "$(__cwk_guard_dir "$pattern")" ]] && return 0
    done
    return 1
}

# Lexical normalisation of an absolute path: `//` and `.` dropped, `..` pops one
# segment (never above `/`). The filesystem is not consulted.
__cwk_guard_norm() {
    local seg out="" rest="$1/"
    local -a kept=()
    # Split by parameter expansion, not `read`: a newline inside a segment must
    # stay inside it (`read` stops at the first line and drops the rest).
    while [[ -n "$rest" ]]; do
        seg="${rest%%/*}"
        rest="${rest#*/}"
        case "$seg" in
            '' | .) ;;
            ..) if [[ ${#kept[@]} -gt 0 ]]; then kept=("${kept[@]:0:${#kept[@]}-1}"); fi ;;
            *) kept+=("$seg") ;;
        esac
    done
    for seg in "${kept[@]}"; do out+="/$seg"; done
    printf '%s' "${out:-/}"
}

# __cwk_guard_strip <path> <root>: the path relative to root (`.` when equal);
# exit 1 when the path is not under root.
__cwk_guard_strip() {
    local path="$1" root="$2"
    [[ -n "$root" ]] || return 1
    if [[ "$path" == "$root" ]]; then
        printf '.'
    elif [[ "$root" == / ]]; then
        printf '%s' "${path#/}"
    elif [[ "$path" == "$root"/* ]]; then
        printf '%s' "${path#"$root"/}"
    else
        return 1
    fi
}

# __cwk_cd_pwd <dir>: set __CWK_PWD to the physical form of a directory (`cd -P`),
# exit 1 when it can't be entered. `$(…)` drops trailing newlines, which would turn
# a folder named `p` + a newline into `p` (and a link to it into the project): a
# sentinel closes the output, then goes, with pwd's own newline. The result is set,
# not printed, so no caller's `$(…)` strips it again.
__cwk_cd_pwd() {
    local out
    out="$(cd -P "$1" 2>/dev/null && { pwd -P; printf x; })" || return 1
    out="${out%x}"
    __CWK_PWD="${out%$'\n'}"
}

# cwk_real_path <path> [<base>]: print the physical absolute form of a path: a
# relative one joins <base> (else the project dir), `..` is applied lexically,
# then the deepest existing parent is resolved with `cd -P`. Exit 1 when it can't be.
cwk_real_path() {
    local path="$1" base="${2:-${CLAUDE_PROJECT_DIR:-}}" dir rest="" resolved out
    [[ -n "$path" ]] || return 1
    if [[ "$path" != /* ]]; then
        [[ "$base" == /* ]] || return 1
        path="$base/$path"
    fi
    dir="$(__cwk_guard_norm "$path")"
    while [[ "$dir" != / && ! -d "$dir" ]]; do
        rest="/${dir##*/}$rest"
        dir="${dir%/*}"
        [[ -n "$dir" ]] || dir=/
    done
    __cwk_cd_pwd "$dir" || return 1
    resolved="$__CWK_PWD"
    out="${resolved%/}$rest"
    # A path ending in a newline cannot cross the caller's `$(…)`: no answer.
    [[ "$out" != *$'\n' ]] || return 1
    printf '%s' "${out:-/}"
}

# cwk_real_file <path> [<base>]: cwk_real_path, then the last component followed
# while it is a symlink (40 hops at most), so a link names the file it opens.
# cwk_real_path alone stops at the link: right for `rm`, which removes the link.
cwk_real_file() {
    local path hops=0 link fdir fbase
    path="$(cwk_real_path "$1" "${2:-}")" || return 1
    while [[ -L "$path" ]]; do
        hops=$((hops + 1))
        [[ "$hops" -le 40 ]] || return 1
        link="$(readlink "$path")" || return 1
        [[ "$link" == /* ]] || link="${path%/*}/$link"
        # `cd -P` hands the path to the kernel: a `..` after a symlinked folder
        # (`ext/../x`) climbs from the folder's target, never lexically.
        if [[ -d "$link" ]]; then
            __cwk_cd_pwd "$link" || return 1
            path="$__CWK_PWD"
            continue
        fi
        fdir="${link%/*}"
        fbase="${link##*/}"
        case "$fbase" in
            '' | . | ..) path="$(cwk_real_path "$link")" || return 1 ;;
            *)
                if __cwk_cd_pwd "${fdir:-/}"; then
                    path="${__CWK_PWD%/}/$fbase"
                else
                    path="$(cwk_real_path "$link")" || return 1
                fi
                ;;
        esac
    done
    [[ "$path" != *$'\n' ]] || return 1
    printf '%s' "$path"
}

# cwk_real_rel <path> [<base>]: the project-relative form of the file a path
# opens, symlinks followed; exit 1 when it lies outside the physical project.
# Unlike cwk_guard_rel, a `.claude/worktrees/<x>/` prefix is kept.
cwk_real_rel() {
    local project real
    [[ "${CLAUDE_PROJECT_DIR:-}" == /* ]] || return 1
    project="$(cwk_real_path "$CLAUDE_PROJECT_DIR")" || return 1
    real="$(cwk_real_file "$1" "${2:-}")" || return 1
    __cwk_guard_strip "$real" "$project"
}

# cwk_guard_rel <path> [<base>]: print the repo-relative form of a path a tool
# named, exit 1 (nothing printed) when it lies outside the project.
#   - a relative path joins <base> — the hook input's `.cwd` — else the project
#     dir; never $PWD, which is the hook process's directory, not the session's
#   - normalised lexically, absolute or not (`src/../vite.config.ts`)
#   - the project dir is matched as given and in its physical form; failing both,
#     the deepest existing parent of the path is resolved, so a symlinked alias
#     of the project still lands inside it
#   - a leading `.claude/worktrees/<x>/` is stripped: a worktree's guardrails are
#     the same files, and acceptEdits does not prompt under that folder
cwk_guard_rel() {
    local path="$1" base="${2:-}" project="${CLAUDE_PROJECT_DIR:-}" physical rel dir rest resolved
    [[ -n "$path" && -n "$project" ]] || return 1
    [[ "$project" == /* ]] || return 1
    project="$(__cwk_guard_norm "$project")"
    [[ -n "$base" ]] || base="$project"
    [[ "$base" == /* ]] || base="$project/$base"
    [[ "$path" == /* ]] || path="$base/$path"
    path="$(__cwk_guard_norm "$path")"
    if __cwk_cd_pwd "$project"; then physical="$__CWK_PWD"; else physical="$project"; fi

    if ! rel="$(__cwk_guard_strip "$path" "$project")" \
        && ! rel="$(__cwk_guard_strip "$path" "$physical")"; then
        dir="$path"
        rest=""
        while [[ "$dir" != / && ! -d "$dir" ]]; do
            rest="/${dir##*/}$rest"
            dir="${dir%/*}"
            [[ -n "$dir" ]] || dir=/
        done
        __cwk_cd_pwd "$dir" || return 1
        resolved="$__CWK_PWD"
        rel="$(__cwk_guard_strip "${resolved%/}$rest" "$physical")" || return 1
    fi

    case "$rel" in
        .claude/worktrees/*/*) rel="${rel#.claude/worktrees/*/}" ;;
        .claude/worktrees/*) rel=. ;;
    esac
    printf '%s' "$rel"
}
