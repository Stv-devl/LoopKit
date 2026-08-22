#!/usr/bin/env python3
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
# CONFIGURE: MODULE_ROOT, SESSION_NAMES and EXTERNAL_CLIENTS below. An empty
#            EXTERNAL_CLIENTS disables check 3.
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

# --- configuration -----------------------------------------------------------
# Package root of the backend source, as it appears in the path.
#
# Matched on a path BOUNDARY, never as a bare substring: `app/` inside
# `/home/u/myapp/api/x.py` is not this package, and an unanchored match denied
# every write in a project whose directory happens to end in "app".
MODULE_ROOT = "app/"

# External clients and the ONLY modules allowed to import them.
# Paths are relative to MODULE_ROOT, matched as prefixes.
#   "<import specifier>": ["<allowed path prefix>", ...]
#
# Build the list from the code, not from the architecture you wish you had:
#   grep -rn "from app.core.<client> import" app/ | cut -d: -f1 | sort -u
# then remove the modules that should NOT be there and fix them — otherwise the
# first legitimate write gets blocked and the hook gets switched off.
EXTERNAL_CLIENTS: dict[str, list[str]] = {
    # "app.core.qdrant":  ["core/", "services/search.py", "services/ingestion/",
    #                      "services/chat/", "services/admin.py", "services/summary.py"],
    # "app.core.mistral": ["core/", "services/chat/", "services/ingestion/",
    #                      "services/admin.py", "services/summary.py"],
}
# -----------------------------------------------------------------------------

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

# CONFIGURE: how this project names the SQLAlchemy session it passes around.
# The patterns in this addon all use `db: AsyncSession` — a project that calls it
# `session` (or `async_session`) and leaves this list alone turns check 2 off
# without a word, which is the worst kind of guardrail. Grep first:
#   grep -rhoE "\b\w+: AsyncSession" app/ | sort -u
SESSION_NAMES = ("db", "session", "async_session")

# Session calls that mean "this file talks to the database".
DB_CALLS = r"\b(%s)\.(execute|add|add_all|commit|refresh|delete|get|scalar|scalars)\s*\(" % (
    "|".join(SESSION_NAMES),
)


def deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


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
    match = None
    for m in re.finditer(r"(?:^|/)%s" % re.escape(MODULE_ROOT), path):
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
        if re.search(DB_CALLS, content):
            deny(
                f"Database access in the HTTP layer ({rel}).\n\n"
                "api/ routes validate, delegate and return. Move the query into "
                "services/ and call the service from the route. "
                "See .claude/rules/07-backend.md."
            )

    # --- Check 3: external client outside its owning modules ---------------
    for module, allowed in EXTERNAL_CLIENTS.items():
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
