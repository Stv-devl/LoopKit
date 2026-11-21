#!/usr/bin/env python3
# cwk-guard-api: 6
"""Resolve the write targets of a Bash command: `python3 -B shell_targets.py <cmd> <base>`.

Secret mode, `--secret-reads <cmd> <base> <verbs>`: prints `deny\t<text>` and
`ask\t<text>` lines for the reads that would print a secret (SecretWalker), then
`#end\t<line count>`.

Prints `<verb>\t<target>` rows, then always `#end\t<row count>`. A target is an
absolute normalised path, `?glob:<abs folder>` (then a unit separator and the word's last segment pattern),
`?unknown:<text>` or `?inline:<program>`. A /tmp path outside the project that a link moves is
emitted on the side the verb acts on: physical for a write through it, lexical for an operand that
acts on the link itself (`target`'s `follows`). A `-delete` root of find is labelled `find-delete`. It resolves, never classifies: prevent-destructive-commands.sh
asks hook-guarded.sh about each row. Any failure exits nonzero and the hook falls
back to its text rules. Contract: docs/work/guard-shell/plan.md.

Two exceptions classify here, because only the parse knows: `kit_cwd_rows`, and the
verb `>cg`, a redirect whose own segment starts with a generator listed in
`.claude/project.json` `codegen_commands` (docs/work/app-roots-codegen/plan.md, Q2).
"""

import glob
import os
import re
import shlex
import signal
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import project_config
except ImportError:
    project_config = None

MAX_ROWS = 64
CONTENTS_ROWS = 24
GLOB_NAME_SEP = "\x1f"
MAX_DIRS = 8
CONFIG = []


def config():
    """`(codegen commands, env template suffixes, bad status or None)`, read once.

    A file that cannot be read gives the kit defaults (no generator, the default suffixes;
    with no reader at all, no suffix: every `.env*` name is then a secret)
    and its status (3 invalid, 4 absent, 5 no project, 6 no reader): `main` then prints a
    `?config` row, and the hook keeps its denies and asks where it would pass.
    """
    if not CONFIG:
        if project_config is None:
            CONFIG.append(((), (), 6))
        else:
            try:
                loaded = project_config.load_strict(os.environ.get("CLAUDE_PROJECT_DIR", ""))
                CONFIG.append((loaded.codegen_commands, loaded.env_template_suffixes, None))
            except project_config.ConfigError as error:
                CONFIG.append(((), tuple(project_config.DEFAULTS["env_template_suffixes"]), error.status))
    return CONFIG[0]


def codegen_commands():
    """The project's listed generators; none when the file is absent or bad."""
    return config()[0]


def config_rows():
    """`[("?config", <status>)]` when the project's config could not be read, else `[]`."""
    if not CONFIG or CONFIG[0][2] is None:
        return []
    return [("?config", str(CONFIG[0][2]))]


CODEGEN_RUNNERS = (("pnpm",), ("pnpm", "exec"), ("pnpm", "dlx"), ("npx",), ("npm", "exec"),
                   ("yarn",), ("yarn", "dlx"), ("bunx",), ("bun", "x"))


def redirect_verb(words):
    """`>cg` when the segment's own words start with a listed generator, else `>`.

    One package-runner prefix (`pnpm exec`, `npx`...) may come before the listed words.
    """
    plain = [unhide(word) for word in words]
    for prefix in codegen_commands():
        listed = list(prefix)
        if plain[:len(listed)] == listed:
            return ">cg"
        for runner in CODEGEN_RUNNERS:
            if plain[:len(runner) + len(listed)] == list(runner) + listed:
                return ">cg"
    return ">"
NUMERIC_STACK = re.compile(r"^[+-][0-9]+$")
BRACE_FD = re.compile(r"^\{[A-Za-z_][A-Za-z0-9_]*\}$")


def is_fd(word):
    """True for a word of ASCII digits only: str.isdigit() also accepts `²`, which int() rejects."""
    return re.fullmatch(r"[0-9]+", word) is not None
SUB_REF = re.compile("([0-9]+)")

HIDE = {"*": "", "?": "", "[": "", "{": "", "$": ""}
UNHIDE = {v: k for k, v in HIDE.items()}
SUB = ""
ARITH = ""
HEREDOC = ""

SUB_END = ""

LIVE_PARAM = re.compile("\\$[A-Za-z_0-9{@*#?!" + HIDE["{"] + HIDE["*"] + HIDE["?"] + "-]")
QUOTED_TOKEN = re.compile(r"'([^']*)'|\"([^\"]*)\"")
ESCAPED_WORD_START = ""

PUNCTUATION = ";&|()<>\n"
CONTROL = {"&&", "||", ";;", "|&", ";", "&", "|", "(", ")", "\n"}
REDIRECTS = {"&>>", "&>", ">>", ">|", ">&", "<<<", "<<", "<&", "<>", "<", ">"}
OPERATORS = sorted(CONTROL | REDIRECTS, key=len, reverse=True)

PREFIX_WORDS = {"env", "command", "exec", "time", "nice", "nohup", "setsid", "{", "!",
                "if", "then", "else", "elif", "while", "until", "do", "sudo", "builtin",
                "stdbuf", "xargs", "timeout"}
PREFIX_VALUE_OPTS = {
    "env": {"-u", "-C", "-S"}, "nice": {"-n"}, "timeout": {"-k", "-s"},
    "sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"},
    "stdbuf": {"-i", "-o", "-e"}, "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a"},
}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
EVERY_OPERAND = {"mv", "rm", "rmdir", "unlink", "shred", "truncate", "touch", "chmod", "chown"}
LAST_OPERAND = {"cp", "install", "ln", "rsync"}
WRITERS = EVERY_OPERAND | LAST_OPERAND | {"tee", "patch"}
VALUE_OPTS = {"cp": "tS", "install": "mogtS", "ln": "tS", "mv": "tS", "rsync": "eTf",
              "touch": "dtr", "shred": "ns", "truncate": "sr", "patch": "pdiDoBrFVYzg"}
CHMOD_OPTION = re.compile(r"^-[Rvcf]+$")
RECURSIVE_SHORT = re.compile(r"^-[a-zA-Z]*[rR][a-zA-Z]*$")
PYTHON = re.compile(r"^python[0-9.]*$")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
GLOB_BRACE = re.compile("[{" + HIDE["{"] + r"][^{}]*(,|\.\.)[^{}]*\}")

RUNNERS = {"pnpm", "npm", "yarn", "npx"}
RUNNER_BUILTINS = {"install", "i", "ci", "add", "remove", "rm", "uninstall", "update", "up",
                   "upgrade", "audit", "outdated", "list", "ls", "why", "publish", "pack", "dlx",
                   "create", "init", "config", "store", "link", "unlink", "rebuild", "prune",
                   "fetch", "import", "help", "env", "bin", "root", "dedupe", "patch",
                   "patch-commit", "setup", "licenses", "cache", "login", "logout", "whoami"}
RUNNER_BASE_OPTS = {"-C", "--dir", "--prefix", "--cwd"}
RUNNER_VALUE_OPTS = {"--filter", "-F", "--workspace", "--reporter", "--loglevel"}
EXEC_VALUE_OPTS = {"-p", "--package", "--filter"}
EXEC_SHELL_OPTS = {"-c", "--call"}
FLAG_TOOLS = {"vite", "vitest", "playwright", "tsc"}
FLAG_WRITE = {"--outputFile", "--output-file", "--outFile", "--declarationDir", "--generateTrace",
              "--tsBuildInfoFile", "--generateCpuProfile", "--last-failed-file"}
FLAG_RECURSIVE = {"--out-dir", "--emptyOutDir", "--coverage.reportsDirectory", "--attachmentsDir",
                  "--coverage.htmlDir"}
CFG_PROJECT = {"-p", "--project"}
CFG_TOOL = {"-c", "--config", "--root", "--dir"}
VALUE = "value"
BOOL = frozenset({"true", "false"})


class Names(frozenset):
    """The built-in names a NAME option accepts, alone or as a comma list."""


VITEST_REPORTERS = Names({"default", "agent", "minimal", "blob", "verbose", "dot", "json", "tap", "tap-flat",
                          "junit", "tree", "hanging-process", "github-actions", "html"})
PLAYWRIGHT_REPORTERS = Names({"list", "line", "dot", "json", "junit", "html", "blob", "github", "null",
                              "perfetto"})
COVERAGE_REPORTERS = Names({"text", "text-summary", "html", "lcov", "lcovonly", "json", "json-summary",
                            "clover", "cobertura", "teamcity", "none"})
ENVIRONMENTS = Names({"node", "jsdom", "happy-dom", "edge-runtime"})
POOLS = Names({"threads", "forks", "vmThreads", "vmForks"})
VITE_COMMANDS = {"build", "dev", "serve", "preview", "optimize"}
SAFE_VITEST = {
    "-t": VALUE, "--testNamePattern": VALUE, "--reporter": VITEST_REPORTERS, "--project": VALUE,
    "--coverage": BOOL,
    "--coverage.enabled": BOOL, "--coverage.include": VALUE, "--coverage.exclude": VALUE,
    "--coverage.reporter": COVERAGE_REPORTERS, "--bail": VALUE, "--retry": VALUE, "--silent": BOOL,
    "--passWithNoTests": BOOL, "--ui": BOOL, "--run": BOOL, "--watch": BOOL, "-w": None,
    "--shard": VALUE, "--sequence.shuffle": BOOL, "--sequence.seed": VALUE, "--maxWorkers": VALUE,
    "--minWorkers": VALUE, "--pool": POOLS, "--environment": ENVIRONMENTS, "--testTimeout": VALUE,
    "--hookTimeout": VALUE, "--teardownTimeout": VALUE, "--changed": VALUE, "--mode": VALUE,
    "--exclude": VALUE, "--hideSkippedTests": BOOL, "--logHeapUsage": BOOL, "--globals": BOOL,
    "--allowOnly": BOOL, "--no-color": None, "--color": BOOL,
    "--update": frozenset({"false"}), "--help": None, "-h": None, "--version": None, "-v": None,
}
SAFE_PLAYWRIGHT = {
    "--reporter": PLAYWRIGHT_REPORTERS, "-j": VALUE, "--workers": VALUE, "-g": VALUE, "--grep": VALUE,
    "--grep-invert": VALUE, "-gv": VALUE, "--last-failed": None, "--list": None, "--trace": VALUE,
    "--project": VALUE, "--headed": None, "--debug": None, "--retries": VALUE,
    "--repeat-each": VALUE, "-x": None, "--max-failures": VALUE, "--timeout": VALUE,
    "--global-timeout": VALUE, "--forbid-only": None, "--fully-parallel": None, "--quiet": None,
    "--pass-with-no-tests": None, "--shard": VALUE, "--ui": None, "--no-deps": None,
    "--browser": VALUE, "--tsconfig": VALUE, "--update-snapshots": frozenset({"none"}),
    "-unone": None, "--help": None, "-h": None, "--version": None, "-V": None,
}
SAFE_TSC = {
    "--pretty": None, "--skipLibCheck": None, "--extendedDiagnostics": None, "--diagnostics": None,
    "--listFiles": None, "--explainFiles": None, "--traceResolution": None,
    "--noErrorTruncation": None, "--showConfig": None, "--strict": None, "--noUnusedLocals": None,
    "--noUnusedParameters": None, "--all": None, "--help": None, "-h": None, "--version": None,
    "-v": None,
}
SAFE_VITE = {
    "--mode": VALUE, "-m": VALUE, "--minify": VALUE, "--sourcemap": VALUE, "--logLevel": VALUE,
    "-l": VALUE, "--base": VALUE, "--help": None, "-h": None, "--version": None, "-v": None,
}
CHECKED_TSC = FLAG_WRITE - {"--outputFile", "--output-file", "--last-failed-file"} | {
    "--outDir", "--noEmit", "--init", "--project"}
TSC_OPTIONS = {n.lstrip("-").lower(): n for n in CHECKED_TSC | SAFE_TSC.keys() if n.startswith("--")}
TSC_OPTIONS["p"] = "-p"
SAFE_SCRIPTS = {"test:run", "test:coverage", "typecheck", "build"}
TOOL_SAFE = {"vitest": SAFE_VITEST, "playwright": SAFE_PLAYWRIGHT, "tsc": SAFE_TSC, "vite": SAFE_VITE}
SCRIPT_TOOL = {"test:run": "vitest", "test:coverage": "vitest", "vitest": "vitest", "build": "vite",
               "vite": "vite", "typecheck": "tsc", "tsc": "tsc", "playwright": "playwright"}

MAX_GLOB = 256
GLOB_BUDGET = 1.8
GLOB_EACH = 0.4
GREPS = {"grep", "egrep", "fgrep"}
GREP_VALUE_SHORT = "ABCDdm"
READER_VALUE_SHORT = {"grep": GREP_VALUE_SHORT, "egrep": GREP_VALUE_SHORT, "fgrep": GREP_VALUE_SHORT,
                      "rg": "ABCEMTdgjmrt", "sed": "l", "awk": "vF", "gawk": "vF", "mawk": "vF"}
BYPASS_WRAPPERS = {"command", "env", "exec", "nice", "nohup", "setsid", "sudo", "stdbuf",
                   "timeout", "xargs"}
SECRET_NAME = re.compile(r"^(\.env(\..+)?|.*\.(pem|key)|\.?credentials(\..*)?)$")
TEMPLATE_KEEP = []
LIVE_BRACE = re.compile(r"\{([^{}]*,[^{}]*)\}")
BASH_ONLY_GLOB = re.compile(r"\{[^{}]*\.\.[^{}]*\}|\[\^|\[[!^]?\]?[^\]]*\[[:.=]")
SHELL_LINE = "shell-line"


class GlobBudget(Exception):
    """A glob scan ran past the time budget of the secret scan."""


class GlobCap(Exception):
    """A brace list gave more than MAX_GLOB words: the scan cannot list them all."""


class Unreadable(Exception):
    """A construct this resolver cannot follow: the hook falls back to its text rules."""


class Scan:
    """The quote-aware pre-scan: hides quoted globs, lifts `$(…)` out, cuts heredoc bodies."""

    def __init__(self, text, subs=None, heredocs=None, mark=False):
        self.text = text
        self.subs = [] if subs is None else subs
        self.heredocs = [] if heredocs is None else heredocs
        self.mark = mark

    def run(self):
        out, end = self.region(0, None)
        if end != len(self.text):
            raise Unreadable("unbalanced region")
        return out

    def region(self, i, closer):
        """Transform text from i up to the closer (`)`, backtick, or the end)."""
        text, out, sq, dq, depth, pending = self.text, [], False, False, 0, []
        while i < len(text):
            ch = text[i]
            if sq:
                if ch == "'":
                    sq = False
                out.append(ch if ch == "'" else HIDE.get(ch, ch))
                i += 1
                continue
            if ch == "\\" and i + 1 < len(text):
                nxt = text[i + 1]
                if nxt == "\n":
                    i += 2
                    continue
                if self.mark and not dq and (not out or out[-1][-1:] in " \t\n;&|()"):
                    out.append(ESCAPED_WORD_START)
                out.append(ch + HIDE.get(nxt, nxt))
                i += 2
                continue
            if ch == "'" and not dq:
                sq = True
                out.append(ch)
                i += 1
                continue
            if ch == '"':
                dq = not dq
                out.append(ch)
                i += 1
                continue
            if text.startswith("$((", i):
                end = self.arith_end(i + 3)
                self.body_subs(text[i + 3:end - 2])
                i = end
                out.append(ARITH)
                continue
            if not dq and text.startswith(("<(", ">("), i):
                inner, i = self.region(i + 2, ")")
                self.subs.append(inner)
                out.append(SUB + str(len(self.subs) - 1) + SUB_END)
                continue
            if text.startswith("$(", i):
                inner, i = self.region(i + 2, ")")
                self.subs.append(inner)
                out.append(SUB + str(len(self.subs) - 1) + SUB_END)
                continue
            if ch == "`":
                if closer == "`" and not dq:
                    return "".join(out), i + 1
                inner, i = self.region(i + 1, "`")
                self.subs.append(inner)
                out.append(SUB + str(len(self.subs) - 1) + SUB_END)
                continue
            if dq:
                out.append(HIDE.get(ch, ch) if ch in "*?[{" else ch)
                i += 1
                continue
            if ch == ")" and closer == ")" and depth == 0:
                if pending:
                    raise Unreadable("heredoc without body")
                return "".join(out), i + 1
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            if ch == "#" and (not out or out[-1][-1:] in " \t\n;&|()"):
                while i < len(text) and text[i] != "\n":
                    i += 1
                continue
            if text.startswith("<<<", i):
                out.append("<<<")
                i += 3
                continue
            if text.startswith("<<", i):
                i, word = self.heredoc_opener(i + 2, pending)
                out.append("<< " + word + " ")
                continue
            if ch == "\n" and pending:
                out.append(ch)
                i = self.heredoc_bodies(i + 1, pending)
                pending = []
                continue
            out.append(ch)
            i += 1
        if closer or sq or dq or pending:
            raise Unreadable("unterminated quote, region or heredoc")
        return "".join(out), i

    def arith_end(self, i):
        depth = 2
        while i < len(self.text):
            depth += {"(": 1, ")": -1}.get(self.text[i], 0)
            i += 1
            if depth == 0:
                return i
        raise Unreadable("unterminated arithmetic")

    def heredoc_opener(self, i, pending):
        text, strip, quoted, word = self.text, False, False, []
        if i < len(text) and text[i] == "-":
            strip, i = True, i + 1
        while i < len(text) and text[i] in " \t":
            i += 1
        while i < len(text) and text[i] not in " \t\n;&|()<>":
            ch = text[i]
            if ch in "'\"":
                close = text.find(ch, i + 1)
                if close < 0:
                    raise Unreadable("unterminated heredoc delimiter")
                quoted = True
                word.append(text[i + 1:close])
                i = close + 1
            elif ch == "\\":
                quoted = True
                i += 1
            else:
                word.append(ch)
                i += 1
        delim = "".join(word)
        if not delim:
            raise Unreadable("heredoc without delimiter")
        self.heredocs.append("")
        pending.append((len(self.heredocs) - 1, delim, strip, quoted))
        return i, HEREDOC + str(len(self.heredocs) - 1)

    def heredoc_bodies(self, i, pending):
        text = self.text
        for index, delim, strip, quoted in pending:
            lines = []
            while True:
                if i >= len(text):
                    raise Unreadable("heredoc without terminator")
                end = text.find("\n", i)
                line = text[i:] if end < 0 else text[i:end]
                i = len(text) if end < 0 else end + 1
                if (line.lstrip("\t") if strip else line) == delim:
                    break
                lines.append(line)
            body = "\n".join(lines)
            self.heredocs[index] = body
            if not quoted:
                self.body_subs(body)
        return i

    def body_subs(self, body):
        """An unquoted heredoc or arithmetic body expands its `$(…)` and backticks: lift them out."""
        nested = Scan(body, self.subs, self.heredocs, self.mark)
        j = 0
        while j < len(body):
            if body.startswith("$((", j):
                end = nested.arith_end(j + 3)
                self.body_subs(body[j + 3:end - 2])
                j = end
            elif body.startswith("$(", j):
                inner, j = nested.region(j + 2, ")")
                self.subs.append(inner)
            elif body[j] == "`":
                inner, j = nested.region(j + 1, "`")
                self.subs.append(inner)
            else:
                j += 1


def close_dangling_backslash(text):
    """Bash reads a final unpaired backslash as a literal one; shlex refuses it."""
    run = len(text) - len(text.rstrip("\\"))
    return text + "\\" if run % 2 else text


def tokens(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=PUNCTUATION)
    lex.whitespace_split = True
    lex.whitespace = " \t\r"
    lex.commenters = ""
    out = []
    for tok in lex:
        if tok and all(c in PUNCTUATION for c in tok):
            out.extend(split_operators(tok))
        else:
            out.append(tok)
    return out


def split_operators(run):
    parts, i = [], 0
    while i < len(run):
        for op in OPERATORS:
            if run.startswith(op, i):
                parts.append(op)
                i += len(op)
                break
        else:
            raise Unreadable("unknown operator " + run)
    return parts


class State:
    """The possible working directories (None = unknown) and the pushd stack.

    A `cd` may fail or be conditional, so after one the directory before it stays
    possible: a relative target is checked against every candidate.
    """

    def __init__(self, directory, stack=(), dirs=None, physical=False):
        self.dirs = [directory] if dirs is None else list(dirs)
        self.stack = [list(entry) for entry in stack]
        self.physical = physical

    @property
    def dir(self):
        return self.dirs[0]

    def copy(self):
        return State(None, self.stack, self.dirs, self.physical)

    def resolve(self, word):
        return resolve_in(word, self.dir)

    def move(self, word, physical=False):
        resolve = resolve_physical if physical or self.physical else resolve_in
        moved = [resolve(word, d) for d in self.dirs]
        kept = []
        for d in moved + self.dirs:
            if d not in kept:
                kept.append(d)
        self.dirs = kept if len(kept) <= MAX_DIRS else [None]

    def cd(self, args):
        self.move(skip_cd_options(args), cd_physical(args))

    def pushd(self, args):
        self.stack.append(list(self.dirs))
        if any(NUMERIC_STACK.match(a) for a in args):
            self.dirs = [None]
        else:
            self.move(skip_cd_options(args), cd_physical(args))

    def set_mode(self, verb, args):
        """`set -P`/`set -o physical`/`shopt -s -o physical` make later cds physical; `+P`,
        `+o physical` and `shopt -u -o physical` undo it. A live word after them sets it."""
        if any(has_live(a) for a in args):
            self.physical = True
        elif verb == "set":
            for j, a in enumerate(args):
                following = args[j + 1] if j + 1 < len(args) else None
                if re.match(r"^[-+][a-zA-Z]*P", a) or (a in ("-o", "+o") and following == "physical"):
                    self.physical = a.startswith("-")
        elif "-o" in args and "physical" in args:
            if "-s" in args:
                self.physical = True
            elif "-u" in args:
                self.physical = False

    def popd(self, args):
        if any(NUMERIC_STACK.match(a) for a in args):
            self.dirs = [None]
        else:
            self.dirs = self.stack.pop() if self.stack else [None]


def resolve_in(word, directory):
    """The absolute directory a cd-like word names from `directory`, None when unknown."""
    if word is None or has_live(word) or word.startswith("~") or word == "-":
        return None
    raw = unhide(word)
    if raw.startswith("/"):
        return os.path.normpath(raw)
    return None if directory is None else os.path.normpath(os.path.join(directory, raw))


def cd_physical(args):
    """Whether cd/pushd's options hold -P (the last of -P/-L wins, as in bash)."""
    physical = False
    for a in args:
        if not a.startswith("-") or a in ("-", "--"):
            break
        for letter in a[1:]:
            if letter in "PL":
                physical = letter == "P"
    return physical


def resolve_physical(word, directory):
    """The directory a `cd -P`-like word lands in: links followed before `..`, as chdir(2) does.

    A result inside the physical project is mapped back onto the project's spelling, so every
    in-project row keeps the prefix the hook compares against. None when unknown.
    """
    if word is None or has_live(word) or word.startswith("~") or word == "-":
        return None
    raw = unhide(word)
    if not raw.startswith("/") and directory is None:
        return None
    joined = os.path.join(directory or "/", raw)
    physical = tmp_physical(joined)
    if physical == "?":
        return None
    if physical is None:
        return os.path.normpath(joined)
    physical = os.path.normpath(physical)
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if project.startswith("/"):
        real = os.path.realpath(project)
        if under(physical, real):
            return os.path.normpath(project) + physical[len(real):]
    return physical


def skip_cd_options(args):
    """The directory word of cd/pushd: options -P -L -e -@ and `--` are skipped."""
    j = 0
    while j < len(args) and args[j].startswith("-") and args[j] != "-":
        j += 1
        if args[j - 1] == "--":
            break
    return args[j] if j < len(args) else None


class Segment:
    """One simple command: its words, write redirects and stdin sources."""

    def __init__(self, piped):
        self.words = []
        self.redirects = []
        self.heredocs = []
        self.herestrings = []
        self.stdin_file = False
        self.stdin_targets = []
        self.piped = piped
        self.subs = []


class Walker:
    """Walk a command and every command nested in it, collecting write rows."""

    mark = False

    def __init__(self, command):
        self.command = close_dangling_backslash(command)
        self.heredocs = []
        self.rows = []
        self.subs = []
        self.walked = set()
        self.prior = False
        self.start = None
        self.seq = 0
        self.first = None
        self.after = None
        self.top = False
        self.kits = []
        self.fd_events = []
        self.inner = 0
        self.seg_count = 0
        self.row_segs = {}
        self.maker_weight = {}

    def walk(self, state):
        self.start = state.dir
        flat = Scan(self.command, self.subs, self.heredocs, self.mark).run()
        self.walk_flat(flat, state, True)
        for index, sub in enumerate(self.subs):
            if index not in self.walked:
                self.walk_flat(sub, state.copy())
        self.rows = self.link_rewrite(self.rows)
        self.rows.extend(self.kit_cwd_rows())
        self.rows.extend(self.fd_rows())

    def note_fd(self, op, fd, word):
        """Record a redirect's fd: an int, None (the operator's default) or "?" (a `{var}` fd)."""
        self.fd_events.append((op, fd, word))

    def fd_rows(self):
        """`fd-bound` rows: the fds 0-2 that may point at a path anywhere in the call.

        A read redirect binds its fd; a dup copies a binding, repeated until nothing changes, in any
        order. shlex drops whitespace, so a digit word before the operator binds both that fd and
        the default one (`head -n 5 < f` binds 0). A `{var}` fd is unknown: 0, 1 and 2 are bound.
        Here-docs and here-strings bind nothing.
        """
        bound, dups = set(), []
        for op, fd, word in self.fd_events:
            if op in ("<<", "<<<"):
                continue
            default = 1 if op == ">&" else 0
            fds = {0, 1, 2} if fd == "?" else ({default} if fd is None else {fd, default})
            if fd == "?" or op in ("<", "<>") or (op == "<&" and not is_fd(word) and word != "-"):
                bound |= fds
            elif op in ("<&", ">&") and is_fd(word):
                dups.extend((n, int(word)) for n in fds)
        changed = True
        while changed:
            changed = False
            for n, m in dups:
                if m in bound and n not in bound:
                    bound.add(n)
                    changed = True
        return [("fd-bound", str(n)) for n in sorted(bound) if n in (0, 1, 2)]

    def walk_flat(self, flat, state, top=False):
        outer, self.top = self.top, top
        try:
            self.walk_segments(flat, state)
        finally:
            self.top = outer

    def walk_segments(self, flat, state):
        stack, seg, pending, pending_fd = [state], Segment(False), None, None
        for tok in tokens(flat):
            seg.subs.extend(int(n) for n in SUB_REF.findall(tok))
            if pending is not None:
                self.note_fd(pending, pending_fd, tok)
                self.redirect(seg, pending, tok)
                pending = None
            elif tok in CONTROL or tok == "}":
                self.after = tok
                self.finish(seg, stack[-1])
                if tok == "(":
                    stack.append(stack[-1].copy())
                elif tok == ")" and len(stack) > 1:
                    stack.pop()
                seg = Segment(tok in ("|", "|&"))
            elif tok in REDIRECTS:
                pending_fd = None
                if seg.words and is_fd(seg.words[-1]):
                    pending_fd = int(seg.words.pop())
                elif seg.words and BRACE_FD.match(seg.words[-1]):
                    pending_fd = "?"
                pending = tok
            else:
                seg.words.append(tok)
        if pending is not None:
            raise Unreadable("redirect without target")
        self.after = None
        self.finish(seg, stack[-1])

    def note_kit(self, seg, words, chdir):
        """Record, for the `kit-cwd` rule, this segment's place and whether it names a kit script."""
        number = None
        if self.top:
            number = self.seq
            self.seq += 1
            if number == 0:
                self.first = (list(seg.words), self.after)
        if kit_mention(seg.words, words):
            plain = chdir is None and list(seg.words) == list(words) and kit_shape(words)
            self.kits.append((number if plain else None, " ".join(show(w) for w in seg.words)))

    def kit_cwd_rows(self):
        """One `kit-cwd` row for a kit script run by relative path from an unproven directory.

        An allowlist of positions, no bash cwd model: the kit script is the command's first
        segment and the hook cwd is the project root or a registered worktree; or the first
        segment is `cd <absolute root>` joined by `&&` to the kit script as second segment.
        What follows the kit script does not matter. Any other occurrence asks.
        """
        for number, text in self.kits:
            if number == 0 and kit_cwd_ok(self.start):
                continue
            if number == 1 and self.first is not None and self.first[1] == "&&" \
                    and cd_to_root(self.first[0]):
                continue
            return [("kit-cwd", "?unknown:" + text)]
        return []

    def redirect(self, seg, op, word):
        if op in (">&", "<&") and (is_fd(word) or word == "-"):
            return
        if op == "<<":
            if not word.startswith(HEREDOC):
                raise Unreadable("heredoc marker lost")
            seg.heredocs.append(self.heredocs[int(word[len(HEREDOC):])])
        elif op == "<<<":
            seg.herestrings.append(show(word))
        elif op in ("<", "<&"):
            seg.stdin_file = True
        else:
            seg.redirects.append(word)

    def finish(self, seg, state):
        words, implicit, chdir = strip_prefixes(seg.words)
        rows = []
        redirect = redirect_verb(words) if seg.redirects else ">"
        for directory in state.dirs:
            rows.extend((redirect, target(word, directory)) for word in seg.redirects)
            if words:
                where = State(directory)
                if chdir is not None:
                    where = State(resolve_physical(chdir, directory))
                verb = os.path.basename(unhide(words[0]))
                rows.extend(self.verb_rows(verb, words[1:], seg, where, implicit))
                script = run_target(words)
                if script is not None:
                    rows.append(("run", target(script, where.dir)))
        self.note_kit(seg, words, chdir)
        unique = []
        for row in rows:
            if row not in unique:
                unique.append(row)
        order = {"path": 0, "?glob": 0, "?link": 0, "?unknown": 1, "?inline": 2}
        unique.sort(key=lambda row: order[kind(row[1])])
        self.rows.extend(unique)
        if self.inner == 0:
            number = self.seg_count
            self.seg_count += 1
            for row in unique:
                self.row_segs.setdefault(row, set()).add(number)
            weight = link_maker_weight(words)
            if weight:
                self.maker_weight[number] = weight
        self.follow(seg, state, words)

    def link_rewrite(self, rows):
        """The structural link rule: once the call holds a link maker, a row lexically under /tmp
        and outside the project becomes `?link:`, but for a row of the sole link maker's own
        segment and a settled operand that acts on the link itself."""
        total = sum(self.maker_weight.values())
        if not total:
            return rows
        sole = next(iter(self.maker_weight)) if total == 1 else None
        made = [(t, s) for (_, t), segs in self.row_segs.items() for s in segs
                if s in self.maker_weight and t.startswith("/")]
        out = []
        for label, tgt in rows:
            path = tgt[len("?glob:"):].replace(GLOB_NAME_SEP, "/") if tgt.startswith("?glob:") else tgt
            segs = self.row_segs.get((label, tgt), set())
            if not path.startswith("/") or not under_tmp(path) or in_project(path) \
                    or (sole is not None and segs == {sole}) \
                    or ((label, tgt) in ACTS_ON_LINK and settled(path, segs, made)):
                out.append((label, tgt))
            else:
                out.append((label, "?link:" + path))
        return out

    def follow(self, seg, state, words):
        """Walk the segment's substitutions, then apply its cd/pushd/popd to the state."""
        for index in seg.subs:
            if index not in self.walked:
                self.walked.add(index)
                self.walk_flat(self.subs[index], state.copy())
        if words:
            self.prior = True
            verb, args = os.path.basename(unhide(words[0])), words[1:]
            if verb == "cd":
                state.cd(args)
            elif verb == "pushd":
                state.pushd(args)
            elif verb == "popd":
                state.popd(args)
            elif verb in ("set", "shopt"):
                state.set_mode(verb, args)

    def verb_rows(self, verb, args, seg, state, implicit):
        rows = output_rows(verb, args, state)
        text = " ".join(show(w) for w in [verb] + args)
        if PYTHON.match(verb) and kit_doctor_args(args, implicit):
            rows.append(("kit-doctor", "?unknown:" + text))
        if verb in RUNNERS:
            rows.extend(self.runner_rows(verb, args, seg, state, implicit, text))
        elif verb in FLAG_TOOLS:
            rows.extend(tool_rows(verb, args, package_base(state.dir), False, self.prior, text,
                                  positional="vite" if verb == "vite" else None))
        elif verb == "rg":
            if any(a in ("--pre", "--hostname-bin") or a.startswith(("--pre=", "--hostname-bin="))
                   for a in args):
                rows.append((verb, "?unknown:" + text))
        elif verb == "eval":
            rows.append((verb, "?inline:" + " ".join(show(a) for a in args)))
        elif verb in SHELLS or PYTHON.match(verb) or verb in ("node", "perl", "ruby"):
            rows.extend(self.interpreter(verb, args, seg, state, implicit))
        elif verb == "find":
            rows.extend(self.find(args, state))
        elif verb == "sed":
            rows.extend(sed_rows(args, state, implicit, text))
        elif verb in WRITERS:
            rows.extend(writer_rows(verb, args, state, implicit, text))
            rows.extend(into_rows(verb, args, state))
        elif verb == "mkdir":
            rows.extend(("mkdir", target(op, state.dir)) for op in mkdir_operands(args))
        for _, tgt in list(rows):
            if tgt.startswith("?inline:"):
                rows.extend(("inline-path", p) for p in inline_paths(tgt[len("?inline:"):], state.dir))
        return rows

    def runner_rows(self, verb, args, seg, state, implicit, text):
        """pnpm/npm/yarn/npx: the command an `exec` runs, or a package script's flag rows."""
        call = runner_exec(verb, args)
        if call is SHELL_LINE:
            return [("exec", "?unknown:" + text)]
        if call is not None:
            words, base, _, inner_implicit, chdir = call
            where = State(state.dir if base is None else resolve_in(base, state.dir))
            if chdir is not None:
                where = State(where.resolve(chdir))
            if not words:
                return []
            return self.verb_rows(os.path.basename(unhide(words[0])), words[1:], seg, where,
                                  implicit or inner_implicit)
        base, sub, rest = runner_split(verb, args)
        if sub is None:
            return []
        directory = state.dir if base is None else resolve_in(base, state.dir)
        name = sub
        if sub in ("run", "run-script"):
            name, rest = (rest[0] if rest else None), rest[1:]
        elif sub in RUNNER_BUILTINS:
            return []
        script_base = directory if directory != state.dir else package_base(directory)
        return tool_rows("script", rest, script_base, True, self.prior, text,
                         name in SAFE_SCRIPTS or name in FLAG_TOOLS,
                         positional={"build": "build", "vite": "vite"}.get(name),
                         parser=SCRIPT_TOOL.get(name))

    def interpreter(self, verb, args, seg, state, implicit):
        if verb in ("perl", "ruby"):
            program, files, inplace = perl_program(args)
            file_rows = [(verb, target(f, state.dir)) for f in files] if inplace else []
            if program is not None:
                return file_rows + [(verb, "?inline:" + show(program))]
            runs_script = any(not a.startswith("-") for a in args)
            if file_rows:
                return file_rows
        elif verb == "node":
            program, runs_script = node_program(args)
            if program is not None:
                return [(verb, "?inline:" + show(program))]
        else:
            program, runs_script = shell_or_python_program(verb, args)
            if program is not None:
                return [(verb, "?inline:" + show(program))]
        if runs_script:
            return []
        if seg.heredocs or seg.herestrings:
            return [(verb, "?inline:" + flat_text(" ".join(seg.heredocs + seg.herestrings)))]
        if seg.stdin_file:
            return []
        if seg.piped or implicit:
            return [(verb, "?inline:" + flat_text(self.command))]
        return []

    def find(self, args, state):
        roots, j = [], 0
        while j < len(args) and (args[j] in ("-H", "-L", "-P") or args[j].startswith("-O")
                                 or args[j] == "-D"):
            j += 2 if args[j] == "-D" else 1
        follow = "-L" in args[:j]
        while j < len(args) and not (args[j].startswith("-") or args[j] in ("(", "!")):
            roots.append(args[j])
            j += 1
        roots = roots or ["."]
        follow = follow or self.follows_links(args[j:])
        rows = []
        while j < len(args):
            a = args[j]
            if a == "-delete":
                rows.extend(("find-delete", target(r, state.dir)) for r in roots)
                if follow:
                    rows.extend(self.followed_rows("find-delete", roots, state))
            elif a in ("-fprint", "-fprint0", "-fls", "-fprintf") and j + 1 < len(args):
                rows.append(("find", target(args[j + 1], state.dir)))
                j += 1
            elif a in ("-exec", "-execdir", "-ok", "-okdir"):
                cmd = []
                j += 1
                while j < len(args) and args[j] != ";" and not (args[j] == "+" and cmd[-1:] == ["{}"]):
                    cmd.append(args[j])
                    j += 1
                ran = self.exec_rows(cmd, roots, state, a.endswith("dir"))
                rows.extend(ran)
                if follow and (ran or link_maker_weight(strip_prefixes(cmd)[0])):
                    rows.extend(self.followed_rows(os.path.basename(cmd[0]) if cmd else "find", roots, state))
            j += 1
        return rows

    @staticmethod
    def follows_links(args):
        """True when `-follow` is one of find's own expression words, not an -exec clause word."""
        j = 0
        while j < len(args):
            if args[j] == "-follow":
                return True
            if args[j] in ("-exec", "-execdir", "-ok", "-okdir"):
                j += 1
                while j < len(args) and args[j] != ";" and not (args[j] == "+" and args[j - 1] == "{}"):
                    j += 1
            j += 1
        return False

    @staticmethod
    def followed_rows(label, roots, state):
        """With -L or -follow, find walks through the links under a root; one outside the project
        may lead into it, so the delete or exec on it is `?unknown`."""
        rows = []
        for root in roots:
            raw = unhide(root)
            joined = raw if raw.startswith("/") else (os.path.join(state.dir, raw) if state.dir else "")
            if not joined or not in_project(os.path.normpath(joined)):
                rows.append((label, "?unknown:" + show(root)))
        return rows

    def exec_rows(self, cmd, roots, state, in_matched_dir):
        """Resolve the executed command once per root, `{}` standing for the matches under it.

        A root a link moves runs twice: on the link itself and on where it leads (`?unknown` when
        that side cannot be known).
        """
        rows = []
        resolved_roots = []
        for root in roots:
            for follows in (False, True):
                resolved = target(root, state.dir, follows)
                if resolved not in resolved_roots:
                    resolved_roots.append(resolved)
        for resolved in resolved_roots:
            if not resolved.startswith("/"):
                rows.append((os.path.basename(cmd[0]) if cmd else "find", resolved))
                continue
            inner = Segment(False)
            inner.words = [hide_path(resolved) + "/*" if w == "{}" else w for w in cmd]
            before = len(self.rows)
            self.inner += 1
            try:
                self.finish(inner, State(None if in_matched_dir else state.dir))
            finally:
                self.inner -= 1
            rows.extend(self.rows[before:])
            del self.rows[before:]
        return rows


class SecretWalker(Walker):
    """Secret mode: the reads of a command that would print a secret file or the environment.

    Collects `deny\t<text>` (an operand that is, or globs to, a secret file) and
    `ask\t<text>` (a read that skips Claude Code's grep wrapper or the ignore files,
    a glob in an unknown directory, the bare environment). Contract:
    docs/work/harness-hooks/plan.md, A6.
    """

    mark = True

    def __init__(self, command, verbs):
        super().__init__(command)
        self.verbs = set(verbs) | {".", "source"}
        self.verdicts = []
        self.deadline = time.monotonic() + GLOB_BUDGET

    def redirect(self, seg, op, word):
        word = word.replace(ESCAPED_WORD_START, "")
        if op == "<" or (op == "<&" and not (is_fd(word) or word == "-")):
            seg.stdin_targets.append(word)
        super().redirect(seg, op, word)

    def finish(self, seg, state):
        clean = [w.replace(ESCAPED_WORD_START, "") for w in seg.words]
        words, _, chdir = strip_prefixes(clean)
        start = len(clean) - len(words)
        dropped = {w for w in clean[:start] if w in PREFIX_WORDS}
        escaped = start < len(seg.words) and seg.words[start].startswith(ESCAPED_WORD_START)
        dirs = list(state.dirs)
        if chdir is not None:
            dirs = [resolve_in(chdir, d) for d in dirs]
        for word in seg.stdin_targets:
            self.operand("<", word, dirs)
        if words:
            self.judge(words, dropped, escaped, dirs)
        elif "env" in dropped:
            self.ask("env: prints the whole environment")
        self.follow(seg, state, words)

    def judge(self, words, dropped, escaped, dirs):
        verb, args = os.path.basename(unhide(words[0])), words[1:]
        if verb in RUNNERS:
            call = runner_exec(verb, args)
            if call is SHELL_LINE:
                self.ask(f"{show(words[0])} -c/--call: runs a shell line that this scan does not read")
                return
            if call is not None:
                inner_words, base, more, _, chdir = call
                inner_dirs = dirs if base is None else [resolve_in(base, d) for d in dirs]
                if chdir is not None:
                    inner_dirs = [resolve_in(chdir, d) for d in inner_dirs]
                if inner_words:
                    self.judge(inner_words, dropped | more | {"exec"}, False, inner_dirs)
                elif "env" in more:
                    self.ask(f"{show(words[0])} exec env: prints the whole environment")
                return
        text = " ".join(show(w) for w in words)
        if verb in ("printenv", "set") and not args:
            self.ask(text + ": prints the whole environment")
        if verb in self.verbs:
            for word in file_operands(verb, args):
                self.operand(verb, word, dirs)
        bypass = escaped or "/" in unhide(words[0]) or bool(dropped & BYPASS_WRAPPERS)
        if verb in GREPS and grep_recursive(args) and (bypass or grep_null(args)):
            self.ask(text + ": a recursive grep past Claude Code's grep wrapper, which skips"
                     " gitignored files, or with -Z/--null")
        elif verb == "rg" and rg_unrestricted(args):
            self.ask(text + ": rg told to read ignored or hidden files")
        elif verb == "git" and git_grep_untracked(args):
            self.ask(text + ": git grep over untracked or ignored files")

    def operand(self, verb, word, dirs):
        if has_live(word):
            return
        if BASH_ONLY_GLOB.search(word):
            self.ask(f"{verb} {show(word)}: an unsupported glob form, bash expands it differently"
                     " from this scan")
            return
        try:
            expanded = brace_expand(word)
        except GlobCap:
            self.ask(f"{verb}: the braces give more than {MAX_GLOB} words, so the scan cannot "
                     f"list them all: {show(word)}")
            return
        for each in expanded:
            if not any(c in each for c in "*?["):
                name = os.path.basename(os.path.expanduser(unhide(each)).rstrip("/"))
                if is_secret_name(name):
                    self.deny(f"{verb} {show(word)} reads {name}")
                    return
                continue
            pattern = os.path.expanduser("".join(
                glob.escape(UNHIDE[c]) if c in UNHIDE else c for c in each))
            roots = [None] if os.path.isabs(pattern) else dirs
            for root in roots:
                if root is None and not os.path.isabs(pattern):
                    self.ask(f"{verb} {show(word)}: a glob in an unknown directory")
                    continue
                full = pattern if root is None else os.path.join(glob.escape(root), pattern)
                try:
                    name = bounded_glob(full, self.deadline)
                except GlobBudget:
                    self.ask(f"{verb} {show(word)}: the glob scan exceeded its time budget")
                    return
                if name is not None:
                    self.deny(f"{verb} {show(word)} reads {name}")
                    return

    def deny(self, text):
        self.verdicts.append(("deny", flat_text(text)))

    def ask(self, text):
        self.verdicts.append(("ask", flat_text(text)))


def secret_in_glob(pattern):
    """The first secret file name among every match of a glob, or None once all are read."""
    for match in glob.iglob(pattern):
        name = os.path.basename(match.rstrip("/"))
        if is_secret_name(name):
            return name
    return None


def bounded_glob(pattern, deadline):
    """The first secret name a glob matches, or None; GlobBudget past GLOB_EACH seconds or the `deadline`.

    Every match is read, however many: only a name that is a secret decides. A
    timer interrupts the listing, so a pattern that lists a huge or looping tree
    cannot hold the hook past its timeout and asks instead; the next glob still
    gets its own slice, so a later operand naming a secret is still denied.
    """
    left = min(deadline - time.monotonic(), GLOB_EACH)
    if left <= 0:
        raise GlobBudget()
    if not hasattr(signal, "setitimer"):
        return secret_in_glob(pattern)

    def stop(signum, frame):
        raise GlobBudget()

    previous = signal.signal(signal.SIGALRM, stop)
    signal.setitimer(signal.ITIMER_REAL, left)
    try:
        return secret_in_glob(pattern)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def runner_split(verb, args):
    """(directory option value or None, subcommand or None, its arguments) of a package runner call.

    pnpm/npm/yarn read their own options before the subcommand (-C/--dir move the
    directory); npx has no subcommand and runs its arguments as `exec` does.
    """
    if verb == "npx":
        return None, "exec", args
    base, i = None, 0
    while i < len(args) and args[i].startswith("-") and args[i] != "--":
        name, equals, value = args[i].partition("=")
        if not equals and (name in RUNNER_BASE_OPTS or name in RUNNER_VALUE_OPTS):
            value = args[i + 1] if i + 1 < len(args) else None
            i += 1
        if name in RUNNER_BASE_OPTS:
            base = value
        i += 1
    if i >= len(args):
        return base, None, []
    return base, args[i], args[i + 1:]


def runner_exec(verb, args):
    """What a package runner's `exec` (npm's alias `x`, npx's own call) runs, for both modes.

    None when the call is not an exec. SHELL_LINE for -c/--call, which hands the runner
    a shell line neither mode reads. Else (words, directory option value, prefix words
    dropped, xargs implied, `env -C` directory): the runner and its options are
    stripped, then the same prefixes as any command (env, nice, timeout, assignments…).
    `words` is empty when only prefixes follow.
    """
    base, sub, rest = runner_split(verb, args)
    if not (sub == "exec" or (sub == "x" and verb == "npm")):
        return None
    i = 0
    while i < len(rest) and rest[i].startswith("-"):
        name = rest[i].partition("=")[0]
        if rest[i] == "--":
            i += 1
            break
        if name in EXEC_SHELL_OPTS:
            return SHELL_LINE
        i += 2 if name in EXEC_VALUE_OPTS and "=" not in rest[i] else 1
    inner = rest[i:]
    if verb == "npm" and "--" in inner:
        inner = inner[:inner.index("--")] + inner[inner.index("--") + 1:]
    words, implicit, chdir = strip_prefixes(inner)
    dropped = {w for w in inner[:len(inner) - len(words)] if w in PREFIX_WORDS}
    return words, base, dropped, implicit, chdir


def file_operands(verb, args):
    """The words of a secret-reading verb that name a file.

    Options are dropped; a value given to -f/--file is a file, one given to
    -e/--regexp/--expression is a pattern. A reader's first plain word is its
    pattern or script, unless -e/-f gave one. `--x=value` values are kept.
    """
    reader = verb in READER_VALUE_SHORT
    files, plain, given, opts, i = [], [], False, True, 0
    while i < len(args):
        a = args[i]
        i += 1
        if opts and a == "--":
            opts = False
        elif opts and a.startswith("--"):
            name, eq, value = a.partition("=")
            role = reader_long_role(name) if reader else None
            if role and not eq and i < len(args):
                value, eq = args[i], "="
                i += 1
            given = given or role is not None
            if eq and role != "pattern":
                files.append(value)
        elif opts and reader and a.startswith("-") and len(a) > 1:
            for j, c in enumerate(a[1:], 1):
                if c in "ef" or c in READER_VALUE_SHORT[verb]:
                    value = a[j + 1:]
                    if not value and i < len(args):
                        value = args[i]
                        i += 1
                    if c == "f":
                        files.append(value)
                    given = given or c in "ef"
                    break
        elif not (opts and a.startswith("-") and len(a) > 1):
            plain.append(a)
    if reader and not given:
        plain = plain[1:]
    return files + plain


def reader_long_role(name):
    """`pattern`, `file` or None for a reader's long option, unique prefixes included."""
    if len(name) >= 4 and ("--regexp".startswith(name) or "--expression".startswith(name)):
        return "pattern"
    if len(name) >= 4 and "--file".startswith(name):
        return "file"
    return None


def short_flags(args, value_chars):
    """Every single-letter flag of the bundles, each bundle cut at its first value-taking letter."""
    flags = set()
    for a in args:
        if a == "--":
            break
        if a.startswith("-") and not a.startswith("--"):
            for c in a[1:]:
                flags.add(c)
                if c in value_chars:
                    break
    return flags


def grep_recursive(args):
    return bool(short_flags(args, "ABCDdefm") & {"r", "R"}) or any(
        a in ("--recursive", "--dereference-recursive", "--directories=recurse") for a in args)


def grep_null(args):
    return "Z" in short_flags(args, "ABCDdefm") or "--null" in args


def rg_unrestricted(args):
    return bool(short_flags(args, READER_VALUE_SHORT["rg"] + "ef") & {"u", "."}) or any(
        a.startswith("--no-ignore") or a in ("--hidden", "--unrestricted") for a in args)


def git_grep_untracked(args):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in ("-C", "-c") else 1
    return i < len(args) and args[i] == "grep" and any(
        a in ("--untracked", "--no-exclude-standard") for a in args[i + 1:])


def brace_expand(word):
    """Unquoted `{a,b}` expanded, one level at a time; GlobCap past MAX_GLOB words."""
    match = LIVE_BRACE.search(word)
    if match is None:
        return [word]
    out = []
    for part in match.group(1).split(","):
        out.extend(brace_expand(word[:match.start()] + part + word[match.end():]))
        if len(out) > MAX_GLOB:
            raise GlobCap()
    return out


def secret_keep():
    """`.env[.<x>].<suffix>` for the project's `env_template_suffixes`: a template, never a secret."""
    if not TEMPLATE_KEEP:
        suffixes = "|".join(re.escape(suffix) for suffix in config()[1])
        TEMPLATE_KEEP.append(re.compile(r"^\.env(\..+)?\.(" + suffixes + r")$" if suffixes else r"(?!)"))
    return TEMPLATE_KEEP[0]


def is_secret_name(name):
    if SECRET_NAME.match(name) is None:
        return False
    return secret_keep().match(name) is None


def strip_prefixes(words):
    """Drop assignments and wrappers before the verb; flag xargs' implicit operands.

    Returns (words, implicit, directory word of `env -C`/`--chdir` or None).
    """
    i, implicit, chdir = 0, False, None
    while i < len(words):
        w = words[i]
        if ASSIGNMENT.match(w):
            i += 1
            continue
        if w not in PREFIX_WORDS:
            break
        implicit = implicit or w == "xargs"
        i += 1
        with_value = PREFIX_VALUE_OPTS.get(w, set())
        while i < len(words) and words[i].startswith("-") and w not in ("{", "!") and words[i] != "-":
            opt = words[i]
            if w == "env":
                if opt in ("-C", "--chdir") and i + 1 < len(words):
                    chdir = words[i + 1]
                    i += 2
                    continue
                if opt.startswith("--chdir="):
                    chdir = opt.split("=", 1)[1]
                elif opt.startswith("-C") and len(opt) > 2:
                    chdir = opt[2:]
            i += 2 if opt in with_value else 1
        if w == "env":
            while i < len(words) and ASSIGNMENT.match(words[i]):
                i += 1
        if w == "timeout" and i < len(words):
            i += 1
    return words[i:], implicit, chdir


def package_base(directory):
    """The nearest folder holding package.json, from `directory` up to the project, else `directory`.

    The walk stops at the physical $CLAUDE_PROJECT_DIR, so a package.json above the
    project (a home folder's) never becomes the base; with no project dir there is no walk.
    """
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if directory is None or not project:
        return directory
    top, here = os.path.realpath(project), os.path.realpath(directory)
    while True:
        if os.path.isfile(os.path.join(here, "package.json")):
            return here
        if here == top or not here.startswith(top + os.sep):
            return directory
        here = os.path.dirname(here)


def flag_kind(tool, name, script):
    """The row label a tool option gets: flag-r, flag-w, cfg, noemit, or None."""
    if name == "--noEmit":
        return "noemit" if tool == "tsc" or script else None
    if name in FLAG_WRITE or name.startswith(("--outputFile.", "--output-file.")):
        return "flag-w"
    if name == "--outDir":
        return "flag-w" if tool == "tsc" else "flag-r"
    if name in FLAG_RECURSIVE:
        return "flag-r" if tool in ("vite", "vitest") or script else None
    if name == "--output":
        return "flag-r" if tool == "playwright" or script else None
    if name in CFG_PROJECT:
        return "cfg" if tool == "tsc" or script else None
    if name in CFG_TOOL:
        return "cfg" if tool in ("vite", "vitest", "playwright") or script else None
    if name == "-r":
        return "cfg" if tool == "vitest" or script else None
    return None


def canon_option(tool, script, arg):
    """tsc folds option case and takes a single dash: `-OutDir=x` becomes `--outDir=x`, `-P` becomes `-p`."""
    if tool != "tsc" and not script:
        return arg
    name, equals, value = arg.partition("=")
    dashes = re.match(r"-{1,2}(?=[^-])", name)
    known = TSC_OPTIONS.get(name[dashes.end():].lower()) if dashes else None
    return known + equals + value if known else arg


def camel_option(name):
    """cac accepts kebab for the first segment of an option: `--clear-cache` is `--clearCache`."""
    head, dot, rest = name.partition(".")
    bare = head.lstrip("-")
    return head[:len(head) - len(bare)] + re.sub(r"-([a-z])", lambda m: m.group(1).upper(), bare) + dot + rest


def snapshot_flag(tool, arg, script):
    """vitest `-u`/`--update`, playwright `-u`/`--update-snapshots` (but `=none`): snapshots rewritten."""
    name, _, value = arg.partition("=")
    vitest, playwright = tool == "vitest" or script, tool == "playwright" or script
    if name == "-u":
        return (vitest and value != "false") or (playwright and value != "none")
    if name == "--update":
        return vitest and value != "false"
    if name == "--update-snapshots":
        return playwright and value != "none"
    return False


def config_write_flag(tool, arg, script):
    """tsc `--init` and vitest `--coverage.thresholds.autoUpdate`: they rewrite a guarded config."""
    name, _, value = arg.partition("=")
    if name == "--coverage.thresholds.autoUpdate":
        return (tool == "vitest" or script) and value != "false"
    return name == "--init" and (tool == "tsc" or script)


def kit_doctor_args(args, implicit=False):
    """True when a python call runs kit-doctor.py with any argument after the script.

    Under xargs the operands are implicit, so the call counts with no written argument.
    """
    names = [os.path.basename(unhide(a)) for a in args]
    if "kit-doctor.py" not in names:
        return False
    return implicit or names.index("kit-doctor.py") + 1 < len(args)


def kit_path(word):
    """True when the word is a relative path whose first segments are .claude/hooks or .claude/scripts."""
    raw = unhide(word)
    if raw.startswith("/"):
        return False
    return os.path.normpath(raw).startswith((".claude/hooks/", ".claude/scripts/"))


def kit_relative(words):
    """True when the command runs a kit script through a relative path (as verb or script operand)."""
    verb = os.path.basename(unhide(words[0]))
    if kit_path(words[0]):
        return True
    return (verb in SHELLS or bool(PYTHON.match(verb))) and any(kit_path(a) for a in words[1:])


def kit_mention(raw_words, words):
    """True when a segment runs or hands over a relative kit path: as the command, a script
    operand, or any word of a segment with a wrapper, assignment, find, xargs, runner or shell."""
    if not any(kit_path(w) for w in raw_words):
        return False
    if words and kit_relative(words):
        return True
    if list(raw_words) != list(words) or not words or kit_path(words[0]):
        return True
    verb = os.path.basename(unhide(words[0]))
    return verb in SHELLS or verb in RUNNERS or verb in ("find", "xargs") or bool(PYTHON.match(verb))


def kit_shape(words):
    """True when the words are the kit path itself or a shell/python verb whose first operand is it."""
    if not words:
        return False
    if kit_path(words[0]):
        return True
    verb = os.path.basename(unhide(words[0]))
    if verb not in SHELLS and not PYTHON.match(verb):
        return False
    operand = next((w for w in words[1:] if not w.startswith("-")), None)
    return operand is not None and kit_path(operand)


def cd_to_root(words):
    """True when the words are literally `cd <absolute path>` and that path is a root or worktree."""
    if len(words) != 2 or words[0] != "cd":
        return False
    arg = words[1]
    raw = unhide(arg)
    return not (has_live(arg) or arg.startswith("~") or is_glob(arg)) and raw.startswith("/") \
        and ".." not in raw.split("/") and kit_cwd_ok(raw)


def kit_cwd_ok(directory):
    """True when `directory` is known and is, lexically and by realpath, the project root or a registered worktree root.

    A worktree root counts only when some `<project>/.git/worktrees/<name>/gitdir` names it
    AND its own `.git` file names that entry back (a stale entry asks); a project whose
    `.git` is not a folder (itself a linked worktree) accepts only its root.
    """
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if directory is None or not project:
        return False
    top, here = os.path.realpath(project), os.path.realpath(directory)
    lexical = os.path.normpath(directory)
    roots = {os.path.normpath(project), top}
    if lexical in roots:
        return here == top
    if os.path.dirname(lexical) not in {os.path.join(r, ".claude", "worktrees") for r in roots} \
            or os.path.dirname(here) != os.path.join(top, ".claude", "worktrees"):
        return False
    registry = os.path.join(top, ".git", "worktrees")
    if os.path.islink(os.path.join(top, ".git")) or not os.path.isdir(registry):
        return False
    try:
        names = os.listdir(registry)
    except OSError:
        return False
    for name in names:
        entry = os.path.join(registry, name)
        try:
            with open(os.path.join(entry, "gitdir"), encoding="utf-8") as f:
                named = f.read(4096).strip()
        except (OSError, UnicodeDecodeError):
            continue
        if not named or os.path.realpath(os.path.join(entry, os.path.dirname(named))) != here:
            continue
        marker = os.path.join(here, ".git")
        if os.path.islink(marker) or not os.path.isfile(marker):
            continue
        try:
            with open(marker, encoding="utf-8") as f:
                lines = f.read(4096).splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for line in lines:
            if line.startswith("gitdir:") and \
                    os.path.realpath(os.path.join(here, line[7:].strip())) == os.path.realpath(entry):
                return True
    return False


def not_a_path(value, base, prior):
    """A package script's `-p 3000` or `--project=unit`: no `/`, no `.`, nothing on disk, first call."""
    on_disk = base is not None and os.path.exists(os.path.join(base, unhide(value)))
    return not prior and "/" not in value and "." not in value and not on_disk


def safe_option(table, name, equals, value, following, consumes=False):
    """None when `name` is a listed safe option spelled right, else the word to quote.

    A boolean takes no value; a value option takes `=value` or the next word; a name
    option takes only built-in names (`Names`), alone or as a comma list. With `consumes`
    (a commander or tsc parser) a next word starting with `-` is the value, not an option.
    """
    if name not in table:
        return name + equals + value
    spec = table[name]
    if spec is None:
        return None if not equals else name + equals + value
    if isinstance(spec, Names):
        given = value if equals else following
        if given and (equals or consumes or not given.startswith("-")) and not set(given.split(",")) <= spec:
            return name + equals + value if equals else given
        return None
    if isinstance(spec, frozenset):
        return None if not equals or value in spec else name + equals + value
    return None


def takes_value(table, name, equals, following, consumes=False):
    """True when the safe option `name`, spelled without `=`, consumes the word `following`.

    A word starting with `-` is consumed only when `consumes` (commander or tsc parser).
    """
    spec = table.get(name)
    return (spec is not None and not isinstance(spec, frozenset) or isinstance(spec, Names)) \
        and not equals and following is not None and (consumes or not following.startswith("-"))


def tool_rows(tool, args, base, script, prior, text, listed=True, positional=None, parser=None):
    """The rows of the options that write a folder or file, or load a config, from `base`.

    A word starting with `-` must be a checked option (its row) or a safe option of the
    tool (`TOOL_SAFE`); any other asks. `listed` false (unknown script program): no list.
    `positional` is `vite` or `build` when a bare word is a project root to ask about.
    `parser` is the tool a script runs (`SCRIPT_TOOL`): mri (vite, vitest) leaves a next
    `-` word alone, commander and tsc consume it, an unknown one is checked both ways.
    A leading unquoted glob word always asks.
    """
    rows, j, value_at, seen = [], 0, -1, False
    kind_tool = parser or tool
    table = TOOL_SAFE.get(kind_tool, {})
    mri = kind_tool in ("vite", "vitest")
    unknown = script and parser is None
    consumes = not mri and not unknown
    while j < len(args):
        arg = canon_option(tool, script, args[j])
        following = args[j + 1] if j + 1 < len(args) else None
        if args[j][:1] in ("*", "?", "["):
            rows.append(("glob", "?unknown:" + text))
            j += 1
            continue
        if listed and positional and not arg.startswith("-") and j != value_at:
            first, seen = not seen, True
            if not (first and positional == "vite" and arg in VITE_COMMANDS):
                rows.append(("option", "?unknown:" + tool + " " + arg))
        j += 1
        if arg.startswith("@") and (tool == "tsc" or (script and listed)):
            rows.append(("cfg", "?unknown:" + text))
            continue
        if not arg.startswith("-") or arg in ("-", "--"):
            continue
        if snapshot_flag(tool, arg, script):
            rows.append(("snapshot", "?unknown:" + text))
            continue
        if config_write_flag(tool, arg, script):
            rows.append(("cfg-write", "?unknown:" + text))
            continue
        if camel_option(arg) == "--clearCache" and (tool == "vitest" or script):
            rows.append(("cache-clear", "?unknown:" + text))
            continue
        name, equals, value = arg.partition("=")
        if equals and not value and listed:
            rows.append(("option", "?unknown:" + tool + " " + arg))
            continue
        if (tool == "playwright" or script) and re.match(r"-c[^-=]", name):
            name, equals, value = "-c", "=", arg[2:]
        kind = flag_kind(tool, name, script)
        if kind is None and (tool in ("vite", "vitest") or script):
            kind = flag_kind(tool, camel_option(name), script)
            name = camel_option(name) if kind else name
        if kind is None:
            bad = safe_option(table, name, equals, value, following, consumes) if listed else None
            if bad is not None:
                rows.append(("option", "?unknown:" + tool + " " + bad))
            elif listed and takes_value(table, name, equals, following, consumes):
                value_at = j
            continue
        if kind == "noemit":
            if (value if equals else following) == "false":
                rows.append(("noemit", "?unknown:" + text))
            elif following in ("true", "false"):
                value_at = j
            continue
        if not equals:
            if name == "--emptyOutDir" and (following is None or following.startswith("-")):
                continue
            if following is None or (mri and following.startswith("-")):
                continue
            value = following
            if not (unknown and following.startswith("-")):
                j += 1
            if following[:1] in ("*", "?", "["):
                rows.append(("glob", "?unknown:" + text))
                continue
        if name == "--emptyOutDir" and value in ("true", "false", ""):
            continue
        if kind == "cfg" and script and not_a_path(value, base, prior):
            continue
        rows.append((kind, target(value, base)))
    return rows


def output_rows(verb, args, state):
    """The files of `--output`, and of curl's `-o` and wget's `-O`/`--output-document` (a short
    cluster ending in the letter takes the next word, `-sSLo f`; a glued value is the rest)."""
    rows = []
    short = {"curl": "o", "wget": "O"}.get(verb)
    for j, a in enumerate(args):
        following = args[j + 1] if j + 1 < len(args) else None
        value = None
        if a == "--":
            break
        if a.startswith("--output="):
            value = a[len("--output="):]
        elif a == "--output":
            value = following
        elif verb == "wget" and a.startswith("--output-document="):
            value = a[len("--output-document="):]
        elif verb == "wget" and a == "--output-document":
            value = following
        elif short and a.startswith("-") and not a.startswith("--") and short in a[1:]:
            letters, rest = a[1:].split(short, 1)
            if letters.isalpha() or not letters:
                value = rest or following
        if value is not None and value != "-":
            rows.append((verb, target(value, state.dir)))
    return rows


def run_target(words):
    """The script a segment runs, for the `run` row: its command word when that is a path, or the
    first operand of a shell or of `source`/`.`; None for a `-c` program or a bare command name."""
    if not words:
        return None
    command = unhide(words[0])
    verb = os.path.basename(command)
    if verb == "env" and "/" in command:
        rest = words[1:]
        while rest and (rest[0].startswith("-") or ASSIGNMENT.match(rest[0])):
            rest = rest[1:]
        if rest and os.path.basename(unhide(rest[0])) in SHELLS:
            return run_target(rest)
        return words[0]
    if "/" in command and verb not in SHELLS:
        return words[0]
    if verb not in SHELLS and verb not in ("source", "."):
        return None
    args = words[1:]
    options = [w for w in args if w.startswith("-")]
    if verb in SHELLS and any(o == "-c" or (not o.startswith("--") and "c" in o) for o in options):
        return None
    skip = False
    for w in args:
        if skip:
            skip = False
        elif verb in SHELLS and w in ("-o", "+o", "-O", "+O"):
            skip = True
        elif not w.startswith("-"):
            return w
    return None


def into_rows(verb, args, state):
    """`into` rows for a copy or move into an existing folder: `<folder>/<source name>` per source,
    the file the write creates (`cp /tmp/k/install.sh .`). Only the kit-code check reads them."""
    if verb not in LAST_OPERAND and verb != "mv":
        return []
    operands = operands_of(verb, args)
    explicit = target_dir_option(verb, args)
    if explicit is not None:
        folder, sources = explicit, operands
    elif len(operands) >= 2:
        folder, sources = operands[-1], operands[:-1]
    else:
        return []
    resolved = resolve_in(folder, state.dir)
    if resolved is None or not os.path.isdir(resolved):
        return []
    rows = []
    for source in sources:
        clean = unhide(source)
        name = os.path.basename(clean.rstrip("/"))
        if name == "." or (verb == "rsync" and clean.endswith("/")):
            rows.extend(contents_rows(clean, folder, state))
        elif name and name != "..":
            rows.append(("into", target(os.path.join(folder, name), state.dir)))
    return rows


def contents_rows(source, folder, state):
    """`into` rows of a contents copy (`cp -R /tmp/k/. dir`, `rsync -a /tmp/k/ dir`): one per entry
    of the source folder, or the folder itself when the source cannot be listed (a clone made by
    the same command). A source past CONTENTS_ROWS entries is the folder row too: one row per
    entry would pass MAX_ROWS and turn the whole command into an unknown ask."""
    listed = resolve_in(source, state.dir)
    try:
        names = sorted(os.listdir(listed)) if listed is not None and os.path.isdir(listed) else None
    except OSError:
        names = None
    if names is None or len(names) > CONTENTS_ROWS:
        return [("into", target(folder, state.dir))]
    return [("into", target(os.path.join(folder, n), state.dir)) for n in names]


def mkdir_operands(args):
    """The folders a `mkdir` creates: its operands, `-m <mode>`'s value skipped."""
    out, skip = [], False
    for a in args:
        if skip:
            skip = False
        elif a in ("-m", "--mode"):
            skip = True
        elif not a.startswith("-"):
            out.append(a)
    return out


def writer_rows(verb, args, state, implicit, text):
    """The rows of a file writer. An operand acts through a link (a write, `follows`) or on the
    link itself: rm, unlink, rmdir and mv's sources do, and so does ln's link operand unless it is
    an existing folder taken as a target directory (no -n/-T)."""
    operands = operands_of(verb, args)
    if verb in ("chmod", "chown") and not any(a.startswith("--reference") for a in args):
        operands = operands[1:]
    follows = None
    if verb in LAST_OPERAND:
        explicit = target_dir_option(verb, args)
        operands = [explicit] if explicit is not None else operands[-1:]
        if verb == "ln" and explicit is None and operands:
            no_deref = any(a in ("--no-dereference", "--no-target-directory")
                           or (re.match(r"^-[a-zA-Z]+$", a) and ("n" in a or "T" in a)) for a in args)
            link = resolve_in(operands[0], state.dir)
            follows = [not no_deref and link is not None and os.path.isdir(link)]
    elif verb == "mv":
        explicit = target_dir_option(verb, args)
        if explicit is not None:
            follows = [False] * len(operands) + [True]
            operands = operands + [explicit]
        else:
            last = not any(a in ("-T", "--no-target-directory") for a in args)
            follows = [False] * (len(operands) - 1) + [last] if operands else []
    elif verb in ("rm", "rmdir", "unlink"):
        follows = [False] * len(operands)
    if verb == "patch":
        output = patch_output(args)
        operands = [output] if output is not None else operands[:1]
        if not operands:
            return [(verb, "?unknown:" + text)]
    label = verb
    if verb == "rm" and any(RECURSIVE_SHORT.match(a) or (len(a) >= 3 and "--recursive".startswith(a))
                           for a in args):
        label = "rm-r"
    if follows is None or len(follows) != len(operands):
        follows = [True] * len(operands)
    rows = [(label, target(op, state.dir, f)) for op, f in zip(operands, follows)]
    ACTS_ON_LINK.update(row for row, f in zip(rows, follows) if not f)
    if implicit:
        rows.append((label, "?unknown:" + text))
    return rows


def operands_of(verb, args):
    value_opts = VALUE_OPTS.get(verb, "")
    out, j, ended = [], 0, False
    while j < len(args):
        a = args[j]
        if ended or not a.startswith("-") or a == "-":
            out.append(a)
        elif a == "--":
            ended = True
        elif verb == "chmod" and not CHMOD_OPTION.match(a) and not a.startswith("--"):
            out.append(a)
        elif not a.startswith("--") and len(a) == 2 and a[1] in value_opts:
            if a == "-t" and j + 1 < len(args):
                out.append(args[j + 1])
            j += 1
        j += 1
    return out


def target_dir_option(verb, args):
    """The directory of `-t DIR`, `-rtDIR`, `--target-directory[=DIR]` or a unique prefix of it."""
    value_letters = VALUE_OPTS.get(verb, "").replace("t", "")
    for j, a in enumerate(args):
        if a == "--":
            break
        if a.startswith("--"):
            name, equals, value = a.partition("=")
            if len(name) >= 3 and "--target-directory".startswith(name):
                if equals:
                    return value
                return args[j + 1] if j + 1 < len(args) else None
        elif a.startswith("-") and len(a) > 1 and verb != "rsync":
            for k, c in enumerate(a[1:], 1):
                if c == "t":
                    return a[k + 1:] or (args[j + 1] if j + 1 < len(args) else None)
                if c in value_letters:
                    break
    return None


def patch_output(args):
    """The file named by patch's `-o FILE` / `-oFILE`, else None."""
    for j, a in enumerate(args):
        if a == "-o" and j + 1 < len(args):
            return args[j + 1]
        if a.startswith("-o") and len(a) > 2 and not a.startswith("--"):
            return a[2:]
    return None


def perl_program(args):
    """(program or None, file operands, in place) for perl/ruby."""
    inplace = False
    for j, a in enumerate(args):
        if not a.startswith("-") or a == "--":
            if not inplace:
                return None, [], inplace
            after = args[j + 2:] if a == "--" else args[j + 1:]
            return None, [f for f in after if not f.startswith("-")], inplace
        flags = a[1:]
        for k, c in enumerate(flags):
            if c == "i":
                inplace = True
                break
            if c in "eE":
                rest = flags[k + 1:]
                if rest:
                    return rest, [f for f in args[j + 1:] if not f.startswith("-")], inplace
                program = args[j + 1] if j + 1 < len(args) else ""
                return program, [f for f in args[j + 2:] if not f.startswith("-")], inplace
    return None, [], inplace


def node_program(args):
    """(program or None, runs a script file) for node."""
    j = 0
    while j < len(args):
        a = args[j]
        if a in ("-e", "--eval", "-p", "--print", "-pe"):
            return (args[j + 1] if j + 1 < len(args) else ""), False
        if a.startswith(("--eval=", "--print=")):
            return a.split("=", 1)[1], False
        if a == "-":
            return None, False
        if not a.startswith("-"):
            return None, True
        j += 2 if a in ("-r", "--require") else 1
    return None, False


def shell_or_python_program(verb, args):
    """(program or None, runs a script file or module) for a shell or python."""
    is_python = bool(PYTHON.match(verb))
    j = 0
    while j < len(args):
        a = args[j]
        if a == "-" or a == "--":
            return None, False
        if not a.startswith("-"):
            return None, True
        if a.startswith("--"):
            j += 1
            continue
        flags = a[1:]
        if "c" in flags:
            if is_python:
                rest = flags[flags.index("c") + 1:]
                if rest:
                    return rest, False
            return (args[j + 1] if j + 1 < len(args) else ""), False
        if is_python and "m" in flags:
            return None, True
        if (not is_python and flags[-1] in "oO") or (is_python and flags[-1] in "WX"):
            j += 2
            continue
        j += 1
    return None, False


def sed_long(name):
    """`expression` or `file` for a long option or a unique prefix of it (`--expr`, `--fi`)."""
    if len(name) >= 3 and "--expression".startswith(name):
        return "expression"
    if len(name) >= 4 and "--file".startswith(name):
        return "file"
    return None


def sed_rows(args, state, implicit, text):
    scripts, files, inplace, script_file, given = [], [], False, False, False
    j = 0
    while j < len(args):
        a = args[j]
        if a == "--":
            files.extend(args[j + 1:])
            break
        name, equals, value = a.partition("=")
        if a.startswith("--in-place"):
            inplace = True
        elif a.startswith("--") and sed_long(name):
            given = True
            if not equals:
                value = args[j + 1] if j + 1 < len(args) else ""
                j += 1
            if sed_long(name) == "expression":
                scripts.append(value)
            else:
                script_file = True
        elif a.startswith("-") and len(a) > 1 and not a.startswith("--"):
            bundle = sed_bundle(a[1:])
            inplace = inplace or bundle["i"]
            script_file = script_file or bundle["f"]
            if bundle["value"] is not None:
                given = given or bundle["e"] or bundle["f"]
                value = bundle["value"] or (args[j + 1] if j + 1 < len(args) else "")
                if not bundle["value"]:
                    j += 1
                if bundle["e"]:
                    scripts.append(value)
        elif not a.startswith("-"):
            files.append(a)
        j += 1
    if not scripts and not script_file and files:
        scripts.append(files.pop(0))
    rows = []
    for script in scripts:
        if SUB in script:
            raise Unreadable("command substitution in sed script: $(…)")
        if LIVE_PARAM.search(script):
            raise Unreadable("live expansion in sed script: ${…}")
        script = script.replace(ARITH, "1")
        for what, name in sed_writes(unhide(script)):
            rows.append(("sed", target(name, state.dir) if what == "w" else "?unknown:" + text))
    if inplace:
        rows.extend(("sed", target(f, state.dir)) for f in files)
        if not files or implicit:
            rows.append(("sed", "?unknown:" + text))
    if given or script_file:
        rows.append(("sed", "?unknown:" + text))
    return rows


def sed_bundle(flags):
    """One short-flag bundle: in place, script file, -e, and the value it carries ('' = next arg)."""
    found = {"i": False, "f": False, "e": False, "value": None}
    for k, c in enumerate(flags):
        if c == "i":
            found["i"] = True
            return found
        if c in "efl":
            found[c if c != "l" else "e"] = c != "l"
            if c == "f":
                found["f"], found["e"] = True, False
            found["value"] = flags[k + 1:]
            return found
    return found


def sed_writes(script):
    """[('w', file) | ('e', command)] for a sed script; raises Unreadable."""
    out, i, n = [], 0, len(script)

    def regex_end(start, delim):
        k = start
        while k < n:
            if script[k] == "\\":
                k += 2
            elif script[k] == delim:
                return k
            else:
                k += 1
        raise Unreadable("unterminated sed regex")

    def to_eol(k):
        end = script.find("\n", k)
        return n if end < 0 else end

    def address(k, second):
        if k >= n:
            return k
        c = script[k]
        if c.isdigit():
            while k < n and (script[k].isdigit() or script[k] == "~"):
                k += 1
        elif c == "$":
            k += 1
        elif c == "/":
            k = regex_end(k + 1, "/") + 1
        elif c == "\\" and k + 1 < n:
            k = regex_end(k + 2, script[k + 1]) + 1
        elif second and c in "+~":
            k += 1
            while k < n and script[k].isdigit():
                k += 1
        while k < n and script[k] in "IM" and c in "/\\":
            k += 1
        return k

    while i < n:
        while i < n and script[i] in " \t\n;":
            i += 1
        if i >= n:
            break
        i = address(i, False)
        if i < n and script[i] == ",":
            i = address(i + 1, True)
        while i < n and script[i] in " \t!":
            i += 1
        if i >= n:
            raise Unreadable("sed address without command")
        cmd = script[i]
        i += 1
        if cmd in "{}":
            continue
        if cmd in ":btT":
            while i < n and script[i] not in ";\n":
                i += 1
        elif cmd in "aicrR":
            i = to_eol(i)
        elif cmd in "wWe":
            end = to_eol(i)
            out.append(("w" if cmd in "wW" else "e", script[i:end].strip()))
            i = end
        elif cmd in "sy":
            if i >= n:
                raise Unreadable("sed s without delimiter")
            delim = script[i]
            i = regex_end(regex_end(i + 1, delim) + 1, delim) + 1
            while cmd == "s" and i < n and script[i] not in ";\n}":
                if script[i] == "w":
                    end = to_eol(i + 1)
                    out.append(("w", script[i + 1:end].strip()))
                    i = end
                    break
                if script[i] == "e":
                    out.append(("e", ""))
                i += 1
        elif cmd in "qQlLz=dDgGhHnNpPxF":
            while i < n and (script[i].isdigit() or script[i] in " \t"):
                i += 1
        else:
            raise Unreadable("unknown sed command " + readable(cmd))
    return out


def readable(text):
    """Placeholders shown as the construct they stand for, never as a private-use char."""
    return unhide(text).replace(SUB_END, "").replace(SUB, "$(…)").replace(ARITH, "$((…))") \
        .replace(HEREDOC, "<<…").replace(ESCAPED_WORD_START, "")


def inline_paths(program, directory):
    """Absolute paths under the project that a quoted token of an inline program names."""
    root = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not root.startswith("/"):
        return []
    root = os.path.normpath(root)
    found = []
    for match in QUOTED_TOKEN.finditer(program):
        token = (match.group(1) if match.group(1) is not None else match.group(2)).strip()
        if not token or "$" in token or "`" in token or token.startswith("~"):
            continue
        if not token.startswith("/") and directory is None:
            continue
        path = os.path.normpath(os.path.join(directory or "/", token))
        if path == root or not path.startswith(root + "/"):
            continue
        first = os.path.relpath(path, root).split("/", 1)[0]
        if (os.path.exists(path) or os.path.exists(os.path.join(root, first))) and path not in found:
            found.append(path)
    return found


def has_live(word):
    return "$" in word or "`" in word or SUB in word or ARITH in word


def unhide(word):
    return "".join(UNHIDE.get(c, c) for c in word)


def hide_path(path):
    return "".join(HIDE.get(c, c) for c in path)


def flat_text(text):
    return text.replace("\t", " ").replace("\n", " ")


def show(word):
    return flat_text(SUB_REF.sub("$(…)", unhide(word)).replace(ARITH, "$((…))"))


def kind(tgt):
    return tgt.split(":", 1)[0] if tgt.startswith("?") else "path"


def is_glob(word):
    return any(c in word for c in "*?[") or GLOB_BRACE.search(word) is not None


def under_tmp(path):
    return path == "/tmp" or path.startswith("/tmp/")


def under(path, root):
    return path == root or path.startswith(root + "/")


def tmp_physical(path):
    """Where a write to a /tmp path lands: None when no link moves it, "?" when unknowable.

    Links are followed in order and `..` is applied after them, as the kernel does. A link into
    /proc or /dev is never followed (it would resolve in this process, not in the shell's), and
    an existing file with a second hard link may be a project file: both are "?".
    """
    queue = [p for p in path.split("/") if p]
    current, hops = "/", 0
    while queue:
        seg = queue.pop(0)
        if seg == ".":
            continue
        if seg == "..":
            current = os.path.dirname(current)
            continue
        step = os.path.join(current, seg)
        if os.path.islink(step):
            hops += 1
            dest = os.readlink(step)
            if hops > 40 or under(step, "/proc") or under(step, "/dev") \
                    or under(os.path.normpath(os.path.join(current, dest)), "/proc") \
                    or under(os.path.normpath(os.path.join(current, dest)), "/dev"):
                return "?"
            if dest.startswith("/"):
                current = "/"
            queue = [p for p in dest.split("/") if p] + queue
            continue
        current = step
    try:
        info = os.stat(current)
        if os.path.isfile(current) and info.st_nlink > 1:
            return "?"
    except OSError:
        pass
    lexical = os.path.normpath(path)
    if current == os.path.realpath("/tmp") + lexical[len("/tmp"):]:
        return None
    return current


LINK_CAPABLE = {"ln", "link", "cp", "mv", "rsync", "install", "tar", "cpio", "unzip", "busybox",
                "bsdtar", "pax"}
GIT_READ = {"status", "diff", "log", "show", "rev-parse", "ls-files", "grep", "blame"}
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
NON_CREATING = {
    "echo", "printf", "cat", "grep", "egrep", "fgrep", "rg", "ls", "sort", "head", "tail", "wc",
    "cut", "tr", "uniq", "diff", "cmp", "comm", "jq", "yq", "test", "[", "[[", "]]", "true",
    "false", ":", "pwd", "date", "basename", "dirname", "realpath", "readlink", "stat", "file",
    "which", "type", "command", "sleep", "printenv", "id", "whoami", "uname", "tee", "seq",
    "column", "fold", "nl", "paste", "join", "od", "xxd", "hexdump", "md5sum", "sha256sum",
    "base64", "cd", "pushd", "popd", "export", "unset", "set", "shopt", "local", "declare",
    "readonly", "shift", "exit", "return", "wait", "read", "mkdir", "rm", "rmdir", "unlink",
    "shred", "truncate", "touch", "chmod", "chown", "patch", "curl", "wget", "kill", "trap",
    "jobs", "du", "df", "ps", "tree", "less", "more", "if", "then", "elif", "else", "fi", "for",
    "while", "until", "do", "done", "case", "esac", "in", "{", "}", "!", "function",
}
INTERPRETERS = SHELLS | {"node", "ruby", "perl", "deno", "bun"}
AWKS = {"awk", "gawk", "mawk", "nawk"}
AWK_SYSTEM = re.compile(r"\bsystem\s*\(")
AWK_VALUED = "FvWil"
AWK_LONG_VALUED = ("--assign", "--field-separator", "--include", "--load")
AWK_REGEX_AFTER = set(";{}(,!~&|=?:<>+-*%^\n")
ACTS_ON_LINK = set()


def awk_program(args):
    """The program text of an awk call: the -e/--source values, else the first plain operand.
    None when a -f/--file/-E/--exec script hides the program. Option values (-v, -F, --assign...)
    are skipped, never read as the program."""
    texts, plain, opts, i = [], [], True, 0
    while i < len(args):
        a = args[i]
        i += 1
        if opts and a == "--":
            opts = False
        elif opts and a.startswith("--"):
            name, eq, value = a.partition("=")
            if name in ("--file", "--exec"):
                return None
            if name in ("--source", *AWK_LONG_VALUED):
                if not eq and i < len(args):
                    value = args[i]
                    i += 1
                if name == "--source":
                    texts.append(value)
        elif opts and a.startswith("-") and len(a) > 1:
            for j, c in enumerate(a[1:], 1):
                if c in "fE":
                    return None
                if c == "e" or c in AWK_VALUED:
                    value = a[j + 1:]
                    if not value and i < len(args):
                        value = args[i]
                        i += 1
                    if c == "e":
                        texts.append(value)
                    break
        else:
            plain.append(a)
    return texts or plain[:1]


def awk_code(text):
    """An awk program without its string literals, regex literals and comments."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        last = next((x for x in reversed(out) if not x.isspace()), "")
        if c == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            out.append("s")
        elif c == "/" and (not last or last in AWK_REGEX_AFTER):
            i += 1
            while i < n and text[i] not in "/\n":
                i += 2 if text[i] == "\\" else 1
            out.append("r")
        elif c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def awk_runs(args):
    """True when an awk call can run a command: system(), a pipe to or from a command, or a
    program file it cannot read."""
    texts = awk_program(args)
    if texts is None:
        return True
    return any(AWK_SYSTEM.search(code) or "|" in code.replace("||", "")
               for code in map(awk_code, texts))


def sed_runs(args):
    """True when a sed call can run a command, from sed_rows' own reading: an `e` command or flag,
    a script file. An unreadable script counts."""
    try:
        rows = sed_rows(args, State("/"), False, "")
    except Unreadable:
        return True
    return any(kind(tgt) == "?unknown" for _, tgt in rows)


def git_subcommand(args):
    j = 0
    while j < len(args) and args[j].startswith("-"):
        j += 2 if args[j] in GIT_VALUE_OPTS else 1
    return (args[j], args[j + 1:]) if j < len(args) else (None, [])


def find_exec_commands(args):
    """The commands of find's -exec/-execdir/-ok/-okdir clauses."""
    out, j = [], 0
    while j < len(args):
        if args[j] in ("-exec", "-execdir", "-ok", "-okdir"):
            cmd, j = [], j + 1
            while j < len(args) and args[j] != ";" and not (args[j] == "+" and cmd[-1:] == ["{}"]):
                cmd.append(args[j])
                j += 1
            out.append(cmd)
        j += 1
    return out


def link_maker_weight(words):
    """How many link makers a command is: a command that can create a link or move one into
    place, or one the tokenizer cannot read. A find counts each inner command; an awk or sed that
    runs a command counts two, because its own rows may write through the link it makes."""
    if not words:
        return 0
    head = words[0]
    if has_live(head) or BRACE_FD.match(head):
        return 1
    verb, args = os.path.basename(unhide(head)), words[1:]
    if verb in ("eval", "source", ".") or verb in INTERPRETERS or PYTHON.match(verb):
        return 1
    if verb == "git":
        sub, rest = git_subcommand(args)
        read = sub in GIT_READ or (sub == "branch" and all(a.startswith("-") for a in rest)
                                   and not any(a in ("-m", "-M", "-c", "-C", "-d", "-D") for a in rest))
        return 0 if read else 1
    if verb in LINK_CAPABLE:
        return 1
    if verb in RUNNERS:
        call = runner_exec(verb, args)
        if call is SHELL_LINE:
            return 1
        if call is None:
            return 1 if runner_split(verb, args)[1] == "dlx" else 0
        return link_maker_weight(call[0])
    if verb == "find":
        return sum(link_maker_weight(strip_prefixes(cmd)[0]) for cmd in find_exec_commands(args))
    if verb in AWKS or verb == "sed":
        return 2 if (sed_runs(args) if verb == "sed" else awk_runs(args)) else 0
    if verb in NON_CREATING or verb in FLAG_TOOLS:
        return 0
    return 1


def settled(path, segs, made):
    """An operand acting on a /tmp link is settled when its folder exists before the call runs and
    no link maker in another segment targets it or a folder above it."""
    if not os.path.isdir(os.path.dirname(path)):
        return False
    return not any(under(path, t) and any(s != m for s in segs) for t, m in made)


def in_project(path):
    """True when an absolute path lies in $CLAUDE_PROJECT_DIR as written, or once the deepest
    existing directory on it (the path itself included) is resolved, as cwk_guard_rel does."""
    project = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not project.startswith("/") or not path.startswith("/"):
        return False
    project = os.path.normpath(project)
    if under(path, project):
        return True
    deepest, rest = path, []
    while deepest != "/" and not os.path.isdir(deepest):
        rest.insert(0, os.path.basename(deepest))
        deepest = os.path.dirname(deepest)
    return under(os.path.normpath(os.path.join(os.path.realpath(deepest), *rest)),
                 os.path.realpath(project))


def link_side(joined, follows):
    """Where an operation on a /tmp path lands: None when no link moves it, "?" when unknowable.
    A write (`follows`) follows every link; an operation on the link itself only its folders."""
    name = os.path.basename(joined)
    if follows or name in ("", ".", ".."):
        return tmp_physical(joined)
    folder = tmp_physical(os.path.dirname(joined))
    return folder if folder in (None, "?") else os.path.join(folder, name)


def target(word, directory, follows=True):
    """The row target of an operand, joined to the tracked directory.

    A /tmp operand outside the project that a link moves, or with a second hard link, is given on
    the side the operation acts on (`link_side`), `?unknown` when that side cannot be known. A /tmp
    glob outside the project with a glob character in a folder segment may cross a folder link:
    `?unknown`.
    """
    if has_live(word) or word.startswith("~"):
        return "?unknown:" + show(word)
    if is_glob(word):
        cuts = [word.index(c) for c in "*?[" if c in word]
        cuts += [m.start() for m in GLOB_BRACE.finditer(word)]
        tail = unhide(word[min(cuts):])
        if ".." in tail.split("/"):
            return "?unknown:" + show(word)
        prefix = os.path.dirname(unhide(word[:min(cuts)]))
        if not prefix.startswith("/") and directory is None:
            return "?unknown:" + show(word)
        joined = os.path.join(directory or "/", prefix)
        folder = os.path.normpath(joined)
        if under_tmp(folder) and not in_project(folder):
            moved = tmp_physical(joined)
            if "/" in tail or moved == "?" or (moved is not None and GLOB_NAME_SEP in moved):
                return "?unknown:" + show(word)
            folder = moved or folder
        return "?glob:" + flat_text(folder) + GLOB_NAME_SEP + flat_text(unhide(word).rsplit("/", 1)[-1])
    raw = unhide(word)
    if not raw.startswith("/") and directory is None:
        return "?unknown:" + show(word)
    joined = os.path.join(directory or "/", raw)
    lexical = os.path.normpath(joined)
    if under_tmp(lexical) and not in_project(lexical):
        physical = link_side(joined, follows)
        if physical == "?" or (physical is not None and GLOB_NAME_SEP in physical):
            return "?unknown:" + show(word)
        if physical is not None:
            return flat_text(os.path.normpath(physical))
    return flat_text(lexical)


def main(argv):
    if len(argv) == 5 and argv[1] == "--secret-reads":
        command, base, verbs = argv[2], argv[3], argv[4]
        walker = SecretWalker(command, verbs.split("|"))
        walker.walk(State(os.path.normpath(base) if base.startswith("/") else None))
        verdicts = config_rows() + walker.verdicts[:MAX_ROWS]
        for verdict, text in verdicts:
            print(f"{verdict}\t{text}")
        print(f"#end\t{len(verdicts)}")
        return 0
    if len(argv) != 3:
        print("usage: shell_targets.py <command> <base dir>"
              " | --secret-reads <command> <base dir> <verbs>", file=sys.stderr)
        return 2
    command, base = argv[1], argv[2]
    walker = Walker(command)
    walker.walk(State(os.path.normpath(base) if base.startswith("/") else None))
    rows = walker.rows
    if len(rows) > MAX_ROWS:
        rows = [("?", "?unknown:" + flat_text(command))]
    rows = config_rows() + rows
    for verb, tgt in rows:
        print(f"{verb}\t{tgt}")
    print(f"#end\t{len(rows)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Unreadable as exc:
        print(f"shell_targets: {readable(str(exc))}", file=sys.stderr)
        sys.exit(3)
    except (ValueError, IndexError, RecursionError) as exc:
        print(f"shell_targets: {readable(str(exc))}", file=sys.stderr)
        sys.exit(1)
