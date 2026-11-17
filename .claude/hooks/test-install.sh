#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
# No install below reaches a terminal question (lefthook, remote, CD) when the
# suite itself runs from a terminal; the tty cases get theirs from `script`.
# The doctor runs offline: no `gh` call from the suite.
exec </dev/null
export CWK_DOCTOR_OFFLINE=1
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
jq -e '[.hooks.SessionStart[]? | select(.matcher == "clear") | .hooks[].command] | any(endswith("next-feature-on-clear.py"))' "$TARGET/.claude/settings.json" >/dev/null
for script in "$TARGET"/.claude/scripts/*.sh; do
    [[ -x "$script" ]]
done

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

# The backend gates are allowlisted, or /loop:ship prompts on each of them and a
# reflex "no" drops one silently. Merged, never duplicated by a second install.
for gate in 'Bash(python -m pytest *)' 'Bash(uv run pytest *)' 'Bash(mypy *)' \
            'Bash(ruff check .)' 'Bash(uv audit *)' 'Bash(pyright *)'; do
    jq -e --arg gate "$gate" '.permissions.allow | index($gate)' "$PY_TARGET/.claude/settings.json" >/dev/null
done
jq -e '.permissions.allow | length == (unique | length)' "$PY_TARGET/.claude/settings.json" >/dev/null
if jq -e '.permissions.allow | index("Bash(ruff check *)")' "$PY_TARGET/.claude/settings.json" >/dev/null; then exit 1; fi

# A fresh Supabase install declares lib/supabase and rewrites its template copies,
# or /kit:doctor reports the installer's own divergence on day one.
SB_TARGET="$SCRATCH/supabase-target"
mkdir -p "$SB_TARGET"
"$ROOT/install.sh" "$SB_TARGET" --supabase --no-ci >/dev/null 2>&1
SB_DOCTOR="$(python3 "$SB_TARGET/.claude/hooks/kit-doctor.py" || true)"
grep -q 'ok          client-copies' <<<"$SB_DOCTOR"
grep -q 'ok          coverage-holes' <<<"$SB_DOCTOR"
grep -Fq 'import { supabase as client } from "@/lib/supabase";' "$SB_TARGET/.claude/skills/templates/feature.md"
grep -Fq 'supabase: createMockClient(),' "$SB_TARGET/.claude/skills/templates/fixtures.md"

# The handoff is ignored on a fresh install and added to an older kit's block.
grep -qxF 'docs/work/*/handoff.md' "$PY_TARGET/.gitignore"
sed -i '/^docs\/work\/\*\/handoff.md$/d; /^\.claude\/\.restart-ready$/d' "$PY_TARGET/.gitignore"
"$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci >/dev/null 2>&1
grep -qxF 'docs/work/*/handoff.md' "$PY_TARGET/.gitignore"
[[ "$(grep -cxF '.claude/.restart-ready' "$PY_TARGET/.gitignore")" -eq 1 ]]

# The kit's runtime files are ignored on a fresh install, and back-filled into an
# older kit's block (a worktree's scope check would otherwise see them as drift).
for ignored in .claude/.kit-health.jsonl .claude/settings.local.json __pycache__/ .ruff_cache/ .pr-shots/ 'docs/work/*/pr-body.md'; do
    grep -qxF "$ignored" "$PY_TARGET/.gitignore"
done
# pr-screenshots AC6: no allow for the pr-assets script, a push or a gh pr call.
for pr_allow in kit-pr-assets 'Bash(git push' 'Bash(gh pr'; do
    if jq -e --arg a "$pr_allow" '[.permissions.allow[]? | select(contains($a))] | length > 0' \
        "$PY_TARGET/.claude/settings.json" >/dev/null; then exit 1; fi
done
sed -i '/^\.claude\/\.kit-health\.jsonl$/d; /^\.ruff_cache\/$/d; /^\.pr-shots\/$/d; /^docs\/work\/\*\/pr-body.md$/d' "$PY_TARGET/.gitignore"
"$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci >/dev/null 2>&1
for ignored in .claude/.kit-health.jsonl .ruff_cache/ .pr-shots/ 'docs/work/*/pr-body.md'; do
    [[ "$(grep -cxF "$ignored" "$PY_TARGET/.gitignore")" -eq 1 ]]
done

# I1 key and credential files are ignored on a fresh install, counted in the
# closing line, and back-filled once into an older kit's block.
KEY_TARGET="$SCRATCH/key-target"
mkdir -p "$KEY_TARGET"
KEY_OUT="$("$ROOT/install.sh" "$KEY_TARGET" --no-ci 2>&1)"
grep -Fq '20 chemins' <<<"$KEY_OUT"
for ignored in '*.pem' '*.key' 'credentials.*'; do
    [[ "$(grep -cxF "$ignored" "$KEY_TARGET/.gitignore")" -eq 1 ]]
done
sed -i '/^\*\.pem$/d; /^\*\.key$/d; /^credentials\.\*$/d' "$KEY_TARGET/.gitignore"
"$ROOT/install.sh" "$KEY_TARGET" --no-ci >/dev/null 2>&1
for ignored in '*.pem' '*.key' 'credentials.*'; do
    [[ "$(grep -cxF "$ignored" "$KEY_TARGET/.gitignore")" -eq 1 ]]
done

# I2 hold-back: the narrow permissions (P1) reach a target only when its guard
# hooks carry the current guard api; a target's own settings are never removed.
p1_fresh() {
    mkdir -p "$1"
    "$ROOT/install.sh" "$1" --no-ci >/dev/null 2>&1
}
p1_strip() {
    jq 'del(.permissions.defaultMode) | .permissions.allow -= ["Bash(git add *)"]' \
        "$1/.claude/settings.json" >"$SCRATCH/strip.json"
    cp "$SCRATCH/strip.json" "$1/.claude/settings.json"
}
p1_present() {
    jq -e '.permissions.defaultMode == "acceptEdits" and (.permissions.allow | index("Bash(git add *)"))' \
        "$1/.claude/settings.json" >/dev/null
}
p1_absent() {
    jq -e '(.permissions | has("defaultMode") | not) and (.permissions.allow | index("Bash(git add *)") | not)' \
        "$1/.claude/settings.json" >/dev/null
}
p1_rerun() {
    "$ROOT/install.sh" "$1" --no-ci 2>&1
}

# (c) a fresh install carries P1 and keeps it on a re-run.
HC="$SCRATCH/hold-c"
p1_fresh "$HC"
p1_present "$HC"
p1_rerun "$HC" >/dev/null
p1_present "$HC"

# (d) a target's own edits never hold P1 back, and survive.
HD="$SCRATCH/hold-d"
p1_fresh "$HD"
jq '.protected_dirs += ["docs"] | .protected_branches += ["release"]' "$HD/.claude/project.json" >"$HD/pj.tmp"
mv "$HD/pj.tmp" "$HD/.claude/project.json"
p1_strip "$HD"
HD_OUT="$(p1_rerun "$HD")"
p1_present "$HD"
if grep -Fq 'P1 held back' <<<"$HD_OUT"; then exit 1; fi
jq -e '(.protected_dirs | index("docs")) and (.protected_branches | index("release"))' "$HD/.claude/project.json" >/dev/null
PY_OUT="$("$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci 2>&1)"
if grep -Fq 'P1 held back' <<<"$PY_OUT"; then exit 1; fi

# (DA1) a target's own permissions.deny keeps its entries, first, and gains the
# kit's missing ones in the kit's order, so `Read(!.env.example)` still follows
# `Read(.env.*)`. A re-run adds nothing; a held-back install keeps the deny.
KIT_DENY="$(jq -c '.permissions.deny // []' "$ROOT/.claude/settings.json")"
jq -e 'index("Read(.env.*)") < index("Read(!.env.example)")' <<<"$KIT_DENY" >/dev/null
for carve in 'Read(!.env.*.example)' 'Read(!.env.*.sample)' 'Read(!.env.*.template)'; do
    jq -e --arg carve "$carve" 'index("Read(.env.*)") < index($carve)' <<<"$KIT_DENY" >/dev/null
done
HG="$SCRATCH/deny-own"
p1_fresh "$HG"
jq -e --argjson kit "$KIT_DENY" '.permissions.deny == $kit' "$HG/.claude/settings.json" >/dev/null
jq '.permissions.deny = ["Bash(curl *)", "Read(.env.*)"]' "$HG/.claude/settings.json" >"$SCRATCH/deny.json"
cp "$SCRATCH/deny.json" "$HG/.claude/settings.json"
p1_rerun "$HG" >/dev/null
jq -e --argjson kit "$KIT_DENY" \
    '.permissions.deny == (["Bash(curl *)", "Read(.env.*)"] + ($kit - ["Read(.env.*)"]))
     and (.permissions.deny | index("Read(.env.*)") < index("Read(!.env.example)"))' \
    "$HG/.claude/settings.json" >/dev/null
HG_DENY="$(jq -c '.permissions.deny' "$HG/.claude/settings.json")"
p1_rerun "$HG" >/dev/null
[[ "$(jq -c '.permissions.deny' "$HG/.claude/settings.json")" == "$HG_DENY" ]]

# (g) a deleted guard file is restored by the copy before the settings merge.
HG="$SCRATCH/hold-g"
p1_fresh "$HG"
rm "$HG/.claude/hooks/shell_targets.py"
p1_strip "$HG"
HG_OUT="$(p1_rerun "$HG")"
[[ -f "$HG/.claude/hooks/shell_targets.py" ]]
p1_present "$HG"
if grep -Fq 'P1 held back' <<<"$HG_OUT"; then exit 1; fi

# (I1b) a back-fill into an older block says how many lines it added, never
# that the block was added.
K1B_TARGET="$SCRATCH/key-backfill"
p1_fresh "$K1B_TARGET"
sed -i '/^\*\.pem$/d; /^\*\.key$/d' "$K1B_TARGET/.gitignore"
K1B_OUT="$(p1_rerun "$K1B_TARGET")"
grep -Fq '2 chemins ajoutés' <<<"$K1B_OUT"
if grep -Fq 'bloc « état de session » ajouté' <<<"$K1B_OUT"; then exit 1; fi

# I4 harness-cd: what an assembled target really receives.
cd_install() {
    mkdir -p "$1"
    "$ROOT/install.sh" "$@" >/dev/null 2>&1 </dev/null
}
CD_TEMPLATE="$ROOT/templates/github/dependabot.yml"
# (I4a) dependabot arrives with the CI.
I4A="$SCRATCH/cd-with-ci"
cd_install "$I4A" --deploy=none
cmp -s "$CD_TEMPLATE" "$I4A/.github/dependabot.yml"
# (I4b) and not without it.
I4B="$SCRATCH/cd-no-ci"
cd_install "$I4B" --no-ci
[ ! -e "$I4B/.github/dependabot.yml" ]
# (I5a) CODEOWNERS arrives with the CI, equal to its template.
cmp -s "$ROOT/templates/github/CODEOWNERS" "$I4A/.github/CODEOWNERS"
# (I5b) and not without it.
[ ! -e "$I4B/.github/CODEOWNERS" ]
# (I4c) every target, each on a fresh directory, since copy_file keeps a first deploy.yml.
for fragment in "$ROOT"/templates/github/publish/*.yml; do
    target="$(basename "$fragment" .yml)"
    target_dir="$SCRATCH/cd-target-$target"
    cd_install "$target_dir" --deploy="$target"
    assembled="$target_dir/.github/workflows/deploy.yml"
    grep -Fxq -- "    if: github.event_name == 'workflow_dispatch' || (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_repository.full_name == github.repository && github.event.workflow_run.head_branch == github.event.repository.default_branch)" "$assembled"
    [ "$(grep -c '^    if:' "$assembled")" -eq 1 ]
    [ "$(awk '/^jobs:/ { jobs = 1; next } jobs && /^  [^ #]/ { n++ } END { print n + 0 }' "$assembled")" -eq 1 ]
    assembled_uses="$(grep -E '^[^#]*\buses["'"'"']?[[:space:]]*:' "$assembled")"
    [ -n "$assembled_uses" ]
    if grep -Ev '^[[:space:]]*(- )?uses: [^[:space:]@]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$assembled_uses"; then exit 1; fi
done
# (I4d) the SSH target carries its host key checks once assembled.
grep -Eq '^ +: "\$\{DEPLOY_KNOWN_HOSTS:\?' "$SCRATCH/cd-target-ssh/.github/workflows/deploy.yml"
grep -Fxq -- "          printf '%s\n' \"\$DEPLOY_KNOWN_HOSTS\" > ~/.ssh/known_hosts" "$SCRATCH/cd-target-ssh/.github/workflows/deploy.yml"
grep -Fxq -- '            -e "ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=yes" \' "$SCRATCH/cd-target-ssh/.github/workflows/deploy.yml"
# (I4e) a second install keeps the target's own file and writes the copy beside it.
echo '# local edit' >>"$I4A/.github/dependabot.yml"
cd_install "$I4A" --deploy=none
grep -Fxq '# local edit' "$I4A/.github/dependabot.yml"
cmp -s "$CD_TEMPLATE" "$I4A/.github/dependabot.yml.new"

# HP-B2 harness-prompts: the prompt allows ride with P1. A current install has
# them all, a held-back one none, and a hold-back removes the ones an earlier
# install left while a target's own allow stays.
HP_ALLOWS='["Bash(pnpm exec tsc --noEmit)",
  "Bash(python3 .claude/hooks/kit-attempts.py *)", "Bash(python3 .claude/hooks/kit-doctor.py)",
  "Bash(python3 .claude/hooks/kit-doctor.py *)", "Bash(.claude/scripts/small-dispatch-check.sh *)",
  "Bash(.claude/scripts/small-paths.sh *)", "Bash(.claude/scripts/small-plan.sh *)",
  "Bash(.claude/scripts/small-scope.sh *)", "Bash(git fetch)", "Bash(git fetch *)",
  "Bash(git stash list)", "Bash(python3 .claude/hooks/kit-gate-route.py *)",
  "Bash(python3 .claude/hooks/kit-audit-surface.py *)"]'
for hp_suite in attempts audit-surface gate-route hooks kit-doctor measure rules-floor small-lane; do
    HP_ALLOWS="$(jq -c --arg s "$hp_suite" \
        '. + ["Bash(bash .claude/hooks/test-\($s).sh)", "Bash(bash .claude/hooks/test-\($s).sh *)"]' <<<"$HP_ALLOWS")"
done
jq -e 'length == 29' <<<"$HP_ALLOWS" >/dev/null
hp_all() {
    jq -e --argjson want "$HP_ALLOWS" '(.permissions.allow // []) as $a | all($want[]; . as $w | $a | index($w))' \
        "$1/.claude/settings.json" >/dev/null
}
HPA="$SCRATCH/hp-current"
p1_fresh "$HPA"
hp_all "$HPA"

# HP-A review 5: the argument wildcards of the test, lint, build and typecheck
# runners are retired. A current install drops the ones an earlier install left,
# keeps the bare forms and a target's own allow.
HP_RETIRED='["Bash(pnpm test:run *)", "Bash(pnpm test:coverage *)", "Bash(pnpm typecheck *)",
  "Bash(pnpm lint *)", "Bash(pnpm build *)", "Bash(pnpm vitest run *)", "Bash(pnpm exec vitest run *)",
  "Bash(pnpm exec tsc --noEmit *)", "Bash(pnpm exec playwright test *)"]'
HPR="$SCRATCH/hp-retired"
p1_fresh "$HPR"
jq --argjson r "$HP_RETIRED" '.permissions.allow += $r + ["Bash(make *)"]' \
    "$HPR/.claude/settings.json" >"$SCRATCH/hpr.json"
cp "$SCRATCH/hpr.json" "$HPR/.claude/settings.json"
p1_rerun "$HPR" >/dev/null
jq -e --argjson r "$HP_RETIRED" '(.permissions.allow // []) as $a | all($r[]; . as $w | $a | index($w) | not)' \
    "$HPR/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(make *)") and index("Bash(pnpm test:run)") and index("Bash(pnpm build)")' \
    "$HPR/.claude/settings.json" >/dev/null
p1_present "$HPR"

# Ship audit C2: the kit-development suites (test-install runs install.sh,
# test-workflow-contracts runs workflow.py and codex-handoff.sh) never carry an
# allow into a target: a fresh install has none, a rerun drops an earlier one.
HP_KITDEV='["Bash(bash .claude/hooks/test-install.sh)", "Bash(bash .claude/hooks/test-install.sh *)",
  "Bash(bash .claude/hooks/test-workflow-contracts.sh)", "Bash(bash .claude/hooks/test-workflow-contracts.sh *)"]'
hp_kitdev_none() {
    jq -e --argjson d "$HP_KITDEV" '(.permissions.allow // []) as $a | all($d[]; . as $w | $a | index($w) | not)' \
        "$1/.claude/settings.json" >/dev/null
}
HPD="$SCRATCH/hp-kitdev"
p1_fresh "$HPD"
hp_kitdev_none "$HPD"
jq --argjson d "$HP_KITDEV" '.permissions.allow += $d' "$HPD/.claude/settings.json" >"$SCRATCH/hpd.json"
cp "$SCRATCH/hpd.json" "$HPD/.claude/settings.json"
p1_rerun "$HPD" >/dev/null
hp_kitdev_none "$HPD"
p1_present "$HPD"

# The FastAPI addon allows the exact uv-run lint and type gates, never `uv run *`.
for hp_uv in 'Bash(uv run ruff check .)' 'Bash(uv run ruff check app)' 'Bash(uv run ruff check app/)' \
             'Bash(uv run mypy app)' 'Bash(uv run pyright)'; do
    jq -e --arg a "$hp_uv" '.permissions.allow | index($a)' "$PY_TARGET/.claude/settings.json" >/dev/null
done
if jq -e '.permissions.allow | index("Bash(uv run *)")' "$PY_TARGET/.claude/settings.json" >/dev/null; then exit 1; fi

# (I6) harness-kit-ci K4: the lefthook pre-push is optional, asked only on a
# terminal, default no. `script` gives the install a terminal, fed from a pipe.
LH_TEMPLATE="$ROOT/templates/lefthook.yml"
LH_QUESTION='pre-push local'
lh_tty() {
    mkdir -p "$1"
    printf '%s' "$2" | script -qec "\"$ROOT/install.sh\" \"$1\" --no-ci" /dev/null
}
# (I6a) terminal, Enter → the question is asked, nothing installed.
I6A="$SCRATCH/lh-tty-enter"
I6A_OUT="$(lh_tty "$I6A" $'\n')"
grep -Fq "$LH_QUESTION" <<<"$I6A_OUT"
[ ! -e "$I6A/lefthook.yml" ]
[ -f "$I6A/.claude/settings.json" ]
# (I6b) no terminal → no question, nothing installed.
I6B="$SCRATCH/lh-no-tty"
mkdir -p "$I6B"
I6B_OUT="$("$ROOT/install.sh" "$I6B" --no-ci 2>&1 </dev/null)"
if grep -Fq "$LH_QUESTION" <<<"$I6B_OUT"; then exit 1; fi
[ ! -e "$I6B/lefthook.yml" ]
[ -f "$I6B/.claude/settings.json" ]
# (I6c) --lefthook → installed, equal to the template, no question.
I6C="$SCRATCH/lh-flag"
mkdir -p "$I6C"
I6C_OUT="$("$ROOT/install.sh" "$I6C" --lefthook --no-ci 2>&1 </dev/null)"
cmp -s "$LH_TEMPLATE" "$I6C/lefthook.yml"
if grep -Fq "$LH_QUESTION" <<<"$I6C_OUT"; then exit 1; fi
[ -f "$I6C/.claude/settings.json" ]
# (I6d) terminal, answer o → installed.
I6D="$SCRATCH/lh-tty-yes"
lh_tty "$I6D" $'o\n' >/dev/null
cmp -s "$LH_TEMPLATE" "$I6D/lefthook.yml"
[ -f "$I6D/.claude/settings.json" ]
# (I6e) terminal, input ends before an answer → exit 0, nothing installed.
I6E="$SCRATCH/lh-tty-eof"
lh_tty "$I6E" '' >/dev/null
[ ! -e "$I6E/lefthook.yml" ]
[ -f "$I6E/.claude/settings.json" ]

# IN1-IN3 (app-roots-codegen, amended by project-config): the kit's .claude/project.json
# ships; a v1 file is upgraded in place, keeping its roots, never shadowed by a .new; and
# project_config.py carries its api line.
cmp -s "$ROOT/.claude/project.json" "$TARGET/.claude/project.json"
printf '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[]}\n' > "$TARGET/.claude/project.json"
rm -f "$TARGET/.claude/project.json.new"
"$ROOT/install.sh" "$TARGET" --no-ci >/dev/null 2>&1
jq -e '.schema_version == 3 and .app_roots == ["frontend"]' "$TARGET/.claude/project.json" >/dev/null
[ ! -e "$TARGET/.claude/project.json.new" ]
grep -q '^# cwk-guard-api: [0-9]' "$TARGET/.claude/hooks/project_config.py"

# IN4-IN13 (project-config step 6): `project_config.py migrate` reads a target's active hooks.
MIGRATE=(python3 -I -B "$ROOT/.claude/hooks/project_config.py" migrate)
# A target holding only the given hook files, each one line per argument after its name.
mig_tree() {
    local dir="$1" file
    shift
    mkdir -p "$dir/.claude/hooks"
    while [[ $# -gt 0 ]]; do
        file="$1"
        shift
        printf '%s\n' "$1" >>"$dir/.claude/hooks/$file"
        shift
    done
}
# IN4 EcoCrew's active hook lines, through a real install.
IN4="$SCRATCH/in4"
mig_tree "$IN4" \
    enforce-git-workflow.sh 'PROTECTED_BRANCHES="main"' \
    prevent-destructive-commands.sh 'PROTECTED_DIRS="frontend|backend|src|shared|app|alembic|\.claude|public|node_modules|dist"' \
    enforce-architecture.py 'DATA_CLIENT_MODULE = "lib/api"' \
    enforce-architecture.py 'DATA_CLIENT_OWN_PATH = "lib/api.ts"' \
    enforce-architecture.py 'COMPOSITION_ROOTS = ("main.tsx", "routes/__root.tsx")' \
    tdd-prove-red.sh 'RUN_TESTS="pnpm --dir frontend exec vitest run"' \
    tdd_py_lib.py 'MODULE_ROOT = "app"' \
    tdd_py_lib.py 'TEST_FIRST_DIRS = ("services/",)' \
    format-on-save.sh 'if PRETTIER=$(cwk_bin prettier); then' \
    eslint-batch.sh 'ESLINT=$(cwk_bin eslint) || exit 0'
"$ROOT/install.sh" "$IN4" --no-ci >/dev/null 2>&1
jq -e '.protected_branches == ["main"]
    and .protected_dirs == ["frontend","backend","src","shared","app","alembic",".claude","public","node_modules","dist"]
    and .data_client.module == "lib/api" and .data_client.own_path == "lib/api.ts"
    and .data_client.composition_roots == ["main.tsx","routes/__root.tsx"]
    and .data_client.shared_dirs == ["components/","hooks/","lib/","types/","stores/","config/"]
    and .test_command == ["pnpm","--dir","frontend","exec","vitest","run"]
    and .fastapi.module_root == "app" and .fastapi.test_first_dirs == ["services"]
    and .formatter == ["prettier","--write"] and .linter == "eslint"
    and .env_template_suffixes == ["example","sample","template"]
    and .tdd_layers == ["repository","services","mapper","utils"]
    and .app_roots == [] and .codegen_commands == []' "$IN4/.claude/project.json" >/dev/null
# IN5 a branch regex `x/.*` becomes the glob `x/*`.
IN5="$SCRATCH/in5"
mig_tree "$IN5" enforce-git-workflow.sh 'PROTECTED_BRANCHES="main|release/.*"'
"${MIGRATE[@]}" "$IN5" >/dev/null 2>&1
jq -e '.protected_branches == ["main","release/*"]' "$IN5/.claude/project.json" >/dev/null
# IN6 a v1 file is upgraded, keeping its roots and codegen, taking the hook values.
IN6="$SCRATCH/in6"
mig_tree "$IN6" enforce-git-workflow.sh 'PROTECTED_BRANCHES="main"'
printf '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[["supabase","gen","types"]]}\n' \
    >"$IN6/.claude/project.json"
"${MIGRATE[@]}" "$IN6" >/dev/null 2>&1
jq -e '.schema_version == 3 and .app_roots == ["frontend"] and .codegen_commands == [["supabase","gen","types"]]
    and .protected_branches == ["main"]' "$IN6/.claude/project.json" >/dev/null
# IN7 a fresh install writes the kit defaults, and no .new.
IN7="$SCRATCH/in7"
mkdir -p "$IN7"
"$ROOT/install.sh" "$IN7" --no-ci >/dev/null 2>&1
cmp -s <(python3 -I -B "$ROOT/.claude/hooks/project_config.py" defaults) "$IN7/.claude/project.json"
[ ! -e "$IN7/.claude/project.json.new" ]
# IN8 a typed, multi-line, commented EXTERNAL_CLIENTS migrates to the same map.
IN8="$SCRATCH/in8"
mig_tree "$IN8" enforce-backend-layers.py 'EXTERNAL_CLIENTS: dict[str, list[str]] = {
    # the vector store
    "app.core.qdrant": ["core/", "services/search.py"],
    "app.core.mistral": [
        "core/",  # owner
        "services/chat/",
    ],
}'
"${MIGRATE[@]}" "$IN8" >/dev/null 2>&1
jq -e '.fastapi.external_clients == {"app.core.qdrant":["core/","services/search.py"],"app.core.mistral":["core/","services/chat/"]}' \
    "$IN8/.claude/project.json" >/dev/null
# IN9 a value that is not a plain literal keeps the default and says so.
IN9="$SCRATCH/in9"
mig_tree "$IN9" enforce-git-workflow.sh 'PROTECTED_BRANCHES="(main|dev)+"' \
    tdd-prove-red.sh 'RUN_TESTS="pnpm test:run \"$X\""'
IN9_OUT="$("${MIGRATE[@]}" "$IN9" 2>&1)"
jq -e '.protected_branches == ["main","master"] and .test_command == ["pnpm","test:run"]' "$IN9/.claude/project.json" >/dev/null
grep -Fq 'migrate: protected_branches unreadable in enforce-git-workflow.sh, default kept' <<<"$IN9_OUT"
grep -Fq 'migrate: test_command unreadable in tdd-prove-red.sh, default kept' <<<"$IN9_OUT"
# IN10 env copies that disagree: protect-files wins, the other copy is named.
IN10="$SCRATCH/in10"
mig_tree "$IN10" protect-files.sh "ENV_TEMPLATE_RE='\\.(example|dist)\$'" \
    prevent-destructive-commands.sh "    SANITIZED=\$(echo \"\$COMMAND\" | sed -E 's/\\.env\\.(example)//g')"
IN10_OUT="$("${MIGRATE[@]}" "$IN10" 2>&1)"
jq -e '.env_template_suffixes == ["example","dist"]' "$IN10/.claude/project.json" >/dev/null
grep -q 'prevent-destructive-commands.sh' <<<"$IN10_OUT"
# IN11 a second install over a v2 file leaves it byte-identical.
cp "$IN4/.claude/project.json" "$SCRATCH/in4.json"
"$ROOT/install.sh" "$IN4" --no-ci >/dev/null 2>&1
cmp -s "$SCRATCH/in4.json" "$IN4/.claude/project.json"
# IN12 an invalid existing file is left untouched, reported, and the install exits 0.
IN12="$SCRATCH/in12"
mkdir -p "$IN12/.claude"
printf '{"schema_version":2}\n' >"$IN12/.claude/project.json"
IN12_OUT="$("$ROOT/install.sh" "$IN12" --no-ci 2>&1)"
[ "$(cat "$IN12/.claude/project.json")" = '{"schema_version":2}' ]
grep -q 'project.json' <<<"$IN12_OUT"
# IN13 --supabase then --fastapi on a fresh target, then a re-run.
IN13="$SCRATCH/in13"
mkdir -p "$IN13"
"$ROOT/install.sh" "$IN13" --supabase --no-ci >/dev/null 2>&1
"$ROOT/install.sh" "$IN13" --fastapi --no-ci >/dev/null 2>&1
"$ROOT/install.sh" "$IN13" --supabase --fastapi --no-ci >/dev/null 2>&1
jq -e '([.protected_dirs[] | select(. == "supabase")] | length) == 1
    and ([.protected_dirs[] | select(. == "app")] | length) == 1
    and ([.protected_dirs[] | select(. == "alembic")] | length) == 1
    and .data_client.module == "lib/supabase"' "$IN13/.claude/project.json" >/dev/null
grep -q 'lib/supabase' "$IN13/.claude/skills/templates/feature.md"
for f in "$ROOT"/.claude/hooks/*.sh "$ROOT"/.claude/hooks/*.py; do
    cmp -s "$f" "$IN13/.claude/hooks/$(basename "$f")" || { echo "IN13: $(basename "$f") differs" >&2; exit 1; }
done
if python3 -I -B "$IN13/.claude/hooks/kit-doctor.py" "$IN13" 2>&1 | grep -q 'DIVERGENCE  client-copies'; then
    echo 'IN13: client-copies divergence' >&2; exit 1
fi

# IN14 (review 1): an ERE branch is mapped to a glob that matches as much, or the default stays.
IN14="$SCRATCH/in14"
mig_tree "$IN14" enforce-git-workflow.sh 'PROTECTED_BRANCHES="main|master|release.*|hotfix-.*|release/.*"'
"${MIGRATE[@]}" "$IN14" >/dev/null 2>&1
jq -e '.protected_branches == ["main","master","release*","hotfix-*","release/*"]' "$IN14/.claude/project.json" >/dev/null
IN14B="$SCRATCH/in14b"
mig_tree "$IN14B" enforce-git-workflow.sh 'PROTECTED_BRANCHES="main|rel.ease"'
IN14B_OUT="$("${MIGRATE[@]}" "$IN14B" 2>&1)"
jq -e '.protected_branches == ["main","master"]' "$IN14B/.claude/project.json" >/dev/null
grep -Fq 'migrate: protected_branches unreadable in enforce-git-workflow.sh, default kept' <<<"$IN14B_OUT"

# IN15 (review 1): a v2 file the user edited survives a reinstall beside a hook holding an old literal.
IN15="$SCRATCH/in15"
mig_tree "$IN15" enforce-git-workflow.sh 'PROTECTED_BRANCHES="main"'
"$ROOT/install.sh" "$IN15" --no-ci >/dev/null 2>&1
jq '.protected_branches = ["main","develop"]' "$IN15/.claude/project.json" >"$SCRATCH/in15.json"
cp "$SCRATCH/in15.json" "$IN15/.claude/project.json"
"$ROOT/install.sh" "$IN15" --no-ci >/dev/null 2>&1
cmp -s "$SCRATCH/in15.json" "$IN15/.claude/project.json"
jq -e '.protected_branches == ["main","develop"]' "$IN15/.claude/project.json" >/dev/null

# IN17 (review 1): wire_fastapi warns on an invalid project.json, as wire_supabase does.
IN17="$SCRATCH/in17"
mkdir -p "$IN17/.claude"
printf '{"schema_version":2}\n' >"$IN17/.claude/project.json"
IN17_OUT="$("$ROOT/install.sh" "$IN17" --fastapi --no-ci 2>&1)"
grep -Fq 'fastapi non câblé' <<<"$IN17_OUT"

# IN20 (review 2): an upgrade that finds no value anywhere writes the defaults and says so.
IN20="$SCRATCH/in20"
mkdir -p "$IN20"
"$ROOT/install.sh" "$IN20" --no-ci >/dev/null 2>&1
rm -f "$IN20/.claude/project.json"
IN20_OUT="$("$ROOT/install.sh" "$IN20" --no-ci 2>&1)"
cmp -s <(python3 -I -B "$ROOT/.claude/hooks/project_config.py" defaults) "$IN20/.claude/project.json"
grep -Fq 'no value found in the active hooks' <<<"$IN20_OUT"
mkdir -p "$SCRATCH/in20-fresh"
if grep -Fq 'no value found' <<<"$("$ROOT/install.sh" "$SCRATCH/in20-fresh" --no-ci 2>&1)"; then
    echo 'IN20: a fresh install must stay silent' >&2; exit 1
fi

# IN21 (review 2): an invalid file with --fastapi says it is unreadable and stays byte-identical.
IN21="$SCRATCH/in21"
mkdir -p "$IN21/.claude"
printf '{"schema_version":2}\n' >"$IN21/.claude/project.json"
cp "$IN21/.claude/project.json" "$SCRATCH/in21.json"
IN21_OUT="$("$ROOT/install.sh" "$IN21" --fastapi --no-ci 2>&1)"
grep -Fq 'illisible : fastapi non câblé' <<<"$IN21_OUT"
cmp -s "$SCRATCH/in21.json" "$IN21/.claude/project.json"

# IN22 (review 2): without python3 the install says python3 is missing, not that the file is invalid.
IN22="$SCRATCH/in22"
IN22_BIN="$SCRATCH/in22-bin"
mkdir -p "$IN22" "$IN22_BIN"
for tool in env bash dirname basename date jq grep sed cat tr head tail cut sort uniq mktemp rm mkdir wc \
            readlink realpath awk ls touch cp mv ln tee chmod find perl id uname git cmp diff expr; do
    [[ -x "$(command -v "$tool" 2>/dev/null)" ]] && ln -sf "$(command -v "$tool")" "$IN22_BIN/$tool"
done
IN22_OUT="$(PATH="$IN22_BIN" "$ROOT/install.sh" "$IN22" --no-ci 2>&1)" || true
grep -Fq 'python3 absent' <<<"$IN22_OUT"
if grep -Fq 'invalide' <<<"$IN22_OUT"; then echo 'IN22: a missing python3 reported as an invalid file' >&2; exit 1; fi

# IN23 (review 2): the same upgrade from the real a8efa59 kit (a v1 file, api-1 reader, literal hooks).
if git -C "$ROOT" cat-file -e a8efa59:.claude/project.json 2>/dev/null; then
    IN23="$SCRATCH/in23"
    mkdir -p "$IN23"
    git -C "$ROOT" archive a8efa59 .claude | tar -x -C "$IN23"
    sed -i 's/^PROTECTED_BRANCHES=.*/PROTECTED_BRANCHES="main|trunk"/' "$IN23/.claude/hooks/enforce-git-workflow.sh"
    sed -i 's/^PROTECTED_DIRS=.*/PROTECTED_DIRS="src|infra|\\.claude"/' "$IN23/.claude/hooks/prevent-destructive-commands.sh"
    sed -i 's/^DATA_CLIENT_MODULE = .*/DATA_CLIENT_MODULE = "lib\/api"/; s/^DATA_CLIENT_OWN_PATH = .*/DATA_CLIENT_OWN_PATH = "lib\/api.ts"/' \
        "$IN23/.claude/hooks/enforce-architecture.py"
    cp "$IN23/.claude/hooks/enforce-git-workflow.sh" "$SCRATCH/in23-old-git.sh"
    "$ROOT/install.sh" "$IN23" --no-ci >/dev/null 2>&1
    jq -e '.schema_version == 3 and .protected_branches == ["main","trunk"]
        and .protected_dirs == ["src","infra",".claude"] and .data_client.module == "lib/api"' \
        "$IN23/.claude/project.json" >/dev/null
    cmp -s "$IN23/.claude/hooks/enforce-git-workflow.sh" "$ROOT/.claude/hooks/enforce-git-workflow.sh"
    IN23_BK=("$IN23"/.claude/kit-backup/*/.claude/hooks/enforce-git-workflow.sh)
    [ "${#IN23_BK[@]}" -eq 1 ] && cmp -s "${IN23_BK[0]}" "$SCRATCH/in23-old-git.sh"
else
    echo 'SKIP IN23: a8efa59 absent'
fi

# IN25 (review 2): one unreadable alternative drops that item only; the readable ones and the
# defaults stay, with one note per dropped item.
IN25="$SCRATCH/in25"
mig_tree "$IN25" enforce-git-workflow.sh 'PROTECTED_BRANCHES="main|release-[0-9]+|hotfix/.*"' \
    prevent-destructive-commands.sh 'PROTECTED_DIRS="src|infra/.*|\.claude|var-data"'
IN25_OUT="$("${MIGRATE[@]}" "$IN25" 2>&1)"
jq -e '(.protected_branches | sort) == ["hotfix/*","main","master"]
    and (.protected_dirs | index("var-data") != null and index("infra/.*") == null
         and index("shared") != null and index("src") != null)' "$IN25/.claude/project.json" >/dev/null
grep -Fq "migrate: protected_branches unreadable in enforce-git-workflow.sh, default kept ('release-[0-9]+' dropped)" <<<"$IN25_OUT"
grep -Fq "migrate: protected_dirs unreadable in prevent-destructive-commands.sh, default kept ('infra/.*' dropped)" <<<"$IN25_OUT"
[ "$(grep -c 'dropped' <<<"$IN25_OUT")" -eq 2 ]

# IN27-IN29, IN41 (kit-boundary step 5): kit-apply.sh applies a /kit:init proposal from the
# user's terminal: validated, the old file backed up, the proposal moved over project.json.
KA="$SCRATCH/ka"
mkdir -p "$KA"
"$ROOT/install.sh" "$KA" --no-ci >/dev/null 2>&1
KA_APPLY="$KA/.claude/scripts/kit-apply.sh"
[[ -x "$KA_APPLY" ]]
cp "$KA/.claude/project.json" "$SCRATCH/ka-old.json"
jq '.protected_branches = ["main", "trunk"]' "$KA/.claude/project.json" >"$KA/.claude/project.proposed.json"
cp "$KA/.claude/project.proposed.json" "$SCRATCH/ka-proposal.json"
# IN27 a valid proposal: exit 0, project.json is the proposal, the old file backed up, the proposal gone.
bash "$KA_APPLY"
cmp -s "$KA/.claude/project.json" "$SCRATCH/ka-proposal.json"
KA_BACKUP=("$KA"/.claude/kit-backup/*/.claude/project.json)
[ "${#KA_BACKUP[@]}" -eq 1 ] && cmp -s "${KA_BACKUP[0]}" "$SCRATCH/ka-old.json"
[[ ! -e "$KA/.claude/project.proposed.json" ]]
# IN28 an invalid proposal (an unknown key): exit 3, the key named, nothing changed, no backup folder.
rm -r "$KA/.claude/kit-backup"
cp "$KA/.claude/project.json" "$SCRATCH/ka-before.json"
jq '.bogus_key = 1' "$KA/.claude/project.json" >"$KA/.claude/project.proposed.json"
KA_CODE=0
KA_OUT="$(bash "$KA_APPLY" 2>&1)" || KA_CODE=$?
[ "$KA_CODE" -eq 3 ]
grep -Fq bogus_key <<<"$KA_OUT"
cmp -s "$KA/.claude/project.json" "$SCRATCH/ka-before.json"
[[ -e "$KA/.claude/project.proposed.json" && ! -e "$KA/.claude/kit-backup" ]]
# IN41 a proposal whose app root is a symlink in the project: valid in the tmp copy, refused on the
# project itself: exit 3, project.json unchanged, the proposal kept, no backup folder left.
mkdir -p "$KA/frontend"
ln -s frontend "$KA/fe"
jq '.app_roots = ["fe"]' "$SCRATCH/ka-before.json" >"$KA/.claude/project.proposed.json"
KA_CODE=0
bash "$KA_APPLY" >/dev/null 2>&1 || KA_CODE=$?
[ "$KA_CODE" -eq 3 ]
cmp -s "$KA/.claude/project.json" "$SCRATCH/ka-before.json"
[[ -e "$KA/.claude/project.proposed.json" && ! -e "$KA/.claude/kit-backup" ]]
# IN29 no proposal: exit 4, nothing written.
rm "$KA/.claude/project.proposed.json"
KA_CODE=0
bash "$KA_APPLY" >/dev/null 2>&1 || KA_CODE=$?
[ "$KA_CODE" -eq 4 ]
cmp -s "$KA/.claude/project.json" "$SCRATCH/ka-before.json"
[[ ! -e "$KA/.claude/kit-backup" ]]

# IN30-IN40 (kit-boundary step 6): kit code is overwritten from the kit after a backup of the
# files that differ; prompts, rules and docs keep their .new; settings.json still merges.
KO="$SCRATCH/ko"
mkdir -p "$KO"
"$ROOT/install.sh" "$KO" --no-ci >/dev/null 2>&1
# IN34 a fresh install writes the stamp.
grep -Fxq core "$KO/.claude/INSTALL_PROFILE"
# IN31 an up-to-date project: no backup folder, no .new under hooks/ or scripts/, said.
KO_OUT="$("$ROOT/install.sh" "$KO" --no-ci 2>&1)"
[[ ! -e "$KO/.claude/kit-backup" ]]
[ -z "$(find "$KO/.claude/hooks" "$KO/.claude/scripts" -name '*.new')" ]
grep -Fq 'kit code: up to date' <<<"$KO_OUT"
grep -Fxq core "$KO/.claude/INSTALL_PROFILE"
# IN30, IN32, IN33, IN35, IN39 in one re-install.
printf '# local\n' >>"$KO/.claude/hooks/hook-lib.sh"
for f in .claude/hooks/hook-lib.sh workflow.sh workflow.py codex-handoff.sh .claude/scripts/small-lib.sh; do
    [[ "$f" == .claude/hooks/hook-lib.sh ]] || printf '# local\n' >>"$KO/$f"
    mkdir -p "$SCRATCH/ko-old/$(dirname "$f")"
    cp "$KO/$f" "$SCRATCH/ko-old/$f"
done
for f in CLAUDE.md .claude/rules/00-project.md .claude/commands/kit/init.md docs/ADAPTATION.md; do
    printf 'local line\n' >>"$KO/$f"
done
rm "$KO/.claude/scripts/small-plan.sh"
printf 'mine\n' >"$KO/.claude/hooks/my-hook.sh"
KO_OUT="$("$ROOT/install.sh" "$KO" --no-ci 2>&1)"
KO_BK=("$KO"/.claude/kit-backup/*)
[ "${#KO_BK[@]}" -eq 1 ] && [[ -d "${KO_BK[0]}" ]]
grep -Fq ".claude/kit-backup/${KO_BK[0]##*/}" <<<"$KO_OUT"
for f in .claude/hooks/hook-lib.sh workflow.sh workflow.py codex-handoff.sh .claude/scripts/small-lib.sh; do
    cmp -s "$KO/$f" "$ROOT/$f"
    cmp -s "${KO_BK[0]}/$f" "$SCRATCH/ko-old/$f"
    [[ ! -e "$KO/$f.new" ]]
done
for f in CLAUDE.md .claude/rules/00-project.md .claude/commands/kit/init.md docs/ADAPTATION.md; do
    [[ -e "$KO/$f.new" ]]
done
grep -Fq 'Fusionne d'"'"'abord .claude/commands/kit/init.md.new' <<<"$KO_OUT"
[[ ! -e "$KO/.claude/settings.json.new" ]]
cmp -s "$KO/.claude/scripts/small-plan.sh" "$ROOT/.claude/scripts/small-plan.sh"
[[ ! -e "${KO_BK[0]}/.claude/scripts/small-plan.sh" ]]
grep -Fxq mine "$KO/.claude/hooks/my-hook.sh"
[[ ! -e "${KO_BK[0]}/.claude/hooks/my-hook.sh" ]]
# IN32 with --fastapi, the addon's tdd_py_lib.py too.
KF="$SCRATCH/kf"
mkdir -p "$KF"
"$ROOT/install.sh" "$KF" --fastapi --no-ci >/dev/null 2>&1
printf '# local\n' >>"$KF/.claude/hooks/tdd_py_lib.py"
cp "$KF/.claude/hooks/tdd_py_lib.py" "$SCRATCH/kf-old.py"
"$ROOT/install.sh" "$KF" --fastapi --no-ci >/dev/null 2>&1
cmp -s "$KF/.claude/hooks/tdd_py_lib.py" "$ROOT/addons/fastapi/hooks/tdd_py_lib.py"
KF_BK=("$KF"/.claude/kit-backup/*/.claude/hooks/tdd_py_lib.py)
[ "${#KF_BK[@]}" -eq 1 ] && cmp -s "${KF_BK[0]}" "$SCRATCH/kf-old.py"
# IN34 --react-ts writes its own stamp.
KR="$SCRATCH/kr"
mkdir -p "$KR"
"$ROOT/install.sh" "$KR" --react-ts --no-ci >/dev/null 2>&1
grep -Fxq react-ts "$KR/.claude/INSTALL_PROFILE"
# IN36 the kit dir itself, or a link to it, is refused before anything is written.
KC="$SCRATCH/kitcopy"
mkdir -p "$KC"
tar -C "$ROOT" --exclude=./.git --exclude=./node_modules -cf - . | tar -C "$KC" -xf -
rm -f "$KC/.claude/INSTALL_PROFILE"
ln -s "$KC" "$SCRATCH/kitlink"
for KC_TARGET in "$KC" "$SCRATCH/kitlink"; do
    KC_CODE=0
    KC_OUT="$("$KC/install.sh" "$KC_TARGET" --no-ci 2>&1)" || KC_CODE=$?
    [ "$KC_CODE" -eq 1 ]
    grep -Fq "$KC" <<<"$KC_OUT"
    [[ ! -e "$KC/.claude/INSTALL_PROFILE" ]]
    [ -z "$(find "$KC" -name '*.new' -print -quit)" ]
done
# IN37 guard hooks with an older cwk-guard-api: P1 is applied all the same, never held back.
KP="$SCRATCH/kp"
mkdir -p "$KP"
"$ROOT/install.sh" "$KP" --no-ci >/dev/null 2>&1
sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 1/' "$KP/.claude/hooks/enforce-git-workflow.sh" "$KP/.claude/hooks/hook-guarded.sh"
KP_OUT="$("$ROOT/install.sh" "$KP" --no-ci 2>&1)"
P1_EXPECTED='["Bash(git add *)", "Bash(git commit -m *)", "Bash(git switch -c *)",
              "Bash(git branch --show-current)", "Bash(git worktree list)"]'
jq -e --argjson p1 "$P1_EXPECTED" '.permissions.defaultMode == "acceptEdits"
    and ((.permissions.allow // []) as $a | $p1 | all(. as $x | $a | index($x)))' \
    "$KP/.claude/settings.json" >/dev/null
if grep -Fq 'P1 held back' <<<"$KP_OUT"; then exit 1; fi
# IN38 a v1 project.json is upgraded on re-install and keeps its app root.
mkdir -p "$KP/web"
printf '{"schema_version":1,"app_roots":["web"],"codegen_commands":[]}\n' >"$KP/.claude/project.json"
"$ROOT/install.sh" "$KP" --no-ci >/dev/null 2>&1
jq -e '.schema_version == 3 and .app_roots == ["web"]' "$KP/.claude/project.json" >/dev/null
# IN40 an upgrade from hooks that still hold the values, with no project.json: migrate reads
# them before the overwrite.
if git -C "$ROOT" cat-file -e ac3c9a4^:.claude/hooks/enforce-git-workflow.sh 2>/dev/null; then
    KV="$SCRATCH/kv"
    mkdir -p "$KV"
    git -C "$ROOT" archive ac3c9a4^ .claude | tar -x -C "$KV"
    rm -f "$KV/.claude/project.json"
    sed -i 's/^PROTECTED_BRANCHES=.*/PROTECTED_BRANCHES="main|develop"/' "$KV/.claude/hooks/enforce-git-workflow.sh"
    "$ROOT/install.sh" "$KV" --no-ci >/dev/null 2>&1
    jq -e '.protected_branches == ["main","develop"]' "$KV/.claude/project.json" >/dev/null
    cmp -s "$KV/.claude/hooks/enforce-git-workflow.sh" "$ROOT/.claude/hooks/enforce-git-workflow.sh"
fi

# IN27-IN29 (ship-audit-surface): v3 adds server_roots. A v2 file migrates with the roots its
# protected dirs imply; wiring an addon adds its roots, once.
v2_doc() { jq --argjson d "$1" 'del(.server_roots) | .schema_version = 2 | .protected_dirs = $d' "$ROOT/.claude/project.json"; }
IN27="$SCRATCH/in27"
mkdir -p "$IN27/.claude"
v2_doc '["src","shared",".claude"]' >"$IN27/.claude/project.json"
"${MIGRATE[@]}" "$IN27" >/dev/null 2>&1
jq -e '.schema_version == 3 and .server_roots == [] and (keys_unsorted | last) == "server_roots"' \
    "$IN27/.claude/project.json" >/dev/null
IN28="$SCRATCH/in28"
mkdir -p "$IN28/.claude"
v2_doc '["src","shared","app","alembic",".claude"]' >"$IN28/.claude/project.json"
"${MIGRATE[@]}" "$IN28" >/dev/null 2>&1
jq -e '.schema_version == 3 and .server_roots == ["app","alembic"]' "$IN28/.claude/project.json" >/dev/null
v2_doc '["src","shared","supabase",".claude"]' >"$IN28/.claude/project.json"
"${MIGRATE[@]}" "$IN28" >/dev/null 2>&1
jq -e '.schema_version == 3 and .server_roots == ["supabase"]' "$IN28/.claude/project.json" >/dev/null
IN29="$SCRATCH/in29"
mkdir -p "$IN29/.claude"
cp "$ROOT/.claude/project.json" "$IN29/.claude/project.json"
WIRE=(python3 -I -B "$ROOT/.claude/hooks/project_config.py" wire "$IN29")
"${WIRE[@]}" fastapi >/dev/null 2>&1
jq -e '.server_roots == ["app","alembic"]' "$IN29/.claude/project.json" >/dev/null
"${WIRE[@]}" supabase >/dev/null 2>&1
"${WIRE[@]}" fastapi >/dev/null 2>&1
jq -e '.server_roots == ["app","alembic","supabase"]' "$IN29/.claude/project.json" >/dev/null

# IN41 (review 1, F1, re-decided on kit-boundary): a target whose reader carries the previous api
# number is migrated by the kit's reader and gets the current one; nothing is held back.
IN41="$SCRATCH/in41"
mkdir -p "$IN41"
"$ROOT/install.sh" "$IN41" --no-ci >/dev/null 2>&1
sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 4/' "$IN41/.claude/hooks/project_config.py"
v2_doc '["src","shared","supabase",".claude"]' >"$IN41/.claude/project.json"
IN41_OUT="$("$ROOT/install.sh" "$IN41" --no-ci 2>&1)"
jq -e '.schema_version == 3 and .server_roots == ["supabase"]' "$IN41/.claude/project.json" >/dev/null
grep -q '^# cwk-guard-api: 5$' "$IN41/.claude/hooks/project_config.py"
if grep -Fq 'non migré' <<<"$IN41_OUT"; then echo 'IN41: install still says non migré' >&2; exit 1; fi

# IN42 (review 1, F5): a v1 file migrates with the server roots of the active hooks' protected dirs.
IN42="$SCRATCH/in42"
mkdir -p "$IN42/.claude/hooks"
printf '{"schema_version":1,"app_roots":[],"codegen_commands":[]}\n' >"$IN42/.claude/project.json"
printf 'PROTECTED_DIRS="src|shared|supabase|\\.claude"\n' >"$IN42/.claude/hooks/prevent-destructive-commands.sh"
"${MIGRATE[@]}" "$IN42" >/dev/null 2>&1
jq -e '.schema_version == 3 and .server_roots == ["supabase"]' "$IN42/.claude/project.json" >/dev/null

# IN43 (review 1, F5): the same from an absent file.
IN43="$SCRATCH/in43"
mkdir -p "$IN43/.claude/hooks"
printf 'PROTECTED_DIRS="src|shared|app|alembic|\\.claude"\n' >"$IN43/.claude/hooks/prevent-destructive-commands.sh"
"${MIGRATE[@]}" "$IN43" >/dev/null 2>&1
jq -e '.schema_version == 3 and .server_roots == ["app","alembic"]' "$IN43/.claude/project.json" >/dev/null

echo 'install fixtures: green.'
