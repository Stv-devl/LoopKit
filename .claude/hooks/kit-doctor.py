#!/usr/bin/env python3
"""kit-doctor — checks that the kit's declared twins still agree.

NOT A HOOK. Nothing registers this file in settings.json; it is run by
`/kit:doctor`, or by hand:

    python3 .claude/hooks/kit-doctor.py [project_root]

Read-only, and deliberately not a gate. Exit 0 = nothing diverged, exit 1 =
something did. Wiring that exit code into `/ship` would be a mistake: a rule
file and its enforced copy disagreeing is a decision to take, not a build to
stop.

WHY IT EXISTS. Half a dozen places in this kit hold the same value twice — a
rule states it, a hook enforces it — and every one of them says "change both
together, never one alone". Nothing checked that. The failure is silent and
inverted: the rule keeps claiming the layer is covered while the hook matches a
module nobody imports. See `.claude/rules/01-stack.md`, "The data client".

ADDING A CHECK. One function, returning a Finding list, appended to CHECKS. A
check whose source file is absent returns SKIP — an installed project may have
dropped a template, and that is not a divergence.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------- infrastructure

OK, DIVERGENCE, MISSING, FILL, SKIP = "ok", "DIVERGENCE", "MISSING", "FILL", "skip"
OVER = "OVER"
# Only these three mean "a human has something to decide". The rest is reporting.
FAILING = (DIVERGENCE, MISSING, OVER)

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]

# pnpm's own subcommands, not project scripts: they are never declared in
# `00-project.md` and comparing them against it would report a permanent
# divergence for something that cannot drift.
PNPM_BUILTINS = {"install", "dlx", "exec", "add", "remove", "why"}


class Finding:
    def __init__(self, check: str, status: str, summary: str, evidence: list[str] | None = None):
        self.check = check
        self.status = status
        self.summary = summary
        self.evidence = evidence or []


def read(rel: str) -> str | None:
    path = ROOT / rel
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def skip(check: str, *missing: str) -> list[Finding]:
    return [Finding(check, SKIP, "source absent: " + ", ".join(missing))]


def compare(check: str, left: tuple[str, object], right: tuple[str, object]) -> list[Finding]:
    """The whole point of the file: two copies, named by their file, side by side."""
    (lname, lval), (rname, rval) = left, right
    if lval == rval:
        return [Finding(check, OK, fmt(lval))]
    return [Finding(check, DIVERGENCE, "the two copies disagree", [
        f"{lname}  →  {fmt(lval)}",
        f"{rname}  →  {fmt(rval)}",
    ])]


def fmt(value: object) -> str:
    if isinstance(value, (set, frozenset)):
        return ", ".join(sorted(value)) or "(empty)"
    if isinstance(value, dict):
        return ", ".join(f"{k}={v}" for k, v in sorted(value.items())) or "(empty)"
    return str(value)


# ----------------------------------------------------------------- twin checks

def check_protected_dirs() -> list[Finding]:
    doc, hook = read("CLAUDE.md"), read(".claude/hooks/prevent-destructive-commands.sh")
    if doc is None or hook is None:
        return skip("protected-dirs", "CLAUDE.md", "prevent-destructive-commands.sh")

    block = re.search(r"Recursive delete on:(.*?)(?:\n\s*\n|\n- )", doc, re.S)
    enforced = re.search(r'^PROTECTED_DIRS="([^"]+)"', hook, re.M)
    if not enforced:
        return [Finding("protected-dirs", MISSING, "PROTECTED_DIRS no longer parses in the hook")]
    if not block:
        # The common case is not a rename: it is a project that came with its own
        # CLAUDE.md, so the installer patched the hook and could not patch the doc.
        return [Finding("protected-dirs", MISSING, "CLAUDE.md declares no protected list — the hook guards alone", [
            f".claude/hooks/prevent-destructive-commands.sh  →  {fmt({d.replace(chr(92) + '.', '.') for d in enforced.group(1).split('|')})}",
            "add that list to CLAUDE.md under \"Recursive delete on:\", so the two copies exist",
        ])]

    # The doc writes them as `src/`; the hook as an alternation with escaped dots.
    declared = set(re.findall(r"`([^`]+?)/`", block.group(1)))
    actual = {d.replace("\\.", ".") for d in enforced.group(1).split("|")}
    return compare("protected-dirs", ("CLAUDE.md", declared),
                   (".claude/hooks/prevent-destructive-commands.sh", actual))


def check_data_client() -> list[Finding]:
    stack, hook = read(".claude/rules/01-stack.md"), read(".claude/hooks/enforce-architecture.py")
    if stack is None or hook is None:
        return skip("data-client", "01-stack.md", "enforce-architecture.py")

    row = re.search(r"\|\s*Where does the client live\?\s*\|\s*`([^`]+)`", stack)
    own = re.search(r'^DATA_CLIENT_OWN_PATH = "([^"]+)"', hook, re.M)
    module = re.search(r'^DATA_CLIENT_MODULE = "([^"]+)"', hook, re.M)
    if not row or not own or not module:
        return [Finding("data-client", MISSING, "one side no longer parses — the row or the constant moved")]

    findings: list[Finding] = []
    # A hook whose two constants disagree matches an import path that never
    # resolves: the layer reads as guarded and is not.
    if own.group(1) != module.group(1) + ".ts":
        findings.append(Finding("data-client", DIVERGENCE, "the hook disagrees with itself", [
            f"DATA_CLIENT_MODULE    →  {module.group(1)}",
            f"DATA_CLIENT_OWN_PATH  →  {own.group(1)}",
        ]))

    declared = row.group(1)
    if "<" in declared:
        findings.append(Finding("data-client", FILL, "the rule still carries its placeholder", [
            f".claude/rules/01-stack.md            →  {declared}",
            f".claude/hooks/enforce-architecture.py →  src/{own.group(1)} (already enforced)",
        ]))
        return findings

    findings += compare("data-client", (".claude/rules/01-stack.md", re.sub(r"^src/", "", declared)),
                        (".claude/hooks/enforce-architecture.py", own.group(1)))
    return findings


def check_composition_roots() -> list[Finding]:
    arch, hook = read(".claude/rules/02-architecture.md"), read(".claude/hooks/enforce-architecture.py")
    if arch is None or hook is None:
        return skip("composition-roots", "02-architecture.md", "enforce-architecture.py")

    row = next((l for l in arch.splitlines() if "composition root:" in l), None)
    tup = re.search(r"COMPOSITION_ROOTS = \(([^)]*)\)", hook, re.S)
    if row is None or not tup:
        return [Finding("composition-roots", MISSING, "one side no longer parses — the row or the constant moved")]

    declared = set(re.findall(r"`src/([^`]+)`", row))
    actual = set(re.findall(r'"([^"]+)"', tup.group(1)))
    return compare("composition-roots", (".claude/rules/02-architecture.md", declared),
                   (".claude/hooks/enforce-architecture.py", actual))


def check_shared_dirs() -> list[Finding]:
    """The leaf-code list — the third constant of that config block, and the one
    that has already diverged once (`config/` was missing from both import lists
    while the structure diagram carried it).

    Four copies, not two: the tuple, `02-architecture.md`'s forbidden bullet,
    `CLAUDE.md`'s non-negotiable, and `reviewer.md` — which restates the list AND
    its count, the cheapest of the four to let rot.
    """
    arch, hook = read(".claude/rules/02-architecture.md"), read(".claude/hooks/enforce-architecture.py")
    doc, rev = read("CLAUDE.md"), read(".claude/agents/reviewer.md")
    if hook is None:
        return skip("shared-dirs", "enforce-architecture.py")

    tup = re.search(r"SHARED_DIRS = \(([^)]*)\)", hook, re.S)
    if not tup:
        return [Finding("shared-dirs", MISSING, "SHARED_DIRS no longer parses in the hook")]
    actual = {d.rstrip("/") for d in re.findall(r'"([^"]+)"', tup.group(1))}

    # Every doc copy wraps across lines, so each is matched as a block, never a line.
    # Each copy is compared INDEPENDENTLY. An installed project that arrived with
    # its own CLAUDE.md is the common case (see check_protected_dirs) — losing
    # that one copy must not abandon the two that are kit-shipped and still there.
    copies = (
        ("shared-dirs", ".claude/rules/02-architecture.md",
         r"\*\*Forbidden:\*\*(.*?)→ `features/\*`", r"`src/([a-z]+)/\*`", arch),
        ("shared-dirs (CLAUDE.md)", "CLAUDE.md",
         r"shared leaf code \((.*?)\) never imports a feature", r"`([a-z]+)/`", doc),
        ("shared-dirs (reviewer)", ".claude/agents/reviewer.md",
         r"No shared \*\*leaf\*\* code depending on a feature:(.*?)— the full", r"`src/([a-z]+)`", rev),
    )

    out: list[Finding] = []
    for name, fname, block_re, item_re, text in copies:
        if text is None:
            out += skip(name, fname)
            continue
        block = re.search(block_re, text, re.S)
        if not block:
            out.append(Finding(name, MISSING, f"{fname} declares no leaf list — the wording moved", [
                f".claude/hooks/enforce-architecture.py  →  {fmt(actual)}",
                f"restate that list in {fname}, so the two copies exist",
            ]))
            continue
        out += compare(name, (fname, set(re.findall(item_re, block.group(1)))),
                       (".claude/hooks/enforce-architecture.py", actual))

    # reviewer.md also states the COUNT in prose — a number nothing else compares.
    words = {"three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9}
    n = re.search(r"of `enforce-architecture\.py`, (\w+) entries", rev) if rev else None
    if rev is None:
        out += skip("shared-dirs (count)", ".claude/agents/reviewer.md")
    elif not n:
        out.append(Finding("shared-dirs (count)", MISSING, "reviewer.md no longer states the entry count"))
    elif words.get(n.group(1)) != len(actual):
        out.append(Finding("shared-dirs (count)", DIVERGENCE, "the stated count is wrong", [
            f".claude/agents/reviewer.md  →  {n.group(1)} entries",
            f".claude/hooks/enforce-architecture.py  →  {len(actual)} entries",
        ]))
    else:
        out.append(Finding("shared-dirs (count)", OK, f"{n.group(1)} entries"))
    return out


def check_coverage_floor() -> list[Finding]:
    rule, cfg = read(".claude/rules/05-testing.md"), read(".claude/skills/templates/tooling-config.md")
    if rule is None or cfg is None:
        return skip("coverage-floor", "05-testing.md", "tooling-config.md")

    declared = re.search(r"lines (\d+) / functions (\d+) / branches (\d+)", rule)
    actual = re.search(r"thresholds: \{ lines: (\d+), functions: (\d+), branches: (\d+) \}", cfg)
    if not declared or not actual:
        return [Finding("coverage-floor", MISSING, "one side no longer parses — the numbers moved")]

    keys = ("lines", "functions", "branches")
    return compare("coverage-floor",
                   (".claude/rules/05-testing.md", dict(zip(keys, declared.groups()))),
                   (".claude/skills/templates/tooling-config.md", dict(zip(keys, actual.groups()))))


def check_coverage_holes() -> list[Finding]:
    """The floor's exclusion list — the rule calls it "three wiring files and only three"."""
    rule, cfg = read(".claude/rules/05-testing.md"), read(".claude/skills/templates/tooling-config.md")
    if rule is None or cfg is None:
        return skip("coverage-holes", "05-testing.md", "tooling-config.md")

    declared = set(re.findall(r"`(lib/[A-Za-z0-9/._-]+\.ts)`", rule))
    # The coverage `exclude`, not the suite's — both keys exist, and the suite's
    # neighbour `include` legitimately holds `src/lib/**/*.ts`.
    block = re.search(r"exclude:\s*\[\s*\.\.\.coverageConfigDefaults\.exclude,(.*?)\]", cfg, re.S)
    if not block:
        return [Finding("coverage-holes", MISSING, "the coverage exclude list no longer parses")]
    actual = set(re.findall(r"'src/(lib/[^']+)'", block.group(1)))
    return compare("coverage-holes", (".claude/rules/05-testing.md", declared),
                   (".claude/skills/templates/tooling-config.md", actual))


def check_token_thresholds() -> list[Finding]:
    rule, status = read(".claude/rules/11-token-budget.md"), read(".claude/hooks/token-statusline.py")
    if rule is None or status is None:
        return skip("token-thresholds", "11-token-budget.md", "token-statusline.py")

    declared = {name: pct for name, pct in re.findall(r"`\.([a-z-]+)` at (\d+)%", rule)}

    # Each marker is written inside the `if used >= N` block above its write_text.
    variables = {"token-warning": "warning", "token-stop-agents": "stop_agents", "codex-ready": "ready"}
    actual: dict[str, str] = {}
    current: str | None = None
    for line in status.splitlines():
        threshold = re.match(r"\s*(?:el)?if used >= (\d+)", line)
        if threshold:
            current = threshold.group(1)
        if current:
            for marker, var in variables.items():
                if re.search(rf"\b{var}\.write_text", line):
                    actual.setdefault(marker, current)

    if not declared or not actual:
        return [Finding("token-thresholds", MISSING, "one side no longer parses — markers or thresholds moved")]
    return compare("token-thresholds", (".claude/rules/11-token-budget.md", declared),
                   (".claude/hooks/token-statusline.py", actual))


def check_tdd_layers() -> list[Finding]:
    """The four layer words, in the three places that act on them."""
    lib = read(".claude/hooks/hook-lib.sh")
    cfg = read(".claude/skills/templates/tooling-config.md")
    mutation = read(".claude/commands/audit/mutation.md")
    if lib is None or cfg is None or mutation is None:
        return skip("tdd-layers", "hook-lib.sh", "tooling-config.md", "audit/mutation.md")

    hooks = re.search(r'CWK_TDD_LAYERS="([^"]+)"', lib)
    coverage = re.search(r"TEST_FIRST = '\{([^}]+)\}'", cfg)
    if not hooks or not coverage:
        return [Finding("tdd-layers", MISSING, "one side no longer parses — the layer list moved")]

    sources = {
        ".claude/hooks/hook-lib.sh": set(hooks.group(1).split("|")),
        ".claude/skills/templates/tooling-config.md": set(coverage.group(1).split(",")),
    }
    globs = re.findall(r"\{([a-z,]+)\}\.ts", mutation)
    if globs:
        sources[".claude/commands/audit/mutation.md"] = set(globs[0].split(","))

    reference = sources[".claude/hooks/hook-lib.sh"]
    off = {name: words for name, words in sources.items() if words != reference}
    if not off:
        return [Finding("tdd-layers", OK, fmt(reference))]
    return [Finding("tdd-layers", DIVERGENCE, "the freeze and the measurement cover different layers",
                    [f"{name}  →  {fmt(words)}" for name, words in sources.items()])]


def check_gate_allowlist() -> list[Finding]:
    """Every command `/ship` runs in its gate batch is allowlisted, or it prompts.

    The failure this catches is quiet and inverted: a gate added to `/ship`
    without its `permissions.allow` entry does not fail — it *asks*. Somebody
    declines it by reflex mid-batch, the other five stay green, and the ship
    reports success without the gate that was just added.

    Scope: the `pnpm` invocations of the gate fence only. Everything else on
    those lines (`grep`, a repo script) is covered by a broader allow entry or
    by the user's own settings, and guessing at it would produce noise.
    """
    ship, settings = read(".claude/commands/ship.md"), read(".claude/settings.json")
    if ship is None or settings is None:
        return skip("gate-allowlist", "commands/ship.md", "settings.json")

    fence = re.search(r"### 1\. Gates.*?```bash\n(.*?)```", ship, re.S)
    if not fence:
        return [Finding("gate-allowlist", MISSING, "the gate fence no longer parses in /ship")]

    try:
        allow = json.loads(settings).get("permissions", {}).get("allow", [])
    except json.JSONDecodeError:
        return [Finding("gate-allowlist", MISSING, "settings.json does not parse")]
    granted = {entry[len("Bash("):-1] for entry in allow
               if entry.startswith("Bash(") and entry.endswith(")")}

    # `pnpm audit --audit-level=high` needs the `*` form; a bare `pnpm build`
    # does not. Asking for the wrong one is the same gap as asking for neither.
    needed: dict[str, str] = {}
    for line in fence.group(1).splitlines():
        call = re.match(r"\s*(pnpm\s+[\w:.-]+)(.*)$", line)
        if not call:
            continue
        script, rest = call.group(1).strip(), call.group(2).split("#")[0].strip()
        pattern = f"{script} *" if rest else script
        needed[pattern] = script

    if not needed:
        return [Finding("gate-allowlist", MISSING, "no pnpm gate found in the fence — did it move?")]

    missing = {p: s for p, s in needed.items() if p not in granted}
    if not missing:
        return [Finding("gate-allowlist", OK, fmt({s for s in needed.values()}))]

    local = read(".claude/settings.local.json") or "{}"
    evidence = []
    for pattern, script in sorted(missing.items()):
        note = " (granted in settings.local.json only — that file does not ship)" \
            if f'Bash({pattern})' in local else ""
        evidence.append(f'.claude/settings.json  →  add "Bash({pattern})"{note}')
    return [Finding("gate-allowlist", DIVERGENCE,
                    f"{len(missing)} gate(s) /ship runs but nothing allows — they will prompt",
                    evidence)]


def check_ci_scripts() -> list[Finding]:
    """The CI workflow and the local gate fence run the same set. BOTH ways.

    The third copy of the same list. `00-project.md` declares the scripts,
    `/ship` calls them locally, and `.github/workflows/ci.yml` calls them on the
    runner — and only the first two had a check. The divergence is silent and
    it surfaces at the worst moment: the CI is red on `main`, for a script name
    nobody touched, on a diff that is fine.

    Two directions, and they catch opposite failures:
      * a script the CI runs that `00-project.md` does not declare — a rename;
      * a gate `/ship` runs that the CI does NOT — a role deleted from the YAML,
        which the one-directional version reported as `ok`.

    Scope: `run:` lines only, and only their `pnpm <script>` head. pnpm's own
    subcommands (`install`, `dlx`) are not project scripts and are skipped —
    they cannot drift against a rule that never declared them.

    Reads the workflow wherever it lives: `templates/github/` in the kit source,
    `.github/workflows/` once installed.
    """
    project = read(".claude/rules/00-project.md")
    ci = read("templates/github/ci.yml") or read(".github/workflows/ci.yml")
    if project is None or ci is None:
        return skip("ci-scripts", "rules/00-project.md", "ci.yml")

    fence = re.search(r"```bash\n(.*?)```", project, re.S)
    if not fence:
        return [Finding("ci-scripts", MISSING, "the command fence no longer parses in 00-project.md")]
    declared = {m.group(1) for m in re.finditer(r"^pnpm\s+([\w:.-]+)", fence.group(1), re.M)}

    # `run:` only. A `pnpm test` inside a comment is documentation — here it is
    # even a warning telling you never to put it in CI — and matching it would
    # make the check cry wolf on its own advice.
    #
    # Block scalars (`run: |`) count too. Reading only the `run:` line made the
    # check silently blind: convert one gate to a block and it kept reporting
    # `ok` while checking nothing — the exact silent gap it exists to close.
    # `block_indent` holds the indentation of the `run:` key; every following
    # line indented deeper belongs to that script.
    called: set[str] = set()
    block_indent: int | None = None
    for line in ci.splitlines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())

        if block_indent is not None:
            if not stripped:
                continue
            if indent > block_indent:
                if not stripped.startswith("#"):
                    for call in re.finditer(r"pnpm\s+([\w:.-]+)", line):
                        called.add(call.group(1))
                continue
            block_indent = None   # dedented out of the block

        if stripped.startswith("#"):
            continue
        # `- run: …` compte autant que `run: …`. Sans le `(?:-\s+)?`, tout un
        # style YAML — le tiret et la clef sur la meme ligne — etait invisible,
        # et le controle reportait `ok` en ne voyant rien. Meme classe de trou
        # que les blocs `run: |` qu'il vient de fermer.
        run = re.search(r"^\s*(?:-\s+)?run:\s*(.*)$", line)
        if not run:
            continue
        body = run.group(1).strip()
        if body in ("|", ">", "|-", ">-", "|+", ">+"):
            block_indent = indent
            continue
        for call in re.finditer(r"pnpm\s+([\w:.-]+)", body):
            called.add(call.group(1))

    called -= PNPM_BUILTINS
    if not called:
        return [Finding("ci-scripts", MISSING, "no pnpm script found in ci.yml — did the gates move?")]

    evidence: list[str] = []

    undeclared = called - declared
    evidence += [f".github/workflows/ci.yml  →  pnpm {s}   (absent from 00-project.md)"
                 for s in sorted(undeclared)]

    # THE OTHER DIRECTION, and it is the dangerous one. `undeclared` only ever
    # noticed a script the workflow calls and the rule does not — a rename. A
    # gate role DELETED from ci.yml reported `ok`: measured twice, removing the
    # Typecheck, Lint and Dependency-audit steps left this check printing
    # "No divergence." That is a green CI with no gate in it, reported healthy.
    #
    # The reference is `/ship`'s gate fence, NOT every script 00-project.md
    # declares: the naive reverse (`declared - called`) flags `dev`, `test`,
    # `test:run` and `test:ui` on the pristine kit — four false positives, and a
    # check that cries wolf is a check nobody reads. The fence is already parsed
    # by check_gate_allowlist(); LOCAL_ONLY names the roles that legitimately
    # stop at the machine.
    LOCAL_ONLY = {"dev"}
    ship = read(".claude/commands/ship.md")
    fence_ship = re.search(r"### 1\. Gates.*?```bash\n(.*?)```", ship, re.S) if ship else None
    if fence_ship:
        gated = {m.group(1) for m in re.finditer(r"^\s*(?:pnpm)\s+([\w:.-]+)",
                                                 fence_ship.group(1), re.M)}
        gated -= PNPM_BUILTINS | LOCAL_ONLY
        uncovered = gated - called
        evidence += [f".github/workflows/ci.yml  →  MISSING `pnpm {s}`   "
                     f"(/ship gates on it; the CI does not)"
                     for s in sorted(uncovered)]

    if evidence:
        return [Finding("ci-scripts", DIVERGENCE,
                        "the local gate fence and the CI workflow do not run the same set",
                        evidence)]
    return [Finding("ci-scripts", OK, fmt(called))]


def check_workflow_names() -> list[Finding]:
    """The CD names the CI workflow, and it must name the one that exists.

    `ci.yml` declares `name: CI`; `deploy.yml` names it twice — in its
    `workflow_run` trigger and in the `gh run list --workflow=` of the step that
    resolves which run to deploy. Rename the CI workflow and the CD does not
    fail: `workflow_run` simply never matches, so nothing triggers, nothing goes
    red, and the CI stays green while no deployment has happened for weeks.

    Three copies of one string, and until this check nothing compared them.
    """
    ci = read("templates/github/ci.yml") or read(".github/workflows/ci.yml")
    dep = read("templates/github/deploy.yml") or read(".github/workflows/deploy.yml")
    if ci is None or dep is None:
        return skip("workflow-names", "ci.yml", "deploy.yml")

    declared = re.search(r"^name:\s*(.+?)\s*$", ci, re.M)
    if not declared:
        return [Finding("workflow-names", MISSING, "ci.yml declares no `name:`")]
    expected = declared.group(1)

    # A list, not a set: two sites naming the same workflow is the normal case,
    # and reporting "1 reference" for it reads as if one site had gone missing.
    referenced: list[str] = []
    trigger = re.search(r"^\s*workflows:\s*\[(.+?)\]", dep, re.M)
    if trigger:
        referenced += [n.strip().strip("\"'") for n in trigger.group(1).split(",")]
    referenced += [m.group(1).strip("\"'") for m in re.finditer(r"--workflow=(\S+)", dep)]

    if not referenced:
        return [Finding("workflow-names", MISSING,
                        "deploy.yml no longer names the CI workflow — did the trigger move?")]

    wrong = {n for n in referenced if n != expected}
    if wrong:
        return [Finding("workflow-names", DIVERGENCE,
                        "the CD names a workflow that does not exist — it would never trigger",
                        [f"templates/github/ci.yml      →  name: {expected}"]
                        + [f"templates/github/deploy.yml  →  {n}" for n in sorted(wrong)])]
    return [Finding("workflow-names", OK, f"{expected} ({len(referenced)} reference(s))")]


def check_agent_models() -> list[Finding]:
    """Every agent's `model:` is the tier `11-token-budget.md` assigns it.

    The rule is one table; the enforced copy is a `model:` line in each agent's
    frontmatter, which nobody re-reads once the file exists. The failure is quiet
    and always in the same direction: a new agent is started by copying its
    nearest neighbour and inherits that neighbour's tier, so a **judge** ends up
    on the cheap model — the one case the rule was written to forbid. Nothing
    else in the kit compares the two.
    """
    rule = read(".claude/rules/11-token-budget.md")
    agents_dir = ROOT / ".claude/agents"
    if rule is None or not agents_dir.is_dir():
        return skip("agent-models", "11-token-budget.md", ".claude/agents/")

    # The tier table: the row's first cell is the tier, its LAST cell the agents.
    # Only the last one — the prose cell names an agent too, and reading it would
    # assign that agent its own row's tier by accident.
    declared: dict[str, str] = {}
    for line in rule.splitlines():
        row = re.match(r"\|\s*`([a-z][a-z0-9.-]+)`\s*\|(.*)\|\s*$", line)
        if not row:
            continue
        for name in re.findall(r"`([a-z][a-z0-9-]+)`", row.group(2).split("|")[-1]):
            declared[name] = row.group(1)
    if not declared:
        return [Finding("agent-models", MISSING,
                        "the model-tier table no longer parses in 11-token-budget.md")]

    actual: dict[str, str] = {}
    for path in sorted(agents_dir.glob("*.md")):
        found = re.search(r"^model:\s*(\S+)\s*$", path.read_text(encoding="utf-8"), re.M)
        actual[path.stem] = found.group(1) if found else "(no model: line)"

    findings: list[Finding] = []
    wrong = [(name, declared[name], tier) for name, tier in sorted(actual.items())
             if name in declared and declared[name] != tier]
    if wrong:
        findings.append(Finding("agent-models", DIVERGENCE,
                                f"{len(wrong)} agent(s) run on a tier the rule does not assign them",
                                [f"{name}: .claude/rules/11-token-budget.md → {want}   |   "
                                 f".claude/agents/{name}.md → {got}" for name, want, got in wrong]))

    untiered = sorted(set(actual) - set(declared))
    if untiered:
        findings.append(Finding("agent-models", MISSING,
                                f"{len(untiered)} agent(s) the tier table does not cover",
                                [f"{name}   (runs on {actual[name]} — add its row to "
                                 f"11-token-budget.md, or say there why it is exempt)"
                                 for name in untiered]))

    ghosts = sorted(set(declared) - set(actual))
    if ghosts:
        findings.append(Finding("agent-models", MISSING,
                                f"{len(ghosts)} agent(s) given a tier with no file behind them",
                                [f"{name}   (11-token-budget.md assigns {declared[name]})"
                                 for name in ghosts]))

    if not findings:
        tally: dict[str, int] = {}
        for tier in actual.values():
            tally[tier] = tally.get(tier, 0) + 1
        findings.append(Finding("agent-models", OK, f"{len(actual)} agents — {fmt(tally)}"))
    return findings


# --------------------------------------------------------------- wiring & links

# Written at runtime, or created by a command — absent is the normal state.
RUNTIME_PATHS = {
    ".claude/.tdd-unfrozen", ".claude/.tdd-red", ".claude/.token-warning",
    ".claude/.token-stop-agents", ".claude/.codex-ready", ".claude/.quota-warning",
    ".claude/.hook-timings.log", ".claude/settings.local.json", ".claude/worktrees",
}
# In .claude/hooks/ but invoked by a human or by another script, never by
# settings.json. `hook-lib.sh` and `tdd_py_lib.py` are the two shared libraries,
# one per language.
NON_HOOKS = {"hook-lib.sh", "tdd_py_lib.py", "hook-timings-report.sh", "kit-doctor.py"}
# Claude Code's own slash commands: referenced by the docs, shipped by nobody here.
BUILTIN_COMMANDS = {
    "compact", "clear", "config", "context", "cost", "doctor", "help", "init", "ide",
    "agents", "memory", "model", "resume", "review", "code-review", "security-review",
    "simplify", "run", "loop", "schedule", "fewer-permission-prompts", "update-config",
    "rewind", "hooks", "mcp", "permissions", "statusline", "vim", "usage", "add-dir",
    # The design canvas (research preview), called by `/interface`. The kit
    # deliberately owns no command of that name — a project command would shadow
    # the built-in one and `Skill("design")` would resolve back into the kit.
    "design",
}
# An HTTP verb on the line means the backticked `/thing` is a route, not a command.
HTTP_VERBS = re.compile(r"\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b")


# Kit-owned docs only. An installed project's own README and docs/ are not
# scanned: they name that project's commands and paths, which this file knows
# nothing about, and a doctor that reports someone else's vocabulary as broken
# is a doctor that gets turned off.
KIT_DOCS = ("CLAUDE.md", "AGENTS.md", "docs/Claude_Workflows.md",
            "docs/ADAPTATION.md", "docs/measuring-the-loop.md")

# What `addons/` ships and the core docs legitimately name. The dynamic scan
# below only works in the kit source; an installed project has no `addons/`
# directory at all, so without this list every fresh install would open on three
# false MISSING and an exit 1.
ADDON_PATH_HINTS = ("07-backend.md", "enforce-backend-layers.py", "-ADDON.md", "msw-supabase.md")
ADDON_COMMAND_PREFIXES = ("backend:",)


def is_kit_source() -> bool:
    return (ROOT / "install.sh").is_file() and (ROOT / "addons").is_dir()


def scanned_docs() -> list[Path]:
    docs = [ROOT / name for name in KIT_DOCS]
    if is_kit_source():
        docs.append(ROOT / "README.md")
    docs += sorted((ROOT / ".claude").rglob("*.md"))
    return [d for d in docs if d.is_file()]


def shipped_by_addon(name: str) -> bool:
    if any(hint in name for hint in ADDON_PATH_HINTS):
        return True
    addons = ROOT / "addons"
    return addons.is_dir() and any(addons.rglob(name))


def check_hook_wiring() -> list[Finding]:
    settings, hooks_dir = read(".claude/settings.json"), ROOT / ".claude/hooks"
    if settings is None or not hooks_dir.is_dir():
        return skip("hook-wiring", ".claude/settings.json", ".claude/hooks/")

    try:
        json.loads(settings)
    except json.JSONDecodeError as exc:
        return [Finding("hook-wiring", MISSING, f"settings.json does not parse: {exc}")]

    registered = set(re.findall(r"\.claude/hooks/([A-Za-z0-9._-]+)", settings))
    on_disk = {p.name for p in hooks_dir.iterdir() if p.suffix in (".sh", ".py")}

    findings: list[Finding] = []
    mute = sorted(on_disk - registered - NON_HOOKS)
    if mute:
        findings.append(Finding("hook-wiring", MISSING, "on disk, registered nowhere — installed but mute",
                                [f".claude/hooks/{name}" for name in mute]))
    ghost = sorted(registered - on_disk)
    if ghost:
        findings.append(Finding("hook-wiring", MISSING, "registered in settings.json, absent from disk",
                                [f".claude/hooks/{name}" for name in ghost]))
    # A shell hook without +x fails open: Claude Code reports the error, the
    # guardrail does not run, and the write goes through.
    unarmed = sorted(n for n in registered & on_disk if n.endswith(".sh") and not (hooks_dir / n).stat().st_mode & 0o111)
    if unarmed:
        findings.append(Finding("hook-wiring", MISSING, "registered but not executable",
                                [f".claude/hooks/{name}" for name in unarmed]))
    if not findings:
        findings.append(Finding("hook-wiring", OK, f"{len(registered)} registered, {len(NON_HOOKS & on_disk)} standalone"))
    return findings


def check_shipped_paths() -> list[Finding]:
    """Every `.claude/**` path a doc names must exist. Paths under docs/ are not
    checked: `CLAUDE.md` declares them produced by the loop, so absent is normal."""
    seen: dict[str, str] = {}
    for doc in scanned_docs():
        rel_doc = doc.relative_to(ROOT).as_posix()
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            for raw in re.findall(r"\.claude/[A-Za-z0-9._/*-]+", line):
                path = raw.rstrip("./`,;:)")
                if path in RUNTIME_PATHS:
                    continue
                # A glob is a legitimate way to name a family of files
                # (`patterns/edge-function*.md`): one match is enough.
                if "*" in path:
                    if any(ROOT.glob(path)):
                        continue
                elif (ROOT / path).exists():
                    continue
                seen.setdefault(path, f"{rel_doc}:{number}")

    broken = {p: site for p, site in seen.items() if not shipped_by_addon(Path(p).name)}
    from_addon = sorted(set(seen) - set(broken))

    findings: list[Finding] = []
    if broken:
        findings.append(Finding("shipped-paths", MISSING, f"{len(broken)} path(s) named by a doc, absent from disk",
                                [f"{path}   ({site})" for path, site in sorted(broken.items())]))
    if from_addon:
        findings.append(Finding("shipped-paths", SKIP, f"{len(from_addon)} path(s) shipped by an addon, not installed here",
                                sorted(from_addon)))
    if not findings:
        findings.append(Finding("shipped-paths", OK, f"{len(scanned_docs())} docs scanned, every path resolves"))
    return findings


def check_command_references() -> list[Finding]:
    commands_dir = ROOT / ".claude/commands"
    if not commands_dir.is_dir():
        return skip("command-refs", ".claude/commands/")

    known = {p.relative_to(commands_dir).with_suffix("").as_posix().replace("/", ":")
             for p in commands_dir.rglob("*.md")}
    seen: dict[str, str] = {}
    for doc in scanned_docs():
        rel_doc = doc.relative_to(ROOT).as_posix()
        in_code = False
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("```"):
                in_code = not in_code
                continue
            # Inside a fence, `/app` is a route and `/bin/sh` a path — never a
            # command. Same verdict for a line carrying an HTTP verb: that is an
            # endpoint table, and the addon templates are full of them.
            if in_code or HTTP_VERBS.search(line):
                continue
            # Backticked only, for the same reason.
            for name in re.findall(r"`/([a-z][a-z0-9:-]*)`", line):
                if name not in known and name not in BUILTIN_COMMANDS:
                    seen.setdefault(name, f"{rel_doc}:{number}")

    addon_commands = {name: site for name, site in seen.items()
                      if name.startswith(ADDON_COMMAND_PREFIXES)
                      or shipped_by_addon(name.split(":")[-1] + ".md")}
    broken = {name: site for name, site in seen.items() if name not in addon_commands}

    findings: list[Finding] = []
    if broken:
        findings.append(Finding("command-refs", MISSING, f"{len(broken)} command(s) referenced, no file behind them",
                                [f"/{name}   ({site})" for name, site in sorted(broken.items())]))
    if addon_commands:
        findings.append(Finding("command-refs", SKIP, f"{len(addon_commands)} addon command(s), not installed here",
                                sorted("/" + name for name in addon_commands)))
    if not findings:
        findings.append(Finding("command-refs", OK, f"{len(known)} commands, every reference resolves"))
    return findings


def check_agent_references() -> list[Finding]:
    agents_dir = ROOT / ".claude/agents"
    if not agents_dir.is_dir():
        return skip("agent-refs", ".claude/agents/")

    known = {p.stem for p in agents_dir.glob("*.md")}
    known |= {"general-purpose", "explore", "plan", "claude"}  # Claude Code's own
    seen: dict[str, str] = {}
    for doc in scanned_docs():
        rel_doc = doc.relative_to(ROOT).as_posix()
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            # Only where the word "agent" is adjacent — anything looser matches prose.
            names = re.findall(r"`([a-z][a-z0-9-]{2,})`\s+agents?\b", line)
            names += re.findall(r"\bagents?\s+`([a-z][a-z0-9-]{2,})`", line)
            names += re.findall(r'subagent_type:\s*"?([a-z][a-z0-9-]+)"?', line)
            for name in names:
                if name not in known:
                    seen.setdefault(name, f"{rel_doc}:{number}")

    if seen:
        return [Finding("agent-refs", MISSING, f"{len(seen)} agent(s) referenced, no file behind them",
                        [f"{name}   ({site})" for name, site in sorted(seen.items())])]
    return [Finding("agent-refs", OK, f"{len(known - {'general-purpose', 'explore', 'plan', 'claude'})} agents, every reference resolves")]


def check_fill_markers() -> list[Finding]:
    targets = [ROOT / "CLAUDE.md"]
    for folder in (".claude/rules", ".claude/commands", ".claude/skills/templates", ".claude/skills/patterns"):
        targets += sorted((ROOT / folder).rglob("*.md")) if (ROOT / folder).is_dir() else []

    # The workflows are the only non-markdown thing shipped with a placeholder,
    # and it is the one that fails closed: `deploy.yml`'s `Publish` step is an
    # `exit 1` until a target is named. Scanning only `*.md` reported "no
    # placeholder left" on a project whose CD could not deploy — the marker was
    # there, in a file nothing looked at.
    for folder in ("templates/github", ".github/workflows"):
        targets += sorted((ROOT / folder).rglob("*.yml")) if (ROOT / folder).is_dir() else []

    counts: list[str] = []
    total = 0
    for path in targets:
        # This command's own doc explains the marker; it does not carry one.
        if not path.is_file() or path == ROOT / ".claude/commands/kit/doctor.md":
            continue
        hits = len(re.findall(r"\bFILL\b", path.read_text(encoding="utf-8")))
        if hits:
            total += hits
            counts.append(f"{path.relative_to(ROOT).as_posix()}   ({hits})")
    if not total:
        return [Finding("fill-markers", OK, "no placeholder left")]
    return [Finding("fill-markers", FILL, f"{total} placeholder(s) in {len(counts)} file(s)", counts)]


def check_hook_prerequisites() -> list[Finding]:
    """`jq` is on PATH, because every guardrail hook parses its stdin with it.

    Not a twin — a prerequisite, and the only one whose absence is INVISIBLE.
    Under `set -e`, a missing jq aborts the hook at rc 127, and a PreToolUse hook
    blocks on exit 2 only: the freeze, the test-first gate and the shell-write
    guard all read as "allow", with no message anywhere. The hooks now fail
    closed (`cwk_require_jq` in hook-lib.sh), which turns the silence into a
    refusal — this check is what turns the refusal into a sentence you can act
    on before it fires mid-edit.

    README lists jq as a prerequisite and nothing verified it, which is how a
    documented requirement becomes an assumption.
    """
    import shutil

    hooks = ROOT / ".claude" / "hooks"
    guarded = sorted(p.name for p in hooks.glob("*.sh")
                     if "cwk_require_jq" in (p.read_text(errors="replace")))
    if shutil.which("jq"):
        return [Finding("hook-prerequisites", OK,
                        f"jq present — {len(guarded)} hook(s) fail closed without it")]
    return [Finding("hook-prerequisites", MISSING,
                    "jq is NOT on PATH — every guardrail hook refuses instead of guarding",
                    [f".claude/hooks/{name}" for name in guarded]
                    + ["install it: apt install jq / brew install jq / dnf install jq"])]


def check_settled_ledger() -> list[Finding]:
    """The settled facts live in one cold file, and no rule grows a copy.

    They used to sit in `.claude/rules/01-stack.md`, which every session and
    every subagent reads in full — ~2 300 tokens of cache that only `/research`
    and `doc-researcher` ever consult — and which `addons/supabase/` REPLACES on
    install, silently deleting every answer the loop had paid to establish.

    Moving them to `docs/research-cache/settled.md` fixes both at once: no addon
    touches `docs/`, and no session pays for them. This check exists to stop the
    regrowth — a dated table reappearing in any rule file, core or addon.
    """
    ledger = read("docs/research-cache/settled.md")
    if ledger is None:
        return [Finding("settled-ledger", MISSING,
                        "docs/research-cache/settled.md — the ledger the rules point at")]

    dated = re.compile(r"^\| (.+?) \| .+? \| \d{4}-\d{2}-\d{2} \|$", re.M)
    rows = len(dated.findall(ledger))
    if rows == 0:
        return [Finding("settled-ledger", MISSING,
                        "the ledger carries no dated row — did the table move again?")]

    regrown = []
    for path in sorted(ROOT.glob(".claude/rules/*.md")) + sorted(ROOT.glob("addons/*/rules/*.md")):
        text = path.read_text(encoding="utf-8", errors="replace")
        n = len(dated.findall(text))
        if n:
            regrown.append(f"{path.relative_to(ROOT)}  →  {n} dated row(s), hot in every session")
    if regrown:
        return [Finding("settled-ledger", DIVERGENCE,
                        "a rule file grew a settled-facts table again", regrown)]
    return [Finding("settled-ledger", OK, f"{rows} row(s), cold, no rule copy")]


def check_rules_loaded() -> list[Finding]:
    """The `@` lines in CLAUDE.md are the loader. Nothing else walks rules/.

    There is no SessionStart hook in this kit: Claude Code reads CLAUDE.md and
    the files it imports. A rule dropped into `.claude/rules/` without an `@`
    line never reaches a session, and nothing says so — the failure is a
    guardrail everyone believes is on.
    """
    claude = read("CLAUDE.md")
    if claude is None:
        return skip("rules-loaded", "CLAUDE.md")

    imported = set(re.findall(r"@(\.claude/rules/[\w.-]+\.md)", claude))
    on_disk = {str(p.relative_to(ROOT)) for p in ROOT.glob(".claude/rules/*.md")}

    findings = []
    for orphan in sorted(on_disk - imported):
        findings.append(Finding("rules-loaded", MISSING,
                                f"{orphan} is on disk and never loaded — add its @ line to CLAUDE.md"))
    for ghost in sorted(imported - on_disk):
        if shipped_by_addon(Path(ghost).name):
            continue
        findings.append(Finding("rules-loaded", MISSING,
                                f"CLAUDE.md imports {ghost}, which does not exist"))
    return findings or [Finding("rules-loaded", OK, f"{len(imported)} rule(s) imported, all present")]


def check_rules_budget() -> list[Finding]:
    """Every loaded file declares a line budget, and stays under it.

    These files are re-read in full by every session AND by every subagent, so a
    paragraph added here is a paragraph multiplied by the fan-out of the loop.
    Nothing else in the kit measures the one cost that is paid unconditionally.
    Passing a budget is a decision: raise the number in the same commit and say
    what it bought. A file with no budget line is the same gap as an agent with
    no model row — nobody priced it.
    """
    header = re.compile(r"^<!-- budget: (\d+) lines\b")
    targets = sorted(ROOT.glob(".claude/rules/*.md")) + sorted(ROOT.glob("addons/*/rules/*.md"))
    claude = ROOT / "CLAUDE.md"
    if claude.exists():
        targets.insert(0, claude)
    if not targets:
        return skip("rules-budget", "CLAUDE.md", ".claude/rules/*.md")

    findings, total, chars, budgeted = [], 0, 0, 0
    for path in targets:
        rel = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = len(text.rstrip("\n").split("\n"))
        hot = not rel.startswith("addons/")
        if hot:
            total += lines
            chars += len(text)
        m = header.match(text)
        if not m:
            findings.append(Finding("rules-budget", MISSING,
                                    f"{rel} declares no budget ({lines} lines)"))
            continue
        budgeted += 1
        budget = int(m.group(1))
        if lines > budget:
            findings.append(Finding("rules-budget", OVER,
                                    f"{rel}: {lines} lines, budget {budget} (+{lines - budget})",
                                    ["raise the number in this commit and say what it bought,",
                                     "or move the overflow — hook deny text, pattern, or guide"]))
    findings.append(Finding("rules-budget", OK,
                            f"session floor: {total} lines / {chars} chars loaded "
                            f"unconditionally (~{chars // 4 // 100 * 100} tokens per session "
                            f"and per subagent), {budgeted} file(s) budgeted"))
    return findings


CHECKS = [
    ("twins", [check_protected_dirs, check_data_client, check_composition_roots,
               check_shared_dirs,
               check_coverage_floor, check_coverage_holes, check_token_thresholds,
               check_tdd_layers, check_gate_allowlist, check_ci_scripts,
               check_workflow_names, check_agent_models, check_settled_ledger]),
    ("budget", [check_rules_loaded, check_rules_budget]),
    ("wiring", [check_hook_prerequisites, check_hook_wiring]),
    ("links", [check_shipped_paths, check_command_references, check_agent_references]),
    ("placeholders", [check_fill_markers]),
]


def main() -> int:
    print(f"kit-doctor · {ROOT}")
    if is_kit_source():
        print("  mode: kit source — FILL markers here are the template's own placeholders\n")
    else:
        print("  mode: installed project — a FILL left here is an unfinished adaptation\n")

    findings: list[Finding] = []
    for section, checks in CHECKS:
        print(section.upper())
        for check in checks:
            for finding in check():
                findings.append(finding)
                label = finding.status if finding.status != OK else "ok"
                print(f"  {label:<11} {finding.check:<23} {finding.summary}")
                for line in finding.evidence:
                    print(f"                                  {line}")
        print()

    failing = [f for f in findings if f.status in FAILING]
    notes = [f for f in findings if f.status == FILL]
    if failing:
        print(f"{len(failing)} divergence(s) — each one is two files that must move together.")
    else:
        print("No divergence.")
    if notes:
        print(f"{len(notes)} placeholder finding(s) — informational.")
    return 1 if failing else 0


if __name__ == "__main__":
    raise SystemExit(main())
