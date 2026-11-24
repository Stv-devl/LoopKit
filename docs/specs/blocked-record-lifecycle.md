# Spec: blocked-record lifecycle (auto-mode review R6 + R7)
Token profile: critical
Validation: auto

Source: review findings R6 and R7 of `auto-mode-trial-fixes` (PR #18, review gate BLOCKED 3/3, shipped as
known limits): `docs/work/auto-mode-trial-fixes/route-review-3.json`, design in
`docs/work/auto-mode-trial-fixes/follow-ups.md` ("Next pass"). Framing note: the user chose `auto` knowing
that auto mode denies every kit-code write (V8) and that the last pass hit a blocked stop at its first
EXECUTE write.

## Objective
A blocked auto pass can never resume in auto or reach a push/PR ask nobody answers, and the user's lift
keeps the arbiter verdicts and the guarded-file ledger so the later PR still shows every decision the
auto segment took.

## Scope
- IN :
  1. `loop-record.py --mode` prints a third state, `blocked`, for a record marked `blocked` (auto
     otherwise valid); `auto`/`moi` unchanged.
  2. `/loop:orchestrate` Phase 0 step 2 opens, before branching on `phase:`, with `--mode`; `blocked` →
     stop before any phase, write nothing, tell the user to run `--release`. The "--mode alone decides"
     paragraph, step 3's "else take it back" for a `BLOCKED` board line, and `auto-mode.md`'s "a restart
     resumes in the recorded mode" carve out the blocked record.
  3. `./workflow.sh` / `workflow.py` refuse to launch on a blocked record of the tree: print the cause
     and `python3 .claude/hooks/loop-record.py --release`, start no session.
  4. New user-only `loop-record.py --release`: on a blocked v1 record, mode → `moi`, `blocked` dropped,
     `released_at` set, `verdicts`, `guarded`, `rows` and their `.tdd-unfrozen` lines kept. No-op on a
     non-blocked or absent record. Off every allowlist (shell guard, `settings.json`, `install.sh`), so the
     agent's own call is denied in auto and asks in moi.
  5. A released record: `record_allow` refuses it (push and PR ask; the user is there);
     `--guarded-block` still emits the `Guarded files touched` block, and the github agent's
     `Decided without you` still comes from its verdicts; the git hook's byte check of the block applies
     to it as in auto.
  6. Docs: orchestrate.md (blocked stop, Validation mode, Phase 0), ship.md, github.md, auto-mode.md,
     README.md name `--release` as the lift and say `--clear` deletes the record and its ledger.
- OUT :
  - `--clear` behaviour (stays the full delete, closing check included).
  - The minors of the last pass (m1-m15: contorted `gh` forms, `-w=true`, `--block` silent no-op,
    test-needle weaknesses) and the other follow-ups (Python freeze twin, native gh allows, kit-code
    writes in auto).
  - Any hook setting the `blocked` mark by itself (the agent still runs `--block`).

## Data model
`.claude/.loop-record.json` (v1): new optional field `released_at` (ISO time); `blocked`/`blocked_at`
already exist. No version bump.

## Custom backend
NONE — kit hooks, launcher and prompts only.

## Front surface
none (kit repo, no UI).

## Acceptance criteria
- [ ] AC1: with a v1 auto record marked `blocked` on its branch, `loop-record.py --mode` prints `blocked`;
  unmarked it prints `auto`; no record prints `moi`.
- [ ] AC2: `./workflow.sh` on a tree whose record is blocked exits non-zero without starting a session
  and prints `loop-record.py --release`.
- [ ] AC3: `orchestrate.md` Phase 0 step 2 runs `--mode` before branching on `phase:` and stops on
  `blocked`; no kit doc still says a blocked record resumes in auto or that a gate go lifts it
  (contract greps).
- [ ] AC4: `loop-record.py --release` on a blocked record leaves a record with mode `moi`, no `blocked`,
  a `released_at`, and the same `verdicts`, `guarded` and `rows`; `.tdd-unfrozen` lines unchanged.
- [ ] AC5: the agent's `python3 .claude/hooks/loop-record.py --release` is denied in auto (shell guard)
  and has no allow entry in `settings.json` / `install.sh`.
- [ ] AC6: on a released record, `git push -u origin <branch>` and the exact-form `gh pr create` ask;
  `--guarded-block` prints the block with the ledger rows; a `gh pr create` body missing that block is
  refused as in auto.
- [ ] AC7: `--clear` still deletes any record, blocked or released.
- [ ] AC8: every kit suite green (`.claude/hooks/test-*.sh`, fastapi `test_imported_symbols.py`).

## Business logic to cover
- `--mode` three states and their precedence (invalid record → `moi`, blocked → `blocked`).
- `--release` transitions: blocked → released (ledger kept), non-blocked/absent → no-op, locked and
  atomic write.
- `record_allow` refuses blocked and released records; `guarded_block` emits for auto and released.
- Launcher refusal on a blocked record.
- Shell guard: `--release` not a manual form the agent may run.
