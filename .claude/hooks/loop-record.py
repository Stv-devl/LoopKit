#!/usr/bin/env python3
"""Hook loop-record: `<tree>/.claude/.loop-record.json` from the user's own answers.

PreToolUse AskUserQuestion: a pre-filled `Plan gate` or `Contract gate` is denied.
PostToolUse AskUserQuestion: a main-thread `Plan gate` answered exactly `go` writes the record
(docs/specs/loop-to-pr.md); a main-thread `Contract gate` showing `Validation: auto`, answered
exactly `as written`, writes it in auto mode (docs/specs/auto-mode.md). SubagentStop of the
`arbiter` agent: its verdict block is ledgered in an auto record. PostToolUse Bash: the pass's
exact `gh pr create` printing its PR URL deletes it. `--clear` deletes it, `--mode` prints the
mode. A Post path never fails the tool call. Standard library only.
"""

import fcntl
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Iterator
from urllib.parse import quote

RECORD = os.path.join(".claude", ".loop-record.json")
LOCK = os.path.join(".claude", ".loop-record.lock")
GATE_HEADER = "Plan gate"
CONTRACT_HEADER = "Contract gate"
FIRST_LINE_RE = re.compile(r"^Plan go — (docs/work/([a-z0-9][a-z0-9.-]*)/plan\.md)$")
CONTRACT_LINE_RE = re.compile(r"^Contract go — (docs/work/([a-z0-9][a-z0-9.-]*)/research\.md)$")
VALIDATION_AUTO = "Validation: auto"
ARBITER = "arbiter"
VERDICT_HEAD = "ARBITER VERDICT"
FENCE_RE = re.compile(r"```[^\n]*\n(.*?)```", re.S)
CASE_RE = re.compile(r"^[UMRB][0-9]+$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
KEPT_ON_PLAN_GO = ("mode", "contract_go", "verdicts", "guarded")
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


def run(argv: list[str], cwd: str, seconds: float, extra_env: dict[str, str] | None = None) -> tuple[int, str]:
    """Runs argv in its own process group, killed whole past `seconds`; (exit, stdout)."""
    if seconds <= 0:
        return 124, ""
    env = dict(os.environ, GH_PROMPT_DISABLED="1", NO_COLOR="1", GIT_TERMINAL_PROMPT="0", **(extra_env or {}))
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
    """Denies a pre-filled Plan gate or Contract gate, and an unreadable input naming one."""
    headers = (GATE_HEADER, CONTRACT_HEADER)
    try:
        data = json.loads(raw)
        tool_input = data["tool_input"]
        questions = tool_input.get("questions") or []
        answers = tool_input.get("answers")
        gate = any(isinstance(q, dict) and q.get("header") in headers for q in questions)
    except Exception:
        if any(h in raw for h in headers):
            deny("BLOCKED: this AskUserQuestion input could not be read and it names a loop gate.\n\n"
                 "The plan gate and the contract gate are answered by the user, never pre-filled: "
                 "ask it plainly.")
        return
    if gate and answers:
        deny("BLOCKED: the plan gate and the contract gate are answered by the user, never pre-filled.\n\n"
             "Ask the gate question without `answers`; the user's own answer is what opens "
             "the loop record.")


def read_record(tree: str) -> dict[str, object] | None:
    """The tree's record as a dict, or None (absent, a symlink, unreadable, not an object)."""
    target = os.path.join(tree, RECORD)
    if os.path.islink(target) or not os.path.isfile(target):
        return None
    try:
        with open(target, encoding="utf-8") as handle:
            record = json.load(handle)
    except (OSError, ValueError):
        return None
    return record if isinstance(record, dict) else None


@contextmanager
def locked(tree: str) -> Iterator[None]:
    """Holds the tree's record lock: every read-modify-write of the record runs inside it."""
    path = os.path.join(tree, LOCK)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def auto_mode(tree: str, record: dict[str, object] | None) -> bool:
    """True when `record` puts `tree` in auto mode (the rule of hook-guarded.sh cwk_auto_mode)."""
    if not record or record.get("version") != 1 or record.get("mode") != "auto":
        return False
    if not isinstance(record.get("contract_go"), dict):
        return False
    branch, base, sha = record.get("branch"), record.get("base"), record.get("base_sha")
    if not (isinstance(branch, str) and isinstance(base, str) and isinstance(sha, str)):
        return False
    code, head = git(tree, "symbolic-ref", "-q", "--short", "HEAD")
    head = head.strip()
    return code == 0 and bool(head) and bool(branch) and head == branch


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


def now() -> str:
    """The current UTC time, ISO 8601 to the second, `Z`-suffixed."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def gate_answer(data: dict[str, object], header: str) -> tuple[str, str] | None:
    """(question text, the user's answer) of the main-thread question with `header`, or None."""
    if "agent_id" in data or "agent_type" in data:
        return None
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    questions = tool_input.get("questions")
    if not isinstance(questions, list):
        return None
    gate = next((q for q in questions if isinstance(q, dict) and q.get("header") == header), None)
    if gate is None or not isinstance(gate.get("question"), str):
        return None
    text = gate["question"]
    response = data.get("tool_response")
    answers = response.get("answers") if isinstance(response, dict) else None
    if not isinstance(answers, dict):
        answers = tool_input.get("answers")
    if not isinstance(answers, dict) or not isinstance(answers.get(text), str):
        return None
    return text, answers[text]


def base_record(data: dict[str, object], tree: str, slug: str, plan: str) -> dict[str, object] | None:
    """The fields every record carries (branch, base, server facts), or None when git cannot name them."""
    where = branch_and_base(tree, slug)
    if where is None:
        return None
    branch, base, base_sha = where
    record: dict[str, object] = {"version": 1, "slug": slug, "plan": plan, "branch": branch,
                                 "base": base, "base_sha": base_sha}
    record.update(server_facts(tree, base))
    return record


def post_plan_go(data: dict[str, object]) -> None:
    """Writes the record from a main-thread Plan gate answered `go`; an auto record of the same
    pass keeps its mode, contract go and ledgers."""
    asked = gate_answer(data, GATE_HEADER)
    if asked is None or asked[1] != "go":
        return
    text = asked[0]
    first = FIRST_LINE_RE.match(text.split("\n", 1)[0])
    if not first:
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
    record = base_record(data, tree, slug, plan)
    if record is None:
        return
    record["rows"] = rows
    record["at"] = now()
    tool_use_id = data.get("tool_use_id")
    record["tool_use_id"] = tool_use_id if isinstance(tool_use_id, str) else ""
    with locked(tree):
        old = read_record(tree)
        if old and old.get("slug") == slug and old.get("branch") == record["branch"]:
            for key in KEPT_ON_PLAN_GO:
                if key in old:
                    record[key] = old[key]
        write_record(tree, record)


def post_contract_go(data: dict[str, object]) -> None:
    """Writes an auto record from a main-thread Contract gate showing `Validation: auto`,
    answered exactly `as written`."""
    asked = gate_answer(data, CONTRACT_HEADER)
    if asked is None or asked[1] != "as written":
        return
    lines = asked[0].split("\n")
    first = CONTRACT_LINE_RE.match(lines[0])
    if not first or len(lines) < 2 or lines[1] != VALIDATION_AUTO:
        return
    tree = toplevel(data.get("cwd"))
    if tree is None:
        return
    research, slug = first.group(1), first.group(2)
    if not os.path.isfile(os.path.join(tree, research)):
        return
    record = base_record(data, tree, slug, f"docs/work/{slug}/plan.md")
    if record is None:
        return
    tool_use_id = data.get("tool_use_id")
    tool_use_id = tool_use_id if isinstance(tool_use_id, str) else ""
    record.update({"rows": [], "mode": "auto", "contract_go": {"at": now(), "tool_use_id": tool_use_id},
                   "verdicts": [], "guarded": [], "at": now(), "tool_use_id": tool_use_id})
    with locked(tree):
        write_record(tree, record)


def post_ask(data: dict[str, object]) -> None:
    """Writes the record from a main-thread Plan gate or Contract gate."""
    post_plan_go(data)
    post_contract_go(data)


def verdict_blocks(text: object) -> list[dict[str, str]]:
    """The fenced `ARBITER VERDICT` blocks of `text`, each as its `key: value` lines."""
    if not isinstance(text, str):
        return []
    blocks = []
    for body in FENCE_RE.findall(text):
        lines = [line.strip() for line in body.strip().split("\n")]
        if not lines or lines[0] != VERDICT_HEAD:
            continue
        fields: dict[str, str] = {}
        for line in lines[1:]:
            key, sep, value = line.partition(":")
            if sep:
                fields[key.strip()] = value.strip()
        blocks.append(fields)
    return blocks


def transcript_texts(path: object) -> list[str]:
    """From a subagent transcript: its last assistant text, then its last SubagentHandback message."""
    if not isinstance(path, str) or not os.path.isabs(path) or not os.path.isfile(path):
        return []
    last_text, handback = "", ""
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                    content = entry["message"]["content"]
                except (ValueError, KeyError, TypeError):
                    continue
                if entry.get("type") != "assistant" or not isinstance(content, list):
                    continue
                for part in content:
                    if not isinstance(part, dict):
                        continue
                    if part.get("type") == "text" and isinstance(part.get("text"), str):
                        last_text = part["text"]
                    elif part.get("type") == "tool_use" and part.get("name") == "SubagentHandback":
                        message = (part.get("input") or {}).get("message")
                        if isinstance(message, str):
                            handback = message
    except OSError:
        return []
    return [last_text, handback]


def ledger_entry(fields: dict[str, str], agent_id: str) -> dict[str, str] | None:
    """A verdict ledger entry from one block, or None when the block is malformed."""
    kind, verdict = fields.get("kind"), fields.get("verdict", "")
    if kind == "frozen-case":
        path, case, sha = fields.get("path", ""), fields.get("case", ""), fields.get("sha256", "")
        if not path or " " in path or not CASE_RE.match(case) or not SHA_RE.match(sha):
            return None
        if os.path.isabs(path) or path != os.path.normpath(path) or "//" in path or path.startswith("../"):
            return None
        if verdict not in ("unfreeze", "refuse"):
            return None
        return {"kind": kind, "path": path, "id": case, "sha256": sha, "verdict": verdict,
                "agent_id": agent_id, "at": now()}
    if kind == "decision" and fields.get("question") and verdict:
        return {"kind": kind, "question": fields["question"], "verdict": verdict,
                "agent_id": agent_id, "at": now()}
    return None


def file_sha(path: str) -> str:
    """sha256 of the file at `path`, or `absent`."""
    import hashlib
    try:
        with open(path, "rb") as handle:
            return hashlib.sha256(handle.read()).hexdigest()
    except FileNotFoundError:
        return "absent"
    except OSError:
        return "unknown"


def text_sha(text: str) -> str:
    """sha256 of `text` encoded UTF-8."""
    import hashlib
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def guarded_op(data: dict[str, object]) -> bool:
    """Appends one guarded-write row to the auto record of the tree holding `abs`, for
    protect-files.sh and the shell guard (never a model-run CLI). True once written."""
    rel, absolute, tool = data.get("path"), data.get("abs"), data.get("tool")
    if not (isinstance(rel, str) and rel and isinstance(absolute, str) and os.path.isabs(absolute)
            and isinstance(tool, str) and tool):
        return False
    probe = os.path.dirname(absolute)
    while probe != "/" and not os.path.isdir(probe):
        probe = os.path.dirname(probe)
    tree = toplevel(probe)
    if tree is None:
        return False
    before = file_sha(absolute)
    after = "unknown"
    tool_input = data.get("tool_input")
    if tool == "Write" and isinstance(tool_input, dict) and isinstance(tool_input.get("content"), str):
        after = text_sha(tool_input["content"])
    elif tool == "Edit" and isinstance(tool_input, dict):
        old, new = tool_input.get("old_string"), tool_input.get("new_string")
        try:
            with open(absolute, encoding="utf-8", newline="") as handle:
                current = handle.read()
        except OSError:
            current = None
        if isinstance(old, str) and old and isinstance(new, str) and current is not None and old in current:
            count = -1 if tool_input.get("replace_all") is True else 1
            after = text_sha(current.replace(old, new, count))
    with locked(tree):
        record = read_record(tree)
        if record is None or not auto_mode(tree, record):
            return False
        guarded = record.get("guarded")
        guarded = guarded if isinstance(guarded, list) else []
        record["guarded"] = guarded + [{"path": rel, "before": before, "after": after, "tool": tool, "at": now()}]
        write_record(tree, record)
    return True


def subagent_stop(data: dict[str, object]) -> None:
    """Ledgers the arbiter's verdict block in an auto record: the first verdict per case is final."""
    if data.get("agent_type") != ARBITER or data.get("stop_hook_active") is True:
        return
    blocks = verdict_blocks(data.get("last_assistant_message"))
    if not blocks:
        for text in transcript_texts(data.get("agent_transcript_path")):
            blocks = verdict_blocks(text)
            if blocks:
                break
    if not blocks:
        return
    agent_id = data.get("agent_id")
    entry = ledger_entry(blocks[-1], agent_id if isinstance(agent_id, str) else "")
    if entry is None:
        return
    tree = toplevel(data.get("cwd"))
    if tree is None:
        return
    with locked(tree):
        record = read_record(tree)
        if record is None or not auto_mode(tree, record):
            return
        verdicts = record.get("verdicts")
        verdicts = verdicts if isinstance(verdicts, list) else []
        if entry["kind"] == "frozen-case" and any(
                isinstance(v, dict) and v.get("kind") == "frozen-case"
                and v.get("path") == entry["path"] and v.get("id") == entry["id"] for v in verdicts):
            return
        record["verdicts"] = verdicts + [entry]
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


def comment_row_lines(tree: str, rows: object, verdicts: object = None) -> None:
    """Comments out the `.tdd-unfrozen` lines whose every (path, id) is a row or a frozen-case
    verdict of the record being dropped: with the record gone such a line would read as a
    whole-file exemption."""
    pairs = {(r.get("path"), r.get("id")) for r in rows if isinstance(r, dict)} if isinstance(rows, list) else set()
    if isinstance(verdicts, list):
        pairs |= {(v.get("path"), v.get("id")) for v in verdicts
                  if isinstance(v, dict) and v.get("kind") == "frozen-case"}
    if not pairs:
        return
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
        with locked(tree):
            drop_locked(tree, target)
    except OSError:
        try:
            os.unlink(target)
        except FileNotFoundError:
            pass


def drop_locked(tree: str, target: str) -> None:
    """The body of `drop_record`, run with the record lock held."""
    try:
        with open(target, encoding="utf-8") as handle:
            record = json.load(handle)
        comment_row_lines(tree, record.get("rows"), record.get("verdicts"))
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


TEST_PATH_RE = re.compile(r"\.(?:test|spec)\.[cm]?[jt]sx?$|(?:^|/)test_[^/]*\.py$|_test\.py$")
TS_CASE_RE = re.compile(r"""(?<![A-Za-z0-9_$.])(?:it|test)(?:\.[A-Za-z]+)*[ \t]*\([ \t]*['"`]([A-Za-z][0-9]+)\b""")
PY_CASE_RE = re.compile(r"def[ \t]+test_([A-Za-z])([0-9]+)(?:_|[ \t]*\()")
FETCH_SECONDS = 8
GUARDED_HEADER = "### Guarded files touched"


def case_ids(text: str) -> set[str]:
    """The case ids (`U2`, `B1`) named by the `it(`/`test(` titles and `def test_` names of `text`."""
    ids = {m.group(1).upper() for m in TS_CASE_RE.finditer(text)}
    return ids | {(m.group(1) + m.group(2)).upper() for m in PY_CASE_RE.finditer(text)}


def auto_classes(tree: str, paths: list[str]) -> dict[str, str]:
    """{path: denied | ledgered | none}, from hook-guarded.sh cwk_auto_class in one shell."""
    if not paths:
        return {}
    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hook-guarded.sh")
    script = 'source "$1" || exit 1; shift; for p in "$@"; do printf "%s\\t%s\\n" "$(cwk_auto_class "$p")" "$p"; done'
    code, out = run(["bash", "-c", script, "_", lib, *paths], tree, GIT_SECONDS, {"CLAUDE_PROJECT_DIR": tree})
    if code != 0:
        raise RuntimeError("cwk_auto_class could not run")
    found = {}
    for line in out.splitlines():
        cls, _, path = line.partition("\t")
        found[path] = cls
    return found


def short_sha(value: object) -> str:
    """A ledger digest as the block shows it: 12 hex, or `absent` / `unknown` as written."""
    text = value if isinstance(value, str) else "unknown"
    return text[:12] if re.fullmatch(r"[0-9a-f]{64}", text) else text


def guarded_block(tree: str, fetch: bool) -> str | None:
    """The PR body's `Guarded files touched` block of an auto pass (docs/specs/auto-mode.md, step 5):
    "" outside auto mode, None when it cannot be computed (fetch or diff failed)."""
    record = read_record(tree)
    if not auto_mode(tree, record):
        return ""
    base = str(record["base"])
    if fetch and run(["git", "-C", tree, "fetch", "-q", "--no-tags", "origin", base], tree, FETCH_SECONDS)[0] != 0:
        return None
    ref = "origin/" + base
    code, merge_base = git(tree, "merge-base", ref, "HEAD")
    code2, diff = git(tree, "diff", "--no-renames", "--name-status", ref + "...HEAD")
    if code != 0 or code2 != 0:
        return None
    merge_base = merge_base.strip()
    entries = [line.split("\t", 1) for line in diff.splitlines() if "\t" in line]
    classes = auto_classes(tree, [path for _, path in entries])
    allowed: dict[str, set[str]] = {}
    for item in list(record.get("rows") or []) + list(record.get("verdicts") or []):
        if isinstance(item, dict) and item.get("kind", "frozen-case") == "frozen-case" \
                and item.get("verdict", "unfreeze") == "unfreeze":
            allowed.setdefault(str(item.get("path")), set()).add(str(item.get("id")))
    failures, listed = [], []
    for status, path in entries:
        is_test = bool(TEST_PATH_RE.search(path)) and status in ("M", "D")
        if is_test or classes.get(path) in ("denied", "ledgered"):
            listed.append("- `%s %s` (diff)" % (status, path))
        if not is_test:
            continue
        code, patch = git(tree, "diff", "--no-renames", "-U0", ref + "...HEAD", "--", path)
        code2, before = git(tree, "show", "%s:%s" % (merge_base, path))
        if code != 0 or code2 != 0:
            return None
        changed = "\n".join(line[1:] for line in patch.splitlines()
                            if line[:1] in "+-" and not line.startswith(("+++", "---")))
        for cid in sorted((case_ids(changed) & case_ids(before)) - allowed.get(path, set())):
            failures.append("- GUARD FAILURE: %s %s changed with no ledger row" % (path, cid))
    ledger = ["- `%s` before `%s` after `%s` (ledger, %s)" % (g.get("path"), short_sha(g.get("before")),
                                                              short_sha(g.get("after")), g.get("tool"))
              for g in record.get("guarded") or [] if isinstance(g, dict)]
    body = "\n".join(failures + listed + ledger or ["- none"]) + "\n"
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    return "%s\n<!-- guarded-files sha256:%s -->\n%s" % (GUARDED_HEADER, digest, body)


def main() -> int:
    """Dispatches on --clear, then on the hook event and tool."""
    if sys.argv[1:] == ["--clear"]:
        try:
            clear()
        except Exception:
            pass
        return 0
    if sys.argv[1:] == ["--mode"]:
        mode = "moi"
        try:
            tree = toplevel(os.getcwd())
            if tree is not None and auto_mode(tree, read_record(tree)):
                mode = "auto"
        except Exception:
            mode = "moi"
        print(mode)
        return 0
    if sys.argv[1:] in (["--guarded-block"], ["--guarded-block", "--no-fetch"]):
        try:
            tree = toplevel(os.getcwd())
            block = guarded_block(tree, len(sys.argv) == 2) if tree is not None else ""
        except Exception:
            block = None
        if block is None:
            return 1
        sys.stdout.write(block)
        return 0
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except ValueError:
        data = None
    if not isinstance(data, dict):
        pre_ask(raw)
        return 0
    if data.get("loop_record_op") == "guarded":
        try:
            return 0 if guarded_op(data) else 1
        except Exception:
            return 1
    event, tool = data.get("hook_event_name"), data.get("tool_name")
    if event == "PreToolUse" and tool == "AskUserQuestion":
        pre_ask(raw)
        return 0
    try:
        if event == "PostToolUse" and tool == "AskUserQuestion":
            post_ask(data)
        elif event == "PostToolUse" and tool == "Bash":
            post_bash(data)
        elif event == "SubagentStop":
            subagent_stop(data)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
