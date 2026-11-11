#!/usr/bin/env python3
# cwk-guard-api: 1
"""The one reader of `.claude/project.json`, the project's own config for the guard hooks.

Imported by `shell_targets.py` and `kit-doctor.py`; run by `hook-guarded.sh` as
`python3 -I -B project_config.py roots <project dir>`. An absent file is an empty
config (today's behaviour). Anything malformed raises `ConfigError`: the CLI then
prints nothing on stdout and exits 3, so no caller ever widens a pass from it.
"""
import errno
import json
import os
import re
import stat
import sys
from typing import NamedTuple

SCHEMA_VERSION = 1
MAX_BYTES = 64 * 1024
KEYS = {"schema_version", "app_roots", "codegen_commands"}
SEGMENT = re.compile(r"[A-Za-z0-9._-]+")
RESERVED = {".claude", ".git", "node_modules"}


class ConfigError(Exception):
    """`.claude/project.json` exists but cannot be trusted."""


class Config(NamedTuple):
    app_roots: tuple
    codegen_commands: tuple


EMPTY = Config((), ())


def _root(value):
    if not isinstance(value, str) or not value:
        raise ConfigError(f"app root {value!r} is not a non-empty string")
    segments = value.split("/")
    for segment in segments:
        if segment in ("", ".", "..") or not SEGMENT.fullmatch(segment):
            raise ConfigError(f"app root {value!r} is not a canonical relative path")
    if segments[0] in RESERVED or value.startswith("-"):
        raise ConfigError(f"app root {value!r} names a reserved folder or starts with '-'")
    return value


def _check_real(project_dir, root):
    """A root that exists must not cross a symlink: the lexical and real guards agree."""
    joined = os.path.join(project_dir, root)
    if not os.path.lexists(joined):
        return
    expected = os.path.join(os.path.realpath(project_dir), root)
    if os.path.realpath(joined) != os.path.normpath(expected):
        raise ConfigError(f"app root {root!r} resolves through a symlink")


def _command(value):
    if not isinstance(value, list) or not value:
        raise ConfigError(f"codegen command {value!r} is not a non-empty list")
    for word in value:
        if not isinstance(word, str) or not word or "\0" in word or "\n" in word:
            raise ConfigError(f"codegen command {value!r} holds an empty or invalid word")
    return tuple(value)


def _pairs(pairs):
    keys = [key for key, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ConfigError("a JSON object repeats a key")
    return dict(pairs)


def _read(path):
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        fd = os.open(path, flags)
    except OSError as error:
        if error.errno == errno.ELOOP or os.path.islink(path):
            raise ConfigError(f"{path} is a symlink") from None
        raise
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ConfigError(f"{path} is not a regular file")
        handle = os.fdopen(fd, "rb")
    except BaseException:
        os.close(fd)
        raise
    with handle:
        data = handle.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ConfigError(f"{path} is over {MAX_BYTES} bytes")
    return data.decode("utf-8")


def load(project_dir):
    """The config of `project_dir`; `EMPTY` when there is no project or no file."""
    if not project_dir or not os.path.isabs(project_dir):
        return EMPTY
    path = os.path.join(project_dir, ".claude", "project.json")
    if not os.path.lexists(path):
        return EMPTY
    try:
        raw = json.loads(_read(path), object_pairs_hook=_pairs)
    except ConfigError:
        raise
    except (OSError, UnicodeDecodeError, ValueError, RecursionError) as error:
        raise ConfigError(f"{path} cannot be read as JSON: {error}") from None
    if not isinstance(raw, dict):
        raise ConfigError(f"{path} is not a JSON object")
    unknown = sorted(set(raw) - KEYS)
    if unknown:
        raise ConfigError(f"{path} has unknown key(s): {', '.join(unknown)}")
    missing = sorted(KEYS - set(raw))
    if missing:
        raise ConfigError(f"{path} is missing key(s): {', '.join(missing)}")
    version = raw["schema_version"]
    if type(version) is not int or version != SCHEMA_VERSION:
        raise ConfigError(f"{path} schema_version must be the integer {SCHEMA_VERSION}")
    roots, commands = raw["app_roots"], raw["codegen_commands"]
    if not isinstance(roots, list) or not isinstance(commands, list):
        raise ConfigError(f"{path} app_roots and codegen_commands must be lists")
    app_roots = tuple(_root(value) for value in roots)
    if len(set(app_roots)) != len(app_roots):
        raise ConfigError(f"{path} lists an app root twice")
    for root in app_roots:
        _check_real(project_dir, root)
    return Config(app_roots, tuple(_command(value) for value in commands))


def main(argv):
    if len(argv) != 3 or argv[1] not in ("roots", "check"):
        print("usage: project_config.py roots|check <project dir>", file=sys.stderr)
        return 2
    try:
        config = load(argv[2])
    except ConfigError as error:
        print(f"project-config: {error}", file=sys.stderr)
        return 3
    if argv[1] == "roots":
        sys.stdout.write("".join(f"{root}\n" for root in config.app_roots))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
