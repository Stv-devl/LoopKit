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
    local tmp input stdout_file stderr_file code verdict fixture_name extra_marker="" project_dir="$PROJECT_ROOT"
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
                    git -C "$tmp" add src/x.ts .env.example
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
                    ;;
            esac
            ;;
    esac

    set +e
    ( cd "$hook_pwd" && printf '%s' "$input" | PATH="$hook_path" HOME="$hook_home" TMPDIR="$hook_tmp" CLAUDE_PROJECT_DIR="$project_dir" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
        ${CASE_TIMEOUT[@]+"${CASE_TIMEOUT[@]}"} "$HOOKS_DIR/$hook" >"$stdout_file" 2>"$stderr_file" )
    code=$?
    set -e
    verdict="$(semantic_verdict "$code" "$stdout_file")"
    CASES=$((CASES + 1))
    if [[ "$code" -eq 124 || "$code" -eq 137 ]]; then
        fail "$hook" "$(basename "$fixture")" "the hook did not finish within ${CASE_SECONDS}s (killed, exit $code)"
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
    git -C "$tmp" add x.ts
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
    git -C "$1" add x.ts
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
    g15_expect PC15 pass "$out"

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
    g15_expect PC16 pass "$out"

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
    g15_expect AR8 pass "$out"

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
    [[ "$(grep -c 'project_config.py roots' "$tmp/pylog" 2>/dev/null || true)" -le 1 ]] \
        || fail hook-guarded.sh AR27 "the reader ran $(grep -c 'project_config.py roots' "$tmp/pylog") times in one hook run"
    CASES=$((CASES + 1))
    [[ "$(grep -c 'project_config.py roots' "$tmp/pylog" 2>/dev/null || true)" -ge 1 ]] \
        || fail hook-guarded.sh AR27 "the reader never ran: the case proves nothing"

    mkdir -p "$tmp/shim3"
    printf '#!/bin/sh\ncase "$*" in *project_config.py*) echo frontend; exit 3 ;; esac\nexec %s "$@"\n' \
        "$(command -v python3)" >"$tmp/shim3/python3"
    chmod +x "$tmp/shim3/python3"
    out="$(PATH="$tmp/shim3:$PATH" pf_probe "$tmp/a" Edit frontend/vite.config.ts)"
    g15_expect AR30 pass "$out"

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
    g15_expect CG19 pass "$out"

    : >"$c/src/features/a/a.utils.ts"
    : >"$c/app/a.py"
    for cmd in 'echo x > src/features/a/a.utils.t[s]' 'echo x > src/b.t[s]' 'echo x > src/b.t?' 'echo x >> src/b.t[s]' \
        'echo x > app/a.p[y]' 'cp /etc/hostname src/features/a/a.utils.t[s]' \
        'sed -i s/a/b/ src/features/a/a.utils.t[s]' 'echo x | tee src/features/a/a.utils.t[s]' \
        'supabase gen types > src/types/d.t[s]'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG28[$cmd]" ask "$out" "unresolved write target"
    done
    for cmd in 'cat src/*.ts > /tmp/out.txt' 'ls src/*.ts' 'rm src/*.log' 'sed -i s/a/b/ docs/*.md' 'echo x > docs/*.md' \
        'echo x > /tmp/*.log'; do
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
        g15_expect "CG32[$cmd]" ask "$out" "unresolved write target"
    done
    for cmd in 'echo x > docs/*.md' 'echo x > docs/*.json' 'sed -i s/a/b/ docs/*.md' 'mv /tmp/x docs/*.md'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG33[$cmd]" pass "$out"
    done
    out="$(pd_probe "$c" 'supabase gen types > db[.]ts')"
    g15_expect CG32r ask "$out"
    out="$(pd_probe "$c" 'echo x > src/*[.]ts')"
    g15_expect CG34 ask "$out" "onto a glob that may match a source or test file" "src"
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
        g15_expect "CG37[$cmd]" ask "$out" "unresolved write target"
    done
    for cmd in $'shopt -s nocaseglob\necho x > src/*.TEST.TS' $'shopt -s nocaseglob\necho x > src/*.TS' \
        $'shopt -s nocaseglob\necho x > app/*.PY' 'shopt -s nocaseglob; echo x > src/*.TEST.TS' \
        'shopt -s nocaseglob; echo x > src/*.TS' 'shopt -s nocaseglob; echo x > app/*.PY'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG38[$cmd]" ask "$out" "unresolved write target"
    done
    for cmd in $'shopt -s extglob\necho x > src/!(*.md)' $'shopt -s extglob\necho x > src/a.!(md)' \
        $'shopt -s extglob\necho x > src/a.@(ts)' $'shopt -s extglob\necho x > src/a.+(t|s)' \
        $'shopt -s extglob\ncp /etc/hostname src/a.!(md)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG39[$cmd]" ask "$out" "unresolved write target"
    done
    out="$(pd_probe "$c" 'echo x > src/*/Makefile')"
    g15_expect CG40 ask "$out" "unresolved write target"
    g15_expect CG41 ask "$(pd_probe "$c" 'supabase gen types > db[.]ts')" "guarded path"
    out="$(pd_probe "$c" 'echo x > src/*/a.ts')"
    g15_expect CG42 ask "$out" "a.ts under src"
    # CG43-CG49 (fix batch 4): extglob syntax asks without a literal `shopt` (the option is set by
    # a spelling the text never shows, or by a sourced file); the message names the syntax; a
    # glob without shopt, a failing lowercase step and a lone `]` still ask.
    for cmd in $'sh\'\'opt -s extglob\necho x > src/a.!(md)' $'sh\\opt -s extglob\necho x > src/a.!(md)' \
        $'. f\necho x > src/a.utils.+(ts)' $'source f\necho x > src/a.@(ts)' $'s=sh; ${s}opt -s extglob; echo x > src/a.!(md)' \
        $'. f\ncp /etc/hostname src/a.!(md)' $'. f\necho x >> src/a.+(ts)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG43[$cmd]" ask "$out" "unresolved write target" "extglob syntax"
    done
    g15_expect CG43mv ask "$(pd_probe "$c" $'. f\nmv /tmp/x src/a.!(md)')"
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
        g15_expect "CG45[$cmd]" ask "$out" "unresolved write target"
    done
    for cmd in $'sh\'\'opt -s nocaseglob\necho x > src/*.TS' $'shopt -u nocaseglob\necho x > src/*.TS'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG46[$cmd]" ask "$out" "unresolved write target"
    done
    mkdir -p "$tmp/trfail"
    printf '#!/bin/sh\ncase "$*" in *upper*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v tr)" >"$tmp/trfail/tr"
    chmod +x "$tmp/trfail/tr"
    out="$(PATH="$tmp/trfail:$PATH" pd_probe "$c" 'echo x > docs/*.md')"
    g15_expect CG47 ask "$out" "unresolved write target"
    out="$(pd_probe "$c" 'echo x > src/*/a.json]')"
    g15_expect CG48 ask "$out" "unresolved write target" "may match a source or test file"
    out="$(pd_probe "$c" $'shopt -s extglob\necho x > src/a.!(md)')"
    g15_expect CG39b ask "$out" "uses extglob syntax"
    for cmd in 'echo x > src/a.?(ts)' 'echo x > src/a.*(ts)'; do
        out="$(pd_probe "$c" "$cmd")"
        g15_expect "CG49[$cmd]" ask "$out" "unresolved write target"
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
        g15_expect "CG51[$cmd]" ask "$out" "extglob syntax"
    done
    out="$(pd_probe "$c" $'. f\nsupabase gen types > src/types/db.ts\necho x > src/a.!\\\n(md)')"
    g15_expect CG52 ask "$out" "extglob syntax"
    out="$(pd_probe "$c" $'echo x \\\n> docs/a.md')"
    g15_expect CG53 pass "$out"
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
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}' > "$tmp/X14.01-ask.json"
    operands="$(printf 'f%d ' $(seq 1 70))"
    jq -cn --arg command "rm ${operands}.claude/.tdd-red/m" --arg cwd "__PROJECT_ROOT__" --arg reason "is written only by tdd-prove-red.sh" \
        '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd, _expect_reason: $reason}' > "$tmp/X14.02-deny.json"
    run_case prevent-destructive-commands.sh "$tmp/X14.01-ask.json" ask
    start="$(date +%s%N)"
    sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" "$tmp/X14.01-ask.json" \
        | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" CWK_HOOK_TIMING=0 CWK_HEALTH_LOG=0 \
            "$HOOKS_DIR/prevent-destructive-commands.sh" >/dev/null 2>&1 || true
    end="$(date +%s%N)"
    elapsed_ms=$(((end - start) / 1000000))
    [[ "$elapsed_ms" -lt 2000 ]] \
        || fail prevent-destructive-commands.sh X14.01-ask.json "500-operand rm took ${elapsed_ms} ms, bound is 2000"
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
    for banned in 'mapfile' 'readarray' '[-1]' 'declare -A' 'local -A'; do
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
    [[ "$code" -eq 0 && -z "$out" ]] \
        || fail prevent-destructive-commands.sh "no-base" "expected exit 0 and no output, got $code '${out:0:120}'"
    rm -r "$tmp"
}

set -e
run_fixture_sweep
if [[ "${1:-}" != --fixtures-only ]]; then
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
    run_app_roots_cases
    run_app_roots_cfg_cases
    run_codegen_cases
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
