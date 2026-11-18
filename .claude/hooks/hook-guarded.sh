#!/usr/bin/env bash
# cwk-guard-api: 8
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
    '.claude/project.json'       # every project value: it widens a pass
    '.claude/project.snapshot.json' # left by an older install.sh in projects that still have one
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
    '.claude/kit-manifest'       # which prompts are kit code in an installed project
)

# Kit code: changed in the LoopKit repo and brought by install.sh. In an installed
# project a write to it is denied (CWK_KIT_DENY); in the kit repo it keeps the guarded
# ask. Every entry but the stamp is also in CWK_GUARDED (PK10).
CWK_KIT_CODE=(
    '.claude/hooks/*'
    '.claude/scripts/*'
    'workflow.py'
    'workflow.sh'
    'codex-handoff.sh'
    'install.sh'
    'addons'
    'addons/*'
    '.claude/project.json'
    '.claude/project.snapshot.json' # an older install.sh's leftover
    '.claude/INSTALL_PROFILE'       # the install stamp
    '.claude/kit-manifest'          # the prompts install.sh shipped
)
CWK_KIT_DENY='kit code changes in the LoopKit repo, then `install.sh`'

# The four prompt dirs. In an installed project the prompts install.sh shipped there are
# kit code: .claude/kit-manifest lists them, and a project's own prompt stays writable.
CWK_KIT_PROMPT_DIRS=(
    '.claude/agents'
    '.claude/commands'
    '.claude/skills'
    '.claude/guides'
)

# __cwk_kit_manifest: print the valid entries of $CLAUDE_PROJECT_DIR/.claude/kit-manifest,
# exit 1 when there is no readable manifest. A line with a character outside
# [A-Za-z0-9._/-], a `.` or `..` segment, or outside the four dirs is ignored.
__cwk_kit_manifest() {
    local project="${CLAUDE_PROJECT_DIR:-}" file line dir
    [[ "$project" == /* ]] || return 1
    file="$project/.claude/kit-manifest"
    [[ -f "$file" && -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[A-Za-z0-9._/-]+$ ]] || continue
        [[ "/$line/" == */../* || "/$line/" == */./* || "$line" == *//* ]] && continue
        for dir in "${CWK_KIT_PROMPT_DIRS[@]}"; do
            if [[ "$line" == "$dir"/?* ]]; then
                printf '%s\n' "$line"
                break
            fi
        done
    done <"$file"
    return 0
}

# cwk_kit_prompt <repo-relative path> [--reach]: exit 0 for a prompt the manifest lists or a
# path under it; with --reach a folder above a listed prompt counts too. No readable manifest
# fails closed: every path under the four dirs counts. Never prints.
cwk_kit_prompt() {
    local rel="$1" reach="${2:-}" entries entry dir
    [[ -n "$rel" && "$rel" != . ]] || return 1
    if entries="$(__cwk_kit_manifest)"; then
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            [[ "$rel" == "$entry" || "$rel" == "$entry"/* ]] && return 0
            [[ "$reach" == --reach && "$entry" == "$rel"/* ]] && return 0
        done <<<"$entries"
        return 1
    fi
    for dir in "${CWK_KIT_PROMPT_DIRS[@]}"; do
        [[ "$rel" == "$dir" || "$rel" == "$dir"/* ]] && return 0
        [[ "$reach" == --reach && "$dir" == "$rel"/* ]] && return 0
    done
    return 1
}

# cwk_kit_patterns: the kit-code patterns, one per line, for a reader that matches them itself
# (the git hook's fnmatch): CWK_KIT_CODE, then in an installed project the manifest's prompts,
# or the four dirs when there is no readable manifest. Manifest entries are literal paths.
cwk_kit_patterns() {
    local entries
    printf '%s\n' "${CWK_KIT_CODE[@]}"
    cwk_installed || return 0
    if entries="$(__cwk_kit_manifest)"; then
        [[ -z "$entries" ]] || printf '%s\n' "$entries"
    else
        printf '%s\n' "${CWK_KIT_PROMPT_DIRS[@]}"
    fi
}

# cwk_installed: exit 0 when $CLAUDE_PROJECT_DIR is a project the kit was installed
# into, 1 for the LoopKit repo itself. Installed = the stamp is present, or install.sh
# and addons/ are not both there; an unset or relative project dir counts as installed.
cwk_installed() {
    local project="${CLAUDE_PROJECT_DIR:-}"
    [[ "$project" == /* ]] || return 0
    [[ -e "$project/.claude/INSTALL_PROFILE" ]] && return 0
    [[ -f "$project/install.sh" && -d "$project/addons" ]] && return 1
    return 0
}

# cwk_is_kit_code <repo-relative path> [--reach]: exit 0 for a kit-code entry or a path
# under it, and in an installed project for a kit prompt (cwk_kit_prompt). With --reach
# (a removal or move operand), a folder above an entry counts too (`.claude`,
# `.claude/hooks`), never `.` itself.
cwk_is_kit_code() {
    local rel="$1" reach="${2:-}" pattern dir
    [[ -n "$rel" && "$rel" != . ]] || return 1
    for pattern in "${CWK_KIT_CODE[@]}"; do
        # shellcheck disable=SC2053  # the pattern is a glob on purpose
        [[ "$rel" == $pattern || "$rel" == "$pattern"/* ]] && return 0
        if [[ "$reach" == --reach ]]; then
            dir="$(__cwk_guard_dir "$pattern")"
            [[ "$pattern" == *[*?[]* ]] || dir="$pattern"
            [[ "$rel" == "$dir" || "$dir" == "$rel"/* ]] && return 0
        fi
    done
    cwk_installed && cwk_kit_prompt "$rel" "$reach" && return 0
    return 1
}

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

# The root config patterns a declared app root (`.claude/project.json` `app_roots`)
# guards under itself, like the repo root does above.
CWK_APP_ROOT_PATTERNS=('vitest.config.*' 'eslint.config.*' 'vite.config.*' 'playwright.config.*'
                       'package.json' 'tsconfig*.json')
__CWK_GUARD_LIB_DIR="${BASH_SOURCE[0]%/*}"
__CWK_APP_ROOTS=()
__CWK_CFG_LOADED=0
CWK_NEVER_RE='[^[:print:][:space:]]{255}'
CWK_CFG_STATUS=0
CWK_CFG_DEGRADED=0
CWK_CFG_REASON=''

# The project's values, read from `.claude/project.json` by `project_config.py shell`, once
# per process and only when a rule asks (cwk_config). Fixed globals, never a nameref.
__cwk_cfg_reset() {
    CWK_CFG_APP_ROOTS=()
    CWK_CFG_PROTECTED_BRANCHES=()
    CWK_CFG_TEST_COMMAND=()
    CWK_CFG_FORMATTER=()
    CWK_CFG_PROTECTED_DIRS_ERE=''
    CWK_CFG_PROTECTED_DIRS_TEXT=''
    CWK_CFG_LINTER=''
    CWK_CFG_ENV_SUFFIX_ERE=''
    CWK_CFG_ICONS_ERE=''
    CWK_CFG_TDD_LAYERS_ERE=''
    CWK_CFG_PY_TARGET_ERE=''
    CWK_CFG_MODULE_ROOT=''
    CWK_CFG_TESTS_ROOT=''
    __CWK_CFG_SEEN=''
}
__cwk_cfg_reset

# shellcheck disable=SC2034  # read by the hooks that source this file
__cwk_cfg_put() {
    local key="${1%%=*}" value="${1#*=}"
    [[ "$1" == *=* ]] || return 1
    case "$key" in
        app_roots) CWK_CFG_APP_ROOTS+=("$value") ;;
        protected_branches) CWK_CFG_PROTECTED_BRANCHES+=("$value") ;;
        test_command) CWK_CFG_TEST_COMMAND+=("$value") ;;
        formatter) CWK_CFG_FORMATTER+=("$value") ;;
        protected_dirs_ere) CWK_CFG_PROTECTED_DIRS_ERE="$value" ;;
        protected_dirs_text) CWK_CFG_PROTECTED_DIRS_TEXT="$value" ;;
        linter) CWK_CFG_LINTER="$value" ;;
        env_suffix_ere) CWK_CFG_ENV_SUFFIX_ERE="$value" ;;
        icons_ere) CWK_CFG_ICONS_ERE="$value" ;;
        tdd_layers_ere) CWK_CFG_TDD_LAYERS_ERE="$value" ;;
        py_target_ere) CWK_CFG_PY_TARGET_ERE="$value" ;;
        module_root) CWK_CFG_MODULE_ROOT="$value" ;;
        tests_root) CWK_CFG_TESTS_ROOT="$value" ;;
        *) return 1 ;;
    esac
    __CWK_CFG_SEEN+=" $key "
}

__cwk_cfg_complete() {
    local key
    for key in protected_dirs_ere protected_dirs_text protected_branches test_command linter \
               env_suffix_ere icons_ere tdd_layers_ere py_target_ere module_root tests_root; do
        [[ "$__CWK_CFG_SEEN" == *" $key "* ]] || return 1
    done
}

# __cwk_cfg_parse <separator>: reads `#status=<n>`, records, `#end=<count>` from stdin.
# Prints nothing; returns the in-band status, or 3 when the frame is incomplete.
__cwk_cfg_parse() {
    local sep="$1" rec status=3 end=-1 count=0 bad=0
    __cwk_cfg_reset
    while IFS= read -r -d "$sep" rec || [[ -n "$rec" ]]; do
        case "$rec" in
            '#status='[0-9]) status="${rec#*=}" ;;
            '#end='*) end="${rec#*=}" ;;
            *) count=$((count + 1)); __cwk_cfg_put "$rec" || bad=1 ;;
        esac
    done
    if [[ "$status" == 0 ]] && { [[ "$end" != "$count" || "$bad" == 1 ]] || ! __cwk_cfg_complete; }; then
        status=3
    fi
    return "$status"
}

# cwk_config: fills the CWK_CFG_* values once per process and returns CWK_CFG_STATUS (0 ok,
# 3 invalid or incomplete, 4 absent, 5 no absolute CLAUDE_PROJECT_DIR, 6 no python3 or no
# reader). On any non-zero status the values are the kit defaults (project-defaults.records)
# and CWK_CFG_DEGRADED=1: a hook then keeps its denies and asks where it would pass.
# shellcheck disable=SC2034  # read by the hooks that source this file
cwk_config() {
    local status=0 dir="${CLAUDE_PROJECT_DIR:-}" reader="$__CWK_GUARD_LIB_DIR/project_config.py"
    if [[ "$__CWK_CFG_LOADED" == 1 ]]; then
        return "$CWK_CFG_STATUS"
    fi
    __CWK_CFG_LOADED=1
    if [[ "$dir" != /* ]]; then
        status=5
    elif ! command -v python3 >/dev/null 2>&1 || [[ ! -f "$reader" ]]; then
        status=6
    else
        __cwk_cfg_parse '' < <(python3 -I -B "$reader" shell "$dir" 2>/dev/null) || status=$?
    fi
    CWK_CFG_STATUS="$status"
    if [[ "$status" != 0 ]]; then
        CWK_CFG_DEGRADED=1
        case "$status" in
            4) CWK_CFG_REASON=".claude/project.json is missing" ;;
            5) CWK_CFG_REASON=".claude/project.json cannot be found: CLAUDE_PROJECT_DIR is not an absolute path" ;;
            6) CWK_CFG_REASON=".claude/project.json cannot be read: python3 or .claude/hooks/project_config.py is missing" ;;
            *) CWK_CFG_REASON=".claude/project.json is invalid or could not be read" ;;
        esac
        CWK_CFG_REASON+=", so the hooks run on the kit defaults and ask instead of passing. Restore it: rerun install.sh on this project, or /kit:init."
        __cwk_cfg_parse $'\n' <"$__CWK_GUARD_LIB_DIR/project-defaults.records" 2>/dev/null || {
            __cwk_cfg_reset
            CWK_CFG_PROTECTED_DIRS_ERE="$CWK_NEVER_RE"
            CWK_CFG_ENV_SUFFIX_ERE="$CWK_NEVER_RE"
            CWK_CFG_ICONS_ERE="$CWK_NEVER_RE"
            CWK_CFG_PY_TARGET_ERE="$CWK_NEVER_RE"
        }
    fi
    return "$status"
}

# cwk_app_roots: fill __CWK_APP_ROOTS from the project's app_roots through cwk_config. A bad
# file gives the defaults (no root), and the hook, degraded, asks where it would pass.
cwk_app_roots() {
    cwk_config || true
    __CWK_APP_ROOTS=(${CWK_CFG_APP_ROOTS[@]+"${CWK_CFG_APP_ROOTS[@]}"})
    return 0
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
    cwk_app_roots
    for dir in ${__CWK_APP_ROOTS[@]+"${__CWK_APP_ROOTS[@]}"}; do
        [[ "$rel" == "$dir" || "$dir" == "$rel"/* ]] && return 0
        for pattern in "${CWK_APP_ROOT_PATTERNS[@]}"; do
            # shellcheck disable=SC2053
            [[ "$rel" == "$dir"/$pattern ]] && return 0
        done
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
