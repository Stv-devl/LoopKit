#!/usr/bin/env bash
set -euo pipefail
# No `gh` call from the suite unless a case puts its shim first on PATH.
export CWK_DOCTOR_OFFLINE=1

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_OUTPUT="$(python3 "$HOOKS_DIR/kit-doctor.py")"
grep -q 'version: 0.1.0 (tag: unknown)' <<<"$SOURCE_OUTPUT"

SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/.claude/hooks"
cp "$HOOKS_DIR/kit-doctor.py" "$SCRATCH/.claude/hooks/kit-doctor.py"
cp "$HOOKS_DIR/project_config.py" "$SCRATCH/.claude/hooks/project_config.py"
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

mkdir -p "$SCRATCH/.claude/agents"
printf '| Tier | For | Effort | Agents |\n| --- | --- | --- | --- |\n| `inherit` | gates | set at the call | `reviewer` |\n| `sonnet` | tests | `high` | `test-writer` |\n| `sonnet` | production | `medium` | `github` |\n' \
    > "$SCRATCH/.claude/rules/11-token-budget.md"
printf -- '---\nname: reviewer\nmodel: inherit\n---\n' > "$SCRATCH/.claude/agents/reviewer.md"
printf -- '---\nname: test-writer\nmodel: sonnet\neffort: high\n---\n' > "$SCRATCH/.claude/agents/test-writer.md"
printf -- '---\nname: github\nmodel: sonnet\neffort: high\n---\n' > "$SCRATCH/.claude/agents/github.md"
EFFORT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  agent-efforts' <<<"$EFFORT_OUTPUT"
grep -q 'github' <<<"$(grep -A3 'agent-efforts' <<<"$EFFORT_OUTPUT")"
grep -q 'ok          agent-models' <<<"$EFFORT_OUTPUT"
printf -- '---\nname: github\nmodel: sonnet\neffort: medium\n---\n' > "$SCRATCH/.claude/agents/github.md"
printf -- '---\nname: reviewer\nmodel: inherit\neffort: low\n---\n' > "$SCRATCH/.claude/agents/reviewer.md"
EFFORT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'reviewer' <<<"$(grep -A3 'agent-efforts' <<<"$EFFORT_OUTPUT")"
printf -- '---\nname: reviewer\nmodel: inherit\n---\n' > "$SCRATCH/.claude/agents/reviewer.md"
EFFORT_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'ok          agent-efforts' <<<"$EFFORT_OUTPUT"
rm -r "$SCRATCH/.claude/agents" "$SCRATCH/.claude/rules/11-token-budget.md"

printf 'Fork `.claude/worktrees/small-<name>`, list `.claude/worktrees/small-*`, read `.claude/nonexistent-x.md`.\n' \
    > "$SCRATCH/.claude/commands/loop/small-probe.md"
SHIPPED_OUTPUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q '\.claude/nonexistent-x\.md' <<<"$SHIPPED_OUTPUT"
if grep -q '\.claude/worktrees/small' <<<"$SHIPPED_OUTPUT"; then exit 1; fi
rm "$SCRATCH/.claude/commands/loop/small-probe.md"

# KD harness-kit-ci: github-protection, informational only, through a gh shim
# driven by GH_SHIM_RULES / GH_SHIM_PROT / GH_SHIM_AUTH / GH_SHIM_HANG, every
# call logged to $GH_SHIM_LOG.
GH_WS="$SCRATCH/ghws"
mkdir -p "$GH_WS/bin" "$GH_WS/nogh"
cat > "$GH_WS/bin/gh" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_SHIM_LOG"
case "$1" in
    auth) exit "${GH_SHIM_AUTH:-0}" ;;
    api)
        [ "${GH_SHIM_HANG:-0}" = 1 ] && exec sleep 30
        case "$*" in
            *rules/branches*) printf '%s' "${GH_SHIM_RULES:-[]}"; exit 0 ;;
            *protection*)
                printf 'HTTP/2.0 %s X\n\n{}\n' "${GH_SHIM_PROT:-404}"
                [ "${GH_SHIM_PROT:-404}" = 200 ] && exit 0
                exit 1 ;;
        esac ;;
esac
exit 1
SHIM
chmod +x "$GH_WS/bin/gh"
ln -s "$(python3 -I -c 'import sys; print(sys.executable)')" "$GH_WS/nogh/python3"
ln -s "$(command -v git)" "$GH_WS/nogh/git"
export GH_SHIM_LOG="$GH_WS/gh.log"
# kd_run <env assignments...>: the doctor on the scratch kit, online, shim first.
kd_run() {
    : > "$GH_SHIM_LOG"
    env -u CWK_DOCTOR_OFFLINE PATH="$GH_WS/bin:$PATH" "$@" \
        python3 "$SCRATCH/.claude/hooks/kit-doctor.py"
}
# KD1 a ruleset applies to main → nothing.
KD_OUT="$(kd_run GH_SHIM_RULES='[{"type":"deletion"}]' || true)"
if grep -q 'github-protection' <<<"$KD_OUT"; then exit 1; fi
grep -q 'rules/branches/main' "$GH_SHIM_LOG"
# KD2 no ruleset, classic protection present (200) → nothing.
set +e; KD_OUT="$(kd_run GH_SHIM_RULES='[]' GH_SHIM_PROT=200)"; KD2_CODE=$?; set -e
if grep -q 'github-protection' <<<"$KD_OUT"; then exit 1; fi
# KD3 neither (404) → one INFO line, exit code unchanged.
set +e; KD_OUT="$(kd_run GH_SHIM_RULES='[]' GH_SHIM_PROT=404)"; KD3_CODE=$?; set -e
[ "$(grep -c 'INFO        github-protection' <<<"$KD_OUT")" -eq 1 ]
grep -q 'main has no ruleset and no classic protection' <<<"$KD_OUT"
[ "$KD3_CODE" -eq "$KD2_CODE" ]
# KD3b the INFO line never counts as a divergence: same count line with and without it.
KD3B_WITHOUT="$(kd_run GH_SHIM_RULES='[]' GH_SHIM_PROT=200 || true)"
KD3B_WITH="$(kd_run GH_SHIM_RULES='[]' GH_SHIM_PROT=404 || true)"
grep -q 'INFO        github-protection' <<<"$KD3B_WITH"
KD3B_COUNT="$(grep -E '^[0-9]+ divergence\(s\)' <<<"$KD3B_WITHOUT")"
[ "$(grep -E '^[0-9]+ divergence\(s\)' <<<"$KD3B_WITH")" == "$KD3B_COUNT" ]
# KD4 protection not readable (403) → one INFO line naming it.
KD_OUT="$(kd_run GH_SHIM_RULES='[]' GH_SHIM_PROT=403 || true)"
[ "$(grep -c 'INFO        github-protection' <<<"$KD_OUT")" -eq 1 ]
grep -q 'not readable' <<<"$KD_OUT"
# KD5 no gh on PATH → nothing.
KD_OUT="$(env -u CWK_DOCTOR_OFFLINE PATH="$GH_WS/nogh" python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
if grep -q 'github-protection' <<<"$KD_OUT"; then exit 1; fi
# KD5b that run reached the wiring section: a doctor that never started proves nothing.
grep -qx 'WIRING' <<<"$KD_OUT"
# KD6 gh not authenticated → nothing, and no api call.
KD_OUT="$(kd_run GH_SHIM_AUTH=1 GH_SHIM_PROT=404 || true)"
if grep -q 'github-protection' <<<"$KD_OUT"; then exit 1; fi
if grep -q '^api' "$GH_SHIM_LOG"; then exit 1; fi
# KD7 gh hangs → nothing, and the doctor returns within 12 s.
KD_START="$(date +%s)"
KD_OUT="$(kd_run GH_SHIM_HANG=1 || true)"
[ $(( $(date +%s) - KD_START )) -le 12 ]
if grep -q 'github-protection' <<<"$KD_OUT"; then exit 1; fi
# KD8 offline → nothing, and no gh call at all.
: > "$GH_SHIM_LOG"
KD_OUT="$(PATH="$GH_WS/bin:$PATH" CWK_DOCTOR_OFFLINE=1 GH_SHIM_RULES='[]' GH_SHIM_PROT=404 \
    python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
if grep -q 'github-protection' <<<"$KD_OUT"; then exit 1; fi
[ ! -s "$GH_SHIM_LOG" ]
# KD9 an unfilled CODEOWNERS owner is a placeholder, in the kit template and on a target.
mkdir -p "$SCRATCH/.github"
printf '%s\n' '# FILL: replace @OWNER' '/.claude/hooks/ @OWNER' > "$SCRATCH/templates/github/CODEOWNERS"
cp "$SCRATCH/templates/github/CODEOWNERS" "$SCRATCH/.github/CODEOWNERS"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -Eq '(^|[[:space:]])templates/github/CODEOWNERS[[:space:]]+\(1\)' <<<"$KD_OUT"
grep -Eq '(^|[[:space:]])\.github/CODEOWNERS[[:space:]]+\(1\)' <<<"$KD_OUT"

# KD1-KD4 (app-roots-codegen): .claude/project.json is checked through the one reader.
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'ok          project-config' <<<"$KD_OUT"
printf '{"schema_version":1,"app_roots":[],"codegen_commands":[],"extra":1}\n' > "$SCRATCH/.claude/project.json"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  project-config' <<<"$KD_OUT"
grep -q 'extra' <<<"$KD_OUT"
printf '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[]}\n' > "$SCRATCH/.claude/project.json"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  project-config' <<<"$KD_OUT"
grep -q 'frontend' <<<"$KD_OUT"
mkdir -p "$SCRATCH/frontend"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'ok          project-config' <<<"$KD_OUT"
rm "$SCRATCH/.claude/project.json"

echo 'kit-doctor version fixtures: green.'
