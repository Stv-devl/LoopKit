# Plan: tmp-glob-escape (bug)

Token profile: critical
Entry: docs/work/tmp-glob-escape/debug.md
Pipeline: BUG

## Contracts
`prevent-destructive-commands.sh` shell write guard, verbs `>`, `>>`, `mv`, and
`GUARD_SOURCE_WRITERS`:
- C1. A target under `/tmp` keeps the `/tmp` exemption only when it has no `..` path
  component. A `/tmp` target with `..` (glob or not) is not exempt: it is resolved like any
  other path, or asks as unresolved when it cannot be resolved.
- C2. `/dev/fd/*` is exempt only for `/dev/fd/0`, `/dev/fd/1`, `/dev/fd/2` exactly. Any other
  `/dev/fd/<n>` or a sub-path under it asks.
- C3. `/dev/null`, `/dev/stdout`, `/dev/stderr`, `/tmp/<name>`, `/tmp/<dir>/<name>` and a
  `/tmp` glob without `..` (e.g. `/tmp/*.log`) keep passing.

## Reproduction cases (test-hooks.sh, pure additions after CG53, `pd_probe` + `g15_expect`)
The probe project is the fixture's `CLAUDE_PROJECT_DIR`; `<UP>` is a `/tmp/<glob>/../..`
prefix (glob in a segment, e.g. `/tmp/*/../..` or the real tmp segment spelled with `*`)
that resolves to `/` in real bash, followed by the project's absolute path.

| Id | Command | Expected |
| --- | --- | --- |
| CG54 | `echo x > <UP><project>/.claude/settings.json` | not pass (ask or deny) |
| CG55 | `echo x > <UP><project>/src/a.py` | not pass |
| CG56 | `echo x > <UP><project>/src/a.utils.t?` | not pass |
| CG57 | `echo x > /tmp/../<project-without-leading-slash>/src/a.py` (no glob) | not pass |
| CG58 | `exec 9<"<project>"; echo x > /dev/fd/9/.claude/settings.json` | ask |
| CG59 | `echo x > /dev/fd/9` | ask |
| CG60 | each of `echo x > /tmp/out.txt`, `echo x > /tmp/d/out.txt`, `echo x > /tmp/*.log`, `echo x > /dev/fd/2`, `echo x > /dev/null` | pass |

CG54-CG59 fail today (verdict pass); CG60 passes today and pins C3.

## Gate
- 2026-11-11 test plan: **go** (C1-C3, CG54-CG60 as written).
