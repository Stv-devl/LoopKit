#!/usr/bin/env python3
"""Classify every Bash call of Claude Code sessions: prompted native, prompted hook, interpreter write.

Plan-only (docs/work/harness-prompts/plan.md, Measure), never shipped. Usage:
  measure.py --settings <settings.json> --hooks <hooks dir> --project <repo> [--sample N] <session.jsonl>...
The native column approximates Claude Code's matcher (docs/research-cache/claude-code-permissions.md
§2 and §6): split on top-level separators, wrappers and leading assignments stripped, read-only
built-ins exempt, `Bash(x *)` matching `x` or `x <anything>`. The hook column replays
prevent-destructive-commands.sh and enforce-git-workflow.sh from `--hooks` in `--project`.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import random
import re
import subprocess
import sys
from pathlib import Path

SEPARATORS = ("&&", "||", "|&", ";", "|", "&", "\n")
WRAPPERS = {"time", "nice", "nohup", "stdbuf", "command", "builtin", "noglob"}
READ_ONLY = {"ls", "cat", "echo", "pwd", "head", "tail", "grep", "find", "wc", "which", "diff", "stat",
             "du", "cd", "true", "false", "test", "[", "printf", "sort", "uniq", "cut", "tr", "basename",
             "dirname", "realpath", "readlink", "file", "date", "env", "type", "jq", "rg", "tree"}
GIT_READ_ONLY = {"status", "log", "diff", "show", "rev-parse", "ls-files", "blame", "branch", "remote",
                 "describe", "shortlog", "reflog", "ls-tree", "cat-file", "merge-base", "worktree"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+")
FILE_REDIRECT = re.compile(r"(?<![0-9&])>>?\s*(?!/dev/null|&)\S|[0-9]>>?\s*(?!/dev/null|&)[^&\s]")
INTERPRETER_WRITE = [
    re.compile(r"\bpython[0-9.]*\s+(-\s|-c\s|-\s*<<|-$)[\s\S]*(open\([^)]*['\"][wa]b?['\"]|\.write_text\(|\.write\()"),
    re.compile(r"\bnode\s+-e\b[\s\S]*writeFile"),
    re.compile(r"\bperl\s+(-\w*\s+)*-\w*i"),
    re.compile(r"\bsed\s+(-\w+\s+)*-\w*i"),
    re.compile(r"\bcat\b[^|;&\n]*(<<-?\s*['\"]?\w+['\"]?[^|;&\n]*)?>\s*(?!/dev/null)[^\s&]"),
]


def bash_calls(path: Path) -> list[tuple[str, str]]:
    calls = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") != "assistant":
            continue
        for item in event.get("message", {}).get("content", []) or []:
            if isinstance(item, dict) and item.get("type") == "tool_use" and item.get("name") == "Bash":
                command = item.get("input", {}).get("command", "")
                if isinstance(command, str) and command:
                    calls.append((command, event.get("cwd", "")))
    return calls


def split_parts(text: str) -> list[str] | None:
    """Top-level subcommands; None when quotes or substitutions do not close."""
    parts, current, quote, depth, i = [], [], "", 0, 0
    text = text.replace("\\\n", " ")
    while i < len(text):
        ch = text[i]
        if quote:
            current.append(ch)
            if ch == "\\" and quote == '"' and i + 1 < len(text):
                current.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = ""
            i += 1
            continue
        if ch in "'\"":
            quote = ch
        elif text.startswith("$(", i):
            depth += 1
        elif ch == ")" and depth:
            depth -= 1
        if depth == 0:
            separator = next((s for s in SEPARATORS if text.startswith(s, i)), None)
            if separator and not (separator == "&" and (text[i - 1:i] in "<>" or text[i + 1:i + 2] == ">")):
                parts.append("".join(current).strip())
                current = []
                i += len(separator)
                continue
        current.append(ch)
        i += 1
    if quote or depth:
        return None
    parts.append("".join(current).strip())
    return [p for p in parts if p]


def strip_wrappers(part: str) -> str:
    while True:
        match = ASSIGNMENT.match(part)
        if match:
            part = part[match.end():]
            continue
        word, _, rest = part.partition(" ")
        if word in WRAPPERS:
            part = rest.lstrip()
            continue
        if word == "timeout":
            tokens = rest.split()
            while tokens and tokens[0].startswith("-"):
                tokens.pop(0)
            part = " ".join(tokens[1:])
            continue
        return part


def read_only(part: str) -> bool:
    if FILE_REDIRECT.search(part) or "$(" in part or "`" in part:
        return False
    words = part.split()
    if not words:
        return True
    head = words[0]
    if head == "git":
        sub = next((w for w in words[1:] if not w.startswith("-")), "")
        return sub in GIT_READ_ONLY
    if head == "find":
        return not re.search(r"\s-(exec|execdir|delete|ok|fprint\w*|files0-from)\b", part)
    if head in ("sed",):
        return False
    return head in READ_ONLY


def allowed(part: str, rules: list[str]) -> bool:
    for rule in rules:
        if rule.endswith(" *") and "*" not in rule[:-2]:
            prefix = rule[:-2]
            if part == prefix or part.startswith(prefix + " "):
                return True
        elif "*" in rule:
            if fnmatch.fnmatchcase(part, rule):
                return True
        elif part == rule:
            return True
    return False


def native_prompt(command: str, rules: list[str]) -> bool:
    if len(command) > 10000:
        return True
    parts = split_parts(command)
    if parts is None:
        return True
    for part in parts:
        bare = strip_wrappers(part)
        if not (allowed(bare, rules) or read_only(bare)):
            return True
    return False


def hook_verdict(command: str, hooks: Path, project: Path) -> str:
    strongest = "pass"
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(project)})
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(project), CWK_HEALTH_LOG="0", CWK_HOOK_TIMING="0")
    for hook in ("prevent-destructive-commands.sh", "enforce-git-workflow.sh"):
        try:
            done = subprocess.run(["bash", str(hooks / hook)], input=payload, capture_output=True,
                                  text=True, env=env, cwd=project, timeout=30)
        except subprocess.TimeoutExpired:
            return "ask"
        if done.returncode == 2:
            return "deny"
        try:
            decision = json.loads(done.stdout)["hookSpecificOutput"]["permissionDecision"]
        except (ValueError, KeyError, TypeError):
            continue
        if decision == "deny":
            return "deny"
        if decision == "ask":
            strongest = "ask"
    return strongest


def interpreter_write(command: str) -> bool:
    return any(pattern.search(command) for pattern in INTERPRETER_WRITE)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--hooks", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--sample", type=int, default=0)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("sessions", type=Path, nargs="+")
    args = parser.parse_args()
    rules = [r[5:-1] for r in json.loads(args.settings.read_text())["permissions"]["allow"]
             if r.startswith("Bash(") and r.endswith(")")]
    totals = {"calls": 0, "native": 0, "hook_ask": 0, "hook_deny": 0, "interp": 0}
    rows = []
    for session in args.sessions:
        counts = dict.fromkeys(totals, 0)
        for command, _ in bash_calls(session):
            row = {"session": session.stem[:8], "command": command,
                   "native": native_prompt(command, rules),
                   "hook": hook_verdict(command, args.hooks, args.project),
                   "interp": interpreter_write(command)}
            rows.append(row)
            counts["calls"] += 1
            counts["native"] += row["native"]
            counts["hook_ask"] += row["hook"] == "ask"
            counts["hook_deny"] += row["hook"] == "deny"
            counts["interp"] += row["interp"]
        for key in totals:
            totals[key] += counts[key]
        print(json.dumps({"session": session.stem[:8], **counts}))
    per100 = {k: round(100 * v / totals["calls"], 1) for k, v in totals.items() if k != "calls"}
    print(json.dumps({"total": totals, "per_100_calls": per100}))
    if args.sample:
        for row in random.Random(args.seed).sample(rows, min(args.sample, len(rows))):
            print(json.dumps({**row, "command": row["command"][:300]}), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
