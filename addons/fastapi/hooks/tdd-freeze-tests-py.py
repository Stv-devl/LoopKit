#!/usr/bin/env python3
#
# Hook: tdd-freeze-tests-py
# Event: PreToolUse (Write|Edit)
# Purpose: Once a pytest file of a test-first layer has been written and proved
#          red, it stops moving. The implementation bends to the test, never the
#          reverse. The twin of tdd-freeze-tests.sh.
#
# Allowed:  adding a case, as a pure insertion carrying its own assertion.
#           Re-saving the file byte-for-byte identical (the only way to ask for a
#           fresh RED verdict when the red was observed inside a subagent).
# Denied:   rewriting an assertion, renaming or deleting a case, anchoring the
#           insertion INSIDE an existing case, and the four shapes below that
#           neutralise a case without touching a single assertion.
#
# `.claude/.tdd-unfrozen` is the visible exception, shared with the TypeScript
# cycle: a path, with a reason, in review.
#
# CONFIGURE: the layers and the module root live in tdd_py_lib.py.

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tdd_py_lib as lib  # noqa: E402

lib.register_timing("tdd-freeze-tests-py")

ASSERTION_RE = re.compile(r"(^|\W)assert(\s|\()|pytest\.raises|assertRaises|assert_")
# `def test_x(` or `async def test_x(`, the head of a case that already runs.
CASE_HEAD_RE = re.compile(r"(^|\W)(?:async\s+)?def\s+test_[A-Za-z0-9_]*\s*\(")
CONTROL_FLOW_RE = re.compile(r"(^|[\s;:])(return|raise)(\s|$|\()")


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def _spans_whole_lines(current: str, start: int, length: int) -> bool:
    """The anchor starts at a line start and ends at a line end (or EOF)."""
    if start > 0 and current[start - 1] != "\n":
        return False
    end = start + length
    return end >= len(current) or current[end] == "\n"


def added_base_indent(added: str) -> int:
    """The column the inserted block starts at, ignoring blank lines."""
    body = [ln for ln in added.split("\n") if ln.strip()]
    return min(_indent(ln) for ln in body) if body else 0


def enclosing_case_indent(current: str, offset: int):
    """Indent of the `def test_…` whose body contains `offset`, or None.

    Python has no closing delimiter, so "inside a case" is decided by
    indentation: the body of a `def test_…` runs until the first non-blank line
    indented at or below the def's own column.
    """
    pos = 0
    case_indent = None
    for line in current.split("\n"):
        end = pos + len(line)
        if line.strip():
            if case_indent is not None and _indent(line) <= case_indent:
                case_indent = None
            if re.match(r"\s*(?:async\s+)?def\s+test_[A-Za-z0-9_]*\s*\(", line):
                case_indent = _indent(line)
        if pos <= offset <= end + 1:
            return case_indent
        pos = end + 1
    return case_indent


def top_level_control_flow(added: str) -> bool:
    """A `return`/`raise` at the inserted block's OWN top level.

    `^\\s*(return|raise)` was line-start-only, so `if True: return` — inserted
    after a genuine assertion, killing every case below it — was allowed. Reading
    the statement anywhere on a line at the block's base indent catches the
    compound form; a `return` inside the new case's body sits deeper and is
    ordinary code.
    """
    body = [ln for ln in added.split("\n") if ln.strip()]
    if not body:
        return False
    base = min(_indent(ln) for ln in body)
    return any(_indent(ln) == base and CONTROL_FLOW_RE.search(ln) for ln in body)
# Every way pytest is asked to not run a case. Unlike the TypeScript side there
# is NO lint rule behind this one: `@vitest/eslint-plugin` fails the build on
# `it.skip`, ruff has no equivalent for `@pytest.mark.skip`. So the freeze is the
# only thing that sees it, and it refuses it here rather than at /ship.
SKIP_RE = re.compile(
    r"@pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\s*\(|pytestmark\s*="
)
# Patching the module under test turns every assertion in the frozen file into a
# statement about the patch. Patching what the service CALLS (an external client,
# another module) is legitimate and stays allowed — 07-backend.md asks for it.
#
# LIMIT, stated rather than hidden, and it is the same one the TypeScript twin
# declares: this matches a patch whose target is a STRING containing the dotted
# module. `monkeypatch.setattr(project, "slugify", ...)` — the module object,
# imported — is not matched, and neither is a target behind a variable.
# `/review`'s `tests` dimension owns those.
PATCH_RE = re.compile(r"\b(?:mocker\.)?(?:patch|patch\.object)\s*\(|monkeypatch\.setattr\s*\(")


def patched_module_names(added: str, dotted: str, impl_rel: str) -> tuple:
    """Patches aimed at the module under test. Returns (names, kind).

    kind is "defined" when the patched name is code the module itself DEFINES —
    the one that must be refused, because every assertion in the frozen file
    would then run against the patch.

    A name the module merely IMPORTS is a different thing and stays allowed:
    `patch("app.services.project.send_email")` is the form
    `patterns/pytest-backend.md` requires in as many words ("patch where the
    name is looked up, not where it is defined"). A substring check cannot tell
    the two apart and got it exactly backwards — it denied the documented form
    and allowed patching at the origin, which that same file calls a bug.

    kind is "unwritten" when the implementation does not exist yet. Then EVERY
    patch on the module is refused, and the narrowness of the window is the
    reason rather than an argument against: between RED and GREEN there is no
    module to patch, so no such line can be legitimate — and one inserted here
    is frozen into the file before the code it will go on to neutralise exists.
    """
    matches = []
    for match in re.finditer(
        r"['\"]%s\.([A-Za-z_][A-Za-z0-9_]*)" % re.escape(dotted), added
    ):
        if match.group(1) not in matches:
            matches.append(match.group(1))
    if not matches:
        return [], ""

    abs_impl = os.path.join(lib.project_dir(), impl_rel)
    if not os.path.isfile(abs_impl):
        return matches, "unwritten"

    defined = lib.defined_names(abs_impl)
    hits = [n for n in matches if n in defined]
    return (hits, "defined") if hits else ([], "")


def main() -> None:
    payload = lib.read_payload()
    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path") or ""
    if not file_path or not lib.is_frozen_test(file_path):
        sys.exit(0)

    abs_test = lib.abs_path(file_path)

    # The file does not exist yet: this is the RED phase, let it through.
    if not os.path.isfile(abs_test):
        sys.exit(0)

    if lib.is_unfrozen(file_path):
        sys.exit(0)

    try:
        with open(abs_test, encoding="utf-8") as fh:
            current = fh.read()
    except OSError:
        sys.exit(0)

    impl_rel = lib.impl_for_test(file_path)
    dotted = lib.dotted_module(impl_rel)

    # ---- Write ---------------------------------------------------------------
    content = tool_input.get("content")
    if content is not None:
        if content == current:
            print(
                '{"systemMessage": %s}'
                % _json(
                    "TDD: identical re-save of the frozen test '%s' — allowed, nothing "
                    "changed. tdd-prove-red-py is re-running it; read its verdict "
                    "before writing any implementation." % file_path
                )
            )
            sys.exit(0)
        lib.deny(
            "TDD: %s is frozen — it was validated at the /plan gate and proved red, "
            "and a wholesale overwrite rewrites assertions with nothing watching.\n\n"
            "Adding a case is allowed, as an Edit that inserts after the last line of "
            "the previous case and carries its own assertion. Correcting a case is a "
            "plan-level decision: say which case and why, add one line to "
            "`.claude/.tdd-unfrozen`:\n\n    %s  # <one-line reason>\n\nthen edit.\n\n"
            "The implementation bends to the test — fix %s instead."
            % (file_path, file_path, impl_rel)
        )

    # ---- Edit ----------------------------------------------------------------
    old_string = tool_input.get("old_string") or ""
    new_string = tool_input.get("new_string") or ""

    refused = ""
    anchor_at = current.find(old_string) if old_string else -1

    if not old_string:
        refused = "the edit does not anchor on anything the file already contains"
    elif old_string not in new_string:
        refused = "the edit replaces the anchor instead of inserting after it"
    elif anchor_at < 0:
        refused = "the anchor does not appear in the file as it stands"
    elif not _spans_whole_lines(current, anchor_at, len(old_string)):
        # THE hole this hook had. The assertion guard below tests the ANCHOR
        # STRING, never the line it sits on — so truncating the anchor by one
        # word made it stop "carrying an assertion" while the rest of the line
        # was still there to be rewritten. Measured: anchor `slugify("A, B!")`
        # taken out of `assert slugify("A, B!") == "a-b"` was ALLOWED, the real
        # expectation ended up commented out and the spec became `is not None`.
        #
        # A pure insertion never needs a partial line. Requiring the anchor to
        # start at a line start and end at a line end closes the whole class,
        # rather than adding one more thing to look for inside it.
        refused = (
            "the anchor covers only part of a line. A pure insertion anchors on whole "
            "lines; a partial anchor leaves the rest of the line to be rewritten while "
            "the anchor itself looks untouched"
        )

    if not refused:
        added = new_string.replace(old_string, "", 1)

        # Whether the addition lands inside a case is decided by ITS OWN column,
        # not by where the anchor sits. Python has no closing delimiter, so under
        # the addon's Arrange -> Act -> Assert convention the last line of the
        # previous case IS an assert — which is precisely the anchor this hook's
        # own deny text prescribes. Refusing an anchor because it carries an
        # assertion made the documented append unimplementable at the end of the
        # file, and pushed the only working anchor to the import block at the
        # top, inverting the required ordering. So the assertion in the anchor is
        # no longer the question: the question is whether the added block dedents
        # back out of the case.
        case_indent = enclosing_case_indent(current, anchor_at + len(old_string))
        if case_indent is not None and added_base_indent(added) > case_indent:
            refused = (
                "the inserted block is indented into the body of the `def test_…` it "
                "follows, so it lands INSIDE a case that already runs. A new case "
                "dedents back to column %d" % case_indent
            )
        elif CASE_HEAD_RE.search(old_string):
            refused = (
                "the anchor opens an existing `def test_…`, so the insertion lands "
                "INSIDE a case that already runs. Inserting a `return` at the top of a "
                "case leaves every assertion byte-for-byte intact and kills it anyway"
            )
        elif not ASSERTION_RE.search(added):
            refused = "the inserted block carries no assertion of its own"
        elif top_level_control_flow(added):
            refused = (
                "the inserted block carries a return/raise at its own top level, which "
                "skips the cases below it — `if True: return` on one line included"
            )
        elif SKIP_RE.search(added):
            refused = (
                "the inserted block skips or xfails a case. Nothing else catches this "
                "on Python — ruff has no equivalent of `no-disabled-tests` — so a "
                "skipped case would ship green and unnoticed"
            )
        elif PATCH_RE.search(added):
            patched, kind = patched_module_names(added, dotted, impl_rel)
            names = ", ".join("`%s`" % p for p in patched)
            if kind == "defined":
                refused = (
                    "the inserted block patches %s — code DEFINED by the module under "
                    "test (`%s`). Every assertion in this frozen file would then run "
                    "against the patch and pass whatever the implementation does. "
                    "Patching a name the service merely *imports* is a different thing "
                    "and stays allowed: that is the form `patterns/pytest-backend.md` "
                    "asks for" % (names, dotted)
                )
            elif kind == "unwritten":
                refused = (
                    "the inserted block patches %s on `%s`, which does not exist yet — "
                    "you are between RED and GREEN. Nothing there can be patched "
                    "legitimately, and a line added now is frozen into the file before "
                    "the code it would neutralise is even written" % (names, dotted)
                )

    if refused:
        lib.deny(
            "TDD: %s is frozen and this edit is not a pure insertion — %s.\n\n"
            "Allowed: appending a case. Anchor on the WHOLE last line of the previous "
            "case (an `assert` line is fine — that is what the last line of a case is), "
            "keep it verbatim, and let the added block dedent back to the column of "
            "`def test_…` and carry its own `assert` (or `pytest.raises`). No "
            "return/raise at its own top level, no skip/xfail, no patch of the module "
            "under test.\n\n"
            "Denied: rewriting an assertion, renaming or deleting a case, anchoring on "
            "part of a line. That is a plan-level correction — say which case and why, "
            "add one line to `.claude/.tdd-unfrozen`:\n\n    %s  # <one-line reason>\n\n"
            "then edit.\n\n"
            "The implementation bends to the test: fix %s."
            % (file_path, refused, file_path, impl_rel)
        )

    print(
        '{"systemMessage": %s}'
        % _json(
            "TDD: case appended to the frozen test %s — allowed as a pure insertion. "
            "Say which behaviour it covers and why the /plan test plan missed it."
            % file_path
        )
    )
    sys.exit(0)


def _json(text: str) -> str:
    import json

    return json.dumps(text)


if __name__ == "__main__":
    main()
