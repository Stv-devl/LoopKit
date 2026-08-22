#!/usr/bin/env bash
#
# Hook: prevent-destructive-commands
# Event: PreToolUse (Bash)
# Purpose: Block dangerous commands that could delete directories or cause data loss
#

set -e
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq

# Read JSON from stdin
INPUT=$(cat)

# Extract command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if no command
if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Emit a decision and stop.
#
# Built with jq, never with a heredoc. A reason interpolating a path or a branch
# name that contains a `"` produced unparseable JSON, and unparseable JSON is
# DROPPED — the deny vanished silently, which is the one failure mode a guardrail
# must not have. The `${x//\\n/}` expansion turns the authored `\n` into real
# newlines and leaves every other backslash alone (a path is full of them).
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
# `ask` is not a block: it forces the permission prompt back in front of the user
# even when the command would otherwise be auto-approved. Same idiom as
# enforce-git-workflow.sh.
ask()  { decide "ask"  "$1"; }

# =============================================================================
# WORKTREES - a worktree is deleted by git, never by rm
# (checked first: it carries the actionable message, .claude/ would otherwise
#  be caught by the generic protected-dirs rule below)
# =============================================================================

# git worktree remove --force: deletes a worktree WITH its uncommitted work.
# The plain `git worktree remove` refuses a dirty tree — that refusal is the
# safety net (.claude/guides/10-worktrees.md), so don't let --force erase it.
if echo "$COMMAND" | grep -qE 'git\s+worktree\s+remove\b[^|;&]*(\s-f\b|\s--force\b)'; then
    deny "BLOCKED: 'git worktree remove --force' destroys uncommitted work.\\n\\nRun it without --force. If it refuses, the worktree is dirty: commit or report it, don't force."
fi

# rm -rf on a worktree directory: same destruction, and it leaves git's
# administrative files behind (needs `git worktree prune` afterwards).
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+)+[^|;&]*(\.claude/)?worktrees(/|\s|$)'; then
    deny "BLOCKED: Do not delete a worktree with rm.\\n\\nUse 'git worktree remove .claude/worktrees/<slug>' — it checks for uncommitted work and cleans git's metadata."
fi

# =============================================================================
# PROTECTED DIRECTORIES - Block recursive delete
# =============================================================================

# CONFIGURE: the top-level folders that must never be deleted recursively.
# Add the ones this repo owns (backend, infra, migrations...).
PROTECTED_DIRS="src|shared|\.claude|public|node_modules|dist"

# The recursive flag, in every spelling: -r, -rf, -fr, -Rf, --recursive.
# The target is checked SEPARATELY from the flags, because tying the two together
# ("flags immediately followed by the directory") is what made the previous
# version miss every real-world form: `rm -rf ./src`, `rm -rf /abs/path/src` and
# `rm -r -- src` all passed while only the bare `rm -rf src` was caught.
RM_RECURSIVE='(^|[|;&(`[:space:]])rm([[:space:]]+-[a-zA-Z-]+)*[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)'

# The target test runs on the rm's OWN segment, never on the whole command.
# Testing the whole command is a false positive waiting to happen: a chain like
# `rm -rf /tmp/x; mkdir -p .claude/hooks src` has a recursive rm and the word
# `.claude` in it, and blocking that is both wrong and infuriating. Splitting on
# the shell separators keeps each rm judged on what it actually deletes.
PROTECTED_TARGET="(^|[[:space:]'\"/])($PROTECTED_DIRS)/?([[:space:]]|;|&|\||\"|'|\$)"

# `|| [[ -n "$SEG" ]]` is not optional: tr emits no trailing newline, so a
# single-segment command (`rm -rf src`) ends without one and a plain
# `while read` never runs its body — the rule silently checked nothing.
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE "$RM_RECURSIVE" || continue

    # A protected dir as a whole path segment: `src`, `./src`, `src/`,
    # `/abs/path/src/`. A path INSIDE one (`dist/assets`) stays deletable — that
    # is the documented escape ("specify a subdirectory").
    if echo "$SEG" | grep -qE "$PROTECTED_TARGET"; then
        deny "BLOCKED: Cannot delete protected directory recursively.\\n\\nProtected: src/, shared/, .claude/, public/, node_modules/, dist/\\n\\nSpecify a subdirectory or specific files instead."
    fi

    # Root, home, cwd — with or without a trailing slash. The missing `/?` is
    # what let `rm -rf ~/` through while `rm -rf ~` was blocked.
    if echo "$SEG" | grep -qE '[[:space:]](/|~|\$HOME|\$\{HOME\}|\$PWD|\$\{PWD\})/?[[:space:]]*$'; then
        deny "BLOCKED: Cannot delete root or home directory."
    fi

    # rm -rf * / . / .. — and `/*`, `~/*`, which the previous form also missed.
    if echo "$SEG" | grep -qE '[[:space:]](\*|\.\.?|[~/][^[:space:]]*\*)/?[[:space:]]*$'; then
        deny "BLOCKED: 'rm -rf *' or 'rm -rf .' is too dangerous.\\n\\nSpecify exact files/folders to delete instead."
    fi

    # --no-preserve-root is never anything but an attempt to wipe /.
    if echo "$SEG" | grep -qE '\-\-no-preserve-root'; then
        deny "BLOCKED: '--no-preserve-root' removes the last safety on 'rm -rf /'."
    fi
done < <(cwk_segments "$COMMAND")

# rm -rf without any target
if echo "$COMMAND" | grep -qE 'rm\s+-[a-zA-Z]*r[a-zA-Z]*f?\s*$'; then
    deny "BLOCKED: 'rm -rf' without target is not allowed."
fi

# `find <protected> -delete` / `-exec rm` is a recursive delete that never spells
# `rm -r`, so none of the rules above see it. The target test is the same one the
# rm rules use — deliberately not re-anchored on "right after `find`", because
# trying to enforce that ordering inside one regex is what silently retired this
# check the first time (a `\$` inside a double-quoted string is a literal dollar,
# not an end-of-line).
# `|| [[ -n "$SEG" ]]` is not optional: tr emits no trailing newline, so a
# single-segment command (`rm -rf src`) ends without one and a plain
# `while read` never runs its body — the rule silently checked nothing.
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE '\bfind\b.*(-delete\b|-exec(dir)?[[:space:]]+rm\b)' || continue
    if echo "$SEG" | grep -qE "$PROTECTED_TARGET"; then
        deny "BLOCKED: 'find ... -delete' on a protected directory is a recursive delete under another name.\\n\\nProtected: src/, shared/, .claude/, public/, node_modules/, dist/\\n\\nTarget specific files instead, and list them before deleting."
    fi
done < <(cwk_segments "$COMMAND")

# =============================================================================
# SECRET FILES - Block reading/copying secrets via shell (file-read hooks only
# cover the Read/Edit tools; Bash would otherwise bypass them)
# =============================================================================

# The verb list is the whole strength of this rule, and the short version was a
# sieve: `sed`, `awk`, `python`, an interpreter, a `<` redirection and
# `--env-file` all read a secret without naming a single verb it listed. Worse,
# `Bash(sed -n *)` is in the auto-approve list of settings.json, so
# `sed -n 1p .env` printed a secret with no prompt at all.
SECRET_FILE='(\.env(\.[A-Za-z0-9_-]+)?|\.pem|\.key|credentials)'
SECRET_VERB='cat|less|more|head|tail|tac|nl|bat|batcat|grep|egrep|fgrep|rg|ag|ack'
SECRET_VERB="$SECRET_VERB|sed|awk|gawk|mawk|perl|python|python3|ruby|node|deno|bun|php"
SECRET_VERB="$SECRET_VERB|jq|yq|xxd|od|strings|hexdump|base64|shasum|md5sum"
SECRET_VERB="$SECRET_VERB|cp|mv|scp|rsync|tar|zip|curl|wget|install"
SECRET_VERB="$SECRET_VERB|source|export|dotenv|vim|vi|nano|emacs|open|code"

# The terminator class has to include the quote characters, or an interpreter
# one-liner slips through on punctuation alone: `python3 -c "open('.env')"` ends
# the path on a `'`, not on a space.
# `]` is deliberately NOT in the class: inside a bracket expression it is only
# literal in first position, so writing it anywhere else silently closes the
# class early and the whole alternative stops matching.
SQ="'"
SECRET_END="([[:space:]]|[\"),;]|$SQ|\\.|\$)"
SECRET_RE="\b($SECRET_VERB)\b[^|;&]*$SECRET_FILE$SECRET_END"
# A `<` redirection reads the file with no verb of its own, and `--env-file`
# hands it to another process wholesale.
SECRET_RE="$SECRET_RE|<[[:space:]]*[\"']?[^|;&<>[:space:]\"']*$SECRET_FILE"
SECRET_RE="$SECRET_RE|--env-file[=[:space:]][\"']?[^|;&[:space:]\"']*$SECRET_FILE"
# `. ./.env` — the POSIX source builtin, which no \b can anchor.
SECRET_RE="$SECRET_RE|(^|[;&|][[:space:]]*)\.[[:space:]]+[^|;&]*$SECRET_FILE"

if echo "$COMMAND" | grep -qE "$SECRET_RE"; then
    # Template env files contain no secrets — strip them, then re-check.
    # CONFIGURE: this whitelist is duplicated in protect-files.sh
    # (ENV_TEMPLATE_RE). Change both, or the shell and the tools stop protecting
    # the same set of files.
    SANITIZED=$(echo "$COMMAND" | sed -E 's/\.env\.(example|sample|template)//g')
    if echo "$SANITIZED" | grep -qE "$SECRET_RE"; then
        deny "BLOCKED: Reading or copying secret files (.env*, *.key, *.pem, credentials) via shell is not allowed.\\n\\nAsk the user for variable NAMES (not values) or check .env.example."
    fi
fi

# =============================================================================
# DANGEROUS SYSTEM COMMANDS - Always blocked
#
# ORDER MATTERS, and it is the reason this block sits ABOVE the source-write
# section rather than below it. `decide` exits on the first match, so an `ask`
# emitted early wins over every `deny` that would have fired later:
# `echo x > a.ts && mkfs.ext4 /dev/sdb` came back as a permission prompt instead
# of a block. Every deny in this file now precedes the only `ask` it contains.
# =============================================================================

# Disk operations
if echo "$COMMAND" | grep -qE '\b(mkfs|fdisk|parted)\b'; then
    deny "BLOCKED: Disk formatting commands are not allowed."
fi

# dd to devices
if echo "$COMMAND" | grep -qE 'dd\s+.*of=/dev/'; then
    deny "BLOCKED: Writing directly to devices is not allowed."
fi

# chmod 777 (security risk)
if echo "$COMMAND" | grep -qE 'chmod\s+(-[a-zA-Z]*\s+)?777'; then
    deny "BLOCKED: 'chmod 777' is a security risk.\\n\\nUse more restrictive permissions."
fi

# Write to block devices
if echo "$COMMAND" | grep -qE '>\s*/dev/sd[a-z]'; then
    deny "BLOCKED: Cannot write directly to block devices."
fi

# Fork bomb
if echo "$COMMAND" | grep -qE ':\s*\(\s*\)\s*\{'; then
    deny "BLOCKED: Potential fork bomb detected."
fi

# =============================================================================
# THE FILES THE TDD HOOKS OWN
#
# The three test-first layers (05-testing.md) + any test file. Used by the two
# rules below — the snapshot rule and the source-write rule — because both are
# about the same thing: a frozen file rewritten by something other than
# Write/Edit, which is the only path the freeze can see.
# =============================================================================

TDD_TARGET_RE="$CWK_TDD_SHELL_TARGET_RE"

# The FROZEN test files only — the four layer words, not every test file. The
# source-write rule wants the wide list (no test file is written from a shell);
# the snapshot rule wants the narrow one, or it denies a legitimate
# `Button.test.tsx` snapshot update.
TDD_FROZEN_TEST_RE="$CWK_TDD_SHELL_FROZEN_TEST_RE"

# =============================================================================
# DELETING A FROZEN TEST  —  the shortest way around the freeze, and it was open
#
# `tdd-freeze-tests.sh` lets a Write through when the file does not exist: that
# IS the RED phase. So `rm x.utils.test.ts` followed by a fresh Write rewrites a
# frozen test wholesale, with no deny and no message, from any agent — the exact
# outcome the freeze exists to prevent, reached without ever editing the file.
# Measured: exit 0, no output.
#
# The rm rules above never see it: they key on `-r`/`--recursive` and on
# PROTECTED_DIRS, and this is a single non-recursive file. The regex the snapshot
# rule two blocks below already computes is the one this needs.
#
# `mv` is the same deletion under another name (the file leaves its path), and
# `mv` INTO a frozen path is a write — both are denied, so the rule reads on the
# whole segment rather than trying to tell source from destination.
# =============================================================================

while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE '(^|[[:space:]])(rm|unlink|shred|mv|truncate)([[:space:]]|$)' || continue
    if echo "$SEG" | grep -qE "$TDD_FROZEN_TEST_RE"; then
        deny "BLOCKED: deleting or moving a frozen test file from the shell.\\n\\nThe freeze (tdd-freeze-tests.sh) allows a Write when the file does not exist — that is the RED phase. So removing the file and writing it again rewrites a frozen test wholesale, past every guardrail, which is exactly what the freeze exists to stop (.claude/rules/05-testing.md).\\n\\nIf a case is genuinely wrong, that is a plan-level correction: say which case and why, add the path + '# reason' to .claude/.tdd-unfrozen, then edit it with Edit.\\n\\nIf the whole feature is being abandoned, delete the implementation module too and say so — do not start by removing the specification."
    fi
done < <(cwk_segments "$COMMAND")

# =============================================================================
# SNAPSHOT UPDATES  —  the runner rewriting a frozen test in place
#
# `vitest -u` rewrites inline snapshots INSIDE the test file and regenerates
# `.snap` files. On one of the three frozen layers that is the freeze broken
# with no trace at all: the writer is the test runner, so tdd-freeze-tests.sh
# never sees it (it is registered on Write|Edit), and the source-write rule
# below never sees it either (there is no redirection, no tee, no sed -i).
# It is literally "adjust the test until it agrees with the code", in one
# pre-approved command.
#
# Deny only when the command NAMES a frozen target. The blanket `pnpm test:run
# -u` is handled upstream instead: 05-testing.md forbids a snapshot assertion in
# those three layers at all, so a repo-wide update has nothing frozen to touch.
# Updating a component snapshot stays a normal thing to do.
#
# Judged per SEGMENT, like the rm rules above: `<runner> -u Button.test.tsx &&
# cat x.utils.test.ts` has the flag in one command and the frozen path in
# another, and denying that would be wrong.
#
# Limit, stated rather than hidden: this reads the command as TEXT, so a
# command that merely quotes the pattern (a grep, an echo, a doc example) is
# denied too. Same best-effort class as every other rule in this file — it
# closes the move, it is not a sandbox.
# =============================================================================

while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE '\b(vitest|jest|test:run|test:coverage|test:ui)\b[^|;&]*([[:space:]]-u\b|--update\b|--update-snapshots?\b)' || continue
    if echo "$SEG" | grep -qE "$TDD_FROZEN_TEST_RE"; then
        deny "BLOCKED: updating snapshots on a test-first layer.\\n\\nThe runner rewrites the assertion in place, so tdd-freeze-tests.sh never sees the edit — the test ends up agreeing with the code, which is exactly what the freeze exists to prevent.\\n\\nThe three frozen layers (utils / mapper / repository-services) carry no snapshot at all (.claude/rules/05-testing.md). If one slipped in, remove it and assert the value; if a case is genuinely wrong, that is .claude/.tdd-unfrozen, visibly, with a reason."
    fi
done < <(cwk_segments "$COMMAND")

# =============================================================================
# SOURCE WRITES VIA THE SHELL  —  the only `ask` in this file, so it comes LAST
#
# Every other guardrail in this kit (no-any, no-forbidden-icons,
# enforce-architecture, tdd-require-red, tdd-freeze-tests) is registered on the
# Write|Edit matcher. A shell redirection writes the same file without any of
# them ever running — so `cat > x.repository.ts <<EOF` is the one move that turns
# the whole TDD apparatus off, and it is exactly what an agent reaches for after
# a Write is denied.
#
# Two levels, because the cost of a false positive is not the same:
#   deny — the files the TDD hooks own (the three test-first layers and any test
#          file). There is no legitimate reason to write those from a shell.
#   ask  — any other .ts/.tsx. Codegen is real (`supabase gen types ... >
#          src/types/database.types.ts`), so it goes through the user instead of
#          being blocked.
#
# Deliberate limit, stated rather than hidden: this matches the literal path in
# the command. A target hidden behind a variable or a substitution
# (`> "$FILE"`) is not caught — same best-effort class as the branch detection in
# enforce-git-workflow.sh. It closes the move an agent actually makes after a
# denied Write; it is not a sandbox.
# =============================================================================

# The writer verbs, at the head of their own segment.
#
# `>`/`tee`/`sed -i` were the original three, and the deny text ("Use Write/Edit")
# is precisely what pushes an agent to the next spelling — so the next spellings
# are listed here. Measured before this line existed: heredoc → deny, `tee` →
# deny, `sed -i` → deny, while `cp`, `mv`, `python3 -c`, `node -e` and `>|` all
# wrote a frozen test ALLOWED and silent.
#
# `>|` is the noclobber-override redirection, a single operator: `cwk_segments`
# keeps it inside its segment, and the `\|?` here is what matches it.
#
# The verbs are anchored at the start of the segment (past any `VAR=x` prefix and
# `sudo`) rather than matched anywhere in it. That is what keeps
# `grep -r "cp x.utils.ts" .` out of this rule: a command's verb is its first
# word, and `tee` after a pipe is the first word of its own segment.
SEG_HEAD="^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(sudo[[:space:]]+)?"

SRC_WRITE_RE=">>?\|?[[:space:]]*[\"']?[^|;&<>\`[:space:]\"']*\.tsx?[\"']?([[:space:]]|;|\$)"
SRC_WRITE_RE="$SRC_WRITE_RE|${SEG_HEAD}(tee|cp|mv|install|rsync|ln|patch|truncate).*\.tsx?"
SRC_WRITE_RE="$SRC_WRITE_RE|${SEG_HEAD}(sed|perl)\b.*(-[a-zA-Z]*i|--in-place).*\.tsx?"
SRC_WRITE_RE="$SRC_WRITE_RE|${SEG_HEAD}(python3?|node|deno|bun|ruby|php)\b.*(-c|-e|--eval|-p)\b.*\.tsx?"

# `TDD_TARGET_RE` is defined above, and shared with the snapshot rule.

# The same door, on the Python cycle (fastapi addon). Deny only — there is no
# `ask` tier here, because this pattern names the two test-first paths and
# nothing else: an ordinary `.py` written from the shell is not this rule's
# business. Inert on a repo with no Python service layer.
PY_WRITE_RE=">>?\|?[[:space:]]*[\"']?[^|;&<>[:space:]\"']*\.py[\"']?([[:space:]]|;|$)"
PY_WRITE_RE="$PY_WRITE_RE|${SEG_HEAD}(tee|cp|mv|install|rsync|ln|patch|truncate).*\.py"
PY_WRITE_RE="$PY_WRITE_RE|${SEG_HEAD}(sed|perl)\b.*(-[a-zA-Z]*i|--in-place).*\.py"
PY_WRITE_RE="$PY_WRITE_RE|${SEG_HEAD}(python3?|node|deno|bun|ruby|php)\b.*(-c|-e|--eval|-p)\b.*\.py"

PY_WRITE_SEEN=0
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE "$PY_WRITE_RE" || continue
    echo "$SEG" | grep -qE "$CWK_TDD_PY_TARGET_RE" || continue
    PY_WRITE_SEEN=1
done < <(cwk_segments "$COMMAND")

if [[ "$PY_WRITE_SEEN" == "1" ]]; then
    deny "BLOCKED: writing the Python test-first layer from the shell.\\n\\nThe three Python TDD hooks (tdd-require-red-py, tdd-freeze-tests-py, tdd-prove-red-py) only see the Write and Edit tools, exactly like their TypeScript twins. A redirection bypasses all three: app/services/ would be created with no RED ever observed, and a frozen tests/services/test_*.py rewritten silently.\\n\\nUse Write/Edit. If the module already exists and you are in GREEN or REFACTOR, Edit is allowed. To correct a frozen test, that is .claude/.tdd-unfrozen — visibly, with a reason (.claude/rules/07-backend.md)."
fi

SRC_WRITE_SEEN=0
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE "$SRC_WRITE_RE" || continue
    SRC_WRITE_SEEN=1
    if echo "$SEG" | grep -qE "$TDD_TARGET_RE"; then
        deny "BLOCKED: writing a test-first layer or a test file from the shell.\\n\\nThe TDD hooks (tdd-require-red, tdd-freeze-tests, tdd-prove-red) only see the Write and Edit tools. A redirection bypasses all three: the RED phase is never observed and a frozen test can be rewritten silently.\\n\\nUse Write/Edit. If the module already exists and you are in GREEN or REFACTOR, Edit is allowed and nothing will block you. If you genuinely need to correct a frozen test, that is .claude/.tdd-unfrozen — visibly, with a reason (.claude/rules/05-testing.md)."
    fi
done < <(cwk_segments "$COMMAND")

if [[ "$SRC_WRITE_SEEN" == "1" ]]; then
    ask "This writes a TypeScript source from the shell, so no PreToolUse guardrail sees it (no-any, forbidden icons, architecture layering all run on Write|Edit only).\\n\\nIf this is authored code, write it with the Write/Edit tool instead. If it is genuine codegen (generated DB types), say what it generates and where — then let the user decide."
fi

exit 0
