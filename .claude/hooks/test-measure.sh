#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HOOKS_DIR/fixtures/_harness/kit-measure"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT

VIEW="$(python3 "$HOOKS_DIR/kit-measure.py" --root "$ROOT" --since 2026-10-01 --json)"

jq -e '.sessions == ["S1"]' <<<"$VIEW" >/dev/null
jq -e '.agents["(session) (opus)"] | .launches == 1 and .turns_median == 3
    and .in == 10 and .write == 1000 and .read == 3000 and .out == 160
    and .cost == 0.0088 and .first_hit_rate == 0' <<<"$VIEW" >/dev/null
jq -e '.agents["reviewer (opus)"] | .launches == 1 and .turns_median == 2
    and .write == 2000 and .read == 7000 and .out == 300 and .cost == 0.0234
    and .first_write_median == 2000 and .first_read_median == 3000
    and .first_hit_rate == 1 and .effort == {medium: 1}' <<<"$VIEW" >/dev/null
jq -e '.phases == {research: 0.0084, interface: 0, plan: 0, execute: 0,
    review: 0.0238, ship: 0}' <<<"$VIEW" >/dev/null

ALL="$(python3 "$HOOKS_DIR/kit-measure.py" --root "$ROOT" --json)"
jq -e '.sessions == ["S1", "S2"] and .agents["(session) (sonnet)"].cost == 2' <<<"$ALL" >/dev/null

python3 "$HOOKS_DIR/kit-measure.py" --root "$ROOT" --since 2026-10-01 \
    --out "$SCRATCH/report.md" --title "Fixture"
grep -Fq '| reviewer (opus) | 1 | 2 | 5 | 2000 | 7000 | 300 | 2000 | 100% | medium 1 | $0.02 | 73% |' \
    "$SCRATCH/report.md"

set +e
python3 "$HOOKS_DIR/kit-measure.py" --root "$SCRATCH/missing" >/dev/null 2>&1
CODE=$?
set -e
[[ "$CODE" -eq 2 ]]
echo 'kit-measure fixtures: green.'
