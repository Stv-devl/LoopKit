#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SURFACE="$HOOKS_DIR/kit-audit-surface.py"
KIT_JSON="$HOOKS_DIR/../project.json"
SCRATCH="$(mktemp -d)"
trap 'rm -r "$SCRATCH"' EXIT
REPO=""
BASE=""
OUT=""
N=0

fail() { echo "$1 failed${2:+: $2}" >&2; exit 1; }
kas() { env -C "$REPO" python3 -I "$SURFACE" "$@"; }
ok() { jq -e "$2" <<<"$OUT" >/dev/null || fail "$1" "$2 on $OUT"; }
surfaces() { ok "$1" "[.surfaces[].surface] == $2"; }
refused() {
    local id="$1" needle="$2" err rc
    shift 2
    set +e
    err="$(env -C "$REPO" python3 -I "$SURFACE" "$@" 2>&1 >/dev/null)"
    rc=$?
    set -e
    [[ $rc -eq 2 ]] || fail "$id" "exit $rc, want 2 ($err)"
    [[ -z "$needle" || "$err" == *"$needle"* ]] || fail "$id" "stderr lacks '$needle': $err"
}
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "${@:2}" >"$REPO/$1"; }
add() { printf '%s\n' "${@:2}" >>"$REPO/$1"; }

# new_repo [server_roots-json|none]: a fresh repo, one base commit, the kit's v3 project.json.
new_repo() {
    local roots="${1:-[\"server\"]}"
    N=$((N + 1))
    REPO="$SCRATCH/r$N"
    mkdir -p "$REPO/.claude"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@example.invalid
    git -C "$REPO" config user.name t
    if [[ "$roots" != none ]]; then
        jq --argjson r "$roots" '.server_roots = $r' "$KIT_JSON" >"$REPO/.claude/project.json"
    fi
    put src/app.tsx 'export const App = () => null;'
    put src/helpers.ts 'export const helper = 1;'
    put src/auth.ts 'export function signOut() {' '  api.logout();' '}'
    put src/form.tsx 'export function Form({ form }) {' '  return null;' '}'
    put src/legacy.ts 'export const a = 1;' 'localStorage.clear();'
    put server/routes/orders.py 'def orders():' '    pass'
    put README.md '# fixture'
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm base
    BASE="$(git -C "$REPO" rev-parse HEAD)"
}
sel() { OUT="$(kas select --base "$BASE")"; }

# ---- Core behaviour ----

new_repo
add src/app.tsx 'export const Title = "Hi";'
put src/util.ts 'export const x = 1;'
sel
surfaces A1 '[]'
ok A1 '.reason == "no server root touched, no trigger line added (2 files)"'

new_repo
add server/routes/orders.py 'def list_orders():' '    pass'
sel
surfaces A2 '["authz"]'
ok A2 '.surfaces[0].reason == "server root `server`: server/routes/orders.py"'

new_repo
put server/services/billing.py 'def bill():' '    pass'
sel
surfaces A3 '["authz"]'

new_repo
git -C "$REPO" mv src/helpers.ts server/helpers.ts
sel
surfaces A4 '["authz"]'

new_repo
git -C "$REPO" rm -q server/routes/orders.py
sel
surfaces A5 '["authz"]'

new_repo
add src/auth.ts 'export async function signOutAll() {' '  queryClient.clear();' '}'
sel
surfaces A6 '["session"]'
ok A6 '.surfaces[0].reason | contains("src/auth.ts:")'

new_repo
add src/app.tsx 'localStorage.removeItem("draft");'
sel
surfaces A7 '["session"]'
ok A7 '.surfaces[0].reason | contains("localStorage") and contains("src/app.tsx:2")'

new_repo
add src/app.tsx 'export const H = ({ html }) => <div dangerouslySetInnerHTML={{ __html: html }} />;'
sel
surfaces A8 '["input-output"]'

new_repo
add src/app.tsx 'export const L = ({ item }) => <a href={item.url}>go</a>;'
sel
surfaces A9 '["input-output"]'

new_repo
add src/app.tsx 'export const U = () => <input type="file" />;'
sel
surfaces A10 '["input-output"]'

new_repo
add server/routes/orders.py 'def list_orders():' '    pass'
add src/app.tsx 'localStorage.setItem("k", "v");'
sel
surfaces A11 '["authz", "session"]'
ok A11 '.surfaces[0].reason == "server root `server`: server/routes/orders.py"'
ok A11 '.surfaces[1].reason | contains("localStorage") and contains("src/app.tsx:2")'

new_repo
put src/auth.ts 'export function signOut() {' '  useCartStore.getState().reset();' '  api.logout();' '}'
sel
surfaces A29 '["session"]'

new_repo
put src/form.tsx 'export function Form({ form }) {' '  form.reset();' '  return null;' '}'
sel
surfaces A30 '[]'

# ---- Business rules ----

new_repo
put src/legacy.ts 'export const a = 1;'
sel
surfaces A12 '["session"]'
ok A12 '.surfaces[0].reason | contains("localStorage") and contains("removed") and contains("src/legacy.ts")'
new_repo
put src/view.tsx 'export const V = ({ html }) => <div dangerouslySetInnerHTML={{ __html: html }} />;'
git -C "$REPO" add -A
git -C "$REPO" commit -qm 'view with html'
BASE="$(git -C "$REPO" rev-parse HEAD)"
put src/view.tsx 'export const V = () => null;'
sel
surfaces A12 '[]'

new_repo
add src/app.tsx '// localStorage later'
sel
surfaces A13 '[]'

new_repo '[]'
add server/routes/orders.py 'def list_orders():' '    pass'
sel
surfaces A14 '[]'
ok A14 '.reason | startswith("no server root declared, no trigger line added (")'

new_repo
put src/app.test.tsx 'localStorage.clear();'
put docs/notes.md 'dangerouslySetInnerHTML'
add README.md 'localStorage'
sel
surfaces A15 '[]'

new_repo
add src/app.tsx 'export const A = () => <a href="/about">about</a>;'
sel
surfaces A16 '[]'

new_repo
add src/app.tsx 'const token = theme.tokens.primary;'
sel
surfaces A17 '[]'

new_repo
add src/app.tsx 'const headers = { Authorization: `Bearer ${t}` };'
sel
surfaces A18 '["session"]'

new_repo
put src/orders.gateway.ts 'export const Row = z.object({ id: z.string() });'
sel
surfaces A19 '["input-output"]'
new_repo
put src/OrderCard.tsx 'export const Row = z.object({ id: z.string() });'
sel
surfaces A19 '[]'

new_repo
put src/webhooks/stripe.ts 'export const handler = 1;'
sel
surfaces A20 '["input-output"]'

new_repo
add src/app.tsx 'export const H = ({ html }) => <div dangerouslySetInnerHTML={{ __html: html }} />;' \
    'localStorage.setItem("a", "1");' 'sessionStorage.setItem("b", "2");'
add src/helpers.ts 'document.cookie = "c=3";'
add server/routes/orders.py 'def list_orders():' '    pass'
sel
surfaces A21 '["authz", "session", "input-output"]'

new_repo
add server/routes/orders.py 'def list_orders():' '    pass'
git -C "$REPO" commit -qam 'on the branch'
sel
surfaces A22 '["authz"]'

# ---- Review 1 ----

# A32 a user's diff.noprefix must not hide the added lines of a tracked file.
new_repo
git -C "$REPO" config diff.noprefix true
add src/app.tsx 'localStorage.removeItem("draft");'
sel
surfaces A32 '["session"]'

# A33 a tracked path with a space (git appends a TAB to its +++ label) is still read.
new_repo
put 'src/upload/Upload Form.tsx' 'export const U = () => null;'
git -C "$REPO" add -A
git -C "$REPO" commit -qm 'spaced path'
BASE="$(git -C "$REPO" rev-parse HEAD)"
add 'src/upload/Upload Form.tsx' 'export const F = () => <input type="file" />;'
sel
surfaces A33 '["input-output"]'

# A34 an added line that starts with "++ " is a line, not a +++ header.
new_repo
add src/app.tsx '++ <input type="file" />'
sel
surfaces A34 '["input-output"]'

# A35 a path git quotes (a double quote in the name) is still read.
new_repo
put 'src/we"ird.tsx' 'export const W = () => null;'
git -C "$REPO" add -A
git -C "$REPO" commit -qm 'quoted path'
BASE="$(git -C "$REPO" rev-parse HEAD)"
add 'src/we"ird.tsx' 'export const F = () => <input type="file" />;'
sel
surfaces A35 '["input-output"]'

# A36 a server root is one path segment: apps/api would never match the first segment of a path.
new_repo '["apps/api"]'
add src/app.tsx 'export const Title = "Hi";'
refused A36 server_roots select --base "$BASE"

# A37 a reader without server_roots refuses (exit 2), never crashes with another code.
new_repo
mkdir -p "$SCRATCH/stub"
cp "$SURFACE" "$SCRATCH/stub/kit-audit-surface.py"
printf '%s\n' 'import collections' 'class ConfigError(Exception):' '    status = 3' \
    'def load_strict(project_dir):' '    return collections.namedtuple("C", "app_roots")(())' \
    >"$SCRATCH/stub/project_config.py"
set +e
a37_err="$(env -C "$REPO" python3 -I "$SCRATCH/stub/kit-audit-surface.py" select --base "$BASE" 2>&1 >/dev/null)"
a37_rc=$?
set -e
[[ $a37_rc -eq 2 ]] || fail A37 "exit $a37_rc, want 2 ($a37_err)"
[[ "$a37_err" == *server_roots* ]] || fail A37 "stderr lacks server_roots: $a37_err"

# A38 the cache-reset triggers decide on their own, with no session identifier around.
new_repo
add src/app.tsx 'export function refreshOrders() {' '  queryClient.removeQueries({ queryKey: ["orders"] });' '}'
sel
surfaces A38 '["session"]'
ok A38 '.surfaces[0].reason | contains(".removeQueries(") and contains("src/app.tsx:")'

# A39 a trigger under docs/ or .claude/ is skipped even when the file is not markdown.
new_repo
put docs/x.tsx 'localStorage.setItem("k", "v");'
put .claude/x.ts 'localStorage.setItem("k", "v");'
sel
surfaces A39 '[]'

# A40 a removed reset with no session identifier around it selects nothing.
new_repo
put src/form.tsx 'export function Form({ form }) {' '  form.reset();' '  return null;' '}'
git -C "$REPO" add -A
git -C "$REPO" commit -qm 'form reset'
BASE="$(git -C "$REPO" rev-parse HEAD)"
put src/form.tsx 'export function Form({ form }) {' '  return null;' '}'
sel
surfaces A40 '[]'

# A41 a removed comment line naming a trigger selects nothing.
new_repo
put src/app.tsx 'export const App = () => null;' '// localStorage note'
git -C "$REPO" add -A
git -C "$REPO" commit -qm 'note'
BASE="$(git -C "$REPO" rev-parse HEAD)"
put src/app.tsx 'export const App = () => null;'
sel
surfaces A41 '[]'

# A42 a project root that is a subfolder of the git repo still reads a tracked file's added lines.
new_repo
mkdir -p "$REPO/web/.claude" "$REPO/web/src"
cp "$REPO/.claude/project.json" "$REPO/web/.claude/project.json"
put web/src/auth.ts 'export const a = 1;'
git -C "$REPO" add -A
git -C "$REPO" commit -qm 'web root'
BASE="$(git -C "$REPO" rev-parse HEAD)"
add web/src/auth.ts 'localStorage.removeItem("t");'
OUT="$(env -C "$REPO/web" python3 -I "$SURFACE" select --base "$BASE")"
surfaces A42 '["session"]'

# ---- Follow-ups ----

T="docs/work/t"
fin() { mkdir -p "$REPO/$T"; printf '%s\n' "$@" | jq -sc '{findings: .}' >"$REPO/$T/audit-1.json"; }
fu() { OUT="$(kas follow-ups "$T/audit-1.json")"; }
has_line() { grep -Fxq -- "$2" "$REPO/$T/follow-ups.md" || fail "$1" "follow-ups.md lacks: $2"; }
count_line() { grep -Fxc -- "$2" "$REPO/$T/follow-ups.md" || true; }

new_repo
fin '{"surface":"input-output","severity":"Major","path":"src/a.tsx","line":12,"problem":"problem A"}' \
    '{"surface":"input-output","severity":"Minor","path":"src/b.tsx","line":3,"problem":"problem B"}'
fu
has_line A23 '- [audit:input-output] src/a.tsx:12 — problem A (major)'
has_line A23 '- [audit:input-output] src/b.tsx:3 — problem B (minor)'
ok A23 '.follow_ups_added == 2 and .next == "clear" and .critical == 0 and .major == 1 and .minor == 1'
ok A23 '.follow_ups == "docs/work/t/follow-ups.md"'

new_repo
fin '{"surface":"authz","severity":"Critical","path":"server/x.py","line":5,"problem":"crit"}' \
    '{"surface":"session","severity":"Minor","path":"src/c.ts","line":7,"problem":"minor C"}'
fu
ok A24 '.critical == 1 and .next == "stop" and .follow_ups_added == 1'
has_line A24 '- [audit:session] src/c.ts:7 — minor C (minor)'
! grep -Fq 'crit' "$REPO/$T/follow-ups.md" || fail A24 "a Critical was written to follow-ups.md"

new_repo
mkdir -p "$REPO/$T"
printf '%s\n' '- [correctness] src/x.ts:3 — kept (minor)' >"$REPO/$T/follow-ups.md"
fin '{"surface":"authz","severity":"Major","path":"server/y.py","line":9,"problem":"problem E"}'
fu
ok A25 '.follow_ups_added == 1'
fu
ok A25 '.follow_ups_added == 0'
[[ "$(count_line A25 '- [correctness] src/x.ts:3 — kept (minor)')" == 1 ]] || fail A25 "review line not kept once"
[[ "$(count_line A25 '- [audit:authz] server/y.py:9 — problem E (major)')" == 1 ]] || fail A25 "audit line not once"

new_repo
fin '{"surface":"supply-chain","severity":"Minor","path":"package.json","line":null,"problem":"problem D"}'
fu
has_line A31 '- [audit:supply-chain] package.json — problem D (minor)'

# ---- Edge cases and refusals ----

new_repo none
add src/app.tsx 'export const Title = "Hi";'
refused A26 project.json select --base "$BASE"
printf '{\n' >"$REPO/.claude/project.json"
refused A26 "" select --base "$BASE"

new_repo
refused A27 "" select --base 0000000000000000000000000000000000000000

new_repo
mkdir -p "$REPO/docs/work"
printf '%s\n' '{"findings":[]}' >"$REPO/docs/work/audit-1.json"
refused A28 "" follow-ups docs/work/audit-1.json
fin '{"surface":"authz","severity":"Major","path":"a.py","line":1,"problem":"p"}'
refused A28 "" follow-ups "$REPO/$T/audit-1.json"
fin '{"surface":"authz","severity":"Blocker","path":"a.py","line":1,"problem":"p"}'
refused A28 "" follow-ups "$T/audit-1.json"
fin '{"surface":"network","severity":"Major","path":"a.py","line":1,"problem":"p"}'
refused A28 "" follow-ups "$T/audit-1.json"
fin '{"surface":"authz","severity":"Major","path":"a.py","line":1}'
refused A28 "" follow-ups "$T/audit-1.json"
[[ ! -e "$REPO/$T/follow-ups.md" ]] || fail A28 "a refused input wrote follow-ups.md"

echo 'audit-surface fixtures: green.'
