#!/usr/bin/env python3
"""Cases for `imported_symbols` in tdd-prove-red-py.py, run by test-hooks.sh.

The hook itself runs pytest, so the fixture sweep of test-hooks.sh cannot drive
it; its import parser is tested here directly. Expected sets are written by hand.
"""

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["CWK_HOOK_TIMING"] = "0"
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("prove_red", os.path.join(HERE, "tdd-prove-red-py.py"))
prove_red = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prove_red)

MODULE = "app.services.project"
CASES = [
    ("plain names", "from app.services.project import slugify, total as t\n", {"slugify", "total"}),
    ("trailing comment", "from app.services.project import f  # isort: skip\n", {"f"}),
    ("comment inside parentheses", "from app.services.project import (a,  # c\n b)\n", {"a", "b"}),
    ("parent alias with comment", "from app.services import project  # noqa\nproject.build()\n", {"build"}),
    ("module alias", "import app.services.project as svc\nsvc.total()\n", {"total"}),
    ("hash inside a string", "from app.services import project\nassert project.tag(\"#a\") == project.total()\n", {"tag", "total"}),
]


def main() -> int:
    """Run every case; print each failure and return its count."""
    failures = 0
    for title, source, expected in CASES:
        actual = prove_red.imported_symbols(source, MODULE)
        if actual != expected:
            failures += 1
            print(f"FAIL imported_symbols / {title}: expected {sorted(expected)}, got {sorted(actual)}")
    return failures


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
