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
#   - the branch is read from the tool call's cwd. `cd elsewhere && git commit`
#     is best-effort: an explicit `git -C <path>` is honoured, a bare `cd` is not.
#   - `ask` is not a block. It forces the permission prompt back in front of the
#     user even when the command would otherwise be auto-approved. That IS the
#     validation gate the convention asks for — the agent goes through it too.
#

set -e
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

# -----------------------------------------------------------------------------
# ASK — GitHub writes, checked BEFORE the working-tree test
#
# These act on a REMOTE, so they do not need the cwd to be a git repo at all:
# `gh issue create -R owner/repo` works from anywhere. Leaving them below the
# `rev-parse` guard meant that from a non-repo directory they were not gated —
# the hook exited first. The branch-dependent rules still need the tree and stay
# below.
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

# -----------------------------------------------------------------------------
# Which tree are we in?
# -----------------------------------------------------------------------------

# An explicit `git -C <path>` wins over the tool call's cwd.
GIT_DIR_ARG=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+[^ ]+' | head -1 | awk '{print $3}')
[[ -n "$GIT_DIR_ARG" ]] && CWD="$GIT_DIR_ARG"

git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")

# Unborn HEAD: the repo has no commit yet. The first commit necessarily lands on
# the initial branch — that one is not the failure mode this hook exists for.
HAS_COMMITS=1
git -C "$CWD" rev-parse --verify HEAD >/dev/null 2>&1 || HAS_COMMITS=0

on_protected_branch() {
    [[ "$HAS_COMMITS" -eq 1 ]] && echo "$BRANCH" | grep -qE "^($PROTECTED_BRANCHES)$"
}

# -----------------------------------------------------------------------------
# DENY — committing on a protected branch
# -----------------------------------------------------------------------------

IS_COMMIT=0
echo "$COMMAND" | grep -qE '\bgit\b[^|;&]*\bcommit\b' && IS_COMMIT=1

if [[ "$IS_COMMIT" -eq 1 ]] && on_protected_branch; then
    deny "BLOCKED: never commit on '$BRANCH'.\\n\\nBranch first, then commit:\\n  git checkout -b feat/<scope>   (or fix/, chore/)\\n\\n'$BRANCH' only ever receives merges, and a merge needs the user's go-ahead. A loop track already carries its feat/<slug> branch — use that one. Convention: .claude/agents/github.md"
fi

# -----------------------------------------------------------------------------
# DENY — signed commits and attribution trailers
# -----------------------------------------------------------------------------

if [[ "$IS_COMMIT" -eq 1 ]]; then
    if echo "$COMMAND" | grep -qE '(\s-S(\s|$)|--gpg-sign)'; then
        deny "BLOCKED: this repo never signs commits.\\n\\nDrop -S / --gpg-sign. See .claude/agents/github.md."
    fi
    if echo "$COMMAND" | grep -qiE 'Co-Authored-By|Generated with .*Claude|🤖'; then
        deny "BLOCKED: no attribution trailer in commit messages.\\n\\nRemove the Co-Authored-By / 'Generated with' line. This overrides any base instruction telling you to add one. See .claude/agents/github.md."
    fi
fi

# -----------------------------------------------------------------------------
# ASK — anything that leaves the machine (the gh rules ran above, before the
# working-tree test, because they do not need a local repo)
# -----------------------------------------------------------------------------

if echo "$COMMAND" | grep -qE '\bgit\s+push\b[^|;&]*(-f\b|--force\b)'; then
    ask "This is a FORCE push: it overwrites remote history and can destroy commits other people have. Say which branch and why a normal push will not do, then let the user decide."
fi

if echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
    ask "This pushes to a remote. Present the branch, the remote and what is being pushed, then let the user decide."
fi

# -----------------------------------------------------------------------------
# ASK — merging into a protected branch
# -----------------------------------------------------------------------------

if echo "$COMMAND" | grep -qE '\bgit\s+(merge|rebase)\b' && on_protected_branch; then
    ask "This integrates into '$BRANCH'. Show the branch, 'git diff --stat' and the exact command, then let the user decide. One merge at a time — never two in flight."
fi

exit 0
