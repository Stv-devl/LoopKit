#!/usr/bin/env bash
# Generate a small ticket's plan from its committed spec (docs/specs/small-lane.md, S6).
# Writes docs/work/small-<name>/plan.md and nothing else, then checks its own copy.
# Usage: small-plan.sh small-<name>        generate, check, print `plan: <path>`
#        small-plan.sh --check small-<name> check the plan on disk, print `ok`
# Exit 1 on a failed check, printing only `missing:`, `reworded:`, `added:`, `no block:` lines.

set -euo pipefail

SMALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=small-lib.sh
source "$SMALL_DIR/small-lib.sh"

mode=write
if [[ "${1:-}" == "--check" ]]; then
    mode=check
    shift
fi
if [[ $# -ne 1 || "$1" != small-?* ]]; then
    echo "usage: small-plan.sh [--check] small-<name>" >&2
    exit 2
fi

slug="$1"
name="${slug#small-}"
if ! small_valid_name "$name"; then
    echo "invalid name: $name" >&2
    exit 2
fi
cd "$(git rev-parse --show-toplevel)"
spec="$(small_spec_file "$name")"
plan="docs/work/$slug/plan.md"
if [[ ! -f "$spec" ]]; then
    echo "no spec: $spec" >&2
    exit 2
fi
if [[ "$mode" == "check" && ! -f "$plan" ]]; then
    echo "no plan: $plan" >&2
    exit 2
fi

base_sha="$(small_spec_base "$spec" | awk '{ print $2 }')"
rows=""
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    status=Create
    if [[ -n "$base_sha" ]] && git cat-file -e "$base_sha:$path" 2>/dev/null; then
        status=Edit
    fi
    rows+="$path"$'\t'"$(small_layer "$path")"$'\t'"$status"$'\n'
done < <(small_spec_files "$spec")

SMALL_ROWS="$rows" SMALL_RED_GREEN="$CWK_TDD_LAYERS" SMALL_TEST_RE="$CWK_TDD_TEST_RE" SMALL_DATE="$(date +%F)" \
    python3 - "$mode" "$spec" "$plan" "$slug" <<'PY'
import os
import re
import sys
from pathlib import Path

mode, spec_path, plan_path, slug = sys.argv[1:5]
test_first_re = re.compile(os.environ["SMALL_TEST_RE"])
rows = [line.split("\t") for line in os.environ["SMALL_ROWS"].splitlines() if line]
CASE_RE = re.compile(r"^- \[ \] ")
ID_RE = re.compile(r"^- \[ \] ([A-Z][0-9]+) ")
CHAIN = ["DB", "backend", "types", "schemas", "errors", "gateway", "utils", "mapper",
         "repository", "hooks", "store", "components", "forms", "wiring"]
RED_GREEN = {"repository" if word == "services" else word for word in os.environ["SMALL_RED_GREEN"].split("|")}


def sections(text: str) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            found[current] = []
        elif current is not None:
            found[current].append(line)
    return found


def trimmed(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def blocks(lines: list[str]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    current = None
    for line in lines:
        if line.startswith("#### "):
            current = line[5:].strip()
            found[current] = []
        elif line.startswith("### ") or line.startswith("## "):
            current = None
        elif current is not None:
            found[current].append(line)
    return {path: trimmed(body) for path, body in found.items()}


def body(found: dict[str, list[str]], heading: str) -> list[str]:
    for key, value in found.items():
        if key == heading or key.startswith(heading + " "):
            return trimmed(value)
    return []


spec = sections(Path(spec_path).read_text(encoding="utf-8"))
spec_blocks = blocks(body(spec, "Test cases"))
test_files = [path for path, layer, _ in rows if layer == "test"]


def render() -> str:
    objective = next((line for line in body(spec, "Objective") if line.strip()), slug)
    first = {path: b for path, b in spec_blocks.items() if test_first_re.search(path)}
    after = {path: b for path, b in spec_blocks.items() if not test_first_re.search(path)}
    out = [f"# Plan: {objective.strip()} (entry: {spec_path} · research: inline (dispatch) · design: n/a)",
           "Pipeline: small", "Token profile: economy", "",
           "## Skips",
           "- Interface : SKIP — small lane, no new screen.",
           "- Plan-critic : SKIP — small lane, the committed spec is the validated contract.",
           "- Research fan-out : SKIP — done inline at dispatch, its traps are the Vigilance.", "",
           "## Write chain (sequential)"]
    for layer in CHAIN:
        paths = [path for path, kind, _ in rows if kind == layer]
        if not paths:
            out.append(f"- {layer}: SKIP")
            continue
        suffix = " — RED→GREEN" if layer in RED_GREEN else ""
        out.append(f"- {layer}: {', '.join(paths)}{suffix}")
    out += [f"- unmapped: {path}" for path, kind, _ in rows if kind != "test" and kind not in CHAIN]
    out += ["", "## Parallel lots (inside this track, same tree)", "none — fully sequential", "",
            "## Track isolation",
            f"- Worktree: `.claude/worktrees/{slug}` on `feat/{slug}`",
            "- Shared foundations touched: none", "",
            "## Files", "| Path | Create/Edit | Role |", "| --- | --- | --- |"]
    out += [f"| `{path}` | {status} | small ticket |" for path, _, status in rows]
    out += ["", "## Contracts", *body(spec, "Contracts"), "",
            "## Test plan (gate — validated by the user before EXECUTE)", "", "### Test-first"]
    for path, lines in first.items():
        out += ["", f"#### {path}", *lines]
    out += ["", "### Test-after"]
    for path, lines in after.items():
        out += ["", f"#### {path}", *lines]
    out += ["", "## Vigilance (carried from research)", *body(spec, "Vigilance"), "",
            "## Acceptance criteria (carried from the entry artifact)", *body(spec, "Done when"), "",
            "## Plan critic", "Plan critic: skipped (small lane)", "- surviving blockers: none", "",
            "## Gate", f"- {os.environ['SMALL_DATE']} go", "- Contract: as written", ""]
    return "\n".join(out)


def check(text: str) -> list[str]:
    plan = sections(text)
    plan_blocks: dict[str, list[str]] = {}
    test_plan = next((v for k, v in plan.items() if k.startswith("Test plan")), [])
    for kind in ("Test-first", "Test-after"):
        lines = []
        on = False
        for line in test_plan:
            if line.startswith("### "):
                on = line[4:].strip() == kind
            elif on:
                lines.append(line)
        for path, b in blocks(lines).items():
            wanted = "Test-first" if test_first_re.search(path) else "Test-after"
            if wanted == kind:
                plan_blocks[path] = b
    problems = [f"no block: {path}" for path in test_files
                if path not in spec_blocks or path not in plan_blocks]
    for path, spec_body in spec_blocks.items():
        spec_cases = [line for line in spec_body if CASE_RE.match(line)]
        plan_cases = [line for line in plan_blocks.get(path, []) if CASE_RE.match(line)]
        plan_ids = {m.group(1): line for line in plan_cases if (m := ID_RE.match(line))}
        reworded_ids = set()
        for line in spec_cases:
            if line in plan_cases:
                continue
            match = ID_RE.match(line)
            if match and match.group(1) in plan_ids:
                reworded_ids.add(match.group(1))
                problems.append(f"reworded: {line}")
            else:
                problems.append(f"missing: {line}")
        for line in plan_cases:
            match = ID_RE.match(line)
            if line not in spec_cases and not (match and match.group(1) in reworded_ids):
                problems.append(f"added: {line}")
        problems += [f"added: {line}" for line in dict.fromkeys(plan_cases)
                     if plan_cases.count(line) > spec_cases.count(line) and line in spec_cases]
    return problems


if mode == "write":
    target = Path(plan_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render(), encoding="utf-8")
problems = check(Path(plan_path).read_text(encoding="utf-8"))
if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"plan: {plan_path}" if mode == "write" else "ok")
PY
