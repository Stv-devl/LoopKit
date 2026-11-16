#!/usr/bin/env python3
# cwk-guard-api: 1
#
# Hook: enforce-backend-layers
# Event: PreToolUse (Write|Edit)
# Purpose: Block the FastAPI layer violations that are mechanically detectable
#          with near-zero false positives. See .claude/rules/07-backend.md
#
#   1. HTTP in services/     : services/ importing or raising FastAPI HTTP objects
#   2. DB access in api/     : api/ running SQLAlchemy session calls itself
#   3. Client outside owner  : an external client imported outside the modules
#                              declared as its owners
#
# Anything ambiguous (a missing tenant filter, business logic hiding in a route)
# is deliberately NOT enforced here: those need judgement, and a hook that
# over-blocks gets disabled within a day. Backstop = the `reviewer` agent.
#
# NOTE: on Edit, only the inserted delta (new_string) is inspected, not the whole
#       file. A violation already present elsewhere in the file passes through.

import json
import os
import re
import sys
import time



def _ask_on_crash(kind, value, trace):
    """Any uncaught error, a mismatched tdd_py_lib.py included, asks: exit 1 would let the write through."""
    note = (f"{os.path.basename(sys.argv[0])} failed ({kind.__name__}: {value}); the hooks in .claude/hooks come "
            "from two kit versions. Restore them: rerun install.sh on this project, or /kit:init.")
    sys.stdout.write(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                       "permissionDecision": "ask",
                                                       "permissionDecisionReason": note}}))
    sys.stdout.flush()
    os._exit(0)


sys.excepthook = _ask_on_crash
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tdd_py_lib as lib  # noqa: E402

# --- timing ------------------------------------------------------------------
# Same log and same TSV columns as hook-lib.sh and english-comments.py, so
# hook-timings-report.sh sees this hook too. A hook missing from that log reads
# as a hook that costs nothing. Off with CWK_HOOK_TIMING=0.
if os.environ.get("CWK_HOOK_TIMING", "1") == "1":
    import atexit

    _T0 = time.time()

    def _record() -> None:
        log = os.path.join(
            os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".claude", ".hook-timings.log"
        )
        try:
            with open(log, "a") as fh:
                fh.write(
                    "%d\t%s\t%d\t%s\t%s\n"
                    % (_T0 * 1000, "enforce-backend-layers", (time.time() - _T0) * 1000, "-", "-")
                )
        except OSError:
            pass

    atexit.register(_record)


# FastAPI names that carry HTTP semantics. Depends/UploadFile/BackgroundTasks are
# NOT here: a service may legitimately receive them as values.
HTTP_NAMES = r"HTTPException|APIRouter|Request|Response|JSONResponse|StreamingResponse|status"

# Three ways the same violation is written. Matching only the first one let the
# other two through, and both are what an agent writes when the first is denied:
#   1. from fastapi import HTTPException          → the named import
#   2. import fastapi  … fastapi.HTTPException(…) → the qualified call
#   3. from starlette.responses import …          → the layer FastAPI re-exports
HTTP_IMPORT_RES = (
    r"from\s+fastapi[\w.]*\s+import\s+[^\n]*\b(?:%s)\b" % HTTP_NAMES,
    r"\bfastapi\.(?:%s)\b" % HTTP_NAMES,
    r"from\s+starlette[\w.]*\s+import\s+[^\n]*\b(?:%s)\b" % HTTP_NAMES,
    r"\bstarlette\.[\w.]*\b(?:%s)\b" % HTTP_NAMES,
    r"\braise\s+HTTPException\b",
)

DB_CALL_VERBS = r"(execute|add|add_all|commit|refresh|delete|get|scalar|scalars)"


def load_config() -> None:
    """`module_root` (matched on a path boundary, never as a bare substring: `app/` inside
    `/home/u/myapp/api/x.py` is not this package), `session_names` (how the project names
    the SQLAlchemy session it passes around) and `external_clients` (each client and the
    only module prefixes, under the module root, allowed to import it) come from
    `.claude/project.json` `fastapi`, through tdd_py_lib.configure. When the file cannot be
    read the kit defaults apply and a pass becomes an ask; with no reader, the hook asks."""
    lib.configure(ask_on_pass=True)
    if not lib.VALUES:
        sys.exit(0)


def module_root() -> str:
    """The module root with its trailing `/`."""
    return lib.VALUES["module_root"].rstrip("/") + "/"


def db_calls() -> str:
    """Session calls that mean "this file talks to the database"."""
    names = "|".join(re.escape(n) for n in lib.VALUES["session_names"])
    return r"\b(%s)\.%s\s*\(" % (names, DB_CALL_VERBS)


def deny(reason: str) -> None:
    lib.deny(reason)


def main() -> None:
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_input = data.get("tool_input", {}) or {}
    path = (tool_input.get("file_path") or "").replace("\\", "/")
    content = tool_input.get("content") or tool_input.get("new_string") or ""
    if not path or not content:
        sys.exit(0)

    if not path.endswith(".py"):
        sys.exit(0)
    load_config()
    match = None
    for m in re.finditer(r"(?:^|/)%s" % re.escape(module_root()), path):
        match = m
    if match is None:
        sys.exit(0)
    rel = path[match.end():]

    # Tests import and mock freely.
    if "/tests/" in path or rel.startswith("tests/") or "test_" in rel.rsplit("/", 1)[-1]:
        sys.exit(0)

    # --- Check 1: HTTP concepts inside services/ ---------------------------
    if rel.startswith("services/"):
        if any(re.search(pattern, content) for pattern in HTTP_IMPORT_RES):
            deny(
                f"HTTP concepts in the service layer ({rel}).\n\n"
                "services/ owns business logic, not transport: no HTTPException, no "
                "status codes, no Request/Response. Raise a business exception from "
                "core/exceptions.py — the global handler maps it to a status code. "
                "See .claude/rules/07-backend.md."
            )

    # --- Check 2: database access inside api/ ------------------------------
    if rel.startswith("api/") and not rel.endswith("deps.py"):
        if re.search(db_calls(), content):
            deny(
                f"Database access in the HTTP layer ({rel}).\n\n"
                "api/ routes validate, delegate and return. Move the query into "
                "services/ and call the service from the route. "
                "See .claude/rules/07-backend.md."
            )

    # --- Check 3: external client outside its owning modules ---------------
    for module, allowed in lib.VALUES["external_clients"].items():
        if any(rel.startswith(prefix) for prefix in allowed):
            continue
        pattern = r"(from\s+%s[\w.]*\s+import|import\s+%s\b)" % (
            re.escape(module), re.escape(module),
        )
        if re.search(pattern, content):
            deny(
                f"External client '{module}' imported outside its owning modules ({rel}).\n\n"
                f"Allowed: {', '.join(allowed)}.\n"
                "Raw I/O lives in one named layer; everything above it goes through "
                "a service. See .claude/rules/07-backend.md."
            )

    sys.exit(0)


if __name__ == "__main__":
    main()
