#!/usr/bin/env python3
# cwk-guard-api: 1
"""Route plan-critic and review findings from docs/work/<slug>/ input files."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

SEVERITIES = ("Critical", "Major", "Minor")
STATUSES = ("new", "not-fixed")
P1_CLASSES = ("a", "b", "c", "d")
KINDS = ("demonstrated", "interpretation", "vigilance")
HOOKS = ("require-red", "freeze")
LEGS = ("claude", "codex")
DIMENSIONS = ("correctness", "tests", "db", "security", "ui")
CLASSES = (
    "security",
    "correctness",
    "data-integrity",
    "architecture",
    "test-quality",
    "maintainability",
    "other",
)
SCOPED_CLASSES = ("security", "correctness", "data-integrity")
HOOK_STEMS = {
    ("require-red", "front"): "tdd-require-red",
    ("freeze", "front"): "tdd-freeze-tests",
    ("require-red", "py"): "tdd-require-red-py",
    ("freeze", "py"): "tdd-freeze-tests-py",
}
BASE_LINE = re.compile(r"^Base:\s*(\S+)", re.MULTILINE)
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
GIT_DIFF = (
    "-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--no-renames",
    "--src-prefix=a/", "--dst-prefix=b/",
)


class Refused(Exception):
    pass


def refuse(message: str) -> None:
    raise Refused(message)


@dataclass(frozen=True)
class GateDir:
    slug: str
    directory: Path

    @property
    def plan(self) -> Path:
        return self.directory / "plan.md"

    @property
    def fix_base(self) -> Path:
        return self.directory / "fix-base"

    @property
    def follow_ups(self) -> Path:
        return self.directory / "follow-ups.md"

    @property
    def exclude(self) -> str:
        return f":(exclude)docs/work/{self.slug}"


def gate_dir(argument: str) -> tuple[GateDir, Path]:
    pure = PurePosixPath(argument)
    parts = pure.parts
    if (
        pure.is_absolute()
        or len(parts) != 4
        or parts[:2] != ("docs", "work")
        or any(part in (".", "..") for part in parts)
    ):
        refuse(f"{argument} must be docs/work/<slug>/<file>, relative to the project root")
    directory = Path(*parts[:3])
    return GateDir(parts[2], directory), Path(*parts)


def write_atomic(path: Path, text: str) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def git(*args: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, env=env, check=False
    )
    if result.returncode != 0:
        refuse(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def snapshot_tree() -> str:
    with tempfile.TemporaryDirectory(prefix="kit-gate-route-") as scratch:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(scratch) / "index"))
        has_head = subprocess.run(
            ["git", "rev-parse", "--verify", "-q", "HEAD"], capture_output=True, check=False
        ).returncode == 0
        git("read-tree", *(["HEAD"] if has_head else ["--empty"]), env=env)
        git("add", "-A", env=env)
        return git("write-tree", env=env).strip()


def resolve(value: str, kind: str, where: str) -> str:
    """Resolve a user-supplied revision to a full object id, never an option."""
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "--end-of-options", f"{value}^{{{kind}}}"],
        capture_output=True, text=True, check=False,
    )
    sha = result.stdout.strip()
    if result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", sha):
        refuse(f"{where}: {value!r} is not a {kind} in this repository")
    return sha


def read_fix_base(gate: GateDir) -> str:
    if not gate.fix_base.is_file():
        refuse(f"no fix-base in {gate.directory}: run snapshot before the fix batch")
    sha = gate.fix_base.read_text(encoding="utf-8").strip()
    if not sha:
        refuse(f"{gate.fix_base} is empty")
    return resolve(sha, "tree", str(gate.fix_base))


def read_base(gate: GateDir) -> str:
    text = gate.plan.read_text(encoding="utf-8") if gate.plan.is_file() else ""
    match = BASE_LINE.search(text)
    if match is None:
        refuse(f"{gate.plan} has no Base: line; add the branch merge-base and rerun")
    return resolve(match.group(1), "commit", f"{gate.plan} Base:")


def diff_text(old: str, new: str, gate: GateDir, context: int) -> str:
    return git(*GIT_DIFF, f"-U{context}", old, new, "--", ".", gate.exclude)


def fix_hunks(diff: str) -> dict[str, set[int] | None]:
    """New-side lines per path; None means the whole file is new."""
    hunks: dict[str, set[int] | None] = {}
    created = False
    current: str | None = None
    for line in diff.splitlines():
        if line.startswith("diff --git "):
            created, current = False, None
        elif line.startswith("--- "):
            created = line == "--- /dev/null"
        elif line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else None
            if current is not None:
                hunks[current] = None if created else hunks.get(current, set())
        elif current is not None and (match := HUNK.match(line)):
            lines = hunks[current]
            if lines is not None:
                start, count = int(match.group(1)), int(match.group(2) or "1")
                lines.update(range(start, start + count))
    return hunks


def in_fix_hunk(hunks: dict[str, set[int] | None], path: str, line: int) -> bool:
    if path not in hunks:
        return False
    lines = hunks[path]
    return lines is None or line in lines


def check(condition: bool, where: str, what: str) -> None:
    if not condition:
        refuse(f"{where}: {what}")


def text_field(finding: dict[str, object], key: str, where: str) -> str:
    value = finding.get(key)
    check(isinstance(value, str) and value.strip() != "", where, f"{key} must be a non-empty string")
    assert isinstance(value, str)
    return value


def optional_text(finding: dict[str, object], key: str, where: str) -> str | None:
    check(key in finding, where, f"missing {key}")
    value = finding[key]
    check(value is None or isinstance(value, str), where, f"{key} must be a string or null")
    return value.strip() or None if isinstance(value, str) else None


def enum_field(
    finding: dict[str, object], key: str, allowed: tuple[str, ...], where: str, nullable: bool = False
) -> str | None:
    check(key in finding, where, f"missing {key}")
    value = finding[key]
    if value is None and nullable:
        return None
    check(isinstance(value, str) and value in allowed, where, f"{key} must be one of {allowed}")
    assert isinstance(value, str)
    return value


def bool_field(finding: dict[str, object], key: str, where: str) -> bool:
    value = finding.get(key)
    check(isinstance(value, bool), where, f"{key} must be true or false")
    return bool(value)


def int_field(data: dict[str, object], key: str, where: str) -> int:
    value = data.get(key)
    check(isinstance(value, int) and not isinstance(value, bool) and value >= 1, where,
          f"{key} must be an integer >= 1")
    assert isinstance(value, int)
    return value


def findings_of(data: dict[str, object]) -> list[dict[str, object]]:
    findings = data.get("findings")
    check(isinstance(findings, list), "input", "findings must be a list")
    assert isinstance(findings, list)
    for index, finding in enumerate(findings):
        check(isinstance(finding, dict), f"finding {index}", "must be an object")
    return findings


@dataclass(frozen=True)
class PlanFinding:
    id: str
    severity: str
    claim: str
    p1_class: str | None
    kind: str | None
    status: str
    in_rewritten_section: bool
    closure: str | None
    hook: str | None
    leg: str
    test_path: str | None


def parse_plan_finding(raw: dict[str, object], index: int) -> PlanFinding:
    where = f"finding {index}"
    finding_id = text_field(raw, "id", where)
    where = f"finding {finding_id}"
    p1_class = enum_field(raw, "p1_class", P1_CLASSES, where, nullable=True)
    kind = enum_field(raw, "kind", KINDS, where, nullable=True)
    if p1_class is not None:
        check(kind in ("demonstrated", "interpretation"), where,
              "a P1 finding needs kind demonstrated or interpretation")
    severity = enum_field(raw, "severity", SEVERITIES, where)
    status = enum_field(raw, "status", STATUSES, where)
    leg = enum_field(raw, "leg", LEGS, where)
    assert severity is not None and status is not None and leg is not None
    return PlanFinding(
        id=finding_id,
        severity=severity,
        claim=text_field(raw, "claim", where),
        p1_class=p1_class,
        kind=kind,
        status=status,
        in_rewritten_section=bool_field(raw, "in_rewritten_section", where),
        closure=optional_text(raw, "closure", where),
        hook=enum_field(raw, "hook", HOOKS, where, nullable=True),
        leg=leg,
        test_path=optional_text(raw, "test_path", where),
    )


def registered_stems() -> set[str]:
    settings = Path(".claude/settings.json")
    try:
        data = json.loads(settings.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    stems: set[str] = set()

    def walk(node: object) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "command" and isinstance(value, str):
                    stems.update(PurePosixPath(token).stem for token in value.split())
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)
    return stems


def hook_covered(finding: PlanFinding, stems: set[str]) -> bool:
    if finding.hook is None or finding.leg != "claude" or finding.test_path is None:
        return False
    path = finding.test_path
    if path.startswith(("src/", "shared/")):
        root = "front"
    elif path.startswith("tests/services/"):
        root = "py"
    else:
        return False
    return HOOK_STEMS[(finding.hook, root)] in stems


def plan_route(finding: PlanFinding, pass_number: int, stems: set[str]) -> str:
    if finding.severity == "Minor" or finding.p1_class is None:
        return "vigilance"
    if hook_covered(finding, stems):
        return "hook-covered"
    if finding.closure is None:
        return "needs-closure" if finding.severity == "Critical" else "vigilance"
    if (
        pass_number >= 2
        and finding.status == "new"
        and not finding.in_rewritten_section
        and finding.kind == "interpretation"
    ):
        return "vigilance"
    if pass_number == 1:
        return "rewrite"
    if finding.kind == "interpretation":
        return "arbitrate"
    return "rewrite" if pass_number == 2 else "blocked"


def route_plan(data: dict[str, object]) -> dict[str, object]:
    pass_number = int_field(data, "pass", "input")
    if pass_number > 3:
        refuse(f"pass {pass_number}: the ceiling is 3, never a pass 4")
    findings = [parse_plan_finding(raw, i) for i, raw in enumerate(findings_of(data))]
    stems = registered_stems()
    routes = [(f, plan_route(f, pass_number, stems)) for f in findings]
    taken = {route for _, route in routes}
    failing: tuple[str, ...] = ()
    if "needs-closure" in taken:
        next_step, action = "write-closure", "none"
    elif "blocked" in taken:
        next_step, action, failing = "blocked", "fail", ("blocked",)
    elif "rewrite" in taken:
        next_step, action, failing = "rewrite", "fail", ("rewrite",)
    elif "arbitrate" in taken:
        next_step, action = "arbitrate", "none"
    else:
        next_step, action = "clear", "pass"
    attempt: dict[str, str] = {"action": action}
    if failing:
        first = next(f for f, route in routes if route in failing)
        attempt["reason"] = f"{first.id}: {first.claim}"
    return {
        "mode": "plan",
        "pass": pass_number,
        "findings": [{"id": f.id, "route": route} for f, route in routes],
        "attempt": attempt,
        "next": next_step,
    }


@dataclass(frozen=True)
class ReviewFinding:
    id: str
    severity: str
    dimension: str
    klass: str
    path: str
    line: int
    problem: str
    scenario: str | None
    regression: bool
    status: str
    closure: str | None


def no_scenario(value: str | None) -> str | None:
    return None if value is not None and value.lower() == "none" else value


def parse_review_finding(raw: dict[str, object], index: int) -> ReviewFinding:
    where = f"finding {index}"
    finding_id = text_field(raw, "id", where)
    where = f"finding {finding_id}"
    severity = enum_field(raw, "severity", SEVERITIES, where)
    check(
        raw.get("dimension") in DIMENSIONS,
        where,
        f"dimension must be one of {', '.join(DIMENSIONS)}; a Stage 2.5 shadow item carries "
        "the dimension of the dependency it shadows",
    )
    dimension = enum_field(raw, "dimension", DIMENSIONS, where)
    klass = enum_field(raw, "class", CLASSES, where)
    status = enum_field(raw, "status", STATUSES, where)
    assert severity is not None and dimension is not None and klass is not None
    assert status is not None
    path = text_field(raw, "path", where)
    pure = PurePosixPath(path)
    check(not pure.is_absolute() and not any(part in (".", "..") for part in path.split("/")),
          where, "path must be relative to the project root, with no . or .. segment")
    return ReviewFinding(
        id=finding_id,
        severity=severity,
        dimension=dimension,
        klass=klass,
        path=path,
        line=int_field(raw, "line", where),
        problem=text_field(raw, "problem", where),
        scenario=no_scenario(optional_text(raw, "scenario", where)),
        regression=bool_field(raw, "regression", where),
        status=status,
        closure=optional_text(raw, "closure", where),
    )


@dataclass(frozen=True)
class Scope:
    hunks: dict[str, set[int] | None]
    feature_files: frozenset[str]


def review_scope(gate: GateDir) -> Scope:
    fix_base = read_fix_base(gate)
    base = read_base(gate)
    current = snapshot_tree()
    hunks = fix_hunks(diff_text(fix_base, current, gate, 0))
    names = git(*GIT_DIFF, "--name-only", base, current, "--", ".", gate.exclude)
    return Scope(hunks, frozenset(names.splitlines()))


def review_route(finding: ReviewFinding, round_number: int, scope: Scope | None) -> tuple[str, bool, str]:
    """Return (route, fix_introduced, follow-up label)."""
    if finding.severity == "Minor":
        return "follow-up", False, "minor"
    if finding.closure is None:
        if finding.severity == "Critical":
            return "needs-closure", False, ""
        return "follow-up", False, "minor"
    if round_number == 1 or finding.status == "not-fixed":
        return "blocking", False, ""
    assert scope is not None
    if in_fix_hunk(scope.hunks, finding.path, finding.line):
        return "blocking", True, ""
    if finding.regression:
        if finding.scenario is not None:
            return "blocking", True, ""
        return "follow-up", False, "out of scope"
    if (
        finding.klass in SCOPED_CLASSES
        and finding.scenario is not None
        and finding.path in scope.feature_files
    ):
        return "blocking", False, ""
    return "follow-up", False, "out of scope"


def append_follow_ups(gate: GateDir, lines: list[str]) -> int:
    existing = gate.follow_ups.read_text(encoding="utf-8") if gate.follow_ups.is_file() else ""
    present = set(existing.splitlines())
    added: list[str] = []
    for line in lines:
        if line not in present:
            present.add(line)
            added.append(line)
    if added:
        prefix = existing if not existing or existing.endswith("\n") else existing + "\n"
        write_atomic(gate.follow_ups, prefix + "".join(f"{line}\n" for line in added))
    return len(added)


def route_review(data: dict[str, object], gate: GateDir) -> dict[str, object]:
    round_number = int_field(data, "round", "input")
    findings = [parse_review_finding(raw, i) for i, raw in enumerate(findings_of(data))]
    scope = review_scope(gate) if round_number >= 2 else None
    routed = [(f, *review_route(f, round_number, scope)) for f in findings]
    taken = {route for _, route, _, _ in routed}
    if "needs-closure" in taken:
        next_step, action = "write-closure", "none"
    elif "blocking" in taken:
        next_step, action = "fix-batch", "fail"
    else:
        next_step, action = "clear", "pass"
    attempt: dict[str, str] = {"action": action}
    if action == "fail":
        first = next(f for f, route, _, _ in routed if route == "blocking")
        attempt["reason"] = f"{first.id}: {first.problem}"
    lines = [
        f"- [{f.dimension}] {f.path}:{f.line} — {f.problem} ({label})"
        for f, route, _, label in routed
        if route == "follow-up"
    ]
    added = append_follow_ups(gate, lines)
    return {
        "mode": "review",
        "round": round_number,
        "findings": [
            {"id": f.id, "route": route, "fix_introduced": introduced}
            for f, route, introduced, _ in routed
        ],
        "attempt": attempt,
        "next": next_step,
        "follow_ups": gate.follow_ups.as_posix(),
        "follow_ups_added": added,
    }


def command_route(argument: str) -> int:
    gate, path = gate_dir(argument)
    if path.suffix != ".json":
        refuse(f"{argument} must be a .json input file")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        refuse(f"cannot read {argument}: {error.strerror}")
    except ValueError as error:
        refuse(f"{argument} is not valid JSON: {error}")
    check(isinstance(data, dict), "input", "must be a JSON object")
    mode = data.get("mode")
    if mode == "plan":
        result = route_plan(data)
    elif mode == "review":
        result = route_review(data, gate)
    else:
        refuse("input: mode must be plan or review")
    print(json.dumps(result, ensure_ascii=False))
    return 0


def plan_argument(argument: str) -> GateDir:
    gate, path = gate_dir(argument)
    if path.name != "plan.md":
        refuse(f"{argument} must be docs/work/<slug>/plan.md")
    return gate


def command_snapshot(argument: str) -> int:
    gate = plan_argument(argument)
    sha = snapshot_tree()
    write_atomic(gate.fix_base, f"{sha}\n")
    print(sha)
    return 0


def command_diff(argument: str, which: str) -> int:
    gate = plan_argument(argument)
    old = read_fix_base(gate) if which == "fix" else read_base(gate)
    sys.stdout.write(diff_text(old, snapshot_tree(), gate, 3))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("snapshot").add_argument("plan")
    diff = commands.add_parser("diff")
    diff.add_argument("plan")
    diff.add_argument("which", choices=("fix", "feature"))
    commands.add_parser("route").add_argument("input")
    args = parser.parse_args()
    try:
        if args.command == "snapshot":
            return command_snapshot(args.plan)
        if args.command == "diff":
            return command_diff(args.plan, args.which)
        return command_route(args.input)
    except Refused as refusal:
        print(f"kit-gate-route: {refusal}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
