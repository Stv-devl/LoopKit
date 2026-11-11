#!/usr/bin/env python3
"""PR screenshots on the orphan `pr-assets` branch.

Subcommands: ui, path, plan, section, commit, drop (docs/specs/pr-screenshots.md).
Exit 0 ok, 2 refused with a one-line English reason on stderr and nothing on
stdout. Only `commit` and `drop` write, and only `refs/heads/pr-assets`, through
a temporary index and a compare-and-swap update-ref. Nothing is pushed or fetched.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import PurePosixPath

REF = "refs/heads/pr-assets"
REMOTE_REF = "refs/remotes/origin/pr-assets"
MAX_STEPS_PER_FLOW = 3
MAX_IMAGES = 32
WIDTHS = {"desktop": 400, "mobile": 180}

BRANCH_RE = re.compile(r"[A-Za-z0-9._/-]+")
SHA_RE = re.compile(r"[0-9a-f]{7,40}")
NAME_RE = re.compile(r"[a-z0-9-]+")
STEP_RE = re.compile(r"[0-9]{2}-[a-z0-9-]+")
REPO_RE = re.compile(r"[A-Za-z0-9._-]+/[A-Za-z0-9._-]+")
IMAGE_RE = re.compile(
    r"(?P<step>[0-9]{2}-[a-z0-9-]+?)-(?P<theme>light|dark)-(?P<viewport>desktop|mobile)"
    r"(?P<before>-before)?\.png"
)
URL_PATH_RE = re.compile(r"blob/pr-assets/([^\s\"'<>()?#]+)")
UI_SUFFIXES = (".tsx", ".jsx", ".css", ".scss")


class Refused(Exception):
    """A refusal: exit 2 with this reason, nothing written."""


@dataclass(frozen=True)
class Shot:
    """One captured image and where it is published."""

    local: str
    flow: str
    step: str
    theme: str
    viewport: str
    before: bool
    path: str
    url: str


def is_ui_path(path: str) -> bool:
    """True when a changed path can change what a screen looks like."""
    p = path.strip().removeprefix("./")
    name = PurePosixPath(p).name
    if p.startswith("src/") and (p.endswith(UI_SUFFIXES) or ".module." in name):
        return True
    if p.startswith("public/") or p == "index.html":
        return True
    return "/" not in p and name.startswith("tailwind.config.")


def check_branch(branch: str) -> str:
    if (
        not BRANCH_RE.fullmatch(branch)
        or ".." in branch
        or branch.startswith("/")
        or branch.endswith("/")
        or "//" in branch
    ):
        raise Refused(f"invalid branch name: {branch!r}")
    return branch


def short_sha(sha: str) -> str:
    if not SHA_RE.fullmatch(sha):
        raise Refused(f"invalid sha: {sha!r}")
    return sha[:7]


def image_path(branch: str, sha: str, flow: str, step: str, theme: str, viewport: str, before: bool) -> str:
    """The published path of one image on pr-assets."""
    if not NAME_RE.fullmatch(flow):
        raise Refused(f"invalid flow: {flow!r}")
    if not STEP_RE.fullmatch(step):
        raise Refused(f"invalid step: {step!r}")
    suffix = "-before" if before else ""
    return f"{check_branch(branch)}/{short_sha(sha)}/{flow}-{step}-{theme}-{viewport}{suffix}.png"


def collect(directory: str, branch: str, sha: str, repo: str) -> list[Shot]:
    """Every image of a run dir, validated, capped, in publishing order."""
    check_branch(branch)
    short_sha(sha)
    if not REPO_RE.fullmatch(repo):
        raise Refused(f"invalid repo: {repo!r}")
    if not os.path.isdir(directory):
        return []
    shots: list[Shot] = []
    for root, dirs, files in os.walk(directory):
        for name in dirs + files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, directory).replace(os.sep, "/")
            info = os.lstat(full)
            if stat.S_ISLNK(info.st_mode) or (
                not stat.S_ISDIR(info.st_mode) and (not stat.S_ISREG(info.st_mode) or info.st_nlink > 1)
            ):
                raise Refused(f"not a plain image file (symlink, hard link or special): {rel}")
        for name in files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, directory).replace(os.sep, "/")
            parts = rel.split("/")
            match = IMAGE_RE.fullmatch(parts[-1]) if len(parts) == 2 else None
            if match is None or not NAME_RE.fullmatch(parts[0]):
                raise Refused(f"unexpected file in the screenshots dir: {rel}")
            flow = parts[0]
            before = match.group("before") is not None
            if before and (match.group("theme"), match.group("viewport")) != ("light", "desktop"):
                raise Refused(f"a before image is light desktop only: {rel}")
            path = image_path(branch, sha, flow, match.group("step"), match.group("theme"),
                              match.group("viewport"), before)
            shots.append(Shot(full, flow, match.group("step"), match.group("theme"),
                              match.group("viewport"), before, path,
                              f"https://github.com/{repo}/blob/pr-assets/{path}?raw=true"))
    if len(shots) > MAX_IMAGES:
        raise Refused(f"{len(shots)} images, the cap is {MAX_IMAGES}")
    for flow in {s.flow for s in shots}:
        steps = {s.step for s in shots if s.flow == flow}
        if len(steps) > MAX_STEPS_PER_FLOW:
            raise Refused(f"flow {flow} has {len(steps)} steps, the cap is {MAX_STEPS_PER_FLOW}")
    order = {"light": 0, "dark": 1, "desktop": 0, "mobile": 1}
    return sorted(shots, key=lambda s: (s.flow, s.step, s.before, order[s.viewport], order[s.theme]))


def cell(shot: Shot | None) -> str:
    if shot is None:
        return "—"
    return f'<a href="{shot.url}"><img src="{shot.url}" width="{WIDTHS[shot.viewport]}"></a>'


def render_section(shots: list[Shot]) -> str:
    """The PR body's Screenshots block: one block per flow, one table per step."""
    blocks: list[str] = []
    for flow in sorted({s.flow for s in shots}):
        lines = [f"**Screenshots** — {flow}"]
        for step in sorted({s.step for s in shots if s.flow == flow}):
            mine = [s for s in shots if s.flow == flow and s.step == step]

            def find(theme: str, viewport: str, before: bool) -> Shot | None:
                return next((s for s in mine if (s.theme, s.viewport, s.before) == (theme, viewport, before)), None)

            if len(lines) > 1:
                lines.append("")
            number, _, slug = step.partition("-")
            lines.append(f"| {number} {slug.replace('-', ' ')} | light | dark |")
            lines.append("| --- | --- | --- |")
            for viewport in ("desktop", "mobile"):
                light, dark = find("light", viewport, False), find("dark", viewport, False)
                if light or dark:
                    lines.append(f"| {viewport} | {cell(light)} | {cell(dark)} |")
            before = find("light", "desktop", True)
            if before:
                lines.append(f"| before (desktop) | {cell(before)} | — |")
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks)


def git(*args: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(["git", *args], capture_output=True, text=True, env=env)
    if result.returncode != 0:
        reason = (result.stderr.strip().splitlines() or ["no output"])[-1]
        raise Refused(f"git {args[0]} failed: {reason}")
    return result.stdout.strip()


def resolve(ref: str) -> str | None:
    result = subprocess.run(["git", "rev-parse", "-q", "--verify", f"{ref}^{{commit}}"],
                            capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def is_ancestor(older: str, newer: str) -> bool:
    return subprocess.run(["git", "merge-base", "--is-ancestor", older, newer],
                          capture_output=True).returncode == 0


def pick_parent() -> tuple[str | None, str | None]:
    """(parent, current local tip): the newer of local and origin pr-assets."""
    git("rev-parse", "--git-dir")
    local, remote = resolve(REF), resolve(REMOTE_REF)
    if local is None or remote is None or local == remote:
        return (local or remote), local
    if is_ancestor(local, remote):
        return remote, local
    if is_ancestor(remote, local):
        return local, local
    raise Refused("local pr-assets and origin/pr-assets diverged: fetch first")


def write_commit(parent: str | None, old: str | None, message: str, fill) -> str:
    """Build a commit on a temporary index, then compare-and-swap the ref."""
    with tempfile.TemporaryDirectory() as scratch:
        env = {**os.environ, "GIT_INDEX_FILE": os.path.join(scratch, "index")}
        if parent:
            git("read-tree", parent, env=env)
        else:
            git("read-tree", "--empty", env=env)
        fill(env)
        tree = git("write-tree", env=env)
    parent_args = ["-p", parent] if parent else []
    commit = git("commit-tree", tree, *parent_args, "-m", message)
    git("update-ref", REF, commit, old or "")
    return commit


def tree_paths(commit: str | None) -> list[str]:
    if commit is None:
        return []
    listing = git("ls-tree", "-r", "--name-only", commit)
    return listing.splitlines() if listing else []


def cmd_commit(args: argparse.Namespace) -> None:
    shots = collect(args.dir, args.branch, args.sha, args.repo)
    if not shots:
        raise Refused(f"no image in {args.dir}")
    parent, old = pick_parent()
    existing = set(tree_paths(parent))
    taken = [s.path for s in shots if s.path in existing]
    if taken:
        raise Refused(f"already on pr-assets, never rewritten: {taken[0]}")

    def fill(env: dict[str, str]) -> None:
        for shot in shots:
            blob = git("hash-object", "-w", "--", shot.local)
            git("update-index", "--add", "--cacheinfo", f"100644,{blob},{shot.path}", env=env)

    message = f"chore(pr-assets): add {args.branch} {short_sha(args.sha)}"
    print(write_commit(parent, old, message, fill))


def published_folders(body: str, branch: str) -> set[str]:
    """The `<branch>/<sha7>` folders a PR body's image URLs point at."""
    folders = set()
    for path in URL_PATH_RE.findall(body):
        if not path.startswith(branch + "/"):
            continue
        match = re.fullmatch(r"([0-9a-f]{7})/[^/]+", path[len(branch) + 1:])
        if match:
            folders.add(f"{branch}/{match.group(1)}")
    return folders


def cmd_drop(args: argparse.Namespace) -> None:
    branch = check_branch(args.branch)
    folders = published_folders(sys.stdin.read(), branch)
    parent, old = pick_parent()
    doomed = [p for p in tree_paths(parent) if p.rpartition("/")[0] in folders]
    if not doomed:
        print("nothing to clean")
        return

    def fill(env: dict[str, str]) -> None:
        git("update-index", "--force-remove", "--", *doomed, env=env)

    print(write_commit(parent, old, f"chore(pr-assets): drop {branch}", fill))


class Parser(argparse.ArgumentParser):
    """argparse whose usage errors are refusals (exit 2, one stderr line)."""

    def error(self, message: str) -> None:  # type: ignore[override]
        raise Refused(message)


def build_parser() -> argparse.ArgumentParser:
    parser = Parser(prog="kit-pr-assets")
    sub = parser.add_subparsers(dest="cmd", required=True, parser_class=Parser)
    sub.add_parser("ui")
    path = sub.add_parser("path")
    path.add_argument("--branch", required=True)
    path.add_argument("--sha", required=True)
    path.add_argument("--flow", required=True)
    path.add_argument("--step", required=True)
    path.add_argument("--theme", required=True, choices=["light", "dark"])
    path.add_argument("--viewport", required=True, choices=["desktop", "mobile"])
    path.add_argument("--before", action="store_true")
    for name in ("plan", "section", "commit"):
        run = sub.add_parser(name)
        run.add_argument("--dir", required=True)
        run.add_argument("--branch", required=True)
        run.add_argument("--sha", required=True)
        run.add_argument("--repo", required=True)
    drop = sub.add_parser("drop")
    drop.add_argument("--branch", required=True)
    return parser


def run(argv: list[str]) -> None:
    args = build_parser().parse_args(argv)
    if args.cmd == "ui":
        paths = [line for line in sys.stdin.read().splitlines() if line.strip()]
        print("ui" if any(is_ui_path(p) for p in paths) else "none")
    elif args.cmd == "path":
        print(image_path(args.branch, args.sha, args.flow, args.step, args.theme, args.viewport, args.before))
    elif args.cmd == "plan":
        shots = collect(args.dir, args.branch, args.sha, args.repo)
        print(json.dumps([{"local": s.local, "path": s.path, "url": s.url} for s in shots], indent=2))
    elif args.cmd == "section":
        text = render_section(collect(args.dir, args.branch, args.sha, args.repo))
        if text:
            print(text)
    elif args.cmd == "commit":
        cmd_commit(args)
    else:
        cmd_drop(args)


def main() -> int:
    try:
        run(sys.argv[1:])
    except Refused as refusal:
        print(f"kit-pr-assets: {refusal}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
