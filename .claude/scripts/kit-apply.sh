#!/usr/bin/env bash
# Applies a /kit:init proposal (.claude/project.proposed.json) to .claude/project.json.
# The user runs it from their own terminal at the project root: the hooks deny it to every
# tool call, so the agent never applies its own proposal.
#
# The proposal is validated by the project reader on a tmp copy, the current file is backed up
# under .claude/kit-backup/<UTC time>/, the proposal is moved over project.json, then the reader
# checks the project itself (an app root that crosses a symlink there); on that failure every
# change is undone.
# Exit codes: 0 applied, 3 invalid (nothing changed), 4 no proposal.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$PROJECT/.claude/project.json"
PROPOSAL="$PROJECT/.claude/project.proposed.json"
READER="$PROJECT/.claude/hooks/project_config.py"

if [[ ! -f "$PROPOSAL" ]]; then
    echo "kit-apply: no proposal at .claude/project.proposed.json; run /kit:init first." >&2
    exit 4
fi

CHECK_DIR="$(mktemp -d)"
trap 'rm -r "$CHECK_DIR"' EXIT
mkdir -p "$CHECK_DIR/.claude"
cp "$PROPOSAL" "$CHECK_DIR/.claude/project.json"
if ! python3 -I "$READER" check "$CHECK_DIR"; then
    echo "kit-apply: the proposal is invalid; .claude/project.json is unchanged." >&2
    exit 3
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="$PROJECT/.claude/kit-backup"
BACKUP="$BACKUP_ROOT/$STAMP"
if [[ -f "$CONFIG" ]]; then
    mkdir -p "$BACKUP/.claude"
    cp -p "$CONFIG" "$BACKUP/.claude/project.json"
fi
mv "$PROPOSAL" "$CONFIG"
if ! python3 -I "$READER" check "$PROJECT"; then
    mv "$CONFIG" "$PROPOSAL"
    if [[ -f "$BACKUP/.claude/project.json" ]]; then
        cp -p "$BACKUP/.claude/project.json" "$CONFIG"
        rm -r "$BACKUP"
    fi
    rmdir "$BACKUP_ROOT" 2>/dev/null || true
    echo "kit-apply: the proposal is invalid in this project; .claude/project.json is unchanged." >&2
    exit 3
fi
echo "kit-apply: .claude/project.json applied; the previous file is in .claude/kit-backup/$STAMP/."
