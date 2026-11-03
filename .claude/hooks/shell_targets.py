#!/usr/bin/env python3
# cwk-guard-api: 2
"""Resolve the write targets of a Bash command: `python3 -B shell_targets.py <cmd> <base>`.

Secret mode, `--secret-reads <cmd> <base> <verbs>`: prints `deny\t<text>` and
`ask\t<text>` lines for the reads that would print a secret (SecretWalker), then
`#end\t<line count>`.

Prints `<verb>\t<target>` rows, then always `#end\t<row count>`. A target is an
absolute normalised path, `?glob:<abs folder>`, `?unknown:<text>` or
`?inline:<program>`. It resolves, never classifies: prevent-destructive-commands.sh
asks hook-guarded.sh about each row. Any failure exits nonzero and the hook falls
back to its text rules. Contract: docs/work/guard-shell/plan.md.
"""

import glob
import itertools
import os
import re
import shlex
import signal
import sys
import time

MAX_ROWS = 64
MAX_DIRS = 8
NUMERIC_STACK = re.compile(r"^[+-][0-9]+$")
SUB_REF = re.compile("([0-9]+)")

HIDE = {"*": "", "?": "", "[": "", "{": "", "$": ""}
UNHIDE = {v: k for k, v in HIDE.items()}
SUB = ""
ARITH = ""
HEREDOC = ""

SUB_END = ""

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
              "--tsBuildInfoFile"}
FLAG_RECURSIVE = {"--out-dir", "--emptyOutDir", "--coverage.reportsDirectory"}
CFG_PROJECT = {"-p", "--project"}
CFG_TOOL = {"-c", "--config", "--root", "--dir"}

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
SECRET_KEEP = re.compile(r"^\.env(\..+)?\.(example|sample|template)$")
LIVE_BRACE = re.compile(r"\{([^{}]*,[^{}]*)\}")
BASH_ONLY_GLOB = re.compile(r"\{[^{}]*\.\.[^{}]*\}|\[\^|\[[!^]?\]?[^\]]*\[[:.=]")
SHELL_LINE = "shell-line"


class GlobBudget(Exception):
    """A glob scan ran past the time budget of the secret scan."""


class GlobCap(Exception):
    """A glob or a brace list gave more than MAX_GLOB entries: the scan cannot list them all."""


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
                i = self.arith_end(i + 3)
                out.append(ARITH)
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
        """An unquoted heredoc body expands its `$(…)` and backticks: lift them out."""
        nested = Scan(body, self.subs, self.heredocs, self.mark)
        j = 0
        while j < len(body):
            if body.startswith("$((", j):
                j = nested.arith_end(j + 3)
            elif body.startswith("$(", j):
                inner, j = nested.region(j + 2, ")")
                self.subs.append(inner)
            elif body[j] == "`":
                inner, j = nested.region(j + 1, "`")
                self.subs.append(inner)
            else:
                j += 1


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

    def __init__(self, directory, stack=(), dirs=None):
        self.dirs = [directory] if dirs is None else list(dirs)
        self.stack = [list(entry) for entry in stack]

    @property
    def dir(self):
        return self.dirs[0]

    def copy(self):
        return State(None, self.stack, self.dirs)

    def resolve(self, word):
        return resolve_in(word, self.dir)

    def move(self, word):
        moved = [resolve_in(word, d) for d in self.dirs]
        kept = []
        for d in moved + self.dirs:
            if d not in kept:
                kept.append(d)
        self.dirs = kept if len(kept) <= MAX_DIRS else [None]

    def cd(self, args):
        self.move(skip_cd_options(args))

    def pushd(self, args):
        self.stack.append(list(self.dirs))
        if any(NUMERIC_STACK.match(a) for a in args):
            self.dirs = [None]
        else:
            self.move(skip_cd_options(args))

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
        self.command = command
        self.heredocs = []
        self.rows = []
        self.subs = []
        self.walked = set()
        self.prior = False

    def walk(self, state):
        flat = Scan(self.command, self.subs, self.heredocs, self.mark).run()
        self.walk_flat(flat, state)
        for index, sub in enumerate(self.subs):
            if index not in self.walked:
                self.walk_flat(sub, state.copy())

    def walk_flat(self, flat, state):
        stack, seg, pending = [state], Segment(False), None
        for tok in tokens(flat):
            seg.subs.extend(int(n) for n in SUB_REF.findall(tok))
            if pending is not None:
                self.redirect(seg, pending, tok)
                pending = None
            elif tok in CONTROL or tok == "}":
                self.finish(seg, stack[-1])
                if tok == "(":
                    stack.append(stack[-1].copy())
                elif tok == ")" and len(stack) > 1:
                    stack.pop()
                seg = Segment(tok in ("|", "|&"))
            elif tok in REDIRECTS:
                if seg.words and seg.words[-1].isdigit():
                    seg.words.pop()
                pending = tok
            else:
                seg.words.append(tok)
        if pending is not None:
            raise Unreadable("redirect without target")
        self.finish(seg, stack[-1])

    def redirect(self, seg, op, word):
        if op in (">&", "<&") and (word.isdigit() or word == "-"):
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
        for directory in state.dirs:
            rows.extend((">", target(word, directory)) for word in seg.redirects)
            if words:
                where = State(directory)
                if chdir is not None:
                    where = State(where.resolve(chdir))
                verb = os.path.basename(unhide(words[0]))
                rows.extend(self.verb_rows(verb, words[1:], seg, where, implicit))
        unique = []
        for row in rows:
            if row not in unique:
                unique.append(row)
        order = {"path": 0, "?glob": 0, "?unknown": 1, "?inline": 2}
        unique.sort(key=lambda row: order[kind(row[1])])
        self.rows.extend(unique)
        self.follow(seg, state, words)

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

    def verb_rows(self, verb, args, seg, state, implicit):
        rows = output_rows(verb, args, state)
        text = " ".join(show(w) for w in [verb] + args)
        if verb in RUNNERS:
            rows.extend(self.runner_rows(verb, args, seg, state, implicit, text))
        elif verb in FLAG_TOOLS:
            rows.extend(tool_rows(verb, args, package_base(state.dir), False, self.prior, text))
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
        if sub in ("run", "run-script"):
            rest = rest[1:]
        elif sub in RUNNER_BUILTINS:
            return []
        script_base = directory if directory != state.dir else package_base(directory)
        return tool_rows("script", rest, script_base, True, self.prior, text)

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
        while j < len(args) and not (args[j].startswith("-") or args[j] in ("(", "!")):
            roots.append(args[j])
            j += 1
        roots = roots or ["."]
        rows = []
        while j < len(args):
            a = args[j]
            if a == "-delete":
                rows.extend(("find", target(r, state.dir)) for r in roots)
            elif a in ("-fprint", "-fprint0", "-fls", "-fprintf") and j + 1 < len(args):
                rows.append(("find", target(args[j + 1], state.dir)))
                j += 1
            elif a in ("-exec", "-execdir", "-ok", "-okdir"):
                cmd = []
                j += 1
                while j < len(args) and args[j] != ";" and not (args[j] == "+" and cmd[-1:] == ["{}"]):
                    cmd.append(args[j])
                    j += 1
                rows.extend(self.exec_rows(cmd, roots, state, a.endswith("dir")))
            j += 1
        return rows

    def exec_rows(self, cmd, roots, state, in_matched_dir):
        """Resolve the executed command once per root, `{}` standing for the matches under it."""
        rows = []
        for root in roots:
            resolved = target(root, state.dir)
            if not resolved.startswith("/"):
                rows.append((os.path.basename(cmd[0]) if cmd else "find", resolved))
                continue
            inner = Segment(False)
            inner.words = [hide_path(resolved) + "/*" if w == "{}" else w for w in cmd]
            before = len(self.rows)
            self.finish(inner, State(None if in_matched_dir else state.dir))
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
        if op == "<" or (op == "<&" and not (word.isdigit() or word == "-")):
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
                    matches = bounded_glob(full, self.deadline)
                except GlobBudget:
                    self.ask(f"{verb} {show(word)}: the glob scan exceeded its time budget")
                    return
                except GlobCap:
                    self.ask(f"{verb}: the glob matches more than {MAX_GLOB} entries, so the scan "
                             f"cannot list them all: {show(word)}")
                    continue
                for match in matches:
                    name = os.path.basename(match.rstrip("/"))
                    if is_secret_name(name):
                        self.deny(f"{verb} {show(word)} reads {name}")
                        return

    def deny(self, text):
        self.verdicts.append(("deny", flat_text(text)))

    def ask(self, text):
        self.verdicts.append(("ask", flat_text(text)))


def capped_glob(pattern):
    """The matches of a glob; GlobCap past MAX_GLOB, never a truncated list passed off as complete."""
    matches = list(itertools.islice(glob.iglob(pattern), MAX_GLOB + 1))
    if len(matches) > MAX_GLOB:
        raise GlobCap()
    return matches


def bounded_glob(pattern, deadline):
    """The matches of a glob, at most MAX_GLOB; GlobBudget past GLOB_EACH seconds or the `deadline`.

    A timer interrupts the listing, so a pattern that lists a huge or looping tree
    cannot hold the hook past its timeout; the next glob still gets its own slice,
    so a later operand naming a secret is still denied. More than MAX_GLOB matches
    raise GlobCap: the caller asks instead of trusting a partial list.
    """
    left = min(deadline - time.monotonic(), GLOB_EACH)
    if left <= 0:
        raise GlobBudget()
    if not hasattr(signal, "setitimer"):
        return capped_glob(pattern)

    def stop(signum, frame):
        raise GlobBudget()

    previous = signal.signal(signal.SIGALRM, stop)
    signal.setitimer(signal.ITIMER_REAL, left)
    try:
        return capped_glob(pattern)
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


def is_secret_name(name):
    return SECRET_NAME.match(name) is not None and SECRET_KEEP.match(name) is None


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
    if name in FLAG_WRITE or name.startswith("--outputFile."):
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
    return None


def not_a_path(value, base, prior):
    """A package script's `-p 3000` or `--project=unit`: no `/`, no `.`, nothing on disk, first call."""
    on_disk = base is not None and os.path.exists(os.path.join(base, unhide(value)))
    return not prior and "/" not in value and "." not in value and not on_disk


def tool_rows(tool, args, base, script, prior, text):
    """The rows of the options that write a folder or file, or load a config, from `base`."""
    rows, j = [], 0
    while j < len(args):
        arg = args[j]
        j += 1
        if not arg.startswith("-") or arg == "--":
            continue
        name, equals, value = arg.partition("=")
        kind = flag_kind(tool, name, script)
        if kind is None:
            continue
        following = args[j] if j < len(args) else None
        if kind == "noemit":
            if (value if equals else following) == "false":
                rows.append(("noemit", "?unknown:" + text))
            continue
        if not equals:
            if name == "--emptyOutDir" and (following is None or following.startswith("-")):
                continue
            if following is None:
                continue
            value = following
            j += 1
        if name == "--emptyOutDir" and value in ("true", "false", ""):
            continue
        if kind == "cfg" and script and not_a_path(value, base, prior):
            continue
        rows.append((kind, target(value, base)))
    return rows


def output_rows(verb, args, state):
    rows = []
    for j, a in enumerate(args):
        if a.startswith("--output="):
            rows.append((verb, target(a[len("--output="):], state.dir)))
        elif a == "--output" and j + 1 < len(args):
            rows.append((verb, target(args[j + 1], state.dir)))
    return rows


def writer_rows(verb, args, state, implicit, text):
    operands = operands_of(verb, args)
    if verb in ("chmod", "chown") and not any(a.startswith("--reference") for a in args):
        operands = operands[1:]
    if verb in LAST_OPERAND:
        explicit = target_dir_option(verb, args)
        operands = [explicit] if explicit is not None else operands[-1:]
    elif verb == "mv":
        explicit = target_dir_option(verb, args)
        operands = operands + ([explicit] if explicit is not None else [])
    if verb == "patch":
        output = patch_output(args)
        operands = [output] if output is not None else operands[:1]
        if not operands:
            return [(verb, "?unknown:" + text)]
    label = verb
    if verb == "rm" and any(RECURSIVE_SHORT.match(a) or (len(a) >= 3 and "--recursive".startswith(a))
                           for a in args):
        label = "rm-r"
    rows = [(label, target(op, state.dir)) for op in operands]
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
            raise Unreadable("unknown sed command " + cmd)
    return out


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


def target(word, directory):
    """The row target of an operand, joined to the tracked directory."""
    if has_live(word) or word.startswith("~"):
        return "?unknown:" + show(word)
    if is_glob(word):
        cuts = [word.index(c) for c in "*?[" if c in word]
        cuts += [m.start() for m in GLOB_BRACE.finditer(word)]
        prefix = os.path.dirname(unhide(word[:min(cuts)]))
        if not prefix.startswith("/") and directory is None:
            return "?unknown:" + show(word)
        return "?glob:" + flat_text(os.path.normpath(os.path.join(directory or "/", prefix)))
    raw = unhide(word)
    if not raw.startswith("/") and directory is None:
        return "?unknown:" + show(word)
    return flat_text(os.path.normpath(os.path.join(directory or "/", raw)))


def main(argv):
    if len(argv) == 5 and argv[1] == "--secret-reads":
        command, base, verbs = argv[2], argv[3], argv[4]
        walker = SecretWalker(command, verbs.split("|"))
        walker.walk(State(os.path.normpath(base) if base.startswith("/") else None))
        verdicts = walker.verdicts[:MAX_ROWS]
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
    for verb, tgt in rows:
        print(f"{verb}\t{tgt}")
    print(f"#end\t{len(rows)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (Unreadable, ValueError, IndexError, RecursionError) as exc:
        print(f"shell_targets: {exc}", file=sys.stderr)
        sys.exit(1)
