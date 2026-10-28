#!/usr/bin/env bash
#
# Hook: protect-files
# Event: PreToolUse (Write|Edit), PreToolUse (Read), PreToolUse (Grep|Glob)
# Purpose: Prevent modification of critical files — and, on any read-shaped tool,
#          prevent the reading of secrets.
#
# WHY Grep AND Glob ARE ON THIS LIST. They were not, and that was the whole hole:
# `Read .env` was denied here, `cat .env` was denied by
# prevent-destructive-commands.sh (about forty verbs, plus `<`, `--env-file` and
# the `.` builtin) — and then `Grep(path: ".env", output_mode: "content")` handed
# the values over with nothing in the way. Blocking a file from two of its three
# doors is not blocking it.
#
# Those tools do not carry `file_path`, which is why widening the matcher alone
# would have changed nothing: Grep names its target with `path` + `glob`, Glob
# with `pattern` + `path`. All of them are collected below.
#
# Limit, stated rather than hidden: a Grep aimed at a DIRECTORY that happens to
# contain a secret is not denied — the target named is the directory. In practice
# ripgrep honours .gitignore, and `.env` is in it (see this kit's .gitignore), so
# the file is skipped at the source. What this hook closes is the explicit aim.
#
# The two events do NOT get the same list, and that distinction is the point.
# A lock file, `node_modules/` and `.git/` must never be *written* by an agent;
# reading them is ordinary work (checking an installed version is exactly what
# `patterns/forms.md` asks for). Applying the write list to Read denied those
# reads with a message about modification, which reads as a bug and pushes the
# agent toward the shell.
#
# Secrets are refused on both: a value you cannot write is a value you must not
# read either.
#

set -e
CWK_GUARD_HOOK=1
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

# Read JSON from stdin
INPUT=$(cat)

# Extract which tool asked, and every field it can name a target with.
#
#   Write/Edit/Read : file_path
#   Grep            : path (file or directory) + glob (a filter)
#   Glob            : pattern (a path pattern) + path
#
# `pattern` is taken ONLY for Glob. On Grep it is the regex being searched FOR,
# and looking for the string ".env" across the codebase is ordinary work — a
# hook that denied it would be denying a search, not protecting a secret.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

TARGETS=()
[[ -n "$FILE_PATH" ]] && TARGETS+=("$FILE_PATH")
while IFS= read -r t; do
    [[ -n "$t" ]] && TARGETS+=("$t")
done < <(echo "$INPUT" | jq -r '[.tool_input.path, .tool_input.glob] | .[] | select(. != null and . != "")')
if [[ "$TOOL_NAME" == "Glob" ]]; then
    while IFS= read -r t; do
        [[ -n "$t" ]] && TARGETS+=("$t")
    done < <(echo "$INPUT" | jq -r '.tool_input.pattern // empty')
fi

# Nothing named → nothing to judge.
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    exit 0
fi

# Built with jq, never with a heredoc: this function interpolates $FILE_PATH into
# the reason, and a path containing a `"` produced unparseable JSON. Unparseable
# JSON is DROPPED, so the deny disappeared silently — a protected file would have
# been written with no message at all. The `${x//\\n/}` expansion turns the authored `\n`
# into real newlines and leaves every other backslash alone.
decide() {
    local reason
    reason="${2//\\n/$'\n'}"
    jq -n --arg d "$1" --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: $d,
        permissionDecisionReason: $r
      }
    }'
    exit 0
}
deny() { decide deny "$1"; }
ask() { decide ask "$1"; }

# =============================================================================
# SECRETS — refused whatever the tool, and on EVERY field that names a target
# =============================================================================

# CONFIGURE: the template suffixes that carry no secret. This list is duplicated
# in prevent-destructive-commands.sh (SECRET_RE sanitizer) — change both, or the
# two guards stop protecting the same set.
ENV_TEMPLATE_RE='\.(example|sample|template)$'

SECRET_PATTERNS=(
    "\.pem$"                    # SSL certificates
    "\.key$"                    # Private keys
    "(^|/)credentials(\.|$)"    # credentials.json & co — anchored, so a
                                # src/features/credentials/ file stays writable
)

for target in "${TARGETS[@]}"; do
    # Two probes per target, because a glob hides the secret in two different
    # places and stripping for one blinds the other:
    #
    #   `.env*`, `**/.env*`  → the name is a PREFIX. Take the basename and drop
    #                          the trailing wildcard: `.env`.
    #   `*.key`, `**/*.pem`  → the name is a SUFFIX, and the wildcard is on the
    #                          left. Nothing may be stripped — the suffix
    #                          patterns are anchored on `$` and match as-is.
    #
    # Cutting at the FIRST `*` handled the prefix form and silently emptied the
    # suffix form, which let `Glob **/*.pem` and `Grep --glob *.key` straight
    # through. Both probes are kept, and each pattern is tested against the one
    # it can actually see.
    base="${target##*/}"
    base="${base%\*}"
    base="${base%/}"

    # Every `.env`, `.env.<anything>` — minus the templates above. Enumerating the
    # known suffixes (`.local`, `.production`, …) always misses one, and the previous
    # shortcut for "anything but .example" was `\.env\.[^e]`, which silently let
    # `.env.e2e` and `.env.enc` through.
    if [[ "$base" =~ ^\.env(\..*)?$ ]] && [[ ! "$base" =~ $ENV_TEMPLATE_RE ]]; then
        deny "Protected target: '$target' names environment secrets.\n\nThis is refused on every tool that can surface the contents — Read, Grep, Glob, Write, Edit — and prevent-destructive-commands.sh refuses it from the shell.\n\nAsk the user for the variable NAMES (never the values), or read .env.example."
    fi

    for pattern in "${SECRET_PATTERNS[@]}"; do
        if [[ "$target" =~ $pattern ]]; then
            deny "Protected target: '$target' is a key or a credentials file.\n\nIt is never read and never written by an agent, and never searched either. Work from .env.example and from the usage sites."
        fi
    done
done

# =============================================================================
# WRITE-ONLY — reading these is legitimate, writing them is not
# =============================================================================

# The read-shaped tools stop here: a lock file, `node_modules/` and `.git/` are
# ordinary things to read, search and list. Anything else — including a tool this
# hook has never heard of — falls through to the write list. Failing closed is
# the safe direction.
if [[ "$TOOL_NAME" == "Read" || "$TOOL_NAME" == "Grep" || "$TOOL_NAME" == "Glob" ]]; then
    exit 0
fi

WRITE_PROTECTED_PATTERNS=(
    "pnpm-lock\.yaml$"          # Lock file
    "package-lock\.json$"       # npm lock file
    "yarn\.lock$"               # yarn lock file
    "bun\.lock(b)?$"            # bun lock file
    "\.git/"                    # Git internals
    "node_modules/"             # Dependencies
)

for pattern in "${WRITE_PROTECTED_PATTERNS[@]}"; do
    if [[ "$FILE_PATH" =~ $pattern ]]; then
        deny "Protected file: cannot modify '$FILE_PATH'\n\nThis file is protected to prevent accidental changes:\n• lock files - only a package manager writes them\n• .git/ - Git internal files\n• node_modules/ - managed by the package manager\n\nReading them is allowed; this block is on the write."
    fi
done

# =============================================================================
# GUARDED — the kit's own guardrails: asked, never silently written
# =============================================================================

# The list and the resolver live in hook-guarded.sh (sourced by hook-lib.sh).
# A relative file_path resolves against the session's cwd from the input, never
# against this process's directory. Outside the project: nothing to guard.
if ! declare -F cwk_guard_rel cwk_is_guarded cwk_is_guard_denied >/dev/null 2>&1; then
    deny "BLOCKED: the guarded-path functions are not loaded (hook-lib.sh and protect-files.sh are out of step, or hook-guarded.sh is broken), so this guard refuses rather than passes.\n\nThe user restores the kit from a terminal: git checkout -- .claude/hooks/ (or re-copy .claude/hooks/ from the kit)."
fi
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
REL=$(cwk_guard_rel "$FILE_PATH" "$CWD") || exit 0

if cwk_is_guard_denied "$REL"; then
    deny "BLOCKED: .claude/.tdd-red/ is written only by tdd-prove-red.sh — a hand-written RED marker lets a module in with no observed failing test.\n\nWrite the test, run it, and let the PostToolUse hook record the RED it sees."
fi
if cwk_is_guarded "$REL"; then
    ask "guarded path: $REL (kit guardrail; approve only if you meant to change it)"
fi

exit 0
