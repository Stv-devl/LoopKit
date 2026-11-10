#!/usr/bin/env bash
# cwk-guard-api: 3
#
# Hook: enforce-git-workflow
# Event: PreToolUse (Bash)
# Purpose: make the Git convention mechanical instead of declarative.
#
#   deny → committing on a protected branch, signing a commit; a `git add` (or
#          `git stage`) that forces, hides its paths, cancels the dry-run,
#          is not alone in its call (only git add/stage/status/diff/log may
#          come before it), or would stage a secret (`git add --dry-run`); a
#          `-C` value the shell expands (`$`, a backtick, a leading `~`, glob or
#          brace characters) is not resolved and denies as unconfirmed
#   ask  → a `git add` aimed at a directory that is not a repository the hook
#          can read safely (its git dir is not `.git`, `.git/worktrees/<name>` or
#          `.git/modules/<path>`, or its common dir is not the project's (the
#          project's own, a worktree or a submodule of it): a bare-clone worktree,
#          `--separate-git-dir`, a planted git dir, a `git init` repository inside
#          the project, a missing or non-repo directory): no dry-run, because
#          the git dir's own config could run code. The ask names the directory
#          and says the hook did not check what is staged. An argument naming a
#          secret (`.env*`, `*.pem`, `*.key`, `[.]credentials[.*]`) still denies there,
#          read from the argument text alone;
#          anything that touches the remote or merges into a protected branch;
#          a commit with --amend, --no-verify, --all, --include, --only,
#          --patch, --interactive or a pathspec; a switch/checkout that
#          discards or resets
#   foreign (python, every git call but add/stage): ask when a cd earlier in the
#          call moved it, or when it runs in a repository whose common dir is not
#          the project's: that repository's config can run programs on status/diff
#   destructive (python, on the parsed call, a non-`!` alias expanded up to 5
#          hops): ask on git init, on a git config that is not a full-spelling
#          read (--get*, --list, get, list, one key), on clean without -n/-i, reset --hard, stash clear|drop,
#          branch -D/-M/-C/-f, update-ref on HEAD/refs/heads or --stdin, a
#          checkout/restore that overwrites `.`, `:/`, a glob, a directory or a
#          named file with uncommitted changes (`git diff --quiet HEAD`, under the
#          add dry-run's preconditions), a fetch into a local branch, upload-pack,
#          update-head-ok, an alias's worktree add outside .claude/worktrees/;
#          deny a checkout/restore that rewrites a test-first module or a test
#   pass → a call naming `git` and add, stage, commit or switch passes only as
#          one whole strict form (`grammar_strict`); anything else asks, as the
#          last decision. The parser keeps the denies and the specific asks; it
#          never decides a pass for such a call.
#
# When its parser cannot be trusted (python3 missing or failing, no end
# marker, a top-level parse failure) or a call holds more than 50 git calls,
# it fails closed on a raw word scan that reads through quotes: every
# `git add`/`git stage` is denied, every commit/switch/checkout asked.
#
# The convention itself lives in `.claude/agents/github.md` (the only copy).
# CLAUDE.md keeps one line saying all Git work goes through that agent; this
# hook is what holds when something bypasses it — a `git commit` typed straight
# into Bash never reads either file.
#
# Deliberate limits:
#   - the branch is read from the tool call's cwd, or from each git call's own
#     `-C`. A bare `cd` is not followed: a `cd` before a `git add` denies it,
#     before any other git call asks (the foreign rule).
#   - wrappers that take options (`nice -n 5 git`, `env -i git`, `sudo git`) are
#     not unwrapped; the whole-text rules decide them.
#   - a `$(...)` or `bash -c` string shlex cannot read is skipped by the parsing
#     rules (a commit message with an apostrophe is the normal case), but when
#     the call names the four words the grammar ask now decides it; a top-level
#     command it cannot read falls back to a scan of the raw text.
#   - an `export GIT_DIR=...` (or GIT_WORK_TREE, GIT_CONFIG*) in an earlier
#     statement is not read, like a bare `cd`.
#   - the destructive rules live in the parser: with python3 missing or bad
#     only the floor answers. A wrapped or unreadable call (`timeout 5 git
#     clean -fdx`, a destructive call beside a heredoc shlex cannot read) gets
#     no verdict from them (harness-hardening.md, Open follow-ups).
#   - `ask` is not a block. It forces the permission prompt back in front of the
#     user even when the command would otherwise be auto-approved. That IS the
#     validation gate the convention asks for — the agent goes through it too.
#

set -e
# shellcheck disable=SC2034  # read by the sourced hook-lib.sh
CWK_GUARD_HOOK=1
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[[ -z "$COMMAND" ]] && exit 0
[[ -z "$CWD" ]] && CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# The command as the shell would glue it: quotes, `\` and `\`+newline removed.
NORM="${COMMAND//\\$'\n'/}"
NORM="${NORM//[\'\"\\]/}"

# Nothing git-shaped in either reading → cheapest possible exit.
printf '%s\n%s\n' "$COMMAND" "$NORM" | grep -qE 'git|\bgh\b' || exit 0

# CONFIGURE: branches that only ever receive merges.
PROTECTED_BRANCHES="main|master"

# jq, never a heredoc: the reasons below interpolate $BRANCH, and a branch name
# holding a `"` produced unparseable JSON — dropped by the harness, so the gate
# silently disappeared. Only the authored `\n` is expanded;
# every other backslash is left alone.
decide() {
    local decision="$1" reason
    local cut=" [reason truncated]"
    reason="${2//\\n/$'\n'}"
    ((${#reason} > 4000)) && reason="${reason:0:$((4000 - ${#cut}))}$cut"
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
commit_reason() { printf '%s' "BLOCKED: never commit on '$1'.\\n\\nBranch first, then commit:\\n  git switch -c feat/<scope>   (or fix/, chore/)\\n\\n'$1' only ever receives merges, and a merge needs the user's go-ahead. A loop track already carries its feat/<slug> branch — use that one. Convention: .claude/agents/github.md"; }
ADD_HIDDEN_REASON="BLOCKED: this git add hides what it stages (\$, \$(…), backtick, pathspec file or git options). Name the paths literally, in a plain \`git add <paths>\`."
ADD_UNREADABLE_REASON="BLOCKED: unreadable git add — the hook could not read this call (a wrapper such as timeout, stdbuf or xargs, a cd before it, another command before it, or a parse failure). Run \`git add <paths>\` alone, as its own call, with literal paths (\`git -C <tree> add …\` for another tree)."
add_reason() {
    case "$1" in
        force)  printf '%s' "BLOCKED: git add --force stages a path .gitignore excludes. Stage explicit paths without -f; an ignored file stays out of the repo." ;;
        hidden) printf '%s' "$ADD_HIDDEN_REASON" ;;
        nodry)  printf '%s' "BLOCKED: git add --no-dry-run would cancel the hook's own dry-run. Stage explicit paths without it." ;;
        cd|prior) printf '%s' "$ADD_UNREADABLE_REASON" ;;
        locked) printf '%s' "BLOCKED: .git/index.lock exists, another git process holds the index. Wait for it, then retry; never delete the lock while it runs." ;;
        secret:*) printf '%s' "BLOCKED: this git add would stage a secret: ${1#secret:}. Never stage .env*, *.pem, *.key, credentials.*, .credentials.*; add the pattern to .gitignore." ;;
        *) printf '%s' "BLOCKED: git add --dry-run could not confirm what this stages ($1). If the paths are new in this same call (touch, git init), run git add as its own call; otherwise name existing paths literally." ;;
    esac
}
# The `c:` (commit) or `s:` (switch/checkout) part of a row's flags column.
row_flags() {
    local part
    if [[ "$1" == c ]]; then part="${2#c:}"; part="${part%%;*}"; else part="${2##*;s:}"; fi
    printf '%s' "${part//,/, }"
}
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

# One line per git call: subcommand, directory, alias-on-command-line, force,
# dangerous flags (`c:` as a commit, `s:` as a switch/checkout), and the verdict
# of a `git add` (`-` for any other call). Only codes in the last two columns,
# never user text, except the paths of a `secret:` verdict, which come last.
# A command shlex cannot read prints UNPARSABLE. When it cannot read a call, a
# fallback scan of the raw text adds `?fb-add` / `?fb-flags` rows.
parse_segments() {
    python3 -I - "$1" "$2" "$CWK_TDD_SHELL_TARGET_RE" "$CWK_TDD_SHELL_FROZEN_TEST_RE" <<'PY'
import os
import re
import shlex
import subprocess
import sys
import time

WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
              "--config-env", "--exec-path", "--attr-source"}
PREFIXES = {"env", "command", "exec", "time", "nice", "nohup", "setsid", "{", "!",
            "if", "then", "else", "elif", "while", "until", "do"}
SHELLS = {"bash", "sh", "zsh", "dash"}
SEPARATOR_CHARS = set(";&|()\n")
WORD_START = set(" \t\r\n;&|()<>")
HIDDEN = "?hidden"
MAX_GIT_SEGMENTS = 50
ALLOWED_ADD_GLOBALS = {"-C", "--no-pager", "-P"}
DRY_RUN_BUDGET = 2.0
SECRET_KEEP = {".env.example", ".env.sample", ".env.template"}
REDIRECT_CHARS = set("<>&")
HEREDOC = re.compile(r"(?<!<)<<(-?)[ \t]*['\"]?([A-Za-z0-9_.-]+)['\"]?")
COMMIT = {
    "dangerous": {"amend": "--amend", "no-verify": "--no-verify", "all": "--all",
                  "patch": "--patch", "interactive": "--interactive",
                  "include": "--include", "only": "--only",
                  "pathspec-from-file": "pathspec"},
    "short": {"a": "--all", "n": "--no-verify", "i": "--include", "o": "--only", "p": "--patch"},
    "value_short": set("mFcCt"),
    "attached_short": set("uS"),
    "value_long": {"message", "file", "author", "date", "reuse-message", "reedit-message",
                   "fixup", "squash", "template", "trailer", "cleanup", "pathspec-from-file"},
    "pathspec": True,
}
SWITCH = {
    "dangerous": {"discard-changes": "--discard-changes", "force": "--force",
                  "force-create": "--force-create"},
    "short": {"f": "--force", "C": "--force-create", "B": "--force-create"},
    "value_short": set("cbBC"),
    "attached_short": set(),
    "value_long": {"orphan", "create", "force-create"},
}
ADD_SUBS = {"add", "stage"}
QUIET_SUBS = {"add", "stage", "status", "diff", "log"}
RAW_SEPARATORS = re.compile(r"[\s;&|()`'\"]+|\$\(")
TDD_TARGET = re.compile(sys.argv[3].replace("[:space:]", r"\s"))
TDD_FROZEN = re.compile(sys.argv[4].replace("[:space:]", r"\s"))
NETWORK_SUBS = {"fetch", "pull", "clone", "ls-remote"}
NETWORK_LONG = {"upload-pack", "update-head-ok", "refmap"}
NETWORK_KNOWN = {"update-shallow", "unshallow", "refetch", "recurse-submodules",
                 "rebase", "reference", "reference-if-able"}
NETWORK_VALUE_LONG = {"depth", "deepen", "shallow-since", "shallow-exclude", "jobs", "negotiation-tip",
                      "server-option", "recurse-submodules-default", "submodule-prefix", "upload-pack",
                      "refmap", "origin", "branch", "template", "reference", "separate-git-dir",
                      "config", "strategy", "strategy-option"}
NETWORK_VALUE_SHORT = {"fetch": "jo", "pull": "josX", "clone": "bocju", "ls-remote": "o"}
FETCH_COMPLETION = (
    "--verbose --quiet --all --set-upstream --append --atomic --upload-pack= --force --multiple "
    "--tags --jobs= --prefetch --prune --prune-tags --recurse-submodules --dry-run --porcelain "
    "--write-fetch-head --keep --update-head-ok --progress --depth= --shallow-since= "
    "--shallow-exclude= --deepen= --unshallow --refetch --submodule-prefix= "
    "--recurse-submodules-default= --update-shallow --refmap= --server-option= --ipv4 --ipv6 "
    "--negotiation-tip= --negotiate-only --filter= --auto-maintenance --auto-gc "
    "--show-forced-updates --write-commit-graph --stdin --no-verbose -- --no-quiet --no-all "
    "--no-set-upstream --no-append --no-atomic --no-upload-pack --no-force --no-multiple "
    "--no-tags --no-jobs --no-prefetch --no-prune --no-prune-tags --no-recurse-submodules "
    "--no-dry-run --no-porcelain --no-write-fetch-head --no-keep --no-update-head-ok "
    "--no-progress --no-depth --no-shallow-since --no-shallow-exclude --no-deepen "
    "--no-submodule-prefix --no-recurse-submodules-default --no-update-shallow "
    "--no-server-option --no-negotiation-tip --no-negotiate-only --no-filter "
    "--no-auto-maintenance --no-auto-gc --no-show-forced-updates --no-write-commit-graph "
    "--no-stdin"
)
FETCH_LONG = {w[2:].rstrip("=") for w in FETCH_COMPLETION.split() if w != "--"}
FETCH_LONG_VALUE = {w[2:-1] for w in FETCH_COMPLETION.split() if w.endswith("=")}
FETCH_SHORT = "afjkmnopPqtuv46"
FETCH_SHORT_VALUE = "jo"
FETCH_SHORT_LONG = {"P": "prune-tags", "f": "force", "u": "update-head-ok", "o": "server-option"}
REMOTE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
FETCH_SHALLOW = {"depth", "deepen", "shallow-since", "shallow-exclude", "unshallow", "update-shallow"}
RESET_KNOWN = {"soft", "mixed", "merge", "keep", "quiet", "no-quiet", "patch", "intent-to-add",
               "pathspec-from-file", "pathspec-file-nul", "recurse-submodules",
               "no-recurse-submodules", "refresh", "no-refresh"}
BRANCH_KNOWN = {"format", "delete", "move", "copy", "create-reflog", "set-upstream-to", "track",
                "no-track", "unset-upstream", "edit-description", "list", "all", "remotes",
                "contains", "no-contains", "merged", "no-merged", "sort", "points-at", "column",
                "no-column", "color", "no-color", "verbose", "quiet", "abbrev", "no-abbrev",
                "show-current", "ignore-case", "omit-empty", "recurse-submodules"}
CHECKOUT_FAMILY = {
    "restore": {"value_short": "s", "value_long": {"source", "conflict"},
                "known": {"staged", "worktree", "source", "ours", "theirs", "merge", "conflict",
                          "ignore-unmerged", "overlay", "no-overlay", "quiet", "progress",
                          "no-progress", "recurse-submodules", "no-recurse-submodules",
                          "ignore-skip-worktree-bits", "pathspec-file-nul", "patch"}},
    "checkout": {"value_short": "bB", "value_long": {"orphan", "conflict"},
                 "known": {"orphan", "conflict", "ours", "theirs", "merge", "detach", "track",
                           "no-track", "guess", "no-guess", "overlay", "no-overlay", "quiet",
                           "progress", "no-progress", "force", "ignore-skip-worktree-bits",
                           "ignore-other-worktrees", "overwrite-ignore", "no-overwrite-ignore",
                           "recurse-submodules", "no-recurse-submodules", "pathspec-file-nul",
                           "patch"}},
}
GLOB_CHARS = set("*?[")
MAX_ALIAS_HOPS = 5
LOST_UNCOMMITTED = "every uncommitted change there is lost, and no commit or stash holds it"
rows = []
state = {"capped": False, "unread": False, "deadline": None, "cd": False, "prior": False,
         "builtins": None, "common": {}}


def strip_comments(text):
    out, quote, i = [], "", 0
    while i < len(text):
        ch = text[i]
        if quote == "'":
            quote = "" if ch == "'" else quote
        elif ch == "\\" and text[i + 1:i + 2] == "\n":
            i += 2
            continue
        elif ch == "\\" and i + 1 < len(text):
            out.append(ch)
            i += 1
            ch = text[i]
        elif quote == '"':
            quote = "" if ch == '"' else quote
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (not out or out[-1] in WORD_START):
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def close_dangling_backslash(text):
    """Bash reads a final unpaired backslash as a literal one; shlex refuses it."""
    run = len(text) - len(text.rstrip("\\"))
    return text + "\\" if run % 2 else text


def tokens(text):
    lexer = shlex.shlex(close_dangling_backslash(strip_comments(text)), posix=True,
                        punctuation_chars="();<>|&\n")
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


def strip_redirections(args):
    out, i = [], 0
    while i < len(args):
        tok = args[i]
        if tok and set(tok) <= REDIRECT_CHARS:
            if out and out[-1].isdigit():
                out.pop()
            i += 2
            continue
        out.append(tok)
        i += 1
    return out


def classify(args, family, stop_at_dashdash=True):
    found, i = [], 0
    dangerous = family["dangerous"]
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            if family.get("pathspec") and i < len(args):
                found.append("pathspec")
            if stop_at_dashdash:
                break
            continue
        if family.get("pathspec") and not (arg.startswith("-") and len(arg) > 1):
            found.append("pathspec")
            continue
        if arg.startswith("--") and len(arg) > 2:
            name, eq, _ = arg[2:].partition("=")
            if name in dangerous:
                hits = [name]
            else:
                hits = [d for d in dangerous if d.startswith(name)]
            found.extend(dangerous[h] for h in hits)
            takes_value = any(v.startswith(name) for v in family["value_long"])
            if not eq and takes_value and all(h in family["value_long"] for h in hits):
                i += 1
            continue
        if arg.startswith("-") and len(arg) > 1:
            letters = arg[1:]
            for j, ch in enumerate(letters):
                if ch in family["short"]:
                    found.append(family["short"][ch])
                if ch in family["value_short"]:
                    if j == len(letters) - 1:
                        i += 1
                    break
                if ch in family["attached_short"]:
                    break
    return sorted(set(found))


def flags_column(args):
    commit = ",".join(classify(args, COMMIT))
    switch = ",".join(classify(args, SWITCH))
    return f"c:{commit};s:{switch}"


def is_secret(path):
    base = path.rsplit("/", 1)[-1]
    if base.startswith(".env"):
        return base not in SECRET_KEEP
    return base.endswith((".pem", ".key")) or re.match(r"\.?credentials(\.|$)", base) is not None


def staged_secrets(dry_run_output):
    paths = (line[5:-1] for line in dry_run_output.splitlines()
             if line.startswith("add '") and line.endswith("'"))
    return [p for p in paths if is_secret(p)]


def lock_held(directory):
    try:
        res = subprocess.run(["git", "-C", directory, "rev-parse", "--git-path", "index.lock"],
                             stdin=subprocess.DEVNULL, capture_output=True, timeout=1)
    except (OSError, subprocess.TimeoutExpired):
        return False
    lock = res.stdout.decode(errors="replace").strip()
    if res.returncode != 0 or not lock:
        return False
    return os.path.exists(os.path.join(directory, lock))


def common_dir(directory):
    """The physical git common dir of the repository holding <directory>, or None."""
    if directory not in state["common"]:
        res = quick_git(directory, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
        value = None
        if res is not None and res.returncode == 0:
            text = res.stdout.decode(errors="replace").strip()
            value = os.path.realpath(text) if text else None
        state["common"][directory] = value
    return state["common"][directory]


def project_repo(directory):
    """True when <directory> is in the project's repository, a worktree or a submodule of it."""
    project = common_dir(os.environ.get("CLAUDE_PROJECT_DIR") or sys.argv[2])
    here = common_dir(directory)
    if project is None or here is None:
        return False
    return here == project or here.startswith(project + os.sep + "modules" + os.sep)


def readable_git_dir(directory):
    try:
        res = subprocess.run(["git", "-C", directory, "rev-parse", "--absolute-git-dir"],
                             stdin=subprocess.DEVNULL, capture_output=True, timeout=1,
                             env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.TimeoutExpired):
        return False
    if res.returncode != 0:
        return False
    parts = os.path.normpath(res.stdout.decode(errors="replace").strip()).split(os.sep)
    if not (parts[-1] == ".git" or parts[-3:-1] == [".git", "worktrees"]
            or any(parts[k] == ".git" and parts[k + 1] == "modules" for k in range(len(parts) - 2))):
        return False
    return project_repo(directory)


def foreign_verdict(sub, directory, moved):
    """`-` or an ask: a git call that a cd moved, or that runs in another repository."""
    if moved:
        return ask(f"'git {sub}' follows a cd earlier in the same call: the hook cannot tell which "
                   "repository it lands in, and another repository's own config can run programs "
                   "(core.fsmonitor, filters, hooks). Run it alone, with -C <dir> if needed.")
    if common_dir(directory) is None or project_repo(directory):
        return "-"
    return ask(f"'git {sub}' runs in {directory}, a repository outside the project: its own config "
               "can run programs (core.fsmonitor, filters, hooks) that nothing here has vetted.")


def dry_run(directory, args):
    if not readable_git_dir(directory):
        named = [a for a in args if a != "--" and is_secret(a)]
        if named:
            return "secret:" + ",".join(p.replace("\t", " ") for p in named)
        return "unsafe:" + directory.replace("\t", " ").replace("\n", " ")
    code, out = deadline_git(directory, ["add", "--dry-run", *args], capture=True)
    if code in ("timeout", "failed"):
        return code
    if code != 0:
        return "failed"
    secrets = staged_secrets(out.decode(errors="replace"))
    if secrets:
        return "secret:" + ",".join(p.replace("\t", " ") for p in secrets)
    return "ok"


def add_verdict(args, directory, other_globals, git_env, dir_unread):
    for arg in args:
        if arg == "--":
            break
        if arg.startswith("--") and len(arg) > 2:
            name = arg[2:].partition("=")[0]
            if name.startswith("no-d") and "no-dry-run".startswith(name):
                return "nodry"
            if "force".startswith(name):
                return "force"
        elif arg.startswith("-") and len(arg) > 1 and "f" in arg[1:]:
            return "force"
    for arg in args:
        if "$" in arg or "`" in arg:
            return "hidden"
        name = arg[2:].partition("=")[0] if arg.startswith("--") else ""
        if name.startswith("pathspec-f") and (
                "pathspec-from-file".startswith(name) or "pathspec-file-nul".startswith(name)):
            return "hidden"
    if other_globals or git_env:
        return "hidden"
    if dir_unread:
        return "failed"
    if lock_held(directory):
        return "locked"
    return dry_run(directory, args)


def git_builtins():
    if state["builtins"] is None:
        try:
            res = subprocess.run(["git", "--list-cmds=builtins"], stdin=subprocess.DEVNULL,
                                 capture_output=True, timeout=1)
            names = res.stdout.decode(errors="replace").split() if res.returncode == 0 else []
        except (OSError, subprocess.TimeoutExpired):
            names = []
        state["builtins"] = set(names)
    return state["builtins"]


def quick_git(directory, args):
    try:
        return subprocess.run(["git", "-C", directory, *args], stdin=subprocess.DEVNULL,
                              capture_output=True, timeout=1, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.TimeoutExpired):
        return None


def deadline_git(directory, args, capture=False):
    """Run git inside the call's shared budget.

    Returns (exit code, stdout), or ("timeout"|"failed", b"") when the budget is
    spent or git cannot start; a git still running at the deadline is killed.
    """
    if state["deadline"] is None:
        state["deadline"] = time.monotonic() + DRY_RUN_BUDGET
    left = state["deadline"] - time.monotonic()
    if left <= 0:
        return "timeout", b""
    try:
        proc = subprocess.Popen(["git", "-C", directory, *args], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, env={**os.environ, "LC_ALL": "C"})
    except OSError:
        return "failed", b""
    try:
        out, _ = proc.communicate(timeout=left)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(0.5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        return "timeout", b""
    return proc.returncode, out or b""


def expand_alias(sub, args, directory):
    """The builtin a non-`!` alias runs, its args first: (sub, args, via_alias, problem)."""
    seen, via = {sub}, False
    for hop in range(MAX_ALIAS_HOPS + 1):
        if sub in git_builtins() or not os.path.isdir(directory):
            return sub, args, via, ""
        if hop == MAX_ALIAS_HOPS:
            return sub, args, via, "it chains more than five aliases"
        res = quick_git(directory, ["config", "--get", f"alias.{sub}"])
        if res is None:
            return sub, args, via, "its config could not be read"
        value = res.stdout.decode(errors="replace").strip()
        if res.returncode != 0 or not value or value.startswith("!"):
            return sub, args, via, ""
        try:
            words = shlex.split(value)
        except ValueError:
            return sub, args, via, "its value does not parse"
        if not words:
            return sub, args, via, ""
        sub, args, via = words[0], words[1:] + args, True
        if sub in seen:
            return sub, args, via, "it calls itself"
        seen.add(sub)
    return sub, args, via, ""


def is_long(arg):
    return arg.startswith("--") and len(arg) > 2


def is_short(arg):
    return arg.startswith("-") and not arg.startswith("--") and len(arg) > 1


def long_hits(arg, ours, known=()):
    """The options of `ours` a long option names, exactly or by a prefix only they share."""
    name = arg[2:].partition("=")[0]
    if name in ours:
        return {name}
    if not name or name in known:
        return set()
    hits = {c for c in (*ours, *known) if c.startswith(name)}
    return hits if hits <= set(ours) else set()


def short_letters(arg, value_letters=""):
    letters = ""
    for ch in arg[1:]:
        letters += ch
        if ch in value_letters:
            break
    return letters


def split_operands(args, value_short, value_long):
    """The operands before and after `--`, option values skipped, and whether `--` was there."""
    before, i = [], 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            return before, args[i:], True
        if is_long(arg):
            if "=" not in arg and long_hits(arg, value_long):
                i += 1
            continue
        if is_short(arg):
            letters = short_letters(arg, value_short)
            if letters[-1] in value_short and len(letters) == len(arg) - 1:
                i += 1
            continue
        before.append(arg)
    return before, [], False


def ask(text):
    return f"ask:{text} Show the exact call, then let the user decide."


def deny(text):
    return f"deny:{text}"


def sequence_ask(what):
    return ask(f"This {what} reads the work tree, and a cd or an earlier command in the same call "
               "keeps the hook from checking which tree and what it would lose. Run it alone.")


def has_glob_or_magic(path):
    return path in (".", "") or path.startswith(":") or bool(GLOB_CHARS & set(path))


def worktree_clean(directory, paths, ctx):
    if ctx["other_globals"] or ctx["git_env"] or ctx["dir_unread"]:
        return False
    if not readable_git_dir(directory):
        return False
    return deadline_git(directory, ["diff", "--quiet", "HEAD", "--", *paths])[0] == 0


def clean_rule(sub, args, directory, ctx):
    dry, interactive, i = False, False, 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            break
        if is_long(arg):
            hits = long_hits(arg, {"dry-run", "no-dry-run", "interactive", "no-interactive"},
                             {"force", "quiet"})
            if "no-interactive" in hits:
                interactive = False
            elif "interactive" in hits:
                interactive = True
            elif "no-dry-run" in hits:
                dry = False
            elif "dry-run" in hits:
                dry = True
            elif "=" not in arg and "exclude".startswith(arg[2:]):
                i += 1
            continue
        if is_short(arg):
            letters = short_letters(arg, "e")
            if "i" in letters:
                interactive = True
            if "n" in letters:
                dry = True
            if letters[-1] == "e" and len(letters) == len(arg) - 1:
                i += 1
    if dry or interactive:
        return "-"
    return ask("git clean deletes untracked files for good: no commit or stash holds them. "
               "Run `git clean -n` first and show its list.")


def reset_rule(sub, args, directory, ctx):
    for arg in args:
        if arg == "--":
            break
        if is_long(arg) and "hard" in long_hits(arg, {"hard"}, RESET_KNOWN):
            return ask(f"git reset --hard discards the work tree and the index: {LOST_UNCOMMITTED}. "
                       "Show `git status` first.")
    return "-"


def stash_rule(sub, args, directory, ctx):
    if args and args[0] in ("clear", "drop"):
        return ask(f"git stash {args[0]} deletes stashed work that nothing else holds. "
                   "Show `git stash list` first.")
    return "-"


def branch_rule(sub, args, directory, ctx):
    for arg in args:
        if arg == "--":
            break
        if (is_long(arg) and "force" in long_hits(arg, {"force"}, BRANCH_KNOWN)) or \
                (is_short(arg) and set(short_letters(arg, "u")) & set("DMCf")):
            return ask(f"This git branch {arg} deletes, renames over or resets a branch: "
                       "commits only that branch holds can be lost.")
    return "-"


def update_ref_rule(sub, args, directory, ctx):
    operands, i = [], 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--stdin":
            return ask("git update-ref --stdin reads the refs it rewrites from its input: the hook "
                       "cannot see them, and a branch it moves can lose commits.")
        if arg == "-m":
            i += 1
        elif not arg.startswith("-"):
            operands.append(arg)
    if operands and (operands[0] == "HEAD" or operands[0].startswith("refs/heads/")):
        return ask(f"git update-ref rewrites {operands[0]} directly, with no merge check: "
                   "the commits it pointed to can be lost.")
    return "-"


def checkout_rule(sub, args, directory, ctx):
    family = CHECKOUT_FAMILY[sub]
    staged = worktree = False
    for arg in args:
        if arg == "--":
            break
        if is_long(arg):
            hits = long_hits(arg, {"pathspec-from-file", "staged", "worktree"}, family["known"])
            if "pathspec-from-file" in hits:
                return ask(f"This git {sub} reads its paths from a file, so the hook cannot see "
                           "which files it overwrites.")
            staged = staged or "staged" in hits
            worktree = worktree or "worktree" in hits
        elif is_short(arg) and sub == "restore":
            letters = short_letters(arg, family["value_short"])
            staged = staged or "S" in letters
            worktree = worktree or "W" in letters
    if sub == "restore" and staged and not worktree:
        return "-"
    before, after, dashdash = split_operands(args, family["value_short"], family["value_long"])
    for operand in before + after:
        if TDD_TARGET.search(operand) or TDD_FROZEN.search(operand):
            return deny(f"BLOCKED: this git {sub} would rewrite '{operand}', a test-first module or "
                        "a test file, from git. A frozen test changes only through the plan, a "
                        "test-first module only after a proved RED (.claude/rules/05-testing.md). "
                        "Edit it with Write/Edit instead.")
    if sub == "restore":
        paths = before + after
    elif dashdash:
        paths = after
    elif len(before) > 1:
        paths = before[1:]
    elif before and has_glob_or_magic(before[0]):
        paths = before
    elif before and ctx["moved"]:
        return sequence_ask(f"git {sub}")
    elif before and os.path.exists(os.path.join(directory, before[0])):
        paths = before
    else:
        paths = []
    for path in paths:
        if has_glob_or_magic(path):
            return ask(f"This git {sub} overwrites '{path}' in the work tree, a pattern that reaches "
                       f"many files: {LOST_UNCOMMITTED}. Show `git status` first.")
    if paths and ctx["moved"]:
        return sequence_ask(f"git {sub}")
    for path in paths:
        if os.path.isdir(os.path.join(directory, path)):
            return ask(f"This git {sub} overwrites the directory '{path}' in the work tree: "
                       f"{LOST_UNCOMMITTED}. Show `git status` first.")
    if not paths or worktree_clean(directory, paths, ctx):
        return "-"
    return ask(f"This git {sub} overwrites {', '.join(paths)}, which hold uncommitted changes or "
               "could not be checked: those changes are lost. Show `git diff HEAD -- <paths>` first.")


def refspec_destination(spec):
    spec = spec.lstrip("+")
    if spec.startswith("^") or ":" not in spec:
        return ""
    return spec.split(":", 1)[1]


def fetch_long_name(name):
    """The fetch option a long name spells, exactly or by a prefix only it has; "" otherwise."""
    if name in FETCH_LONG:
        return name
    hits = [c for c in FETCH_LONG if c.startswith(name)] if name else []
    return hits[0] if len(hits) == 1 else ""


def fetch_option_ask(name, upload, head_ok):
    if name == "upload-pack":
        return upload
    if name == "update-head-ok":
        return head_ok
    if name == "server-option":
        return ask("This git fetch uses a server option (-o / --server-option): it sends a free "
                   "string to the remote, a channel for data to leave the machine. Show the "
                   "call, then let the user decide.")
    if name == "prune-tags":
        return ask("This git fetch uses --prune-tags (-P): it deletes the local tags the remote "
                   "no longer has. Show the call, then let the user decide.")
    if name == "force":
        return ask("This git fetch uses --force (-f): a refspec may overwrite a local tag or ref "
                   "without a fast-forward, and the old one is lost. Show the call, then let the "
                   "user decide.")
    if name == "set-upstream":
        return ask("This git fetch uses --set-upstream: it writes the branch's upstream into "
                   ".git/config. Show the call, then let the user decide.")
    if name in FETCH_SHALLOW:
        return ask(f"This git fetch uses --{name}: it changes the repository's shallow state "
                   "(which history is kept locally). Show the call, then let the user decide.")
    if name == "filter":
        return ask("This git fetch uses --filter: it turns the repository into a partial clone "
                   "(repositoryformatversion, remote.<r>.promisor and partialclonefilter written "
                   "into .git/config). Show the call, then let the user decide.")
    if name == "stdin":
        return ask("This git fetch uses --stdin: it reads refspecs the hook cannot see, which "
                   "may write any local ref. Show the refspecs, then let the user decide.")
    return "-"


def fetch_rule(args, upload, head_ok, directory="."):
    def unknown(arg):
        return ask(f"This git fetch uses '{arg}', an unknown or ambiguous option for the hook "
                   "(git 2.43's list): it cannot tell what it writes. Spell the option out in "
                   "full, then let the user decide.")

    positional, refmaps, multiple, i = [], [], False, 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            positional += args[i:]
            break
        if is_long(arg):
            spelled, eq, value = arg[2:].partition("=")
            name = fetch_long_name(spelled)
            if not name:
                return unknown(arg)
            if name == "multiple":
                multiple = True
            verdict = fetch_option_ask(name, upload, head_ok)
            if verdict != "-":
                return verdict
            if not eq and name in FETCH_LONG_VALUE:
                value = args[i] if i < len(args) else ""
                i += 1
            if name == "refmap":
                refmaps.append(value)
            continue
        if is_short(arg):
            for k, letter in enumerate(arg[1:], 1):
                if letter not in FETCH_SHORT:
                    return unknown(arg)
                verdict = fetch_option_ask(FETCH_SHORT_LONG.get(letter, ""), upload, head_ok)
                if verdict != "-":
                    return verdict
                if letter in FETCH_SHORT_VALUE:
                    if k == len(arg) - 1:
                        i += 1
                    break
            continue
        positional.append(arg)
    for repo in (positional if multiple else positional[:1]):
        if repo == ".":
            continue
        if not REMOTE_NAME.match(repo) or os.path.exists(os.path.join(directory, repo)):
            return ask(f"This git fetch names '{repo}', not a bare remote name: a URL or a path "
                       "can send data off the machine and pull untrusted content. Fetch a "
                       "configured remote instead.")
    for spec in refmaps + positional[1:]:
        dst = refspec_destination(spec)
        if dst and (dst.startswith("refs/heads/") or not dst.startswith("refs/")):
            return ask(f"This git fetch writes '{dst}', a local branch: it moves or force-rewinds "
                       "it outside the merge ask. Fetch into refs/remotes/ instead.")
        if dst and not dst.startswith("refs/remotes/"):
            return ask(f"This git fetch writes '{dst}', a ref outside refs/remotes/ (a tag, the "
                       "stash, notes or another local ref): it can move or replace it. Fetch "
                       "into refs/remotes/ instead.")
    return "-"


def network_rule(sub, args, directory, ctx):
    upload = ask(f"This git {sub} sets the upload-pack program: it runs an arbitrary command.")
    head_ok = ask(f"This git {sub} uses --update-head-ok: it can move the checked-out branch, "
                  "and the work tree no longer matches it.")
    if sub == "fetch":
        return fetch_rule(args, upload, head_ok, directory)
    short_values = NETWORK_VALUE_SHORT[sub]
    i = 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            break
        if is_long(arg):
            name, eq, _ = arg[2:].partition("=")
            hits = long_hits(arg, NETWORK_LONG, NETWORK_KNOWN | NETWORK_VALUE_LONG)
            if "upload-pack" in hits:
                return upload
            if "update-head-ok" in hits:
                return head_ok
            if not eq and ("refmap" in hits or name in NETWORK_VALUE_LONG):
                i += 1
            continue
        if is_short(arg):
            letters = short_letters(arg, short_values)
            if "u" in letters:
                return upload if sub in ("clone", "ls-remote") else head_ok
            if letters[-1] in short_values and len(letters) == len(arg) - 1:
                i += 1
    return "-"


CONFIG_READ_MARKS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}
CONFIG_READ_OPTS = CONFIG_READ_MARKS | {
    "--show-origin", "--show-scope", "--name-only", "--null", "-z", "--local", "--global",
    "--system", "--worktree", "--includes", "--no-includes", "--bool", "--int", "--bool-or-int",
    "--path", "--expiry-date", "--all", "--regexp"}
CONFIG_READ_VALUED = ("--type=", "--default=", "--url=", "--value=")


def config_rule(sub, args, directory, ctx):
    """A git config call passes only when every option is a read option spelled in full."""
    positional, marked = [], False
    for arg in args:
        if arg == "--" or not arg.startswith("-") or arg == "-":
            positional.append(arg)
        elif arg in CONFIG_READ_OPTS or arg.startswith(CONFIG_READ_VALUED):
            marked = marked or arg in CONFIG_READ_MARKS
        else:
            positional = None
            break
    if positional is not None and (
            marked or (positional and positional[0] in ("get", "list")) or len(positional) == 1):
        return "-"
    return ask("git config writes change what later git calls run (core.fsmonitor, core.hooksPath, "
               "filters, aliases). Only full-spelling reads (--get, --list, get, list) pass.")


def init_rule(sub, args, directory, ctx):
    return ask("git init creates or re-initialises a repository: its template can plant hooks and "
               "config that later git calls run.")


def worktree_rule(sub, args, directory, ctx):
    if not ctx["via_alias"] or not args or args[0] != "add":
        return "-"
    rest = args[1:]
    for arg in rest:
        if arg == "--":
            break
        if (is_long(arg) and "force" in long_hits(arg, {"force"}, {"detach", "checkout", "lock",
                                                                    "reason", "orphan", "quiet",
                                                                    "track", "guess-remote"})) or \
                (is_short(arg) and set(short_letters(arg, "bB")) & set("Bf")):
            return ask(f"This alias runs git worktree add {arg}: it resets an existing branch or "
                       "overrides git's own checks, and work on that branch can be lost.")
    before, after, _ = split_operands(rest, "bB", {"reason"})
    paths = before + after
    if not paths:
        return "-"
    if ctx["moved"]:
        return sequence_ask("alias of git worktree add")
    outside = ask(f"This alias runs git worktree add '{paths[0]}', a tree outside "
                  ".claude/worktrees/ (or one the hook could not place), where the kit's guarded "
                  "paths no longer apply.")
    res = quick_git(directory, ["rev-parse", "--show-toplevel"])
    if res is None or res.returncode != 0:
        return outside
    root = os.path.join(res.stdout.decode(errors="replace").strip(), ".claude", "worktrees")
    lexical = os.path.normpath(os.path.join(directory, paths[0]))
    if not lexical.startswith(os.path.normpath(root) + os.sep):
        return outside
    if not os.path.realpath(lexical).startswith(os.path.realpath(root) + os.sep):
        return outside
    return "-"


DESTRUCTIVE_RULES = {"clean": clean_rule, "reset": reset_rule, "stash": stash_rule,
                     "branch": branch_rule, "update-ref": update_ref_rule,
                     "checkout": checkout_rule, "restore": checkout_rule,
                     "worktree": worktree_rule, "config": config_rule, "init": init_rule,
                     **{s: network_rule for s in NETWORK_SUBS}}


def destructive_verdict(sub, args, directory, ctx):
    """`-`, `ask:<reason>` or `deny:<reason>`: what this call, alias expanded, can destroy."""
    for value in ctx["configs"]:
        key = value.partition("=")[0].lower()
        if key.endswith(".uploadpack") or (key.startswith("remote.") and key.endswith(".fetch")):
            return ask(f"This git call sets {key} on the command line: it picks the program git "
                       "runs, or rewrites which local refs a fetch moves.")
    runs, args, via_alias, problem = expand_alias(sub, args, directory)
    if problem:
        return ask(f"'git {sub}' is an alias the hook could not expand: {problem}.")
    rule = DESTRUCTIVE_RULES.get(runs)
    if rule is None:
        return "-"
    return rule(runs, args, directory, {**ctx, "via_alias": via_alias})


def parse_git(seg, start, base, assigns):
    directory, alias_cfg, i = base, 0, start
    git_dir = work_tree = None
    other_globals = dir_unread = False
    configs = []
    git_env = any(a.startswith("GIT_") for a in assigns)
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
        if opt not in ALLOWED_ADD_GLOBALS:
            other_globals = True
        if opt == "-C":
            directory = os.path.join(directory, value)
            if value.startswith("~") or any(ch in value for ch in "$`*?[{}"):
                dir_unread = True
        if name == "--git-dir" and value is not None:
            git_dir = value
        if name == "--work-tree" and value is not None:
            work_tree = value
        if name in ("-c", "--config-env") and value:
            configs.append(value)
            if hides_config(value):
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
    args = strip_redirections(seg[i + 1:])
    if sub not in ADD_SUBS:
        addv = "-"
    elif state["cd"]:
        addv = "cd"
    else:
        addv = add_verdict(args, directory, other_globals, git_env, dir_unread)
        if (addv == "ok" or addv.startswith("unsafe:")) and state["prior"]:
            addv = "prior"
    destr = "-"
    if sub != HIDDEN:
        destr = destructive_verdict(sub, args, directory, {
            "configs": configs, "other_globals": other_globals, "git_env": git_env,
            "dir_unread": dir_unread, "moved": state["cd"] or state["prior"]})
    if sub != HIDDEN and sub not in ADD_SUBS and destr == "-":
        destr = foreign_verdict(sub, directory, state["cd"])
    destr = destr.replace("\t", " ").replace("\n", " ")
    rows.append(f"{sub}\t{clean}\t{alias_cfg}\t{force}\t{flags_column(args)}"
                f"\t{addv.replace(chr(10), ' ')}\t{destr}")


def nested(text, base, depth):
    try:
        walk(text, base, depth)
    except ValueError:
        state["unread"] = True


def quiet_git(seg, i):
    if seg[i] != "git" and not seg[i].endswith("/git"):
        return False
    j = i + 1
    while j < len(seg) and seg[j].startswith("-"):
        j += 2 if seg[j] in WITH_VALUE else 1
    return j >= len(seg) or seg[j] in QUIET_SUBS


def walk(text, base, depth):
    pending = False
    for seg in segments(tokens(text)):
        if pending:
            state["prior"] = True
        if depth < 3:
            for tok in seg:
                if "$(" in tok or "`" in tok:
                    nested(tok.replace("$(", " ( ").replace("`", " ; "), base, depth + 1)
        i = 0
        while i < len(seg) and (seg[i] in PREFIXES or is_assignment(seg[i])):
            i += 1
        if i >= len(seg):
            pending = any(is_assignment(t) for t in seg)
            continue
        pending = not quiet_git(seg, i)
        prog = seg[i]
        if prog in ("cd", "pushd"):
            state["cd"] = True
            continue
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
    if pending:
        state["prior"] = True


def logical_lines(text):
    out, cur, quote, i = [], [], "", 0
    while i < len(text):
        ch = text[i]
        if quote == "'":
            quote = "" if ch == "'" else quote
        elif ch == "\\" and text[i + 1:i + 2] == "\n":
            i += 2
            continue
        elif ch == "\\" and i + 1 < len(text):
            cur.append(ch)
            i += 1
            ch = text[i]
        elif quote == '"':
            quote = "" if ch == '"' else quote
        elif ch in "'\"":
            quote = ch
        elif ch == "\n":
            out.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out


def heredoc_free_lines(text):
    lines = text.split("\n")
    kept, i = [], 0
    while i < len(lines):
        kept.append(lines[i])
        match = HEREDOC.search(lines[i])
        if match:
            strip_tabs, word = match.group(1) == "-", match.group(2)
            for j in range(i + 1, len(lines)):
                candidate = lines[j].lstrip("\t") if strip_tabs else lines[j]
                if candidate == word:
                    i = j
                    break
        i += 1
    return logical_lines("\n".join(kept))


def fallback_rows(text, base, strict=False):
    found = []
    for line in heredoc_free_lines(text):
        try:
            words, split_only = tokens(line), False
        except ValueError:
            words, split_only = line.split(), True
        for seg in segments(words):
            for k, tok in enumerate(seg):
                if tok != "git" and not tok.endswith("/git"):
                    continue
                j = k + 1
                while j < len(seg) and seg[j].startswith("-"):
                    j += 2 if seg[j] in WITH_VALUE else 1
                if j >= len(seg):
                    continue
                sub, rest = seg[j], strip_redirections(seg[j + 1:])
                if sub in ADD_SUBS:
                    found.append(f"?fb-add\t{base}\t0\t0\t-\t-")
                elif sub in ("commit", "switch", "checkout"):
                    family = COMMIT if sub == "commit" else SWITCH
                    if split_only:
                        bare = [w.replace("'", "").replace('"', "") for w in rest]
                        flags = [f for f in classify(bare, family, stop_at_dashdash=False)
                                 if f != "pathspec"]
                    else:
                        flags = classify(rest, family)
                    if strict:
                        found.append(f"?fb-cap\t{base}\t0\t0\t{sub}:{','.join(flags)}\t-")
                    elif flags:
                        found.append(f"?fb-flags\t{base}\t0\t0\t{', '.join(flags)}\t-")
    return found


def raw_rows(text, base, adds_only=False):
    words = [w for w in RAW_SEPARATORS.split(text.replace("\\\n", "")) if w]
    found = []
    for k, word in enumerate(words):
        if word != "git" and not word.endswith("/git"):
            continue
        j = k + 1
        while j < len(words) and words[j].startswith("-"):
            j += 2 if words[j] in WITH_VALUE else 1
        if j >= len(words):
            continue
        if words[j] in ADD_SUBS:
            found.append(f"?fb-add\t{base}\t0\t0\t-\t-")
        elif not adds_only and words[j] in ("commit", "switch", "checkout"):
            found.append(f"?fb-cap\t{base}\t0\t0\t{words[j]}:\t-")
    return found


failed = False
try:
    walk(sys.argv[1], sys.argv[2], 0)
except ValueError:
    failed = True
base_dir = sys.argv[2].replace("\t", " ").replace("\n", " ")
if failed:
    plain = "\n".join(heredoc_free_lines(sys.argv[1]))
    out = fallback_rows(sys.argv[1], base_dir) + raw_rows(plain, base_dir, adds_only=True)
    out.append("UNPARSABLE")
else:
    out = rows
    if state["unread"]:
        out.append("?unread\t.\t0\t0\t-\t-")
        out.extend(fallback_rows(sys.argv[1], base_dir))
    if state["capped"]:
        out.extend(fallback_rows(sys.argv[1], base_dir, strict=True))
        out.extend(raw_rows(sys.argv[1], base_dir) + ["UNPARSABLE"])
out.append(f"#end\t{len(out)}")
print("\n".join(out))
PY
}

# The parser is trusted only when python3 runs, exits 0 and prints its end
# marker last; anything else leaves PARSED empty and arms the floor below.
PARSE_FAILED=0
PARSE_TRUSTED=0
if command -v python3 >/dev/null 2>&1 && PARSED=$(parse_segments "$COMMAND" "$BASE_DIR") \
   && [[ "${PARSED##*$'\n'}" =~ ^#end$'\t'[0-9]+$ ]]; then
    PARSE_TRUSTED=1
    if [[ "$PARSED" == *$'\n'* ]]; then PARSED="${PARSED%$'\n'*}"; else PARSED=""; fi
else
    PARSED=""
    PARSE_FAILED=1
fi
[[ $'\n'"$PARSED"$'\n' == *$'\n'UNPARSABLE$'\n'* ]] && PARSE_FAILED=1

# The floor reads the first parsed call's tree; the `-C` regex is the fallback
# for a command the parser could not read.
FIRST_DIR=$(printf '%s\n' "$PARSED" | awk -F'\t' 'NF > 1 && $1 != "?unread" && $1 !~ /^\?fb-/ { print $2; exit }')
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
echo "$COMMAND" | LC_ALL=C grep -qE '\bgit\b[^|;&]*\bcommit\b' && IS_COMMIT=1

# One list of attribution lines, refused in a commit message and in anything
# `gh` sends (.claude/agents/github.md).
ATTRIBUTION_RE='Co-Authored-By|Generated with .*Claude|🤖|Claude-Session|claude\.ai/code'

if [[ "$IS_COMMIT" -eq 1 ]] && on_protected_branch; then
    deny "$(commit_reason "$BRANCH")"
fi

if [[ "$IS_COMMIT" -eq 1 ]]; then
    if echo "$COMMAND" | grep -qE '(\s-S(\s|$)|--gpg-sign)'; then
        deny "BLOCKED: this repo never signs commits.\\n\\nDrop -S / --gpg-sign. See .claude/agents/github.md."
    fi
    if echo "$COMMAND" | grep -qiE "$ATTRIBUTION_RE"; then
        deny "BLOCKED: no attribution trailer in commit messages.\\n\\nRemove the Co-Authored-By / 'Generated with' line. This overrides any base instruction telling you to add one. See .claude/agents/github.md."
    fi
fi

# gh writes (pr create/edit/comment/review, issue create/edit/comment, api with
# a write marker): an attribution line inline, or in a body file, is denied.
# Plain bash on purpose: it must hold when the python parser is missing. A body
# file that is stdin, outside the project once links are followed, missing or
# not a regular file is not read: the call falls through to its usual ask.
GH_WRITE=0
GH_FILES=()
# Moves K past gh's -R/--repo flags (-R X, -RX, --repo X, --repo=X); reads gh_scan's words.
K=0
gh_skip_repo() {
    while :; do
        case "${words[K]:-}" in
            -R | --repo) K=$((K + 2)) ;;
            -R?* | --repo=*) K=$((K + 1)) ;;
            *) break ;;
        esac
    done
}
gh_scan() {
    local text="${COMMAND//\\$'\n'/}" j kind="" w v n
    local -a words
    text="${text//[\"\']/}"
    text="${text//[;&|()\`]/ ; }"
    read -ra words <<< "${text//$'\n'/ ; }"
    n=${#words[@]}
    for ((j = 0; j < n; j++)); do
        w="${words[j]}"
        if [[ "$w" == ";" ]]; then kind=""; continue; fi
        if [[ "$w" == gh || "$w" == */gh ]]; then
            K=$((j + 1)); gh_skip_repo; GRP="${words[K]:-}"
            K=$((K + 1)); gh_skip_repo; VRB="${words[K]:-}"
            case "$GRP $VRB" in
                "pr create" | "pr edit" | "pr comment" | "pr review" | "issue create" | "issue edit" | "issue comment")
                    kind=body; GH_WRITE=1 ;;
                api\ *) kind=api ;;
                *) kind="" ;;
            esac
            continue
        fi
        [[ -n "$kind" ]] || continue
        v=""
        if [[ "$kind" == body ]]; then
            case "$w" in
                --body-file=*) v="${w#*=}" ;;
                --body-file | -F) v="${words[j + 1]:-}" ;;
                -F?*) v="${w#-F}" ;;
            esac
        else
            case "$w" in
                -X | --method)
                    [[ "${words[j + 1]:-}" =~ ^[Gg][Ee][Tt]$ ]] || GH_WRITE=1 ;;
                -X?* | --method=*)
                    v="${w#-X}"; v="${v#--method=}"
                    [[ "$v" =~ ^[Gg][Ee][Tt]$ ]] || GH_WRITE=1
                    v="" ;;
                -f | -f?* | --raw-field | --raw-field=*) GH_WRITE=1 ;;
                -F | --field) GH_WRITE=1; v="${words[j + 1]:-}" ;;
                -F?* | --field=*) GH_WRITE=1; v="${w#-F}"; v="${v#--field=}" ;;
                --input) GH_WRITE=1; GH_FILES+=("${words[j + 1]:-}") ;;
                --input=*) GH_WRITE=1; GH_FILES+=("${w#*=}") ;;
            esac
            [[ "$v" == *=@* ]] && v="${v#*=@}" || v=""
        fi
        [[ -n "$v" ]] && GH_FILES+=("$v")
    done
    return 0
}
if echo "$COMMAND" | LC_ALL=C grep -qE '\bgh\b'; then
    gh_scan
    if [[ "$GH_WRITE" -eq 1 ]]; then
        if echo "$COMMAND" | grep -qiE "$ATTRIBUTION_RE"; then
            deny "BLOCKED: attribution line in a gh body (inline): the project forbids it (.claude/agents/github.md).\\n\\nRemove the Co-Authored-By / 'Generated with' / session line and send it again."
        fi
        for GH_FILE in ${GH_FILES[@]+"${GH_FILES[@]}"}; do
            [[ -n "$GH_FILE" && "$GH_FILE" != - ]] || continue
            GH_REAL="$(cwk_real_file "$GH_FILE" "$BASE_DIR")" || continue
            cwk_real_rel "$GH_FILE" "$BASE_DIR" >/dev/null || continue
            [[ -f "$GH_REAL" && -r "$GH_REAL" ]] || continue
            if head -c 1048576 -- "$GH_REAL" 2>/dev/null | grep -qiE "$ATTRIBUTION_RE"; then
                deny "BLOCKED: attribution line in a gh body (file $GH_FILE): the project forbids it (.claude/agents/github.md).\\n\\nRemove the Co-Authored-By / 'Generated with' / session line from the file and send it again."
            fi
        done
    fi
fi

# The python floor: the parser did not run or cannot be trusted, so the
# subcommand after each `git` word (global options and their values skipped)
# decides alone — every add denied first, then every commit/switch/checkout asked.
FLOOR_SUBS=()
floor_subs() {
    local text="${COMMAND//\\$'\n'/}" j
    local -a words
    text="${text//[;&|()\"\'\`\$]/ }"
    read -ra words <<< "${text//$'\n'/ }"
    for ((j = 0; j < ${#words[@]}; j++)); do
        [[ "${words[j]}" == git || "${words[j]}" == */git ]] || continue
        while ((j + 1 < ${#words[@]})) && [[ "${words[j + 1]}" == -* ]]; do
            case "${words[j + 1]}" in
                -C|-c|--git-dir|--work-tree|--namespace|--config-env|--exec-path|--attr-source) j=$((j + 2)) ;;
                *) j=$((j + 1)) ;;
            esac
        done
        if ((j + 1 < ${#words[@]})); then
            FLOOR_SUBS+=("${words[j + 1]}")
        fi
    done
    return 0
}
if [[ "$PARSE_TRUSTED" -eq 0 ]]; then
    floor_subs
    for FLOOR_SUB in "${FLOOR_SUBS[@]}"; do
        [[ "$FLOOR_SUB" == add || "$FLOOR_SUB" == stage ]] && deny "$ADD_UNREADABLE_REASON"
    done
    for FLOOR_SUB in "${FLOOR_SUBS[@]}"; do
        [[ "$FLOOR_SUB" == commit ]] && on_protected_branch && deny "$(commit_reason "$BRANCH")"
    done
    for FLOOR_SUB in "${FLOOR_SUBS[@]}"; do
        if [[ "$FLOOR_SUB" =~ ^(commit|switch|checkout)$ ]]; then
            ask "The hook could not run its parser (python3 missing or failed); this git $FLOOR_SUB is not checked. Show the exact call, then let the user decide."
        fi
    done
fi

while IFS=$'\t' read -r SUB DIR _ _ _ ADDV DESTR; do
    [[ "$SUB" == "?fb-add" ]] && deny "$ADD_UNREADABLE_REASON"
    [[ -z "$SUB" || "$SUB" == UNPARSABLE || "$SUB" == "?unread" || "$SUB" == "?fb-flags" || "$SUB" == "?fb-cap" ]] && continue
    if [[ -n "$ADDV" && "$ADDV" != "-" && "$ADDV" != ok && "$ADDV" != unsafe:* ]]; then
        deny "$(add_reason "$ADDV")"
    fi
    [[ "$DESTR" == deny:* ]] && deny "${DESTR#deny:}"
    effective_sub "$SUB" "$DIR"
    [[ "$EFF_SUB" == commit ]] && dir_protected "$DIR" && deny "$(commit_reason "$SEG_BRANCH")"
    [[ "$SUB" != add && "$SUB" != stage && ( "$EFF_SUB" == add || "$EFF_SUB" == stage ) ]] && deny "$ADD_HIDDEN_REASON"
done <<< "$PARSED"

# -----------------------------------------------------------------------------
# ASK pass — anything that leaves the machine or merges into a protected branch
#
# GitHub writes first: they act on a REMOTE, so they need no git tree at all
# (`gh issue create -R owner/repo` works from anywhere). Only after the deny pass,
# so a gh ask never hides a commit on a protected branch.
# -----------------------------------------------------------------------------

if echo "$COMMAND" | grep -qE '\bgh\s+((((-R|--repo)\s+[^ ]+)|(-R[^ ]+)|(--repo=[^ ]+))\s+)*pr\s+((((-R|--repo)\s+[^ ]+)|(-R[^ ]+)|(--repo=[^ ]+))\s+)*(create|merge|edit|close|reopen|ready|review)\b'; then
    ask "This acts on a pull request. Show the title, body and target branch first, then let the user decide."
fi

if echo "$COMMAND" | grep -qE '\bgh\s+((((-R|--repo)\s+[^ ]+)|(-R[^ ]+)|(--repo=[^ ]+))\s+)*(issue|release|repo|api)\b'; then
    ask "This writes to GitHub. Show exactly what will be sent, then let the user decide."
fi

if echo "$COMMAND" | LC_ALL=C grep -qE '\bgh\b[^|;&]*\bcomment\b'; then
    ask "This posts a public comment. Show its full text first, then let the user decide."
fi

if echo "$COMMAND" | LC_ALL=C grep -qE '\bgit\s+push\b[^|;&]*(-f\b|--force\b)'; then
    ask "$FORCE_REASON"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
    ask "$PUSH_REASON"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+(merge|rebase)($|[^-[:alnum:]_])' && on_protected_branch; then
    ask "$(merge_reason "$BRANCH")"
fi

while IFS=$'\t' read -r SUB DIR ALIAS_CFG FORCE FLAGS ADDV DESTR; do
    [[ "$ADDV" == unsafe:* ]] && ask "This git add targets '${ADDV#unsafe:}', not a repository the hook can read safely (its git dir is not a .git directory or a linked worktree's), so the hook did not dry-run it and did not check what this stages, so it may include secrets. Show the exact call, then let the user decide."
    [[ "$SUB" == "?fb-flags" ]] && ask "The hook could not read this git call (a wrapper or a parse failure), and it carries $FLAGS. Show the exact call, then let the user decide."
    if [[ "$SUB" == "?fb-cap" ]]; then
        CAP_ITEMS="${FLAGS#*:}"
        ask "The hook could not read this whole call (more than 50 git calls); this git ${FLAGS%%:*} carries ${CAP_ITEMS:-nothing the hook could check}. Show the exact call, then let the user decide."
    fi
    [[ -z "$SUB" || "$SUB" == UNPARSABLE || "$SUB" == "?unread" || "$SUB" == "?fb-add" ]] && continue
    [[ "$SUB" == "?hidden" ]] && ask "The git subcommand is built from an expansion, so it is hidden. Show the expanded command, then let the user decide."
    [[ "$ALIAS_CFG" == 1 ]] && ask "This git call defines an alias or config include outside the repo config, so the subcommand it runs is hidden. Show the expanded command, then let the user decide."
    if [[ "$SUB" == push || "$SUB" == send-pack ]]; then
        [[ "$FORCE" == 1 ]] && ask "$FORCE_REASON"
        ask "$PUSH_REASON"
    fi
    effective_sub "$SUB" "$DIR"
    if ! is_builtin "$SUB"; then
        [[ -d "$DIR" ]] || ask "'git $SUB' may be an alias, and '$DIR' does not exist to read it from. Show what it runs, then let the user decide."
        if [[ "$ALIAS" == '!'* ]] || echo "$ALIAS" | grep -qE '\b(push|send-pack|merge|rebase)\b'; then
            ask "'git $SUB' is an alias for '$ALIAS'. Show what it runs, then let the user decide."
        fi
        if [[ -n "$ALIAS" ]] && ! is_builtin "$EFF_SUB"; then
            ask "'git $SUB' is an alias for '$ALIAS', which is not a plain builtin command (an alias chain). Show what it runs, then let the user decide."
        fi
    fi
    if [[ -n "$ALIAS" && "$ALIAS" == *[[:space:]]* ]] && [[ "$EFF_SUB" =~ ^(commit|switch|checkout)$ ]]; then
        ask "'git $SUB' is an alias for '$ALIAS', which carries its own flags. Show what it runs, then let the user decide."
    fi
    [[ "$DESTR" == ask:* ]] && ask "${DESTR#ask:}"
    COMMIT_FLAGS=$(row_flags c "$FLAGS")
    SWITCH_FLAGS=$(row_flags s "$FLAGS")
    if [[ "$EFF_SUB" == commit && -n "$COMMIT_FLAGS" ]]; then
        ask "This commit uses $COMMIT_FLAGS (it rewrites history, skips the hooks, or commits beyond what is staged). Say why, then let the user decide."
    fi
    if [[ "$EFF_SUB" =~ ^(switch|checkout)$ && -n "$SWITCH_FLAGS" ]]; then
        ask "This git $EFF_SUB uses $SWITCH_FLAGS: it discards local changes or resets an existing branch. Say why, then let the user decide."
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
    if echo "$COMMAND" | LC_ALL=C grep -qE '\b(push|send-pack|merge|rebase)\b|alias\.' \
       || { echo "$COMMAND" | LC_ALL=C grep -qE '\bcommit\b' \
            && echo "$COMMAND" | LC_ALL=C grep -qE '(^|[[:space:]])(-C|--git-dir|--work-tree)|GIT_DIR|GIT_WORK_TREE'; }; then
        ask "The hook could not read which git command runs here. Show the exact git calls, then let the user decide."
    fi
    if echo "$COMMAND" | LC_ALL=C grep -qE '(^|[^A-Za-z0-9_-])fetch($|[^A-Za-z0-9_-])'; then
        ask "The hook could not parse this git fetch (an unclosed quote or an escape it cannot read), so it cannot see which refs it writes. Show the exact call, then let the user decide."
    fi
fi

grammar_triggered() {
    [[ "$1" =~ git($|[^A-Za-z0-9_]) ]] && [[ "$1" =~ (^|[^A-Za-z0-9_])(add|stage|commit|switch)($|[^A-Za-z0-9_]) ]]
}

grammar_value_ok() {
    [[ "$1" != -* && "$1" != . && "/$1/" != */../* ]]
}

grammar_add_ok() {
    local dir="$1" tree="$BASE_DIR" path full
    local -a paths
    if [[ -n "$dir" ]]; then
        grammar_value_ok "$dir" || return 1
        if [[ "$dir" == /* ]]; then tree="$dir"; else tree="$BASE_DIR/$dir"; fi
    fi
    read -r -a paths <<< "$2"
    for path in "${paths[@]}"; do
        grammar_value_ok "$path" || return 1
        if [[ "$path" == /* ]]; then full="$path"; else full="$tree/$path"; fi
        [[ -d "$full" ]] && return 1
    done
    return 0
}

grammar_strict() {
    local text="$1"
    local safe='[A-Za-z0-9._/@+-]+' word='[A-Za-z0-9._/@+:-]+' branch='[A-Za-z0-9._/-]+'
    local double='"[^"$`\\]+"' single="'[^'\$\`\\\\]+'"
    local add_form="^git( -C ($safe))? (add|stage)( --)?(( $safe)+)\$"
    local commit_form="^git( -C ($safe))? commit -m ($double|$single|$word)\$"
    local switch_form="^git switch -c ($branch)\$"
    text="${text#"${text%%[! $'\t']*}"}"
    text="${text%"${text##*[! $'\t']}"}"
    [[ "$text" =~ [[:cntrl:]] ]] && return 1
    if [[ "$text" =~ $add_form ]]; then
        grammar_add_ok "${BASH_REMATCH[2]}" "${BASH_REMATCH[5]}"
    elif [[ "$text" =~ $commit_form ]]; then
        # Group 3 is the message; group 2 the -C tree, checked like `git -C <tree> add`'s.
        [[ "${BASH_REMATCH[3]}" != -* ]] || return 1
        [[ -z "${BASH_REMATCH[2]}" ]] || grammar_value_ok "${BASH_REMATCH[2]}"
    elif [[ "$text" =~ $switch_form ]]; then
        [[ "${BASH_REMATCH[1]}" != -* ]]
    else
        return 1
    fi
}

grammar_decide() {
    # Under a UTF-8 locale, [A-Za-z0-9] in a bash regex also matches non-ASCII letters.
    local LC_ALL=C
    grammar_triggered "$COMMAND" || grammar_triggered "$NORM" || return 0
    if grammar_strict "$COMMAND"; then
        # `git -C <tree> commit -m "<one line>"` has no settings allow (no inner `*` in
        # an allow): every deny above has run, so the strict form is allowed here.
        # Only a tree that is the project or one of its worktrees; any other repo gets no decision.
        if [[ "$COMMAND" =~ ^[[:space:]]*git\ -C\ ([^[:space:]]+)\ commit\ -m\  ]]; then
            local c_tree="${BASH_REMATCH[1]}" c_real p_real w_line w_real
            c_tree="${c_tree#[\"\']}"
            c_tree="${c_tree%[\"\']}"
            [[ "$c_tree" == /* ]] || c_tree="$BASE_DIR/$c_tree"
            c_real="$(cd "$c_tree" 2>/dev/null && pwd -P)" || c_real=""
            p_real=""
            if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
                p_real="$(cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P)" || p_real=""
            fi
            if [[ -n "$c_real" && -n "$p_real" ]]; then
                if [[ "$c_real" == "$p_real" ]]; then
                    decide allow "a one-line commit in another tree of the project (here the project tree itself), the strict form the git hook polices"
                fi
                while IFS= read -r w_line; do
                    [[ "$w_line" == "worktree "* ]] || continue
                    w_real="$(cd "${w_line#worktree }" 2>/dev/null && pwd -P)" || continue
                    if [[ "$c_real" == "$w_real" ]]; then
                        decide allow "a one-line commit in another tree of the project (a worktree), the strict form the git hook polices"
                    fi
                done < <(git -C "$p_real" worktree list --porcelain 2>/dev/null)
            fi
        fi
        return 0
    fi
    ask "This is not a plain git call: only \`git add <paths>\`, \`git commit -m \"<one line>\"\` and \`git switch -c <branch>\` run without a prompt, each alone in its call. Show the exact call, then let the user decide."
}

grammar_decide

exit 0
