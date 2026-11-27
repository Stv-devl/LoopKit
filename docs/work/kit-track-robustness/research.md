# Research: kit-track robustness   (entry: docs/specs/kit-track-robustness.md)
Token profile: standard

## Pattern to follow
- Refusals in kit-track.py are `raise Refused(<reason>)` → stderr `kit-track: <reason>`, exit 2
  (`main` :374-380; argparse errors mapped too, :46-48). Uncaught exceptions = traceback, exit 1.
- Close already computes its whole plan before writing (`Closing` :248-294, plan :318-329) and
  checks targets first (symlink_in :330-334, tracked :335-338): the same "check, then act" shape
  extends to fork rollback and copy-back reporting.
- Suite style: `.claude/hooks/test-kit-track.sh` — `mkrepo` fixture (:59-111), `run_kt` (:113-118,
  sets OUT/ERR/CODE), `no_fork` (:122-126: no worktree, no branch), `close_fixture` (:260-274),
  `fail KT<n>`/`case_start`; highest id KT29 (:421), 31 cases.
- Contract pins: `pk <id> has|lacks|has_in|in_order …` (test-workflow-contracts.sh:1411-1416),
  WT family :1679-1720.

## Wiring points
- kit-track.py fork :181-217: checks (slug, main_root, kit_local :184, detached HEAD :187-189,
  dirty :191-193, tree exists :196-197, branch exists :198-199) → `ignored_only` :200 →
  `git worktree add` :202-204 → copy+hash loop :205-208 → snapshot write :209-210 → prints
  :211-217 (`env_slot` :217 last).
- walk :107-123: symlink refusal per child (:118-120) and top (:109-110) **before** `candidates`
  applies `skipped(rel)` (:133) and before `ignored_only` (:137-144).
- close :297-352: snapshot read `json.loads(...).get("files", {})` :307 (no validation) →
  merge check :309-311 → dirty :312-314 → plan → copy loop :339-345 (OSError → Refused "nothing
  removed" :340-343; verify mismatch → Refused :344-345) → reports printed only after the loop
  :346-347 → `git worktree remove` :348-350 → "closed"/"next:" :351-352.
- Lists: SKIP_DIRS :34, SKIP_NAMES :35-36, SKIP_PREFIXES :37 (`.token-`, `.eslint-queue`),
  SESSION_DOCS :38. kit-doctor RUNTIME_PATHS :872-879 (has `project.snapshot.json`,
  `project.proposed.json`); loop-record.py:280 temp `.claude/.loop-record.<rand>.tmp`;
  install.sh:644-665 `.ruff_cache/` (a gitignore entry).
- Prompts: tracks.md :22-39 (closing check; :38-39 `closed`→BLOCKED only, rest "one line"),
  :150-163 (kit-local fork + hand-over rule), :165-192 (bare add; :190-192 unscoped
  "enters at most one — EnterWorktree"), :196-203 hand-over template (no `cd … && ./workflow.sh`,
  no local-kit-env). orchestrate.md :166-168 (closed + `Approved`, orphaned stop), :235-239 step 4
  "Any exit other than /loop:ship step 5 gives it back → BLOCKED", :249-250 kit-local hand-over,
  :265-266 unscoped "This session drives it → EnterWorktree". docs/Claude_Workflows.md:690-692
  (French) same unscoped EnterWorktree. ship.md :229-252 closing order (not in spec list, consistent).
- next-feature-on-clear.py:124 (`.claude/worktrees` parent + `.kit-snapshot` → silent);
  test-small-lane.sh N3 :659-665, floor `CASES -lt 91` :674.
- settings.json:57 allows only `kit-track.py fork *`; WT9.2 pins no `close` allow.

## Reusable
- `Refused`, `registered` (:220-223), `symlink_in` (:238-245), `hash_or_none`, `sha256`.
- `git worktree remove <rel>` (no --force) already used by close :348; the copied kit files are
  git-ignored, so a fresh fork's tree stays clean and `remove` succeeds without --force.
- `git branch -d feat/<slug>` works right after a failed fork (branch sits at base).
- test helpers `no_fork`, `run_kt`, `close_fixture`; small-lane `check`, `write_board`.

## Blast radius
- kit-track.py is run by tracks.md / orchestrate.md / ship.md / 10-worktrees guide by command name
  only; the printed text callers depend on: `forked …`, the `cd <tree> && ./workflow.sh` line and
  `local-kit-env` block (tracks.md:162-163), `close` report lines, `next:` (unpinned).
- Pins that must stay green: WT1-WT15 (test-workflow-contracts.sh:1679-1720), KT1-KT29,
  test-small-lane N1-N3, kit-doctor DW6, test-install IW3.
- EcoCrew uses kit-local tracks (its `.claude/` is git-ignored).

## Live DB state
n/a

## External surface
n/a

## Traps (points of vigilance for the review)
- Rollback must never use `--force` or `rm -r`: `git worktree remove` then `git branch -d`; if the
  rollback itself fails, refuse with the exact manual commands, never a traceback.
- Rollback must not remove anything that existed before the fork (a pre-existing branch or tree is
  already refused earlier — keep that order).
- Symlink check moved after the filters must still refuse a symlink in what **is** copied, and a
  symlinked `.claude/` top.
- Snapshot validation must refuse before any write (close is otherwise "check, then act").
- Copy-back report: every file that landed is printed, even when a later copy fails; a rerun stays
  idempotent and reports the rest.
- `.loop-record.*.tmp` skip must not hide `.loop-record.json` handling (already skipped by name).
- Prompt edits must keep WT1-WT15 green and pin the new wording; docs/Claude_Workflows.md is
  French (user-facing doc), prompts English.
- KT ids: new cases take KT30+; KT15 is duplicated today (:298, :320) — do not reuse.

## Open questions
1. Copy-back (K4): print each report line as its copy lands (so a failure leaves every landed
   file reported), or pre-flight every target's writability first? Proposed: print as it lands,
   plus a pre-flight on the target dirs, report the remainder on failure.
2. Fork rollback (K1): on any exception after `git worktree add`, `git worktree remove <rel>`
   then `git branch -d feat/<slug>`, then refuse `fork failed after the worktree was created:
   <error>; rolled back`. If rollback fails, refuse naming the two commands to run. Proposed: yes.
3. Verify mismatch on close (:344-345) has no injection point short of a race. Proposed: cover the
   copy OSError path (read-only target dir) and leave verify mismatch to a review read, or add a
   test-only seam? Proposed: no seam; covered by reading.
4. Snapshot schema (K3): a dict with `files` a dict of relative path → 64-hex string; anything
   else → `malformed .kit-snapshot` refusal before any write. Proposed: yes.
5. K5 names: add `project.proposed.json`, `project.snapshot.json` (SKIP_NAMES), `.ruff_cache`
   (SKIP_DIRS), prefix `.loop-record.` (SKIP_PREFIXES, covers `.tmp`). Proposed: yes.
6. K6 scope: also fix docs/Claude_Workflows.md:690-692 (same unscoped EnterWorktree) though the
   spec names tracks.md and orchestrate.md only? Proposed: yes, same defect.
7. K7: wording — a kit-local hand-over is not an exit that gives the line back; the line stays
   `IN LOOP`, owned by the track session. Proposed: one sentence in step 4.
8. K8: tracks.md lines 38-39 mirror orchestrate :166-168 (`closed` → BLOCKED + story `Approved`;
   `orphaned:<b>` → stop on it). Proposed: yes.
9. The module docstring's "a refusal creates and removes nothing" becomes true for fork via
   rollback; close's partial copy-back makes it false there. Proposed: reword to what holds.
