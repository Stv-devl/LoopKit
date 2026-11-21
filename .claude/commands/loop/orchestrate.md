---
description: Runs the whole feature loop — research → interface → plan → execute → review → ship. Each step is also callable alone.
argument-hint: [--economy|--standard|--critical] [--inline-execute] [path: spec, story, handoff, research/design/plan artifact]
---

# /loop:orchestrate — the feature loop, end to end

You receive an **entry artifact** and drive it to shipped:

```
RESEARCH → INTERFACE → PLAN → EXECUTE → REVIEW → SHIP → next feature
```

A `/loop:spec` contract (light) and a reviewed story (full) enter the same loop.
**You decide** what to skip, sequence or parallelise from the real dependencies:
parallelise reads, sequence writes. Reasons for every rule below:
`.claude/guides/orchestrate.md`.

The loop's artifacts live in `docs/work/<slug>/`. The slug is **derived from the
entry artifact's path** by the rule in `/loop:research` — the only copy. Every
phase reads it out of the path it was handed; Phase 0.5 applies the same rule
itself, before research has run.

## Token profile

Select once in Phase 0 and persist `Token profile: <value>` in every
`docs/work/<slug>/` artifact. `economy` (default), `standard`, or `critical` for
the cases `11-token-budget.md` lists. A downstream command inherits it and never
silently upgrades it. Mechanical shell gates always run.

## Validation mode — `moi` or `auto`, chosen once

The framing asks `Validation : moi | auto` (`/loop:spec` step 1; a full/BMAD entry is
asked at Phase 0 step 2, `AskUserQuestion`), never again in the pass. Two sources, one
job each: the spec's `Validation:` line (or that Phase 0 answer, copied into the
handoff) only opens the `Contract gate` at the end of Phase 1 and grants nothing; from
the contract go on, `python3 .claude/hooks/loop-record.py --mode` alone decides. A
restart in phase `research` re-reads the spec line;
a restart after `research` reads `--mode`, and `moi` there (no record, cleared,
mismatched) continues in `moi`.

| Gate after the contract | `moi` | `auto` |
| --- | --- | --- |
| Interface: pick a mock-up (UI only) | the user picks | the front-runner (economy, 2 alternatives) or the `designer` judge (`critical`); reasons in `design.md`; no canvas render |
| Contract question at the first gate (B3) | asked | already taken at the `Contract gate` |
| Plan-critic `interpretation` findings | the user | the `arbiter` |
| Open questions + test plan | the user | the `arbiter` |
| Frozen-test correction (plan or EXECUTE) | the user | the `arbiter` (`unfreeze` / `refuse`) |
| Commit, push, PR | the agent | the agent |
| Merge of the PR | the user | the user |

In `auto`, every gate after the contract goes to **one fresh `arbiter` per decision**,
never resumed, never the agent that asked; its verdict block is ledgered in the record
by a hook (`SubagentStop`), so the PR's `Decided without you` comes from the record.
The main thread and its agents **never issue a command that asks** (destructive git,
`gh pr merge`, a second push, a secret read, a whole-folder formatter); the kit's
guarded asks are denied in `auto` with a reason opening `auto mode — blocked stop:`.
The shell asks the hook keeps (nobody answers them in `auto`) are never issued either:
a snapshot update (`vitest -u`), a recursive delete (`rm -r`), a secret read, a command
the guard cannot parse or a failed guard, a whole-folder formatter, a TypeScript source
written from the shell, a deleted Vitest cache, an option off the safe list, a kit script
run from a nested folder, a write through a temporary-folder or fd path, a write outside the
project, a tool option aimed at a folder or file, and a codegen target.

**A contract contradicted mid-run:** never rewrite the contract. Continue on it as
written when something coherent can be built, and put the contradiction first in the PR
(`Contract contradiction`); when nothing coherent can be built → blocked stop.

**Blocked stop** (`auto` only). Its causes: a remaining ask (a deny opening
`auto mode — blocked stop:`), plan-critic `BLOCKED`, an attempts cap,
a red gate after the fix budget, an undecidable case,
a correction that changes an acceptance criterion's meaning (the `arbiter` answers `blocked`). It ends the run: handoff `blocked: <cause>`,
board line `BLOCKED` (main tree), local commits kept, **no push, no PR**, then
`python3 .claude/hooks/loop-record.py --clear`. `./workflow.sh` resumes it, in `moi`
unless a new `Contract gate` is taken.

## Automatic checkpoints

Maintain `docs/work/<slug>/handoff.md` inline, without a subagent, from the
`/handoff:codex` template (its frontmatter `phase:` is what a restart resumes):
create it once `docs/work/<slug>/` exists; refresh it after interface, plan, each
RED→GREEN layer, review fixes and ship gates, and on a contract amendment
re-entry; store only state, changed paths,
decisions/traps and last deterministic results; link, never copy.

Before launching any agent, check `.claude/.token-stop-agents`: if present,
launch none, finish the atomic write/test, refresh the checkpoint, yield. When
`.claude/.restart-ready` exists, start no phase: `workflow.sh` stops Claude and
starts a fresh session on `/loop:orchestrate docs/work/<slug>/handoff.md`. Two
restarts per feature, then it stops: the phase goes back to the plan to be split.

## Gate attempt ceiling

Every retryable gate owns one key in `docs/work/<slug>/attempts.json`:
`interface`, `contract` (light only: one failure per contract amendment, `pass` on
`as written`), `plan-critic`, `test-plan`, each `red:<layer>`, `review`, and each
ship gate (`typecheck`, `lint`, `test`, `coverage`, `build`, `audit`, `security`).
On failure run:

```bash
python3 .claude/hooks/kit-attempts.py fail docs/work/<slug>/plan.md <gate> "<last failure>" \
  --board docs/product/backlog.md --unit "<exact Feature / story cell>"
```

On success use action `pass` and omit the reason. Exit 3 is the third failure:
the script writes `BLOCKED — <gate> failed 3x : <reason>` into the exact unit
cell, so never start a fourth attempt. In a worktree omit `--board/--unit`, report
that exact main-tree edit and stop. Return a story to `Approved` when blocking.
A new session does not reset the counter; a successful gate does. (Small: exit 3 ejects, step 1 of Phase 0.)

---

## Phase 0 — Read & decide

Shell discipline for the whole pass:
- kit scripts run from the project root by relative path, never behind `cd x;` (`cd <absolute root> && …` at most);
- work artifacts are written with Write/Edit, never from the shell (`plan.md`, `handoff.md`, `design.md`; appending `## Gate` is an Edit).

0. **Closing check**, before anything else. For each `docs/work/*/handoff.md` with
   `phase: awaiting-merge` (main tree and every `.claude/worktrees/*`), run
   `.claude/scripts/loop-pr-state.sh --chain <its branch>`:
   - `closable` → first, only for the **main tree's** handoff whose HEAD is the pass's own branch
     `feat/<slug>` (a main-tree pass is still standing on its merged branch), switch it to the
     default branch (`gh repo view --json defaultBranchRef`, as `loop-pr-state.sh` reads it) and
     sync it as the `github` agent's "Keeping local in sync" does: `git switch <default branch>`,
     `git fetch origin`, `git merge --ff-only origin/<default branch>`; blocked or diverged →
     report it and stop on this pass; a worktree handoff skips the switch and the sync (git
     refuses a branch checked out in the main tree) and goes straight to the next sentence. Then
     `/loop:ship` step 5 (story `Done`, board `SHIPPED`, brief) on the default branch;
     a worktree handoff's `/loop:ship` step 5 runs in the main tree, which must be on the synced default branch
     (else report and stop: never write the board or the story into a pass branch's checkout).
     Then `python3 .claude/hooks/loop-record.py --clear` in the pass's tree and the
     handoff → `phase: shipped`, and only then `4bis-local` item 3's clean-up (the worktree removal,
     then `git branch -d feat/<slug>`), so neither targets a removed tree. Say so.
   - `closed` → board `BLOCKED` "PR closed unmerged", story `Approved`.
   - `orphaned:<b>` → say the commits never reached the default branch, and stop on it.
   - `open`, `stacked:<b>`, `unknown`, `none` → one line each, nothing moved.
   Then, if HEAD is the branch of a pass still `open` or `stacked`, say in one line that the
   new pass will stack on that branch (its PR targets it): stay on it, switch nothing.

1. **Small pipeline**, picked before anything else, so before the resume
   branching of step 2. Select it when the entry is under `docs/specs/small/`, the
   plan header says `Pipeline: small`, or a resumed handoff body has `Entry:`
   naming a small spec: a resumed small handoff selects this branch first, then
   branches on its `phase:` (`execute` → Phase 4, `review` → the review below,
   honouring `review_status`: `fixes-done`, or a fix batch already landed, re-runs
   only stages 1-2 once on the fixed findings, never a fresh judgment pass and never
   a second fix batch (S7); `ship` → Phase 6). The branch skips Phase 0 steps 3-4, the board (small tickets are
   off-board), Phase 0.5 (the session already runs in its worktree) and Phases 1, 2
   and 3 (the committed spec is the validated contract); it replaces Phase 5 with the
   review below. Run `.claude/scripts/small-plan.sh small-<name>` only when
   `docs/work/small-<name>/plan.md` is absent, then execute that plan unchanged
   (Phase 4). Run `kit-attempts.py` by path, without `--board/--unit`: exit 3
   ejects. This branch asks the user nothing before `/loop:ship`'s merge go.

   Review: stage 0 only for UI files; one reviewer for correctness, tests, security
   and ui when applicable, then the three inline checks, one verifier, and one
   implementer fix batch, each finding reproduced by a failing case first. Review
   once more; a confirmed finding records
   `python3 .claude/hooks/kit-attempts.py fail docs/work/small-<name>/plan.md review "<finding>"`
   and ejects with `review FAIL: <finding>`. Before ship's commit run
   `small-scope.sh <name>`; a refusal ejects. A judged S2 trigger writes
   `S2 trigger: <kind>` and ejects.

   Ejection triggers: a frozen test-first case that needs correcting, a path outside
   `Files` needed, a size exemption needed, a judged S2 trigger, review `FAIL`, a
   `small-scope.sh` refusal before the commit, a gate failed 3 times. Ejection
   commits `docs/work/small-<name>/ejected` with the one-line reason, stops, and
   prints the reason, then `re-enter: /loop:spec` in the main tree (the small spec's
   Objective, Files and Done when as the description), then only
   `git worktree remove .claude/worktrees/small-<name>` (the branch stays as a
   reference, never continued).
2. Parse the optional profile flag (default `economy`; an entry that carries a
   profile is inherited unless the user overrides) and `--inline-execute` (keeps
   EXECUTE and review fixes on Claude whatever the routing file says). Read the
   entry in full. A spec or story without its `Token profile:` line: say so.

   **A `docs/work/<slug>/handoff.md`**
   (outside the small pipeline above; or `handoff-codex.md`, its name before 0.2) is a resume: read its frontmatter, then the artifacts it links, and
   branch on `phase:`. `research` → Phase 1, keeping whatever `research.md`
   already holds (after a contract amendment the stale one was already deleted,
   "Contract amendment" below); `interface` → Phase 2;
   `plan` → Phase 3 — a `plan.md` with `## Gate` present goes to Phase 4 without
   asking; without it, if `plan.md` exists and its `## Plan critic` reads
   `surviving blockers: none`, only `/loop:plan` step 7 is asked, on `plan.md` as it
   stands; otherwise (no plan yet, or the critic not cleared — a contract
   amendment re-entry interrupted) `/loop:plan` reruns in full; `execute` → Phase 4,
   from the layer `## In progress` names (`execute_status: done` → Phase 5);
   `review` → Phase 5 (`review_status: fixes-handed-to-codex` → re-run only the
   dimensions those fixes came from, on the fix diff, never a fresh judgment pass);
   `ship` → Phase 6; `awaiting-merge` → print this pass's closing-check result
   (step 0 already ran it) and **stop**: no phase runs, `closable` already closed
   it. Nothing completed is redone. A `plan.md` with no sibling handoff
   jumps to Phase 4; with one, the handoff decides.
3. **FEATURE READY check**, if `docs/product/backlog.md` exists. Not listed → add
   the line as `READY` **at the end** of the table (`Entry artifact` = the path,
   `Pipeline` = `light` for a spec, `full` for a story, `BUG` for `debug.md`) and
   say so. `DRAFT` → stop and ask. `BLOCKED` → name its reason, stop if it still
   holds, else take it back. `DROPPED` or `SHIPPED` → stop. No board → skip in one
   line. States and transitions: `/loop:product`, "The board's state machine".
4. **Take the entry**, in one line: a story's `Status` → `InProgress`, always; the
   board line → `IN LOOP`, **only from the main tree**. In a worktree, say so and
   leave the board alone: `/loop:ship` moves the line after the merge. Any exit other than `/loop:ship` step 5 gives it
   back: the line → `BLOCKED` with its reason, from the main tree, and the story's
   `Status` → `Approved`.
5. Announce each **SKIP** and why. No user surface (migration, job, backend-only,
   refactor) → INTERFACE SKIP. RESEARCH is **never** skipped (small: done inline at dispatch, `/loop:small` step 2).

## Phase 0.5 — Track isolation (worktree or not)

Decide **once**, announce in one line, never revisit mid-loop. Fork only if all hold
(`.claude/guides/10-worktrees.md` is the authority — read it before forking):
another pass is in flight or the user asked for this one in the background; the
file sets are disjoint; neither touches a shared foundation (migrations & DB,
`src/lib/*`, `shared/*`, router, providers, composition root, design system,
backlog, lockfile); clean tree, known base branch. How many fork is computed,
three at most: `/loop:tracks` in a story pipeline, otherwise the four steps of
`10-worktrees.md`, "How many tracks", announced with the named set. Shared
foundations are not a reason to fork finer: they are done first in the main
tree, committed, and the tracks fork from that commit.

`<slug>` is this pass's loop slug (`docs/stories/inbox/1.2.md` → `inbox-1.2`,
never `inbox`). The fork always names its start point, the main tree's current
branch, so git records `Created from <base>` for the loop record:
`git worktree add .claude/worktrees/<slug> -b feat/<slug> <base>`. This session
drives it → `EnterWorktree` with that worktree's `path`; another session will → hand over the path. Then every phase runs inside it, said in the opening
line. **A loop pass is never an `isolation: "worktree"` subagent**: the loop has
human gates and a subagent cannot hold them. One session drives one worktree; N
tracks means N sessions. Announce the empty
`node_modules` and ask the user for the env file (`.env*` is not copyable by an
agent). Otherwise: "single track, no worktree".

## Phase 1 — RESEARCH

`/loop:research <entry>` → `docs/work/<slug>/research.md`. Barrier: the file
exists before designing. Retain its `Traps`: Phase 3 restates them as `Vigilance`.

**End of Phase 1 in `auto`: the one stop after the framing.** Ask one
`AskUserQuestion`, header `Contract gate`, never pre-filled, whose text opens with
exactly these two lines (the record hook parses them):

```
Contract go — docs/work/<slug>/research.md
Validation: auto
```

then the spec's Objective, Scope IN/OUT and Acceptance criteria verbatim under
`Contract (validated by this go)` (full/BMAD: the reviewed stories) and research's
`Traps`, one line each. Answers: `as written` (→ `kit-attempts.py pass` on `contract`;
the hook writes the auto record) or free text to amend (the "Contract amendment" rules
below). Right after `as written`, on the base branch run `git switch -c feat/<slug> <base>`
(the start point named: the record reads its base from it) before Phase 2 (main tree; a worktree pass already stands on it): auto mode holds only
on the record's own branch, never on its base. Then check the record: without `barrier: true` (`.claude/.loop-record.json`,
read-only) auto mode does not start — blocked stop before Phase 2.

## Phase 2 — INTERFACE (skippable)

`/loop:interface docs/work/<slug>/research.md` → `docs/work/<slug>/design.md`.
Arity is the profile's call, declared in `/loop:interface`. The retained proposal
is rendered on the `/design` canvas before the gate. **Human gate**: the user
picks, edits or grafts, 3 rounds at most; do not enter Phase 3 on silence in `moi`. A
canvas edited after the gate reopens it. In `auto` there is no canvas and no gate
(`/loop:interface`, auto mode).

## Phase 3 — PLAN

`/loop:plan …` → `docs/work/<slug>/plan.md`. It runs `plan-critic`, refutes its
Critical/Major claims, rewrites until completeness and quality clear (scores kept
separate) or the ceiling blocks. **Human gate**: it prints the `Test plan` and
waits for an explicit go — the go freezes the test-first files
(`.claude/rules/05-testing.md`). Do not enter Phase 4 on silence in `moi`; in `auto`
the `arbiter` takes the gate (`/loop:plan` step 7).

**Light pass: the contract is validated at the first gate.** `/loop:spec` chains
straight into this command, so the user has not yet re-read the written contract:
`/loop:interface` asks it when there is a screen, else `/loop:plan` step 7, as its own
question in the gate's call. The go is recorded in `plan.md`'s `## Gate`.

**Contract amendment.** An amended contract re-enters at the earliest phase the
edit invalidates: `Scope`, `Data model` or `Custom backend` → Phase 1; `Front
surface` → Phase 2 (reopening the INTERFACE SKIP decision); `Acceptance criteria`
or `Business logic to cover` → Phase 3. Before re-entering, delete the artifacts
the rerun replaces — `research.md`, `design.md`, `plan.md` from that phase on, each
by its exact path — and write the handoff's `phase:` to the re-entered phase. Then
rerun that phase and every phase after it, `plan-critic` included; Phase 1 writes
`research.md` from scratch. The gate that took the amendment already recorded its
failure on `contract`; do not record it again here.

## Phase 4 — EXECUTE (sequential, on the main thread)

**Routing first.** Read `.claude/workflow-routing.yml`, role `execute-green`.
Absent, `provider: claude`, `codex --version` failing, or `--inline-execute` →
everything stays on Claude (inline, or `implementer` past 70%). `provider: codex` and Codex runs → you still do the
test-first layers, then at the first step that is not test-first (right after
`repository` or `services` goes green) write the handoff
(`phase: execute`, `execute_status: in-progress`, `codex_safe`), and **once the
Write has returned, in a later message**, run in the background, without polling:

```bash
./codex-handoff.sh docs/work/<slug>/handoff.md execute-green --auto
```

`codex_safe: yes` only when every remaining gate runs offline; a database test or
e2e step stays inline (the launcher refuses it, and a handoff older than the plan
or the last commit). Read `docs/work/<slug>/codex-last-message.txt` when it lands;
a question Codex stopped on goes to the user. Migrations never move:
`/database:migration` is yours whatever the provider.

Implement **yourself**, in the plan's order. Three exceptions, and only these: the
RED legs (`test-writer`), GREEN past 70% (`implementer`), and the plan's parallel
lots:

```
1. DB       → /database:migration        (schema + authorization + triggers)
2. Backend  → handlers, if the plan asks for one
3. Front    → types → schemas → errors → gateway
              then ONE LAYER AT A TIME, in dependency order:
              ├─ utils        RED → GREEN
              ├─ mapper       RED → GREEN
              ├─ repository   RED → GREEN
              └─ then  : hooks → store → components → forms
4. Wiring   → router + guards
5. Tests    → hooks.ts + the rest of the test plan (gateway, UI) — MANDATORY,
              one `test-writer` launched in its mode "after the code" per file
6. REFACTOR → clean the logic with the suite green. No new behaviour, no test
              edited. This is the third leg of the cycle, not an optional tidy-up.
```

For each test-first layer the plan has:

- **RED** — one `test-writer` per feature: launch it on the first layer (test file
  path, plan path, layer), then continue the same agent with `SendMessage` for
  each next layer (no `SendMessage` in this Claude Code → launch it per layer). It writes that one file, runs it, returns the failure output,
  and never reads the module under test. `Blocked on` a contract ambiguity → the
  user decides, never you writing the test.
- **GREEN** — you, inline: just enough code in that one module. The test does not
  move. When `.claude/.token-delegate` exists (context past 70%), hand the layer to
  one `implementer` instead — test path, module path, plan — and check its proof
  run yourself.

Then the next layer. **Never batch the REDs then the GREENs.** `errors.ts` and
`gateway.ts` come right after the schemas, before the first RED: the repository
test imports them.

The RED is proved, not declared: `tdd-prove-red.sh` leaves a marker on a genuine
red, and `tdd-require-red.sh` denies the module until it exists. Denied → the test
came after the code or never failed; never work around it. One benign case: the
`test-writer` reported a real red but no marker landed — re-save the test file
**byte for byte identical** and read the verdict; anything but `RED confirmed`
means the denial was right. Once green, adding a case to a frozen file is a pure
insertion (say what it covers) with the next free id of its letter; whoever wrote
it, you append its plan line — an `implementer` reproduction case included, from
the id it reports. A case the plan gate recorded as a row (`Frozen cases to
amend:`) is not a correction: its `.tdd-unfrozen` line is written with no prompt and
the freeze hook checks each edited case against its row. Any other correction is
the one step of EXECUTE that waits for the user:
the `.tdd-unfrozen` write asks the user (a guarded path), and a headless run cannot answer. The agent that hits the
freeze stops and reports; you **queue** it in `docs/work/<slug>/unfreeze-queue.md`
(case id, old and new case line, reason, hunk) and keep working on what does not
depend on it; the main thread stops once for the whole batch: print the queue,
then write `.claude/.tdd-unfrozen` citing the ids (`<path>  # U2: <reason>`,
several as `# U2, U5: …`) once the user approves the prompt — all the entries a gate needs go in one Edit,
and the chat never asks again what the hook's ask asks — make the edit yourself —
never through `implementer` or `test-writer`, whose contracts forbid rewriting a
frozen case — then rewrite each plan line with the same id and append
`amended <date> U2: <old> → <new>` to `## Gate` (create it if absent). The amended
cases are listed in the PR body (`Frozen cases`, `/loop:ship`). (Small: no correction, the ticket ejects.)
In `auto` nobody answers the prompt: each queued case carries its fenced `diff` hunk
against the current test file, and you launch one fresh `arbiter` per queued case id
with it; then one `.tdd-unfrozen` Edit for the `unfreeze` verdicts only (the hook lets
in a line only on a ledgered `unfreeze` verdict); a `refuse` keeps the case frozen and
the work bends to it; an `amended` line decided by the arbiter says so. On a Python service layer the `-py` hooks
play the same roles (`.claude/rules/07-backend.md`); hand the `test-writer` the
`.py` path.

Load what you need from `.claude/skills/patterns/` and `templates/`.

Impeccable applies only on a UI feature: its review stage 0 findings are advisory
input when fixing the screen, never a replacement for `design.md` or
`patterns/a11y.md`.

**Parallel lots** may fork only when their file sets are disjoint, as agents in
this track's tree, never as extra worktrees.

## Phase 5 — REVIEW

(Small: replaced by the review of Phase 0 step 1.) `/loop:review docs/work/<slug>/plan.md`, handing it the plan's **`Vigilance`**
section. Claude keeps the verdict. `kit-gate-route.py` routes the survivors (review stage 3)
and writes Minors and out-of-scope findings to `docs/work/<slug>/follow-ups.md`. On
`write-closure`, close those findings and rerun the route before anything else.

On `fix-batch`, the `blocking` findings always leave the main thread, in three steps:
1. Run `python3 .claude/hooks/kit-gate-route.py snapshot docs/work/<slug>/plan.md` first. It
   records the batch's base in `fix-base`.
2. Hand off the batch:
   - Codex routed for `review-fixes` and running → the handoff (`phase: review`,
     `review_status: fixes-handed-to-codex`, `codex_safe`), same guards,
     `./codex-handoff.sh docs/work/<slug>/handoff.md review-fixes --auto`;
   - otherwise → one `implementer`, the findings as its fix batch, `fix-introduced` ones first.
     Print its `Growth:` line.
   - An e2e spec the change broke → `e2e-tester` in repair mode.
3. Re-run only the affected dimensions, round + 1, on the fix diff.
   - Each reviewer gets the confirmed findings with their `Closure:`, plus
     `kit-gate-route.py diff docs/work/<slug>/plan.md fix` and `… feature`.
   - The verifier gets `fix-base` and the fix diff.
   - The route then tags `fix-introduced` and keeps only admissible findings blocking.

## Phase 6 — SHIP

`/loop:ship docs/work/<slug>/plan.md`: gates, acceptance criteria one by one,
commit via the `github` agent, board advanced, next feature named. A `critical`
profile also arms one `security-auditor` on the surfaces the diff touches before
the commit (step 1bis). On
a forked track the gates run in its worktree and the merge is `/loop:ship`'s last,
user-gated step.

## Conclusion (mandatory)

Close with: criteria met, what was SKIP and why, what stays OUT, what needs
deploying, and the next feature. If the track forked: the branch, and whether it
is merged, awaiting your go-ahead, or still open. (Small: no next feature; the
ship cleanup commands, then `/loop:small --status` in the main session.)

## Task: $ARGUMENTS
