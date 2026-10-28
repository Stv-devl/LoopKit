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
REVIEWER="$ROOT/.claude/guides/review/ui.md"
grep -Fq '.claude/guides/review/ui.md' "$ROOT/.claude/agents/reviewer.md"
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

# After /clear, the SessionStart hook names the next feature: an interrupted one
# first (IN LOOP with a handoff), else the topmost READY line. Only on `clear`.
NX="$WS/next"
rm -rf -- "$NX"; mkdir -p "$NX/docs/product" "$NX/docs/work/checkout-1.1"
next_ctx() { printf '{"hook_event_name":"SessionStart","source":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$NX" python3 "$ROOT/.claude/hooks/next-feature-on-clear.py"; }
cat > "$NX/docs/product/backlog.md" <<'BOARD'
| Feature / story | Entry artifact | Pipeline | State | Shipped |
| --- | --- | --- | --- | --- |
| auth | docs/specs/auth.md | light | SHIPPED | 2026-10-01 |
| billing | docs/specs/billing.md | light | READY | — |
| checkout 1.2 — payment | docs/stories/checkout/1.2.md | full | READY | — |
BOARD
next_ctx clear | grep -q '/loop:orchestrate docs/specs/billing.md'
if next_ctx clear | grep -q 'checkout/1.2'; then exit 1; fi
next_ctx clear | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="SessionStart"'
[[ -z "$(next_ctx startup)" ]]
[[ -z "$(next_ctx resume)" ]]
printf '| checkout 1.1 — cart | docs/stories/checkout/1.1.md | full | IN LOOP | — |\n' >> "$NX/docs/product/backlog.md"
printf -- '---\nphase: review\n---\n' > "$NX/docs/work/checkout-1.1/handoff.md"
next_ctx clear | grep -q '/loop:orchestrate docs/work/checkout-1.1/handoff.md'
sed -i 's/| READY |/| SHIPPED |/; s/| IN LOOP |/| SHIPPED |/' "$NX/docs/product/backlog.md"
sed -i 's/| READY |/| SHIPPED |/' "$NX/docs/product/backlog.md"
next_ctx clear | grep -q 'No READY line'
rm "$NX/docs/product/backlog.md"
next_ctx clear | grep -q 'No board'
# Escaped pipes, an indented board, backticked paths, a stuck IN LOOP line,
# bytes that are not UTF-8 and a non-object payload never derail the hook.
printf '  | Feature / story | Entry artifact | Pipeline | State | Shipped |\n  | --- | --- | --- | --- | --- |\n  | a \\| b | `docs/specs/ab.md` | light | READY | — |\n  | c | docs/specs/c.md | light | READY | — |\n' > "$NX/docs/product/backlog.md"
next_ctx clear | grep -q '/loop:orchestrate docs/specs/ab.md'
printf '| Feature / story | Entry artifact | Pipeline | State | Shipped |\n| --- | --- | --- | --- | --- |\n| cart | docs/stories/shop/1.1.md | full | IN LOOP | — |\n| c | docs/specs/c.md | light | READY | — |\n' > "$NX/docs/product/backlog.md"
next_ctx clear | grep -q 'cart'
next_ctx clear | grep -q '/loop:orchestrate docs/specs/c.md'
mkdir -p "$NX/.claude/worktrees/shop-1.1"
if next_ctx clear | grep -q 'cart'; then exit 1; fi
next_ctx clear | grep -q '/loop:orchestrate docs/specs/c.md'
rm -r "$NX/.claude/worktrees"
printf '| Feature / story | Entry artifact | Pipeline | State | Shipped |\n| --- | --- | --- | --- | --- |\n| caf\xe9 | docs/specs/cafe.md | light | READY | — |\n' > "$NX/docs/product/backlog.md"
next_ctx clear | grep -q 'docs/specs/cafe.md'
[[ -z "$(printf '[]' | CLAUDE_PROJECT_DIR="$NX" python3 "$ROOT/.claude/hooks/next-feature-on-clear.py")" ]]

# Work that had no attributed agent (1.8): implementer, test-writer after the
# code, e2e repair, migrations on Opus.
grep -Fq 'name: implementer' "$ROOT/.claude/agents/implementer.md"
grep -Fq '.token-delegate' "$ROOT/.claude/commands/loop/orchestrate.md"
grep -Fq '`implementer`' "$ROOT/.claude/commands/loop/orchestrate.md"
grep -Fq 'after the code' "$ROOT/.claude/agents/test-writer.md"
grep -Fq 'after the code' "$ROOT/.claude/commands/loop/orchestrate.md"
grep -Fq 'repair' "$ROOT/.claude/agents/e2e-tester.md"
grep -Fxq 'model: opus' "$ROOT/.claude/commands/database/migration.md"

# The 70 % delegate marker: written at 70, removed below it.
SL="$WS/sl"; mkdir -p "$SL/.claude"
sl() { printf '{"context_window":{"used_percentage":%s},"workspace":{"project_dir":"%s"}}' "$1" "$SL" | python3 "$ROOT/.claude/hooks/token-statusline.py" >/dev/null; }
sl 69.9; [[ ! -e "$SL/.claude/.token-delegate" ]]
sl 70; [[ -e "$SL/.claude/.token-delegate" ]]
sl 40; [[ ! -e "$SL/.claude/.token-delegate" ]]

# Light loop with one stop fewer (docs/specs/light-fewer-gates.md): the spec
# chains into the loop, the contract is asked at the first gate, the go is
# recorded, case ids, frozen-test corrections confirmed at the merge.
# A section whose end anchor is missing fails instead of reading to the end of
# the file; a section is always assigned first so `set -e` sees that failure.
section() { awk -v s="$2" -v e="$3" '!on && index($0, s) { on = 1; print; next } on && index($0, e) { ended = 1; exit } on; END { exit !ended }' "$1"; }
TESTS_GUIDE="$ROOT/.claude/guides/review/tests.md"
TEST_WRITER="$ROOT/.claude/agents/test-writer.md"
SHIP="$ROOT/.claude/commands/loop/ship.md"
PY_FREEZE="$ROOT/addons/fastapi/hooks/tdd-freeze-tests-py.py"
if section "$PLAN" '7. **TEST PLAN GATE' 'no such end anchor' >/dev/null; then exit 1; fi
if grep -Fq 'Once the spec is written, stop and propose' "$SPEC"; then exit 1; fi
if grep -Fq 'Frame the contract, stop.' "$SPEC"; then exit 1; fi
grep -Fq 'you will validate the contract with research in hand at the first gate' "$SPEC"
grep -Fq '.token-warning' "$SPEC"
grep -Fq './workflow.sh "/loop:orchestrate docs/specs/<slug>.md"' "$SPEC"
gate_ui="$(section "$INTERFACE" '5. **INTERFACE GATE' '6. **Write**')"
grep -Fq 'Contract (validated by this go)' <<<"$gate_ui"
grep -Fq 'first round only' <<<"$gate_ui"
grep -Fq 'write `design.md` (step 6) first' <<<"$gate_ui"
design_gate="$(section "$INTERFACE" '## Chosen at the gate' '## Rejected')"
grep -Fq 'Contract: as written' <<<"$design_gate"
gate_plan="$(section "$PLAN" '7. **TEST PLAN GATE' '8. **Stop')"
grep -Fq 'amended:' <<<"$gate_plan"
grep -Fq 'proposed answer' <<<"$gate_plan"
grep -Fq '## Gate' <<<"$gate_plan"
grep -Fq 'asks step 7 again' <<<"$gate_plan"
grep -Fq '`research.md` is read-only' <<<"$gate_plan"
template_plan="$(section "$PLAN" '## Test plan (gate' '### Test-after')"
grep -Fq -- '- [ ] U1' <<<"$template_plan"
grep -Fq 'next free id' <<<"$template_plan"
resume="$(section "$ORCHESTRATE" '## Phase 0 —' '## Phase 0.5 —')"
grep -Fq '`## Gate` present' <<<"$resume"
grep -Fq 'surviving blockers: none' <<<"$resume"
phase3="$(section "$ORCHESTRATE" '## Phase 3 —' '## Phase 4 —')"
grep -Fq 'Do not enter Phase 4 on silence' <<<"$phase3"
grep -Fq 're-enters at the earliest phase' <<<"$phase3"
grep -Fq 'from scratch' <<<"$phase3"
if grep -Fq 'Each amendment is one failure on `contract`' <<<"$phase3"; then exit 1; fi
ceiling="$(section "$ORCHESTRATE" '## Gate attempt ceiling' '## Phase 0 —')"
grep -Fq '`contract`' <<<"$ceiling"
if grep -Fq '(except on a contract amendment, below)' <<<"$resume"; then exit 1; fi
phase4="$(section "$ORCHESTRATE" '## Phase 4 —' '## Phase 5 —')"
if grep -Fq 'RED-leg `test-writer`' <<<"$phase4"; then exit 1; fi
grep -Fq 'you append its plan line' <<<"$phase4"
grep -Fq '`## Gate` amendment' "$TESTS_GUIDE"
no_amendment="$(grep -F 'without one' "$TESTS_GUIDE")"
grep -Fq 'stays **Major**' <<<"$no_amendment"
TESTS_PY="$ROOT/.claude/guides/review/tests-python.md"
grep -Fq '`## Gate` amendment' "$TESTS_PY"
grep -Fq 'no assertion removed' "$TESTS_PY"
grep -Fq 'case-insensitive' "$TESTS_PY"
BACKEND_TEST="$ROOT/addons/fastapi/commands/backend/test.md"
grep -Fq 'test_b<n>_{action}_{scenario}' "$BACKEND_TEST"
grep -Fq 'next free `B` id' "$BACKEND_TEST"
grep -Fq 'test_b<n>_' "$ROOT/addons/fastapi/commands/backend/service.md"
if grep -Fq 'contract, stops.' "$ROOT/docs/RATIONALE.md"; then exit 1; fi
grep -Fq 'append each further amendment' <<<"$gate_plan"
grep -Fq 'no assertion removed' "$TESTS_GUIDE"
naming="$(section "$TEST_WRITER" 'The case name is the case' 'Both outcomes')"
grep -Fq 'starts with the case id' <<<"$naming"
grep -Fq 'next free case id' "$ROOT/.claude/agents/implementer.md"
grep -Fq 'with its case id' "$DEBUG"
grep -Fq "it('R1 " "$ROOT/.claude/skills/patterns/tests.md"
grep -Fq 'test_b1_' "$ROOT/addons/fastapi/skills/patterns/pytest-backend.md"
if grep -Fq "**s'arrête** — tu relis les critères" "$ROOT/docs/Claude_Workflows.md"; then exit 1; fi
commit_step="$(section "$SHIP" '### 4. Commit' '### 4bis')"
grep -Fq '`amended`' <<<"$commit_step"
if grep -Fq '`## Gate` (step 2)' "$SHIP"; then exit 1; fi
merge_step="$(section "$SHIP" '2. Present the branch' '3. After the merge')"
grep -Fq '`amended`' <<<"$merge_step"
grep -Fq 'test hunk' <<<"$merge_step"
if grep -Fq 'otherwise ask for them here' "$SHIP"; then exit 1; fi
if grep -Fq 'tell the user' "$ROOT/.claude/hooks/tdd-freeze-tests.sh"; then exit 1; fi
grep -Fq 'The main thread records it' "$ROOT/.claude/hooks/tdd-freeze-tests.sh"
grep -Fq 'rewrite the plan line (same id)' "$ROOT/.claude/hooks/tdd-freeze-tests.sh"
if grep -Fq 'say so to the user' "$ROOT/.claude/hooks/tdd-freeze-tests.sh"; then exit 1; fi
if grep -Fq 'say which case and why' "$PY_FREEZE"; then exit 1; fi
grep -Fq 'the main thread adds one line' "$PY_FREEZE"
if grep -Fq 'say which case and why' "$ROOT/.claude/hooks/prevent-destructive-commands.sh"; then exit 1; fi
if grep -Fq 'tell the user, with which case and why' "$ROOT/.claude/commands/audit/mutation.md"; then exit 1; fi
if grep -Fq "et s'arrêter là" "$ROOT/docs/ADAPTATION.md"; then exit 1; fi
if grep -Eq '^[[:space:]]*/loop:orchestrate docs/specs/<slug>\.md[[:space:]]*$' "$ROOT/README.md"; then exit 1; fi

echo 'workflow contract fixtures: green.'
