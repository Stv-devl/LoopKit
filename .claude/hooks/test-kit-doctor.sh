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

git -C "$SCRATCH" init -q
printf 'docs/work/\n.claude/agents/\n' > "$SCRATCH/.gitignore"
IGNORED_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  ignored-loop-paths' <<<"$IGNORED_OUTPUT"
grep -q 'docs/work/' <<<"$IGNORED_OUTPUT"
grep -q '.claude/agents/' <<<"$IGNORED_OUTPUT"
printf 'docs/work/*/handoff.md\n' > "$SCRATCH/.gitignore"
IGNORED_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'ok          ignored-loop-paths' <<<"$IGNORED_OUTPUT"

mkdir -p "$SCRATCH/.claude/skills/templates" "$SCRATCH/.claude/skills/patterns"
printf 'DATA_CLIENT_MODULE = "lib/api"\nDATA_CLIENT_OWN_PATH = "lib/api.ts"\n' > "$SCRATCH/.claude/hooks/enforce-architecture.py"
printf 'import { client } from "@/lib/client";\n' > "$SCRATCH/.claude/skills/templates/feature.md"
printf 'vi.mock("@/lib/client", () => ({}));\n' > "$SCRATCH/.claude/skills/templates/fixtures.md"
printf 'import { client } from "@/lib/api";\n' > "$SCRATCH/.claude/skills/patterns/react-query.md"
printf "exclude: [\n  ...coverageConfigDefaults.exclude,\n  'src/lib/client.ts',      // FILL: the data client INSTANCE\n]\n" \
    > "$SCRATCH/.claude/skills/templates/tooling-config.md"
CLIENT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  client-copies' <<<"$CLIENT_OUTPUT"
grep -q 'templates/feature.md' <<<"$CLIENT_OUTPUT"
grep -q 'templates/tooling-config.md' <<<"$CLIENT_OUTPUT"
if grep -q 'patterns/react-query.md' <<<"$CLIENT_OUTPUT"; then exit 1; fi
printf "exclude: [\n  ...coverageConfigDefaults.exclude,\n  'src/lib/client.ts',\n]\n" \
    > "$SCRATCH/.claude/skills/templates/tooling-config.md"
CLIENT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'templates/tooling-config.md' <<<"$CLIENT_OUTPUT"

echo 'kit-doctor version fixtures: green.'
