#!/usr/bin/env python3
# cwk-guard-api: 1
#
# Hook: tdd-require-red-py
# Event: PreToolUse (Write|Edit)
# Purpose: A test-first service module cannot be CREATED before its pytest file
#          has been seen failing. The twin of tdd-require-red.sh.
#
# It gates creation only. Blocking later edits would deadlock GREEN and REFACTOR,
# which are the two legs that are supposed to change the implementation.
#
# The marker it requires is written by tdd-prove-red-py.py and carries the digest
# of the test file, so a marker cannot outlive the test that earned it.
#

import json
import os
import sys


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

lib.register_timing("tdd-require-red-py")


def main() -> None:
    payload = lib.read_payload()
    file_path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not file_path or not file_path.endswith(".py"):
        sys.exit(0)
    lib.configure(ask_on_pass=True)
    if not lib.VALUES:
        sys.exit(0)

    # The test file itself is somebody else's business (tdd-freeze-tests-py.py).
    if os.path.basename(file_path).startswith("test_"):
        sys.exit(0)

    if not lib.is_test_first_impl(file_path):
        sys.exit(0)

    # Already exists -> GREEN or REFACTOR, both legitimate. Let it through.
    if os.path.isfile(lib.abs_path(file_path)):
        sys.exit(0)

    # The single visible exception list, shared with the TypeScript cycle. Its
    # one honest use here is moving existing code into a new module.
    if lib.is_unfrozen(file_path):
        sys.exit(0)

    impl_rel = lib.rel_path(file_path)
    test_rel = lib.test_for_impl(file_path)
    abs_test = os.path.join(lib.project_dir(), test_rel)

    if not os.path.isfile(abs_test):
        lib.deny(
            "TDD: %s is a test-first layer and its test does not exist yet.\n\n"
            "Write %s first — the cases come from the `Test plan` block of "
            "docs/work/<slug>/plan.md, validated at the /loop:plan gate. Saving it runs "
            "pytest; when the run is a genuine red, the marker is recorded and this "
            "module can be created.\n\n"
            "`tests/` mirrors `%s/` — that mapping is what makes this hook able to "
            "find the test at all (`.claude/rules/07-backend.md`)."
            % (impl_rel, test_rel, lib.VALUES["module_root"])
        )

    if not lib.marker_is_fresh(abs_test):
        marker_exists = os.path.isfile(lib.marker_path(abs_test))
        if marker_exists:
            lib.deny(
                "TDD: %s exists but the recorded RED does not match it — the test "
                "changed after the red was proved.\n\n"
                "Re-save %s to get a fresh verdict from tdd-prove-red-py, then create "
                "%s. A marker that outlives the test it proved is how a module gets "
                "created against a red nobody observed."
                % (test_rel, test_rel, impl_rel)
            )
        lib.deny(
            "TDD: no RED was recorded for %s, so %s cannot be created.\n\n"
            "Save the test file and read tdd-prove-red-py's verdict. It refuses to "
            "record a marker when the failure proves nothing — no assertion in the "
            "file, a syntax error, no test collected, or an unresolved import that is "
            "not the module under test. If the test passes already, it asserts "
            "behaviour that exists: rewrite it.\n\n"
            "Genuine exception (moving existing code into a new module): list the "
            "path in `.claude/.tdd-unfrozen` as `<path>  # <one-line reason>` — visibly, never "
            "silently." % (test_rel, impl_rel)
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
