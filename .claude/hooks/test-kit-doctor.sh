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

mkdir -p "$SCRATCH/.claude/commands/loop" "$SCRATCH/.claude/rules" "$SCRATCH/templates/github"
printf '### 1. Gates\n```bash\npnpm audit --audit-level=high\n```\n' > "$SCRATCH/.claude/commands/loop/ship.md"
printf '```bash\npnpm audit --prod --audit-level=high\n```\n' > "$SCRATCH/.claude/rules/00-project.md"
printf '      - run: pnpm audit --prod --audit-level=high\n' > "$SCRATCH/templates/github/ci.yml"
AUDIT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  audit-flags' <<<"$AUDIT_OUTPUT"
printf '### 1. Gates\n```bash\npnpm audit --prod --audit-level=high\npnpm audit --dev --audit-level=high || true\n```\n' \
    > "$SCRATCH/.claude/commands/loop/ship.md"
AUDIT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'ok          audit-flags' <<<"$AUDIT_OUTPUT"

echo 'kit-doctor version fixtures: green.'
