# Spec: kit fixes from the EcoCrew agent-ia-2.5 / agent-ia-4.6 auto runs
Token profile: economy
Validation: moi

## Objective
Remove the recurring hook round-trips, the stale PR-body refusal and the unreadable guard output that the EcoCrew agent-ia-2.5 auto pass (2026-11-25, PR #50) and the live agent-ia-4.6 auto pass showed, without loosening any guard.

Source evidence (read-only): EcoCrew transcripts `~/.claude/projects/-home-stevan-Travail-Projetperso-ecocrew/156208f4-…` (2.5, main + 66 subagents) and `928747b9-…` (4.6, live), EcoCrew `docs/work/agent-ia-2.5/`, commit `47e4619`. Neither pass made an unplanned user stop: the user only saw the mode question, the Contract go and the merge. Every item below is agent friction or reviewer noise. Branch: one, off `main` (1a99f7c).

## Scope
- IN :
  1. **`kit-pr-assets.py ui` takes no pipe.** `.claude/commands/loop/review.md:160` prescribes `{ git diff --name-only <base>; git ls-files --others --exclude-standard; } | python3 .claude/hooks/kit-pr-assets.py ui`, which kit-cwd refuses ("Pipe nothing into it"). This was refused in 2.5 (12:47) and again in 4.6 (14:00), so the screenshot decision falls back to the orchestrator's guess and the "exit 2 → blocked stop" rule never runs. `ui` gains `--base <sha>`: the script lists the working-tree changes against `<base>` (tracked diff plus untracked, not ignored) itself, and `review.md` invokes it alone in its own Bash call. Stdin input keeps working for the existing tests. kit-cwd does not change.
  2. **Deny texts say what to do.**
     - In `prevent-destructive-commands.sh` (around 972-977), a manual form (`--mode`, `--guarded-block`, `--clear`, `--block`) chained after another command (`cat …; python3 .claude/hooks/loop-record.py --mode`) is still denied, but the text says to run that form alone in its own Bash call. It no longer says "only Claude Code runs loop-record.py". This happened in 2.5 (12:46) and in 4.6 (13:43).
     - A read of `.claude/.loop-record.json` by an inline program (`python3 -c "…json.load(open(…))…"`) is denied as an inline program, and the text points to `Read` or `loop-record.py --mode`. It is no longer reported as "written by inline-path" (2.5, 11:50).
  3. **The guarded block is computed on the shipped HEAD.**
     - `.claude/commands/loop/ship.md` 4bis-PR step 2 says `--guarded-block` runs only after the `github` agent has reported the commit and push, and never in parallel with it. In 2.5 the block was computed at 13:31:31, before the commit, so it was stale and `gh pr create` was refused.
     - The block's comment line carries the HEAD sha it was computed on. On a digest mismatch, the `gh pr create` deny says whether HEAD moved since the block was printed, so the orchestrator knows to regenerate it.
  4. **Precise case ids in `GUARD FAILURE`.** `loop-record.py` `PY_CASE_RE` (and its TS twin) reads `def test_s27_ac5_…` as case id `S27`. In 2.5, ~10 rewritten cases collapsed into one line, `backend/tests/api/test_agent_api.py S27 changed with no ledger row`. When two or more cases of one file share an id, each changed case is reported by its full test name (Python function name, TS title). Unique ids keep their current form, so ledger rows and the freeze hooks keyed on them are unchanged.
  5. **Planned rewrites of existing cases are declared at the plan gate.** A story that knowingly changes the behaviour an earlier story tested rewrites those cases, even in test-after files. In 2.5, the `test_s27_*` cases of story 2.7 were rewritten for AC3. `/loop:plan` lists such cases (path + id or full name from item 4) as `amended` rows, and the plan gate (the user in `moi`, the arbiter in `auto`) records them in the ledger. `--guarded-block` then reports only unplanned rewrites. A rewrite that was not declared still prints `GUARD FAILURE`, exactly as today.
  6. **Agent prompts name the frequent refusals.** `implementer.md` and `test-writer.md` gain one short block, and `/loop:orchestrate` keeps the same rules in its own Bash calls:
     - git in another directory uses `git -C <abs>`, never `cd … && git …` (refused 3× in 2.5, 2× in 4.6 so far);
     - no heredoc or redirection into any file, tests included;
     - no `python3 -`/`-c`;
     - no `sed -i`/`perl -i` (4.6, 13:55: only Claude Code's auto classifier stopped it);
     - no `Any` in tests;
     - a new import a frozen test case needs goes inside the case body, because the freeze hook refuses an import-only insertion (2.5, B557).
     Each line names the tool to use instead.
  7. **In-place and redirected shell writes are denied on every project path.** CLAUDE.md forbids every shell file write, but the shell guard only denies them on guarded paths. `sed -i docs/work/agent-ia-4.6/plan.md` reached Claude Code's classifier. `sed -i`, `perl -i`, `tee` and `>`/`>>` whose resolved target lies inside the project root or a registered worktree are denied, with a text pointing to `Write`/`Edit`. Allowed: `/dev/null`, `/dev/std*`, and paths outside the project (scratchpad, `/tmp` under the existing link/fd rules). A kit prompt or script the change would break is fixed in the same pass, never exempted.
  8. **Local screenshot runs are tidied at ship.** After a successful publish, `kit-pr-assets.py` gains a `prune-local --slug <slug> --keep <run-dir>` that deletes the PNG files of that slug's other run dirs under `.pr-shots/<slug>/`, then removes the emptied dirs with a non-recursive `rmdir`. It never touches `.pr-shots` itself, another slug or a non-PNG file. `ship.md` calls it after the `Screenshots` section is in the body. The remote `pr-assets` branch is kept: the merged PRs' images keep working, and the existing optional `drop` cleanup is unchanged.
  9. **Shadow-area findings route as they are.** `/loop:review` Stage 2.5 (SHADOW AREAS, `review.md:201`) emits findings with `dimension: "shadow"`, but `kit-gate-route.py` `DIMENSIONS` accepts only `correctness, tests, db, security, ui`. In 4.6 (14:02) `route-review-1.json` exited 2 on K8, and the orchestrator relabelled K8/K9 as `tests` to pass, which misfiles them. Either the router accepts `shadow`, with the same routing as the dimension that owns the shadowed dependency, or `review.md` names the dimension a shadow finding must carry. Whichever is chosen, prompt and router agree, and a shadow finding is never relabelled by hand.
- OUT :
  - Allowing import-only insertions in frozen test files, and allowing read-only `git` after a `cd` to the project root. Both loosen a guard, so they go to their own `critical` pass.
  - EcoCrew's `app_roots: []` in its `.claude/project.json` (the kit side shipped with auto-mode-trial-fixes; the value is EcoCrew config, the user's).
  - EcoCrew test gap: no case undoes a **confirmed** held deletion since `test_s27_ac7`'s restore assertions were removed. This is an EcoCrew follow-up.
  - New findings from the 4.6 probe: added to this spec before `/loop:orchestrate`, or to a later pass.

## Data model
none

## Custom backend
NONE — kit hooks, kit scripts and prompts only.

## Front surface
none

## Acceptance criteria
- [ ] `python3 .claude/hooks/kit-pr-assets.py ui --base <sha>` run alone from the project root prints `ui` for a working tree changing `src/X.tsx` and `none` for one changing only `docs/x.md`, untracked files included; an invalid `project.json` still exits 2.
- [ ] `review.md` holds no pipe into a kit script, and `test-hooks.sh` checks that no kit prompt pipes into `.claude/hooks/*.py`.
- [ ] `cat x; python3 .claude/hooks/loop-record.py --mode` is denied with a text that tells to run the form alone; `python3 .claude/hooks/loop-record.py --mode` alone still prints the mode; running it with no flag is still denied with the current text.
- [ ] A `python3 -c` that reads `.claude/.loop-record.json` is denied with a text naming `Read` / `--mode`, not "written by".
- [ ] `--guarded-block` prints the HEAD sha it ran on. A body whose block was computed on an older HEAD is denied with a text saying HEAD moved. A fresh block passes as today.
- [ ] In a test file with `test_s27_ac5_x` and `test_s27_ac6_y` both changed, the block lists both full names; a file whose ids are unique (`test_b517_…`) still prints `B517`.
- [ ] An `amended` row recorded at the plan gate for a non-frozen test case removes its `GUARD FAILURE` line; an undeclared rewrite of another case in the same file still prints one.
- [ ] `sed -i 's/a/b/' docs/work/x/plan.md`, `echo x > docs/work/x/a.md` and `… | tee src/a.ts` are denied; `cmd > /dev/null` and a write to the session scratchpad pass.
- [ ] No kit prompt or script in the repo prescribes a shell write into the project (grep proof in the PR).
- [ ] `prune-local` keeps the shipped run dir intact, deletes the PNGs of the slug's older runs, removes their emptied dirs, and refuses a `--keep` outside `.pr-shots/<slug>/`.
- [ ] A route file holding a Stage 2.5 shadow finding, written exactly as `review.md` tells, routes with exit 0 and keeps its dimension, and a test checks that `review.md`'s dimension list and `DIMENSIONS` agree.
- [ ] `implementer.md` and `test-writer.md` carry the refusal block of item 6, and `/kit:doctor` passes.
- [ ] `bash .claude/hooks/test-hooks.sh` passes with a case per criterion above.

## Business logic to cover
- `kit-pr-assets.py`: the change list built from `--base` (tracked plus untracked, ignored excluded), the `ui`/`none` decision from it, and `prune-local`'s keep/delete/refuse rules.
- `loop-record.py`: the case-id collision fallback to full names, the HEAD sha in the guarded block, and `amended` rows silencing exactly the declared cases.
- Shell guard: deny texts for chained manual forms and inline reads; the in-place/redirect deny on project paths with its `/dev/null`, scratchpad and outside-project exceptions.
