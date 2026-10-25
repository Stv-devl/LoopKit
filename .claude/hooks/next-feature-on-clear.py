#!/usr/bin/env python3
"""SessionStart on `/clear`: hand the fresh session the next feature to run.

The model cannot clear its own context; the user types `/clear` (it works from
Remote Control too), then `go`. This hook only fires on that clear and adds one
paragraph of context naming what `go` means: an interrupted feature first (a
board line `IN LOOP` whose work folder holds a handoff), else the topmost `READY`
line. An `IN LOOP` line with a worktree is held by another session and skipped;
one with neither is mentioned, never proposed: it may be held elsewhere.
Any other session start gets nothing.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys

HANDOFF_NAMES = ("handoff.md", "handoff-codex.md")


def board_rows(board: Path) -> list[dict[str, str]]:
    """The board's lines as dicts keyed by its header cells."""
    rows: list[dict[str, str]] = []
    header: list[str] | None = None
    for line in board.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [cell.strip().replace("\\|", "|").strip("`").strip()
                 for cell in re.split(r"(?<!\\)\|", line.strip("|"))]
        if header is None:
            if "State" in cells and "Entry artifact" in cells:
                header = cells
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        rows.append(dict(zip(header, cells)))
    return rows


def loop_slug(entry: str) -> str:
    """`/loop:research`'s slug rule: a story is `<feature>-<n>`, anything else its stem."""
    path = Path(entry)
    if len(path.parts) >= 3 and path.parts[:2] == ("docs", "stories"):
        return f"{path.parts[-2]}-{path.stem}"
    return path.stem


def handoff_of(project: Path, entry: str) -> str | None:
    work = project / "docs" / "work" / loop_slug(entry)
    for name in HANDOFF_NAMES:
        if (work / name).is_file():
            return str((work / name).relative_to(project))
    return None


def next_feature(project: Path) -> str:
    board = project / "docs" / "product" / "backlog.md"
    if not board.is_file():
        return ("No board (docs/product/backlog.md). Ask the user which entry artifact "
                "to run, then /loop:orchestrate <it>.")
    rows = board_rows(board)
    unsure: list[str] = []
    for row in rows:
        entry = row.get("Entry artifact", "")
        if row.get("State") != "IN LOOP" or entry in ("", "—"):
            continue
        name = row.get("Feature / story", entry)
        handoff = handoff_of(project, entry)
        if handoff:
            return (f"Interrupted feature: {name}. "
                    f"On `go`, run /loop:orchestrate {handoff}")
        if not (project / ".claude" / "worktrees" / loop_slug(entry)).is_dir():
            unsure.append(name)
    note = ""
    if unsure:
        note = (f" Also IN LOOP with no handoff and no worktree: {', '.join(unsure)} — "
                "another session may hold it; ask the user before resuming it.")
    for row in rows:
        entry = row.get("Entry artifact", "")
        if row.get("State") == "READY" and entry not in ("", "—"):
            return (f"Next feature (topmost READY): {row.get('Feature / story', entry)}. "
                    f"On `go`, run /loop:orchestrate {entry}.{note}")
    if note:
        return "No READY line on the board." + note
    return "No READY line on the board. Say so and ask the user what comes next."


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0
    if not isinstance(payload, dict) or payload.get("source") != "clear":
        return 0
    try:
        project = Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    except FileNotFoundError:
        return 0
    context = ("Fresh session after /clear. " + next_feature(project)
               + " Wait for the user's `go` before starting.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": context}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
