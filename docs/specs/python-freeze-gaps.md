# Spec: Python freeze insertion gaps
Token profile: economy
Validation: moi

## Objective
The FastAPI addon's frozen-test hook refuses an inserted block that changes what
an existing frozen case runs, and stops refusing a harmless head import.

## Context (verified 2026-11-27 at 7ebc764, traced in code; live run blocked by the shell guard)
- F1 `insertion_refusal` (addons/fastapi/hooks/tdd-freeze-tests-py.py:175-250)
  never checks the names an inserted block binds: appending, after the last case,
  `from app.services.c import g` or a same-name helper/fixture rebinds `g` for the
  frozen cases above, and is allowed. The head-import path already refuses this
  (`tdd_py_lib.py:772-774`, `bound & present`).
- F2 `enclosing_case_indent` (:77-101) checks only the added block's indent, not
  that the anchor is the case's last line: a new case inserted after a mid-case
  line moves the remaining lines of the frozen case into the new one.
- F3 a head import whose anchor sits below the line after the last import (e.g. a
  `# helpers` comment) is refused by `without_head_imports` (tdd_py_lib.py:781)
  and then by the plain path ("no assertion of its own"); the deny text does not
  name the working anchor.
- Source: docs/work/ecocrew-day-fixes/follow-ups.md (#1, #7, #14, #15).

## Scope
- IN : F1, F2, F3 — Python hook and lib only, with fixtures.
- OUT: lone `\r`, `replace_all` anchors, dunder imports, importorskip helpers,
  misscanned headers (known limits under the careless-agent threat model); the
  TypeScript freeze hook.

## Data model
none

## Custom backend
NONE — kit hook.

## Front surface
none.

## Acceptance criteria
- [ ] An insertion that binds at top level a name referenced by an existing case
      (import, assignment, def, fixture) is denied with a message naming it; a
      new case binding fresh names is still allowed.
- [ ] A new case inserted after a line that is not the last of a frozen case is
      denied; the same case after the last line is allowed.
- [ ] A pure head import anchored on a comment or blank line just below the
      imports is allowed (or, if kept refused, the deny names the last-import
      anchor that works).
- [ ] Each case fails on the current hook where the defect exists; all existing
      fixtures stay green.

## Business logic to cover
- names bound by an inserted block vs names used by frozen cases.
- anchor-is-last-line rule for inserted cases.
- head region boundary for import-only edits.
