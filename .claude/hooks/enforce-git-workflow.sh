#!/usr/bin/env bash
#
# Hook: enforce-git-workflow
# Event: PreToolUse (Bash)
# Purpose: make the Git convention mechanical instead of declarative.
#
#   deny → committing on a protected branch, signing a commit
#   ask  → anything that touches the remote or merges into a protected branch
#
# The convention itself lives in `.claude/agents/github.md` (the only copy).
# CLAUDE.md keeps one line saying all Git work goes through that agent; this
# hook is what holds when something bypasses it — a `git commit` typed straight
# into Bash never reads either file.
#
# Deliberate limits:
#   - the branch is read from the tool call's cwd, or from each git call's own
#     `-C`. `cd elsewhere && git commit` is best-effort: a bare `cd` is not read.
#   - wrappers that take options (`nice -n 5 git`, `env -i git`, `sudo git`) are
#     not unwrapped; the whole-text rules decide them.
#   - a `$(...)` or `bash -c` string shlex cannot read is skipped, not asked about
#     (a commit message with an apostrophe is the normal case); a top-level
#     command it cannot read, or more than 50 git calls, falls back to word rules.
#   - an `export GIT_DIR=...` (or GIT_WORK_TREE, GIT_CONFIG*) in an earlier
#     statement is not read, like a bare `cd`.
#   - `ask` is not a block. It forces the permission prompt back in front of the
#     user even when the command would otherwise be auto-approved. That IS the
#     validation gate the convention asks for — the agent goes through it too.
#

set -e
CWK_GUARD_HOOK=1
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[[ -z "$COMMAND" ]] && exit 0
[[ -z "$CWD" ]] && CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# Nothing git-shaped in this command → cheapest possible exit.
echo "$COMMAND" | grep -qE '\b(git|gh)\b' || exit 0

# CONFIGURE: branches that only ever receive merges.
PROTECTED_BRANCHES="main|master"

# jq, never a heredoc: the reasons below interpolate $BRANCH, and a branch name
# holding a `"` produced unparseable JSON — dropped by the harness, so the gate
# silently disappeared. Only the authored `\n` is expanded;
# every other backslash is left alone.
decide() {
    local decision="$1" reason
    reason="${2//\\n/$'\n'}"
    jq -n --arg d "$decision" --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: $d,
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

deny() { decide "deny" "$1"; }
ask()  { decide "ask"  "$1"; }

PUSH_REASON="This pushes to a remote. Present the branch, the remote and what is being pushed, then let the user decide."
FORCE_REASON="This is a FORCE push: it overwrites remote history and can destroy commits other people have. Say which branch and why a normal push will not do, then let the user decide."
commit_reason() { printf '%s' "BLOCKED: never commit on '$1'.\\n\\nBranch first, then commit:\\n  git checkout -b feat/<scope>   (or fix/, chore/)\\n\\n'$1' only ever receives merges, and a merge needs the user's go-ahead. A loop track already carries its feat/<slug> branch — use that one. Convention: .claude/agents/github.md"; }
merge_reason() { printf '%s' "This integrates into '$1'. Show the branch, 'git diff --stat' and the exact command, then let the user decide. One merge at a time — never two in flight."; }

# -----------------------------------------------------------------------------
# Two readings of the command
#
# The floor: regexes over the whole text, against the tree of the first
# `git -C` or the cwd. They decide every plain form, wrappers included.
# The segments: each git call parsed on its own — global options skipped, every
# `-C` applied, its own tree, aliases. They add what the floor cannot see.
# -----------------------------------------------------------------------------

BASE_DIR="$CWD"

GIT_DIR_ARG=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+[^ ]+' | head -1 | awk '{print $3}')
[[ -n "$GIT_DIR_ARG" ]] && CWD="$GIT_DIR_ARG"

on_protected_branch() {
    [[ "$HAS_COMMITS" -eq 1 ]] && echo "$BRANCH" | grep -qE "^($PROTECTED_BRANCHES)$"
}

# Sets SEG_BRANCH. True when <dir> has commits and sits on a protected branch.
dir_protected() {
    git -C "$1" rev-parse --verify HEAD >/dev/null 2>&1 || return 1
    SEG_BRANCH=$(git -C "$1" branch --show-current 2>/dev/null || echo "")
    echo "$SEG_BRANCH" | grep -qE "^($PROTECTED_BRANCHES)$"
}

# One line per git call: subcommand, directory, alias-on-command-line, force.
# A command shlex cannot read prints UNPARSABLE.
parse_segments() {
    python3 - "$1" "$2" <<'PY'
import os
import shlex
import sys

WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
              "--config-env", "--exec-path", "--attr-source"}
PREFIXES = {"env", "command", "exec", "time", "nice", "nohup", "setsid", "{", "!",
            "if", "then", "else", "elif", "while", "until", "do"}
SHELLS = {"bash", "sh", "zsh", "dash"}
SEPARATOR_CHARS = set(";&|()\n")
WORD_START = set(" \t\r\n;&|()<>")
HIDDEN = "?hidden"
MAX_GIT_SEGMENTS = 50
rows = []
state = {"capped": False, "unread": False}


def strip_comments(text):
    out, quote, i = [], "", 0
    while i < len(text):
        ch = text[i]
        if quote == "'":
            quote = "" if ch == "'" else quote
        elif ch == "\\" and i + 1 < len(text):
            out.append(ch)
            i += 1
            ch = text[i]
        elif quote == '"':
            quote = "" if ch == '"' else quote
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or text[i - 1] in WORD_START):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def tokens(text):
    lexer = shlex.shlex(strip_comments(text), posix=True, punctuation_chars="();<>|&\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def segments(toks):
    current = []
    for tok in toks:
        if tok and set(tok) <= SEPARATOR_CHARS:
            if current:
                yield current
            current = []
        else:
            current.append(tok)
    if current:
        yield current


def is_assignment(tok):
    name, eq, _ = tok.partition("=")
    return bool(eq) and name.isidentifier()


def is_force(args):
    for arg in args:
        if arg in ("-f", "--force") or arg.startswith(("--force-with-lease", "--force-if-includes")):
            return True
        if arg.startswith("+") and len(arg) > 1:
            return True
        if arg.startswith("-") and not arg.startswith("--") and "f" in arg[1:]:
            return True
    return False


def hides_config(value):
    low = value.lower()
    return low.startswith(("alias.", "include"))


def parse_git(seg, start, base, assigns):
    directory, alias_cfg, i = base, 0, start
    git_dir = work_tree = None
    for assign in assigns:
        name, _, value = assign.partition("=")
        if name == "GIT_DIR":
            git_dir = value
        elif name == "GIT_WORK_TREE":
            work_tree = value
        elif name.startswith("GIT_CONFIG"):
            alias_cfg = 1
    while i < len(seg) and seg[i].startswith("-"):
        opt = seg[i]
        name, eq, value = opt.partition("=")
        if opt in WITH_VALUE:
            value = seg[i + 1] if i + 1 < len(seg) else ""
            i += 2
        else:
            i += 1
            if not eq:
                value = None
        if opt == "-C":
            directory = os.path.join(directory, value)
        if name == "--git-dir" and value is not None:
            git_dir = value
        if name == "--work-tree" and value is not None:
            work_tree = value
        if name in ("-c", "--config-env") and value and hides_config(value):
            alias_cfg = 1
    if i >= len(seg):
        return
    if work_tree:
        directory = os.path.join(directory, work_tree)
    elif git_dir:
        directory = os.path.join(directory, git_dir)
    sub = seg[i]
    if any(ch in sub for ch in "$`'\"{*?[\n"):
        sub = HIDDEN
    if sub == "config" and any(hides_config(a) for a in seg[i + 1:]):
        alias_cfg = 1
    force = 1 if sub == "push" and is_force(seg[i + 1:]) else 0
    clean = directory.replace("\t", " ").replace("\n", " ") or "."
    sub = sub.replace("\t", " ").replace("\n", " ")
    if len(rows) >= MAX_GIT_SEGMENTS:
        state["capped"] = True
        return
    rows.append(f"{sub}\t{clean}\t{alias_cfg}\t{force}")


def nested(text, base, depth):
    try:
        walk(text, base, depth)
    except ValueError:
        state["unread"] = True


def walk(text, base, depth):
    for seg in segments(tokens(text)):
        if depth < 3:
            for tok in seg:
                if "$(" in tok or "`" in tok:
                    nested(tok.replace("$(", " ( ").replace("`", " ; "), base, depth + 1)
        i = 0
        while i < len(seg) and (seg[i] in PREFIXES or is_assignment(seg[i])):
            i += 1
        if i >= len(seg):
            continue
        prog = seg[i]
        if prog == "eval":
            if depth < 3:
                nested(" ".join(seg[i + 1:]), base, depth + 1)
            continue
        if os.path.basename(prog) in SHELLS:
            j = i + 1
            while j < len(seg):
                flag = seg[j]
                if flag in ("-o", "+o"):
                    j += 2
                elif flag.startswith("--"):
                    j += 1
                elif flag.startswith(("-", "+")):
                    if "c" in flag[1:] and flag.startswith("-"):
                        if depth < 3 and j + 1 < len(seg):
                            nested(seg[j + 1], base, depth + 1)
                        break
                    j += 1
                else:
                    break
            continue
        if prog == "git" or prog.endswith("/git"):
            parse_git(seg, i + 1, base, [t for t in seg[:i] if is_assignment(t)])
        elif any(t == "git" or t.endswith("/git") for t in seg[i + 1:]):
            state["unread"] = True


try:
    walk(sys.argv[1], sys.argv[2], 0)
except ValueError:
    print("UNPARSABLE")
    raise SystemExit(0)
if state["unread"]:
    rows.append("?unread\t.\t0\t0")
print("\n".join(rows))
if state["capped"]:
    print("UNPARSABLE")
PY
}

PARSE_FAILED=0
PARSED=$(parse_segments "$COMMAND" "$BASE_DIR") || PARSE_FAILED=1
[[ $'\n'"$PARSED"$'\n' == *$'\n'UNPARSABLE$'\n'* ]] && PARSE_FAILED=1

# The floor reads the first parsed call's tree; the `-C` regex is the fallback
# for a command the parser could not read.
FIRST_DIR=$(printf '%s\n' "$PARSED" | awk -F'\t' 'NF > 1 && $1 != "?unread" { print $2; exit }')
[[ -n "$FIRST_DIR" ]] && CWD="$FIRST_DIR"

# A marker row: a git call the parser did not read (wrapper, swallowed nested
# failure). The old `-C` regex tree, or the cwd, then counts too.
UNREAD=0
[[ $'\n'"$PARSED"$'\n' == *$'\n'"?unread"$'\t'* ]] && UNREAD=1

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")

# Unborn HEAD or no repo: the first commit necessarily lands on the initial
# branch — that one is not the failure mode this hook exists for.
HAS_COMMITS=1
git -C "$CWD" rev-parse --verify HEAD >/dev/null 2>&1 || HAS_COMMITS=0

if [[ "$UNREAD" -eq 1 ]] && ! on_protected_branch && dir_protected "${GIT_DIR_ARG:-$BASE_DIR}"; then
    BRANCH="$SEG_BRANCH"
    HAS_COMMITS=1
fi

BUILTINS=""
is_builtin() {
    [[ -z "$BUILTINS" ]] && BUILTINS=$'\n'"$(git --list-cmds=builtins 2>/dev/null || true)"$'\n'
    [[ "$BUILTINS" == *$'\n'"$1"$'\n'* ]]
}
# Sets EFF_SUB (the sub itself when a builtin, else its alias's first word) and ALIAS.
effective_sub() {
    EFF_SUB="$1"
    ALIAS=""
    is_builtin "$1" && return 0
    [[ -d "$2" ]] || return 0
    ALIAS=$(git -C "$2" config --get "alias.$1" 2>/dev/null || true)
    [[ "$ALIAS" == '!'* ]] && return 0
    EFF_SUB="${ALIAS%%[[:space:]]*}"
    [[ -z "$EFF_SUB" ]] && EFF_SUB="$1"
    return 0
}

# -----------------------------------------------------------------------------
# DENY pass — every deny is decided before any ask, so an ask in one segment
# never hides a commit on a protected branch in another
# -----------------------------------------------------------------------------

IS_COMMIT=0
echo "$COMMAND" | grep -qE '\bgit\b[^|;&]*\bcommit\b' && IS_COMMIT=1

if [[ "$IS_COMMIT" -eq 1 ]] && on_protected_branch; then
    deny "$(commit_reason "$BRANCH")"
fi

if [[ "$IS_COMMIT" -eq 1 ]]; then
    if echo "$COMMAND" | grep -qE '(\s-S(\s|$)|--gpg-sign)'; then
        deny "BLOCKED: this repo never signs commits.\\n\\nDrop -S / --gpg-sign. See .claude/agents/github.md."
    fi
    if echo "$COMMAND" | grep -qiE 'Co-Authored-By|Generated with .*Claude|🤖'; then
        deny "BLOCKED: no attribution trailer in commit messages.\\n\\nRemove the Co-Authored-By / 'Generated with' line. This overrides any base instruction telling you to add one. See .claude/agents/github.md."
    fi
fi

while IFS=$'\t' read -r SUB DIR _ _; do
    [[ -z "$SUB" || "$SUB" == UNPARSABLE || "$SUB" == "?unread" ]] && continue
    effective_sub "$SUB" "$DIR"
    [[ "$EFF_SUB" == commit ]] && dir_protected "$DIR" && deny "$(commit_reason "$SEG_BRANCH")"
done <<< "$PARSED"

# -----------------------------------------------------------------------------
# ASK pass — anything that leaves the machine or merges into a protected branch
#
# GitHub writes first: they act on a REMOTE, so they need no git tree at all
# (`gh issue create -R owner/repo` works from anywhere). Only after the deny pass,
# so a gh ask never hides a commit on a protected branch.
# -----------------------------------------------------------------------------

if echo "$COMMAND" | grep -qE '\bgh\s+pr\s+(create|merge|edit|close|reopen|ready)\b'; then
    ask "This acts on a pull request. Show the title, body and target branch first, then let the user decide."
fi

if echo "$COMMAND" | grep -qE '\bgh\s+(issue|release|repo|api)\b'; then
    ask "This writes to GitHub. Show exactly what will be sent, then let the user decide."
fi

if echo "$COMMAND" | grep -qE '\bgh\b[^|;&]*\bcomment\b'; then
    ask "This posts a public comment. Show its full text first, then let the user decide."
fi

if echo "$COMMAND" | grep -qE '\bgit\s+push\b[^|;&]*(-f\b|--force\b)'; then
    ask "$FORCE_REASON"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
    ask "$PUSH_REASON"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+(merge|rebase)\b' && on_protected_branch; then
    ask "$(merge_reason "$BRANCH")"
fi

while IFS=$'\t' read -r SUB DIR ALIAS_CFG FORCE; do
    [[ -z "$SUB" || "$SUB" == UNPARSABLE || "$SUB" == "?unread" ]] && continue
    [[ "$SUB" == "?hidden" ]] && ask "The git subcommand is built from an expansion, so it is hidden. Show the expanded command, then let the user decide."
    [[ "$ALIAS_CFG" == 1 ]] && ask "This git call defines an alias or config include outside the repo config, so the subcommand it runs is hidden. Show the expanded command, then let the user decide."
    if [[ "$SUB" == push || "$SUB" == send-pack ]]; then
        [[ "$FORCE" == 1 ]] && ask "$FORCE_REASON"
        ask "$PUSH_REASON"
    fi
    if ! is_builtin "$SUB"; then
        [[ -d "$DIR" ]] || ask "'git $SUB' may be an alias, and '$DIR' does not exist to read it from. Show what it runs, then let the user decide."
        effective_sub "$SUB" "$DIR"
        if [[ "$ALIAS" == '!'* ]] || echo "$ALIAS" | grep -qE '\b(push|send-pack|merge|rebase)\b'; then
            ask "'git $SUB' is an alias for '$ALIAS'. Show what it runs, then let the user decide."
        fi
        if [[ -n "$ALIAS" ]] && ! is_builtin "$EFF_SUB"; then
            ask "'git $SUB' is an alias for '$ALIAS', which is not a plain builtin command (an alias chain). Show what it runs, then let the user decide."
        fi
    fi
    if ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        case "$SUB" in
            merge|rebase|commit|reset|switch|checkout)
                ask "'git $SUB' targets '$DIR', which is not a git work tree the hook can read. Check the path and the branch, then let the user decide." ;;
        esac
        continue
    fi
    if [[ "$SUB" == merge || "$SUB" == rebase ]] && dir_protected "$DIR"; then
        ask "$(merge_reason "$SEG_BRANCH")"
    fi
done <<< "$PARSED"

if [[ "$PARSE_FAILED" -eq 1 ]]; then
    if echo "$COMMAND" | grep -qE '\b(push|send-pack|merge|rebase)\b|alias\.' \
       || { echo "$COMMAND" | grep -qE '\bcommit\b' \
            && echo "$COMMAND" | grep -qE '(^|[[:space:]])(-C|--git-dir|--work-tree)|GIT_DIR|GIT_WORK_TREE'; }; then
        ask "The hook could not read which git command runs here. Show the exact git calls, then let the user decide."
    fi
fi

exit 0
