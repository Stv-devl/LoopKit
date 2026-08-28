#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
TARGET="$SCRATCH/target"
mkdir -p "$TARGET"

"$ROOT/install.sh" "$TARGET" --no-ci >/dev/null 2>&1
BEFORE="$(jq '[.hooks[][]?.hooks[]?] | length' "$TARGET/.claude/settings.json")"
grep -Fxq core "$TARGET/.claude/INSTALL_PROFILE"
jq -e '[.hooks[][]?.hooks[]?.command] | all(
    contains("no-any-type.sh") or
    contains("no-forbidden-icons.sh") or
    contains("enforce-architecture.py") or
    contains("tdd-") or
    contains("eslint-") or
    contains("format-on-save.sh") | not
)' "$TARGET/.claude/settings.json" >/dev/null
python3 "$TARGET/.claude/hooks/kit-doctor.py" | grep -Fq 'No divergence.'

# A second install re-merges the selected layer into active settings.
"$ROOT/install.sh" "$TARGET" --no-ci >/dev/null 2>&1
[[ ! -e "$TARGET/.claude/settings.json.new" ]]
AFTER="$(jq '[.hooks[][]?.hooks[]?] | length' "$TARGET/.claude/settings.json")"
[[ "$BEFORE" -eq "$AFTER" ]]

# A user-owned key survives another reinstall; hook groups have no duplicates.
jq '.userFixture = true' "$TARGET/.claude/settings.json" >"$SCRATCH/settings.json"
cp "$SCRATCH/settings.json" "$TARGET/.claude/settings.json"
"$ROOT/install.sh" "$TARGET" --no-ci >/dev/null 2>&1
jq -e '.userFixture == true' "$TARGET/.claude/settings.json" >/dev/null
jq -e '[.hooks[][]?.hooks? | map(.command) as $commands | select(($commands | length) != ($commands | unique | length))] | length == 0' \
    "$TARGET/.claude/settings.json" >/dev/null

# React/TS is opt-in and brings every front guardrail back.
REACT_TARGET="$SCRATCH/react-target"
mkdir -p "$REACT_TARGET"
"$ROOT/install.sh" "$REACT_TARGET" --react-ts --no-ci >/dev/null 2>&1
grep -Fxq react-ts "$REACT_TARGET/.claude/INSTALL_PROFILE"
for hook in no-any-type.sh no-forbidden-icons.sh enforce-architecture.py \
            tdd-freeze-tests.sh tdd-require-red.sh tdd-prove-red.sh \
            eslint-check.sh eslint-batch.sh format-on-save.sh; do
    jq -e --arg hook "$hook" '[.hooks[][]?.hooks[]?.command] | any(endswith($hook))' \
        "$REACT_TARGET/.claude/settings.json" >/dev/null
done

# FastAPI is cumulative directly on core and its six hooks stay idempotent.
PY_TARGET="$SCRATCH/python-target"
mkdir -p "$PY_TARGET"
"$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci >/dev/null 2>&1
for hook in no-any-type-py.py enforce-backend-layers.py tdd-require-red-py.py \
            tdd-freeze-tests-py.py ruff-on-save.sh tdd-prove-red-py.py; do
    jq -e --arg hook "$hook" '[.hooks[][]?.hooks[]?.command] | any(endswith($hook))' \
        "$PY_TARGET/.claude/settings.json" >/dev/null
done
PY_COUNT="$(jq '[.hooks[][]?.hooks[]?.command | select(endswith("-py.py") or endswith("ruff-on-save.sh") or endswith("enforce-backend-layers.py") or endswith("no-any-type-py.py"))] | length' "$PY_TARGET/.claude/settings.json")"
"$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci >/dev/null 2>&1
[[ "$PY_COUNT" -eq "$(jq '[.hooks[][]?.hooks[]?.command | select(endswith("-py.py") or endswith("ruff-on-save.sh") or endswith("enforce-backend-layers.py") or endswith("no-any-type-py.py"))] | length' "$PY_TARGET/.claude/settings.json")" ]]

echo 'install fixtures: green.'
