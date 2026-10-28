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
   dimensions those fixes came from, never a fresh judgment pass);
   `ship` → Phase 6. Nothing completed is redone. A `plan.md` with no sibling handoff
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
never `inbox`). This session drives it → `EnterWorktree` with `name: "<slug>"`;
another session will → `git worktree add .claude/worktrees/<slug> -b feat/<slug>`
and hand over the path. Then every phase runs inside it, said in the opening
line. **A loop pass is never an `isolation: "worktree"` subagent**: the loop has
human gates and a subagent cannot hold them. One session drives one worktree; N
tracks means N sessions. Announce the empty
`node_modules` and ask the user for the env file (`.env*` is not copyable by an
agent). Otherwise: "single track, no worktree".

## Phase 1 — RESEARCH

`/loop:research <entry>` → `docs/work/<slug>/research.md`. Barrier: the file
exists before designing. Retain its `Traps`: Phase 3 restates them as `Vigilance`.

## Phase 2 — INTERFACE (skippable)

`/loop:interface docs/work/<slug>/research.md` → `docs/work/<slug>/design.md`.
Arity is the profile's call, declared in `/loop:interface`. The retained proposal
is rendered on the `/design` canvas before the gate. **Human gate**: the user
picks, edits or grafts, 3 rounds at most; do not enter Phase 3 on silence. A
canvas edited after the gate reopens it.

## Phase 3 — PLAN

`/loop:plan …` → `docs/work/<slug>/plan.md`. It runs `plan-critic`, refutes its
Critical/Major claims, rewrites until completeness and quality clear (scores kept
separate) or the ceiling blocks. **Human gate**: it prints the `Test plan` and
waits for an explicit go — the go freezes the test-first files
(`.claude/rules/05-testing.md`). Do not enter Phase 4 on silence.

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
the id it reports. Correcting one is the one step of EXECUTE that waits for the user:
the `.tdd-unfrozen` write asks the user (a guarded path), and a headless run
cannot answer, so it stops there. The agent that hits the freeze stops and
reports; you print the case id, the old and new case line and the reason, write
`.claude/.tdd-unfrozen` citing the id (`<path>  # U2: <reason>`, several as
`# U2, U5: …`) once the user approves the prompt, make the edit yourself —
never through `implementer` or `test-writer`, whose contracts forbid rewriting a
frozen case — then rewrite the plan line with the same id and append
`amended <date> U2: <old> → <new>` to `## Gate` (create it if absent). The user
confirms it at the merge (`/loop:ship`). (Small: no correction, the ticket ejects.) On a Python service layer the `-py` hooks
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
section. Claude keeps the verdict; the fixes of the surviving Critical/Major always
leave the main thread. Codex routed for `review-fixes` and running → the handoff
(`phase: review`, `review_status: fixes-handed-to-codex`, `codex_safe`), same
guards, `./codex-handoff.sh docs/work/<slug>/handoff.md review-fixes --auto`.
Otherwise → one `implementer`, the findings as its fix batch. An e2e spec the
change broke → `e2e-tester` in repair mode. Then re-run only the affected
dimensions.

## Phase 6 — SHIP

`/loop:ship docs/work/<slug>/plan.md`: gates, acceptance criteria one by one,
commit via the `github` agent, board advanced, next feature named. A `critical`
profile also arms one `/audit:security` surface before the commit (step 1bis). On
a forked track the gates run in its worktree and the merge is `/loop:ship`'s last,
user-gated step.

## Conclusion (mandatory)

Close with: criteria met, what was SKIP and why, what stays OUT, what needs
deploying, and the next feature. If the track forked: the branch, and whether it
is merged, awaiting your go-ahead, or still open. (Small: no next feature; the
ship cleanup commands, then `/loop:small --status` in the main session.)

## Task: $ARGUMENTS
