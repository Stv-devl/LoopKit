#!/usr/bin/env bash
# cwk-guard-api: 6
#
# Hook: prevent-destructive-commands
# Event: PreToolUse (Bash)
# Purpose: Block dangerous commands that could delete directories or cause data loss
#

set -e
# shellcheck disable=SC2034  # read by the sourced hook-lib.sh
CWK_GUARD_HOOK=1
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq
# shellcheck disable=SC2034  # read by hook-lib.sh's exit trap
CWK_DEGRADED_ASK=1

# A hook-lib.sh older than this guard may not check cwk_app_roots: calling it would exit 127,
# which a PreToolUse hook reads as "allow". Refuse instead.
if ! declare -F cwk_app_roots cwk_config cwk_tdd_load cwk_installed cwk_is_kit_code cwk_real_rel >/dev/null 2>&1; then
    echo "BLOCKED: hook-guarded.sh or hook-lib.sh lacks cwk_app_roots/cwk_config/cwk_tdd_load/cwk_installed/cwk_is_kit_code/cwk_real_rel (a stale hook-lib.sh or hook-guarded.sh next to this guard), so this guard refuses rather than passes. The user re-copies the kit's .claude/hooks/ files from a terminal." >&2
    exit 2
fi

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
    cwk_cfg_reason "${2//\\n/$'\n'}"
    reason="$CWK_CFG_OUT"
    [[ "$decision" == "deny" ]] && cwk_log_health_deny "$reason"
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

# The top-level folders that must never be deleted recursively come from
# `.claude/project.json` (`protected_dirs`), read on the first rule that needs them:
# pdc_protected_load fills PROTECTED_DIRS (an ERE alternation), PROTECTED_TEXT (the
# list as the deny text shows it), PROTECTED_TARGET and the GUARD_PROTECTED_* regexes.
PROTECTED_DIRS="$CWK_NEVER_RE" PROTECTED_TEXT="" PROTECTED_TARGET="$CWK_NEVER_RE"
GUARD_PROTECTED_RE="$CWK_NEVER_RE" GUARD_PROTECTED_ROOT_RE="$CWK_NEVER_RE"
__PDC_PROTECTED_LOADED=0
pdc_protected_load() {
    [[ "$__PDC_PROTECTED_LOADED" == 1 ]] && return 0
    __PDC_PROTECTED_LOADED=1
    cwk_config || true
    [[ -n "$CWK_CFG_PROTECTED_DIRS_ERE" ]] || return 0
    PROTECTED_DIRS="$CWK_CFG_PROTECTED_DIRS_ERE"
    PROTECTED_TEXT="$CWK_CFG_PROTECTED_DIRS_TEXT"
    PROTECTED_TARGET="(^|[[:space:]'\"/])($PROTECTED_DIRS)/?([[:space:]]|;|&|\||\"|'|\$)"
    GUARD_PROTECTED_RE="^($PROTECTED_DIRS)(/|$)"
    GUARD_PROTECTED_ROOT_RE="^($PROTECTED_DIRS)$"
}

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
# PROTECTED_TARGET is built by pdc_protected_load above.

# `|| [[ -n "$SEG" ]]` is not optional: tr emits no trailing newline, so a
# single-segment command (`rm -rf src`) ends without one and a plain
# `while read` never runs its body — the rule silently checked nothing.
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    echo "$SEG" | grep -qE "$RM_RECURSIVE" || continue
    pdc_protected_load

    # A protected dir as a whole path segment: `src`, `./src`, `src/`,
    # `/abs/path/src/`. A path INSIDE one (`dist/assets`) is not denied here: the
    # guarded-set block below asks for it.
    if echo "$SEG" | grep -qE "$PROTECTED_TARGET"; then
        deny "BLOCKED: Cannot delete protected directory recursively.\\n\\nProtected: $PROTECTED_TEXT\\n\\nA subdirectory is asked, not blocked: name it and let the user approve."
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
    pdc_protected_load
    if echo "$SEG" | grep -qE "$PROTECTED_TARGET"; then
        deny "BLOCKED: 'find ... -delete' on a protected directory is a recursive delete under another name.\\n\\nProtected: $PROTECTED_TEXT\\n\\nTarget specific files instead, and list them before deleting."
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
    # Template env files contain no secrets — strip them, then re-check. The
    # suffixes are `.claude/project.json` `env_template_suffixes`, the list
    # protect-files.sh, auto-approve-config.sh and enforce-git-workflow.sh read too.
    cwk_config || true
    SANITIZED=$(echo "$COMMAND" | sed -E "s/\\.env\\.(${CWK_CFG_ENV_SUFFIX_ERE:-$CWK_NEVER_RE})(\$|[^[:alnum:]_.-])/\\2/g")
    if echo "$SANITIZED" | grep -qE "$SECRET_RE"; then
        deny "BLOCKED: Reading or copying secret files (.env*, *.key, *.pem, credentials) via shell is not allowed.\\n\\nAsk the user for variable NAMES (not values) or check .env.example."
    fi
fi

# The text above reads spelling: `cat .e*`, `cat .e""nv` and `\grep -r` escape it.
# shell_targets.py's secret mode expands each operand against the real listing
# and names the reads that skip the grep wrapper or the ignore files. A failed
# run adds no verdict: SECRET_RE stays the floor, the guard asks below keep theirs.
HOOK_DIR="$(dirname "${BASH_SOURCE[0]}")"
GUARD_BASE="$(jq -r '.cwd // empty' <<<"$INPUT")"
[[ -n "$GUARD_BASE" ]] || GUARD_BASE="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$GUARD_BASE" ]] || GUARD_BASE="$PWD"
# Auto mode (docs/specs/auto-mode.md V8), read once from the command's tree: a `denied` target is
# denied, a `ledgered` one is written with no guarded ask and recorded, `.tdd-unfrozen` is never
# written from the shell, and every other guard ask below becomes a blocked stop.
GUARD_AUTO=0 GUARD_AUTO_DENY="" GUARD_AUTO_LEDGER=()
if GUARD_AUTO_TREE="$(git -C "$GUARD_BASE" rev-parse --show-toplevel 2>/dev/null)" \
    && [[ -f "$GUARD_AUTO_TREE/.claude/.loop-record.json" ]] && cwk_auto_mode "$GUARD_AUTO_TREE"; then
    GUARD_AUTO=1
fi
SECRET_DENY="" SECRET_ASK=""
# A resolver of another guard API (a partial merge of the .new files) is not trusted: its line 2
# must be exactly this guard's API, else both calls are skipped and the failure paths below run.
GUARD_API_OK=0
if [[ -f "$HOOK_DIR/shell_targets.py" ]]; then
    { IFS= read -r _ && IFS= read -r GUARD_API_LINE; } <"$HOOK_DIR/shell_targets.py" || GUARD_API_LINE=""
    [[ "$GUARD_API_LINE" != "# cwk-guard-api: 6" ]] || GUARD_API_OK=1
fi
if [[ "$GUARD_API_OK" == 1 ]] && command -v python3 >/dev/null 2>&1; then
    SECRET_OUT="$(python3 -I -B "$HOOK_DIR/shell_targets.py" --secret-reads "$COMMAND" "$GUARD_BASE" "$SECRET_VERB" 2>/dev/null)" || SECRET_OUT=""
    SECRET_LINES=()
    while IFS= read -r SECRET_LINE; do
        SECRET_LINES+=("$SECRET_LINE")
    done <<<"$SECRET_OUT"
    SECRET_COUNT=${#SECRET_LINES[@]}
    if [[ "$SECRET_COUNT" -gt 0 && "${SECRET_LINES[$((SECRET_COUNT - 1))]}" == $'#end\t'"$((SECRET_COUNT - 1))" ]]; then
        for SECRET_LINE in "${SECRET_LINES[@]:0:$((SECRET_COUNT - 1))}"; do
            case "$SECRET_LINE" in
                $'?config\t'*) cwk_config || true ;;
                $'deny\t'*) [[ -n "$SECRET_DENY" ]] || SECRET_DENY="${SECRET_LINE#*$'\t'}" ;;
                $'ask\t'*) [[ -n "$SECRET_ASK" ]] || SECRET_ASK="${SECRET_LINE#*$'\t'}" ;;
            esac
        done
    fi
fi
if [[ -n "$SECRET_DENY" ]]; then
    deny "BLOCKED: ${SECRET_DENY:0:300}, a secret file.\\n\\nA glob or a quoted spelling still opens it. Ask the user for variable NAMES (not values) or read .env.example."
fi

# =============================================================================
# DANGEROUS SYSTEM COMMANDS - Always blocked
#
# ORDER MATTERS, and it is the reason this block sits ABOVE the source-write
# section rather than below it. `decide` exits on the first match, so an `ask`
# emitted early wins over every `deny` that would have fired later:
# `echo x > a.ts && mkfs.ext4 /dev/sdb` came back as a permission prompt instead
# of a block. Every deny in this file now precedes every `ask` it contains.
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

# The FROZEN test files only — the four layer words, not every test file. The
# source-write rule wants the wide list (no test file is written from a shell);
# the snapshot rule wants the narrow one, or it denies a legitimate
# `Button.test.tsx` snapshot update.
#
# pdc_tdd <target|frozen|py|any> <subject>: grep-style match, line by line, of the
# subject against the layer regexes; pdc_tdd_rel the same with `=~` on one path.
# Each regex needs `.ts` or `.py` in its own subject, so the project's config is read
# only for a subject that holds one: a command naming no such file costs no reader.
pdc_tdd_re() {
    cwk_tdd_load || true
    case "$1" in
        target) printf '%s' "$CWK_TDD_SHELL_TARGET_RE" ;;
        frozen) printf '%s' "$CWK_TDD_SHELL_FROZEN_TEST_RE" ;;
        py) printf '%s' "$CWK_TDD_PY_TARGET_RE" ;;
        tsany) printf '%s' "$CWK_TDD_SHELL_TARGET_RE|$CWK_TDD_SHELL_FROZEN_TEST_RE" ;;
        any) printf '%s' "$CWK_TDD_SHELL_TARGET_RE|$CWK_TDD_SHELL_FROZEN_TEST_RE|$CWK_TDD_PY_TARGET_RE" ;;
    esac
}
pdc_tdd() {
    [[ "$2" == *.ts* || "$2" == *.py* ]] || return 1
    cwk_tdd_load || true
    grep -qE -- "$(pdc_tdd_re "$1")" <<<"$2"
}
pdc_tdd_rel() {
    local re
    [[ "$2" == *.ts* || "$2" == *.py* ]] || return 1
    cwk_tdd_load || true
    re="$(pdc_tdd_re "$1")"
    [[ "$2" =~ $re ]]
}

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
    if pdc_tdd frozen "$SEG"; then
        deny "BLOCKED: deleting or moving a frozen test file from the shell.\\n\\nThe freeze (tdd-freeze-tests.sh) allows a Write when the file does not exist — that is the RED phase. So removing the file and writing it again rewrites a frozen test wholesale, past every guardrail, which is exactly what the freeze exists to stop (.claude/rules/05-testing.md).\\n\\nIf a case is genuinely wrong, that is a plan-level correction: a subagent stops and reports the case id and why; the main thread adds the path + '# <case id>: <reason>' to .claude/.tdd-unfrozen, records it in plan.md's ## Gate (orchestrate.md, Phase 4), then edits it with Edit.\\n\\nIf the whole feature is being abandoned, delete the implementation module too and say so — do not start by removing the specification."
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
    if pdc_tdd frozen "$SEG"; then
        deny "BLOCKED: updating snapshots on a test-first layer.\\n\\nThe runner rewrites the assertion in place, so tdd-freeze-tests.sh never sees the edit — the test ends up agreeing with the code, which is exactly what the freeze exists to prevent.\\n\\nThe three frozen layers (utils / mapper / repository-services) carry no snapshot at all (.claude/rules/05-testing.md). If one slipped in, remove it and assert the value; if a case is genuinely wrong, that is .claude/.tdd-unfrozen, visibly, with a reason."
    fi
done < <(cwk_segments "$COMMAND")

# =============================================================================
# SOURCE WRITES VIA THE SHELL  —  an `ask`, so it comes after every deny
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
SRC_VERB_RE="${SEG_HEAD}(tee|cp|mv|install|rsync|ln|patch|truncate).*\.tsx?"
SRC_VERB_RE="$SRC_VERB_RE|${SEG_HEAD}(sed|perl)\b.*(^|[[:space:]])(-[a-zA-Z]*i|--in-place).*\.tsx?"
SRC_VERB_RE="$SRC_VERB_RE|${SEG_HEAD}(python3?|node|deno|bun|ruby|php)\b.*(^|[[:space:]])(-c|-e|--eval|-p)\b.*\.tsx?"

# `pdc_tdd target` is defined above, and shared with the snapshot rule.

# The same door, on the Python cycle (fastapi addon). Deny only — there is no
# `ask` tier here, because this pattern names the two test-first paths and
# nothing else: an ordinary `.py` written from the shell is not this rule's
# business. Inert on a repo with no Python service layer.
PY_WRITE_RE=">>?\|?[[:space:]]*[\"']?[^|;&<>[:space:]\"']*\.py[\"']?([[:space:]]|;|$)"
PY_VERB_RE="${SEG_HEAD}(tee|cp|mv|install|rsync|ln|patch|truncate).*\.py"
PY_VERB_RE="$PY_VERB_RE|${SEG_HEAD}(sed|perl)\b.*(^|[[:space:]])(-[a-zA-Z]*i|--in-place).*\.py"
PY_VERB_RE="$PY_VERB_RE|${SEG_HEAD}(python3?|node|deno|bun|ruby|php)\b.*(^|[[:space:]])(-c|-e|--eval|-p)\b.*\.py"

PY_WRITE_SEEN=0
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    # Quotes and backslashes dropped for the verb and flag only: `sed '-i'`, `sed $'-i'`,
    # `sed \-i` and `--in''-place` are the flag. The redirect alternative reads the raw
    # segment, where a quoted `"=>"` is not a redirection.
    SEG_N="${SEG//\$\'/\'}"
    SEG_N="${SEG_N//\$\"/\"}"
    SEG_N="${SEG_N//[\'\"\\]/}"
    { echo "$SEG" | grep -qE "$PY_WRITE_RE"; } || { echo "$SEG_N" | grep -qE "$PY_VERB_RE"; } || continue
    pdc_tdd py "$SEG_N" || pdc_tdd py "$SEG" || continue
    PY_WRITE_SEEN=1
done < <(cwk_segments "$COMMAND")

# The module and test roots come from `.claude/project.json` (`fastapi`), loaded by the
# `pdc_tdd py` test that precedes every use.
pdc_py_deny() {
    printf '%s' "BLOCKED: writing the Python test-first layer from the shell.\\n\\nThe three Python TDD hooks (tdd-require-red-py, tdd-freeze-tests-py, tdd-prove-red-py) only see the Write and Edit tools, exactly like their TypeScript twins. A redirection bypasses all three: a test-first module under ${CWK_CFG_MODULE_ROOT:-the module root}/ would be created with no RED ever observed, and a frozen ${CWK_CFG_TESTS_ROOT:-tests}/…/test_*.py rewritten silently.\\n\\nUse Write/Edit. If the module already exists and you are in GREEN or REFACTOR, Edit is allowed. To correct a frozen test, that is .claude/.tdd-unfrozen — visibly, with a reason (.claude/rules/07-backend.md)."
}
TS_TDD_DENY="BLOCKED: writing a test-first layer or a test file from the shell.\\n\\nThe TDD hooks (tdd-require-red, tdd-freeze-tests, tdd-prove-red) only see the Write and Edit tools. A redirection bypasses all three: the RED phase is never observed and a frozen test can be rewritten silently.\\n\\nUse Write/Edit. If the module already exists and you are in GREEN or REFACTOR, Edit is allowed and nothing will block you. If you genuinely need to correct a frozen test, that is .claude/.tdd-unfrozen — visibly, with a reason (.claude/rules/05-testing.md)."

if [[ "$PY_WRITE_SEEN" == "1" ]]; then
    deny "$(pdc_py_deny)"
fi

SRC_WRITE_SEEN=0 SRC_VERB_SEEN=0
while IFS= read -r SEG || [[ -n "$SEG" ]]; do
    SEG_N="${SEG//\$\'/\'}"
    SEG_N="${SEG_N//\$\"/\"}"
    SEG_N="${SEG_N//[\'\"\\]/}"
    if { echo "$SEG_N" | grep -qE "$SRC_VERB_RE"; }; then
        SRC_VERB_SEEN=1
    elif ! { echo "$SEG" | grep -qE "$SRC_WRITE_RE"; }; then
        continue
    fi
    SRC_WRITE_SEEN=1
    if pdc_tdd target "$SEG_N" || pdc_tdd target "$SEG"; then
        deny "$TS_TDD_DENY"
    fi
done < <(cwk_segments "$COMMAND")

# =============================================================================
# THE GUARDED SET, SHELL SIDE  —  the last deny of this file, then the first ask
#
# protect-files.sh asks on a Write/Edit of a guarded path; every shell writer
# reaches the same files without that hook ever running. shell_targets.py
# resolves each write of the command (redirect, cp, sed -i, find -exec, an
# interpreter's inline program…) to an absolute path or a marker, and this
# block classifies the rows with hook-guarded.sh — the one list, never copied.
#
# Failure is not a pass: no python3, no resolver, a nonzero exit or output
# without its `#end` sentinel fall back to the raw text (docs/specs/guard-shell.md).
# =============================================================================

GUARD_FAILED=0
GUARD_DENY_RAW=""
GUARD_PARSE=""
GUARD_OUT=""
if [[ "$GUARD_API_OK" == 1 ]] && command -v python3 >/dev/null 2>&1; then
    # No temp file: the resolver still runs, only its parse reason is lost.
    GUARD_ERR_FILE="$(mktemp 2>/dev/null)" || GUARD_ERR_FILE=/dev/null
    GUARD_STATUS=0
    GUARD_OUT="$(python3 -B "$HOOK_DIR/shell_targets.py" "$COMMAND" "$GUARD_BASE" 2>"$GUARD_ERR_FILE")" || GUARD_STATUS=$?
    if [[ "$GUARD_STATUS" == 3 ]]; then
        # Exit 3 is a construct the resolver cannot follow, named on stderr; any other
        # nonzero exit is a crash and keeps the "unavailable" path below.
        GUARD_PARSE="$(head -c 300 "$GUARD_ERR_FILE" | tr '\n' ' ')"
        GUARD_PARSE="${GUARD_PARSE#shell_targets: }"
        GUARD_PARSE="${GUARD_PARSE% }"
        [[ -n "$GUARD_PARSE" ]] || GUARD_PARSE="unreadable construct"
        GUARD_FAILED=1
    elif [[ "$GUARD_STATUS" != 0 ]]; then
        GUARD_FAILED=1
    fi
    [[ "$GUARD_ERR_FILE" == /dev/null ]] || rm -f "$GUARD_ERR_FILE"
else
    GUARD_FAILED=1
fi

GUARD_ROWS=()
if [[ "$GUARD_FAILED" == 0 ]]; then
    # bash 3.2 constructs only (macOS /bin/bash): a read loop, positive indices.
    GUARD_LINES=()
    GUARD_COUNT=0
    while IFS= read -r GUARD_LINE || [[ -n "$GUARD_LINE" ]]; do
        GUARD_LINES+=("$GUARD_LINE")
        GUARD_COUNT=$((GUARD_COUNT + 1))
    done <<<"$GUARD_OUT"
    GUARD_END_RE=$'^#end\t([0-9]+)$'
    GUARD_ROW_RE=$'^[^\t]+\t.+$'
    GUARD_LAST=""
    [[ "$GUARD_COUNT" -eq 0 ]] || GUARD_LAST="${GUARD_LINES[$((GUARD_COUNT - 1))]}"
    if [[ "$GUARD_LAST" =~ $GUARD_END_RE && "${BASH_REMATCH[1]}" == "$((GUARD_COUNT - 1))" ]]; then
        GUARD_INDEX=0
        while [[ "$GUARD_INDEX" -lt $((GUARD_COUNT - 1)) ]]; do
            GUARD_LINE="${GUARD_LINES[$GUARD_INDEX]}"
            [[ "$GUARD_LINE" =~ $GUARD_ROW_RE ]] || GUARD_FAILED=1
            GUARD_ROWS+=("$GUARD_LINE")
            GUARD_INDEX=$((GUARD_INDEX + 1))
        done
    else
        GUARD_FAILED=1
    fi
fi

# One verdict per row, D > G > P > U > R; the reason shown is the first row of
# the strongest verdict over the whole command. R: acceptEdits auto-approves
# `rm`, so any other recursive delete inside the project asks.
GUARD_DENY="" GUARD_DENY_WHY="" GUARD_ASK_G="" GUARD_ASK_P="" GUARD_ASK_U="" GUARD_ASK_R=""
GUARD_DENY_CG="" GUARD_ASK_CG=""
GUARD_ASK_F="" GUARD_ASK_T="" GUARD_ASK_O="" GUARD_ASK_M="" GUARD_INLINE_TDD="" GUARD_ASK_S="" GUARD_ASK_C="" GUARD_ASK_K="" GUARD_ASK_W="" GUARD_ASK_Q=""
GUARD_PROJECT_REAL=""
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    GUARD_PROJECT_REAL="$(cwk_real_path "$CLAUDE_PROJECT_DIR")" || GUARD_PROJECT_REAL=""
fi
GUARD_ROOT_WHY="It is the project root or a folder above it: deleting or emptying it loses the whole project."
GUARD_TEST_WHY="A test-first module or a test file is written only with Write/Edit, where the TDD hooks see it (.claude/rules/05-testing.md)."
GUARD_KIT_APPLY_WHY="kit-apply.sh applies a /kit:init proposal to .claude/project.json: the user runs it from their own terminal, never a tool call."

# Running the /kit:init apply script, in every project: by the file a `run` row opens (a link
# to it, a worktree copy) or by its name inside a `-c` program.
guard_kit_apply_run() {
    local target="$1" real dir pat
    case "$target" in
        '?inline:'*) [[ "$target" == *kit-apply.sh* ]] || return 1 ;;
        '?unknown:'*)
            # `$CLAUDE_PROJECT_DIR/…`, `$(pwd)/…`, `$PWD/…`: the prefix is unresolved, the name is not.
            [[ "$target" == *kit-apply.sh && ( "$target" == *'/kit-apply.sh' || "$target" == '?unknown:kit-apply.sh' ) ]] || return 1
            ;;
        '?glob:'*)
            # A glob that names the script in a folder that holds it asks; it never passes.
            dir="${target#?glob:}"
            pat=""
            if [[ "$dir" == *$'\x1f'* ]]; then
                pat="${dir#*$'\x1f'}"
                dir="${dir%%$'\x1f'*}"
            fi
            # shellcheck disable=SC2053  # the pattern is a glob on purpose
            if [[ -n "$pat" && "kit-apply.sh" == $pat && -e "$dir/kit-apply.sh" ]]; then
                [[ -n "$GUARD_ASK_U" ]] || GUARD_ASK_U="run kit-apply.sh by a glob: $dir/${pat:0:50}"
            fi
            return 1
            ;;
        /*)
            real="$(cwk_real_rel "$target" 2>/dev/null)" || return 1
            [[ "$real" == .claude/scripts/kit-apply.sh || "$real" == .claude/worktrees/*/.claude/scripts/kit-apply.sh ]] || return 1
            ;;
        *) return 1 ;;
    esac
    guard_note_deny "running .claude/scripts/kit-apply.sh" "$GUARD_KIT_APPLY_WHY"
}

# Kit code in an installed project, by the row's name or by the file it opens. A removal or move
# acts on a link itself, so its link is not followed; its operand also reaches a folder above kit
# code (`.claude`), and so does a copy into a folder (`cp -r /tmp/k/.claude .`).
guard_kit_code() {
    local verb="$1" target="$2" rel="$3" glob="${4:-0}" reach="" real="" shown
    case "$verb" in
        rm | rm-r | rmdir | unlink | mv | find-delete | into) reach=--reach ;;
    esac
    # A glob row names the folder its pattern expands in: a write onto it can land on kit code.
    [[ "$glob" == 1 ]] && reach=--reach
    if [[ "$verb" == into && "$rel" == . ]]; then
        # `cp -R /tmp/k/. .`, the contents of a source that cannot be listed, into the project root.
        guard_note_deny "kit code: the project root written by a contents copy" "$CWK_KIT_DENY"
        return 0
    fi
    if [[ "$verb" != rm && "$verb" != rm-r && "$verb" != rmdir && "$verb" != unlink && "$verb" != mv ]] \
        || [[ ! -L "$target" ]]; then
        real="$(cwk_real_rel "$target" 2>/dev/null)" || real=""
    fi
    if cwk_is_kit_code "$rel" $reach; then
        shown="$rel"
    elif [[ -n "$real" ]] && cwk_is_kit_code "$real" $reach; then
        shown="$real"
    else
        return 1
    fi
    guard_note_deny "kit code: $shown written by $verb" "$CWK_KIT_DENY"
}
GUARD_SOURCE_WRITERS=" sed perl cp tee install rsync ln patch truncate "

guard_show() {
    if [[ "$1" == . ]]; then printf '%s' 'the project root'; else printf '%s' "$1"; fi
}

guard_note_deny() {
    [[ -n "$GUARD_DENY" ]] && return 0
    GUARD_DENY="$1"
    GUARD_DENY_WHY="$2"
}

# guard_guarded <rel> <verb>: a write to a guarded path. Outside auto mode, the guarded ask. In
# auto mode: a `denied` path or `.tdd-unfrozen` is a blocked stop, a `ledgered` one is recorded
# instead of asked (GUARD_AUTO_LEDGER), any other guarded path keeps the ask that becomes a
# blocked stop below.
guard_guarded() {
    local rel="$1" verb="$2" class
    if [[ "$GUARD_AUTO" == 1 ]]; then
        class="$(cwk_auto_class "$rel")"
        if [[ "$class" == denied ]]; then
            [[ -n "$GUARD_AUTO_DENY" ]] || GUARD_AUTO_DENY="$rel (written by $verb) is not written in auto mode (docs/specs/auto-mode.md V8); a pass that needs it ends in a blocked stop."
            return 0
        fi
        if [[ "$rel" == .claude/.tdd-unfrozen ]]; then
            [[ -n "$GUARD_AUTO_DENY" ]] || GUARD_AUTO_DENY=".tdd-unfrozen is written only through Edit on an arbiter unfreeze verdict, never from the shell."
            return 0
        fi
        if [[ "$class" == ledgered ]]; then
            GUARD_AUTO_LEDGER+=("$rel")
            return 0
        fi
    fi
    [[ -n "$GUARD_ASK_G" ]] || GUARD_ASK_G="$(guard_show "$rel") written by $verb"
}

# ask_or_block <message>: the ask, or in auto mode a deny opening `auto mode — blocked stop:`.
ask_or_block() {
    if [[ "$GUARD_AUTO" == 1 ]]; then
        deny "auto mode — blocked stop: $1"
    fi
    ask "$1"
}

# The project root or a folder above it, compared physically: an alias of the
# project dir, `..`, `../..` or the absolute path all land here.
guard_is_root_or_above() {
    local real
    [[ -n "$GUARD_PROJECT_REAL" ]] || return 1
    real="$(cwk_real_path "$1")" || return 1
    [[ "$real" == / || "$GUARD_PROJECT_REAL" == "$real" || "$GUARD_PROJECT_REAL" == "$real"/* ]]
}

# flag-r empties or rewrites a folder, flag-w writes a file, cfg loads a config.
guard_classify_tool() {
    local verb="$1" target="$2" rel="$3"
    pdc_protected_load
    case "$verb" in
        flag-r | flag-w)
            if [[ "$rel" =~ $GUARD_PROTECTED_ROOT_RE && "$rel" != dist ]]; then
                guard_note_deny "$rel written by $verb" "$rel is a protected directory, and a tool option that writes its output there empties or overwrites it whole."
            elif pdc_tdd_rel target "$rel" || [[ "$rel" =~ $CWK_TEST_FILE_RE ]]; then
                guard_note_deny "$rel written by $verb" "$GUARD_TEST_WHY"
            elif cwk_is_guarded "$rel"; then
                [[ -n "$GUARD_ASK_G" ]] || GUARD_ASK_G="$(guard_show "$rel") written by $verb"
            elif [[ "$verb" == flag-r || "$rel" =~ $GUARD_PROTECTED_RE ]]; then
                [[ -n "$GUARD_ASK_F" ]] || GUARD_ASK_F="$rel ($verb)"
            fi
            ;;
        cfg)
            if [[ -d "$target" ]]; then
                local real root
                real="$(cwk_real_path "$target")" || real=""
                [[ -n "$real" && "$real" == "$GUARD_PROJECT_REAL" ]] && return 0
                # A declared app root (.claude/project.json) is a project of its own: the
                # real path of the target must be the real path of the declared folder.
                cwk_app_roots
                for root in ${__CWK_APP_ROOTS[@]+"${__CWK_APP_ROOTS[@]}"}; do
                    [[ -n "$real" && -n "$GUARD_PROJECT_REAL" \
                        && "$real" == "$(cwk_real_path "$GUARD_PROJECT_REAL/$root")" ]] && return 0
                done
            elif cwk_is_guarded "$rel"; then
                return 0
            fi
            [[ -n "$GUARD_ASK_F" ]] || GUARD_ASK_F="$rel (cfg)"
            ;;
    esac
    return 0
}

# guard_is_write_verb <verb> [mv]: the one write-verb test of the classifier. A redirect or a
# GUARD_SOURCE_WRITERS verb; with the `mv` argument, mv too.
guard_is_write_verb() {
    [[ "$1" == '>' || "$1" == '>>' || "$GUARD_SOURCE_WRITERS" == *" $1 "* \
        || ( "${2:-}" == mv && "$1" == mv ) ]]
}

# guard_classify_outside <verb> <target>: a target cwk_guard_rel places outside the project.
# /dev/null passes; an fd alias asks when the tokenizer's `fd-bound` rows bind its fd (/dev/stdin
# is never exempt); a /tmp target passes, but for rm-r, flag-r and cfg; anything else asks. A
# /tmp path a link made in this call may reach is already a `?link:` row (shell_targets.py).
guard_classify_outside() {
    local verb="$1" target="$2" fd=""
    [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || return 0
    case "$target" in
        /dev/null) return 0 ;;
        /dev/fd/0) fd=0 ;;
        /dev/stdout | /dev/fd/1) fd=1 ;;
        /dev/stderr | /dev/fd/2) fd=2 ;;
    esac
    if [[ -n "$fd" ]]; then
        if [[ "$GUARD_FD_BOUND" == *" $fd "* && -z "$GUARD_ASK_T" ]]; then
            GUARD_ASK_T="$target by $verb: fd $fd is bound to a path in this command"
        fi
        return 0
    fi
    if [[ "$verb" != rm-r && "$verb" != flag-r && "$verb" != cfg ]] \
        && [[ "$target" == /tmp || "$target" == /tmp/* ]]; then
        return 0
    fi
    [[ -n "$GUARD_ASK_O" ]] || GUARD_ASK_O="$target by $verb"
    return 0
}

guard_classify() {
    local verb="$1" target="$2" rel text slot="" plain=1 codegen=0 globpat="" globpat_l shopt_chars extglob_re ext
    pdc_protected_load
    # `>cg` (a listed generator's redirect) is shown and handled as `>`, but for its ask.
    if [[ "$verb" == '>cg' ]]; then
        verb='>'
        codegen=1
    fi
    if [[ "$verb" == run ]]; then
        guard_kit_apply_run "$target" || true
        return 0
    fi
    [[ "$target" == '?inline:'* ]] && { guard_kit_apply_run "$target" || true; }
    # `into` and `mkdir` rows feed only the kit-code check: an unresolved one adds no ask.
    if [[ ( "$verb" == into || "$verb" == mkdir ) && "$target" != /* && "$target" != '?glob:'* ]]; then
        return 0
    fi
    case "$target" in
        '?inline:'* | '?unknown:'*)
            text="${target#*:}"
            case "$verb" in
                snapshot) slot=GUARD_ASK_S ;;
                cfg-write) slot=GUARD_ASK_C ;;
                cache-clear) slot=GUARD_ASK_K ;;
                option) slot=GUARD_ASK_W ;;
                kit-cwd) slot=GUARD_ASK_Q ;;
            esac
            if [[ -n "$slot" ]]; then
                [[ -n "${!slot}" ]] || printf -v "$slot" '%s' "${text:0:200}"
            elif [[ "$text" == *.claude/.tdd-red* || "$text" == *.claude/.loop-record* ]]; then
                if [[ -z "$GUARD_DENY" ]]; then
                    GUARD_DENY="$verb ${text:0:200}"
                    if [[ "$text" == *.claude/.tdd-red* ]]; then
                        GUARD_DENY_WHY="$(cwk_guard_denied_why .claude/.tdd-red)"
                    else
                        GUARD_DENY_WHY="$(cwk_guard_denied_why .claude/.loop-record.json)"
                    fi
                fi
            elif [[ "$target" == '?inline:'* ]] \
                && pdc_tdd any "$text"; then
                [[ -n "$GUARD_INLINE_TDD" ]] || GUARD_INLINE_TDD="$verb ${text:0:200}"
            else
                [[ -n "$GUARD_ASK_U" ]] || GUARD_ASK_U="$verb ${text:0:200}"
            fi
            return 0
            ;;
        '?link:'*)
            # The tokenizer's structural link rule: another command of this call can make a link
            # this /tmp path goes through before it runs.
            [[ -n "$GUARD_ASK_T" ]] || GUARD_ASK_T="${target#?link:} by $verb: a link made in this command may lead this write into the project"
            return 0
            ;;
        '?glob:'*)
            target="${target#?glob:}"
            plain=0
            if [[ "$target" == *$'\x1f'* ]]; then
                globpat="${target#*$'\x1f'}"
                target="${target%%$'\x1f'*}"
            fi
            # A /tmp glob outside the project: bash's expansion, its shell options and the links
            # it meets cannot be replayed here, so it asks.
            if [[ ( "$target" == /tmp || "$target" == /tmp/* ) && "$verb" != ln ]] \
                && guard_is_write_verb "$verb" && ! cwk_guard_rel "$target" >/dev/null; then
                [[ -n "$GUARD_ASK_T" ]] || GUARD_ASK_T="$target/${globpat:0:50} by $verb: a /tmp glob may expand through a link into the project"
                return 0
            fi
            ;;
    esac
    if [[ "$plain" == 1 && ( "$verb" == rm-r || "$verb" == flag-r ) ]] && guard_is_root_or_above "$target"; then
        guard_note_deny "$target written by $verb" "$GUARD_ROOT_WHY"
        return 0
    fi
    if ! rel="$(cwk_guard_rel "$target")"; then
        [[ "$verb" == into || "$verb" == mkdir ]] || guard_classify_outside "$verb" "$target"
        return 0
    fi
    if cwk_installed && guard_kit_code "$verb" "$target" "$rel" "$((1 - plain))"; then
        return 0
    fi
    [[ "$verb" == into || "$verb" == mkdir ]] && return 0
    # A write onto a glob may expand to one source or test file the folder row hides: it asks
    # unless the last segment is plainly a non-source name (docs/*.md passes). A bracket or brace
    # class can spell any dot, extension or test name (a brace holding a slash leaves only its
    # closing bracket in the last segment), so any of [ ] { } asks; `*`/`?` alone ask on no dot, a
    # glob extension, ts/tsx/py, or test/spec in the name, compared in lower case (nocaseglob). A
    # command that sets a shell option (`shopt`: nocaseglob, extglob) asks on any glob character.
    # Bash drops backslash-newline before parsing, so `!\<newline>(md)` is a live `!(md)`: the
    # `shopt` clause and the extglob regex below read a copy with every continuation removed.
    cmd_joined="${COMMAND//$'\\\n'/}"
    if [[ -n "$globpat" ]] && guard_is_write_verb "$verb" mv; then
        globpat_l="$(printf '%s' "$globpat" | tr '[:upper:]' '[:lower:]')" || globpat_l=""
        ext="${globpat_l##*.}"
        shopt_chars='*[][*?{}()|!@+]*'
        # shellcheck disable=SC2053 # $shopt_chars is a glob pattern on purpose
        if [[ -z "$globpat_l" || "$globpat" == *[][{}]* || "$globpat_l" != *.*|| "$ext" == *[\*\?]* || "$ext" == ts || "$ext" == tsx || "$ext" == py \
              || "$globpat_l" == *test* || "$globpat_l" == *spec* \
              || ( "$cmd_joined" == *shopt* && "$globpat" == $shopt_chars ) ]]; then
            [[ -n "$GUARD_ASK_U" ]] || GUARD_ASK_U="$verb onto a glob that may match a source or test file: ${globpat:0:50} under ${rel:0:150}"
        fi
    fi
    # Extglob (`a.!(md)`, `@(ts)`, `+(t|s)`) is on whenever any spelling or sourced file sets it, so the
    # text is the only signal; the target tokenizer cuts the word at the parenthesis, so the call asks.
    # A listed generator onto a source keeps its own codegen ask.
    extglob_re='[@!+]\('
    if [[ "$cmd_joined" =~ $extglob_re ]] && guard_is_write_verb "$verb" mv \
        && ! [[ "$codegen" == 1 && "$rel" =~ \.(tsx?|py)$ ]]; then
        [[ -n "$GUARD_ASK_U" ]] || GUARD_ASK_U="$verb in a command that uses extglob syntax (@(, !( or +( ), which can name a source or test file the guard cannot resolve"
    fi
    if [[ "$verb" == rm && "$rel" =~ ^\.git/(worktrees/[^/]+/)?(refs/([^/]+/)*)?[^/]+\.lock$ ]]; then
        # A stale lock (`.git/index.lock`, `.git/refs/heads/x.lock`, a linked worktree's
        # `.git/worktrees/<name>/index.lock`) is removed with a plain `rm`; a recursive
        # delete, a move or any other path under .git stays denied.
        return 0
    elif cwk_is_guard_denied "$rel"; then
        guard_note_deny "$rel written by $verb" "$(cwk_guard_denied_why "$rel")"
    elif [[ "$verb" == inline-path ]]; then
        # An inline program naming a repo path: sent back to Read/Grep or Write/Edit. A
        # test-first or test file keeps the GUARD_INLINE_TDD deny and its own text.
        pdc_tdd_rel tsany "$rel" && return 0
        guard_note_deny "inline programs are not used here: $rel" "Read/Grep to read, Write/Edit to write."
    elif [[ "$verb" == '>' || "$verb" == '>>' ]]; then
        # A redirect whose filename carries a quote is invisible to the raw-text rules above;
        # the resolved target gets the same decision the unquoted spelling gets there.
        if pdc_tdd_rel tsany "$rel"; then
            [[ -n "$GUARD_DENY_RAW" ]] || GUARD_DENY_RAW="$TS_TDD_DENY"
        elif pdc_tdd_rel py "$rel"; then
            [[ -n "$GUARD_DENY_RAW" ]] || GUARD_DENY_RAW="$(pdc_py_deny)"
        elif [[ "$rel" =~ \.(tsx?|py)$ ]]; then
            # A source written by a redirect skips every Write/Edit guardrail: denied, but
            # for a generator listed in .claude/project.json onto an unguarded file.
            if [[ "$codegen" == 1 && "$rel" =~ $CWK_TEST_FILE_RE ]]; then
                guard_note_deny "$rel written by $verb" "$GUARD_TEST_WHY"
            elif [[ "$codegen" == 1 ]] && ! cwk_is_guarded "$rel"; then
                [[ -n "$GUARD_ASK_CG" ]] || GUARD_ASK_CG="$rel"
            else
                [[ -n "$GUARD_DENY_CG" ]] || GUARD_DENY_CG="$rel"
            fi
        elif cwk_is_guarded "$rel"; then
            guard_guarded "$rel" "$verb"
        fi
    elif [[ "$GUARD_SOURCE_WRITERS" == *" $verb "* && "$rel" =~ \.(tsx?|py)$ ]]; then
        # An in-place or copy write of a source goes around every Write/Edit guardrail:
        # denied, so the agent retries with Edit instead of asking the user. A redirect
        # (`>`) keeps its ask below, and `mv` keeps the protected-dir ask (no rename tool).
        if pdc_tdd_rel any "$rel"; then
            guard_note_deny "$rel written by $verb" "$GUARD_TEST_WHY"
        else
            guard_note_deny "$rel written by $verb" "This edits a source from the shell, around every Write/Edit guardrail. Use Write/Edit."
        fi
    elif [[ "$verb" == flag-r || "$verb" == flag-w || "$verb" == cfg ]]; then
        guard_classify_tool "$verb" "$target" "$rel"
    elif cwk_is_guarded "$rel"; then
        guard_guarded "$rel" "$verb"
    elif [[ "$verb" == mv &&"$rel" =~ $GUARD_PROTECTED_RE ]]; then
        [[ -n "$GUARD_ASK_M" ]] || GUARD_ASK_M="$rel"
    elif [[ ( "$verb" == rm-r || "$verb" == find-delete ) && "$rel" =~ $GUARD_PROTECTED_RE ]]; then
        [[ -n "$GUARD_ASK_P" ]] || GUARD_ASK_P="$rel"
    elif [[ "$verb" == rm-r ]]; then
        [[ -n "$GUARD_ASK_R" ]] || GUARD_ASK_R="$rel"
    fi
    return 0
}

GUARD_FD_BOUND=" "
if [[ "$GUARD_FAILED" == 0 ]]; then
    # The tokenizer's `fd-bound N` rows: fds 0-2 a redirect in this command may point at a path.
    for GUARD_LINE in "${GUARD_ROWS[@]}"; do
        if [[ "${GUARD_LINE%%$'\t'*}" == fd-bound ]]; then
            GUARD_FD_BOUND+="${GUARD_LINE#*$'\t'} "
        fi
    done
    for GUARD_LINE in "${GUARD_ROWS[@]}"; do
        if [[ "${GUARD_LINE%%$'\t'*}" == '?config' ]]; then
            cwk_config || true
        elif [[ "${GUARD_LINE%%$'\t'*}" != fd-bound ]]; then
            guard_classify "${GUARD_LINE%%$'\t'*}" "${GUARD_LINE#*$'\t'}"
        fi
    done
    # A shell that reads kit-apply.sh from stdin (`bash < kit-apply.sh`) has no `run` row.
    GUARD_SHELL_WORD_RE='(^|[^[:alnum:]_.-])(sudo[[:space:]]+)?([^[:space:]]*/)?(ba|z|da|k)?sh([[:space:]<|;&]|$)'
    if [[ "$COMMAND" == *kit-apply* && "$GUARD_FD_BOUND" == *" 0 "* && "$COMMAND" =~ $GUARD_SHELL_WORD_RE ]]; then
        [[ -n "$GUARD_ASK_U" ]] || GUARD_ASK_U="a shell reads kit-apply.sh from stdin"
    fi
fi

if [[ -n "$GUARD_AUTO_DENY" ]]; then
    deny "auto mode — blocked stop: $GUARD_AUTO_DENY"
fi
if [[ -n "$GUARD_DENY" ]]; then
    deny "BLOCKED: $GUARD_DENY.\\n\\n$GUARD_DENY_WHY"
fi
if [[ -n "$GUARD_DENY_RAW" ]]; then
    deny "$GUARD_DENY_RAW"
fi
if [[ -n "$GUARD_PARSE" && "$COMMAND" == *.claude/.tdd-red* ]]; then
    deny "BLOCKED: the shell guard could not parse this command ($GUARD_PARSE) and it names .claude/.tdd-red/, which only tdd-prove-red.sh writes.\\n\\nWrite it plainly, without the construct, or leave RED markers to tdd-prove-red.sh."
fi
if [[ "$GUARD_FAILED" == 1 && "$COMMAND" == *.claude/.tdd-red* ]]; then
    deny "BLOCKED: shell guard unavailable and the command names .claude/.tdd-red/.\\n\\nshell_targets.py is missing, broken or python3 is absent, so this write cannot be resolved; a RED marker is created only by the tdd-prove-red.sh script. Run /kit:doctor."
fi
if [[ -n "$GUARD_PARSE" && "$COMMAND" == *.claude/.loop-record* ]]; then
    deny "BLOCKED: the shell guard could not parse this command ($GUARD_PARSE) and it names .claude/.loop-record.json, which is written only by loop-record.py.\\n\\nWrite it plainly, without the construct; the record itself comes only from the user's plan-gate go."
fi
if [[ "$GUARD_FAILED" == 1 && "$COMMAND" == *.claude/.loop-record* ]]; then
    deny "BLOCKED: shell guard unavailable and the command names .claude/.loop-record.json, which is written only by loop-record.py.\\n\\nshell_targets.py is missing, broken or python3 is absent, so this write cannot be resolved. Run /kit:doctor."
fi
# loop-record.py runs as a hook, on the user's own answer; run by hand it would write a record
# from an input nobody answered. `--clear` only deletes the record, `--block` only marks it blocked
# (it removes the push/PR allow), `--mode` and `--guarded-block` only read it: those four exact forms
# stay allowed. `--release` is the user's lift of a blocked record: its exact form is denied to the agent in
# auto (a blocked record still reads auto here) and asks in moi; it is on no allow list.
LOOP_RECORD_RELEASE_RE='^[[:space:]]*python3[[:space:]]+\.claude/hooks/loop-record\.py[[:space:]]+--release[[:space:]]*$'
if [[ "$COMMAND" =~ $LOOP_RECORD_RELEASE_RE ]]; then
    [[ "$GUARD_AUTO" == 1 ]] \
        && deny "auto mode — blocked stop: \`loop-record.py --release\` is the user's lift of a blocked record, never the agent's.\\n\\nEnd the run with a blocked stop; the user runs python3 .claude/hooks/loop-record.py --release in their own terminal, then the pass resumes in moi."
    ask "This runs loop-record.py --release: it turns a blocked loop record into a released moi record that keeps its ledger. Only the user lifts a blocked stop; let the user decide."
fi
LOOP_RECORD_RUN_RE='(^|[^[:alnum:]_./-])(env[[:space:]]+)?([^[:space:]]*/)?python3?(\.[0-9]+)?[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*([^[:space:]]*/)?loop-record\.py([^[:alnum:]_.-]|$)'
LOOP_RECORD_HEAD_RE='(^|[;&|(])[[:space:]]*([^[:space:]]*/)?loop-record\.py([^[:alnum:]_.-]|$)'
LOOP_RECORD_CLEAR_RE='^[[:space:]]*python3[[:space:]]+\.claude/hooks/loop-record\.py[[:space:]]+(--clear|--block|--mode|--guarded-block)[[:space:]]*$'
if [[ ( "$COMMAND" =~ $LOOP_RECORD_RUN_RE || "$COMMAND" =~ $LOOP_RECORD_HEAD_RE ) \
    && ! "$COMMAND" =~ $LOOP_RECORD_CLEAR_RE ]]; then
    deny "BLOCKED: only Claude Code runs loop-record.py, as a hook on the user's plan-gate answer.\\n\\nRun by hand, it would write .claude/.loop-record.json from an answer the user never gave. The manual forms are: python3 .claude/hooks/loop-record.py --clear, --block, --mode, --guarded-block; --release is the user's own lift of a blocked record."
fi
if [[ -n "$GUARD_INLINE_TDD" ]]; then
    deny "BLOCKED: an inline program names a test-first module or a test file ($GUARD_INLINE_TDD).\\n\\n$GUARD_TEST_WHY Write it with Write/Edit; to only read it, use the Read tool or cat."
fi

# A fix pass of eslint or ruff naming a test file rewrites it in place, past the
# freeze: denied here, before every ask below, so no ask ever hides it. A folder
# (`tests/services`) is not a named test file and keeps the formatter's ask.
FORMAT_FIX_RE='[[:space:]](--fix|--fix-only|--fix=[^[:space:]]*|--unsafe-fixes)([[:space:]]|$)'
set -f
while IFS= read -r SEG; do
    [[ "$SEG" =~ ^[[:space:]]*(git|echo|printf)[[:space:]] ]] && continue
    TOOL_ARGS=$(echo "$SEG" | grep -oE '\b(eslint|ruff[[:space:]]+check)\b.*' || true)
    [[ -n "$TOOL_ARGS" && "$TOOL_ARGS" =~ $FORMAT_FIX_RE ]] || continue
    for word in $TOOL_ARGS; do
        [[ "$word" == -* ]] && continue
        if [[ "$word" =~ $CWK_TEST_FILE_RE ]]; then
            set +f
            deny "BLOCKED: ${TOOL_ARGS%% *} with a fix flag rewrites the test file $word in place.\\n\\n$GUARD_TEST_WHY Fix it with Edit, or run the fix on the implementation files only."
        fi
    done
done < <(cwk_segments "$COMMAND")
set +f

# The codegen deny comes after every other deny, the eslint test-file one included.
if [[ -n "$GUARD_DENY_CG" ]]; then
    deny "BLOCKED: $GUARD_DENY_CG written by a redirect.\\n\\nThis writes a source from the shell, around every Write/Edit guardrail. Use Write/Edit; a generator listed in .claude/project.json codegen_commands may redirect with >."
fi

# Three shapes whose remedy is a rewrite by the agent, never a decision of the user: denied, so
# the agent retries in the right form instead of handing the user a prompt (EcoCrew agent-ia-1.3,
# 2026-11-22: 7 of 12 prompts). They come before every ask, so none hides behind one.
if [[ -n "$GUARD_ASK_Q" ]]; then
    deny "kit-cwd: this kit script ($GUARD_ASK_Q) is run by a relative path where the directory is not the project root or a registered worktree, or is not provably so: a nested copy of the kit script would run instead of the project's own.\\n\\nRun it alone, as the first command of its own Bash call, from the project root or a registered worktree, or right after a lone 'cd <absolute root> &&'. Pipe nothing into it and put no loop, ';' or other command before it."
fi
if [[ -n "$GUARD_ASK_T" ]]; then
    deny "This write goes through a /tmp or fd path that may land inside the project ($GUARD_ASK_T).\\n\\nWrite files with the Write/Edit tool. To keep a command's output, read it directly. A /tmp write that must stay in the shell goes in its own Bash call, with no cp, mv, ln, tar or unknown program beside it."
fi
if [[ -n "$GUARD_ASK_U" ]]; then
    deny "unresolved write target ($GUARD_ASK_U): a variable, a substitution, an unknown directory or an inline program decides where this writes, so the guarded set cannot be checked.\\n\\nWrite files with the Write/Edit tool, or spell the target as a literal path. No inline program (python3 -, python3 -c, node -e) and no no-op probe such as an empty heredoc: Read/Grep to read, Write/Edit to write."
fi

# The text fallback's ask half: a guarded name, a heredoc, a redirect or a writer verb.
guard_text_writes() {
    local pattern prefix bare
    [[ "$COMMAND" == *.claude/* || "$COMMAND" == *'<<'* ]] && return 0
    for pattern in "${CWK_GUARDED[@]}"; do
        prefix="${pattern%%[*?[]*}"
        [[ -n "$prefix" && "$COMMAND" == *"$prefix"* ]] && return 0
    done
    bare="$(sed -E 's/[0-9]*>&[0-9-]+//g' <<<"$COMMAND")"
    [[ "$bare" == *'>'* || "$COMMAND" == *--output* ]] && return 0
    grep -qE '(^|[^[:alnum:]_.-])(tee|cp|mv|install|rsync|ln|patch|rm|rmdir|unlink|shred|truncate|touch|chmod|chown|sed|perl|ruby|python[0-9.]*|node|bash|sh|zsh|eval|find|rg)([^[:alnum:]_.-]|$)' <<<"$COMMAND"
}

if [[ -n "$SECRET_ASK" ]]; then
    ask "This read may print a secret: ${SECRET_ASK:0:300}.\\n\\nSay what it searches and why, then let the user decide. A search that honours .gitignore (plain grep -r, rg without -u/--no-ignore/--hidden) skips .env."
fi
guard_runs_tool() {
    local word
    local -a words
    read -ra words <<< "${COMMAND//$'\n'/ }"
    for word in "${words[@]}"; do
        case "${word##*/}" in
            pnpm | npm | npx | yarn | bunx | vitest | vite | tsc | playwright) return 0 ;;
        esac
    done
    return 1
}

if [[ -n "$GUARD_PARSE" ]] && { guard_runs_tool || guard_text_writes; }; then
    ask "the shell guard could not parse this command: $GUARD_PARSE.\\n\\nShow the exact command, then let the user decide; writing it without that construct avoids this prompt."
fi
if [[ "$GUARD_FAILED" == 1 ]] && guard_runs_tool; then
    ask "The shell guard could not parse this command (an unclosed quote or an escape it cannot read), and it runs a package runner or a test/build tool whose options can write anywhere.\\n\\nShow the exact call, then let the user decide; quoting it plainly avoids this prompt."
fi
if [[ "$GUARD_FAILED" == 1 ]] && guard_text_writes; then
    ask "shell guard unavailable: shell_targets.py is missing, broken or python3 is absent, so the write targets of this command cannot be resolved.\\n\\nApprove only if it writes nothing under the kit's guardrails (.claude/, package.json, tsconfig*, vite/vitest/eslint configs, .github/workflows/, the root launchers install.sh, workflow.py, workflow.sh, codex-handoff.sh, addons/). Run /kit:doctor."
fi
for GUARD_AUTO_REL in ${GUARD_AUTO_LEDGER[@]+"${GUARD_AUTO_LEDGER[@]}"}; do
    jq -cn --arg rel "$GUARD_AUTO_REL" --arg abs "$GUARD_AUTO_TREE/$GUARD_AUTO_REL" \
        '{loop_record_op: "guarded", path: $rel, abs: $abs, tool: "shell"}' \
        | python3 -I "$HOOK_DIR/loop-record.py" >/dev/null 2>&1 \
        || deny "auto mode — blocked stop: the shell write of $GUARD_AUTO_REL could not be recorded in the loop record's guarded ledger, so it is not allowed unrecorded."
done
if [[ -n "$GUARD_ASK_G" ]]; then
    ask_or_block "guarded path: $GUARD_ASK_G (kit guardrail; approve only if you meant to change it).\\n\\nWrite files with the Write/Edit tool instead."
fi
if [[ -n "$GUARD_ASK_S" ]]; then
    ask "This test run rewrites the snapshots ($GUARD_ASK_S).\\n\\n.claude/rules/05-testing.md forbids snapshot updates that bypass Write/Edit. Approve only if the user asked for it."
fi
if [[ -n "$GUARD_ASK_C" ]]; then
    ask_or_block "This tool option writes a guarded config ($GUARD_ASK_C): tsc --init writes tsconfig.json, coverage.thresholds.autoUpdate rewrites the vitest config. Approve only if you meant to change it."
fi
if [[ -n "$GUARD_ASK_K" ]]; then
    ask "This run deletes Vitest's caches ($GUARD_ASK_K) instead of running tests. Say why, then let the user decide."
fi
if [[ -n "$GUARD_ASK_W" ]]; then
    ask "'${GUARD_ASK_W#* }' is not on the hook's safe-option list for ${GUARD_ASK_W%% *}: an unknown option or spelling may load a config, rewrite snapshots, or write or delete files. Spell it as listed, or let the user decide."
fi
if [[ -n "$GUARD_ASK_P" ]]; then
    ask_or_block "recursive delete/move under a protected dir: $GUARD_ASK_P.\\n\\nProtected: $PROTECTED_TEXT. Approve only if this subtree is meant to go."
fi
if [[ -n "$GUARD_ASK_M" ]]; then
    ask_or_block "this moves a path under a protected dir: $GUARD_ASK_M.\\n\\nProtected: $PROTECTED_TEXT. A move out of the tree is a deletion from it; Write/Edit cannot rename, so the user decides."
fi
if [[ -n "$GUARD_ASK_F" ]]; then
    ask "A tool option targets $GUARD_ASK_F: flag-r empties or rewrites that folder, flag-w writes that file, cfg loads its config from there, a file the agent may have written. Approve only if that path is meant."
fi
if [[ -n "$GUARD_ASK_O" ]]; then
    ask "This writes outside the project ($GUARD_ASK_O): no guardrail of the kit covers that path. Say what it writes and why, then let the user decide."
fi
if [[ -n "$GUARD_ASK_R" ]]; then
    ask "This rm deletes recursively ($GUARD_ASK_R). Say what it removes and why, then let the user decide."
fi

# =============================================================================
# FORMATTER WRITING A WHOLE FOLDER  —  an `ask`, so after every deny
#
# `prettier --write .` on a track reformatted 99 files nobody touched and left 12
# rebase conflicts. The on-save hooks already format each written file; by hand,
# a formatter in write mode is only needed on the files of the diff. A target
# that is a folder, `.`, a glob, or nothing at all (eslint's default) is asked.
# `ruff` is the exception for a named folder: the FastAPI addon prescribes
# `ruff format app/`, scoped away from the frozen `tests/services/`; a ruff
# target under `tests/` is asked like a folder.
# =============================================================================
FORMAT_WIDE=""
# cwk_segments splits at every `&`, so `2>&1 .`, `>&2 .` and `&>/dev/null .` reach
# this loop cut in two, the folder target in a segment with no formatter word. The
# `&` is restored first: a segment ending in `N>` followed by one starting with a
# digit, or any segment followed by one starting with `>`, is one redirection.
FORMAT_SEGS=()
while IFS= read -r SEG; do
    FORMAT_LAST=$((${#FORMAT_SEGS[@]} - 1))
    FORMAT_PREV_SKIPPED=0
    # A git/echo/printf part is skipped below, so a rejoin must never hide the next part inside it.
    [[ "$FORMAT_LAST" -lt 0 || ! "${FORMAT_SEGS[$FORMAT_LAST]}" =~ ^[[:space:]]*(git|echo|printf)[[:space:]] ]] || FORMAT_PREV_SKIPPED=1
    if [[ "$FORMAT_LAST" -ge 0 && "$FORMAT_PREV_SKIPPED" == 0 ]] \
        && [[ "${FORMAT_SEGS[$FORMAT_LAST]}" =~ [0-9]*\>[[:space:]]*$ && "$SEG" =~ ^[0-9] ]]; then
        FORMAT_SEGS[$FORMAT_LAST]="${FORMAT_SEGS[$FORMAT_LAST]%"${FORMAT_SEGS[$FORMAT_LAST]##*[![:space:]]}"}&$SEG"
    elif [[ "$FORMAT_LAST" -ge 0 && "$FORMAT_PREV_SKIPPED" == 0 && "$SEG" =~ ^\> && "$COMMAND" == *"&$SEG"* ]]; then
        # Joined only when the split was on an `&` right before the `>`, never on `;` or a newline.
        FORMAT_SEGS[$FORMAT_LAST]="${FORMAT_SEGS[$FORMAT_LAST]%"${FORMAT_SEGS[$FORMAT_LAST]##*[![:space:]]}"} &$SEG"
    else
        FORMAT_SEGS+=("$SEG")
    fi
done < <(cwk_segments "$COMMAND")
FORMAT_GLUED_RE='^[0-9]*(>|>>|>\||&>|&>>)[^[:space:]]+$'
FORMAT_BARE_RE='^[0-9]*(>|>>|>\||&>|&>>)$'
set -f
for SEG in ${FORMAT_SEGS[@]+"${FORMAT_SEGS[@]}"}; do
    [[ "$SEG" =~ ^[[:space:]]*(git|echo|printf)[[:space:]] ]] && continue
    [[ "$SEG" =~ (^|[[:space:]])xargs[[:space:]] ]] && continue
    [[ "$SEG" == *'$('* || "$SEG" == *'`'* ]] && continue
    if [[ "$SEG" =~ (^|[[:space:]])(pnpm|npm|yarn)([[:space:]]+run)?[[:space:]]+(lint[^[:space:]]*) ]]; then
        LINT_SCRIPT="${BASH_REMATCH[4]}"
        if [[ "$SEG" =~ $FORMAT_FIX_RE ]]; then
            FORMAT_WIDE="the $LINT_SCRIPT script's own targets"
            break
        fi
    fi
    TOOL_ARGS=$(echo "$SEG" | grep -oE '\b(prettier|eslint|ruff[[:space:]]+(format|check)|biome[[:space:]]+(format|check|lint))\b.*' || true)
    [[ -z "$TOOL_ARGS" ]] && continue
    case "$TOOL_ARGS" in
        prettier*) [[ "$TOOL_ARGS" =~ [[:space:]](--write|-w)([[:space:]]|$) ]] || continue ;;
        eslint*) [[ "$TOOL_ARGS" =~ $FORMAT_FIX_RE ]] || continue ;;
        ruff*check*) [[ "$TOOL_ARGS" =~ $FORMAT_FIX_RE ]] || continue ;;
        ruff*) [[ "$TOOL_ARGS" =~ [[:space:]](--check|--diff)([[:space:]]|$) ]] && continue ;;
        biome*) [[ "$TOOL_ARGS" =~ [[:space:]]--write([[:space:]]|$) ]] || continue ;;
    esac
    TOOL="${TOOL_ARGS%% *}"
    TARGETS=0
    SKIP_NEXT=0
    for word in $(echo "$TOOL_ARGS" | sed -E 's/^(ruff[[:space:]]+(format|check)|biome[[:space:]]+(format|check|lint)|prettier|eslint)//'); do
        if [[ "$SKIP_NEXT" == 1 ]]; then SKIP_NEXT=0; continue; fi
        [[ "$word" =~ $FORMAT_GLUED_RE ]] && continue
        if [[ "$word" =~ $FORMAT_BARE_RE ]]; then SKIP_NEXT=1; continue; fi
        case "$word" in
            --max-warnings|--log-level|--config|-c|--cache-location|--ignore-path|--plugin|--rule|--ext|--format|-f|--parser|--output-file|-o|--resolve-plugins-relative-to|--select|--ignore|--line-length|--target-version)
                SKIP_NEXT=1; continue ;;
            -*) continue ;;
        esac
        TARGETS=$((TARGETS + 1))
        if [[ "$word" == "." || "$word" == "./" || "$word" == *"*"* ]]; then
            FORMAT_WIDE="$word"
        elif [[ "$TOOL" == ruff && "$word" =~ ^(\./)?tests(/|$) ]]; then
            FORMAT_WIDE="$word"
        elif [[ "$TOOL" != ruff && ( "$word" == */ || ! "$word" =~ \.[A-Za-z0-9]+$ ) ]]; then
            FORMAT_WIDE="$word"
        fi
    done
    [[ "$TARGETS" -eq 0 ]] && FORMAT_WIDE="the default, every file"
    [[ -n "$FORMAT_WIDE" ]] && break
done
set +f

if [[ -n "$FORMAT_WIDE" ]]; then
    ask "This runs a formatter in write mode on a whole folder ($FORMAT_WIDE).\n\nOn a track it rewrites files the diff never touched and turns into rebase conflicts later (.claude/guides/10-worktrees.md); in Python it can rewrite the frozen tests/services/ past the freeze. The on-save hooks (format-on-save.sh, ruff-on-save.sh) already format each file as it is written; to format by hand, name the changed files: git diff --name-only.\n\nIf the whole-folder pass is deliberate (a one-off formatting commit on its own), say so and let the user decide."
fi

if [[ -n "$GUARD_ASK_CG" && "$SRC_VERB_SEEN" != 1 ]]; then
    ask "codegen: $GUARD_ASK_CG is written by a generator listed in .claude/project.json. Say what it generates, then let the user decide."
fi

if [[ "$SRC_WRITE_SEEN" == "1" ]]; then
    ask "This writes a TypeScript source from the shell, so no PreToolUse guardrail sees it (no-any, forbidden icons, architecture layering all run on Write|Edit only).\\n\\nIf this is authored code, write it with the Write/Edit tool instead. If it is genuine codegen (generated DB types), say what it generates and where — then let the user decide.\\n\\nWrite files with the Write/Edit tool instead."
fi

exit 0
