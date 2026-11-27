#!/usr/bin/env bash
# Fixtures for .claude/scripts/kit-lint.sh, the kit repo's local twin of kit-ci.yml's lint.
# A stub uvx on PATH stands for the three pinned runners; a scratch kit-source tree stands
# for the repo. Nothing here touches the network.
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HOOKS_DIR/../scripts/kit-lint.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT

fail() { echo "kit-lint fixtures: $1" >&2; exit 1; }

TREE="$SCRATCH/tree"
mkdir -p "$TREE/addons" "$TREE/.claude/hooks" "$TREE/.claude/scripts" "$TREE/.github/workflows" \
    "$TREE/templates/github/publish"
printf '#!/usr/bin/env bash\necho a\n' >"$TREE/.claude/hooks/a.sh"
printf '#!/usr/bin/env bash\necho b\n' >"$TREE/.claude/scripts/b.sh"
printf 'name: w\n' >"$TREE/.github/workflows/w.yml"
printf 'x\n' >"$TREE/templates/github/publish/one.yml"
printf 'x\n' >"$TREE/templates/github/publish/two.yml"
cat >"$TREE/install.sh" <<'EOF'
#!/usr/bin/env bash
target="$1"; deploy=""
for a in "$@"; do case "$a" in --deploy=*) deploy="${a#--deploy=}" ;; esac; done
mkdir -p "$target/.github/workflows"
printf 'name: %s\n' "$deploy" >"$target/.github/workflows/$deploy.yml"
EOF
chmod +x "$TREE/install.sh"

BIN="$SCRATCH/bin"
CFG="$SCRATCH/cfg"
mkdir -p "$BIN" "$CFG"
cat >"$BIN/uvx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CFG/log"
case "$*" in
    *shellcheck-py*) tool=shellcheck ;;
    *ruff@*) tool=ruff ;;
    *actionlint-py*) tool=actionlint ;;
    *) exit 99 ;;
esac
mode=run
case " $* " in *" --version "*) mode=probe ;; esac
out="$STUB_CFG/$tool.$mode.out"
code="$STUB_CFG/$tool.$mode.code"
if [[ "$mode" == run && -f "$STUB_CFG/$tool.match" ]]; then
    case "$*" in *"$(cat "$STUB_CFG/$tool.match")"*) ;; *) exit 0 ;; esac
fi
[[ -f "$out" ]] && cat "$out"
[[ -f "$code" ]] && exit "$(cat "$code")"
exit 0
EOF
chmod +x "$BIN/uvx"
# A PATH holding the stub, then only the system tools the gate may use.
SYS_PATH="/usr/bin:/bin"

reset_cfg() { rm -f "$CFG"/*; rm -rf "$SCRATCH/tmp"; mkdir -p "$SCRATCH/tmp"; }
OUT=""
CODE=0
run_gate() {
    local path="$1"
    set +e
    OUT="$(cd "$TREE" && env PATH="$path" STUB_CFG="$CFG" TMPDIR="$SCRATCH/tmp" \
        KIT_LINT_ROOT="$TREE" bash "$GATE" 2>&1)"
    CODE=$?
    set -e
}
has() { grep -Fq -- "$1" <<<"$OUT"; }

# KL1 a shellcheck finding: exit 1, the tool's full line (file and rule), then the FAIL line.
reset_cfg
printf '.claude/hooks/a.sh:3:1: warning SC1010\n' >"$CFG/shellcheck.run.out"
echo 1 >"$CFG/shellcheck.run.code"
run_gate "$BIN:$SYS_PATH"
[[ "$CODE" -eq 1 ]] || fail "KL1: exit $CODE, expected 1"
has '.claude/hooks/a.sh:3:1: warning SC1010' || fail 'KL1: tool output not printed'
has 'kit-lint: shellcheck FAIL' || fail 'KL1: no shellcheck FAIL line'

# KL2 every tool clean: exit 0 and one ok line per step.
reset_cfg
run_gate "$BIN:$SYS_PATH"
[[ "$CODE" -eq 0 ]] || fail "KL2: exit $CODE, expected 0: $OUT"
for kl2 in shellcheck ruff actionlint actionlint-targets:one actionlint-targets:two; do
    has "kit-lint: $kl2 ok" || fail "KL2: no ok line for $kl2"
done

# KL3 a ruff finding: exit 1, its line printed, ruff FAIL, the other steps still run.
reset_cfg
printf '.claude/hooks/x.py:4:5: F841\n' >"$CFG/ruff.run.out"
echo 1 >"$CFG/ruff.run.code"
run_gate "$BIN:$SYS_PATH"
[[ "$CODE" -eq 1 ]] || fail "KL3: exit $CODE, expected 1"
has '.claude/hooks/x.py:4:5: F841' || fail 'KL3: tool output not printed'
has 'kit-lint: ruff FAIL' || fail 'KL3: no ruff FAIL line'
has 'kit-lint: shellcheck ok' || fail 'KL3: shellcheck step did not run'
has 'kit-lint: actionlint ok' || fail 'KL3: actionlint step did not run'

# KL4 an actionlint finding on .github/workflows: exit 1, actionlint FAIL.
reset_cfg
printf '.github/workflows/w.yml' >"$CFG/actionlint.match"
printf '.github/workflows/w.yml:1:1: bad [syntax-check]\n' >"$CFG/actionlint.run.out"
echo 1 >"$CFG/actionlint.run.code"
run_gate "$BIN:$SYS_PATH"
[[ "$CODE" -eq 1 ]] || fail "KL4: exit $CODE, expected 1"
has 'kit-lint: actionlint FAIL' || fail 'KL4: no actionlint FAIL line'

# KL5 the runners receive kit-ci.yml's arguments and pinned versions (the argv is the contract).
reset_cfg
run_gate "$BIN:$SYS_PATH"
grep -Fq -- '--from shellcheck-py==0.11.0.1 shellcheck -S warning .claude/hooks/a.sh' "$CFG/log" \
    || fail 'KL5: shellcheck argv'
grep -Fq -- 'ruff@0.17.4 check --select E4,E7,E9,F .claude/hooks .claude/scripts' "$CFG/log" \
    || fail 'KL5: ruff argv'
grep -Fq -- '--from actionlint-py==1.7.12.24 actionlint .github/workflows/w.yml' "$CFG/log" \
    || fail 'KL5: actionlint argv'

# KL6 no uvx on PATH: exit 1, each tool MISSING, no ok line.
reset_cfg
run_gate "$SYS_PATH"
[[ "$CODE" -eq 1 ]] || fail "KL6: exit $CODE, expected 1"
for kl6 in shellcheck ruff actionlint; do
    has "kit-lint: $kl6 MISSING: uvx not found" || fail "KL6: no MISSING line for $kl6"
done
if grep -Eq 'kit-lint: [^ ]+ ok' <<<"$OUT"; then fail 'KL6: an ok line without uvx'; fi

# KL7 the ruff runner cannot be fetched: MISSING with the reason, no lint run, others still run.
reset_cfg
printf 'error: failed to fetch\n' >"$CFG/ruff.probe.out"
echo 2 >"$CFG/ruff.probe.code"
run_gate "$BIN:$SYS_PATH"
[[ "$CODE" -eq 1 ]] || fail "KL7: exit $CODE, expected 1"
has 'kit-lint: ruff MISSING' || fail 'KL7: no ruff MISSING line'
has 'failed to fetch' || fail 'KL7: reason not shown'
if grep -Fq 'ruff@0.17.4 check' "$CFG/log"; then fail 'KL7: ruff lint ran after a failed probe'; fi
has 'kit-lint: shellcheck ok' || fail 'KL7: shellcheck step did not run'

# KL8 a finding only in the assembled `two` target: two FAIL, one ok.
reset_cfg
printf 'two.yml' >"$CFG/actionlint.match"
printf 'two.yml:1:1: bad [syntax-check]\n' >"$CFG/actionlint.run.out"
echo 1 >"$CFG/actionlint.run.code"
run_gate "$BIN:$SYS_PATH"
[[ "$CODE" -eq 1 ]] || fail "KL8: exit $CODE, expected 1"
has 'kit-lint: actionlint-targets:two FAIL' || fail 'KL8: no two FAIL line'
has 'kit-lint: actionlint-targets:one ok' || fail 'KL8: no one ok line'

# KL9 no temp install dir survives a run, green or red.
reset_cfg
run_gate "$BIN:$SYS_PATH"
[[ -z "$(ls -A "$SCRATCH/tmp")" ]] || fail 'KL9: temp left after a green run'
echo 1 >"$CFG/actionlint.run.code"
run_gate "$BIN:$SYS_PATH"
[[ -z "$(ls -A "$SCRATCH/tmp")" ]] || fail 'KL9: temp left after a red run'

# KL10 an installed project (INSTALL_PROFILE present): exit 2, kit source only, no uvx call.
reset_cfg
printf 'core\n' >"$TREE/.claude/INSTALL_PROFILE"
run_gate "$BIN:$SYS_PATH"
rm "$TREE/.claude/INSTALL_PROFILE"
[[ "$CODE" -eq 2 ]] || fail "KL10: exit $CODE, expected 2"
has 'kit source only' || fail 'KL10: no refusal message'
[[ ! -s "$CFG/log" ]] || fail 'KL10: uvx was called'

echo 'kit-lint fixtures: green (10 cases).'
