#!/usr/bin/env python3
"""kit-track: fork or close a loop track when the project git-ignores the kit.

    python3 .claude/scripts/kit-track.py fork <slug>
    python3 .claude/scripts/kit-track.py close <slug> [--merged]

Run from the main tree's root. Exit 0 done, 2 refused (stderr `kit-track: <reason>`);
a refusal creates and removes nothing. Guide: .claude/guides/10-worktrees.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import NoReturn

SLUG_RE = re.compile(r"[a-z0-9][a-z0-9.-]*")
STORY_RE = re.compile(r"(?P<feature>.+)-(?P<story>[0-9]+\.[0-9]+)")
SNAPSHOT = ".claude/.kit-snapshot"
OVERLAY = ".claude/overlays/guides/10-worktrees.md"
ENV_SLOT = "local-kit-env"

ROOT_FILES = ("CLAUDE.md", "AGENTS.md", "PRODUCT.md", "DESIGN.md", "workflow.py", "workflow.sh", "codex-handoff.sh")
DOC_DIRS = ("docs/stories", "docs/prd", "docs/architecture", "docs/product", "docs/work", "docs/specs",
            "docs/research-cache")
SKIP_DIRS = {"worktrees", "kit-backup", ".tdd-red", "__pycache__"}
SKIP_NAMES = {".tdd-unfrozen", ".loop-record.json", ".loop-record.lock", ".restart-ready", ".codex-ready",
              ".quota-warning", ".kit-health.jsonl", ".hook-timings.log", "settings.local.json", ".kit-snapshot"}
SKIP_PREFIXES = (".token-", ".eslint-queue")
SESSION_DOCS = {"handoff.md", "codex-last-message.txt", "pr-body.md"}
SECRET_RE = re.compile(r"^\.env(\..*)?$|\.pem$|\.key$|^\.?credentials(\.|$)")


class Refused(Exception):
    """A precondition failed; nothing was changed."""


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise Refused(message)


def git(root: Path, *args: str, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-c", "core.quotePath=false", "-C", str(root), *args],
                          capture_output=True, text=True, input=stdin, check=False)


def git_out(root: Path, *args: str) -> str:
    result = git(root, *args)
    if result.returncode != 0:
        raise Refused(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout.strip()


def main_root() -> Path:
    cwd = Path.cwd().resolve()
    top = git(cwd, "rev-parse", "--show-toplevel")
    if top.returncode != 0:
        raise Refused("not inside a git work tree")
    root = Path(top.stdout.strip()).resolve()
    if root != cwd:
        raise Refused(f"run from the project root ({root}), not {cwd}")
    common = Path(git_out(root, "rev-parse", "--path-format=absolute", "--git-common-dir")).resolve()
    if common != (root / ".git").resolve():
        raise Refused("run from the main tree, not from a worktree")
    return root


def kit_local(root: Path) -> bool:
    ignored = git(root, "check-ignore", "-q", ".claude/hooks/probe").returncode == 0
    tracked = git_out(root, "ls-tree", "-r", "--name-only", "HEAD", "--", ".claude/hooks")
    return ignored and not tracked


def check_slug(slug: str) -> None:
    if not SLUG_RE.fullmatch(slug) or ".." in slug:
        raise Refused(f"invalid slug {slug!r}: lowercase letters, digits, '.' and '-', starting with a letter or digit")


def unsafe_name(rel: str) -> bool:
    name = rel.rsplit("/", 1)[-1]
    return bool(SECRET_RE.search(name)) or name.endswith(".pyc")


def skipped(rel: str) -> bool:
    parts = rel.split("/")
    name = parts[-1]
    if unsafe_name(rel):
        return True
    if parts[0] == ".claude":
        if any(part in SKIP_DIRS for part in parts[1:-1]):
            return True
        return name in SKIP_NAMES or name.startswith(SKIP_PREFIXES)
    if parts[:2] == ["docs", "work"]:
        return name in SESSION_DOCS
    return False


def walk(root: Path, top: str) -> Iterable[str]:
    start = root / top
    if start.is_symlink():
        raise Refused(f"symlink in the kit: {top}")
    if start.is_file():
        yield top
        return
    if not start.is_dir():
        return
    for current, dirs, files in os.walk(start):
        here = Path(current)
        for name in sorted(dirs + files):
            if (here / name).is_symlink():
                raise Refused(f"symlink in the kit: {(here / name).relative_to(root).as_posix()}")
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            yield (here / name).relative_to(root).as_posix()


def candidates(root: Path) -> list[str]:
    tops = [".claude", *ROOT_FILES, *DOC_DIRS]
    docs = root / "docs"
    if docs.is_dir():
        tops += sorted(f"docs/{p.name}" for p in docs.iterdir() if p.name.startswith("design-system"))
    found: list[str] = []
    for top in tops:
        found += [rel for rel in walk(root, top) if not skipped(rel)]
    return found


def ignored_only(root: Path, paths: list[str]) -> list[str]:
    if not paths:
        return []
    result = git(root, "check-ignore", "--stdin", "-z", stdin="\0".join(paths) + "\0")
    if result.returncode not in (0, 1):
        raise Refused(f"git check-ignore: {result.stderr.strip()}")
    ignored = {p for p in result.stdout.split("\0") if p}
    return [p for p in paths if p in ignored]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst, follow_symlinks=False)
    shutil.copymode(src, dst, follow_symlinks=False)


def env_slot(root: Path) -> str:
    overlay = root / OVERLAY
    if not overlay.is_file():
        return f"{ENV_SLOT}: none declared ({OVERLAY} absent)"
    lines = overlay.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index(f"## {ENV_SLOT}") + 1
    except ValueError:
        return f"{ENV_SLOT}: none declared (no `## {ENV_SLOT}` in {OVERLAY})"
    body: list[str] = []
    for line in lines[start:]:
        if line.startswith("## "):
            break
        body.append(line)
    text = "\n".join(body).strip("\n")
    if not text.strip() or "FILL:" in text:
        return f"{ENV_SLOT}: none declared (still empty or FILL in {OVERLAY})"
    return f"{ENV_SLOT} (from {OVERLAY}):\n{text}"


def fork(slug: str) -> None:
    check_slug(slug)
    root = main_root()
    if not kit_local(root):
        raise Refused("not kit-local: .claude/ is versioned here, fork with git worktree add "
                      "(.claude/guides/10-worktrees.md)")
    base = git(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    if base.returncode != 0:
        raise Refused("HEAD is detached: check out the base branch first")
    base_name = base.stdout.strip()
    dirty = git_out(root, "status", "--porcelain", "--untracked-files=normal")
    if dirty:
        raise Refused(f"the main tree is not clean: {dirty.splitlines()[0]}")
    rel_tree = f".claude/worktrees/{slug}"
    tree = root / rel_tree
    if os.path.lexists(tree):
        raise Refused(f"{rel_tree} already exists")
    if git(root, "rev-parse", "--quiet", "--verify", f"refs/heads/feat/{slug}").returncode == 0:
        raise Refused(f"branch feat/{slug} already exists")
    files = ignored_only(root, candidates(root))
    base_sha = git_out(root, "rev-parse", "HEAD")
    added = git(root, "worktree", "add", rel_tree, "-b", f"feat/{slug}", base_name)
    if added.returncode != 0:
        raise Refused(f"git worktree add: {added.stderr.strip()}")
    hashes: dict[str, str] = {}
    for rel in files:
        copy(root / rel, tree / rel)
        hashes[rel] = sha256(root / rel)
    snapshot = {"slug": slug, "base": base_name, "base_sha": base_sha, "files": hashes}
    (tree / SNAPSHOT).write_text(json.dumps(snapshot, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"forked {rel_tree} on feat/{slug} from {base_name} ({len(files)} kit files copied, git-ignored there)")
    print("next, by hand:")
    print(f"  1. copy your env file(s) (.env*) into {rel_tree}/ yourself: the kit never copies them")
    print(f"  2. install the project's dependencies inside {rel_tree}/")
    print(f"  3. start the track's own session: cd {rel_tree} && ./workflow.sh \"/loop:orchestrate <entry>\"")
    print("     (never EnterWorktree: the session must run the worktree's own kit)")
    print(env_slot(root))


def registered(root: Path, tree: Path) -> bool:
    listing = git_out(root, "worktree", "list", "--porcelain")
    return any(Path(line[len("worktree "):]).resolve() == tree.resolve()
               for line in listing.splitlines() if line.startswith("worktree "))


def owned_roots(slug: str) -> list[str]:
    roots = [f"docs/work/{slug}"]
    story = STORY_RE.fullmatch(slug)
    if story:
        roots.append(f"docs/stories/{story.group('feature')}/{story.group('story')}.md")
    return roots


def hash_or_none(path: Path) -> str | None:
    return sha256(path) if path.is_file() and not path.is_symlink() else None


def symlink_in(root: Path, rel: str) -> str | None:
    """The first prefix of `rel` below `root` that is a symlink, or None."""
    parts = rel.split("/")
    for end in range(1, len(parts) + 1):
        prefix = "/".join(parts[:end])
        if (root / prefix).is_symlink():
            return prefix
    return None


class Closing:
    """The copy-back and report plan of one `close`, computed before anything is written."""

    def __init__(self, root: Path, tree: Path, slug: str, manifest: dict[str, str]) -> None:
        self.root, self.tree, self.slug, self.manifest = root, tree, slug, manifest
        self.copies: list[tuple[str, str]] = []
        self.reports: list[str] = []

    def place(self, rel: str, track: str) -> None:
        main = hash_or_none(self.root / rel)
        if main == track:
            return
        if (main is None and not os.path.lexists(self.root / rel)) or main == self.manifest.get(rel):
            self.copies.append((rel, rel))
            self.reports.append(f"copied {rel}")
            return
        side = f"{rel}.from-{self.slug}"
        self.copies.append((rel, side))
        self.reports.append(f"conflict {rel} → {side}")

    def owned(self, rel: str) -> None:
        track = sha256(self.tree / rel)
        if self.manifest.get(rel) != track:
            self.place(rel, track)

    def research(self, rel: str) -> None:
        track = sha256(self.tree / rel)
        known = self.manifest.get(rel)
        if known is None:
            self.place(rel, track)
        elif known != track:
            side = f"{rel}.from-{self.slug}"
            self.copies.append((rel, side))
            self.reports.append(f"research-cache modified {rel} → {side}")

    def snapshot(self, rel: str) -> None:
        if self.manifest.get(rel) != sha256(self.tree / rel):
            self.reports.append(f"snapshot change ignored {rel}")

    def drift(self, track_files: list[str]) -> None:
        kit = [rel for rel in self.manifest if rel.startswith(".claude/") or rel in ROOT_FILES]
        for rel in sorted(set(kit) | {f for f in track_files if f.startswith(".claude/") or f in ROOT_FILES}):
            known = self.manifest.get(rel)
            if hash_or_none(self.tree / rel) != known:
                self.reports.append(f"kit drift track-changed {rel}")
            if known is not None and hash_or_none(self.root / rel) != known:
                self.reports.append(f"kit drift main-changed {rel}")


def close(slug: str, merged: bool) -> None:
    check_slug(slug)
    root = main_root()
    rel_tree = f".claude/worktrees/{slug}"
    tree = root / rel_tree
    if not tree.is_dir() or not registered(root, tree):
        raise Refused(f"{rel_tree} is not a registered worktree")
    snap = tree / SNAPSHOT
    if not snap.is_file():
        raise Refused(f"{rel_tree} has no {SNAPSHOT}: it was not forked by kit-track")
    manifest: dict[str, str] = json.loads(snap.read_text(encoding="utf-8")).get("files", {})
    branch = f"feat/{slug}"
    is_merged = git(root, "merge-base", "--is-ancestor", branch, "HEAD").returncode == 0
    if not is_merged and not merged:
        raise Refused(f"{branch} is not merged into the main tree's HEAD; pass --merged once its PR reads MERGED")
    dirty = git_out(tree, "status", "--porcelain", "--untracked-files=normal")
    if dirty:
        raise Refused(f"{rel_tree} has uncommitted changes: {dirty.splitlines()[0]}")
    track_files = ignored_only(tree, [rel for rel in candidates(tree) if rel != SNAPSHOT])
    owned_files = ignored_only(tree, [rel for top in owned_roots(slug) for rel in walk(tree, top)
                                      if not unsafe_name(rel)])
    plan = Closing(root, tree, slug, manifest)
    owned_set = set(owned_files)
    for rel in owned_files:
        plan.owned(rel)
    for rel in track_files:
        if rel in owned_set or rel.startswith(".claude/") or rel in ROOT_FILES:
            continue
        if rel.startswith("docs/research-cache/"):
            plan.research(rel)
        else:
            plan.snapshot(rel)
    plan.drift(track_files)
    targets = [dst for _, dst in plan.copies]
    for dst in targets:
        link = symlink_in(root, dst)
        if link:
            raise Refused(f"copy-back target goes through a symlink in the main tree: {link}; nothing written")
    tracked = git_out(root, "ls-files", "--", *targets) if targets else ""
    if tracked:
        raise Refused(f"copy-back target tracked in the main tree: {tracked.splitlines()[0]}; it travels with the "
                      "merge, resolve it by hand")
    for src, dst in plan.copies:
        try:
            copy(tree / src, root / dst)
        except OSError as error:
            raise Refused(f"copy-back of {src} to {dst} failed ({error}); nothing removed") from error
        if sha256(root / dst) != sha256(tree / src):
            raise Refused(f"copy-back of {src} to {dst} did not verify; nothing removed")
    for line in plan.reports:
        print(line)
    removed = git(root, "worktree", "remove", rel_tree)
    if removed.returncode != 0:
        raise Refused(f"git worktree remove: {removed.stderr.strip()} (copies landed; rerun close once it is clean)")
    print(f"closed {rel_tree}")
    print(f"next: /loop:ship step 5, main-tree handoff → phase: shipped, then git branch -d {branch}")


def build_parser() -> Parser:
    parser = Parser(prog="kit-track", description="fork or close a kit-local loop track")
    commands = parser.add_subparsers(dest="command", required=True, parser_class=Parser)
    forking = commands.add_parser("fork", help="create the worktree and copy the kit into it")
    forking.add_argument("slug")
    closing = commands.add_parser("close", help="copy the track's docs back, report drift, remove the worktree")
    closing.add_argument("slug")
    closing.add_argument("--merged", action="store_true", help="the branch's PR reads MERGED (squash merge)")
    return parser


def run(argv: list[str]) -> None:
    args = build_parser().parse_args(argv)
    if args.command == "fork":
        fork(args.slug)
    else:
        close(args.slug, args.merged)


def main(argv: list[str] | None = None) -> int:
    try:
        run(sys.argv[1:] if argv is None else argv)
    except Refused as refusal:
        print(f"kit-track: {refusal}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
