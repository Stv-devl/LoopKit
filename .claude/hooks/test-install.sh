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
for ignored in .claude/.kit-health.jsonl .claude/settings.local.json __pycache__/ .ruff_cache/; do
    grep -qxF "$ignored" "$PY_TARGET/.gitignore"
done
sed -i '/^\.claude\/\.kit-health\.jsonl$/d; /^\.ruff_cache\/$/d' "$PY_TARGET/.gitignore"
"$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci >/dev/null 2>&1
for ignored in .claude/.kit-health.jsonl .ruff_cache/; do
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

# (a) a guard hook without the api line holds P1 back, and says which one.
HB="$SCRATCH/hold-a"
p1_fresh "$HB"
sed -i '/^# cwk-guard-api:/d' "$HB/.claude/hooks/enforce-git-workflow.sh"
p1_strip "$HB"
HB_OUT="$(p1_rerun "$HB")"
p1_absent "$HB"
grep -Fq 'P1 held back: .claude/hooks/enforce-git-workflow.sh' <<<"$HB_OUT"
# (a, A0) the held-back message names the .new copy to merge.
grep -Fq 'merge .claude/hooks/enforce-git-workflow.sh.new' <<<"$HB_OUT"
# (a, A0) the pnpm gate wildcards go too, the bare forms and pnpm audit * stay.
gates_wild_none() {
    jq -e '[.permissions.allow[]? | select(IN("Bash(pnpm build *)", "Bash(pnpm test:run *)",
            "Bash(pnpm test:coverage *)", "Bash(pnpm lint *)", "Bash(pnpm typecheck *)"))] | length == 0' \
        "$1/.claude/settings.json" >/dev/null
}
gates_wild_all() {
    jq -e '[.permissions.allow[]? | select(IN("Bash(pnpm build *)", "Bash(pnpm test:run *)",
            "Bash(pnpm test:coverage *)", "Bash(pnpm lint *)", "Bash(pnpm typecheck *)"))] | length == 5' \
        "$1/.claude/settings.json" >/dev/null
}
gates_wild_none "$HB"
jq -e '.permissions.allow | index("Bash(pnpm build)") and index("Bash(pnpm audit *)")' \
    "$HB/.claude/settings.json" >/dev/null
# (a, A0) the held-back settings still satisfy the doctor's gate allowlist.
python3 "$HB/.claude/hooks/kit-doctor.py" | grep -q 'ok          gate-allowlist'
# (b) its .new copies merged in, the re-run adds P1.
while IFS= read -r new; do mv "$new" "${new%.new}"; done < <(find "$HB" -name '*.new')
HB_OUT="$(p1_rerun "$HB")"
p1_present "$HB"
gates_wild_all "$HB"
if grep -Fq 'P1 held back' <<<"$HB_OUT"; then exit 1; fi

# (A0) tdd-require-red.sh and auto-approve-config.sh are guard files: without
# their api line P1 and the gate wildcards are held back, merged they come back.
for guard in tdd-require-red.sh auto-approve-config.sh; do
    HA0="$SCRATCH/hold-a0-$guard"
    p1_fresh "$HA0"
    sed -i '/^# cwk-guard-api:/d' "$HA0/.claude/hooks/$guard"
    HA0_OUT="$(p1_rerun "$HA0")"
    p1_absent "$HA0"
    gates_wild_none "$HA0"
    grep -Fq "P1 held back: .claude/hooks/$guard" <<<"$HA0_OUT"
    while IFS= read -r new; do mv "$new" "${new%.new}"; done < <(find "$HA0" -name '*.new')
    p1_rerun "$HA0" >/dev/null
    p1_present "$HA0"
    gates_wild_all "$HA0"
done

# (A2) enforce-git-workflow.sh left at its previous api, 1, is held back.
HA2="$SCRATCH/hold-a2"
p1_fresh "$HA2"
sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 1/' "$HA2/.claude/hooks/enforce-git-workflow.sh"
HA2_OUT="$(p1_rerun "$HA2")"
p1_absent "$HA2"
gates_wild_none "$HA2"
grep -Fq 'P1 held back: .claude/hooks/enforce-git-workflow.sh' <<<"$HA2_OUT"

# (A3) hook-guarded.sh left at its previous api, 1, is held back.
HA3="$SCRATCH/hold-a3"
p1_fresh "$HA3"
sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 1/' "$HA3/.claude/hooks/hook-guarded.sh"
HA3_OUT="$(p1_rerun "$HA3")"
p1_absent "$HA3"
gates_wild_none "$HA3"
grep -Fq 'P1 held back: .claude/hooks/hook-guarded.sh' <<<"$HA3_OUT"

# (A4) shell_targets.py, prevent-destructive-commands.sh and hook-lib.sh left at
# their previous api, 1, are held back.
for guard in shell_targets.py prevent-destructive-commands.sh hook-lib.sh; do
    HA4="$SCRATCH/hold-a4-$guard"
    p1_fresh "$HA4"
    sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 1/' "$HA4/.claude/hooks/$guard"
    HA4_OUT="$(p1_rerun "$HA4")"
    p1_absent "$HA4"
    gates_wild_none "$HA4"
    grep -Fq "P1 held back: .claude/hooks/$guard" <<<"$HA4_OUT"
done

# (A7) protect-files.sh left at its previous api, 1, is held back.
HA7="$SCRATCH/hold-a7"
p1_fresh "$HA7"
sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 1/' "$HA7/.claude/hooks/protect-files.sh"
HA7_OUT="$(p1_rerun "$HA7")"
p1_absent "$HA7"
gates_wild_none "$HA7"
grep -Fq 'P1 held back: .claude/hooks/protect-files.sh' <<<"$HA7_OUT"

# (c) a fresh install carries P1 and keeps it on a re-run.
HC="$SCRATCH/hold-c"
p1_fresh "$HC"
p1_present "$HC"
p1_rerun "$HC" >/dev/null
p1_present "$HC"

# (d) a target's own edits never hold P1 back, and survive.
HD="$SCRATCH/hold-d"
p1_fresh "$HD"
sed -i 's/^PROTECTED_DIRS="src|shared/PROTECTED_DIRS="src|shared|docs/' "$HD/.claude/hooks/prevent-destructive-commands.sh"
sed -i 's/^PROTECTED_BRANCHES="main|master"/PROTECTED_BRANCHES="main|master|release"/' "$HD/.claude/hooks/enforce-git-workflow.sh"
p1_strip "$HD"
HD_OUT="$(p1_rerun "$HD")"
p1_present "$HD"
if grep -Fq 'P1 held back' <<<"$HD_OUT"; then exit 1; fi
grep -q '^PROTECTED_DIRS="src|shared|docs' "$HD/.claude/hooks/prevent-destructive-commands.sh"
grep -q '^PROTECTED_BRANCHES="main|master|release"' "$HD/.claude/hooks/enforce-git-workflow.sh"
PY_OUT="$("$ROOT/install.sh" "$PY_TARGET" --fastapi --no-ci 2>&1)"
if grep -Fq 'P1 held back' <<<"$PY_OUT"; then exit 1; fi

# (e) held back over a target's own mode and allows: both kept untouched.
HE="$SCRATCH/hold-e"
p1_fresh "$HE"
sed -i '/^# cwk-guard-api:/d' "$HE/.claude/hooks/enforce-git-workflow.sh"
jq '.permissions.defaultMode = "default" | .permissions.allow = (.permissions.allow - ["Bash(git add *)"] + ["Bash(make *)"])' \
    "$HE/.claude/settings.json" >"$SCRATCH/own.json"
cp "$SCRATCH/own.json" "$HE/.claude/settings.json"
p1_rerun "$HE" >/dev/null
jq -e '.permissions.defaultMode == "default" and (.permissions.allow | index("Bash(make *)"))
       and (.permissions.allow | index("Bash(git add *)") | not)' "$HE/.claude/settings.json" >/dev/null

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
HGH="$SCRATCH/deny-held"
p1_fresh "$HGH"
sed -i '/^# cwk-guard-api:/d' "$HGH/.claude/hooks/enforce-git-workflow.sh"
grep -Fq 'P1 held back' <<<"$(p1_rerun "$HGH")"
jq -e --argjson kit "$KIT_DENY" '.permissions.deny == $kit' "$HGH/.claude/settings.json" >/dev/null

# (f) hook-lib.sh that no longer sources hook-guarded.sh holds P1 back.
HF="$SCRATCH/hold-f"
p1_fresh "$HF"
sed -i 's/source \(.*\)hook-guarded\.sh/source \1hook-other.sh/' "$HF/.claude/hooks/hook-lib.sh"
p1_strip "$HF"
HF_OUT="$(p1_rerun "$HF")"
p1_absent "$HF"
grep -Fq 'P1 held back: .claude/hooks/hook-lib.sh' <<<"$HF_OUT"

# (g) a deleted guard file is restored by the copy before the settings merge.
HG="$SCRATCH/hold-g"
p1_fresh "$HG"
rm "$HG/.claude/hooks/shell_targets.py"
p1_strip "$HG"
HG_OUT="$(p1_rerun "$HG")"
[[ -f "$HG/.claude/hooks/shell_targets.py" ]]
p1_present "$HG"
if grep -Fq 'P1 held back' <<<"$HG_OUT"; then exit 1; fi

# (h) an api number lower than the kit's holds P1 back.
HH="$SCRATCH/hold-h"
p1_fresh "$HH"
sed -i 's/^# cwk-guard-api: .*/# cwk-guard-api: 0/' "$HH/.claude/hooks/protect-files.sh"
p1_strip "$HH"
HH_OUT="$(p1_rerun "$HH")"
p1_absent "$HH"
grep -Fq 'P1 held back: .claude/hooks/protect-files.sh' <<<"$HH_OUT"

# I3 hold-back removes a P1 the target already holds: the five kit allows and an
# acceptEdits mode go, everything else the target has stays.
P1_KIT="$(sed -n "/^P1_ALLOWS='/,/]'\$/p" "$ROOT/install.sh" | sed "s/^P1_ALLOWS='//; s/'\$//")"
jq -e 'length == 5' <<<"$P1_KIT" >/dev/null
p1_none() {
    jq -e --argjson p1 "$P1_KIT" \
        '(.permissions.defaultMode != "acceptEdits") and ([.permissions.allow[]? | select(IN($p1[]))] | length == 0)' \
        "$1/.claude/settings.json" >/dev/null
}
p1_all() {
    jq -e --argjson p1 "$P1_KIT" \
        '(.permissions.defaultMode == "acceptEdits") and ([.permissions.allow[]? | select(IN($p1[]))] | length == ($p1 | length))' \
        "$1/.claude/settings.json" >/dev/null
}
p1_add_allow() {
    jq --arg a "$2" '.permissions.allow += [$a]' "$1/.claude/settings.json" >"$SCRATCH/allow.json"
    cp "$SCRATCH/allow.json" "$1/.claude/settings.json"
}

# (I3a) reproduction: P1 present from an earlier install, then a guard falls behind.
H3A="$SCRATCH/hold-3a"
p1_fresh "$H3A"
p1_all "$H3A"
p1_add_allow "$H3A" 'Bash(make *)'
sed -i '/^# cwk-guard-api:/d' "$H3A/.claude/hooks/enforce-git-workflow.sh"
H3A_OUT="$(p1_rerun "$H3A")"
p1_none "$H3A"
jq -e '.permissions.allow | index("Bash(make *)")' "$H3A/.claude/settings.json" >/dev/null
grep -Fq 'P1 held back: .claude/hooks/enforce-git-workflow.sh' <<<"$H3A_OUT"

# (I3b) a mode the user chose is not the kit's: kept, only the allows go.
H3B="$SCRATCH/hold-3b"
p1_fresh "$H3B"
jq '.permissions.defaultMode = "plan"' "$H3B/.claude/settings.json" >"$SCRATCH/mode.json"
cp "$SCRATCH/mode.json" "$H3B/.claude/settings.json"
sed -i '/^# cwk-guard-api:/d' "$H3B/.claude/hooks/enforce-git-workflow.sh"
p1_rerun "$H3B" >/dev/null
jq -e '.permissions.defaultMode == "plan"' "$H3B/.claude/settings.json" >/dev/null
p1_none "$H3B"

# (I3c) the .new copies merged in, the re-run gives all of P1 back.
while IFS= read -r new; do mv "$new" "${new%.new}"; done < <(find "$H3A" -name '*.new')
p1_rerun "$H3A" >/dev/null
p1_all "$H3A"

# (I3d) no settings yet over held hooks: the fresh copy carries none of the five.
H3D="$SCRATCH/hold-3d"
p1_fresh "$H3D"
rm "$H3D/.claude/settings.json"
sed -i '/^# cwk-guard-api:/d' "$H3D/.claude/hooks/enforce-git-workflow.sh"
p1_rerun "$H3D" >/dev/null
p1_none "$H3D"

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

echo 'install fixtures: green.'
