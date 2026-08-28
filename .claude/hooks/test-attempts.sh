#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/docs/work/example"
ARTIFACT="$SCRATCH/docs/work/example/plan.md"
touch "$ARTIFACT"
BOARD="$SCRATCH/docs/product/backlog.md"
mkdir -p "$(dirname "$BOARD")"
cp "$HOOKS_DIR/fixtures/_harness/backlog.md" "$BOARD"

python3 "$HOOKS_DIR/kit-attempts.py" fail "$ARTIFACT" tests first --now 2026-08-28T10:00:00Z >/dev/null
python3 "$HOOKS_DIR/kit-attempts.py" fail "$ARTIFACT" tests second --now 2026-08-28T10:01:00Z >/dev/null
set +e
THIRD="$(python3 "$HOOKS_DIR/kit-attempts.py" fail "$ARTIFACT" tests third \
    --now 2026-08-28T10:02:00Z --board "$BOARD" --unit 'Example bug')"
CODE=$?
set -e
[[ "$CODE" -eq 3 ]]
jq -e '.blocked == true and .count == 3 and .reason == "third"' <<<"$THIRD" >/dev/null
jq -e '.tests == {count: 3, last: "2026-08-28T10:02:00Z", reason: "third"}' \
    "$SCRATCH/docs/work/example/attempts.json" >/dev/null
grep -Fq '| Example bug | docs/work/example/debug.md | BUG | BLOCKED — tests failed 3x : third | — |' "$BOARD"

python3 "$HOOKS_DIR/kit-attempts.py" pass "$ARTIFACT" tests >/dev/null
jq -e 'has("tests") | not' "$SCRATCH/docs/work/example/attempts.json" >/dev/null
echo 'attempt counter fixtures: green.'
