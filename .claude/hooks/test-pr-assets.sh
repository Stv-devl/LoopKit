#!/usr/bin/env bash
# kit-pr-assets.py: UI decision, image paths, publish plan, PR section, and the
# pr-assets commit/drop plumbing (docs/work/pr-screenshots/plan.md, K1-K23).

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SCRIPT="$HOOKS_DIR/kit-pr-assets.py"
FAILURES=0
CASES=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
export XDG_CONFIG_HOME="$SCRATCH/.config"

OUT=""
ERR=""
RC=0
CWD="$SCRATCH"

fail() {
    printf 'FAIL %s: %s\n' "$1" "$2" >&2
    FAILURES=$((FAILURES + 1))
}

case_start() {
    CASES=$((CASES + 1))
    CASE_DIR="$SCRATCH/case-$CASES"
    mkdir -p "$CASE_DIR"
    CWD="$CASE_DIR"
}

# run_in <stdin> <args…>: run the script from $CWD; a missing script is 127,
# so python's own exit 2 never passes a refusal case.
run_in() {
    local input="$1" errf="$SCRATCH/stderr"
    shift
    if [[ ! -f "$SCRIPT" ]]; then
        OUT=""
        ERR="kit-pr-assets.py missing"
        RC=127
        return
    fi
    OUT="$(cd "$CWD" && python3 "$SCRIPT" "$@" 2>"$errf" <<<"$input")"
    RC=$?
    ERR="$(cat "$errf")"
}

run_cmd() {
    run_in "" "$@"
}

expect_out() {
    local id="$1" want="$2"
    [[ "$RC" -eq 0 ]] || { fail "$id" "exit $RC (stderr: $ERR)"; return; }
    [[ "$OUT" == "$want" ]] || fail "$id" "stdout was [$OUT], want [$want]"
}

expect_refused() {
    local id="$1"
    [[ "$RC" -eq 2 ]] || { fail "$id" "exit $RC, want 2 (stderr: $ERR)"; return; }
    [[ -z "$OUT" ]] || fail "$id" "stdout not empty on refusal: [$OUT]"
    [[ -n "$ERR" ]] || fail "$id" "no reason on stderr"
}

mkrepo() {
    local d="$1"
    git init -q --bare "$d/origin.git"
    git init -q -b main "$d/work"
    git -C "$d/work" config user.name kit-test
    git -C "$d/work" config user.email kit-test@example.invalid
    git -C "$d/work" config commit.gpgsign false
    printf 'readme\n' >"$d/work/README.md"
    git -C "$d/work" add README.md
    git -C "$d/work" commit -q -m init
    git -C "$d/work" remote add origin "$d/origin.git"
    git -C "$d/work" push -q origin main 2>/dev/null
}

# mkshots <dir> <relative names…>: one distinct small file per image.
mkshots() {
    local d="$1" n
    shift
    for n in "$@"; do
        mkdir -p "$(dirname "$d/$n")"
        printf 'png %s' "$n" >"$d/$n"
    done
}

# seed <repo> <ref> <parent|-> <paths…>: a pr-assets-like commit built with plumbing.
seed() {
    local repo="$1" ref="$2" parent="$3" idx blob tree commit p
    shift 3
    idx="$SCRATCH/seed-index-$RANDOM$RANDOM"
    for p in "$@"; do
        blob="$(printf 'seed %s' "$p" | git -C "$repo" hash-object -w --stdin)"
        GIT_INDEX_FILE="$idx" git -C "$repo" update-index --add --cacheinfo "100644,$blob,$p"
    done
    tree="$(GIT_INDEX_FILE="$idx" git -C "$repo" write-tree)"
    rm -f "$idx"
    if [[ "$parent" == "-" ]]; then
        commit="$(git -C "$repo" commit-tree "$tree" -m seed)"
    else
        commit="$(git -C "$repo" commit-tree "$tree" -p "$parent" -m seed)"
    fi
    git -C "$repo" update-ref "$ref" "$commit"
    printf '%s' "$commit"
}

snapshot() {
    local r="$1"
    git -C "$r" rev-parse HEAD
    git -C "$r" for-each-ref --format='%(refname) %(objectname)' | grep -v '^refs/heads/pr-assets '
    sha256sum <"$r/.git/index"
    git -C "$r" status --porcelain
}

tree_of() {
    git -C "$1" ls-tree -r --name-only refs/heads/pr-assets 2>/dev/null
}

tip_of() {
    git -C "$1" rev-parse -q --verify refs/heads/pr-assets 2>/dev/null
}

parents_of() {
    git -C "$1" rev-list --parents -n 1 "$2" | cut -s -d' ' -f2-
}

U="https://github.com/o/r/blob/pr-assets/feat/pr-shots/abc1234"
COMMON=(--dir .pr-shots/run --branch feat/pr-shots --sha abc1234 --repo o/r)

# ---------------------------------------------------------------- core

case_start
run_in $'.claude/agents/github.md\ndocs/specs/x.md' ui
expect_out "K1 a diff of agent and spec files only prints none" "none"

case_start
run_in $'docs/specs/x.md\nsrc/features/cart/Cart.tsx' ui
expect_out "K2 a diff containing a .tsx under src prints ui" "ui"

case_start
for P in src/styles/app.css index.html public/logo.svg; do
    run_in "$P" ui
    expect_out "K3 $P alone prints ui" "ui"
done
run_in "src/features/cart/cart.utils.ts" ui
expect_out "K3 a .ts utils file alone prints none" "none"

case_start
run_cmd path --branch feat/pr-shots --sha abc1234 --flow checkout --step 02-pay --theme dark --viewport mobile
expect_out "K4 path joins branch, sha and the flow-step-theme-viewport name" \
    "feat/pr-shots/abc1234/checkout-02-pay-dark-mobile.png"

case_start
run_cmd path --branch feat/pr-shots --sha abc1234 --flow checkout --step 02-pay --theme dark --viewport mobile --before
expect_out "K5 path with --before ends in -before.png" \
    "feat/pr-shots/abc1234/checkout-02-pay-dark-mobile-before.png"

case_start
mkshots "$CASE_DIR/shots" checkout/01-cart-light-desktop.png checkout/01-cart-dark-desktop.png
run_cmd plan --dir "$CASE_DIR/shots" --branch feat/pr-shots --sha abc1234 --repo o/r
if [[ "$RC" -ne 0 ]]; then
    fail "K8 plan lists one entry per image with its raw url" "exit $RC (stderr: $ERR)"
else
    K8_GOT="$(python3 -I -c '
import json, sys
entries = json.load(sys.stdin)
for e in entries:
    if sorted(e) != ["local", "path", "url"]:
        print("bad keys", sorted(e)); continue
    tail = e["local"].replace("\\", "/").split("/")[-2:]
    print(e["path"] + "|" + e["url"] + "|" + "/".join(tail))
' <<<"$OUT" | sort)"
    K8_WANT="$(printf '%s\n' \
        "feat/pr-shots/abc1234/checkout-01-cart-dark-desktop.png|$U/checkout-01-cart-dark-desktop.png?raw=true|checkout/01-cart-dark-desktop.png" \
        "feat/pr-shots/abc1234/checkout-01-cart-light-desktop.png|$U/checkout-01-cart-light-desktop.png?raw=true|checkout/01-cart-light-desktop.png")"
    [[ "$K8_GOT" == "$K8_WANT" ]] || fail "K8 plan lists one entry per image with its raw url" "got [$K8_GOT]"
fi

K12_ROWS="$(cat <<EOF
**Screenshots** — checkout
| 01 cart | light | dark |
| --- | --- | --- |
| desktop | <a href="$U/checkout-01-cart-light-desktop.png?raw=true"><img src="$U/checkout-01-cart-light-desktop.png?raw=true" width="400"></a> | <a href="$U/checkout-01-cart-dark-desktop.png?raw=true"><img src="$U/checkout-01-cart-dark-desktop.png?raw=true" width="400"></a> |
| mobile | <a href="$U/checkout-01-cart-light-mobile.png?raw=true"><img src="$U/checkout-01-cart-light-mobile.png?raw=true" width="180"></a> | <a href="$U/checkout-01-cart-dark-mobile.png?raw=true"><img src="$U/checkout-01-cart-dark-mobile.png?raw=true" width="180"></a> |
EOF
)"
FOUR=(checkout/01-cart-light-desktop.png checkout/01-cart-dark-desktop.png
      checkout/01-cart-light-mobile.png checkout/01-cart-dark-mobile.png)

case_start
mkshots "$CASE_DIR/.pr-shots/run" "${FOUR[@]}"
run_cmd section "${COMMON[@]}"
expect_out "K12 section on one step with four variants prints the fixture block" "$K12_ROWS"

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
mkshots "$CWD/.pr-shots/run" checkout/01-cart-light-desktop.png checkout/01-cart-dark-desktop.png
BEFORE="$(snapshot "$CWD")"
run_cmd commit "${COMMON[@]}"
AFTER="$(snapshot "$CWD")"
K15="K15 commit with no pr-assets creates a parentless commit of exactly the planned paths"
if [[ "$RC" -ne 0 ]]; then
    fail "$K15" "exit $RC (stderr: $ERR)"
else
    TIP="$(tip_of "$CWD")"
    [[ -n "$TIP" && "$OUT" == "$TIP" ]] || fail "$K15" "printed [$OUT], ref is [$TIP]"
    [[ -z "$(parents_of "$CWD" "$TIP")" ]] || fail "$K15" "commit has a parent"
    WANT="$(printf '%s\n' feat/pr-shots/abc1234/checkout-01-cart-dark-desktop.png feat/pr-shots/abc1234/checkout-01-cart-light-desktop.png)"
    [[ "$(tree_of "$CWD")" == "$WANT" ]] || fail "$K15" "tree was [$(tree_of "$CWD")]"
    [[ "$(git -C "$CWD" log -1 --format=%B "$TIP" | sed '/^$/d')" == "chore(pr-assets): add feat/pr-shots abc1234" ]] \
        || fail "$K15" "message was [$(git -C "$CWD" log -1 --format=%B "$TIP")]"
    [[ "$(git -C "$CWD" cat-file -p "$TIP:feat/pr-shots/abc1234/checkout-01-cart-light-desktop.png")" == "png checkout/01-cart-light-desktop.png" ]] \
        || fail "$K15" "blob does not hold the image bytes"
    [[ "$BEFORE" == "$AFTER" ]] || fail "$K15" "HEAD, another ref, the index or the status changed"
fi

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
OLD="$(seed "$CWD" refs/heads/pr-assets - other/keep/x.png feat/x/abc1234/a.png feat/x/9999999/b.png feat/x-y/abc1234/c.png main/abc1234/d.png)"
BEFORE="$(snapshot "$CWD")"
run_in "body with https://github.com/o/r/blob/pr-assets/feat/x/abc1234/checkout-01-cart-light-desktop.png?raw=true" drop --branch feat/x
AFTER="$(snapshot "$CWD")"
K19="K19 drop leaves HEAD, other refs, the index and the status identical"
if [[ "$RC" -ne 0 ]]; then
    fail "$K19" "exit $RC (stderr: $ERR)"
else
    tree_of "$CWD" | grep -q '^feat/x/abc1234/' && fail "$K19" "the published folder is still there"
    [[ "$BEFORE" == "$AFTER" ]] || fail "$K19" "HEAD, another ref, the index or the status changed"
fi

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
OLD="$(seed "$CWD" refs/heads/pr-assets - feat/x/abc1234/a.png feat/x/9999999/b.png feat/x-y/abc1234/c.png main/abc1234/d.png)"
K20_BODY='## Summary
**Screenshots** — checkout
| desktop | <a href="https://github.com/o/r/blob/pr-assets/feat/x/abc1234/checkout-01-cart-light-desktop.png?raw=true"><img src="https://github.com/o/r/blob/pr-assets/feat/x/abc1234/checkout-01-cart-light-desktop.png?raw=true" width="400"></a> |
see also https://github.com/o/r/blob/pr-assets/feat/x-y/abc1234/c.png?raw=true'
run_in "$K20_BODY" drop --branch feat/x
K20="K20 drop removes exactly the folders the PR body names for that branch"
if [[ "$RC" -ne 0 ]]; then
    fail "$K20" "exit $RC (stderr: $ERR)"
else
    WANT="$(printf '%s\n' feat/x-y/abc1234/c.png feat/x/9999999/b.png main/abc1234/d.png)"
    [[ "$(tree_of "$CWD")" == "$WANT" ]] || fail "$K20" "tree was [$(tree_of "$CWD")]"
    TIP="$(tip_of "$CWD")"
    [[ "$(parents_of "$CWD" "$TIP")" == "$OLD" ]] || fail "$K20" "parent is not the old tip"
    [[ "$(git -C "$CWD" log -1 --format=%B "$TIP" | sed '/^$/d')" == "chore(pr-assets): drop feat/x" ]] \
        || fail "$K20" "message was [$(git -C "$CWD" log -1 --format=%B "$TIP")]"
fi

# ---------------------------------------------------------------- business rules

case_start
mkshots "$CASE_DIR/.pr-shots/run" "${FOUR[@]}" checkout/01-cart-light-desktop-before.png
run_cmd section "${COMMON[@]}"
K13_WANT="$K12_ROWS
| before (desktop) | <a href=\"$U/checkout-01-cart-light-desktop-before.png?raw=true\"><img src=\"$U/checkout-01-cart-light-desktop-before.png?raw=true\" width=\"400\"></a> | — |"
expect_out "K13 a step with a before image gets the before (desktop) row" "$K13_WANT"
case_start
mkshots "$CASE_DIR/.pr-shots/run" "${FOUR[@]}"
run_cmd section "${COMMON[@]}"
if [[ "$RC" -ne 0 ]] || grep -q 'before (desktop)' <<<"$OUT"; then
    fail "K13 a step without a before image has no before row" "exit $RC, stdout [$OUT]"
fi

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
OLD="$(seed "$CWD" refs/heads/pr-assets - other/keep/x.png)"
mkshots "$CWD/.pr-shots/run" checkout/01-cart-light-desktop.png
run_cmd commit "${COMMON[@]}"
K16="K16 commit on an existing local pr-assets parents on its tip and keeps its tree"
if [[ "$RC" -ne 0 ]]; then
    fail "$K16" "exit $RC (stderr: $ERR)"
else
    [[ "$(parents_of "$CWD" "$(tip_of "$CWD")")" == "$OLD" ]] || fail "$K16" "parent is not the old tip"
    WANT="$(printf '%s\n' feat/pr-shots/abc1234/checkout-01-cart-light-desktop.png other/keep/x.png)"
    [[ "$(tree_of "$CWD")" == "$WANT" ]] || fail "$K16" "tree was [$(tree_of "$CWD")]"
fi

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
OLD="$(seed "$CWD" refs/heads/pr-assets - feat/pr-shots/abc1234/checkout-01-cart-light-desktop.png)"
mkshots "$CWD/.pr-shots/run" checkout/01-cart-light-desktop.png
run_cmd commit "${COMMON[@]}"
expect_refused "K17 commit onto an existing path exits 2"
[[ "$(tip_of "$CWD")" == "$OLD" ]] || fail "K17 commit onto an existing path leaves the ref unchanged" "ref moved"

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
REMOTE="$(seed "$CWD" refs/remotes/origin/pr-assets - other/keep/x.png)"
mkshots "$CWD/.pr-shots/run" checkout/01-cart-light-desktop.png
run_cmd commit "${COMMON[@]}"
K18="K18 no local pr-assets and origin/pr-assets present parents on origin/pr-assets"
if [[ "$RC" -ne 0 ]]; then
    fail "$K18" "exit $RC (stderr: $ERR)"
else
    [[ "$(parents_of "$CWD" "$(tip_of "$CWD")")" == "$REMOTE" ]] || fail "$K18" "parent is not origin/pr-assets"
fi

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
LOCAL="$(seed "$CWD" refs/heads/pr-assets - other/keep/x.png)"
REMOTE="$(seed "$CWD" refs/remotes/origin/pr-assets "$LOCAL" other/keep/x.png other/keep/y.png)"
mkshots "$CWD/.pr-shots/run" checkout/01-cart-light-desktop.png
run_cmd commit "${COMMON[@]}"
K22A="K22 local pr-assets an ancestor of origin/pr-assets parents on origin"
if [[ "$RC" -ne 0 ]]; then
    fail "$K22A" "exit $RC (stderr: $ERR)"
else
    [[ "$(parents_of "$CWD" "$(tip_of "$CWD")")" == "$REMOTE" ]] || fail "$K22A" "parent is not origin/pr-assets"
fi
case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
LOCAL="$(seed "$CWD" refs/heads/pr-assets - other/keep/x.png)"
seed "$CWD" refs/remotes/origin/pr-assets - other/keep/z.png >/dev/null
mkshots "$CWD/.pr-shots/run" checkout/01-cart-light-desktop.png
run_cmd commit "${COMMON[@]}"
expect_refused "K22 diverged local and origin pr-assets exits 2"
grep -q 'fetch first' <<<"$ERR" || fail "K22 diverged refusal says fetch first" "stderr was [$ERR]"
[[ "$(tip_of "$CWD")" == "$LOCAL" ]] || fail "K22 diverged refusal leaves the ref unchanged" "ref moved"

case_start
NAMES=()
for S in 01-a 02-b 03-c 04-d; do NAMES+=("checkout/$S-light-desktop.png"); done
mkshots "$CASE_DIR/shots" "${NAMES[@]}"
run_cmd plan --dir "$CASE_DIR/shots" --branch feat/pr-shots --sha abc1234 --repo o/r
expect_refused "K10 a fourth step in one flow exits 2"
case_start
NAMES=()
for F in f01 f02 f03 f04 f05 f06 f07 f08 f09 f10 f11; do
    for S in 01-a 02-b 03-c; do NAMES+=("$F/$S-light-desktop.png"); done
done
mkshots "$CASE_DIR/shots" "${NAMES[@]}"
run_cmd plan --dir "$CASE_DIR/shots" --branch feat/pr-shots --sha abc1234 --repo o/r
expect_refused "K10 a 33rd image exits 2"
rm "$CASE_DIR/shots/f11/03-c-light-desktop.png"
run_cmd plan --dir "$CASE_DIR/shots" --branch feat/pr-shots --sha abc1234 --repo o/r
[[ "$RC" -eq 0 ]] || fail "K10 32 images are accepted" "exit $RC (stderr: $ERR)"

# ---------------------------------------------------------------- edge cases

case_start
for B in "feat/pr shots" "feat/../x"; do
    run_cmd path --branch "$B" --sha abc1234 --flow checkout --step 02-pay --theme dark --viewport mobile
    expect_refused "K6 branch [$B] exits 2"
done

case_start
for S in xyz abc12; do
    run_cmd path --branch feat/pr-shots --sha "$S" --flow checkout --step 02-pay --theme dark --viewport mobile
    expect_refused "K7 sha [$S] exits 2"
done

case_start
mkshots "$CASE_DIR/shots" checkout/shot.png
run_cmd plan --dir "$CASE_DIR/shots" --branch feat/pr-shots --sha abc1234 --repo o/r
expect_refused "K9 an unknown image name exits 2"
grep -q 'shot.png' <<<"$ERR" || fail "K9 the refusal names the file" "stderr was [$ERR]"

case_start
run_cmd plan --dir "$CASE_DIR/missing" --branch feat/pr-shots --sha abc1234 --repo o/r
if [[ "$RC" -ne 0 ]] || ! python3 -I -c 'import json,sys; sys.exit(0 if json.load(sys.stdin) == [] else 1)' <<<"$OUT" 2>/dev/null; then
    fail "K11 plan on a missing dir prints []" "exit $RC, stdout [$OUT]"
fi
run_cmd section --dir "$CASE_DIR/missing" --branch feat/pr-shots --sha abc1234 --repo o/r
expect_out "K11 section on a missing dir prints nothing" ""

case_start
mkdir -p "$CASE_DIR/.pr-shots/run"
run_cmd section "${COMMON[@]}"
expect_out "K14 section with zero images prints nothing" ""

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
OLD="$(seed "$CWD" refs/heads/pr-assets - feat/x/abc1234/a.png)"
run_in "see https://github.com/o/r/blob/pr-assets/feat/x/1234567/checkout-01-cart-light-desktop.png?raw=true" drop --branch feat/x
expect_out "K21 a body naming an absent folder prints nothing to clean" "nothing to clean"
[[ "$(tip_of "$CWD")" == "$OLD" ]] || fail "K21 absent folder leaves the ref unchanged" "ref moved"
run_in "a body with no image" drop --branch feat/x
expect_out "K21 a body with no image url prints nothing to clean" "nothing to clean"
[[ "$(tip_of "$CWD")" == "$OLD" ]] || fail "K21 no image url leaves the ref unchanged" "ref moved"

case_start
run_cmd path --branch feat/pr-shots --sha abc1234def5678 --flow checkout --step 02-pay --theme dark --viewport mobile
expect_out "K23 a 14-char sha folds to its first 7 chars" \
    "feat/pr-shots/abc1234/checkout-02-pay-dark-mobile.png"

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
printf 'SECRET=1' >"$CASE_DIR/secret.env"
mkdir -p "$CWD/.pr-shots/run/checkout"
ln -s "$CASE_DIR/secret.env" "$CWD/.pr-shots/run/checkout/01-cart-light-desktop.png"
run_cmd commit "${COMMON[@]}"
expect_refused "K24 commit with a symlink in the run dir exits 2"
[[ -z "$(tip_of "$CWD")" ]] || fail "K24 a symlink refusal leaves pr-assets absent" "ref exists"
case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
printf 'SECRET=1' >"$CASE_DIR/secret.env"
mkdir -p "$CWD/.pr-shots/run/checkout"
ln "$CASE_DIR/secret.env" "$CWD/.pr-shots/run/checkout/01-cart-light-desktop.png"
run_cmd plan "${COMMON[@]}"
expect_refused "K24 plan with a hard link in the run dir exits 2"

case_start
mkshots "$CASE_DIR/shots" checkout/01-cart-dark-mobile-before.png
run_cmd plan --dir "$CASE_DIR/shots" --branch feat/pr-shots --sha abc1234 --repo o/r
expect_refused "K25 a before image outside light-desktop exits 2"

case_start
mkrepo "$CASE_DIR"
CWD="$CASE_DIR/work"
seed "$CWD" refs/heads/pr-assets - feat/x/abc1234/a.png feat/x/abc1234/1234567/n.png >/dev/null
run_in "see https://github.com/o/r/blob/pr-assets/feat/x/abc1234/a.png?raw=true" drop --branch feat/x
K26="K26 drop never removes a nested branch's folder under the same prefix"
if [[ "$RC" -ne 0 ]]; then
    fail "$K26" "exit $RC (stderr: $ERR)"
else
    [[ "$(tree_of "$CWD")" == "feat/x/abc1234/1234567/n.png" ]] || fail "$K26" "tree was [$(tree_of "$CWD")]"
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf '%d failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2
    exit 1
fi
printf 'PR assets: %d case(s), all green.\n' "$CASES"
