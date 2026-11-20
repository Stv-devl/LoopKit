#!/usr/bin/env python3
"""Hook loop-record: `<tree>/.claude/.loop-record.json` from the user's own plan-gate `go`.

PreToolUse AskUserQuestion: a pre-filled `Plan gate` is denied. PostToolUse AskUserQuestion:
a main-thread `Plan gate` answered exactly `go` writes the record (docs/specs/loop-to-pr.md).
PostToolUse Bash: the pass's exact `gh pr create` printing its PR URL deletes it. `--clear`
deletes it. A Post path never fails the tool call. Standard library only.
"""

import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from urllib.parse import quote

RECORD = os.path.join(".claude", ".loop-record.json")
GATE_HEADER = "Plan gate"
FIRST_LINE_RE = re.compile(r"^Plan go — (docs/work/([a-z0-9][a-z0-9.-]*)/plan\.md)$")
BLOCK_HEADER = "Frozen cases to amend:"
ROW_RE = re.compile(r"^(\S+) \| ([UMRB][0-9]+) \| ([0-9a-f]{64})$")
REPO_RE = r"[A-Za-z0-9._-]+/[A-Za-z0-9._-]+"
BRANCH_RE = r"[A-Za-z0-9._/][A-Za-z0-9._/-]*"
PR_FORM_RE = re.compile(
    r"^gh pr create --repo (" + REPO_RE + r") --base (" + BRANCH_RE + r") --head (" + BRANCH_RE + r")"
    r' --title "[^"$`\\]*" --body-file docs/work/[a-z0-9][a-z0-9.-]*/pr-body\.md$'
)
BARRIER_TYPES = {"pull_request", "non_fast_forward", "deletion"}
GIT_SECONDS = 5.0


def gh_budget() -> float:
    """Seconds all gh calls of one go may take together (10 by default)."""
    try:
        return max(0.0, float(os.environ.get("CWK_LOOP_RECORD_GH_BUDGET", "10")))
    except ValueError:
        return 10.0


def run(argv: list[str], cwd: str, seconds: float) -> tuple[int, str]:
    """Runs argv in its own process group, killed whole past `seconds`; (exit, stdout)."""
    if seconds <= 0:
        return 124, ""
    env = dict(os.environ, GH_PROMPT_DISABLED="1", NO_COLOR="1", GIT_TERMINAL_PROMPT="0")
    try:
        proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                start_new_session=True)
    except OSError:
        return 127, ""
    try:
        out, _ = proc.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return 124, ""
    return proc.returncode, out.decode("utf-8", "replace")


def git(tree: str, *args: str) -> tuple[int, str]:
    """One git call in `tree`, under the git time cap."""
    return run(["git", "-C", tree, *args], tree, GIT_SECONDS)


def toplevel(cwd: object) -> str | None:
    """The work tree holding `cwd`, or None."""
    if not isinstance(cwd, str) or not os.path.isabs(cwd) or not os.path.isdir(cwd):
        return None
    code, out = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], cwd, GIT_SECONDS)
    top = out.strip()
    return top if code == 0 and top else None


def deny(reason: str) -> None:
    """Prints a PreToolUse deny."""
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))


def pre_ask(raw: str) -> None:
    """Denies a pre-filled Plan gate, and an unreadable input that names it."""
    try:
        data = json.loads(raw)
        tool_input = data["tool_input"]
        questions = tool_input.get("questions") or []
        answers = tool_input.get("answers")
        gate = any(isinstance(q, dict) and q.get("header") == GATE_HEADER for q in questions)
    except Exception:
        if GATE_HEADER in raw:
            deny("BLOCKED: this AskUserQuestion input could not be read and it names the Plan gate.\n\n"
                 "The plan gate is answered by the user, never pre-filled: ask it plainly.")
        return
    if gate and answers:
        deny("BLOCKED: the plan gate is answered by the user, never pre-filled.\n\n"
             "Ask the Plan gate question without `answers`; the user's own go is what opens "
             "the loop record.")


def parse_rows(text: str) -> list[dict[str, str]] | None:
    """The `Frozen cases to amend:` block as rows, [] for `none`, None when malformed."""
    lines = text.split("\n")
    try:
        start = [line.strip() for line in lines].index(BLOCK_HEADER) + 1
    except ValueError:
        return None
    block: list[str] = []
    for line in lines[start:]:
        if not line.strip():
            break
        block.append(line.strip())
    if block == ["none"]:
        return []
    rows = []
    for line in block:
        match = ROW_RE.match(line)
        if not match:
            return None
        rows.append({"path": match.group(1), "id": match.group(2), "sha256": match.group(3)})
    return rows or None


def branch_and_base(tree: str, slug: str) -> tuple[str, str, str] | None:
    """(branch, base, base_sha) for the pass, or None when git cannot name the base."""
    branch = f"feat/{slug}"
    code, head = git(tree, "symbolic-ref", "-q", "--short", "HEAD")
    head = head.strip()
    if code != 0 or not head:
        return None
    if head != branch:
        code, sha = git(tree, "rev-parse", "--verify", "HEAD")
        return (branch, head, sha.strip()) if code == 0 and sha.strip() else None
    code, log = git(tree, "reflog", "show", "--format=%gs", f"refs/heads/{branch}", "--")
    if code != 0:
        return None
    created = [line[len("branch: Created from "):].strip()
               for line in log.splitlines() if line.startswith("branch: Created from ")]
    if not created:
        return None
    base = created[-1]
    if not base or base == "HEAD" or base.startswith("-"):
        return None
    if git(tree, "show-ref", "--verify", "--quiet", f"refs/heads/{base}")[0] != 0:
        return None
    code, sha = git(tree, "merge-base", "HEAD", f"refs/heads/{base}")
    return (branch, base, sha.strip()) if code == 0 and sha.strip() else None


def rule_types(tree: str, repo: str, branch: str, deadline: float) -> set[str] | None:
    """The rule types GitHub applies to `branch`, or None when gh cannot say."""
    code, out = run(["gh", "api", f"repos/{repo}/rules/branches/{quote(branch, safe='')}"],
                    tree, deadline - time.monotonic())
    if code != 0:
        return None
    try:
        rules = json.loads(out)
    except ValueError:
        return None
    if not isinstance(rules, list):
        return None
    return {r.get("type") for r in rules if isinstance(r, dict) and isinstance(r.get("type"), str)}


def server_facts(tree: str, base: str) -> dict[str, object]:
    """repo, default_branch, barrier and base_ok, read once within the gh budget."""
    facts: dict[str, object] = {"repo": "", "default_branch": "", "barrier": False, "base_ok": False}
    deadline = time.monotonic() + gh_budget()
    code, out = run(["gh", "repo", "view", "--json", "nameWithOwner,defaultBranchRef"],
                    tree, deadline - time.monotonic())
    if code != 0:
        return facts
    try:
        view = json.loads(out)
        repo = view["nameWithOwner"]
        default = view["defaultBranchRef"]["name"]
    except (ValueError, KeyError, TypeError):
        return facts
    if not (isinstance(repo, str) and re.fullmatch(REPO_RE, repo) and isinstance(default, str) and default):
        return facts
    facts["repo"], facts["default_branch"] = repo, default
    types = rule_types(tree, repo, default, deadline)
    facts["barrier"] = types is not None and BARRIER_TYPES <= types
    if base == default:
        facts["base_ok"] = True
    else:
        code, out = git(tree, "ls-remote", "origin", f"refs/heads/{base}")
        if code == 0 and out.strip():
            facts["base_ok"] = rule_types(tree, repo, base, deadline) == set()
    return facts


def write_record(tree: str, record: dict[str, object]) -> None:
    """Replaces the tree's record atomically."""
    target = os.path.join(tree, RECORD)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=".loop-record.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(record, handle, indent=1)
            handle.write("\n")
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def post_ask(data: dict[str, object]) -> None:
    """Writes the record from a main-thread Plan gate answered `go`."""
    if "agent_id" in data or "agent_type" in data:
        return
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        return
    questions = tool_input.get("questions")
    if not isinstance(questions, list):
        return
    gate = next((q for q in questions if isinstance(q, dict) and q.get("header") == GATE_HEADER), None)
    if gate is None or not isinstance(gate.get("question"), str):
        return
    text = gate["question"]
    first = FIRST_LINE_RE.match(text.split("\n", 1)[0])
    if not first:
        return
    response = data.get("tool_response")
    answers = response.get("answers") if isinstance(response, dict) else None
    if not isinstance(answers, dict):
        answers = tool_input.get("answers")
    if not isinstance(answers, dict) or answers.get(text) != "go":
        return
    rows = parse_rows(text)
    if rows is None:
        return
    tree = toplevel(data.get("cwd"))
    if tree is None:
        return
    plan, slug = first.group(1), first.group(2)
    if not os.path.isfile(os.path.join(tree, plan)):
        return
    where = branch_and_base(tree, slug)
    if where is None:
        return
    branch, base, base_sha = where
    record: dict[str, object] = {"version": 1, "slug": slug, "plan": plan, "branch": branch,
                                 "base": base, "base_sha": base_sha}
    record.update(server_facts(tree, base))
    record["rows"] = rows
    record["at"] = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    tool_use_id = data.get("tool_use_id")
    record["tool_use_id"] = tool_use_id if isinstance(tool_use_id, str) else ""
    write_record(tree, record)


def post_bash(data: dict[str, object]) -> None:
    """Deletes the record once the pass's own PR command printed the record repo's PR URL."""
    tool_input = data.get("tool_input")
    response = data.get("tool_response")
    if not isinstance(tool_input, dict) or not isinstance(response, dict):
        return
    command, stdout = tool_input.get("command"), response.get("stdout")
    if not isinstance(command, str) or not isinstance(stdout, str):
        return
    if not PR_FORM_RE.match(command.strip()):
        return
    tree = toplevel(data.get("cwd"))
    if tree is None:
        return
    target = os.path.join(tree, RECORD)
    try:
        with open(target, encoding="utf-8") as handle:
            repo = json.load(handle).get("repo")
    except (OSError, ValueError, AttributeError):
        return
    if not isinstance(repo, str) or not repo:
        return
    if re.search(r"https://github\.com/" + re.escape(repo) + r"/pull/[0-9]+(?![0-9A-Za-z])", stdout):
        drop_record(tree)


UNFROZEN_LINE_RE = re.compile(r"(\S+)[ \t]+#[ \t]*([UMRB][0-9]+!?(?:[ \t]*,[ \t]*[UMRB][0-9]+!?)*)[ \t]*:.*")


def comment_row_lines(tree: str, rows: object) -> None:
    """Comments out the `.tdd-unfrozen` lines whose every (path, id) is a row of the record being
    dropped: with the record gone such a line would read as a whole-file exemption."""
    if not isinstance(rows, list):
        return
    pairs = {(r.get("path"), r.get("id")) for r in rows if isinstance(r, dict)}
    listing = os.path.join(tree, ".claude", ".tdd-unfrozen")
    with open(listing, encoding="utf-8", newline="") as handle:
        lines = handle.read().splitlines(keepends=True)
    changed = False
    for index, line in enumerate(lines):
        match = UNFROZEN_LINE_RE.fullmatch(line.strip())
        if match and all((match.group(1), cid.rstrip("!")) in pairs for cid in re.split(r"[ \t]*,[ \t]*", match.group(2))):
            lines[index] = "# " + line
            changed = True
    if changed:
        handle_fd, scratch = tempfile.mkstemp(dir=os.path.dirname(listing), prefix=".tdd-unfrozen.")
        with os.fdopen(handle_fd, "w", encoding="utf-8", newline="") as out:
            out.write("".join(lines))
        os.replace(scratch, listing)


def drop_record(tree: str) -> None:
    """Deletes the record of `tree`, after commenting out the `.tdd-unfrozen` lines it backed."""
    target = os.path.join(tree, RECORD)
    try:
        with open(target, encoding="utf-8") as handle:
            rows = json.load(handle).get("rows")
        comment_row_lines(tree, rows)
    except (OSError, ValueError, AttributeError):
        pass
    try:
        os.unlink(target)
    except FileNotFoundError:
        pass


def clear() -> None:
    """Deletes the record of the tree holding the cwd, if any."""
    tree = toplevel(os.getcwd())
    if tree is None:
        return
    drop_record(tree)


def main() -> int:
    """Dispatches on --clear, then on the hook event and tool."""
    if sys.argv[1:] == ["--clear"]:
        try:
            clear()
        except Exception:
            pass
        return 0
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        data = None
    if not isinstance(data, dict):
        pre_ask(raw)
        return 0
    event, tool = data.get("hook_event_name"), data.get("tool_name")
    if event == "PreToolUse" and tool == "AskUserQuestion":
        pre_ask(raw)
        return 0
    try:
        if event == "PostToolUse" and tool == "AskUserQuestion":
            post_ask(data)
        elif event == "PostToolUse" and tool == "Bash":
            post_bash(data)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
