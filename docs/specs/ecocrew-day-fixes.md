# Spec: EcoCrew day fixes — stash, fix-base, case ids, Python freeze imports, route JSON shapes
Token profile: critical
Validation: auto

## Objective
Close the five kit frictions verified on EcoCrew on 2026-11-26 (stories 4.5, 3.1, 3.7, 3.2, 3.3), so none of them can silently cost work, a gate or an extra arbiter again.

## Scope
- IN :
  1. **git stash guard.** `enforce-git-workflow.sh` asks on a `git stash` (bare, `push`, `save`, `-q`, inside a chained command) when the tree has tracked changes; in auto mode that ask is a blocked-stop deny, so it never passes silently. `stash list`, `stash show` and a stash with no tracked change pass as today; `clear`/`drop` keep their current behaviour.
  2. **fix-base written by the route.** `kit-gate-route.py route` on a review round whose `next` is `fix-batch` writes `docs/work/<slug>/fix-base` itself (same content as `snapshot`) when none exists for that round, and says so in its output; `orchestrate.md` says the route does it. A later round's `fix` diff therefore always has a base.
  3. **Case ids, any case.** The arbiter ledger (`loop-record.py` `ledger_entry`) and the `.tdd-unfrozen` line check (`protect-files.sh`) accept a lowercase id (`b204`) and normalise it to uppercase (`B204`), as the freeze side already does. A malformed verdict block makes `subagent_stop` emit a message naming the field that failed (no silent drop). `arbiter.md` states the id format and the `test_b204_… → B204` mapping.
  4. **Python freeze: import lines at the head.** `tdd-freeze-tests-py.py` accepts whole `import x` / `from x import a, b` lines added to the import head of a frozen test file when an unfreeze verdict backs that file, as the TS freeze's `import_additions` does: no existing line changed or removed, no name already bound in the file, also in rows mode. `arbiter.md:44-51` is corrected so its Python statement is true.
  5. **Route and audit JSON shapes.** `review.md`, `plan.md` and `ship.md` each carry one literal JSON skeleton (envelope + one finding) with the allowed values of `mode`, `status`, `dimension`, `kind`, `p1_class`, and `{"findings": [...]}` for the audit file. `plan-critic.md` emits `not-fixed`. `kit-gate-route.py` and `kit-audit-surface.py` errors name the fix (e.g. "a fixed or refuted finding is dropped before the route", "a vigilance finding takes p1_class null", "wrap the list as {\"findings\": [...]}").
  6. **`.tdd-unfrozen` comment-out wording.** `ship.md` says a comment-out is the bare `# ` prefix of the exact line, nothing else; `protect-files.sh` gives a non-verbatim `#` line its own deny text instead of "no unfreeze verdict backs this entry".
- OUT : the screenshot step cap and its late detection; the stacked-base retarget at ship; the english-comments French-string false positive; the review stage 0 `run` obligation; the Codex sandbox preflight; the kit-cwd deny text; any EcoCrew project change (its overlay, project.json).

## Data model
none

## Custom backend
NONE — kit hooks, scripts and prompts only.

## Front surface
none

## Acceptance criteria
- [ ] In a fixture repo with a modified tracked file, `git stash`, `git stash -q`, `git stash push -m x` and `ruff check . && git stash -q` are asked (denied with the blocked-stop reason in auto mode); with no tracked change, and for `git stash list` / `git stash show`, the guard passes.
- [ ] `kit-gate-route.py route` on a review route file whose result is `fix-batch` creates `docs/work/<slug>/fix-base` when absent and reports it; a second call does not overwrite it; `diff … fix` then works without a manual `snapshot`.
- [ ] An arbiter verdict block with `case: b204` is ledgered as `B204`; the `.tdd-unfrozen` line `<path>  # b204: <reason>` backed by it is accepted; a block missing `sha256` produces a visible message naming the field, and records nothing.
- [ ] In a frozen Python test file backed by an unfreeze verdict, an Edit adding `from datetime import UTC` to the import head passes; the same addition without a verdict, an edit changing an existing import line, and an added import of a name already bound in the file are refused; this holds when the file is in rows mode.
- [ ] `review.md`, `plan.md`, `ship.md` hold a JSON skeleton that `kit-gate-route.py route` / `kit-audit-surface.py follow-ups` accepts as written (a contract test feeds each skeleton to its script); `plan-critic.md` names `not-fixed`; the three named error cases print the fix.
- [ ] `ship.md` defines comment-out as the bare `# ` prefix; an annotated `#` line in `.tdd-unfrozen` is denied with a text that names the comment-out format.
- [ ] Every existing hook fixture, contract and suite stays green (`test-hooks.sh`, `test-workflow-contracts.sh`, `test-gate-route.sh`, `test-audit-surface.sh`, the fastapi addon fixtures, `kit-doctor.py`).

## Business logic to cover
- The stash classifier: which stash forms count as putting tracked work aside, detection of tracked changes, the auto-mode deny, chained commands.
- Route writing fix-base once per round, never overwriting.
- Case-id normalisation on both the ledger and the `.tdd-unfrozen` check, and the malformed-block message.
- The Python import-head allowance: verdict required, additions only, no rebinding, rows mode included.
- Error texts of both scripts naming the fix; the skeletons accepted by the scripts.
- The `.tdd-unfrozen` comment-out recognition and its distinct deny.
