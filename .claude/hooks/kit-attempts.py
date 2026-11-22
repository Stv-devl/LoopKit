#!/usr/bin/env python3
# cwk-guard-api: 1
"""Record per-gate loop attempts in docs/work/<slug>/attempts.json."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

CEILING = 3


def load(path: Path) -> dict[str, dict[str, object]]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("attempts.json must contain an object")
    return data


def write_atomic(path: Path, data: dict[str, dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def log_health(event: str, gate: str, reason: str, now: str) -> None:
    """One JSONL line per gate result. Feeds `.claude/.kit-health.jsonl`,
    gitignored, local-only — read back by
    kit-doctor.py check_kit_health. Best-effort: never lets this probe fail the gate it observes."""
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    log = root / ".claude" / ".kit-health.jsonl"
    try:
        with log.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({"ts": now, "source": f"gate:{gate}", "event": event,
                                  "reason": reason}) + "\n")
    except OSError:
        pass


def record(path: Path, gate: str, reason: str, now: str) -> int:
    data = load(path)
    previous = data.get(gate, {})
    count = int(previous.get("count", 0)) + 1
    data[gate] = {"count": count, "last": now, "reason": reason}
    write_atomic(path, data)
    log_health("fail", gate, reason, now)
    return count


def clear(path: Path, gate: str) -> None:
    data = load(path)
    if gate in data:
        del data[gate]
        write_atomic(path, data)
    log_health("pass", gate, "", datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))


def block_board(path: Path, unit: str, gate: str, reason: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    matches = []
    for index, line in enumerate(lines):
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) >= 5 and cells[0] == unit:
            matches.append((index, cells))
    if len(matches) != 1:
        raise ValueError(f"board unit must match exactly once: {unit!r} matched {len(matches)}")
    index, cells = matches[0]
    cells[3] = f"BLOCKED — {gate} failed 3x : {reason}"
    lines[index] = "| " + " | ".join(cells) + " |"
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temporary.replace(path)


def clean_prefix(prefix: tuple[str, ...]) -> bool:
    """No `.git`, and `.claude` only as a trailing worktree track `.claude/worktrees/<name>`."""
    if ".git" in prefix:
        return False
    if ".claude" not in prefix:
        return True
    return prefix.count(".claude") == 1 and prefix[-3:-1] == (".claude", "worktrees")


def artifact_allowed(path: Path) -> bool:
    parts = path.resolve().parts
    pairs = [k for k in range(len(parts) - 1) if parts[k:k + 2] == ("docs", "work")]
    if not pairs:
        return False
    k = pairs[-1]
    return len(parts) == k + 4 and clean_prefix(parts[:k])


def board_allowed(path: Path) -> bool:
    parts = path.resolve().parts
    return len(parts) >= 3 and parts[-3:-1] == ("docs", "product") and clean_prefix(parts[:-3])


def refuse(what: str, shape: str) -> None:
    print(f"kit-attempts: {what} must live at {shape}", file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("fail", "pass", "show"))
    parser.add_argument("artifact", type=Path)
    parser.add_argument("gate", nargs="?")
    parser.add_argument("reason", nargs="?")
    parser.add_argument("--now")
    parser.add_argument("--board", type=Path)
    parser.add_argument("--unit")
    args = parser.parse_args()
    if not artifact_allowed(args.artifact):
        refuse("artifact", "docs/work/<slug>/<file>")
    if args.board is not None and not board_allowed(args.board):
        refuse("board", "docs/product/<file>")
    path = args.artifact.parent / "attempts.json"

    if args.action == "show":
        print(json.dumps(load(path), indent=2, sort_keys=True))
        return 0
    if not args.gate:
        parser.error("gate is required for fail/pass")
    if args.action == "pass":
        clear(path, args.gate)
        print(f"{args.gate}: cleared")
        return 0
    if not args.reason:
        parser.error("reason is required for fail")

    now = args.now or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    count = record(path, args.gate, args.reason, now)
    if count >= CEILING and (args.board or args.unit):
        if not args.board or not args.unit:
            parser.error("--board and --unit must be provided together")
        block_board(args.board, args.unit, args.gate, args.reason)
    print(json.dumps({"gate": args.gate, "count": count, "ceiling": CEILING,
                      "blocked": count >= CEILING, "reason": args.reason}))
    return 3 if count >= CEILING else 0


if __name__ == "__main__":
    raise SystemExit(main())
