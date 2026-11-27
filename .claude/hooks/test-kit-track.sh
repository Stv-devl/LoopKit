#!/usr/bin/env bash
# KT (local-kit-tracks): kit-track.py fork|close on a project that git-ignores the kit.
# Each fixture is a fresh repo whose .gitignore keeps the kit, the root kit files and
# the loop docs/ folders local; its .claude/ is a copy of this repo's kit plus fake
# runtime, session and secret files that must never reach a worktree.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$HOOKS_DIR/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'chmod -R u+w "$SCRATCH" 2>/dev/null; rm -r "$SCRATCH"' EXIT
CASES=0
FAILS=0

fail() {
    FAILS=$((FAILS + 1))
    echo "FAIL $1: $2" >&2
}

case_start() {
    CASES=$((CASES + 1))
}

GITIGNORE='.claude/
CLAUDE.md
AGENTS.md
PRODUCT.md
DESIGN.md
workflow.py
workflow.sh
codex-handoff.sh
docs/stories/
docs/prd/
docs/architecture/
docs/product/
docs/work/
docs/specs/
docs/research-cache/
docs/design-system*
.env*
*.pem
*.key
credentials.*'

OVERLAY='# Overlay — guides/10-worktrees.md

## foundations

- src/shared/

## local-kit-env

export DWG2DXF_PATH=/opt/libredwg/bin/dwg2dxf
COMPOSE_PROJECT_NAME=ecocrew-<slug>

## Local rules
'

# mkrepo <dir>: a kit-local project on branch main, committed and clean.
mkrepo() {
    local root="$1"
    mkdir -p "$root"
    git -C "$root" init -q -b main
    git -C "$root" config user.email kt@example.invalid
    git -C "$root" config user.name kt
    git -C "$root" config core.hooksPath /dev/null
    printf '%s\n' "$GITIGNORE" > "$root/.gitignore"
    mkdir -p "$root/src"
    printf 'tracked\n' > "$root/src/a.txt"
    mkdir -p "$root/.claude/overlays/guides"
    cp -r "$KIT_DIR/hooks" "$KIT_DIR/scripts" "$root/.claude/"
    cp "$KIT_DIR/settings.json" "$KIT_DIR/project.json" "$KIT_DIR/VERSION" "$KIT_DIR/workflow-routing.yml" "$root/.claude/"
    printf 'core\n' > "$root/.claude/INSTALL_PROFILE"
    printf 'commands/loop/tracks.md\n' > "$root/.claude/kit-manifest"
    printf '%s' "$OVERLAY" > "$root/.claude/overlays/guides/10-worktrees.md"
    # runtime, session and secret files: never copied
    mkdir -p "$root/.claude/worktrees/old" "$root/.claude/kit-backup" "$root/.claude/.tdd-red" "$root/.claude/hooks/__pycache__"
    printf 'x\n' > "$root/.claude/worktrees/old/x"
    printf 'x\n' > "$root/.claude/kit-backup/x"
    printf 'x\n' > "$root/.claude/.tdd-red/m"
    printf 'x\n' > "$root/.claude/hooks/__pycache__/m.cpython-312.pyc"
    local f
    for f in .tdd-unfrozen .loop-record.json .loop-record.lock .token-warning .token-delegate .token-stop-agents \
             .restart-ready .codex-ready .quota-warning .kit-health.jsonl .hook-timings.log .eslint-queue \
             .eslint-queue.1 settings.local.json; do
        printf 'runtime\n' > "$root/.claude/$f"
    done
    printf 'claude\n' > "$root/CLAUDE.md"
    printf 'agents\n' > "$root/AGENTS.md"
    printf 'print(1)\n' > "$root/workflow.py"
    printf '#!/bin/sh\n' > "$root/workflow.sh"
    printf '#!/bin/sh\n' > "$root/codex-handoff.sh"
    for f in .env .env.local x.pem x.key credentials.json; do
        printf 'SECRET=1\n' > "$root/$f"
    done
    mkdir -p "$root/docs/stories/demo" "$root/docs/stories/agent-ia" "$root/docs/research-cache" \
             "$root/docs/product" "$root/docs/work/old" "$root/.claude/certs"
    for f in .claude/.env .claude/x.key .claude/certs/x.pem docs/work/old/credentials.json docs/work/old/.env.local; do
        printf 'SECRET=1\n' > "$root/$f"
    done
    printf 'Status: Approved\n' > "$root/docs/stories/demo/1.1.md"
    printf 'Status: Approved\n' > "$root/docs/stories/agent-ia/3.7.md"
    printf 'settled\n' > "$root/docs/research-cache/settled.md"
    printf '| board |\n' > "$root/docs/product/backlog.md"
    printf 'old research\n' > "$root/docs/work/old/research.md"
    for f in handoff.md codex-last-message.txt pr-body.md; do
        printf 'session\n' > "$root/docs/work/old/$f"
    done
    git -C "$root" add .gitignore src/a.txt
    git -C "$root" commit -q -m init
}

# run_kt <root> <args...>: runs the script from <root>; sets OUT, ERR, CODE.
run_kt() {
    local root="$1"
    shift
    OUT="$(cd "$root" && python3 .claude/scripts/kit-track.py "$@" 2>"$SCRATCH/err")"
    CODE=$?
    ERR="$(cat "$SCRATCH/err")"
}

no_fork() {
    local root="$1" id="$2"
    [[ ! -e "$root/.claude/worktrees/demo-1.1" ]] || fail "$id" "a worktree was created"
    ! git -C "$root" rev-parse -q --verify refs/heads/feat/demo-1.1 >/dev/null || fail "$id" "a branch was created"
}

# ---------------------------------------------------------------- fork
R="$SCRATCH/main"
mkrepo "$R"
run_kt "$R" fork demo-1.1
FORK_OUT="$OUT"
WT="$R/.claude/worktrees/demo-1.1"

case_start  # KT1
if [[ "$CODE" -ne 0 ]]; then
    fail KT1 "fork exited $CODE: $ERR"
else
    git -C "$R" worktree list --porcelain | grep -Fqx "worktree $WT" || fail KT1 "worktree not registered"
    [[ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" == feat/demo-1.1 ]] || fail KT1 "worktree not on feat/demo-1.1"
    [[ "$(git -C "$R" rev-parse feat/demo-1.1)" == "$(git -C "$R" rev-parse main)" ]] || fail KT1 "start point is not main"
fi

case_start  # KT2
for f in .claude/hooks/enforce-git-workflow.sh .claude/project.json .claude/INSTALL_PROFILE .claude/kit-manifest \
         .claude/overlays/guides/10-worktrees.md CLAUDE.md AGENTS.md workflow.py workflow.sh codex-handoff.sh \
         docs/stories/demo/1.1.md docs/research-cache/settled.md; do
    cmp -s "$R/$f" "$WT/$f" || fail KT2 "$f missing or different in the worktree"
    [[ ! -L "$WT/$f" ]] || fail KT2 "$f is a symlink"
done

case_start  # KT3
[[ -d "$WT" && -z "$(git -C "$WT" status --porcelain 2>&1)" ]] || fail KT3 "worktree status not clean: $(git -C "$WT" status --porcelain 2>&1 | head -3)"

case_start  # KT4
if [[ -f "$WT/.claude/settings.json" ]]; then
    PF_CMD="$(jq -r '[.. | objects | select(has("command")) | .command | select(test("protect-files"))][0]' "$WT/.claude/settings.json")"
    PF_OUT="$(jq -cn --arg f "$WT/.env" --arg c "$WT" '{tool_name:"Read", cwd:$c, tool_input:{file_path:$f}}' \
        | CLAUDE_PROJECT_DIR="$WT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 bash -c "$PF_CMD" 2>&1)"
    [[ "$PF_OUT" == *"names environment secrets"* ]] || fail KT4 "worktree hook did not deny .env by its own rule: ${PF_OUT:0:200}"
else
    fail KT4 "no settings.json in the worktree"
fi

case_start  # KT5
SNAP="$WT/.claude/.kit-snapshot"
if [[ -f "$SNAP" ]]; then
    jq -e --arg sha "$(git -C "$R" rev-parse main)" '.slug == "demo-1.1" and .base == "main" and .base_sha == $sha' "$SNAP" >/dev/null \
        || fail KT5 "snapshot header wrong"
    for f in CLAUDE.md .claude/project.json docs/stories/demo/1.1.md; do
        want="$(sha256sum "$R/$f" | cut -d' ' -f1)"
        jq -e --arg f "$f" --arg h "$want" '.files[$f] == $h' "$SNAP" >/dev/null || fail KT5 "snapshot hash for $f"
    done
else
    fail KT5 "no .kit-snapshot"
fi

case_start  # KT6
for want in '.env' 'install' 'cd .claude/worktrees/demo-1.1 && ./workflow.sh' \
            'export DWG2DXF_PATH=/opt/libredwg/bin/dwg2dxf' 'COMPOSE_PROJECT_NAME=ecocrew-<slug>'; do
    [[ "$FORK_OUT" == *"$want"* ]] || fail KT6 "hand-over lacks: $want"
done

case_start  # KT7
for f in .claude/worktrees .claude/kit-backup .claude/.tdd-red .claude/hooks/__pycache__ .claude/.tdd-unfrozen \
         .claude/.loop-record.json .claude/.loop-record.lock .claude/.token-warning .claude/.token-delegate \
         .claude/.token-stop-agents .claude/.restart-ready .claude/.codex-ready .claude/.quota-warning \
         .claude/.kit-health.jsonl .claude/.hook-timings.log .claude/.eslint-queue .claude/.eslint-queue.1 \
         .claude/settings.local.json docs/work/old/handoff.md docs/work/old/codex-last-message.txt \
         docs/work/old/pr-body.md .env .env.local x.pem x.key credentials.json; do
    [[ ! -e "$WT/$f" ]] || fail KT7 "$f was copied"
done
[[ -f "$WT/docs/work/old/research.md" ]] || fail KT7 "docs/work/old/research.md (not a session file) was not copied"

case_start  # KT7.2
for f in .claude/.env .claude/x.key .claude/certs/x.pem docs/work/old/credentials.json docs/work/old/.env.local; do
    [[ -f "$R/$f" ]] || fail KT7.2 "fixture lacks $f"
    [[ ! -e "$WT/$f" ]] || fail KT7.2 "$f was copied"
done

case_start  # KT8
R8="$SCRATCH/kt8"
mkrepo "$R8"
git -C "$R8" add -f .claude/hooks/hook-lib.sh
git -C "$R8" commit -q -m tracked-kit
run_kt "$R8" fork demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"not kit-local"* ]] || fail KT8 "expected refusal 'not kit-local', got $CODE: $ERR"
no_fork "$R8" KT8

case_start  # KT9
R9="$SCRATCH/kt9"
mkrepo "$R9"
printf 'dirty\n' >> "$R9/src/a.txt"
run_kt "$R9" fork demo-1.1
[[ "$CODE" -eq 2 ]] || fail KT9 "dirty tree not refused ($CODE)"
no_fork "$R9" KT9

case_start  # KT10
R10="$SCRATCH/kt10"
mkrepo "$R10"
git -C "$R10" branch feat/demo-1.1
run_kt "$R10" fork demo-1.1
[[ "$CODE" -eq 2 && ! -e "$R10/.claude/worktrees/demo-1.1" ]] || fail KT10 "existing branch not refused ($CODE)"
git -C "$R10" branch -D -q feat/demo-1.1
mkdir -p "$R10/.claude/worktrees/demo-1.1"
printf 'keep\n' > "$R10/.claude/worktrees/demo-1.1/keep"
run_kt "$R10" fork demo-1.1
[[ "$CODE" -eq 2 ]] || fail KT10 "existing path not refused ($CODE)"
[[ "$(cat "$R10/.claude/worktrees/demo-1.1/keep")" == keep ]] || fail KT10 "existing path touched"
! git -C "$R10" rev-parse -q --verify refs/heads/feat/demo-1.1 >/dev/null || fail KT10 "branch created over an existing path"

case_start  # KT11
R11="$SCRATCH/kt11"
mkrepo "$R11"
for slug in '../x' 'A B' '-x' ''; do
    run_kt "$R11" fork "$slug"
    [[ "$CODE" -eq 2 ]] || fail KT11 "slug '$slug' not refused ($CODE)"
done
[[ "$(git -C "$R11" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]] || fail KT11 "a worktree was created"

case_start  # KT12
R12="$SCRATCH/kt12"
mkrepo "$R12"
ln -s hook-lib.sh "$R12/.claude/hooks/link.sh"
run_kt "$R12" fork demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *".claude/hooks/link.sh"* ]] || fail KT12 "symlink not refused by name ($CODE): $ERR"
no_fork "$R12" KT12

case_start  # KT13
R13="$SCRATCH/kt13"
mkrepo "$R13"
OUT="$(cd "$R13/src" && python3 ../.claude/scripts/kit-track.py fork demo-1.1 2>&1)"
CODE=$?
[[ "$CODE" -eq 2 ]] || fail KT13 "run from a subfolder not refused ($CODE)"
no_fork "$R13" KT13

# ---------------------------------------------------------------- close
# close_fixture <dir> [merge]: a fork of demo-1.1 whose track commits src/b.txt and
# writes its own docs; merged with --ff-only into main unless the second arg is "nomerge".
close_fixture() {
    local root="$1" merge="${2:-merge}" wt
    mkrepo "$root"
    (cd "$root" && python3 .claude/scripts/kit-track.py fork demo-1.1 >/dev/null 2>&1)
    wt="$root/.claude/worktrees/demo-1.1"
    printf 'feature\n' > "$wt/src/b.txt"
    git -C "$wt" add src/b.txt
    git -C "$wt" commit -q -m feature
    mkdir -p "$wt/docs/work/demo-1.1"
    printf 'track research\n' > "$wt/docs/work/demo-1.1/research.md"
    printf -- '---\nphase: awaiting-merge\n---\n' > "$wt/docs/work/demo-1.1/handoff.md"
    printf 'Status: InProgress\nDev Agent Record\n' > "$wt/docs/stories/demo/1.1.md"
    printf 'new topic\n' > "$wt/docs/research-cache/x.md"
    [[ "$merge" == nomerge ]] || git -C "$root" merge -q --ff-only feat/demo-1.1
}

registered() {
    git -C "$1" worktree list --porcelain | grep -Fqx "worktree $1/.claude/worktrees/demo-1.1"
}

RA="$SCRATCH/close-a"
close_fixture "$RA"
WA="$RA/.claude/worktrees/demo-1.1"
printf 'track overlay edit\n' >> "$WA/.claude/overlays/guides/10-worktrees.md"
printf '9.9.9\n' > "$RA/.claude/VERSION"
printf 'track settled edit\n' >> "$WA/docs/research-cache/settled.md"
printf '| board edited in track |\n' > "$WA/docs/product/backlog.md"
run_kt "$RA" close demo-1.1
CLOSE_OUT="$OUT"

case_start  # KT14
[[ "$CODE" -eq 0 ]] || fail KT14 "close exited $CODE: $ERR"
[[ "$(cat "$RA/docs/work/demo-1.1/research.md" 2>/dev/null)" == 'track research' ]] || fail KT14 "research.md not copied back"
grep -Fq 'phase: awaiting-merge' "$RA/docs/work/demo-1.1/handoff.md" 2>/dev/null || fail KT14 "handoff.md not copied back"
! registered "$RA" || fail KT14 "worktree still registered"
[[ ! -e "$WA" ]] || fail KT14 "worktree still on disk"
git -C "$RA" rev-parse -q --verify refs/heads/feat/demo-1.1 >/dev/null || fail KT14 "branch deleted by close"

case_start  # KT15
[[ "$(cat "$RA/docs/stories/demo/1.1.md")" == $'Status: InProgress\nDev Agent Record' ]] || fail KT15 "story not copied back"

case_start  # KT16
[[ "$(cat "$RA/docs/research-cache/x.md" 2>/dev/null)" == 'new topic' ]] || fail KT16 "new research-cache file not copied back"

case_start  # KT17
[[ "$CLOSE_OUT" == *"kit drift track-changed .claude/overlays/guides/10-worktrees.md"* ]] || fail KT17 "track drift not reported"
[[ "$CLOSE_OUT" == *"kit drift main-changed .claude/VERSION"* ]] || fail KT17 "main drift not reported"
grep -Fq 'COMPOSE_PROJECT_NAME=ecocrew-<slug>' "$RA/.claude/overlays/guides/10-worktrees.md" \
    && ! grep -Fq 'track overlay edit' "$RA/.claude/overlays/guides/10-worktrees.md" || fail KT17 "main overlay overwritten"
[[ "$(cat "$RA/.claude/VERSION")" == 9.9.9 ]] || fail KT17 "main VERSION overwritten"

case_start  # KT19
[[ "$(cat "$RA/docs/research-cache/settled.md")" == settled ]] || fail KT19 "main settled.md overwritten"
[[ "$CLOSE_OUT" == *"research-cache modified docs/research-cache/settled.md"* ]] || fail KT19 "modification not reported"
grep -Fq 'track settled edit' "$RA/docs/research-cache/settled.md.from-demo-1.1" 2>/dev/null || fail KT19 "no sidecar"

case_start  # KT20
[[ "$(cat "$RA/docs/product/backlog.md")" == '| board |' ]] || fail KT20 "board copied back"
[[ "$CLOSE_OUT" == *"snapshot change ignored docs/product/backlog.md"* ]] || fail KT20 "snapshot change not reported"

case_start  # KT15 (hyphenated feature: the story derives from the last hyphen)
RH="$SCRATCH/close-h"
mkrepo "$RH"
(cd "$RH" && python3 .claude/scripts/kit-track.py fork agent-ia-3.7 >/dev/null 2>&1)
printf 'Status: InProgress\n' > "$RH/.claude/worktrees/agent-ia-3.7/docs/stories/agent-ia/3.7.md"
run_kt "$RH" close agent-ia-3.7
[[ "$CODE" -eq 0 && "$(cat "$RH/docs/stories/agent-ia/3.7.md")" == 'Status: InProgress' ]] \
    || fail KT15 "agent-ia-3.7 story not copied back ($CODE): $ERR"

case_start  # KT18
RB="$SCRATCH/close-b"
close_fixture "$RB"
printf 'Status: Done\n' > "$RB/docs/stories/demo/1.1.md"
run_kt "$RB" close demo-1.1
[[ "$(cat "$RB/docs/stories/demo/1.1.md")" == 'Status: Done' ]] || fail KT18 "main story overwritten"
grep -Fq 'Dev Agent Record' "$RB/docs/stories/demo/1.1.md.from-demo-1.1" 2>/dev/null || fail KT18 "no sidecar"
[[ "$OUT" == *"conflict docs/stories/demo/1.1.md"* ]] || fail KT18 "conflict not reported"

case_start  # KT21
RC="$SCRATCH/close-c"
close_fixture "$RC"
printf 'uncommitted\n' >> "$RC/.claude/worktrees/demo-1.1/src/a.txt"
run_kt "$RC" close demo-1.1
[[ "$CODE" -eq 2 ]] || fail KT21 "dirty worktree not refused ($CODE)"
[[ ! -e "$RC/docs/work/demo-1.1" && "$(cat "$RC/docs/stories/demo/1.1.md")" == 'Status: Approved' ]] || fail KT21 "main changed"
registered "$RC" && grep -Fq uncommitted "$RC/.claude/worktrees/demo-1.1/src/a.txt" || fail KT21 "worktree not intact"

case_start  # KT22
RD="$SCRATCH/close-d"
close_fixture "$RD" nomerge
run_kt "$RD" close demo-1.1
[[ "$CODE" -eq 2 ]] && registered "$RD" && [[ ! -e "$RD/docs/work/demo-1.1" ]] || fail KT22 "unmerged branch not refused ($CODE)"
run_kt "$RD" close demo-1.1 --merged
[[ "$CODE" -eq 0 && -f "$RD/docs/work/demo-1.1/research.md" ]] && ! registered "$RD" || fail KT22 "--merged did not complete ($CODE): $ERR"

case_start  # KT24
RE="$SCRATCH/close-e"
close_fixture "$RE"
mkdir -p "$RE/docs/work"
printf 'in the way\n' > "$RE/docs/work/demo-1.1"
run_kt "$RE" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"docs/work/demo-1.1"* ]] || fail KT24 "blocked copy-back not refused by name ($CODE): $ERR"
registered "$RE" && [[ -f "$RE/.claude/worktrees/demo-1.1/docs/work/demo-1.1/research.md" ]] || fail KT24 "worktree not intact"
git -C "$RE" rev-parse -q --verify refs/heads/feat/demo-1.1 >/dev/null || fail KT24 "branch touched"

case_start  # KT25
RF="$SCRATCH/close-f"
close_fixture "$RF"
git -C "$RF" add -f docs/stories/demo/1.1.md
git -C "$RF" commit -q -m track-story
run_kt "$RF" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"docs/stories/demo/1.1.md"* ]] || fail KT25 "tracked destination not refused ($CODE): $ERR"
[[ ! -e "$RF/docs/work/demo-1.1" ]] && registered "$RF" || fail KT25 "copy-back or removal happened"

case_start  # KT23
RG="$SCRATCH/close-g"
mkrepo "$RG"
run_kt "$RG" close nope-1.1
[[ "$CODE" -eq 2 ]] || fail KT23 "unknown slug not refused ($CODE)"
mkdir -p "$RG/.claude/worktrees/ghost-1.1"
printf 'keep\n' > "$RG/.claude/worktrees/ghost-1.1/keep"
run_kt "$RG" close ghost-1.1
[[ "$CODE" -eq 2 && -f "$RG/.claude/worktrees/ghost-1.1/keep" ]] || fail KT23 "unregistered directory not refused ($CODE)"

case_start  # KT26
RS="$SCRATCH/close-s"
close_fixture "$RS"
for f in .env x.pem x.key credentials.json; do
    printf 'SECRET=1\n' > "$RS/.claude/worktrees/demo-1.1/docs/work/demo-1.1/$f"
done
run_kt "$RS" close demo-1.1
[[ "$CODE" -eq 0 ]] || fail KT26 "close exited $CODE: $ERR"
for f in .env x.pem x.key credentials.json; do
    [[ ! -e "$RS/docs/work/demo-1.1/$f" ]] || fail KT26 "$f copied back into main"
    [[ "$OUT" != *"$f"* ]] || fail KT26 "$f named in the output"
done
[[ -f "$RS/docs/work/demo-1.1/handoff.md" ]] || fail KT26 "handoff.md not copied back"

case_start  # KT27
RL="$SCRATCH/close-l"
close_fixture "$RL"
mkdir -p "$SCRATCH/outside-l" "$RL/docs/work/demo-1.1"
printf 'outside\n' > "$SCRATCH/outside-l/target.txt"
ln -s "$SCRATCH/outside-l/target.txt" "$RL/docs/work/demo-1.1/notes.md"
printf 'track notes\n' > "$RL/.claude/worktrees/demo-1.1/docs/work/demo-1.1/notes.md"
run_kt "$RL" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"docs/work/demo-1.1/notes.md"* ]] || fail KT27 "symlink destination not refused by name ($CODE): $ERR"
[[ "$(cat "$SCRATCH/outside-l/target.txt")" == outside ]] || fail KT27 "outside target changed"
registered "$RL" && [[ -d "$RL/.claude/worktrees/demo-1.1" ]] || fail KT27 "worktree not intact"

case_start  # KT28
RM="$SCRATCH/close-m"
close_fixture "$RM"
mkdir -p "$SCRATCH/outside-m"
printf 'outside\n' > "$SCRATCH/outside-m/keep.txt"
ln -s "$SCRATCH/outside-m" "$RM/docs/work/demo-1.1"
run_kt "$RM" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"docs/work/demo-1.1"* ]] || fail KT28 "symlinked parent not refused by name ($CODE): $ERR"
[[ "$(ls "$SCRATCH/outside-m")" == keep.txt ]] || fail KT28 "outside directory changed: $(ls "$SCRATCH/outside-m")"
registered "$RM" && [[ -d "$RM/.claude/worktrees/demo-1.1" ]] || fail KT28 "worktree not intact"

case_start  # KT29
RN="$SCRATCH/close-n"
close_fixture "$RN"
mkdir -p "$RN/docs/work/demo-1.1"
printf 'main research\n' > "$RN/docs/work/demo-1.1/research.md"
run_kt "$RN" close demo-1.1
[[ "$(cat "$RN/docs/work/demo-1.1/research.md")" == 'main research' ]] || fail KT29 "main research.md overwritten"
[[ "$(cat "$RN/docs/work/demo-1.1/research.md.from-demo-1.1" 2>/dev/null)" == 'track research' ]] || fail KT29 "no sidecar with the track's content"
[[ "$OUT" == *"conflict docs/work/demo-1.1/research.md"* ]] || fail KT29 "conflict not reported"

# ---------------------------------------------------------------- kit-track-robustness
case_start  # KT30 a fork that fails after `git worktree add` rolls back; a second fork works
R30="$SCRATCH/kt30"
mkrepo "$R30"
chmod 000 "$R30/.claude/hooks/hook-lib.sh"
run_kt "$R30" fork demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"fork failed after the worktree was created"* ]] \
    || fail KT30 "expected the rollback refusal, got $CODE: ${ERR:0:300}"
[[ "$ERR" != *Traceback* ]] || fail KT30 "traceback"
no_fork "$R30" KT30
chmod 644 "$R30/.claude/hooks/hook-lib.sh"
run_kt "$R30" fork demo-1.1
[[ "$CODE" -eq 0 ]] || fail KT30 "second fork exited $CODE: $ERR"

case_start  # KT31 a tracked CLAUDE.md -> AGENTS.md link does not block the fork
R31="$SCRATCH/kt31"
mkrepo "$R31"
mv "$R31/CLAUDE.md" "$SCRATCH/kt31-claude.md"
ln -s AGENTS.md "$R31/CLAUDE.md"
git -C "$R31" add -f CLAUDE.md
git -C "$R31" commit -q -m link
run_kt "$R31" fork demo-1.1
[[ "$CODE" -eq 0 && -f "$R31/.claude/worktrees/demo-1.1/.claude/.kit-snapshot" ]] \
    || fail KT31 "fork with a tracked CLAUDE.md link exited $CODE: $ERR"

case_start  # KT32 a symlinked skipped name does not block the fork
R32="$SCRATCH/kt32"
mkrepo "$R32"
printf 'outside\n' > "$SCRATCH/kt32-local.json"
mv "$R32/.claude/settings.local.json" "$SCRATCH/kt32-old.json"
ln -s "$SCRATCH/kt32-local.json" "$R32/.claude/settings.local.json"
run_kt "$R32" fork demo-1.1
[[ "$CODE" -eq 0 ]] || fail KT32 "symlinked settings.local.json blocked the fork ($CODE): $ERR"

case_start  # KT33 (pin) a symlink inside what is copied is still refused
R33="$SCRATCH/kt33"
mkrepo "$R33"
printf 'outside\n' > "$SCRATCH/kt33-evil.sh"
ln -s "$SCRATCH/kt33-evil.sh" "$R33/.claude/hooks/evil.sh"
run_kt "$R33" fork demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *".claude/hooks/evil.sh"* ]] || fail KT33 "copied symlink not refused by name ($CODE): $ERR"
no_fork "$R33" KT33

case_start  # KT34 a .kit-snapshot that is not JSON: one-line refusal, nothing written
R34="$SCRATCH/kt34"
close_fixture "$R34"
printf 'not json\n' > "$R34/.claude/worktrees/demo-1.1/.claude/.kit-snapshot"
run_kt "$R34" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"malformed .kit-snapshot"* ]] || fail KT34 "expected malformed refusal ($CODE): ${ERR:0:300}"
[[ "$ERR" != *Traceback* ]] || fail KT34 "traceback"
[[ ! -e "$R34/docs/work/demo-1.1" && "$(cat "$R34/docs/stories/demo/1.1.md")" == 'Status: Approved' ]] || fail KT34 "main written"
registered "$R34" || fail KT34 "worktree removed"

case_start  # KT35 a .kit-snapshot whose files map to a non-hex value is refused
R35="$SCRATCH/kt35"
close_fixture "$R35"
S35="$R35/.claude/worktrees/demo-1.1/.claude/.kit-snapshot"
jq '.files |= with_entries(.value = "nothex")' "$S35" > "$SCRATCH/kt35-snap" && cp "$SCRATCH/kt35-snap" "$S35"
run_kt "$R35" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"malformed .kit-snapshot"* ]] || fail KT35 "non-hex snapshot not refused ($CODE): ${ERR:0:300}"
[[ ! -e "$R35/docs/work/demo-1.1" ]] || fail KT35 "main written"

case_start  # KT37 an interrupted copy-back reports what landed; the rerun finishes
R37="$SCRATCH/kt37"
close_fixture "$R37"
chmod 555 "$R37/docs/research-cache"
run_kt "$R37" close demo-1.1
OUT37="$OUT"
[[ "$CODE" -eq 2 ]] || fail KT37 "interrupted copy-back exited $CODE"
for f in docs/work/demo-1.1/handoff.md docs/work/demo-1.1/research.md docs/stories/demo/1.1.md; do
    [[ "$OUT37" == *"copied $f"* ]] || fail KT37 "landed copy not reported: $f"
done
[[ "$OUT37" != *"copied docs/research-cache/x.md"* ]] || fail KT37 "the failed copy was reported as landed"
[[ "$ERR" == *"docs/research-cache/x.md"* && "$ERR" == *"earlier copies landed"* ]] || fail KT37 "refusal lacks the file or the landed note: ${ERR:0:300}"
chmod 755 "$R37/docs/research-cache"
run_kt "$R37" close demo-1.1
[[ "$CODE" -eq 0 && "$OUT" == *"copied docs/research-cache/x.md"* ]] || fail KT37 "rerun did not finish ($CODE): $OUT $ERR"

case_start  # KT38 runtime files are neither copied nor in the snapshot
R38="$SCRATCH/kt38"
mkrepo "$R38"
mkdir -p "$R38/.claude/.ruff_cache"
for f in .claude/project.proposed.json .claude/project.snapshot.json .claude/.ruff_cache/x .claude/.loop-record.abc.tmp; do
    printf 'runtime\n' > "$R38/$f"
done
run_kt "$R38" fork demo-1.1
[[ "$CODE" -eq 0 ]] || fail KT38 "fork exited $CODE: $ERR"
for f in .claude/project.proposed.json .claude/project.snapshot.json .claude/.ruff_cache/x .claude/.loop-record.abc.tmp; do
    [[ ! -e "$R38/.claude/worktrees/demo-1.1/$f" ]] || fail KT38 "$f was copied"
    jq -e --arg f "$f" '.files | has($f) | not' "$R38/.claude/worktrees/demo-1.1/.claude/.kit-snapshot" >/dev/null 2>&1 \
        || fail KT38 "$f in the snapshot"
done

case_start  # KT39 (pin) a detached HEAD is refused
R39="$SCRATCH/kt39"
mkrepo "$R39"
git -C "$R39" checkout -q --detach
run_kt "$R39" fork demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *detached* ]] || fail KT39 "detached HEAD not refused ($CODE): $ERR"
no_fork "$R39" KT39

case_start  # KT40 (pin) fork from inside a worktree is refused
run_kt "$WT" fork demo-1.2
[[ "$CODE" -eq 2 && "$ERR" == *"run from the main tree"* ]] || fail KT40 "fork from a worktree not refused ($CODE): $ERR"
[[ ! -e "$R/.claude/worktrees/demo-1.2" && ! -e "$WT/.claude/worktrees/demo-1.2" ]] || fail KT40 "a worktree was created"

case_start  # KT41 (pin) close on a worktree whose snapshot was deleted
R41="$SCRATCH/kt41"
close_fixture "$R41"
mv "$R41/.claude/worktrees/demo-1.1/.claude/.kit-snapshot" "$SCRATCH/kt41-snap"
run_kt "$R41" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"has no .claude/.kit-snapshot"* ]] || fail KT41 "missing snapshot not refused ($CODE): $ERR"
[[ ! -e "$R41/docs/work/demo-1.1" ]] || fail KT41 "main written"

case_start  # KT42 (pin) a failed `git worktree remove` is refused after the reported copies
R42="$SCRATCH/kt42"
close_fixture "$R42"
git -C "$R42" worktree lock .claude/worktrees/demo-1.1
run_kt "$R42" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"rerun close once it is clean"* ]] || fail KT42 "locked removal not refused ($CODE): $ERR"
[[ "$OUT" == *"copied docs/work/demo-1.1/research.md"* ]] || fail KT42 "landed copies not reported"
git -C "$R42" worktree unlock .claude/worktrees/demo-1.1

case_start  # KT43 (pin) a conflict close exits 0
R43="$SCRATCH/kt43"
close_fixture "$R43"
printf 'Status: Done\n' > "$R43/docs/stories/demo/1.1.md"
run_kt "$R43" close demo-1.1
[[ "$CODE" -eq 0 && "$OUT" == *"conflict docs/stories/demo/1.1.md"* ]] || fail KT43 "conflict close exited $CODE: $ERR"

case_start  # KT44 (pin) KT27/KT28 refusals: named as symlinks, main untouched
R44="$SCRATCH/kt44a"
close_fixture "$R44"
mkdir -p "$SCRATCH/outside-44a" "$R44/docs/work/demo-1.1"
printf 'outside\n' > "$SCRATCH/outside-44a/target.txt"
ln -s "$SCRATCH/outside-44a/target.txt" "$R44/docs/work/demo-1.1/notes.md"
printf 'track notes\n' > "$R44/.claude/worktrees/demo-1.1/docs/work/demo-1.1/notes.md"
run_kt "$R44" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *symlink* && "$ERR" == *"docs/work/demo-1.1/notes.md"* ]] || fail KT44 "KT27 refusal ($CODE): $ERR"
[[ ! -e "$R44/docs/work/demo-1.1/research.md" ]] || fail KT44 "KT27: research.md written in main"
R44B="$SCRATCH/kt44b"
close_fixture "$R44B"
mkdir -p "$SCRATCH/outside-44b"
ln -s "$SCRATCH/outside-44b" "$R44B/docs/work/demo-1.1"
run_kt "$R44B" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *symlink* ]] || fail KT44 "KT28 refusal ($CODE): $ERR"
[[ "$(cat "$R44B/docs/stories/demo/1.1.md")" == 'Status: Approved' && ! -e "$R44B/docs/research-cache/x.md" ]] \
    || fail KT44 "KT28: main written"

case_start  # KT45 (pin) a symlinked track session doc is refused on close
R45="$SCRATCH/kt45"
close_fixture "$R45"
printf 'outside\n' > "$SCRATCH/kt45-target.md"
mv "$R45/.claude/worktrees/demo-1.1/docs/work/demo-1.1/handoff.md" "$SCRATCH/kt45-handoff.md"
ln -s "$SCRATCH/kt45-target.md" "$R45/.claude/worktrees/demo-1.1/docs/work/demo-1.1/handoff.md"
run_kt "$R45" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"docs/work/demo-1.1/handoff.md"* ]] || fail KT45 "symlinked session doc not refused ($CODE): $ERR"
[[ ! -e "$R45/docs/work/demo-1.1" ]] || fail KT45 "main written"

case_start  # KT46 a symlinked SKIP_DIR leaf does not block the fork
R46="$SCRATCH/kt46"
mkrepo "$R46"
mv "$R46/.claude/kit-backup" "$SCRATCH/outside-46"
ln -s "$SCRATCH/outside-46" "$R46/.claude/kit-backup"
run_kt "$R46" fork demo-1.1
[[ "$CODE" -eq 0 ]] || fail KT46 "symlinked kit-backup blocked the fork ($CODE): $ERR"

case_start  # KT47 (pin) a .kit-snapshot that is a JSON array is refused
R47="$SCRATCH/kt47"
close_fixture "$R47"
printf '[]\n' > "$R47/.claude/worktrees/demo-1.1/.claude/.kit-snapshot"
run_kt "$R47" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"malformed .kit-snapshot"* ]] || fail KT47 "array snapshot not refused ($CODE): ${ERR:0:300}"
[[ "$ERR" != *Traceback* ]] || fail KT47 "traceback"
[[ ! -e "$R47/docs/work/demo-1.1" && "$(cat "$R47/docs/stories/demo/1.1.md")" == 'Status: Approved' ]] || fail KT47 "main written"

case_start  # KT48 (pin) a .kit-snapshot whose `files` is not an object is refused
R48="$SCRATCH/kt48"
close_fixture "$R48"
printf '{"files":[]}\n' > "$R48/.claude/worktrees/demo-1.1/.claude/.kit-snapshot"
run_kt "$R48" close demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"malformed .kit-snapshot"* ]] || fail KT48 "array files not refused ($CODE): ${ERR:0:300}"
[[ "$ERR" != *Traceback* ]] || fail KT48 "traceback"
[[ ! -e "$R48/docs/work/demo-1.1" && "$(cat "$R48/docs/stories/demo/1.1.md")" == 'Status: Approved' ]] || fail KT48 "main written"

case_start  # KT49 (pin) a committed symlinked docs/stories top is refused on fork
R49="$SCRATCH/kt49"
mkrepo "$R49"
mkdir -p "$SCRATCH/outside-49"
rm -r "$R49/docs/stories"
ln -s "$SCRATCH/outside-49" "$R49/docs/stories"
git -C "$R49" add -f docs/stories
git -C "$R49" commit -q -m stories-link
run_kt "$R49" fork demo-1.1
[[ "$CODE" -eq 2 && "$ERR" == *"symlink in the kit: docs/stories"* ]] || fail KT49 "symlinked docs/stories not refused ($CODE): ${ERR:0:300}"
no_fork "$R49" KT49

case_start  # KT50 an unreadable track file is refused on close, nothing written
R50="$SCRATCH/kt50"
close_fixture "$R50"
if [[ "$(id -u)" -ne 0 ]]; then
    chmod 000 "$R50/.claude/worktrees/demo-1.1/docs/work/demo-1.1/research.md"
    run_kt "$R50" close demo-1.1
    chmod 644 "$R50/.claude/worktrees/demo-1.1/docs/work/demo-1.1/research.md"
    [[ "$CODE" -eq 2 && "$ERR" == *"cannot read docs/work/demo-1.1/research.md"* ]] || fail KT50 "unreadable file not refused ($CODE): ${ERR:0:300}"
    [[ "$ERR" != *Traceback* ]] || fail KT50 "traceback"
    [[ ! -e "$R50/docs/work/demo-1.1" && "$(cat "$R50/docs/stories/demo/1.1.md")" == 'Status: Approved' ]] || fail KT50 "main written"
    registered "$R50" || fail KT50 "worktree removed"
fi

if [[ "$FAILS" -gt 0 ]]; then
    echo "kit-track fixtures: $FAILS failure(s) over $CASES cases." >&2
    exit 1
fi
echo "kit-track fixtures: green ($CASES cases)."
