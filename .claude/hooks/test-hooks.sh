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
                    ;;
            esac
            ;;
    esac
    # A tmp project gets the kit's project.json, unless its case is about a missing one.
    if [[ -n "$project_dir" && "$project_dir" != "$PROJECT_ROOT" && -d "$project_dir" \
          && ! -e "$project_dir/.claude/project.json" && "$fixture_name" != *-noconfig-* ]]; then
        seed_project "$project_dir"
    fi

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

    write_project_json "$tmp/p25a" "$(printf '%s' "$v2" | jq -c '.schema_version = 3')"
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
    pv_expect PX13 ask "$(semantic_verdict 0 <(printf '%s' "$out"))
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
        g15_expect "CG28[$cmd]" ask "$out" "unresolved write target"
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
            || fail prevent-destructive-commands.sh "$id[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
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
            || fail prevent-destructive-commands.sh "$id[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
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
    g15_expect "CG60-R2" ask "$out"
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
            || fail prevent-destructive-commands.sh "$id[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
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
            || fail prevent-destructive-commands.sh "$id[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"
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
            || { fail prevent-destructive-commands.sh "$id[$cmd]" "expected ask or deny, got $verdict '${out:0:200}'"; return 0; }
    elif [[ "$verdict" != "$want" ]]; then
        fail prevent-destructive-commands.sh "$id[$cmd]" "expected $want, got $verdict '${out:0:200}'"
        return 0
    fi
    for needle in "$@"; do
        [[ "$out" == *"$needle"* ]] || fail prevent-destructive-commands.sh "$id[$cmd]" "reason lacks '$needle': '${out:0:300}'"
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
    run_project_config_v2_cases
    run_project_config_review1_cases
    run_project_values_cases
    run_project_values_step3_cases
    run_project_values_step4_cases
    run_project_values_step5_cases
    run_review1_cases
    run_review2_cases
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
