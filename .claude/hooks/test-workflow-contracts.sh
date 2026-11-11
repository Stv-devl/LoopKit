#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEBUG="$ROOT/.claude/commands/loop/debug.md"
PLAN="$ROOT/.claude/commands/loop/plan.md"
CRITIC="$ROOT/.claude/agents/plan-critic.md"
PRODUCT="$ROOT/.claude/commands/loop/product.md"
ORCHESTRATE="$ROOT/.claude/commands/loop/orchestrate.md"
REVIEW="$ROOT/.claude/commands/loop/review.md"
SMALL="$ROOT/.claude/commands/loop/small.md"
SHIP="$ROOT/.claude/commands/loop/ship.md"
TRACKS="$ROOT/.claude/commands/loop/tracks.md"
WORKTREES="$ROOT/.claude/guides/10-worktrees.md"
GITHUB_AGENT="$ROOT/.claude/agents/github.md"
RESEARCH="$ROOT/.claude/commands/loop/research.md"
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
[ "$(ls "$ROOT"/.claude/commands/loop/*.md | wc -l)" -eq 13 ]
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
next_ctx clear | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="SessionStart"'
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

# Small-lane command and workflow contracts.
[ "$(grep -Fc 'AskUserQuestion' "$SMALL")" -eq 1 ]
for trigger in 'schema change' 'critical trigger' 'new dependency' 'new screen'; do
  grep -Fq "$trigger" "$SMALL"
done
research_line=$(grep -nF 'Research inline' "$SMALL" | head -1 | cut -d: -f1)
draft_line=$(grep -nF 'Draft the small spec' "$SMALL" | head -1 | cut -d: -f1)
paths_line=$(grep -nF 'small-paths.sh' "$SMALL" | head -1 | cut -d: -f1)
go_line=$(grep -nF 'AskUserQuestion' "$SMALL" | head -1 | cut -d: -f1)
dispatch_line=$(grep -nF 'small-dispatch-check.sh' "$SMALL" | tail -1 | cut -d: -f1)
dispatch_before=$(grep -nF 'small-dispatch-check.sh' "$SMALL" | head -1 | cut -d: -f1)
paths_after=$(grep -nF 'small-paths.sh' "$SMALL" | tail -1 | cut -d: -f1)
[ "$research_line" -lt "$draft_line" ]
[ "$paths_line" -lt "$go_line" ]
[ "$dispatch_before" -lt "$go_line" ]
[ "$go_line" -lt "$dispatch_line" ]
[ "$go_line" -lt "$paths_after" ]
grep -Fq './workflow.sh "/loop:orchestrate docs/specs/small/<name>.md"' "$SMALL"
if grep -Fq 'EnterWorktree' "$SMALL"; then exit 1; fi

small_pick=$(grep -nF 'docs/specs/small/' "$ORCHESTRATE" | head -1 | cut -d: -f1)
light_pick=$(grep -nF 'Light pass' "$ORCHESTRATE" | head -1 | cut -d: -f1)
ready_pick=$(grep -nF 'FEATURE READY check' "$ORCHESTRATE" | head -1 | cut -d: -f1)
resume_rule=$(grep -nF 'is a resume' "$ORCHESTRATE" | head -1 | cut -d: -f1)
[ "$small_pick" -lt "$light_pick" ]
[ "$small_pick" -lt "$ready_pick" ]
[ "$small_pick" -lt "$resume_rule" ]
small_branch=$(section "$ORCHESTRATE" 'Small pipeline' 'FEATURE READY check')
for required in 'Pipeline: small' 'Entry:' 'small-plan.sh' 'one reviewer' 'one verifier' 'implementer' 'small-scope.sh'; do
  grep -Fq "$required" <<<"$small_branch"
done
if grep -Fq 'AskUserQuestion' <<<"$small_branch"; then exit 1; fi

grep -Fq 'small-ticket' "$WORKTREES"
if grep -Fq 'What lives in the main tree only' "$WORKTREES"; then exit 1; fi
for required in 'small-scope.sh' '4bis.1' '4bis.2' '4bis.3' 'merge --ff-only'; do
  grep -Fq "$required" "$SHIP"
done

small_slug=$(grep -nF -- '- entry `docs/specs/small/<name>.md`' "$RESEARCH" | head -1 | cut -d: -f1)
generic_slug=$(grep -nF -- '- entry `docs/specs/<x>.md`' "$RESEARCH" | head -1 | cut -d: -f1)
[ "$small_slug" -lt "$generic_slug" ]

for required in 'docs/work/small-<name>/ejected' 're-enter: /loop:spec' 'S2 trigger:' 'review FAIL:' 'kit-attempts.py'; do
  grep -Fq "$required" <<<"$small_branch"
done
attempt_line=$(grep -F 'kit-attempts.py' <<<"$small_branch" | head -1)
grep -Fq 'without `--board/--unit`' <<<"$attempt_line"
for required in '--status' 'in flight' 'ejected' 'to clean'; do
  grep -Fq -- "$required" "$SMALL"
done
grep -Fq "plan's \`Acceptance criteria\`" "$REVIEW"
github_small=$(section "$GITHUB_AGENT" 'For a small-ticket branch' '1. `git worktree list`')
grep -Fq 'small-ticket' <<<"$github_small"
grep -Fq 'merge --ff-only' <<<"$github_small"
grep -Fq "spec's \`Base:\`" <<<"$github_small"
grep -Fq 'Do not copy' <<<"$github_small"
grep -Fq 'docs/work/' <<<"$github_small"
grep -Fq 'small-ticket dirty-tree exception' "$TRACKS"
grep -Fq 'unmerged `small-*` worktrees' "$TRACKS"
grep -Fq 'close this terminal' "$SHIP"
grep -Fq '/loop:small --status' "$SHIP"
grep -Fq 'no board line to move' "$SHIP"
grep -Fq 'Step 6 and the closing line print that cleanup' "$SHIP"
grep -Fq 'git worktree remove .claude/worktrees/small-<name>' "$SHIP"

# W7 guard-writes: the TDD escape hatch is now a guarded write, and the deny
# texts say so; ADAPTATION names the guarded set and the kit-repo prompts.
TDD_RED_HOOK="$ROOT/.claude/hooks/tdd-require-red.sh"
TDD_FREEZE_HOOK="$ROOT/.claude/hooks/tdd-freeze-tests.sh"
ADAPTATION="$ROOT/docs/ADAPTATION.md"
[[ "$(grep -c 'this write will ask the user' "$TDD_RED_HOOK")" -eq 5 ]]
[[ "$(grep -c 'this write will ask the user' "$TDD_FREEZE_HOOK")" -eq 2 ]]
grep -Fq '## 14. Chemins gardés' "$ADAPTATION"
for needle in 'hook-guarded.sh' '.claude/.tdd-red/' 'vite.config.*' 'package.json' \
              "dans le dépôt du kit, chaque écriture d'un hook, d'un script ou des settings demande ton accord"; do
    section "$ADAPTATION" '## 14. Chemins gardés' '## Vérifier que le câblage tient' | grep -Fq -- "$needle"
done

# W12 the .tdd-unfrozen write is a user prompt now: orchestrate Phase 4 and the
# mutation audit say so, and the unattended claim is qualified; ADAPTATION names
# the two settings files instead of a glob.
MUTATION="$ROOT/.claude/commands/audit/mutation.md"
grep -Fq 'the `.tdd-unfrozen` write asks the user' "$ORCHESTRATE"
grep -Fq 'the `.tdd-unfrozen` write asks the user' "$MUTATION"
if grep -Fq 'Correcting one never stops EXECUTE — it may run unattended' "$ORCHESTRATE"; then exit 1; fi
adapt_guard=$(section "$ADAPTATION" '## 14. Chemins gardés' '## Vérifier que le câblage tient')
grep -Fq '`.claude/settings.json`' <<<"$adapt_guard"
grep -Fq '`.claude/settings.local.json`' <<<"$adapt_guard"
if grep -Fq 'settings*.json' <<<"$adapt_guard"; then exit 1; fi

# K1 light-permissions-git: the narrow permissions, exactly; the commit and
# staging forms the git hook polices; keys ignored; the branch hint.
SETTINGS="$ROOT/.claude/settings.json"
jq -e '.permissions.defaultMode == "acceptEdits"' "$SETTINGS" >/dev/null
for allow in 'Bash(git add *)' 'Bash(git commit -m *)' 'Bash(git switch -c *)' \
             'Bash(git branch --show-current)' 'Bash(git worktree list)'; do
    jq -e --arg a "$allow" '.permissions.allow | index($a)' "$SETTINGS" >/dev/null
done
for wide in 'Bash(git commit *)' 'Bash(git switch *)' 'Bash(git branch *)' 'Bash(git push *)' 'Bash(git *)' \
            'Bash(git -C *)' 'Bash(git -C * commit *)' 'Bash(git -C * commit -m *)'; do
    if jq -e --arg a "$wide" '.permissions.allow | index($a)' "$SETTINGS" >/dev/null; then exit 1; fi
done
grep -Fq 'git commit -m "<one line>"' "$GITHUB_AGENT"
grep -Fq 'never `.`, `-A`, `--all`, `-u`' "$GITHUB_AGENT"
for ignored in '*.pem' '*.key' 'credentials.*'; do
    grep -qxF "$ignored" "$ROOT/.gitignore"
done
# K1 harness-hooks DA1: the kit's Read deny, exactly and in order (a `!` entry
# carves only out of the entries before it); the doc names the union and the gap.
jq -e '.permissions.deny == ["Read(.env)", "Read(.env.*)", "Read(!.env.example)",
        "Read(!.env.sample)", "Read(!.env.template)", "Read(!.env.*.example)",
        "Read(!.env.*.sample)", "Read(!.env.*.template)", "Read(*.pem)", "Read(*.key)",
        "Read(credentials.*)", "Read(.credentials.*)"]' "$SETTINGS" >/dev/null
grep -Fq 'Read(!.env.example)' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'permissions.deny' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'sandbox.enabled' "$ROOT/docs/ADAPTATION.md"
GIT_HOOK="$ROOT/.claude/hooks/enforce-git-workflow.sh"
grep -Fq 'git switch -c feat/<scope>' "$GIT_HOOK"
if grep -Fq 'git checkout -b' "$GIT_HOOK"; then exit 1; fi
# K1 docs: the hold-back and the measure method; the prompts a light pass keeps.
for needle in 'P1 held back' 'tool_use' 'tool_result'; do
    grep -Fq "$needle" "$ROOT/docs/ADAPTATION.md"
done
for needle in 'git push' 'gh pr' '--amend' '--discard-changes' 'chemins gardés'; do
    grep -Fq -- "$needle" "$ROOT/docs/Claude_Workflows.md"
done

# K1b install.sh strips exactly the five P1 allows K1 names, no other list.
P1_KIT="$(sed -n "/^P1_ALLOWS='/,/]'\$/p" "$ROOT/install.sh" | sed "s/^P1_ALLOWS='//; s/'\$//")"
jq -en --argjson kit "$P1_KIT" \
    '($kit | sort) == (["Bash(git add *)", "Bash(git commit -m *)", "Bash(git switch -c *)",
                        "Bash(git branch --show-current)", "Bash(git worktree list)"] | sort)' >/dev/null
# K1c docs: the removal on hold-back, settings.local.json, and the prompts the
# amendment adds to a light pass.
for needle in 'retirés' 'settings.local.json'; do
    grep -Fq "$needle" "$ROOT/docs/ADAPTATION.md"
done
# K1 harness-hooks A0: the hold-back message and list in the doc match install.sh.
for needle in 'merge <fichiers>.new, then re-run install.sh' 'Bash(pnpm build *)' \
              'tdd-require-red.sh' 'auto-approve-config.sh'; do
    grep -Fq -- "$needle" "$ROOT/docs/ADAPTATION.md"
done
if grep -Fq 'merge their .new copies' "$ROOT/docs/ADAPTATION.md"; then exit 1; fi
for needle in 'rm -r' 'pathspec'; do
    grep -Fq -- "$needle" "$ROOT/docs/Claude_Workflows.md"
done
if grep -Fq 'blocks both' "$ROOT/.claude/commands/loop/ship.md"; then exit 1; fi
# K1d amendment 2: git add alone and git stage in §15; the github agent stages
# from another tree with -C and knows the new asks; the light pass lists --patch.
adapt_p1=$(section "$ADAPTATION" '## 15. Permissions étroites' '## Vérifier que le câblage tient')
for needle in 'seul dans son appel' 'git stage'; do
    grep -Fq -- "$needle" <<<"$adapt_p1"
done
for needle in 'git -C <tree> add' '--include'; do
    grep -Fq -- "$needle" "$GITHUB_AGENT"
done
grep -Fq -- '--patch' "$ROOT/docs/Claude_Workflows.md"
# K1e git-allow-grammar: the strict forms are the only prompt-free ones.
grep -Fq 'formes strictes' <<<"$adapt_p1"
if grep -Fq 'peuvent le précéder' <<<"$adapt_p1"; then exit 1; fi
grep -Fq 'strict forms' "$GITHUB_AGENT"
if grep -Fq 'git add/stage/status/diff/log' "$GITHUB_AGENT"; then exit 1; fi
grep -Fq 'formes strictes' "$ROOT/docs/Claude_Workflows.md"
# K1f the three guard hooks fail closed: every handler naming one carries onFailure=block
# (a timeout or a crash otherwise falls through to the normal permission flow).
jq -e '[.hooks[][].hooks[]
        | select(.command | endswith("protect-files.sh") or endswith("prevent-destructive-commands.sh")
                            or endswith("enforce-git-workflow.sh"))]
       | length >= 5 and all(.onFailure == "block")
         and ([.[].command | sub(".*/"; "")] | unique | length == 3)' "$ROOT/.claude/settings.json" >/dev/null
# K1g the two TDD guards fail closed too: a timeout or a crash must not let a
# module through before its RED, or a frozen test be rewritten.
jq -e '[.hooks[][].hooks[]
        | select(.command | endswith("tdd-require-red.sh") or endswith("tdd-freeze-tests.sh"))]
       | length == 2 and all(.onFailure == "block")
         and ([.[].command | sub(".*/"; "")] | unique | length == 2)' "$ROOT/.claude/settings.json" >/dev/null
# HC harness-cd: a deploy leaves only from a green push of this repository's
# default branch, on pinned actions and CLIs, to a host whose key is known.
CD_DIR="$ROOT/templates/github"
CD_DEPLOY="$CD_DIR/deploy.yml"
CD_SSH="$CD_DIR/publish/ssh.yml"
# HC1a reproduces the hole: a run from a fork's `main` satisfies the old condition.
grep -Fxq -- "    if: github.event_name == 'workflow_dispatch' || (github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_repository.full_name == github.repository && github.event.workflow_run.head_branch == github.event.repository.default_branch)" "$CD_DEPLOY"
# HC1b one job-level condition, and nothing YAML would fold into it.
[ "$(grep -c '^    if:' "$CD_DEPLOY")" -eq 1 ]
[ "$(awk '/^jobs:/ { jobs = 1; next } jobs && /^  [^ #]/ { n++ } END { print n + 0 }' "$CD_DEPLOY")" -eq 1 ]
if grep -Fq '>-' "$CD_DEPLOY"; then exit 1; fi
awk '/^    if:/ { seen = 1; next } seen && /[^[:space:]]/ { match($0, /^ */); exit (RLENGTH > 4) }' "$CD_DEPLOY"
# The whole `run:` body of a named step, from the line after `run: |` to the next
# line indented less than the body (blank lines kept only between body lines).
cd_run_body() {
    awk -v name="$2" '
        !step && $0 ~ ("^ +- name: " name "$") { step = 1; next }
        step && !body && /^ +run: \|$/ { body = 1; next }
        body && /^[[:space:]]*$/ { blank = blank "\n"; next }
        body && /^          / { printf "%s%s\n", blank, $0; blank = ""; next }
        body { exit }
    ' "$1"
}
# HC1c-e the Resolve body is byte for byte what the kit means: dispatch picks the newest
# successful push run of the default branch, and both paths refuse a commit that is not on
# it before any output is written.
cmp -s <(cd_run_body "$CD_DEPLOY" 'Resolve the CI run to deploy') - <<'EOF'
          set -euo pipefail
          if [ "$EVENT" = "workflow_run" ]; then
            id="$RUN_ID"; sha="$RUN_SHA"
          else
            # Dispatch manuel : le dernier CI VERT issu d'un push sur la branche par défaut.
            # Aucun run vert → on s'arrête, plutôt que de déployer autre chose.
            # `|| true` : sans lui, un `gh` en échec (réseau, token) fait
            # retourner 1 à `read`, et `set -e` tue le step AVANT le message
            # ci-dessous — le garde ne couvrait que le cas « aucun run vert »,
            # pas le cas « gh est cassé ». Les deux mènent ici maintenant.
            id=""; sha=""
            read -r id sha < <(gh run list --workflow=CI --branch="$DEFAULT_BRANCH" --event=push \
              --status=success --limit=1 \
              --json databaseId,headSha --jq '.[0] | "\(.databaseId) \(.headSha)"') || true
            if [ -z "$id" ] || [ "$id" = "null" ]; then
              echo "Aucun run CI vert exploitable sur $DEFAULT_BRANCH." >&2
              echo "Causes : aucun run reussi, ou 'gh run list' a echoue." >&2
              exit 1
            fi
            echo "Dispatch manuel : deploiement du run CI $id ($sha)."
            # Si ce run a plus de `retention-days` (7 dans ci.yml), son artefact
            # a expire et le telechargement plus bas echouera sur un message qui
            # ne dit pas ca. Relancer le CI sur la branche par defaut regle le
            # cas ; monter la retention dans ci.yml est l'autre option.
          fi
          # Le `head_branch` d'un run ne suffit pas : un push de TAG rapporte
          # son nom de tag comme `head_branch`, donc un tag nommé comme la
          # branche par défaut passe le `if:`. On exige que le commit soit
          # un ancêtre (ou la tête) de la branche par défaut.
          status="$(gh api "repos/$GH_REPO/compare/$sha...refs/heads/$DEFAULT_BRANCH?per_page=1" --jq .status)"
          case "$status" in
            ahead|identical) ;;
            *) echo "Le commit $sha n'est pas sur la branche $DEFAULT_BRANCH : deploiement refuse." >&2; exit 1 ;;
          esac
          echo "id=$id"   >> "$GITHUB_OUTPUT"
          echo "sha=$sha" >> "$GITHUB_OUTPUT"
EOF
# HC3a-f the SSH target refuses any host key but the pinned one.
if grep -Eq 'accept-new|StrictHostKeyChecking=no' "$CD_SSH"; then exit 1; fi
if grep -oiE 'StrictHostKeyChecking[^[:alnum:]]*[[:alnum:]-]*' "$CD_SSH" | grep -vx 'StrictHostKeyChecking=yes'; then exit 1; fi
# the whole Publish body: guards, the secret written to known_hosts before rsync, and rsync's strict option.
cmp -s <(cd_run_body "$CD_SSH" 'Publish') - <<'EOF'
          set -euo pipefail
          : "${DEPLOY_HOST:?secret DEPLOY_HOST manquant}"
          : "${DEPLOY_PATH:?variable DEPLOY_PATH manquante — refus de rsync --delete vers la racine}"
          : "${DEPLOY_KNOWN_HOSTS:?secret DEPLOY_KNOWN_HOSTS manquant — refus de deployer sans cle d hote}"
          case "$DEPLOY_PATH" in
            /) echo "DEPLOY_PATH=/ interdit avec --delete." >&2; exit 1 ;;
            /*) : ;;
            *) echo "DEPLOY_PATH doit être un chemin absolu (reçu: $DEPLOY_PATH)." >&2; exit 1 ;;
          esac
          mkdir -p ~/.ssh && chmod 700 ~/.ssh
          printf '%s\n' "$DEPLOY_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > ~/.ssh/known_hosts
          chmod 600 ~/.ssh/known_hosts
          rsync -az --delete \
            -e "ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=yes" \
            dist/ "$DEPLOY_HOST:$DEPLOY_PATH/"
EOF
grep -Fxq -- '          DEPLOY_KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}' "$CD_SSH"
grep -Eq '^ *# +secret +DEPLOY_KNOWN_HOSTS ' "$CD_SSH"
grep -Eq '^ *# +secret +DEPLOY_HOST .*statique' "$CD_SSH"
# nothing outside the comments may scan a host key: the env block and the steps before `run:` included.
if grep -vE '^[[:space:]]*#' "$CD_SSH" | grep -Fq 'ssh-keyscan'; then exit 1; fi
# HC2a-b every active `uses:` is pinned to a full SHA with its exact tag, and none went missing.
cd_uses="$(grep -rhE '^[^#]*\buses["'"'"']?[[:space:]]*:' "$CD_DIR")"
[ -n "$cd_uses" ]
if grep -Ev '^[[:space:]]*(- )?uses: [^[:space:]@]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$cd_uses"; then exit 1; fi
[ "$(wc -l <<<"$cd_uses")" -eq 13 ]
# HC2c every CLI call names an exact version, and no other launcher appears.
cd_active="$(find "$CD_DIR" -type f -exec awk '
    FNR == 1 { if (cont != "") print cont; cont = "" }
    cont == "" && /^[[:space:]]*#/ { next }
    { line = $0
      if (cont != "") { sub(/^[[:space:]]+/, "", line); line = cont " " line; cont = "" }
      if (line ~ /\\[[:space:]]*$/) { sub(/[[:space:]]*\\[[:space:]]*$/, "", line); cont = line; next }
      sub(/[[:space:]]+#.*$/, "", line)
      print line }
    END { if (cont != "") print cont }' {} +)"
cd_calls="$(grep -oE 'pnpm([[:space:]]+[^[:space:];&|]+)*[[:space:]]+dlx([[:space:]]+-[^[:space:];&|]+)*[[:space:]]+[^[:space:];&|]+' <<<"$cd_active")"
if grep -Ev '^pnpm (dlx vercel@[0-9]+\.[0-9]+\.[0-9]+|--package=netlify-cli@[0-9]+\.[0-9]+\.[0-9]+ dlx netlify)$' <<<"$cd_calls"; then exit 1; fi
grep -Fq 'netlify-cli@' <<<"$cd_calls"
grep -Fq 'vercel@' <<<"$cd_calls"
cd_flags='(-[^[:space:]]+[[:space:]]+)*'
cd_before='(^|[^[:alnum:]_.-])'
if grep -Eq "${cd_before}(npx|pnpx|bunx|yarn[[:space:]]+dlx)([^[:alnum:]_.-]|\$)|${cd_before}npm[[:space:]]+${cd_flags}(i|install|exec|x)([[:space:]]|\$)|${cd_before}(pnpm|yarn)[[:space:]]+${cd_flags}(add|global)([[:space:]]|\$)" <<<"$cd_active"; then exit 1; fi
# HC2d dependabot is byte for byte what the kit means: both ecosystems weekly, npm majors left out.
cmp -s "$CD_DIR/dependabot.yml" - <<'EOF'
version: 2
updates:
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
    ignore:
      - dependency-name: "*"
        update-types: ["version-update:semver-major"]
EOF
# HC4 the docs and comments state the same guarantees.
CD_CI_MD="$ROOT/.claude/skills/templates/ci.md"
cd_property="$(section "$CD_CI_MD" '1. **It deploys only what a green CI produced' '2. **It ships')"
grep -Fq 'push' <<<"$cd_property"
grep -Fq 'same repository' <<<"$cd_property"
grep -Fq 'DEPLOY_KNOWN_HOSTS' "$CD_CI_MD"
cd_environment="$(section "$CD_CI_MD" '4. **`environment: production` is the human gate.' '## What is deliberately not here')"
for needle in 'runs the file of the chosen ref' '"Deployment branches and tags"' '"Protected branches only"' 'environment secrets' 'GitHub Free' '`ghcr` has no secret' 'who holds write access' '`pages` is not settled'; do
    grep -Fq -- "$needle" <<<"$(tr -s ' \n' ' ' <<<"$cd_environment")"
done
cd_adapt="$(section "$ROOT/docs/ADAPTATION.md" '**`deploy.yml`** est **assemblé**' 'Puis **`CLAUDE.md`, section `Environment`**')"
cd_adapt_flat="$(tr -s ' \n' ' ' <<<"$cd_adapt")"
# shellcheck disable=SC1112  # the French apostrophe in a needle is literal on purpose
for needle in 'DEPLOY_KNOWN_HOSTS' 'statique' 'dependabot' 'doit fusionner le `deploy.yml.new`' 'son propre `--deploy=<cible>`' 'hors terminal le défaut est `none`' 'cette fusion rend `DEPLOY_KNOWN_HOSTS` obligatoire' 'à la main' 'majeures' 'Deployment branches and tags' 'secrets d’environnement' 'GitHub Free' '`ghcr` n'"'"'a aucun secret' 'sur qui a l'"'"'accès en écriture' 'ce point n'"'"'est pas tranché'; do
    grep -Fq -- "$needle" <<<"$cd_adapt_flat"
done
for cd_snippet in netlify vercel ssh; do
    grep -Fq -- 'Settings → Environments → `production` → Environment secrets' "$CD_DIR/publish/$cd_snippet.yml"
done
grep -Fq -- 'ssh-keyscan -t ed25519 <hote> | ssh-keygen -lf -' "$CD_SSH"
grep -Fq -- 'chemin OpenSSH standard' "$CD_SSH"
cd_comment="$(awk '/^    if:/ { printf "%s", block; exit } /^ *#/ { block = block $0 "\n"; next } { block = "" }' "$CD_DEPLOY")"
grep -Fq 'push' <<<"$cd_comment"
grep -Fq 'fork' <<<"$cd_comment"
cd_header="$(section "$CD_DEPLOY" '#   1. Il ne déploie' '#   2. Il déploie')"
grep -Fq 'push' <<<"$cd_header"
grep -Eq '# Dispatch manuel.*push' "$CD_DEPLOY"
# HP-B1 harness-prompts: files are written through Write/Edit, never through an
# interpreter, and a guarded-path ask is the user's to answer.
hp_line="$(grep -F '**Never write any file from the shell**' -A2 "$ROOT/CLAUDE.md")"
for hp_needle in 'python3 -' 'node -e' 'perl -i' 'heredoc' 'never by switching tools' 'auto-memory included'; do
    grep -Fq -- "$hp_needle" <<<"$hp_line"
done
for hp_agent in implementer test-writer; do
    grep -Fq 'never by switching tools' "$ROOT/.claude/agents/$hp_agent.md"
    grep -Fq 'node -e' "$ROOT/.claude/agents/$hp_agent.md"
done
hp_flow="$(section "$ROOT/docs/Claude_Workflows.md" '## Hors boucle' '## ')"
grep -Fq 'bash .claude/hooks/test-hooks.sh' <<<"$hp_flow"
grep -Fq '$(…)' <<<"$hp_flow"
# HP-B2 harness-prompts: the prompt allows, exactly, in settings.json and in
# install.sh's held-back list; no wide form; every star only trailing.
HP_WANT='["Bash(pnpm exec tsc --noEmit)",
  "Bash(python3 .claude/hooks/kit-attempts.py *)", "Bash(python3 .claude/hooks/kit-doctor.py)",
  "Bash(python3 .claude/hooks/kit-doctor.py *)", "Bash(.claude/scripts/small-dispatch-check.sh *)",
  "Bash(.claude/scripts/small-paths.sh *)", "Bash(.claude/scripts/small-plan.sh *)",
  "Bash(.claude/scripts/small-scope.sh *)", "Bash(git fetch)", "Bash(git fetch *)",
  "Bash(git stash list)"]'
for hp_suite in attempts hooks kit-doctor measure rules-floor small-lane; do
    HP_WANT="$(jq -c --arg s "$hp_suite" \
        '. + ["Bash(bash .claude/hooks/test-\($s).sh)", "Bash(bash .claude/hooks/test-\($s).sh *)"]' <<<"$HP_WANT")"
done
HP_KIT="$(sed -n "/^PROMPT_ALLOWS='/,/]'\$/p" "$ROOT/install.sh" | sed "s/^PROMPT_ALLOWS='//; s/'\$//")"
jq -en --argjson kit "$HP_KIT" --argjson want "$HP_WANT" '($kit | sort) == ($want | sort) and ($want | length) == 23' >/dev/null
jq -e --argjson want "$HP_WANT" '.permissions.allow as $a | all($want[]; . as $w | $a | index($w))' "$SETTINGS" >/dev/null
# Ship audit C2: the kit-development suites run root files (install.sh, workflow.py,
# codex-handoff.sh); their allows stay in the kit and never ride to a target.
for hp_dev in install workflow-contracts; do
    for hp_form in "Bash(bash .claude/hooks/test-$hp_dev.sh)" "Bash(bash .claude/hooks/test-$hp_dev.sh *)"; do
        jq -e --arg a "$hp_form" '.permissions.allow | index($a)' "$SETTINGS" >/dev/null
        if jq -en --argjson kit "$HP_KIT" --arg a "$hp_form" '$kit | index($a)' >/dev/null; then exit 1; fi
    done
done
# Ship audit C1: no kit shell file feeds Python from stdin or -c without -I, which
# would put the cwd first on sys.path and import a planted root re.py/json.py.
hp_noi="$(grep -nE 'python3( +-[A-Za-z]+)* +(-c|-)( |$)' "$ROOT/install.sh" "$ROOT/workflow.sh" \
    "$ROOT/codex-handoff.sh" "$ROOT"/.claude/hooks/*.sh "$ROOT"/.claude/scripts/*.sh 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE 'python3( +-[A-Za-z]+)* +-[A-Za-z]*I' || true)"
if [[ -n "$hp_noi" ]]; then printf 'python3 without -I:\n%s\n' "$hp_noi" >&2; exit 1; fi
# Review 6: workflow.sh runs workflow.py without its own directory on sys.path, so
# a root select.py written beside it is never imported by the launcher.
mkdir -p "$WS/hp-wf/run"
cp "$ROOT/workflow.sh" "$ROOT/workflow.py" "$WS/hp-wf/"
printf 'open(%s, "w").close()\n' "'$WS/hp-wf/planted-ran'" > "$WS/hp-wf/select.py"
(cd "$WS/hp-wf/run" && bash ../workflow.sh --help >/dev/null 2>&1) || true
if [[ -e "$WS/hp-wf/planted-ran" ]]; then echo 'workflow.sh imported a planted root module' >&2; exit 1; fi
for hp_wide in 'Bash(pnpm exec *)' 'Bash(uv run *)' 'Bash(python3 *)' 'Bash(node *)' 'Bash(bash *)' \
               'Bash(bash -x *)' 'Bash(mkdir -p *)' 'Bash(sed -i *)' 'Bash(git switch *)' \
               'Bash(git branch *)' 'Bash(git worktree add *)' 'Bash(git worktree remove *)' \
               'Bash(pnpm test:run *)' 'Bash(pnpm test:coverage *)' 'Bash(pnpm typecheck *)' \
               'Bash(pnpm lint *)' 'Bash(pnpm build *)' 'Bash(pnpm vitest run *)' \
               'Bash(pnpm exec vitest run *)' 'Bash(pnpm exec tsc --noEmit *)' \
               'Bash(pnpm exec playwright test *)'; do
    if jq -e --arg a "$hp_wide" '.permissions.allow | index($a)' "$SETTINGS" >/dev/null; then exit 1; fi
done
jq -e '[.permissions.allow[] | select(startswith("Bash(")) | ltrimstr("Bash(") | rtrimstr(")") | rtrimstr(" *")]
       | all(contains("*") | not)' "$SETTINGS" >/dev/null
hp_py="$(sed -n '/^add_py_hooks()/,/^}/p' "$ROOT/install.sh")"
for hp_uv in '"Bash(uv run ruff check .)"' '"Bash(uv run ruff check app)"' '"Bash(uv run ruff check app/)"' \
             '"Bash(uv run mypy app)"' '"Bash(uv run pyright)"'; do
    grep -Fq -- "$hp_uv" <<<"$hp_py"
done
grep -Fq 'kit-attempts.py' <<<"$(sed -n '/^GUARD_FILES=(/,/)/p' "$ROOT/install.sh")"
# K3a harness-kit-ci: ci.md, shipped to every target, names the repository
# settings that make the gates binding.
K3_CI_MD="$ROOT/.claude/skills/templates/ci.md"
k3_settings="$(awk '/^## Repository settings/ { f = 1; next } f && /^## / { exit } f' "$K3_CI_MD")"
grep -Fq 'ruleset' <<<"$k3_settings"
grep -Fq '`main`' <<<"$k3_settings"
grep -Fq 'pull request' <<<"$k3_settings"
grep -Fq '`Gates`' <<<"$k3_settings"
grep -Fq 'force push' <<<"$k3_settings"
grep -Fq 'deletion' <<<"$k3_settings"
grep -Fq 'CODEOWNERS' <<<"$k3_settings"
grep -Fq '`production`' <<<"$k3_settings"
grep -Fq 'required reviewer' <<<"$k3_settings"
# K3b `kit` is this repo's own check: never a required check of a target.
if grep -Fq '`kit`' "$K3_CI_MD"; then exit 1; fi
grep -Fq 'check requis `kit`' "$ROOT/docs/ADAPTATION.md"
# K3c the CODEOWNERS template covers the three guarded paths.
for k3_path in /.claude/hooks/ /.claude/settings.json /.github/workflows/; do
    grep -Eq "^${k3_path//./\\.}[[:space:]]+@" "$ROOT/templates/github/CODEOWNERS"
done
# K3d CODEOWNERS owns itself: a PR that empties it needs the owner too.
grep -Eq '^/\.github/CODEOWNERS[[:space:]]+@' "$ROOT/templates/github/CODEOWNERS"
# K2a harness-kit-ci: the kit's own CI lints what it ships and keeps every suite.
K2_CI="$ROOT/.github/workflows/kit-ci.yml"
grep -Fq 'shellcheck -S warning .claude/hooks/*.sh .claude/scripts/*.sh' "$K2_CI"
grep -Fq 'args: check --select E4,E7,E9,F' "$K2_CI"
grep -Fq 'src: .claude/hooks' "$K2_CI"
grep -Eq '^[[:space:]]+run: actionlint \.github/workflows/\*\.yml$' "$K2_CI"
grep -Fq 'for f in templates/github/publish/*.yml; do' "$K2_CI"
grep -Fq -- './install.sh "$d" --deploy="$t" </dev/null' "$K2_CI"
grep -Fq 'actionlint "$d"/.github/workflows/*.yml' "$K2_CI"
for k2_suite in test-hooks test-install test-kit-doctor test-small-lane test-attempts test-workflow-contracts test-rules-floor test-measure; do
    grep -Eq "^[[:space:]]+run: \.claude/hooks/${k2_suite}\.sh$" "$K2_CI"
done
grep -Eq '^[[:space:]]+run: python3 \.claude/hooks/kit-doctor\.py$' "$K2_CI"
# K2b every `uses:` of the kit CI is pinned to a full SHA with its exact tag.
k2_uses="$(grep -E '^[^#]*\buses:' "$K2_CI")"
[ "$(wc -l <<<"$k2_uses")" -eq 2 ]
if grep -Ev '^[[:space:]]*(- )?uses: [^[:space:]@]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$k2_uses"; then exit 1; fi
# K2c a hung step cannot hold the runner, and the checkout token is not kept.
grep -Eq '^[[:space:]]+timeout-minutes: 30$' "$K2_CI"
grep -Eq '^[[:space:]]+persist-credentials: false$' "$K2_CI"
# K2d each tarball is checked against a literal digest of the very file that is
# downloaded and extracted, and no step is allowed to fail quietly.
k2_sums="$(sed -nE 's/^.*"[0-9a-f]{64}  ([A-Za-z0-9._-]+\.tar\.gz)" \| sha256sum -c -$/\1/p' "$K2_CI")"
[ "$(wc -l <<<"$k2_sums")" -eq 2 ]
grep -Fxq 'shellcheck-v0.11.0.linux.x86_64.tar.gz' <<<"$k2_sums"
grep -Fxq 'actionlint_1.7.12_linux_amd64.tar.gz' <<<"$k2_sums"
while IFS= read -r k2_tar; do
    grep -Eq "^[[:space:]]+curl -fsSLO https://github\.com/[^[:space:]]+/${k2_tar//./\\.}$" "$K2_CI"
    grep -Fq "tar -xzf $k2_tar " "$K2_CI"
done <<<"$k2_sums"
if grep -Eq '\|\| true|continue-on-error' "$K2_CI"; then exit 1; fi
# K2e ruff is the pinned version, checked against a literal digest.
grep -Eq '^[[:space:]]+version: 0\.17\.4$' "$K2_CI"
grep -Eq '^[[:space:]]+checksum: [0-9a-f]{64}$' "$K2_CI"

# C1-C9 fewer-asks: the prompt half of the pass. Each needle is the rule an agent
# reads; the hooks enforce what they can, these lines say the rest.
fa_orch="$ROOT/.claude/commands/loop/orchestrate.md"
grep -Fq 'kit scripts run from the project root by relative path, never behind `cd x;`' "$fa_orch"
grep -Fq 'work artifacts are written with Write/Edit, never from the shell' "$fa_orch"
grep -Fq 'all the entries a gate needs go in one Edit' "$fa_orch"
grep -Fq "the chat never asks again what the hook's ask asks" "$fa_orch"
grep -Fq '# U2, U5:' "$fa_orch"
grep -Fq 'hand the `github` agent the subject only' "$ROOT/.claude/commands/loop/ship.md"
grep -Fq 'remove the applied `.tdd-unfrozen` entries in one Edit' "$ROOT/.claude/commands/loop/ship.md"
grep -Fq 'a body asked by the caller goes into the PR body, never into the commit' "$ROOT/.claude/agents/github.md"
grep -Fq 'git -C <tree> commit -m "<one line>"' "$ROOT/.claude/agents/github.md"
for fa_agent in implementer test-writer e2e-tester; do
    grep -Fq 'no no-op probe' "$ROOT/.claude/agents/$fa_agent.md"
    grep -Fq 'never redirect gate output to a file' "$ROOT/.claude/agents/$fa_agent.md"
done
grep -Fq 'never by switching tools' "$ROOT/.claude/agents/e2e-tester.md"
grep -Fq 'node -e' "$ROOT/.claude/agents/e2e-tester.md"
for fa_cmd in loop/spec bmad/pm; do
    grep -Fq 'printed, not asked' "$ROOT/.claude/commands/$fa_cmd.md"
    grep -Fq 'loosens a kit guard' "$ROOT/.claude/commands/$fa_cmd.md"
    if grep -Fq 'asked alone and asked always' "$ROOT/.claude/commands/$fa_cmd.md"; then exit 1; fi
done
for fa_cmd in interface plan; do
    grep -Fq "exactly the user's own words is recorded, not asked again" "$ROOT/.claude/commands/loop/$fa_cmd.md"
done
grep -Fq 'je lance' "$ROOT/CLAUDE.md"
grep -Fq 'cd dir;' "$ROOT/CLAUDE.md"

# W1-W4 (app-roots-codegen): /kit:init writes .claude/project.json; the doctor and the
# adaptation guide name it; every project_config.py call runs python3 -I.
KIT_INIT="$ROOT/.claude/commands/kit/init.md"
for needle in '.claude/project.json' 'app_roots' 'codegen_commands' 'pyproject.toml'; do
    grep -Fq "$needle" "$KIT_INIT"
done
grep -Fq 'project-config' "$ROOT/.claude/commands/kit/doctor.md"
grep -Fq '.claude/project.json' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'frontend/vite.config.' "$ROOT/docs/ADAPTATION.md"
grep -Fq 'project_config.py' "$ROOT/.claude/hooks/hook-guarded.sh"

# W5: no rule line was added for this pass; counted as test-rules-floor.sh counts the core total.
RULES_TOTAL="$(wc -l "$ROOT/CLAUDE.md" "$ROOT"/.claude/rules/*.md | tail -1 | awk '{print $1}')"
[[ "$RULES_TOTAL" -le 516 ]] || {
    echo "W5: the session floor is $RULES_TOTAL lines, over the 516 this pass started from" >&2
    exit 1
}
for f in "$ROOT"/.claude/hooks/*.sh "$ROOT/install.sh"; do
    [[ "$(basename "$f")" == test-* ]] && continue
    if grep -n 'project_config\.py' "$f" | grep -v '^[0-9]*:[[:space:]]*#' \
        | grep 'roots\|check' | grep -qv 'python3 -I'; then
        exit 1
    fi
done

echo 'workflow contract fixtures: green.'
