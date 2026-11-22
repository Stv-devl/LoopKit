#!/usr/bin/env python3
# cwk-guard-api: 1
"""Pick the security surfaces a ship diff touches, and file the audit's follow-ups.

`select --base <rev>` reads the working tree against `<rev>` (untracked files included) and
prints the surfaces to audit, each with one reason. `follow-ups docs/work/<slug>/<file>.json`
appends the audit's Majors and Minors to `docs/work/<slug>/follow-ups.md`.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import project_config  # noqa: E402

ORDER = ("authz", "session", "input-output")
AUDIT_SURFACES = ("secrets", "authz", "input-output", "session", "data-exposure", "supply-chain")
SEVERITIES = ("Critical", "Major", "Minor")
WINDOW = 30
COMMENT_PREFIXES = ("//", "#", "*", "/*", "{/*", "<!--")
SESSION_IDENTIFIERS = (
    "signIn", "signOut", "logIn", "logOut", "login", "logout", "sign_in", "sign_out",
    "onAuthStateChange", "setSession", "getSession", "switchUser",
)
SESSION_TRIGGERS = SESSION_IDENTIFIERS + (
    "queryClient.clear(", ".resetQueries(", ".removeQueries(",
    "localStorage", "sessionStorage", "indexedDB", "document.cookie", "persist(",
    "accessToken", "refreshToken", "access_token", "refresh_token", "Authorization", "Bearer ",
)
RESETS = (".reset(", ".$reset(", ".clear(", "clearStorage(")
IO_TRIGGERS = (
    "dangerouslySetInnerHTML", ".innerHTML", "outerHTML", "insertAdjacentHTML",
    'target="_blank"', 'target: "_blank"', "target: '_blank'",
    "window.open(", "location.href =", "location.assign(",
    'type="file"', "FormData", "FileReader", "UploadFile", "multipart",
    "webhook", "callback", ".passthrough(", "z.any(", "z.unknown(",
)
IO_PATTERN = re.compile(r"(?:href|src)=\{(?!\s*[\"'`])")
PATH_WORDS = ("webhook", "callback")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def refuse(message: str) -> None:
    print(f"kit-audit-surface: {message}", file=sys.stderr)
    raise SystemExit(2)


def git(*args: str) -> str:
    result = subprocess.run(["git", "-c", "core.quotePath=false", *args],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        refuse(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def skipped(path: str) -> bool:
    parts = PurePosixPath(path).parts
    name = parts[-1] if parts else path
    return (
        parts[:1] in (("docs",), (".claude",))
        or "tests" in parts[:-1]
        or "e2e" in parts[:-1]
        or name.endswith(".md")
        or ".test." in name
        or ".spec." in name
    )


def boundary_schema(path: str) -> bool:
    name = PurePosixPath(path).name
    return (name.endswith((".gateway.ts", ".schema.ts")) or name == "schemas.ts"
            or path.startswith("shared/schemas/"))


def changed(base: str) -> tuple[list[str], dict[str, list[tuple[int, str]]], dict[str, list[str]]]:
    """Every changed path (diff order, then untracked), the added lines of each file with their
    number, and the removed lines of each file. Each file is diffed on its own, by the name `-z`
    gave, so no `+++` label is ever parsed and a line starting with `++ ` is only a line."""
    names = git("diff", "--no-renames", "--name-only", "-z", base).split("\0")
    untracked = git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
    paths = [p for p in names if p] + [p for p in untracked if p and p not in names]
    added: dict[str, list[tuple[int, str]]] = {}
    removed: dict[str, list[str]] = {}
    for path in (p for p in names if p):
        patch = git("diff", "--no-color", "--no-ext-diff", "--no-renames", "-U0",
                    "--src-prefix=a/", "--dst-prefix=b/", base, "--", f":(top,literal){path}")
        number, inside = 0, False
        for line in patch.splitlines():
            if line.startswith("@@"):
                match = HUNK.match(line)
                number = int(match.group(1)) if match else 0
                inside = True
            elif not inside:
                continue
            elif line.startswith("+"):
                added.setdefault(path, []).append((number, line[1:]))
                number += 1
            elif line.startswith("-"):
                removed.setdefault(path, []).append(line[1:])
    for path in untracked:
        if path and path not in names:
            added[path] = list(enumerate(read_lines(path), start=1))
    return paths, added, removed


def read_lines(path: str) -> list[str]:
    try:
        data = Path(path).read_bytes()
    except OSError:
        return []
    if b"\0" in data:
        return []
    return data.decode("utf-8", errors="replace").splitlines()


def session_reason(path: str, number: int, text: str, lines: list[str]) -> str | None:
    for trigger in SESSION_TRIGGERS:
        if trigger in text:
            return f"`{trigger}` at {path}:{number}"
    reset = next((r for r in RESETS if r in text), None)
    if reset is None:
        return None
    window = lines[max(0, number - 1 - WINDOW):number]
    for identifier in SESSION_IDENTIFIERS:
        if any(identifier in line for line in window):
            return f"`{reset.strip('.(')}` near `{identifier}` at {path}:{number}"
    return None


def io_reason(path: str, number: int, text: str) -> str | None:
    for trigger in IO_TRIGGERS:
        if trigger in text:
            return f"`{trigger}` at {path}:{number}"
    match = IO_PATTERN.search(text)
    if match:
        return f"`{match.group(0)}` at {path}:{number}"
    if "z.object(" in text and boundary_schema(path):
        return f"`z.object(` in a boundary schema at {path}:{number}"
    return None


def select(base: str) -> dict[str, object]:
    try:
        config = project_config.load_strict(os.getcwd())
    except project_config.ConfigError as error:
        refuse(f"{error}")
    if git("rev-parse", "--is-inside-work-tree").strip() != "true":
        refuse("not inside a git work tree")
    result = subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}"],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        refuse(f"--base {base} is not a commit")
    roots = getattr(config, "server_roots", None)
    if roots is None:
        refuse("the project_config.py reader has no server_roots: merge project_config.py.new")
    paths, added, removed = changed(base)
    reasons: dict[str, str] = {}
    for path in paths:
        first = PurePosixPath(path).parts[0]
        if first in roots:
            reasons.setdefault("authz", f"server root `{first}`: {path}")
            break
    for path in paths:
        if skipped(path):
            continue
        word = next((w for w in PATH_WORDS if w in path), None)
        if word:
            reasons.setdefault("input-output", f"`{word}` in the path {path}")
        lines_of: list[str] | None = None
        for number, text in added.get(path, []):
            if text.strip().startswith(COMMENT_PREFIXES):
                continue
            if "session" not in reasons:
                if lines_of is None:
                    lines_of = read_lines(path)
                found = session_reason(path, number, text, lines_of)
                if found:
                    reasons["session"] = found
            if "input-output" not in reasons:
                found = io_reason(path, number, text)
                if found:
                    reasons["input-output"] = found
        if "session" not in reasons:
            for text in removed.get(path, []):
                if text.strip().startswith(COMMENT_PREFIXES):
                    continue
                trigger = next((t for t in SESSION_TRIGGERS if t in text), None)
                if trigger:
                    reasons["session"] = f"`{trigger}` removed from {path}"
                    break
    surfaces = [{"surface": s, "reason": reasons[s]} for s in ORDER if s in reasons]
    reason = None
    if not surfaces:
        count = len(paths)
        files = f"{count} file{'' if count == 1 else 's'}"
        root = "no server root touched" if roots else "no server root declared"
        reason = f"{root}, no trigger line added ({files})"
    return {"surfaces": surfaces, "reason": reason}


def gate_route():
    spec = importlib.util.spec_from_file_location("kit_gate_route", HERE / "kit-gate-route.py")
    if spec is None or spec.loader is None:
        refuse("kit-gate-route.py cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def finding_line(index: int, raw: object) -> tuple[str, str | None]:
    if not isinstance(raw, dict):
        refuse(f"finding {index} is not an object")
    for key in ("surface", "severity", "path", "line", "problem"):
        if key not in raw:
            refuse(f"finding {index} lacks {key}")
    surface, severity, path = raw["surface"], raw["severity"], raw["path"]
    line, problem = raw["line"], raw["problem"]
    if surface not in AUDIT_SURFACES:
        refuse(f"finding {index}: surface {surface!r} is not one of {', '.join(AUDIT_SURFACES)}")
    if severity not in SEVERITIES:
        refuse(f"finding {index}: severity {severity!r} is not one of {', '.join(SEVERITIES)}")
    if not isinstance(path, str) or not path or not isinstance(problem, str) or not problem:
        refuse(f"finding {index}: path and problem must be non-empty strings")
    if line is not None and (type(line) is not int or line < 1):
        refuse(f"finding {index}: line must be a positive integer or null")
    if severity == "Critical":
        return severity, None
    where = path if line is None else f"{path}:{line}"
    return severity, f"- [audit:{surface}] {where} — {problem} ({severity.lower()})"


def follow_ups(argument: str) -> dict[str, object]:
    route = gate_route()
    try:
        gate, path = route.gate_dir(argument)
    except route.Refused as error:
        refuse(str(error))
    if path.suffix != ".json" or not path.is_file():
        refuse(f"{argument} is not an existing .json file")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError) as error:
        refuse(f"{argument} cannot be read as JSON: {error}")
    findings = data.get("findings") if isinstance(data, dict) else None
    if not isinstance(findings, list):
        refuse(f"{argument} has no findings list")
    parsed = [finding_line(i, raw) for i, raw in enumerate(findings)]
    counts = {s: sum(1 for severity, _ in parsed if severity == s) for s in SEVERITIES}
    added = route.append_follow_ups(gate, [line for _, line in parsed if line is not None])
    return {
        "critical": counts["Critical"],
        "major": counts["Major"],
        "minor": counts["Minor"],
        "follow_ups": gate.follow_ups.as_posix(),
        "follow_ups_added": added,
        "next": "stop" if counts["Critical"] else "clear",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    pick = commands.add_parser("select")
    pick.add_argument("--base", required=True)
    file_them = commands.add_parser("follow-ups")
    file_them.add_argument("input")
    args = parser.parse_args()
    if args.command == "select":
        result = select(args.base)
    else:
        result = follow_ups(args.input)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
