#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE="$HOOKS_DIR/kit-gate-route.py"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
export CLAUDE_PROJECT_DIR="$SCRATCH"
REPO="$SCRATCH/repo"
T="$REPO/docs/work/t"
OUT=""

fail() { echo "$1 failed${2:+: $2}" >&2; exit 1; }
kgr() { env -C "$REPO" python3 -I "$ROUTE" "$@"; }
ok() { jq -e "$2" <<<"$OUT" >/dev/null || fail "$1" "$2 on $OUT"; }
refused() {
    local id="$1" needle="$2" err rc
    shift 2
    set +e
    err="$(env -C "$REPO" python3 -I "$ROUTE" "$@" 2>&1 >/dev/null)"
    rc=$?
    set -e
    [[ $rc -eq 2 ]] || fail "$id" "exit $rc, want 2 ($err)"
    [[ -z "$needle" || "$err" == *"$needle"* ]] || fail "$id" "stderr lacks '$needle': $err"
}

# rf <id> <severity> <class> <path> <line> <scenario|""> <regression> <status> <closure|""> [dimension]
rf() {
    jq -nc --arg id "$1" --arg sev "$2" --arg cls "$3" --arg path "$4" --argjson line "$5" \
        --arg sc "$6" --argjson reg "$7" --arg st "$8" --arg cl "$9" --arg dim "${10:-correctness}" '
        def n: if . == "" then null else . end;
        {id: $id, severity: $sev, dimension: $dim, class: $cls, path: $path, line: $line,
         problem: ("problem " + $id), scenario: ($sc | n), regression: $reg, status: $st,
         closure: ($cl | n)}'
}
# review_in <dir> <file> <round> <finding-json>...
review_in() {
    local dir="$1" file="$2" round="$3"
    shift 3
    printf '%s\n' "$@" | jq -sc --argjson r "$round" '{mode: "review", round: $r, findings: .}' >"$dir/$file"
}
# pf <id> <severity> <p1|""> <kind|""> <status> <in_rewritten> <closure|""> [hook] [leg] [test_path]
pf() {
    jq -nc --arg id "$1" --arg sev "$2" --arg p1 "$3" --arg kind "$4" --arg st "$5" \
        --argjson rw "$6" --arg cl "$7" --arg hook "${8:-}" --arg leg "${9:-claude}" --arg tp "${10:-}" '
        def n: if . == "" then null else . end;
        {id: $id, severity: $sev, claim: ("claim " + $id), p1_class: ($p1 | n), kind: ($kind | n),
         status: $st, in_rewritten_section: $rw, closure: ($cl | n), hook: ($hook | n),
         leg: $leg, test_path: ($tp | n)}'
}
# plan_in <pass> <finding-json>...
plan_in() {
    local pass="$1"
    shift
    printf '%s\n' "$@" | jq -sc --argjson p "$pass" '{mode: "plan", pass: $p, findings: .}' >"$T/p.json"
}
route_review() { review_in "$T" r.json "$@"; OUT="$(kgr route docs/work/t/r.json)"; }
route_plan() { plan_in "$@"; OUT="$(kgr route docs/work/t/p.json)"; }
settings() {
    mkdir -p "$REPO/.claude"
    jq -n --arg c "$1" '{hooks: {PreToolUse: [{matcher: "Write|Edit",
        hooks: [{type: "command", command: $c}]}]}}' >"$REPO/.claude/settings.json"
}

# Fixture: base commit, plan commit, feature edits, snapshot, fix edits.
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name gate-route
git -C "$REPO" config user.email gate-route@example.invalid
git -C "$REPO" config commit.gpgsign false
seq -f 'line %g' 1 30 >"$REPO/a.ts"
seq -f 'b %g' 1 10 >"$REPO/b.ts"
seq -f 'e %g' 1 10 >"$REPO/e.ts"
git -C "$REPO" add -A
git -C "$REPO" commit -qm base
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$T"
printf '# Plan: t\nBase: %s\n' "$BASE_SHA" >"$T/plan.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm plan
{ seq -f 'feature %g' 1 10; seq -f 'line %g' 11 30; } >"$REPO/a.ts"
seq -f 'c %g' 1 5 >"$REPO/c.ts"
SNAP="$(kgr snapshot docs/work/t/plan.md)"
[[ "$(cat "$T/fix-base")" == "$SNAP" ]] || fail fixture "fix-base does not hold the printed sha"
[[ "$(tail -c1 "$T/fix-base" | od -An -c | tr -d ' ')" == '\n' ]] || fail fixture "fix-base lacks its newline"
{ seq -f 'feature %g' 1 10; seq -f 'line %g' 11 19; echo 'fixed 20'; seq -f 'line %g' 21 30; } >"$REPO/a.ts"
seq -f 'd %g' 1 50 >"$REPO/d.ts"

# ---- Review mode ----

# G1 round 1: no scoping before a fix batch
rm -f "$T/follow-ups.md"
route_review 1 "$(rf F1 Major test-quality e.ts 3 '' false new 'case X passes')"
ok G1 '.findings[0].route == "blocking" and .attempt.action == "fail" and .next == "fix-batch"'

# G2 a prior finding not fixed stays blocking
route_review 2 "$(rf F1 Major architecture e.ts 3 '' false not-fixed 'case X passes')"
ok G2 '.findings[0].route == "blocking" and .findings[0].fix_introduced == false'

# G3 (spec B1) correctness Major with a scenario in a feature file, outside the fix hunks
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major correctness a.ts 5 'call x with 0, gets 1' false new 'case X passes')"
ok G3 '.findings[0].route == "blocking" and .findings[0].fix_introduced == false'
ok G3 '.attempt.action == "fail" and .attempt.reason == "F1: problem F1"'
[[ ! -e "$T/follow-ups.md" ]] || fail G3 "follow-ups.md created"

# G4 (spec B2) architecture Major outside the fix hunks
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes')"
ok G4 '.findings[0].route == "follow-up" and .attempt.action == "pass" and .next == "clear"'
[[ "$(cat "$T/follow-ups.md")" == "- [correctness] a.ts:5 — problem F1 (out of scope)" ]] \
    || fail G4 "follow-ups.md: $(cat "$T/follow-ups.md")"

# G7 (spec B2) the same Major inside the fix hunk
route_review 2 "$(rf F1 Major architecture a.ts 20 '' false new 'case X passes')"
ok G7 '.findings[0].route == "blocking" and .findings[0].fix_introduced == true'

# G8 (spec B3) regression with a scenario outside the feature diff
route_review 2 "$(rf F1 Major correctness e.ts 3 'call y, gets z' true new 'case X passes')"
ok G8 '.findings[0].route == "blocking" and .findings[0].fix_introduced == true'

# G5 (spec B3) a Minor is a follow-up, in a fix hunk and at round 1
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Minor test-quality a.ts 20 '' false new '')"
ok G5 '.findings[0].route == "follow-up"'
grep -Fxq -- "- [correctness] a.ts:20 — problem F1 (minor)" "$T/follow-ups.md" || fail G5 "minor line"
route_review 1 "$(rf F2 Minor test-quality e.ts 3 '' false new '')"
ok G5 '.findings[0].route == "follow-up"'

# G6 (spec B4) a new file in the fix diff is one whole hunk
route_review 2 "$(rf F1 Major test-quality d.ts 40 '' false new 'case X passes')"
ok G6 '.findings[0].route == "blocking" and .findings[0].fix_introduced == true'

# G9 (spec B3) a regression without a scenario
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major correctness e.ts 3 '' true new 'case X passes')"
ok G9 '.findings[0].route == "follow-up"'
grep -Fxq -- "- [correctness] e.ts:3 — problem F1 (out of scope)" "$T/follow-ups.md" || fail G9 "line"

# G10 only Minors and out-of-scope findings
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Minor test-quality a.ts 20 '' false new '')" \
    "$(rf F2 Major architecture a.ts 5 '' false new 'case X passes')"
ok G10 '.attempt.action == "pass" and .next == "clear" and .follow_ups_added == 2'

# G13 (spec B8) no closure: Major → minor follow-up, Critical → needs-closure
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major architecture a.ts 20 '' false new '')"
ok G13 '.findings[0].route == "follow-up"'
grep -Fxq -- "- [correctness] a.ts:20 — problem F1 (minor)" "$T/follow-ups.md" || fail G13 "minor line"
route_review 2 "$(rf F1 Critical correctness a.ts 5 'call x, gets y' false new '')" \
    "$(rf F2 Major correctness a.ts 5 'call x, gets y' false new 'case X passes')"
ok G13 '.findings[0].route == "needs-closure" and .findings[1].route == "blocking"'
ok G13 '.attempt.action == "none" and .next == "write-closure"'

# G20 a rerun adds no duplicate follow-up
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes')"
OUT="$(kgr route docs/work/t/r.json)"
[[ "$(grep -Fxc -- "- [correctness] a.ts:5 — problem F1 (out of scope)" "$T/follow-ups.md")" == 1 ]] \
    || fail G20 "duplicate line"

# G22 the two diffs, the gate directory excluded, the real index untouched
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes')"
[[ -e "$T/follow-ups.md" && -e "$T/fix-base" ]] || fail G22 "gate files missing"
FIX="$(kgr diff docs/work/t/plan.md fix)"
grep -Fq 'd.ts' <<<"$FIX" || fail G22 "fix diff lacks d.ts"
grep -Fq 'new file' <<<"$FIX" || fail G22 "fix diff lacks a new file"
grep -Fq '+fixed 20' <<<"$FIX" || fail G22 "fix diff lacks the line-20 hunk"
! grep -Fq '+feature 1' <<<"$FIX" || fail G22 "fix diff shows feature lines"
! grep -Fq 'c.ts' <<<"$FIX" || fail G22 "fix diff shows c.ts"
FEAT="$(kgr diff docs/work/t/plan.md feature)"
for needle in c.ts d.ts '+feature 1' '+fixed 20'; do
    grep -Fq -- "$needle" <<<"$FEAT" || fail G22 "feature diff lacks $needle"
done
! grep -Fq 'docs/work/t' <<<"$FIX$FEAT" || fail G22 "a diff names the gate directory"
git -C "$REPO" diff --cached --quiet || fail G22 "real index changed"

# G23 refusals exit 2 and write nothing
cp "$T/r.json" "$REPO/elsewhere.json"
rm -f "$T/follow-ups.md"
refused G23 '' route elsewhere.json
refused G23 '' route "$T/r.json"
V="$REPO/docs/work/v"
mkdir -p "$V"
printf '# Plan: v\nBase: %s\n' "$BASE_SHA" >"$V/plan.md"
review_in "$V" r.json 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes')"
refused G23 'fix-base' route docs/work/v/r.json
[[ ! -e "$V/follow-ups.md" ]] || fail G23 "v follow-ups written"
review_in "$T" bad.json 2 "$(rf F1 Major style a.ts 5 '' false new 'case X passes')"
refused G23 '' route docs/work/t/bad.json
plan_in 1 "$(pf F1 Major a '' new true 'case X passes')"
refused G23 '' route docs/work/t/p.json
[[ ! -e "$T/follow-ups.md" ]] || fail G23 "t follow-ups written"

# G24 a plan without Base: (own slug u)
U="$REPO/docs/work/u"
mkdir -p "$U"
printf '# Plan: u\n' >"$U/plan.md"
kgr snapshot docs/work/u/plan.md >/dev/null
refused G24 'Base:' diff docs/work/u/plan.md feature
review_in "$U" r.json 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes')"
refused G24 'Base:' route docs/work/u/r.json
[[ ! -e "$U/follow-ups.md" ]] || fail G24 "u follow-ups written"

# ---- Plan mode ----

# G11 (spec B5) pass 2, demonstrated (c) and (d) rewrite, never arbitrate
route_plan 2 "$(pf F1 Major c demonstrated new true 'case X passes')"
ok G11 '.findings[0].route == "rewrite" and .attempt.action == "fail" and .next == "rewrite"'
ok G11 '.attempt.reason == "F1: claim F1"'
route_plan 2 "$(pf F1 Major d demonstrated new true 'case X passes')"
ok G11 '.findings[0].route == "rewrite"'

# G12 (spec B6) pass 2, interpretation only → arbitrate; a mix → rewrite + arbitrate
route_plan 2 "$(pf F1 Major a interpretation not-fixed true 'case X passes')" \
    "$(pf F2 Major b interpretation new true 'case Y passes')"
ok G12 '([.findings[].route] | unique) == ["arbitrate"] and .attempt.action == "none" and .next == "arbitrate"'
route_plan 2 "$(pf F1 Major c demonstrated new true 'case X passes')" \
    "$(pf F2 Major a interpretation new true 'case Y passes')"
ok G12 '.findings[0].route == "rewrite" and .findings[1].route == "arbitrate"'
ok G12 '.attempt.action == "fail" and .next == "rewrite" and .attempt.reason == "F1: claim F1"'

# G16 (spec B7) pass 3, demonstrated → blocked
route_plan 3 "$(pf F1 Major a demonstrated not-fixed true 'case X passes')"
ok G16 '.findings[0].route == "blocked" and .attempt.action == "fail" and .next == "blocked"'

# G14 (spec B8) no closure: Major → vigilance, Critical → needs-closure
route_plan 1 "$(pf F1 Major a demonstrated new true '')"
ok G14 '.findings[0].route == "vigilance"'
route_plan 1 "$(pf F1 Critical a demonstrated new true '')"
ok G14 '.findings[0].route == "needs-closure" and .next == "write-closure" and .attempt.action == "none"'

# G15 (spec B7) a non-P1 item is vigilance at any severity
route_plan 1 "$(pf F1 Critical '' '' new true 'case X passes')"
ok G15 '.findings[0].route == "vigilance" and .attempt.action == "pass" and .next == "clear"'
route_plan 1 "$(pf F1 Major '' '' new true 'case X passes')"
ok G15 '.findings[0].route == "vigilance" and .attempt.action == "pass" and .next == "clear"'

# G17 (P2) hook-covered only when the hook is registered
settings 'bash .claude/hooks/tdd-require-red.sh'
route_plan 1 "$(pf F1 Major b demonstrated new true 'case X passes' require-red claude src/x.utils.test.ts)"
ok G17 '.findings[0].route == "hook-covered" and .attempt.action == "pass"'
settings 'bash .claude/hooks/other-hook.sh'
route_plan 1 "$(pf F1 Major b demonstrated new true 'case X passes' require-red claude src/x.utils.test.ts)"
ok G17 '.findings[0].route == "rewrite"'
settings 'bash .claude/hooks/tdd-require-red.sh'

# G18 (P2) a Codex leg or an unhooked path is an ordinary finding
route_plan 1 "$(pf F1 Major b demonstrated new true 'case X passes' require-red codex src/x.utils.test.ts)"
ok G18 '.findings[0].route == "rewrite" and .attempt.action == "fail"'
route_plan 1 "$(pf F1 Major b demonstrated new true 'case X passes' require-red claude .claude/hooks/test-x.sh)"
ok G18 '.findings[0].route == "rewrite"'

# G19 (P3) pass 2, a new finding outside the rewritten sections
route_plan 2 "$(pf F1 Major a interpretation new false 'case X passes')"
ok G19 '.findings[0].route == "vigilance" and .attempt.action == "pass"'
route_plan 2 "$(pf F1 Major b demonstrated new false 'case X passes')"
ok G19 '.findings[0].route == "rewrite"'

# G21 pass 1, interpretation → rewrite
route_plan 1 "$(pf F1 Major a interpretation new true 'case X passes')"
ok G21 '.findings[0].route == "rewrite"'

# G25 never a pass 4
plan_in 4 "$(pf F1 Major a demonstrated new true 'case X passes')"
refused G25 'never a pass 4' route docs/work/t/p.json

# G26 (C-M3) a path that is absolute or has a . or .. segment is refused, nothing written
rm -f "$T/follow-ups.md"
for bad in ./a.ts /a.ts a/../a.ts; do
    review_in "$T" bad.json 2 "$(rf F1 Major architecture "$bad" 5 '' false new 'case X passes')"
    refused G26 'path' route docs/work/t/bad.json
done
[[ ! -e "$T/follow-ups.md" ]] || fail G26 "follow-ups written"

# G27 (C-M5) the literal scenario "none" is no scenario
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major correctness a.ts 5 none false new 'case X passes')"
ok G27 '.findings[0].route == "follow-up" and .next == "clear"'
route_review 2 "$(rf F1 Major correctness e.ts 3 None true new 'case X passes')"
ok G27 '.findings[0].route == "follow-up" and .next == "clear"'
grep -Fxq -- "- [correctness] a.ts:5 — problem F1 (out of scope)" "$T/follow-ups.md" || fail G27 "a.ts line"

# G28 (T-M1) negative side of the scenario rules: no scenario, or a scenario without regression
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Major correctness a.ts 5 '' false new 'case X passes')"
ok G28 '.findings[0].route == "follow-up" and .attempt.action == "pass"'
grep -Fxq -- "- [correctness] a.ts:5 — problem F1 (out of scope)" "$T/follow-ups.md" || fail G28 "a.ts line"
route_review 2 "$(rf F1 Major correctness e.ts 3 'call y, gets z' false new 'case X passes')"
ok G28 '.findings[0].route == "follow-up" and .attempt.action == "pass"'
grep -Fxq -- "- [correctness] e.ts:3 — problem F1 (out of scope)" "$T/follow-ups.md" || fail G28 "e.ts line"

# G29 (S-M1) Base: and fix-base never reach git diff as options
W="$REPO/docs/work/w"
mkdir -p "$W"
printf '# Plan: w\nBase: --output=x\n' >"$W/plan.md"
kgr snapshot docs/work/w/plan.md >/dev/null
refused G29 '' diff docs/work/w/plan.md feature
review_in "$W" r.json 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes')"
refused G29 '' route docs/work/w/r.json
[[ ! -e "$REPO/x" && ! -e "$W/x" ]] || fail G29 "Base: wrote a file"
printf '# Plan: w\nBase: %s\n' "$BASE_SHA" >"$W/plan.md"
printf -- '--output=y\n' >"$W/fix-base"
refused G29 '' diff docs/work/w/plan.md fix
refused G29 '' route docs/work/w/r.json
[[ ! -e "$REPO/y" && ! -e "$W/y" ]] || fail G29 "fix-base wrote a file"

# G30 (docs/specs/auto-mode-2.5-fixes.md item 9) a shadow item with dimension "shadow" is refused, and the
# reason names the five dimensions and the Stage 2.5 rule
rm -f "$T/follow-ups.md"
review_in "$T" bad.json 2 "$(rf F1 Major architecture a.ts 5 '' false new 'case X passes' shadow)"
refused G30 'Stage 2.5' route docs/work/t/bad.json
refused G30 'correctness, tests, db, security, ui' route docs/work/t/bad.json
[[ ! -e "$T/follow-ups.md" ]] || fail G30 "follow-ups written"

# G31 a Stage 2.5 item written as review.md tells (the dimension of the shadowed dependency) routes
rm -f "$T/follow-ups.md"
route_review 2 "$(rf F1 Minor correctness c.ts 2 'caller y, gets z' false new '' correctness)"
ok G31 '.findings[0].route == "follow-up" and .attempt.action == "pass" and .next == "clear"'
grep -Fxq -- "- [correctness] c.ts:2 — problem F1 (minor)" "$T/follow-ups.md" || fail G31 "follow-up line"

echo 'gate route fixtures: green.'
