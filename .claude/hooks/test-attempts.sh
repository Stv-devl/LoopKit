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

# B2a harness-prompts: an artifact outside docs/work/<slug>/<file>, or a board
# outside docs/product/<file>, is refused before any read or write.
refused() {
    local expect="$1" err code
    shift
    set +e
    err="$(cd "$SCRATCH/a/b" && python3 "$HOOKS_DIR/kit-attempts.py" "$@" 2>&1 >/dev/null)"
    code=$?
    set -e
    [[ "$code" -eq 2 ]] || { echo "expected exit 2, got $code: $*" >&2; exit 1; }
    grep -Fq "kit-attempts: $expect must live at" <<<"$err" \
        || { echo "missing refusal message for: $*" >&2; exit 1; }
}
ARTIFACT_MSG=artifact
mkdir -p "$SCRATCH/a/b"
refused "$ARTIFACT_MSG" fail .claude/hooks/x.md g r
[[ ! -e "$SCRATCH/a/b/.claude/hooks/attempts.json" ]]
refused "$ARTIFACT_MSG" fail .claude/hooks/docs/work/x/plan.md g r
[[ ! -e "$SCRATCH/a/b/.claude/hooks/docs/work/x/attempts.json" ]]
refused "$ARTIFACT_MSG" fail .git/docs/work/x/plan.md g r
[[ ! -e "$SCRATCH/a/b/.git/docs/work/x/attempts.json" ]]
refused "$ARTIFACT_MSG" fail docs/work/plan.md g r
[[ ! -e "$SCRATCH/a/b/docs/work/attempts.json" ]]
refused "$ARTIFACT_MSG" fail docs/work/a/b/plan.md g r
[[ ! -e "$SCRATCH/a/b/docs/work/a/b/attempts.json" ]]
refused "$ARTIFACT_MSG" fail docs/work/../../.claude/x/plan.md g r
[[ ! -e "$SCRATCH/a/b/.claude/x/attempts.json" ]]
refused "$ARTIFACT_MSG" pass .claude/hooks/x.md g
refused "$ARTIFACT_MSG" show .claude/hooks/x.md
[[ ! -e "$SCRATCH/a/b/.claude/hooks/attempts.json" ]]

TRACK="$SCRATCH/.claude/worktrees/small-x/docs/work/small-x/plan.md"
mkdir -p "$(dirname "$TRACK")"
python3 "$HOOKS_DIR/kit-attempts.py" fail "$TRACK" tests worktree --now 2026-08-28T10:00:00Z >/dev/null
jq -e '.tests.count == 1' "$SCRATCH/.claude/worktrees/small-x/docs/work/small-x/attempts.json" >/dev/null

mkdir -p "$SCRATCH/a/b/src"
printf 'untouched\n' > "$SCRATCH/a/b/src/a.md"
python3 "$HOOKS_DIR/kit-attempts.py" fail "$ARTIFACT" boardgate one >/dev/null
python3 "$HOOKS_DIR/kit-attempts.py" fail "$ARTIFACT" boardgate two >/dev/null
cp "$SCRATCH/docs/work/example/attempts.json" "$SCRATCH/attempts.before"
refused board fail "$ARTIFACT" boardgate three --board src/a.md --unit 'Example bug'
[[ "$(cat "$SCRATCH/a/b/src/a.md")" == untouched ]]
cmp -s "$SCRATCH/attempts.before" "$SCRATCH/docs/work/example/attempts.json"
echo 'attempt counter fixtures: green.'
