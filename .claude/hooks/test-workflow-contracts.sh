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
              "dans le dépôt du kit, chaque écriture d'un hook, d'un script ou des settings demande ton accord" \
              '**Le code du kit, refusé dans un projet installé.**'; do
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
for needle in 'tool_use' 'tool_result'; do
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
for needle in 'Bash(pnpm build *)' \
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
# install.sh's prompt allow list; no wide form; every star only trailing.
HP_WANT='["Bash(pnpm exec tsc --noEmit)",
  "Bash(python3 .claude/hooks/kit-attempts.py *)", "Bash(python3 .claude/hooks/kit-doctor.py)",
  "Bash(python3 .claude/hooks/kit-doctor.py *)", "Bash(.claude/scripts/small-dispatch-check.sh *)",
  "Bash(.claude/scripts/small-paths.sh *)", "Bash(.claude/scripts/small-plan.sh *)",
  "Bash(.claude/scripts/small-scope.sh *)", "Bash(git fetch)", "Bash(git fetch *)",
  "Bash(git stash list)", "Bash(python3 .claude/hooks/kit-gate-route.py *)",
  "Bash(python3 .claude/hooks/kit-audit-surface.py *)"]'
for hp_suite in attempts audit-surface gate-route hooks kit-doctor measure rules-floor small-lane; do
    HP_WANT="$(jq -c --arg s "$hp_suite" \
        '. + ["Bash(bash .claude/hooks/test-\($s).sh)", "Bash(bash .claude/hooks/test-\($s).sh *)"]' <<<"$HP_WANT")"
done
HP_KIT="$(sed -n "/^PROMPT_ALLOWS='/,/]'\$/p" "$ROOT/install.sh" | sed "s/^PROMPT_ALLOWS='//; s/'\$//")"
jq -en --argjson kit "$HP_KIT" --argjson want "$HP_WANT" '($kit | sort) == ($want | sort) and ($want | length) == 29' >/dev/null
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
for k2_suite in test-hooks test-install test-kit-doctor test-small-lane test-attempts test-audit-surface test-gate-route test-workflow-contracts test-rules-floor test-measure; do
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
RULES_CEILING="$(sed -n 's/^CORE_CEILING=\([0-9][0-9]*\)$/\1/p' "$ROOT/.claude/hooks/test-rules-floor.sh")"
[[ -n "$RULES_CEILING" && "$RULES_TOTAL" -le "$RULES_CEILING" ]] || {
    echo "W5/PK3: the session floor is $RULES_TOTAL lines, over test-rules-floor.sh's ceiling ${RULES_CEILING:-?}" >&2
    exit 1
}
for f in "$ROOT"/.claude/hooks/*.sh "$ROOT/install.sh"; do
    [[ "$(basename "$f")" == test-* ]] && continue
    if grep -n 'project_config\.py' "$f" | grep -v '^[0-9]*:[[:space:]]*#' \
        | grep 'roots\|check' | grep -qv 'python3 -I'; then
        exit 1
    fi
done

# pr-screenshots: the PR body order, the pr-assets publishing and cleanup, the
# capture contract, and no other image host.
pr_template=$(section "$GITHUB_AGENT" '**Body**: in this order' '### The rules that make it short')
pr_last=0
for pr_needle in '<One line: what this does' '**Where to look**' '**Uncertain**' '- `<sha>`' '**Screenshots** —'; do
    pr_line=$(grep -Fn -- "$pr_needle" <<<"$pr_template" | head -n 1 | cut -d: -f1)
    [[ -n "$pr_line" && "$pr_line" -gt "$pr_last" ]] || { echo "PR body order broken at: $pr_needle" >&2; exit 1; }
    pr_last=$pr_line
done
for pr_needle in 'one line per commit' '--body-file' 'kit-pr-assets.py commit' 'kit-pr-assets.py drop' 'pr-assets'; do
    grep -Fq -- "$pr_needle" "$GITHUB_AGENT"
done
for pr_needle in PR_SHOTS PR_SHOTS_DIR .pr-shots/ emulateMedia PW_BASE_URL; do
    grep -Fq -- "$pr_needle" "$ROOT/.claude/skills/e2e-playwright/SKILL.md"
done
grep -Fq 'Screenshots:' "$ROOT/.claude/agents/e2e-tester.md"
for pr_needle in 'kit-pr-assets.py ui' 'ls-files --others --exclude-standard' 'PR_SHOTS=before'; do
    grep -Fq -- "$pr_needle" "$REVIEW"
done
grep -Fq 'kit-pr-assets.py drop' "$SHIP"
grep -Fq 'MERGED' "$SHIP"
for pr_file in "$GITHUB_AGENT" "$ROOT/.claude/skills/e2e-playwright/SKILL.md" "$ROOT/.claude/agents/e2e-tester.md"; do
    if grep -Eiq 'imgur|supabase|upload-artifact|s3\.' "$pr_file"; then echo "foreign image host in $pr_file" >&2; exit 1; fi
done

# PK1 (project-config): no hook holds a moved project value or its default literal; the
# values live in .claude/project.json, read by project_config.py.
PK1_OUT="$(python3 -I - "$ROOT" <<'PY'
import ast
import glob
import io
import json
import os
import re
import sys
import tokenize

root = sys.argv[1]
icons = "|".join(json.load(open(os.path.join(root, ".claude", "project.json")))["forbidden_icons"])
literals = ["example|sample|template", r"^\.env\.example$", "app/services", "lib/client",
            '"main|master"', "cwk_bin prettier", "cwk_bin eslint", "Protected: src/", icons]
shell_names = ["PROTECTED_DIRS", "PROTECTED_BRANCHES", "RUN_TESTS", "CWK_TDD_LAYERS"]
py_names = {"DATA_CLIENT_MODULE", "DATA_CLIENT_OWN_PATH", "COMPOSITION_ROOTS", "SHARED_DIRS",
            "SECRET_KEEP", "MODULE_ROOT", "TESTS_ROOT", "TEST_FIRST_DIRS", "SESSION_NAMES",
            "EXTERNAL_CLIENTS"}
files = []
for pattern in (".claude/hooks/*.sh", ".claude/hooks/*.py", "addons/fastapi/hooks/*.sh", "addons/fastapi/hooks/*.py"):
    files += glob.glob(os.path.join(root, pattern))
bad = []
for path in sorted(files):
    name = os.path.basename(path)
    if name in ("project_config.py", "kit-doctor.py") or name.startswith(("test-", "test_")):
        continue
    text = open(path, encoding="utf-8").read()
    rel = os.path.relpath(path, root)
    if name.endswith(".sh"):
        for number, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for var in shell_names:
                if re.search(rf'(^|[^A-Za-z0-9_]){var}="[^$]', line):
                    bad.append(f"{rel}:{number}: {var}= literal")
            if "ENV_TEMPLATE_RE" in line or re.search(r"SECRET_KEEP\s*=", line):
                bad.append(f"{rel}:{number}: env template copy")
            for literal in literals:
                if literal in line:
                    bad.append(f"{rel}:{number}: {literal}")
        continue
    tree = ast.parse(text)
    for node in ast.walk(tree):
        targets = node.targets if isinstance(node, ast.Assign) else [node.target] if isinstance(node, ast.AnnAssign) else []
        for target in targets:
            if isinstance(target, ast.Name) and target.id in py_names:
                bad.append(f"{rel}:{node.lineno}: {target.id} =")
    docs = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(getattr(first, "value", None), ast.Constant) \
                    and isinstance(first.value.value, str):
                docs.update(range(first.lineno, first.end_lineno + 1))
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.type == tokenize.COMMENT or token.start[0] in docs:
            continue
        for literal in literals:
            if literal in token.string:
                bad.append(f"{rel}:{token.start[0]}: {literal}")
print("\n".join(sorted(set(bad))))
PY
)"
if [[ -n "$PK1_OUT" ]]; then printf 'PK1: a hook still holds a project value:\n%s\n' "$PK1_OUT" >&2; exit 1; fi

# PK2: every reader call runs isolated, and no file sources or evals reader output.
PK2_OUT="$(grep -nE 'project_config\.py' "$ROOT"/.claude/hooks/*.sh "$ROOT"/.claude/scripts/*.sh \
    "$ROOT"/addons/*/hooks/*.sh "$ROOT/install.sh" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -E 'python3( +-[A-Za-z]+)* +"?[^ ]*project_config\.py' | grep -vE 'python3 +-I' || true)"
if [[ -n "$PK2_OUT" ]]; then printf 'PK2: reader call without -I:\n%s\n' "$PK2_OUT" >&2; exit 1; fi
if grep -nE '(source|eval|\.) +.*project_config\.py' "$ROOT"/.claude/hooks/*.sh "$ROOT"/.claude/scripts/*.sh \
        "$ROOT/install.sh" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; then
    echo 'PK2: reader output sourced or evaluated' >&2; exit 1
fi

# PK4: the four hooks that read project values are guard files, each stamped.
for pk_hook in tdd-freeze-tests.sh no-forbidden-icons.sh enforce-architecture.py tdd-prove-red.sh; do
    grep -q '^# cwk-guard-api: [0-9]' "$ROOT/.claude/hooks/$pk_hook"
done

# PK5: /kit:init writes the project values into .claude/project.json, never into a hook.
for pk_key in protected_branches test_command env_template_suffixes forbidden_icons tdd_layers; do
    grep -Fq "$pk_key" "$KIT_INIT"
done
if grep -nE '^[0-9]+\. +`?(\.claude/hooks/|[a-z_-]+\.(sh|py)`)' "$KIT_INIT"; then
    echo 'PK5: a /kit:init step edits a hook' >&2; exit 1
fi

# PK6 (amended with PV3): cwk_is_guarded stays two-state, 0 or 1; an unreadable config is the
# degraded mode, which turns the hook's pass into an ask, never a third return code that a bare
# `if cwk_is_guarded` would read as "not guarded".
PK6_BODY="$(sed -n '/^cwk_is_guarded() {/,/^}/p' "$ROOT/.claude/hooks/hook-guarded.sh")"
[[ -n "$PK6_BODY" ]] || { echo 'PK6: cwk_is_guarded not found' >&2; exit 1; }
if grep -nE 'return +[2-9]' <<<"$PK6_BODY"; then
    echo 'PK6: cwk_is_guarded returns a third state' >&2; exit 1
fi

# PK7 (review 1): a hook whose reading of the project values changed carries a new stamp, so
# the line is inert since kit-boundary: protect-files 2 → 3, auto-approve-config 1 → 2.
pk7_stamp() { sed -n 's/^# cwk-guard-api: \([0-9][0-9]*\)$/\1/p' "$ROOT/.claude/hooks/$1" | head -n 1; }
[[ "$(pk7_stamp protect-files.sh)" -ge 3 ]] || { echo 'PK7: protect-files.sh stamp is below 3' >&2; exit 1; }
[[ "$(pk7_stamp auto-approve-config.sh)" -ge 2 ]] || { echo 'PK7: auto-approve-config.sh stamp is below 2' >&2; exit 1; }

# PK8: the never-matching pattern stays under BSD's repetition limit (RE_DUP_MAX 255).
pk8_count="$(sed -n "s/^CWK_NEVER_RE=.*{\([0-9][0-9]*\)}'.*/\1/p" "$ROOT/.claude/hooks/hook-guarded.sh")"
[[ -n "$pk8_count" && "$pk8_count" -le 255 ]] || { echo "PK8: CWK_NEVER_RE repeats ${pk8_count:-?} times" >&2; exit 1; }
pk8_files=()
for pk8_f in "$ROOT"/.claude/hooks/*.sh "$ROOT"/.claude/hooks/*.py "$ROOT"/.claude/scripts/*.sh \
             "$ROOT"/addons/fastapi/hooks/*.sh "$ROOT"/addons/fastapi/hooks/*.py; do
    [[ "$(basename "$pk8_f")" == test-* ]] || pk8_files+=("$pk8_f")
done
if grep -nE '\{(25[6-9]|2[6-9][0-9]|[3-9][0-9]{2}|[0-9]{4,})\}' "${pk8_files[@]}"; then
    echo 'PK8: an ERE repeats more than 255 times (RE_DUP_MAX on BSD)' >&2; exit 1
fi

# PK9: CODEOWNERS owns .claude/project.json, the file that holds every project value.
grep -Eq '^/\.claude/project\.json[[:space:]]+@' "$ROOT/templates/github/CODEOWNERS" \
    || { echo 'PK9: CODEOWNERS does not own .claude/project.json' >&2; exit 1; }
grep -Fq '.claude/project.json' <<<"$(grep -A4 '^- \*\*`CODEOWNERS`\*\*' "$ROOT/.claude/skills/templates/ci.md")" \
    || { echo 'PK9: ci.md does not list .claude/project.json among the owned paths' >&2; exit 1; }

# review-convergence: the routed gates (plan critic and review), their prose contracts.
rc_has() {
    local id="$1" text="$2" needle
    shift 2
    for needle in "$@"; do
        grep -Fq -- "$needle" <<<"$text" || { echo "$id failed: lacks $needle" >&2; exit 1; }
    done
}
RC_REVIEWER="$ROOT/.claude/agents/reviewer.md"
RC_VERIFIER="$ROOT/.claude/agents/verifier.md"
RC_IMPLEMENTER="$ROOT/.claude/agents/implementer.md"
RC_WORKFLOWS="$ROOT/docs/Claude_Workflows.md"
# T1 plan-critic carries the P1 classes, the kinds, the closure and the rerun answer.
rc_has T1 "$(cat "$CRITIC")" vigilance '(a)' '(b)' '(c)' '(d)' demonstrated interpretation \
    'Closure:' 'fixed | not fixed'
# T2 plan.md step 6 routes through kit-gate-route.py, the unconditional block first.
rc_step6="$(section "$PLAN" '6. **PLAN CRITIC GATE' '7. **TEST PLAN GATE')"
rc_has T2 "$rc_step6" 'rewritten sections' '## Vigilance' 'no failed attempt' kit-gate-route.py \
    write-closure 'narrowing that rewrite' 'never re-entered as `interpretation`' \
    'Critical/Major claim to a `verifier`' 'whatever `next` is'
awk -v a='whatever `next` is' -v b='write-closure' '
    { buf = buf $0 "\n" }
    END { i = index(buf, a); j = index(buf, b); exit !(i > 0 && j > 0 && i < j) }' <<<"$rc_step6" \
    || { echo "T2 failed: whatever \`next\` is must precede the first write-closure" >&2; exit 1; }
# T3 plan.md step 7 opens arbitration and records the pass on the go.
rc_has T3 "$(section "$PLAN" '7. **TEST PLAN GATE' '8. **Stop')" 'Plan critic, open' 'kit-attempts.py pass'
# T4 orchestrate Phase 5 snapshots, routes and re-reviews on the fix diff.
rc_has T4 "$(section "$ORCHESTRATE" '## Phase 5 —' '## Phase 6 —')" 'fix diff' follow-ups.md \
    'kit-gate-route.py snapshot' kit-gate-route.py write-closure 'Growth:'
# T5 reviewer re-review mode, review.md stage 3 routing, ship reads the follow-ups.
rc_has T5 "$(cat "$RC_REVIEWER")" 'fixed | not fixed' regression 'Closure:' fix-introduced 'only when'
rc_has T5 "$(section "$REVIEW" '### Stage 3 — SYNTHESIS' '## Output')" follow-ups.md kit-gate-route.py \
    write-closure
rc_has T5 "$(cat "$SHIP")" follow-ups.md
# T6 implementer answers a fix-introduced finding with the smaller fix and reports growth.
rc_has T6 "$(cat "$RC_IMPLEMENTER")" fix-introduced 'smaller fix' 'Growth:'
# T7 verifier gets the fix base and checks a regression claim.
rc_has T7 "$(cat "$RC_VERIFIER")" fix-base regression
# T8 one source for what records a failed review attempt.
rc_head="$(sed -n 1,15p "$REVIEW")"
! grep -Fq 'Any surviving Critical/Major records one failed attempt' <<<"$rc_head" \
    || { echo "T8 failed: review.md still records its own attempt rule" >&2; exit 1; }
rc_has T8 "$rc_head" kit-gate-route.py
# T9 the plan template records its Base.
rc_has T9 "$(cat "$PLAN")" 'Base: <sha>'
# T10 a Codex fix batch resumes on the fix diff.
rc_has T10 "$(section "$ORCHESTRATE" '`review_status: fixes-handed-to-codex` →' '`ship` → Phase 6')" 'fix diff'
# T11 the French map names the new mechanics.
rc_has T11 "$(cat "$RC_WORKFLOWS")" follow-ups.md fix-introduced Vigilance 'interprétation'
# T12 plan.md step 6 derives leg from the routing file, execute-red always claude.
rc_has T12 "$rc_step6" 'workflow-routing.yml' 'execute-red' 'always `claude`'
# T13 review.md 3bis: a not-fixed finding re-enters the route, the main thread writes its own
# findings' Closure, and only orchestrate Phase 5 increments the round.
rc_3bis="$(section "$REVIEW" '3bis. **Route the survivors' '4. Report the refuted')"
rc_has T13 "$rc_3bis" 'status: not-fixed' 'main thread' 'a fresh `/loop:review` is round 1'

# PK10 (kit-boundary): every kit-code entry but the stamp is guarded, the stamp is not, and
# CWK_KIT_CODE names every entry of the spec's kit-code list.
PK10_OUT="$(CLAUDE_PROJECT_DIR="$ROOT" bash -c '
    source "$1" || exit 99
    for e in "${CWK_KIT_CODE[@]}"; do
        [[ "$e" == .claude/INSTALL_PROFILE ]] && continue
        cwk_is_guarded "${e//\*/x}" || echo "unguarded: $e"
    done
    cwk_is_guarded .claude/INSTALL_PROFILE && echo "guarded stamp"
    for e in .claude/hooks/x .claude/scripts/x addons/fastapi/hooks/x workflow.py workflow.sh \
             codex-handoff.sh install.sh .claude/project.json .claude/INSTALL_PROFILE; do
        cwk_is_kit_code "$e" || echo "not kit code: $e"
    done' _ "$ROOT/.claude/hooks/hook-guarded.sh" 2>&1)" || { echo "PK10: $PK10_OUT" >&2; exit 1; }
[[ -z "$PK10_OUT" ]] || { echo "PK10: $PK10_OUT" >&2; exit 1; }
# PK11 the hold-back is gone from install.sh, and project_config.py has no snapshot subcommand.
for pk_dead in guard_api_missing reader_stale 'P1 held back'; do
    if grep -Fq "$pk_dead" "$ROOT/install.sh"; then echo "PK11: install.sh still holds $pk_dead" >&2; exit 1; fi
done
if grep -qw held "$ROOT/install.sh"; then echo 'PK11: install.sh still holds held' >&2; exit 1; fi
if grep -Eq 'argv\[1\] == "snapshot"|^def snapshot' "$ROOT/.claude/hooks/project_config.py"; then
    echo 'PK11: project_config.py still has a snapshot subcommand' >&2; exit 1
fi
# PK12 /kit:init writes a proposal the user applies; ADAPTATION §15 names the backup, not the hold-back.
for pk_needle in '.claude/project.proposed.json' 'bash .claude/scripts/kit-apply.sh'; do
    grep -Fq "$pk_needle" "$ROOT/.claude/commands/kit/init.md" || { echo "PK12: init.md lacks $pk_needle" >&2; exit 1; }
done
PK12_S15="$(section "$ADAPTATION" '## 15. ' '## Vérifier que le câblage tient')"
grep -Fq '.claude/kit-backup/' <<<"$PK12_S15" || { echo 'PK12: §15 does not name .claude/kit-backup/' >&2; exit 1; }
if grep -Fq 'P1 held back' <<<"$PK12_S15"; then echo 'PK12: §15 still names P1 held back' >&2; exit 1; fi
# PK13 the three guard hooks carry the deny text through CWK_KIT_DENY, never a literal copy.
for pk_hook in protect-files.sh prevent-destructive-commands.sh enforce-git-workflow.sh; do
    grep -Fq 'CWK_KIT_DENY' "$ROOT/.claude/hooks/$pk_hook" || { echo "PK13: $pk_hook ignores CWK_KIT_DENY" >&2; exit 1; }
    if grep -Fq 'kit code changes in the LoopKit repo' "$ROOT/.claude/hooks/$pk_hook"; then
        echo "PK13: $pk_hook copies the deny text" >&2; exit 1
    fi
done
# PK14 (review round 1): the TDD messages that send the agent to .claude/project.json name the route
# that works in an installed project, where that file is kit code.
for pk_needle in '/kit:init' 'bash .claude/scripts/kit-apply.sh'; do
    grep -Fq "$pk_needle" "$ROOT/.claude/hooks/tdd-prove-red.sh" || { echo "PK14: tdd-prove-red.sh lacks $pk_needle" >&2; exit 1; }
done
# ship-audit-surface: step 1bis picks the surfaces from the diff and files the follow-ups.
sa_1bis="$(section "$SHIP" '### 1bis.' '### 2. Acceptance criteria')"
# T14 ship.md 1bis runs the selector, never drops, says not armed, files follow-ups.
rc_has T14 "$sa_1bis" kit-audit-surface.py 'not armed' follow-ups.md 'never drops' \
    'review security ran' 'one `security-auditor`' 'Audit added:' 'the surfaces the user named'
# T15 the guide names the diff as the selector, not one surface per profile reason.
sa_guide="$(section "$ROOT/.claude/guides/ship.md" '## Why `critical` arms an audit' '## Why advancing the state')"
rc_has T15 "$sa_guide" kit-audit-surface.py diff
! grep -Fq 'One surface is one `security-auditor`' <<<"$sa_guide" \
    || { echo "T15 failed: the guide still says one surface is one security-auditor" >&2; exit 1; }
# T16 the ship report carries both not-armed variants.
rc_has T16 "$(section "$SHIP" '## Output' '## Rules')" 'not armed — profile' \
    'not armed — diff touches no audit surface'
# T17 the French map names the selector and the follow-ups beside step 1bis.
rc_has T17 "$(grep -F 1bis "$RC_WORKFLOWS")" kit-audit-surface.py follow-ups.md
# T18 any non-zero exit of the selector stops the ship, not only exit 2.
rc_has T18 "$sa_1bis" 'any non-zero exit'

# ---- kit-prompts step 6: no project value in a kit prompt; values live in overlays/project.json.
kp_dirs=()
for d in "$ROOT"/.claude/{agents,commands,skills,guides} "$ROOT"/addons/*/{agents,commands,skills,guides}; do
    [[ -d "$d" ]] && kp_dirs+=("$d")
done
# kp_prompt_paths <text>: kit prompt paths named in <text> and not under .claude/overlays/, one per line.
kp_prompt_paths() {
    local p rel
    grep -oE '[A-Za-z0-9./_-]*(agents|commands|skills|guides|templates|patterns)/[A-Za-z0-9/._-]+\.md' <<<"$1" \
        | while IFS= read -r p; do
            [[ "$p" == .claude/overlays/* ]] && continue
            rel="${p#.claude/}"
            case "$rel" in templates/* | patterns/*) rel="skills/$rel" ;; esac
            if [[ -f "$ROOT/.claude/$rel" ]] || compgen -G "$ROOT/addons/*/$rel" >/dev/null; then
                printf '%s\n' "$p"
            fi
        done || true
}
# PK15 no FILL marker left in a kit prompt, core or addon.
if grep -rnE -- '<!-- FILL|— FILL>' "${kp_dirs[@]}"; then echo 'PK15: a FILL marker in a kit prompt' >&2; exit 1; fi
# PK16 every slot line names its own overlay, whose template holds the section, and back.
kp16_lines="$(grep -rnoE '\*\*Project slot `[a-z-]+`\*\* — `## [a-z-]+` in `\.claude/overlays/[^`]+`' "$ROOT/.claude" || true)"
[[ -n "$kp16_lines" ]] || { echo 'PK16: no slot line at all' >&2; exit 1; }
while IFS= read -r kp_line; do
    kp_file="${kp_line%%:*}"; kp_rel="${kp_file#"$ROOT/.claude/"}"
    kp_slot="$(sed -E 's/.*\*\*Project slot `([a-z-]+)`.*/\1/' <<<"$kp_line")"
    kp_sect="$(sed -E 's/.*`## ([a-z-]+)` in.*/\1/' <<<"$kp_line")"
    kp_over="$(sed -E 's/.*`\.claude\/overlays\/([^`]+)`.*/\1/' <<<"$kp_line")"
    [[ "$kp_slot" == "$kp_sect" ]] || { echo "PK16: $kp_rel slot $kp_slot names section $kp_sect" >&2; exit 1; }
    [[ "$kp_over" == "$kp_rel" ]] || { echo "PK16: $kp_rel names the overlay of $kp_over" >&2; exit 1; }
    grep -qx "## $kp_slot" "$ROOT/templates/overlays/$kp_rel" 2>/dev/null \
        || { echo "PK16: templates/overlays/$kp_rel lacks ## $kp_slot" >&2; exit 1; }
done <<<"$kp16_lines"
while IFS= read -r -d '' kp_tpl; do
    kp_rel="${kp_tpl#"$ROOT/templates/overlays/"}"
    while IFS= read -r kp_sect; do
        case "$kp_sect" in 'Recipes' | 'Local rules') continue ;; esac
        grep -Fq "**Project slot \`$kp_sect\`**" "$ROOT/.claude/$kp_rel" 2>/dev/null \
            || { echo "PK16: overlay section $kp_rel ## $kp_sect has no slot line" >&2; exit 1; }
    done < <(sed -n 's/^## //p' "$kp_tpl")
done < <(find "$ROOT/templates/overlays" -type f -name '*.md' -print0)
# PK17 github.md reads protected_branches; correctness.md reads data_client.shared_dirs, no count.
kp_gh="$ROOT/.claude/agents/github.md"
grep -Fq 'protected_branches' "$kp_gh" && grep -Fq '.claude/project.json' "$kp_gh" \
    || { echo 'PK17: github.md does not read protected_branches' >&2; exit 1; }
if grep -F 'a commit on' "$kp_gh" | grep -Eq '`(main|master)`'; then echo 'PK17: github.md names a protected branch' >&2; exit 1; fi
kp_cr="$ROOT/.claude/guides/review/correctness.md"
grep -Fq 'data_client.shared_dirs' "$kp_cr" || { echo 'PK17: correctness.md does not read shared_dirs' >&2; exit 1; }
if grep -Eq 'project\.json`,[[:space:]]+[a-z]+[[:space:]]+entries' "$kp_cr"; then echo 'PK17: correctness.md states a count' >&2; exit 1; fi
# PK18 ADAPTATION §2/§9/§10/§12/§13 and init.md steps 2/9/10/12 write overlays or the proposal,
# never a kit prompt; init.md has a Port step naming the backup.
kp_adapt="$ROOT/docs/ADAPTATION.md"
for kp_n in 2 9 10 12 13; do
    kp_text="$(awk -v n="$kp_n" '$0 ~ "^## "n"\\. " { on = 1; print; next } on && /^## [0-9]+\. |^## [A-Z]/ { exit } on' "$kp_adapt")"
    [[ -n "$kp_text" ]] || { echo "PK18: ADAPTATION §$kp_n not found" >&2; exit 1; }
    grep -Eq '\.claude/overlays/|project\.proposed\.json|\.claude/project\.json' <<<"$kp_text" \
        || { echo "PK18: ADAPTATION §$kp_n names no overlay nor project.json" >&2; exit 1; }
    kp_bad="$(kp_prompt_paths "$kp_text")"
    [[ -z "$kp_bad" ]] || { echo "PK18: ADAPTATION §$kp_n names kit prompts: $kp_bad" >&2; exit 1; }
done
kp_init="$ROOT/.claude/commands/kit/init.md"
for kp_n in 2 9 10 12; do
    kp_text="$(awk -v n="$kp_n" '/^## Phase 3/ { p3 = 1; next } p3 && /^## / { exit } p3 && $0 ~ "^"n"\\. " { on = 1; print; next } on && /^[0-9]+\. / { exit } on' "$kp_init")"
    [[ -n "$kp_text" ]] || { echo "PK18: init.md step $kp_n not found" >&2; exit 1; }
    grep -Eq '\.claude/overlays/|project\.proposed\.json|\.claude/project\.json' <<<"$kp_text" \
        || { echo "PK18: init.md step $kp_n names no overlay nor project.json" >&2; exit 1; }
    kp_bad="$(kp_prompt_paths "$kp_text")"
    [[ -z "$kp_bad" ]] || { echo "PK18: init.md step $kp_n names kit prompts: $kp_bad" >&2; exit 1; }
done
kp_port="$(awk '/^## Phase [0-9]+ — Port/ { on = 1; print; next } on && /^## / { exit } on' "$kp_init")"
[[ -n "$kp_port" ]] && grep -Fq '.claude/kit-backup/' <<<"$kp_port" \
    || { echo 'PK18: init.md has no Port step naming .claude/kit-backup/' >&2; exit 1; }
# PK19 recipes, the CLAUDE.md kit-code line, the manifest in README and ADAPTATION.
grep -Fq '.claude/recipes/' "$ROOT/.claude/commands/kit/recipe.md" && grep -Fq '## Recipes' "$ROOT/.claude/commands/kit/recipe.md" \
    || { echo 'PK19: recipe.md does not route an installed project to .claude/recipes/' >&2; exit 1; }
grep -F 'Kit code' "$ROOT/CLAUDE.md" | grep -F 'prompts' | grep -Fq '.claude/overlays/' \
    || { echo 'PK19: CLAUDE.md kit-code line does not name prompts and overlays' >&2; exit 1; }
grep -Fq '.claude/kit-manifest' "$ROOT/README.md" || { echo 'PK19: README lacks .claude/kit-manifest' >&2; exit 1; }
grep -Fq '.claude/kit-manifest' "$kp_adapt" || { echo 'PK19: ADAPTATION lacks .claude/kit-manifest' >&2; exit 1; }
# PK20 the fastapi README §3/§4 name overlays and no kit prompt to edit; security.md has its section.
kp_fa="$(section "$ROOT/addons/fastapi/README.md" '### 3.' '### 5.')"
grep -Fq '.claude/overlays/' <<<"$kp_fa" || { echo 'PK20: fastapi README §3/§4 name no overlay' >&2; exit 1; }
kp_bad="$(kp_prompt_paths "$kp_fa")"
[[ -z "$kp_bad" ]] || { echo "PK20: fastapi README §3/§4 name kit prompts: $kp_bad" >&2; exit 1; }
grep -qx '## extra-checks' "$ROOT/templates/overlays/guides/review/security.md" 2>/dev/null \
    || { echo 'PK20: security.md overlay lacks ## extra-checks' >&2; exit 1; }
# PK21 the ship bundle-secret scan computes its directories from app_roots, never a literal src/.
kp_ship="$ROOT/.claude/commands/loop/ship.md"
kp_fence="$(awk '/^```bash/ { buf = ""; inb = 1; next } /^```/ && inb { if (buf ~ /Bundle secrets/) { printf "%s", buf; exit } inb = 0; next } inb { buf = buf $0 "\n" }' "$kp_ship")"
[[ -n "$kp_fence" ]] || { echo 'PK21: ship.md bundle-scan fence not found' >&2; exit 1; }
grep -Fq 'app_roots' <<<"$kp_fence" && grep -Fq '.claude/project.json' <<<"$kp_fence" \
    || { echo 'PK21: ship.md bundle-scan fence does not read app_roots from .claude/project.json' >&2; exit 1; }
! grep -Fq 'test -d src/' <<<"$kp_fence" || { echo 'PK21: ship.md bundle-scan fence still tests a literal src/' >&2; exit 1; }
if command -v jq >/dev/null 2>&1; then
    kp_tmp="$(mktemp -d)"
    mkdir -p "$kp_tmp/.claude" "$kp_tmp/frontend/src"
    printf '{"app_roots": ["frontend"]}\n' >"$kp_tmp/.claude/project.json"
    printf 'const a = import.meta.env.VITE_X_SECRET\nVITE_X_SECRET=1\n' >"$kp_tmp/frontend/src/a.ts"
    kp_scan="$(sed -n '/^# Bundle secrets/,$p' <<<"$kp_fence")"
    kp_out="$(cd "$kp_tmp" && bash -c "$kp_scan" 2>&1 || true)"
    rm -rf "$kp_tmp"
    grep -Fq 'frontend/src/a.ts' <<<"$kp_out" || { echo "PK21: executed fence did not scan frontend/src: $kp_out" >&2; exit 1; }
    ! grep -Fq 'SCAN NOT RUN' <<<"$kp_out" || { echo "PK21: executed fence reported SCAN NOT RUN: $kp_out" >&2; exit 1; }
fi
# PK22 every kit prompt importing @/lib/client in an example names data_client.module.
for kp_f in templates/feature.md templates/fixtures.md patterns/react-query.md; do
    kp_p="$ROOT/.claude/skills/$kp_f"
    grep -Fq '@/lib/client' "$kp_p" || continue
    grep -Fq 'data_client.module' "$kp_p" || { echo "PK22: $kp_f imports @/lib/client without naming data_client.module" >&2; exit 1; }
done
# PK23 the bundle-scan fence falls back to src on empty app_roots, and reports each missing root.
kp23_ship="${KP23_SHIP:-$ROOT/.claude/commands/loop/ship.md}"
kp23_fence="$(awk '/^```bash/ { buf = ""; inb = 1; next } /^```/ && inb { if (buf ~ /Bundle secrets/) { printf "%s", buf; exit } inb = 0; next } inb { buf = buf $0 "\n" }' "$kp23_ship")"
if command -v jq >/dev/null 2>&1; then
    kp23_scan="$(sed -n '/^# Bundle secrets/,$p' <<<"$kp23_fence")"
    kp23_tmp="$(mktemp -d)"
    mkdir -p "$kp23_tmp/.claude" "$kp23_tmp/src"
    printf '{"app_roots": []}\n' >"$kp23_tmp/.claude/project.json"
    printf 'VITE_X_SECRET=1\n' >"$kp23_tmp/src/a.ts"
    kp23_out="$(cd "$kp23_tmp" && bash -c "$kp23_scan" 2>&1 || true)"
    rm -rf "$kp23_tmp"
    grep -Fq 'src/a.ts' <<<"$kp23_out" || { echo "PK23: empty app_roots did not fall back to src: $kp23_out" >&2; exit 1; }
    ! grep -Fq 'SCAN NOT RUN' <<<"$kp23_out" || { echo "PK23: empty app_roots reported SCAN NOT RUN: $kp23_out" >&2; exit 1; }
    kp23_tmp="$(mktemp -d)"
    mkdir -p "$kp23_tmp/.claude" "$kp23_tmp/frontend/src"
    printf '{"app_roots": ["frontend","web"]}\n' >"$kp23_tmp/.claude/project.json"
    kp23_out="$(cd "$kp23_tmp" && bash -c "$kp23_scan" 2>&1 || true)"
    rm -rf "$kp23_tmp"
    grep -Fq 'SCAN NOT RUN: no web/src' <<<"$kp23_out" || { echo "PK23: missing web/src not reported: $kp23_out" >&2; exit 1; }
fi
# PK24 the bundle-scan fence also scans <root>/.env.example for each declared root.
kp24_ship="${KP24_SHIP:-$ROOT/.claude/commands/loop/ship.md}"
kp24_fence="$(awk '/^```bash/ { buf = ""; inb = 1; next } /^```/ && inb { if (buf ~ /Bundle secrets/) { printf "%s", buf; exit } inb = 0; next } inb { buf = buf $0 "\n" }' "$kp24_ship")"
if command -v jq >/dev/null 2>&1; then
    kp24_scan="$(sed -n '/^# Bundle secrets/,$p' <<<"$kp24_fence")"
    kp24_tmp="$(mktemp -d)"
    mkdir -p "$kp24_tmp/.claude" "$kp24_tmp/frontend/src"
    printf '{"app_roots": ["frontend"]}\n' >"$kp24_tmp/.claude/project.json"
    printf 'const a = 1\n' >"$kp24_tmp/frontend/src/a.ts"
    printf 'VITE_X_SECRET=\n' >"$kp24_tmp/frontend/.env.example"
    kp24_out="$(cd "$kp24_tmp" && bash -c "$kp24_scan" 2>&1 || true)"
    rm -rf "$kp24_tmp"
    grep -Fq 'frontend/.env.example' <<<"$kp24_out" || { echo "PK24: fence did not scan frontend/.env.example: $kp24_out" >&2; exit 1; }
fi

# github-sync-local: the github agent keeps local in sync, ff-only, never forced.
gs_never='Never `--force`, `reset --hard`, `pull --rebase` or a rebase to make the sync fit.'
gs_sec="$(awk '/^### Keeping local in sync/ { on = 1; print; next } on && /^##/ { exit } on' "$GITHUB_AGENT")"
# GS1 the section exists, before ## Output format.
[[ -n "$gs_sec" ]] || { echo 'GS1: github.md has no ### Keeping local in sync section' >&2; exit 1; }
gs_at="$(grep -n '^### Keeping local in sync' "$GITHUB_AGENT" | head -1 | cut -d: -f1)"
gs_out="$(grep -n '^## Output format' "$GITHUB_AGENT" | head -1 | cut -d: -f1)"
[[ -n "$gs_out" && "$gs_at" -lt "$gs_out" ]] || { echo 'GS1: Keeping local in sync is not before ## Output format' >&2; exit 1; }
# GS2 the three sync commands.
for gs_p in '`git fetch origin`' '`git merge --ff-only origin/<branch>`' '`git fetch origin <base>:<base>`'; do
    grep -Fq "$gs_p" <<<"$gs_sec" || { echo "GS2: sync section lacks $gs_p" >&2; exit 1; }
done
# GS3 the three triggers.
for gs_p in 'after a merge you ran' 'after a PR you merged or found' 'at the start of a task, when origin is ahead'; do
    grep -Fq "$gs_p" <<<"$gs_sec" || { echo "GS3: sync section lacks trigger: $gs_p" >&2; exit 1; }
done
# GS4 report-not-fix, dirty tree, and the one-line Never sentence.
for gs_p in 'Diverged or blocked: report it, change nothing.' 'a dirty tree the fast-forward would overwrite' "$gs_never"; do
    grep -Fq "$gs_p" <<<"$gs_sec" || { echo "GS4: sync section lacks: $gs_p" >&2; exit 1; }
done
# GS5 the Local: report line with its three forms.
gs_local="$(sed -n "${gs_out},\$p" "$GITHUB_AGENT" | grep -E '^- Local:' || true)"
for gs_p in '<old>..<new>' 'up to date' 'diverged:'; do
    grep -Fq "$gs_p" <<<"$gs_local" || { echo "GS5: Output format - Local: line lacks $gs_p" >&2; exit 1; }
done
# GS6a inside the section, force/reset/rebase appear only on the Never line.
gs_bad="$(grep -E -- '--force|reset --hard|rebase' <<<"$gs_sec" | grep -vF "$gs_never" || true)"
[[ -z "$gs_bad" ]] || { echo "GS6a: sync section names force/reset/rebase outside the Never sentence: $gs_bad" >&2; exit 1; }
# GS6b file-wide, reset --hard and pull --rebase only on the Never line.
gs_bad="$(grep -E -- 'reset --hard|pull --rebase' "$GITHUB_AGENT" | grep -vF "$gs_never" || true)"
[[ -z "$gs_bad" ]] || { echo "GS6b: github.md names reset --hard / pull --rebase outside the Never sentence: $gs_bad" >&2; exit 1; }
# GS7 diverged means commits on both sides; a branch only ahead has its own Local: form.
grep -Fq 'commits on both sides' <<<"$gs_sec" || { echo "GS7: sync section does not define diverged as commits on both sides" >&2; exit 1; }
grep -Fq 'ahead:' <<<"$gs_local" || { echo "GS7: Output format - Local: line lacks the ahead: form" >&2; exit 1; }

echo 'workflow contract fixtures: green.'
