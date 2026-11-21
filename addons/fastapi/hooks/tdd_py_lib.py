#!/usr/bin/env python3
# cwk-guard-api: 1
#
# Shared library for the three Python TDD hooks:
#   tdd-require-red-py.py  (Pre)   — the implementation cannot be created first
#   tdd-prove-red-py.py    (Post)  — the RED is proved, not declared
#   tdd-freeze-tests-py.py (Pre)   — the proved test file stops moving
#
# It is the Python twin of `.claude/hooks/hook-lib.sh`, and it exists for the
# same reason: three hooks that each retype the layer list, the marker naming
# and the runner resolution are three hooks that drift apart in silence.

import atexit
import hashlib
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import time


def _crash_envelope(kind, value, trace) -> None:
    """An uncaught error in a hook that imports this library (an older hook beside this
    version raising a KeyError, say) must not end as a bare exit 1, which lets the write
    through: a PreToolUse hook asks, the PostToolUse prover reports. Exits 0 so the harness
    reads the JSON."""
    name = os.path.basename(sys.argv[0]) if sys.argv and sys.argv[0] else "hook"
    note = (f"{name} failed ({kind.__name__}: {value}); the hooks in .claude/hooks come from two kit "
            "versions. Restore them: rerun install.sh on this project, or /kit:init.")
    if "prove-red" in name:
        envelope = {"systemMessage": note}
    else:
        envelope = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
                                           "permissionDecisionReason": note}}
    sys.stdout.write(json.dumps(envelope))
    sys.stdout.flush()
    os._exit(0)


if sys.excepthook is sys.__excepthook__:
    sys.excepthook = _crash_envelope

# --- configuration -----------------------------------------------------------
# The Python package root, relative to the project. Same value as
# enforce-backend-layers.py's MODULE_ROOT.
VALUES = {}
# Where the tests live. `tests/` MIRRORS the module root — that is the addon's
# own convention (`patterns/pytest-backend.md`, "Mirroring"), and it is what
# makes the test <-> module mapping derivable instead of guessed.
# The layers written TEST-FIRST and then frozen, as path prefixes under
# MODULE_ROOT. `services/` is the backend's twin of the front end's
# repository/services: the layer where "correct" is decided.
#
# Deliberately NOT here, and each for a reason the front end already settled:
#   api/     — HTTP wiring. The gateway's twin: test-after (`07-backend.md`).
#   models/  — SQLAlchemy declarations, no branch to walk.
#   schemas/ — Pydantic declarations.
#   core/    — majority wiring (config, database, middleware). The two modules
#              that do carry logic (auth, security) would have to be listed file
#              by file, and a list of files rots faster than a list of layers.
#              They stay mandatory-to-test, test-after.
# -----------------------------------------------------------------------------
CONFIG_STATE = []
DECIDED = []
CONFIG_REASONS = {
    3: ".claude/project.json is invalid or could not be read",
    4: ".claude/project.json is missing",
    5: ".claude/project.json cannot be found: CLAUDE_PROJECT_DIR is not an absolute path",
    6: ".claude/project.json cannot be read: .claude/hooks/project_config.py is missing",
}
CONFIG_TAIL = (", so the hooks run on the kit defaults and ask instead of passing. Restore it: "
               "rerun install.sh on this project, or /kit:init.")


def _reader():
    """The kit's one reader module: beside this file in an installed project, else under
    `$CLAUDE_PROJECT_DIR/.claude/hooks`; None when neither holds one."""
    places = [os.path.dirname(os.path.abspath(__file__))]
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if project and os.path.isabs(project):
        places.append(os.path.join(project, ".claude", "hooks"))
    for place in places:
        if os.path.isfile(os.path.join(place, "project_config.py")):
            if place not in sys.path:
                sys.path.insert(0, place)
            import project_config
            return project_config
    return None


def configure(ask_on_pass: bool = False) -> str:
    """Fill VALUES (`module_root`, `tests_root`, `test_first_dirs`, `session_names`,
    `external_clients`) from `.claude/project.json`, once; from the reader's kit defaults
    when the file cannot be read. Returns that config reason, else "". With no reader at
    all VALUES stays empty and the caller decides nothing. With `ask_on_pass`, a PreToolUse
    hook that then exits without a decision asks instead of passing."""
    if CONFIG_STATE:
        return CONFIG_STATE[0]
    reason = ""
    try:
        reader = _reader()
        if reader is None:
            reason = CONFIG_REASONS[6]
        else:
            try:
                block = reader.load_strict(os.environ.get("CLAUDE_PROJECT_DIR", "")).fastapi
            except reader.ConfigError as error:
                reason = CONFIG_REASONS.get(error.status, CONFIG_REASONS[3])
                block = reader.DEFAULTS["fastapi"]
            VALUES.update(
                module_root=block["module_root"],
                tests_root=block["tests_root"],
                test_first_dirs=tuple(d.rstrip("/") + "/" for d in block["test_first_dirs"]),
                session_names=tuple(block["session_names"]),
                external_clients={k: list(v) for k, v in block["external_clients"].items()},
            )
    except Exception:
        VALUES.clear()
        reason = CONFIG_REASONS[3]
    if reason:
        reason += CONFIG_TAIL
    CONFIG_STATE.append(reason)
    if reason and ask_on_pass:
        atexit.register(_ask_if_undecided)
    return reason


def _ask_if_undecided() -> None:
    if not DECIDED:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": CONFIG_STATE[0],
        }}))
        sys.stdout.flush()

_T0 = time.time()


def _record_timing(name: str) -> None:
    """Append this hook's cost to the shared TSV log.

    Same file and same columns as hook-lib.sh and english-comments.py, so
    hook-timings-report.sh reads them without knowing which language wrote the
    line. A hook that is never measured looks free.
    """
    if os.environ.get("CWK_HOOK_TIMING", "1") != "1":
        return
    log = os.path.join(project_dir(), ".claude", ".hook-timings.log")
    try:
        with open(log, "a") as fh:
            fh.write(
                "%d\t%s\t%d\t%s\t%s\n"
                % (_T0 * 1000, name, (time.time() - _T0) * 1000, "-", "-")
            )
    except OSError:
        pass


def register_timing(name: str) -> None:
    import atexit

    atexit.register(_record_timing, name)


def project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def read_payload() -> dict:
    try:
        return json.loads(sys.stdin.read()) or {}
    except Exception:
        return {}


def abs_path(path: str) -> str:
    """Absolute form, matching cwk_abs_path in hook-lib.sh.

    The two must agree: both hooks derive a marker name from this, and they do
    not always receive the same spelling of the same file.
    """
    p = path.replace("\\", "/")
    if p.startswith("/"):
        return p
    return posixpath.join(project_dir().replace("\\", "/"), p)


def rel_path(path: str) -> str:
    """Project-relative form, or the path itself when it lies outside."""
    root = project_dir().replace("\\", "/").rstrip("/")
    p = abs_path(path)
    if p.startswith(root + "/"):
        return p[len(root) + 1 :]
    return p.lstrip("/")


# ------------------------------------------------------------------ the layers


def _split_root(rel: str, root: str):
    """Locate `root` (e.g. "app") as a path SEGMENT — anchored at the start of
    `rel` or right after a "/" — taking the LAST such occurrence, exactly like
    `enforce-backend-layers.py`'s `MODULE_ROOT` match (`(?:^|/)app/`, last
    match, `.claude/hooks/enforce-backend-layers.py:137-141`). On a monorepo
    every path this library sees is prefixed by the module subdirectory (e.g.
    `backend/`), and the two applicators diverged because this one tested
    `rel.startswith("app/")` on a project-relative path, which is never true
    for `backend/app/services/x.py`.

    Returns (prefix, inner): `prefix` is what comes BEFORE the root segment,
    without a trailing slash ("" when `root` sits at the project's own root —
    a repo with no monorepo subdirectory), and `inner` is everything AFTER it.
    (None, None) when `root` never occurs as a "/"-bounded segment.
    """
    match = None
    for m in re.finditer(r"(?:^|/)%s/" % re.escape(root), rel):
        match = m
    if match is None:
        return None, None
    return rel[: match.start()].lstrip("/"), rel[match.end() :]


def _join_root(prefix: str, root: str, inner: str) -> str:
    """The inverse of `_split_root`: prefix + root + inner, monorepo-safe."""
    head = (prefix + "/") if prefix else ""
    return head + root + "/" + inner


def is_test_first_impl(path: str) -> bool:
    """True for an implementation module the cycle applies to."""
    rel = rel_path(path)
    if not rel.endswith(".py"):
        return False
    if posixpath.basename(rel) == "__init__.py":
        return False
    _, inner = _split_root(rel, VALUES["module_root"])
    if inner is None:
        return False
    if inner.startswith(VALUES["test_first_dirs"]):
        return True
    # A FLAT module spelled like the layer — `app/services.py` rather than the
    # `app/services/` package `07-backend.md` prescribes. It happens on a small
    # service, and keying on the directory alone left it silently outside the
    # cycle, which is the worst of the two answers: the layout is wrong AND
    # nothing says so. The TypeScript side keys on the filename and covers its
    # own flat spelling (`services.ts`) for exactly this reason.
    return inner in tuple(d.rstrip("/") + ".py" for d in VALUES["test_first_dirs"])


def is_frozen_test(path: str) -> bool:
    """True for a test file that covers a test-first module.

    Keyed on the mirrored path, never on the basename alone: every domain owns a
    `test_project.py`-shaped name somewhere, and `tests/api/test_project.py` is
    test-after while `tests/services/test_project.py` is frozen.
    """
    rel = rel_path(path)
    base = posixpath.basename(rel)
    if not (base.startswith("test_") and rel.endswith(".py")):
        return False
    return is_test_first_impl(impl_for_test(rel))


def impl_for_test(path: str) -> str:
    """tests/services/test_project.py -> app/services/project.py
    backend/tests/services/test_project.py -> backend/app/services/project.py
    """
    rel = rel_path(path)
    prefix, inner = _split_root(rel, VALUES["tests_root"])
    if inner is None:
        return ""
    parts = inner.split("/")
    if not parts or not parts[-1].startswith("test_"):
        return ""
    parts[-1] = parts[-1][len("test_") :]
    return _join_root(prefix, VALUES["module_root"], "/".join(parts))


def test_for_impl(path: str) -> str:
    """app/services/project.py -> tests/services/test_project.py
    backend/app/services/project.py -> backend/tests/services/test_project.py
    """
    rel = rel_path(path)
    prefix, inner = _split_root(rel, VALUES["module_root"])
    if inner is None:
        return ""
    parts = inner.split("/")
    parts[-1] = "test_" + parts[-1]
    return _join_root(prefix, VALUES["tests_root"], "/".join(parts))


def dotted_module(rel_impl: str) -> str:
    """app/services/project.py -> app.services.project
    backend/app/services/project.py -> app.services.project — the monorepo
    prefix is stripped, because that is the name the test file actually
    imports (`from app.services.project import …`), never `backend.…`.
    """
    if not rel_impl.endswith(".py"):
        return ""
    _, inner = _split_root(rel_impl, VALUES["module_root"])
    if inner is None:
        return ""
    return (VALUES["module_root"] + "/" + inner)[: -len(".py")].replace("/", ".")


# ----------------------------------------------------------------- the markers


def defined_names(path: str) -> set:
    """The names a module DEFINES, as opposed to the ones it imports.

    The distinction is what separates two patches that look identical:

        patch("app.services.project.slugify")     # the code under test  -> refuse
        patch("app.services.project.send_email")  # a dependency it imported -> allow

    and `patterns/pytest-backend.md` requires the second form in as many words
    ("patch where the name is looked up, not where it is defined"). A substring
    check cannot tell them apart, and got it exactly backwards: it denied the
    documented form and allowed patching at the origin, which is the one the
    same file calls a bug — the service keeps the real client and the test
    passes while the network call happens.

    Known over-detection, and it is the harmless direction: a nested function or
    a method body is matched too, so `app.services.x.render` reads as defined
    even when `render` only exists inside a class. Patching that path does not
    work at runtime either, so the extra refusal costs nothing — whereas the
    opposite bias would silently allow neutralising the code under test.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            source = fh.read()
    except OSError:
        return set()
    found = set()
    for pattern in (
        r"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)",
        r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)",
        r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=\n]+)?=",
    ):
        found.update(re.findall(pattern, source, re.M))
    return found


def red_dir() -> str:
    return os.path.join(project_dir(), ".claude", ".tdd-red")


def marker_path(path: str) -> str:
    """Same derivation as marker_path() in the two bash TDD hooks.

    `tr -c 'A-Za-z0-9._-' '_'` over the absolute path. The marker directory is
    shared with the TypeScript cycle on purpose: `/loop:review`'s `tests` dimension
    checks "a marker exists for each test-first file in the diff" without
    caring which language produced it.
    """
    return os.path.join(red_dir(), re.sub(r"[^A-Za-z0-9._-]", "_", abs_path(path)))


def file_digest(path: str) -> str:
    """Which test file was seen failing, not merely that one was.

    Without it a marker outlives the test that earned it: delete the test, write
    a different one at the same path, and the module could be created on a red
    nobody observed.
    """
    import hashlib

    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return "unavailable"


def write_marker(test_path: str) -> None:
    os.makedirs(red_dir(), exist_ok=True)
    gi = os.path.join(red_dir(), ".gitignore")
    if not os.path.exists(gi):
        try:
            with open(gi, "w") as fh:
                fh.write("*\n")
        except OSError:
            pass
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(marker_path(test_path), "w") as fh:
        fh.write("%s\nsha256:%s\n" % (stamp, file_digest(test_path)))


def marker_is_fresh(test_path: str) -> bool:
    """A marker counts only if it names the test file as it stands now."""
    mp = marker_path(test_path)
    if not os.path.isfile(mp) or not os.path.isfile(test_path):
        return False
    try:
        with open(mp) as fh:
            recorded = fh.read()
    except OSError:
        return False
    return ("sha256:" + file_digest(test_path)) in recorded


# --------------------------------------------------------------- the exception


def _project_listing() -> str:
    return os.path.join(project_dir(), ".claude", ".tdd-unfrozen")


def _rows_listing(path: str) -> str:
    """`.tdd-unfrozen` read by rows mode (entry and listed ids): the list of the tree holding the file
    when that tree is the project dir or a `.claude/worktrees/<name>` tree of it (a worktree pass keeps
    its record and its no-ask line there); the project dir's otherwise, so a nested repository's list
    unfreezes nothing."""
    tree = _git(os.path.dirname(abs_path(path)), "rev-parse", "--show-toplevel")
    project = os.path.realpath(project_dir())
    if tree and os.path.isdir(os.path.join(tree, ".claude")) and (
        tree == project or os.path.dirname(tree) == os.path.join(project, ".claude", "worktrees")
    ):
        return os.path.join(tree, ".claude", ".tdd-unfrozen")
    return _project_listing()


def _names_path(listing: str, path: str) -> bool:
    """True when a path line of `listing` names `path`: one field with a `/`, a fragment of the path."""
    target = abs_path(path)
    try:
        with open(listing) as fh:
            lines = fh.readlines()
    except OSError:
        return False
    for line in lines:
        entry = line.split("#", 1)[0].strip().split()
        if entry and "/" in entry[0] and entry[0] in target:
            return True
    return False


def rows_entry(path: str) -> bool:
    """True when the list of the file's own worktree tree, not the project dir's, names the file: the
    way into rows mode of a worktree pass, which never exempts the file whole."""
    listing = _rows_listing(path)
    return listing != _project_listing() and _names_path(listing, path)


def is_unfrozen(path: str) -> bool:
    """`.claude/.tdd-unfrozen`, shared with the TypeScript cycle.

    An entry must contain a `/` and is matched as a path fragment. A bare
    basename is skipped: every domain owns a `test_project.py`, and one basename
    would unfreeze all of them at once (`.claude/rules/05-testing.md`).

    The FIRST field is the path; anything after it is the reason, with or
    without a `#`. Both spellings are accepted because both are prescribed —
    several deny texts say "add '<path>' + a one-line reason" with no `#`, and
    that spelling used to parse as a path containing a space and match nothing,
    silently. Semantically identical to the bash parser in
    `.claude/hooks/tdd-freeze-tests.sh` — change the three together.
    """
    return _names_path(_project_listing(), path)


# ------------------------------------------------------------------ the runner


def _git(tree: str, *args: str):
    """Stripped stdout of `git -C <tree> <args>`, or None when it fails."""
    try:
        done = subprocess.run(["git", "-C", tree, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def _loop_record(path: str):
    """(record, path relative to its tree) of the tree's valid loop record for this test, or None.

    The tree is the git toplevel of the directory holding the file; the record is valid when
    HEAD is its branch, or HEAD is its base and holds its base commit. Same rule as
    `tdd-freeze-tests.sh` and `protect-files.sh` (docs/specs/loop-to-pr.md, step 5).
    """
    target = abs_path(path)
    tree = _git(os.path.dirname(target), "rev-parse", "--show-toplevel")
    if not tree:
        return None
    record = os.path.join(tree, ".claude", ".loop-record.json")
    try:
        if os.path.islink(record):
            return None
        with open(record, encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(rec, dict) or rec.get("version") != 1 or not isinstance(rec.get("rows"), list):
        return None
    head = _git(tree, "symbolic-ref", "-q", "--short", "HEAD")
    if not head:
        return None
    if head != rec.get("branch"):
        sha = rec.get("base_sha")
        if head != rec.get("base") or not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
            return None
        if _git(tree, "merge-base", "--is-ancestor", sha, "HEAD") is None:
            return None
    return rec, os.path.relpath(os.path.realpath(target), os.path.realpath(tree))


def loop_rows(path: str) -> dict:
    """{case id: sha256} rows of the tree's valid loop record for this test, {} when none."""
    found = _loop_record(path)
    if not found:
        return {}
    rec, rel = found
    return {r.get("id"): r.get("sha256") for r in rec["rows"] if isinstance(r, dict) and r.get("path") == rel}


def loop_auto(path: str):
    """(auto, granted, refused) for this test (docs/specs/auto-mode.md, step 4): whether the tree's valid
    record is in auto mode (`mode: auto` and a contract go), the {case id: sha256} of its `unfreeze`
    verdicts and the case ids of its `refuse` verdicts. Same rule as `tdd-freeze-tests.sh`."""
    found = _loop_record(path)
    if not found:
        return False, {}, set()
    rec, rel = found
    if rec.get("mode") != "auto" or not isinstance(rec.get("contract_go"), dict):
        return False, {}, set()
    if _git(os.path.dirname(abs_path(path)), "symbolic-ref", "-q", "--short", "HEAD") != rec.get("branch"):
        return False, {}, set()
    granted, refused = {}, set()
    for v in rec.get("verdicts") or []:
        if isinstance(v, dict) and v.get("kind") == "frozen-case" and v.get("path") == rel:
            if v.get("verdict") == "unfreeze":
                granted.setdefault(v.get("id"), v.get("sha256"))
            elif v.get("verdict") == "refuse":
                refused.add(v.get("id"))
    return True, granted, refused


def unfrozen_ids(path: str) -> set:
    """Case ids listed on `.claude/.tdd-unfrozen` lines (`<path>  # <ids>: <reason>`) for this test."""
    listing = _rows_listing(path)
    target = abs_path(path)
    ids = set()
    try:
        with open(listing, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return ids
    for line in lines:
        match = re.fullmatch(r"(\S+)[ \t]+#[ \t]*([UMRB][0-9]+!?(?:[ \t]*,[ \t]*[UMRB][0-9]+!?)*)[ \t]*:.*", line.strip())
        if match and "/" in match.group(1) and match.group(1) in target:
            ids.update(tok.rstrip("!") for tok in re.split(r"[ \t]*,[ \t]*", match.group(2)))
    return ids


def _py_cases(text: str) -> list:
    """Each `def test_…` as {start, end, id, title}: the def line to the first non-blank line at or
    below its column. The id is `test_<letter><digits>_…` upper-cased, the title the def name."""
    found, pos, open_case = [], 0, None
    for line in text.split("\n"):
        if line.strip():
            indent = len(line) - len(line.lstrip())
            if open_case is not None and indent <= open_case["indent"]:
                open_case["end"] = pos
                open_case = None
            match = re.match(r"\s*(?:async\s+)?def\s+(test_[A-Za-z0-9_]*)\s*\(", line)
            if match:
                ident = re.match(r"test_([A-Za-z])([0-9]+)(?:_|$)", match.group(1))
                open_case = {"start": pos, "end": len(text), "indent": indent, "title": match.group(1),
                             "id": (ident.group(1).upper() + ident.group(2)) if ident else None}
                found.append(open_case)
        pos += len(line) + 1
    return found


def _touched(text: str, cases: list, lo: int, hi: int):
    """The cases meeting [lo, hi), or None when a non-blank character there lies outside them."""
    hit = [c for c in cases if c["start"] < hi and lo < c["end"]]
    for offset in range(lo, hi):
        if not any(c["start"] <= offset < c["end"] for c in hit) and not text[offset].isspace():
            return None
    return hit


def rows_refusal(path: str, rows: dict, current: str, tool_input: dict, tool_name: str,
                 auto: bool = False, refused: frozenset = frozenset()) -> str:
    """Why rows mode refuses this write, or "" when every case it touches is a row whose new name
    hashes to it, or an id listed for this path on `.tdd-unfrozen`."""
    if tool_name != "Edit":
        return "a Write replaces the whole frozen file; edit the amended cases one by one with Edit"
    old, new = tool_input.get("old_string"), tool_input.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str) or not old or tool_input.get("replace_all") is True:
        return "rows mode takes one Edit with a non-empty old_string, never replace_all"
    start = current.find(old)
    if start < 0:
        return "the old_string does not appear in the file as it stands"
    result = current[:start] + new + current[start + len(old):]
    before = _touched(current, _py_cases(current), start, start + len(old))
    if before is None:
        return "the edit changes text outside every case; rows mode edits amended cases only"
    if not before:
        return "the edit touches no case; rows mode edits amended cases only"
    ids = set()
    for case in before:
        if not case["id"]:
            return "the edit touches `%s`, whose name carries no case id" % case["title"]
        ids.add(case["id"])
    after_cases = _py_cases(result)
    written = _touched(result, after_cases, start, start + len(new))
    if written is None:
        return "the edit writes text outside every case; rows mode edits amended cases only"
    for case in written:
        if case["id"] not in ids:
            return "the edit writes case %s, which is not among the cases it replaces" % (case["id"] or case["title"])
    listed = set() if auto else unfrozen_ids(path)
    for cid in sorted(ids):
        if cid in refused:
            return "case %s: the arbiter answered refuse on its correction (auto mode), so it stays frozen" % cid
        if cid in rows:
            after = [c for c in after_cases if c["id"] == cid]
            if len(after) != 1:
                return "case %s is a plan-gate row and must stay exactly one case in the file" % cid
            actual = hashlib.sha256(after[0]["title"].encode("utf-8")).hexdigest()
            if actual != rows[cid]:
                return "case %s: its new name hashes to %s, the plan-gate row holds %s" % (cid, actual, rows[cid])
        elif auto:
            return ("case %s has neither a plan-gate row nor an unfreeze verdict in the loop record "
                    "(auto mode: a .tdd-unfrozen line alone unfreezes nothing)" % cid)
        elif cid not in listed:
            return "case %s is neither a plan-gate row nor listed on a .tdd-unfrozen line for this path" % cid
    return ""


def module_root_dir(path: str) -> str:
    """Absolute directory holding `MODULE_ROOT` for this file.

    `<project>/backend` when `path` is `backend/app/services/x.py` or
    `backend/tests/services/test_x.py`; `<project>` itself on a repo with no
    monorepo subdirectory. Tries `MODULE_ROOT` first (an impl path), then
    `TESTS_ROOT` (a test path) — a caller only ever has one of the two.

    THE MEASURED REASON THIS EXISTS: `pytest_cmd()` used to look for `.venv`
    and `uv.lock` at `project_dir()`, which is the monorepo root here — they
    live under `backend/`, so it always fell through to the bare `python3` of
    whatever shell launched the hook. `run_pytest` then ran with
    `cwd=project_dir()`, where `from app…` cannot resolve. Both are wrong for
    the same reason: neither followed the file to the module root it actually
    belongs to.
    """
    rel = rel_path(path)
    prefix, inner = _split_root(rel, VALUES["module_root"])
    if inner is None:
        prefix, inner = _split_root(rel, VALUES["tests_root"])
    if inner is None or not prefix:
        return project_dir()
    return os.path.join(project_dir(), prefix)


def sanitized_addopts(root: str) -> str:
    """The project's own addopts, minus every coverage flag.

    THE MEASURED REASON THIS EXISTS. The addon ships
    `addopts = "--cov=app --cov-report=term-missing --cov-fail-under=85"`.
    Run one test file with that in force and pytest prints `1 passed` and exits
    **1**, because the coverage of the whole package is below the floor. A hook
    that reads "exit != 0" as RED would then record a marker for a GREEN test —
    the apparatus looks armed and proves nothing. Measured, not assumed.

    `--no-cov` is the obvious fix and it is the wrong one: on a project without
    pytest-cov installed it is an unrecognized argument and pytest exits 4.
    Blanking the coverage flags through --override-ini works in both cases.

    Everything else in addopts is preserved, and that matters: blanking it
    wholesale would drop a `-p` plugin the suite needs, and an async test whose
    plugin never loaded is reported as skipped rather than failed — a false
    GREEN, the same bug one level down.

    All four config files pytest itself reads are searched, in its own order.
    Covering only pyproject.toml would have made the sentence above false on a
    repo configured through pytest.ini: nothing would be found, and the fallback
    blanks addopts entirely.

    `root` is `module_root_dir()`'s answer, not `project_dir()` — on a monorepo
    the project's own `pyproject.toml` (with the addopts above) lives under the
    module subdirectory, and reading the repo root found none, silently
    returning "" instead of the real config.
    """
    pyproject = os.path.join(root, "pyproject.toml")
    if os.path.isfile(pyproject):
        try:
            import tomllib

            with open(pyproject, "rb") as fh:
                data = tomllib.load(fh)
            opts = (
                data.get("tool", {})
                .get("pytest", {})
                .get("ini_options", {})
                .get("addopts")
            )
            if opts is not None:
                return _strip_cov(opts)
        except Exception:
            pass

    import configparser

    for name, section in (
        ("pytest.ini", "pytest"),
        ("tox.ini", "pytest"),
        ("setup.cfg", "tool:pytest"),
    ):
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            continue
        try:
            parser = configparser.ConfigParser()
            parser.read(path)
            if parser.has_option(section, "addopts"):
                return _strip_cov(parser.get(section, "addopts"))
        except Exception:
            continue

    return ""


def _strip_cov(opts) -> str:
    tokens = list(opts) if isinstance(opts, list) else str(opts).split()
    return " ".join(t for t in tokens if not t.startswith("--cov"))


def pytest_cmd(root: str) -> list:
    """How to run pytest here, as a command prefix.

    ALWAYS `python -m pytest`, never the bare `pytest` console script. Measured
    on a tree laid out exactly as this addon prescribes: `pytest` exits 2 with
    `No module named 'app'`, `python -m pytest` exits 0 — `-m` puts the current
    directory on `sys.path`, the console script does not.

    `root` is `module_root_dir()`'s answer. On a monorepo, searching `.venv`/
    `uv.lock` at `project_dir()` found nothing — they live under the module
    subdirectory (e.g. `backend/`) — and silently fell back to the bare
    `python3` on `PATH`, running with whatever interpreter happened to be on
    the shell instead of the project's own.
    """
    override = os.environ.get("CWK_PYTEST")
    if override:
        import shlex

        return shlex.split(override)

    for venv in (".venv", "venv"):
        candidate = os.path.join(root, venv, "bin", "python")
        if os.path.isfile(candidate):
            return [candidate, "-m", "pytest"]
    if os.path.isfile(os.path.join(root, "poetry.lock")) and shutil.which("poetry"):
        return ["poetry", "run", "python", "-m", "pytest"]
    if os.path.isfile(os.path.join(root, "uv.lock")) and shutil.which("uv"):
        return ["uv", "run", "python", "-m", "pytest"]
    return [shutil.which("python3") or sys.executable, "-m", "pytest"]


def run_pytest(test_path: str, timeout: int) -> tuple:
    """Run one test file. Returns (exit_code, combined output).

    Exit code 124 is reserved for our own timeout, mirroring `timeout(1)` in the
    bash hook so both report the same way.

    `cwd` is the module's own root (`module_root_dir()`), never
    `project_dir()`: this is a monorepo, `from app…` only resolves from
    `backend/`, and the test path handed to pytest must be relative to THAT
    cwd — passing the project-relative `backend/tests/services/test_x.py` to a
    pytest already running inside `backend/` is `file or directory not found`,
    exit 4, before a single test is collected.
    """
    root = module_root_dir(test_path)
    root_norm = root.rstrip("/")
    test_abs = abs_path(test_path)
    if test_abs.startswith(root_norm + "/"):
        test_rel_to_root = test_abs[len(root_norm) + 1 :]
    else:
        test_rel_to_root = test_abs
    cmd = pytest_cmd(root) + [
        "-q",
        "--override-ini=addopts=" + sanitized_addopts(root),
        test_rel_to_root,
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=root,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return 124, ""
    except (OSError, ValueError) as exc:
        return -1, str(exc)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


# ------------------------------------------------------------------- envelopes


def emit(message: str) -> None:
    """A PostToolUse note. Built with json.dumps, never a format string: an
    unparseable hook envelope is DROPPED by the harness, and a TDD hook that
    says nothing reads exactly like a gate that passed."""
    DECIDED.append(True)
    if CONFIG_STATE and CONFIG_STATE[0]:
        message = f"{message}\n\n{CONFIG_STATE[0]}"
    print(json.dumps({"systemMessage": message}))
    sys.exit(0)


def notice(message: str) -> None:
    """A PreToolUse edit that is allowed and announced. With the config unreadable the allow
    becomes an ask carrying the message and the config note: one JSON object, never a
    message beside the degraded ask."""
    DECIDED.append(True)
    reason = CONFIG_STATE[0] if CONFIG_STATE else ""
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"{message}\n\n{reason}",
        }}))
    else:
        print(json.dumps({"systemMessage": message}))
    sys.exit(0)


def deny(reason: str) -> None:
    DECIDED.append(True)
    if CONFIG_STATE and CONFIG_STATE[0]:
        reason = f"{reason}\n\n{CONFIG_STATE[0]}"
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    sys.exit(0)
