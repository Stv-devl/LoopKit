#!/usr/bin/env bash
# Replay the small-lane script fixtures on throwaway git repos.

set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$KIT/.claude/scripts"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
FAILURES=0
CASES=0
RUN_OUT=""
RUN_RC=0

fail() {
    printf 'FAIL %s / %s: %s\n' "$1" "$2" "$3" >&2
    FAILURES=$((FAILURES + 1))
}

run() {
    RUN_OUT="$("$@" 2>/dev/null)"
    RUN_RC=$?
}

expect() {
    local group="$1" case_id="$2" want_out="$3" want_rc="$4"
    CASES=$((CASES + 1))
    if [[ "$RUN_OUT" != "$want_out" || "$RUN_RC" -ne "$want_rc" ]]; then
        fail "$group" "$case_id" "want [$want_out] rc $want_rc, got [$RUN_OUT] rc $RUN_RC"
    fi
}

check() {
    local group="$1" case_id="$2" why="$3"
    shift 3
    CASES=$((CASES + 1))
    if ! "$@"; then
        fail "$group" "$case_id" "$why"
    fi
}

git_q() {
    git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1
}

make_fixture() {
    local dir
    dir="$(mktemp -d "$SCRATCH/repo.XXXXXX")"
    git_q -C "$dir" init -q -b main
    printf '.claude/worktrees/\n' >"$dir/.gitignore"
    printf '{ "name": "fixture" }\n' >"$dir/package.json"
    mkdir -p "$dir/src/features/a" "$dir/src/features/b" "$dir/src/lib"
    printf 'export const a = 1;\n' >"$dir/src/features/a/a.utils.ts"
    printf 'export const x = 1;\n' >"$dir/src/features/a/x.ts"
    printf 'export const b = 1;\n' >"$dir/src/features/b/b.utils.ts"
    printf 'export const lib = 1;\n' >"$dir/src/lib/x.ts"
    git_q -C "$dir" add -A
    git_q -C "$dir" commit -q -m base
    printf '%s' "$dir"
}

kit_variant() {
    local dir="$1" lib_sed="${2:-}" with_board="${3:-}"
    mkdir -p "$dir/.claude/scripts" "$dir/.claude/hooks"
    cp "$SCRIPTS"/*.sh "$dir/.claude/scripts/"
    if [[ -n "$lib_sed" ]]; then
        sed "$lib_sed" "$KIT/.claude/hooks/hook-lib.sh" >"$dir/.claude/hooks/hook-lib.sh"
    else
        cp "$KIT/.claude/hooks/hook-lib.sh" "$dir/.claude/hooks/"
    fi
    [[ -z "$with_board" ]] || cp "$KIT/.claude/hooks/next-feature-on-clear.py" "$dir/.claude/hooks/"
}

SELECTORS_SED='s/^CWK_TDD_LAYERS="repository|services|mapper|utils"/CWK_TDD_LAYERS="repository|services|mapper|utils|selectors"/'

group_paths() {
    local repo kit_copy path seven=() six=()
    repo="$(make_fixture)"
    cd "$repo" || return

    run "$SCRIPTS/small-paths.sh" src/features/a/a.utils.ts src/features/a/a.utils.test.ts
    expect small-paths P1 "ok" 0

    for path in package.json vite.config.ts .claude/hooks/x.sh docs/x.md CLAUDE.md pnpm-lock.yaml; do
        run "$SCRIPTS/small-paths.sh" "$path"
        expect small-paths "P2 $path" "outside small allowlist: $path" 1
    done

    kit_copy="$SCRATCH/kit-p3"
    mkdir -p "$kit_copy/.claude/scripts" "$kit_copy/.claude/hooks"
    sed 's|^FOUNDATIONS=(|FOUNDATIONS=( "src/features/core/*"|' "$SCRIPTS/small-paths.sh" >"$kit_copy/.claude/scripts/small-paths.sh"
    chmod +x "$kit_copy/.claude/scripts/small-paths.sh"
    [[ -f "$SCRIPTS/small-lib.sh" ]] && cp "$SCRIPTS/small-lib.sh" "$kit_copy/.claude/scripts/"
    cp "$KIT/.claude/hooks/hook-lib.sh" "$kit_copy/.claude/hooks/"
    for path in src/lib/x.ts src/routes/x.tsx src/main.tsx src/providers/x.tsx src/features/core/x.ts; do
        run "$kit_copy/.claude/scripts/small-paths.sh" "$path"
        expect small-paths "P3 $path" "foundation: $path" 1
    done

    for n in 1 2 3 4 5 6 7; do seven+=("src/features/a/f$n.ts"); done
    six=("${seven[@]:0:6}")
    run "$SCRIPTS/small-paths.sh" "${seven[@]}"
    expect small-paths "P4 seven" "more than 6 paths: 7" 1
    run "$SCRIPTS/small-paths.sh" "${six[@]}"
    expect small-paths "P4 six" "ok" 0

    repo="$(make_fixture)"
    cd "$repo" || return
    local before after replay_ok=1
    before="$(git status --porcelain --ignored; ls -a .claude 2>/dev/null)"
    run "$SCRIPTS/small-paths.sh" src/features/a/a.utils.ts
    [[ "$RUN_OUT" == "ok" ]] || replay_ok=0
    run "$SCRIPTS/small-paths.sh" package.json
    [[ "$RUN_OUT" == "outside small allowlist: package.json" ]] || replay_ok=0
    run "$kit_copy/.claude/scripts/small-paths.sh" src/lib/x.ts
    [[ "$RUN_OUT" == "foundation: src/lib/x.ts" ]] || replay_ok=0
    run "$SCRIPTS/small-paths.sh" "${seven[@]}"
    [[ "$RUN_OUT" == "more than 6 paths: 7" ]] || replay_ok=0
    after="$(git status --porcelain --ignored; ls -a .claude 2>/dev/null)"
    check small-paths P5 "a run changed the tree or did not answer" \
        test "$before" == "$after" -a "$replay_ok" -eq 1 -a ! -e .claude/.hook-timings.log -a ! -e "$kit_copy/.claude/.hook-timings.log"

    for path in src/../package.json /etc/passwd; do
        run "$SCRIPTS/small-paths.sh" "$path"
        expect small-paths "P6 $path" "outside small allowlist: $path" 1
    done

    for path in src/features//a.ts src/features/a/ src/features/a//; do
        run "$SCRIPTS/small-paths.sh" "$path"
        expect small-paths "P7 malformed $path" "outside small allowlist: $path" 1
    done
    for path in src/lib src/routes src/providers src/Lib/x.ts src/LIB/x.ts src/Main.tsx src/Routes/x.tsx src/Providers/x.tsx; do
        run "$SCRIPTS/small-paths.sh" "$path"
        expect small-paths "P7 foundation $path" "foundation: $path" 1
    done
    cd "$KIT" || return
}

write_small_spec() {
    local repo="$1" name="$2" base="$3" files="$4" blocks="$5"
    mkdir -p "$repo/docs/specs/small"
    {
        printf '# Small: %s ticket\nPipeline: small\nToken profile: economy\nBase: %s\n\n' "$name" "$base"
        printf '## Objective\nShow the %s card with its total.\n\n' "$name"
        printf '## Files\n%s\n\n' "$files"
        printf '## Contracts\n`total(items: Item[]): number`\n\n'
        printf '## Vigilance\n- the total ignores negative items\n\n'
        printf '## Done when\n- [ ] the card shows the total\n\n'
        printf '## Test cases\n%s\n\n' "$blocks"
        printf '## Verify\npnpm test:run\n'
    } >"$repo/docs/specs/small/$name.md"
}

has_line() {
    grep -Fxq -- "$1" "$2"
}

group_plan() {
    local repo sha plan files blocks ok
    repo="$(make_fixture)"
    cd "$repo" || return
    printf 'export const toA = 1;\n' >src/features/a/a.mapper.ts
    git_q add -A
    git_q commit -q -m mapper
    sha="$(git rev-parse HEAD)"
    files='- src/features/a/utils.ts
- src/features/a/utils.test.ts
- src/features/a/a.mapper.ts
- src/features/a/a.mapper.test.ts
- src/features/a/useA.ts
- src/features/a/useA.test.ts
- src/features/a/Card.tsx
- src/features/a/Card.test.tsx'
    blocks='#### src/features/a/utils.test.ts
- [ ] U1 total sums the item prices
- [ ] U2 total skips an item with a negative price

#### src/features/a/a.mapper.test.ts
- [ ] M1 toA maps a raw row to an Item

#### src/features/a/useA.test.ts
- [ ] useA returns the items once loaded

#### src/features/a/Card.test.tsx
- [ ] the card renders the total'
    write_small_spec "$repo" a "main $sha" "$files" "$blocks"
    run "$SCRIPTS/small-plan.sh" small-a
    plan="docs/work/small-a/plan.md"
    expect small-plan "Q1 exit" "plan: $plan" 0

    ok=1
    [[ -f "$plan" ]] || ok=0
    if [[ "$ok" -eq 1 ]]; then
        [[ "$(head -n1 "$plan")" == "# Plan: Show the a card with its total. (entry: docs/specs/small/a.md · research: inline (dispatch) · design: n/a)" ]] || ok=0
        [[ "$(sed -n 2p "$plan")" == "Pipeline: small" ]] || ok=0
        [[ "$(sed -n 3p "$plan")" == "Token profile: economy" ]] || ok=0
    fi
    check small-plan "Q1 header" "header lines differ" test "$ok" -eq 1

    ok=1
    for heading in '## Skips' '## Write chain' '## Parallel lots' '## Track isolation' '## Files' '## Contracts' \
        '## Test plan' '### Test-first' '### Test-after' '## Vigilance' '## Acceptance criteria' '## Plan critic' '## Gate'; do
        grep -q "^$heading" "$plan" 2>/dev/null || ok=0
    done
    check small-plan "Q1 sections" "a template section is missing" test "$ok" -eq 1

    ok=1
    sed -n '/^## Skips/,/^## /p' "$plan" 2>/dev/null | grep -qi 'interface' || ok=0
    sed -n '/^## Skips/,/^## /p' "$plan" 2>/dev/null | grep -qi 'plan-critic' || ok=0
    check small-plan "Q1 skips" "Skips does not name interface and plan-critic" test "$ok" -eq 1

    ok=1
    local chain
    chain="$(sed -n '/^## Write chain/,/^## Parallel/p' "$plan" 2>/dev/null)"
    for layer in utils mapper hooks components; do
        grep -Eq "^- ${layer}: src/" <<<"$chain" || ok=0
    done
    for layer in types schemas errors gateway repository store forms DB backend wiring; do
        grep -Eq "^- ${layer}: SKIP$" <<<"$chain" || ok=0
    done
    grep -q 'test\.ts' <<<"$chain" && ok=0
    check small-plan "Q1 write chain" "layers present/SKIP wrong, or a test file under a layer" test "$ok" -eq 1

    ok=1
    has_line '| `src/features/a/a.mapper.ts` | Edit | small ticket |' "$plan" 2>/dev/null || ok=0
    has_line '| `src/features/a/utils.ts` | Create | small ticket |' "$plan" 2>/dev/null || ok=0
    has_line '| `src/features/a/Card.test.tsx` | Create | small ticket |' "$plan" 2>/dev/null || ok=0
    check small-plan "Q1 files" "Create/Edit rows wrong" test "$ok" -eq 1

    ok=1
    local first after
    first="$(sed -n '/^### Test-first/,/^### Test-after/p' "$plan" 2>/dev/null)"
    after="$(sed -n '/^### Test-after/,/^## /p' "$plan" 2>/dev/null)"
    grep -Fxq -- '- [ ] U1 total sums the item prices' <<<"$first" || ok=0
    grep -Fxq -- '- [ ] U2 total skips an item with a negative price' <<<"$first" || ok=0
    grep -Fxq -- '- [ ] M1 toA maps a raw row to an Item' <<<"$first" || ok=0
    grep -Fxq -- '#### src/features/a/utils.test.ts' <<<"$first" || ok=0
    grep -Fxq -- '- [ ] useA returns the items once loaded' <<<"$after" || ok=0
    grep -Fxq -- '- [ ] the card renders the total' <<<"$after" || ok=0
    grep -Fxq -- '#### src/features/a/Card.test.tsx' <<<"$after" || ok=0
    grep -Fq 'useA returns' <<<"$first" && ok=0
    check small-plan "Q1 test plan" "blocks not verbatim under the right heading" test "$ok" -eq 1

    ok=1
    has_line 'Plan critic: skipped (small lane)' "$plan" 2>/dev/null || ok=0
    has_line '- surviving blockers: none' "$plan" 2>/dev/null || ok=0
    has_line '- Contract: as written' "$plan" 2>/dev/null || ok=0
    sed -n '/^## Acceptance criteria/,/^## /p' "$plan" 2>/dev/null | grep -Fxq -- '- [ ] the card shows the total' || ok=0
    sed -n '/^## Vigilance/,/^## /p' "$plan" 2>/dev/null | grep -Fxq -- '- the total ignores negative items' || ok=0
    check small-plan "Q1 tail" "critic, gate, criteria or vigilance lines wrong" test "$ok" -eq 1

    if [[ -f "$plan" ]]; then
        sed -i 's/^- \[ \] U1 total sums the item prices$/- [ ] U1 total adds the item prices/' "$plan"
    fi
    run "$SCRIPTS/small-plan.sh" --check small-a
    expect small-plan "Q2 reworded" "reworded: - [ ] U1 total sums the item prices" 1

    write_small_spec "$repo" b "main $sha" '- src/features/b/b.utils.ts
- src/features/b/b.utils.test.ts' '#### src/features/b/other.test.ts
- [ ] U1 something'
    run "$SCRIPTS/small-plan.sh" small-b
    expect small-plan "Q2 no block" "no block: src/features/b/b.utils.test.ts" 1

    write_small_spec "$repo" c "main $sha" '- src/features/a/data.json
- src/features/a/x.ts' ''
    run "$SCRIPTS/small-plan.sh" small-c
    check small-plan "Q3 unmapped" "unmapped path not listed" \
        grep -Fxq -- '- unmapped: src/features/a/data.json' docs/work/small-c/plan.md

    mkdir -p docs/work/other docs/specs
    printf 'keep\n' >docs/work/other/plan.md
    write_small_spec "$repo" other "main $sha" '- src/features/a/x.ts' ''
    cp docs/specs/small/other.md docs/specs/other.md
    run "$SCRIPTS/small-plan.sh" "small-/../other"
    check small-plan "Q4 invalid name" "an invalid name reached another plan: [$RUN_OUT] rc $RUN_RC" \
        test "$RUN_RC" -eq 2 -a -z "$RUN_OUT" -a "$(cat docs/work/other/plan.md)" == keep
    run "$SCRIPTS/small-plan.sh" --check "small-A_b"
    expect small-plan "Q4 invalid check" "" 2

    kit_variant "$SCRATCH/kit-q5" "$SELECTORS_SED"
    write_small_spec "$repo" d "main $sha" '- src/features/a/selectors.ts
- src/features/a/x.ts' ''
    run "$SCRATCH/kit-q5/.claude/scripts/small-plan.sh" small-d
    check small-plan "Q5 unknown layer kept" "a path of an unknown layer was dropped" \
        grep -Fxq -- '- unmapped: src/features/a/selectors.ts' docs/work/small-d/plan.md
    cd "$KIT" || return
}

fork_small() {
    local repo="$1" name="$2" wt files="" path
    shift 2
    wt="$repo/.claude/worktrees/small-$name"
    git_q -C "$repo" worktree add -q "$wt" -b "feat/small-$name"
    for path in "$@"; do files+="- $path"$'\n'; done
    write_small_spec "$wt" "$name" "$(git -C "$repo" branch --show-current) $(git -C "$repo" rev-parse HEAD)" "${files%$'\n'}" ''
    git_q -C "$wt" add "docs/specs/small/$name.md"
    git_q -C "$wt" commit -q -m "spec: small $name"
}

write_board() {
    local repo="$1" entry="$2" state="$3"
    mkdir -p "$repo/docs/product"
    printf '| Feature / story | Entry artifact | Pipeline | State | Shipped |\n| --- | --- | --- | --- | --- |\n| feature x | %s | light | %s | — |\n' \
        "$entry" "$state" >"$repo/docs/product/backlog.md"
}

dispatch() {
    run "$SCRIPTS/small-dispatch-check.sh" "$@"
}

group_dispatch() {
    local repo A=(src/features/a/a.utils.ts src/features/a/a.utils.test.ts) B=(src/features/b/b.utils.ts src/features/b/b.utils.test.ts)
    local C=(src/features/c/c.ts) D=(src/features/d/d.ts) clean

    repo="$(make_fixture)"; cd "$repo" || return
    dispatch a "${A[@]}"; expect dispatch "D1 a" "ok" 0
    fork_small "$repo" a "${A[@]}"
    clean="$(git status --porcelain)"
    check dispatch "D1 clean after a" "main tree dirty after fork: [$clean]" test -z "$clean"
    dispatch b "${B[@]}"; expect dispatch "D1 b" "ok" 0
    fork_small "$repo" b "${B[@]}"
    clean="$(git status --porcelain)"
    check dispatch "D1 clean after b" "main tree dirty after fork: [$clean]" test -z "$clean"

    repo="$(make_fixture)"; cd "$repo" || return
    fork_small "$repo" a "${A[@]}"
    dispatch b src/features/a/a.utils.ts src/features/a/a.utils.test.ts
    expect dispatch D2 "waits behind small-a: src/features/a/a.utils.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    fork_small "$repo" a "${A[@]}"
    git_q merge -q --ff-only feat/small-a
    dispatch b "${A[@]}"; expect dispatch "D3 merged blocks nothing" "ok" 0
    fork_small "$repo" c "${C[@]}"
    fork_small "$repo" d "${D[@]}"
    dispatch b "${A[@]}"; expect dispatch "D3 merged off the ceiling" "ok" 0

    repo="$(make_fixture)"; cd "$repo" || return
    fork_small "$repo" a "${A[@]}"
    fork_small "$repo" c "${C[@]}"
    fork_small "$repo" d "${D[@]}"
    dispatch b "${B[@]}"; expect dispatch D4 "queued" 1

    repo="$(make_fixture)"; cd "$repo" || return
    git_q branch feat/small-a
    dispatch a "${A[@]}"; expect dispatch D5 "exists: propose a-2" 1

    repo="$(make_fixture)"; cd "$repo" || return
    printf 'export const x = 2;\n' >src/features/a/x.ts
    dispatch b "${B[@]}"; expect dispatch "D6 dirty src" "main tree dirty: src/features/a/x.ts" 1
    git_q checkout -- src/features/a/x.ts
    git_q checkout -q --detach
    dispatch b "${B[@]}"; expect dispatch "D6 detached" "main tree detached" 1
    git_q checkout -q main
    write_board "$repo" docs/specs/x.md "IN LOOP"
    dispatch b "${B[@]}"; expect dispatch "D6 main-tree loop" "waits behind main-tree loop x" 1
    write_board "$repo" docs/specs/x.md "READY"
    mkdir -p docs/specs; printf '# Spec: x\n' >docs/specs/x.md
    dispatch b "${B[@]}"; expect dispatch "D6 dirty board and spec pass" "ok" 0

    repo="$(make_fixture)"; cd "$repo" || return
    git_q worktree add -q .claude/worktrees/feat-x -b feat/feat-x
    dispatch b "${B[@]}"; expect dispatch "D7 no Files list" "waits behind feat-x: no Files list yet" 1
    fork_small "$repo" c "${C[@]}"
    fork_small "$repo" d "${D[@]}"
    dispatch b "${B[@]}"; expect dispatch "D7 counted" "queued" 1

    repo="$(make_fixture)"; cd "$repo" || return
    dispatch a src/features/a/a.utils.ts
    expect dispatch D8 "no test file: src/features/a/a.utils.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    fork_small "$repo" a "${A[@]}"
    git_q -C .claude/worktrees/small-a checkout -q --detach
    dispatch b "${A[@]}"; expect dispatch D9 "waits behind small-a: src/features/a/a.utils.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    write_board "$repo" docs/specs/feat-x.md "IN LOOP"
    git_q worktree add -q .claude/worktrees/feat-x -b feat/feat-x
    mkdir -p .claude/worktrees/feat-x/docs/work/feat-x
    printf '## Files\n| Path | Create/Edit | Role |\n| --- | --- | --- |\n| `src/features/b/b.utils.ts` | Edit | x |\n\n## Contracts\n' \
        >.claude/worktrees/feat-x/docs/work/feat-x/plan.md
    dispatch b "${B[@]}"; expect dispatch D10 "waits behind feat-x: src/features/b/b.utils.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    git_q worktree add -q .claude/worktrees/small-a -b feat/small-a
    dispatch b "${B[@]}"; expect dispatch "D11 failed dispatch" "waits behind small-a: no spec commit (failed dispatch)" 1
    fork_small "$repo" c "${C[@]}"
    fork_small "$repo" d "${D[@]}"
    dispatch b "${B[@]}"; expect dispatch "D11 counted" "queued" 1

    repo="$(make_fixture)"; cd "$repo" || return
    fork_small "$repo" a "${A[@]}"
    git_q checkout -q -b other
    git_q branch -f main feat/small-a
    dispatch b "${A[@]}"; expect dispatch D12 "ok" 0

    repo="$(make_fixture)"; cd "$repo" || return
    dispatch "../x" "${A[@]}"; expect dispatch "D13 invalid name" "" 2
    dispatch "A_b" "${A[@]}"; expect dispatch "D13 invalid chars" "" 2

    repo="$(make_fixture)"; cd "$repo" || return
    git_q worktree add -q .claude/worktrees/feat-x -b feat/feat-x
    mkdir -p .claude/worktrees/feat-x/docs/work/feat-x
    printf '## Files\n| Path | Create/Edit | Role |\n| --- | --- | --- |\n| `src/features/b/b.utils.ts`, `src/features/b/b.utils.test.ts` | Edit | x |\n| `src/features/a/x.ts` (new) | Create | y |\n\n## Contracts\n' \
        >.claude/worktrees/feat-x/docs/work/feat-x/plan.md
    dispatch b src/features/b/b.utils.test.ts
    expect dispatch "D14 grouped cell" "waits behind feat-x: src/features/b/b.utils.test.ts" 1
    dispatch b src/features/a/x.ts
    expect dispatch "D14 new marker" "waits behind feat-x: src/features/a/x.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    dispatch b src/features/b/hooks.ts src/features/b/hooks.test.tsx; expect dispatch "D15 tsx test" "ok" 0
    dispatch b src/features/b/hooks.ts; expect dispatch "D15 no test" "no test file: src/features/b/hooks.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    kit_variant "$SCRATCH/kit-d16" "$SELECTORS_SED"
    run "$SCRATCH/kit-d16/.claude/scripts/small-dispatch-check.sh" b src/features/b/selectors.ts
    expect dispatch "D16 layer words from the hook lib" "no test file: src/features/b/selectors.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    git_q mv src/features/a/x.ts src/features/a/y.ts
    dispatch b "${B[@]}"; expect dispatch "D17 rename shows the new path" "main tree dirty: src/features/a/y.ts" 1
    git_q reset -q --hard
    mkdir -p src/features/c
    printf 'x\n' >"src/features/c/with space.ts"
    dispatch b "${B[@]}"; expect dispatch "D17 untracked real path" "main tree dirty: src/features/c/with space.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    kit_variant "$SCRATCH/kit-d18"
    write_board "$repo" docs/specs/x.md READY
    run "$SCRATCH/kit-d18/.claude/scripts/small-dispatch-check.sh" b "${B[@]}"
    expect dispatch "D18 board helper missing" "board unreadable" 1

    repo="$(make_fixture)"; cd "$repo" || return
    git_q checkout -q -b topic
    fork_small "$repo" a "${A[@]}"
    git_q checkout -q main
    git_q merge -q --ff-only feat/small-a
    git_q branch -d topic
    dispatch b "${A[@]}"; expect dispatch "D19 base gone, merged" "ok" 0

    repo="$(make_fixture)"; cd "$repo" || return
    git_q checkout -q -b topic
    fork_small "$repo" a "${A[@]}"
    git_q checkout -q main
    git_q branch -D topic
    dispatch b "${A[@]}"; expect dispatch "D19 base gone, in flight" "waits behind small-a: src/features/a/a.utils.ts" 1

    repo="$(make_fixture)"; cd "$repo" || return
    kit_variant "$SCRATCH/kit-d20" "" board
    write_board "$repo" docs/specs/x.md READY
    run "$SCRATCH/kit-d20/.claude/scripts/small-dispatch-check.sh" b "${B[@]}"
    check dispatch "D20 dispatch leaves no bytecode in the hooks folder" \
        "found: $(find "$SCRATCH/kit-d20/.claude/hooks" -name '*.pyc' | tr '\n' ' ')" \
        test -z "$(find "$SCRATCH/kit-d20/.claude/hooks" -name '*.pyc')"
    cd "$KIT" || return
}

scope() {
    run "$SCRIPTS/small-scope.sh" "$@"
}

group_scope() {
    local repo wt A=(src/features/a/a.utils.ts src/features/a/a.utils.test.ts)

    repo="$(make_fixture)"
    fork_small "$repo" a "${A[@]}"
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    printf 'export const a = 2;\n' >src/features/a/a.utils.ts
    printf 'test("a", () => {});\n' >src/features/a/a.utils.test.ts
    scope a; expect scope C1 "ok" 0

    printf 'export const b = 2;\n' >src/features/b/b.utils.ts
    scope a; expect scope "C2 edit outside" "scope drift: src/features/b/b.utils.ts" 1
    git_q checkout -- src/features/b/b.utils.ts
    printf 'export const n = 1;\n' >src/features/b/new.ts
    scope a; expect scope "C2 untracked outside" "scope drift: src/features/b/new.ts" 1
    rm src/features/b/new.ts
    printf '{ "name": "fixture", "private": true }\n' >package.json
    scope a
    check scope "C2 package.json" "no refusal line names package.json: [$RUN_OUT] rc $RUN_RC" \
        test "$RUN_RC" -eq 1 -a "$(grep -c 'package.json' <<<"$RUN_OUT")" -ge 1
    git_q checkout -- package.json

    repo="$(make_fixture)"
    fork_small "$repo" m src/features/a/moved.ts
    wt="$repo/.claude/worktrees/small-m"; cd "$wt" || return
    git_q mv src/lib/x.ts src/features/a/moved.ts
    scope m
    check scope C3 "the move source is not named: [$RUN_OUT] rc $RUN_RC" \
        test "$RUN_RC" -eq 1 -a "$(grep -c 'src/lib/x.ts' <<<"$RUN_OUT")" -ge 1

    repo="$(make_fixture)"
    fork_small "$repo" a "${A[@]}"
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    printf -- '- src/features/b/b.utils.ts\n' >>docs/specs/small/a.md
    scope a; expect scope C4 "spec edited" 1

    repo="$(make_fixture)"
    fork_small "$repo" a "${A[@]}"
    fork_small "$repo" b src/features/b/b.utils.ts src/features/b/b.utils.test.ts
    printf 'export const b = 3;\n' >"$repo/.claude/worktrees/small-b/src/features/b/b.utils.ts"
    git_q -C "$repo/.claude/worktrees/small-b" commit -q -am "b: change"
    git_q -C "$repo" merge -q --ff-only feat/small-b
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    git_q rebase -q main
    printf 'export const a = 3;\n' >src/features/a/a.utils.ts
    scope a; expect scope C5 "ok" 0

    repo="$(make_fixture)"
    fork_small "$repo" a "${A[@]}"
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    printf 'export const lib = 2;\n' >src/lib/x.ts
    git_q commit -q -am "out of scope"
    git_q rm -q docs/specs/small/a.md
    git_q commit -q -m "drop spec"
    git_q checkout -q HEAD~2 -- docs/specs/small/a.md
    git_q add docs/specs/small/a.md
    git_q commit -q -m "spec again"
    scope a
    check scope "C6 spec re-added" "a deleted-then-re-added spec was accepted: [$RUN_OUT] rc $RUN_RC" \
        test "$RUN_RC" -eq 1 -a "$(grep -c 'spec edited' <<<"$RUN_OUT")" -ge 1 -a "$(grep -c 'src/lib/x.ts' <<<"$RUN_OUT")" -ge 1

    repo="$(make_fixture)"
    fork_small "$repo" a "${A[@]}"
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    printf 'export const y = 1;\n' >src/lib/y.ts
    git_q add src/lib/y.ts
    rm src/lib/y.ts
    scope a
    check scope "C7 staged then deleted" "a staged-then-deleted foundation file was missed: [$RUN_OUT] rc $RUN_RC" \
        test "$RUN_RC" -eq 1 -a "$(grep -c 'src/lib/y.ts' <<<"$RUN_OUT")" -ge 1

    repo="$(make_fixture)"
    printf '.claude/worktrees/\n.claude/.kit-health.jsonl\n' >"$repo/.gitignore"
    git_q -C "$repo" commit -q -am "ignore health log"
    fork_small "$repo" a "${A[@]}"
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    mkdir -p .claude
    printf '{}\n' >.claude/.kit-health.jsonl
    scope a; expect scope "C8 ignored health log" "ok" 0

    repo="$(make_fixture)"
    fork_small "$repo" a "${A[@]}"
    wt="$repo/.claude/worktrees/small-a"; cd "$wt" || return
    scope "a/../b"; expect scope "C9 invalid name" "" 2
    cd "$KIT" || return
}

group_clear() {
    local hook="$KIT/.claude/hooks/next-feature-on-clear.py" small other slug
    small="$SCRATCH/clear/.claude/worktrees/small-a"
    other="$SCRATCH/clear-other"
    write_board "$small" docs/specs/x.md READY
    write_board "$other" docs/specs/x.md READY
    RUN_OUT="$(printf '{"source":"clear"}' | CLAUDE_PROJECT_DIR="$small" python3 "$hook" 2>/dev/null)"
    RUN_RC=$?
    expect clear "N1 small worktree silent" "" 0
    RUN_OUT="$(printf '{"source":"clear"}' | CLAUDE_PROJECT_DIR="$other" python3 "$hook" 2>/dev/null)"
    check clear "N1 other root names the feature" "got [$RUN_OUT]" grep -Fq 'Next feature (topmost READY): feature x' <<<"$RUN_OUT"

    for slug in "docs/specs/small/a.md=small-a" "docs/specs/x.md=x" "docs/stories/inbox/1.2.md=inbox-1.2"; do
        RUN_OUT="$(python3 - "$hook" "${slug%%=*}" <<'PY' 2>/dev/null
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("next_feature_on_clear", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.loop_slug(sys.argv[2]))
PY
)"
        RUN_RC=$?
        expect clear "N2 ${slug%%=*}" "${slug#*=}" 0
    done
}

group_paths
group_plan
group_dispatch
group_scope
group_clear

if [[ "$CASES" -lt 91 ]]; then
    fail harness floor "only $CASES case(s) ran, expected at least 91"
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2
    exit 1
fi
printf 'small lane fixtures: %d case(s), all green.\n' "$CASES"
