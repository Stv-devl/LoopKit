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
python3 -I -B "$HOOKS_DIR/project_config.py" defaults \
    | jq '.data_client.module = "lib/api" | .data_client.own_path = "lib/api.ts"' > "$SCRATCH/.claude/project.json"
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
rm "$SCRATCH/.claude/project.json"

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

# PD1-PD7 (project-config step 1b): every value twin reads .claude/project.json, never hook text.
pd_json() {
    python3 -I -B "$HOOKS_DIR/project_config.py" defaults | jq "$1" > "$SCRATCH/.claude/project.json"
}
pd_run() {
    python3 "$SCRATCH/.claude/hooks/kit-doctor.py" "$@" || true
}
mkdir -p "$SCRATCH/.claude/rules" "$SCRATCH/.claude/agents" "$SCRATCH/.claude/commands/audit" \
    "$SCRATCH/.claude/skills/templates"
printf -- '- Recursive delete on: `src/`, `shared/`, `.claude/`, `public/`, `node_modules/`,\n  `dist/`\n\nend\n' \
    > "$SCRATCH/CLAUDE.md"
printf '| Where does the client live? | `src/lib/client.ts` |\n' > "$SCRATCH/.claude/rules/01-stack.md"
printf "TEST_FIRST = '{repository,services,mapper,utils}'\n" > "$SCRATCH/.claude/skills/templates/tooling-config.md"
printf 'src/**/*.{repository,services,mapper,utils}.ts\n' > "$SCRATCH/.claude/commands/audit/mutation.md"
printf '```bash\npnpm test:run\n```\n' > "$SCRATCH/.claude/rules/00-project.md"
printf 'they are not yours to interpret: a commit on `main`/`master` and a signed or\n' \
    > "$SCRATCH/.claude/agents/github.md"
jq -n '{permissions: {deny: ["Read(.env.*)"], allow: ["Read(!.env.example)", "Read(!.env.sample)",
    "Read(!.env.template)", "Read(!.env.*.example)", "Read(!.env.*.sample)", "Read(!.env.*.template)"]}}' \
    > "$SCRATCH/.claude/settings.json"
rm -f "$SCRATCH/.claude/hooks/enforce-architecture.py" "$SCRATCH/.claude/hooks/hook-lib.sh" \
    "$SCRATCH/.claude/hooks/prevent-destructive-commands.sh"

pd_json '.'
KD_OUT="$(pd_run)"
grep -q 'ok          protected-dirs' <<<"$KD_OUT"
grep -q 'ok          data-client' <<<"$KD_OUT"
grep -q 'ok          tdd-layers' <<<"$KD_OUT"
grep -q 'ok          env-suffixes' <<<"$KD_OUT"
grep -q 'DIVERGENCE  protected-branches' <<<"$KD_OUT" && exit 1

# PD1 protected_dirs plus frontend, not in CLAUDE.md.
pd_json '.protected_dirs += ["frontend"]'
grep -q 'DIVERGENCE  protected-dirs' <<<"$(pd_run)"
# PD2 data_client lib/api against an 01-stack.md naming src/lib/client.ts.
pd_json '.data_client.module = "lib/api" | .data_client.own_path = "lib/api.ts"'
grep -q 'DIVERGENCE  data-client' <<<"$(pd_run)"
# PD3 a usecase layer against the default tooling-config.
pd_json '.tdd_layers += ["usecase"]'
grep -q 'DIVERGENCE  tdd-layers' <<<"$(pd_run)"
# PD4 a different test command is INFO, never a divergence.
pd_json '.test_command = ["npm", "test"]'
KD_OUT="$(pd_run)"
grep -q 'INFO        test-command' <<<"$KD_OUT"
grep -q 'DIVERGENCE  test-command' <<<"$KD_OUT" && exit 1
# PD5 protected_branches ["main"]: diverges from `main`/`master`, agrees with `main`.
pd_json '.protected_branches = ["main"]'
grep -q 'DIVERGENCE  protected-branches' <<<"$(pd_run)"
printf 'they are not yours to interpret: a commit on `main` and a signed or\n' > "$SCRATCH/.claude/agents/github.md"
KD_OUT="$(pd_run)"
grep -q 'ok          protected-branches' <<<"$KD_OUT"
# PD6 `kit-doctor.py <root>` reads that root's file: an invalid one is reported, the twins are not checked.
mkdir -p "$SCRATCH/other/.claude"
printf '{"schema_version":2}\n' > "$SCRATCH/other/.claude/project.json"
KD_OUT="$(pd_run "$SCRATCH/other")"
grep -q 'DIVERGENCE  project-config' <<<"$KD_OUT"
grep -q 'not checked' <<<"$KD_OUT"
# PD7 env_template_suffixes ["example"] against the default settings.json Read entries.
pd_json '.env_template_suffixes = ["example"]'
grep -q 'DIVERGENCE  env-suffixes' <<<"$(pd_run)"
rm "$SCRATCH/.claude/project.json"

# KD10 A worktree under .claude/worktrees/ is another track's tree: its docs are not this
# kit's, so a path one of them names is never reported missing here.
mkdir -p "$SCRATCH/.claude/worktrees/other/.claude/rules"
printf 'See `.claude/hooks/kd10-absent.sh`.\n' > "$SCRATCH/.claude/worktrees/other/.claude/rules/x.md"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
if grep -q 'kd10-absent' <<<"$KD_OUT"; then echo 'KD10: a worktree doc was scanned' >&2; exit 1; fi
rm -r "$SCRATCH/.claude/worktrees"

# KD11 A tmp project with the stamp and no markers: mode "installed", no `stamp` divergence.
printf 'core\n' > "$SCRATCH/.claude/INSTALL_PROFILE"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'mode: installed project' <<<"$KD_OUT"
if grep -q 'DIVERGENCE  stamp' <<<"$KD_OUT"; then echo 'KD11: a stamped project reported' >&2; exit 1; fi
# KD12 A tmp project without the stamp and without the markers: `DIVERGENCE stamp`, naming install.sh.
rm "$SCRATCH/.claude/INSTALL_PROFILE"
KD_OUT="$(python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true)"
grep -q 'DIVERGENCE  stamp' <<<"$KD_OUT"
grep -A1 'DIVERGENCE  stamp' <<<"$KD_OUT" | grep -q 'install.sh'
# KD13 The kit repo with no stamp: mode "kit source", and no `stamp` row.
grep -q 'mode: kit source' <<<"$SOURCE_OUTPUT"
if grep -qE '^  [A-Za-z]+ +stamp ' <<<"$SOURCE_OUTPUT"; then echo 'KD13: the kit repo has a stamp row' >&2; exit 1; fi
# KD14 (ship-audit-surface) server-roots: 02-architecture.md's `Server roots:` line against
# project.json; a deleted Backend section is fine only with no root.
mkdir -p "$SCRATCH/.claude/rules"
KD_ARCH="$SCRATCH/.claude/rules/02-architecture.md"
kd_roots() {
    python3 -I -B "$HOOKS_DIR/project_config.py" defaults | jq --argjson r "$1" '.server_roots = $r' \
        > "$SCRATCH/.claude/project.json"
    python3 "$SCRATCH/.claude/hooks/kit-doctor.py" || true
}
printf '# Arch\n\n## Backend (fill or delete)\n\nNone.\nServer roots: none.\n\n## Router\n' > "$KD_ARCH"
grep -Eq 'ok +server-roots' <<<"$(kd_roots '[]')" || { echo 'KD11: none ↔ [] not ok' >&2; exit 1; }
printf '# Arch\n\n## Backend\n\nServer roots: `app`, `alembic`.\n\n## Router\n' > "$KD_ARCH"
grep -Eq 'ok +server-roots' <<<"$(kd_roots '["app","alembic"]')" || { echo 'KD11: app/alembic pair not ok' >&2; exit 1; }
grep -Eq 'DIVERGENCE +server-roots' <<<"$(kd_roots '["supabase"]')" || { echo 'KD11: drift not red' >&2; exit 1; }
printf '# Arch\n\n## Backend\n\nNone.\n\n## Router\n' > "$KD_ARCH"
grep -Eq 'MISSING +server-roots' <<<"$(kd_roots '[]')" || { echo 'KD11: missing line not red' >&2; exit 1; }
printf '# Arch\n\n## Router\n' > "$KD_ARCH"
grep -Eq 'ok +server-roots' <<<"$(kd_roots '[]')" || { echo 'KD11: deleted section with no root not ok' >&2; exit 1; }
grep -Eq 'MISSING +server-roots' <<<"$(kd_roots '["app"]')" || { echo 'KD11: deleted section with roots not red' >&2; exit 1; }
rm "$KD_ARCH" "$SCRATCH/.claude/project.json"

echo 'kit-doctor version fixtures: green.'
