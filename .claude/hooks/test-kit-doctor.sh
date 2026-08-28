#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_OUTPUT="$(python3 "$HOOKS_DIR/kit-doctor.py")"
grep -q 'version: 0.1.0 (tag: unknown)' <<<"$SOURCE_OUTPUT"

SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/.claude/hooks"
cp "$HOOKS_DIR/kit-doctor.py" "$SCRATCH/.claude/hooks/kit-doctor.py"
cp "$HOOKS_DIR/../VERSION" "$SCRATCH/.claude/VERSION"
INSTALLED_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'version: 0.1.0 (tag: v0.1.0)' <<<"$INSTALLED_OUTPUT"

rm "$SCRATCH/.claude/VERSION"
UNKNOWN_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'version: unknown (tag: unknown)' <<<"$UNKNOWN_OUTPUT"

echo 'kit-doctor version fixtures: green.'
