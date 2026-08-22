#!/usr/bin/env python3
#
# Hook: english-comments
# Event: PreToolUse (Write|Edit)
# Purpose: Comments in TS/JS sources must be English, JSDoc-only, attached to a
#          declaration, and short. See .claude/rules/03-conventions.md
#
#          On .py the rule is narrower — check 1 only. "English" is a project
#          rule whatever the language (03-conventions.md, and 07-backend.md when
#          the FastAPI addon is installed); "JSDoc only" is a TS convention with
#          no Python equivalent, since a docstring IS the documented form.
#
#   1. French comment        : accented char, or 2+ French stopwords in a block
#   2. Non-JSDoc comment     : `//` or `/* */` in the code (no implementation
#                              comments), except tooling directives
#   3. Floating JSDoc        : a /** */ block sitting on a statement (if, for,
#                              return, ...) instead of a declaration
#   4. Verbose JSDoc         : block longer than MAX_JSDOC_LINES lines
#
# NOTE: on Edit, only the inserted delta (new_string) is inspected, not the whole
#       file. A French comment already present elsewhere passes through here —
#       backstop = reviewer agent. That delta may also START inside a comment
#       block, which the scanner infers rather than knows: see
#       _starts_inside_block.

import io
import sys
import json
import re
import os
import time
import tokenize
import atexit

# --- timing ------------------------------------------------------------------
# Same log and same TSV columns as hook-lib.sh and enforce-architecture.py, so
# hook-timings-report.sh sees this hook too. A hook missing from the log reads as
# a hook that costs nothing, and 11-token-budget.md leans on that report to
# decide what is worth optimising. Off with CWK_HOOK_TIMING=0.
if os.environ.get("CWK_HOOK_TIMING", "1") == "1":
    _T0 = time.time()

    def _record() -> None:
        log = os.path.join(
            os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".claude", ".hook-timings.log"
        )
        try:
            with open(log, "a") as fh:
                fh.write(
                    "%d\t%s\t%d\t%s\t%s\n"
                    % (_T0 * 1000, "english-comments", (time.time() - _T0) * 1000, "-", "-")
                )
        except OSError:
            pass

    atexit.register(_record)

MAX_JSDOC_LINES = 10

# `//` comments that are tooling directives, not prose.
DIRECTIVE = re.compile(
    r"^\s*/?\s*(eslint-|@ts-|prettier-ignore|biome-ignore|v8 ignore|"
    r"istanbul ignore|<reference|#!|@vitest-environment|deno-lint-ignore|"
    r"noinspection)"
)

# Generated or declaration files: never authored by hand.
SKIPPED = re.compile(r"(\.d\.ts|\.gen\.ts|routeTree\.gen\.tsx?)$")

# Tests and mocks keep their step-by-step comments; English is still enforced.
LOOSE = re.compile(r"(\.test\.tsx?|\.spec\.tsx?)$|/(mocks|__mocks__|test)/")

ACCENTED = re.compile(r"[àâäçéèêëîïôöùûüÿœæÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆ]")

# Python: tests and generated migrations keep their prose loose. A revision is
# written by Alembic, not by hand.
LOOSE_PY = re.compile(r"(^|/)(test_[^/]*|conftest)\.py$|/(alembic|migrations)/versions/")

FRENCH_WORDS = {
    "le", "la", "les", "un", "une", "des", "du", "de", "dans", "pour", "avec",
    "sans", "sur", "sous", "est", "sont", "etre", "avoir", "fait", "faire",
    "cette", "cet", "ces", "qui", "que", "dont", "pas", "ne", "plus", "alors",
    "donc", "mais", "aussi", "chaque", "tous", "toutes", "tout", "aucun",
    "retourne", "renvoie", "recupere", "permet", "doit", "peut", "verifie",
    "utilise", "ajoute", "supprime", "liste", "valeur", "ligne", "champ",
    "tableau", "chaine", "fichier", "erreur", "utilisateur", "appelle",
    "selon", "depuis", "entre", "vers", "ici", "celui", "celle", "leur",
    "notre", "nous", "vous", "elle", "ils", "elles", "sinon", "ainsi",
}

STATEMENT = re.compile(
    r"^\s*(if|for|while|switch|return|try|catch|finally|else|do|throw|await|"
    r"break|continue)\b"
)

# A `/` opens a regex literal when what precedes it cannot end an expression.
# Without this the scanner walks INTO the regex body and reads the `//` of
# `/https:\/\//` as a line comment — every file with an escaped slash in a
# regex was denied as an "implementation comment".
REGEX_PREV_CHARS = set("(,=:[!&|?{};+-*%~^<>")
REGEX_PREV_WORDS = {
    "return", "typeof", "case", "in", "of", "new", "delete", "void", "do",
    "else", "yield", "await", "instanceof",
}
IDENT_TAIL = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*$")


def _regex_starts_at(line: str, j: int) -> bool:
    """Is the `/` at index j the opening of a regex literal rather than a division?

    Biased towards "regex": guessing regex on a division only makes the scanner
    skip ahead (a missed comment, i.e. a false negative on a deny hook), while
    guessing division on a regex blocks legitimate code.
    """
    k = j - 1
    while k >= 0 and line[k] in " \t":
        k -= 1
    if k < 0:
        return True
    ch = line[k]
    if ch in REGEX_PREV_CHARS:
        return True
    if ch.isalnum() or ch in "_$":
        m = IDENT_TAIL.search(line[: k + 1])
        return bool(m and m.group(0) in REGEX_PREV_WORDS)
    return False


def _skip_regex(line: str, j: int):
    """Index just past the closing `/`, or None if the literal does not close here."""
    k = j + 1
    while k < len(line):
        c = line[k]
        if c == "\\":
            k += 2
            continue
        if c == "[":  # char class: a `/` inside it does not close the literal
            k += 1
            while k < len(line) and line[k] != "]":
                k += 2 if line[k] == "\\" else 1
        elif c == "/":
            return k + 1
        k += 1
    return None


# An Edit's delta can START inside a `/** */` block, and nothing in it says so.
# Scanned from a neutral state those lines read as code, so the first `//` they
# contain — a URL, a `//` shown in an example — was reported as an
# implementation comment, and a JSDoc containing one could only be edited by
# re-including its `/**`. Same class as the regex-literal case above: the
# scanner in the wrong state.
CONTINUATION = re.compile(r"^\s*\*")


def _starts_inside_block(lines) -> bool:
    """Does this delta begin in the middle of a block comment?

    Biased towards "yes", like _regex_starts_at: a wrong yes hides a comment
    from the scanner (a false negative on a deny hook, backstopped by the
    reviewer agent), a wrong no blocks a legitimate edit.
    """
    for line in lines:
        if not line.strip():
            continue
        return bool(CONTINUATION.match(line)) and "/*" not in line
    return False


def deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def scan(content: str):
    """Split the delta into comments, skipping strings and template literals.

    Returns (line_comments, block_comments) where each entry is
    (line_index, text) / (line_index, lines, is_jsdoc).
    """
    lines = content.split("\n")
    line_comments = []
    block_comments = []
    quote = None
    block = None

    # Assumed JSDoc: the opener is not in the delta, so its kind is unknown, and
    # guessing `/*` would deny the block outright at check 2.
    if _starts_inside_block(lines):
        block = {"start": 0, "lines": [], "jsdoc": True}

    for i, line in enumerate(lines):
        if block is not None:
            end = line.find("*/")
            block["lines"].append(line if end == -1 else line[:end])
            if end != -1:
                block_comments.append((block["start"], block["lines"], block["jsdoc"]))
                block = None
            continue

        j = 0
        while j < len(line):
            c = line[j]
            if quote:
                if c == "\\":
                    j += 2
                    continue
                if c == quote:
                    quote = None
            elif c in "\"'`":
                quote = c
            elif c == "/":
                nxt = line[j + 1] if j + 1 < len(line) else ""
                if nxt == "/":
                    line_comments.append((i, line[j + 2:]))
                    break
                if nxt == "*":
                    jsdoc = line[j:].startswith("/**")
                    end = line.find("*/", j + 2)
                    if end != -1:
                        block_comments.append((i, [line[j:end]], jsdoc))
                        j = end + 2
                        continue
                    block = {"start": i, "lines": [line[j:]], "jsdoc": jsdoc}
                    break
                if _regex_starts_at(line, j):
                    end = _skip_regex(line, j)
                    if end is not None:
                        j = end
                        continue
            j += 1

        # Single and double quotes do not span lines; backticks do.
        if quote in ("'", '"'):
            quote = None

    return line_comments, block_comments


def scan_python(source: str) -> list[tuple[int, str]]:
    """Every comment and docstring of a Python delta, as (line, text).

    `tokenize` rather than a regex, for the same reason as no-any-type-py.py: a
    `#` inside a string is not a comment, and a docstring is a triple-quoted
    string that no line-oriented scan can find the end of. An Edit inserts a
    fragment, not a module, so failing to tokenize is the common case, not the
    exception — fall back to a cheap line scan rather than checking nothing.
    """
    found: list[tuple[int, str]] = []
    quotes = ('"""', "'''")
    try:
        prev_type = tokenize.INDENT
        for tok in tokenize.generate_tokens(io.StringIO(source).readline):
            if tok.type == tokenize.COMMENT:
                found.append((tok.start[0], tok.string.lstrip("#")))
            elif tok.type == tokenize.STRING and prev_type in (
                tokenize.INDENT, tokenize.NEWLINE, tokenize.NL, tokenize.DEDENT,
            ):
                # A string in statement position is a docstring: prose, not data.
                found.append((tok.start[0], tok.string.strip("\"'")))
            if tok.type not in (tokenize.NL, tokenize.COMMENT):
                prev_type = tok.type
        return found
    except (tokenize.TokenError, IndentationError, SyntaxError):
        for i, line in enumerate(source.split("\n"), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                found.append((i, stripped.lstrip("#")))
            elif stripped.startswith(quotes):
                found.append((i, stripped.strip("\"'")))
        return found


def is_french(text: str) -> bool:
    if ACCENTED.search(text):
        return True
    words = re.findall(r"[A-Za-z]+", text.lower())
    return len({w for w in words if w in FRENCH_WORDS}) >= 2


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

    # --- Python: check 1 only ----------------------------------------------
    if path.endswith(".py"):
        if LOOSE_PY.search(path):
            sys.exit(0)
        for line_no, text in scan_python(content):
            if is_french(text):
                deny(
                    f"French comment or docstring at line {line_no}: "
                    f"{text.strip()[:80]}\n\n"
                    "Comments, docstrings, logs and errors are written in English "
                    "(French is only for user-facing messages). "
                    "See .claude/rules/03-conventions.md."
                )
        sys.exit(0)

    if not re.search(r"\.(ts|tsx|js|jsx)$", path):
        sys.exit(0)
    if SKIPPED.search(path):
        sys.exit(0)
    loose = bool(LOOSE.search(path))

    lines = content.split("\n")
    line_comments, block_comments = scan(content)

    # --- Check 1: French ---------------------------------------------------
    for _, text in line_comments:
        if is_french(text):
            deny(
                f"French comment detected: //{text.strip()[:80]}\n\n"
                "Comments, logs and errors are written in English "
                "(French is only for user-facing messages). "
                "See .claude/rules/03-conventions.md."
            )
    for start, blines, _ in block_comments:
        body = " ".join(blines)
        if is_french(body):
            deny(
                f"French comment detected at line {start + 1}: "
                f"{body.strip()[:80]}\n\n"
                "Comments, logs and errors are written in English "
                "(French is only for user-facing messages). "
                "See .claude/rules/03-conventions.md."
            )

    # --- Check 2: JSDoc only -----------------------------------------------
    if loose:
        sys.exit(0)

    for _, text in line_comments:
        if text.strip() and not DIRECTIVE.match(text):
            deny(
                f"Implementation comment detected: //{text.strip()[:80]}\n\n"
                "Only JSDoc is allowed, and only on a declaration "
                "(function, hook, service, store, exported type). "
                "Explain the code by naming it better, not by commenting it. "
                "See .claude/rules/03-conventions.md."
            )
    for start, blines, jsdoc in block_comments:
        if not jsdoc and " ".join(blines).strip("/* \t"):
            deny(
                f"Non-JSDoc block comment at line {start + 1}.\n\n"
                "Use a /** ... */ JSDoc on the declaration, or no comment at all. "
                "See .claude/rules/03-conventions.md."
            )

    # --- Checks 3 & 4: JSDoc placement and length --------------------------
    for start, blines, jsdoc in block_comments:
        if not jsdoc:
            continue

        if len(blines) > MAX_JSDOC_LINES:
            deny(
                f"JSDoc block at line {start + 1} is {len(blines)} lines "
                f"(max {MAX_JSDOC_LINES}).\n\n"
                "Keep it to a one-line summary plus @param/@returns. "
                "Long explanations belong in docs/, not in the source."
            )

        nxt = next(
            (l for l in lines[start + len(blines):] if l.strip()),
            None,
        )
        if nxt is not None and STATEMENT.match(nxt):
            deny(
                f"JSDoc at line {start + 1} documents a statement, not a "
                f"declaration ({nxt.strip()[:60]}).\n\n"
                "JSDoc goes on functions, hooks, services, stores and exported "
                "types — not inside a function body. "
                "See .claude/rules/03-conventions.md."
            )

    sys.exit(0)


if __name__ == "__main__":
    main()
