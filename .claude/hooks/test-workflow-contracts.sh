#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEBUG="$ROOT/.claude/commands/loop/debug.md"
PLAN="$ROOT/.claude/commands/loop/plan.md"
CRITIC="$ROOT/.claude/agents/plan-critic.md"
PRODUCT="$ROOT/.claude/commands/loop/product.md"
ORCHESTRATE="$ROOT/.claude/commands/loop/orchestrate.md"
REVIEW="$ROOT/.claude/commands/loop/review.md"
SPIKE="$ROOT/.claude/commands/loop/spike.md"
RECIPE="$ROOT/.claude/commands/kit/recipe.md"

grep -Fq 'No fix is written or' "$DEBUG"
grep -Fq 'least two candidate causes' "$DEBUG"
grep -Fq 'LOOPKIT_DEBUG' "$DEBUG"
grep -Fq 'Pipeline` = `BUG`' "$DEBUG"

grep -Fq 'model: inherit' "$CRITIC"
grep -Fq 'completeness:' "$CRITIC"
grep -Fq 'quality:' "$CRITIC"
grep -Fq 'Never average' "$CRITIC"
grep -Fq 'PLAN CRITIC GATE' "$PLAN"
grep -Fq 'Critical/Major claim to a `verifier`' "$PLAN"

grep -Fq '`BUG` (a reproduced defect)' "$PRODUCT"
grep -Fq 'BLOCKED — <gate> failed 3x : <reason>' "$ORCHESTRATE"
grep -Fq 'never start a fourth attempt' "$ORCHESTRATE"

grep -Fq 'at most **3** items' "$REVIEW"
grep -Fq 'On `economy`, stay silent' "$REVIEW"
grep -Fq 'answer: indeterminate' "$SPIKE"
grep -Fq 'one search and two' "$SPIKE"
grep -Fq 'no board line' "$SPIKE"
grep -Fq 'exactly one citation' "$RECIPE"
grep -Fq 'automatic' "$RECIPE"

INTERFACE="$ROOT/.claude/commands/loop/interface.md"
DESIGNER="$ROOT/.claude/agents/designer.md"
skip_line=$(grep -nF 'Skip first' "$REVIEW" | head -1 | cut -d: -f1)
detect_line=$(grep -nF 'pnpm dlx impeccable detect' "$REVIEW" | head -1 | cut -d: -f1)
[ -n "$skip_line" ] && [ -n "$detect_line" ] && [ "$skip_line" -lt "$detect_line" ]
grep -Fq 'an Impeccable failure is a gap in the gate, never clean' "$REVIEW"
grep -Fq 'Impeccable findings bypass stage 2' "$REVIEW"
grep -Fq 'any exit other than 0 or 2 is a gap' "$REVIEW"
grep -Fq 'an exit 0 that scanned nothing is not' "$REVIEW"
grep -Fq '22.18' "$REVIEW"
if grep -Fq 'impeccable install' "$REVIEW"; then exit 1; fi
if grep -Fiq 'impeccable' "$ROOT/.claude/commands/loop/ship.md"; then exit 1; fi
grep -Fq 'Impeccable is never a ship gate' "$REVIEW"
grep -Fq 'Playwright stays the flow proof' "$REVIEW"
grep -Fq 'impeccable' "$DESIGNER"
grep -Fq 'frontend-design' "$DESIGNER"
grep -Fq 'Impeccable, loaded by `designer`' "$INTERFACE"
grep -Fq 'only on a UI feature' "$ORCHESTRATE"
grep -Fq 'only on a UI feature' "$PLAN"
[ "$(ls "$ROOT"/.claude/commands/loop/*.md | wc -l)" -eq 12 ]
for f in PRODUCT.md DESIGN.md; do
  [ "$(wc -l < "$ROOT/$f")" -le 10 ]
done
grep -Fq 'docs/product/brief.md' "$ROOT/PRODUCT.md"
grep -Fq 'docs/design-system.md' "$ROOT/DESIGN.md"
grep -Fq 'Impeccable' "$ROOT/docs/Claude_Workflows.md"
grep -Fq '22.18' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'impeccable init' "$ROOT/docs/ADAPTATION.md"

PATTERNS="$ROOT/.claude/skills/patterns"
MOTION="$PATTERNS/motion.md"
GSAP="$PATTERNS/gsap.md"
REVIEWER="$ROOT/.claude/agents/reviewer.md"
STACK="$ROOT/.claude/rules/01-stack.md"
SPEC="$ROOT/.claude/commands/loop/spec.md"
[ -f "$MOTION" ] && [ -f "$GSAP" ]
grep -Fq '../patterns/motion.md' "$ROOT/.claude/skills/project-rules/SKILL.md"
grep -Fq '../patterns/gsap.md' "$ROOT/.claude/skills/project-rules/SKILL.md"
grep -Fq 'Motion: gsap - <reason>' "$SPEC"
grep -Fq 'Motion: gsap' "$STACK"
grep -Fq 'Animation conformance' "$REVIEWER"
grep -Fq 'GSAP not requested by the spec or design.md is Major' "$REVIEWER"
grep -Fq 'both libraries in one component (Motion and GSAP) is Major' "$REVIEWER"
grep -Fq 'an animated feature without `prefers-reduced-motion` handling is Major' "$REVIEWER"
grep -Fq 'prefers-reduced-motion' "$REVIEWER"
grep -Fq 'Acceptance criteria for animated features' "$MOTION"
grep -Fq 'prefers-reduced-motion' "$MOTION"
grep -Fq 'prefers-reduced-motion' "$PATTERNS/a11y.md"
grep -Fq 'still animates opacity' "$MOTION"
grep -Fq 'Standard no charge' "$GSAP"
grep -Fq 'Webflow' "$GSAP"
grep -Fq 'dynamic import' "$GSAP"
grep -Fq 'never in the same component' "$GSAP"
[ "$(wc -l < "$STACK")" -le 45 ]
if grep -Fq 'patterns/motion' "$ROOT/CLAUDE.md"; then exit 1; fi
grep -Fq 'ne juge pas le mouvement' "$ROOT/docs/Claude_Workflows.md"
grep -Fq 'motifs de code connus' "$ROOT/docs/Claude_Workflows.md"
grep -Fq 'patterns/motion.md' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'motifs de code connus' "$ROOT/docs/ADAPTATION.md"
[ ! -e "$ROOT/package.json" ]
for f in "$MOTION" "$GSAP" "$STACK"; do
  if grep -Eq 'motion@|gsap@|[0-9]+\.[0-9]+\.[0-9]+' "$f"; then exit 1; fi
done

# workflow.py sets the session's model and effort unless the caller already did;
# `--critical` is the launcher's own flag and never reaches claude.
WF_SCRATCH="$(mktemp -d)"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/args"\n' "$WF_SCRATCH" > "$WF_SCRATCH/claude"
chmod +x "$WF_SCRATCH/claude"
cp "$ROOT/workflow.py" "$WF_SCRATCH/workflow.py"
wf_args() { CLAUDE_WORKFLOW_CLAUDE_BIN="$WF_SCRATCH/claude" python3 "$WF_SCRATCH/workflow.py" "$@" </dev/null >/dev/null 2>&1; tr '\n' ' ' < "$WF_SCRATCH/args"; }
[[ "$(wf_args)" == "--model opus --effort medium " ]]
[[ "$(wf_args --critical)" == "--model opus --effort high " ]]
[[ "$(wf_args --model sonnet -c)" == "--effort medium --model sonnet -c " ]]
[[ "$(wf_args --effort low)" == "--model opus --effort low " ]]
rm -r "$WF_SCRATCH"

# The supervisor and the Codex launcher run on a scratch project: a copy of both
# scripts, a git repo, fake `claude` and `codex` binaries. Nothing is written in
# this repo's docs/work, which the real supervisor reads.
WS="$(mktemp -d)"
trap 'rm -rf -- "$WS"' EXIT
mkdir -p "$WS/bin" "$WS/.claude"
cp "$ROOT/workflow.py" "$ROOT/codex-handoff.sh" "$WS/"
cp "$ROOT/.claude/workflow-routing.yml" "$WS/.claude/"
git -C "$WS" init -q
git -C "$WS" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base --date '2000-01-01T00:00:00'
GIT_COMMITTER_DATE='2000-01-01T00:00:00' git -C "$WS" -c user.email=t@t -c user.name=t commit -q --amend --allow-empty -m base --date '2000-01-01T00:00:00'
cat > "$WS/bin/codex" <<FAKE
#!/usr/bin/env bash
[[ "\$1" == --version ]] && exit 0
printf '%s\n' "\$*" >> "$WS/codex-calls"
FAKE
cat > "$WS/bin/claude" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WS/claude-calls"
[[ -e "$WS/say-limit" ]] && { echo "usage: 95%"; sleep 1; echo "usage limit reached"; touch "$WS/.claude/.restart-ready"; read -r -t 5 _ || true; exit 0; }
if [[ ! -e "$WS/saturated-once" || -e "$WS/always-saturate" ]]; then
    touch "$WS/saturated-once" "$WS/.claude/.restart-ready"
    read -r -t 5 _ || true
fi
exit 0
FAKE
chmod +x "$WS/bin/codex" "$WS/bin/claude"
reset_ws() { rm -rf -- "$WS/docs" "$WS/codex-calls" "$WS/claude-calls" "$WS/saturated-once" "$WS/always-saturate" "$WS/say-limit"; mkdir -p "$WS/docs/work/feat"; }
cx() { rm -f "$WS/codex-calls"; PATH="$WS/bin:$PATH" "$WS/codex-handoff.sh" "$@" </dev/null >/dev/null 2>&1; }
sup() { rm -f "$WS/claude-calls" "$WS/saturated-once"; PATH="$WS/bin:$PATH" CLAUDE_WORKFLOW_CLAUDE_BIN="$WS/bin/claude" python3 "$WS/workflow.py" </dev/null >/dev/null 2>&1; }
H="$WS/docs/work/feat/handoff.md"

# codex-handoff.sh: routed model, E16 (offline gates only), E17 (stale handoff).
reset_ws
printf '# plan\n' > "$WS/docs/work/feat/plan.md"; touch -d '1 hour ago' "$WS/docs/work/feat/plan.md"
printf -- '---\nphase: execute\ncodex_safe: yes   # yes only when every gate of this step runs offline\n---\n# Handoff\n' > "$H"
cx docs/work/feat/handoff.md execute-green
grep -q -- '-m gpt-5.6-terra' "$WS/codex-calls"
grep -q -- 'model_reasoning_effort=low' "$WS/codex-calls"
printf -- '---\nphase: execute\ncodex_safe: no\n---\n# Handoff\n' > "$H"
if cx docs/work/feat/handoff.md execute-green; then exit 1; fi
[[ ! -e "$WS/codex-calls" ]]
printf '# Handoff\ncodex_safe: yes\n' > "$H"
if cx docs/work/feat/handoff.md execute-green; then exit 1; fi
printf -- '---\nphase: execute\ncodex_safe: yes\n---\n# Handoff\n' > "$H"; touch -d '2 hours ago' "$H"
if cx docs/work/feat/handoff.md execute-green; then exit 1; fi
[[ ! -e "$WS/codex-calls" ]]
rm "$WS/docs/work/feat/plan.md"; touch -d '1999-12-31' "$H"
if cx docs/work/feat/handoff.md execute-green; then exit 1; fi

# A saturated context restarts Claude on the handoff, never Codex; the third
# saturation of one feature stops. A plan.md alone resumes at the plan gate.
reset_ws
printf '# plan\n' > "$WS/docs/work/feat/plan.md"
sup
[[ "$(wc -l < "$WS/claude-calls")" -eq 2 ]]
sed -n 2p "$WS/claude-calls" | grep -q -- '--model opus --effort medium /loop:orchestrate docs/work/feat/handoff.md'
grep -q '^phase: plan$' "$H"
grep -q '^restarts: 1$' "$H"
[[ ! -e "$WS/codex-calls" ]]
touch "$WS/always-saturate"
if sup; then exit 1; fi
grep -q '^restarts: 2$' "$H"
[[ "$(wc -l < "$WS/claude-calls")" -eq 2 ]]
printf -- '---\nphase: execute\nrestarts: two\n---\n# Handoff\n' > "$H"
if sup; then exit 1; fi
[[ "$(wc -l < "$WS/claude-calls")" -eq 1 ]]

# The newest feature wins over a shipped feature's leftover handoff.
reset_ws
mkdir -p "$WS/docs/work/old"
printf -- '---\nphase: ship\nrestarts: 0\n---\n# Old\n' > "$WS/docs/work/old/handoff.md"; touch -d '1 day ago' "$WS/docs/work/old/handoff.md"
printf '# research\n' > "$WS/docs/work/feat/research.md"
sup
sed -n 2p "$WS/claude-calls" | grep -q 'docs/work/feat/handoff.md'
grep -q '^restarts: 0$' "$WS/docs/work/old/handoff.md"

# The old name is still resumed for one version.
reset_ws
printf -- '---\nphase: review\n---\n# Old name\n' > "$WS/docs/work/feat/handoff-codex.md"
sup
sed -n 2p "$WS/claude-calls" | grep -q 'docs/work/feat/handoff-codex.md'

# A usage limit never restarts Claude, and a checkpoint refresh keeps the
# handoff's age, so a stale `codex_safe: yes` is still refused (E17 on relay).
reset_ws
printf '# plan\n' > "$WS/docs/work/feat/plan.md"; touch -d '1 hour ago' "$WS/docs/work/feat/plan.md"
printf -- '---\nphase: execute\ncodex_safe: yes\n---\n# Handoff\n' > "$H"; touch -d '2 hours ago' "$H"
touch "$WS/say-limit"
sup || true
[[ "$(wc -l < "$WS/claude-calls")" -eq 1 ]]
[[ ! -e "$WS/codex-calls" ]]
grep -q '^restarts: 0$' "$H"
[[ "$(stat -c %Y "$H")" -lt "$(stat -c %Y "$WS/docs/work/feat/plan.md")" ]]

# Phase 0 resumes a handoff on every phase the template can write.
for phase in research interface plan execute review ship; do
    grep -q "\`$phase\` → Phase" "$ROOT/.claude/commands/loop/orchestrate.md"
done
grep -q 'handoff-codex.md`, its name before 0.2' "$ROOT/.claude/commands/loop/orchestrate.md"
TEMPLATE_PHASES="$(sed -nE 's/^phase: [a-z-]+ +# (.*)$/\1/p' "$ROOT/.claude/commands/handoff/codex.md")"
[[ "$TEMPLATE_PHASES" == "research | interface | plan | execute | review | ship" ]]

echo 'workflow contract fixtures: green.'
