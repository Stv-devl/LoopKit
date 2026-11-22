#!/usr/bin/env bash
# cwk-guard-api: 1
#
# Hook: tdd-freeze-tests
# Event: PreToolUse (Write|Edit)
# Purpose: Once written and validated at the /loop:plan gate, a test file of the three
#          test-first layers is immutable for the rest of the feature. The
#          implementation bends to the test, never the reverse.
#          Scope + rationale: .claude/rules/05-testing.md ("Test-first").
#
# Creating the file is always allowed (that IS the RED phase). Only editing an
# existing one is blocked.
#
# One edit is NOT blocked: appending a new case. Canon TDD keeps the test list
# alive — you add to it as you learn — and a freeze that forbids growth pushes
# the agent to either drop the case silently or work around the freeze. So a pure
# insertion that touches no existing assertion goes through, and is announced.
# Everything else — rewriting an assertion, renaming an `it()`, deleting a case,
# overwriting the file wholesale — is denied.
#
# "Touches no existing assertion" is not enough on its own, and that is the whole
# subtlety of this hook. Anchoring on the `it(...) => {` line of an existing case
# and inserting `return;` leaves every assertion byte-for-byte intact and kills
# the case anyway — and the lint does not see it either, since `expect-expect` is
# lexical and the now-unreachable `expect()` is still there. So an insertion must
# also: land outside every case body (computed, not inferred from the anchor's
# first line), carry its own assertion, introduce no control flow that can skip
# what already runs, and shadow nothing the file imports from the module under
# test — a `const total = () => 5` at describe scope is a mock without the word.
#
# Escape hatch: list the path in .claude/.tdd-unfrozen, one per line, as
# `<path>  # <reason>`. The reason may also follow the path with no `#` — both
# spellings are read, because both are prescribed by the deny texts below.
# Making the exception visible is the point — it is a plan-level correction, not
# a silent edit. The same list exempts an implementation file from
# tdd-require-red.sh.
#

set -e
# shellcheck disable=SC2034  # read by the sourced hook-lib.sh
CWK_GUARD_HOOK=1
source "$(dirname "${BASH_SOURCE[0]}")/hook-lib.sh"
cwk_require_jq
# shellcheck disable=SC2034  # read by hook-lib.sh's exit trap
CWK_DEGRADED_ASK=1
if ! declare -F cwk_config cwk_tdd_load cwk_cfg_reason >/dev/null 2>&1; then
    echo "BLOCKED: hook-lib.sh is older than this hook (no cwk_config/cwk_tdd_load), so this guard refuses rather than passes. The user re-copies the kit's .claude/hooks/ files from a terminal." >&2
    exit 2
fi

# Read JSON from stdin
INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# jq, never a heredoc: these reasons interpolate $FILE_PATH, and a path holding a
# `"` produced unparseable JSON — which the harness DROPS, so the deny vanished
# with no message at all. Only the authored `\n` is expanded; every other backslash is left alone.
deny() {
    local reason
    cwk_cfg_reason "${1//\\n/$'\n'}"
    reason="$CWK_CFG_OUT"
    cwk_log_health_deny "$reason"
    jq -n --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

# An allowed edit, announced. With the config unreadable the allow becomes an ask carrying the
# same text and the config note: one JSON object, never a message beside the degraded ask.
notice() {
    cwk_cfg_reason "$1"
    if [[ "${CWK_CFG_DEGRADED:-0}" == 1 ]]; then
        jq -n --arg r "$CWK_CFG_OUT" '{hookSpecificOutput: {hookEventName: "PreToolUse",
            permissionDecision: "ask", permissionDecisionReason: $r}}'
    else
        jq -n --arg m "$1" '{systemMessage: $m}'
    fi
    exit 0
}

# A test file or one of its fixtures, read on the path relative to the project
# root and normalised: a project that itself sits under a `tests/` folder, or a
# `src/tests/../x.ts`, must not pass for test support.
# A hook-lib.sh of the previous kit defines no CWK_TEST_FILE_RE, and an empty
# regex matches every path: refuse rather than freeze (or free) the wrong files.
[[ -n "${CWK_TEST_FILE_RE:-}" ]] \
    || deny "hook-lib.sh is stale: it defines no CWK_TEST_FILE_RE, so the test files cannot be told from the rest. Merge hook-lib.sh.new (or re-run install.sh), then retry."
TEST_FILE_RE="$CWK_TEST_FILE_RE"
TEST_SUPPORT_RE='(^|/)(tests?|__tests__|__mocks__|__fixtures__|fixtures|e2e)/|\.fixtures?\.[cm]?[jt]sx?$'

# The test-writer holds Edit to append a case to a frozen file, and nothing else:
# a test written next to the code it is about to pass is no longer independent.
# `agent_type` is set by Claude Code when the call comes from a sub-agent.
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
if [[ "$AGENT_TYPE" == test-writer && ! "$FILE_PATH" =~ $TEST_FILE_RE ]]; then
    REL_PATH=$(python3 -I -c 'import os, sys; p, r = (os.path.normpath(a) for a in sys.argv[1:]); print(os.path.relpath(p, r) if p.startswith(r + os.sep) else p)' \
        "$FILE_PATH" "${CLAUDE_PROJECT_DIR:-$PWD}") \
        || deny "test-writer write to '$FILE_PATH' refused: python3 is needed to read the path against the project root and is not available."
    [[ "$REL_PATH" =~ $TEST_SUPPORT_RE ]] || deny "test-writer may only write test files and their fixtures; '$FILE_PATH' is neither (.claude/agents/test-writer.md). Return the failing output instead: the implementation is written after the RED, by the session or the implementer."
fi

# A raw invisible space in a test is indistinguishable from a plain one on screen,
# and every later edit anchored on that line misses it — the frozen file then
# needs an unfreeze to change nothing. fr-FR `Intl` output is full of U+202F.
# Only what the write ADDS counts: an anchor that already holds one is copied.
if [[ "$FILE_PATH" =~ $TEST_FILE_RE ]] \
   && echo "$INPUT" | jq -e '"[\u00a0\u202f\u2007\u200b\u2060\ufeff]" as $raw
        | def count: [match($raw; "g")] | length;
        ((.tool_input.content // .tool_input.new_string // "") | count)
        > ((.tool_input.old_string // "") | count)' > /dev/null; then
    deny "Raw invisible character (no-break space U+00A0, narrow no-break space U+202F, zero-width space or BOM) in the content written to '$FILE_PATH'. Write its escape in the source instead (\\u00a0, \\u202f); in the tool payload, that backslash is doubled. A raw one cannot be told apart from a space when the case is later edited."
fi

# A tree with its own toolchain never entered the cycle (tdd-require-red and
# tdd-prove-red both skip it), so there is nothing to freeze — and freezing it
# would lock a file no red ever validated. See hook-lib.sh.
if cwk_foreign_toolchain "$FILE_PATH"; then
    exit 0
fi

# Only the three test-first layers. hooks.test.tsx, *.gateway.test.ts and
# component tests are written AFTER the code — they are not frozen.
[[ "$FILE_PATH" == *.test.ts || "$FILE_PATH" == *.test.tsx ]] || exit 0
cwk_tdd_load || true
if [[ ! "$FILE_PATH" =~ $CWK_TDD_TEST_RE ]]; then
    exit 0
fi

# The file does not exist yet: this is the RED phase, let it through.
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Rows mode (docs/specs/loop-to-pr.md, step 5). A path the tree's valid loop record holds rows for
# is not exempted whole by its .tdd-unfrozen line: `has` says whether it has rows, `check` reads
# the Edit and decides it case by case. Every case whose span in the current file meets the
# replaced text must be a row, whose title in the resulting file is a plain-quoted literal hashing
# to the row, or an id listed on a .tdd-unfrozen line for this path (a batch the user approved).
# `check` prints the deny reason and exits 1, or exits 0.
freeze_rows() {
    python3 -I -c '
import hashlib, json, os, re, subprocess, sys
mode, path, listing = sys.argv[1], sys.argv[2], sys.argv[3]
tree_dir = os.path.dirname(path)
def git(*args):
    try:
        done = subprocess.run(["git", "-C", tree_dir, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() if done.returncode == 0 else None
tree = git("rev-parse", "--show-toplevel")
if not tree:
    sys.exit(1)
rec_path = os.path.join(tree, ".claude", ".loop-record.json")
try:
    if os.path.islink(rec_path):
        sys.exit(1)
    with open(rec_path, encoding="utf-8") as fh:
        rec = json.load(fh)
except (OSError, ValueError):
    sys.exit(1)
if not isinstance(rec, dict) or rec.get("version") != 1 or not isinstance(rec.get("rows"), list):
    sys.exit(1)
head = git("symbolic-ref", "-q", "--short", "HEAD")
if not head:
    sys.exit(1)
if head != rec.get("branch"):
    sha = rec.get("base_sha")
    if head != rec.get("base") or not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        sys.exit(1)
    if git("merge-base", "--is-ancestor", sha, "HEAD") is None:
        sys.exit(1)
rel = os.path.relpath(os.path.realpath(path), os.path.realpath(tree))
rows = {r.get("id"): r.get("sha256") for r in rec["rows"] if isinstance(r, dict) and r.get("path") == rel}
auto = sys.argv[4] == "1"
refused = set()
if auto:
    for v in rec.get("verdicts") or []:
        if isinstance(v, dict) and v.get("kind") == "frozen-case" and v.get("path") == rel:
            if v.get("verdict") == "unfreeze" and v.get("id") not in rows:
                rows[v.get("id")] = v.get("sha256")
            elif v.get("verdict") == "refuse":
                refused.add(v.get("id"))
if mode == "has":
    sys.exit(0 if rows else 1)
def refuse(reason):
    print(reason)
    sys.exit(1)
listed = set()
try:
    with open(listing, encoding="utf-8") as fh:
        for line in fh:
            m = re.fullmatch(r"(\S+)[ \t]+#[ \t]*([UMRB][0-9]+!?(?:[ \t]*,[ \t]*[UMRB][0-9]+!?)*)[ \t]*:.*", line.strip())
            if m and "/" in m.group(1) and m.group(1) in path:
                for tok in re.split(r"[ \t]*,[ \t]*", m.group(2)):
                    listed.add(tok.rstrip("!"))
except OSError:
    pass
if auto:
    listed = set()
data = json.load(sys.stdin)
ti = data.get("tool_input") or {}
if data.get("tool_name") != "Edit":
    refuse("a Write replaces the whole frozen file; edit the amended cases one by one with Edit")
old, new = ti.get("old_string"), ti.get("new_string")
with open(path, encoding="utf-8") as fh:
    current = fh.read()
if not isinstance(old, str) or not isinstance(new, str) or not old or ti.get("replace_all") is True:
    refuse("rows mode takes one Edit with a non-empty old_string, never replace_all")
start = current.find(old)
if start < 0:
    refuse("the old_string does not appear in the file as it stands")
result = current[:start] + new + current[start + len(old):]
CALL = re.compile(r"(?<![A-Za-z0-9_$.])(?:it|test)(?:(?:\.[A-Za-z]+)*[ \t]*\(|(?:\.[A-Za-z]+)+[ \t]*`)")
def skip_string(s, i):
    q, i = s[i], i + 1
    while i < len(s) and s[i] != q:
        i += 2 if s[i] == "\\" else 1
    return i + 1
def opens_regex(s, k):
    j = k - 1
    while j >= 0 and s[j] in " \t":
        j -= 1
    if j < 0 or s[j] in "\n(,=:[!&|?{};":
        return True
    if s[j] == ">" and j and s[j - 1] == "=":
        return True
    return bool(re.search(r"(?:^|[^A-Za-z0-9_$.])(?:return|typeof)$", s[max(0, j - 6):j + 1]))
def scan(s, k, amb):
    n, depth = len(s), 1
    while k < n and depth:
        c = s[k]
        if c in "\x27\"`":
            e = skip_string(s, k)
            amb = amb or (c != "`" and "\n" in s[k:e])
            k = e
            continue
        if s.startswith("//", k):
            e = s.find("\n", k)
            k = n if e < 0 else e
            continue
        if s.startswith("/*", k):
            e = s.find("*/", k + 2)
            k = n if e < 0 else e + 2
            continue
        amb = amb or (c == "/" and opens_regex(s, k))
        depth += c == "("
        depth -= c == ")"
        k += 1
    return k, depth, amb
def indent_end(s, i, tp):
    base = len(re.match(r"[ \t]*", s[s.rfind("\n", 0, i) + 1:]).group())
    n, nl = len(s), s.find("\n", tp)
    while 0 <= nl < n:
        p = nl + 1
        nl = s.find("\n", p)
        e = n if nl < 0 else nl
        line = s[p:e]
        if line.strip():
            ind = len(re.match(r"[ \t]*", line).group())
            if ind <= base:
                return e if ind == base and line.lstrip()[0] in ")}]" else p
    return n
def cases(s):
    found, i, n = [], 0, len(s)
    while i < n:
        ch = s[i]
        if s.startswith("//", i):
            j = s.find("\n", i)
            i = n if j < 0 else j
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif ch in "\x27\"`":
            i = skip_string(s, i)
        else:
            m = CALL.match(s, i)
            if not m or (i and re.match(r"[A-Za-z0-9_$.]", s[i - 1])):
                i += 1
                continue
            tp = m.end()
            if s[tp - 1] == "`":
                tp = skip_string(s, tp - 1)
                while tp < n and s[tp] in " \t\r\n":
                    tp += 1
                if tp >= n or s[tp] != "(":
                    i += 1
                    continue
                tp += 1
            k, depth, amb = scan(s, tp, False)
            if not depth and re.search(r"\.each[ \t]*\($", m.group()):
                q = k
                while q < n and s[q] in " \t\r\n":
                    q += 1
                if q < n and s[q] == "(":
                    amb = amb or bool(CALL.search(s, m.end(), q))
                    tp = q + 1
                    k, depth, amb = scan(s, tp, amb)
            j = tp
            while j < n and s[j] in " \t\r\n":
                j += 1
            raw, plain = None, False
            if j < n and s[j] in "\x27\"`":
                e = skip_string(s, j)
                raw = s[j + 1:e - 1]
                plain = s[j] != "`" and "\\" not in raw and "\x27" not in raw
            ie = indent_end(s, i, tp)
            runs = k > ie or s.count("\n", 0, max(k - 1, 0)) != s.count("\n", 0, max(len(s[:ie].rstrip(" \t\r\n")) - 1, 0))
            idm = re.match(r"([UMRB][0-9]+)(?![0-9A-Za-z])", raw or "")
            found.append({"start": i, "end": k, "id": idm.group(1) if idm else None,
                          "title": raw if plain else None, "open": bool(depth), "bad": runs, "amb": amb or runs or bool(depth)})
            i = k
    return found
def touched(found, lo, hi):
    hit = [c for c in found if c["start"] < hi and lo < c["end"]]
    for pos in range(lo, hi):
        if not any(c["start"] <= pos < c["end"] for c in hit) and not (current if found is cur else result)[pos].isspace():
            refuse("the edit changes text outside every case (offset %d); rows mode edits amended cases only" % pos)
    return hit
cur = cases(current)
res = cases(result)
before = touched(cur, start, start + len(old))
for found, edge in ((cur, start + len(old)), (res, start + len(new))):
    for case in found:
        if case["amb"] and case["start"] < edge:
            if case["open"]:
                refuse("case %s (offset %d) never closes, so its span cannot be told from the cases after it; correct it through the unfreeze queue" % (case["id"] or "<no id>", case["start"]))
            refuse("case %s (offset %d) is ambiguous: its character span and its indentation span disagree, or a regex, a quote crossing a line, a stray backtick or a second call in its table could open something its closing line does not close, so it cannot be told from the cases after it; end the rows pass with python3 .claude/hooks/loop-record.py --clear, or correct it through the unfreeze queue" % (case["id"] or "<no id>", case["start"]))
if not before:
    refuse("the edit touches no case; rows mode edits amended cases only")
ids = set()
for case in before:
    if not case["id"]:
        refuse("the edit touches a case whose title carries no case id")
    ids.add(case["id"])
for case in touched(res, start, start + len(new)):
    if case["id"] not in ids:
        refuse("the edit writes case %s, which is not among the cases it replaces" % (case["id"] or "<no id>"))
for cid in sorted(ids):
    if cid in refused:
        refuse("case %s: the arbiter answered refuse on its correction (auto mode), so it stays frozen" % cid)
    if cid in rows:
        after = [c for c in res if c["id"] == cid]
        if len(after) != 1:
            refuse("case %s is a plan-gate row and must stay exactly one case in the file" % cid)
        if after[0]["title"] is None:
            refuse("case %s: its new title is not a plain-quoted literal (no template literal, no escape, no \x27), so it cannot be checked against the plan-gate row" % cid)
        actual = hashlib.sha256(after[0]["title"].encode("utf-8")).hexdigest()
        if actual != rows[cid]:
            refuse("case %s: its new title hashes to %s, the plan-gate row holds %s" % (cid, actual, rows[cid]))
    elif cid not in listed:
        refuse("case %s is neither a plan-gate row nor listed on a .tdd-unfrozen line for this path" % cid
               if not auto else "case %s has neither a plan-gate row nor an unfreeze verdict in the loop record (auto mode: a .tdd-unfrozen line alone unfreezes nothing)" % cid)
sys.exit(0)
' "$1" "$FILE_PATH" "$ROWS_LIST" "$FREEZE_AUTO" <<<"$INPUT"
}

# Rows mode's verdict on an edit the insertion rules would deny.
rows_verdict() {
    local why
    why="$(freeze_rows check)" && notice "TDD: amended case(s) of the frozen test '$FILE_PATH' edited as recorded at the plan gate (loop record rows, .tdd-unfrozen ids). The amended cases go in the PR body (Frozen cases)."
    deny "Frozen test, rows mode: '$FILE_PATH' has amended cases recorded at the plan gate, and this edit is refused: ${why:-the rows check could not run}.\n\nEdit only the amended cases, one Edit per case, giving each the exact title the gate hashed. Any other correction is queued in docs/work/<slug>/unfreeze-queue.md (case id, old and new line, reason, hunk); the main thread stops once for the whole batch (orchestrate.md, Phase 4)."
}

# Explicitly unfrozen? The whole-file exemption reads the project dir's list only. Rows mode (entry,
# and the case ids listed) also reads the list of the edited file's own tree when that tree is the
# project dir or a `.claude/worktrees/<name>` tree of it (a worktree pass keeps its record and its
# no-ask line there); a nested repository's list unfreezes nothing.
UNFROZEN_LIST="${CLAUDE_PROJECT_DIR:-.}/.claude/.tdd-unfrozen"
ROWS_LIST="$UNFROZEN_LIST"
FILE_TREE="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)" || FILE_TREE=""
PROJECT_REAL="$(cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null && pwd -P)" || PROJECT_REAL=""
if [[ -n "$FILE_TREE" && -n "$PROJECT_REAL" && -d "$FILE_TREE/.claude" ]] \
   && [[ "$FILE_TREE" == "$PROJECT_REAL" || "$(dirname "$FILE_TREE")" == "$PROJECT_REAL/.claude/worktrees" ]]; then
    ROWS_LIST="$FILE_TREE/.claude/.tdd-unfrozen"
fi
# unfrozen_names <list>: 0 when a path line of <list> names FILE_PATH.
unfrozen_names() {
    [[ -f "$1" ]] || return 1
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"          # strip comment
        line="${line#"${line%%[![:space:]]*}"}"   # trim leading space
        line="${line%"${line##*[![:space:]]}"}"   # trim trailing space
        [[ -z "$line" ]] && continue
        # The FIRST field is the path; anything after it is the reason. Both
        # spellings are accepted because both are prescribed: this hook's own
        # deny text says "add '<path>' + a one-line reason", with no `#`, and
        # before this line that exact spelling was parsed as a path containing a
        # space and matched nothing — silently. A guardrail whose escape hatch
        # only works in a spelling it never mentions is an escape hatch nobody
        # can use.
        line="${line%%[[:space:]]*}"
        # Path match only — never a bare basename. Every feature owns a
        # `services.test.ts`; matching on the basename would unfreeze all of
        # them at once.
        if [[ "$line" == */* ]] && [[ "$FILE_PATH" == *"$line"* ]]; then
            return 0
        fi
    done < "$1"
    return 1
}
ROWS_MODE=0
# Auto mode (docs/specs/auto-mode.md, step 4): no whole-file exemption; a listed file is always in rows
# mode, whose rows add the arbiter's `unfreeze` verdicts and whose listed-id fallback is off.
FREEZE_AUTO=0
[[ -n "$FILE_TREE" ]] && cwk_auto_mode "$FILE_TREE" && FREEZE_AUTO=1
if [[ "$FREEZE_AUTO" == 1 ]]; then
    if unfrozen_names "$UNFROZEN_LIST" || unfrozen_names "$ROWS_LIST"; then
        ROWS_MODE=1
    fi
elif unfrozen_names "$UNFROZEN_LIST"; then
    freeze_rows has </dev/null || exit 0
    ROWS_MODE=1
elif [[ "$ROWS_LIST" != "$UNFROZEN_LIST" ]] && unfrozen_names "$ROWS_LIST"; then
    ! freeze_rows has </dev/null || ROWS_MODE=1
fi

# An identical re-save changes nothing and is the only way to ask tdd-prove-red
# for a fresh verdict — needed when the RED was observed in a subagent whose
# context the hook did not run in. Refusing it would deadlock the cycle on a
# no-op.
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
if [[ -n "$CONTENT" && "$CONTENT" == "$(cat "$FILE_PATH")" ]]; then
    notice "TDD: identical re-save of the frozen test '$FILE_PATH' — allowed, nothing changed. tdd-prove-red is re-running it; read its verdict before writing any implementation."
fi
[[ "$ROWS_MODE" == 0 || "$(echo "$INPUT" | jq -r '.tool_name // empty')" != Write ]] || rows_verdict

# The module under test, needed by three of the conditions below.
MODULE_BASE="${FILE_PATH%.test.ts}"
[[ "$MODULE_BASE" == "$FILE_PATH" ]] && MODULE_BASE="${FILE_PATH%.test.tsx}"
MODULE_BASE=$(basename "$MODULE_BASE")
MODULE_RE=$(printf '%s' "$MODULE_BASE" | sed 's/\./\\./g')

# Where does the anchor SIT? Conditions 1 and 3 below read the anchor and the
# added text as strings, and that is not enough: anchoring on the second line of
# a case body passes both ("the anchor is not an `it(` line", "the added block
# does not OPEN with return") while `if (1) return;` lands inside a case that
# already runs and kills every assertion under it. The lint cannot see it either
# — `expect-expect` is lexical and the now-unreachable `expect()` is still there.
#
# So the position is computed, not inferred: everything before the anchor is
# walked, tracking brace depth from the most recent `it(`/`test(`. Depth still
# open at the anchor = the insertion point is inside a case body.
anchor_scope() {
    printf '%s' "$1" | awk '
    function scan(s,   i, n, ch) {
        n = length(s)
        for (i = 1; i <= n; i++) {
            ch = substr(s, i, 1)
            if (ch == "{") { if (pending >= 0) pending++ }
            else if (ch == "}") { if (pending > 0) { pending--; if (pending == 0) pending = -1 } }
        }
    }
    BEGIN { pending = -1 }
    {
        line = $0; pos = 0; off = 0; s = line
        while (match(s, /(^|[^A-Za-z0-9_$])(it|test)[ \t]*(\.[A-Za-z]+)?[ \t]*\(/)) {
            off += RSTART + RLENGTH - 1
            s = substr(s, RSTART + RLENGTH)
            pos = off
        }
        if (pos > 0) { scan(substr(line, 1, pos)); pending = 0; scan(substr(line, pos + 1)) }
        else { scan(line) }
    }
    END { print (pending > 0) ? "inside" : "outside" }
    '
}

# What the added block does AT ITS OWN TOP LEVEL — i.e. in the `describe` scope,
# outside any function it introduces. Two things are reported:
#
#   CTRL        a `return`/`throw` at depth 0. Inside the new case body it is
#               ordinary code and depth is >= 1, so it is not reported; at
#               describe scope it returns from the describe callback and every
#               case below it is never registered. That is the same defect as an
#               inserted `return;`, and the old line-start-only regex missed
#               `if (1) return;` completely.
#   DECL <name> a top-level const/let/var/function/class binding. Compared
#               against what this file imports from the module under test: a
#               `const total = () => 5` in the describe scope shadows the import
#               for every case in the block — a pure insertion, anchored outside
#               every case, carrying its own expect(), that makes the whole
#               frozen file run against a stub. Condition 4 never saw it: there
#               is no `vi.mock` anywhere in it.
added_shape() {
    printf '%s' "$1" | awk '
    BEGIN { depth = 0; ctrl = 0 }
    {
        line = $0
        sub(/\/\/.*$/, "", line)
        n = length(line)
        for (i = 1; i <= n; i++) {
            ch = substr(line, i, 1)
            if (ch == "{" || ch == "(" || ch == "[") { depth++; continue }
            if (ch == "}" || ch == ")" || ch == "]") { depth--; continue }
            if (depth > 0) continue
            prev = (i > 1) ? substr(line, i - 1, 1) : " "
            if (prev ~ /[A-Za-z0-9_$.]/) continue
            rest = substr(line, i)
            if (match(rest, /^(return|throw)([^A-Za-z0-9_$]|$)/)) { ctrl = 1; continue }
            if (match(rest, /^(const|let|var|function|class)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
                d = substr(rest, RSTART, RLENGTH)
                sub(/^(const|let|var|function|class)[ \t]+/, "", d)
                print "DECL " d
            }
        }
    }
    END { if (ctrl) print "CTRL" }
    '
}

# The conditions of an insertion. The first three say nothing existing was
# rewritten or made unreachable; the last three say what is added is a real case
# rather than a way in.
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')

# WHERE the addition lands inside the anchor, and what exactly it is.
#
# `${NEW_STRING/"$OLD_STRING"/}` looks like the answer and is not: it removes the
# FIRST occurrence, and on the one anchor the deny text prescribes — the previous
# case's closing `});` — that occurrence is at the END of new_string, so the
# addition came back with the anchor's own closing brace glued in front of it and
# the insertion point read as "inside the case that just closed". The append the
# hook documents was denied.
#
# What is actually added is what sits between the longest common prefix and the
# longest common suffix of old_string and new_string. The prefix length is also
# the offset, inside the anchor, where the addition lands.
common_affix_len() {   # $1 a, $2 b, $3 = "prefix" | "suffix"
    local a="$1" b="$2" hi=${#1} i=0
    (( ${#b} < hi )) && hi=${#b}
    if [[ "$3" == "prefix" ]]; then
        while (( i < hi )) && [[ "${a:i:1}" == "${b:i:1}" ]]; do ((i++)); done
    else
        while (( i < hi )) && [[ "${a: -i-1:1}" == "${b: -i-1:1}" ]]; do ((i++)); done
    fi
    printf '%s' "$i"
}

if [[ -n "$OLD_STRING" && "$OLD_STRING" != *"expect("* && "$NEW_STRING" == *"$OLD_STRING"* ]]; then
    AFFIX_P=$(common_affix_len "$OLD_STRING" "$NEW_STRING" prefix)
    AFFIX_S=$(common_affix_len "$OLD_STRING" "$NEW_STRING" suffix)
    (( AFFIX_P + AFFIX_S > ${#OLD_STRING} )) && AFFIX_S=$(( ${#OLD_STRING} - AFFIX_P ))
    ADDED="${NEW_STRING:AFFIX_P:${#NEW_STRING} - AFFIX_S - AFFIX_P}"

    REFUSED=""

    # 1. The anchor must not open an existing case. Anchoring on `it(... => {`
    #    keeps every assertion intact and still lets a statement slip in at the
    #    top of the body. Appending a case never needs that anchor: a new case
    #    goes after the closing `});` of the previous one.
    if [[ "$OLD_STRING" =~ (^|[^A-Za-z0-9_])(it|test)[[:space:]]*(\.[A-Za-z]+)?[[:space:]]*\( ]]; then
        REFUSED="the anchor opens an existing it()/test() block, so the insertion lands INSIDE a case that already runs"
    fi

    # 1bis. The INSERTION POINT must not sit inside a case body, not merely the
    #    anchor's first line. Condition 1 reads the anchor as a string and passes
    #    on the second body line of the same case.
    #
    #    The point is computed from the resulting file, never from the anchor
    #    alone: what lands where is `<file up to the anchor> + <the part of
    #    new_string that precedes the addition>`. That is what makes the
    #    documented append work — anchoring on the previous case's closing `});`
    #    puts the addition AFTER it, i.e. outside — while `if (1) return;` glued
    #    under the second line of a body is refused.
    if [[ -z "$REFUSED" && -n "$ADDED" ]]; then
        CURRENT_CONTENT=$(cat "$FILE_PATH")
        if [[ "$CURRENT_CONTENT" == *"$OLD_STRING"* ]]; then
            INSERT_PREFIX="${CURRENT_CONTENT%%"$OLD_STRING"*}${NEW_STRING:0:AFFIX_P}"
            if [[ "$(anchor_scope "$INSERT_PREFIX")" == "inside" ]]; then
                REFUSED="the insertion point sits INSIDE the body of an existing it()/test() block, so what is added lands in a case that already runs"
            fi
        fi
    fi

    # 2. What is added must assert something. A case that asserts nothing is not
    #    a case — and it is what `expect-expect` would only report at /ship.
    if [[ -z "$REFUSED" && "$ADDED" != *"expect("* && "$ADDED" != *"expectTypeOf("* ]]; then
        REFUSED="the inserted block carries no expect() of its own"
    fi

    # 3 + 5. What the added block does at describe scope: control flow that skips
    #    the cases below it, and a binding that shadows the module under test.
    #    Both are read from the walked shape, never from a line-start regex —
    #    `if (1) return;` opens no line with `return`.
    ADDED_SHAPE=""
    if [[ -z "$REFUSED" ]]; then
        ADDED_SHAPE=$(added_shape "$ADDED")
    fi

    if [[ -z "$REFUSED" ]] && printf '%s\n' "$ADDED_SHAPE" | grep -qx 'CTRL'; then
        REFUSED="the inserted block carries a return/throw at describe scope, which skips every case declared below it"
    fi

    # 4. No mocking the module under test. This is the hole conditions 1-3 left
    #    wide open: `vi.mock('./x.utils', () => ({ a: () => 1 }))` is a pure
    #    insertion, anchors outside every case, carries its own expect() — and
    #    every assertion in the frozen file now runs against the mock instead of
    #    the implementation. The file passes whatever the code does, which is
    #    exactly the "adjust the test until it agrees" the freeze exists to stop,
    #    achieved without editing a single existing assertion.
    #
    #    BOTH call forms are matched. `vi.mock(import('./x.repository'))` is the
    #    type-safe spelling Vitest documents since 2.1, so it is what an agent
    #    reading current docs writes — and anchoring the specifier on a quote
    #    immediately after the `(` let it through while the string form was
    #    denied. A guardrail that only stops the older spelling is a guardrail
    #    that stops nobody.
    #
    #    Limit, stated rather than hidden: this catches the vi/jest mock calls.
    #    A `vi.spyOn` on a namespace import of the module under test is not
    #    matched, and neither is a specifier behind a variable — /loop:review's
    #    `tests` dimension owns those.
    #
    #    utils/mapper are pure, so 05-testing.md forbids mocking them at all —
    #    any mock added there is refused. A repository/services test legitimately
    #    mocks the gateway below it, so only a mock naming the module under test
    #    is refused.
    if [[ -z "$REFUSED" ]] && printf '%s' "$ADDED" | grep -qE '\b(vi|jest)\.(do)?[Mm]ock[[:space:]]*\('; then
        if [[ "$FILE_PATH" =~ (utils|mapper)\.test\.tsx?$ ]]; then
            REFUSED="the inserted block mocks a module, and this is a pure layer (utils/mapper) where 05-testing.md forbids mocking outright — a mocked pure function tests the mock"
        elif printf '%s' "$ADDED" | grep -qE "\b(vi|jest)\.(do)?[Mm]ock[[:space:]]*\([[:space:]]*(import[[:space:]]*\([[:space:]]*)?['\"][^'\"]*${MODULE_RE}['\"]"; then
            REFUSED="the inserted block mocks '$MODULE_BASE', the module under test — every assertion in this frozen file would then run against the mock and pass whatever the implementation does"
        fi
    fi

    # 5. No SHADOWING the module under test. Condition 4 matches the vi/jest mock
    #    calls, and that is the hole it leaves: a plain
    #    `const total = () => 5` at describe scope shadows the import for every
    #    case in the block. No mock, no rewritten assertion, a pure insertion
    #    carrying its own expect() — and the whole frozen file now runs against
    #    the stub. Same outcome as condition 4, reached with ordinary JavaScript.
    #
    #    Only names this file actually imports FROM THE MODULE UNDER TEST are
    #    refused. A helper, a fixture or a local builder introduced by the new
    #    case shares none of them and goes through untouched.
    if [[ -z "$REFUSED" ]]; then
        IMPORTED_SYMS=$(tr '\n' ' ' < "$FILE_PATH" \
            | grep -oE "import[[:space:]]+[^;]*from[[:space:]]*['\"][^'\"]*${MODULE_RE}['\"]" \
            | sed -E "s/^import[[:space:]]+//; s/[[:space:]]+from[[:space:]]*['\"].*//" \
            | tr -d '{}' | tr ',' '\n' \
            | sed -E 's/^[[:space:]]*type[[:space:]]+//; s/.*[[:space:]]as[[:space:]]+//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
            | grep -E '^[A-Za-z_$][A-Za-z0-9_$]*$' | sort -u || true)

        if [[ -n "$IMPORTED_SYMS" ]]; then
            while IFS= read -r decl; do
                [[ "$decl" == DECL\ * ]] || continue
                name="${decl#DECL }"
                if printf '%s\n' "$IMPORTED_SYMS" | grep -qx -- "$name"; then
                    REFUSED="the inserted block declares '$name' at describe scope, and this file imports '$name' from '$MODULE_BASE' — the declaration shadows the module under test for every case in the block, so they would all run against the stub"
                    break
                fi
            done <<< "$ADDED_SHAPE"
        fi
    fi

    if [[ -z "$REFUSED" ]]; then
        notice "TDD: new case appended to the frozen test '$FILE_PATH' — allowed (the test list grows as you learn), nothing existing was touched. Say in your next message which behaviour it covers and why the /loop:plan test plan missed it; /loop:review compares this file against that plan."
    fi

    [[ "$ROWS_MODE" == 0 ]] || rows_verdict
    deny "Frozen test: this edit to '$FILE_PATH' looks like an insertion, but $REFUSED (.claude/rules/05-testing.md).\n\nAdding a case is allowed; opening a way into a case that already runs is not — an inserted 'return;' leaves every assertion intact and kills the case anyway, and the lint cannot see it.\n\nA real append: anchor on a line outside any case body (the closing '});' of the previous one), keep that anchor verbatim, and let the added block carry its own 'expect('. Add its fixtures in the same edit.\n\nIf you genuinely need to change what an existing case asserts, that is a plan-level correction. A subagent stops and reports the case id and why. The main thread records it: it queues it in docs/work/<slug>/unfreeze-queue.md (case id, old and new line, reason, hunk), keeps working on what does not depend on it, then stops once for the whole batch: one .tdd-unfrozen write (this write will ask the user), a line per path in this shape:\n\n    $FILE_PATH  # <case id>: <one-line reason>\n\neach plan line rewritten with the same id, an 'amended' line in plan.md's ## Gate; the amended cases are listed in the PR body (Frozen cases) (orchestrate.md, Phase 4). Then edit."
fi

[[ "$ROWS_MODE" == 0 ]] || rows_verdict
deny "Frozen test: '$FILE_PATH' is a test-first file (.claude/rules/05-testing.md).\n\nIt was validated at the /loop:plan gate and the implementation is written against it. Adjusting a test so it agrees with the code is exactly what the freeze prevents. The fix is almost always in the implementation, not here.\n\nTwo different situations, and this edit is neither:\n\n  ADDING a case — allowed without any ceremony, but only as a pure insertion: anchor the edit on a line outside any case body and carrying no 'expect(', keep that anchor verbatim, and let the added block carry its own 'expect('. Rewriting an 'it()' title is not an insertion.\n\n  CORRECTING an assertion — a plan-level correction, so:\n    1. a subagent stops and reports the case id and why; the main thread goes on\n    2. the main thread queues it in docs/work/<slug>/unfreeze-queue.md (case id, old and new line, reason, hunk) and stops once for the whole batch\n    3. one .tdd-unfrozen write for the batch (this write will ask the user), a line per path in this shape:\n         $FILE_PATH  # <case id>: <one-line reason>\n    4. for each case, rewrite the plan line (same id), append 'amended' to plan.md's ## Gate; the amended cases are listed in the PR body (Frozen cases) (orchestrate.md, Phase 4)\n    5. then edit"
