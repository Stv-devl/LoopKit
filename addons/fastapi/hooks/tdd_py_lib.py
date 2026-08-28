#!/usr/bin/env python3
#
# Shared library for the three Python TDD hooks:
#   tdd-require-red-py.py  (Pre)   — the implementation cannot be created first
#   tdd-prove-red-py.py    (Post)  — the RED is proved, not declared
#   tdd-freeze-tests-py.py (Pre)   — the proved test file stops moving
#
# It is the Python twin of `.claude/hooks/hook-lib.sh`, and it exists for the
# same reason: three hooks that each retype the layer list, the marker naming
# and the runner resolution are three hooks that drift apart in silence.
#
# CONFIGURE: MODULE_ROOT, TESTS_ROOT and TEST_FIRST_DIRS below.
#            They must agree with `.claude/rules/07-backend.md` ("Tests") and
#            with MODULE_ROOT in enforce-backend-layers.py.

import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import time

# --- configuration -----------------------------------------------------------
# The Python package root, relative to the project. Same value as
# enforce-backend-layers.py's MODULE_ROOT.
MODULE_ROOT = "app"
# Where the tests live. `tests/` MIRRORS the module root — that is the addon's
# own convention (`patterns/pytest-backend.md`, "Mirroring"), and it is what
# makes the test <-> module mapping derivable instead of guessed.
TESTS_ROOT = "tests"
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
TEST_FIRST_DIRS = ("services/",)
# -----------------------------------------------------------------------------

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


def is_test_first_impl(path: str) -> bool:
    """True for an implementation module the cycle applies to."""
    rel = rel_path(path)
    if not rel.endswith(".py"):
        return False
    if posixpath.basename(rel) == "__init__.py":
        return False
    prefix = MODULE_ROOT + "/"
    if not rel.startswith(prefix):
        return False
    inner = rel[len(prefix) :]
    if inner.startswith(TEST_FIRST_DIRS):
        return True
    # A FLAT module spelled like the layer — `app/services.py` rather than the
    # `app/services/` package `07-backend.md` prescribes. It happens on a small
    # service, and keying on the directory alone left it silently outside the
    # cycle, which is the worst of the two answers: the layout is wrong AND
    # nothing says so. The TypeScript side keys on the filename and covers its
    # own flat spelling (`services.ts`) for exactly this reason.
    return inner in tuple(d.rstrip("/") + ".py" for d in TEST_FIRST_DIRS)


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
    """tests/services/test_project.py -> app/services/project.py"""
    rel = rel_path(path)
    parts = rel.split("/")
    if not parts or not parts[-1].startswith("test_"):
        return ""
    parts[-1] = parts[-1][len("test_") :]
    if parts[0] == TESTS_ROOT:
        parts[0] = MODULE_ROOT
    else:
        return ""
    return "/".join(parts)


def test_for_impl(path: str) -> str:
    """app/services/project.py -> tests/services/test_project.py"""
    rel = rel_path(path)
    parts = rel.split("/")
    if not parts or parts[0] != MODULE_ROOT:
        return ""
    parts[0] = TESTS_ROOT
    parts[-1] = "test_" + parts[-1]
    return "/".join(parts)


def dotted_module(rel_impl: str) -> str:
    """app/services/project.py -> app.services.project"""
    return rel_impl[: -len(".py")].replace("/", ".") if rel_impl.endswith(".py") else ""


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
    listing = os.path.join(project_dir(), ".claude", ".tdd-unfrozen")
    if not os.path.isfile(listing):
        return False
    target = abs_path(path)
    try:
        with open(listing) as fh:
            lines = fh.readlines()
    except OSError:
        return False
    for line in lines:
        entry = line.split("#", 1)[0].strip().split()
        if not entry:
            continue
        entry = entry[0]
        if "/" not in entry:
            continue
        if entry in target:
            return True
    return False


# ------------------------------------------------------------------ the runner


def sanitized_addopts() -> str:
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
    """
    root = project_dir()

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


def pytest_cmd() -> list:
    """How to run pytest here, as a command prefix.

    ALWAYS `python -m pytest`, never the bare `pytest` console script. Measured
    on a tree laid out exactly as this addon prescribes: `pytest` exits 2 with
    `No module named 'app'`, `python -m pytest` exits 0 — `-m` puts the current
    directory on `sys.path`, the console script does not.
    """
    override = os.environ.get("CWK_PYTEST")
    if override:
        import shlex

        return shlex.split(override)

    root = project_dir()
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
    """
    cmd = pytest_cmd() + [
        "-q",
        "--override-ini=addopts=" + sanitized_addopts(),
        rel_path(test_path),
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=project_dir(),
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
    print(json.dumps({"systemMessage": message}))
    sys.exit(0)


def deny(reason: str) -> None:
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
