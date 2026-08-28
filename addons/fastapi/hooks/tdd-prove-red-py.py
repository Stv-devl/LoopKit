#!/usr/bin/env python3
#
# Hook: tdd-prove-red-py
# Event: PostToolUse (Write|Edit)
# Purpose: The Python half of the RED proof. Runs the pytest file that was just
#          written, decides whether that run is a GENUINE red, and — when it is —
#          drops the marker `tdd-require-red-py.py` requires before the service
#          module may be created.
#
# The twin of `.claude/hooks/tdd-prove-red.sh`, and it answers the sentence that
# rule 07-backend.md used to end on: "extending the cycle to Python means a
# pytest RED prover — a real piece of work, not a regex widening." This is that
# prover. What made it work is not the regex, it is the four exit codes below.
#
# WHAT A PYTEST RUN ACTUALLY RETURNS, measured on pytest 9.1.1 rather than
# assumed, because three different outcomes share one exit code:
#
#   exit 0  green
#   exit 1  an assertion fired          -> the real RED
#   exit 2  SyntaxError                 -> broken file, proves nothing
#   exit 2  module under test missing   -> the legitimate first RED
#   exit 2  some OTHER import missing   -> broken file, proves nothing
#   exit 2  `cannot import name X from Y` -> a DIFFERENT message from
#           ModuleNotFoundError ("No module named" never appears in it), so it
#           needs its own branch: legitimate red when Y is the module under
#           test, a broken helper import otherwise
#   exit 5  no test collected           -> proves nothing
#
# And two things that are not exit codes at all: a case pytest was asked to SKIP,
# and a file that imports nothing from the module under test. Both fail, neither
# proves anything.
#
# So the exit code alone cannot decide, exactly as on the TypeScript side, and
# the discrimination is on the module name inside the ModuleNotFoundError. It is
# an EXACT match, never a prefix: a project whose `app` package is not importable
# at all reports `No module named 'app'`, and a prefix match would read that
# packaging failure as the legitimate first red of every feature.
#
# CONFIGURE: the layers, the module root and the runner live in tdd_py_lib.py.

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tdd_py_lib as lib  # noqa: E402

# Below the harness timeout in settings.json, so a slow suite reports instead of
# being killed silently. A hook that dies without a word looks like a green gate.
RUN_TIMEOUT = 150

lib.register_timing("tdd-prove-red-py")


def imported_symbols(source: str, dotted: str) -> set:
    """The names this test file exercises from the module under test.

    Three import forms, because all three are idiomatic and an agent writes
    whichever the surrounding file uses:
        from app.services.project import slugify, total as t
        from app.services import project        -> project.<name>
        import app.services.project as svc      -> svc.<name>
    """
    symbols = set()
    flat = re.sub(r"\s*\\\n\s*", " ", source)
    escaped = re.escape(dotted)

    for match in re.finditer(
        r"from\s+%s\s+import\s+(\([^)]*\)|[^\n]+)" % escaped, flat
    ):
        clause = match.group(1).strip().strip("()")
        for piece in clause.split(","):
            name = piece.strip().split(" as ")[0].strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) and name != "*":
                symbols.add(name)

    aliases = set()
    parent, _, leaf = dotted.rpartition(".")
    if parent:
        for match in re.finditer(
            r"from\s+%s\s+import\s+([^\n]+)" % re.escape(parent), flat
        ):
            for piece in match.group(1).split(","):
                raw = piece.strip()
                name = raw.split(" as ")[0].strip()
                if name == leaf:
                    aliases.add(raw.split(" as ")[-1].strip() if " as " in raw else leaf)
    for match in re.finditer(r"import\s+%s\s+as\s+([A-Za-z_][A-Za-z0-9_]*)" % escaped, flat):
        aliases.add(match.group(1))

    for alias in aliases:
        for match in re.finditer(
            r"\b%s\.([A-Za-z_][A-Za-z0-9_]*)" % re.escape(alias), flat
        ):
            symbols.add(match.group(1))

    return symbols


def main() -> None:
    payload = lib.read_payload()
    file_path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not file_path or not lib.is_frozen_test(file_path):
        sys.exit(0)

    abs_test = lib.abs_path(file_path)
    if not os.path.isfile(abs_test):
        sys.exit(0)

    impl_rel = lib.impl_for_test(file_path)
    dotted = lib.dotted_module(impl_rel)
    abs_impl = os.path.join(lib.project_dir(), impl_rel)
    impl_exists = os.path.isfile(abs_impl)

    try:
        with open(abs_test, encoding="utf-8") as fh:
            source = fh.read()
    except OSError:
        sys.exit(0)

    # Does the file assert anything at all? A run that fails without asserting is
    # a broken file, not a RED phase — and it is the exact shape of the "red" an
    # agent produces when it is in a hurry. `pytest.raises` counts: asserting
    # that a call raises IS an assertion about behaviour.
    has_assertion = bool(
        re.search(r"(^|\W)assert(\s|\()", source)
        or re.search(r"pytest\.raises|assertRaises|assert_", source)
    )

    # And does it contain a case at all? This one is checked on the SOURCE, not
    # on pytest's count, and the difference is the whole point: when the module
    # under test does not exist yet — the legitimate first RED — collection dies
    # on the import and pytest never counts anything. exit 5 ("no tests ran")
    # therefore cannot fire on precisely the run this hook exists to bless, and a
    # file holding zero `def test_` was recorded as a genuine red. Measured.
    has_case = bool(re.search(r"^\s*(?:async\s+)?def\s+test_", source, re.M))

    exit_code, output = lib.run_pytest(file_path, RUN_TIMEOUT)
    tail = "\n".join(output.strip().splitlines()[-15:])

    if exit_code == 124:
        lib.emit(
            "TDD: pytest exceeded %ds on %s — the RED phase was NOT proved and no "
            "marker was recorded. Run it yourself and report the outcome, or raise "
            "RUN_TIMEOUT in tdd-prove-red-py.py." % (RUN_TIMEOUT, file_path)
        )

    if exit_code == -1 or re.search(r"No module named ['\"]?pytest", output):
        lib.emit(
            "TDD: pytest could not be launched for %s, so the RED phase was NOT "
            "proved and tdd-require-red-py.py will refuse to create %s. Install "
            "pytest in the project environment, or point CWK_PYTEST at the right "
            "command.\n\n%s" % (file_path, impl_rel, tail)
        )

    if exit_code == 4:
        lib.emit(
            "TDD: pytest rejected its own arguments on %s (usage error), so nothing "
            "was proved and no marker was recorded. This is a configuration "
            "problem, not a test result.\n\n%s" % (file_path, tail)
        )

    # ---- classify the failure ------------------------------------------------
    missing_modules = re.findall(r"No module named ['\"]([^'\"]+)['\"]", output)

    # `ImportError: cannot import name 'X' from 'Y'` is a DIFFERENT CPython
    # branch from ModuleNotFoundError, with different message text: the phrase
    # "No module named" is absent from it. The classifier looked only for that
    # phrase, so a name that does not exist in a module that does fell through to
    # the default `assertion` — pytest exits 2 on the collection error, zero
    # assertions run, and the marker was written. Trigger measured in practice: a
    # test importing a factory under the wrong name.
    #
    # Which side it lands on depends on WHICH module the name is missing from:
    #   the module under test  -> the legitimate first red for a new symbol,
    #                             exactly like the module itself not existing
    #   anything else          -> a broken helper/fixture import, proves nothing
    bad_names = re.findall(
        r"cannot import name ['\"]([^'\"]+)['\"] from(?: partially initialized module)?"
        r"\s+['\"]([^'\"]+)['\"]",
        output,
    )
    other_bad_names = [(n, m) for n, m in bad_names if m != dotted]

    failure_kind = "assertion"
    if exit_code == 5:
        failure_kind = "no-tests"
    elif re.search(r"async def functions are not natively supported", output):
        # The test FAILED without running a line of itself: no async plugin
        # claimed it. A FastAPI service test is async almost by definition, so
        # this would otherwise record a genuine-looking RED for every single one
        # of them, on a suite that never executed an assertion — the apparatus
        # fully armed on nothing. Measured on pytest 9.1.1 + pytest-asyncio in
        # its default strict mode.
        failure_kind = "async-not-configured"
    elif re.search(r"SyntaxError|IndentationError", output):
        failure_kind = "broken-file"
    elif other_bad_names:
        failure_kind = "unresolved-name"
    elif missing_modules:
        if dotted in missing_modules:
            failure_kind = "missing-module"
        elif any(dotted.startswith(m + ".") for m in missing_modules):
            failure_kind = "unimportable-package"
        else:
            failure_kind = "unresolved-other"
    elif bad_names:
        # every one of them names the module under test: the symbol does not
        # exist yet, which is the first RED of a new function in a module that
        # already exists.
        failure_kind = "missing-module"

    # Belt, not braces: sanitized_addopts() already strips the coverage flags, so
    # this should be unreachable. It stays because the failure it guards is
    # silent and total — a GREEN suite recorded as a RED, which arms the whole
    # apparatus on nothing.
    if exit_code == 1 and re.search(r"Required test coverage|Coverage failure", output):
        if not re.search(r"\d+ (failed|error)", output):
            lib.emit(
                "TDD: %s PASSES — pytest exited non-zero only because the coverage "
                "floor was not reached, which says nothing about this file. NO "
                "marker was recorded. If you meant to prove a RED, the test asserts "
                "behaviour that already exists.\n\n%s" % (file_path, tail)
            )

    if exit_code != 0:
        if not has_case:
            lib.emit(
                "TDD: %s holds no `def test_…` at all, so pytest ran nothing — "
                "whatever it printed. NO marker was recorded and %s still cannot be "
                "created. A helper function is not a case: pytest collects on the "
                "`test_` prefix.\n\n%s" % (file_path, impl_rel, tail)
            )

        if not has_assertion:
            lib.emit(
                "TDD: %s failed, but it contains no assertion — no `assert`, no "
                "`pytest.raises`. A run that fails without asserting anything proves "
                "nothing about the behaviour it names, so NO marker was recorded and "
                "%s still cannot be created. Write the cases from the /loop:plan test "
                "plan, then save again.\n\n%s" % (file_path, impl_rel, tail)
            )

        if failure_kind == "no-tests":
            lib.emit(
                "TDD: pytest collected no test from %s — every test function must be "
                "named `test_*`. That is not a RED phase: NO marker was recorded.\n\n%s"
                % (file_path, tail)
            )

        if failure_kind == "async-not-configured":
            lib.emit(
                "TDD: %s failed because no async plugin claimed its `async def` tests — "
                "not because of the behaviour under test. Not a single assertion ran, "
                "so NO marker was recorded.\n\nFix the configuration, not the test: "
                "`asyncio_mode = \"auto\"` under [tool.pytest.ini_options] "
                "(`.claude/rules/07-backend.md`), and pytest-asyncio installed. Until "
                "then every async service test fails this way and none of them proves "
                "anything.\n\n%s" % (file_path, tail)
            )

        if failure_kind == "broken-file":
            lib.emit(
                "TDD: %s did not fail on an assertion — pytest could not even import "
                "it (syntax or indentation error). That is a broken test file, not a "
                "RED phase: NO marker was recorded. Fix the file and save again.\n\n%s"
                % (file_path, tail)
            )

        if failure_kind == "unimportable-package":
            lib.emit(
                "TDD: %s failed because `%s` itself is not importable, not because of "
                "the behaviour under test — so NO marker was recorded. This is the "
                "sys.path setup, not your test: run pytest as `python -m pytest`, or "
                "add `pythonpath = [\".\"]` to [tool.pytest.ini_options] "
                "(`.claude/rules/07-backend.md`).\n\n%s"
                % (file_path, missing_modules[0], tail)
            )

        if failure_kind == "unresolved-other":
            lib.emit(
                "TDD: %s failed on an import that is NOT the module under test (%s) — "
                "a helper, a fixture or a dependency that does not resolve. An "
                "unresolved import of the module under test is a legitimate red; this "
                "one only says the test file is broken. NO marker was recorded.\n\n%s"
                % (file_path, dotted, tail)
            )

        if failure_kind == "unresolved-name":
            names = ", ".join("`%s` from `%s`" % (n, m) for n, m in other_bad_names)
            lib.emit(
                "TDD: %s failed at COLLECTION on %s — a name that does not exist in a "
                "module that does, and not the module under test (%s). pytest exits 2 "
                "before a single assertion runs, so this says nothing about the "
                "behaviour under test: NO marker was recorded. Fix the import (a "
                "factory or fixture renamed?) and save again.\n\n%s"
                % (file_path, names, dotted, tail)
            )

        # A case that pytest is asked NOT to run cannot prove a red, and nothing
        # else on the Python side sees it: ruff has no `no-disabled-tests`, and
        # the freeze's own skip check only inspects what an Edit ADDS. A skip
        # present at RED time therefore armed the marker and shipped frozen —
        # the specification silently switched off, in a file that can no longer
        # be corrected.
        skipped = re.search(
            r"@pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\s*\(|^\s*pytestmark\s*=",
            source,
            re.M,
        )
        if skipped:
            lib.emit(
                "TDD: %s carries `%s`, so at least one case is not being run — and a "
                "case that does not run cannot prove a red. NO marker was recorded and "
                "%s still cannot be created.\n\nNothing else catches this on Python: "
                "ruff has no equivalent of `no-disabled-tests`, and the freeze only "
                "inspects what an edit adds. Remove the skip and save again; if the "
                "case is genuinely not ready, `pytest.mark.xfail` is not the answer "
                "either — park it as a comment in the /loop:plan test plan.\n\n%s"
                % (file_path, skipped.group(0).strip(), impl_rel, tail)
            )

        # The red has to exercise something this hook can read, exactly as the
        # GREEN branch below requires. Twin of the same guard in
        # `.claude/hooks/tdd-prove-red.sh`.
        if not imported_symbols(source, dotted):
            lib.emit(
                "TDD: %s failed, but this hook cannot tell what it exercises — it "
                "carries no import of %s that can be read. A red that names nothing "
                "about the module under test proves nothing about the behaviour it "
                "claims, so NO marker was recorded and %s still cannot be created.\n\n%s"
                % (file_path, dotted, impl_rel, tail)
            )

        # ---- a genuine RED -------------------------------------------------
        lib.write_marker(file_path)

        if not impl_exists:
            lib.emit(
                "TDD: RED confirmed for %s — %s does not exist yet. Now write just "
                "enough code to pass; the test does not move.\n\n%s"
                % (file_path, impl_rel, tail)
            )

        missing = sorted(imported_symbols(source, dotted) - lib.defined_names(abs_impl))
        if missing:
            lib.emit(
                "TDD: RED confirmed for %s — not yet in %s: %s. Write just enough "
                "code to pass; the test does not move.\n\n%s"
                % (file_path, impl_rel, " ".join(missing), tail)
            )
        lib.emit(
            "TDD: RED confirmed for %s — every symbol it exercises already exists in "
            "%s, so this is a new case on existing behaviour. Fix the implementation, "
            "not the test — it is frozen (`.claude/rules/07-backend.md`).\n\n%s"
            % (file_path, impl_rel, tail)
        )

    # ---- GREEN. The only question left is whether it proves anything ---------
    symbols = imported_symbols(source, dotted)
    if not symbols:
        lib.emit(
            "TDD: %s is GREEN, but this hook cannot tell what it exercises — it reads "
            "no import of %s. The RED phase is NOT proved: say so, or restate the "
            "test against the module under test." % (file_path, dotted)
        )

    missing = sorted(symbols - lib.defined_names(abs_impl)) if impl_exists else sorted(symbols)
    if missing:
        lib.emit(
            "TDD: %s PASSES while %s is not defined in %s — the test asserts nothing "
            "about the behaviour it names. Rewrite it before writing any "
            "implementation (`.claude/rules/07-backend.md`)."
            % (file_path, " ".join(missing), impl_rel)
        )

    lib.emit(
        "TDD: %s is GREEN and every symbol it exercises already exists in %s — the RED "
        "phase could NOT be proved for it. Legitimate only if this write was an "
        "unfreezing correction (`.claude/.tdd-unfrozen`). Otherwise the test was "
        "written after the code and proves nothing: say which one it is."
        % (file_path, impl_rel)
    )


if __name__ == "__main__":
    main()
