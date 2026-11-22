#!/usr/bin/env bash
# cwk-guard-api: 4
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
# shellcheck disable=SC2034  # read by the sourced hook-lib.sh
CWK_GUARD_HOOK=1
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq
if ! declare -F cwk_config cwk_cfg_reason >/dev/null 2>&1; then
    echo "BLOCKED: hook-lib.sh is older than this hook (no cwk_config/cwk_cfg_reason), so this guard refuses rather than passes. The user re-copies the kit's .claude/hooks/ files from a terminal." >&2
    exit 2
fi
# shellcheck disable=SC2034  # read by hook-lib.sh's exit trap
CWK_DEGRADED_ASK=1

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
    cwk_cfg_reason "${2//\\n/$'\n'}"
    reason="$CWK_CFG_OUT"
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

# The template suffixes that carry no secret come from `.claude/project.json`
# (`env_template_suffixes`), the one list every guard reads: env_template_re builds
# ENV_KEEP_ERE on the first `.env*` name, so no other target spawns the reader.
ENV_KEEP_ERE="$CWK_NEVER_RE"
__ENV_TEMPLATE_LOADED=0
env_template_re() {
    [[ "$__ENV_TEMPLATE_LOADED" == 1 ]] && return 0
    __ENV_TEMPLATE_LOADED=1
    cwk_config || true
    [[ -z "$CWK_CFG_ENV_SUFFIX_ERE" ]] || ENV_KEEP_ERE="^\.env(\..+)?\.(${CWK_CFG_ENV_SUFFIX_ERE})$"
}

SECRET_PATTERNS=(
    "\.pem$"                    # SSL certificates
    "\.key$"                    # Private keys
    "(^|/)\.?credentials(\.|$)" # credentials.json, .credentials.json — anchored,
                                # so a src/features/credentials/ file stays writable
)

# A relative target resolves against the session's cwd, else the project dir.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Each target is also probed by the file it opens: `docs/conf.txt` linked to an
# outside `.env` is a secret under an innocent name. The physical path comes
# from cwk_real_file, never from cwk_real_rel, which prints nothing outside.
PROBES=()
for target in "${TARGETS[@]}"; do
    PROBES+=("$target")
    physical="$(cwk_real_file "$target" "$CWD" 2>/dev/null)" || physical=""
    if [[ -n "$physical" && "$physical" != "$target" ]]; then
        PROBES+=("$physical")
    fi
done

for target in "${PROBES[@]}"; do
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
    [[ ! "$base" =~ ^\.env(\..*)?$ ]] || env_template_re
    if [[ "$base" =~ ^\.env(\..*)?$ ]] && [[ ! "$base" =~ $ENV_KEEP_ERE ]]; then
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
if ! declare -F cwk_guard_rel cwk_is_guarded cwk_is_guard_denied cwk_guard_denied_why cwk_real_file cwk_app_roots \
        cwk_installed cwk_is_kit_code cwk_real_rel >/dev/null 2>&1; then
    deny "BLOCKED: the guarded-path functions are not loaded (hook-lib.sh and protect-files.sh are out of step, or hook-guarded.sh is broken), so this guard refuses rather than passes.\n\nThe user restores the kit from a terminal: git checkout -- .claude/hooks/ (or re-copy .claude/hooks/ from the kit)."
fi
if ! REL=$(cwk_guard_rel "$FILE_PATH" "$CWD"); then
    # Outside the project by name: a link there can still open kit code of an installed project.
    if cwk_installed; then
        REAL_REL=$(cwk_real_rel "$FILE_PATH" "$CWD" 2>/dev/null) || REAL_REL=""
        if [[ -n "$REAL_REL" ]] && cwk_is_kit_code "$REAL_REL"; then
            deny "kit code: $REAL_REL — $CWK_KIT_DENY"
        fi
    fi
    exit 0
fi

if cwk_is_guard_denied "$REL"; then
    deny "BLOCKED: $REL is never written by hand.\n\n$(cwk_guard_denied_why "$REL")"
fi

# Auto mode (docs/specs/auto-mode.md V8), read from the edited file's tree: a `denied` path is
# denied, a `ledgered` one is written without an ask and recorded, `.tdd-unfrozen` needs an
# arbiter `unfreeze` verdict per (path, id), and any other guarded ask becomes a blocked stop —
# nobody answers a prompt in auto mode.
PF_ABS="$FILE_PATH"
[[ "$PF_ABS" == /* ]] || PF_ABS="${CWD:-$PWD}/$PF_ABS"
pf_tree() {
    local d
    d="$(dirname "$PF_ABS")"
    while [[ "$d" != / && ! -d "$d" ]]; do d="$(dirname "$d")"; done
    git -C "$d" rev-parse --show-toplevel 2>/dev/null
}
pf_ledger() {
    jq -c --arg rel "$REL" --arg abs "$PF_ABS" \
        '{loop_record_op: "guarded", path: $rel, abs: $abs, tool: .tool_name, tool_input: .tool_input}' <<<"$INPUT" \
        | python3 -I "$(dirname "${BASH_SOURCE[0]}")/loop-record.py" >/dev/null 2>&1 \
        || deny "auto mode — blocked stop: the write of $REL could not be recorded in the loop record's guarded ledger, so it is not allowed unrecorded."
}
PF_AUTO=0
if [[ "$TOOL_NAME" == Write || "$TOOL_NAME" == Edit ]] && PF_TREE="$(pf_tree)" \
    && [[ -f "$PF_TREE/.claude/.loop-record.json" ]] && cwk_auto_mode "$PF_TREE"; then
    PF_AUTO=1
    PF_CLASS="$(cwk_auto_class "$REL")"
    if [[ "$PF_CLASS" == denied ]]; then
        deny "auto mode — blocked stop: $REL is not written in auto mode (docs/specs/auto-mode.md V8); a pass that needs it ends in a blocked stop."
    fi
    if [[ "$PF_CLASS" == ledgered && "$REL" != .claude/.tdd-unfrozen ]]; then
        pf_ledger
        exit 0
    fi
    if [[ "$REL" != .claude/.tdd-unfrozen ]] && cwk_is_guarded "$REL"; then
        deny "auto mode — blocked stop: $REL would ask (guarded path), and nobody answers a prompt in auto mode."
    fi
fi

# Kit code in an installed project: denied by its name or by the file it opens (a
# symlink alias, dangling or not). The kit repo keeps the guarded ask below.
if cwk_installed; then
    REAL_REL=$(cwk_real_rel "$FILE_PATH" "$CWD" 2>/dev/null) || REAL_REL=""
    if cwk_is_kit_code "$REL"; then
        deny "kit code: $REL — $CWK_KIT_DENY"
    elif [[ -n "$REAL_REL" ]] && cwk_is_kit_code "$REAL_REL"; then
        deny "kit code: $REAL_REL — $CWK_KIT_DENY"
    fi
fi

# A Write/Edit of .tdd-unfrozen that only deletes entries or comments them out
# narrows the freeze's escape hatch: it passes with no prompt. The resulting file is
# computed from the current one; every non-blank resulting line must be a distinct
# current line, as is or prefixed with `#`. Anything else, an absent file or an
# unreadable input keeps the guarded ask below.
unfrozen_removal_only() {
    local abs="$FILE_PATH"
    [[ "$abs" == /* ]] || abs="${CWD:-$PWD}/$abs"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 -I -c '
import json, sys
data = json.load(sys.stdin)
ti = data.get("tool_input") or {}
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        current = fh.read()
except OSError:
    sys.exit(1)
if data.get("tool_name") == "Write":
    result = ti.get("content")
    if not isinstance(result, str):
        sys.exit(1)
else:
    old, new = ti.get("old_string"), ti.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str) or not old or old not in current:
        sys.exit(1)
    result = current.replace(old, new) if ti.get("replace_all") is True else current.replace(old, new, 1)
def file_lines(text):
    return [part[:-1] if part.endswith("\r") else part for part in text.split("\n")]
pool = file_lines(current)
used = [False] * len(pool)
for line in file_lines(result):
    if not line.strip():
        continue
    body = line.lstrip()
    forms = [line]
    if body.startswith("#"):
        forms += [body[1:], body[1:][1:] if body[1:].startswith(" ") else body[1:]]
    for k, cur in enumerate(pool):
        if not used[k] and cur in forms:
            used[k] = True
            break
    else:
        sys.exit(1)
sys.exit(0)
' "$abs" <<<"$INPUT"
}
# A Write/Edit of .tdd-unfrozen whose every added line `<test path>  # <ids>: <reason>` names
# only (path, id) rows of the tree's valid loop record (the frozen cases the user's plan-gate go
# amended) passes with no prompt; removals may share the edit. An absent file counts as empty for
# a Write. A non-test path, a path that is no existing file of the tree (the freeze hook matches a
# row on the repo-relative path; a suffix of it would fall back to the whole-file exemption), an
# unbacked id, a missing or stale record keeps the guarded ask below
# (docs/specs/loop-to-pr.md, step 4).
unfrozen_record_rows() {
    local abs="$FILE_PATH" tree
    [[ "$abs" == /* ]] || abs="${CWD:-$PWD}/$abs"
    command -v python3 >/dev/null 2>&1 || return 1
    tree="$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ "$INPUT" != *.py* ]] || cwk_config >/dev/null 2>&1 || true
    python3 -I -c '
import json, os, re, subprocess, sys
path, tree, tests_root = sys.argv[1], sys.argv[2], sys.argv[3] or "tests"
data = json.load(sys.stdin)
ti = data.get("tool_input") or {}
tool = data.get("tool_name")
try:
    with open(path, encoding="utf-8") as fh:
        current = fh.read()
except FileNotFoundError:
    if tool != "Write" or os.path.lexists(path):
        sys.exit(1)
    current = ""
except OSError:
    sys.exit(1)
if tool == "Write":
    result = ti.get("content")
    if not isinstance(result, str):
        sys.exit(1)
else:
    old, new = ti.get("old_string"), ti.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str) or not old or old not in current:
        sys.exit(1)
    result = current.replace(old, new) if ti.get("replace_all") is True else current.replace(old, new, 1)
def git(*args):
    try:
        done = subprocess.run(["git", "-C", tree, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() if done.returncode == 0 else None
rec_path = os.path.join(tree, ".claude", ".loop-record.json")
if os.path.islink(rec_path) or not os.path.isfile(rec_path):
    sys.exit(1)
try:
    with open(rec_path, encoding="utf-8") as fh:
        rec = json.load(fh)
except (OSError, ValueError):
    sys.exit(1)
if not isinstance(rec, dict) or rec.get("version") != 1 or not isinstance(rec.get("rows"), list):
    sys.exit(1)
head = git("symbolic-ref", "-q", "--short", "HEAD")
if not head:
    sys.exit(1)
if head != rec.get("branch"):
    sha = rec.get("base_sha")
    if head != rec.get("base") or not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        sys.exit(1)
    if git("merge-base", "--is-ancestor", sha, "HEAD") is None:
        sys.exit(1)
rows = {(r.get("path"), r.get("id")) for r in rec["rows"] if isinstance(r, dict)}
refused = set()
if os.environ.get("CWK_AUTO_VERDICTS") == "1":
    found = [v for v in (rec.get("verdicts") or []) if isinstance(v, dict) and v.get("kind") == "frozen-case"]
    rows |= {(v.get("path"), v.get("id")) for v in found if v.get("verdict") == "unfreeze"}
    refused = {(v.get("path"), v.get("id")) for v in found if v.get("verdict") == "refuse"}
line_re = re.compile(r"(\S+)[ \t]+#[ \t]*([UMRB][0-9]+(?:[ \t]*,[ \t]*[UMRB][0-9]+)*)[ \t]*:[ \t]*\S.*")
test_re = re.compile(r"(?:[A-Za-z0-9_.@-]+/)*[A-Za-z0-9_.@-]+\.test\.tsx?|"
                     + r"(?:[A-Za-z0-9_.@-]+/)*" + re.escape(tests_root)
                     + r"/(?:[A-Za-z0-9_.-]+/)*test_[A-Za-z0-9_]*\.py")
def file_lines(text):
    return [part[:-1] if part.endswith("\r") else part for part in text.split("\n")]
pool = file_lines(current)
used = [False] * len(pool)
for line in file_lines(result):
    if not line.strip():
        continue
    body = line.lstrip()
    forms = [line]
    if body.startswith("#"):
        forms += [body[1:], body[1:][1:] if body[1:].startswith(" ") else body[1:]]
    for k, cur in enumerate(pool):
        if not used[k] and cur in forms:
            used[k] = True
            break
    else:
        match = line_re.fullmatch(line.strip())
        if not match:
            sys.exit(1)
        target = match.group(1)
        if not test_re.fullmatch(target) or any(p in ("", ".", "..") for p in target.split("/")):
            sys.exit(1)
        if not os.path.isfile(os.path.join(tree, target)):
            sys.exit(1)
        for case_id in re.split(r"[ \t]*,[ \t]*", match.group(2)):
            if (target, case_id) not in rows or (target, case_id) in refused:
                sys.exit(1)
sys.exit(0)
' "$abs" "$tree" "${CWK_CFG_TESTS_ROOT:-tests}" <<<"$INPUT"
}
if [[ "$PF_AUTO" == 1 && "$REL" == .claude/.tdd-unfrozen ]]; then
    if unfrozen_removal_only || CWK_AUTO_VERDICTS=1 unfrozen_record_rows; then
        pf_ledger
        exit 0
    fi
    deny "auto mode — blocked stop: no unfreeze verdict backs this .tdd-unfrozen entry (every added line needs an arbiter \`unfreeze\` verdict for its test path and each id, and no \`refuse\`)."
fi
if [[ "$REL" == .claude/.tdd-unfrozen && ( "$TOOL_NAME" == Write || "$TOOL_NAME" == Edit ) ]] \
    && { unfrozen_removal_only || unfrozen_record_rows; }; then
    exit 0
fi
if cwk_is_guarded "$REL"; then
    ask "guarded path: $REL (kit guardrail; approve only if you meant to change it)"
fi

exit 0
