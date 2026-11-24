#!/usr/bin/env bash
# Replay the hook fixtures exactly as Claude Code sends them on stdin.

set -uo pipefail

HOOKS_DIR="${HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
FIXTURES_DIR="${FIXTURES_DIR:-$HOOKS_DIR/fixtures}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$HOOKS_DIR/../.." && pwd)}"
FAILURES=0
CASES=0
# The git fixtures must not depend on this machine's git config (a global
# excludesFile ignoring *.pem would turn a deny into a pass).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Git still reads $XDG_CONFIG_HOME/git/ignore as its default excludesFile (the
# ~/.config one only when XDG_CONFIG_HOME is unset): point it at an empty scratch dir.
CWK_TEST_HOME="$(mktemp -d)"
trap 'rm -r "$CWK_TEST_HOME"' EXIT
export XDG_CONFIG_HOME="$CWK_TEST_HOME/.config"

# Every hook call runs under a wall-clock cap, far above the slowest legitimate
# case (a stalled git is cut at 3 s), so a hook that hangs turns its case red
# instead of stopping the suite. Resolved once: a case may run with a PATH that
# lacks `timeout`. No `timeout`/`gtimeout` on this machine: no cap.
CASE_SECONDS="${CWK_CASE_TIMEOUT:-60}"
CASE_TIMEOUT=()
for CWK_TIMEOUT_BIN in timeout gtimeout; do
    if CWK_TIMEOUT_PATH="$(command -v "$CWK_TIMEOUT_BIN" 2>/dev/null)" && [[ -x "$CWK_TIMEOUT_PATH" ]]; then
        CASE_TIMEOUT=("$CWK_TIMEOUT_PATH" -k 5 "$CASE_SECONDS")
        break
    fi
done

# no_python_bin <dir>: a PATH directory holding every tool a hook needs, python3 aside.
no_python_bin() {
    local tool
    mkdir -p "$1"
    for tool in env bash dirname basename date jq grep sed cat tr head tail cut sort uniq \
                mktemp rm mkdir wc readlink realpath sha256sum awk ls touch cp mv ln tee \
                id uname sleep timeout git; do
        [[ -x "$(command -v "$tool" 2>/dev/null)" ]] && ln -sf "$(command -v "$tool")" "$1/$tool"
    done
    return 0
}

fail() {
    printf 'FAIL %s / %s: %s\n' "$1" "$2" "$3" >&2
    FAILURES=$((FAILURES + 1))
}

semantic_verdict() {
    local code="$1" stdout_file="$2"
    if [[ "$code" -eq 2 ]]; then
        printf deny
        return
    fi
    if [[ "$code" -ne 0 ]]; then
        printf crash
        return
    fi
    python3 -I - "$stdout_file" <<'PY'
import json
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if not text:
    print("pass")
else:
    try:
        payload = json.loads(text)
        print(payload.get("hookSpecificOutput", {}).get("permissionDecision", "pass"))
    except json.JSONDecodeError:
        print("invalid")
PY
}

deny_has_reason() {
    python3 -I - "$1" "$2" <<'PY'
import json
import pathlib
import sys

stdout = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
stderr = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
if stderr:
    raise SystemExit(0)
try:
    reason = json.loads(stdout).get("hookSpecificOutput", {}).get("permissionDecisionReason", "")
except json.JSONDecodeError:
    reason = ""
raise SystemExit(0 if reason.strip() else 1)
PY
}

# A fixture may carry "_expect_reason": the decision's reason must contain it.
reason_has_expected() {
    python3 -I - "$1" "$2" <<'PY'
import json
import pathlib
import sys

expected = json.loads(sys.argv[1]).get("_expect_reason")
if not expected:
    raise SystemExit(0)
try:
    reason = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")).get(
        "hookSpecificOutput", {}).get("permissionDecisionReason", "")
except json.JSONDecodeError:
    reason = ""
raise SystemExit(0 if expected in reason else 1)
PY
}

run_case() {
    local hook="$1" fixture="$2" expected="$3"
    local tmp input stdout_file stderr_file code verdict fixture_name extra_marker="" project_dir="$PROJECT_ROOT" lp_variant
    local -a hook_unset=()
    local hook_path="$PATH" real_git hook_home="$HOME" hook_tmp="${TMPDIR:-/tmp}" hook_pwd="$PWD"
    tmp="$(mktemp -d)"
    fixture_name="$(basename "$fixture")"
    stdout_file="$tmp/stdout"
    stderr_file="$tmp/stderr"
    input="$(sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g; s|__FIXTURE_ROOT__|$tmp|g; s|__MAIN_TREE__|$tmp|g; s|__FEAT_TREE__|$tmp/.feat|g; s|__OUT_TREE__|$tmp/out|g" "$fixture")"

    # A shell-guard row's `setup` key, matched whole, never as a substring.
    # `aliasdir`: the project dir is a symlink to $tmp/real, the cwd its physical path.
    # `pkgroot`: package.json at the project root $tmp. `pkgabove`: package.json in
    # $tmp, ABOVE the project $tmp/p; `pkgalias`: same, the project a symlink to it.
    # `pkgsub`: package.json and src/ in $tmp/sub. `cfgdirs`: docs/, .github/, src/
    # in the project $tmp. `cfgempty`: an empty project $tmp. `noproject`: no
    # CLAUDE_PROJECT_DIR at all.
    if [[ "$hook" == prevent-destructive-commands.sh ]]; then
        case "${SHELL_SETUP:-}" in
            aliasdir)
                mkdir -p "$tmp/real"
                ln -s "$tmp/real" "$tmp/alias"
                project_dir="$tmp/alias"
                ;;
            pkgroot)
                printf '{}\n' >"$tmp/package.json"
                mkdir -p "$tmp/docs"
                project_dir="$tmp"
                ;;
            pkgabove|pkgalias)
                printf '{}\n' >"$tmp/package.json"
                mkdir -p "$tmp/p"
                project_dir="$tmp/p"
                if [[ "$SHELL_SETUP" == pkgalias ]]; then
                    ln -s "$tmp/p" "$tmp/link"
                    project_dir="$tmp/link"
                fi
                ;;
            pkgsub)
                mkdir -p "$tmp/sub/src"
                printf '{}\n' >"$tmp/sub/package.json"
                project_dir="$tmp"
                ;;
            cfgdirs)
                mkdir -p "$tmp/docs" "$tmp/.github" "$tmp/src"
                project_dir="$tmp"
                ;;
            cfgempty) project_dir="$tmp" ;;
            noproject) project_dir="" ;;
            # `notmp`: TMPDIR names a folder that does not exist, so mktemp fails.
            notmp) hook_tmp="/nonexistent-dir" ;;
            # Fake secrets for the glob rows, all in the project $tmp. `secrets`:
            # .env, .env.example, server.pem, credentials.json, notes.txt, sub/.env.
            # `secrets-home`: .env only in $tmp/home, the hook's HOME. `secrets-sub`:
            # .env only in sub/. `secrets-dot`: .env and notes.txt.
            secrets)
                mkdir -p "$tmp/sub"
                printf 'K=v\n' >"$tmp/.env"
                printf 'K=\n' >"$tmp/.env.example"
                printf 'k\n' >"$tmp/server.pem"
                printf '{}\n' >"$tmp/credentials.json"
                printf 'n\n' >"$tmp/notes.txt"
                printf 'K=v\n' >"$tmp/sub/.env"
                project_dir="$tmp"
                ;;
            secrets-home)
                mkdir -p "$tmp/home"
                printf 'K=v\n' >"$tmp/home/.env"
                hook_home="$tmp/home"
                project_dir="$tmp"
                ;;
            secrets-sub)
                mkdir -p "$tmp/sub"
                printf 'K=v\n' >"$tmp/sub/.env"
                project_dir="$tmp"
                ;;
            secrets-dot)
                printf 'K=v\n' >"$tmp/.env"
                printf 'n\n' >"$tmp/notes.txt"
                project_dir="$tmp"
                ;;
            # `secrets-keys`: id.key, .credentials, credentials, .env.local, notes.txt
            # (no .env). `secrets-tmpl`: the three templates and notes.txt only.
            secrets-keys)
                printf 'k\n' >"$tmp/id.key"
                printf '{}\n' >"$tmp/.credentials"
                printf '{}\n' >"$tmp/credentials"
                printf 'K=v\n' >"$tmp/.env.local"
                printf 'n\n' >"$tmp/notes.txt"
                project_dir="$tmp"
                ;;
            secrets-tmpl)
                printf 'K=\n' >"$tmp/.env.example"
                printf 'K=\n' >"$tmp/.env.sample"
                printf 'K=\n' >"$tmp/.env.template"
                printf 'n\n' >"$tmp/notes.txt"
                project_dir="$tmp"
                ;;
            # `secrets-deep`: $tmp/d holds two symlinks to itself, so `*/*/…/*` has
            # 2^N paths to list: a glob that cannot finish within the hook's timeout;
            # the only .env is $tmp/.env, outside what that glob lists.
            secrets-deep)
                mkdir -p "$tmp/d"
                ln -s . "$tmp/d/a"
                ln -s . "$tmp/d/b"
                printf 'K=v\n' >"$tmp/.env"
                project_dir="$tmp"
                ;;
            # `secrets-many`: 300 folders m001-m300 holding x, 300 files .e001-.e300,
            # .env, cfg/server.pem and notes.txt: `*/*` and `.e*` list 301 entries,
            # more than 256, in whatever order the filesystem gives; the scan reads all.
            secrets-many)
                mkdir -p "$tmp/cfg"
                for ((n = 1; n <= 300; n++)); do
                    mkdir "$tmp/$(printf 'm%03d' "$n")"
                    : >"$tmp/$(printf 'm%03d' "$n")/x"
                    : >"$tmp/$(printf '.e%03d' "$n")"
                done
                printf 'K=v\n' >"$tmp/.env"
                printf 'k\n' >"$tmp/cfg/server.pem"
                printf 'n\n' >"$tmp/notes.txt"
                project_dir="$tmp"
                ;;
            # `secrets-mode`: .env.development.local (a secret), .env.example and
            # .env.local.example (templates), notes.txt.
            secrets-mode)
                printf 'K=v\n' >"$tmp/.env.development.local"
                printf 'K=\n' >"$tmp/.env.example"
                printf 'K=\n' >"$tmp/.env.local.example"
                printf 'n\n' >"$tmp/notes.txt"
                project_dir="$tmp"
                ;;
            # `secrets-modetmpl`: .env.local.sample and .env.local.template (templates),
            # .env.development.local (the control, a secret), notes.txt.
            secrets-modetmpl)
                printf 'K=\n' >"$tmp/.env.local.sample"
                printf 'K=\n' >"$tmp/.env.local.template"
                printf 'K=v\n' >"$tmp/.env.development.local"
                printf 'n\n' >"$tmp/notes.txt"
                project_dir="$tmp"
                ;;
            # `kitwt`: a git project $tmp with a real linked worktree .claude/worktrees/w,
            # a plain folder .claude/worktrees/evil (a `cp -r` of a nested copy) and
            # .claude/worktrees/copy (a `cp -r` of w, its .git file still naming w).
            kitwt)
                git -C "$tmp" init -q -b main
                git -C "$tmp" -c user.email=fixture@loopkit.invalid -c user.name=Fixture \
                    commit -q --allow-empty -m seed
                git -C "$tmp" worktree add -q "$tmp/.claude/worktrees/w" -b feat/w
                mkdir -p "$tmp/.claude/worktrees/evil/.claude/hooks"
                cp -r "$tmp/.claude/worktrees/w" "$tmp/.claude/worktrees/copy"
                # `stale`: registered (gitdir names it) but its folder holds no .git
                # file, as `git worktree list` shows a prunable entry.
                mkdir -p "$tmp/.git/worktrees/stale" "$tmp/.claude/worktrees/stale/.claude/hooks"
                printf '%s\n' "$tmp/.claude/worktrees/stale/.git" >"$tmp/.git/worktrees/stale/gitdir"
                project_dir="$tmp"
                ;;
            # `kitwtrel`: the real worktree .claude/worktrees/w registered with a relative
            # gitdir (git >= 2.48 `worktree.useRelativePaths`), written relative to
            # .git/worktrees/w as git does.
            kitwtrel)
                git -C "$tmp" init -q -b main
                git -C "$tmp" -c user.email=fixture@loopkit.invalid -c user.name=Fixture \
                    commit -q --allow-empty -m seed
                git -C "$tmp" worktree add -q "$tmp/.claude/worktrees/w" -b feat/w
                printf '%s\n' '../../../.claude/worktrees/w/.git' >"$tmp/.git/worktrees/w/gitdir"
                project_dir="$tmp"
                ;;
            # `pnpmlink`: a pnpm layout in the project $tmp, node_modules/foo a symlink
            # to .pnpm/foo@1/node_modules/foo, so `foo/../..` is the root logically
            # and node_modules/.pnpm/foo@1 physically.
            pnpmlink)
                mkdir -p "$tmp/node_modules/.pnpm/foo@1/node_modules/foo" "$tmp/node_modules/.pnpm/foo@1/.claude/hooks"
                ln -s .pnpm/foo@1/node_modules/foo "$tmp/node_modules/foo"
                project_dir="$tmp"
                ;;
            '') ;;
            *)
                fail "$hook" "$fixture_name" "unknown setup '$SHELL_SETUP' (a misspelt name would run with no setup)"
                ;;
        esac
    fi

    case "$hook:$fixture_name" in
        # Edits an EXISTING item.utils.ts to add a never-before-exported
        # symbol. Deny case: no test file for it at all, so the symbol-level
        # check in tdd-require-red.sh has nothing to read a proved red from.
        tdd-require-red.sh:06-existing-new-export-deny.json)
            mkdir -p "$tmp/src"
            printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
            ;;
        # Same edit, pass case: a marker exists for item.utils.test.ts, its
        # digest matches the test file on disk, and its `missing:` line names
        # the symbol this edit adds — exactly what a real tdd-prove-red run
        # would have left behind. The marker lives under the REAL project's
        # .claude/.tdd-red/ (RED_DIR is derived from CLAUDE_PROJECT_DIR, which
        # run_case pins to $PROJECT_ROOT, never $tmp) — same reason
        # marker_path() is replicated below rather than sourcing hook-lib.sh.
        tdd-require-red.sh:07-existing-new-export-pass.json)
            mkdir -p "$tmp/src" "$PROJECT_ROOT/.claude/.tdd-red"
            printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
            printf '%s\n' "import { bonus } from './item.utils'; it('doubles', () => { expect(bonus()).toBe(2) })" \
                >"$tmp/src/item.utils.test.ts"
            extra_marker="$PROJECT_ROOT/.claude/.tdd-red/$(printf '%s' "$tmp/src/item.utils.test.ts" | tr -c 'A-Za-z0-9._-' '_')"
            {
                date -u +%Y-%m-%dT%H:%M:%SZ
                printf 'sha256:%s\n' "$(sha256sum "$tmp/src/item.utils.test.ts" | cut -d' ' -f1)"
                printf 'missing:%s\n' "bonus"
            } >"$extra_marker"
            ;;
        # Marker digest cases, 08-18: `NN-<create|edit>-<marker>[-nohash]-*`.
        # The project is $tmp, so the marker lives in $tmp/.claude/.tdd-red/.
        # `empty` = empty marker, `nodigest` = no sha256 line, `emptydigest` =
        # `sha256:` with no value, `match`/`other` = right/wrong digest,
        # `unavail` = `sha256:unavailable`. `-nohash` takes sha256sum and
        # shasum off the hook's PATH. `-edit-` adds `bonus`, named missing.
        tdd-require-red.sh:0[89]-*|tdd-require-red.sh:1[0-8]-*)
            project_dir="$tmp"
            mkdir -p "$tmp/src" "$tmp/.claude/.tdd-red"
            printf '%s\n' "import { bonus } from './item.utils'; it('doubles', () => { expect(bonus()).toBe(2) })" \
                >"$tmp/src/item.utils.test.ts"
            [[ "$fixture_name" == *-edit-* ]] && printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
            extra_marker="$tmp/.claude/.tdd-red/$(printf '%s' "$tmp/src/item.utils.test.ts" | tr -c 'A-Za-z0-9._-' '_')"
            case "$fixture_name" in
                *-empty-*) : >"$extra_marker" ;;
                *)
                    date -u +%Y-%m-%dT%H:%M:%SZ >"$extra_marker"
                    case "$fixture_name" in
                        *-emptydigest-*) printf 'sha256:\n' >>"$extra_marker" ;;
                        *-match-*) printf 'sha256:%s\n' "$(sha256sum "$tmp/src/item.utils.test.ts" | cut -d' ' -f1)" >>"$extra_marker" ;;
                        *-other-*) printf 'sha256:%064d\n' 0 >>"$extra_marker" ;;
                        *-unavail-*) printf 'sha256:unavailable\n' >>"$extra_marker" ;;
                    esac
                    printf 'missing:bonus\n' >>"$extra_marker"
                    ;;
            esac
            if [[ "$fixture_name" == *-nohash-* ]]; then
                no_python_bin "$tmp/.bin"
                rm -f "$tmp/.bin/sha256sum" "$tmp/.bin/shasum"
                hook_path="$tmp/.bin"
            fi
            ;;
        # Path cases 08-17: the project is $tmp/p, $tmp/out lies outside it.
        # `-filelink-`: p/docs/link.md → out/id_rsa; `-dirlink-`: p/docs/ext → out;
        # `-unset-`: no CLAUDE_PROJECT_DIR.
        auto-approve-config.sh:0[89]-*|auto-approve-config.sh:[12][0-9]-*)
            mkdir -p "$tmp/p/docs" "$tmp/out"
            project_dir="$tmp/p"
            case "$fixture_name" in
                # `-newlinelink-`: p/docs/ext → a sibling folder named `p` + a newline,
                # holding notes.md: a resolver that drops that newline reads it as the project.
                *-newlinelink-*)
                    mkdir -p "$tmp/p"$'\n'
                    printf 'x\n' >"$tmp/p"$'\n'/notes.md
                    ln -s "$tmp/p"$'\n' "$tmp/p/docs/ext"
                    ;;
                # `-newlinefilelink-`: p/docs/l.md (a FILE link) → p + a newline + /notes.md,
                # a sibling folder: a resolver that drops that newline reads the project's notes.md.
                *-newlinefilelink-*)
                    mkdir -p "$tmp/p"$'\n'
                    printf 'x\n' >"$tmp/p"$'\n'/notes.md
                    ln -s "$tmp/p"$'\n'/notes.md "$tmp/p/docs/l.md"
                    ;;
                # `-dotdotlink-`: p/.claude/l → ext/../x, p/.claude/ext → out.
                *-dotdotlink-*)
                    mkdir -p "$tmp/p/.claude"
                    ln -s "$tmp/out" "$tmp/p/.claude/ext"
                    ln -s ext/../x "$tmp/p/.claude/l"
                    ;;
                *-filelink-*)
                    printf 'k\n' >"$tmp/out/id_rsa"
                    ln -s "$tmp/out/id_rsa" "$tmp/p/docs/link.md"
                    ;;
                *-dirlink-*)
                    printf 'x\n' >"$tmp/out/notes.md"
                    ln -s "$tmp/out" "$tmp/p/docs/ext"
                    ;;
                *-unset-*) project_dir="" ;;
            esac
            ;;
        # A file inside the project linked to a secret outside it, named `.env`.
        protect-files.sh:36-*)
            mkdir -p "$tmp/p/docs" "$tmp/out"
            printf 'K=v\n' >"$tmp/out/.env"
            ln -s "$tmp/out/.env" "$tmp/p/docs/conf.txt"
            project_dir="$tmp/p"
            ;;
        # The session runs inside a worktree: its project dir is the worktree.
        auto-approve-config.sh:0[12]-worktree-*)
            project_dir="$tmp/.claude/worktrees/small-a"
            mkdir -p "$project_dir"
            ;;
        *)
            case "$hook:$expected" in
                tdd-freeze-tests.sh:deny)
                    mkdir -p "$tmp/src"
                    printf '%s\n' "it('keeps the contract', () => { expect(1).toBe(1) })" >"$tmp/src/item.utils.test.ts"
                    ;;
                tdd-require-red.sh:pass)
                    mkdir -p "$tmp/src"
                    printf '%s\n' 'export const value = 1' >"$tmp/src/item.utils.ts"
                    ;;
                # Every git-hook fixture gets the same repo: __MAIN_TREE__ on
                # main, __FEAT_TREE__ a worktree on feat/x, aliases, and two
                # tracked files. `-secrets-` cases add untracked secrets to the
                # feat tree; `-shim-` cases put a git that stalls on
                # `add --dry-run` first on the hook's PATH; `-envmod-`,
                # `-nopy-`, `-badpy-`, `-ignored-`, `-envkeep-`, `-stalias-`
                # are described where they are built below.
                enforce-git-workflow.sh:*)
                    # The fixture repo is the project: only the project's repository is trusted.
                    project_dir="$tmp"
                    git -C "$tmp" init -q -b main
                    git -C "$tmp" config user.email fixture@loopkit.invalid
                    git -C "$tmp" config user.name Fixture
                    git -C "$tmp" config alias.p push
                    git -C "$tmp" config alias.q '!sh -c x'
                    git -C "$tmp" config alias.a p
                    git -C "$tmp" config alias.ci commit
                    git -C "$tmp" config alias.nuke 'clean -fdx'
                    git -C "$tmp" config alias.wa 'worktree add'
                    git -C "$tmp" config alias.rs restore
                    mkdir -p "$tmp/src"
                    printf '%s\n' 'export const x = 1' >"$tmp/src/x.ts"
                    printf '%s\n' 'API_URL=' >"$tmp/.env.example"
                    seed_project "$tmp"
                    git -C "$tmp" add src/x.ts .env.example .claude/project.json
                    git -C "$tmp" commit -q -m seed
                    git -C "$tmp" worktree add -q "$tmp/.feat" -b feat/x
                    # The `-C` commit allow is limited to the project tree and its
                    # worktrees: these fixtures run with the fixture repo as project,
                    # and `__OUT_TREE__` is a separate repo on a feature branch.
                    # `-noproj-`: no CLAUDE_PROJECT_DIR, the hook runs inside the outside repo;
                    # `-projpwd-`: the hook runs in the project tree itself.
                    if [[ "$fixture_name" == *-fa[0-9]-* || "$fixture_name" == *-proj-* || "$fixture_name" == G14.14-* \
                          || "$fixture_name" == *-noproj-* || "$fixture_name" == *-projpwd-* ]]; then
                        project_dir="$tmp"
                        git init -q -b feat/y "$tmp/out"
                        git -C "$tmp/out" -c user.email=fixture@loopkit.invalid -c user.name=Fixture \
                            commit -q --allow-empty -m seed
                        [[ "$fixture_name" != *-noproj-* ]] || { project_dir=""; hook_pwd="$tmp/out"; }
                        [[ "$fixture_name" != *-projpwd-* ]] || hook_pwd="$tmp"
                    fi
                    if [[ "$fixture_name" == *-secrets-* ]]; then
                        mkdir -p "$tmp/.feat/certs"
                        printf '%s\n' key >"$tmp/.feat/certs/a.pem"
                        printf '%s\n' 'API_KEY=x' >"$tmp/.feat/.env.local"
                    fi
                    if [[ "$fixture_name" == *-shim-* ]]; then
                        real_git="$(command -v git)"
                        mkdir -p "$tmp/.shim"
                        printf '#!/bin/sh\ncase " $* " in *" add "*"--dry-run"*) sleep 3 ;; esac\nexec "%s" "$@"\n' \
                            "$real_git" >"$tmp/.shim/git"
                        chmod +x "$tmp/.shim/git"
                        hook_path="$tmp/.shim:$PATH"
                    fi
                    if [[ "$fixture_name" == *-envmod-* ]]; then
                        printf '%s\n' 'API_URL=x' >"$tmp/.feat/.env.example"
                    fi
                    # `-ignored-`: the secrets exist but an untracked .gitignore
                    # hides them, so only a statement run before the add exposes them.
                    if [[ "$fixture_name" == *-ignored-* ]]; then
                        mkdir -p "$tmp/.feat/certs"
                        printf '%s\n' key >"$tmp/.feat/certs/a.pem"
                        printf '%s\n' 'API_KEY=x' >"$tmp/.feat/.env.local"
                        printf '%s\n' '.env*' '*.pem' '!.env.example' >"$tmp/.feat/.gitignore"
                    fi
                    if [[ "$fixture_name" == *-envkeep-* ]]; then
                        printf '%s\n' 'API_URL=' >"$tmp/.feat/.env.sample"
                        printf '%s\n' 'API_URL=' >"$tmp/.feat/.env.template"
                    fi
                    if [[ "$fixture_name" == *-stalias-* ]]; then
                        git -C "$tmp" config alias.st stage
                    fi
                    # `-modified-`: src/x.ts edited in the feat tree; `-staged-`:
                    # edited and staged; `-cycle-`: alias.l1 and alias.l2 call each other.
                    if [[ "$fixture_name" == *-modified-* || "$fixture_name" == *-staged-* ]]; then
                        printf '%s\n' 'export const x = 2' >"$tmp/.feat/src/x.ts"
                    fi
                    if [[ "$fixture_name" == *-staged-* ]]; then
                        git -C "$tmp/.feat" add src/x.ts
                    fi
                    # `-credfile-`: an untracked .credentials.json in the feat tree.
                    if [[ "$fixture_name" == *-credfile-* ]]; then
                        printf '%s\n' '{}' >"$tmp/.feat/.credentials.json"
                    fi
                    if [[ "$fixture_name" == *-cycle-* ]]; then
                        git -C "$tmp" config alias.l1 l2
                        git -C "$tmp" config alias.l2 l1
                    fi
                    # `-nopy-`: no python3 on the hook's PATH; `-badpy-`: a
                    # python3 that prints a plausible row and no end marker.
                    if [[ "$fixture_name" == *-nopy-* || "$fixture_name" == *-badpy-* ]]; then
                        no_python_bin "$tmp/.bin"
                        if [[ "$fixture_name" == *-badpy-* ]]; then
                            printf '#!/bin/sh\nprintf '"'"'commit\\t.\\t0\\t0\\tc:;s:\\t-\\n'"'"'\n' >"$tmp/.bin/python3"
                            chmod +x "$tmp/.bin/python3"
                        fi
                        hook_path="$tmp/.bin"
                    fi
                    # `-ghbody-`: the project is the fixture repo, so a gh body
                    # file resolves inside it; the files sit in the feat tree's
                    # docs/. pr-only-root.md carries the trailer only in the
                    # feat tree (its project-root twin is clean), and pr-out.md
                    # links out of the project to a file that carries it, in the
                    # case file's own scratch dir (removed by its caller).
                    if [[ "$fixture_name" == *-ghbody-* ]]; then
                        project_dir="$tmp"
                        mkdir -p "$tmp/.feat/docs" "$tmp/docs"
                        printf '%s\n' 'Summary.' '' '🤖 Generated with [Claude Code](https://claude.com/claude-code)' \
                            >"$tmp/.feat/docs/pr-sign.md"
                        printf '%s\n' 'Summary.' >"$tmp/.feat/docs/pr-clean.md"
                        printf '%s\n' 'Summary.' 'Claude-Session: https://claude.ai/code/session_x' >"$tmp/.feat/docs/pr-sess.md"
                        printf '%s\n' 'Summary.' 'Co-Authored-By: x' >"$tmp/.feat/docs/pr-only-root.md"
                        printf '%s\n' 'Summary.' >"$tmp/docs/pr-only-root.md"
                        printf '%s\n' 'Summary.' 'Co-Authored-By: x' >"$(dirname "$fixture")/outside-trailer.md"
                        ln -s "$(dirname "$fixture")/outside-trailer.md" "$tmp/.feat/docs/pr-out.md"
                        mkfifo "$tmp/.feat/docs/pr-fifo"
                    fi
                    # `-lp<variant>-`: a loop-to-pr record case (G21), built by lp_git_setup. The
                    # record allow refuses any GIT_CONFIG* in its environment, so the suite's own
                    # two are unset for the hook; its HOME is an empty folder instead.
                    if [[ "$fixture_name" == *-lp*-* ]]; then
                        lp_variant="${fixture_name#*-}"
                        lp_variant="${lp_variant%-*}"
                        lp_git_setup "$tmp" "$lp_variant" || fail "$hook" "$fixture_name" "unknown setup '$lp_variant'"
                        hook_home="$tmp/.home"
                        hook_unset=(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM)
                    fi
                    ;;
            esac
            ;;
    esac
    # A tmp project gets the kit's project.json, unless its case is about a missing one.
    if [[ -n "$project_dir" && "$project_dir" != "$PROJECT_ROOT" && -d "$project_dir" \
          && ! -e "$project_dir/.claude/project.json" && "$fixture_name" != *-noconfig-* ]]; then
        seed_project "$project_dir"
    fi

    local -a hook_cap=(${CASE_TIMEOUT[@]+"${CASE_TIMEOUT[@]}"})
    local cap_s="$CASE_SECONDS"
    [[ "${lp_variant:-}" != lpslowb || "${#hook_cap[@]}" -eq 0 ]] || { hook_cap[3]=7; cap_s=7; }
    set +e
    ( cd "$hook_pwd" && printf '%s' "$input" | PATH="$hook_path" HOME="$hook_home" TMPDIR="$hook_tmp" CLAUDE_PROJECT_DIR="$project_dir" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
        ${hook_unset[@]+"${hook_unset[@]}"} ${hook_cap[@]+"${hook_cap[@]}"} "$HOOKS_DIR/$hook" >"$stdout_file" 2>"$stderr_file" )
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" "$stdout_file")"
    CASES=$((CASES + 1))
    if [[ "$code" -eq 124 || "$code" -eq 137 ]]; then
        fail "$hook" "$(basename "$fixture")" "the hook did not finish within ${cap_s}s (killed, exit $code)"
    fi

    if [[ "$verdict" != "$expected" ]]; then
        fail "$hook" "$(basename "$fixture")" \
            "expected $expected, got $verdict (process exit $code)"
    fi
    if [[ "$verdict" == invalid ]]; then
        fail "$hook" "$(basename "$fixture")" "hook output is not valid JSON"
    fi
    if [[ "$verdict" == crash ]]; then
        fail "$hook" "$(basename "$fixture")" \
            "unexpected non-zero exit $code (only 2 is a legacy deny)"
    fi
    if [[ "$verdict" == deny ]] && ! deny_has_reason "$stdout_file" "$stderr_file"; then
        fail "$hook" "$(basename "$fixture")" "deny has no actionable reason"
    fi
    if ! reason_has_expected "$input" "$stdout_file"; then
        fail "$hook" "$(basename "$fixture")" "reason does not contain the fixture's _expect_reason"
    fi

    [[ -n "$extra_marker" ]] && rm -f "$extra_marker"
    rm -r "$tmp"
}

run_fixture_sweep() {
    local directory hook fixture expected count
    while IFS= read -r directory; do
        hook="$(basename "$directory")"
        [[ "$hook" == _harness || "$hook" == install ]] && continue
        count=0
        while IFS= read -r fixture; do
            count=$((count + 1))
            case "$(basename "$fixture")" in
                *-pass.json) expected=pass ;;
                *-deny.json) expected=deny ;;
                *-ask.json) expected=ask ;;
                *-allow.json) expected=allow ;;
                *) fail "$hook" "$(basename "$fixture")" "name must end in -pass.json, -deny.json, -ask.json or -allow.json"; continue ;;
            esac
            run_case "$hook" "$fixture" "$expected"
        done < <(find "$directory" -maxdepth 1 -type f -name '*.json' | sort)
        [[ "$count" -gt 0 ]] || fail "$hook" "(none)" "hook directory is uncovered"
    done < <(find "$FIXTURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
}

run_harness_reproduction() {
    local tmp fixture output code
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/fixtures/always-pass.sh"
    cp "$FIXTURES_DIR/_harness/01-deny.json" "$tmp/fixtures/always-pass.sh/01-deny.json"
    cp "$FIXTURES_DIR/_harness/always-pass.sh" "$tmp/always-pass.sh"
    chmod +x "$tmp/always-pass.sh"
    set +e
    output="$(HOOKS_DIR="$tmp" FIXTURES_DIR="$tmp/fixtures" PROJECT_ROOT="$PROJECT_ROOT" \
        "$0" --fixtures-only 2>&1)"
    code=$?
    set -e
    if [[ "$code" -eq 0 ]]; then
        fail _harness 01-deny.json "broken hook was not detected"
    elif [[ "$output" != *"always-pass.sh / 01-deny.json"* ]] || \
         [[ "$output" != *"expected deny, got pass"* ]]; then
        fail _harness 01-deny.json "failure does not name hook, fixture, and expected/actual verdict"
    fi
    rm -r "$tmp"
}

run_harness_edges() {
    local tmp output code
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/fixtures/empty.sh"
    cp "$FIXTURES_DIR/_harness/always-pass.sh" "$tmp/empty.sh"
    chmod +x "$tmp/empty.sh"
    set +e
    output="$(HOOKS_DIR="$tmp" FIXTURES_DIR="$tmp/fixtures" PROJECT_ROOT="$PROJECT_ROOT" \
        "$0" --fixtures-only 2>&1)"
    code=$?
    set -e
    if [[ "$code" -eq 0 || "$output" != *"hook directory is uncovered"* ]]; then
        fail _harness empty "zero-fixture hook was not reported as uncovered"
    fi
    rm -r "$tmp"

    tmp="$(mktemp -d)"
    mkdir -p "$tmp/fixtures/crash.sh"
    cp "$FIXTURES_DIR/_harness/01-deny.json" "$tmp/fixtures/crash.sh/01-deny.json"
    cp "$FIXTURES_DIR/_harness/crash.sh" "$tmp/crash.sh"
    chmod +x "$tmp/crash.sh"
    set +e
    output="$(HOOKS_DIR="$tmp" FIXTURES_DIR="$tmp/fixtures" PROJECT_ROOT="$PROJECT_ROOT" \
        "$0" --fixtures-only 2>&1)"
    code=$?
    set -e
    if [[ "$code" -eq 0 || "$output" != *"unexpected non-zero exit 1"* ]]; then
        fail _harness crash "non-deny process failure was not reported as a crash"
    fi
    rm -r "$tmp"
}

run_missing_jq_cases() {
    local tmp hook code output
    tmp="$(mktemp -d)"
    for command in env bash dirname basename date; do
        ln -s "$(command -v "$command")" "$tmp/$command"
    done
    for hook in no-any-type.sh protect-files.sh no-forbidden-icons.sh \
                tdd-freeze-tests.sh tdd-require-red.sh tdd-prove-red.sh \
                prevent-destructive-commands.sh enforce-git-workflow.sh; do
        set +e
        output="$(printf '{}' | PATH="$tmp" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/$hook" 2>&1)"
        code=$?
        set -e
        CASES=$((CASES + 1))
        if [[ "$code" -ne 2 ]]; then
            fail "$hook" jq-absent "expected fail-closed exit 2, got $code"
        elif [[ "$output" != *"jq is not on PATH"* ]]; then
            fail "$hook" jq-absent "exit 2 did not explain the missing prerequisite"
        fi
    done
    rm -r "$tmp"
}

# tdd-prove-red.sh runs the real suite, so its import reader is driven alone:
# one tab-separated case per line, title, test file content (`\\n` for a line
# break), expected symbols.
run_prove_red_symbols() {
    local tmp title content expected actual
    tmp="$(mktemp -d)"
    while IFS=$'\t' read -r title content expected; do
        [[ -z "$title" ]] && continue
        CASES=$((CASES + 1))
        printf '%b\n' "$content" > "$tmp/item.mapper.test.ts"
        actual="$("$HOOKS_DIR/tdd-prove-red.sh" --symbols "$tmp/item.mapper.test.ts" | tr '\n' ' ' | sed 's/ $//')"
        [[ "$actual" == "$expected" ]] \
            || fail tdd-prove-red.sh "symbols: $title" "expected '$expected', got '$actual'"
    done < "$FIXTURES_DIR/_harness/prove-red-symbols.tsv"
    rm -r "$tmp"
}

# hook-guarded.sh: one case = one function call in a fresh bash, run from the
# project root and again from .claude/hooks/ (the result may not depend on $PWD).
guard_call() {
    local dir="$1"; shift
    (cd "$dir" && bash -c 'source "$1" || exit 99; shift; "$@"' _ "$HOOKS_DIR/hook-guarded.sh" "$@" 2>&1)
}

guard_expect() {
    local want="$1" out code dir; shift
    for dir in "$PROJECT_ROOT" "$HOOKS_DIR"; do
        CASES=$((CASES + 1))
        set +e
        out="$(CLAUDE_PROJECT_DIR="$PROJECT_ROOT" guard_call "$dir" "$@")"
        code=$?
        set -e
        [[ "$code" -eq "$want" ]] \
            || fail hook-guarded.sh "$* (from ${dir#"$PROJECT_ROOT"})" "expected exit $want, got $code"
        [[ -z "$out" ]] || fail hook-guarded.sh "$* (from ${dir#"$PROJECT_ROOT"})" "printed '$out'"
    done
}

guard_rel_expect() {
    local want="$1" want_code="$2" project="$3" out code; shift 3
    CASES=$((CASES + 1))
    set +e
    out="$(CLAUDE_PROJECT_DIR="$project" guard_call "$HOOKS_DIR" cwk_guard_rel "$@")"
    code=$?
    set -e
    [[ "$out" == "$want" && "$code" -eq "$want_code" ]] \
        || fail hook-guarded.sh "cwk_guard_rel $*" "expected '$want' exit $want_code, got '$out' exit $code"
}

# W1's check, shared by T1/T2: sourcing <hook> writes no log line, prints
# nothing, sets no trap and leaves extglob off. On a side effect it prints the
# failure text (captured by the caller) and returns 1.
guarded_side_effects() {
    local hook="$1" dir before after out code
    dir="$(mktemp -d)"
    mkdir -p "$dir/.claude"
    printf 'seed\n' > "$dir/.claude/.hook-timings.log"
    before="$(sha256sum < "$dir/.claude/.hook-timings.log")"
    set +e
    out="$(CLAUDE_PROJECT_DIR="$dir" CWK_HOOK_TIMING=1 bash -c \
        'b="$(trap -p)"; source "$1" || exit 99; a="$(trap -p)"
         [[ "$a" == "$b" ]] || echo trap-changed; shopt -p extglob || true' _ "$hook" 2>&1)"
    code=$?
    set -e
    after="$(sha256sum < "$dir/.claude/.hook-timings.log")"
    rm -r "$dir"
    [[ "$code" -eq 0 && "$out" == "shopt -u extglob" && "$before" == "$after" ]] && return 0
    printf "expected exit 0, no trap, extglob off, log unchanged; got exit %s, '%s'" "$code" "$out"
    return 1
}

run_guarded_cases() {
    local p="$PROJECT_ROOT" tmp rel out code hook before after msg
    # W1 the set, folders above it, and the denied set
    for rel in .claude/scripts/a.sh .claude/hooks .github .claude . package.json tsconfig.app.json; do
        guard_expect 0 cwk_is_guarded "$rel"
    done
    for rel in src/x.ts src docs/x.md apps/web/package.json; do
        guard_expect 1 cwk_is_guarded "$rel"
    done
    for rel in .claude/.tdd-red/m .claude/.tdd-red; do
        guard_expect 0 cwk_is_guard_denied "$rel"
    done
    for rel in .claude .claude/hooks/a.sh; do
        guard_expect 1 cwk_is_guard_denied "$rel"
    done

    # W1 sourcing it has no side effect: no log line, no output, no trap, no shopt
    tmp="$(mktemp -d)"
    CASES=$((CASES + 1))
    msg="$(guarded_side_effects "$HOOKS_DIR/hook-guarded.sh")" \
        || fail hook-guarded.sh side-effects "$msg"

    # T1 a SIGPIPE ignore inherited from the caller (GitHub runners) is not a side effect
    CASES=$((CASES + 1))
    msg="$( (trap '' PIPE; guarded_side_effects "$HOOKS_DIR/hook-guarded.sh") )" \
        || fail hook-guarded.sh "T1 side-effects, inherited SIGPIPE ignore" "$msg"

    # T2 a trap set by the sourced file itself is still caught
    cp "$HOOKS_DIR/hook-guarded.sh" "$tmp/trap-guarded.sh"
    printf "trap 'true' EXIT\n" >> "$tmp/trap-guarded.sh"
    CASES=$((CASES + 1))
    if guarded_side_effects "$tmp/trap-guarded.sh" > /dev/null; then
        fail hook-guarded.sh "T2 side-effects, trap set by the hook" "a trap set by the sourced file passed"
    fi

    # W2 cwk_guard_rel
    ln -s "$p" "$tmp/alias"
    guard_rel_expect .claude/hooks/a.sh 0 "$p" "$p/.claude/worktrees/x/.claude/hooks/a.sh"
    guard_rel_expect vite.config.ts 0 "$p" "$p/src/../vite.config.ts"
    guard_rel_expect package.json 0 "$p" "$p//package.json"
    guard_rel_expect package.json 0 "$p" "$p/./package.json"
    guard_rel_expect package.json 0 "$p" ../package.json "$p/src"
    guard_rel_expect package.json 0 "$p" package.json
    guard_rel_expect vite.config.ts 0 "$p" "$tmp/alias/vite.config.ts"
    guard_rel_expect vite.config.ts 0 "$tmp/alias" "$p/vite.config.ts"
    guard_rel_expect "" 1 "$p" "$p/../y"
    guard_rel_expect "" 1 "$p" /etc/passwd
    rm -r "$tmp"

    # W6 hook-guarded.sh missing: the guard hooks fail closed, the Stop hook does not
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    rm -f "$tmp/hook-guarded.sh"
    for hook in protect-files.sh prevent-destructive-commands.sh enforce-git-workflow.sh \
                tdd-require-red.sh tdd-freeze-tests.sh; do
        CASES=$((CASES + 1))
        set +e
        out="$(printf '{}' | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$tmp/$hook" 2>&1)"
        code=$?
        set -e
        [[ "$code" -eq 2 && "$out" == *"BLOCKED: hook-guarded.sh missing"* ]] \
            || fail "$hook" guarded-missing "expected exit 2 with 'BLOCKED: hook-guarded.sh missing', got $code"
    done
    mkdir -p "$tmp/root/.claude"
    CASES=$((CASES + 1))
    set +e
    out="$(CLAUDE_PROJECT_DIR="$tmp/root" CWK_HOOK_TIMING=0 "$tmp/eslint-batch.sh" </dev/null 2>&1)"
    code=$?
    set -e
    [[ "$code" -eq 0 && "$out" == *"WARNING: hook-guarded.sh missing"* ]] \
        || fail eslint-batch.sh guarded-missing "expected exit 0 with 'WARNING: hook-guarded.sh missing', got $code"
    rm -r "$tmp"
}

# P1-P2 (fewer-asks V4): a Write/Edit of .tdd-unfrozen that only removes entries or
# comments them out passes; anything that adds or changes an active line asks.
unfrozen_case() {
    local id="$1" want="$2" tool="$3" input="$4" root="$5" out code
    CASES=$((CASES + 1))
    set +e
    out="$(jq -cn --arg t "$tool" --arg f "$root/.claude/.tdd-unfrozen" --arg c "$root" \
              --argjson i "$input" '{tool_name:$t, cwd:$c, tool_input:($i + {file_path:$f})}' \
        | CLAUDE_PROJECT_DIR="$root" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/protect-files.sh" 2>&1)"
    code=$?
    set -e
    if [[ "$want" == pass ]]; then
        [[ "$code" -eq 0 && -z "$out" ]] || fail protect-files.sh "$id" "expected pass, got exit $code: ${out:0:200}"
    else
        [[ "$code" -eq 0 && "$out" == *'"ask"'* && "$out" == *"guarded path:"* ]] \
            || fail protect-files.sh "$id" "expected ask 'guarded path:', got exit $code: ${out:0:200}"
    fi
}

run_unfrozen_removal_cases() {
    local tmp line1='src/a.test.ts  # U1: r' line2='src/b.test.ts  # U2: r'
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/.claude"
    printf '%s\n%s\n' "$line1" "$line2" > "$tmp/.claude/.tdd-unfrozen"
    unfrozen_case P1.01 pass Edit "$(jq -cn --arg o "$line1"$'\n' '{old_string:$o, new_string:""}')" "$tmp"
    unfrozen_case P1.02 pass Edit "$(jq -cn --arg o "$line1" '{old_string:$o, new_string:""}')" "$tmp"
    unfrozen_case P1.03 pass Edit "$(jq -cn --arg o "$line1" --arg n "# $line1" '{old_string:$o, new_string:$n}')" "$tmp"
    unfrozen_case P1.04 pass Edit "$(jq -cn --arg o "$line1"$'\n'"$line2" --arg n "# $line1"$'\n'"# $line2" \
        '{old_string:$o, new_string:$n}')" "$tmp"
    unfrozen_case P1.05 pass Write "$(jq -cn --arg c "$line2"$'\n' '{content:$c}')" "$tmp"
    unfrozen_case P1.06 pass Write '{"content":""}' "$tmp"
    unfrozen_case P2.01 ask Edit "$(jq -cn --arg o "$line2" --arg n "$line2"$'\n''src/c.test.ts  # U3: r' \
        '{old_string:$o, new_string:$n}')" "$tmp"
    unfrozen_case P2.02 ask Edit "$(jq -cn --arg o "$line1" '{old_string:$o, new_string:"src/a.test.ts  # U1: r2"}')" "$tmp"
    unfrozen_case P2.03 ask Write "$(jq -cn --arg c "$line1"$'\n'"$line2"$'\n''src/c.test.ts' '{content:$c}')" "$tmp"
    unfrozen_case P2.04 ask Edit '{"old_string":"not in the file","new_string":""}' "$tmp"
    unfrozen_case P2.05 ask Edit "$(jq -cn --arg o "$line1" '{old_string:$o, new_string:"src/a.test.ts # commented"}')" "$tmp"
    unfrozen_case P2.06 ask Write "$(jq -cn --arg c "$line1"$'\n'"$line1"$'\n' '{content:$c}')" "$tmp"
    # P2.08: a line break only Python knows (\x1c) is not a line of the file
    printf '# note\034src/evil.test.ts\n' > "$tmp/.claude/.tdd-unfrozen"
    unfrozen_case P2.08 ask Write "$(jq -cn --arg c 'src/evil.test.ts'$'\n' '{content:$c}')" "$tmp"
    rm "$tmp/.claude/.tdd-unfrozen"
    unfrozen_case P2.07 ask Write '{"content":"x"}' "$tmp"
    rm -r "$tmp"
}

guard_hook_run() {
    local dir="$1" hook="$2" input="$3"
    printf '%s' "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$dir/$hook" 2>&1
}

# W8-W11 hardening of the guarded set: a broken list fails closed like a missing
# one, a half-upgraded kit does not pass, a newline in a path does not escape.
run_guarded_hardening_cases() {
    local p="$PROJECT_ROOT" tmp hook out code variant
    # W8 hook-guarded.sh present but empty, or CWK_GUARDED emptied: the five guard hooks refuse
    for variant in empty guarded-empty; do
        tmp="$(mktemp -d)"
        cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
        if [[ "$variant" == empty ]]; then
            : > "$tmp/hook-guarded.sh"
        else
            printf 'CWK_GUARDED=()\n' >> "$tmp/hook-guarded.sh"
        fi
        for hook in protect-files.sh prevent-destructive-commands.sh enforce-git-workflow.sh \
                    tdd-require-red.sh tdd-freeze-tests.sh; do
            CASES=$((CASES + 1))
            set +e
            out="$(guard_hook_run "$tmp" "$hook" '{}')"
            code=$?
            set -e
            [[ "$code" -eq 2 && "$out" == *"hook-guarded.sh missing or broken"* ]] \
                || fail "$hook" "guarded-$variant" "expected exit 2 with 'hook-guarded.sh missing or broken', got $code"
        done
        rm -r "$tmp"
    done

    # W9 half-upgraded kit: the previous hook-lib.sh (no source of hook-guarded.sh) + the current protect-files.sh
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    sed '/^# -* hook-guarded$/,/^# -* cwk_require_jq$/{/cwk_require_jq/!d;}' "$HOOKS_DIR/hook-lib.sh" > "$tmp/hook-lib.sh"
    for rel in package.json .claude/.tdd-red/x; do
        CASES=$((CASES + 1))
        set +e
        out="$(guard_hook_run "$tmp" protect-files.sh \
            "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$p/$rel\",\"content\":\"x\"}}")"
        code=$?
        set -e
        [[ "$code" -eq 2 || "$out" == *'"permissionDecision":"deny"'* || "$out" == *'"permissionDecision": "deny"'* ]] \
            || fail protect-files.sh "old-hook-lib $rel" "expected deny, got exit $code '$out'"
    done
    rm -r "$tmp"

    # W10 a newline inside a path segment stays inside it
    guard_rel_expect package.json 0 "$p" "$p/x"$'\n'"/../package.json"
    guard_rel_expect .claude/.tdd-red/m 0 "$p" "$p/a"$'\n'"/../.claude/.tdd-red/m"

    # W11 near-prefix folders are not guarded; sourcing changes no shell option at all
    guard_expect 1 cwk_is_guarded .git
    guard_expect 1 cwk_is_guarded .claude/hook
    CASES=$((CASES + 1))
    set +e
    out="$(bash -c 'a="$(shopt -p; set +o)"; source "$1" || exit 99; b="$(shopt -p; set +o)"; [[ "$a" == "$b" ]] && echo same || echo changed' _ "$HOOKS_DIR/hook-guarded.sh" 2>&1)"
    set -e
    [[ "$out" == same ]] || fail hook-guarded.sh side-effects-full "shopt/set output changed after sourcing: '$out'"
}

# W12 partial install: the current tdd-freeze-tests.sh beside a hook-lib.sh of the
# previous kit, which defines no CWK_TEST_FILE_RE. An empty regex matches every
# path, so the freeze fails closed and names the stale file.
run_freeze_partial_install_case() {
    local tmp out code
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    sed '/^CWK_TEST_FILE_RE=/d' "$HOOKS_DIR/hook-lib.sh" > "$tmp/hook-lib.sh"
    CASES=$((CASES + 1))
    set +e
    out="$(guard_hook_run "$tmp" tdd-freeze-tests.sh \
        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJECT_ROOT/src/x.ts\",\"content\":\"x\"}}")"
    code=$?
    set -e
    [[ "$code" -eq 0 && "$out" == *'"permissionDecision": "deny"'* && "$out" == *hook-lib.sh* ]] \
        || fail tdd-freeze-tests.sh "partial-install" "expected a deny naming hook-lib.sh, got exit $code '${out:0:160}'"
    rm -r "$tmp"
}

# X1-X11 of docs/work/guard-shell/plan.md: one case per line of the jsonl, each
# turned into a fixture and run through run_case, so it gets the same checks.
run_shell_guard_cases() {
    local file="$FIXTURES_DIR/_harness/shell-guard.jsonl" tmp line id verdict command cwd reason count=0
    local -A seen=()
    local -a lines=()
    if [[ ! -f "$file" ]]; then
        fail prevent-destructive-commands.sh shell-guard.jsonl "case file is missing"
        return 0
    fi
    mapfile -t lines < "$file"
    tmp="$(mktemp -d)"
    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        if ! jq -e 'type == "object" and (.id | type == "string") and (.command | type == "string")
                    and (.verdict | IN("ask", "deny", "pass"))' <<<"$line" >/dev/null 2>&1; then
            fail prevent-destructive-commands.sh shell-guard.jsonl "unparsable or incomplete line: ${line:0:60}"
            continue
        fi
        id="$(jq -r '.id' <<<"$line")"
        verdict="$(jq -r '.verdict' <<<"$line")"
        command="$(jq -r '.command' <<<"$line")"
        cwd="$(jq -r '.cwd // "__PROJECT_ROOT__"' <<<"$line")"
        reason="$(jq -r '.reason // ""' <<<"$line")"
        SHELL_SETUP="$(jq -r '.setup // ""' <<<"$line")"
        if [[ -n "${seen[$id]:-}" ]]; then
            fail prevent-destructive-commands.sh "$id" "duplicate case id"
            continue
        fi
        seen[$id]=1
        if [[ "$verdict" != pass && -z "$reason" ]]; then
            fail prevent-destructive-commands.sh "$id" "ask/deny case has no reason"
            continue
        fi
        count=$((count + 1))
        jq -cn --arg command "$command" --arg cwd "$cwd" --arg reason "$reason" \
            '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}
             + (if $reason != "" then {_expect_reason: $reason} else {} end)' \
            > "$tmp/$id-$verdict.json"
        run_case prevent-destructive-commands.sh "$tmp/$id-$verdict.json" "$verdict"
    done
    SHELL_SETUP=""
    [[ "$count" -gt 0 ]] || fail prevent-destructive-commands.sh shell-guard.jsonl "case file holds no case"
    rm -r "$tmp"
}

# The git cases of docs/specs/light-permissions-git.md (G1-G13): same shape as
# shell-guard.jsonl, run in the git fixture repo. `setup` (secrets, shim, envmod,
# nopy, badpy, ignored, envkeep, stalias) lands in the fixture name, which is
# what run_case keys the repo setup on.
run_git_guard_cases() {
    local file="$FIXTURES_DIR/_harness/git-guard.jsonl" tmp line id verdict command cwd reason setup count=0
    local -A seen=()
    local -a lines=()
    if [[ ! -f "$file" ]]; then
        fail enforce-git-workflow.sh git-guard.jsonl "case file is missing"
        return 0
    fi
    mapfile -t lines < "$file"
    tmp="$(mktemp -d)"
    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        if ! jq -e 'type == "object" and (.id | type == "string") and (.command | type == "string")
                    and (.verdict | IN("ask", "deny", "pass", "allow"))' <<<"$line" >/dev/null 2>&1; then
            fail enforce-git-workflow.sh git-guard.jsonl "unparsable or incomplete line: ${line:0:60}"
            continue
        fi
        id="$(jq -r '.id' <<<"$line")"
        verdict="$(jq -r '.verdict' <<<"$line")"
        command="$(jq -r '.command' <<<"$line")"
        cwd="$(jq -r '.cwd // "__FEAT_TREE__"' <<<"$line")"
        reason="$(jq -r '.reason // ""' <<<"$line")"
        setup="$(jq -r '.setup // "plain"' <<<"$line")"
        if [[ -n "${seen[$id]:-}" ]]; then
            fail enforce-git-workflow.sh "$id" "duplicate case id"
            continue
        fi
        seen[$id]=1
        if [[ "$verdict" != pass && -z "$reason" ]]; then
            fail enforce-git-workflow.sh "$id" "ask/deny case has no reason"
            continue
        fi
        count=$((count + 1))
        [[ -z "${CWK_CASE_PREFIX:-}" || "$id" == "$CWK_CASE_PREFIX"* ]] || continue
        jq -cn --arg command "$command" --arg cwd "$cwd" --arg reason "$reason" \
            '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}
             + (if $reason != "" then {_expect_reason: $reason} else {} end)' \
            > "$tmp/$id-$setup-$verdict.json"
        run_case enforce-git-workflow.sh "$tmp/$id-$setup-$verdict.json" "$verdict"
    done
    [[ "$count" -gt 0 ]] || fail enforce-git-workflow.sh git-guard.jsonl "case file holds no case"
    rm -r "$tmp"
}

# G10: a dry-run past its deadline is stopped so git removes its own index.lock;
# a lock already held is refused without running anything, and left alone.
run_git_add_lock_case() {
    local tmp feat lock input out code verdict
    tmp="$(mktemp -d)"
    feat="$tmp/.feat"
    git -C "$tmp" init -q -b main
    git -C "$tmp" config user.email fixture@loopkit.invalid
    git -C "$tmp" config user.name Fixture
    mkdir -p "$tmp/src"
    printf '%s\n' 'export const x = 1' >"$tmp/src/x.ts"
    git -C "$tmp" add src/x.ts
    git -C "$tmp" commit -q -m seed
    git -C "$tmp" worktree add -q "$feat" -b feat/x
    printf '%s\n' 'export const x = 2' >"$feat/src/x.ts"
    lock="$(git -C "$feat" rev-parse --path-format=absolute --git-path index.lock)"
    printf '#!/bin/sh\nsleep 4\n' >"$tmp/slow-fsmonitor"
    chmod +x "$tmp/slow-fsmonitor"
    git -C "$feat" config core.fsmonitor "$tmp/slow-fsmonitor"
    input="$(jq -cn --arg cwd "$feat" '{tool_name: "Bash", tool_input: {command: "git add src/x.ts"}, cwd: $cwd}')"

    CASES=$((CASES + 1))
    set +e
    out="$(printf '%s' "$input" | CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)"
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" <(printf '%s' "$out"))"
    [[ "$verdict" == deny && "$out" == *timeout* ]] \
        || fail enforce-git-workflow.sh G10.01 "expected deny with timeout, got $verdict '${out:0:120}'"
    [[ ! -e "$lock" ]] || fail enforce-git-workflow.sh G10.01 "index.lock left behind after the timeout"
    git -C "$feat" config --unset core.fsmonitor
    git -C "$feat" add src/x.ts 2>/dev/null || fail enforce-git-workflow.sh G10.01 "a real git add fails after the timeout"

    CASES=$((CASES + 1))
    : >"$lock"
    set +e
    out="$(printf '%s' "$input" | CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)"
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" <(printf '%s' "$out"))"
    [[ "$verdict" == deny && "$out" == *"index.lock exists"* ]] \
        || fail enforce-git-workflow.sh G10.02 "expected deny with index.lock exists, got $verdict '${out:0:120}'"
    [[ -e "$lock" ]] || fail enforce-git-workflow.sh G10.02 "the held lock was removed"
    rm -r "$tmp"
}

# G10.03: a secret list too long for one jq argument still ends in a deny, never in no output.
run_git_add_long_reason_case() {
    local tmp feat input out code verdict i pad
    tmp="$(mktemp -d)"
    feat="$tmp/.feat"
    git -C "$tmp" init -q -b main
    git -C "$tmp" config user.email fixture@loopkit.invalid
    git -C "$tmp" config user.name Fixture
    printf '%s\n' 'export const x = 1' >"$tmp/x.ts"
    git -C "$tmp" add x.ts
    git -C "$tmp" commit -q -m seed
    git -C "$tmp" worktree add -q "$feat" -b feat/x
    pad="$(printf 'p%.0s' $(seq 1 240))"
    for i in $(seq 1 560); do
        : >"$feat/.env.$pad$i"
    done
    input="$(jq -cn --arg cwd "$feat" '{tool_name: "Bash", tool_input: {command: "git add -A"}, cwd: $cwd}')"

    CASES=$((CASES + 1))
    set +e
    out="$(printf '%s' "$input" | CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)"
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" <(printf '%s' "$out"))"
    [[ "$code" -eq 0 && "$verdict" == deny && "$out" == *secret* ]] \
        || fail enforce-git-workflow.sh G10.03 "expected deny naming secrets with exit 0, got rc=$code $verdict '${out:0:120}'"
    rm -r "$tmp"
}

# Fills <dir> with a git dir in bare layout (core.bare=false, core.worktree=.) whose
# config runs `touch <marker>` through core.fsmonitor or a filter's clean command.
make_untrusted_repo() {
    local dir="$1" kind="$2" marker="$3"
    mkdir -p "$dir/objects" "$dir/refs" "$dir/info"
    printf 'ref: refs/heads/main\n' >"$dir/HEAD"
    printf 'payload\n' >"$dir/y.txt"
    {
        printf '[core]\n\trepositoryformatversion = 0\n\tbare = false\n\tworktree = .\n'
        if [[ "$kind" == fsmonitor ]]; then
            printf '\tfsmonitor = touch %s\n' "$marker"
        else
            printf '[filter "x"]\n\tclean = touch %s; cat\n' "$marker"
            printf 'y.txt filter=x\n' >"$dir/info/attributes"
        fi
    } >"$dir/config"
}

# Runs the hook on <command> with <cwd> in the payload, from <run_dir> as process cwd.
# The project is $PROBE_PROJECT, else <cwd>, never the session's. Prints the verdict,
# then the hook's stdout.
git_hook_probe() {
    local command="$1" cwd="$2" run_dir="$3" input out code
    input="$(jq -cn --arg command "$command" --arg cwd "$cwd" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}')"
    set +e
    out="$(cd "$run_dir" && printf '%s' "$input" | CLAUDE_PROJECT_DIR="${PROBE_PROJECT:-$cwd}" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)"
    code=$?
    set -e
    printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out"
}

# G15.01-G15.05: a git dir the agent wrote itself (no `.git` segment) runs nothing
# from its config: no dry-run, an ask naming the directory.
run_git_untrusted_repo_cases() {
    local tmp marker id kind command cwd run_dir out verdict
    local -a specs=(
        "G15.01|fsmonitor|git -C @EVIL add y.txt|@TMP|@TMP"
        "G15.02|fsmonitor|git add y.txt|@EVIL|@EVIL"
        "G15.03|filter|git -C @EVIL add y.txt|@TMP|@TMP"
        "G15.04|fsmonitor|git -C @EVIL add y.txt; true|@TMP|@TMP"
        "G15.05|fsmonitor|git -C @TMP/wt add y.txt|@TMP|@TMP"
    )
    local spec
    for spec in "${specs[@]}"; do
        IFS='|' read -r id kind command cwd run_dir <<<"$spec"
        tmp="$(mktemp -d)"
        marker="$tmp/MARKER"
        make_untrusted_repo "$tmp/evil" "$kind" "$marker"
        if [[ "$id" == G15.05 ]]; then
            mkdir -p "$tmp/wt"
            printf 'gitdir: ../evil\n' >"$tmp/wt/.git"
            cp "$tmp/evil/y.txt" "$tmp/wt/y.txt"
        fi
        command="${command//@EVIL/$tmp/evil}"; command="${command//@TMP/$tmp}"
        cwd="${cwd//@EVIL/$tmp/evil}"; cwd="${cwd//@TMP/$tmp}"
        run_dir="${run_dir//@EVIL/$tmp/evil}"; run_dir="${run_dir//@TMP/$tmp}"
        CASES=$((CASES + 1))
        out="$(git_hook_probe "$command" "$cwd" "$run_dir")"
        verdict="${out%%$'\n'*}"
        [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh "$id" "the repository's own config ran inside the hook ($kind)"
        if [[ "$id" == G15.04 ]]; then
            [[ "$verdict" != pass ]] || fail enforce-git-workflow.sh "$id" "expected no pass, got $verdict"
        else
            [[ "$verdict" == ask && "$out" == *"not a repository the hook can read safely"* ]] \
                || fail enforce-git-workflow.sh "$id" "expected ask naming an unsafe repository, got $verdict '${out:0:160}'"
        fi
        rm -r "$tmp"
    done
}

# G15.06: a real linked worktree (git dir under .git/worktrees/) still passes a plain git add.
run_git_linked_worktree_case() {
    local tmp feat out verdict
    tmp="$(mktemp -d)"
    feat="$tmp/.feat"
    git -C "$tmp" init -q -b main
    git -C "$tmp" config user.email fixture@loopkit.invalid
    git -C "$tmp" config user.name Fixture
    printf '%s\n' 'export const x = 1' >"$tmp/x.ts"
    seed_project "$tmp"
    git -C "$tmp" add x.ts .claude/project.json
    git -C "$tmp" commit -q -m seed
    git -C "$tmp" worktree add -q "$feat" -b feat/x
    printf '%s\n' 'export const y = 1' >"$feat/y.ts"
    CASES=$((CASES + 1))
    out="$(git_hook_probe "git add y.ts" "$feat" "$tmp")"
    verdict="${out%%$'\n'*}"
    [[ "$verdict" == pass ]] || fail enforce-git-workflow.sh G15.06 "expected pass in a linked worktree, got $verdict '${out:0:160}'"
    rm -r "$tmp"
}

# G15.07: a shlex.py in the process cwd is not imported by the hook's parser.
run_git_python_isolation_case() {
    local tmp out verdict
    tmp="$(mktemp -d)"
    printf 'import pathlib\npathlib.Path(%s).touch()\n' "'$tmp/MARKER'" >"$tmp/shlex.py"
    seed_project "$tmp"
    CASES=$((CASES + 1))
    out="$(git_hook_probe "git status" "$tmp" "$tmp")"
    verdict="${out%%$'\n'*}"
    [[ ! -e "$tmp/MARKER" ]] || fail enforce-git-workflow.sh G15.07 "a shlex.py in the cwd ran inside the hook"
    [[ "$verdict" == pass ]] || fail enforce-git-workflow.sh G15.07 "expected pass, got $verdict '${out:0:160}'"
    rm -r "$tmp"
}

# Fails <id> unless the probe output <out> holds the verdict <want> and every needle.
g15_expect() {
    local id="$1" want="$2" out="$3" verdict needle
    shift 3
    verdict="${out%%$'\n'*}"
    CASES=$((CASES + 1))
    if [[ "$verdict" != "$want" ]]; then
        fail enforce-git-workflow.sh "$id" "expected $want, got $verdict '${out:0:200}'"
        return 0
    fi
    for needle in "$@"; do
        [[ "$out" == *"$needle"* ]] || fail enforce-git-workflow.sh "$id" "reason lacks '$needle': '${out:0:300}'"
    done
    return 0
}

# A repository with one commit in <dir>.
make_seed_repo() {
    git init -q -b main "$1"
    git -C "$1" config user.email fixture@loopkit.invalid
    git -C "$1" config user.name Fixture
    printf '%s\n' 'export const x = 1' >"$1/x.ts"
    seed_project "$1"
    git -C "$1" add x.ts .claude/project.json
    git -C "$1" commit -q -m seed
}

UNSAFE_PHRASE="not a repository the hook can read safely"
UNCHECKED_PHRASE="did not check what this stages"

# G15.08-G15.10: a real submodule (git dir under .git/modules/) keeps the secret deny.
# G15.11-G15.14: a worktree of a bare clone and a --separate-git-dir repository: a secret named
# in the call still denies, anything else asks with the warning.
run_git_secret_scope_cases() {
    local tmp out
    tmp="$(mktemp -d)"
    make_seed_repo "$tmp/lib"
    make_seed_repo "$tmp/sup"
    git -C "$tmp/sup" -c protocol.file.allow=always submodule add -q "$tmp/lib" sub >/dev/null 2>&1
    printf 'k\n' >"$tmp/sup/sub/.env.local"
    printf 'v\n' >"$tmp/sup/sub/y.ts"
    out="$(git_hook_probe "git add .env.local" "$tmp/sup/sub" "$tmp")"
    g15_expect G15.08 deny "$out" "would stage a secret"
    out="$(git_hook_probe "git add -A" "$tmp/sup/sub" "$tmp")"
    g15_expect G15.09 deny "$out" "would stage a secret"
    out="$(git_hook_probe "git add y.ts" "$tmp/sup/sub" "$tmp")"
    g15_expect G15.10 pass "$out"

    git clone -q --bare "$tmp/sup" "$tmp/bare.git"
    git -C "$tmp/bare.git" worktree add -q "$tmp/wt" -b feat/x main
    printf 'k\n' >"$tmp/wt/.env.local"
    out="$(git_hook_probe "git add .env.local" "$tmp/wt" "$tmp")"
    g15_expect G15.11 deny "$out" "would stage a secret"
    out="$(git_hook_probe "git add -A" "$tmp/wt" "$tmp")"
    g15_expect G15.12 ask "$out" "$UNSAFE_PHRASE" "$UNCHECKED_PHRASE" "may include secrets" "$tmp/wt"

    git init -q -b main --separate-git-dir "$tmp/sep.git" "$tmp/work"
    printf 'k\n' >"$tmp/work/.env.local"
    out="$(git_hook_probe "git add .env.local" "$tmp/work" "$tmp")"
    g15_expect G15.13 deny "$out" "would stage a secret"
    out="$(git_hook_probe "git add -A" "$tmp/work" "$tmp")"
    g15_expect G15.14 ask "$out" "$UNSAFE_PHRASE" "$UNCHECKED_PHRASE" "may include secrets" "$tmp/work"
    rm -r "$tmp"
}

# G15.15-G15.22: a -C value the shell expands is not resolved: the deny for a target that
# cannot be confirmed, as before the readable-git-dir check.
run_git_expanded_dir_cases() {
    local tmp out id command spec
    local -a specs=(
        'G15.15|git -C ~/proj add .env.local'
        'G15.16|git -C $HOME/proj add .env.local'
        'G15.17|git -C "$HOME/proj" add -A'
        'G15.18|git -C rep* add -A'
        'G15.19|git -C {repo,x} add -A'
        'G15.20|git -C rep? add -A'
        'G15.21|git -C rep[a] add -A'
    )
    tmp="$(mktemp -d)"
    make_seed_repo "$tmp/repo"
    for spec in "${specs[@]}"; do
        id="${spec%%|*}"
        command="${spec#*|}"
        out="$(git_hook_probe "$command" "$tmp/repo" "$tmp")"
        g15_expect "$id" deny "$out" "could not confirm"
    done
    out="$(git_hook_probe 'git -C `pwd` add -A' "$tmp/repo" "$tmp")"
    g15_expect G15.22 deny "$out" "BLOCKED"
    rm -r "$tmp"
}

# G15.23-G15.31: the git-dir test is exact (no `.git` substring, suffix or any `worktrees` parent),
# the rev-parse timeout is not trusted, and the ask names the directory and the unchecked staging.
run_git_unsafe_edge_cases() {
    local tmp marker out id dir real_git spec
    local -a layouts=("G15.23|.github/evil" "G15.24|site.github.io/evil" "G15.25|evil.git" "G15.26|x/worktrees/y")
    for spec in "${layouts[@]}"; do
        id="${spec%%|*}"
        tmp="$(mktemp -d)"
        marker="$tmp/MARKER"
        dir="$tmp/${spec#*|}"
        make_untrusted_repo "$dir" fsmonitor "$marker"
        out="$(git_hook_probe "git -C $dir add y.txt" "$tmp" "$tmp")"
        [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh "$id" "the repository's own config ran inside the hook"
        g15_expect "$id" ask "$out" "$UNSAFE_PHRASE" "$UNCHECKED_PHRASE" "$dir"
        rm -r "$tmp"
    done

    tmp="$(mktemp -d)"
    marker="$tmp/MARKER"
    make_seed_repo "$tmp/repo"
    printf 'v\n' >"$tmp/repo/y.ts"
    real_git="$(command -v git)"
    mkdir "$tmp/shim"
    printf '#!/bin/sh\ncase "$*" in *"rev-parse --absolute-git-dir"*) exec sleep 5 ;; esac\nexec %s "$@"\n' "$real_git" >"$tmp/shim/git"
    chmod +x "$tmp/shim/git"
    out="$(PATH="$tmp/shim:$PATH" git_hook_probe "git add y.ts" "$tmp/repo" "$tmp")"
    g15_expect G15.27 ask "$out" "$UNSAFE_PHRASE" "$tmp/repo"

    out="$(git_hook_probe "mkdir n2; git -C n2 add x" "$tmp" "$tmp")"
    g15_expect G15.28 deny "$out" "unreadable git add"
    make_untrusted_repo "$tmp/evil" fsmonitor "$marker"
    out="$(git_hook_probe "git -C $tmp/evil add y.txt; git add -f x" "$tmp" "$tmp")"
    g15_expect G15.29 deny "$out" "--force"
    [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh G15.29 "the repository's own config ran inside the hook"
    out="$(git_hook_probe "git -C $tmp/nonexistent add x" "$tmp" "$tmp")"
    g15_expect G15.30 ask "$out" "$UNSAFE_PHRASE" "$UNCHECKED_PHRASE" "$tmp/nonexistent"
    mkdir "$tmp/plain"
    out="$(git_hook_probe "git -C $tmp/plain add x" "$tmp" "$tmp")"
    g15_expect G15.31 ask "$out" "$UNSAFE_PHRASE" "$UNCHECKED_PHRASE" "$tmp/plain"
    rm -r "$tmp"
}

# G15.32: a git restore in a --separate-git-dir repository runs no git diff, so its
# core.fsmonitor never fires, and asks.
run_git_restore_planted_case() {
    local tmp out
    tmp="$(mktemp -d)"
    git init -q -b main --separate-git-dir "$tmp/sep.git" "$tmp/work"
    git -C "$tmp/work" config user.email fixture@loopkit.invalid
    git -C "$tmp/work" config user.name Fixture
    mkdir -p "$tmp/work/src"
    printf '%s\n' 'export const x = 1' >"$tmp/work/src/x.ts"
    git -C "$tmp/work" add src/x.ts
    git -C "$tmp/work" commit -q -m seed
    git -C "$tmp/work" switch -q -c feat/x
    git -C "$tmp/work" config core.fsmonitor "touch $tmp/MARKER"
    out="$(git_hook_probe "git restore src/x.ts" "$tmp/work" "$tmp")"
    [[ ! -e "$tmp/MARKER" ]] || fail enforce-git-workflow.sh G15.32 "the repository's own config ran inside the hook"
    g15_expect G15.32 ask "$out" "uncommitted changes"
    rm -r "$tmp"
}

# G15.33-G15.48: only the project's repository (its worktrees and submodules too) is trusted.
# A repository the agent made inside the project with a planted core.fsmonitor runs nothing:
# a git add there asks with no dry-run, any other git call there asks, a cd before git asks.
# git init and git config writes ask; git config reads still pass.
run_git_foreign_repo_cases() {
    local tmp proj marker out
    tmp="$(mktemp -d)"
    proj="$tmp/proj"
    marker="$tmp/MARKER"
    make_seed_repo "$proj"
    git init -q -b main "$proj/sub"
    printf 'a\n' >"$proj/sub/a.txt"
    git -C "$proj/sub" config core.fsmonitor "touch $marker"

    out="$(git_hook_probe "git -C sub add a.txt" "$proj" "$tmp")"
    [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh G15.33 "the planted core.fsmonitor ran inside the hook"
    g15_expect G15.33 ask "$out" "$UNSAFE_PHRASE" "$proj/sub"
    rm -f "$marker"
    out="$(PROBE_PROJECT="$proj" git_hook_probe "git add a.txt" "$proj/sub" "$tmp")"
    [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh G15.34 "the planted core.fsmonitor ran inside the hook"
    g15_expect G15.34 ask "$out" "$UNSAFE_PHRASE"
    rm -f "$marker"
    out="$(PROBE_PROJECT="$proj" git_hook_probe "git status" "$proj/sub" "$tmp")"
    g15_expect G15.35 ask "$out" "outside the project" "$proj/sub"
    out="$(git_hook_probe "git -C sub diff" "$proj" "$tmp")"
    g15_expect G15.36 ask "$out" "outside the project" "$proj/sub"
    out="$(git_hook_probe "cd sub && git status" "$proj" "$tmp")"
    g15_expect G15.37 ask "$out" "a cd earlier"
    # G15.37a-g: a read-only git call after literal cds that all land in the project repo
    # passes; a cd into another repo, a cd the hook cannot read, or a writing call still asks.
    mkdir -p "$proj/d"
    out="$(git_hook_probe "cd $proj && git status && git diff" "$proj" "$tmp")"
    g15_expect G15.37a pass "$out"
    out="$(git_hook_probe "cd $proj/d; git log -1; git branch --show-current" "$proj" "$tmp")"
    g15_expect G15.37b pass "$out"
    out="$(git_hook_probe "cd d && git diff --stat main -- x.ts" "$proj" "$tmp")"
    g15_expect G15.37c pass "$out"
    out="$(git_hook_probe "cd $proj/d && cd ../sub && git status" "$proj" "$tmp")"
    g15_expect G15.37d ask "$out" "a cd earlier"
    [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh G15.37d "the planted core.fsmonitor ran inside the hook"
    out="$(git_hook_probe "cd \"\$D\" && git status" "$proj" "$tmp")"
    g15_expect G15.37e ask "$out" "a cd earlier"
    out="$(git_hook_probe "cd $proj/d && git branch newb" "$proj" "$tmp")"
    g15_expect G15.37f ask "$out" "a cd earlier"
    out="$(git_hook_probe "cd ~ && git status" "$proj" "$tmp")"
    g15_expect G15.37g ask "$out" "a cd earlier"
    git init -q --bare "$proj/d/evil"
    git -C "$proj/d/evil" config core.fsmonitor "touch $marker"
    out="$(git_hook_probe "cd d/evil && git status" "$proj" "$tmp")"
    g15_expect G15.37h ask "$out" "a cd earlier"
    [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh G15.37h "the planted core.fsmonitor ran inside the hook"
    out="$(git_hook_probe "cd $proj/d/evil && git log -1" "$proj" "$tmp")"
    g15_expect G15.37i ask "$out" "a cd earlier"
    out="$(git_hook_probe "git config core.fsmonitor x" "$proj" "$tmp")"
    g15_expect G15.38 ask "$out" "git config writes"
    out="$(git_hook_probe "git init x" "$proj" "$tmp")"
    g15_expect G15.39 ask "$out" "git init"
    out="$(git_hook_probe "git config --get user.name" "$proj" "$tmp")"
    g15_expect G15.40 pass "$out"
    out="$(git_hook_probe "git config user.name" "$proj" "$tmp")"
    g15_expect G15.41 pass "$out"
    out="$(git_hook_probe "git status" "$proj" "$tmp")"
    g15_expect G15.42 pass "$out"
    out="$(git_hook_probe "git config get user.name" "$proj" "$tmp")"
    g15_expect G15.43 pass "$out"
    out="$(git_hook_probe "git config --list --show-origin" "$proj" "$tmp")"
    g15_expect G15.44 pass "$out"
    out="$(git_hook_probe "git config --unset user.name" "$proj" "$tmp")"
    g15_expect G15.45 ask "$out" "git config writes"
    out="$(git_hook_probe "git config --global core.hooksPath x" "$proj" "$tmp")"
    g15_expect G15.46 ask "$out" "git config writes"

    git -C "$proj" worktree add -q "$proj/.feat" -b feat/x
    out="$(PROBE_PROJECT="$proj" git_hook_probe "git status" "$proj/.feat" "$tmp")"
    g15_expect G15.47 pass "$out"
    make_seed_repo "$tmp/lib"
    git -C "$proj" -c protocol.file.allow=always submodule add -q "$tmp/lib" lib >/dev/null 2>&1
    out="$(PROBE_PROJECT="$proj" git_hook_probe "git status" "$proj/lib" "$tmp")"
    g15_expect G15.48 pass "$out"
    [[ ! -e "$marker" ]] || fail enforce-git-workflow.sh G15.48 "the planted core.fsmonitor ran"
    rm -r "$tmp"
}

# Runs <hook> on <input json> with <project> as CLAUDE_PROJECT_DIR. Prints the verdict, then stdout.
project_hook_probe() {
    local hook="$1" project="$2" input="$3" out code
    local -a cap=(${CASE_TIMEOUT[@]+"${CASE_TIMEOUT[@]}"})
    [[ -z "${PROBE_SECONDS:-}" || "${#cap[@]}" -eq 0 ]] || cap[3]="$PROBE_SECONDS"
    set +e
    out="$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$project" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
        ${cap[@]+"${cap[@]}"} "$HOOKS_DIR/$hook" 2>/dev/null)"
    code=$?
    set -e
    printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out"
}

# Copies the repo's own .claude/project.json into <dir>/.claude/; with --reader, also
# project_config.py into <dir>/.claude/hooks/ (the addon cases).
seed_project() {
    mkdir -p "$1/.claude"
    cp "$PROJECT_ROOT/.claude/project.json" "$1/.claude/project.json"
    if [[ "${2:-}" == --reader ]]; then
        mkdir -p "$1/.claude/hooks"
        cp "$HOOKS_DIR/project_config.py" "$1/.claude/hooks/project_config.py"
    fi
}

# Writes <json text> into <project>/.claude/project.json.
write_project_json() {
    mkdir -p "$1/.claude"
    printf '%s\n' "$2" >"$1/.claude/project.json"
}

# Fails <id> unless `project_config.py roots <project>` exits <code> and prints exactly <stdout>.
pc_roots_expect() {
    local id="$1" project="$2" code="$3" want="$4" out rc
    CASES=$((CASES + 1))
    out="$(python3 -I -B "$HOOKS_DIR/project_config.py" roots "$project" 2>/dev/null; printf x)"
    out="${out%x}"
    rc="$(python3 -I -B "$HOOKS_DIR/project_config.py" roots "$project" >/dev/null 2>&1; echo $?)"
    [[ "$rc" == "$code" ]] || { fail project_config.py "$id" "expected exit $code, got $rc"; return 0; }
    [[ "$out" == "$want" ]] || fail project_config.py "$id" "expected stdout '$want', got '$out'"
    return 0
}

# PC1-PC15 (app-roots-codegen step 1): the one reader of .claude/project.json. Absent is
# empty; anything malformed exits 3 with nothing on stdout, so no caller widens a pass.
run_project_config_cases() {
    local tmp out rc root bad deep i
    tmp="$(mktemp -d)"
    write_project_json "$tmp/p1" '{"schema_version":1,"app_roots":["frontend","backend"],"codegen_commands":[]}'
    pc_roots_expect PC1 "$tmp/p1" 0 $'frontend\nbackend\n'

    write_project_json "$tmp/p2" '{"schema_version":1,"app_roots":[],"codegen_commands":[["supabase","gen","types"]]}'
    CASES=$((CASES + 1))
    out="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import project_config as p; print(p.load(sys.argv[2]).codegen_commands)' \
        "$HOOKS_DIR" "$tmp/p2" 2>&1)" || true
    [[ "$out" == "(('supabase', 'gen', 'types'),)" ]] || fail project_config.py PC2 "load returned '$out'"

    mkdir -p "$tmp/p3"
    pc_roots_expect PC3 "$tmp/p3" 0 ""
    CASES=$((CASES + 1))
    python3 -I -B "$HOOKS_DIR/project_config.py" check "$tmp/p3" >/dev/null 2>&1 \
        || fail project_config.py PC3 "check on an absent file must exit 0"

    write_project_json "$tmp/p4" '{"schema_version":1,'
    pc_roots_expect PC4 "$tmp/p4" 3 ""
    CASES=$((CASES + 1))
    rc=0
    out="$(python3 -I -B "$HOOKS_DIR/project_config.py" check "$tmp/p4" 2>&1)" || rc=$?
    [[ "$rc" == 3 && "$out" == *project.json* ]] || fail project_config.py PC4 "check: rc=$rc '$out'"

    write_project_json "$tmp/p5" '{"schema_version":1,"app_roots":[],"codegen_commands":[],"extra":1}'
    pc_roots_expect PC5 "$tmp/p5" 3 ""
    CASES=$((CASES + 1))
    out="$(python3 -I -B "$HOOKS_DIR/project_config.py" check "$tmp/p5" 2>&1)" || true
    [[ "$out" == *extra* ]] || fail project_config.py PC5 "reason does not name the key: '$out'"

    write_project_json "$tmp/p6a" '{"schema_version":2,"app_roots":[],"codegen_commands":[]}'
    pc_roots_expect PC6 "$tmp/p6a" 3 ""
    write_project_json "$tmp/p6b" '{"app_roots":[],"codegen_commands":[]}'
    pc_roots_expect PC6 "$tmp/p6b" 3 ""

    i=0
    for root in '../x' '/abs' '.' 'a/../b' './frontend' 'frontend/' 'front//end' 'front*' 'a\\b' 'a\nb'; do
        i=$((i + 1))
        write_project_json "$tmp/p7-$i" "{\"schema_version\":1,\"app_roots\":[\"$root\"],\"codegen_commands\":[]}"
        pc_roots_expect "PC7[$root]" "$tmp/p7-$i" 3 ""
    done

    i=0
    for bad in '"supabase gen types"' '[]' '[""]'; do
        i=$((i + 1))
        write_project_json "$tmp/p8-$i" "{\"schema_version\":1,\"app_roots\":[],\"codegen_commands\":[$bad]}"
        pc_roots_expect "PC8[$bad]" "$tmp/p8-$i" 3 ""
    done

    write_project_json "$tmp/p13" '{"schema_version":1,"app_roots":["frontend","frontend"],"codegen_commands":[]}'
    pc_roots_expect PC13 "$tmp/p13" 3 ""

    write_project_json "$tmp/real" '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[]}'
    mkdir -p "$tmp/p9/.claude"
    ln -s "$tmp/real/.claude/project.json" "$tmp/p9/.claude/project.json"
    pc_roots_expect PC9 "$tmp/p9" 3 ""

    mkdir -p "$tmp/p10/.claude"
    { printf '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[]'
      head -c 70000 /dev/zero | tr '\0' ' '
      printf '}\n'; } >"$tmp/p10/.claude/project.json"
    pc_roots_expect PC10 "$tmp/p10" 3 ""

    deep="$(printf '[%.0s' $(seq 1 5000))$(printf ']%.0s' $(seq 1 5000))"
    write_project_json "$tmp/p15a" "$deep"
    pc_roots_expect PC15 "$tmp/p15a" 3 ""
    write_project_json "$tmp/p15b" '{"schema_version":true,"app_roots":["frontend"],"codegen_commands":[]}'
    pc_roots_expect PC15 "$tmp/p15b" 3 ""
    write_project_json "$tmp/p15c" '{"schema_version":1.0,"app_roots":["frontend"],"codegen_commands":[]}'
    pc_roots_expect PC15 "$tmp/p15c" 3 ""
    write_project_json "$tmp/p15d" '["frontend"]'
    pc_roots_expect PC15 "$tmp/p15d" 3 ""
    out="$(project_hook_probe prevent-destructive-commands.sh "$tmp/p15a" \
        "$(jq -cn --arg cwd "$tmp/p15a" '{tool_name:"Bash",tool_input:{command:"echo x > docs/a.md"},cwd:$cwd}')")"
    g15_expect PC15 ask "$out" "rerun install.sh on this project, or /kit:init"

    out="$(project_hook_probe protect-files.sh "$PROJECT_ROOT" \
        "$(jq -cn --arg f "$PROJECT_ROOT/.claude/project.json" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"a",new_string:"b"}}')")"
    g15_expect PC12 ask "$out" "guarded path"
    out="$(shell_guard_probe "$HOOKS_DIR" "" 'echo {} > .claude/project.json')"
    g15_expect PC12 ask "$out" "guarded path"

    mkdir -p "$tmp/p16/.claude" "$tmp/p16/frontend"
    mkfifo "$tmp/p16/.claude/project.json"
    rc=0
    timeout 5 python3 -I -B "$HOOKS_DIR/project_config.py" roots "$tmp/p16" >/dev/null 2>&1 || rc=$?
    CASES=$((CASES + 1))
    [[ "$rc" == 3 ]] || fail project_config.py PC16 "a FIFO project.json: expected exit 3, got $rc"
    out="$(PROBE_SECONDS=5 pf_probe "$tmp/p16" Edit frontend/vite.config.ts)"
    g15_expect PC16 ask "$out" "rerun install.sh on this project, or /kit:init"

    i=0
    for root in '.claude' '.claude/x' '.git' 'node_modules/a' '-x'; do
        i=$((i + 1))
        write_project_json "$tmp/p17-$i" "{\"schema_version\":1,\"app_roots\":[\"$root\"],\"codegen_commands\":[]}"
        pc_roots_expect "PC17[$root]" "$tmp/p17-$i" 3 ""
    done
    write_project_json "$tmp/p17-ok" '{"schema_version":1,"app_roots":["a/-x","a.claude"],"codegen_commands":[]}'
    pc_roots_expect PC17 "$tmp/p17-ok" 0 $'a/-x\na.claude\n'

    mkdir -p "$tmp/p18/real"
    ln -s real "$tmp/p18/fe"
    write_project_json "$tmp/p18" '{"schema_version":1,"app_roots":["fe"],"codegen_commands":[]}'
    pc_roots_expect PC18 "$tmp/p18" 3 ""
    mkdir -p "$tmp/p18b/real/sub"
    ln -s real "$tmp/p18b/fe"
    write_project_json "$tmp/p18b" '{"schema_version":1,"app_roots":["fe/sub"],"codegen_commands":[]}'
    pc_roots_expect PC18 "$tmp/p18b" 3 ""

    write_project_json "$tmp/p19" '{"schema_version":1,"app_roots":["a"],"app_roots":["b"],"codegen_commands":[]}'
    pc_roots_expect PC19 "$tmp/p19" 3 ""

    pc_roots_expect PC14 "" 0 ""
    mkdir -p "$tmp/rel/.claude"
    cp "$tmp/real/.claude/project.json" "$tmp/rel/.claude/project.json"
    out="$(cd "$tmp" && python3 -I -B "$HOOKS_DIR/project_config.py" roots rel 2>/dev/null; echo "rc=$?")"
    CASES=$((CASES + 1))
    [[ "$out" == "rc=0" ]] || fail project_config.py PC14 "a relative project dir was read: '$out'"
    # PC20: reading a directory as project.json leaves no descriptor open.
    mkdir -p "$tmp/p20/.claude/project.json"
    out="$("${CASE_TIMEOUT[@]+"${CASE_TIMEOUT[@]}"}" python3 -I -B -c '
import os, sys
sys.path.insert(0, sys.argv[1])
import project_config
before = len(os.listdir("/proc/self/fd"))
for _ in range(20):
    try:
        project_config._read(sys.argv[2])
    except (project_config.ConfigError, OSError):
        pass
print(len(os.listdir("/proc/self/fd")) - before)
' "$HOOKS_DIR" "$tmp/p20/.claude/project.json" 2>&1)"
    CASES=$((CASES + 1))
    [[ "$out" == 0 ]] || fail project_config.py PC20 "a directory project.json leaked descriptors: '${out:0:200}'"
    rm -r "$tmp"
}

# Prints `project_config.py shell <project>` with NUL records turned into lines, then `rc=<n>`.
pc_shell() {
    local rc=0 out
    out="$(python3 -I -B "$HOOKS_DIR/project_config.py" shell "$1" 2>/dev/null | tr '\0' '\n'; printf 'x')" || true
    python3 -I -B "$HOOKS_DIR/project_config.py" shell "$1" >/dev/null 2>&1 || rc=$?
    printf '%src=%s\n' "${out%x}" "$rc"
}

# Fails <id> unless `shell <project>` exits <code>, prints only `#status=<code>` and names
# <needle> on stderr.
pc_shell_reject() {
    local id="$1" project="$2" code="$3" needle="$4" err
    CASES=$((CASES + 1))
    err="$(python3 -I -B "$HOOKS_DIR/project_config.py" shell "$project" 2>&1 >/dev/null)" || true
    [[ "$(pc_shell "$project")" == $'#status='"$code"$'\nrc='"$code" ]] \
        || { fail project_config.py "$id" "expected only #status=$code and exit $code, got '$(pc_shell "$project" | head -c 200)'"; return 0; }
    [[ -z "$needle" || "$err" == *"$needle"* ]] || fail project_config.py "$id" "reason does not name '$needle': '$err'"
    return 0
}

# PC21-PC32 (project-config step 1): schema 2, the `shell` records, `defaults`. Expected values
# are hand-written; the icon names come from .claude/rules/09-icons.md, never from the reader.
run_project_config_v2_cases() {
    local tmp out want icons v2 py
    tmp="$(mktemp -d)"
    icons="$(sed -n '/heroicons names:/,/\.$/p' "$PROJECT_ROOT/.claude/rules/09-icons.md" \
        | grep -o '`[A-Za-z]*`' | tr -d '`' | paste -sd'|' -)"
    py="(^|[/[:space:]\"'])(app/(services)(/[A-Za-z0-9_./-]*)?\\.py|tests/((services)/[A-Za-z0-9_./-]*)?test_[A-Za-z0-9_]*\\.py)"
    want="#status=0
protected_dirs_ere=src|shared|\\.claude|public|node_modules|dist
protected_dirs_text=src/, shared/, .claude/, public/, node_modules/, dist/
protected_branches=main
protected_branches=master
test_command=pnpm
test_command=test:run
formatter=prettier
formatter=--write
linter=eslint
env_suffix_ere=example|sample|template
icons_ere=$icons
tdd_layers_ere=repository|services|mapper|utils
py_target_ere=$py
module_root=app
tests_root=tests
#end=15
rc=0"
    v2="{\"schema_version\":2,\"app_roots\":[],\"codegen_commands\":[],
 \"data_client\":{\"module\":\"lib/client\",\"own_path\":\"lib/client.ts\",
  \"composition_roots\":[\"main.tsx\",\"routes/__root.tsx\"],
  \"shared_dirs\":[\"components/\",\"hooks/\",\"lib/\",\"types/\",\"stores/\",\"config/\"]},
 \"protected_dirs\":[\"src\",\"shared\",\".claude\",\"public\",\"node_modules\",\"dist\"],
 \"protected_branches\":[\"main\",\"master\"],\"test_command\":[\"pnpm\",\"test:run\"],
 \"formatter\":[\"prettier\",\"--write\"],\"linter\":\"eslint\",
 \"env_template_suffixes\":[\"example\",\"sample\",\"template\"],
 \"forbidden_icons\":$(printf '%s' "$icons" | jq -Rc 'split("|")'),
 \"tdd_layers\":[\"repository\",\"services\",\"mapper\",\"utils\"],
 \"fastapi\":{\"module_root\":\"app\",\"tests_root\":\"tests\",\"test_first_dirs\":[\"services\"],
  \"session_names\":[\"db\",\"session\",\"async_session\"],\"external_clients\":{}}}"

    write_project_json "$tmp/p21" "$v2"
    CASES=$((CASES + 1))
    out="$(pc_shell "$tmp/p21")"
    [[ "$out" == "$want" ]] || fail project_config.py PC21 "schema-2 shell records differ: '$out'"

    write_project_json "$tmp/p22" '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[["supabase","gen","types"]]}'
    mkdir -p "$tmp/p22/frontend"
    CASES=$((CASES + 1))
    out="$(pc_shell "$tmp/p22")"
    [[ "$out" == "$(printf '%s' "$want" | sed -e 's/^#status=0$/#status=0\napp_roots=frontend/' -e 's/^#end=15$/#end=16/')" ]] \
        || fail project_config.py PC22 "a schema-1 file did not keep its root and take the defaults: '$out'"
    CASES=$((CASES + 1))
    out="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import project_config as p; print(p.load(sys.argv[2]).codegen_commands)' \
        "$HOOKS_DIR" "$tmp/p22" 2>&1)" || true
    [[ "$out" == "(('supabase', 'gen', 'types'),)" ]] || fail project_config.py PC22 "a schema-1 file lost its codegen: '$out'"

    write_project_json "$tmp/p23" "$(printf '%s' "$v2" | jq -c '.protected_dirs = [".claude", "a.b"]')"
    CASES=$((CASES + 1))
    out="$(pc_shell "$tmp/p23" | grep '^protected_dirs_')"
    [[ "$out" == $'protected_dirs_ere=\\.claude|a\\.b\nprotected_dirs_text=.claude/, a.b/' ]] \
        || fail project_config.py PC23 "protected dirs are not ERE-escaped: '$out'"

    mkdir -p "$tmp/p24"
    pc_shell_reject PC24 "$tmp/p24" 4 "missing"
    pc_roots_expect PC24 "$tmp/p24" 0 ""
    CASES=$((CASES + 1))
    python3 -I -B "$HOOKS_DIR/project_config.py" check "$tmp/p24" >/dev/null 2>&1 \
        || fail project_config.py PC24 "check on an absent file must still exit 0"

    write_project_json "$tmp/p25a" "$(printf '%s' "$v2" | jq -c '.schema_version = 4')"
    pc_shell_reject PC25 "$tmp/p25a" 3 "schema_version"
    write_project_json "$tmp/p25b" "$(printf '%s' "$v2" | jq -c 'del(.protected_branches)')"
    pc_shell_reject PC25 "$tmp/p25b" 3 "protected_branches"
    write_project_json "$tmp/p25c" "$(printf '%s' "$v2" | jq -c '.extra = 1')"
    pc_shell_reject PC25 "$tmp/p25c" 3 "extra"
    write_project_json "$tmp/p25d" "$(printf '%s' "$v2" | jq -c '.data_client.extra = 1')"
    pc_shell_reject PC25 "$tmp/p25d" 3 "extra"

    local -a bad=(
        'protected_branches|.protected_branches = ["../x"]'
        'protected_branches|.protected_branches = ["-x"]'
        'protected_branches|.protected_branches = ["a b"]'
        'protected_dirs|.protected_dirs = [".."]'
        'env_template_suffixes|.env_template_suffixes = ["ex.ample"]'
        'tdd_layers|.tdd_layers = ["Utils"]'
        'test_command|.test_command = []'
        'test_command|.test_command = ["pnpm", "a\nb"]'
        'formatter|.formatter = ["../x"]'
        'linter|.linter = "a/b"'
        'own_path|.data_client.own_path = "lib/other.ts"'
        'module_root|.fastapi.module_root = "app/"'
        'external_clients|.fastapi.external_clients = {"9x": ["core/"]}'
    )
    local entry i=0
    for entry in "${bad[@]}"; do
        i=$((i + 1))
        write_project_json "$tmp/p26-$i" "$(printf '%s' "$v2" | jq -c "${entry#*|}")"
        pc_shell_reject "PC26[${entry%%|*}]" "$tmp/p26-$i" 3 "${entry%%|*}"
    done

    pc_shell_reject PC27 "" 5 ""
    pc_shell_reject PC27 "rel/p" 5 ""

    write_project_json "$tmp/p28" "$(printf '%s' "$v2" | jq -c '.formatter = [] | .linter = ""')"
    CASES=$((CASES + 1))
    out="$(pc_shell "$tmp/p28")"
    [[ "$out" == "$(printf '%s' "$want" | sed -e '/^formatter=/d' -e 's/^linter=eslint$/linter=/' -e 's/^#end=15$/#end=13/')" ]] \
        || fail project_config.py PC28 "formatter [] and linter \"\" must give empty records: '$out'"

    write_project_json "$tmp/p29" "$(printf '%s' "$v2" | jq -c '.fastapi.module_root = "srv" | .fastapi.test_first_dirs = ["domain"]')"
    CASES=$((CASES + 1))
    out="$(pc_shell "$tmp/p29" | sed -n 's/^py_target_ere=//p')"
    if [[ -z "$out" ]]; then
        fail project_config.py PC29 "no py_target_ere record"
    else
        [[ "srv/domain/x.py" =~ $out && "tests/domain/test_x.py" =~ $out ]] \
            || fail project_config.py PC29 "the derived target misses srv/domain: '$out'"
        [[ ! "app/services/x.py" =~ $out && ! "srv/domain_old/x.py" =~ $out ]] \
            || fail project_config.py PC29 "the derived target still matches the default or a lookalike: '$out'"
    fi

    CASES=$((CASES + 1))
    cmp -s <(python3 -I -B "$HOOKS_DIR/project_config.py" defaults 2>/dev/null) "$PROJECT_ROOT/.claude/project.json" \
        || fail project_config.py PC30 "the repo's project.json is not the reader's defaults byte for byte"
    CASES=$((CASES + 1))
    [[ "$(pc_shell "$PROJECT_ROOT")" == "$want" ]] || fail project_config.py PC30 "the repo's project.json shell output differs from PC21"

    write_project_json "$tmp/p31" "$(printf '%s' "$v2" | jq -c '.fastapi.external_clients = {"app.core.qdrant": ["core/", "services/search.py"]}')"
    CASES=$((CASES + 1))
    [[ "$(pc_shell "$tmp/p31" | head -1)" == "#status=0" ]] || fail project_config.py PC31 "a real external_clients map was refused"

    CASES=$((CASES + 1))
    cmp -s <(python3 -I -B "$HOOKS_DIR/project_config.py" defaults --shell 2>/dev/null) "$HOOKS_DIR/project-defaults.records" \
        && cmp -s "$HOOKS_DIR/project-defaults.records" <(python3 -I -B "$HOOKS_DIR/project_config.py" shell "$tmp/p21" 2>/dev/null | tr '\0' '\n') \
        || fail project_config.py PC32 "project-defaults.records is not the reader's default records"
    rm -r "$tmp"
}

# PC33-PC35 (project-config review 1): secret suffix words, a leading dash, the writer's temp file.
run_project_config_review1_cases() {
    local tmp word d victim
    tmp="$(mktemp -d)"
    for word in local production development prod dev staging test; do
        pv_project "$tmp/p33-$word" ".env_template_suffixes = [\"example\", \"$word\"]"
        pc_shell_reject "PC33[$word]" "$tmp/p33-$word" 3 "env_template_suffixes"
    done
    pv_project "$tmp/p34a" '.linter = "-x"'
    pc_shell_reject PC34 "$tmp/p34a" 3 "linter"
    pv_project "$tmp/p34b" '.formatter = ["-x", "--write"]'
    pc_shell_reject PC34 "$tmp/p34b" 3 "formatter"
    pv_project "$tmp/p34c" '.test_command = ["-x"]'
    pc_shell_reject PC34 "$tmp/p34c" 3 "test_command"

    d="$tmp/p35"
    victim="$d/victim"
    pv_project "$d"
    printf 'keep\n' >"$victim"
    ln -s "$victim" "$d/.claude/project.json.tmp"
    CASES=$((CASES + 1))
    python3 -I -B "$HOOKS_DIR/project_config.py" wire "$d" fastapi >/dev/null 2>&1 || true
    [[ "$(cat "$victim")" == keep ]] || fail project_config.py PC35 "the writer followed a planted .tmp symlink onto another file"
    CASES=$((CASES + 1))
    [[ -f "$d/.claude/project.json" && ! -L "$d/.claude/project.json" ]] \
        && jq -e '.protected_dirs | index("alembic")' "$d/.claude/project.json" >/dev/null 2>&1 \
        || fail project_config.py PC35 "the wired file is not a regular file holding the addon's dirs"
    rm -r "$tmp"
}

# Writes the reader's defaults, through jq filter <filter>, as <dir>/.claude/project.json.
pv_project() {
    mkdir -p "$1/.claude" "$1/src" "$1/docs"
    python3 -I -B "$HOOKS_DIR/project_config.py" defaults | jq "${2:-.}" >"$1/.claude/project.json"
}

# Fails <id> unless the first line of <out> is <verdict> (and, with a 4th arg, the rest
# holds it; with a 5th, the rest lacks it).
pv_expect() {
    local id="$1" want="$2" out="$3" needle="${4:-}" absent="${5:-}"
    CASES=$((CASES + 1))
    if [[ "${out%%$'\n'*}" != "$want" ]]; then
        fail project-values "$id" "expected $want, got '${out:0:240}'"
    elif [[ -n "$needle" && "$out" != *"$needle"* ]]; then
        fail project-values "$id" "reason lacks '$needle': '${out:0:240}'"
    elif [[ -n "$absent" && "$out" == *"$absent"* ]]; then
        fail project-values "$id" "reason holds '$absent': '${out:0:240}'"
    fi
    return 0
}

# A python3 on PATH that logs each call's arguments to <dir>/calls, then runs the real one.
pv_python_spy() {
    mkdir -p "$1/bin"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/calls"\nexec %s "$@"\n' \
        "$1" "$(command -v python3)" >"$1/bin/python3"
    chmod +x "$1/bin/python3"
    : >"$1/calls"
}

# PV1-PV3, PX1, PX10, PX11, PX13 (project-config step 2): the loader and the TDD regexes.
run_project_values_cases() {
    local tmp out p rc stale junk
    tmp="$(mktemp -d)"
    p="$tmp/pv1"
    pv_project "$p" '.tdd_layers = ["repository", "usecase"]'
    out="$(project_hook_probe tdd-require-red.sh "$p" \
        "$(jq -cn --arg f "$p/src/a.usecase.ts" '{tool_name:"Write",tool_input:{file_path:$f,content:"export const a = 1"}}')")"
    pv_expect PV1 deny "$out"
    out="$(project_hook_probe tdd-require-red.sh "$p" \
        "$(jq -cn --arg f "$p/src/a.mapper.ts" '{tool_name:"Write",tool_input:{file_path:$f,content:"export const a = 1"}}')")"
    pv_expect PV1 pass "$out"
    pv_expect PV1 deny "$(pd_probe "$p" 'echo x > src/a.usecase.ts')"

    p="$tmp/pv2"
    pv_project "$p" '.fastapi.module_root = "srv"'
    pv_expect PV2 deny "$(pd_probe "$p" 'echo x > srv/services/a.py')" "Python test-first layer"
    out="$(pd_probe "$p" 'echo x > app/services/a.py')"
    pv_expect PV2 "${out%%$'\n'*}" "$out" "" "Python test-first layer"

    p="$tmp/pv3"
    pv_project "$p" '.app_roots = ["frontend"]'
    mkdir -p "$p/frontend"
    out="$(cd "$p" && CLAUDE_PROJECT_DIR="$p" bash -c 'source "$1/hook-guarded.sh"; rc=0
        cwk_is_guarded frontend/vite.config.ts || rc=$?; echo "$rc $CWK_CFG_DEGRADED"' _ "$HOOKS_DIR")"
    CASES=$((CASES + 1))
    [[ "$out" == "0 0" ]] || fail hook-guarded.sh PV3 "a declared root's config: expected '0 0', got '$out'"
    printf '{"schema_version":2}\n' >"$p/.claude/project.json"
    out="$(cd "$p" && CLAUDE_PROJECT_DIR="$p" bash -c 'source "$1/hook-guarded.sh"; a=0; b=0
        cwk_is_guarded frontend/vite.config.ts || a=$?; cwk_is_guarded .claude/hooks/x || b=$?
        echo "$a $b $CWK_CFG_DEGRADED"' _ "$HOOKS_DIR")"
    CASES=$((CASES + 1))
    [[ "$out" == "1 0 1" ]] || fail hook-guarded.sh PV3 "an invalid file: expected '1 0 1' (defaults, static list, degraded), got '$out'"

    p="$tmp/px1"
    pv_project "$p"
    printf '{"schema_version":2}\n' >"$p/.claude/project.json"
    pv_python_spy "$tmp/spy1"
    out="$(PATH="$tmp/spy1/bin:$PATH" project_hook_probe protect-files.sh "$p" \
        "$(jq -cn --arg f "$p/src/a.ts" '{tool_name:"Read",tool_input:{file_path:$f}}')")"
    pv_expect PX1 pass "$out"
    CASES=$((CASES + 1))
    grep -q ' shell ' "$tmp/spy1/calls" && fail protect-files.sh PX1 "a Read of src/a.ts ran the reader: $(cat "$tmp/spy1/calls")"

    for junk in 'printf "junk\\n"' 'printf "#status=0\\0linter=eslint\\0"' \
                "printf '#status=0\\0linter=eslint\\0#end=9\\0'"; do
        mkdir -p "$tmp/badpy/bin"
        printf '#!/usr/bin/env bash\ncase " $* " in *" shell "*) %s; exit 0 ;; esac\nexec %s "$@"\n' \
            "$junk" "$(command -v python3)" >"$tmp/badpy/bin/python3"
        chmod +x "$tmp/badpy/bin/python3"
        p="$tmp/px10"
        pv_project "$p"
        out="$(cd "$p" && PATH="$tmp/badpy/bin:$PATH" CLAUDE_PROJECT_DIR="$p" bash -c 'source "$1/hook-guarded.sh"; rc=0
            cwk_config || rc=$?; echo "$rc $CWK_CFG_DEGRADED ${CWK_CFG_PROTECTED_BRANCHES[*]}"' _ "$HOOKS_DIR")"
        CASES=$((CASES + 1))
        [[ "$out" == "3 1 main master" ]] \
            || fail hook-guarded.sh PX10 "reader output [$junk] must be status 3 on the defaults, got '$out'"
    done
    rm -rf "$tmp/px10g"; make_seed_repo "$tmp/px10g"
    pv_project "$tmp/px10g"
    out="$(PATH="$tmp/badpy/bin:$PATH" PROBE_PROJECT="$tmp/px10g" git_hook_probe 'git commit -m x' "$tmp/px10g" "$tmp/px10g")"
    pv_expect PX10 deny "$out"

    stale="$tmp/stale"
    mkdir -p "$stale"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$HOOKS_DIR/project-defaults.records" "$stale/"
    git -C "$PROJECT_ROOT" show 0790de8:.claude/hooks/hook-lib.sh >"$stale/hook-lib.sh"
    for hook in prevent-destructive-commands.sh tdd-require-red.sh tdd-prove-red.sh; do
        rc=0
        out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/a.utils.ts","content":"x","command":"ls"}}' "$PROJECT_ROOT" \
            | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 "$stale/$hook" 2>&1 >/dev/null)" || rc=$?
        CASES=$((CASES + 1))
        [[ "$rc" == 2 && "$out" == *cwk_tdd_load* ]] \
            || fail "$hook" PX11 "a stale hook-lib.sh must exit 2 naming cwk_tdd_load, got rc $rc '${out:0:200}'"
    done

    p="$tmp/px13"
    pv_project "$p"
    printf '{"schema_version":2}\n' >"$p/.claude/project.json"
    mkdir -p "$tmp/px13hooks"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp/px13hooks/"
    printf 'corrupt\n' >"$tmp/px13hooks/project-defaults.records"
    out="$(cd "$p" && printf '%s' "$(jq -cn --arg cwd "$p" '{tool_name:"Bash",tool_input:{command:"echo x > docs/a.md"},cwd:$cwd}')" \
        | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$tmp/px13hooks/prevent-destructive-commands.sh" 2>/dev/null)"
    pv_expect PX13 ask "$(semantic_verdict 0 <(printf '%s' "$out"))
$out" "" "test-first"
    out="$(cd "$p" && printf '%s' "$(jq -cn --arg cwd "$p" '{tool_name:"Bash",tool_input:{command:"python3 -I -c '"'"'x'"'"' > src/b.md"},cwd:$cwd}')" \
        | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$tmp/px13hooks/prevent-destructive-commands.sh" 2>/dev/null)"
    pv_expect PX13 deny "$(semantic_verdict 0 <(printf '%s' "$out"))
$out" "inline program" "test-first"
    rm -rf "$tmp"
}

# <hook> on a <tool> call naming <path> (or a Bash <command>), in project <dir>.
pv_tool() {
    local hook="$1" dir="$2" tool="$3" arg="$4" content="${5:-x}"
    if [[ "$tool" == Bash ]]; then
        project_hook_probe "$hook" "$dir" "$(jq -cn --arg c "$arg" --arg cwd "$dir" \
            '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}')"
    else
        project_hook_probe "$hook" "$dir" "$(jq -cn --arg t "$tool" --arg f "$dir/$arg" --arg c "$content" \
            '{tool_name:$t,tool_input:{file_path:$f,content:$c,old_string:"a",new_string:$c,pattern:"x",path:$f}}')"
    fi
}

# A git repo at <dir> on <branch> with one commit, the project's config committed in it.
pv_repo() {
    make_seed_repo "$1"
    pv_project "$1" "${3:-.}"
    git -C "$1" add .claude/project.json
    git -C "$1" commit -q --allow-empty -m config
    [[ "$2" == main ]] || git -C "$1" switch -q -c "$2"
}

# PV4-PV9, PX2, PX3, PX8, PX9, PX12, PX14, PX15 (project-config step 3): each PreToolUse
# value changes a verdict; an unreadable config keeps every deny and asks where it passed.
run_project_values_step3_cases() {
    local tmp p out icon state bad hook reason id branch rc
    tmp="$(mktemp -d)"
    reason="rerun install.sh on this project, or /kit:init"

    pv_repo "$tmp/pv4" release/1 '.protected_branches = ["release/*"]'
    pv_expect PV4 deny "$(PROBE_PROJECT="$tmp/pv4" git_hook_probe 'git commit -m x' "$tmp/pv4" "$tmp/pv4")"
    git -C "$tmp/pv4" switch -q main
    pv_expect PV4 pass "$(PROBE_PROJECT="$tmp/pv4" git_hook_probe 'git commit -m x' "$tmp/pv4" "$tmp/pv4")"

    p="$tmp/pv5"
    pv_project "$p" '.protected_dirs += ["frontend"]'
    mkdir -p "$p/frontend"
    pv_expect PV5 deny "$(pd_probe "$p" 'rm -rf frontend')" "frontend/"
    pv_project "$p"
    out="$(pd_probe "$p" 'rm -rf frontend')"
    pv_expect PV5 "${out%%$'\n'*}" "$out" "" "Cannot delete protected directory"

    p="$tmp/pv6"
    pv_project "$p" '.env_template_suffixes = ["dist"]'
    printf 'A=1\n' >"$p/.env.dist"; printf 'A=1\n' >"$p/.env.example"
    pv_expect PV6 pass "$(pv_tool protect-files.sh "$p" Read .env.dist)"
    pv_expect PV6 allow "$(pv_tool auto-approve-config.sh "$p" Read .env.dist)"
    pv_expect PV6 deny "$(pv_tool protect-files.sh "$p" Read .env.example)"
    pv_expect PV6 pass "$(pd_probe "$p" 'cat .env.dist')"
    pv_repo "$tmp/pv6g" main '.env_template_suffixes = ["dist"]'
    printf 'A=1\n' >"$tmp/pv6g/.env.dist"
    git -C "$tmp/pv6g" switch -q -c feat/x
    out="$(PROBE_PROJECT="$tmp/pv6g" git_hook_probe 'git add .env.dist' "$tmp/pv6g" "$tmp/pv6g")"
    pv_expect PV6 "${out%%$'\n'*}" "$out" "" "secret"

    p="$tmp/pv7"
    pv_project "$p"
    printf 'A=1\n' >"$p/.env.sample"
    pv_expect PV7 allow "$(pv_tool auto-approve-config.sh "$p" Read .env.sample)"

    p="$tmp/pv8"
    pv_project "$p" '.forbidden_icons = ["Gauge"]'
    icon="$(python3 -I -B "$HOOKS_DIR/project_config.py" defaults | jq -r '.forbidden_icons[0]')"
    pv_expect PV8 deny "$(pv_tool no-forbidden-icons.sh "$p" Write src/a.tsx 'export const A = () => <Gauge />')"
    pv_expect PV8 pass "$(pv_tool no-forbidden-icons.sh "$p" Write src/b.tsx "export const B = () => <$icon />")"

    p="$tmp/pv9"
    pv_project "$p" '.data_client.module = "lib/api" | .data_client.own_path = "lib/api.ts" | .data_client.composition_roots = ["main.tsx"]'
    state="import { client } from '@/lib/api'"
    pv_expect PV9 deny "$(pv_tool enforce-architecture.py "$p" Write src/features/x/hooks.ts "$state")"
    pv_expect PV9 deny "$(pv_tool enforce-architecture.py "$p" Write src/routes/__root.tsx "$state")"
    pv_expect PV9 pass "$(pv_tool enforce-architecture.py "$p" Write src/main.tsx "$state")"

    for bad in invalid absent; do
        p="$tmp/px2-$bad"
        pv_project "$p"
        mkdir -p "$p/frontend"
        printf 'A=1\n' >"$p/.env.example"
        if [[ "$bad" == invalid ]]; then
            printf '{"schema_version":2}\n' >"$p/.claude/project.json"
        else
            rm "$p/.claude/project.json"
        fi
        id="PX2[$bad]"
        pv_expect "$id" deny "$(pd_probe "$p" 'echo x > src/a.utils.ts')" "$reason"
        pv_expect "$id" deny "$(pv_tool tdd-require-red.sh "$p" Write src/a.utils.ts)" "$reason"
        pv_expect "$id" ask "$(pv_tool protect-files.sh "$p" Write frontend/vite.config.ts)" "$reason"
        pv_expect "$id" ask "$(pv_tool protect-files.sh "$p" Read .env.example)" "$reason"
        pv_expect "$id" ask "$(pv_tool protect-files.sh "$p" Grep .env.example)" "$reason"
        pv_expect "$id" pass "$(pv_tool auto-approve-config.sh "$p" Read .env.example)"
        pv_expect "$id" ask "$(pd_probe "$p" 'rm -rf build')" "$reason"
        pv_expect "$id" ask "$(pd_probe "$p" 'cp /tmp/x frontend/package.json')" "$reason"
        pv_expect "$id" deny "$(pd_probe "$p" 'sed -i s/a/b/ frontend/vite.config.ts')" "$reason"
        printf 'it("U1 a", () => { expect(1).toBe(1) })\n' >"$p/src/a.utils.test.ts"
        pv_expect "$id" deny "$(project_hook_probe tdd-freeze-tests.sh "$p" \
            "$(jq -cn --arg f "$p/src/a.utils.test.ts" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"toBe(1)",new_string:"toBe(2)"}}')")" "$reason"
        pv_expect "$id" ask "$(pv_tool no-forbidden-icons.sh "$p" Write src/c.tsx 'export const C = 1')" "$reason"
        pv_expect "$id" ask "$(pv_tool enforce-architecture.py "$p" Write src/features/x/hooks.ts 'export const h = 1')" "$reason"
        pv_expect "$id" ask "$(project_hook_probe protect-files.sh "$p" \
            "$(jq -cn --arg f "$tmp/other/.env.example" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')")" "$reason"
        pv_repo "$tmp/px2g-$bad" main
        if [[ "$bad" == invalid ]]; then
            printf '{"schema_version":2}\n' >"$tmp/px2g-$bad/.claude/project.json"
        else
            rm "$tmp/px2g-$bad/.claude/project.json"
        fi
        pv_expect "$id" deny "$(PROBE_PROJECT="$tmp/px2g-$bad" git_hook_probe 'git commit -m x' "$tmp/px2g-$bad" "$tmp/px2g-$bad")" "$reason"
    done

    p="$tmp/px3"
    pv_project "$p"
    out="$(cd "$p" && printf '%s' "$(jq -cn --arg cwd "$p" '{tool_name:"Bash",tool_input:{command:"rm -rf build"},cwd:$cwd}')" \
        | env -u CLAUDE_PROJECT_DIR CWK_HOOK_TIMING=0 "$HOOKS_DIR/prevent-destructive-commands.sh" 2>/dev/null)"
    pv_expect PX3 ask "$(semantic_verdict 0 <(printf '%s' "$out"))
$out" "CLAUDE_PROJECT_DIR"
    out="$(cd "$p" && printf '%s' "$(jq -cn --arg f "$p/src/a.utils.ts" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')" \
        | CLAUDE_PROJECT_DIR=rel CWK_HOOK_TIMING=0 "$HOOKS_DIR/tdd-require-red.sh" 2>/dev/null)"
    pv_expect PX3 deny "$(semantic_verdict 0 <(printf '%s' "$out"))
$out" "CLAUDE_PROJECT_DIR"

    p="$tmp/px8"
    pv_project "$p" '.codegen_commands = [["supabase", "gen", "types"]] | .linter = "a/b"'
    out="$(pd_probe "$p" 'supabase gen types > src/types.ts')"
    CASES=$((CASES + 1))
    [[ "${out%%$'\n'*}" != pass ]] || fail project-values PX8 "an invalid file's codegen exempted its redirect"

    p="$tmp/px9"
    pv_project "$p"
    printf 'A=1\n' >"$p/.env.example"
    pv_python_spy "$tmp/spy9"
    for hook in protect-files.sh auto-approve-config.sh; do
        : >"$tmp/spy9/calls"
        PATH="$tmp/spy9/bin:$PATH" pv_tool "$hook" "$p" Read src/a.ts >/dev/null
        CASES=$((CASES + 1))
        [[ "$(grep -c ' shell ' "$tmp/spy9/calls" || true)" == 0 ]] || fail "$hook" PX9 "a Read of src/a.ts ran the reader"
        : >"$tmp/spy9/calls"
        PATH="$tmp/spy9/bin:$PATH" pv_tool "$hook" "$p" Read .env.example >/dev/null
        CASES=$((CASES + 1))
        [[ "$(grep -c ' shell ' "$tmp/spy9/calls" || true)" == 1 ]] || fail "$hook" PX9 "a Read of .env.example must run the reader once"
    done
    : >"$tmp/spy9/calls"
    PATH="$tmp/spy9/bin:$PATH" pv_tool enforce-git-workflow.sh "$p" Bash ls >/dev/null
    CASES=$((CASES + 1))
    [[ "$(grep -c ' shell ' "$tmp/spy9/calls" || true)" == 0 ]] || fail enforce-git-workflow.sh PX9 "ls ran the reader"
    # shellcheck disable=SC2043  # one hook today; the loop is the shape PX9 extends
    for hook in prevent-destructive-commands.sh; do
        : >"$tmp/spy9/calls"
        PATH="$tmp/spy9/bin:$PATH" pd_probe "$p" 'rm -rf build' >/dev/null
        CASES=$((CASES + 1))
        [[ "$(grep -c ' shell ' "$tmp/spy9/calls" || true)" -le 1 ]] || fail "$hook" PX9 "rm -rf build ran the reader more than once"
    done
    for hook in protect-files.sh no-forbidden-icons.sh tdd-require-red.sh tdd-freeze-tests.sh; do
        : >"$tmp/spy9/calls"
        PATH="$tmp/spy9/bin:$PATH" pv_tool "$hook" "$p" Write src/a.ts >/dev/null
        CASES=$((CASES + 1))
        [[ "$(grep -c ' shell ' "$tmp/spy9/calls" || true)" -le "$([[ $hook == tdd-freeze-tests.sh ]] && echo 0 || echo 1)" ]] \
            || fail "$hook" PX9 "a Write of src/a.ts ran the reader too often: $(grep -c ' shell ' "$tmp/spy9/calls")"
    done

    p="$tmp/px12"
    pv_project "$p"
    printf '{"schema_version":2}\n' >"$p/.claude/project.json"
    pv_expect PX12 deny "$(pd_probe "$p" 'rm -rf ~')"
    pv_expect PX12 deny "$(pd_probe "$p" 'rm -rf / --no-preserve-root')"
    pv_expect PX12 deny "$(pd_probe "$p" 'touch .claude/.tdd-red/m')"
    pv_repo "$tmp/px12g" feat/x
    printf '{"schema_version":2}\n' >"$tmp/px12g/.claude/project.json"
    pv_expect PX12 deny "$(PROBE_PROJECT="$tmp/px12g" git_hook_probe 'git commit -S -m x' "$tmp/px12g" "$tmp/px12g")"
    pv_expect PX12 deny "$(PROBE_PROJECT="$tmp/px12g" git_hook_probe 'git commit -m x; git add -f .env.local' "$tmp/px12g" "$tmp/px12g")" "force"

    p="$tmp/px14"
    pv_project "$p"
    mkdir -p "$p/src/features/a" "$p/frontend/src"
    printf 'x\n' >"$p/src/a.ts"
    pv_expect PX14 deny "$(pd_probe "$p" 'npx nice tsc --outDir src')"
    pv_expect PX14 ask "$(pd_probe "$p" 'mv src/a.ts src/b.ts')"
    pv_expect PX14 deny "$(pd_probe "$p" "echo x >src/features/a/a.utils.t's'")" "test-first"
    out="$(pd_probe "$p" "pnpm exec tsc --outFile frontend/src/a.utils.t's'")"
    CASES=$((CASES + 1))
    [[ "${out%%$'\n'*}" != pass ]] || fail project-values PX14 "a quote-split test-first target passed"

    no_python_bin "$tmp/nopy"
    pv_repo "$tmp/px15" main
    for branch in main feat/x; do
        [[ "$branch" == main ]] || git -C "$tmp/px15" switch -q -c "$branch"
        rc=0
        out="$(cd "$tmp/px15" && jq -cn --arg cwd "$tmp/px15" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$cwd}' \
            | PATH="$tmp/nopy" CLAUDE_PROJECT_DIR="$tmp/px15" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
              "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)" || rc=$?
        pv_expect PX15 "$([[ $branch == main ]] && echo deny || echo ask)" \
            "$(semantic_verdict "$rc" <(printf '%s' "$out"))
$out" "python3"
    done
    rm -rf "$tmp"
}

# <hook> run in project <dir> on a Write of <rel>; prints its stdout.
pv_post() {
    local hook="$1" dir="$2" rel="$3"
    (cd "$dir" && jq -cn --arg f "$dir/$rel" '{tool_name:"Write",tool_input:{file_path:$f}}' \
        | CLAUDE_PROJECT_DIR="$dir" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/$hook" 2>/dev/null) || true
}

# A node_modules/.bin/<name> in <dir> that appends its argv to <dir>/<name>.calls.
pv_bin_spy() {
    mkdir -p "$1/node_modules/.bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/%s.calls"\n' "$1" "$2" >"$1/node_modules/.bin/$2"
    chmod +x "$1/node_modules/.bin/$2"
}

# A red test file for src/a.utils.ts in <dir>.
pv_red_test() {
    mkdir -p "$1/src"
    printf '%s\n' "import { double } from './a.utils'" "it('U1 doubles', () => { expect(double(1)).toBe(2) })" \
        >"$1/src/a.utils.test.ts"
}

# PV10-PV12, PX4-PX6 (project-config step 4): the PostToolUse and Stop commands come from the
# config; an unreadable config runs nothing and says why.
run_project_values_step4_cases() {
    local tmp p out bad reason rc
    tmp="$(mktemp -d)"
    reason="rerun install.sh on this project, or /kit:init"

    p="$tmp/pv10"
    pv_project "$p" "$(printf '.test_command = ["sh", "%s/runner.sh"]' "$p")"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/argv"\necho "      Tests  1 failed (1)"\nexit 1\n' "$p" >"$p/runner.sh"
    pv_red_test "$p"
    pv_post tdd-prove-red.sh "$p" src/a.utils.test.ts >/dev/null
    CASES=$((CASES + 1))
    [[ "$(tail -1 "$p/argv" 2>/dev/null)" == "$p/src/a.utils.test.ts" ]] \
        || fail tdd-prove-red.sh PV10 "test_command did not run with the test path last: '$(cat "$p/argv" 2>/dev/null)'"
    CASES=$((CASES + 1))
    [[ -n "$(ls -A "$p/.claude/.tdd-red" 2>/dev/null)" ]] || fail tdd-prove-red.sh PV10 "a failing run wrote no RED marker"

    p="$tmp/pv11"
    pv_project "$p" '.formatter = ["fmtshim", "--x"]'
    pv_bin_spy "$p" fmtshim
    printf 'export const a = 1\n' >"$p/src/a.ts"
    pv_post format-on-save.sh "$p" src/a.ts >/dev/null
    CASES=$((CASES + 1))
    [[ "$(cat "$p/fmtshim.calls" 2>/dev/null)" == "--x $p/src/a.ts" ]] \
        || fail format-on-save.sh PV11 "expected 'fmtshim --x <file>', got '$(cat "$p/fmtshim.calls" 2>/dev/null)'"
    pv_project "$p" '.formatter = []'
    rm -f "$p/fmtshim.calls"
    pv_bin_spy "$p" prettier
    pv_post format-on-save.sh "$p" src/a.ts >/dev/null
    CASES=$((CASES + 1))
    [[ ! -e "$p/fmtshim.calls" && ! -e "$p/prettier.calls" ]] || fail format-on-save.sh PV11 "formatter [] still ran a formatter"

    p="$tmp/pv12"
    pv_project "$p" '.linter = "lintshim"'
    pv_bin_spy "$p" lintshim
    printf 'export const a = 1\n' >"$p/src/a.ts"
    printf '%s\n' "$p/src/a.ts" >"$p/.claude/.eslint-queue"
    (cd "$p" && CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$HOOKS_DIR/eslint-batch.sh" </dev/null >/dev/null 2>&1) || true
    CASES=$((CASES + 1))
    [[ "$(cat "$p/lintshim.calls" 2>/dev/null)" == "$p/src/a.ts"* ]] \
        || fail eslint-batch.sh PV12 "lintshim did not run on the queued file: '$(cat "$p/lintshim.calls" 2>/dev/null)'"
    pv_project "$p" '.linter = ""'
    rm -f "$p/lintshim.calls"
    pv_bin_spy "$p" eslint
    printf '%s\n' "$p/src/a.ts" >"$p/.claude/.eslint-queue"
    (cd "$p" && CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$HOOKS_DIR/eslint-batch.sh" </dev/null >/dev/null 2>&1) || true
    CASES=$((CASES + 1))
    [[ ! -e "$p/lintshim.calls" && ! -e "$p/eslint.calls" ]] || fail eslint-batch.sh PV12 "linter \"\" still ran a linter"

    for bad in invalid absent; do
        p="$tmp/px-$bad"
        pv_project "$p"
        if [[ "$bad" == invalid ]]; then
            printf '{"schema_version":2}\n' >"$p/.claude/project.json"
        else
            rm "$p/.claude/project.json"
        fi
        pv_red_test "$p"
        pv_bin_spy "$p" pnpm
        out="$(PATH="$p/node_modules/.bin:$PATH" pv_post tdd-prove-red.sh "$p" src/a.utils.test.ts)"
        CASES=$((CASES + 1))
        [[ "$out" == *systemMessage* && "$out" == *"$reason"* ]] \
            || fail tdd-prove-red.sh "PX4[$bad]" "no systemMessage naming the repair: '${out:0:200}'"
        CASES=$((CASES + 1))
        [[ -z "$(ls -A "$p/.claude/.tdd-red" 2>/dev/null)" && ! -e "$p/pnpm.calls" ]] \
            || fail tdd-prove-red.sh "PX4[$bad]" "an unreadable config ran the tests or wrote a marker"

        printf 'export const   a = 1\n' >"$p/src/b.ts"
        printf '#!/bin/sh\nfor f; do printf "x\\n" >>"$f"; done\n' >"$p/node_modules/.bin/prettier"
        chmod +x "$p/node_modules/.bin/prettier"
        out="$(pv_post format-on-save.sh "$p" src/b.ts)"
        CASES=$((CASES + 1))
        [[ "$out" == *systemMessage* && "$out" == *"$reason"* ]] \
            || fail format-on-save.sh "PX5[$bad]" "no systemMessage naming the repair: '${out:0:200}'"
        CASES=$((CASES + 1))
        [[ "$(cat "$p/src/b.ts")" == 'export const   a = 1' ]] || fail format-on-save.sh "PX5[$bad]" "the file was formatted"

        pv_bin_spy "$p" eslint
        printf '%s\n' "$p/src/b.ts" >"$p/.claude/.eslint-queue"
        rc=0
        out="$(cd "$p" && CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$HOOKS_DIR/eslint-batch.sh" </dev/null 2>/dev/null)" || rc=$?
        CASES=$((CASES + 1))
        [[ "$rc" == 0 && "$out" == *systemMessage* && "$out" == *"$reason"* ]] \
            || fail eslint-batch.sh "PX6[$bad]" "expected exit 0 and a systemMessage naming the repair, got $rc '${out:0:200}'"
        CASES=$((CASES + 1))
        [[ -s "$p/.claude/.eslint-queue" && ! -e "$p/eslint.calls" ]] \
            || fail eslint-batch.sh "PX6[$bad]" "the queue was consumed or the linter ran"
    done
    rm -rf "$tmp"
}

# A tmp project for the fastapi addon: pv_project, plus the reader in <dir>/.claude/hooks.
pv_addon_project() {
    pv_project "$1" "${2:-.}"
    mkdir -p "$1/.claude/hooks"
    cp "$HOOKS_DIR/project_config.py" "$1/.claude/hooks/project_config.py"
}

# The fastapi addon <hook> on a <tool> of <rel> holding <content>, in project <dir>.
pv_addon() {
    local hook="$1" dir="$2" tool="$3" rel="$4" content="${5:-x = 1}" out code
    set +e
    out="$(cd "$dir" && jq -cn --arg t "$tool" --arg f "$dir/$rel" --arg c "$content" \
        '{tool_name:$t,tool_input:{file_path:$f,content:$c}}' \
        | CLAUDE_PROJECT_DIR="$dir" CWK_HOOK_TIMING=0 python3 "$HOOKS_DIR/../../addons/fastapi/hooks/$hook" 2>/dev/null)"
    code=$?
    set -e
    printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out"
}

# PV13-PV15, PX7 (project-config step 5): the fastapi addon reads its roots, layers and
# session names from the config; an unreadable config keeps its denies and asks for the rest.
run_project_values_step5_cases() {
    local tmp p out reason sure
    tmp="$(mktemp -d)"
    reason="rerun install.sh on this project, or /kit:init"

    p="$tmp/pv13"
    pv_addon_project "$p" '.fastapi.module_root = "srv"'
    pv_expect PV13 deny "$(pv_addon tdd-require-red-py.py "$p" Write srv/services/a.py)"
    pv_expect PV13 pass "$(pv_addon tdd-require-red-py.py "$p" Write app/services/a.py)"

    p="$tmp/pv14"
    pv_addon_project "$p" '.fastapi.session_names = ["conn"]'
    pv_expect PV14 deny "$(pv_addon enforce-backend-layers.py "$p" Write app/api/routes.py 'conn.execute(q)')" "Database access"
    pv_expect PV14 pass "$(pv_addon enforce-backend-layers.py "$p" Write app/api/routes.py 'db.execute(q)')"

    p="$tmp/pv15"
    pv_addon_project "$p"
    pv_expect PV15 pass "$(pv_addon tdd-require-red-py.py "$p" Write application/x.py)"
    pv_expect PV15 pass "$(pv_addon tdd-require-red-py.py "$p" Write app/services_old/x.py)"
    pv_expect PV15 deny "$(pv_addon enforce-backend-layers.py "$p" Write app/api/routes.py 'db.execute(q)')" "Database access"
    pv_expect PV15 pass "$(pv_addon enforce-backend-layers.py "$p" Write application/api/routes.py 'db.execute(q)')"

    for bad in invalid noreader raises; do
        p="$tmp/px7-$bad"
        pv_addon_project "$p"
        case "$bad" in
            invalid) printf '{"schema_version":2}\n' >"$p/.claude/project.json" ;;
            noreader) rm "$p/.claude/hooks/project_config.py" ;;
            raises) printf 'raise RuntimeError("boom")\n' >"$p/.claude/hooks/project_config.py" ;;
        esac
        sure=ask
        [[ "$bad" == invalid ]] && sure=deny
        pv_expect "PX7[$bad]" "$sure" "$(pv_addon tdd-require-red-py.py "$p" Write app/services/a.py)" "$reason"
        pv_expect "PX7[$bad]" ask "$(pv_addon tdd-require-red-py.py "$p" Write app/api/x.py)" "$reason"
        pv_expect "PX7[$bad]" ask "$(pv_addon enforce-backend-layers.py "$p" Write app/api/x.py 'x = 1')" "$reason"
        pv_expect "PX7[$bad]" "$sure" "$(pv_addon enforce-backend-layers.py "$p" Write app/api/x.py 'db.execute(q)')" "$reason"
        mkdir -p "$p/tests/services"
        printf 'from app.services.a import f\n\ndef test_f():\n    assert f() == 1\n' >"$p/tests/services/test_a.py"
        out="$(pv_addon tdd-prove-red-py.py "$p" Write tests/services/test_a.py)"
        CASES=$((CASES + 1))
        [[ "$out" == *systemMessage* && "$out" == *"$reason"* && -z "$(ls -A "$p/.claude/.tdd-red" 2>/dev/null)" ]] \
            || fail tdd-prove-red-py "PX7[$bad]" "expected a systemMessage naming the repair and no marker, got '${out:0:200}'"
    done
    CASES=$((CASES + 1))
    (cd "$tmp" && env -u CLAUDE_PROJECT_DIR python3 "$HOOKS_DIR/../../addons/fastapi/hooks/test_imported_symbols.py" >/dev/null 2>&1) \
        || fail tdd-prove-red-py PX7 "test_imported_symbols.py failed with no CLAUDE_PROJECT_DIR"
    rm -rf "$tmp"
}

# Fails <id> unless the stdout part of a probe's <out> is exactly one JSON object.
rv_one_json() {
    local id="$1" out="$2"
    CASES=$((CASES + 1))
    [[ "$(printf '%s' "${out#*$'\n'}" | jq -s 'length == 1 and (.[0] | type) == "object"' 2>/dev/null)" == true ]] \
        || fail review-1 "$id" "stdout is not exactly one JSON object: '${out:0:300}'"
}

# <script> (a hook copied beside its own reader) run in project <dir> on <json>; prints verdict, then stdout.
rv_script() {
    local script="$1" dir="$2" input="$3" out code
    set +e
    out="$(cd "$dir" && printf '%s' "$input" | CLAUDE_PROJECT_DIR="$dir" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
        python3 "$script" 2>/dev/null)"
    code=$?
    set -e
    printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out"
}

# RV1-RV7 (project-config review 1): degraded verdicts stay one decision, config-independent
# denies survive an unusable reader, and the PostToolUse hooks refuse a stale hook-lib.sh.
run_review1_cases() {
    local tmp p bad out reason sure cross f sure_rel sure_content icon
    tmp="$(mktemp -d)"
    reason="rerun install.sh on this project, or /kit:init"
    icon="$(python3 -I -B "$HOOKS_DIR/project_config.py" defaults | jq -r '.forbidden_icons[0]')"
    cross="import { y } from '../b/y'"

    for bad in raises noreader; do
        p="$tmp/rv1-$bad"
        pv_project "$p"
        mkdir -p "$tmp/rv1-hooks-$bad"
        cp "$HOOKS_DIR/enforce-architecture.py" "$tmp/rv1-hooks-$bad/"
        [[ "$bad" == raises ]] && printf 'raise RuntimeError("boom")\n' >"$tmp/rv1-hooks-$bad/project_config.py"
        for out in "src/features/a/x.ts|$cross|deny" "src/features/a/y.ts|export const h = 1|ask"; do
            IFS='|' read -r sure_rel sure_content sure <<<"$out"
            out="$(rv_script "$tmp/rv1-hooks-$bad/enforce-architecture.py" "$p" \
                "$(jq -cn --arg f "$p/$sure_rel" --arg c "$sure_content" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
            pv_expect "RV1[$bad]" "$sure" "$out" "$reason"
            rv_one_json "RV1[$bad]" "$out"
        done
    done

    for bad in invalid noreader raises; do
        p="$tmp/rv2-$bad"
        pv_addon_project "$p"
        case "$bad" in
            invalid) printf '{"schema_version":2}\n' >"$p/.claude/project.json" ;;
            noreader) rm "$p/.claude/hooks/project_config.py" ;;
            raises) printf 'raise RuntimeError("boom")\n' >"$p/.claude/hooks/project_config.py" ;;
        esac
        mkdir -p "$p/tests/services" "$p/tests/api"
        printf 'def test_a():\n    assert 1 == 1\n' >"$p/tests/services/test_a.py"
        printf 'def test_x():\n    assert 1 == 1\n' >"$p/tests/api/test_x.py"
        sure=ask
        [[ "$bad" == invalid ]] && sure=deny
        out="$(pv_addon tdd-freeze-tests-py.py "$p" Write tests/services/test_a.py $'def test_a():\n    assert 2 == 2\n')"
        pv_expect "RV2[$bad]" "$sure" "$out" "$reason"
        rv_one_json "RV2[$bad]" "$out"
        out="$(pv_addon tdd-freeze-tests-py.py "$p" Write tests/api/test_x.py $'def test_x():\n    assert 2 == 2\n')"
        pv_expect "RV2[$bad]" ask "$out" "$reason"
        rv_one_json "RV2[$bad]" "$out"
        out="$(pv_addon tdd-freeze-tests-py.py "$p" Write tests/services/test_a.py $'def test_a():\n    assert 1 == 1\n')"
        pv_expect "RV4[py-$bad]" ask "$out" "$reason"
        rv_one_json "RV4[py-$bad]" "$out"
    done

    for bad in invalid absent; do
        p="$tmp/rv3-$bad"
        pv_project "$p"
        if [[ "$bad" == invalid ]]; then
            printf '{"schema_version":2}\n' >"$p/.claude/project.json"
        else
            rm "$p/.claude/project.json"
        fi
        out="$(pv_tool no-forbidden-icons.sh "$p" Write src/a.tsx "export const A = () => <$icon />")"
        pv_expect "RV3[$bad]" deny "$out" "$reason"
        rv_one_json "RV3[$bad]" "$out"
        out="$(pv_tool enforce-architecture.py "$p" Write src/features/a/x.ts "$cross")"
        pv_expect "RV3[$bad]" deny "$out" "$reason"
        rv_one_json "RV3[$bad]" "$out"
        out="$(pv_tool protect-files.sh "$p" Write .env)"
        pv_expect "RV3[$bad]" deny "$out" "$reason"
        rv_one_json "RV3[$bad]" "$out"

        mkdir -p "$p/src"
        printf 'it("U1 a", () => { expect(1).toBe(1) })' >"$p/src/a.utils.test.ts"
        out="$(project_hook_probe tdd-freeze-tests.sh "$p" \
            "$(jq -cn --arg f "$p/src/a.utils.test.ts" --arg c 'it("U1 a", () => { expect(1).toBe(1) })' \
                '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
        pv_expect "RV4[sh-$bad]" ask "$out" "$reason"
        rv_one_json "RV4[sh-$bad]" "$out"
        printf 'describe("a", () => {\n  it("U1 a", () => {\n    expect(1).toBe(1)\n  })\n})\n' >"$p/src/a.utils.test.ts"
        out="$(project_hook_probe tdd-freeze-tests.sh "$p" \
            "$(jq -cn --arg f "$p/src/a.utils.test.ts" --arg o $'  })\n})' \
                --arg n $'  })\n\n  it("U2 b", () => {\n    expect(2).toBe(2)\n  })\n})' \
                '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}')")"
        pv_expect "RV4[sh-append-$bad]" ask "$out" "$reason"
        rv_one_json "RV4[sh-append-$bad]" "$out"
    done

    p="$tmp/rv5"
    pv_project "$p" '.fastapi.test_first_dirs = ["services", "domain"]'
    mkdir -p "$p/.claude/hooks" "$p/bin" "$p/tests/domain" "$p/tests/services" "$p/tests/api"
    cp "$HOOKS_DIR/hook-lib.sh" "$HOOKS_DIR/hook-guarded.sh" "$HOOKS_DIR/project_config.py" \
        "$HOOKS_DIR/project-defaults.records" "$HOOKS_DIR/../../addons/fastapi/hooks/ruff-on-save.sh" "$p/.claude/hooks/"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/ruff.calls"\n' "$p" >"$p/bin/ruff"
    chmod +x "$p/bin/ruff"
    for f in tests/domain/test_x.py tests/services/test_a.py tests/api/test_y.py; do
        printf 'def test_z():\n    assert 1\n' >"$p/$f"
    done
    for f in tests/domain/test_x.py tests/services/test_a.py tests/api/test_y.py; do
        (cd "$p" && jq -cn --arg f "$p/$f" '{tool_name:"Write",tool_input:{file_path:$f}}' \
            | PATH="$p/bin:$PATH" CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$p/.claude/hooks/ruff-on-save.sh" >/dev/null 2>&1) || true
    done
    CASES=$((CASES + 1))
    [[ "$(grep -c '^format ' "$p/ruff.calls" 2>/dev/null || true)" == 1 && "$(grep '^format ' "$p/ruff.calls")" == "format $p/tests/api/test_y.py" ]] \
        || fail ruff-on-save.sh RV5 "only the test-after file is formatted when test_first_dirs is services+domain, got '$(grep '^format ' "$p/ruff.calls" 2>/dev/null | tr '\n' ' ')'"
    printf '{"schema_version":2}\n' >"$p/.claude/project.json"
    : >"$p/ruff.calls"
    out="$(cd "$p" && jq -cn --arg f "$p/tests/api/test_y.py" '{tool_name:"Write",tool_input:{file_path:$f}}' \
        | PATH="$p/bin:$PATH" CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 "$p/.claude/hooks/ruff-on-save.sh" 2>/dev/null)" || true
    CASES=$((CASES + 1))
    [[ "$out" == *systemMessage* && "$out" == *"$reason"* && -z "$(grep '^format ' "$p/ruff.calls")" ]] \
        || fail ruff-on-save.sh RV5 "an invalid config must format nothing and say why, got '${out:0:200}'"

    for bad in format-on-save.sh eslint-batch.sh; do
        p="$tmp/rv6-$bad"
        pv_project "$p"
        mkdir -p "$p/hooks"
        cp "$HOOKS_DIR/$bad" "$p/hooks/"
        printf ':\n' >"$p/hooks/hook-lib.sh"
        printf 'export const a = 1\n' >"$p/src/a.ts"
        printf '%s\n' "$p/src/a.ts" >"$p/.claude/.eslint-queue"
        out="$(cd "$p" && jq -cn --arg f "$p/src/a.ts" '{tool_name:"Write",tool_input:{file_path:$f}}' \
            | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 bash "$p/hooks/$bad" 2>/dev/null)" || true
        CASES=$((CASES + 1))
        [[ "$out" == *systemMessage* && "$out" == *"hook-lib.sh is older than this hook"* ]] \
            || fail "$bad" RV6 "a stale hook-lib.sh must be reported, got '${out:0:200}'"
    done
    CASES=$((CASES + 1))
    [[ -s "$tmp/rv6-eslint-batch.sh/.claude/.eslint-queue" ]] || fail eslint-batch.sh RV6 "the queue was claimed under a stale hook-lib.sh"

    p="$tmp/rv7"
    pv_project "$p" '.env_template_suffixes = ["example", "env"]'
    pv_expect RV7 deny "$(pv_tool protect-files.sh "$p" Read .env)"
    pv_expect RV7 pass "$(pv_tool auto-approve-config.sh "$p" Read .env)"
    pv_expect RV7 pass "$(pv_tool protect-files.sh "$p" Read .env.example)"
    rm -rf "$tmp"
}

# <hooks dir>/<hook> (a fastapi addon hook) fed <payload json> in project <dir>; prints verdict, then stdout.
rv2_pair() {
    local hooks="$1" hook="$2" dir="$3" payload="$4" out code
    set +e
    out="$(cd "$dir" && printf '%s' "$payload" \
        | CLAUDE_PROJECT_DIR="$dir" CWK_HOOK_TIMING=0 python3 "$hooks/$hook" 2>/dev/null)"
    code=$?
    set -e
    printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out"
}

# A project for ruff-on-save.sh: the config (jq filter <2>), the hook and its libraries copied in,
# a ruff stub logging each call to <dir>/ruff.calls.
rv2_ruff_project() {
    pv_project "$1" "${2:-.}"
    mkdir -p "$1/.claude/hooks" "$1/bin"
    cp "$HOOKS_DIR/hook-lib.sh" "$HOOKS_DIR/hook-guarded.sh" "$HOOKS_DIR/project_config.py" \
        "$HOOKS_DIR/project-defaults.records" "$HOOKS_DIR/../../addons/fastapi/hooks/ruff-on-save.sh" "$1/.claude/hooks/"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/ruff.calls"\n' "$1" >"$1/bin/ruff"
    chmod +x "$1/bin/ruff"
    : >"$1/ruff.calls"
}

# ruff-on-save.sh on a Write of <file> (absolute) in project <dir>; prints stdout.
rv2_ruff() {
    (cd "$1" && jq -cn --arg f "$2" '{tool_name:"Write",tool_input:{file_path:$f}}' \
        | PATH="$1/bin:$PATH" CLAUDE_PROJECT_DIR="$1" CWK_HOOK_TIMING=0 "$1/.claude/hooks/ruff-on-save.sh" 2>/dev/null) || true
}

# RV9-RV10 (project-config review 2, mixed versions): an old TDD consumer next to the new
# hook-lib.sh never calls cwk_tdd_load, so the path regexes it reads must fail closed.
# RV11-RV15 ruff-on-save.sh skips exactly the frozen tests; RV16-RV17 a mixed addon pair asks;
# RV19-RV23 tdd-freeze-tests-py.py on a healthy config; RV24 the env template sanitiser.
run_review2_cases() {
    local tmp p out hook addon rel fmt want old
    tmp="$(mktemp -d)"
    addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"

    out="$(CLAUDE_PROJECT_DIR="$tmp" CWK_HOOK_TIMING=0 bash -c \
        'source "$1/hook-lib.sh"; [[ src/a.utils.ts =~ $CWK_TDD_IMPL_RE && src/a.utils.test.ts =~ $CWK_TDD_TEST_RE && README.md =~ $CWK_TDD_IMPL_RE ]] && echo match' \
        _ "$HOOKS_DIR" 2>&1)"
    CASES=$((CASES + 1))
    [[ "$out" == match ]] || fail hook-lib.sh RV9 "a consumer that skips cwk_tdd_load must see a layer path as a match, got '${out:0:200}'"

    if git -C "$PROJECT_ROOT" cat-file -e a8efa59:.claude/hooks/tdd-require-red.sh 2>/dev/null; then
        p="$tmp/rv10"
        pv_project "$p"
        mkdir -p "$p/.claude/hooks"
        cp "$HOOKS_DIR/hook-lib.sh" "$HOOKS_DIR/hook-guarded.sh" "$HOOKS_DIR/project_config.py" \
            "$HOOKS_DIR/project-defaults.records" "$HOOKS_DIR/shell_targets.py" "$p/.claude/hooks/"
        for hook in tdd-require-red.sh tdd-freeze-tests.sh; do
            git -C "$PROJECT_ROOT" show "a8efa59:.claude/hooks/$hook" >"$p/.claude/hooks/$hook"
            chmod +x "$p/.claude/hooks/$hook"
        done
        printf 'it("U1 a", () => { expect(1).toBe(1) })' >"$p/src/a.utils.test.ts"
        out="$(cd "$p" && jq -cn --arg f "$p/src/a.utils.ts" --arg c 'export const a = 1' \
            '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}' \
            | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$p/.claude/hooks/tdd-require-red.sh" 2>/dev/null; echo "rc=$?")"
        CASES=$((CASES + 1))
        [[ "$out" == *'"deny"'* || "$out" == *rc=2 ]] \
            || fail tdd-require-red.sh RV10 "an a8efa59 copy beside the new hook-lib.sh must deny a layer write, got '${out:0:200}'"
        out="$(cd "$p" && jq -cn --arg f "$p/src/a.utils.test.ts" --arg c 'it("U1 a", () => { expect(2).toBe(2) })' \
            '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}' \
            | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$p/.claude/hooks/tdd-freeze-tests.sh" 2>/dev/null; echo "rc=$?")"
        CASES=$((CASES + 1))
        [[ "$out" == *'"deny"'* || "$out" == *rc=2 ]] \
            || fail tdd-freeze-tests.sh RV10 "an a8efa59 copy beside the new hook-lib.sh must deny a frozen-test rewrite, got '${out:0:200}'"
    else
        printf 'SKIP RV10: a8efa59 absent\n'
    fi

    # RV25 (review 3, G1): the a8efa59 shell guards beside the new lib never call cwk_tdd_load, so
    # the three shell/python target regexes must fail closed: a frozen test is still protected.
    if git -C "$PROJECT_ROOT" cat-file -e a8efa59:.claude/hooks/prevent-destructive-commands.sh 2>/dev/null; then
        p="$tmp/rv25"
        pv_project "$p"
        mkdir -p "$p/.claude/hooks" "$p/src/features/a"
        cp "$HOOKS_DIR/hook-lib.sh" "$HOOKS_DIR/hook-guarded.sh" "$HOOKS_DIR/project_config.py" \
            "$HOOKS_DIR/project-defaults.records" "$p/.claude/hooks/"
        git -C "$PROJECT_ROOT" show "a8efa59:.claude/hooks/shell_targets.py" >"$p/.claude/hooks/shell_targets.py"
        for hook in prevent-destructive-commands.sh enforce-git-workflow.sh; do
            git -C "$PROJECT_ROOT" show "a8efa59:.claude/hooks/$hook" >"$p/.claude/hooks/$hook"
            chmod +x "$p/.claude/hooks/$hook"
        done
        printf 'it("U1 a", () => { expect(1).toBe(1) })' >"$p/src/features/a/a.utils.test.ts"
        for want in "prevent-destructive-commands.sh|rm src/features/a/a.utils.test.ts" \
                    "prevent-destructive-commands.sh|git rm src/features/a/a.utils.test.ts" \
                    "enforce-git-workflow.sh|git checkout HEAD -- src/features/a/a.utils.test.ts" \
                    "enforce-git-workflow.sh|git restore src/features/a/a.utils.test.ts"; do
            hook="${want%%|*}"
            out="$(cd "$p" && jq -cn --arg c "${want#*|}" --arg cwd "$p" \
                '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' \
                | CLAUDE_PROJECT_DIR="$p" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$p/.claude/hooks/$hook" 2>/dev/null; echo "rc=$?")"
            CASES=$((CASES + 1))
            [[ "$out" == *'"deny"'* || "$out" == *rc=2 ]] \
                || fail "$hook" RV25 "an a8efa59 copy beside the new hook-lib.sh must deny '${want#*|}', got '${out:0:200}'"
        done
    else
        printf 'SKIP RV25: a8efa59 absent\n'
    fi

    # RV26 the synthetic twin of RV25, no a8efa59 needed: a consumer that never calls cwk_tdd_load
    # sees every frozen test path match the three regexes.
    out="$(CLAUDE_PROJECT_DIR="$tmp" CWK_HOOK_TIMING=0 bash -c \
        'source "$1/hook-lib.sh"; f="rm src/features/a/a.utils.test.ts"; [[ $f =~ $CWK_TDD_SHELL_TARGET_RE && $f =~ $CWK_TDD_SHELL_FROZEN_TEST_RE && src/features/a/a.utils.test.ts =~ $CWK_TDD_PY_TARGET_RE ]] && echo match; true' \
        _ "$HOOKS_DIR" 2>&1)"
    CASES=$((CASES + 1))
    [[ "$out" == match ]] || fail hook-lib.sh RV26 "a consumer that skips cwk_tdd_load must see a frozen test as a match of the shell and python target regexes, got '${out:0:200}'"

    # RV11 the skip is the frozen-test predicate: tests/test_main.py is test-after (formatted),
    # a prefixed backend/tests/services/test_a.py is frozen (skipped), tests/api is formatted.
    p="$tmp/rv11"
    rv2_ruff_project "$p"
    for rel in tests/test_main.py backend/tests/services/test_a.py tests/services/test_a.py tests/api/test_y.py; do
        mkdir -p "$p/$(dirname "$rel")"
        printf 'def test_z():\n    assert 1\n' >"$p/$rel"
        rv2_ruff "$p" "$p/$rel" >/dev/null
    done
    fmt="$(grep '^format ' "$p/ruff.calls" | sed "s|$p/||" | sort | tr '\n' ' ')"
    CASES=$((CASES + 1))
    [[ "$fmt" == "format tests/api/test_y.py format tests/test_main.py " ]] \
        || fail ruff-on-save.sh RV11 "expected only tests/test_main.py and tests/api/test_y.py formatted, got '$fmt'"

    # RV12 a non-default tests_root and test_first_dirs move the skip with them.
    p="$tmp/rv12"
    rv2_ruff_project "$p" '.fastapi.tests_root = "test" | .fastapi.test_first_dirs = ["domain"]'
    for rel in test/domain/test_x.py test/services/test_a.py tests/domain/test_x.py; do
        mkdir -p "$p/$(dirname "$rel")"
        printf 'def test_z():\n    assert 1\n' >"$p/$rel"
        rv2_ruff "$p" "$p/$rel" >/dev/null
    done
    fmt="$(grep '^format ' "$p/ruff.calls" | sed "s|$p/||" | sort | tr '\n' ' ')"
    CASES=$((CASES + 1))
    [[ "$fmt" == "format tests/domain/test_x.py format test/services/test_a.py " || "$fmt" == "format test/services/test_a.py format tests/domain/test_x.py " ]] \
        || fail ruff-on-save.sh RV12 "expected only test/services/test_a.py and tests/domain/test_x.py formatted, got '$fmt'"

    # RV13 an unreadable config formats nothing, says why, and still lints.
    p="$tmp/rv13"
    rv2_ruff_project "$p"
    mkdir -p "$p/app"
    printf 'x = 1\n' >"$p/app/m.py"
    printf '{"schema_version":2}\n' >"$p/.claude/project.json"
    out="$(rv2_ruff "$p" "$p/app/m.py")"
    CASES=$((CASES + 1))
    [[ "$out" == *systemMessage* && "$out" == *"rerun install.sh on this project, or /kit:init"* \
        && -z "$(grep '^format ' "$p/ruff.calls")" && -n "$(grep '^check ' "$p/ruff.calls")" ]] \
        || fail ruff-on-save.sh RV13 "degraded: no format, a message, and ruff check still run, got '${out:0:160}' / '$(tr '\n' ' ' <"$p/ruff.calls")'"

    # RV14 a path outside the project's own prefix (a worktree, a symlinked checkout) is judged the same way.
    p="$tmp/rv14"
    rv2_ruff_project "$p"
    mkdir -p "$tmp/rv14-other/backend/tests/services"
    printf 'def test_z():\n    assert 1\n' >"$tmp/rv14-other/backend/tests/services/test_a.py"
    rv2_ruff "$p" "$tmp/rv14-other/backend/tests/services/test_a.py" >/dev/null
    CASES=$((CASES + 1))
    [[ -z "$(grep '^format ' "$p/ruff.calls")" ]] \
        || fail ruff-on-save.sh RV14 "a frozen test reached through another prefix must not be formatted, got '$(tr '\n' ' ' <"$p/ruff.calls")'"

    # RV15 the hook agrees with tdd_py_lib.is_frozen_test on every path of a table.
    p="$tmp/rv15"
    rv2_ruff_project "$p" '.fastapi.test_first_dirs = ["services", "domain"]'
    for rel in tests/services/test_a.py tests/domain/sub/test_b.py tests/test_services.py tests/api/test_c.py \
               backend/tests/domain/test_d.py tests/services/app/test_e.py tests/test_x.py tests/conftest.py; do
        mkdir -p "$p/$(dirname "$rel")"
        printf 'def test_z():\n    assert 1\n' >"$p/$rel"
        : >"$p/ruff.calls"
        rv2_ruff "$p" "$p/$rel" >/dev/null
        want="$(cd "$p" && CLAUDE_PROJECT_DIR="$p" python3 -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import tdd_py_lib as lib
lib.configure()
print("skip" if lib.is_frozen_test(sys.argv[2]) else "format")' "$addon" "$p/$rel")"
        [[ -z "$(grep '^format ' "$p/ruff.calls")" ]] && fmt=skip || fmt=format
        CASES=$((CASES + 1))
        [[ "$fmt" == "$want" ]] || fail ruff-on-save.sh RV15 "$rel: the hook says $fmt, is_frozen_test says $want"
    done

    # RV16 an a8efa59 addon hook beside the new tdd_py_lib.py (KeyError at run time) asks, never passes.
    p="$tmp/rv16"
    pv_addon_project "$p"
    mkdir -p "$p/tests/services" "$tmp/rv16-hooks" "$p/app/services"
    printf 'from app.services.a import f\n\ndef test_f():\n    assert f() == 1\n' >"$p/tests/services/test_a.py"
    cp "$addon/tdd_py_lib.py" "$tmp/rv16-hooks/"
    for hook in tdd-freeze-tests-py.py tdd-require-red-py.py; do
        git -C "$PROJECT_ROOT" cat-file -e "a8efa59:addons/fastapi/hooks/$hook" 2>/dev/null || { printf 'SKIP RV16[%s]: a8efa59 absent\n' "$hook"; continue; }
        git -C "$PROJECT_ROOT" show "a8efa59:addons/fastapi/hooks/$hook" >"$tmp/rv16-hooks/$hook"
        case "$hook" in
            tdd-freeze-tests-py.py) rel=tests/services/test_a.py; old=$'def test_f():\n    assert 2 == 2\n' ;;
            *) rel=app/services/b.py; old='x = 1' ;;
        esac
        out="$(rv2_pair "$tmp/rv16-hooks" "$hook" "$p" "$(jq -cn --arg f "$p/$rel" --arg c "$old" \
            '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
        pv_expect "RV16[$hook]" ask "$out" "rerun install.sh on this project, or /kit:init"
    done

    # RV17 a new addon hook beside the a8efa59 tdd_py_lib.py (no configure) asks, never crashes through.
    p="$tmp/rv17"
    pv_addon_project "$p"
    mkdir -p "$tmp/rv17-hooks"
    if git -C "$PROJECT_ROOT" show "a8efa59:addons/fastapi/hooks/tdd_py_lib.py" >"$tmp/rv17-hooks/tdd_py_lib.py" 2>/dev/null; then
        for hook in tdd-freeze-tests-py.py tdd-require-red-py.py enforce-backend-layers.py; do
            cp "$addon/$hook" "$tmp/rv17-hooks/"
            out="$(rv2_pair "$tmp/rv17-hooks" "$hook" "$p" "$(jq -cn --arg f "$p/app/services/new.py" --arg c 'x = 1' \
                '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
            pv_expect "RV17[$hook]" ask "$out" "rerun install.sh on this project, or /kit:init"
        done
    else
        printf 'SKIP RV17: a8efa59 absent\n'
    fi

    # RV19-RV23: the freeze on a healthy config.
    p="$tmp/rv19"
    pv_addon_project "$p"
    mkdir -p "$p/tests/services"
    printf 'from app.services.a import f\n\ndef test_f():\n    assert f() == 1\n' >"$p/tests/services/test_a.py"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_a.py" \
        --arg c $'from app.services.a import f\n\ndef test_f():\n    assert f() == 1\n' \
        '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
    pv_expect RV19 pass "$out" "identical re-save"
    CASES=$((CASES + 1))
    [[ "$out" == *systemMessage* && "$out" != *permissionDecision* ]] || fail tdd-freeze-tests-py "RV19" "an identical re-save is a notice, not an ask, got '${out:0:200}'"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_a.py" \
        --arg c $'from app.services.a import f\n\ndef test_f():\n    assert f() == 9\n' \
        '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
    pv_expect RV19 deny "$out" "frozen"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_a.py" \
        --arg o '    assert f() == 1' --arg n $'    assert f() == 1\n\n\ndef test_g():\n    assert f() == 2' \
        '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}')")"
    pv_expect RV20 pass "$out" "case appended"
    CASES=$((CASES + 1))
    [[ "$out" != *permissionDecision* ]] || fail tdd-freeze-tests-py "RV20" "a pure appended case is a notice, not an ask, got '${out:0:200}'"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_a.py" \
        --arg o '    assert f() == 1' --arg n $'    assert f() == 1\n    assert f() == 3' \
        '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}')")"
    pv_expect RV21 deny "$out" "INSIDE a case"

    # RV24 an allowed template suffix strips the whole `.env.<suffix>` word, never a prefix of another name.
    p="$tmp/rv24"
    pv_project "$p" '.env_template_suffixes = ["loc"]'
    : >"$p/.env.loc"
    : >"$p/.env.local"
    pv_expect RV24 deny "$(pv_tool prevent-destructive-commands.sh "$p" Bash 'cat .env.local')" "Reading or copying secret files"
    pv_expect RV24 pass "$(pv_tool prevent-destructive-commands.sh "$p" Bash 'cat .env.loc')"
    pv_expect RV24 pass "$(pv_tool prevent-destructive-commands.sh "$p" Bash 'cat .env.loc | wc -l')"

    p="$tmp/rv22"
    pv_addon_project "$p" '.fastapi.tests_root = "test"'
    mkdir -p "$p/test/services" "$p/tests/services"
    printf 'def test_f():\n    assert 1 == 1\n' >"$p/test/services/test_a.py"
    printf 'def test_f():\n    assert 1 == 1\n' >"$p/tests/services/test_a.py"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/test/services/test_a.py" \
        --arg c $'def test_f():\n    assert 2 == 2\n' '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
    pv_expect RV22 deny "$out" "frozen"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_a.py" \
        --arg c $'def test_f():\n    assert 2 == 2\n' '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
    pv_expect RV22 pass "$out"

    p="$tmp/rv23"
    pv_addon_project "$p" '.fastapi.test_first_dirs = ["domain"]'
    mkdir -p "$p/tests/domain" "$p/tests/services"
    printf 'def test_f():\n    assert 1 == 1\n' >"$p/tests/domain/test_b.py"
    printf 'def test_f():\n    assert 1 == 1\n' >"$p/tests/services/test_a.py"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/domain/test_b.py" \
        --arg c $'def test_f():\n    assert 2 == 2\n' '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
    pv_expect RV23 deny "$out" "frozen"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_a.py" \
        --arg c $'def test_f():\n    assert 2 == 2\n' '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')")"
    pv_expect RV23 pass "$out"
    rm -rf "$tmp"
}

# Builds the app-roots tree in <dir> for <variant>: approots, approots-none, approots-bad,
# approots-apps, approots-link, approots-two, codegen, codegen-none, codegen-bad.
make_app_tree() {
    local dir="$1" variant="$2" f
    mkdir -p "$dir/frontend/src" "$dir/other/src" "$dir/src/types" "$dir/docs" "$dir/app"
    for f in package.json tsconfig.json tsconfig.app.json vite.config.ts eslint.config.js; do
        printf '{}\n' >"$dir/frontend/$f"
    done
    printf 'export const a = 1\n' >"$dir/frontend/src/a.ts"
    printf '{}\n' >"$dir/other/package.json"
    printf '{}\n' >"$dir/package.json"
    case "$variant" in
        approots) write_project_json "$dir" '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[]}' ;;
        approots-none | codegen-none) ;;
        approots-bad) write_project_json "$dir" '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[],"x":1}' ;;
        approots-apps)
            mkdir -p "$dir/apps/web/sub"
            printf '{}\n' >"$dir/apps/web/vite.config.ts"
            printf '{}\n' >"$dir/apps/web/sub/vite.config.ts"
            write_project_json "$dir" '{"schema_version":1,"app_roots":["apps/web"],"codegen_commands":[]}' ;;
        approots-link)
            ln -s frontend "$dir/fe"
            write_project_json "$dir" '{"schema_version":1,"app_roots":["frontend"],"codegen_commands":[]}' ;;
        approots-two) write_project_json "$dir" '{"schema_version":1,"app_roots":["frontend","other"],"codegen_commands":[]}' ;;
        codegen) write_project_json "$dir" '{"schema_version":1,"app_roots":[],"codegen_commands":[["supabase","gen","types"],["pnpm","supabase","gen","types"]]}' ;;
        codegen-sb) write_project_json "$dir" '{"schema_version":1,"app_roots":[],"codegen_commands":[["supabase","gen","types"]]}' ;;
        codegen-bad) write_project_json "$dir" '{"schema_version":1,"app_roots":[],"codegen_commands":[["supabase","gen","types"]],"x":1}' ;;
    esac
}

# Edit (or Write) of <rel> through protect-files.sh in project <dir>.
pf_probe() {
    local dir="$1" tool="$2" rel="$3"
    project_hook_probe protect-files.sh "$dir" \
        "$(jq -cn --arg t "$tool" --arg f "$dir/$rel" \
            '{tool_name:$t,tool_input:{file_path:$f,old_string:"a",new_string:"b",content:"x"}}')"
}

# <command> through the shell guard in project <dir>, cwd <dir>/<sub> (default the root).
pd_probe() {
    local dir="$1" command="$2" sub="${3:-}"
    project_hook_probe prevent-destructive-commands.sh "$dir" \
        "$(jq -cn --arg c "$command" --arg cwd "$dir${sub:+/$sub}" \
            '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}')"
}

# AR1-AR12, AR23, AR25, PC11 (app-roots-codegen step 2): a declared app root's configs are
# guarded like the root's; nothing moves without a valid declaration.
run_app_roots_cases() {
    local tmp out start ms
    tmp="$(mktemp -d)"
    make_app_tree "$tmp/a" approots
    out="$(pf_probe "$tmp/a" Edit frontend/vite.config.ts)"
    g15_expect AR1 ask "$out" "guarded path"
    out="$(pf_probe "$tmp/a" Write frontend/package.json)"
    g15_expect AR2 ask "$out" "guarded path"
    out="$(pf_probe "$tmp/a" Edit frontend/tsconfig.app.json)"
    g15_expect AR2 ask "$out" "guarded path"
    out="$(pf_probe "$tmp/a" Edit frontend/eslint.config.js)"
    g15_expect AR2 ask "$out" "guarded path"
    out="$(pd_probe "$tmp/a" 'echo {} > frontend/package.json')"
    g15_expect AR3 ask "$out" "guarded path"
    out="$(pd_probe "$tmp/a" 'sed -i s/a/b/ frontend/vite.config.ts')"
    g15_expect AR4 deny "$out" "Use Write/Edit"
    out="$(pf_probe "$tmp/a" Edit frontend/src/a.ts)"
    g15_expect AR5 pass "$out"
    out="$(pf_probe "$tmp/a" Write other/package.json)"
    g15_expect AR6 pass "$out"
    out="$(pd_probe "$tmp/a" 'rm -r frontend')"
    g15_expect AR9 ask "$out" "guarded path"
    out="$(project_hook_probe protect-files.sh "$tmp/a" \
        "$(jq -cn --arg f "$tmp/a/frontend/vite.config.ts" '{tool_name:"Read",tool_input:{file_path:$f}}')")"
    g15_expect AR11 pass "$out"
    out="$(project_hook_probe protect-files.sh "$tmp/a" \
        "$(jq -cn --arg p "$tmp/a/frontend" '{tool_name:"Grep",tool_input:{pattern:"x",path:$p}}')")"
    g15_expect AR11 pass "$out"
    out="$(project_hook_probe protect-files.sh "$tmp/a" \
        "$(jq -cn '{tool_name:"Grep",tool_input:{pattern:"x",glob:"**/vite.config.*"}}')")"
    g15_expect AR11 pass "$out"
    out="$(project_hook_probe protect-files.sh "$tmp/a" \
        "$(jq -cn '{tool_name:"Glob",tool_input:{pattern:"frontend/vite.config.*"}}')")"
    g15_expect AR11 pass "$out"

    make_app_tree "$tmp/n" approots-none
    out="$(CLAUDE_PROJECT_DIR="$tmp/n" bash -c 'source "$1/hook-guarded.sh"; cwk_is_guarded apps/web/package.json; echo "$?"; cwk_is_guarded frontend/vite.config.ts; echo "$?"' _ "$HOOKS_DIR")"
    CASES=$((CASES + 1))
    [[ "$out" == $'1\n1' ]] || fail hook-guarded.sh AR7 "expected nothing guarded with no project.json, got '$out'"

    make_app_tree "$tmp/b" approots-bad
    out="$(pf_probe "$tmp/b" Edit frontend/vite.config.ts)"
    g15_expect AR8 ask "$out" "rerun install.sh on this project, or /kit:init"

    make_app_tree "$tmp/w" approots-apps
    out="$(pf_probe "$tmp/w" Edit apps/web/vite.config.ts)"
    g15_expect AR10 ask "$out" "guarded path"
    out="$(pf_probe "$tmp/w" Edit apps/web/sub/vite.config.ts)"
    g15_expect AR10 pass "$out"

    mkdir -p "$tmp/shim"
    printf '#!/bin/sh\ntouch %s/SHIM_RAN\nexit 0\n' "$tmp" >"$tmp/shim/python3"
    chmod +x "$tmp/shim/python3"
    CLAUDE_PROJECT_DIR="$tmp/a" PATH="$tmp/shim:$PATH" bash -c 'source "$1/hook-guarded.sh"' _ "$HOOKS_DIR"
    CASES=$((CASES + 1))
    [[ ! -e "$tmp/SHIM_RAN" ]] || fail hook-guarded.sh AR12 "sourcing hook-guarded.sh ran python3"

    start="$(date +%s%N)"
    pf_probe "$tmp/a" Edit frontend/vite.config.ts >/dev/null
    ms=$((($(date +%s%N) - start) / 1000000))
    CASES=$((CASES + 1))
    [[ "$ms" -lt 2000 ]] || fail protect-files.sh AR23 "an app-root Edit took $ms ms"

    make_app_tree "$tmp/t" approots-two
    out="$(pf_probe "$tmp/t" Edit frontend/vite.config.ts)"
    g15_expect AR25 ask "$out" "guarded path"
    out="$(pf_probe "$tmp/t" Write other/package.json)"
    g15_expect AR25 ask "$out" "guarded path"

    mkdir -p "$tmp/shim4"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>%s/pylog\nexec %s "$@"\n' "$tmp" "$(command -v python3)" >"$tmp/shim4/python3"
    chmod +x "$tmp/shim4/python3"
    out="$(PATH="$tmp/shim4:$PATH" \
        pd_probe "$tmp/a" 'echo a > frontend/x.txt; echo b > other/y.txt; echo c > docs/z.txt; echo d > frontend/w.txt')"
    CASES=$((CASES + 1))
    [[ "$(grep -c 'project_config.py shell' "$tmp/pylog" 2>/dev/null || true)" -le 1 ]] \
        || fail hook-guarded.sh AR27 "the reader ran $(grep -c 'project_config.py shell' "$tmp/pylog") times in one hook run"
    CASES=$((CASES + 1))
    [[ "$(grep -c 'project_config.py shell' "$tmp/pylog" 2>/dev/null || true)" -ge 1 ]] \
        || fail hook-guarded.sh AR27 "the reader never ran: the case proves nothing"

    mkdir -p "$tmp/shim3"
    printf '#!/bin/sh\ncase "$*" in *project_config.py*) echo frontend; exit 3 ;; esac\nexec %s "$@"\n' \
        "$(command -v python3)" >"$tmp/shim3/python3"
    chmod +x "$tmp/shim3/python3"
    out="$(PATH="$tmp/shim3:$PATH" pf_probe "$tmp/a" Edit frontend/vite.config.ts)"
    g15_expect AR30 ask "$out" "rerun install.sh on this project, or /kit:init"

    mkdir -p "$tmp/plant"
    printf 'import pathlib\npathlib.Path(%s).touch()\nfrom json import *\n' "'$tmp/PLANTED'" >"$tmp/plant/json.py"
    out="$(PYTHONPATH="$tmp/plant" pf_probe "$tmp/a" Edit frontend/vite.config.ts)"
    g15_expect PC11 ask "$out" "guarded path"
    CASES=$((CASES + 1))
    [[ ! -e "$tmp/PLANTED" ]] || fail hook-guarded.sh PC11 "a json.py on PYTHONPATH ran inside the roots read"
    rm -r "$tmp"
}

# AR13-AR21, AR24, AR26 (app-roots-codegen step 3): a cfg option that resolves to a declared
# app root passes; the real path of the target decides, never the cwd. AR22 is the
# existing shell-guard.jsonl cfg rows, replayed unchanged by run_shell_guard_cases.
run_app_roots_cfg_cases() {
    local tmp out
    tmp="$(mktemp -d)"
    make_app_tree "$tmp/a" approots
    mkdir -p "$tmp/a/frontend/src" "$tmp/a/other/src"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc --noEmit -p .' frontend)"
    g15_expect AR13 pass "$out"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc --noEmit -p frontend')"
    g15_expect AR14 pass "$out"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc -p frontend/tsconfig.app.json')"
    g15_expect AR15 pass "$out"
    out="$(pd_probe "$tmp/a" 'pnpm vitest --root frontend')"
    g15_expect AR16 pass "$out"
    out="$(pd_probe "$tmp/a" 'pnpm exec vite build --config frontend/vite.config.ts')"
    g15_expect AR16 pass "$out"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc -p .' other)"
    g15_expect AR17 ask "$out" "other (cfg)"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc -p .' frontend/src)"
    g15_expect AR18 pass "$out"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc -p .' other/src)"
    g15_expect AR18 ask "$out" "other (cfg)"
    out="$(pd_probe "$tmp/a" 'pnpm exec tsc -p frontend/../other')"
    g15_expect AR19 ask "$out" "(cfg)"

    make_app_tree "$tmp/l" approots-link
    out="$(pd_probe "$tmp/l" 'pnpm exec tsc -p fe')"
    g15_expect AR20 pass "$out"

    make_app_tree "$tmp/n" approots-none
    out="$(pd_probe "$tmp/n" 'pnpm exec tsc -p frontend')"
    g15_expect AR21 ask "$out" "frontend (cfg)"

    make_app_tree "$tmp/b" approots-bad
    out="$(pd_probe "$tmp/b" 'pnpm exec tsc -p frontend')"
    g15_expect AR24 ask "$out" "frontend (cfg)"

    make_app_tree "$tmp/t" approots-two
    out="$(pd_probe "$tmp/t" 'pnpm exec tsc -p other')"
    g15_expect AR26 pass "$out"

    make_app_tree "$tmp/s" approots-link
    write_project_json "$tmp/s" '{"schema_version":1,"app_roots":["fe"],"codegen_commands":[]}'
    out="$(pd_probe "$tmp/s" 'pnpm exec tsc -p frontend')"
    g15_expect AR28 ask "$out" "frontend (cfg)"

    # A library from before cwk_app_roots next to this guard fails closed, never exit 127.
    mkdir -p "$tmp/stale"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp/stale"/
    sed -i '/^cwk_app_roots() {$/,/^}$/d; s/^    cwk_app_roots$//' "$tmp/stale/hook-guarded.sh"
    out="$(HOOKS_DIR="$tmp/stale" pd_probe "$tmp/a" 'pnpm exec tsc -p frontend; echo x > .claude/settings.json')"
    g15_expect AR29 deny "$out"
    rm -r "$tmp"
}

# CG5-CG22 (app-roots-codegen step 4): a redirect onto a .ts/.tsx/.py source is denied,
# except from a listed generator (its own segment's command), which asks "codegen". CG1-CG4
# and CG12's first half are the amended shell-guard.jsonl rows X32.07/08, X42.04/05, X28.79,
# X24.413.
run_codegen_cases() {
    local tmp c out cmd
    tmp="$(mktemp -d)"
    make_app_tree "$tmp/c" codegen
    c="$tmp/c"
    mkdir -p "$c/src/features/a" "$c/app/services"
    out="$(pd_probe "$c" 'echo x > app/a.py')"
    g15_expect CG5 deny "$out" "Use Write/Edit"
    out="$(pd_probe "$c" 'pnpm supabase gen types --local > src/types/database.types.ts')"
    g15_expect CG6 ask "$out" "codegen: src/types/database.types.ts"
    out="$(pd_probe "$c" 'supabase gen types > src/types/db.ts')"
    g15_expect CG7 ask "$out" "codegen: src/types/db.ts"
    out="$(pd_probe "$c" 'supabase gen types; echo x > src/a.ts')"
    g15_expect CG8 deny "$out" "Use Write/Edit"
    out="$(pd_probe "$c" 'echo $(supabase gen types) > src/a.ts')"
    g15_expect CG9 deny "$out" "Use Write/Edit"
    out="$(pd_probe "$c" 'env FOO=1 supabase gen types > src/types/db.ts')"
    g15_expect CG10 ask "$out" "codegen: src/types/db.ts"
    out="$(pd_probe "$c" 'supabase gen types | tee src/types/db.ts')"
    g15_expect CG11 deny "$out" "Use Write/Edit"
    out="$(pd_probe "$c" 'supabase gen types > vite.config.ts')"
    g15_expect CG12 deny "$out" "Use Write/Edit"
    out="$(pd_probe "$c" 'echo x > docs/a.md')"
    g15_expect CG13 pass "$out"
    out="$(pd_probe "$c" 'echo x > /tmp/a.py')"
    g15_expect CG13 pass "$out"
    out="$(pd_probe "$c" 'echo x >/dev/null')"
    g15_expect CG13 pass "$out"
    out="$(pd_probe "$c" 'echo x > /tmp/a.ts')"
    g15_expect CG13 ask "$out" "TypeScript source from the shell"
    out="$(pd_probe "$c" 'echo x > src/a.utils.ts')"
    g15_expect CG13 deny "$out" "test-first layer or a test file"
    out="$(pd_probe "$c" 'echo x > app/services/x.py')"
    g15_expect CG13 deny "$out" "Python test-first layer"
    out="$(pd_probe "$c" 'echo x > src/App.tsx')"
    g15_expect CG16 deny "$out" "Use Write/Edit"
    out="$(pd_probe "$c" "supabase gen types > src/features/a/a.utils.t's'")"
    g15_expect CG17 deny "$out" "test-first layer or a test file"
    out="$(pd_probe "$c" 'supabase gen types > src/a.test.ts')"
    g15_expect CG17 deny "$out" "test-first layer or a test file"
    out="$(pd_probe "$c" 'supabase gen types > app/services/x.py')"
    g15_expect CG17 deny "$out" "Python test-first layer"
    out="$(pd_probe "$c" 'supabase gen types > docs/x.md')"
    g15_expect CG18 pass "$out"
    out="$(pd_probe "$c" 'supabase gen types > package.json')"
    g15_expect CG18 ask "$out" "package.json written by >"
    CASES=$((CASES + 1))
    [[ "$out" != *">cg"* ]] || fail prevent-destructive-commands.sh CG18 "the internal verb leaks: '${out:0:300}'"
    out="$(pd_probe "$c" 'pnpm supabase gen types --local > src/types/db.ts && rm -rf node_modules/x')"
    g15_expect CG20 ask "$out" "node_modules/x"
    out="$(pd_probe "$c" "echo x > src/b.ts; echo y > src/a.utils.t's'")"
    g15_expect CG21 deny "$out" "test-first layer or a test file"
    out="$(pd_probe "$c" 'supabase gen types > "$P/.claude/.tdd-red/x"')"
    g15_expect CG22 deny "$out" "BLOCKED: >"
    CASES=$((CASES + 1))
    [[ "$out" != *">cg"* ]] || fail prevent-destructive-commands.sh CG22 "the internal verb leaks: '${out:0:300}'"
    out="$(pd_probe "$c" 'mv /tmp/x app/a.ts')"
    g15_expect CG15 ask "$out" "TypeScript source from the shell"

    make_app_tree "$tmp/n" codegen-none
    out="$(pd_probe "$tmp/n" 'pnpm supabase gen types --local > src/types/database.types.ts')"
    g15_expect CG14 deny "$out" "Use Write/Edit"

    make_app_tree "$tmp/r" codegen-sb
    for cmd in 'pnpm supabase gen types --linked > src/types/database.types.ts' 'npx supabase gen types > src/types/db.ts' \
        'pnpm exec supabase gen types > src/types/db.ts' 'pnpm dlx supabase gen types > src/types/db.ts' \
        'npm exec supabase gen types > src/types/db.ts' 'yarn supabase gen types > src/types/db.ts' \
        'yarn dlx supabase gen types > src/types/db.ts' 'bunx supabase gen types > src/types/db.ts' \
        'bun x supabase gen types > src/types/db.ts'; do
        out="$(pd_probe "$tmp/r" "$cmd")"
        g15_expect "CG30[$cmd]" ask "$out" "codegen: src/types/"
    done
    for cmd in 'pnpm evil supabase gen types > src/types/db.ts' 'pnpmx supabase gen types > src/types/db.ts' \
        'pnpm exec evil supabase gen types > src/types/db.ts'; do
        out="$(pd_probe "$tmp/r" "$cmd")"
        g15_expect "CG31[$cmd]" deny "$out" "Use Write/Edit"
    done

    make_app_tree "$tmp/b" codegen-bad
    out="$(pd_probe "$tmp/b" 'supabase gen types > src/types/db.ts')"
    g15_expect CG19 deny "$out" "Use Write/Edit"
    CASES=$((CASES + 1))
    [[ "$out" != *"shell guard unavailable"* ]] || fail prevent-destructive-commands.sh CG19 "the resolver crashed on a bad file"
    out="$(pd_probe "$tmp/b" 'echo x > docs/a.md')"
    g15_expect CG19 ask "$out" "rerun install.sh on this project, or /kit:init"

    : >"$c/src/features/a/a.utils.ts"
    : >"$c/app/a.py"
    for cmd in 'echo x > src/features/a/a.utils.t[s]' 'echo x > src/b.t[s]' 'echo x > src/b.t?' 'echo x >> src/b.t[s]' \
        'echo x > app/a.p[y]' 'cp /etc/hostname src/features/a/a.utils.t[s]' \
        'sed -i s/a/b/ src/features/a/a.utils.t[s]' 'echo x | tee src/features/a/a.utils.t[s]' \
        'supabase gen types > src/types/d.t[s]'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG28[$cmd]" deny "$out" "unresolved write target"
    done
    for cmd in 'cat src/*.ts > /tmp/out.txt' 'ls src/*.ts' 'rm src/*.log' 'sed -i s/a/b/ docs/*.md' 'echo x > docs/*.md'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG29[$cmd]" pass "$out"
    done
    out="$(pd_probe "$c" 'supabase gen types > src/a.spec.ts')"
    g15_expect CG26 deny "$out" "A test-first module or a test file is written only with Write/Edit"
    out="$(pd_probe "$c" 'supabase gen types > src/types/db.ts && prettier --write .')"
    g15_expect CG27 ask "$out" "runs a formatter in write mode"
    out="$(pd_probe "$c" 'pnpm supabase gen types --local > src/types/db.ts && prettier --write .')"
    g15_expect CG23 ask "$out" "runs a formatter in write mode"
    out="$(pd_probe "$c" 'supabase gen types > src/types/db.ts; ruff format .')"
    g15_expect CG24 ask "$out" "runs a formatter in write mode"
    out="$(pd_probe "$c" 'echo x > src/b.ts && eslint --fix src/a.test.ts')"
    g15_expect CG25 deny "$out" "with a fix flag rewrites the test file"

    # CG32-CG36 (re-review fixes): a bracket or brace class can spell the dot, the extension or a
    # test name, so any glob last segment with one asks; `*`/`?` alone asks on no dot, a glob
    # extension, ts/tsx/py, or test/spec in the name. Each branch has a case that only it can fail.
    for cmd in 'echo x > src/x.utils[.]ts' 'echo x > src/App[.]tsx' 'echo x > src/*[.]ts' \
        'sed -i s/a/b/ src/a.t[e]st[.]ts' 'cp /etc/hostname src/a[.]ts' 'mv /tmp/x lib/a[.]ts' \
        'echo x | tee src/a[.]ts' 'install /etc/hostname src/a[.]ts' 'supabase gen types > src/db[.]ts' \
        'echo x > src/{a,b}.ts' 'echo x > src/{a,b}.js' 'echo x > src/*' 'echo x > src/*test*.js' \
        'echo x > src/*.spec.js' 'echo x > src/a.*' 'echo x > src/a.?s' 'echo x > src/*.ts' \
        'echo x > src/*.tsx' 'echo x > app/*.py' 'echo x > src/t[e]st.js'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG32[$cmd]" deny "$out" "unresolved write target"
    done
    for cmd in 'echo x > docs/*.md' 'echo x > docs/*.json' 'sed -i s/a/b/ docs/*.md' 'mv /tmp/x docs/*.md'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG33[$cmd]" pass "$out"
    done
    out="$(pd_probe "$c" 'supabase gen types > db[.]ts')"
    g15_expect CG32r deny "$out"
    out="$(pd_probe "$c" 'echo x > src/*[.]ts')"
    g15_expect CG34 deny "$out" "onto a glob that may match a source or test file" "src"
    CASES=$((CASES + 1))
    [[ "$out" != *"src/*[.]ts"* || "$out" == *"under src"* ]] || fail prevent-destructive-commands.sh CG34 "the glob ask names a wrong path: '${out:0:300}'"
    out="$(pd_probe "$c" 'supabase gen types > src/types/db.ts && mv /tmp/x lib/b.ts')"
    g15_expect CG35 ask "$out" "This writes a TypeScript source from the shell"
    out="$(pd_probe "$c" 'supabase gen types > src/types/db.ts')"
    g15_expect CG35b ask "$out" "codegen: src/types/db.ts"
    mkdir -p "$tmp/stale2"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp/stale2"/
    sed -i '/^cwk_app_roots() {$/,/^}$/d; s/^    cwk_app_roots$//' "$tmp/stale2/hook-guarded.sh"
    sed -i 's/ cwk_app_roots >\/dev\/null/ >\/dev\/null/' "$tmp/stale2/hook-lib.sh"
    out="$(HOOKS_DIR="$tmp/stale2" pd_probe "$c" 'pnpm exec tsc -p frontend; echo x > .claude/settings.json')"
    g15_expect CG36 deny "$out"
    # CG37-CG42 (fix batch 3): a brace holding a slash leaves only a closing bracket in the last
    # segment; nocaseglob and extglob spell a source name the plain comparison never sees.
    for cmd in 'echo x | tee src/{features/a/a.utils.t?,y.md}' 'tee src/{x/a.t*,y.json}' \
        'sed -i s/a/b/ src/{features/a/*,y.md}'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG37[$cmd]" deny "$out" "unresolved write target"
    done
    for cmd in $'shopt -s nocaseglob\necho x > src/*.TEST.TS' $'shopt -s nocaseglob\necho x > src/*.TS' \
        $'shopt -s nocaseglob\necho x > app/*.PY' 'shopt -s nocaseglob; echo x > src/*.TEST.TS' \
        'shopt -s nocaseglob; echo x > src/*.TS' 'shopt -s nocaseglob; echo x > app/*.PY'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG38[$cmd]" deny "$out" "unresolved write target"
    done
    for cmd in $'shopt -s extglob\necho x > src/!(*.md)' $'shopt -s extglob\necho x > src/a.!(md)' \
        $'shopt -s extglob\necho x > src/a.@(ts)' $'shopt -s extglob\necho x > src/a.+(t|s)' \
        $'shopt -s extglob\ncp /etc/hostname src/a.!(md)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG39[$cmd]" deny "$out" "unresolved write target"
    done
    out="$(pd_probe "$c" 'echo x > src/*/Makefile')"
    g15_expect CG40 deny "$out" "unresolved write target"
    g15_expect CG41 deny "$(pd_probe "$c" 'supabase gen types > db[.]ts')" "unresolved write target"
    out="$(pd_probe "$c" 'echo x > src/*/a.ts')"
    g15_expect CG42 deny "$out" "a.ts under src"
    # CG43-CG49 (fix batch 4): extglob syntax asks without a literal `shopt` (the option is set by
    # a spelling the text never shows, or by a sourced file); the message names the syntax; a
    # glob without shopt, a failing lowercase step and a lone `]` still ask.
    for cmd in $'sh\'\'opt -s extglob\necho x > src/a.!(md)' $'sh\\opt -s extglob\necho x > src/a.!(md)' \
        $'. f\necho x > src/a.utils.+(ts)' $'source f\necho x > src/a.@(ts)' $'s=sh; ${s}opt -s extglob; echo x > src/a.!(md)' \
        $'. f\ncp /etc/hostname src/a.!(md)' $'. f\necho x >> src/a.+(ts)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG43[$cmd]" deny "$out" "unresolved write target" "extglob syntax"
    done
    g15_expect CG43mv deny "$(pd_probe "$c" $'. f\nmv /tmp/x src/a.!(md)')"
    out="$(pd_probe "$c" $'sh\'\'opt -s extglob\necho x > src/a.!(md)')"
    CASES=$((CASES + 1))
    [[ "$out" != *"shopt is set"* && "$out" != *"src/a.!:"* && "$out" != *"src/a.!)"* ]] \
        || fail prevent-destructive-commands.sh CG43m "the extglob ask claims shopt or names a cut path: '${out:0:300}'"
    out="$(pd_probe "$c" 'echo x > docs/a.md')"
    g15_expect CG44 pass "$out"
    out="$(pd_probe "$c" 'echo x > docs/a.md; echo "ok"')"
    g15_expect CG44b pass "$out"
    for cmd in 'echo x > src/*.TS' 'echo x > src/*.Tsx' 'echo x > app/*.PY' 'echo x > src/*.TEST.js'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG45[$cmd]" deny "$out" "unresolved write target"
    done
    for cmd in $'sh\'\'opt -s nocaseglob\necho x > src/*.TS' $'shopt -u nocaseglob\necho x > src/*.TS'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG46[$cmd]" deny "$out" "unresolved write target"
    done
    mkdir -p "$tmp/trfail"
    printf '#!/bin/sh\ncase "$*" in *upper*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v tr)" >"$tmp/trfail/tr"
    chmod +x "$tmp/trfail/tr"
    out="$(PATH="$tmp/trfail:$PATH" pd_probe "$c" 'echo x > docs/*.md')"
    g15_expect CG47 deny "$out" "unresolved write target"
    out="$(pd_probe "$c" 'echo x > src/*/a.json]')"
    g15_expect CG48 deny "$out" "unresolved write target" "may match a source or test file"
    out="$(pd_probe "$c" $'shopt -s extglob\necho x > src/a.!(md)')"
    g15_expect CG39b deny "$out" "uses extglob syntax"
    for cmd in 'echo x > src/a.?(ts)' 'echo x > src/a.*(ts)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG49[$cmd]" deny "$out" "unresolved write target"
    done
    out="$(pd_probe "$c" 'supabase gen types > src/types/db.ts && echo "a+(b)"')"
    g15_expect CG49c ask "$out" "codegen: src/types/db.ts"
    out="$(pd_probe "$c" 'echo x > .')"
    g15_expect CG50 ask "$out" "the project root written by >"
    # CG51-CG53 (fix batch 5): bash removes backslash-newline before parsing, so `!\<newline>(md)`
    # is a live extglob; the text check reads a joined copy. A harmless continuation still passes.
    for cmd in $'sh\'\'opt -s extglob\necho x > src/a.!\\\n(md)' $'. f\necho x > src/a.utils.+\\\n(ts)' \
        $'. f\necho x > src/a.@\\\n(ts)' $'. f\necho x > src/a.!\\\n\\\n(md)' $'. f\necho x > src/a.\\\n!\\\n(md)' \
        $'. f\ncp /etc/hostname src/a.!\\\n(md)' $'. f\necho x | tee src/a.!\\\n(md)' \
        $'. f\nsed -i s/a/b/ src/a.!\\\n(md)' $'. f\nln -sf /tmp/x src/a.@\\\n(ts)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG51[$cmd]" deny "$out" "extglob syntax"
    done
    out="$(pd_probe "$c" $'. f\nsupabase gen types > src/types/db.ts\necho x > src/a.!\\\n(md)')"
    g15_expect CG52 deny "$out" "extglob syntax"
    out="$(pd_probe "$c" $'echo x \\\n> docs/a.md')"
    g15_expect CG53 pass "$out"
    # CG54-CG60 (tmp-glob-escape): a /tmp target holding `..` is not exempt (the glob segment walks
    # back up to /, then down to the project); /dev/fd/N past 0-2 asks; plain /tmp, /dev/null and
    # /dev/fd/0-2 keep passing. "not pass" = ask or deny.
    local up="/tmp/*/../.." verdict id id_cmd
    for id_cmd in "CG54|echo x > $up$c/.claude/settings.json" "CG55|echo x > $up$c/src/a.py" \
        "CG56|echo x > $up$c/src/a.utils.t?" "CG57|echo x > /tmp/..$c/src/a.py"; do
        id="${id_cmd%%|*}"
        cmd="${id_cmd#*|}"
        out="$(pd_probe "$c" "$cmd")"
        verdict="${out%%$'\n'*}"
        CASES=$((CASES + 1))
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || fail prevent-destructive-commands.sh "${id}[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
    done
    for cmd in "exec 9<\"$c\"; echo x > /dev/fd/9/.claude/settings.json" \
        "exec 9<\"$c\"
echo x > /dev/fd/9/.claude/settings.json"; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG58[$cmd]" ask "$out"
    done
    out="$(pd_probe "$c" 'echo x > /dev/fd/9')"
    g15_expect CG59 ask "$out"
    for cmd in 'echo x > /tmp/out.txt' 'echo x > /tmp/d/out.txt' 'echo x > /dev/fd/2' \
        'echo x > /dev/null'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG60[$cmd]" pass "$out"
    done
    # CG61-CG70 (tmp-exemption): an fd alias re-bound to a project file, a brace or glob that
    # expands to `..`, and a symlink under /tmp (made beforehand or in the same command, mid-path or
    # final) all land in the project, so they do not pass; plain /tmp and stderr usage keeps passing.
    local s
    s="$(mktemp -d /tmp/cg-tmpx.XXXXXX)"
    mkdir -p "$s/ok" "$c/.claude"
    : >"$c/src/a.py"
    ln -s "$c/src" "$s/preB"
    ln -s "$c/src/a.py" "$s/x.log"
    for id_cmd in "CG61|echo x 1<$c/src/a.py >/dev/fd/1" \
        "CG62|exec 2<$c/.claude/settings.json; echo x > /dev/stderr" \
        "CG62|exec 2<$c/.claude/settings.json; echo x > /dev/fd/2" \
        "CG63|echo x 0<$c/src/a.py >/dev/fd/0" \
        "CG64|echo x | tee /tmp/{.,}.$c/src/a.py" \
        "CG65|shopt -u globskipdots; echo x > /tmp/.[.]$c/.claude/settings.json" \
        "CG65|shopt -u globskipdots; echo x > /tmp/.?$c/.claude/settings.json" \
        "CG65|shopt -u globskipdots; echo x > /tmp/.*$c/.claude/settings.json" \
        "CG66|ln -s $c/.claude $s/l && echo x > $s/l/settings.json" \
        "CG67|echo x > $s/preB/../.claude/settings.json" \
        "CG68|echo x > $s/pre?/a.py" \
        "CG69|echo x > $s/x.log" "CG69|echo x | tee $s/x.log" "CG69|cp /etc/hostname $s/x.log" \
        "CG69|echo x > $s/*.log"; do
        id="${id_cmd%%|*}"
        cmd="${id_cmd#*|}"
        out="$(pd_probe "$c" "$cmd")"
        verdict="${out%%$'\n'*}"
        CASES=$((CASES + 1))
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || fail prevent-destructive-commands.sh "${id}[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
    done
    for cmd in 'echo x > /tmp/out.txt' 'echo x > /tmp/d/out.txt' 'echo x > /dev/null' \
        'echo x >&2' 'ls 2>&1' 'ls 2>/dev/fd/2' 'echo x >/dev/stderr' 'echo x | tee /dev/stderr' \
        'sort < in.txt > /dev/stdout' 'pnpm test:run 2>&1 | tee /tmp/x.log' "echo x > $s/ok/out.txt"; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG70[$cmd]" pass "$out"
    done
    # CG71-CG79 (tmp-exemption revision 2, after review 1/3): every /tmp glob asks (R2), fd
    # bindings follow dup chains (R1), a /tmp write resolves physically for write verbs only and
    # asks on /proc, /dev or hard links (R3), any spelling of a link maker asks (R4); a link
    # removed, moved or re-pointed keeps its lexical target. CG60/CG70's `/tmp/*.log` now asks (R2).
    out="$(pd_probe "$c" 'echo x > /tmp/*.log')"
    g15_expect "CG60-R2" deny "$out"
    mkdir -p "$s/s2" "$s/s3" "$c/docs"
    : >"$c/docs/n.md"
    for id in a b c d; do ln -s "$c/docs/n.md" "$s/s2/$id.log"; done
    ln -s "$c/src/a.py" "$s/s2/z.log"
    ln -s "$c/src" "$s/s3/.h"
    ln -s /dev/stderr "$s/errl"
    ln -s "$c/.claude/settings.json" "$s/set.lnk"
    : >"$c/.claude/settings.json"
    local hard=0
    ln "$c/src/a.py" "$s/hard" 2>/dev/null && hard=1
    for id_cmd in "CG71|shopt -u globskipdots; echo x > /tmp/.[.]$c/src/a.py" \
        "CG71|shopt -u globskipdots; echo x > /tmp/.?$c/src/a.py" \
        "CG71|shopt -u globskipdots; echo x > /tmp/.*$c/src/a.py" \
        "CG72|echo x 3<$c/src/a.py 2>&3 >/dev/fd/2" \
        "CG72|exec 1<$c/.claude/settings.json 2>&1; echo x > /dev/stderr" \
        "CG72|exec 3<$c/.claude/settings.json; exec 1>&3; echo x > /dev/stdout" \
        "CG73|/bin/ln -s $c/src/a.py $s/l9 && echo x > $s/l9" \
        "CG73|'ln' -s $c/src/a.py $s/l9 && echo x > $s/l9" \
        "CG73|cp --sym $c/src/a.py $s/l9 && echo x > $s/l9" \
        "CG73|cp -a $s/x.log $s/l9 && echo x > $s/l9" \
        "CG74|echo x | tee $s/s2/*.log" \
        "CG75|echo x > $s/[^x]reB/a.py" \
        "CG75|shopt -s dotglob; echo x > $s/s3/*/a.py" \
        "CG76|exec 2<$c/.claude/settings.json; echo x > $s/errl"; do
        id="${id_cmd%%|*}"
        cmd="${id_cmd#*|}"
        out="$(pd_probe "$c" "$cmd")"
        verdict="${out%%$'\n'*}"
        CASES=$((CASES + 1))
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || fail prevent-destructive-commands.sh "${id}[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
    done
    if [[ "$hard" == 1 ]]; then
        out="$(pd_probe "$c" "echo x > $s/hard")"
        verdict="${out%%$'\n'*}"
        CASES=$((CASES + 1))
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || fail prevent-destructive-commands.sh "CG77" "expected ask or deny, got $verdict '${out:0:200}'"
    else
        printf 'skip CG77: /tmp and the fixture project are on different filesystems\n' >&2
    fi
    for cmd in "rm $s/set.lnk" "unlink $s/set.lnk" "mv $s/set.lnk $s/ok/" "ln -sfn $c/src/a.py $s/x2.log" \
        "awk '\$1<10' f > /dev/stdout" $'cp a /tmp/b\nls -l'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG78-79[$cmd]" pass "$out"
    done
    # CG80-CG82 (tmp-exemption revision 3, after review 2/3): find -exec through a /tmp link root,
    # /dev/stdin no longer exempt, a unit separator in a /tmp link name.
    ln -s "$c/.claude/settings.json" "$s/L"$'\x1f'
    for id_cmd in "CG80|find $s/preB/ -name '*.py' -exec sed -i s/x/y/ {} +" \
        "CG81|echo x a2<$c/src/a.py >/dev/stdin" "CG81|true&&<$c/src/a.py echo x >/dev/stdin" \
        "CG82|echo x > $s/L"$'\x1f'; do
        id="${id_cmd%%|*}"
        cmd="${id_cmd#*|}"
        out="$(pd_probe "$c" "$cmd")"
        verdict="${out%%$'\n'*}"
        CASES=$((CASES + 1))
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || fail prevent-destructive-commands.sh "${id}[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
    done
    # CG83 (review 3/3): a find root inside the project that links into /tmp is still guarded as
    # written (`.claude` -> a /tmp folder), not only on its physical side.
    mkdir -p "$tmp/p2" "$s/shc"
    : >"$s/shc/settings.json"
    ln -s "$s/shc" "$tmp/p2/.claude"
    for cmd in "cd $tmp/p2 && find .claude/ -exec /bin/rm {} +" "find $tmp/p2/.claude/ -exec unlink {} \\;"; do
        out="$(pd_probe "$tmp/p2" "$cmd")"
        verdict="${out%%$'\n'*}"
        CASES=$((CASES + 1))
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || fail prevent-destructive-commands.sh "CG83[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
    done
    rm -r "$s"
    rm -r "$tmp"
}

# tok_expect <id> <pass|ask|deny|block> <project> <cwd sub or ""> <command> [needle...]: one shell
# guard verdict; `block` accepts ask or deny.
tok_expect() {
    local id="$1" want="$2" dir="$3" sub="$4" cmd="$5" out verdict needle
    shift 5
    out="$(pd_probe "$dir" "$cmd" "$sub")"
    verdict="${out%%$'\n'*}"
    CASES=$((CASES + 1))
    if [[ "$want" == block ]]; then
        [[ "$verdict" == ask || "$verdict" == deny ]] \
            || { fail prevent-destructive-commands.sh "${id}[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"; return 0; }
    elif [[ "$verdict" != "$want" ]]; then
        fail prevent-destructive-commands.sh "${id}[$cmd]" "expected $want, got $verdict '${out:0:200}'"
        return 0
    fi
    for needle in "$@"; do
        [[ "$out" == *"$needle"* ]] || fail prevent-destructive-commands.sh "${id}[$cmd]" "reason lacks '$needle': '${out:0:300}'"
    done
    return 0
}

# CG84-CG119 (guard-tokenizer-fd-links): the /tmp and fd exemptions decided from tokenizer rows.
# $c is the project; $s holds /tmp links into it.
run_tokenizer_cases() {
    local tmp c s cmd u=https://example.invalid
    tmp="$(mktemp -d)"
    make_app_tree "$tmp/c" codegen
    c="$tmp/c"
    mkdir -p "$c/.claude/sub" "$c/.git" "$tmp/tb"
    printf 'x = 1\n' >"$c/src/a.py"
    printf '{}\n' >"$c/.claude/settings.json"
    printf '[core]\n' >"$c/.git/config"
    ln -s "$c/.claude/sub" "$c/docs/l"
    s="$(mktemp -d /tmp/cg-tok.XXXXXX)"
    ln -s "$c/src" "$s/srcl"
    ln -s "$c/package.json" "$s/pkg"
    ln -s "$c/.claude" "$s/cl"
    ln -s "$c/.claude/sub" "$s/clsub"
    ln -s "$c/.git" "$s/gl"
    ln -s "$c/src/a.py" "$s/x.log"
    ln -s "$c/src/a.py" "$s/x2.log"
    mkdir -p "$s/ok" "$s/d"
    : >"$s/ok/f"
    ln -s "$c/src/a.py" "$s/d/z.log"
    : >"$s/evil"
    ln -s "$c/src/a.py" "$tmp/tb/l"
    tar -cf "$s/t.tar" -C "$tmp/tb" l

    # Reproduction: each fails on 8e39637.
    tok_expect CG84 block "$c" "" "find $s/srcl/ -delete"
    tok_expect CG85 block "$c" "" "find . -fprint $s/pkg"
    for cmd in "shred $s/pkg" "chmod 600 $s/pkg" "touch $s/pkg"; do
        tok_expect CG86 block "$c" "" "$cmd"
    done
    for cmd in "curl --output $s/pkg $u" "pnpm vitest run --outputFile=$s/pkg"; do
        tok_expect CG87 block "$c" "" "$cmd"
    done
    for cmd in "mv $s/evil $s/c?/settings.json" "rm $s/c?/settings.json" "ln -sf $s/evil $s/c?/settings.json"; do
        tok_expect CG89 block "$c" "" "$cmd"
    done
    for cmd in "echo x a2<$c/src/a.py >/dev/fd/0" "true&&<$c/src/a.py echo x >/dev/fd/0" \
               "echo x 2>&1<$c/src/a.py >/dev/fd/0" "echo x >&2<$c/src/a.py >/dev/fd/0" \
               "echo \$<$c/src/a.py >/dev/fd/0"; do
        tok_expect CG90 block "$c" "" "$cmd"
    done
    for cmd in "l'n' -s $c/src/a.py $s/l && echo x > $s/l" "l\\n -s $c/src/a.py $s/l && echo x > $s/l" \
               "rsync -a $s/x.log $s/l && echo x > $s/l" "cp -r $s/d $s/e && echo x > $s/e/z.log" \
               "mv $s/x.log $s/l && echo x > $s/l" "tar -xf $s/t.tar -C $s && echo x > $s/l" \
               "\$(which ln) -s $c/src/a.py $s/l && echo x > $s/l"; do
        tok_expect CG91 block "$c" "" "$cmd"
    done
    for cmd in "cd -P $s/clsub/.. && echo x > settings.json" "cd -P docs/l/.. && echo x > settings.json"; do
        tok_expect CG92 block "$c" "" "$cmd"
    done
    for cmd in "curl -o $s/pkg $u" "curl -sSLo $s/pkg $u" "wget -O $s/pkg $u" \
               "wget --output-document=$s/pkg $u" "curl -o $c/package.json $u"; do
        tok_expect CG99 block "$c" "" "$cmd"
    done
    for cmd in "set -P; cd $s/clsub/.. && echo x > settings.json" \
               "set -o physical; cd $s/clsub/.. && echo x > settings.json" \
               "env -C $s/clsub/.. tee settings.json"; do
        tok_expect CG104 block "$c" "" "$cmd"
    done
    for cmd in "find -P $s/srcl/ -delete" "find -H $s/srcl -delete" "find -H $c/s''rc -delete"; do
        tok_expect CG107 block "$c" docs "$cmd"
    done
    tok_expect CG108 block "$c" "" "ln -s $c/.claude/hooks $s/D && ln -sf /tmp/x/f $s/D"
    tok_expect CG105 block "$c" "" "find $c/s''rc/ -delete"
    tok_expect CG103 block "$c" "" "cat 1 < $c/src/a.py > /dev/stdout"

    # Characterisation: already holds on 8e39637.
    for cmd in "rm $s/x.log" "unlink $s/x.log" "mv $s/x.log $s/ok/" "ln -sfn $c/src/a.py $s/x2.log" \
               "ln -sf /etc/hostname $s/x2.log" "ln -sfn /etc/hostname $s/srcl" "ln -s $c/src/a.py $s/l2" \
               "if true; then pnpm build > /tmp/o.txt; fi" $'cat <<EOF > /dev/stdout\nhi\nEOF' \
               "pnpm build > /tmp/out.txt 2>&1" "echo a > /tmp/a.txt; echo b > /tmp/b.txt" \
               "find $s/ok -name '*.log' -delete" "chmod 600 $s/ok/f" "touch $s/ok/f" \
               "cd $s/clsub/.. && echo x > $s/ok/f" "cd $c && pnpm build > /tmp/out.txt 2>&1" \
               "export X=1; echo x > /tmp/o.txt" "cat <<<hi > /dev/stdout" "exec 3>&1; echo x >/dev/stdout" \
               "sort < in.txt > /dev/stdout" "awk '\$1<10' f > /dev/stdout" \
               "pnpm test:run 2>&1 | tee /tmp/x.log" "ls /tmp && echo x > /tmp/out.txt" "echo x > docs/a.md"; do
        tok_expect CG93 pass "$c" "" "$cmd"
    done
    tok_expect CG94 deny "$c" "" "echo x > $s/x.log" "src/a.py written by a redirect"
    tok_expect CG94 ask "$c" "" "echo x | tee $s/pkg" "guarded path: package.json"
    for cmd in "truncate -s0 $s/pkg" "mv /tmp/f $s/srcl" "cd $s/cl && echo x > settings.json"; do
        tok_expect CG94 block "$c" "" "$cmd"
    done
    for cmd in "exec {fd}<$c/src/a.py; echo x > /dev/stdout" "echo x > /dev/stdin"; do
        tok_expect CG95 block "$c" "" "$cmd"
    done
    tok_expect CG100 block "$c" "" "ln -s $c/src/a.py $s/l3 && cp $s/evil $s/l3"
    for cmd in "pnpm exec ln -s $c/src/a.py $s/l4 && echo x > $s/l4" \
               "find . -maxdepth 0 -exec ln -s $c/src/a.py $s/l5 \\; && echo x > $s/l5" \
               "awk 'BEGIN{system(\"ln -s $c/src/a.py $s/l6\")}' && echo x > $s/l6" \
               "awk 'BEGIN{system(\"ln -s $c/src/a.py $s/l6\")}'; echo x > $s/l6"; do
        tok_expect CG101 block "$c" "" "$cmd"
    done
    for cmd in "ln -s $c/.claude $s/L && rm $s/L/settings.json" "ln -s $c/.claude $s/L && unlink $s/L/settings.json" \
               "ln -s $c/.claude $s/L && mv $s/L/settings.json /tmp/z" "ln -s $c/.git $s/G && rm $s/G/config"; do
        tok_expect CG106 block "$c" "" "$cmd"
    done
    tok_expect CG102 deny "$c" "" "cp $s/evil /tmp/b && rm $s/gl/config" ".git/config written by rm"
    tok_expect CG103 block "$c" "" "head -n 5 < $c/src/a.py > /dev/fd/0"
    tok_expect CG103 deny "$c" "" "cat 2< .env" "secret"

    # CG109-CG115 (review 1/3 fix batch). CG109: awk/sed link makers are read from the program text only.
    for cmd in "sed -n '1,20p' src/features/auth/services.ts > /tmp/snip.txt" \
               "sed 's/foo/bar/; s/old/new/' in.txt > /tmp/out.txt" \
               "awk '\$1==\"a\" || \$2==\"b\"' in.txt > /tmp/out.txt" \
               "awk '{print \$1}' logs/system.log > /tmp/out.txt"; do
        tok_expect CG109 pass "$c" "" "$cmd"
    done
    tok_expect CG109 block "$c" "" "sed -e 's/x/y/e' f > /tmp/out.txt"
    # CG110: the secret mode itself, with a spelling the raw-text scan misses.
    tok_expect CG110 deny "$c" "" "cat 2< .e''nv" "a secret file"
    # CG111: a Unicode digit is not an fd, and must not crash the tokenizer.
    tok_expect CG111 deny "$c" "" "cat ² < .e'n'v" "a secret file"
    tok_expect CG111 deny "$c" "" "echo x ²> /tmp/a; echo y > src/a.ts"
    # CG112: npm eats the first `--`; npx and pnpm forward it.
    for cmd in "npm exec foo -- --output package.json" "npm x foo -- --output package.json"; do
        tok_expect CG112 block "$c" "" "$cmd"
    done
    tok_expect CG112 pass "$c" "" "npx foo -- --output package.json"
    # CG113: a dlx package is an unknown program, not a lexical link maker.
    tok_expect CG113 block "$c" "" "pnpm dlx foo-gen && echo x > /tmp/out.txt"
    tok_expect CG113 pass "$c" "" "pnpm dlx foo-gen > /tmp/out.txt"
    # CG114: find -L and -follow walk through links under a root outside the project.
    tok_expect CG114 block "$c" "" "find -L $s -name '*.py' -delete"
    tok_expect CG114 block "$c" "" "find $s -follow -name '*.json' -delete"
    tok_expect CG114 pass "$c" "" "find -H $s -name '*.py' -delete"
    # CG115: a shell_targets.py of another guard API is not trusted.
    mkdir -p "$tmp/mix"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp/mix"/
    printf '#!/usr/bin/env python3\n# cwk-guard-api: 4\nprint("#end\\t0")\n' >"$tmp/mix/shell_targets.py"
    cmd="ln -s $c/.claude $s/M && rm $s/M/settings.json"
    CASES=$((CASES + 1))
    out="$(HOOKS_DIR="$tmp/mix" pd_probe "$c" "$cmd")"
    verdict="${out%%$'\n'*}"
    [[ "$verdict" == ask || "$verdict" == deny ]] \
        || fail prevent-destructive-commands.sh "CG115[$cmd]" "expected ask or deny with a guard API 4 resolver, got $verdict '${out:0:200}'"

    # CG116-CG119 (fix batch 2). CG116: everyday awk that writes to /tmp is not a link maker.
    for cmd in "ps aux | awk '/systemd/ {print \$2}' > /tmp/pids.txt" \
               "df -h | awk '\$1 != \"Filesystem\"' > /tmp/df.txt" \
               "awk '{print \"system ok\"}' f > /tmp/o" \
               "awk '{print \$1 \"|\" \$2}' f > /tmp/o" \
               "awk 'BEGIN{OFS=\"|\"} {print \$1,\$2}' f > /tmp/o.md" \
               "awk '{n=split(\$0,a,\"|\"); print n}' f > /tmp/o" \
               "awk -F'\t' '{print \"| \" \$1 \" | \" \$2 \" |\"}' data.tsv > /tmp/table.md" \
               "awk --assign 'x=a|system(' '{print x}' f > /tmp/o" \
               "awk -v 'x=a|b' '{print x}' f > /tmp/o" \
               "awk --field-separator '|' '{print \$1}' f > /tmp/o" \
               "awk '\$0 ~ /a|b/ {print}' f > /tmp/o"; do
        tok_expect CG116 pass "$c" "" "$cmd"
    done
    # CG117: a real awk link maker still asks: system, a literal or variable command on a pipe,
    # a coprocess, and a program file that cannot be read.
    for cmd in "awk 'BEGIN{system(\"ln -s x /tmp/l\")}' f > /tmp/o" \
               "awk 'BEGIN{system (\"id\")}' f > /tmp/o" \
               "awk '{print \"x\" | \"sh\"}' f > /tmp/o" \
               "awk 'BEGIN{\"date\" | getline d; print d}' > /tmp/o" \
               "awk -v c=sh '{print | c}' f > /tmp/o" \
               "awk -v c=date 'BEGIN{c | getline d}' > /tmp/o" \
               "awk '{print |& \"sh\"}' f > /tmp/o" \
               "awk -f prog.awk f > /tmp/o" \
               "awk --file=prog.awk f > /tmp/o" \
               "awk -f prog.awk logs/system.log > /tmp/o"; do
        tok_expect CG117 block "$c" "" "$cmd"
    done
    # CG118: sed is weighed by its own analysis: a backslashed delimiter or a file operand is no
    # command; an e command or flag, --expression and a script file still ask.
    tok_expect CG118 pass "$c" "" "sed 's/foo/\\/etc/' f && echo x > /tmp/o"
    tok_expect CG118 pass "$c" "" "sed -n '1,20p' src/x/services.ts > /tmp/s.txt"
    for cmd in "sed 's/x/y/e' f" "sed '1e cmd' f" "sed '\$e date' f" "sed '/x/e ln -s a b' f" \
               "sed --expression='1e id' f" "sed --expr='1e id' f" "sed -f mk.sed f" \
               "sed '1e id' f && echo x > /tmp/o" "sed -f mk.sed f > /tmp/o"; do
        tok_expect CG118 block "$c" "" "$cmd"
    done
    # CG119: find -L / -follow asks on a delete or a writing exec, not on a read-only exec, and
    # -follow counts only among find's own words.
    for cmd in "find -L $s -name x -exec grep -l foo {} \;" "find -L $s -name x -exec cat {} +" \
               "find $s -name x -exec grep -follow {} \;" "find $s -name x -follow -exec ls {} \;"; do
        tok_expect CG119 pass "$c" "" "$cmd"
    done
    for cmd in "find -L $s -name x -exec rm {} \;" "find -L $s -name x -exec cp {} /tmp/z \;" \
               "find $s -exec cat {} + -follow -delete"; do
        tok_expect CG119 block "$c" "" "$cmd"
    done

    # Business rules: the structural link rule.
    tok_expect CG96 block "$c" "" "frobnicate $s && echo x > /tmp/out.txt"
    tok_expect CG96 pass "$c" "" "grep -rn link src > /tmp/hits.txt"
    tok_expect CG96 pass "$c" "" "git diff > /tmp/x.diff"
    tok_expect CG96 block "$c" "" "git checkout x && echo y > /tmp/out.txt"
    tok_expect CG97 pass "$c" "" "cp --verbose a /tmp/b"
    tok_expect CG97 block "$c" "" "cp a /tmp/b && echo x > /tmp/b2"

    # Structure.
    CASES=$((CASES + 1))
    if grep -qE 'guard_fd_bound|guard_makes_link' "$HOOKS_DIR/prevent-destructive-commands.sh" \
        || [[ "$(grep -c '^guard_is_write_verb()' "$HOOKS_DIR/prevent-destructive-commands.sh")" != 1 ]] \
        || [[ "$(grep -c '^guard_classify_outside()' "$HOOKS_DIR/prevent-destructive-commands.sh")" != 1 ]] \
        || grep -q '"?tmp:' "$HOOKS_DIR/shell_targets.py" \
        || ! grep -qx '# cwk-guard-api: 6' "$HOOKS_DIR/shell_targets.py" \
        || ! grep -qx '# cwk-guard-api: 6' "$HOOKS_DIR/prevent-destructive-commands.sh"; then
        fail prevent-destructive-commands.sh CG98 "a raw-text fd/link helper, a ?tmp: row, a duplicated helper or guard API != 6"
    fi
    rm -r "$s"
    rm -r "$tmp"
}

# G10.04: a reason past 4000 characters is cut and says so.
run_git_reason_cut_case() {
    local tmp feat out reason i pad
    tmp="$(mktemp -d)"
    feat="$tmp/.feat"
    make_seed_repo "$tmp"
    git -C "$tmp" worktree add -q "$feat" -b feat/x
    pad="$(printf 'p%.0s' $(seq 1 240))"
    for i in $(seq 1 40); do
        : >"$feat/.env.$pad$i"
    done
    out="$(git_hook_probe "git add -A" "$feat" "$tmp")"
    g15_expect G10.04 deny "$out" "[reason truncated]"
    reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"${out#*$'\n'}")"
    [[ "$reason" == *"[reason truncated]" && "${#reason}" -le 4000 ]] \
        || fail enforce-git-workflow.sh G10.04 "reason of ${#reason} chars does not end in the truncation marker"
    rm -r "$tmp"
}

# L1: the whole-text scans run under LC_ALL=C. A UTF-8 locale picked from `locale -a`
# makes them quadratic on a long run of `git `/`gh ` words: the hook must still answer
# in under 2 s. ASCII calls get the same verdict in both locales.
run_locale_cases() {
    local loc tmp pad word start ms out_c out_u command id=0
    loc="$(locale -a 2>/dev/null | grep -iE 'utf-?8' | head -n 1 || true)"
    if [[ -z "$loc" ]]; then
        printf 'SKIP L1 locale cases: no UTF-8 locale installed\n'
        return 0
    fi
    tmp="$(mktemp -d)"
    make_seed_repo "$tmp/repo"
    git -C "$tmp/repo" switch -q -c feat/x
    for word in git gh; do
        id=$((id + 1))
        pad="$(printf "$word %.0s" $(seq 1 $((60000 / (${#word} + 1)))))"
        [[ "$word" == git ]] && command="$pad; commit" || command="$pad; comment"
        CASES=$((CASES + 1))
        start="$(date +%s%N)"
        LC_ALL="$loc" git_hook_probe "$command" "$tmp/repo" "$tmp" >/dev/null
        ms=$((($(date +%s%N) - start) / 1000000))
        [[ "$ms" -lt 2000 ]] || fail enforce-git-workflow.sh "L1.0$id" "60 KB of '$word ' took $ms ms under $loc"
    done
    for command in "git commit" "gh pr comment 1" "git status"; do
        id=$((id + 1))
        CASES=$((CASES + 1))
        out_c="$(LC_ALL=C git_hook_probe "$command" "$tmp/repo" "$tmp" | head -n 1)"
        out_u="$(LC_ALL="$loc" git_hook_probe "$command" "$tmp/repo" "$tmp" | head -n 1)"
        [[ "$out_c" == "$out_u" ]] \
            || fail enforce-git-workflow.sh "L1.0$id" "'$command': $out_c under C, $out_u under $loc"
    done
    rm -r "$tmp"
}

# Prints the verdict on its first line, then the hook's stdout and stderr.
shell_guard_probe() {
    local dir="$1" path_override="$2" command="$3" input tmp code verdict
    tmp="$(mktemp -d)"
    input="$(jq -cn --arg command "$command" --arg cwd "$PROJECT_ROOT" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}')"
    set +e
    printf '%s' "$input" | PATH="${path_override:-$PATH}" CLAUDE_PROJECT_DIR="$PROJECT_ROOT" \
        CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$dir/prevent-destructive-commands.sh" \
        >"$tmp/stdout" 2>"$tmp/stderr"
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" "$tmp/stdout")"
    printf '%s\n' "$verdict"
    cat "$tmp/stdout" "$tmp/stderr"
    rm -r "$tmp"
}

# X12: a missing or broken shell_targets.py is not a pass.
run_shell_guard_failure_cases() {
    local state tmp bin tool out verdict want reason command path_override i
    local -a commands=("sed -i 's/a/b/' package.json" "echo x > .github/workflows/ci.yml" "touch .claude/.tdd-red/m" "ls src")
    local -a wants=(ask ask deny pass)
    for state in renamed empty exit1 garbage nosentinel no-python3; do
        tmp="$(mktemp -d)"
        cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
        path_override=""
        case "$state" in
            renamed)    rm -f "$tmp/shell_targets.py" ;;
            empty)      : > "$tmp/shell_targets.py" ;;
            exit1)      printf 'import sys\nsys.exit(1)\n' > "$tmp/shell_targets.py" ;;
            garbage)    printf 'print("garbage")\n' > "$tmp/shell_targets.py" ;;
            nosentinel) printf 'print("rm\\tpackage.json")\n' > "$tmp/shell_targets.py" ;;
            no-python3)
                bin="$tmp/bin-no-python3"
                no_python_bin "$bin"
                path_override="$bin"
                ;;
        esac
        for i in 0 1 2 3; do
            command="${commands[$i]}"; want="${wants[$i]}"; reason=""
            [[ "$want" == pass ]] || reason="shell guard unavailable"
            CASES=$((CASES + 1))
            out="$(shell_guard_probe "$tmp" "$path_override" "$command")"
            verdict="${out%%$'\n'*}"
            if [[ "$verdict" != "$want" ]]; then
                fail prevent-destructive-commands.sh "resolver-$state: $command" "expected $want, got $verdict"
            elif [[ -n "$reason" && "$out" != *"$reason"* ]]; then
                fail prevent-destructive-commands.sh "resolver-$state: $command" "reason does not contain '$reason'"
            fi
        done
        rm -r "$tmp"
    done
}

# X14: a padded command stays far under the hook timeout, and the row cap keeps the deny.
run_shell_guard_budget_case() {
    local tmp operands start end elapsed_ms
    tmp="$(mktemp -d)"
    operands="$(printf 'f%d ' $(seq 1 500))"
    jq -cn --arg command "rm ${operands}package.json" --arg cwd "__PROJECT_ROOT__" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}' > "$tmp/X14.01-deny.json"
    operands="$(printf 'f%d ' $(seq 1 70))"
    jq -cn --arg command "rm ${operands}.claude/.tdd-red/m" --arg cwd "__PROJECT_ROOT__" --arg reason "is written only by tdd-prove-red.sh" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd, _expect_reason: $reason}' > "$tmp/X14.02-deny.json"
    run_case prevent-destructive-commands.sh "$tmp/X14.01-deny.json" deny
    start="$(date +%s%N)"
    sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" "$tmp/X14.01-deny.json" \
        | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
            "$HOOKS_DIR/prevent-destructive-commands.sh" >/dev/null 2>&1 || true
    end="$(date +%s%N)"
    elapsed_ms=$(((end - start) / 1000000))
    [[ "$elapsed_ms" -lt 2000 ]] \
        || fail prevent-destructive-commands.sh X14.01-deny.json "500-operand rm took ${elapsed_ms} ms, bound is 2000"
    run_case prevent-destructive-commands.sh "$tmp/X14.02-deny.json" deny
    rm -r "$tmp"
}

# X16: the hook runs on bash 3.2 constructs only (macOS /bin/bash): mapfile and
# readarray are disabled for the run, and the file holds none of the 4.x forms.
run_shell_guard_bash3_case() {
    local hook="$HOOKS_DIR/prevent-destructive-commands.sh" command input out code verdict banned
    for command in "echo x > package.json" "echo hi"; do
        input="$(jq -cn --arg command "$command" --arg cwd "$PROJECT_ROOT" \
            '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}')"
        CASES=$((CASES + 1))
        set +e
        out="$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
            bash -c 'enable -n mapfile readarray 2>/dev/null; . "$0"' "$hook" 2>&1)"
        code=$?
        set -e
        if [[ "$command" == "echo hi" ]]; then
            [[ "$code" -eq 0 && -z "$out" ]] \
                || fail prevent-destructive-commands.sh "bash3: $command" "expected exit 0 and no output, got $code '${out:0:120}'"
        else
            [[ "$out" == *"guarded path:"* && "$code" -eq 0 && "$out" == *'"permissionDecision"'*ask* ]] \
                || fail prevent-destructive-commands.sh "bash3: $command" "expected ask with 'guarded path:', got $code '${out:0:120}'"
        fi
    done
    for banned in 'mapfile' 'readarray' '[-1]' 'declare -A' 'local -A' 'local -n' 'declare -n'; do
        CASES=$((CASES + 1))
        if grep -qF -e "$banned" "$hook"; then
            fail prevent-destructive-commands.sh "bash3-static" "the hook holds '$banned', a bash 4+ construct"
        fi
    done
}

# X22: the resolver-failed deny must not carry the resolver-success deny text.
run_shell_guard_reason_split_case() {
    local tmp out verdict
    tmp="$(mktemp -d)"
    cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py "$tmp"/
    printf 'import sys\nsys.exit(1)\n' > "$tmp/shell_targets.py"
    CASES=$((CASES + 1))
    out="$(shell_guard_probe "$tmp" "" "touch .claude/.tdd-red/m")"
    verdict="${out%%$'\n'*}"
    if [[ "$verdict" != deny ]]; then
        fail prevent-destructive-commands.sh "reason-split" "expected deny, got $verdict"
    elif [[ "$out" != *"shell guard unavailable"* ]]; then
        fail prevent-destructive-commands.sh "reason-split" "reason does not contain 'shell guard unavailable'"
    elif [[ "$out" == *"is written only by tdd-prove-red.sh"* ]]; then
        fail prevent-destructive-commands.sh "reason-split" "reason holds the resolver-success deny text"
    fi
    rm -r "$tmp"
}

# X23: no .cwd and no CLAUDE_PROJECT_DIR (a manual run): the base is $PWD, not empty.
run_shell_guard_no_base_case() {
    local tmp out code
    tmp="$(mktemp -d)"
    CASES=$((CASES + 1))
    set +e
    out="$(cd "$tmp" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo x > app/api/routes.py"}}' \
        | env -u CLAUDE_PROJECT_DIR CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/prevent-destructive-commands.sh" 2>&1)"
    code=$?
    set -e
    [[ "$code" -eq 0 && "$out" == *'"ask"'* && "$out" == *"CLAUDE_PROJECT_DIR is not an absolute path"* ]] \
        || fail prevent-destructive-commands.sh "no-base" "expected exit 0 and an ask naming CLAUDE_PROJECT_DIR, got $code '${out:0:120}'"
    rm -r "$tmp"
}

# kb_setup <dir> <variant>: a tmp project for the kit-boundary cases (kit-boundary plan,
# step 1). `installed`: the stamp, the kit files a project holds; `installed-nostamp`:
# the same, no stamp; `kitlike`: install.sh + addons/, no stamp; `kitlike-stamp`: both
# markers and the stamp; `half-install`: install.sh, no addons/; `half-addons`: the reverse.
kb_setup() {
    local dir="$1" variant="$2"
    seed_project "$dir"
    mkdir -p "$dir/.claude/hooks" "$dir/.claude/scripts" "$dir/src"
    printf 'x\n' >"$dir/.claude/hooks/x"
    printf 'x\n' >"$dir/.claude/scripts/s.sh"
    printf 'x\n' >"$dir/workflow.sh"
    printf 'export const a = 1\n' >"$dir/src/a.ts"
    case "$variant" in
        installed) printf 'core\n' >"$dir/.claude/INSTALL_PROFILE" ;;
        installed-nostamp) ;;
        kitlike) printf 'x\n' >"$dir/install.sh"; mkdir -p "$dir/addons" ;;
        kitlike-stamp)
            printf 'x\n' >"$dir/install.sh"; mkdir -p "$dir/addons"
            printf 'core\n' >"$dir/.claude/INSTALL_PROFILE" ;;
        half-install) printf 'x\n' >"$dir/install.sh" ;;
        half-addons) mkdir -p "$dir/addons" ;;
    esac
}

# kb_expect <id> <want exit> <project or -unset- or a relative path> <function> [args…]:
# one hook-guarded.sh function call with CLAUDE_PROJECT_DIR set (or unset) as given.
kb_expect() {
    local id="$1" want="$2" project="$3" out code; shift 3
    CASES=$((CASES + 1))
    set +e
    if [[ "$project" == -unset- ]]; then
        out="$(env -u CLAUDE_PROJECT_DIR bash -c 'source "$1" || exit 99; shift; "$@"' _ "$HOOKS_DIR/hook-guarded.sh" "$@" 2>&1)"
    else
        out="$(CLAUDE_PROJECT_DIR="$project" bash -c 'source "$1" || exit 99; shift; "$@"' _ "$HOOKS_DIR/hook-guarded.sh" "$@" 2>&1)"
    fi
    code=$?
    set -e
    [[ "$code" -eq "$want" ]] || fail hook-guarded.sh "$id $*" "expected exit $want, got $code"
    [[ -z "$out" ]] || fail hook-guarded.sh "$id $*" "printed '$out'"
}

# KB1-KB9 (kit-boundary step 1): the installed check and the kit-code list.
run_kit_boundary_step1_cases() {
    local tmp v rel
    tmp="$(mktemp -d)"
    for v in installed installed-nostamp kitlike kitlike-stamp half-install half-addons; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
    done
    kb_expect KB1 0 "$tmp/installed" cwk_installed
    kb_expect KB2 1 "$tmp/kitlike" cwk_installed
    kb_expect KB2 1 "$PROJECT_ROOT" cwk_installed
    kb_expect KB3 0 "$tmp/installed-nostamp" cwk_installed
    kb_expect KB4 0 "$tmp/half-install" cwk_installed
    kb_expect KB4 0 "$tmp/half-addons" cwk_installed
    kb_expect KB5 0 "$tmp/kitlike-stamp" cwk_installed
    kb_expect KB6 0 -unset- cwk_installed
    kb_expect KB6 0 "relative/dir" cwk_installed
    for rel in .claude/hooks/x .claude/hooks/fixtures/a/b.json .claude/scripts/s.sh \
               workflow.py workflow.sh codex-handoff.sh install.sh \
               addons addons/fastapi/hooks/x.py \
               .claude/project.json .claude/project.snapshot.json .claude/INSTALL_PROFILE; do
        kb_expect KB7 0 "$PROJECT_ROOT" cwk_is_kit_code "$rel"
    done
    for rel in .claude/settings.json .claude/.tdd-unfrozen .claude/.size-exempt \
               src/a.ts docs/install.sh.md .claude/hooksx \
               . .claude .claude/kit-backup/t/.claude/hooks/x; do
        kb_expect KB8 1 "$PROJECT_ROOT" cwk_is_kit_code "$rel"
    done
    kb_expect KB9 0 "$PROJECT_ROOT" cwk_is_kit_code .claude --reach
    kb_expect KB9 1 "$PROJECT_ROOT" cwk_is_kit_code . --reach
    kb_expect KB9 1 "$PROJECT_ROOT" cwk_is_kit_code src --reach
    rm -r "$tmp"
}

# kb_verdict <id> <want verdict> <label> <probe output> [reason substring]: the first line
# of a project_hook_probe output is the verdict, the rest the hook's JSON.
kb_verdict() {
    local id="$1" want="$2" label="$3" out="$4" needle="${5:-}" verdict
    CASES=$((CASES + 1))
    verdict="${out%%$'\n'*}"
    [[ "$verdict" == "$want" ]] || fail kit-boundary "$id $label" "expected $want, got $verdict: ${out:0:300}"
    [[ -z "$needle" || "$out" == *"$needle"* ]] || fail kit-boundary "$id $label" "reason lacks '$needle'"
}

# kb_pf <id> <want> <project> <tool> <rel> [reason substring]: a Write/Edit through protect-files.sh.
kb_pf() {
    kb_verdict "$1" "$2" "$4 $5 in ${3##*/}" "$(pf_probe "$3" "$4" "$5")" "${6:-}"
}

# KB10-KB15 (kit-boundary step 2): Write/Edit of kit code in an installed project.
run_kit_boundary_step2_cases() {
    local tmp v deny_text='kit code changes in the LoopKit repo, then `install.sh`'
    tmp="$(mktemp -d)"
    for v in installed installed-nostamp kitlike half-install; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
    done
    kb_pf KB10 deny "$tmp/installed" Write .claude/hooks/x "$deny_text"
    kb_pf KB11 deny "$tmp/installed" Edit .claude/project.json
    kb_pf KB11 deny "$tmp/installed" Write .claude/scripts/s.sh
    kb_pf KB11 deny "$tmp/installed" Write workflow.sh
    kb_pf KB11 deny "$tmp/installed" Write codex-handoff.sh
    kb_pf KB11 deny "$tmp/installed" Write install.sh
    kb_pf KB11 deny "$tmp/installed" Write addons/fastapi/hooks/x.py
    kb_pf KB11 deny "$tmp/installed" Write .claude/INSTALL_PROFILE
    ln -s .claude/hooks/x "$tmp/installed/a"
    ln -s install.sh "$tmp/installed/b"
    kb_pf KB12 deny "$tmp/installed" Write a
    kb_pf KB12 deny "$tmp/installed" Write b
    mkdir -p "$tmp/installed/.claude"
    printf '{}\n' >"$tmp/installed/.claude/settings.json"
    kb_pf KB13 ask "$tmp/installed" Edit .claude/settings.json
    kb_pf KB13 ask "$tmp/installed" Write .claude/.tdd-unfrozen
    kb_pf KB13 pass "$tmp/installed" Write src/a.ts
    kb_pf KB13 deny "$tmp/installed" Write .claude/project.snapshot.json
    ln -s .claude/hooks/x "$tmp/kitlike/a"
    kb_pf KB14 ask "$tmp/kitlike" Write .claude/hooks/x
    kb_pf KB14 pass "$tmp/kitlike" Write .claude/INSTALL_PROFILE
    kb_pf KB14 pass "$tmp/kitlike" Write a
    for v in installed installed-nostamp half-install; do
        kb_pf KB15 deny "$tmp/$v" Write .claude/worktrees/w/.claude/hooks/x
    done
    rm -r "$tmp"
}

# kb_pd <id> <want> <project> <command> [reason substring] [sub cwd]: a command through the shell guard.
kb_pd() {
    kb_verdict "$1" "$2" "'$4' in ${3##*/}" "$(pd_probe "$3" "$4" "${6:-}")" "${5:-}"
}

# KB16-KB21 (kit-boundary step 3): shell writes to kit code, and running the kit-apply script.
run_kit_boundary_step3_cases() {
    local tmp v c out deny_text='kit code changes in the LoopKit repo, then `install.sh`'
    tmp="$(mktemp -d)"
    for v in installed kitlike; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
        printf '#!/usr/bin/env bash\n' >"$tmp/$v/.claude/scripts/kit-apply.sh"
        ln -s .claude/scripts/kit-apply.sh "$tmp/$v/r"
    done
    for c in 'echo x > .claude/hooks/x' 'sed -i s/a/b/ .claude/scripts/s.sh' 'printf x | tee workflow.sh' \
             'rm -r .claude/hooks' 'mv .claude/hooks/x /tmp/y' 'ln -s /tmp/x install.sh' 'mkdir addons' \
             'cp /tmp/k/install.sh .' 'cp -r /tmp/k/addons .' 'cp -r /tmp/k/.claude .' \
             'echo x > .claude/INSTALL_PROFILE' 'cp /tmp/a .claude/INSTALL_PROFILE'; do
        kb_pd KB16 deny "$tmp/installed" "$c" "$deny_text"
    done
    ln -s .claude/hooks/x "$tmp/installed/a"
    ln -s .claude/hooks "$tmp/installed/d"
    ln -s install.sh "$tmp/installed/b"
    kb_pd KB17 deny "$tmp/installed" 'echo x >> a' "$deny_text"
    kb_pd KB17 deny "$tmp/installed" 'echo x > d/y' "$deny_text"
    kb_pd KB17 deny "$tmp/installed" 'echo x > b' "$deny_text"
    kb_pd KB18 ask "$tmp/installed" 'cp /tmp/notes.txt .'
    kb_pd KB18 pass "$tmp/installed" 'echo x > docs/a.md'
    for c in 'echo x > .claude/hooks/x' 'ln -s x install.sh'; do
        out="$(pd_probe "$tmp/kitlike" "$c")"
        kb_verdict KB19 ask "'$c' in kitlike" "$out" 'guarded path:'
        CASES=$((CASES + 1))
        [[ "$out" != *'kit code:'* ]] || fail kit-boundary "KB19 '$c' in kitlike" "reason holds 'kit code:'"
    done
    kb_pd KB19 pass "$tmp/kitlike" 'echo x > .claude/INSTALL_PROFILE'
    kb_pd KB19 pass "$tmp/kitlike" 'cp /tmp/a .claude/INSTALL_PROFILE'
    ln -s .claude/hooks/x "$tmp/kitlike/a"
    kb_pd KB19 pass "$tmp/kitlike" 'echo x >> a'
    for v in installed kitlike; do
        for c in 'bash .claude/scripts/kit-apply.sh' './.claude/scripts/kit-apply.sh' \
                 'sh .claude/scripts/kit-apply.sh x.json' "$tmp/$v/.claude/scripts/kit-apply.sh" \
                 './r' 'source .claude/scripts/kit-apply.sh' "bash -c '.claude/scripts/kit-apply.sh'" \
                 'env X=1 .claude/scripts/kit-apply.sh'; do
            kb_pd KB20 deny "$tmp/$v" "$c"
        done
        kb_pd KB20 deny "$tmp/$v" './kit-apply.sh' '' .claude/scripts
        kb_pd KB20 deny "$tmp/$v" 'cd .claude/scripts && ./kit-apply.sh'
        kb_pd KB21 pass "$tmp/$v" 'cat .claude/scripts/kit-apply.sh'
        kb_pd KB21 pass "$tmp/$v" 'grep x .claude/scripts/kit-apply.sh'
    done
    rm -r "$tmp"
}

# kb_repo <dir> <installed|kitlike>: main holds src/a.ts, .claude/hooks/x, workflow.sh and the
# project.json over two commits; `k` changes the hook, `s` only src/a.ts; the tree sits on
# feat/x. `installed` adds the untracked stamp, `kitlike` an untracked install.sh and addons/.
kb_repo() {
    local r="$1" variant="$2"
    git init -q -b main "$r"
    git -C "$r" config user.email fixture@loopkit.invalid
    git -C "$r" config user.name Fixture
    mkdir -p "$r/src" "$r/.claude/hooks" "$r/sub"
    printf 'a\n' >"$r/src/a.ts"
    printf 'x\n' >"$r/.claude/hooks/x"
    printf 'x\n' >"$r/workflow.sh"
    seed_project "$r"
    git -C "$r" add src/a.ts .claude/hooks/x workflow.sh .claude/project.json
    git -C "$r" commit -q -m seed
    printf 'a2\n' >"$r/src/a.ts"
    git -C "$r" commit -q -am two
    git -C "$r" switch -q -c k
    printf 'k\n' >"$r/.claude/hooks/x"
    git -C "$r" commit -q -am k
    git -C "$r" switch -q -c s main
    printf 's\n' >"$r/src/a.ts"
    git -C "$r" commit -q -am s
    git -C "$r" switch -q -c feat/x main
    git -C "$r" diff main k >"$r/p.patch"
    cp "$r/p.patch" "$r/sub/s.patch"
    printf -- '--- a/workflow.sh\n+++ b/workflow.sh\n@@ -1 +1 @@\n-x\n+y\n' >"$r/p.diff"
    printf -- '--- .claude/hooks/x\n+++ .claude/hooks/x\n@@ -1 +1 @@\n-x\n+y\n' >"$r/q.patch"
    printf -- 'diff --git a/hooks/x b/hooks/x\n--- a/hooks/x\n+++ b/hooks/x\n@@ -1 +1 @@\n-x\n+y\n' >"$r/r.patch"
    printf 'not a patch\n@@ garbage\n' >"$r/c.patch"
    git -C "$r" format-patch -q -1 k --stdout >"$r/m.mbox"
    git -C "$r" format-patch -q -1 s --stdout >"$r/n.mbox"
    printf 'b\n' >"$r/b"
    printf 'o\n' >"$r/o"
    case "$variant" in
        installed) printf 'core\n' >"$r/.claude/INSTALL_PROFILE" ;;
        kitlike) printf 'x\n' >"$r/install.sh"; mkdir -p "$r/addons"; printf 'x\n' >"$r/addons/a" ;;
    esac
}

# kb_git <id> <want> <repo> <command> [reason substring]: the git hook on <command> in <repo>.
kb_git() {
    kb_verdict "$1" "$2" "'$4' in ${3##*/}" "$(git_hook_probe "$4" "$3" "$3")" "${5:-}"
}

# kb_git_nokit <id> <repo> <command>: today's verdict, whatever it is: no deny and no kit reason.
kb_git_nokit() {
    local out
    out="$(git_hook_probe "$3" "$2" "$2")"
    CASES=$((CASES + 1))
    if [[ "${out%%$'\n'*}" == deny || "$out" == *'kit code'* || "$out" == *'brings kit changes'* \
          || "$out" == *'kit changes before the fetch'* ]]; then
        fail kit-boundary "$1 '$3' in ${2##*/}" "expected today's verdict, got: ${out:0:200}"
    fi
}

# G19.001-G19.034 (kit-boundary step 4): git writers and kit-bringing calls.
run_kit_boundary_step4_cases() {
    local tmp r c v kit='kit code changes in the LoopKit repo' brings='brings kit changes: .claude/hooks/x'
    tmp="$(mktemp -d)"
    for v in installed kitlike; do kb_repo "$tmp/$v" "$v"; done
    r="$tmp/installed"
    kb_git G19.001 deny "$r" 'git apply p.patch' "$kit"
    kb_git G19.002 deny "$r" 'git apply p.diff' "$kit"
    kb_git G19.003 deny "$r" 'git apply -p0 q.patch' "$kit"
    kb_git G19.003 pass "$r" 'git apply -p2 q.patch'
    kb_git G19.004 deny "$r" 'git apply --directory=.claude r.patch' "$kit"
    kb_git G19.005 deny "$r" 'git -C .claude apply ../p.patch' "$kit"
    kb_git G19.005 pass "$r" 'git -C sub apply s.patch'
    kb_git G19.006 deny "$r" 'git apply --cached p.patch' "$kit"
    kb_git G19.006 deny "$r" 'git apply --index p.patch' "$kit"
    kb_git G19.007 deny "$r" 'git am m.mbox' "$kit"
    kb_git G19.007 pass "$r" 'git am n.mbox'
    for c in 'git apply' 'git apply < p.patch' 'cat p.patch | git apply' 'git apply missing.patch'; do
        kb_git G19.008 ask "$r" "$c"
    done
    for c in 'git checkout -- .claude/hooks/x' 'git checkout HEAD~1 -- .claude/hooks/x' \
             'git restore .claude/hooks/x' 'git restore --source=HEAD~1 workflow.sh' \
             'git restore --staged .claude/project.json'; do
        kb_git G19.009 deny "$r" "$c" "$kit"
    done
    for c in 'git rm .claude/hooks/x' 'git rm -r .claude' 'git rm --cached workflow.sh' \
             "git rm ':(glob)**/x'" 'git -C .claude rm -r hooks'; do
        kb_git G19.011 deny "$r" "$c" "$kit"
    done
    kb_git_nokit G19.011 "$r" 'git rm src/a.ts'
    for c in 'git mv .claude/hooks/x a' 'git mv src/a.ts .claude/hooks/y' 'git mv src/a.ts .claude/hooks' \
             'git -C .claude mv hooks/x ../a'; do
        kb_git G19.012 deny "$r" "$c" "$kit"
    done
    kb_git G19.012 pass "$r" 'git mv src/a.ts src/b.ts'
    kb_git G19.014 deny "$r" 'git merge-file .claude/hooks/x b o' "$kit"
    kb_git G19.014 pass "$r" 'git merge-file -p .claude/hooks/x b o'
    kb_git G19.015 deny "$r" 'git checkout-index -a' "$kit"
    kb_git G19.015 deny "$r" 'git checkout-index -- .claude/hooks/x' "$kit"
    kb_git G19.015 ask "$r" 'git checkout-index --stdin'
    kb_git G19.015 pass "$r" 'git checkout-index -- src/a.ts'
    kb_git G19.016 deny "$r" 'git read-tree -u -m HEAD k' "$kit"
    kb_git G19.016 deny "$r" 'git read-tree k' "$kit"
    kb_git G19.016 pass "$r" 'git read-tree -u -m HEAD s'
    kb_git G19.017 deny "$r" 'git reset --keep k' "$kit"
    kb_git G19.017 deny "$r" 'git reset --merge k' "$kit"
    kb_git G19.017 pass "$r" 'git reset --keep s'
    kb_git G19.018 deny "$r" 'git reset -- .claude/hooks/x' "$kit"
    kb_git G19.018 deny "$r" 'git update-index --chmod=+x .claude/hooks/x' "$kit"
    kb_git G19.018 ask "$r" 'git update-index --stdin'
    kb_git G19.018 pass "$r" 'git update-index --refresh'
    kb_git G19.020 ask "$r" 'git switch k' "$brings"
    kb_git G19.021 ask "$r" 'git checkout k' "$brings"
    kb_git G19.021 pass "$r" 'git checkout s'
    kb_git G19.022 ask "$r" 'git merge k' "$brings"
    kb_git G19.023 ask "$r" 'git pull' 'cannot read the kit changes before the fetch'
    kb_git G19.023 ask "$r" 'git pull origin main' 'cannot read the kit changes before the fetch'
    kb_git G19.024 ask "$r" 'git rebase k' "$brings"
    kb_git_nokit G19.024 "$r" 'git rebase s'
    kb_git G19.024 ask "$r" 'git rebase'
    kb_git G19.026 ask "$r" 'git reset k' "$brings"
    kb_git G19.026 ask "$r" 'git reset --hard k' 'git reset --hard discards'
    kb_git G19.026 ask "$r" 'git reset --hard k' "$brings"
    for c in 'git bisect start' 'git sparse-checkout set src' 'git submodule update' 'git filter-branch --tree-filter true HEAD'; do
        kb_git G19.027 ask "$r" "$c"
        kb_git_nokit G19.027 "$tmp/kitlike" "$c"
    done
    for c in 'git add .claude/hooks/x' 'git commit -m x' 'git worktree add ../w'; do
        kb_git_nokit G19.028 "$r" "$c"
    done
    kb_git G19.029 ask "$r" 'git -C "$x" apply p.patch'
    kb_git G19.029 ask "$r" 'git apply c.patch'
    for c in 'git apply p.patch' 'git checkout -- .claude/hooks/x' 'git rm .claude/hooks/x' 'git mv .claude/hooks/x a' \
             'git merge-file .claude/hooks/x b o' 'git switch k' 'git checkout k' 'git merge k' 'git pull'; do
        kb_git_nokit G19.030 "$tmp/kitlike" "$c"
    done
    for c in 'git checkout nosuch' 'git stash pop stash@{9}' 'git cherry-pick deadbeef'; do
        kb_git_nokit G19.031 "$r" "$c"
    done

    # G19.025: cherry-pick/revert per commit, a range, a merge with -m, a root commit.
    git -C "$r" switch -q -c c main
    printf 'c\n' >"$r/workflow.sh"
    git -C "$r" commit -q -am c
    git -C "$r" switch -q -c d main
    printf 'd\n' >"$r/src/a.ts"
    git -C "$r" commit -q -am d
    git -C "$r" switch -q -c mb main
    git -C "$r" merge -q --no-ff -m m k
    git -C "$r" switch -q --orphan rt
    printf 'r\n' >"$r/workflow.sh"
    git -C "$r" add workflow.sh
    git -C "$r" commit -q -m root
    git -C "$r" switch -q -f feat/x
    kb_git G19.025 ask "$r" 'git cherry-pick c' 'workflow.sh'
    kb_git G19.025 ask "$r" 'git revert c' 'workflow.sh'
    kb_git G19.025 pass "$r" 'git cherry-pick d'
    kb_git G19.025 ask "$r" 'git cherry-pick main..c' 'workflow.sh'
    kb_git G19.025 ask "$r" 'git revert -m 1 mb' "$brings"
    kb_git G19.025 ask "$r" 'git cherry-pick -m 1 mb' "$brings"
    kb_git G19.025 ask "$r" 'git revert mb'
    kb_git G19.025 ask "$r" 'git cherry-pick rt' 'workflow.sh'

    # G19.022: only HEAD's side changed the hook since the base: the three-dot set is empty.
    git -C "$r" switch -q -c h main
    printf 'h\n' >"$r/src/a.ts"
    git -C "$r" commit -q -am h
    git -C "$r" switch -q -c feat/y main
    printf 'y\n' >"$r/.claude/hooks/x"
    git -C "$r" commit -q -am y
    kb_git_nokit G19.022 "$r" 'git merge h'
    git -C "$r" switch -q feat/x

    # G19.010, G19.019, G19.034: the hook modified in the work tree.
    printf 'mod\n' >"$r/.claude/hooks/x"
    for c in 'git checkout -- .claude/hooks/x' 'git checkout -- .claude' 'git restore .' "git restore ':(glob).claude/**'"; do
        kb_git G19.010 deny "$r" "$c" "$kit"
    done
    for c in 'git stash' 'git stash push' 'git stash save x' 'git stash push -- .claude'; do
        kb_git G19.019 deny "$r" "$c" "$kit"
    done
    kb_git_nokit G19.030 "$tmp/kitlike" 'git stash'
    for c in 'git checkout -f' 'git checkout -f feat/x' 'git checkout --force feat/x' 'git switch --discard-changes feat/x'; do
        kb_git G19.034 deny "$r" "$c" "$kit"
    done
    git -C "$r" stash -q
    kb_git G19.013 deny "$r" 'git stash pop' "$kit"
    kb_git G19.013 deny "$r" 'git stash apply stash@{0}' "$kit"
    kb_git G19.019 deny "$r" 'git stash branch b' "$kit"
    git -C "$r" stash drop -q

    # Only src/a.ts modified: today's verdicts.
    printf 'mod\n' >"$r/src/a.ts"
    kb_git G19.010 ask "$r" 'git restore .'
    kb_git_nokit G19.019 "$r" 'git stash'
    kb_git_nokit G19.028 "$r" 'git stash push'
    for c in 'git checkout -f' 'git checkout -f feat/x' 'git switch --discard-changes feat/x'; do
        kb_git G19.034 ask "$r" "$c" 'discards local changes'
    done
    git -C "$r" stash -q
    kb_git G19.013 pass "$r" 'git stash pop'
    git -C "$r" stash drop -q

    # G19.013, G19.019: an untracked install.sh.
    printf 'x\n' >"$r/install.sh"
    kb_git G19.019 deny "$r" 'git stash -u' "$kit"
    kb_git G19.019 deny "$r" 'git stash push -a' "$kit"
    git -C "$r" stash -q -u
    kb_git G19.013 deny "$r" 'git stash pop' "$kit"
    kb_git G19.013 deny "$r" 'git -C src stash pop' "$kit"
    git -C "$r" stash drop -q

    # G19.032: an untrusted git dir runs nothing from its config.
    git init -q -b main --separate-git-dir "$tmp/sep.git" "$tmp/work"
    git -C "$tmp/work" config user.email fixture@loopkit.invalid
    git -C "$tmp/work" config user.name Fixture
    mkdir -p "$tmp/work/.claude/hooks"
    printf 'x\n' >"$tmp/work/.claude/hooks/x"
    git -C "$tmp/work" add .claude/hooks/x
    git -C "$tmp/work" commit -q -m seed
    git -C "$tmp/work" switch -q -c feat/x
    printf 'core\n' >"$tmp/work/.claude/INSTALL_PROFILE"
    printf 'mod\n' >"$tmp/work/.claude/hooks/x"
    git -C "$tmp/work" config core.fsmonitor "touch $tmp/MARKER"
    kb_git G19.032 ask "$tmp/work" 'git checkout -- .claude/hooks/x'
    CASES=$((CASES + 1))
    [[ ! -e "$tmp/MARKER" ]] || fail kit-boundary G19.032 "the repository's own config ran inside the hook"

    # G19.033: a branch that exists only as a remote-tracking ref.
    git clone -q "$tmp/kitlike" "$tmp/down" 2>/dev/null
    git -C "$tmp/down" config user.email fixture@loopkit.invalid
    git -C "$tmp/down" config user.name Fixture
    git -C "$tmp/down" switch -q -c feat/z
    printf 'core\n' >"$tmp/down/.claude/INSTALL_PROFILE"
    kb_git G19.033 ask "$tmp/down" 'git checkout k' "$brings"
    kb_git G19.033 ask "$tmp/down" 'git switch k' "$brings"
    kb_git_nokit G19.033 "$tmp/down" 'git checkout nosuch'
    git -C "$tmp/down" remote add up "$tmp/kitlike"
    git -C "$tmp/down" fetch -q up 2>/dev/null
    kb_git G19.033 ask "$tmp/down" 'git checkout k'

    # G19.030: the kit repo keeps today's verdicts.
    r="$tmp/kitlike"
    for c in 'git apply p.patch' 'git restore .claude/hooks/x' "git rm -r .claude" 'git mv .claude/hooks/x a' \
             'git merge-file .claude/hooks/x b o' 'git checkout k' 'git switch k' 'git merge k'; do
        kb_git_nokit G19.030 "$r" "$c"
    done
    printf 'mod\n' >"$r/.claude/hooks/x"
    git -C "$r" stash -q
    kb_git_nokit G19.030 "$r" 'git stash pop'
    rm -r "$tmp"
}

# kb_nokit_pd <id> <project> <command>: the shell guard's verdict holds no kit-code deny.
kb_nokit_pd() {
    local out
    out="$(pd_probe "$2" "$3")"
    CASES=$((CASES + 1))
    if [[ "$out" == *'kit code:'* || "$out" == *'kit-apply.sh'* ]]; then
        fail kit-boundary "$1 '$3' in ${2##*/}" "expected today's verdict, got: ${out:0:200}"
    fi
}

# KB22-KB25, KB12 (review round 1): an unresolved spelling of the kit-apply run, a write through
# a kit folder or a glob, a Write through a link outside the project.
run_kit_boundary_review1_cases() {
    local tmp v c out deny_text='kit code changes in the LoopKit repo, then `install.sh`'
    tmp="$(mktemp -d)"
    for v in installed kitlike; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
        printf '#!/usr/bin/env bash\n' >"$tmp/$v/.claude/scripts/kit-apply.sh"
    done
    mkdir -p "$tmp/srck/.claude/hooks" "$tmp/benign/docs"
    printf 'x\n' >"$tmp/srck/.claude/hooks/x"
    printf 'x\n' >"$tmp/benign/docs/a.md"
    for v in installed kitlike; do
        for c in 'bash "$CLAUDE_PROJECT_DIR"/.claude/scripts/kit-apply.sh' 'bash "${CLAUDE_PROJECT_DIR}/.claude/scripts/kit-apply.sh"' \
                 'bash $(pwd)/.claude/scripts/kit-apply.sh' 'bash $PWD/.claude/scripts/kit-apply.sh'; do
            kb_pd KB22 deny "$tmp/$v" "$c" 'kit-apply.sh'
        done
        for c in 'bash .claude/scripts/kit-appl*' 'bash < .claude/scripts/kit-apply.sh'; do
            kb_pd KB22 deny "$tmp/$v" "$c" 'unresolved write target'
        done
        kb_pd KB22 deny "$tmp/$v" 'cat .claude/scripts/kit-apply.sh | bash' 'kit-apply.sh'
        kb_pd KB22 pass "$tmp/$v" 'cat .claude/scripts/kit-appl*'
    done
    for c in 'sed -i s/a/b/ .claude/hooks/*.sh' 'perl -pi -e 1 .claude/scripts/*' 'cp -R /tmp/kb-missing/. .claude/hooks/' \
             'rsync -a /tmp/kb-missing/ .claude/' 'find .claude/hooks -type f -exec sed -i s/a/b/ {} +' \
             'cp -R /tmp/kb-missing/. .' "cp -R $tmp/srck/. ."; do
        kb_pd KB23 deny "$tmp/installed" "$c" "$deny_text"
        kb_nokit_pd KB23 "$tmp/kitlike" "$c"
    done
    kb_nokit_pd KB23 "$tmp/installed" "cp -R $tmp/benign/. ."
    kb_nokit_pd KB23 "$tmp/installed" 'cp /tmp/notes.txt .claude/notes.txt'
    ln -s "$tmp/installed/.claude/hooks/x" "$tmp/outlink"
    ln -s "$tmp/kitlike/.claude/hooks/x" "$tmp/outlink-kit"
    printf 'x\n' >"$tmp/plain.txt"
    kb_pf KB24 deny "$tmp/installed" Write ../outlink "$deny_text"
    kb_pf KB24 deny "$tmp/installed" Edit ../outlink "$deny_text"
    kb_pf KB24 pass "$tmp/installed" Write ../plain.txt
    kb_pf KB24 pass "$tmp/installed" Write ../outlink-kit
    kb_pf KB24 pass "$tmp/kitlike" Write ../outlink-kit
    rm -r "$tmp"
}

# G19.035-G19.038 (review round 1): an absolute operand under the root, a rebase branch or --onto
# target, `-` as the previous branch, and the bash floor.
run_kit_boundary_review1_git_cases() {
    local tmp r c v kit='kit code changes in the LoopKit repo' brings='brings kit changes: .claude/hooks/x'
    tmp="$(mktemp -d)"
    for v in installed kitlike prev prev2; do kb_repo "$tmp/$v" "$([[ $v == kitlike ]] && echo kitlike || echo installed)"; done
    git -C "$tmp/prev" switch -q k
    git -C "$tmp/prev" switch -q feat/x
    r="$tmp/installed"
    for c in "git mv $r/.claude/hooks/x a" "git mv src/a.ts $r/.claude/hooks/y" "git merge-file $r/.claude/hooks/x b o" \
             "git checkout-index -f -- $r/.claude/hooks/x" "git update-index --chmod=+x $r/.claude/hooks/x" \
             "git reset -- $r/.claude/hooks/x"; do
        kb_git G19.035 deny "$r" "$c" "$kit"
        kb_git_nokit G19.035 "$tmp/kitlike" "${c//$r/$tmp/kitlike}"
    done
    kb_git G19.035 pass "$r" "git mv $r/src/a.ts $r/src/b.ts"
    kb_git G19.036 ask "$r" 'git rebase main k' "$brings"
    kb_git G19.036 ask "$r" 'git rebase --onto k main' "$brings"
    kb_git G19.036 ask "$r" 'git rebase --onto=k main' "$brings"
    kb_git_nokit G19.036 "$r" 'git rebase main s'
    kb_git_nokit G19.036 "$r" 'git rebase --onto s main'
    for c in 'git checkout -' 'git switch -' 'git merge -' 'git rebase -' 'git cherry-pick -'; do
        kb_git G19.037 ask "$tmp/prev" "$c" "$brings"
        kb_git_nokit G19.037 "$tmp/prev2" "$c"
    done
    mkdir -p "$tmp/fp/bin"
    printf '#!/usr/bin/env bash\n[ "$1" = -I ] && [ "$#" -gt 3 ] && exit 1\nexec %s "$@"\n' "$(command -v python3)" >"$tmp/fp/bin/python3"
    chmod +x "$tmp/fp/bin/python3"
    out="$(PATH="$tmp/fp/bin:$PATH" git_hook_probe 'git restore .claude/hooks/x' "$r" "$r")"
    kb_verdict G19.038 ask 'floor: git restore in installed' "$out" 'may write kit code'
    out="$(PATH="$tmp/fp/bin:$PATH" git_hook_probe 'git restore .claude/hooks/x' "$tmp/kitlike" "$tmp/kitlike")"
    CASES=$((CASES + 1))
    [[ "$out" != *'may write kit code'* ]] || fail kit-boundary G19.038 "floor: the kit repo got a kit-code reason: ${out:0:200}"
    rm -r "$tmp"
}

# KB25 (review round 2, R2-N1): a contents copy from a big folder is one folder row, not one row
# per entry, so it neither collapses to an unknown ask nor hides the kit target.
run_kit_boundary_review2_shell_cases() {
    local tmp v i deny_text='kit code changes in the LoopKit repo, then `install.sh`'
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/big70"
    for i in $(seq 70); do printf 'x\n' >"$tmp/big70/f$i"; done
    for v in installed kitlike; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
        mkdir -p "$tmp/$v/dist"
        kb_pd KB25 pass "$tmp/$v" "rsync -a $tmp/big70/ dist/"
        kb_pd KB25 pass "$tmp/$v" "cp -R $tmp/big70/. dist/"
    done
    kb_pd KB25 deny "$tmp/installed" "cp -R $tmp/big70/. .claude/hooks/" 'kit code:'
    kb_pd KB25 deny "$tmp/installed" "rsync -a $tmp/big70/ .claude/hooks/" "$deny_text"
    kb_nokit_pd KB25 "$tmp/kitlike" "cp -R $tmp/big70/. .claude/hooks/"
    rm -r "$tmp"
}

# G19.039-G19.048 (review round 2, R2-N2 and R2-N3): a rebase `<branch>` switch and an `--onto`
# that drops commits both change kit code; a project nested in a bigger repo roots its kit paths
# on the project, not on the repo's top.
run_kit_boundary_review2_git_cases() {
    local tmp r m a c brings='brings kit changes: .claude/hooks/x' kit='kit code changes in the LoopKit repo'
    tmp="$(mktemp -d)"
    r="$tmp/n2"
    kb_repo "$r" installed
    git -C "$r" switch -q -c h2 main
    printf 'v2\n' >"$r/.claude/hooks/x"
    git -C "$r" commit -q -am h2
    git -C "$r" switch -q -c f3
    printf 'f3\n' >"$r/src/a.ts"
    git -C "$r" commit -q -am f3
    git -C "$r" switch -q h2
    kb_git G19.039 ask "$r" 'git rebase main s' "$brings"
    git -C "$r" switch -q f3
    kb_git G19.040 ask "$r" 'git rebase --onto main h2' "$brings"
    git -C "$r" switch -q feat/x
    kb_git_nokit G19.041 "$r" 'git rebase main s'
    m="$tmp/mono"
    a="$m/app"
    git init -q -b main "$m"
    git -C "$m" config user.email fixture@loopkit.invalid
    git -C "$m" config user.name Fixture
    mkdir -p "$a/src" "$a/.claude/hooks" "$m/other/.claude/hooks"
    printf 'a\n' >"$a/src/a.ts"
    printf 'x\n' >"$a/.claude/hooks/x"
    printf 'x\n' >"$m/other/.claude/hooks/x"
    seed_project "$a"
    printf 'core\n' >"$a/.claude/INSTALL_PROFILE"
    git -C "$m" add -A
    git -C "$m" commit -q -m seed
    for c in 'git restore .claude/hooks/x' 'git rm --cached .claude/hooks/x' 'git update-index --chmod=+x .claude/hooks/x'; do
        kb_git G19.042 deny "$a" "$c" "$kit"
    done
    for c in "git restore $a/.claude/hooks/x" "git rm --cached $a/.claude/hooks/x" "git update-index --chmod=+x $a/.claude/hooks/x"; do
        kb_git G19.043 deny "$a" "$c" "$kit"
    done
    kb_git G19.044 deny "$a" 'git checkout -- .claude/hooks/x' "$kit"
    kb_git G19.045 deny "$a" 'git rm -r .claude' "$kit"
    for c in 'git restore ../other/.claude/hooks/x' 'git rm --cached ../other/.claude/hooks/x' \
             "git restore $m/other/.claude/hooks/x" "git update-index --chmod=+x $m/other/.claude/hooks/x"; do
        kb_git_nokit G19.046 "$a" "$c"
    done
    kb_git_nokit G19.047 "$a" 'git restore src/a.ts'
    rm -r "$tmp"
}

# G19.048-G19.050 (review round 3, R3-2): `git am` applies from the work tree's top, so a mbox read
# from a subfolder (`-C src` or the cwd) is judged on the paths it writes from the top.
run_kit_boundary_review3_git_cases() {
    local tmp v out
    tmp="$(mktemp -d)"
    for v in installed kitlike; do
        kb_repo "$tmp/$v" "$([[ $v == kitlike ]] && echo kitlike || echo installed)"
        cp "$tmp/$v/m.mbox" "$tmp/$v/src/m.mbox"
    done
    kb_git G19.048 deny "$tmp/installed" 'git -C src am m.mbox' 'kit code: .claude/hooks/x'
    out="$(PROBE_PROJECT="$tmp/installed" git_hook_probe 'git am m.mbox' "$tmp/installed/src" "$tmp/installed/src")"
    kb_verdict G19.049 deny 'git am m.mbox with cwd src in installed' "$out" 'kit code: .claude/hooks/x'
    kb_git_nokit G19.050 "$tmp/kitlike" 'git -C src am m.mbox'
    rm -r "$tmp"
}

# KB26 (ship audit): a shell named by path, or `env` by path, running kit-apply.sh is the same run
# as the bare shell; `-o <name>` takes a value; a shell running another script has no kit verdict.
run_kit_boundary_ship_cases() {
    local tmp v c
    tmp="$(mktemp -d)"
    for v in installed kitlike; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
        printf '#!/usr/bin/env bash\n' >"$tmp/$v/.claude/scripts/kit-apply.sh"
    done
    printf 'x\n' >"$tmp/installed/other.sh"
    printf 'x\n' >"$tmp/installed/x.py"
    for c in '/bin/bash .claude/scripts/kit-apply.sh' '/bin/sh .claude/scripts/kit-apply.sh' \
             '/usr/bin/bash .claude/scripts/kit-apply.sh' '/usr/bin/env bash .claude/scripts/kit-apply.sh' \
             "/bin/bash $tmp/installed/.claude/scripts/kit-apply.sh" \
             'cd .claude/scripts && /bin/bash kit-apply.sh' \
             'bash -o pipefail .claude/scripts/kit-apply.sh' '/bin/bash -o pipefail .claude/scripts/kit-apply.sh'; do
        kb_pd KB26 deny "$tmp/installed" "$c" 'kit-apply.sh'
    done
    kb_pd KB26 deny "$tmp/installed" '/bin/bash < .claude/scripts/kit-apply.sh' 'unresolved write target'
    kb_pd KB26 deny "$tmp/kitlike" '/bin/bash .claude/scripts/kit-apply.sh' 'kit-apply.sh'
    kb_nokit_pd KB26 "$tmp/installed" '/bin/bash other.sh'
    kb_nokit_pd KB26 "$tmp/installed" '/usr/bin/env python3 x.py'
    rm -r "$tmp"
}

# kp_manifest <project> <line>…: write the project's .claude/kit-manifest, one argument per line.
kp_manifest() {
    local dir="$1"; shift
    mkdir -p "$dir/.claude"
    printf '%s\n' "$@" >"$dir/.claude/kit-manifest"
}

# KB27-KB33 (kit-prompts step 1): kit prompts are kit code through the install's manifest.
run_kit_prompts_step1_cases() {
    local tmp rel
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/installed" "$tmp/nomanifest" "$tmp/kitlike" "$tmp/malformed"
    kb_setup "$tmp/installed" installed
    kb_setup "$tmp/nomanifest" installed
    kb_setup "$tmp/kitlike" kitlike
    kb_setup "$tmp/malformed" installed
    kp_manifest "$tmp/installed" .claude/commands/loop/ship.md .claude/agents/github.md
    kp_manifest "$tmp/kitlike" .claude/commands/loop/ship.md
    kb_expect KB27 0 "$tmp/installed" cwk_is_kit_code .claude/commands/loop/ship.md
    kb_expect KB28 1 "$tmp/installed" cwk_is_kit_code .claude/skills/own/SKILL.md
    kb_expect KB28 1 "$tmp/installed" cwk_is_kit_code .claude/overlays/commands/loop/ship.md
    kb_expect KB29 0 "$tmp/installed" cwk_is_kit_code .claude/commands --reach
    kb_expect KB29 0 "$tmp/installed" cwk_is_kit_code .claude/commands/loop --reach
    kb_expect KB29 1 "$tmp/installed" cwk_is_kit_code .claude/skills/own --reach
    kb_expect KB30 0 "$tmp/nomanifest" cwk_is_kit_code .claude/skills/own/SKILL.md
    kb_expect KB30 0 "$tmp/nomanifest" cwk_is_kit_code .claude/guides/x.md
    kb_expect KB30 1 "$tmp/nomanifest" cwk_is_kit_code .claude/overlays/x.md
    kb_expect KB30 1 "$tmp/nomanifest" cwk_is_kit_code .claude/recipes/r.md
    kb_expect KB31 1 "$tmp/kitlike" cwk_is_kit_code .claude/commands/loop/ship.md
    kp_manifest "$tmp/malformed" ../x /abs .claude/hooks/y src/a.ts '.claude/skills/*' \
        '.claude/skills/a b.md' .claude/commands/loop/ship.md
    for rel in ../x /abs .claude/hooks/y src/a.ts '.claude/skills/*' .claude/skills/x.md \
               '.claude/skills/a b.md'; do
        kb_expect KB32 1 "$tmp/malformed" cwk_kit_prompt "$rel"
    done
    kb_expect KB32 0 "$tmp/malformed" cwk_kit_prompt .claude/commands/loop/ship.md
    kb_expect KB33 0 "$tmp/installed" cwk_is_kit_code .claude/kit-manifest
    kb_expect KB33 0 "$tmp/nomanifest" cwk_is_kit_code .claude/kit-manifest
    kb_expect KB33 0 "$PROJECT_ROOT" cwk_is_guarded .claude/kit-manifest
    rm -r "$tmp"
}

# kp_prompts <project>: the kit prompts and the project-owned files the KB34-KB40 cases name.
kp_prompts() {
    local dir="$1"
    mkdir -p "$dir/.claude/commands/loop" "$dir/.claude/agents" "$dir/.claude/skills/own" \
        "$dir/.claude/overlays/commands/loop" "$dir/.claude/recipes"
    printf 'x\n' >"$dir/.claude/commands/loop/ship.md"
    printf 'x\n' >"$dir/.claude/agents/github.md"
    printf 'a\n' >"$dir/.claude/skills/own/SKILL.md"
    printf 'a\n' >"$dir/.claude/overlays/commands/loop/ship.md"
    kp_manifest "$dir" .claude/agents/github.md .claude/commands/loop/ship.md
}

# KB34-KB40 (kit-prompts steps 2-3): Write/Edit and shell writes on a kit prompt.
run_kit_prompts_step23_cases() {
    local tmp v deny_text='kit code changes in the LoopKit repo, then `install.sh`'
    tmp="$(mktemp -d)"
    for v in installed kitlike; do
        mkdir -p "$tmp/$v"
        kb_setup "$tmp/$v" "$v"
        kp_prompts "$tmp/$v"
    done
    printf 'a\n' >"$tmp/kitlike/.claude/commands/loop/ship.md"
    kb_pf KB34 deny "$tmp/installed" Write .claude/commands/loop/ship.md "$deny_text"
    kb_pf KB34 deny "$tmp/installed" Edit .claude/commands/loop/ship.md "$deny_text"
    kb_pf KB35 pass "$tmp/installed" Write .claude/skills/own/SKILL.md
    kb_pf KB35 pass "$tmp/installed" Write .claude/overlays/commands/loop/ship.md
    kb_pf KB35 pass "$tmp/installed" Write .claude/recipes/r.md
    kb_pf KB36 pass "$tmp/kitlike" Edit .claude/commands/loop/ship.md
    kb_pd KB37 deny "$tmp/installed" 'sed -i s/a/b/ .claude/commands/loop/ship.md' 'kit code:'
    kb_pd KB37 deny "$tmp/installed" 'printf x > .claude/agents/github.md' 'kit code:'
    kb_pd KB38 deny "$tmp/installed" 'rm -r .claude/commands' 'kit code:'
    kb_pd KB38 deny "$tmp/installed" 'mv .claude/agents/github.md /tmp/' 'kit code:'
    kb_nokit_pd KB39 "$tmp/installed" 'printf x > .claude/skills/own/SKILL.md'
    kb_nokit_pd KB39 "$tmp/installed" 'printf x > .claude/overlays/a.md'
    kb_nokit_pd KB40 "$tmp/kitlike" 'sed -i s/a/b/ .claude/commands/loop/ship.md'
    rm -r "$tmp"
}

# kp_repo <dir> <installed|kitlike> [manifest|nomanifest]: kb_repo plus committed prompts
# (ship.md, github.md, a project-owned skill, a guide), each edited after the commit, and an
# untracked manifest listing ship.md and github.md unless `nomanifest`.
kp_repo() {
    local r="$1" f
    kb_repo "$r" "$2"
    mkdir -p "$r/.claude/commands/loop" "$r/.claude/agents" "$r/.claude/skills/own" "$r/.claude/guides"
    for f in .claude/commands/loop/ship.md .claude/agents/github.md .claude/skills/own/SKILL.md .claude/guides/x.md; do
        printf 'a\n' >"$r/$f"
        git -C "$r" add "$f"
    done
    git -C "$r" commit -q -m prompts
    for f in .claude/commands/loop/ship.md .claude/skills/own/SKILL.md .claude/guides/x.md; do
        printf 'b\n' >"$r/$f"
    done
    [[ "${3:-manifest}" == nomanifest ]] || kp_manifest "$r" .claude/agents/github.md .claude/commands/loop/ship.md
}

# G19.051-G19.055 (kit-prompts step 4): git writers on a kit prompt.
run_kit_prompts_step4_cases() {
    local tmp kit='kit code changes in the LoopKit repo'
    tmp="$(mktemp -d)"
    kp_repo "$tmp/installed" installed
    kp_repo "$tmp/nomanifest" installed nomanifest
    kp_repo "$tmp/kitlike" kitlike
    kb_git G19.051 deny "$tmp/installed" 'git checkout HEAD -- .claude/commands/loop/ship.md' '.claude/commands/loop/ship.md'
    kb_git G19.052 deny "$tmp/installed" 'git rm .claude/agents/github.md' "$kit"
    kb_git_nokit G19.053 "$tmp/installed" 'git checkout HEAD -- .claude/skills/own/SKILL.md'
    kb_git G19.054 deny "$tmp/nomanifest" 'git restore .claude/guides/x.md' "$kit"
    kb_git_nokit G19.055 "$tmp/kitlike" 'git checkout HEAD -- .claude/commands/loop/ship.md'
    rm -r "$tmp"
}

# lp_git_setup <fixture repo> <variant>: the G21 git-guard setup. The feat tree switches to
# feat/s1; a bare origin holds main and audit/x; docs/work/s1/pr-body.md and plan.md exist;
# the record is valid (repo o/r, base audit/x, barrier and base_ok true) unless the variant
# says otherwise: lpnorec none, lpblocked marked blocked, lpnobar barrier false, lpnobaseok base_ok false, lps2 branch
# feat/s2, lpother HEAD stays feat/x, lptag a tag feat/s1, lpremote feat/s1 already on origin,
# lpcfg* one push-redirecting config, lpbody a Co-Authored-By body, lpnobody no body, lpslow an
# origin that never answers (lpslowb: the same, the hook held to 7 s), lpbadjson / lpv2 an unreadable record, lpbasemain plan `Base: main`.
# lp_assets_setup <fixture repo> <variant>: a local refs/heads/pr-assets (the kit-pr-assets.py commit):
# lpassets / lpassetsblk with no remote pr-assets, lpassetsff one commit ahead of origin's, lpassetsdiv
# unrelated to origin's.
lp_assets_setup() {
    local t="$1" tree c1 c2
    tree="$(git -C "$t" mktree </dev/null)"
    c1="$(git -C "$t" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit-tree "$tree" -m shots1)"
    case "$2" in
        lpassetsff)
            git -C "$t" push -q origin "$c1:refs/heads/pr-assets" 2>/dev/null
            c2="$(git -C "$t" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit-tree "$tree" -p "$c1" -m shots2)" ;;
        lpassetsdiv)
            git -C "$t" push -q origin "$c1:refs/heads/pr-assets" 2>/dev/null
            c2="$(git -C "$t" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit-tree "$tree" -m other)" ;;
        *) c2="$c1" ;;
    esac
    git -C "$t" update-ref refs/heads/pr-assets "$c2"
}

lp_git_setup() {
    local t="$1" v="$2" feat="$1/.feat" branch=feat/s1 barrier=true base_ok=true version=1 blocked=false released=false
    git init -q --bare -b main "$t/.origin.git"
    git -C "$t" remote add origin "$t/.origin.git"
    git -C "$t" branch audit/x
    git -C "$t" push -q origin main audit/x 2>/dev/null
    [[ "$v" == lpother || "$v" == lpassetsother ]] || git -C "$feat" switch -q -c feat/s1
    mkdir -p "$feat/docs/work/s1" "$feat/.claude" "$t/.home"
    printf 'Summary.\n' >"$feat/docs/work/s1/pr-body.md"
    printf 'Base: audit/x\n' >"$feat/docs/work/s1/plan.md"
    case "$v" in
        lp | lpnorec | lpbadjson | lpother) ;;
        lpv2) version=2 ;;
        lpblocked) blocked=true ;;
        lpreleased) released=true ;;
        lpnobar) barrier=false ;;
        lpnobaseok) base_ok=false ;;
        lps2) branch=feat/s2 ;;
        lptag) git -C "$t" tag feat/s1 ;;
        lpremote) git -C "$feat" push -q origin feat/s1 2>/dev/null ;;
        lpcfgpush) git -C "$t" config remote.origin.push 'refs/heads/*:refs/heads/x/*' ;;
        lpcfginsteadof) git -C "$t" config url.x.pushInsteadOf "$t/.origin.git" ;;
        lpcfgfollow) git -C "$t" config push.followTags true ;;
        lpcfgssh) git -C "$t" config core.sshCommand ssh ;;
        lpcfginclude)
            printf '[remote "origin"]\n\tpushurl = %s\n' "$t/.other.git" >"$t/.inc"
            git -C "$t" config include.path "$t/.inc" ;;
        lpcfgmirror) git -C "$t" config remote.origin.mirror true ;;
        lpcfgrecv) git -C "$t" config remote.origin.receivepack git-receive-pack ;;
        lpcfgopt) git -C "$t" config push.pushOption ci.skip ;;
        lpbody) printf 'Summary.\nCo-Authored-By: x\n' >"$feat/docs/work/s1/pr-body.md" ;;
        lpnobody) rm "$feat/docs/work/s1/pr-body.md" ;;
        lpslow | lpslowb)
            git -C "$t" config protocol.ext.allow always
            git -C "$t" remote set-url origin 'ext::sleep 30' ;;
        lpbasemain) printf 'Base: main\n' >"$feat/docs/work/s1/plan.md" ;;
        lpassets | lpassetsff | lpassetsdiv | lpassetsblk) lp_assets_setup "$t" "$v"
            [[ "$v" != lpassetsblk ]] || blocked=true ;;
        lpout)
            git init -q -b feat/s1 "$t/out"
            git -C "$t/out" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --allow-empty -m seed ;;
        lpassetsother | lpassetsrel | lpassetstag | lpassetscfg) lp_assets_setup "$t" lpassets
            case "$v" in
                lpassetsrel) released=true ;;
                lpassetstag) git -C "$t" tag pr-assets ;;
                lpassetscfg) git -C "$t" config remote.origin.push 'refs/heads/*:refs/heads/x/*' ;;
            esac ;;
        lpwtignored) printf '%s\n' '.claude/' >"$feat/.gitignore" ;;
        lpwttracked)
            mkdir -p "$feat/.claude/hooks"
            printf 'x\n' >"$feat/.claude/hooks/x"
            git -C "$feat" add -f .claude/hooks/x
            git -C "$feat" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q -m kit
            printf '%s\n' '.claude/' >"$feat/.gitignore" ;;
        *) return 1 ;;
    esac
    case "$v" in
        lpnorec) ;;
        lpbadjson) printf '{"version":1,' >"$feat/.claude/.loop-record.json" ;;
        *)
            jq -n --arg branch "$branch" --arg sha "$(git -C "$t" rev-parse main)" --argjson barrier "$barrier" \
                --argjson ok "$base_ok" --argjson v "$version" --argjson blk "$blocked" --argjson rel "$released" \
                '{version: $v, slug: "s1", plan: "docs/work/s1/plan.md", branch: $branch, base: "audit/x",
                  base_sha: $sha, repo: "o/r", default_branch: "main", barrier: $barrier, base_ok: $ok,
                  rows: [], at: "2026-11-19T00:00:00Z", tool_use_id: "toolu_lp"}
                 + (if $blk then {blocked: true, blocked_at: "2026-11-19T01:00:00Z"} else {} end)
                 + (if $rel then {mode: "moi", released_at: "2026-11-19T02:00:00Z"} else {} end)' \
                >"$feat/.claude/.loop-record.json" ;;
    esac
}

# ---- loop-to-pr step 2 (LP5-LP19): loop-record.py, the record written from the plan-gate go.
LP_HOOK="$HOOKS_DIR/loop-record.py"
LP_RULES_ALL='[{"type":"pull_request"},{"type":"non_fast_forward"},{"type":"deletion"}]'

# lp_shim <dir>: a fake gh answering from files under <dir>/gh: repo.json, rules-<branch>.json
# (`/` → `_`), rules-<branch>.exit (a failing call), sleep (seconds before any answer).
lp_shim() {
    mkdir -p "$1/bin" "$1/gh"
    cat >"$1/bin/gh" <<'SH'
#!/usr/bin/env bash
d="${LP_SHIM:?}"
[[ ! -f "$d/sleep" ]] || sleep "$(cat "$d/sleep")"
if [[ "${1:-}" == repo && "${2:-}" == view ]]; then cat "$d/repo.json"; exit 0; fi
if [[ "${1:-}" == api ]]; then
    for a in "$@"; do [[ "$a" == *"/rules/branches/"* ]] && b="${a#*/rules/branches/}"; done
    b="${b:-}"; b="${b//%2F/_}"; b="${b//%2f/_}"; b="${b//\//_}"
    if [[ -f "$d/rules-$b.exit" ]]; then printf 'gh: HTTP 403\n' >&2; exit "$(cat "$d/rules-$b.exit")"; fi
    if [[ -f "$d/rules-$b.json" ]]; then cat "$d/rules-$b.json"; else printf '[]\n'; fi
    exit 0
fi
exit 1
SH
    chmod +x "$1/bin/gh"
    printf '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}\n' >"$1/gh/repo.json"
    printf '%s\n' "$LP_RULES_ALL" >"$1/gh/rules-main.json"
}

# lp_repo <dir>: a repo on `audit/x` (one commit past `main`), both pushed to a bare
# `<dir>.origin.git`, with the plans docs/work/s1/plan.md and docs/work/s2/plan.md.
lp_repo() {
    local r="$1"
    git init -q --bare -b main "$r.origin.git"
    git init -q -b main "$r"
    git -C "$r" config user.email fixture@loopkit.invalid
    git -C "$r" config user.name Fixture
    mkdir -p "$r/docs/work/s1" "$r/docs/work/s2"
    printf 'p\n' >"$r/docs/work/s1/plan.md"
    printf 'p\n' >"$r/docs/work/s2/plan.md"
    git -C "$r" add docs
    git -C "$r" commit -q -m seed
    git -C "$r" remote add origin "$r.origin.git"
    git -C "$r" switch -q -c audit/x
    printf 'x\n' >"$r/x"
    git -C "$r" add x
    git -C "$r" commit -q -m x
    git -C "$r" push -q origin main audit/x 2>/dev/null
}

# lp_ask <cwd> <header> <question text> <answer> [event]: an AskUserQuestion hook input shaped
# like the 2026-11-18 spike (answers in tool_input and tool_response). PreToolUse: the answer
# `-` leaves `answers` out and there is no tool_response.
lp_ask() {
    jq -cn --arg cwd "$1" --arg h "$2" --arg q "$3" --arg a "$4" --arg ev "${5:-PostToolUse}" '
        {questions: [{question: $q, header: $h, multiSelect: false,
            options: [{label: "go", description: "run EXECUTE"},
                      {label: "amend", description: "change the plan"}]}]} as $in
        | {session_id: "s", hook_event_name: $ev, tool_name: "AskUserQuestion", cwd: $cwd,
           tool_use_id: "toolu_lp", permission_mode: "auto"}
        + (if $ev == "PreToolUse" then
               {tool_input: (if $a == "-" then $in else $in + {answers: {($q): $a}} end)}
           else
               {tool_input: ($in + {answers: {($q): $a}}),
                tool_response: ($in + {answers: {($q): $a}, annotations: {}})}
           end)'
}

# lp_bash <cwd> <command> <stdout>: a PostToolUse Bash hook input.
lp_bash() {
    jq -cn --arg cwd "$1" --arg c "$2" --arg o "$3" '
        {session_id: "s", hook_event_name: "PostToolUse", tool_name: "Bash", cwd: $cwd,
         tool_use_id: "toolu_b", tool_input: {command: $c, description: "open the PR"},
         tool_response: {stdout: $o, stderr: "", interrupted: false, isImage: false}}'
}

# lp_run <stdin> <shim dir> [VAR=value…]: runs the hook from the shim's PATH; sets LP_OUT, LP_CODE.
lp_run() {
    local input="$1" shim="$2"
    shift 2
    set +e
    LP_OUT="$(printf '%s' "$input" | env PATH="$shim/bin:$PATH" LP_SHIM="$shim/gh" CWK_HOOK_TIMING=0 \
        CWK_HEALTH_LOG=0 "$@" ${CASE_TIMEOUT[@]+"${CASE_TIMEOUT[@]}"} "$LP_HOOK" 2>/dev/null)"
    LP_CODE=$?
    set -e
}

# lp_rec <id> <label> <record> <jq filter> <want>: the hook exited 0 and the record's
# <jq filter> prints exactly <want>.
lp_rec() {
    local got
    CASES=$((CASES + 1))
    [[ "$LP_CODE" -eq 0 ]] || { fail loop-record.py "$1 $2" "exit $LP_CODE: ${LP_OUT:0:200}"; return 0; }
    [[ -f "$3" ]] || { fail loop-record.py "$1 $2" "no record at $3"; return 0; }
    got="$(jq -c "$4" "$3" 2>&1)" || true
    [[ "$got" == "$5" ]] || fail loop-record.py "$1 $2" "$4: expected $5, got $got"
}

# lp_none <id> <label> <record>: the hook exited 0 and no record exists.
lp_none() {
    CASES=$((CASES + 1))
    [[ "$LP_CODE" -eq 0 ]] || { fail loop-record.py "$1 $2" "exit $LP_CODE: ${LP_OUT:0:200}"; return 0; }
    [[ ! -e "$3" ]] || fail loop-record.py "$1 $2" "a record was written: $(head -c 300 "$3")"
}

# lp_same <id> <label> <record> <sha256 before>: the hook exited 0 and the record is unchanged.
lp_same() {
    CASES=$((CASES + 1))
    [[ "$LP_CODE" -eq 0 ]] || { fail loop-record.py "$1 $2" "exit $LP_CODE: ${LP_OUT:0:200}"; return 0; }
    [[ -f "$3" && "$(sha256sum <"$3")" == "$4" ]] || fail loop-record.py "$1 $2" "the record changed or went"
}

# lp_verdict <id> <label> <want> [reason substring]: the hook's PreToolUse verdict.
lp_verdict() {
    local got
    CASES=$((CASES + 1))
    got="$(semantic_verdict "$LP_CODE" <(printf '%s' "$LP_OUT"))"
    [[ "$got" == "$3" ]] || { fail loop-record.py "$1 $2" "expected $3, got $got: ${LP_OUT:0:200}"; return 0; }
    [[ -z "${4:-}" || "$LP_OUT" == *"$4"* ]] || fail loop-record.py "$1 $2" "reason lacks '$4'"
}

run_loop_to_pr_step2_cases() {
    local tmp r rec q q6 sha want before h u row
    tmp="$(mktemp -d)"
    q=$'Plan go — docs/work/s1/plan.md\nFrozen cases to amend:\nnone'
    q6=$'Plan go — docs/work/s1/plan.md\nFrozen cases to amend:\nsrc/a/x.utils.test.ts | U2 | 9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5'
    lp_shim "$tmp/sh"

    # LP5 the core record.
    r="$tmp/r5"; lp_repo "$r"; rec="$r/.claude/.loop-record.json"
    sha="$(git -C "$r" rev-parse audit/x)"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    want="$(jq -cn --arg sha "$sha" '{version: 1, slug: "s1", plan: "docs/work/s1/plan.md",
        branch: "feat/s1", base: "audit/x", base_sha: $sha, repo: "o/r", default_branch: "main",
        barrier: true, base_ok: true, rows: [], tool_use_id: "toolu_lp"}')"
    lp_rec LP5 'plan go, no rows' "$rec" \
        '{version, slug, plan, branch, base, base_sha, repo, default_branch, barrier, base_ok, rows, tool_use_id}' "$want"
    lp_rec LP5 'plan go, at' "$rec" '.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' true

    # LP6 one row, stored verbatim.
    rm -f "$rec"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q6" go)" "$tmp/sh"
    lp_rec LP6 'one row' "$rec" '.rows' \
        '[{"path":"src/a/x.utils.test.ts","id":"U2","sha256":"9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5"}]'

    # LP7 a subagent's call records nothing.
    rm -f "$rec"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go | jq -c '. + {agent_id: "a1"}')" "$tmp/sh"
    lp_none LP7 'agent_id' "$rec"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go | jq -c '. + {agent_type: "implementer"}')" "$tmp/sh"
    lp_none LP7 'agent_type' "$rec"

    # LP8 only exactly `go` opens the record.
    for u in amend 'go ' Go 'ship it please'; do
        lp_run "$(lp_ask "$r" 'Plan gate' "$q" "$u")" "$tmp/sh"
        lp_none LP8 "answer '$u'" "$rec"
    done

    # LP9 another header, or a plan that does not exist.
    lp_run "$(lp_ask "$r" 'Plan' "$q" go)" "$tmp/sh"
    lp_none LP9 'header Plan' "$rec"
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s9/plan.md\nFrozen cases to amend:\nnone' go)" "$tmp/sh"
    lp_none LP9 'missing plan' "$rec"

    # LP10 a second go replaces the first.
    lp_run "$(lp_ask "$r" 'Plan gate' "$q6" go)" "$tmp/sh"
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s2/plan.md\nFrozen cases to amend:\nnone' go)" "$tmp/sh"
    lp_rec LP10 'second go' "$rec" '{slug, branch, rows}' '{"slug":"s2","branch":"feat/s2","rows":[]}'

    # LP11 a worktree branch made as the kit makes it.
    r="$tmp/r11"; lp_repo "$r"
    git -C "$r" worktree add -q "$tmp/wt11" -b feat/s1 audit/x 2>/dev/null
    sha="$(git -C "$r" merge-base feat/s1 audit/x)"
    lp_run "$(lp_ask "$tmp/wt11" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_rec LP11 'worktree from audit/x' "$tmp/wt11/.claude/.loop-record.json" '{branch, base, base_sha}' \
        "$(jq -cn --arg sha "$sha" '{branch: "feat/s1", base: "audit/x", base_sha: $sha}')"
    CASES=$((CASES + 1))
    [[ ! -e "$r/.claude/.loop-record.json" ]] || fail loop-record.py 'LP11 worktree' "record written in the main tree"

    # LP12 a base the reflog cannot name records nothing.
    r="$tmp/r12a"; lp_repo "$r"
    git -C "$r" worktree add -q "$tmp/wt12" -b feat/s1 2>/dev/null
    lp_run "$(lp_ask "$tmp/wt12" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_none LP12 'created from HEAD' "$tmp/wt12/.claude/.loop-record.json"
    r="$tmp/r12b"; lp_repo "$r"
    git -C "$r" switch -q -c feat/s1 "$(git -C "$r" rev-parse HEAD)"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_none LP12 'created from a sha' "$r/.claude/.loop-record.json"
    r="$tmp/r12c"; lp_repo "$r"
    git -C "$r" switch -q --detach
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_none LP12 'detached HEAD' "$r/.claude/.loop-record.json"

    # LP13 a malformed row records nothing and leaves an existing record as it was.
    r="$tmp/r13"; lp_repo "$r"; rec="$r/.claude/.loop-record.json"
    h='9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5'
    for row in 'src/a/x.utils.test.ts | U2' "src/a/x.utils.test.ts | U2 | ${h:1}" \
               "src/a/x.utils.test.ts | U2-U4 | $h" "src/a/x.utils.test.ts | X2 | $h"; do
        rm -f "$rec"
        lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s1/plan.md\nFrozen cases to amend:\n'"$row" go)" "$tmp/sh"
        lp_none LP13 "row '$row'" "$rec"
    done
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    before="$( { sha256sum <"$rec"; } 2>/dev/null || true)"
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s2/plan.md\nFrozen cases to amend:\nsrc/a/x.utils.test.ts | X2 | '"$h" go)" "$tmp/sh"
    lp_same LP13 'malformed second go' "$rec" "$before"

    # LP14 the gate is never pre-filled.
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go PreToolUse)" "$tmp/sh"
    lp_verdict LP14 'pre-filled gate' deny 'never pre-filled'
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" - PreToolUse)" "$tmp/sh"
    lp_verdict LP14 'gate asked' pass
    lp_run "$(lp_ask "$r" 'Framework' 'Which framework?' React PreToolUse)" "$tmp/sh"
    lp_verdict LP14 'other question pre-filled' pass
    lp_run '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","header":"Plan gate"' "$tmp/sh"
    lp_verdict LP14 'unparsable with Plan gate' deny
    lp_run '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"' "$tmp/sh"
    lp_verdict LP14 'unparsable without' pass

    # LP15 the PR URL closes the record; anything else keeps it.
    r="$tmp/r15"; lp_repo "$r"; rec="$r/.claude/.loop-record.json"
    u='gh pr create --repo o/r --base audit/x --head feat/s1 --title "Loop to PR" --body-file docs/work/s1/pr-body.md'
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_run "$(lp_bash "$r" "$u" $'Creating pull request\nhttps://github.com/o/r/pull/7\n')" "$tmp/sh"
    CASES=$((CASES + 1))
    [[ "$LP_CODE" -eq 0 && ! -e "$rec" ]] || fail loop-record.py 'LP15 PR opened' "record kept (exit $LP_CODE)"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    before="$( { sha256sum <"$rec"; } 2>/dev/null || true)"
    lp_run "$(lp_bash "$r" "$u" 'no url here')" "$tmp/sh"
    lp_same LP15 'no PR URL' "$rec" "$before"
    lp_run "$(lp_bash "$r" "$u" 'https://github.com/o/z/pull/7')" "$tmp/sh"
    lp_same LP15 'another repo' "$rec" "$before"
    lp_run "$(lp_bash "$r" 'git status' 'https://github.com/o/r/pull/7')" "$tmp/sh"
    lp_same LP15 'another command' "$rec" "$before"

    # LP16 the barrier, read once at the go.
    r="$tmp/r16"; lp_repo "$r"; rec="$r/.claude/.loop-record.json"
    lp_shim "$tmp/sh16a"; printf '[{"type":"pull_request"},{"type":"non_fast_forward"}]\n' >"$tmp/sh16a/gh/rules-main.json"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh16a"
    lp_rec LP16 'no deletion rule' "$rec" '.barrier' false
    rm -f "$rec"
    lp_shim "$tmp/sh16b"; printf '1\n' >"$tmp/sh16b/gh/rules-main.exit"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh16b"
    lp_rec LP16 'gh 403' "$rec" '.barrier' false
    rm -f "$rec"
    mkdir -p "$tmp/nogh"
    ln -sf "$(python3 -I -c 'import sys; print(sys.executable)')" "$tmp/nogh/python3"
    ln -sf "$(command -v git)" "$tmp/nogh/git"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh" PATH="$tmp/nogh"
    lp_rec LP16 'gh absent' "$rec" '.barrier' false
    rm -f "$rec"
    lp_shim "$tmp/sh16c"; printf '3\n' >"$tmp/sh16c/gh/sleep"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh16c" CWK_LOOP_RECORD_GH_BUDGET=1
    lp_rec LP16 'past the budget' "$rec" '.barrier' false

    # LP17 base_ok.
    r="$tmp/r17a"; lp_repo "$r"; git -C "$r" switch -q main
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_rec LP17 'base is the default' "$r/.claude/.loop-record.json" '{base, base_ok}' '{"base":"main","base_ok":true}'
    r="$tmp/r17b"; lp_repo "$r"
    lp_shim "$tmp/sh17"; printf '[{"type":"pull_request"}]\n' >"$tmp/sh17/gh/rules-audit_x.json"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh17"
    lp_rec LP17 'base has a rule' "$r/.claude/.loop-record.json" '.base_ok' false
    r="$tmp/r17c"; lp_repo "$r"; git -C "$r" switch -q -c audit/y
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    lp_rec LP17 'base not on the remote' "$r/.claude/.loop-record.json" '{base, base_ok}' '{"base":"audit/y","base_ok":false}'

    # LP18 --clear.
    r="$tmp/r5"; rec="$r/.claude/.loop-record.json"
    lp_run "$(lp_ask "$r" 'Plan gate' "$q" go)" "$tmp/sh"
    set +e
    (cd "$r" && "$LP_HOOK" --clear </dev/null >/dev/null 2>&1); LP_CODE=$?
    set -e
    lp_none LP18 'clear' "$rec"
    set +e
    (cd "$r" && "$LP_HOOK" --clear </dev/null >/dev/null 2>&1); LP_CODE=$?
    set -e
    lp_none LP18 'clear with none' "$rec"

    # LP19 garbage on the Post paths: exit 0, nothing written, nothing printed.
    for u in 'garbage {' '' '[1]' '"PostToolUse"'; do
        lp_run "$u" "$tmp/sh"
        lp_none LP19 "stdin '$u'" "$rec"
        CASES=$((CASES + 1))
        [[ -z "$LP_OUT" ]] || fail loop-record.py "LP19 stdin '$u'" "printed '${LP_OUT:0:200}'"
    done
    rm -rf "$tmp"
}

# lp_unfrozen_repo <dir> <record branch|-> <rows json>: a git project on feat/s1 (one commit on
# audit/x before it), with a valid-shaped record for <record branch> holding <rows>, or none for `-`.
# Each row's path is created as an empty file, as the plan gate holds frozen files that exist,
# unless a 4th argument asks for the bare rows.
lp_unfrozen_repo() {
    local r="$1" rowpath
    git init -q -b audit/x "$r"
    git -C "$r" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --allow-empty -m seed
    git -C "$r" switch -q -c feat/s1
    mkdir -p "$r/.claude"
    [[ "$2" == - ]] && return 0
    if [[ -z "${4:-}" ]]; then
        while IFS= read -r rowpath; do
            mkdir -p "$r/$(dirname "$rowpath")"
            : >"$r/$rowpath"
        done < <(jq -r '.[].path' <<<"$3")
    fi
    jq -n --arg branch "$2" --arg sha "$(git -C "$r" rev-parse audit/x)" --argjson rows "$3" \
        '{version: 1, slug: "s1", plan: "docs/work/s1/plan.md", branch: $branch, base: "audit/x",
          base_sha: $sha, repo: "o/r", default_branch: "main", barrier: true, base_ok: true,
          rows: $rows, at: "2026-11-19T00:00:00Z", tool_use_id: "toolu_lp"}' >"$r/.claude/.loop-record.json"
}

# LP21-LP32 (loop-to-pr step 4): a `.tdd-unfrozen` line backed by a row of the tree's valid record
# is written with no prompt; anything else keeps the guarded ask.
run_loop_to_pr_step4_cases() {
    local tmp h old='src/b/old.test.ts  # U9: kept' x='src/a/x.utils.test.ts' r
    local -a hrow
    tmp="$(mktemp -d)"
    h='9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5'
    hrow=("$(jq -cn --arg p "$x" --arg h "$h" '[{path: $p, id: "U2", sha256: $h}]')")

    r="$tmp/one"; lp_unfrozen_repo "$r" feat/s1 "${hrow[0]}"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP21 pass Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2: reason" \
        '{old_string:$o, new_string:$n}')" "$r"

    r="$tmp/two"
    lp_unfrozen_repo "$r" feat/s1 "$(jq -cn --arg p "$x" --arg h "$h" \
        '[{path: $p, id: "U2", sha256: $h}, {path: "src/b/y.mapper.test.ts", id: "M3", sha256: $h}]')"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP22 pass Edit "$(jq -cn --arg o "$old" \
        --arg n "$old"$'\n'"$x  # U2: reason"$'\n''src/b/y.mapper.test.ts  # M3: other reason' \
        '{old_string:$o, new_string:$n}')" "$r"

    r="$tmp/absent"; lp_unfrozen_repo "$r" feat/s1 "${hrow[0]}"
    unfrozen_case LP23 pass Write "$(jq -cn --arg c "$x  # U2: reason"$'\n' '{content:$c}')" "$r"

    r="$tmp/one"
    unfrozen_case LP24 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n''src/a/z.utils.test.ts  # U2: r' \
        '{old_string:$o, new_string:$n}')" "$r"
    unfrozen_case LP25 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U7: r" \
        '{old_string:$o, new_string:$n}')" "$r"
    r="$tmp/impl"
    lp_unfrozen_repo "$r" feat/s1 "$(jq -cn --arg h "$h" '[{path: "src/a/x.utils.ts", id: "U2", sha256: $h}]')"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP26 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n''src/a/x.utils.ts  # U2: r' \
        '{old_string:$o, new_string:$n}')" "$r"
    r="$tmp/norec"; lp_unfrozen_repo "$r" - '[]'
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP27 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2: r" \
        '{old_string:$o, new_string:$n}')" "$r"
    r="$tmp/one"
    unfrozen_case LP28 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # no id here" \
        '{old_string:$o, new_string:$n}')" "$r"

    unfrozen_case LP29 pass Edit "$(jq -cn --arg o "$old" --arg n "$x  # U2: reason" \
        '{old_string:$o, new_string:$n}')" "$r"
    unfrozen_case LP29 ask Edit "$(jq -cn --arg o "$old" --arg n "$x  # U7: reason" \
        '{old_string:$o, new_string:$n}')" "$r"

    r="$tmp/other"; lp_unfrozen_repo "$r" feat/s9 "${hrow[0]}"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP30 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2: r" \
        '{old_string:$o, new_string:$n}')" "$r"
    r="$tmp/onbase"; lp_unfrozen_repo "$r" feat/s1 "${hrow[0]}"
    git -C "$r" switch -q audit/x
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP30.2 pass Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2: r" \
        '{old_string:$o, new_string:$n}')" "$r"

    r="$tmp/stale"; lp_unfrozen_repo "$r" feat/s1 "${hrow[0]}"
    git -C "$r" switch -q audit/x
    git -C "$r" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --amend --allow-empty -m rewritten
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP30.3 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2: r" \
        '{old_string:$o, new_string:$n}')" "$r"

    r="$tmp/suffix"
    lp_unfrozen_repo "$r" feat/s1 "$(jq -cn --arg h "$h" '[{path: "a/x.utils.test.ts", id: "U2", sha256: $h}]')" bare
    mkdir -p "$r/src/a"
    printf 't\n' >"$r/src/a/x.utils.test.ts"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP24.2 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n''a/x.utils.test.ts  # U2: r' \
        '{old_string:$o, new_string:$n}')" "$r"

    r="$tmp/pair"
    lp_unfrozen_repo "$r" feat/s1 "$(jq -cn --arg p "$x" --arg h "$h" \
        '[{path: $p, id: "U2", sha256: $h}, {path: $p, id: "U5", sha256: $h}]')"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP32 pass Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2, U5: r" \
        '{old_string:$o, new_string:$n}')" "$r"
    unfrozen_case LP32 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n'"$x  # U2, U6: r" \
        '{old_string:$o, new_string:$n}')" "$r"

    # LP24.3: z.utils.test.ts exists, but only x.utils.test.ts holds the row U2: the pair (path, id) is
    # no row, so the line asks (a membership on the id alone would let it through).
    r="$tmp/pathblind"; lp_unfrozen_repo "$r" feat/s1 "${hrow[0]}"
    printf 't\n' >"$r/src/a/z.utils.test.ts"
    printf '%s\n' "$old" >"$r/.claude/.tdd-unfrozen"
    unfrozen_case LP24.3 ask Edit "$(jq -cn --arg o "$old" --arg n "$old"$'\n''src/a/z.utils.test.ts  # U2: r' \
        '{old_string:$o, new_string:$n}')" "$r"
    rm -rf "$tmp"
}

# lp_freeze_project <dir> <record branch|-> <rows json> <unfrozen lines>: lp_unfrozen_repo plus the
# default project config and the frozen file src/a/x.utils.test.ts (cases U1, U2, U3).
lp_freeze_project() {
    lp_unfrozen_repo "$1" "$2" "$3"
    pv_project "$1"
    mkdir -p "$1/src/a"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U1 returns one', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => {" '    expect(f(0)).toBe(0)' '  })' '' \
        "  it('U3 keeps three', () => {" '    expect(f(3)).toBe(3)' '  })' '})' >"$1/src/a/x.utils.test.ts"
    [[ -z "$4" ]] || printf '%s\n' "$4" >"$1/.claude/.tdd-unfrozen"
}

# lp_freeze <id> <verdict> <project> <tool> <input json> [needle] [absent]: tdd-freeze-tests.sh on
# src/a/x.utils.test.ts of <project>.
lp_freeze() {
    local out
    out="$(project_hook_probe tdd-freeze-tests.sh "$3" "$(jq -cn --arg t "$4" --arg f "$3/src/a/x.utils.test.ts" \
        --arg c "$3" --argjson i "$5" '{tool_name:$t, cwd:$c, tool_input:($i + {file_path:$f})}')")"
    pv_expect "$1" "$2" "$out" "${6:-}" "${7:-}"
}

# lp_c3b <id> <verdict> <dir> <row id> <row title> <U2 line> <U3 line> <U4 block|-> <old> <new> [needle]:
# a frozen x.utils.test.ts whose U2 and U3 bodies hold the given lines (an optional U4 block after
# them), the plan-gate row <row id> on <row title>, and one Edit replacing <old> with <new>.
lp_c3b() {
    local x='src/a/x.utils.test.ts' d="$3"
    lp_freeze_project "$d" feat/s1 "$(jq -cn --arg p "$x" --arg i "$4" --arg h "$(printf '%s' "$5" | sha256sum | cut -c1-64)" \
        '[{path: $p, id: $i, sha256: $h}]')" "$x  # $4: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U1 returns one', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => {" "    $6" '  })' '' \
        "  it('U3 keeps three', () => {" "    $7" '  })' >"$d/$x"
    [[ "$8" == - ]] || printf '%s\n' '' "$8" >>"$d/$x"
    printf '%s\n' '})' >>"$d/$x"
    lp_freeze "$1" "$2" "$d" Edit "$(jq -cn --arg o "$9" --arg n "${10}" '{old_string:$o, new_string:$n}')" "${11:-}"
}

# lp_py_project <dir>: lp_unfrozen_repo on feat/s1 holding the row B2 of tests/services/test_b.py (cases B1,
# B2), the addon config, and the `.tdd-unfrozen` line for it.
lp_py_project() {
    lp_unfrozen_repo "$1" feat/s1 "$(jq -cn \
        '[{path: "tests/services/test_b.py", id: "B2", sha256: "e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b"}]')"
    pv_addon_project "$1"
    mkdir -p "$1/tests/services"
    printf '%s\n' 'from app.services.b import g' '' '' 'def test_b1_returns_ok():' '    assert g(1) == 1' '' '' \
        'def test_b2_returns_err():' '    assert g(0) == 0' >"$1/tests/services/test_b.py"
    printf '%s\n' 'tests/services/test_b.py  # B2: empty input is an error' >"$1/.claude/.tdd-unfrozen"
}

# lp_worktree <main dir>: commits the tree of <main> (on feat/s1), moves <main> back to audit/x, adds
# <main>/.claude/worktrees/s1 on feat/s1 and moves the record and the `.tdd-unfrozen` list into it: the
# tree a pass entered by path works in, with <main> as the project dir and no list of its own.
lp_worktree() {
    local m="$1" w="$1/.claude/worktrees/s1"
    git -C "$m" add -A -- src 2>/dev/null || true
    git -C "$m" add -A -- tests 2>/dev/null || true
    git -C "$m" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --allow-empty -m frozen
    git -C "$m" switch -q audit/x
    git -C "$m" worktree add -q "$w" feat/s1
    mkdir -p "$w/.claude"
    mv "$m/.claude/.loop-record.json" "$w/.claude/.loop-record.json"
    [[ ! -f "$m/.claude/.tdd-unfrozen" ]] || mv "$m/.claude/.tdd-unfrozen" "$w/.claude/.tdd-unfrozen"
}

# PW1-PW9 (agent-ia-trial-fixes item 1): a Python case runs from its whole `def` header (wrapped over
# several lines, closed by the `:` at bracket depth 0) through its body. EcoCrew 2.2 U1/B352: the
# rows freeze ended the case at `) -> None:`, so a body edit under an unfreeze was "outside every case",
# and the insertion path took the body for module level.
run_pw_cases() {
    local tmp p addon pw_body
    tmp="$(mktemp -d)"
    addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"
    pw() {
        rv2_pair "$addon" tdd-freeze-tests-py.py "$1" "$(jq -cn --arg f "$1/tests/services/test_b.py" --arg c "$1" \
            --arg o "$2" --arg n "$3" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')"
    }
    # pw_rows <dir> <listed ids|-> <file lines>...: lp_py_project (record row B2, moi) with test_b.py
    # replaced by <file lines> and `.tdd-unfrozen` listing <listed ids> (none with -).
    pw_rows() {
        local d="$1" ids="$2"
        shift 2
        lp_py_project "$d"
        printf '%s\n' "$@" >"$d/tests/services/test_b.py"
        if [[ "$ids" == - ]]; then
            rm -f "$d/.claude/.tdd-unfrozen"
        else
            printf '%s\n' "tests/services/test_b.py  # $ids: r" >"$d/.claude/.tdd-unfrozen"
        fi
    }
    # pw_plain <dir> <file lines>...: the same file frozen whole (no record, no list): insertion rules.
    pw_plain() {
        local d="$1"
        shift
        lp_py_project "$d"
        rm -f "$d/.claude/.loop-record.json" "$d/.claude/.tdd-unfrozen"
        printf '%s\n' "$@" >"$d/tests/services/test_b.py"
    }
    local -a wrapped=('from app.services.b import g' '' '' 'async def test_b1_restores_all(' '    db: object,' \
        ') -> None:' '    full = 12.5' '    assert g(full) == 1' '' '' 'def test_b2_returns_err():' '    assert g(0) == 0')
    pw_body=$'    full = 12.5\n    assert g(full) == 1'

    p="$tmp/pw1"; pw_rows "$p" B1 "${wrapped[@]}"
    pv_expect PW1 pass "$(pw "$p" "$pw_body" $'    full = 0.0\n    assert g(full) == 1')"
    p="$tmp/pw2"; pw_plain "$p" "${wrapped[@]}"
    pv_expect PW2 deny "$(pw "$p" '    assert g(full) == 1' $'    assert g(full) == 1\n    assert g(2) == 2')" "INSIDE a case"
    p="$tmp/pw3"; pw_rows "$p" - "${wrapped[@]}"
    pv_expect PW3 deny "$(pw "$p" "$pw_body" $'    full = 0.0\n    assert g(full) == 1')"
    p="$tmp/pw4"; pw_rows "$p" B1 "${wrapped[@]:0:8}" '' 'LIMIT = 3' '' "${wrapped[@]:10}"
    pv_expect PW4 deny "$(pw "$p" 'LIMIT = 3' 'LIMIT = 4')" "outside every case"
    p="$tmp/pw5"; pw_plain "$p" "${wrapped[@]}"
    pv_expect PW5 pass "$(pw "$p" '    assert g(0) == 0' $'    assert g(0) == 0\n\n\ndef test_b3_keeps_three():\n    assert g(3) == 3')"
    p="$tmp/pw6"; pw_rows "$p" B1 'from app.services.b import g' '' '' 'def test_b1_maps(' \
        '    opts: dict = {"a": (1, 2)},' ') -> dict[str, int]:' '    full = 12.5' '    assert g(full) == 1'
    pv_expect PW6 pass "$(pw "$p" "$pw_body" $'    full = 0.0\n    assert g(full) == 1')"
    p="$tmp/pw7"; pw_rows "$p" B1 'from app.services.b import g' '' '' 'def test_b1_parses(' \
        '    sep: str = "):",  # closes ) here: not' ') -> None:' '    full = 12.5' '    assert g(full) == 1'
    pv_expect PW7 pass "$(pw "$p" "$pw_body" $'    full = 0.0\n    assert g(full) == 1')"
    p="$tmp/pw8"; pw_rows "$p" B1 'import pytest' 'from app.services.b import g' '' '' '@pytest.mark.parametrize(' \
        '    "v", [1, 2],' ')' 'def test_b1_each(' '    v: int,' ') -> None:' '    full = 12.5' '    assert g(full) == 1' \
        '' '' 'class TestB:' '    def test_b3_returns_err(' '        self,' '    ) -> None:' '        assert g(0) == 0'
    pv_expect PW8 pass "$(pw "$p" "$pw_body" $'    full = 0.0\n    assert g(full) == 1')"
    pv_expect PW8.2 deny "$(pw "$p" '    "v", [1, 2],' '    "v", [1, 3],')"
    printf '%s\n' 'tests/services/test_b.py  # B3: r' >"$p/.claude/.tdd-unfrozen"
    pv_expect PW8.3 pass "$(pw "$p" '        assert g(0) == 0' '        assert g(0) == -1')"
    p="$tmp/pw9"; pw_rows "$p" B1 'from app.services.b import g' '' '' 'async def test_b1_one() -> None:' \
        '    full = 12.5' '    assert g(full) == 1' '' '' 'class TestB:' '    def test_b2_returns_err(self) -> None:' \
        '        assert g(0) == 0'
    pv_expect PW9 pass "$(pw "$p" "$pw_body" $'    full = 0.0\n    assert g(full) == 1')"
    pv_expect PW9.2 deny "$(pw "$p" '        assert g(0) == 0' '        assert g(0) == -1')" "B2"
    p="$tmp/pw9u"; pw_rows "$p" B2 'from app.services.b import g' '' '' 'def test_b1_open(' '    v: int,' \
        '    full = 12.5' '    assert g(full) == 1'
    pv_expect PW9.3 deny "$(pw "$p" '    assert g(full) == 1' '    assert g(full) == 2')" "B1"
    unset -f pw pw_rows pw_plain
    rm -rf "$tmp"
}

# LP33-LP44, LP50 (loop-to-pr step 5): a path with rows in the tree's valid record is not exempted
# whole; each case an edit touches must be a row whose new title hashes to it, or an id listed on a
# `.tdd-unfrozen` line for the path.
run_loop_to_pr_step5_cases() {
    local tmp p x='src/a/x.utils.test.ts' h rows u2 u2new u3 u3new py addon out body
    tmp="$(mktemp -d)"
    addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"
    h='9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5'
    rows="$(jq -cn --arg p "$x" --arg h "$h" '[{path: $p, id: "U2", sha256: $h}]')"
    u2="  it('U2 returns err', () => {"$'\n''    expect(f(0)).toBe(0)'$'\n''  })'
    u2new="  it('U2 returns err on empty input', () => {"$'\n''    expect(f(0)).toBe(-1)'$'\n''  })'
    u3="  it('U3 keeps three', () => {"$'\n''    expect(f(3)).toBe(3)'$'\n''  })'
    u3new="  it('U3 keeps three', () => {"$'\n''    expect(f(3)).toBe(4)'$'\n''  })'

    p="$tmp/rows"; lp_freeze_project "$p" feat/s1 "$rows" "$x  # U2: empty input is an error"
    lp_freeze LP33 pass "$p" Edit "$(jq -cn --arg o "$u2" --arg n "$u2new" '{old_string:$o, new_string:$n}')"
    lp_freeze LP34 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "${u2new/ input/}" \
        '{old_string:$o, new_string:$n}')" "$h"
    lp_freeze LP34.2 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "${u2new/ input/}" \
        '{old_string:$o, new_string:$n}')" "U2"
    lp_freeze LP35 deny "$p" Edit "$(jq -cn --arg o "$u2"$'\n\n'"$u3" --arg n "$u2new"$'\n\n'"$u3new" \
        '{old_string:$o, new_string:$n}')" "U3"
    lp_freeze LP36 deny "$p" Edit "$(jq -cn --arg o $'    expect(f(1)).toBe(1)\n  })\n\n  it(\'U2 returns err\'' \
        --arg n $'    expect(f(1)).toBe(2)\n  })\n\n  it(\'U2 returns err on empty input\'' \
        '{old_string:$o, new_string:$n}')" "U1"
    lp_freeze LP37 deny "$p" Write "$(jq -cn --arg c "$(sed "s/U2 returns err'/U2 returns err on empty input'/" \
        "$p/$x")"$'\n' '{content:$c}')" "Edit"
    lp_freeze LP38 pass "$p" Write "$(jq -cn --rawfile c "$p/$x" '{content:$c}')"
    lp_freeze LP39 pass "$p" Edit "$(jq -cn --arg o $'  })\n})' \
        --arg n $'  })\n\n  it(\'U9 adds nine\', () => {\n    expect(f(9)).toBe(9)\n  })\n})' \
        '{old_string:$o, new_string:$n}')"
    body=$'\n''    expect(f(0)).toBe(-1)'$'\n''  })'
    lp_freeze LP50 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "  it(\`U2 returns err on empty input\`, () => {$body" \
        '{old_string:$o, new_string:$n}')" "U2"
    lp_freeze LP50.2 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "  it('U2 returns err on empty \\'input\\'', () => {$body" \
        '{old_string:$o, new_string:$n}')" "U2"
    lp_freeze LP50.3 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "  it(\"U2 it's empty\", () => {$body" \
        '{old_string:$o, new_string:$n}')" "U2"

    # LP50.4-LP50.5: the row's digest is the raw title as written, so only the refusal of an escape
    # or a quote inside the title (not a hash mismatch) denies; the needle names that refusal.
    local raw2="U2 returns err on empty \\'input\\'" raw3="U2 it's empty"
    p="$tmp/esc"; lp_freeze_project "$p" feat/s1 "$(jq -cn --arg p "$x" --arg h "$(printf '%s' "$raw2" | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U2", sha256: $h}]')" "$x  # U2: reason"
    lp_freeze LP50.4 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "  it('$raw2', () => {$body" \
        '{old_string:$o, new_string:$n}')" "not a plain-quoted literal"
    p="$tmp/quote"; lp_freeze_project "$p" feat/s1 "$(jq -cn --arg p "$x" --arg h "$(printf '%s' "$raw3" | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U2", sha256: $h}]')" "$x  # U2: reason"
    lp_freeze LP50.5 deny "$p" Edit "$(jq -cn --arg o "$u2" --arg n "  it(\"$raw3\", () => {$body" \
        '{old_string:$o, new_string:$n}')" "not a plain-quoted literal"

    # LP50.6-LP50.8: an apostrophe in a comment or a regex literal of the U2 body must not stretch its
    # span over U3; the comment is skipped, and a span that never closes is refused.
    local u2c u2cnew head3 rowsnow
    rowsnow="$(jq -cn --arg p "$x" --arg h "$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U2", sha256: $h}]')"
    u2c="  it('U2 returns err', () => {"$'\n''    /* don'"'"'t retry */'$'\n''    expect(f(0)).toBe(0)'$'\n''  })'
    u2cnew="  it('U2 returns err on empty input', () => {"$'\n''    /* don'"'"'t retry */'$'\n''    expect(f(0)).toBe(-1)'$'\n''  })'
    head3=$'  it(\'U1 returns one\', () => {\n    expect(f(1)).toBe(1)\n  })\n\n'
    p="$tmp/cmt"; lp_freeze_project "$p" feat/s1 "$rowsnow" "$x  # U2: empty input is an error"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "${head3%$'\n\n'}" '' "$u2c" '' "$u3" '})' >"$p/$x"
    lp_freeze LP50.6 deny "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')" "U3"
    p="$tmp/cmt2"; lp_freeze_project "$p" feat/s1 "$rows" "$x  # U2: empty input is an error"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "${head3%$'\n\n'}" '' "$u2c" '' "$u3" '})' >"$p/$x"
    lp_freeze LP50.8 pass "$p" Edit "$(jq -cn --arg o "$u2c" --arg n "$u2cnew" '{old_string:$o, new_string:$n}')"
    p="$tmp/rgx"; lp_freeze_project "$p" feat/s1 "$rowsnow" "$x  # U2: empty input is an error"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "${head3%$'\n\n'}" '' \
        "  it('U2 returns err', () => {" "    const re = /it's/" '    expect(f(0)).toBe(0)' '  })' '' "$u3" '})' >"$p/$x"
    lp_freeze LP50.7 deny "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')" "never closes"

    # LP51-LP51.2 (N1): a nested repository's own `.tdd-unfrozen` line unfreezes nothing; only the project
    # dir's list (and a worktree of it, LP33.2) does.
    p="$tmp/nest"; lp_freeze_project "$p" - '[]' ''
    local nest="$p/libs/core"
    mkdir -p "$nest/.claude" "$nest/src/a"
    git init -q "$nest"
    cp "$p/$x" "$nest/$x"
    printf '%s\n' "$x  # U2: r" >"$nest/.claude/.tdd-unfrozen"
    out="$(project_hook_probe tdd-freeze-tests.sh "$p" "$(jq -cn --arg f "$nest/$x" --arg c "$nest" --arg o "$u3" --arg n "$u3new" \
        '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    pv_expect LP51 deny "$out" "unfreeze-queue.md"

    # LP52-LP52.4 (C3b, N2): a `/` that could open a regex literal makes its case ambiguous; an ambiguous
    # case before or inside the edit refuses rows mode, one wholly after the edit does not.
    lp_c3b LP52 deny "$tmp/c3a" U2 'U2 returns err' "expect(f(0)).toThrow(/can't/)" "expect(f(3)).toThrow(/won't/)" - \
        "    expect(f(3)).toThrow(/won't/)" "    expect(f(3)).toThrow(/will not/)" "ambiguous"
    lp_c3b LP52.2 deny "$tmp/c3e" U2 'U2 returns err' "expect(f(0)).toThrow(/can't/)" 'expect(f(3)).toBe(3)' \
        "  it('U4 notes', () => {
    // the parser won't see this
    expect(f(4)).toBe(4)
  })" '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(99)' "ambiguous"
    lp_c3b LP52.3 deny "$tmp/c3g" U2 'U2 returns err' 'expect(f(0)).toMatch(/^https:\/\//)' 'expect(f(3)).toBe(3)' - \
        '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(99)' "unfreeze-queue.md"
    lp_c3b LP52.4 pass "$tmp/c3n" U1 'U1 returns one' 'expect(f(0)).toBe(0)' "expect(f(3)).toThrow(/can't/)" - \
        '    expect(f(1)).toBe(1)' '    expect(f(1)).toBe(2)'

    p="$tmp/batch"; lp_freeze_project "$p" feat/s1 "$rows" "$x  # U2: empty input is an error"$'\n'"$x  # U5: batch"
    printf '%s\n' "  it('U5 keeps five', () => {" '    expect(f(5)).toBe(5)' '  })' '})' >>"$p/$x.tail"
    python3 -I -c 'import sys; p = sys.argv[1]; t = open(p).read(); open(p, "w").write(t[:t.rindex("})")] + open(p + ".tail").read())' "$p/$x"
    rm -f "$p/$x.tail"
    lp_freeze LP40 pass "$p" Edit "$(jq -cn --arg o $'    expect(f(5)).toBe(5)' --arg n $'    expect(f(5)).toBe(6)' \
        '{old_string:$o, new_string:$n}')"
    lp_freeze LP40.2 deny "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')" "U3"

    p="$tmp/norow"
    lp_freeze_project "$p" feat/s1 "$(jq -cn --arg h "$h" '[{path: "src/b/y.utils.test.ts", id: "U2", sha256: $h}]')" \
        "$x  # U2: r"
    lp_freeze LP42 pass "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')"
    p="$tmp/norec"; lp_freeze_project "$p" - '[]' "$x  # U2: r"
    lp_freeze LP42.2 pass "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')"

    p="$tmp/nohash"; lp_freeze_project "$p" - '[]' "$x reason without a hash sign"
    lp_freeze LP43 pass "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')"
    printf '%s\n' 'src/a/y.utils.ts  # U1: rename' 'src/a/z.utils.ts reason without a hash sign' >"$p/.claude/.tdd-unfrozen"
    for py in y z; do
        out="$(project_hook_probe tdd-require-red.sh "$p" "$(jq -cn --arg f "$p/src/a/$py.utils.ts" \
            '{tool_name:"Write", tool_input:{file_path:$f, content:"export const y = 1\n"}}')")"
        pv_expect "LP43 require-red $py" pass "$out"
    done

    p="$tmp/plain"; lp_freeze_project "$p" - '[]' ''
    lp_freeze LP44 deny "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')" \
        "unfreeze-queue.md" "confirms it at the merge"
    lp_freeze LP44.2 deny "$p" Edit "$(jq -cn --arg o $'  })\n})' --arg n $'  })\n  return\n})' \
        '{old_string:$o, new_string:$n}')" "unfreeze-queue.md" "confirms it at the merge"

    # LP33.2: a pass entered by path works in a worktree whose record and `.tdd-unfrozen` line are its
    # own; the project dir is the main tree, which holds neither.
    p="$tmp/wtmain"; lp_freeze_project "$p" feat/s1 "$rows" "$x  # U2: empty input is an error"
    lp_worktree "$p"
    out="$(project_hook_probe tdd-freeze-tests.sh "$p" "$(jq -cn --arg f "$p/.claude/worktrees/s1/$x" --arg c "$p/.claude/worktrees/s1" \
        --arg o "$u2" --arg n "$u2new" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    pv_expect LP33.2 pass "$out"
    out="$(project_hook_probe tdd-freeze-tests.sh "$p" "$(jq -cn --arg f "$p/.claude/worktrees/s1/$x" --arg c "$p/.claude/worktrees/s1" \
        --arg o "$u3" --arg n "$u3new" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    pv_expect LP33.3 deny "$out" "U3"

    # LP30.4-LP30.5: on the base branch the record holds only while its base commit is an ancestor of
    # HEAD. Valid: rows mode denies the U3 edit. The base rewritten: no record, the whole-file line applies.
    p="$tmp/basevalid"; lp_freeze_project "$p" feat/s1 "$rows" "$x  # U2: empty input is an error"
    git -C "$p" switch -q audit/x
    lp_freeze LP30.4 deny "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')" "U3"
    git -C "$p" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --amend --allow-empty -m rewritten
    lp_freeze LP30.5 pass "$p" Edit "$(jq -cn --arg o "$u3" --arg n "$u3new" '{old_string:$o, new_string:$n}')"

    p="$tmp/py"
    lp_unfrozen_repo "$p" feat/s1 "$(jq -cn \
        '[{path: "tests/services/test_b.py", id: "B2", sha256: "e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b"}]')"
    pv_addon_project "$p"
    mkdir -p "$p/tests/services"
    printf '%s\n' 'from app.services.b import g' '' '' 'def test_b1_returns_ok():' '    assert g(1) == 1' '' '' \
        'def test_b2_returns_err():' '    assert g(0) == 0' >"$p/tests/services/test_b.py"
    printf '%s\n' 'tests/services/test_b.py  # B2: empty input is an error' >"$p/.claude/.tdd-unfrozen"
    py() {
        rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_b.py" --arg c "$p" \
            --arg o "$1" --arg n "$2" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')"
    }
    pv_expect LP41 pass "$(py $'def test_b2_returns_err():\n    assert g(0) == 0' \
        $'def test_b2_returns_err_on_empty():\n    assert g(0) == -1')"
    pv_expect LP41.2 deny "$(py $'def test_b2_returns_err():\n    assert g(0) == 0' \
        $'def test_b2_returns_err_on_empt():\n    assert g(0) == -1')" "B2"
    pv_expect LP41.3 deny "$(py $'    assert g(1) == 1\n\n\ndef test_b2_returns_err():' \
        $'    assert g(1) == 2\n\n\ndef test_b2_returns_err_on_empty():')" "B1"
    out="$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_b.py" --arg c "$p" \
        '{tool_name:"Write", cwd:$c, tool_input:{file_path:$f, content:"def test_b2_returns_err_on_empty():\n    assert 1\n"}}')")"
    pv_expect LP41.4 deny "$out" "Edit"
    printf '%s\n' 'tests/services/test_b.py reason without a hash sign' >"$p/.claude/.tdd-unfrozen"
    rm -f "$p/.claude/.loop-record.json"
    pv_expect LP43.py pass "$(py $'    assert g(1) == 1' $'    assert g(1) == 2')"
    rm -f "$p/.claude/.tdd-unfrozen"
    pv_expect LP44.py deny "$(py $'    assert g(1) == 1' $'    assert g(1) == 2')" \
        "unfreeze-queue.md" "confirms it at the merge"
    unset -f py

    pyw() {
        rv2_pair "$addon" tdd-freeze-tests-py.py "$1" "$(jq -cn --arg f "$2" --arg c "$1" --arg o "$3" --arg n "$4" \
            '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')"
    }
    local b2 b2new b1 b1new
    b2=$'def test_b2_returns_err():\n    assert g(0) == 0'
    b2new=$'def test_b2_returns_err_on_empty():\n    assert g(0) == -1'
    b1=$'    assert g(1) == 1'
    b1new=$'    assert g(1) == 2'
    p="$tmp/pywt"; lp_py_project "$p"
    lp_worktree "$p"
    pv_expect LP41.5 pass "$(pyw "$p" "$p/.claude/worktrees/s1/tests/services/test_b.py" "$b2" "$b2new")"
    pv_expect LP41.6 deny "$(pyw "$p" "$p/.claude/worktrees/s1/tests/services/test_b.py" "$b1" "$b1new")" "B1"
    p="$tmp/pybase"; lp_py_project "$p"
    git -C "$p" switch -q audit/x
    pv_expect LP30.6 deny "$(pyw "$p" "$p/tests/services/test_b.py" "$b1" "$b1new")" "B1"
    git -C "$p" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --amend --allow-empty -m rewritten
    pv_expect LP30.7 pass "$(pyw "$p" "$p/tests/services/test_b.py" "$b1" "$b1new")"
    p="$tmp/pynest"; lp_py_project "$p"
    rm -f "$p/.claude/.tdd-unfrozen" "$p/.claude/.loop-record.json"
    local pn="$p/libs/core"
    mkdir -p "$pn/.claude" "$pn/tests/services"
    git init -q "$pn"
    cp "$p/tests/services/test_b.py" "$pn/tests/services/test_b.py"
    printf '%s\n' 'tests/services/test_b.py  # B2: r' >"$pn/.claude/.tdd-unfrozen"
    pv_expect LP51.2 deny "$(pyw "$p" "$pn/tests/services/test_b.py" "$b1" "$b1new")" "unfreeze-queue.md"
    unset -f pyw
    rm -rf "$tmp"
}

# lp_pr_shim <dir>: a gh whose `pr view <branch>` prints <dir>/gh/pr-<branch, / as _>.json, or exits
# with <dir>/gh/pr-<b>.exit and its .err on stderr; with no file, "no pull requests found" and exit 1.
lp_pr_shim() {
    mkdir -p "$1/bin" "$1/gh"
    cat >"$1/bin/gh" <<'SH'
#!/usr/bin/env bash
d="${LP_SHIM:?}"
[[ ! -f "$d/fail" ]] || { printf 'gh: HTTP 502\n' >&2; exit 1; }
if [[ "${1:-}" == repo && "${2:-}" == view ]]; then cat "$d/repo.json"; exit 0; fi
if [[ "${1:-}" == pr && "${2:-}" == view ]]; then
    b="${3:-}"; b="${b//\//_}"
    if [[ -f "$d/pr-$b.exit" ]]; then cat "$d/pr-$b.err" >&2 2>/dev/null; exit "$(cat "$d/pr-$b.exit")"; fi
    if [[ -f "$d/pr-$b.json" ]]; then cat "$d/pr-$b.json"; exit 0; fi
    printf 'no pull requests found for branch "%s"\n' "$3" >&2
    exit 1
fi
exit 1
SH
    chmod +x "$1/bin/gh"
    printf '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}\n' >"$1/gh/repo.json"
}

# lp_pr <shim> <branch> <state> <base> [mergedAt]: one PR fixture.
lp_pr() {
    jq -cn --arg s "$3" --arg b "$4" --arg m "${5:-}" \
        '{state: $s, baseRefName: $b, mergedAt: (if $m == "" then null else $m end), number: 7}' \
        >"$1/gh/pr-${2//\//_}.json"
}

# lp_state <id> <shim> <want> <args…>: loop-pr-state.sh prints exactly <want> and exits 0.
lp_state() {
    local id="$1" shim="$2" want="$3" out code
    shift 3
    CASES=$((CASES + 1))
    set +e
    out="$(LP_SHIM="$shim/gh" PATH="$shim/bin:$PATH" "$PROJECT_ROOT/.claude/scripts/loop-pr-state.sh" "$@" 2>/dev/null)"
    code=$?
    set -e
    [[ "$code" -eq 0 && "$out" == "$want" ]] || fail loop-pr-state.sh "$id" "expected '$want' exit 0, got '$out' exit $code"
}

# LP45-LP47 (loop-to-pr step 6): the closing rule, one word per PR state.
run_loop_to_pr_step6_cases() {
    local tmp s m
    tmp="$(mktemp -d)"
    for m in merge squash rebase; do
        s="$tmp/$m"; lp_pr_shim "$s"; lp_pr "$s" feat/s1 MERGED main 2026-11-19T10:00:00Z
        lp_state "LP45 $m" "$s" closable feat/s1
    done

    s="$tmp/stack"; lp_pr_shim "$s"; lp_pr "$s" feat/s1 MERGED feat/a 2026-11-19T10:00:00Z
    lp_state LP46 "$s" stacked:feat/a feat/s1
    lp_pr "$s" feat/a MERGED main 2026-11-19T11:00:00Z
    lp_state LP46.2 "$s" closable --chain feat/s1
    lp_pr "$s" feat/a OPEN main
    lp_state LP46.3 "$s" open --chain feat/s1
    lp_pr "$s" feat/a MERGED main 2026-11-19T09:00:00Z
    lp_state LP46.4 "$s" orphaned:feat/a --chain feat/s1
    lp_pr "$s" feat/a MERGED feat/b 2026-11-19T11:00:00Z
    lp_pr "$s" feat/b MERGED main 2026-11-19T12:00:00Z
    lp_state LP46.5 "$s" closable --chain feat/s1
    lp_pr "$s" feat/b MERGED main 2026-11-19T10:30:00Z
    lp_state LP46.6 "$s" orphaned:feat/b --chain feat/s1

    s="$tmp/other"; lp_pr_shim "$s"
    lp_pr "$s" feat/s1 OPEN main
    lp_state LP47 "$s" open feat/s1
    lp_pr "$s" feat/s1 CLOSED main
    lp_state LP47.2 "$s" closed feat/s1
    lp_state LP47.3 "$s" none feat/s9
    : >"$s/gh/fail"
    lp_state LP47.4 "$s" unknown feat/s1
    rm -f "$s/gh/fail"
    printf '4\n' >"$s/gh/pr-feat_s1.exit"; printf 'gh: To get started with GitHub CLI, please run:  gh auth login\n' >"$s/gh/pr-feat_s1.err"
    lp_state LP47.5 "$s" unknown feat/s1
    mkdir -p "$tmp/nogh"
    for m in jq git bash env cat; do ln -sf "$(command -v "$m")" "$tmp/nogh/$m"; done
    CASES=$((CASES + 1))
    s="$(PATH="$tmp/nogh" "$PROJECT_ROOT/.claude/scripts/loop-pr-state.sh" feat/s1 2>/dev/null)" || true
    [[ "$s" == unknown ]] || fail loop-pr-state.sh LP47.6 "gh absent: expected 'unknown', got '$s'"
    rm -rf "$tmp"
}

# LP48 (loop-to-pr hash producer): case-hash.sh prints the sha256 of its one argument, nothing
# else; any other arity exits 2 with an empty stdout; it writes no file.
run_loop_to_pr_hash_cases() {
    local tmp out code n
    tmp="$(mktemp -d)"
    CASES=$((CASES + 1))
    out="$(cd "$tmp" && "$PROJECT_ROOT/.claude/scripts/case-hash.sh" 'U2 returns err on empty input' </dev/null 2>/dev/null)" || true
    [[ "$out" == 9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5 ]] \
        || fail case-hash.sh LP48 "expected the row digest, got '$out'"
    CASES=$((CASES + 1))
    out="$(cd "$tmp" && "$PROJECT_ROOT/.claude/scripts/case-hash.sh" 'U7 keeps $HOME `x` \n' </dev/null 2>/dev/null)" || true
    [[ "$out" == "$(printf '%s' 'U7 keeps $HOME `x` \n' | sha256sum | cut -c1-64)" ]] \
        || fail case-hash.sh LP48.2 "a title with \$, backtick and backslash is hashed as written, got '$out'"
    for n in 0 2; do
        CASES=$((CASES + 1))
        set +e
        if [[ "$n" == 0 ]]; then
            out="$(cd "$tmp" && "$PROJECT_ROOT/.claude/scripts/case-hash.sh" </dev/null 2>/dev/null)"
        else
            out="$(cd "$tmp" && "$PROJECT_ROOT/.claude/scripts/case-hash.sh" a b </dev/null 2>/dev/null)"
        fi
        code=$?
        set -e
        [[ "$code" -eq 2 && -z "$out" ]] || fail case-hash.sh "LP48.$((n + 3))" "$n arguments: expected exit 2 and no stdout, got exit $code '$out'"
    done
    CASES=$((CASES + 1))
    [[ -z "$(ls -A "$tmp")" ]] || fail case-hash.sh LP48.6 "it wrote '$(ls -A "$tmp")'"
    rm -rf "$tmp"
}

# LP53-LP58 (loop-to-pr review round 3): M1 (division, JSX and `=>` no longer ambiguous; a marker line
# `<path>  # <id>!: <reason>` lifts an ambiguous case, and still asks), S2 (a quote crossing a newline in a
# .tsx), TM1 (a nested repo's own record and list; a worktree list naming a file with no rows), S3 (a
# cleared record leaves no row-backed whole-file exemption).
run_loop_to_pr_review3_cases() {
    local tmp p x='src/a/x.utils.test.ts' xt='src/a/x.utils.test.tsx' out h3 row3 nest pn b1 b1new
    local addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"
    tmp="$(mktemp -d)"
    h3="$(printf '%s' 'U3 keeps three' | sha256sum | cut -c1-64)"
    row3="$(jq -cn --arg p "$x" --arg h "$h3" '[{path: $p, id: "U3", sha256: $h}]')"

    # LP53-LP53.2: a division, a self-closing JSX tag and a closing tag open no regex literal.
    lp_c3b LP53 pass "$tmp/m1a" U3 'U3 keeps three' 'expect(f(4) / 2).toBe(2)' 'render(<F />)' - \
        '    render(<F />)' '    render(<G />)'
    lp_c3b LP53.2 pass "$tmp/m1b" U3 'U3 keeps three' 'render(<p>hi</p>)' 'render(<F />)' - \
        '    render(<F />)' '    render(<G />)'
    # LP53.3-LP53.4: a `/` after `=>` or `return` still can, so those cases stay ambiguous.
    lp_c3b LP53.3 deny "$tmp/m1c" U3 'U3 keeps three' 'const g = () => /ab/' 'expect(f(3)).toBe(3)' - \
        '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(4)' "ambiguous"
    lp_c3b LP53.4 deny "$tmp/m1d" U3 'U3 keeps three' 'const g = () => { return /ab/ }' 'expect(f(3)).toBe(3)' - \
        '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(4)' "ambiguous"

    # LP54-LP54.4 (LP54, LP54.2 amended round 6, U2 U3: the lift is removed): the deny names --clear; a
    # `U2!` line lifts nothing (a regex holding quotes); that line asks; a case that does not close stays refused.
    lp_c3b LP54 deny "$tmp/lift" U3 'U3 keeps three' "expect(f(0)).toThrow(/'x'/)" 'expect(f(3)).toBe(3)' - \
        '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(4)' 'blocked stop (record kept)'
    p="$tmp/lift2"
    lp_freeze_project "$p" feat/s1 "$row3" "$x  # U3: r"$'\n'"$x  # U2!: the quotes of its regex are balanced"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U1 returns one', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => {" "    expect(f(0)).toThrow(/'x'/)" '  })' '' \
        "  it('U3 keeps three', () => {" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$x"
    lp_freeze LP54.2 deny "$p" Edit "$(jq -cn --arg o '    expect(f(3)).toBe(3)' --arg n '    expect(f(3)).toBe(4)' \
        '{old_string:$o, new_string:$n}')" 'blocked stop (record kept)'
    p="$tmp/liftask"
    lp_unfrozen_repo "$p" feat/s1 "$(jq -cn --arg p "$x" --arg h "$h3" '[{path: $p, id: "U2", sha256: $h}]')"
    printf '%s\n' "$x  # U2: r" >"$p/.claude/.tdd-unfrozen"
    unfrozen_case LP54.3 ask Edit "$(jq -cn --arg o "$x  # U2: r" --arg n "$x  # U2: r"$'\n'"$x  # U2!: r" \
        '{old_string:$o, new_string:$n}')" "$p"
    p="$tmp/liftopen"
    lp_freeze_project "$p" feat/s1 "$row3" "$x  # U3: r"$'\n'"$x  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    const re = /it's/" '    expect(f(0)).toBe(0)' '  })' '' \
        "  it('U3 keeps three', () => {" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$x"
    lp_freeze LP54.4 deny "$p" Edit "$(jq -cn --arg o '    expect(f(3)).toBe(3)' --arg n '    expect(f(3)).toBe(4)' \
        '{old_string:$o, new_string:$n}')" "never closes"

    # LP55 (S2): in a .tsx, an apostrophe in JSX text opens a string that runs to the apostrophe of a later
    # comment; a string crossing a newline makes its case ambiguous, so the edit of U3 is refused.
    p="$tmp/tsx"
    lp_freeze_project "$p" feat/s1 "$(jq -cn --arg p "$xt" --arg h "$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U2", sha256: $h}]')" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    render(<p>L'adresse</p>)" '  })' '' \
        "  it('U3 keeps three', () => {" "    // the user's input" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$xt"
    out="$(project_hook_probe tdd-freeze-tests.sh "$p" "$(jq -cn --arg f "$p/$xt" --arg c "$p" \
        --arg o '    expect(f(3)).toBe(3)' --arg n '    expect(f(3)).toBe(99)' \
        '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    pv_expect LP55 deny "$out" "ambiguous"

    # LP56 (TM1, kills the tree-test mutants): a nested repository holding its own valid record, its rows and
    # a listed extra id unfreezes nothing; the project dir's list is the only one read.
    p="$tmp/nest3"; lp_freeze_project "$p" - '[]' ''
    nest="$p/libs/core"
    lp_unfrozen_repo "$nest" feat/s1 "$(jq -cn --arg p "$x" --arg h "$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U2", sha256: $h}]')"
    cp "$p/$x" "$nest/$x"
    printf '%s\n' "$x  # U2: r" "$x  # U3: the extra id" >"$nest/.claude/.tdd-unfrozen"
    out="$(project_hook_probe tdd-freeze-tests.sh "$p" "$(jq -cn --arg f "$nest/$x" --arg c "$nest" \
        --arg o '    expect(f(3)).toBe(3)' --arg n '    expect(f(3)).toBe(99)' \
        '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    pv_expect LP56 deny "$out" unfreeze-queue.md 'rows mode'

    # LP57 (TM1, kills the worktree-exemption mutants): a worktree's own list naming a file the record holds
    # no row for is rows-mode entry only, never a whole-file exemption.
    p="$tmp/wtnorow"
    lp_freeze_project "$p" feat/s1 "$(jq -cn --arg h "$h3" '[{path: "src/b/y.utils.test.ts", id: "U2", sha256: $h}]')" \
        "$x  # U2: r"
    lp_worktree "$p"
    out="$(project_hook_probe tdd-freeze-tests.sh "$p" "$(jq -cn --arg f "$p/.claude/worktrees/s1/$x" \
        --arg c "$p/.claude/worktrees/s1" --arg o '    expect(f(3)).toBe(3)' --arg n '    expect(f(3)).toBe(99)' \
        '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    pv_expect LP57 deny "$out" unfreeze-queue.md 'rows mode'

    # LP58 (S3): `--clear` drops the record, and the row-backed line goes with it instead of turning into a
    # whole-file exemption; a line that is no row stays.
    p="$tmp/cleared"
    lp_freeze_project "$p" feat/s1 "$(jq -cn --arg p "$x" --arg h "$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U2", sha256: $h}]')" "$x  # U2: r"$'\n''src/z/other.test.ts  # a plain line'
    set +e
    (cd "$p" && "$LP_HOOK" --clear </dev/null >/dev/null 2>&1)
    set -e
    lp_freeze LP58 deny "$p" Edit "$(jq -cn --arg o '    expect(f(3)).toBe(3)' --arg n '    expect(f(3)).toBe(99)' \
        '{old_string:$o, new_string:$n}')" unfreeze-queue.md 'rows mode'
    CASES=$((CASES + 1))
    [[ "$(<"$p/.claude/.tdd-unfrozen")" == "# $x  # U2: r"$'\n''src/z/other.test.ts  # a plain line' ]] \
        || fail loop-record.py LP58.3 "after --clear the row-backed line is commented out and the plain line kept, got '$(<"$p/.claude/.tdd-unfrozen")'"

    b1=$'    assert g(1) == 1'
    b1new=$'    assert g(1) == 2'
    lp3_pyw() {
        rv2_pair "$addon" tdd-freeze-tests-py.py "$1" "$(jq -cn --arg f "$2" --arg c "$1" --arg o "$b1" --arg n "$b1new" \
            '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')"
    }
    # LP56.2, LP57.2, LP58.2: the same three, python freeze.
    p="$tmp/pynest3"; lp_py_project "$p"
    rm -f "$p/.claude/.tdd-unfrozen" "$p/.claude/.loop-record.json"
    pn="$p/libs/core"
    lp_unfrozen_repo "$pn" feat/s1 "$(jq -cn \
        '[{path: "tests/services/test_b.py", id: "B2", sha256: "e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b"}]')"
    cp "$p/tests/services/test_b.py" "$pn/tests/services/test_b.py"
    printf '%s\n' 'tests/services/test_b.py  # B2: r' 'tests/services/test_b.py  # B1: the extra id' >"$pn/.claude/.tdd-unfrozen"
    pv_expect LP56.2 deny "$(lp3_pyw "$p" "$pn/tests/services/test_b.py")" unfreeze-queue.md 'rows mode'

    p="$tmp/pywtnorow"
    lp_unfrozen_repo "$p" feat/s1 "$(jq -cn \
        '[{path: "tests/services/test_c.py", id: "B2", sha256: "e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b"}]')"
    pv_addon_project "$p"
    mkdir -p "$p/tests/services"
    printf '%s\n' 'from app.services.b import g' '' '' 'def test_b1_returns_ok():' '    assert g(1) == 1' '' '' \
        'def test_b2_returns_err():' '    assert g(0) == 0' >"$p/tests/services/test_b.py"
    printf '%s\n' 'tests/services/test_b.py  # B2: r' >"$p/.claude/.tdd-unfrozen"
    lp_worktree "$p"
    pv_expect LP57.2 deny "$(lp3_pyw "$p" "$p/.claude/worktrees/s1/tests/services/test_b.py")" unfreeze-queue.md 'rows mode'

    p="$tmp/pycleared"; lp_py_project "$p"
    set +e
    (cd "$p" && "$LP_HOOK" --clear </dev/null >/dev/null 2>&1)
    set -e
    pv_expect LP58.2 deny "$(lp3_pyw "$p" "$p/tests/services/test_b.py")" unfreeze-queue.md 'rows mode'
    unset -f lp3_pyw
    rm -rf "$tmp"
}

# LP58.4-LP61.10 (loop-to-pr review round 4): N1/S4 (a case whose raw span holds another `it(`, or whose
# brackets do not nest, is ambiguous and no `U2!` marker lifts it), N2 (the `!` marker line goes with the
# record), T8 (the PR-url drop comments the row-backed line out), T5 (the regex-start tokens and the
# quote-newline rule, each pinned by a case).
run_loop_to_pr_review4_cases() {
    local tmp p x='src/a/x.utils.test.ts' xt='src/a/x.utils.test.tsx' out h2 row2 rowt bt='`' want rec sh
    local o3='    expect(f(3)).toBe(3)' n3='    expect(f(3)).toBe(99)'
    local addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"
    tmp="$(mktemp -d)"
    h2="$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)"
    row2="$(jq -cn --arg p "$x" --arg h "$h2" '[{path: $p, id: "U2", sha256: $h}]')"
    rowt="$(jq -cn --arg p "$xt" --arg h "$h2" '[{path: $p, id: "U2", sha256: $h}]')"
    # lp4_edit <id> <verdict> <dir> <path> <old> <new> [needle]: tdd-freeze-tests.sh on <dir>/<path>.
    lp4_edit() {
        out="$(project_hook_probe tdd-freeze-tests.sh "$3" "$(jq -cn --arg f "$3/$4" --arg c "$3" --arg o "$5" --arg n "$6" \
            '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
        pv_expect "$1" "$2" "$out" "${7:-}"
    }

    # LP59 (N1, liftA1): a regex holding an apostrophe in a lifted U2 swallows the next case; the marker
    # lifts nothing there, so the edit of U3 is refused.
    p="$tmp/a1"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    expect(f(0)).toThrow(/it's/)" '  })' '' \
        "  it('U3 keeps three', () => {" "    // the user's input" "$o3" '  })' '})' >"$p/$x"
    lp4_edit LP59 deny "$p" "$x" "$o3" "$n3" ambiguous
    # LP59.2 (N1, liftB): U2 last in its describe, rewritten into a regex with an unbalanced `\(` and a
    # `beforeEach` after it: the brackets do not nest, so the lift is refused.
    p="$tmp/b"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" '    expect(f(0)).toBe(0)' '  })' '})' >"$p/$x"
    lp4_edit LP59.2 deny "$p" "$x" $'    expect(f(0)).toBe(0)\n  })' \
        $'    expect(f(0)).toThrow(/\\(/)\n  })\n\n  beforeEach(() => {\n    reset()\n  })' ambiguous
    # LP59.3 (FP, round-5 amendment): a string of U2 holding `it(` no longer makes it ambiguous;
    # the Edit of non-listed U3 is still denied, as not listed.
    p="$tmp/rawit"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    const t = \"it('inner', () => {})\"" '    expect(f(0)).toBe(0)' '  })' '' \
        "  it('U3 keeps three', () => {" "$o3" '  })' '})' >"$p/$x"
    lp4_edit LP59.3 deny "$p" "$x" "$o3" "$n3" "neither a plan-gate row nor listed"

    # LP60 (S4): an unbalanced `(` in JSX text of a row case of a .tsx; the marker lifts nothing.
    p="$tmp/jsx"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"$'\n'"$xt  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" '    render(<p>Prix (HT</p>)' '  })' '' \
        "  it('U3 keeps three', () => {" "$o3" '  })' '})' >"$p/$xt"
    lp4_edit LP60 deny "$p" "$xt" "$o3" "$n3" ambiguous
    # LP60.2: the same case last in its describe, an Edit adding a describe-level beforeEach after it.
    p="$tmp/jsx2"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"$'\n'"$xt  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" '    render(<p>Prix (HT</p>)' '  })' '})' >"$p/$xt"
    lp4_edit LP60.2 deny "$p" "$xt" $'    render(<p>Prix (HT</p>)\n  })' \
        $'    render(<p>Prix (HT</p>)\n  })\n\n  beforeEach(() => {\n    reset()\n  })' ambiguous

    # LP61-LP61.4 (T5): a regex holding a backtick after `=`, at a line start, after `,` and after `:`, with
    # a backtick in the next case too: the case is ambiguous, the edit of U3 is refused.
    lp_c3b LP61 deny "$tmp/eq" U2 'U2 returns err' "const re = /$bt/" \
        "expect(f(3)).toBe(3)"$'\n'"    expect(s).toMatch(/$bt/)" - "$o3" "$n3" ambiguous
    lp_c3b LP61.2 deny "$tmp/nl" U2 'U2 returns err' "/$bt/.test(s)" \
        "expect(f(3)).toBe(3)"$'\n'"    expect(s).toMatch(/$bt/)" - "$o3" "$n3" ambiguous
    lp_c3b LP61.3 deny "$tmp/comma" U2 'U2 returns err' "expect(f(0, /$bt/)).toBe(0)" \
        "expect(f(3)).toBe(3)"$'\n'"    expect(s).toMatch(/$bt/)" - "$o3" "$n3" ambiguous
    lp_c3b LP61.4 deny "$tmp/colon" U2 'U2 returns err' "const o = { re: /$bt/ }" \
        "expect(f(3)).toBe(3)"$'\n'"    expect(s).toMatch(/$bt/)" - "$o3" "$n3" ambiguous
    # LP61.5: a double-quoted string crossing a line (backslash continuation) in a row case, quote-newline rule.
    lp_c3b LP61.5 deny "$tmp/dqnl" U2 'U2 returns err' $'const s = "a\\\n    b"' 'expect(f(3)).toBe(3)' - \
        "$o3" "$n3" ambiguous
    # LP61.6: a `"` in JSX text of a row case of a .tsx and another in a later comment.
    p="$tmp/dq"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" '    render(<p>5" screen</p>)' '  })' '' \
        "  it('U3 keeps three', () => {" '    // a 5" mark' "$o3" '  })' '})' >"$p/$xt"
    lp4_edit LP61.6 deny "$p" "$xt" "$o3" "$n3" ambiguous
    # LP61.7-LP61.10: the same four tokens with a plain regex, nothing else in the case that could mark it.
    lp_c3b LP61.7 deny "$tmp/eqp" U2 'U2 returns err' 'const re = /ab/' 'expect(f(3)).toBe(3)' - "$o3" "$n3" ambiguous
    lp_c3b LP61.8 deny "$tmp/nlp" U2 'U2 returns err' '/ab/.test(s)' 'expect(f(3)).toBe(3)' - "$o3" "$n3" ambiguous
    lp_c3b LP61.9 deny "$tmp/commap" U2 'U2 returns err' 'expect(f(0, /ab/)).toBe(0)' 'expect(f(3)).toBe(3)' - \
        "$o3" "$n3" ambiguous
    lp_c3b LP61.10 deny "$tmp/colonp" U2 'U2 returns err' 'const o = { re: /ab/ }' 'expect(f(3)).toBe(3)' - \
        "$o3" "$n3" ambiguous
    unset -f lp4_edit

    # LP58.4 (N2): `--clear` comments the row-backed `!` marker line out as well as the plain one.
    p="$tmp/clr"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U2!: r"
    set +e
    (cd "$p" && "$LP_HOOK" --clear </dev/null >/dev/null 2>&1)
    set -e
    CASES=$((CASES + 1))
    [[ "$(<"$p/.claude/.tdd-unfrozen")" == "# $x  # U2: r"$'\n'"# $x  # U2!: r" ]] \
        || fail loop-record.py LP58.4 "after --clear both lines are commented out, got '$(<"$p/.claude/.tdd-unfrozen")'"
    lp_freeze LP58.4 deny "$p" Edit "$(jq -cn --arg o "$o3" --arg n "$n3" '{old_string:$o, new_string:$n}')" \
        unfreeze-queue.md 'rows mode'
    # LP58.5: the same, python freeze.
    p="$tmp/pyclr"; lp_py_project "$p"
    printf '%s\n' 'tests/services/test_b.py  # B2: r' 'tests/services/test_b.py  # B2!: r' >"$p/.claude/.tdd-unfrozen"
    set +e
    (cd "$p" && "$LP_HOOK" --clear </dev/null >/dev/null 2>&1)
    set -e
    pv_expect LP58.5 deny "$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_b.py" \
        --arg c "$p" --arg o $'    assert g(1) == 1' --arg n $'    assert g(1) == 2' \
        '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")" unfreeze-queue.md 'rows mode'

    # LP58.6-LP58.7 (T8): the PR url drops the record, the row-backed line is commented out and the plain
    # line stays; an edit of the non-row U3 is then denied.
    p="$tmp/prurl"; sh="$tmp/sh"; lp_shim "$sh"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n''src/z/other.test.ts  # a plain line'
    rec="$p/.claude/.loop-record.json"
    lp_run "$(lp_bash "$p" 'gh pr create --repo o/r --base audit/x --head feat/s1 --title "Loop to PR" --body-file docs/work/s1/pr-body.md' \
        $'Creating pull request\nhttps://github.com/o/r/pull/7\n')" "$sh"
    CASES=$((CASES + 1))
    [[ "$LP_CODE" -eq 0 && ! -e "$rec" ]] || fail loop-record.py LP58.6 "record kept (exit $LP_CODE)"
    CASES=$((CASES + 1))
    [[ "$(<"$p/.claude/.tdd-unfrozen")" == "# $x  # U2: r"$'\n''src/z/other.test.ts  # a plain line' ]] \
        || fail loop-record.py LP58.6 "after the PR url the row-backed line is commented out, got '$(<"$p/.claude/.tdd-unfrozen")'"
    lp_freeze LP58.7 deny "$p" Edit "$(jq -cn --arg o "$o3" --arg n "$n3" '{old_string:$o, new_string:$n}')" \
        unfreeze-queue.md 'rows mode'
    rm -rf "$tmp"
}

# LP62-LP65.2 (loop-to-pr review round 5): FP (the raw it(/test( check is gone, benign shapes pass again),
# SC1 (a case whose character span runs past its indentation span is never lifted), N1p (the call-start
# pattern takes any member chain and a tagged table), TQ1 (the never-liftable deny text is pinned).
run_loop_to_pr_review5_cases() {
    local tmp p x='src/a/x.utils.test.ts' xt='src/a/x.utils.test.tsx' out h2 row2 rowt bt='`' old new
    local o0='    expect(f(0)).toBe(0)' n0='    expect(f(0)).toBe(1)'
    local lift_x lift_xt
    tmp="$(mktemp -d)"
    h2="$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)"
    row2="$(jq -cn --arg p "$x" --arg h "$h2" '[{path: $p, id: "U2", sha256: $h}]')"
    rowt="$(jq -cn --arg p "$xt" --arg h "$h2" '[{path: $p, id: "U2", sha256: $h}]')"
    lift_x="$x  # U2: r"$'\n'"$x  # U2!: r"
    lift_xt="$xt  # U2: r"$'\n'"$xt  # U2!: r"
    # lp5_edit <id> <verdict> <dir> <path> <old> <new> [needle] [absent]: tdd-freeze-tests.sh on <dir>/<path>.
    lp5_edit() {
        out="$(project_hook_probe tdd-freeze-tests.sh "$3" "$(jq -cn --arg f "$3/$4" --arg c "$3" --arg o "$5" --arg n "$6" \
            '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
        pv_expect "$1" "$2" "$out" "${7:-}" "${8:-}"
    }
    # lp5_fp <id> <path> <rows> <unfrozen> <U1 title> <U1 body>: U1 then the row case U2; Edit of U2 toBe(0)->toBe(1).
    lp5_fp() {
        local d="$tmp/${1//./_}"
        lp_freeze_project "$d" feat/s1 "$3" "$4"
        printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
            "  it('$5', () => {" "$6" '  })' '' \
            "  it('U2 returns err', () => {" "$o0" '  })' '})' >"$d/$2"
        lp5_edit "$1" pass "$d" "$2" "$o0" "$n0"
    }

    # LP62-LP62.8 (FP): a `(` in a title, a string or a comment above the row case, a JSX `[` or `1)`, no longer
    # refuses an edit of U2 (base verdict: pass); `U1!, U2!` listed passes as well.
    lp5_fp LP62 "$x" "$row2" "$x  # U2: r" 'U1 runs the test (twice)' '    expect(f(1)).toBe(1)'
    lp5_fp LP62.2 "$x" "$row2" "$x  # U2: r" 'U1 does it (once)' '    expect(f(1)).toBe(1)'
    lp5_fp LP62.3 "$x" "$row2" "$x  # U2: r" 'U1 ok' "    expect(g('do it (now)')).toBe(1)"
    lp5_fp LP62.4 "$x" "$row2" "$x  # U2: r" 'U1 ok' $'    // the test (slow) path\n    expect(f(1)).toBe(1)'
    lp5_fp LP62.5 "$x" "$row2" "$x  # U1, U2: r"$'\n'"$x  # U1!, U2!: r" 'U1 ok' $'    // the test (slow) path\n    expect(f(1)).toBe(1)'
    p="$tmp/fp7"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U1 ok', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => {" "$o0" "    expect(g('the test (x)')).toBe(0)" '  })' '})' >"$p/$x"
    lp5_edit LP62.6 pass "$p" "$x" "$o0" "$n0"
    lp5_fp LP62.7 "$xt" "$rowt" "$xt  # U2: r" 'U1 ok' '    render(<p>[beta</p>)'
    # LP62.8 (amended round 6, U4): a JSX `1)` in U1 ends its char span before its indentation span;
    # the two-direction rule refuses it (accepted false positive, exit: the unfreeze queue, or a blocked stop in auto).
    d="$tmp/LP62_8"
    lp_freeze_project "$d" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U1 ok', () => {" '    render(<li>1) Adresse</li>)' '  })' '' \
        "  it('U2 returns err', () => {" "$o0" '  })' '})' >"$d/$xt"
    lp5_edit LP62.8 deny "$d" "$xt" "$o0" "$n0" 'blocked stop (record kept)'

    # LP63-LP63.3 (SC1): a stray quote or backtick opens a string that a later apostrophe closes; the character
    # span of the case runs past its indentation span, so no marker lifts it and the edit is refused.
    # LP63 (A): lifted U2 with `L'adresse`, Edit of the trailing beforeEach.
    p="$tmp/scA"
    lp_freeze_project "$p" feat/s1 "$rowt" "$lift_xt"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    const el = <p>L'adresse</p>" '    expect(f(el)).toBe(0)' '  })' '' \
        '  beforeEach(() => {' "    reset() // the user's input" '  })' '})' >"$p/$xt"
    lp5_edit LP63 deny "$p" "$xt" '    reset() // the user' '    reset(99) // the user' 'blocked stop (record kept)' 'lifts it with'
    # LP63.2 (W_mid): lifted U2, the Edit appends a regex holding `'` plus a beforeEach.
    p="$tmp/scW"
    lp_freeze_project "$p" feat/s1 "$row2" "$lift_x"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "$o0" '  })' '' \
        "  it('U3 keeps three', () => {" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$x"
    old="$o0"$'\n  })'
    new="    const re = /l'a/"$'\n'"$o0"$'\n  })\n\n  beforeEach(() => {\n'"    vi.spyOn(mod, 'f').mockReturnValue(1) // the user's stub"$'\n  })'
    lp5_edit LP63.2 deny "$p" "$x" "$old" "$new" 'blocked stop (record kept)' 'lifts it with'
    # LP63.3 (CW): .tsx, `# U2: r` only, the Edit adds <kbd>`</kbd> to U2 and a beforeEach holding a lone backtick.
    p="$tmp/scCW"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "$o0" '  })' '' \
        "  it('U3 keeps three', () => {" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$xt"
    new="    const k = <kbd>$bt</kbd>"$'\n'"$o0"$'\n  })\n\n  beforeEach(() => {\n'"    vi.spyOn(mod, 'f').mockReturnValue(3) // the $bt key"$'\n  })'
    lp5_edit LP63.3 deny "$p" "$xt" "$old" "$new" 'blocked stop (record kept)' 'lifts it with'

    # LP64-LP64.5 (N1p): a member chain and a tagged table are call starts. LP64 (E): lifted U2 holding /it's/,
    # U3 an it.concurrent.each with an apostrophe comment; LP64.2: .tsx backtick U2 and the same U3, no lift;
    # LP64.3: lifted U2 and an it.each`table` U3. The edit of U3 is refused in each.
    p="$tmp/e"
    lp_freeze_project "$p" feat/s1 "$row2" "$lift_x"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    const re = /it's/" "$o0" '  })' '' \
        "  it.concurrent.each([3])('U3 keeps %i', (v) => {" "    // the user's input" '    expect(f(v)).toBe(3)' '  })' '})' >"$p/$x"
    lp5_edit LP64 deny "$p" "$x" '    expect(f(v)).toBe(3)' '    expect(f(v)).toBe(99)' ambiguous
    p="$tmp/etsx"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    const k = <kbd>$bt</kbd>" "$o0" '  })' '' \
        "  it.concurrent.each([3])('U3 keeps %i', (v) => {" "    // the $bt key" '    expect(f(v)).toBe(3)' '  })' '})' >"$p/$xt"
    lp5_edit LP64.2 deny "$p" "$xt" '    expect(f(v)).toBe(3)' '    expect(f(v)).toBe(99)' ambiguous
    p="$tmp/etag"
    lp_freeze_project "$p" feat/s1 "$row2" "$lift_x"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    const re = /it's/" "$o0" '  })' '' \
        "  it.each${bt}" '    v' '    ${3}' "  ${bt}('U3 keeps \$v', ({ v }) => {" "    // the user's input" '    expect(f(v)).toBe(3)' \
        '  })' '})' >"$p/$x"
    lp5_edit LP64.3 deny "$p" "$x" '    expect(f(v)).toBe(3)' '    expect(f(v)).toBe(99)' ambiguous
    # LP64.4/LP64.5: a benign member-chain table and a benign tagged table, U3 listed, are cases: the edit passes.
    p="$tmp/eok"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U3: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "$o0" '  })' '' \
        "  it.concurrent.each([3])('U3 keeps %i', (v) => {" '    expect(f(v)).toBe(3)' '  })' '})' >"$p/$x"
    lp5_edit LP64.4 pass "$p" "$x" '    expect(f(v)).toBe(3)' '    expect(f(v)).toBe(99)'
    p="$tmp/etagok"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U3: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "$o0" '  })' '' \
        "  it.each${bt}" '    v' '    ${3}' "  ${bt}('U3 keeps \$v', ({ v }) => {" '    expect(f(v)).toBe(3)' '  })' '})' >"$p/$x"
    lp5_edit LP64.5 pass "$p" "$x" '    expect(f(v)).toBe(3)' '    expect(f(v)).toBe(99)'

    # LP65/LP65.2 (TQ1): the liftA1 and liftB shapes of LP59/LP59.2 again, pinning the never-liftable text:
    # it holds 'no marker lifts it' and not the liftable text's 'lifts it with'.
    p="$tmp/a1"
    lp_freeze_project "$p" feat/s1 "$row2" "$lift_x"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "    expect(f(0)).toThrow(/it's/)" '  })' '' \
        "  it('U3 keeps three', () => {" "    // the user's input" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$x"
    lp5_edit LP65 deny "$p" "$x" '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(99)' 'blocked stop (record kept)' 'lifts it with'
    p="$tmp/b"
    lp_freeze_project "$p" feat/s1 "$row2" "$lift_x"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U2 returns err', () => {" "$o0" '  })' '})' >"$p/$x"
    lp5_edit LP65.2 deny "$p" "$x" "$o0"$'\n  })' \
        $'    expect(f(0)).toThrow(/\\(/)\n  })\n\n  beforeEach(() => {\n    reset()\n  })' 'blocked stop (record kept)' 'lifts it with'
    unset -f lp5_edit lp5_fp
    rm -rf "$tmp"
}

# LP66-LP71 (loop-to-pr review round 6): NC (the character span must end on the last non-blank line of the
# indentation span: a de-indented or tab-indented call line is refused), NA (a .each case whose first call
# holds another it/test call is ambiguous), TQE (NL/NL10 pin the end-line conditions, no lift), NB (a template
# literal at or below the call indent is an accepted false positive, pinned as a deny), and the lift is gone:
# `U2!` lifts nothing, every ambiguity names `blocked stop (record kept)` and no marker.
run_loop_to_pr_review6_cases() {
    local tmp p x='src/a/x.utils.test.ts' xt='src/a/x.utils.test.tsx' out h2 row2 rowt bt='`' old new
    local o0='    expect(f(0)).toBe(0)' n0='    expect(f(0)).toBe(1)' clr='blocked stop (record kept)' nol='lifts it with'
    tmp="$(mktemp -d)"
    h2="$(printf '%s' 'U2 returns err' | sha256sum | cut -c1-64)"
    row2="$(jq -cn --arg p "$x" --arg h "$h2" '[{path: $p, id: "U2", sha256: $h}]')"
    rowt="$(jq -cn --arg p "$xt" --arg h "$h2" '[{path: $p, id: "U2", sha256: $h}]')"
    # lp6_edit <id> <verdict> <dir> <path> <old> <new> [needle] [absent]: tdd-freeze-tests.sh on <dir>/<path>.
    lp6_edit() {
        out="$(project_hook_probe tdd-freeze-tests.sh "$3" "$(jq -cn --arg f "$3/$4" --arg c "$3" --arg o "$5" --arg n "$6" \
            '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
        pv_expect "$1" "$2" "$out" "${7:-}" "${8:-}"
    }
    # lp6_u1 <id> <verdict> <path> <rows> <unfrozen> <U1 text> [needle]: U1 text (own newline) then the row case U2;
    # Edit of U2 toBe(0)->toBe(1).
    lp6_u1() {
        local d="$tmp/${1//./_}"
        lp_freeze_project "$d" feat/s1 "$4" "$5"
        printf '%s' "import { f } from './x.utils'"$'\n\n'"describe('x', () => {"$'\n'"$6"$'\n'"  it('U2 returns err', () => {"$'\n'"$o0"$'\n  })\n})\n' >"$d/$3"
        lp6_edit "$1" "$2" "$d" "$3" "$o0" "$n0" "${7:-}" "$nol"
    }
    local u2="  it('U2 returns err', () => {"$'\n'"$o0"$'\n  })'
    local base_src
    base_src="import { f } from './x.utils'"$'\n\n'"describe('x', () => {"$'\n'"$u2"$'\n\n  it(\x27U3 keeps three\x27, () => {\n    expect(f(3)).toBe(3)\n  })\n})\n'

    # LP66/LP66.2 (NC): the Edit de-indents (or tab-indents) the call line of U2 and appends a beforeEach holding
    # a lone backtick; the indentation span stretches to the describe close while the character span ends early.
    p="$tmp/di"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s' "$base_src" >"$p/$xt"
    new="  it('U2 returns err', () => {"$'\n'"    const k = <kbd>$bt</kbd>"$'\n'"$o0"$'\n  })\n\n  beforeEach(() => {\n'"    vi.spyOn(mod, 'f').mockReturnValue(3) // the $bt key"$'\n  })'
    lp6_edit LP66 deny "$p" "$xt" "$u2" "${new#  }" "$clr" "$nol"
    p="$tmp/tab"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s' "$base_src" >"$p/$xt"
    lp6_edit LP66.2 deny "$p" "$xt" "$u2" $'\t'"${new#  }" "$clr" "$nol"
    # LP66.3-LP66.6: controls, the two spans agree: timeout number, call split over lines with an options object,
    # a chained expect, a wrapped arrow. The Edit of U2 passes.
    lp6_u1 LP66.3 pass "$x" "$row2" "$x  # U2: r" "  it('U1 slow', async () => {"$'\n    expect(f(1)).toBe(1)\n  }, 10_000)\n'
    lp6_u1 LP66.4 pass "$x" "$row2" "$x  # U2: r" $'  it(\n    \x27U1 split\x27,\n    async () => {\n      expect(f(1)).toBe(1)\n    },\n    { retry: 2 },\n  )\n'
    lp6_u1 LP66.5 pass "$x" "$row2" "$x  # U2: r" $'  it(\x27U1 chain\x27, async () => {\n    await expect(f(1))\n      .resolves.toBe(1)\n  })\n'
    lp6_u1 LP66.6 pass "$x" "$row2" "$x  # U2: r" $'  it(\x27U1 wrap\x27, () =>\n    expect(f(1)).toBe(1))\n'

    # LP67/LP67.2 (NA): a stray backtick in the first table of an it.each swallows describe-level code up to a later
    # it.each row case; Edit of the beforeEach (LP67) and of the frozen unlisted U2 body (LP67.2) are refused.
    p="$tmp/eb"
    lp_freeze_project "$p" feat/s1 "$(jq -cn --arg p "$xt" --arg h "$(printf '%s' 'U5 maps %s' | sha256sum | cut -c1-64)" '[{path: $p, id: "U5", sha256: $h}]')" "$xt  # U5: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('keys', () => {" \
        "  it.each([[<kbd>$bt</kbd>, 1]])('U2 renders %s', (el, n) => {" '    expect(f(el)).toBe(n)' '  })' '' \
        '  beforeEach(() => {' '    reset()' '  })' '' '  it.each([' "    // the backquote key: $bt" "    ['Backquote', 1]," \
        "  ])('U5 maps %s', (code, n) => {" '    expect(f(code)).toBe(n)' '  })' '})' >"$p/$xt"
    lp6_edit LP67 deny "$p" "$xt" $'    reset()\n' $'    reset(99)\n' "$clr" "$nol"
    lp6_edit LP67.2 deny "$p" "$xt" '    expect(f(el)).toBe(n)' '    expect(f(el)).toBe(99)' "$clr" "$nol"
    # LP67.3/LP67.4: a plain multi-line it.each table and a tagged table above the row case still pass.
    lp6_u1 LP67.3 pass "$x" "$row2" "$x  # U2: r" $'  it.each([\n    [1, 1],\n    [2, 2],\n  ])(\x27U1 %i\x27, (a, b) => {\n    expect(f(a)).toBe(b)\n  })\n'
    lp6_u1 LP67.4 pass "$x" "$row2" "$x  # U2: r" "  it.each${bt}"$'\n    a    | b\n    ${1} | ${1}\n'"  ${bt}(\x27U1 \$a\x27, ({ a, b }) => {"$'\n    expect(f(a)).toBe(b)\n  })\n'

    # LP68/LP68.2 (TQE): .tsx, `# U2: r` only, a single-line U2 holding <kbd>`</kbd>; the next base-indent line
    # (a beforeEach) must end the indentation span, and a closer-led line at the base indent must be a closer.
    # LP68 red under the mutants that end the span on any line at the base (M04) or on any line at the base
    # indent (M06); LP68.2 red under M04 and the mutant that accepts a lower-indent closer line (M09).
    p="$tmp/nl"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "  it('U1 ok', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => expect(f(<kbd>$bt</kbd>)).toBe(0))" "  beforeEach(() => reset()) // the $bt key)))" '})' >"$p/$xt"
    lp6_edit LP68 deny "$p" "$xt" 'reset()' 'reset(99)' "$clr" "$nol"
    p="$tmp/nl10"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "  it('U1 ok', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => expect(f(<kbd>$bt</kbd>)).toBe(0))" '    beforeEach(() => {' '      reset()' '    })' "}) // $bt)))" >"$p/$xt"
    lp6_edit LP68.2 deny "$p" "$xt" '      reset()' '      reset(99)' "$clr" "$nol"

    # LP69 (NB, accepted false positive): a template literal with a column-0 line in U1 makes U1 ambiguous, so the
    # Edit of the row case U2 below it is refused with the --clear text. Documented, not fixed: a string-aware
    # scan cannot keep the backtick swallow of LP63.3 closed.
    lp6_u1 LP69 deny "$x" "$row2" "$x  # U2: r" "  it('U1 parses', () => {"$'\n'"    const src = ${bt}# Title"$'\nbody line\n'"${bt}"$'\n    expect(f(src)).toBe(1)\n  })\n' "$clr"

    # LP70/LP70.2 (lift removed): a `U2!` line is read as the id U2 and lifts nothing, whatever the ambiguity:
    # a regex apostrophe (LP70, edit of the trailing U3 case) and a `.tsx` apostrophe in U2 (LP70.2).
    p="$tmp/lift"
    lp_freeze_project "$p" feat/s1 "$row2" "$x  # U2: r"$'\n'"$x  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "  it('U2 returns err', () => {" "    expect(f(0)).toThrow(/it's/)" '  })' '' \
        "  it('U3 keeps three', () => {" "    // the user's input" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$x"
    lp6_edit LP70 deny "$p" "$x" '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(99)' "$clr" "$nol"
    p="$tmp/lifttsx"
    lp_freeze_project "$p" feat/s1 "$rowt" "$xt  # U2: r"$'\n'"$xt  # U2!: r"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" "  it('U2 returns err', () => {" "    const el = <p>L'adresse</p>" '    expect(f(el)).toBe(0)' '  })' '' \
        '  beforeEach(() => {' "    reset() // the user's input" '  })' '})' >"$p/$xt"
    lp6_edit LP70.2 deny "$p" "$xt" '    reset() // the user' '    reset(99) // the user' "$clr" "$nol"
    unset -f lp6_edit lp6_u1
    rm -rf "$tmp"
}

# ---- auto-mode (AM): guard classes, mode record, verdict ledger, write/shell guards, freeze.
# am_tree <dir> <variant>: make_app_tree `approots` (app_roots ["frontend"]) made a git repo on
# `feat/s1` (from `audit/x`), with a loop record written by the test, never by a hook under test:
# auto (mode auto + contract_go) | moi (no mode) | noc (mode auto, no contract_go) | other (auto,
# branch feat/s2) | link (auto, the record a symlink) | none (no record).
am_tree() {
    local d="$1" v="$2" branch=feat/s1 extra
    make_app_tree "$d" approots
    git init -q -b main "$d"
    git -C "$d" config user.email fixture@loopkit.invalid
    git -C "$d" config user.name Fixture
    git -C "$d" add -A
    git -C "$d" commit -q -m seed
    git -C "$d" branch audit/x
    git -C "$d" switch -q -c feat/s1 audit/x
    mkdir -p "$d/.claude" "$d/docs/work/s1"
    printf 'r\n' >"$d/docs/work/s1/research.md"
    case "$v" in
        auto | link) extra='{mode: "auto", contract_go: {at: "2026-11-20T00:00:00Z", tool_use_id: "toolu_c"}}' ;;
        moi) extra='{}' ;;
        noc) extra='{mode: "auto"}' ;;
        other) extra='{mode: "auto", contract_go: {at: "2026-11-20T00:00:00Z", tool_use_id: "toolu_c"}}'; branch=feat/s2 ;;
        none) return 0 ;;
        *) return 1 ;;
    esac
    jq -n --arg branch "$branch" --arg sha "$(git -C "$d" rev-parse audit/x)" "
        {version: 1, slug: \"s1\", plan: \"docs/work/s1/plan.md\", branch: \$branch, base: \"audit/x\",
         base_sha: \$sha, repo: \"o/r\", default_branch: \"main\", barrier: true, base_ok: true,
         rows: [], verdicts: [], guarded: [], at: \"2026-11-20T00:00:00Z\", tool_use_id: \"toolu_c\"}
        + $extra" >"$d/.claude/.loop-record.json"
    if [[ "$v" == link ]]; then
        mv "$d/.claude/.loop-record.json" "$d/.claude/.rec-target.json"
        ln -s .rec-target.json "$d/.claude/.loop-record.json"
    fi
}

# am_class <tree> <rel> <want>: cwk_auto_class prints exactly <want>.
am_class() {
    local got
    CASES=$((CASES + 1))
    got="$(CLAUDE_PROJECT_DIR="$1" bash -c 'source "$1/hook-guarded.sh"; cwk_auto_class "$2"' _ "$HOOKS_DIR" "$2" 2>&1)" || true
    [[ "$got" == "$3" ]] || fail hook-guarded.sh "AM3 cwk_auto_class $2" "expected '$3', got '$got'"
}

# am_mode <id> <label> <tree> <want 0|1>: cwk_auto_mode's exit status.
am_mode() {
    local code
    CASES=$((CASES + 1))
    set +e
    CLAUDE_PROJECT_DIR="$3" bash -c 'source "$1/hook-guarded.sh"; cwk_auto_mode "$2"' _ "$HOOKS_DIR" "$3" >/dev/null 2>&1
    code=$?
    set -e
    [[ "$code" -eq "$4" ]] || fail hook-guarded.sh "$1 $2" "cwk_auto_mode: expected exit $4, got $code"
}

run_auto_mode_step1_cases() {
    local tmp out rel
    tmp="$(mktemp -d)"
    # AM1 the new guarded paths ask with no record, as vite.config.ts does.
    am_tree "$tmp/a1" none
    for rel in lefthook.yml .npmrc pnpm-workspace.yaml .github/CODEOWNERS .github/actions/x/action.yml \
               vitest.setup.ts vite.config.ts; do
        out="$(pf_probe "$tmp/a1" Write "$rel")"
        g15_expect AM1 ask "$out" "guarded path"
    done
    # AM2 the same patterns under an app root; a source file there is not guarded.
    for rel in frontend/lefthook.yml frontend/vitest.setup.ts; do
        out="$(pf_probe "$tmp/a1" Write "$rel")"
        g15_expect AM2 ask "$out" "guarded path"
    done
    out="$(pf_probe "$tmp/a1" Write frontend/src/a.ts)"
    g15_expect AM2 pass "$out"
    # AM3 the two auto classes.
    for rel in .claude/settings.json .claude/settings.local.json .github/workflows/ci.yml \
               .github/actions/x/action.yml .github/CODEOWNERS .claude/project.json .claude/hooks/x.sh; do
        am_class "$tmp/a1" "$rel" denied
    done
    for rel in vite.config.ts frontend/vite.config.ts .claude/.tdd-unfrozen .claude/.size-exempt package.json \
               eslint.config.js playwright.config.ts tsconfig.app.json vitest.config.ts lefthook.yml .npmrc \
               pnpm-workspace.yaml vitest.setup.ts src/test/setup.ts; do
        am_class "$tmp/a1" "$rel" ledgered
    done
    am_class "$tmp/a1" src/a.ts none
    # AM4 cwk_auto_mode: only a valid auto record of this branch with its contract go.
    am_tree "$tmp/a4" auto;   am_mode AM4 "auto rec" "$tmp/a4" 0
    am_mode AM4 "no record" "$tmp/a1" 1
    am_tree "$tmp/a4m" moi;   am_mode AM4 "moi rec" "$tmp/a4m" 1
    am_tree "$tmp/a4n" noc;   am_mode AM4 "no contract_go" "$tmp/a4n" 1
    am_tree "$tmp/a4o" other; am_mode AM4 "other branch" "$tmp/a4o" 1
    am_tree "$tmp/a4l" link;  am_mode AM4 "symlinked record" "$tmp/a4l" 1
    rm -rf "$tmp"
}

AM_SHA='9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5'

# am_mode_cli <tree>: what `loop-record.py --mode` prints from <tree>.
am_mode_cli() {
    (cd "$1" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --mode 2>/dev/null)
}

# am_block <path> <case> <sha> <verdict>: a fenced frozen-case verdict block.
am_block() {
    printf '```\nARBITER VERDICT\nkind: frozen-case\npath: %s\ncase: %s\nsha256: %s\nverdict: %s\n```\n' "$1" "$2" "$3" "$4"
}

# am_stop <cwd> <agent_type|-> <last_assistant_message> [agent_id]: a SubagentStop input
# (`-` leaves agent_type out).
am_stop() {
    jq -cn --arg cwd "$1" --arg t "$2" --arg m "$3" --arg id "${4:-a1}" '
        {session_id: "s", hook_event_name: "SubagentStop", cwd: $cwd, stop_hook_active: false,
         agent_id: $id, agent_transcript_path: "/nonexistent", last_assistant_message: $m}
        + (if $t == "-" then {} else {agent_type: $t} end)'
}

# am_no_decision <id> <label>: the hook printed nothing and exited 0.
am_no_decision() {
    CASES=$((CASES + 1))
    [[ "$LP_CODE" -eq 0 && -z "$LP_OUT" ]] || fail loop-record.py "$1 $2" "expected no output, got exit $LP_CODE: ${LP_OUT:0:200}"
}

run_auto_mode_step2_cases() {
    local tmp r rec q qm want before out t tr
    tmp="$(mktemp -d)"
    q=$'Contract go — docs/work/s1/research.md\nValidation: auto\n\nObjective …'
    lp_shim "$tmp/sh"

    # AM10 the auto contract go opens the record with the mode.
    r="$tmp/r10"; lp_repo "$r"; rec="$r/.claude/.loop-record.json"
    printf 'r\n' >"$r/docs/work/s1/research.md"
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    want="$(jq -cn --arg sha "$(git -C "$r" rev-parse audit/x)" \
        '{slug: "s1", plan: "docs/work/s1/plan.md", branch: "feat/s1", base: "audit/x", base_sha: $sha,
          mode: "auto", tool: "toolu_lp", rows: [], verdicts: [], guarded: []}')"
    lp_rec AM10 'contract go' "$rec" \
        '{slug, plan, branch, base, base_sha, mode, tool: .contract_go.tool_use_id, rows, verdicts, guarded}' "$want"
    git -C "$r" switch -q -c feat/s1 audit/x

    # AM12 --mode reads it.
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == auto ]] || fail loop-record.py "AM12 --mode auto rec" "expected auto, got '$out'"

    # AM16 a later plan go of the same pass keeps the mode; another pass replaces the record.
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s1/plan.md\nFrozen cases to amend:\nsrc/a/x.utils.test.ts | U2 | '"$AM_SHA" go)" "$tmp/sh"
    lp_rec AM16 'same pass plan go' "$rec" '{mode, c: (.contract_go | type), rows: (.rows | length), v: (.verdicts | type), g: (.guarded | type)}' \
        '{"mode":"auto","c":"object","rows":1,"v":"array","g":"array"}'
    # AM60 `--block` marks the record blocked and keeps the rest (auto included); a later plan go or contract
    # go of the pass rebuilds it without the mark.
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    lp_rec AM60 '--block marks the record' "$rec" '{blocked, at: (.blocked_at | type), mode, rows: (.rows | length)}' \
        '{"blocked":true,"at":"string","mode":"auto","rows":1}'
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == blocked ]] || fail loop-record.py "AM60.2 --mode after --block" "expected blocked, got '$out'"
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s1/plan.md\nFrozen cases to amend:\nnone' go)" "$tmp/sh"
    lp_rec AM60.3 'plan go lifts the mark' "$rec" '{blocked, mode}' '{"blocked":null,"mode":"auto"}'
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    lp_rec AM60.4 'contract go lifts the mark' "$rec" '{blocked, mode}' '{"blocked":null,"mode":"auto"}'
    # AM62 --mode prints `blocked` for a marked record, on its branch and from another branch (AM12: unmarked → auto).
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == blocked ]] || fail loop-record.py "AM62 --mode blocked rec" "expected blocked, got '$out'"
    git -C "$r" switch -q audit/x
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == blocked ]] || fail loop-record.py "AM62.2 --mode blocked rec, other branch" "expected blocked, got '$out'"
    git -C "$r" switch -q feat/s1
    # AM63 `--release` (the user's lift): mode moi, released_at, no mark; every other key unchanged; AM63.2 the
    # verdict-only .tdd-unfrozen line is commented out, the row-backed one stays.
    # The record holds a row (U2 of x.utils.test.ts, from AM16), a verdict and a guarded entry, all kept (R2).
    jq --arg h "$AM_SHA" '.rows += [{path: "src/a/x.utils.test.ts", id: "U2", sha256: $h}]
        | .verdicts += [{kind: "frozen-case", path: "src/a/y.utils.test.ts", id: "U7", sha256: $h,
            verdict: "unfreeze", at: "2026-11-21T00:00:00Z"}]
        | .guarded += [{path: "package.json", before: $h, after: $h, tool: "Write", at: "2026-11-21T00:00:00Z"}]' \
        "$rec" >"$r/.claude/r.x"
    mv "$r/.claude/r.x" "$rec"
    # AM63.2 `--release` comments the line backed only by a verdict (U7) and keeps the row-backed one (U2).
    printf 'src/a/x.utils.test.ts  # U2: kept by the release\nsrc/a/y.utils.test.ts  # U7: verdict only\n' >>"$r/.claude/.tdd-unfrozen"
    jq -e '(.rows | length) >= 1 and (.verdicts | length) >= 1 and (.guarded | length) >= 1' "$rec" >/dev/null \
        || fail loop-record.py AM63.2 "the seeded record misses a row, a verdict or a guarded entry"
    before="$(jq -S 'del(.mode, .blocked, .blocked_at, .released_at)' "$rec")"
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    lp_rec AM63 '--release releases the record' "$rec" '{mode, blocked, blocked_at, r: (.released_at | type)}' \
        '{"mode":"moi","blocked":null,"blocked_at":null,"r":"string"}'
    CASES=$((CASES + 1))
    [[ "$(jq -S 'del(.mode, .blocked, .blocked_at, .released_at)' "$rec" 2>/dev/null)" == "$before" ]] \
        || fail loop-record.py AM63 "--release changed a key other than mode/blocked/blocked_at/released_at"
    CASES=$((CASES + 1))
    [[ "$(<"$r/.claude/.tdd-unfrozen")" == $'src/a/x.utils.test.ts  # U2: kept by the release\n# src/a/y.utils.test.ts  # U7: verdict only' ]] \
        || fail loop-record.py AM63.2 ".tdd-unfrozen after --release: $(<"$r/.claude/.tdd-unfrozen")"
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == moi ]] || fail loop-record.py "AM63.3 --mode after --release" "expected moi, got '$out'"
    # AM63.7 a second --release is a no-op.
    jq '.released_at = "2026-11-19T02:00:00Z"' "$rec" >"$r/.claude/r.x"
    mv "$r/.claude/r.x" "$rec"
    before="$(sha256sum <"$rec")"
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    lp_same AM63.7 'second --release' "$rec" "$before"
    # AM63.6 --clear deletes a released record; AM63.6b (guard) and a blocked one.
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --clear)
    CASES=$((CASES + 1)); [[ ! -e "$rec" ]] || fail loop-record.py AM63.6 "--clear left a released record"
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --clear)
    CASES=$((CASES + 1))
    [[ ! -e "$rec" && "$(am_mode_cli "$r")" == moi ]] || fail loop-record.py AM63.6b "--clear left a blocked record or --mode is not moi"
    # AM63.4 (guard) --release on an unblocked auto record changes nothing.
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    before="$(sha256sum <"$rec")"
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    lp_same AM63.4 '--release on an unblocked record' "$rec" "$before"
    # AM63.8 a same-pass plan go on a released record keeps it released: released_at, --mode moi, a non-empty
    # --guarded-block, and the pass's first push still asks.
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s1/plan.md\nFrozen cases to amend:\nnone' go)" "$tmp/sh"
    lp_rec AM63.8 'plan go keeps the release' "$rec" '{mode, r: (.released_at | type)}' '{"mode":"moi","r":"string"}'
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == moi ]] || fail loop-record.py "AM63.8 --mode after a plan go on a released record" "expected moi, got '$out'"
    CASES=$((CASES + 1))
    [[ -n "$(cd "$r" && python3 -I "$LP_HOOK" --guarded-block 2>/dev/null)" ]] \
        || fail loop-record.py AM63.8 "--guarded-block is empty after a plan go on a released record"
    am_push AM63.8 ask "$r" 'pushes to a remote'
    printf 'Summary.\n' >"$r/docs/work/s1/pr-body.md"
    am_pr AM63.8b deny "$r" '--guarded-block'
    # The same legs on the plain plan-go record (released marks dropped) are the allow: the asks above
    # are the release, not a missing barrier.
    cp "$rec" "$r/.claude/r.rel"
    jq 'del(.released_at, .mode)' "$r/.claude/r.rel" >"$rec"
    am_push AM63.8c allow "$r"
    am_pr AM63.8d allow "$r"
    mv "$r/.claude/r.rel" "$rec"
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    lp_run "$(lp_ask "$r" 'Plan gate' $'Plan go — docs/work/s2/plan.md\nFrozen cases to amend:\nnone' go)" "$tmp/sh"
    lp_rec AM16 'other pass plan go' "$rec" '{slug, mode, contract_go}' '{"slug":"s2","mode":null,"contract_go":null}'

    # AM11 `Validation: moi` opens nothing; --mode prints moi.
    rm -f "$rec"
    lp_run "$(lp_ask "$r" 'Contract gate' $'Contract go — docs/work/s1/research.md\nValidation: moi' 'as written')" "$tmp/sh"
    lp_none AM11 'Validation: moi' "$rec"
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == moi ]] || fail loop-record.py "AM11/AM12 --mode no record" "expected moi, got '$out'"

    # AM13 a subagent's contract go records nothing.
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written' | jq -c '. + {agent_id: "a1"}')" "$tmp/sh"
    lp_none AM13 'agent_id' "$rec"
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written' | jq -c '. + {agent_type: "arbiter"}')" "$tmp/sh"
    lp_none AM13 'agent_type' "$rec"

    # AM14 only exactly `as written`; an existing record is left untouched.
    for t in amend 'tighten the scope' 'As written'; do
        lp_run "$(lp_ask "$r" 'Contract gate' "$q" "$t")" "$tmp/sh"
        lp_none AM14 "answer '$t'" "$rec"
    done
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    before="$(sha256sum <"$rec" 2>/dev/null || true)"
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" amend)" "$tmp/sh"
    lp_same AM14 'amend keeps the record' "$rec" "$before"

    # AM15 a missing or misspelt Validation line, a research file that does not exist.
    rm -f "$rec"
    for qm in $'Contract go — docs/work/s1/research.md\nObjective' \
              $'Contract go — docs/work/s1/research.md\nValidation: Auto' \
              $'Contract go — docs/work/s9/research.md\nValidation: auto'; do
        lp_run "$(lp_ask "$r" 'Contract gate' "$qm" 'as written')" "$tmp/sh"
        lp_none AM15 "question '${qm:0:60}'" "$rec"
    done

    # AM17 a pre-filled Contract gate is denied.
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written' PreToolUse)" "$tmp/sh"
    lp_verdict AM17 'pre-filled contract gate' deny 'answered by the user'

    # AM12 --mode is moi once HEAD is another branch.
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    git -C "$r" switch -q -c other
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == moi ]] || fail loop-record.py "AM12 --mode other branch" "expected moi, got '$out'"
    git -C "$r" switch -q audit/x

    # AM19 --clear leaves moi.
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --clear)
    CASES=$((CASES + 1))
    [[ ! -e "$rec" && "$(am_mode_cli "$r")" == moi ]] || fail loop-record.py AM19 "the record survived --clear or --mode is not moi"
    # AM60.5 `--block` with no record is a no-op, exit 0.
    CASES=$((CASES + 1))
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block) \
        && [[ ! -e "$rec" ]] || fail loop-record.py AM60.5 "--block without a record failed or created one"
    # AM63.5 (guard) `--release` with no record is a no-op, exit 0.
    CASES=$((CASES + 1))
    (cd "$r" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release) \
        && [[ ! -e "$rec" ]] || fail loop-record.py AM63.5 "--release without a record failed or created one"
    # AM62.4 (guard) a blocked record of another version reads moi.
    jq -n '{version: 2, mode: "auto", blocked: true}' >"$rec"
    CASES=$((CASES + 1)); out="$(am_mode_cli "$r")"
    [[ "$out" == moi ]] || fail loop-record.py "AM62.4 --mode v2 blocked rec" "expected moi, got '$out'"
    rm -f "$rec"
    # AM63.9 `release_record` writes under the record lock, through write_record.
    CASES=$((CASES + 1))
    t="$(awk '/^def release_record/{f=1; print; next} f && /^def /{exit} f' "$LP_HOOK")"
    [[ "$t" == *"with locked("* && "$t" == *"write_record("* ]] \
        || fail loop-record.py AM63.9 "release_record does not write under locked() through write_record()"

    # AM18 the record stays agent-proof; the two read-only CLIs pass the shell guard.
    am_tree "$tmp/a18" auto
    out="$(pf_probe "$tmp/a18" Write .claude/.loop-record.json)"
    g15_expect AM18 deny "$out" "written only by loop-record.py"
    for t in 'python3 .claude/hooks/loop-record.py --mode' 'python3 .claude/hooks/loop-record.py --guarded-block' \
             'python3 .claude/hooks/loop-record.py --block'; do
        out="$(pd_probe "$tmp/a18" "$t")"
        g15_expect AM18 pass "$out"
    done
    out="$(pd_probe "$tmp/a18" 'python3 .claude/hooks/loop-record.py < x.json')"
    g15_expect AM18 deny "$out"
    # AM18.r `--release` is the user's lift: the agent's call is denied in auto (blocked record included),
    # asks in moi, and only its exact form is let through to that decision.
    out="$(pd_probe "$tmp/a18" 'python3 .claude/hooks/loop-record.py --release')"
    g15_expect AM18.r deny "$out" "own terminal"
    am_tree "$tmp/a18b" auto
    (cd "$tmp/a18b" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    out="$(pd_probe "$tmp/a18b" 'python3 .claude/hooks/loop-record.py --release')"
    g15_expect AM18.r1 deny "$out" "own terminal"
    am_tree "$tmp/a18n" none
    out="$(pd_probe "$tmp/a18n" 'python3 .claude/hooks/loop-record.py --release')"
    g15_expect AM18.r2 ask "$out" "--release"
    out="$(pd_probe "$tmp/a18" 'python3 .claude/hooks/loop-record.py --release; git push')"
    g15_expect AM18.r3 deny "$out"
    out="$(pd_probe "$tmp/a18n" 'python3 .claude/hooks/loop-record.py --release; git push')"
    g15_expect AM18.r4 deny "$out"

    # ---- step 2b, the verdict ledger (SubagentStop).
    r="$tmp/r20"; lp_repo "$r"; rec="$r/.claude/.loop-record.json"
    printf 'r\n' >"$r/docs/work/s1/research.md"
    lp_run "$(lp_ask "$r" 'Contract gate' "$q" 'as written')" "$tmp/sh"
    git -C "$r" switch -q -c feat/s1 audit/x
    # AM20 an arbiter's unfreeze verdict is ledgered.
    lp_run "$(am_stop "$r" arbiter "Checked the hunk.
$(am_block src/a/x.utils.test.ts U2 "$AM_SHA" unfreeze)" a20)" "$tmp/sh"
    am_no_decision AM26 'AM20 run'
    lp_rec AM20 'unfreeze verdict' "$rec" '.verdicts | map({kind, path, id, sha256, verdict, agent_id})' \
        "[{\"kind\":\"frozen-case\",\"path\":\"src/a/x.utils.test.ts\",\"id\":\"U2\",\"sha256\":\"$AM_SHA\",\"verdict\":\"unfreeze\",\"agent_id\":\"a20\"}]"
    # AM22 a second verdict on the same case changes nothing.
    lp_run "$(am_stop "$r" arbiter "$(am_block src/a/x.utils.test.ts U2 "$AM_SHA" refuse)" a22)" "$tmp/sh"
    am_no_decision AM26 'AM22 run'
    lp_rec AM22 'first verdict final' "$rec" '[.verdicts[] | .verdict]' '["unfreeze"]'
    # AM21 a refuse is ledgered as such.
    lp_run "$(am_stop "$r" arbiter "$(am_block src/a/x.utils.test.ts U3 "$AM_SHA" refuse)" a21)" "$tmp/sh"
    lp_rec AM21 'refuse verdict' "$rec" '[.verdicts[] | select(.id == "U3") | .verdict]' '["refuse"]'
    # AM23 any other agent, or none, records nothing.
    for t in reviewer implementer '' -; do
        lp_run "$(am_stop "$r" "$t" "$(am_block src/a/x.utils.test.ts U4 "$AM_SHA" unfreeze)")" "$tmp/sh"
        lp_rec AM23 "agent_type '$t'" "$rec" '[.verdicts[] | select(.id == "U4")] | length' 0
    done
    # AM25 a malformed block records nothing.
    for t in "$(am_block src/a/x.utils.test.ts U5 "${AM_SHA:1}" unfreeze)" \
             "$(am_block src/a/x.utils.test.ts X5 "$AM_SHA" unfreeze)" \
             "$(am_block src/a/x.utils.test.ts U5 "$AM_SHA" maybe)" \
             "$(printf '```\nARBITER VERDICT\nkind: frozen-case\ncase: U5\nsha256: %s\nverdict: unfreeze\n```\n' "$AM_SHA")"; do
        lp_run "$(am_stop "$r" arbiter "$t")" "$tmp/sh"
        lp_rec AM25 'malformed block' "$rec" '[.verdicts[] | select(.id == "U5" or .id == "X5")] | length' 0
    done
    # AM26 stop_hook_active records nothing, and no run returns a decision.
    lp_run "$(am_stop "$r" arbiter "$(am_block src/a/x.utils.test.ts U6 "$AM_SHA" unfreeze)" | jq -c '.stop_hook_active = true')" "$tmp/sh"
    am_no_decision AM26 'stop_hook_active run'
    lp_rec AM26 'stop_hook_active' "$rec" '[.verdicts[] | select(.id == "U6")] | length' 0
    # AM27 a decision block is a trace entry only.
    lp_run "$(am_stop "$r" arbiter "$(printf '```\nARBITER VERDICT\nkind: decision\nquestion: fix now or follow-up?\nverdict: follow-up\n```\n')" a27)" "$tmp/sh"
    am_no_decision AM26 'AM27 run'
    lp_rec AM27 'decision trace' "$rec" '[.verdicts[] | select(.kind == "decision") | {question, verdict}]' \
        '[{"question":"fix now or follow-up?","verdict":"follow-up"}]'
    # AM40 the block found in the transcript: its last assistant text, then a SubagentHandback message.
    tr="$tmp/tr.jsonl"
    jq -cn --arg t "$(am_block src/a/x.utils.test.ts U7 "$AM_SHA" unfreeze)" \
        '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}' >"$tr"
    lp_run "$(am_stop "$r" arbiter 'done' | jq -c --arg p "$tr" '.agent_transcript_path = $p')" "$tmp/sh"
    lp_rec AM40 'transcript text' "$rec" '[.verdicts[] | select(.id == "U7") | .verdict]' '["unfreeze"]'
    jq -cn --arg t "$(am_block src/a/x.utils.test.ts U8 "$AM_SHA" refuse)" \
        '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", name: "SubagentHandback", input: {message: $t}}]}}' >"$tr"
    jq -cn '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: "Handed back."}]}}' >>"$tr"
    lp_run "$(am_stop "$r" arbiter 'Handed back.' | jq -c --arg p "$tr" '.agent_transcript_path = $p')" "$tmp/sh"
    lp_rec AM40 'SubagentHandback message' "$rec" '[.verdicts[] | select(.id == "U8") | .verdict]' '["refuse"]'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"nothing here"}]}}\n' >"$tr"
    lp_run "$(am_stop "$r" arbiter 'nothing here' | jq -c --arg p "$tr" '.agent_transcript_path = $p')" "$tmp/sh"
    lp_rec AM40 'no block anywhere' "$rec" '.verdicts | length' 5
    # AM24 a moi record, or none: nothing recorded, no record created.
    jq '.mode = null | .contract_go = null' "$rec" >"$rec.x" && mv "$rec.x" "$rec"
    lp_run "$(am_stop "$r" arbiter "$(am_block src/a/x.utils.test.ts U9 "$AM_SHA" unfreeze)")" "$tmp/sh"
    lp_rec AM24 'moi rec' "$rec" '[.verdicts[] | select(.id == "U9")] | length' 0
    rm -f "$rec"
    lp_run "$(am_stop "$r" arbiter "$(am_block src/a/x.utils.test.ts U9 "$AM_SHA" unfreeze)")" "$tmp/sh"
    lp_none AM24 'no record' "$rec"
    rm -rf "$tmp"
}

# am_verdicts <tree> <json array>: sets the record's verdicts (the test writes them, no hook).
am_verdicts() {
    local rec="$1/.claude/.loop-record.json"
    jq --argjson v "$2" '.verdicts = $v' "$rec" >"$rec.x" && mv "$rec.x" "$rec"
}

# am_v <path> <id> <verdict>: one frozen-case verdict entry.
am_v() {
    jq -cn --arg p "$1" --arg i "$2" --arg v "$3" --arg s "$AM_SHA" \
        '{kind: "frozen-case", path: $p, id: $i, sha256: $s, verdict: $v, agent_id: "a", at: "t"}'
}

# am_unfrozen_edit <tree> <added line>: an Edit appending <added line> to .claude/.tdd-unfrozen
# (created with one comment line), through protect-files.sh.
am_unfrozen_edit() {
    printf '# listing\n' >"$1/.claude/.tdd-unfrozen"
    project_hook_probe protect-files.sh "$1" \
        "$(jq -cn --arg f "$1/.claude/.tdd-unfrozen" --arg n "# listing"$'\n'"$2" \
            '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"# listing",new_string:$n}}')"
}

# am_guarded <tree> <jq filter> <want> <id> <label>: the record's guarded rows through <jq filter>.
am_guarded() {
    local got
    CASES=$((CASES + 1))
    got="$(jq -c "$2" "$1/.claude/.loop-record.json" 2>&1)" || true
    [[ "$got" == "$3" ]] || fail loop-record.py "$4 $5" "$2: expected $3, got $got"
}

am_sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

run_auto_mode_step3_cases() {
    local tmp t rel out sx sb
    tmp="$(mktemp -d)"
    t="$tmp/a"; am_tree "$t" auto
    # AM28 the denied class.
    for rel in .claude/settings.json .claude/settings.local.json .github/actions/x/action.yml .github/CODEOWNERS; do
        out="$(pf_probe "$t" Write "$rel")"
        g15_expect AM28 deny "$out" "auto mode"
    done
    for rel in .github/workflows/x.yml .claude/project.json; do
        out="$(pf_probe "$t" Edit "$rel")"
        g15_expect AM28 deny "$out" "auto mode"
    done
    # AM29 the ledgered class: written with no ask, one guarded row each.
    sx="$(am_sha x)"; sb="$(am_sha $'{}\n')"
    out="$(pf_probe "$t" Write vite.config.ts)"
    g15_expect AM29 pass "$out"
    out="$(pf_probe "$t" Write frontend/vite.config.ts)"
    g15_expect AM29 pass "$out"
    am_guarded "$t" '[.guarded[] | {path, before, after, tool}]' \
        "[{\"path\":\"vite.config.ts\",\"before\":\"absent\",\"after\":\"$sx\",\"tool\":\"Write\"},{\"path\":\"frontend/vite.config.ts\",\"before\":\"$sb\",\"after\":\"$sx\",\"tool\":\"Write\"}]" AM29 'two rows'
    # AM34 an Edit's after-hash is the file with the replacement applied; no match → unknown, still pass.
    printf 'a\n' >"$t/vite.config.ts"
    out="$(pf_probe "$t" Edit vite.config.ts)"
    g15_expect AM34 pass "$out"
    am_guarded "$t" '.guarded[-1] | {before, after}' "{\"before\":\"$(am_sha $'a\n')\",\"after\":\"$(am_sha $'b\n')\"}" AM34 'edit hash'
    out="$(project_hook_probe protect-files.sh "$t" "$(jq -cn --arg f "$t/vite.config.ts" \
        '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"zzz",new_string:"y"}}')")"
    g15_expect AM34 pass "$out"
    am_guarded "$t" '.guarded[-1].after' '"unknown"' AM34 'no match'
    # AM30 .tdd-unfrozen on an unfreeze verdict passes and is ledgered; without one, a blocked stop.
    mkdir -p "$t/src/a"; printf 'x\n' >"$t/src/a/x.utils.test.ts"
    am_verdicts "$t" "[$(am_v src/a/x.utils.test.ts U2 unfreeze)]"
    out="$(am_unfrozen_edit "$t" 'src/a/x.utils.test.ts  # U2: reason')"
    g15_expect AM30 pass "$out"
    am_guarded "$t" '.guarded[-1].path' '".claude/.tdd-unfrozen"' AM30 'ledgered'
    # AM30m a monorepo Python test (backend/tests/…) is a test path like tests/… (EcoCrew agent-ia-1.3);
    # a test_*.py outside any tests root is not.
    mkdir -p "$t/backend/tests/services/agent"; printf 'x\n' >"$t/backend/tests/services/agent/test_q.py"
    printf 'x\n' >"$t/backend/test_q.py"
    am_verdicts "$t" "[$(am_v backend/tests/services/agent/test_q.py B83 unfreeze),$(am_v backend/test_q.py B84 unfreeze)]"
    out="$(am_unfrozen_edit "$t" 'backend/tests/services/agent/test_q.py  # B83: reason')"
    g15_expect AM30m pass "$out"
    out="$(am_unfrozen_edit "$t" 'backend/test_q.py  # B84: reason')"
    g15_expect AM30m deny "$out" "auto mode — blocked stop:"
    am_verdicts "$t" '[]'
    out="$(am_unfrozen_edit "$t" 'src/a/x.utils.test.ts  # U2: reason')"
    g15_expect AM30 deny "$out" "auto mode — blocked stop:"
    # AM27 a decision trace backs nothing.
    am_verdicts "$t" '[{"kind":"decision","question":"q","verdict":"v","agent_id":"a","at":"t"}]'
    out="$(am_unfrozen_edit "$t" 'src/a/x.utils.test.ts  # U2: reason')"
    g15_expect AM27 deny "$out" "auto mode — blocked stop:"
    # AM31 a refused id in the line.
    am_verdicts "$t" "[$(am_v src/a/x.utils.test.ts U2 refuse),$(am_v src/a/x.utils.test.ts U3 unfreeze)]"
    out="$(am_unfrozen_edit "$t" 'src/a/x.utils.test.ts  # U2, U3: r')"
    g15_expect AM31 deny "$out" "auto mode — blocked stop:"
    # AM32 an implementation path, or the id on another test path.
    am_verdicts "$t" "[$(am_v src/a/x.utils.test.ts U2 unfreeze)]"
    printf 'x\n' >"$t/src/a/x.utils.ts"; printf 'x\n' >"$t/src/a/y.utils.test.ts"
    out="$(am_unfrozen_edit "$t" 'src/a/x.utils.ts  # U2: r')"
    g15_expect AM32 deny "$out" "auto mode — blocked stop:"
    out="$(am_unfrozen_edit "$t" 'src/a/y.utils.test.ts  # U2: r')"
    g15_expect AM32 deny "$out" "auto mode — blocked stop:"
    # AM43 a guarded path outside both auto classes: the app-root folder itself.
    out="$(pf_probe "$t" Write frontend)"
    g15_expect AM43 deny "$out" "auto mode — blocked stop: frontend would ask"
    # AM35 shell: a denied target is denied; a ledgered one passes with a shell row.
    out="$(pd_probe "$t" 'cp /tmp/a .claude/settings.json')"
    g15_expect AM35 deny "$out" "auto mode"
    out="$(pd_probe "$t" 'cp /tmp/a package.json')"
    g15_expect AM35 pass "$out"
    am_guarded "$t" '.guarded[-1] | {path, after, tool}' '{"path":"package.json","after":"unknown","tool":"shell"}' AM35 'shell row'
    # AM45 shell to .tdd-unfrozen: a blocked stop, no row.
    am_verdicts "$t" '[]'
    out="$(pd_probe "$t" "printf 'src/a/x.utils.test.ts  # U2: r\n' >> .claude/.tdd-unfrozen")"
    g15_expect AM45 deny "$out" "auto mode — blocked stop:"
    am_guarded "$t" '[.guarded[] | select(.tool == "shell" and .path == ".claude/.tdd-unfrozen")] | length' 0 AM45 'no row'
    # AM46 every other shell-guard ask becomes a blocked stop; an unresolved target is a plain
    # deny in every mode, sent back to the agent, never a stop.
    for rel in 'cp /tmp/a frontend' 'rm -r src/a' 'mv src/a.ts /tmp/b' 'npx tsc --init'; do
        out="$(pd_probe "$t" "$rel")"
        g15_expect AM46 deny "$out" "auto mode — blocked stop:"
    done
    out="$(pd_probe "$t" 'cp /tmp/a "$X"')"
    g15_expect AM46u deny "$out" "unresolved write target"
    CASES=$((CASES + 1))
    [[ "$out" != *"blocked stop"* ]] || fail prevent-destructive-commands.sh AM46u "an unresolved target must not end the auto run: '${out:0:200}'"
    # AM33 / moi: the same writes ask, no row; AM45, AM46 ask too.
    t="$tmp/m"; am_tree "$t" moi
    for rel in .claude/settings.json .github/CODEOWNERS vite.config.ts frontend; do
        out="$(pf_probe "$t" Write "$rel")"
        g15_expect AM33 ask "$out" "guarded path"
    done
    am_guarded "$t" '.guarded | length' 0 AM33 'no row in moi'
    mkdir -p "$t/src/a"; printf 'x\n' >"$t/src/a/x.utils.test.ts"
    out="$(am_unfrozen_edit "$t" 'src/a/x.utils.test.ts  # U2: reason')"
    g15_expect AM33 ask "$out" "guarded path"
    out="$(pd_probe "$t" 'cp /tmp/a package.json')"
    g15_expect AM35 ask "$out" "guarded path"
    out="$(pd_probe "$t" "printf 'src/a/x.utils.test.ts  # U2: r\n' >> .claude/.tdd-unfrozen")"
    g15_expect AM45 ask "$out"
    for rel in 'cp /tmp/a frontend' 'rm -r src/a' 'mv src/a.ts /tmp/b' 'npx tsc --init'; do
        out="$(pd_probe "$t" "$rel")"
        g15_expect AM46 ask "$out"
    done
    g15_expect AM46u deny "$(pd_probe "$t" 'cp /tmp/a "$X"')" "unresolved write target"
    # AM36 the guarded row cannot be written: deny, never a silent allow.
    t="$tmp/ro"; am_tree "$t" auto
    chmod 555 "$t/.claude"
    out="$(pf_probe "$t" Write vite.config.ts)"
    chmod 755 "$t/.claude"
    g15_expect AM36 deny "$out" "auto mode"
    # AM42 a drop comments out the verdict-backed .tdd-unfrozen line.
    t="$tmp/d"; am_tree "$t" auto
    am_verdicts "$t" "[$(am_v src/a/x.utils.test.ts U2 unfreeze),$(am_v src/a/x.utils.test.ts U3 refuse)]"
    printf 'src/a/x.utils.test.ts  # U2, U3: r\n' >"$t/.claude/.tdd-unfrozen"
    (cd "$t" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --clear)
    CASES=$((CASES + 1))
    [[ ! -e "$t/.claude/.loop-record.json" && "$(cat "$t/.claude/.tdd-unfrozen")" == '# src/a/x.utils.test.ts  # U2, U3: r' ]] \
        || fail loop-record.py "AM42 --clear" "got: $(cat "$t/.claude/.tdd-unfrozen")"
    t="$tmp/d2"; am_tree "$t" auto
    am_verdicts "$t" "[$(am_v src/a/x.utils.test.ts U2 unfreeze),$(am_v src/a/x.utils.test.ts U3 refuse)]"
    printf 'src/a/x.utils.test.ts  # U2, U3: r\n' >"$t/.claude/.tdd-unfrozen"
    lp_shim "$tmp/sh"
    lp_run "$(lp_bash "$t" 'gh pr create --repo o/r --base audit/x --head feat/s1 --title "t" --body-file docs/work/s1/pr-body.md' \
        'https://github.com/o/r/pull/7')" "$tmp/sh"
    CASES=$((CASES + 1))
    [[ ! -e "$t/.claude/.loop-record.json" && "$(cat "$t/.claude/.tdd-unfrozen")" == '# src/a/x.utils.test.ts  # U2, U3: r' ]] \
        || fail loop-record.py "AM42 PR drop" "got: $(cat "$t/.claude/.tdd-unfrozen")"
    # AM44 concurrent appends never lose one.
    t="$tmp/c"; am_tree "$t" auto
    local i lost=0
    for i in $(seq 1 20); do
        jq '.verdicts = [] | .guarded = []' "$t/.claude/.loop-record.json" >"$t/.claude/r.x" && mv "$t/.claude/r.x" "$t/.claude/.loop-record.json"
        am_stop "$t" arbiter "$(am_block src/a/x.utils.test.ts U2 "$AM_SHA" unfreeze)" \
            | CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" >/dev/null 2>&1 &
        pf_probe "$t" Write vite.config.ts >/dev/null &
        wait
        [[ "$(jq '[(.verdicts | length), (.guarded | length)] == [1, 1]' "$t/.claude/.loop-record.json")" == true ]] || lost=$((lost + 1))
    done
    CASES=$((CASES + 1))
    [[ "$lost" -eq 0 ]] || fail loop-record.py AM44 "$lost of 20 runs lost a row"
    rm -rf "$tmp"
}

# am_freeze_rec <dir> <auto|moi> <verdicts json>: the record of an lp_* project, rows emptied, turned
# into an auto record (contract go) or left moi, carrying <verdicts>.
am_freeze_rec() {
    local extra='{}'
    [[ "$2" == moi ]] || extra='{mode: "auto", contract_go: {at: "2026-11-20T00:00:00Z", tool_use_id: "toolu_c"}}'
    jq --argjson v "$3" ". + {rows: [], verdicts: \$v, guarded: []} + $extra" "$1/.claude/.loop-record.json" >"$1/.claude/r.x"
    mv "$1/.claude/r.x" "$1/.claude/.loop-record.json"
}

# AM37-AM39, AM41, AM47 (auto-mode step 4): in auto the freeze hook's rows are the plan rows plus the
# `unfreeze` verdicts, a `refuse` verdict keeps its case frozen, and the listed / whole-file fallbacks
# are off; a moi record ignores verdicts.
run_auto_mode_step4_cases() {
    local tmp p x='src/a/x.utils.test.ts' h u2 u2new u2bad addon b2 b2new v
    tmp="$(mktemp -d)"
    addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"
    h='9168773984070c306b4b682d4a383e3ab211ebe641e4b7d5321ddec058880bb5'
    u2="  it('U2 returns err', () => {"$'\n''    expect(f(0)).toBe(0)'$'\n''  })'
    u2new="  it('U2 returns err on empty input', () => {"$'\n''    expect(f(0)).toBe(-1)'$'\n''  })'
    u2bad="  it('U2 returns err on bad input', () => {"$'\n''    expect(f(0)).toBe(-1)'$'\n''  })'
    am_v() { jq -cn --arg p "$1" --arg i "$2" --arg h "$3" --arg v "$4" \
        '[{kind: "frozen-case", path: $p, id: $i, sha256: $h, verdict: $v, at: "2026-11-21T00:00:00Z"}]'; }
    am_edit() { jq -cn --arg o "$1" --arg n "$2" '{old_string:$o, new_string:$n}'; }

    p="$tmp/unfreeze"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" auto "$(am_v "$x" U2 "$h" unfreeze)"
    lp_freeze AM37 pass "$p" Edit "$(am_edit "$u2" "$u2new")"
    lp_freeze AM37.2 deny "$p" Edit "$(am_edit "$u2" "$u2bad")" "hashes to"

    p="$tmp/refuse"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" auto "$(am_v "$x" U2 "$h" refuse)"
    lp_freeze AM38 deny "$p" Edit "$(am_edit "$u2" "$u2new")" "refuse"

    p="$tmp/moirefuse"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" moi "$(am_v "$x" U2 "$h" refuse)"
    lp_freeze AM39 pass "$p" Edit "$(am_edit "$u2" "$u2bad")"

    p="$tmp/autolisted"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" auto '[]'
    lp_freeze AM47 deny "$p" Edit "$(am_edit "$u2" "$u2new")"
    p="$tmp/autowhole"; lp_freeze_project "$p" feat/s1 '[]' "$x reason"
    am_freeze_rec "$p" auto '[]'
    lp_freeze AM47.2 deny "$p" Edit "$(am_edit "$u2" "$u2new")"
    p="$tmp/moilisted"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" moi '[]'
    lp_freeze AM47.3 pass "$p" Edit "$(am_edit "$u2" "$u2new")"
    p="$tmp/moiwhole"; lp_freeze_project "$p" feat/s1 '[]' "$x reason"
    am_freeze_rec "$p" moi '[]'
    lp_freeze AM47.4 pass "$p" Edit "$(am_edit "$u2" "$u2new")"

    # AM63.10 `--release` comments the `.tdd-unfrozen` line backed only by a frozen-case verdict: the released
    # (moi) record leaves U2 frozen. AM63.11 a line also backed by a plan row stays: rows hold in any mode.
    p="$tmp/relverdict"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" auto "$(am_v "$x" U2 "$h" unfreeze)"
    lp_freeze AM63.10 pass "$p" Edit "$(am_edit "$u2" "$u2new")"
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    CASES=$((CASES + 1))
    [[ "$(<"$p/.claude/.tdd-unfrozen")" == "# $x  # U2: r" ]] \
        || fail loop-record.py AM63.10 "--release did not comment the verdict-only line: $(<"$p/.claude/.tdd-unfrozen")"
    lp_freeze AM63.10b deny "$p" Edit "$(am_edit "$u2" "$u2new")"
    p="$tmp/relrow"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U2: r"
    am_freeze_rec "$p" auto "$(am_v "$x" U2 "$h" unfreeze)"
    jq --arg p "$x" --arg h "$h" '.rows = [{path: $p, id: "U2", sha256: $h}]' "$p/.claude/.loop-record.json" >"$p/.claude/r.x"
    mv "$p/.claude/r.x" "$p/.claude/.loop-record.json"
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    CASES=$((CASES + 1))
    [[ "$(<"$p/.claude/.tdd-unfrozen")" == "$x  # U2: r" ]] \
        || fail loop-record.py AM63.11 "--release commented a row-backed line: $(<"$p/.claude/.tdd-unfrozen")"
    lp_freeze AM63.11b pass "$p" Edit "$(am_edit "$u2" "$u2new")"
    p="$tmp/relnofile"; lp_freeze_project "$p" feat/s1 '[]' ""
    am_freeze_rec "$p" auto "$(am_v "$x" U2 "$h" unfreeze)"
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    CASES=$((CASES + 1))
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release) \
        && [[ "$(jq -r .mode "$p/.claude/.loop-record.json")" == moi ]] \
        || fail loop-record.py AM63.12 "--release without a .tdd-unfrozen failed or left the record blocked"

    b2=$'def test_b2_returns_err():\n    assert g(0) == 0'
    b2new=$'def test_b2_returns_err_on_empty():\n    assert g(0) == -1'
    for v in unfreeze refuse; do
        p="$tmp/py-$v"; lp_py_project "$p"
        am_freeze_rec "$p" auto "$(am_v tests/services/test_b.py B2 e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b "$v")"
        pv_expect "AM41 $v" "$([[ "$v" == unfreeze ]] && echo pass || echo deny)" \
            "$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_b.py" --arg c "$p" \
                --arg o "$b2" --arg n "$b2new" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    done
    # AM63.13 the commented line keeps a pytest case frozen once the verdict-only record is released.
    p="$tmp/py-released"; lp_py_project "$p"
    am_freeze_rec "$p" auto "$(am_v tests/services/test_b.py B2 e5241b6f59b70aaed1de135c6d62c92d86f4cb7e5eafb257c1e7a94a2a48f76b unfreeze)"
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --block)
    (cd "$p" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --release)
    pv_expect AM63.13 deny \
        "$(rv2_pair "$addon" tdd-freeze-tests-py.py "$p" "$(jq -cn --arg f "$p/tests/services/test_b.py" --arg c "$p" \
            --arg o "$b2" --arg n "$b2new" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    rm -rf "$tmp"
}

# AM48-AM58.5 (auto-mode-trial-fixes, fix 1): in auto, with an `unfreeze` verdict for the listed file,
# whole static import declarations added to the import head pass, alone or with the verdict case's body;
# every other head change, a Write, and the same Edits without a verdict stay refused.
run_auto_mode_import_cases() {
    local tmp p x='src/a/x.utils.test.ts' h3 imp u3 u3new head body3 body3new
    tmp="$(mktemp -d)"
    h3='1cfe4c2a210df3bd4c64546e6559ba3f73cdde543d48719e08e6488972e34697'
    imp="import { f } from './x.utils'"
    u3="  it('U3 keeps three', () => {"$'\n''    expect(f(3)).toBe(3)'
    u3new="  it('U3 keeps three', () => {"$'\n''    expect(f(3)).toBe(4)'
    head="$imp"$'\n\n'"describe('x', () => {"$'\n'"  it('U1 returns one', () => {"$'\n''    expect(f(1)).toBe(1)'$'\n''  })'$'\n\n'"  it('U2 returns err', () => {"$'\n''    expect(f(0)).toBe(0)'$'\n''  })'$'\n\n'
    body3="$head$u3"
    body3new="$imp"$'\n'"import { g } from './y.utils'${head#"$imp"}$u3new"
    ai_v() { jq -cn --arg p "$x" --arg h "$h3" --arg v "$1" \
        '[{kind: "frozen-case", path: $p, id: "U3", sha256: $h, verdict: $v, at: "2026-11-23T00:00:00Z"}]'; }
    ai_edit() { jq -cn --arg o "$1" --arg n "$2" '{old_string:$o, new_string:$n}'; }
    ai_add() { ai_edit "$imp" "$imp"$'\n'"$1"; }
    ai_proj() { p="$tmp/$1"; lp_freeze_project "$p" feat/s1 '[]' "$x  # U3: r"; am_freeze_rec "$p" auto "$2"; }

    ai_proj core "$(ai_v unfreeze)"
    lp_freeze AM48 pass "$p" Edit "$(ai_add "import { g } from './y.utils'")"
    lp_freeze AM49 pass "$p" Edit "$(ai_edit "$body3" "$body3new")"
    lp_freeze AM49.2 deny "$p" Write "$(jq -cn --arg c "$imp"$'\n'"import { g } from './y.utils'${head#"$imp"}$u3"$'\n''  })'$'\n''})' \
        '{content:$c}')" "a Write replaces the whole frozen file"
    lp_freeze AM51 deny "$p" Edit "$(ai_edit "$imp"$'\n\n' $'\n')"
    lp_freeze AM52 deny "$p" Edit "$(ai_edit "$imp" "import { f, h } from './x.utils'")"
    lp_freeze AM53 deny "$p" Edit "$(ai_add 'const k = 1')"
    lp_freeze AM54 pass "$p" Edit "$(ai_add "import {"$'\n''  g,'$'\n''  h,'$'\n'"} from './y.utils'"$'\n'"import type { T } from './t'")"
    lp_freeze AM55 deny "$p" Edit "$(ai_edit "describe('x', () => {" "describe('x', () => {"$'\n'"import { g } from './y.utils'")"
    lp_freeze AM56 deny "$p" Edit "$(ai_add "import { g } from './y.utils'; vi.mock('./x.utils')")"
    lp_freeze AM57 deny "$p" Edit "$(ai_add "import('./y.utils')")"
    lp_freeze AM57.2 deny "$p" Edit "$(ai_add 'import.meta.x = 1')"
    lp_freeze AM58 deny "$p" Edit "$(ai_add "import { expect } from './e'")"
    lp_freeze AM58.2 deny "$p" Edit "$(ai_add "import { it as t } from './n'")"
    lp_freeze AM58.3 deny "$p" Edit "$(ai_add "import './setup'")"
    lp_freeze AM58.4 deny "$p" Edit "$(ai_add "import { f as g2, f2 as f } from './z'")"
    lp_freeze AM58.5 deny "$p" Edit "$(ai_add "import { g } from \"./y'; vi.mock('x')\"")"
    lp_freeze AM58.6 deny "$p" Edit "$(ai_add "import { vi } from './v'")"
    lp_freeze AM58.7 deny "$p" Edit "$(ai_add "import { beforeAll } from './n'")"

    ai_proj noverdict '[]'
    lp_freeze AM50 deny "$p" Edit "$(ai_add "import { g } from './y.utils'")"
    lp_freeze AM50.2 deny "$p" Edit "$(ai_edit "$body3" "$body3new")"

    ai_proj refused "$(ai_v refuse)"
    lp_freeze AM55.2 deny "$p" Edit "$(ai_add "import { g } from './y.utils'")"

    # AM59 (fix 2): the ambiguity deny offers no self clear any more; it names the blocked stop.
    grep -Fq 'end the run with a blocked stop (record kept)' "$HOOKS_DIR/tdd-freeze-tests.sh" \
        || fail tdd-freeze-tests.sh AM59 "the ambiguity deny does not name the blocked stop"
    ! grep -Fq 'loop-record.py --clear' "$HOOKS_DIR/tdd-freeze-tests.sh" \
        || fail tdd-freeze-tests.sh AM59.2 "the hook source still names loop-record.py --clear"
    # AM59.3: the LP54 shape (a U2 regex with quotes, an Edit of U3) denies as ambiguous, names the blocked
    # stop and never offers the self clear.
    p="$tmp/ambig"
    lp_freeze_project "$p" feat/s1 "$(jq -cn --arg p "$x" --arg h "$(printf '%s' 'U3 keeps three' | sha256sum | cut -c1-64)" \
        '[{path: $p, id: "U3", sha256: $h}]')" "$x  # U3: r"$'\n'"$x  # U2!: the quotes of its regex are balanced"
    printf '%s\n' "import { f } from './x.utils'" '' "describe('x', () => {" \
        "  it('U1 returns one', () => {" '    expect(f(1)).toBe(1)' '  })' '' \
        "  it('U2 returns err', () => {" "    expect(f(0)).toThrow(/'x'/)" '  })' '' \
        "  it('U3 keeps three', () => {" '    expect(f(3)).toBe(3)' '  })' '})' >"$p/$x"
    lp_freeze AM59.3 deny "$p" Edit "$(ai_edit '    expect(f(3)).toBe(3)' '    expect(f(3)).toBe(4)')" \
        'blocked stop (record kept)' 'loop-record.py --clear'
    rm -rf "$tmp"
}

# am_git <dir> <auto|moi> <origin>: an am_tree on feat/s1 whose base audit/x is pushed to the bare
# <origin>; src/a/x.utils.test.ts (case U2) is committed on the base.
am_git() {
    am_tree "$1" "$2"
    mkdir -p "$1/src/a"
    printf '%s\n' "describe('x', () => {" "  it('U2 returns err', () => {" '    expect(f(0)).toBe(0)' '  })' '})' \
        >"$1/src/a/x.utils.test.ts"
    git -C "$1" switch -q audit/x
    git -C "$1" add src/a/x.utils.test.ts
    git -C "$1" commit -q -m base
    git -C "$1" switch -q feat/s1
    git -C "$1" merge -q --ff-only audit/x
    jq --arg sha "$(git -C "$1" rev-parse audit/x)" '.base_sha = $sha' "$1/.claude/.loop-record.json" >"$1/.claude/r.x"
    mv "$1/.claude/r.x" "$1/.claude/.loop-record.json"
    git init -q --bare -b main "$3"
    git -C "$1" remote add origin "$3"
    git -C "$1" push -q origin audit/x 2>/dev/null
}

# am_commit <dir> <path> <content>: writes <content> to <path> and commits it on the current branch.
am_commit() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" >"$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -q -m "edit $2"
}

# am_row <dir> <path> <before> <after> <tool>: appends a guarded ledger row to the record.
am_row() {
    jq --arg p "$2" --arg b "$3" --arg a "$4" --arg t "$5" \
        '.guarded += [{path: $p, before: $b, after: $a, tool: $t, at: "2026-11-21T00:00:00Z"}]' \
        "$1/.claude/.loop-record.json" >"$1/.claude/r.x"
    mv "$1/.claude/r.x" "$1/.claude/.loop-record.json"
}

# am_expected_block <line>...: the Guarded files touched block holding <line>s, its digest computed here.
am_expected_block() {
    local body
    body="$(printf '%s\n' "$@")"
    printf '### Guarded files touched\n<!-- guarded-files sha256:%s -->\n%s\n' \
        "$(printf '%s\n' "$body" | sha256sum | cut -c1-64)" "$body"
}

# am_pr <id> <want> <dir> [needle]: enforce-git-workflow.sh on the pass's exact `gh pr create`.
am_pr() {
    local out
    out="$(project_hook_probe enforce-git-workflow.sh "$3" "$(jq -cn --arg c "$3" \
        '{tool_name: "Bash", cwd: $c, tool_input: {command: "gh pr create --repo o/r --base audit/x --head feat/s1 --title \"t\" --body-file docs/work/s1/pr-body.md"}}')")"
    pv_expect "$1" "$2" "$out" "${4:-}"
}

# am_push <id> <want> <dir> [needle]: enforce-git-workflow.sh on the pass's `git push -u origin feat/s1`, with
# the G21 environment (an empty HOME, no GIT_CONFIG*: the record allow refuses a configured push).
am_push() {
    local out code
    mkdir -p "$3/.claude/.home"
    set +e
    out="$(jq -cn --arg c "$3" '{tool_name: "Bash", cwd: $c, tool_input: {command: "git push -u origin feat/s1"}}' \
        | env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM HOME="$3/.claude/.home" CLAUDE_PROJECT_DIR="$3" \
            CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)"
    code=$?
    set -e
    pv_expect "$1" "$2" "$(printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out")" "${4:-}"
}

# am_cmd <id> <want> <dir> <command> [needle]: enforce-git-workflow.sh on <command> run from <dir>, with the
# am_push environment.
am_cmd() {
    local out code
    mkdir -p "$3/.claude/.home"
    set +e
    out="$(jq -cn --arg c "$3" --arg x "$4" '{tool_name: "Bash", cwd: $c, tool_input: {command: $x}}' \
        | env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM HOME="$3/.claude/.home" CLAUDE_PROJECT_DIR="$3" \
            CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 "$HOOKS_DIR/enforce-git-workflow.sh" 2>/dev/null)"
    code=$?
    set -e
    pv_expect "$1" "$2" "$(printf '%s\n%s\n' "$(semantic_verdict "$code" <(printf '%s' "$out"))" "$out")" "${5:-}"
}

# AM65-AM70 (agent-ia-trial-fixes item 4): in auto, every enforce-git-workflow.sh ask is a blocked stop
# (EcoCrew 2.2: four asks reached the user after the contract go); the pass's own push and PR still run;
# moi keeps its asks. Auto is read from the session tree, never from a `-C` target.
run_trial_auto_git_cases() {
    local tmp t
    tmp="$(mktemp -d)"
    t="$tmp/auto"; am_git "$t" auto "$tmp/o1.git"
    am_cmd AM65 deny "$t" 'git push --force origin feat/s1' 'auto mode — blocked stop:'
    am_cmd AM66 deny "$t" 'gh pr merge 1' 'auto mode — blocked stop:'
    am_push AM67 allow "$t"
    printf 'Summary.\n\n%s\n' "$(am_expected_block '- none')" >"$t/docs/work/s1/pr-body.md"
    am_pr AM67.2 allow "$t"
    git init -q -b feat/s1 "$tmp/out"
    git -C "$tmp/out" -c user.email=fixture@loopkit.invalid -c user.name=Fixture commit -q --allow-empty -m seed
    am_cmd AM69 deny "$t" "git -C $tmp/out push -u origin feat/s1" 'auto mode — blocked stop:'
    git -C "$t" worktree add -q "$tmp/wt2" -b feat/other audit/x
    am_cmd AM70 deny "$t" "git -C $tmp/wt2 push -u origin feat/s1" 'auto mode — blocked stop:'
    t="$tmp/moi"; am_git "$t" moi "$tmp/o2.git"
    am_cmd AM68 ask "$t" 'git push --force origin feat/s1' 'FORCE push'
    t="$tmp/none"; am_git "$t" moi "$tmp/o3.git"
    rm -f "$t/.claude/.loop-record.json"
    am_cmd AM68.2 ask "$t" 'git push --force origin feat/s1' 'FORCE push'
    rm -rf "$tmp"
}

# G22.001-G22.009 (auto-mode step 5): in auto, the pass's PR is allowed only when its body carries,
# byte for byte, the Guarded files touched block the hook recomputes; moi is unchanged.
run_auto_mode_step5_cases() {
    local tmp t bs as block x='src/a/x.utils.test.ts'
    tmp="$(mktemp -d)"
    bs="$(printf '{}\n' | sha256sum | cut -c1-64)"
    as="$(printf '{"name":"x"}\n' | sha256sum | cut -c1-64)"

    t="$tmp/allow"; am_git "$t" auto "$tmp/o1.git"
    am_commit "$t" package.json '{"name":"x"}'
    am_row "$t" package.json "$bs" "$as" Write
    block="$(am_expected_block '- `M package.json` (diff)' \
        "- \`package.json\` before \`${bs:0:12}\` after \`${as:0:12}\` (ledger, Write)")"
    printf 'Summary.\n\n%s\n' "$block" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.001 allow "$t"
    CASES=$((CASES + 1))
    [[ "$(cd "$t" && python3 -I "$LP_HOOK" --guarded-block)" == "$block" ]] \
        || fail loop-record.py G22.009 "--guarded-block does not print the expected block"
    printf 'Summary.\n' >"$t/docs/work/s1/pr-body.md"
    am_pr G22.002 deny "$t" '--guarded-block'
    printf 'Summary.\n\n%s\n' "${block/${as:0:12}/${bs:0:12}}" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.003 deny "$t" '--guarded-block'

    t="$tmp/revert"; am_git "$t" auto "$tmp/o2.git"
    am_row "$t" package.json "$bs" "$as" Write
    printf 'Summary.\n\n%s\n' "$(am_expected_block '- none')" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.004 deny "$t" '--guarded-block'
    block="$(am_expected_block "- \`package.json\` before \`${bs:0:12}\` after \`${as:0:12}\` (ledger, Write)")"
    CASES=$((CASES + 1))
    [[ "$(cd "$t" && python3 -I "$LP_HOOK" --guarded-block)" == "$block" ]] \
        || fail loop-record.py G22.004b "--guarded-block does not print the reverted row's ledger line"
    printf 'Summary.\n\n%s\n' "$block" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.004c allow "$t"

    t="$tmp/failure"; am_git "$t" auto "$tmp/o3.git"
    am_commit "$t" "$x" "describe('x', () => {
  it('U2 returns err on empty input', () => {
    expect(f(0)).toBe(-1)
  })
})"
    printf 'Summary.\n\n%s\n' "$(am_expected_block "- GUARD FAILURE: $x U2 changed with no ledger row" \
        "- \`M $x\` (diff)")" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.005 allow "$t"

    t="$tmp/moi"; am_git "$t" moi "$tmp/o4.git"
    am_commit "$t" package.json '{"name":"x"}'
    printf 'Summary.\n' >"$t/docs/work/s1/pr-body.md"
    am_pr G22.006 allow "$t"

    t="$tmp/nofetch"; am_git "$t" auto "$tmp/o5.git"
    printf 'Summary.\n\n%s\n' "$(am_expected_block '- none')" >"$t/docs/work/s1/pr-body.md"
    git -C "$t" remote set-url origin "$tmp/missing.git"
    am_pr G22.007 deny "$t" 'Guarded files touched'

    t="$tmp/none"; am_git "$t" auto "$tmp/o6.git"
    am_commit "$t" src/b.ts 'export const b = 1'
    printf 'Summary.\n\n%s\n' "$(am_expected_block '- none')" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.008 allow "$t"

    t="$tmp/deleted"; am_git "$t" auto "$tmp/o7.git"
    git -C "$t" rm -q "$x"
    git -C "$t" commit -q -m "drop $x"
    block="$(am_expected_block "- GUARD FAILURE: $x U2 changed with no ledger row" "- \`D $x\` (diff)")"
    CASES=$((CASES + 1))
    [[ "$(cd "$t" && python3 -I "$LP_HOOK" --guarded-block)" == "$block" ]] \
        || fail loop-record.py G22.010 "--guarded-block does not list the deleted test file as a U2 failure and a D diff line"
    printf 'Summary.\n\n%s\n' "$block" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.010b allow "$t"
    printf 'Summary.\n\n%s\n' "$(am_expected_block '- none')" >"$t/docs/work/s1/pr-body.md"
    am_pr G22.010c deny "$t" '--guarded-block'
    rm -rf "$tmp"
}

# am_released <dir>: turns the tree's auto record into a released one (what `--release` writes on a
# blocked record): mode moi, released_at, no mark.
am_released() {
    jq '.mode = "moi" | .released_at = "2026-11-23T00:00:00Z" | del(.blocked, .blocked_at)' \
        "$1/.claude/.loop-record.json" >"$1/.claude/r.x"
    mv "$1/.claude/r.x" "$1/.claude/.loop-record.json"
}

# AM64, G21.043 (blocked-record lifecycle): a released record keeps its ledger in the PR body
# (--guarded-block and the byte check, as in auto) and never allows the pass's push or PR.
run_released_record_cases() {
    local tmp t bs as block
    tmp="$(mktemp -d)"
    bs="$(printf '{}\n' | sha256sum | cut -c1-64)"
    as="$(printf '{"name":"x"}\n' | sha256sum | cut -c1-64)"

    # AM64 --guarded-block on a released record on its branch prints the block with its ledger rows.
    t="$tmp/rel"; am_git "$t" auto "$tmp/o1.git"
    am_commit "$t" package.json '{"name":"x"}'
    am_row "$t" package.json "$bs" "$as" Write
    am_released "$t"
    block="$(am_expected_block '- `M package.json` (diff)' \
        "- \`package.json\` before \`${bs:0:12}\` after \`${as:0:12}\` (ledger, Write)")"
    CASES=$((CASES + 1))
    [[ "$(cd "$t" && python3 -I "$LP_HOOK" --guarded-block)" == "$block" ]] \
        || fail loop-record.py AM64 "--guarded-block does not print a released record's block"
    # G21.043.2 a released record's PR never gets the record allow: with the byte-exact block it asks;
    # G21.043.3 without it it is denied, as in auto. (The push cases G21.043/G21.043.5 are in git-guard.jsonl,
    # setup lpreleased; G21.001/G21.002 and G22.006 stay the plain-record allows.)
    printf 'Summary.\n\n%s\n' "$block" >"$t/docs/work/s1/pr-body.md"
    am_pr G21.043.2 ask "$t" 'acts on a pull request'
    printf 'Summary.\n' >"$t/docs/work/s1/pr-body.md"
    am_pr G21.043.3 deny "$t" '--guarded-block'

    # AM64.2 (guard) a moi plan-go record (no released_at) prints nothing.
    t="$tmp/moi"; am_git "$t" moi "$tmp/o2.git"
    am_row "$t" package.json "$bs" "$as" Write
    CASES=$((CASES + 1))
    [[ -z "$(cd "$t" && python3 -I "$LP_HOOK" --guarded-block)" ]] \
        || fail loop-record.py AM64.2 "--guarded-block printed a block for a moi plan-go record"
    rm -rf "$tmp"
}

# R1, R3, R4, R8 (auto-mode review 1): the lock is agent-proof and --clear works without it, an auto
# record read from the base branch is moi, a non-canonical verdict path records nothing, and the Python
# freeze turns the listed and whole-file fallbacks off in auto.
run_auto_mode_review1_cases() {
    local tmp t out rec p b2 b2new addon mode line want
    tmp="$(mktemp -d)"
    addon="${CWK_ADDON_HOOKS:-$HOOKS_DIR/../../addons/fastapi/hooks}"

    # R1 a Write to the lock is denied; a directory at the lock path does not keep --clear from removing the record.
    am_tree "$tmp/r1" auto
    out="$(pf_probe "$tmp/r1" Write .claude/.loop-record.lock)"
    g15_expect AM-R1 deny "$out" "loop-record.lock"
    mkdir "$tmp/r1/.claude/.loop-record.lock"
    (cd "$tmp/r1" && CWK_HOOK_TIMING=0 python3 -I "$LP_HOOK" --clear </dev/null >/dev/null 2>&1) || true
    CASES=$((CASES + 1))
    [[ ! -e "$tmp/r1/.claude/.loop-record.json" ]] || fail loop-record.py AM-R1.2 "the record survived --clear with a directory at the lock path"

    # R3 an auto record read from its base branch is moi; from its own branch it is auto.
    am_tree "$tmp/r3" auto
    git -C "$tmp/r3" switch -q audit/x
    CASES=$((CASES + 1)); out="$(am_mode_cli "$tmp/r3")"
    [[ "$out" == moi ]] || fail loop-record.py AM-R3 "--mode on the base branch: expected moi, got '$out'"
    am_mode AM-R3.2 "auto rec on base" "$tmp/r3" 1
    git -C "$tmp/r3" switch -q feat/s1
    CASES=$((CASES + 1)); out="$(am_mode_cli "$tmp/r3")"
    [[ "$out" == auto ]] || fail loop-record.py AM-R3.3 "--mode on the branch: expected auto, got '$out'"
    am_mode AM-R3.4 "auto rec on branch" "$tmp/r3" 0

    # R4 a verdict block whose path is not canonical records nothing.
    t="$tmp/r4"; am_tree "$t" auto; rec="$t/.claude/.loop-record.json"
    lp_shim "$tmp/sh"
    for p in ./src/a/x.utils.test.ts src/./a/x.utils.test.ts src/../src/a/x.utils.test.ts src//a/x.utils.test.ts /abs/src/a/x.utils.test.ts; do
        lp_run "$(am_stop "$t" arbiter "$(am_block "$p" U2 "$AM_SHA" refuse)" a4)" "$tmp/sh"
        lp_rec AM-R4 "path '$p'" "$rec" '.verdicts | length' 0
    done
    lp_run "$(am_stop "$t" arbiter "$(am_block src/a/x.utils.test.ts U2 "$AM_SHA" refuse)" a4)" "$tmp/sh"
    lp_rec AM-R4.2 "canonical path" "$rec" '.verdicts | length' 1

    # R8 AM47 in Python: auto, no verdict, a listed or whole-file line unfreezes nothing; moi keeps both.
    b2=$'def test_b2_returns_err():\n    assert g(0) == 0'
    b2new=$'def test_b2_returns_err_on_empty():\n    assert g(0) == -1'
    for p in "auto-listed|auto|tests/services/test_b.py  # B2: r|deny" "auto-whole|auto|tests/services/test_b.py reason|deny" \
             "moi-listed|moi|tests/services/test_b.py  # B2: r|pass" "moi-whole|moi|tests/services/test_b.py reason|pass"; do
        IFS='|' read -r t mode line want <<<"$p"
        lp_py_project "$tmp/py-$t"
        printf '%s\n' "$line" >"$tmp/py-$t/.claude/.tdd-unfrozen"
        am_freeze_rec "$tmp/py-$t" "$mode" '[]'
        pv_expect "AM47-py $t" "$want" \
            "$(rv2_pair "$addon" tdd-freeze-tests-py.py "$tmp/py-$t" "$(jq -cn --arg f "$tmp/py-$t/tests/services/test_b.py" --arg c "$tmp/py-$t" \
                --arg o "$b2" --arg n "$b2new" '{tool_name:"Edit", cwd:$c, tool_input:{file_path:$f, old_string:$o, new_string:$n}}')")"
    done
    rm -rf "$tmp"
}

# N1 (auto-mode review 2): `git switch -c <branch> <start>` joins the strict grammar only when <start> is a
# local branch and not also a tag; a sha, a remote ref, HEAD, @, a missing branch or a clash stays an ask.
run_auto_mode_review2_cases() {
    local tmp sha out
    tmp="$(mktemp -d)"
    make_seed_repo "$tmp/r"
    git -C "$tmp/r" branch audit/x
    git -C "$tmp/r" branch both
    git -C "$tmp/r" tag both
    git -C "$tmp/r" tag v1
    sha="$(git -C "$tmp/r" rev-parse HEAD)"

    out="$(git_hook_probe "git switch -c feat/s9 audit/x" "$tmp/r" "$tmp/r")"
    g15_expect G22.011 pass "$out"
    out="$(git_hook_probe "git switch -c feat/s9 v1" "$tmp/r" "$tmp/r")"
    g15_expect G22.012 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 $sha" "$tmp/r" "$tmp/r")"
    g15_expect G22.013 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 origin/main" "$tmp/r" "$tmp/r")"
    g15_expect G22.014 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 nope" "$tmp/r" "$tmp/r")"
    g15_expect G22.015 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 both" "$tmp/r" "$tmp/r")"
    g15_expect G22.016 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 -x" "$tmp/r" "$tmp/r")"
    g15_expect G22.017 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 HEAD" "$tmp/r" "$tmp/r")"
    g15_expect G22.018 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9 @" "$tmp/r" "$tmp/r")"
    g15_expect G22.019 ask "$out" "git switch -c <branch> <local branch>"
    out="$(git_hook_probe "git switch -c feat/s9  audit/x" "$tmp/r" "$tmp/r")"
    g15_expect G22.020 ask "$out" "git switch -c <branch> <local branch>"
    rm -rf "$tmp"
}

set -e
if [[ "${1:-}" == --guard-only ]]; then
    run_shell_guard_cases
    run_git_foreign_repo_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (shell and git guard only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --am-only ]]; then
    run_auto_mode_step1_cases
    run_auto_mode_step2_cases
    run_auto_mode_step3_cases
    run_auto_mode_step4_cases
    run_auto_mode_import_cases
    run_auto_mode_step5_cases
    run_released_record_cases
    run_auto_mode_review1_cases
    run_auto_mode_review2_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (auto-mode only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --lp6-only ]]; then
    run_loop_to_pr_review6_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (loop-to-pr review 6 only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --lp5-only ]]; then
    run_loop_to_pr_review5_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (loop-to-pr review 5 only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --lp4-only ]]; then
    run_loop_to_pr_review4_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (loop-to-pr review 4 only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --lp3-only ]]; then
    run_loop_to_pr_review3_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (loop-to-pr review 3 only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --trial-only ]]; then
    run_pw_cases
    run_git_guard_cases
    run_trial_auto_git_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (agent-ia trial fixes only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" == --lp-only ]]; then
    run_loop_to_pr_hash_cases
    run_loop_to_pr_review3_cases
    run_loop_to_pr_review4_cases
    run_loop_to_pr_review5_cases
    run_loop_to_pr_review6_cases
    run_loop_to_pr_step6_cases
    run_loop_to_pr_step5_cases
    run_loop_to_pr_step4_cases
    run_unfrozen_removal_cases
    run_loop_to_pr_step2_cases
    run_git_guard_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (loop-to-pr only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
[[ "${1:-}" == --kb-only ]] || run_fixture_sweep
if [[ "${1:-}" == --kb-only ]]; then
    run_kit_boundary_step1_cases
    run_kit_boundary_step2_cases
    run_kit_boundary_step3_cases
    run_kit_boundary_step4_cases
    run_kit_boundary_review1_cases
    run_kit_boundary_review1_git_cases
    run_kit_boundary_review2_shell_cases
    run_kit_boundary_review2_git_cases
    run_kit_boundary_review3_git_cases
    run_kit_boundary_ship_cases
    run_kit_prompts_step1_cases
    run_kit_prompts_step23_cases
    run_kit_prompts_step4_cases
    [[ "$FAILURES" -eq 0 ]] || { printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2; exit 1; }
    printf 'Hook fixtures (kit-boundary only): %d case(s), all green.\n' "$CASES"
    exit 0
fi
if [[ "${1:-}" != --fixtures-only ]]; then
    run_kit_boundary_step1_cases
    run_kit_boundary_step2_cases
    run_kit_boundary_step3_cases
    run_kit_boundary_step4_cases
    run_kit_boundary_review1_cases
    run_kit_boundary_review1_git_cases
    run_kit_boundary_review2_shell_cases
    run_kit_boundary_review2_git_cases
    run_kit_boundary_review3_git_cases
    run_kit_boundary_ship_cases
    run_kit_prompts_step1_cases
    run_kit_prompts_step23_cases
    run_kit_prompts_step4_cases
    run_loop_to_pr_step2_cases
    run_loop_to_pr_step4_cases
    run_loop_to_pr_step5_cases
    run_loop_to_pr_step6_cases
    run_loop_to_pr_hash_cases
    run_loop_to_pr_review3_cases
    run_loop_to_pr_review4_cases
    run_loop_to_pr_review5_cases
    run_loop_to_pr_review6_cases
    run_auto_mode_step1_cases
    run_auto_mode_step2_cases
    run_auto_mode_step3_cases
    run_auto_mode_step4_cases
    run_auto_mode_import_cases
    run_auto_mode_step5_cases
    run_released_record_cases
    run_auto_mode_review1_cases
    run_auto_mode_review2_cases
    run_trial_auto_git_cases
    run_harness_reproduction
    run_harness_edges
    run_missing_jq_cases
    run_guarded_cases
    run_guarded_hardening_cases
    run_unfrozen_removal_cases
    run_freeze_partial_install_case
    run_shell_guard_cases
    run_shell_guard_failure_cases
    run_shell_guard_budget_case
    run_shell_guard_bash3_case
    run_shell_guard_reason_split_case
    run_shell_guard_no_base_case
    run_git_guard_cases
    run_git_add_lock_case
    run_git_add_long_reason_case
    run_git_untrusted_repo_cases
    run_git_linked_worktree_case
    run_git_python_isolation_case
    run_git_secret_scope_cases
    run_git_expanded_dir_cases
    run_git_unsafe_edge_cases
    run_git_restore_planted_case
    run_git_foreign_repo_cases
    run_git_reason_cut_case
    run_project_config_cases
    run_project_config_v2_cases
    run_project_config_review1_cases
    run_project_values_cases
    run_project_values_step3_cases
    run_project_values_step4_cases
    run_project_values_step5_cases
    run_review1_cases
    run_review2_cases
    run_pw_cases
    run_app_roots_cases
    run_app_roots_cfg_cases
    run_codegen_cases
    run_tokenizer_cases
    run_locale_cases
    run_prove_red_symbols
    ADDON_TEST="$HOOKS_DIR/../../addons/fastapi/hooks/test_imported_symbols.py"
    if [[ -f "$ADDON_TEST" ]]; then
        CASES=$((CASES + 1))
        python3 "$ADDON_TEST" || fail tdd-prove-red-py imported_symbols "parser cases failed"
    fi
fi

if [[ "$FAILURES" -gt 0 ]]; then
    printf '%d fixture failure(s) across %d case(s).\n' "$FAILURES" "$CASES" >&2
    exit 1
fi
printf 'Hook fixtures: %d case(s), all green.\n' "$CASES"
