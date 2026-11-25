#!/usr/bin/env python3
"""Append one review finding to the gitignored kit health log, `.claude/.kit-health.jsonl`.

`kit-health.py finding --dim <d> --verdict confirmed|refuted|minor --summary <text>` appends
one JSON line `{ts, source: "review:<d>", event: "finding", verdict, summary}` under the
project root (the current directory). Its reader is `kit-doctor.py` `check_kit_health`.
Best-effort: a log that cannot be written prints one English line on stderr and exits 0.
A verdict outside the three exits 2 and appends nothing.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

VERDICTS = ("confirmed", "refuted", "minor")
LOG = Path(".claude") / ".kit-health.jsonl"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="kit-health.py", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    finding = sub.add_parser("finding", help="log one review finding")
    finding.add_argument("--dim", required=True, help="review dimension")
    finding.add_argument("--verdict", required=True, help="confirmed, refuted or minor")
    finding.add_argument("--summary", required=True, help="one line")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.verdict not in VERDICTS:
        print(f"kit-health: verdict must be one of {', '.join(VERDICTS)}", file=sys.stderr)
        return 2
    event = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": f"review:{args.dim}",
        "event": "finding",
        "verdict": args.verdict,
        "summary": args.summary,
    }
    try:
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(event, ensure_ascii=False) + "\n")
    except OSError as exc:
        print(f"kit-health: could not write {LOG}: {type(exc).__name__}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
