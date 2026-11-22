#!/usr/bin/env python3
# cwk-guard-api: 1
#
# Hook: enforce-architecture
# Event: PreToolUse (Write|Edit)
# Purpose: Block the architecture violations that are mechanically detectable
#          with near-zero false positives. See .claude/rules/02-architecture.md
#
#   1. Cross-feature import   : features/A importing features/B (A != B)
#   2. Client outside layer   : importing the data client anywhere other than
#                               the data layer or the composition root
#   3. Shared -> feature      : src/components|hooks|lib|types|stores|config importing
#                               features/* (the arrow points one way). NOT
#                               providers/ nor routes/: they are wiring, and
#                               wiring may know what it composes (SHARED_DIRS).
#
# Anything ambiguous (business logic in components, `as` casts, ...) is NOT
# enforced here on purpose: that is what caused over-blocking before.
#
# NOTE: on Edit, only the inserted delta (new_string) is inspected, not the whole
#       file. A cross-feature import or a client import already present elsewhere in
#       the file passes through here — backstop = reviewer agent (correctness).

import sys
import json
import re
import posixpath
import os
import time
import atexit

# --- timing ------------------------------------------------------------------
# Python twin of hook-lib.sh: a hook that is never measured looks free. Same log,
# same TSV columns, so hook-timings-report.sh reads both without knowing which
# language wrote the line. Off with CWK_HOOK_TIMING=0.
if os.environ.get("CWK_HOOK_TIMING", "1") == "1":
    _T0 = time.time()

    def _record() -> None:
        log = os.path.join(
            os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".claude", ".hook-timings.log"
        )
        try:
            with open(log, "a") as fh:
                fh.write(
                    "%d\t%s\t%d\t%s\t%s\n"
                    % (_T0 * 1000, "enforce-architecture", (time.time() - _T0) * 1000,
                       "-", "-")  # exit code and path: not worth threading through
                )
        except OSError:
            pass

    atexit.register(_record)


def _log_health_deny(reason: str, file_path: str = "") -> None:
    """One JSONL line per real refusal — read back by
    kit-doctor.py check_kit_health. Best-effort: never lets an observability write turn into
    a second reason to fail a call already being denied."""
    if os.environ.get("CWK_HEALTH_LOG") == "0":
        return
    log = os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".claude", ".kit-health.jsonl")
    try:
        with open(log, "a") as fh:
            fh.write(json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "source": "hook:enforce-architecture",
                "event": "deny",
                "reason": reason,
                "file": file_path,
            }) + "\n")
    except OSError:
        pass

# --- configuration -----------------------------------------------------------
CLIENT = {}
DEGRADED = []
CONFIG_REASONS = {
    3: ".claude/project.json is invalid or could not be read",
    4: ".claude/project.json is missing",
    5: ".claude/project.json cannot be found: CLAUDE_PROJECT_DIR is not an absolute path",
    6: ".claude/project.json cannot be read: python3 or .claude/hooks/project_config.py is missing",
}
CONFIG_TAIL = (", so the hooks run on the kit defaults and ask instead of passing. Restore it: "
               "rerun install.sh on this project, or /kit:init.")
# Shared leaf directories that must never depend on a feature (check 3).
# `providers/` and `routes/` are deliberately NOT here: they are wiring, and
# wiring is allowed to know the features it composes.
# `stores/` IS here: an app-level Zustand store (theme, sidebar) is shared leaf
# code like any other — a store that imports a feature is a store that cannot be
# read by another one. Feature-owned stores live in features/*/stores/ and are
# covered by check 1 instead. See .claude/rules/04-state.md.
# `config/` IS here too, and it was the one directory the structure diagram
# listed while both import lists forgot it — so a config file naming a feature
# passed without a word. Config is leaf code by definition: everything reads it,
# it reads nothing back. Route *wiring* that needs a feature belongs in
# src/routes/, which is deliberately not in the `shared_dirs` list of .claude/project.json.
# -----------------------------------------------------------------------------

# Matches `from "x"`, `import "x"`, `import("x")` and `require("x")`.
SPECIFIER_RE = re.compile(
    r"""(?:from|import|require)\s*\(?\s*['"]([^'"]+)['"]"""
)


def load_config() -> None:
    """Fill CLIENT (`module`, `own_path`, `composition_roots`, `shared_dirs`) from
    `.claude/project.json`, or from the reader's kit defaults when the file cannot be read;
    the config reason then lands in DEGRADED. With no reader at all CLIENT stays empty, and
    the hook asks."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import project_config
    except ImportError:
        DEGRADED.append(CONFIG_REASONS[6] + CONFIG_TAIL)
        return
    except Exception:
        DEGRADED.append(CONFIG_REASONS[3] + CONFIG_TAIL)
        return
    try:
        client = project_config.load_strict(os.environ.get("CLAUDE_PROJECT_DIR", "")).data_client
    except project_config.ConfigError as error:
        DEGRADED.append(CONFIG_REASONS.get(error.status, CONFIG_REASONS[3]) + CONFIG_TAIL)
        client = project_config.DEFAULTS["data_client"]
    except Exception:
        DEGRADED.append(CONFIG_REASONS[3] + CONFIG_TAIL)
        return
    CLIENT.update(module=client["module"], own_path=client["own_path"],
                  composition_roots=tuple(client["composition_roots"]),
                  shared_dirs=tuple(client["shared_dirs"]))


def decide(decision: str, reason: str) -> None:
    if DEGRADED:
        reason = f"{reason}\n\n{DEGRADED[0]}" if reason else DEGRADED[0]
    if decision == "deny":
        _log_health_deny(reason)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def deny(reason: str) -> None:
    decide("deny", reason)


def done() -> None:
    """The end of a check that found nothing: a pass, or an ask when degraded."""
    if DEGRADED:
        decide("ask", "")
    sys.exit(0)


def target_path(spec, rel):
    """The src-relative path a specifier points at, or None.

    Relative specifiers are resolved against the importing file's directory, so
    `../../b/services/b.repository` from `features/a/hooks/` resolves to
    `features/b/services/b.repository`. Aliased ones just lose their prefix.
    Bare package imports return None.
    """
    if spec.startswith("./") or spec.startswith("../"):
        return posixpath.normpath(posixpath.join(posixpath.dirname(rel), spec))
    for prefix in ("@/", "~/", "src/"):
        if spec.startswith(prefix):
            return spec[len(prefix):]
    return None


def feature_of(spec, rel):
    """Feature name a specifier points at, or None.

    Requires `features/` to be the FIRST segment of the resolved path — so
    `@/components/features/Card` is not a cross-feature import.
    """
    target = target_path(spec, rel)
    if target is None:
        return None
    m = re.match(r"features/([^/]+)", target)
    return m.group(1) if m else None


def main() -> None:
    try:
        data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_input = data.get("tool_input", {}) or {}
    path = tool_input.get("file_path", "") or ""
    content = tool_input.get("content") or tool_input.get("new_string") or ""
    if not path or not content:
        sys.exit(0)

    p = path.replace("\\", "/")

    # Only enforce on app source (src/). Edge functions, scripts, docs are skipped.
    idx = p.rfind("src/")
    if idx == -1:
        sys.exit(0)
    rel = p[idx + len("src/"):]

    # Only TS/TSX, and never on tests (they mock/import freely).
    if not re.search(r"\.(ts|tsx)$", rel) or re.search(r"\.test\.tsx?$", rel):
        sys.exit(0)

    load_config()
    specs = [m.group(1) for m in SPECIFIER_RE.finditer(content)]

    # --- Check 1: cross-feature import (needs no config, so it runs without a reader) ---
    feat = re.match(r"features/([^/]+)/", rel)
    if feat:
        current = feat.group(1)
        for spec in specs:
            other = feature_of(spec, rel)
            if other and other != current:
                deny(
                    f"Cross-feature import blocked: features/{current} imports "
                    f"features/{other} ({spec}).\n\n"
                    "Shared code must live in shared/, src/components/, src/lib/, "
                    "src/hooks/, src/types/ or src/providers/. See .claude/rules/02-architecture.md."
                )

    if not CLIENT:
        done()

    # --- Check 3: shared code depending on a feature ------------------------
    if rel.startswith(CLIENT["shared_dirs"]):
        for spec in specs:
            other = feature_of(spec, rel)
            if other:
                deny(
                    f"Shared code depends on a feature: {rel} imports "
                    f"features/{other} ({spec}).\n\n"
                    "src/components, src/hooks, src/lib, src/types, src/stores and src/config are imported BY "
                    "features, never the reverse. Move the shared piece down, or keep the "
                    "wiring in the route/page — src/routes and src/providers are wiring and "
                    "MAY import a feature. See .claude/rules/02-architecture.md."
                )

    # --- Check 2: data client outside gateway/services/composition root -----
    module = CLIENT["module"]
    base = rel.rsplit("/", 1)[-1]
    allowed = (
        base.endswith(".gateway.ts")
        or base == "services.ts"
        or rel == CLIENT["own_path"]
        or rel in CLIENT["composition_roots"]
    )
    if allowed:
        done()

    for spec in specs:
        target = target_path(spec, rel)
        if target == module or re.search(
            r"(?:^|/)%s$" % re.escape(module), spec
        ):
            deny(
                f"Data client imported outside the data layer ({rel}).\n\n"
                "DB/API calls belong in gateway.ts (or services.ts if the feature is not "
                "split). hooks.ts calls the repository; providers, guards and route helpers "
                "call a repository too — never the client.\n"
                f"Only the composition root may hold the instance: {', '.join(CLIENT['composition_roots'])}. "
                "See .claude/rules/02-architecture.md."
            )

    done()


if __name__ == "__main__":
    main()
