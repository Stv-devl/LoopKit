#!/usr/bin/env python3
"""Measure the token cost of the loop, per agent and per phase, from Claude Code transcripts.

Reads `~/.claude/projects/<project>/` (one `<session>.jsonl` per session, its
sub-agents under `<session>/subagents/`). Method and rationale:
`docs/measuring-the-loop.md`. Costs are API-price equivalents, indicative only:
how a subscription weighs cache traffic is not public.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

PRICES = {
    "opus": {"in": 4.0, "out": 20.0, "read": 0.20},
    "sonnet": {"in": 2.0, "out": 10.0, "read": 0.20},
    "haiku": {"in": 0.10, "out": 0.50, "read": 0.01},
}
WRITE_5M, WRITE_1H = 1.25, 2.0
FIRST_TURN_HIT = 1000
PHASES = ["research", "interface", "plan", "execute", "review", "ship"]
ARTIFACT_PHASE = {"research": "research", "design": "interface", "plan": "plan"}
AGENT_PHASE = {
    "explorer": "research", "doc-researcher": "research", "designer": "interface",
    "plan-critic": "plan", "test-writer": "execute", "implementer": "execute",
    "reviewer": "review", "verifier": "review", "e2e-tester": "review",
    "security-auditor": "review", "github": "ship",
}
ARTIFACT_RE = re.compile(r"docs/work/[^/]+/(research|design|plan)\.md$")
COMMIT_RE = re.compile(r"\bgit\b[^|;&]*\bcommit\b")


def family(model: str) -> str | None:
    """Price family of a model id, or None for synthetic or unknown models."""
    return next((name for name in PRICES if name in (model or "")), None)


def read_jsonl(path: Path) -> list[dict]:
    """Every parseable JSON object of a transcript; a torn last line is skipped."""
    rows = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def turns(rows: list[dict]) -> list[dict]:
    """One entry per billed API response, de-duplicated on `message.id`."""
    seen, out = set(), []
    for row in rows:
        message = row.get("message") or {}
        if row.get("type") != "assistant" or "usage" not in message:
            continue
        if message.get("model") == "<synthetic>" or message.get("id") in seen:
            continue
        seen.add(message.get("id"))
        usage = message["usage"]
        split = usage.get("cache_creation") or {}
        write_1h = split.get("ephemeral_1h_input_tokens", 0)
        write = usage.get("cache_creation_input_tokens", 0)
        out.append({
            "ts": row.get("timestamp", ""),
            "model": message.get("model", ""),
            "in": usage.get("input_tokens", 0),
            "write_5m": write - write_1h,
            "write_1h": write_1h,
            "read": usage.get("cache_read_input_tokens", 0),
            "out": usage.get("output_tokens", 0),
        })
    return out


def efforts(rows: list[dict]) -> Counter:
    """Effort actually sent with each request, read from the request blobs."""
    seen = Counter()
    for row in rows:
        if row.get("type") == "api-request-blob":
            effort = ((row.get("message") or {}).get("output_config") or {}).get("effort")
            if effort:
                seen[effort] += 1
    return seen


def cost(turn: dict) -> float:
    """API-price equivalent of one response, in dollars."""
    price = PRICES.get(family(turn["model"]) or "")
    if not price:
        return 0.0
    return (turn["in"] * price["in"]
            + turn["write_5m"] * price["in"] * WRITE_5M
            + turn["write_1h"] * price["in"] * WRITE_1H
            + turn["read"] * price["read"]
            + turn["out"] * price["out"]) / 1e6


def phase_marks(rows: list[dict]) -> list[tuple[str, str]]:
    """(timestamp, phase entered) for every loop marker in the main transcript."""
    marks = []
    for row in rows:
        if row.get("type") != "assistant":
            continue
        for block in (row.get("message") or {}).get("content") or []:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            data = block.get("input") or {}
            name, ts = block.get("name"), row.get("timestamp", "")
            match = ARTIFACT_RE.search(str(data.get("file_path", "")))
            if name == "Write" and match:
                marks.append((ts, ARTIFACT_PHASE[match.group(1)]))
            elif name in ("Agent", "Task") and data.get("subagent_type") in AGENT_PHASE:
                marks.append((ts, AGENT_PHASE[data["subagent_type"]]))
            elif name == "Bash" and COMMIT_RE.search(str(data.get("command", ""))):
                marks.append((ts, "ship"))
    return sorted(marks)


def phase_at(marks: list[tuple[str, str]], ts: str) -> str:
    """The phase of the latest marker at or before `ts`. A session chains several
    features, so a marker may move back: the next feature's explorer after a
    commit is research again."""
    current = PHASES[0]
    for when, phase in marks:
        if when > ts:
            break
        current = phase
    return current


def sessions(root: Path, only: list[str], since: str) -> list[Path]:
    """Main transcripts of the selected sessions, oldest first."""
    found = []
    for path in sorted(root.glob("*.jsonl")):
        if only and not any(path.stem.startswith(prefix) for prefix in only):
            continue
        rows = read_jsonl(path)
        first = next((r.get("timestamp", "") for r in rows if r.get("timestamp")), "")
        if since and first and first < since:
            continue
        found.append(path)
    return found


def measure(root: Path, only: list[str], since: str) -> dict:
    """Per-agent and per-phase counters for the selected sessions."""
    agents: dict[str, dict] = defaultdict(lambda: {
        "launches": 0, "turns": [], "in": 0, "write": 0, "read": 0, "out": 0, "cost": 0.0,
        "first_write": [], "first_read": [], "first_hits": 0, "effort": Counter()})
    phases: dict[str, float] = defaultdict(float)
    selected = sessions(root, only, since)
    for main in selected:
        main_rows = read_jsonl(main)
        marks = phase_marks(main_rows)
        runs = [("(session)", main_rows)]
        for meta in sorted((main.parent / main.stem / "subagents").glob("*.meta.json")):
            transcript = meta.with_name(meta.name.replace(".meta.json", ".jsonl"))
            if transcript.exists():
                kind = json.loads(meta.read_text(encoding="utf-8")).get("agentType", "?")
                runs.append((kind, read_jsonl(transcript)))
        for kind, rows in runs:
            billed = turns(rows)
            if not billed:
                continue
            key = f"{kind} ({family(billed[0]['model']) or '?'})"
            agent = agents[key]
            agent["launches"] += 1
            agent["turns"].append(len(billed))
            agent["first_write"].append(billed[0]["write_5m"] + billed[0]["write_1h"])
            agent["first_read"].append(billed[0]["read"])
            agent["first_hits"] += billed[0]["read"] > FIRST_TURN_HIT
            agent["effort"].update(efforts(rows))
            for turn in billed:
                agent["in"] += turn["in"]
                agent["write"] += turn["write_5m"] + turn["write_1h"]
                agent["read"] += turn["read"]
                agent["out"] += turn["out"]
                agent["cost"] += cost(turn)
                phases[phase_at(marks, turn["ts"])] += cost(turn)
    return {"sessions": [p.stem for p in selected], "agents": agents, "phases": phases}


def summary(result: dict) -> dict:
    """JSON-serialisable view of `measure`, one row per agent."""
    rows = {}
    for key, agent in result["agents"].items():
        n = agent["launches"]
        rows[key] = {
            "launches": n,
            "turns_median": statistics.median(agent["turns"]),
            "in": agent["in"], "write": agent["write"], "read": agent["read"], "out": agent["out"],
            "cost": round(agent["cost"], 4),
            "first_write_median": statistics.median(agent["first_write"]),
            "first_read_median": statistics.median(agent["first_read"]),
            "first_hit_rate": round(agent["first_hits"] / n, 4),
            "effort": dict(agent["effort"]),
        }
    return {"sessions": result["sessions"], "agents": rows,
            "phases": {p: round(result["phases"].get(p, 0.0), 4) for p in PHASES}}


def markdown(view: dict, title: str) -> str:
    """The report written to `docs/measurements/`."""
    total = sum(a["cost"] for a in view["agents"].values()) or 1.0
    lines = [f"# {title}", "",
             f"{len(view['sessions'])} session(s). Costs are API-price equivalents, indicative.", "",
             "| Agent | Launches | Turns (median) | Fresh in | Cache write | Cache read | Out "
             "| First-turn write | First-turn hit | Effort | Cost | Share |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: |"]
    for key, a in sorted(view["agents"].items(), key=lambda kv: -kv[1]["cost"]):
        effort = ", ".join(f"{k} {v}" for k, v in sorted(a["effort"].items())) or "—"
        lines.append(
            f"| {key} | {a['launches']} | {a['turns_median']:.0f} | {a['in']} | {a['write']} "
            f"| {a['read']} | {a['out']} | {a['first_write_median']:.0f} "
            f"| {a['first_hit_rate']:.0%} | {effort} | ${a['cost']:.2f} | {a['cost'] / total:.0%} |")
    lines += ["", "| Phase | Cost | Share |", "| --- | ---: | ---: |"]
    for phase, value in view["phases"].items():
        lines.append(f"| {phase} | ${value:.2f} | {value / total:.0%} |")
    return "\n".join(lines) + "\n"


def default_root() -> Path:
    """Claude Code's transcript folder for the current project."""
    project = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    return Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", project)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=None, help="transcript folder of the project")
    parser.add_argument("--session", action="append", default=[], help="session id prefix (repeatable)")
    parser.add_argument("--since", default="", help="ISO timestamp; older sessions are skipped")
    parser.add_argument("--json", action="store_true", help="print JSON instead of Markdown")
    parser.add_argument("--out", type=Path, help="write the Markdown report to this file")
    parser.add_argument("--title", default="Token measurement")
    args = parser.parse_args()
    root = args.root or default_root()
    if not root.is_dir():
        print(f"kit-measure: no transcript folder at {root}", file=sys.stderr)
        return 2
    view = summary(measure(root, args.session, args.since))
    if args.json:
        print(json.dumps(view, indent=2, sort_keys=True))
        return 0
    report = markdown(view, args.title)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
