#!/usr/bin/env python3
"""Interactive Claude supervisor with automatic Codex continuation."""
from __future__ import annotations

import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time
import tty

PROJECT = Path(__file__).resolve().parent
READY = PROJECT / ".claude" / ".codex-ready"
STOP_AGENTS = PROJECT / ".claude" / ".token-stop-agents"
WARNING = PROJECT / ".claude" / ".token-warning"
QUOTA_WARNING = PROJECT / ".claude" / ".quota-warning"
ANSI_RE = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
# The number and the keyword must be ADJACENT — 15 characters of slack, not the
# 100/50 this used to allow.
#
# What the wide spans cost, measured rather than feared: this repo's own
# CLAUDE.md carries the line "continue in Codex at 97% or when Claude reports an
# usage limit". Twenty-seven characters of unrelated prose sit between the number
# and the word, and the old second alternative swallowed them — so it read the
# subscription as 97% consumed. Since 97 >= 95 also set `quota`, merely
# DISPLAYING that file in the terminal (a cat, a git diff, a grep with context)
# interrupted the session and relayed it to Codex. Proven end to end: the kit's
# constitution killed the supervisor that ships with it, and wrote a fabricated
# handoff-codex.md on the way out. docs/Claude_Workflows.md did the same at 94%.
#
# A real CLI notice keeps the two together: "usage limit: 92%", "92% of your
# weekly quota". Prose does not.
DEFAULT_QUOTA_RE = (
    r"(?i)(?:usage|quota|limit)[^%\r\n]{0,15}?(\d{1,3})\s*%"
    r"|(\d{1,3})\s*%[^\r\n]{0,15}?(?:usage|quota|limit)"
)
REMAINING_RE = re.compile(
    r"(?i)(\d{1,3})\s*%\s*(?:remaining|left|restant)"
)
LIMIT_RE = re.compile(
    rb"(usage limit reached|rate limit exceeded|you.ve hit your limit|"
    rb"limit reached[^\r\n]{0,120}resets|out of tokens)",
    re.IGNORECASE,
)


def fallback_artifact() -> str:
    if READY.exists():
        value = READY.read_text().strip()
        if value and (PROJECT / value).is_file():
            return value
    roots = [PROJECT / "docs/work", PROJECT / "docs/stories", PROJECT / "docs/specs", PROJECT / "docs/prd"]
    files = [
        path for root in roots if root.is_dir()
        for path in root.rglob("*.md")
    ]
    if not files:
        raise RuntimeError("aucun artefact de workflow trouvé pour Codex")
    handoffs = [path for path in files if path.name == "handoff-codex.md"]
    chosen = max(handoffs or files, key=lambda path: path.stat().st_mtime)
    return str(chosen.relative_to(PROJECT))



def quota_percentage(output: bytes) -> int | None:
    """Extract a quota percentage from a short CLI system warning."""
    text = ANSI_RE.sub(b"", output).decode("utf-8", errors="ignore")
    remaining = list(REMAINING_RE.finditer(text))
    if remaining:
        return 100 - int(remaining[-1].group(1))
    configured = os.environ.get("CLAUDE_WORKFLOW_QUOTA_WARNING_REGEX", DEFAULT_QUOTA_RE)
    try:
        matches = list(re.finditer(configured, text))
    except re.error:
        return None
    if not matches:
        return None
    groups = [value for value in matches[-1].groups() if value is not None]
    if not groups:
        return None
    value = int(groups[0])
    return value if 0 <= value <= 100 else None


def ensure_quota_checkpoint(percent: int) -> None:
    QUOTA_WARNING.write_text(f"{percent}\n")
    try:
        artifact = fallback_artifact()
    except RuntimeError:
        return
    source = PROJECT / artifact
    relative = source.relative_to(PROJECT)
    if source.name == "handoff-codex.md" or relative.parts[:2] != ("docs", "work"):
        return
    handoff = source.parent / "handoff-codex.md"
    if handoff.exists():
        return
    handoff.write_text(
        "# Codex handoff: Claude subscription checkpoint\n"
        "Token profile: economy\n"
        f"Entry: {artifact}\n"
        "Current phase: infer from the entry and adjacent artifacts\n\n"
        "## In progress\n"
        f"- Claude CLI reported approximately {percent}% subscription usage.\n\n"
        "## Remaining\n"
        "1. Infer the next concrete action from artifacts, story status, and git status.\n\n"
        "## Verification\n"
        "- Treat unrecorded gates as NOT RUN.\n"
    )

def run_claude(arguments: list[str]) -> tuple[int, bool, bool]:
    claude_bin = os.environ.get("CLAUDE_WORKFLOW_CLAUDE_BIN", "claude")
    READY.unlink(missing_ok=True)
    STOP_AGENTS.unlink(missing_ok=True)
    WARNING.unlink(missing_ok=True)
    QUOTA_WARNING.unlink(missing_ok=True)

    pid, master = pty.fork()
    if pid == 0:
        env = os.environ.copy()
        env["CLAUDE_PROJECT_DIR"] = str(PROJECT)
        os.execvpe(claude_bin, [claude_bin, *arguments], env)

    old_settings = None
    if sys.stdin.isatty():
        old_settings = termios.tcgetattr(sys.stdin)
        tty.setraw(sys.stdin.fileno())

    tail = b""
    threshold = False
    quota = False
    quota_percent: int | None = None
    quota_announced = False
    interrupt_at: float | None = None
    status = 1
    try:
        while True:
            readable, _, _ = select.select([master, sys.stdin], [], [], 0.2)
            if master in readable:
                try:
                    chunk = os.read(master, 8192)
                except OSError:
                    chunk = b""
                if not chunk:
                    _, wait_status = os.waitpid(pid, 0)
                    status = os.waitstatus_to_exitcode(wait_status)
                    break
                os.write(sys.stdout.fileno(), chunk)
                tail = (tail + chunk)[-32768:]
                # THE RELAY HAS ONE TRIGGER, AND IT IS THE UNAMBIGUOUS ONE.
                # Interrupting the session is destructive and cannot be undone
                # from here, so it is spelled out by the CLI ("usage limit
                # reached", "rate limit exceeded") or it does not happen.
                # A PARSED PERCENTAGE NEVER RELAYS: it is inferred from free text
                # scrolling past, and free text includes whatever Claude printed
                # - this repo's own documentation among it.
                #
                # This is also what install.sh has always promised: a usage limit
                # DETECTED IN THE OUTPUT triggers the relay. A percentage is not
                # a limit being reached, it is an estimate about one.
                if LIMIT_RE.search(tail):
                    quota = True
                detected = quota_percentage(tail)
                if detected is not None and (quota_percent is None or detected > quota_percent):
                    quota_percent = detected
                    # >= 90 arms a checkpoint: one file on disk, one line on
                    # screen. Both are cheap and both are reversible, which is
                    # why this side may keep a heuristic and the relay may not.
                    if detected >= 90:
                        ensure_quota_checkpoint(detected)
                        if not quota_announced:
                            print(
                                f"\n[workflow] Quota Claude ~{detected}% : checkpoint armé, "
                                "Claude continue. Le relais Codex n'est déclenché que par un "
                                "message explicite de limite atteinte.\n",
                                flush=True,
                            )
                            quota_announced = True
            if sys.stdin in readable:
                data = os.read(sys.stdin.fileno(), 1024)
                if data:
                    os.write(master, data)

            if READY.exists():
                threshold = True
            if (threshold or quota) and interrupt_at is None:
                interrupt_at = time.monotonic()
                os.write(master, b"\x03")
                os.write(master, b"/exit\r")
            elif interrupt_at is not None and time.monotonic() - interrupt_at > 8:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

            finished, wait_status = os.waitpid(pid, os.WNOHANG)
            if finished:
                status = os.waitstatus_to_exitcode(wait_status)
                break
    finally:
        if old_settings is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        os.close(master)
    return status, threshold, quota


def run_codex(artifact: str) -> int:
    launcher = PROJECT / "codex-handoff.sh"
    print(f"\n[workflow] Relais vers Codex depuis {artifact}\n", flush=True)
    return subprocess.call([str(launcher), artifact], cwd=PROJECT)


def main() -> int:
    status, threshold, quota = run_claude(sys.argv[1:])
    if threshold or quota:
        try:
            artifact = fallback_artifact()
        except RuntimeError as error:
            print(f"\n[workflow] {error}", file=sys.stderr)
            return status or 1
        return run_codex(artifact)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
