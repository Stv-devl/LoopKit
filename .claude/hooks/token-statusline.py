#!/usr/bin/env python3
"""Claude Code status line: display context usage and request a restart on the handoff."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys


def newest_artifact(project: Path) -> Path | None:
    """The newest workflow artifact, or its folder's handoff when there is one.

    Same choice as workflow.py's fallback_artifact: a shipped feature's leftover
    handoff must not outrank the feature in progress.
    """
    candidates: list[Path] = []
    for relative in ("docs/work", "docs/stories", "docs/specs", "docs/prd"):
        root = project / relative
        if root.is_dir():
            candidates.extend(root.rglob("*.md"))
    if not candidates:
        return None
    newest = max(candidates, key=lambda path: path.stat().st_mtime)
    for name in ("handoff.md", "handoff-codex.md"):
        if (newest.parent / name).is_file():
            return newest.parent / name
    return newest


def marker(project: Path, name: str) -> Path:
    return project / ".claude" / name


try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    print("ctx ?")
    raise SystemExit(0)

workspace = payload.get("workspace") or {}
project = Path(workspace.get("project_dir") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
context = payload.get("context_window") or {}
used = context.get("used_percentage")
if not isinstance(used, (int, float)):
    remaining = context.get("remaining_percentage")
    used = 100 - remaining if isinstance(remaining, (int, float)) else None

if used is None:
    print("ctx ?")
    raise SystemExit(0)

delegate = marker(project, ".token-delegate")
warning = marker(project, ".token-warning")
stop_agents = marker(project, ".token-stop-agents")
ready = marker(project, ".restart-ready")

if used >= 70:
    delegate.write_text(f"{used:.1f}\n")
else:
    delegate.unlink(missing_ok=True)

if used >= 90:
    warning.write_text(f"{used:.1f}\n")
    current = newest_artifact(project)
    if current and "docs/work/" in str(current.relative_to(project)):
        handoff = current.parent / "handoff.md"
        if not handoff.exists():
            handoff.write_text(
                "# Handoff: automatic context checkpoint\n"
                f"Token profile: economy\n"
                f"Entry: {current.relative_to(project)}\n"
                "Current phase: infer from the entry and adjacent artifacts\n\n"
                "## Completed\n"
                "- Read the adjacent workflow artifacts; do not redo completed phases.\n\n"
                "## In progress\n"
                "- Claude reached the context checkpoint threshold.\n\n"
                "## Remaining\n"
                "1. Infer the next concrete action from the entry, story status, and git status.\n\n"
                "## Verification\n"
                "- Inspect recorded results; do not assume unrecorded gates passed.\n"
            )
else:
    warning.unlink(missing_ok=True)

if used >= 95:
    stop_agents.write_text(f"{used:.1f}\n")
else:
    stop_agents.unlink(missing_ok=True)

if used >= 97 and not ready.exists():
    artifact = newest_artifact(project)
    ready.write_text((str(artifact.relative_to(project)) if artifact else "") + "\n")
elif used < 90:
    # Cleared like the other two markers, but on a hysteresis rather than on its
    # own threshold: /compact drops usage back down, and a .restart-ready left
    # behind keeps telling the external supervisor to restart Claude for a
    # context that has room again. 90 is far enough below 97 not to flap.
    ready.unlink(missing_ok=True)

suffix = ""
if used >= 97:
    suffix = " · RESTART"
elif used >= 95:
    suffix = " · stop agents"
elif used >= 90:
    suffix = " · checkpoint"
elif used >= 70:
    suffix = " · delegate"
print(f"ctx {used:.0f}%{suffix}")
