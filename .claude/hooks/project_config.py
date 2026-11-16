#!/usr/bin/env python3
# cwk-guard-api: 4
"""The one reader of `.claude/project.json`, every value a project adapts.

Imported by `shell_targets.py`, `kit-doctor.py` and the Python hooks; run by the shell
hooks as `python3 -I -B project_config.py shell <project dir>`, which prints NUL-terminated
`key=value` records between `#status=<n>` and `#end=<count>`. `load()` keeps the schema-1
contract (an absent file or a relative dir gives the defaults with no app root);
`load_strict()` and `shell` never do: absent is status 4, no absolute dir status 5, anything
malformed status 3, so no caller ever widens a pass from a file it cannot trust.
"""
import ast
import errno
import json
import os
import re
import stat
import sys
import tempfile
from typing import NamedTuple

SCHEMA_VERSION = 2
MAX_BYTES = 64 * 1024
KEYS_V1 = ("schema_version", "app_roots", "codegen_commands")
SEGMENT = re.compile(r"[A-Za-z0-9._-]+")
NAME = re.compile(r"[A-Za-z0-9._][A-Za-z0-9._-]*")
SECRET_WORDS = frozenset({"local", "production", "development", "prod", "dev", "staging", "test"})
BRANCH = re.compile(r"[A-Za-z0-9._/*?-]+")
WORD = re.compile(r"[a-z0-9]+")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ICON = re.compile(r"[A-Za-z][A-Za-z0-9]*")
DOTTED = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*")
PREFIX = re.compile(r"[A-Za-z0-9._/-]+")
RESERVED = {".claude", ".git", "node_modules"}
ERE_SPECIAL = set("\\.[]()*+?{}|^$")

DEFAULTS = {
    "schema_version": SCHEMA_VERSION,
    "app_roots": [],
    "codegen_commands": [],
    "data_client": {
        "module": "lib/client",
        "own_path": "lib/client.ts",
        "composition_roots": ["main.tsx", "routes/__root.tsx"],
        "shared_dirs": ["components/", "hooks/", "lib/", "types/", "stores/", "config/"],
    },
    "protected_dirs": ["src", "shared", ".claude", "public", "node_modules", "dist"],
    "protected_branches": ["main", "master"],
    "test_command": ["pnpm", "test:run"],
    "formatter": ["prettier", "--write"],
    "linter": "eslint",
    "env_template_suffixes": ["example", "sample", "template"],
    "forbidden_icons": ["Star", "Stars", "Sparkle", "Sparkles", "Rocket",
                        "RocketLaunch", "Zap", "Bolt", "LightningBolt"],
    "tdd_layers": ["repository", "services", "mapper", "utils"],
    "fastapi": {
        "module_root": "app",
        "tests_root": "tests",
        "test_first_dirs": ["services"],
        "session_names": ["db", "session", "async_session"],
        "external_clients": {},
    },
}
KEYS = tuple(DEFAULTS)


class ConfigError(Exception):
    """`.claude/project.json` cannot be trusted. `status`: 3 invalid, 4 absent, 5 no project."""

    def __init__(self, message, status=3):
        super().__init__(message)
        self.status = status

    @property
    def absent(self):
        return self.status == 4


class Config(NamedTuple):
    app_roots: tuple
    codegen_commands: tuple
    data_client: dict = DEFAULTS["data_client"]
    protected_dirs: tuple = tuple(DEFAULTS["protected_dirs"])
    protected_branches: tuple = tuple(DEFAULTS["protected_branches"])
    test_command: tuple = tuple(DEFAULTS["test_command"])
    formatter: tuple = tuple(DEFAULTS["formatter"])
    linter: str = DEFAULTS["linter"]
    env_template_suffixes: tuple = tuple(DEFAULTS["env_template_suffixes"])
    forbidden_icons: tuple = tuple(DEFAULTS["forbidden_icons"])
    tdd_layers: tuple = tuple(DEFAULTS["tdd_layers"])
    fastapi: dict = DEFAULTS["fastapi"]


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


def _keys(where, raw, expected):
    if not isinstance(raw, dict):
        raise ConfigError(f"{where} is not a JSON object")
    unknown = sorted(set(raw) - set(expected))
    if unknown:
        raise ConfigError(f"{where} has unknown key(s): {', '.join(unknown)}")
    missing = [key for key in expected if key not in raw]
    if missing:
        raise ConfigError(f"{where} is missing key(s): {', '.join(missing)}")


def _list(key, value, pattern, allow_empty=True):
    if not isinstance(value, list) or (not value and not allow_empty):
        raise ConfigError(f"{key} must be a{'' if allow_empty else ' non-empty'} list")
    for item in value:
        if not isinstance(item, str) or not pattern.fullmatch(item):
            raise ConfigError(f"{key}: {item!r} is not allowed")
    return tuple(value)


def _relpath(key, value, trailing_slash=False):
    if not isinstance(value, str) or not value:
        raise ConfigError(f"{key}: {value!r} is not a non-empty string")
    body = value[:-1] if trailing_slash and value.endswith("/") else value
    if trailing_slash and body == value:
        raise ConfigError(f"{key}: {value!r} must end with '/'")
    for segment in body.split("/"):
        if segment in ("", ".", "..") or not SEGMENT.fullmatch(segment):
            raise ConfigError(f"{key}: {value!r} is not a canonical relative path")
    return value


def _segment(key, value):
    if not isinstance(value, str) or value in (".", "..") or not SEGMENT.fullmatch(value):
        raise ConfigError(f"{key}: {value!r} is not one path segment")
    return value


def _argv(key, value, allow_empty):
    if not isinstance(value, list) or (not value and not allow_empty):
        raise ConfigError(f"{key} must be a{'' if allow_empty else ' non-empty'} list of words")
    for word in value:
        if not isinstance(word, str) or not word or "\0" in word or "\n" in word:
            raise ConfigError(f"{key} holds an empty or invalid word: {word!r}")
    if value and (value[0] in (".", "..") or not NAME.fullmatch(value[0])):
        raise ConfigError(f"{key}: {value[0]!r} is not a bare program name")
    return tuple(value)


def _data_client(raw):
    _keys("data_client", raw, DEFAULTS["data_client"])
    module = _relpath("data_client.module", raw["module"])
    own_path = _relpath("data_client.own_path", raw["own_path"])
    if own_path != module + ".ts":
        raise ConfigError(f"data_client.own_path {own_path!r} must be data_client.module + '.ts'")
    if not isinstance(raw["composition_roots"], list) or not isinstance(raw["shared_dirs"], list):
        raise ConfigError("data_client.composition_roots and shared_dirs must be lists")
    return {
        "module": module,
        "own_path": own_path,
        "composition_roots": tuple(_relpath("data_client.composition_roots", v) for v in raw["composition_roots"]),
        "shared_dirs": tuple(_relpath("data_client.shared_dirs", v, trailing_slash=True) for v in raw["shared_dirs"]),
    }


def _fastapi(raw):
    _keys("fastapi", raw, DEFAULTS["fastapi"])
    clients = raw["external_clients"]
    if not isinstance(clients, dict):
        raise ConfigError("fastapi.external_clients must be an object")
    for module, prefixes in clients.items():
        if not DOTTED.fullmatch(module):
            raise ConfigError(f"fastapi.external_clients: {module!r} is not a dotted module name")
        for prefix in _list("fastapi.external_clients", prefixes, PREFIX):
            if prefix.startswith("/") or ".." in prefix.split("/"):
                raise ConfigError(f"fastapi.external_clients: {prefix!r} is not a relative prefix")
    return {
        "module_root": _segment("fastapi.module_root", raw["module_root"]),
        "tests_root": _segment("fastapi.tests_root", raw["tests_root"]),
        "test_first_dirs": tuple(_segment("fastapi.test_first_dirs", v)
                                 for v in _list("fastapi.test_first_dirs", raw["test_first_dirs"], SEGMENT)),
        "session_names": _list("fastapi.session_names", raw["session_names"], IDENT),
        "external_clients": {module: tuple(prefixes) for module, prefixes in clients.items()},
    }


def _suffixes(value):
    suffixes = _list("env_template_suffixes", value, WORD)
    for suffix in suffixes:
        if suffix in SECRET_WORDS:
            raise ConfigError(f"env_template_suffixes: {suffix!r} names a file that holds secrets")
    return suffixes


def _branches(value):
    branches = _list("protected_branches", value, BRANCH)
    for branch in branches:
        if branch.startswith("-") or ".." in branch:
            raise ConfigError(f"protected_branches: {branch!r} is not allowed")
    return branches


def _parse(project_dir, path, raw):
    version = raw.get("schema_version") if isinstance(raw, dict) else None
    if type(version) is not int or version not in (1, SCHEMA_VERSION):
        if isinstance(raw, dict) and "schema_version" in raw:
            raise ConfigError(f"{path} schema_version must be the integer 1 or {SCHEMA_VERSION}")
    _keys(path, raw, KEYS_V1 if version == 1 else KEYS)
    if type(raw["schema_version"]) is not int or raw["schema_version"] not in (1, SCHEMA_VERSION):
        raise ConfigError(f"{path} schema_version must be the integer 1 or {SCHEMA_VERSION}")
    roots, commands = raw["app_roots"], raw["codegen_commands"]
    if not isinstance(roots, list) or not isinstance(commands, list):
        raise ConfigError(f"{path} app_roots and codegen_commands must be lists")
    app_roots = tuple(_root(value) for value in roots)
    if len(set(app_roots)) != len(app_roots):
        raise ConfigError(f"{path} lists an app root twice")
    for root in app_roots:
        _check_real(project_dir, root)
    codegen = tuple(_command(value) for value in commands)
    if raw["schema_version"] == 1:
        return Config(app_roots, codegen)
    linter = raw["linter"]
    if not isinstance(linter, str) or (linter and (linter in (".", "..") or not NAME.fullmatch(linter))):
        raise ConfigError(f"linter: {linter!r} is not a bare program name")
    dirs = _list("protected_dirs", raw["protected_dirs"], SEGMENT)
    for item in dirs:
        _segment("protected_dirs", item)
    return Config(
        app_roots,
        codegen,
        _data_client(raw["data_client"]),
        dirs,
        _branches(raw["protected_branches"]),
        _argv("test_command", raw["test_command"], allow_empty=False),
        _argv("formatter", raw["formatter"], allow_empty=True),
        linter,
        _suffixes(raw["env_template_suffixes"]),
        _list("forbidden_icons", raw["forbidden_icons"], ICON),
        _list("tdd_layers", raw["tdd_layers"], WORD, allow_empty=False),
        _fastapi(raw["fastapi"]),
    )


def load_strict(project_dir):
    """The config of `project_dir`; `ConfigError` with status 5, 4 or 3 when it cannot be had."""
    if not project_dir or not os.path.isabs(project_dir):
        raise ConfigError("no absolute project dir (CLAUDE_PROJECT_DIR)", status=5)
    path = os.path.join(project_dir, ".claude", "project.json")
    if not os.path.lexists(path):
        raise ConfigError(f"{path} is missing", status=4)
    try:
        raw = json.loads(_read(path), object_pairs_hook=_pairs)
    except ConfigError:
        raise
    except (OSError, UnicodeDecodeError, ValueError, RecursionError) as error:
        raise ConfigError(f"{path} cannot be read as JSON: {error}") from None
    return _parse(project_dir, path, raw)


def load(project_dir):
    """The config of `project_dir`; `EMPTY` (the defaults, no app root) when there is no
    project or no file. Malformed raises `ConfigError`."""
    try:
        return load_strict(project_dir)
    except ConfigError as error:
        if error.status in (4, 5):
            return EMPTY
        raise


def _ere(text):
    return "".join("\\" + char if char in ERE_SPECIAL else char for char in text)


def records(config):
    """The shell records of `config`, without the `#status`/`#end` frame."""
    fastapi = config.fastapi
    dirs = "|".join(_ere(d) for d in fastapi["test_first_dirs"])
    module_root, tests_root = _ere(fastapi["module_root"]), _ere(fastapi["tests_root"])
    py_target = (f"(^|[/[:space:]\"'])({module_root}/({dirs})(/[A-Za-z0-9_./-]*)?\\.py|"
                 f"{tests_root}/(({dirs})/[A-Za-z0-9_./-]*)?test_[A-Za-z0-9_]*\\.py)")
    out = [f"app_roots={root}" for root in config.app_roots]
    out.append("protected_dirs_ere=" + "|".join(_ere(d) for d in config.protected_dirs))
    out.append("protected_dirs_text=" + ", ".join(d + "/" for d in config.protected_dirs))
    out += [f"protected_branches={branch}" for branch in config.protected_branches]
    out += [f"test_command={word}" for word in config.test_command]
    out += [f"formatter={word}" for word in config.formatter]
    out.append(f"linter={config.linter}")
    out.append("env_suffix_ere=" + "|".join(_ere(s) for s in config.env_template_suffixes))
    out.append("icons_ere=" + "|".join(config.forbidden_icons))
    out.append("tdd_layers_ere=" + "|".join(config.tdd_layers))
    out.append(f"py_target_ere={py_target}")
    out.append(f"module_root={fastapi['module_root']}")
    out.append(f"tests_root={fastapi['tests_root']}")
    return out


def framed(lines, end):
    """`#status=0`, the records, `#end=<count>`, each followed by `end`."""
    return "".join(line + end for line in ["#status=0", *lines, f"#end={len(lines)}"])


def serialise(raw):
    """The one serialisation of a project.json document."""
    return json.dumps(raw, indent=2) + "\n"


def document(config):
    """The schema-2 document of `config`, keys in schema order."""
    return {
        "schema_version": SCHEMA_VERSION,
        "app_roots": list(config.app_roots),
        "codegen_commands": [list(command) for command in config.codegen_commands],
        "data_client": {key: list(value) if isinstance(value, tuple) else value
                        for key, value in config.data_client.items()},
        "protected_dirs": list(config.protected_dirs),
        "protected_branches": list(config.protected_branches),
        "test_command": list(config.test_command),
        "formatter": list(config.formatter),
        "linter": config.linter,
        "env_template_suffixes": list(config.env_template_suffixes),
        "forbidden_icons": list(config.forbidden_icons),
        "tdd_layers": list(config.tdd_layers),
        "fastapi": {key: ({k: list(v) for k, v in value.items()} if isinstance(value, dict)
                          else list(value) if isinstance(value, tuple) else value)
                    for key, value in config.fastapi.items()},
    }


def write(project_dir, raw):
    """Replaces `<project_dir>/.claude/project.json` atomically with `serialise(raw)`."""
    path = os.path.join(project_dir, ".claude", "project.json")
    descriptor, temp = tempfile.mkstemp(prefix="project.json.", suffix=".tmp", dir=os.path.dirname(path))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(serialise(raw))
        os.chmod(temp, 0o644)
        os.replace(temp, path)
    except BaseException:
        if os.path.lexists(temp):
            os.unlink(temp)
        raise


ADDON_DIRS = {"supabase": ("supabase",), "fastapi": ("app", "alembic")}
SUPABASE_CLIENT = {"module": "lib/supabase", "own_path": "lib/supabase.ts"}


def wire(project_dir, addon):
    """Adds an addon's values to the project's file; idempotent. Returns the changed key names."""
    config = load_strict(project_dir)
    raw = document(config)
    changed = []
    dirs = raw["protected_dirs"]
    missing = [d for d in ADDON_DIRS[addon] if d not in dirs]
    if missing:
        at = dirs.index("shared") + 1 if "shared" in dirs else len(dirs)
        raw["protected_dirs"] = dirs[:at] + missing + dirs[at:]
        changed.append("protected_dirs")
    default = DEFAULTS["data_client"]
    client = raw["data_client"]
    if addon == "supabase" and (client["module"], client["own_path"]) == (default["module"], default["own_path"]):
        client.update(SUPABASE_CLIENT)
        changed.append("data_client")
    if changed or config.app_roots != tuple(raw["app_roots"]) or _version(project_dir) != SCHEMA_VERSION:
        write(project_dir, raw)
    return changed


class _Unreadable(Exception):
    """A hook defines the value, in a form migrate will not guess at."""


def _hook_text(project_dir, name):
    path = os.path.join(project_dir, ".claude", "hooks", name)
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError):
        return None


def _shell_string(text, name):
    """The double-quoted literal of `NAME="..."` at the start of a line; None when the hook
    holds no such literal (a value-free hook, or one reading a variable)."""
    if text is None or not re.search(rf'^{name}="(?!\$)', text, re.M):
        return None
    match = re.search(rf'^{name}="([^"$`]+)"$', text, re.M)
    if match is None:
        raise _Unreadable(name)
    return match.group(1)


def _glob_of_ere(part, whole):
    out = ""
    i = 0
    while i < len(part):
        pair = part[i:i + 2]
        if pair == "\\.":
            out += "."
        elif pair == ".*":
            out += "*"
        elif pair == ".+":
            out += "?*"
        elif part[i] in "\\.^$()[]{}?+*":
            raise _Unreadable(whole)
        else:
            out += part[i]
            i += 1
            continue
        i += 2
    return out


def _alternation(value, glob_tail=False):
    """`a|b\\.c` → ["a", "b.c"]. With glob_tail (branches), an unescaped `.*` anywhere becomes
    `*` and `.+` becomes `?*`; any other bare `.` or ERE metacharacter raises _Unreadable, so
    a pattern is never narrowed into a glob that matches less than it did."""
    items = []
    for part in value.split("|"):
        if glob_tail:
            part = _glob_of_ere(part, value)
        else:
            part = part.replace("\\.", ".")
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._/*?-]*|\.[A-Za-z0-9._-]+", part):
            raise _Unreadable(value)
        items.append(part)
    return items


def _py_values(text, names):
    """`{name: value}` for each top-level `name = <literal>` (typed or not) in Python `text`."""
    if text is None:
        return {}
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError):
        return {}
    found = {}
    for node in tree.body:
        targets = node.targets if isinstance(node, ast.Assign) else [node.target] if isinstance(node, ast.AnnAssign) else []
        for target in targets:
            if isinstance(target, ast.Name) and target.id in names and node.value is not None:
                try:
                    found[target.id] = ast.literal_eval(node.value)
                except (ValueError, SyntaxError):
                    pass
    return found


def _migrated(project_dir, notes):
    """The values the target's active hooks define, as `{key: value}` of a v2 document."""
    out = {}

    def shell(key, hook, name, convert):
        try:
            value = _shell_string(_hook_text(project_dir, hook), name)
            if value is not None:
                out[key] = convert(value)
        except _Unreadable:
            notes.append(f"migrate: {key} unreadable in {hook}, default kept")

    def protected(key, hook, name, glob_tail, check):
        try:
            value = _shell_string(_hook_text(project_dir, hook), name)
        except _Unreadable:
            notes.append(f"migrate: {key} unreadable in {hook}, default kept")
            return
        if value is None:
            return
        kept, dropped = [], []
        for part in value.split("|"):
            try:
                item = _alternation(part, glob_tail)[0]
                check(item)
            except (_Unreadable, ConfigError):
                dropped.append(part)
                continue
            if item not in kept:
                kept.append(item)
        notes.extend(f"migrate: {key} unreadable in {hook}, default kept ({part!r} dropped)" for part in dropped)
        if dropped:
            kept += [item for item in DEFAULTS[key] if item not in kept]
        if kept:
            out[key] = kept

    protected("protected_dirs", "prevent-destructive-commands.sh", "PROTECTED_DIRS", False,
              lambda item: (_list("protected_dirs", [item], SEGMENT), _segment("protected_dirs", item)))
    protected("protected_branches", "enforce-git-workflow.sh", "PROTECTED_BRANCHES", True,
              lambda item: _branches([item]))
    shell("tdd_layers", "hook-lib.sh", "CWK_TDD_LAYERS", _alternation)

    def argv(value):
        if re.search(r"[*?\[\]'\"$`\\]", value):
            raise _Unreadable(value)
        return value.split()

    shell("test_command", "tdd-prove-red.sh", "RUN_TESTS", argv)

    formatter = re.search(r"^if PRETTIER=\$\(cwk_bin ([A-Za-z0-9._-]+)\)",
                          _hook_text(project_dir, "format-on-save.sh") or "", re.M)
    if formatter:
        out["formatter"] = [formatter.group(1), "--write"]
    linter = re.search(r"^ESLINT=\$\(cwk_bin ([A-Za-z0-9._-]+)\) ",
                       _hook_text(project_dir, "eslint-batch.sh") or "", re.M)
    if linter:
        out["linter"] = linter.group(1)
    icons = re.search(r"'</\?\(([A-Za-z0-9|]+)\)\\b'", _hook_text(project_dir, "no-forbidden-icons.sh") or "")
    if icons:
        out["forbidden_icons"] = icons.group(1).split("|")

    copies = [
        ("protect-files.sh", r"^ENV_TEMPLATE_RE='\\\.\(([a-z0-9|]+)\)\$'$"),
        ("prevent-destructive-commands.sh", r"sed -E 's/\\\.env\\\.\(([a-z0-9|]+)\)//g'"),
        ("shell_targets.py", r'SECRET_KEEP = re\.compile\(r"\^\\\.env\(\\\.\.\+\)\?\\\.\(([a-z0-9|]+)\)\$"\)'),
    ]
    suffixes = []
    for hook, pattern in copies:
        match = re.search(pattern, _hook_text(project_dir, hook) or "", re.M)
        if match:
            suffixes.append((hook, match.group(1).split("|")))
    if suffixes:
        out["env_template_suffixes"] = suffixes[0][1]
        for hook, words in suffixes[1:]:
            if words != suffixes[0][1]:
                notes.append(f"migrate: env_template_suffixes in {hook} ({'|'.join(words)}) differ from "
                             f"{suffixes[0][0]} ({'|'.join(suffixes[0][1])}), {suffixes[0][0]} kept")

    arch = _py_values(_hook_text(project_dir, "enforce-architecture.py"),
                      {"DATA_CLIENT_MODULE", "DATA_CLIENT_OWN_PATH", "COMPOSITION_ROOTS", "SHARED_DIRS"})
    client = {}
    for name, key in (("DATA_CLIENT_MODULE", "module"), ("DATA_CLIENT_OWN_PATH", "own_path"),
                      ("COMPOSITION_ROOTS", "composition_roots"), ("SHARED_DIRS", "shared_dirs")):
        value = arch.get(name)
        if isinstance(value, str):
            client[key] = value
        elif isinstance(value, (tuple, list)):
            client[key] = list(value)
    if client:
        out["data_client"] = client

    lib = _py_values(_hook_text(project_dir, "tdd_py_lib.py"), {"MODULE_ROOT", "TESTS_ROOT", "TEST_FIRST_DIRS"})
    layers = _py_values(_hook_text(project_dir, "enforce-backend-layers.py"),
                        {"MODULE_ROOT", "SESSION_NAMES", "EXTERNAL_CLIENTS"})
    fastapi = {}
    if isinstance(lib.get("MODULE_ROOT"), str):
        fastapi["module_root"] = lib["MODULE_ROOT"].rstrip("/")
    elif isinstance(layers.get("MODULE_ROOT"), str):
        fastapi["module_root"] = layers["MODULE_ROOT"].rstrip("/")
    if (isinstance(lib.get("MODULE_ROOT"), str) and isinstance(layers.get("MODULE_ROOT"), str)
            and lib["MODULE_ROOT"].rstrip("/") != layers["MODULE_ROOT"].rstrip("/")):
        notes.append(f"migrate: fastapi.module_root differs in enforce-backend-layers.py "
                     f"({layers['MODULE_ROOT']}), tdd_py_lib.py kept")
    if isinstance(lib.get("TESTS_ROOT"), str):
        fastapi["tests_root"] = lib["TESTS_ROOT"].rstrip("/")
    if isinstance(lib.get("TEST_FIRST_DIRS"), (tuple, list)):
        fastapi["test_first_dirs"] = [str(d).rstrip("/") for d in lib["TEST_FIRST_DIRS"]]
    if isinstance(layers.get("SESSION_NAMES"), (tuple, list)):
        fastapi["session_names"] = list(layers["SESSION_NAMES"])
    if isinstance(layers.get("EXTERNAL_CLIENTS"), dict):
        fastapi["external_clients"] = {k: list(v) for k, v in layers["EXTERNAL_CLIENTS"].items()}
    if fastapi:
        out["fastapi"] = fastapi
    return out


SNAPSHOT = "project.snapshot.json"
MIGRATED_KEYS = frozenset({"protected_dirs", "protected_branches", "tdd_layers", "test_command", "formatter",
                           "linter", "forbidden_icons", "env_template_suffixes", "data_client", "fastapi"})


def _snapshot_path(project_dir):
    return os.path.join(project_dir, ".claude", SNAPSHOT)


def _read_snapshot(project_dir, notes):
    """The values an earlier run saved from the then-active hooks; `{}` when there is none."""
    path = _snapshot_path(project_dir)
    if not os.path.lexists(path):
        return {}
    try:
        values = json.loads(_read(path), object_pairs_hook=_pairs)["values"]
        if not isinstance(values, dict):
            raise ValueError("values")
        return values
    except (ConfigError, OSError, ValueError, KeyError, TypeError):
        notes.append(f"migrate: {SNAPSHOT} unreadable, ignored")
        return {}


def _overlay(base, top):
    out = {key: (dict(value) if isinstance(value, dict) else value) for key, value in base.items()}
    for key, value in top.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key].update(value)
        else:
            out[key] = value
    return out


def _drop_snapshot(project_dir):
    try:
        os.unlink(_snapshot_path(project_dir))
    except OSError:
        pass


def snapshot(project_dir, notes):
    """Saves the values of the target's active hooks beside the project file, merged over an
    earlier snapshot (the hooks win), so a later `migrate` still has them once the hooks are
    replaced. Never writes `project.json`: a stale reader must not meet a schema it fails open on."""
    values = _overlay(_read_snapshot(project_dir, notes), _migrated(project_dir, notes))
    if not values:
        return False
    path = _snapshot_path(project_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    descriptor, temp = tempfile.mkstemp(prefix=SNAPSHOT + ".", suffix=".tmp", dir=os.path.dirname(path))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(json.dumps({"schema_version": 1, "values": values}, indent=2) + "\n")
        os.chmod(temp, 0o644)
        os.replace(temp, path)
    except BaseException:
        if os.path.lexists(temp):
            os.unlink(temp)
        raise
    return True


def migrate(project_dir, notes, upgrade=False):
    """Writes the target's v2 `project.json` from its active hooks and the snapshot an earlier run
    saved. A v2 file is left alone; a v1 file keeps its roots and codegen; an absent one is created.
    With `upgrade` (or a v1 file) and no value found anywhere, the defaults are written with a note.
    Raises ConfigError when the existing file is invalid (left untouched)."""
    path = os.path.join(project_dir, ".claude", "project.json")
    if os.path.lexists(path):
        config = load_strict(project_dir)
        if _version(project_dir) == SCHEMA_VERSION:
            _drop_snapshot(project_dir)
            return False
        raw = document(config)
        upgrade = True
    else:
        raw = json.loads(serialise(DEFAULTS))
    saved = _read_snapshot(project_dir, notes)
    for key in [key for key in saved if key not in MIGRATED_KEYS]:
        notes.append(f"migrate: {key} in {SNAPSHOT} is not a value the hooks hold, ignored")
        del saved[key]
    found = _migrated(project_dir, notes)
    values = _overlay(saved, found)
    if upgrade and not values:
        notes.append("migrate: no value found in the active hooks and no saved snapshot, the kit defaults "
                     "are written; check .claude/project.json against what your hooks used to hold")
    for key, value in values.items():
        candidate = json.loads(serialise(raw))
        if isinstance(value, dict) and isinstance(candidate.get(key), dict):
            candidate[key].update(value)
        else:
            candidate[key] = value
        try:
            _parse(project_dir, path, candidate)
        except ConfigError as error:
            notes.append(f"migrate: {key} not valid ({error}), default kept")
            continue
        raw = candidate
        if key in saved and key not in found:
            notes.append(f"migrate: {key} taken from {SNAPSHOT}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write(project_dir, raw)
    _drop_snapshot(project_dir)
    return True


def _snapshot(project_dir):
    notes = []
    try:
        saved = snapshot(project_dir, notes)
    except OSError as error:
        print(f"project-config: snapshot not written ({error})", file=sys.stderr)
        return 1
    sys.stdout.write("".join(f"{note}\n" for note in notes))
    if saved:
        sys.stdout.write(f"saved: .claude/{SNAPSHOT}\n")
    return 0


def _migrate(project_dir, upgrade=False):
    notes = []
    try:
        migrate(project_dir, notes, upgrade)
    except ConfigError as error:
        print(f"project-config: {error}; left untouched", file=sys.stderr)
        return error.status
    sys.stdout.write("".join(f"{note}\n" for note in notes))
    return 0


def _version(project_dir):
    path = os.path.join(project_dir, ".claude", "project.json")
    return json.loads(_read(path)).get("schema_version")


def _wire(project_dir, addon):
    try:
        changed = wire(project_dir, addon)
    except ConfigError as error:
        print(f"project-config: {error}", file=sys.stderr)
        return error.status
    sys.stdout.write("".join(f"{key}=changed\n" for key in changed))
    return 0


def _shell(project_dir):
    try:
        config = load_strict(project_dir)
    except ConfigError as error:
        print(f"project-config: {error}", file=sys.stderr)
        sys.stdout.write(f"#status={error.status}\0")
        return error.status
    sys.stdout.write(framed(records(config), "\0"))
    return 0


def main(argv):
    if len(argv) == 3 and argv[1] == "shell":
        return _shell(argv[2])
    if len(argv) == 4 and argv[1] == "wire" and argv[3] in ADDON_DIRS:
        return _wire(argv[2], argv[3])
    if len(argv) in (3, 4) and argv[1] == "migrate" and argv[3:] in ([], ["--existing"]):
        return _migrate(argv[2], bool(argv[3:]))
    if len(argv) == 3 and argv[1] == "snapshot":
        return _snapshot(argv[2])
    if argv[1:] == ["defaults"]:
        sys.stdout.write(serialise(DEFAULTS))
        return 0
    if argv[1:] == ["defaults", "--shell"]:
        sys.stdout.write(framed(records(_parse("/", "defaults", json.loads(serialise(DEFAULTS)))), "\n"))
        return 0
    if len(argv) != 3 or argv[1] not in ("roots", "check"):
        print("usage: project_config.py roots|check|shell|migrate|snapshot <project dir> | wire <project dir> supabase|fastapi"
              " | defaults [--shell]", file=sys.stderr)
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
