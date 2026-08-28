---
description: SHIP step — parallel gates (typecheck/test/build/audit), a security audit when the profile is critical, commit via the github agent, advance the board, name the next feature
argument-hint: [path docs/work/<slug>/plan.md or the entry artifact]
---

# /loop:ship — close the loop

Last step. Nothing ships on a green review alone: the review reads code, the
gates run it.

Each mechanical gate uses its own `attempts.json` key under
`/loop:orchestrate`'s attempt protocol. Record a failure before fixing, clear
only that key when its rerun passes, and at the third failure stop with
`BLOCKED — <gate> failed 3x : <reason>` instead of starting a fourth run.

## Process

### 0. Where am I?

If this track runs in a worktree (`git worktree list`, and the plan's **Track
isolation** section), everything below happens **there**: gates run on the code
that is about to merge, not on the base branch. Announce the branch in one line.

### 1. Gates (parallel)

ONE message, the independent commands at once — they read the same tree and write
nothing:

```bash
pnpm typecheck          # no `any`, contracts hold
pnpm lint               # --max-warnings=0 — rules only ESLint sees (hook rules,
                        # exhaustive-deps, dead imports) AND the test rules:
                        # a test with no assertion, an `it.only`, an `it.skip`.
                        # The eslint hook is non-blocking; this is where lint
                        # actually gates.
pnpm test:run           # run-once — NEVER watch mode, it hangs
pnpm test:coverage      # thresholds on the logic layers (05-testing.md) — skip
                        # in one line if the repo has no coverage config yet
pnpm build              # production build
pnpm audit --audit-level=high   # known CVEs — the one security surface a
                        # machine reads better than a reviewer (00-project.md)
# Bundle secrets. Read the comment under this block before changing a character
# of it: the `set -o pipefail` and the `test -f` are the check, not decoration.
set -o pipefail
test -d src/ || echo "SCAN NOT RUN: no src/"
grep -rnE 'VITE_[A-Z0-9_]*(SECRET|PRIVATE|SERVICE_ROLE|PASSWORD|TOKEN|_KEY)' \
     src/ $( [ -f .env.example ] && echo .env.example ) \
  | grep -vE '(ANON|PUBLIC|PUBLISHABLE)_KEY'   # everything VITE_* ships in the
                        # bundle — the second grep drops the keys that are
                        # public by design, or this line cries wolf every run
```

<!-- FILL: if this repo has a second test runner (backend, e2e), add it to the
     same batch when the diff touches its surface. -->

All green is the condition to continue. **Red = stop and fix** — never ship
"green except one".

> **The CI re-runs every one of these, and that changes nothing here.**
> `.github/workflows/ci.yml` is the copy nobody can skip from their own machine
> (`00-project.md`); this one is the copy that runs while the fix is still free,
> before the commit exists. Skipping this batch because "the CI will catch it"
> inverts the two: it turns a local red into a pushed red, a force-push and a
> broken `main` for everyone else. The CI is the backstop, never the gate you
> aimed for.

> `pnpm test:run` must be green **and** the diff must **add** the tests for the new
> business logic (`.claude/rules/05-testing.md`). A green suite that tests nothing
> new is a FAIL.
>
> The coverage gate is a **floor, not a verdict**: it makes an unwalked branch
> impossible to ship silently. It says nothing about whether the assertions bite —
> that is `/loop:review`'s `tests` dimension. Passing it is not an argument against a
> review finding.

**The two security lines read differently from the other four.** `pnpm audit` red
with a fix available = bump and re-run; red with **no published fix** = not a
wall, but announced with the package, the advisory and whether the vulnerable
path is even reachable, and the user decides (`00-project.md`). A hit on the
`grep` is never negotiable: **anything named `VITE_*` is compiled into the
bundle** and readable by every visitor, so a secret-shaped name there is either a
misnamed public value — rename it — or a leak that shipping would publish. No
network, no agent, no tokens: both lines are the deterministic half of
`/audit:security`'s `supply-chain` and `secrets` surfaces, run on every ship
precisely because nobody has to remember them.

> **Read the grep's exit code, not just its silence.** No output with **exit 1**
> is the clean result. **Exit 2** means grep could not read one of the paths and
> that is not a pass: name the missing path and say the check did not run. A gate
> that reports green because its target was absent is the failure mode this whole
> file exists to prevent.
>
> **Which is why the pipeline is written the way it is above, and why the
> previous spelling could never report that 2.** A `2>/dev/null` on the first
> grep threw away the only signal it had, and with no `pipefail` the pipeline
> returns the *second* grep's status — measured on an empty tree: the piped form
> exits **1** (the value this paragraph calls "the clean result") where the bare
> first grep exits **2**. So the diagnostic above had never fired once, on any
> repo: `install.sh` scaffolds no `.env.example`, so grep #1 exited 2 on
> essentially every run and the pipeline reported clean. `set -o pipefail`
> restores the exit code, dropping `2>/dev/null` lets the stderr line be the
> message, and `$( [ -f .env.example ] && … )` stops an absent template file
> from being an error at all — the missing `src/` still is one, and is named.
>
> And the pattern is a **name** heuristic, not a value scanner: it catches
> `VITE_STRIPE_SECRET`, it cannot catch a real key hidden behind a bland name.
> It is a floor.

### 1bis. Security audit — armed by the token profile, not by memory

Read the profile carried by the artifact. **On `critical` only**, one
`/audit:security` runs before the commit, scoped to **one surface**.

`11-token-budget.md` reserves `critical` for payment, authorization, destructive
data changes, or explicit user request — that list is the only copy, and it is
also the list of features where a missing server-side barrier is not a Minor.
The same condition therefore arms both: the profile is not only a budget, it is
the repo's statement that this feature is one of the dangerous ones.

| What made it `critical` | The surface to audit |
| --- | --- |
| authorization, roles, guards, a new table or endpoint | `authz` |
| payment, billing, anything with a money amount | `authz`, and `input-output` if a webhook or a callback is involved |
| destructive data change (delete, bulk update, migration with data loss) | `authz` |
| session, login, logout, token handling | `session` |
| explicit user request | ask which surface, or run `everything` if they said so |

**One surface = one `security-auditor` agent**, whatever the profile says about
arity — `/audit:security` is explicit that a single requested surface launches a
single auditor. That is the whole cost of this step, and it is zero on every
feature that is not `critical`.

A Critical finding stops the ship exactly like a red gate: the track stays in its
worktree and the fix comes back through the loop, **with its reproduction test**
(`05-testing.md`). Do not fix it inline here — `/audit:security` writes nothing
by contract, and this step does not change that.

> Not `critical` and you still feel the diff deserves it? Say so in one line and
> ask. Running it unasked on every feature is exactly the token cost the audit
> was put out of the loop to avoid.

### 2. Acceptance criteria

Walk the entry artifact's criteria one by one. For each: checked, and **how it was
observed**. A criterion nobody can observe is not met.

### 3. Deploy (only if the diff requires it, and only on request)

<!-- FILL: the real deploy commands, and their traps. Two that bite everywhere:
     a bulk deploy silently resets per-unit flags, and a migration push applies
     EVERY pending migration — including ones another session wrote. List the
     pending state before pushing. -->

Announce what needs deploying and **ask** before running it.

### 4. Commit

Delegate to the **`github` agent**: it stages, writes the Conventional Commit
message, commits locally, and never signs. It commits **on a branch, never on
`main`** (`enforce-git-workflow.sh` refuses it) — the track's `feat/<slug>` if it has one, a fresh
one otherwise. Anything remote (push, PR) waits for the user's explicit
go-ahead — that gate belongs to the agent, don't bypass it.

### 4bis. Integrate

Every loop pass ends on a branch, worktree or not — so this step always applies.
Of the three sub-steps below, only the **third** (the clean-up) differs when the
track ran in a worktree.

**One integration at a time** — never two merges in flight. Then, via the
`github` agent:

1. Rebase `feat/<slug>` on the current base branch. If the rebase moved anything,
   **re-run the gates** — the code that merges is not the code you tested.
2. Present the branch, the diff summary and the exact merge command, and **wait
   for the go-ahead**. Merging is as gated as pushing.
3. After the merge, clean up. No worktree → `git branch -d feat/<slug>`, done.
   Otherwise, **mind who is standing where**:
   - the session is **inside** the worktree → `ExitWorktree` (`remove`). Git
     cannot delete the tree you are standing in, and the `github` agent has no
     such tool: this one is the main thread's job.
   - the worktree belongs to **another** track → `git worktree remove
     .claude/worktrees/<slug>` then `git branch -d feat/<slug>`.

   Never `--force`, never `rm -rf` (the Bash hook blocks both). A refusal means
   uncommitted work: report it, don't override it.

A red gate or a failed review means the track stays in its worktree and loops on
the fix. It does not merge.

**If the fix is not happening today, give the line back.** A track that stops
without shipping leaves its board line on `IN LOOP`, which asserts that a session
holds it right now — `/loop:tracks` will not fork it and step 6 below will not name
it, so the unit vanishes from the loop while looking healthy. Move it to
**`BLOCKED`** with the reason in one line, from the main tree, and put the story's
`Status` back to `Approved` — no session holds it any more (`/loop:product`, "The
board's state machine"). Still fixing it in this session → leave it `IN LOOP` and
say nothing; that is what the state is for.

### 5. Advance the state

> **This step runs in the main tree, and that is why it comes after 4bis.**
> Step 0 sent everything into the worktree; 4bis merged and removed it, so you
> are back. `docs/product/backlog.md` is on `10-worktrees.md`'s "never in a
> worktree" list — one file, every track, and `docs/product/brief.md` below is on
> it for the same reason. Moving this step before the merge puts a conflict on the
> shared product files at every integration.

- Full pipeline: story `Status` → `Done`, fill the Change Log.
- `docs/product/backlog.md`: the line moves to `SHIPPED` and its `Shipped`
   column takes today's date (`YYYY-MM-DD`). If the feature has no
  line (it entered by `/loop:spec` before the board existed), **add it as `SHIPPED`** —
  a board that only records what it happened to know about is worse than none.
  Match the line on its `Feature / story` cell, never on the artifact path.
  No board file at all → say so in one line and move on.
  Columns, states and transitions: `/loop:product`, "The board's state machine".
- `docs/product/brief.md`, **if this feature added or removed a surface**: update
  `Current surface` and the `(mapped <date>)` next to it. Never touch `Out of
  product` or `Product invariants` — those are the user's decisions, which is why
  `/loop:product` itself carries them over unchanged on a refresh. No brief → one line,
  move on.

  > **Why the board is not enough.** `/bmad:pm` *narrows its exploration* on
  > `Current surface` and `/loop:spec` leans on it to avoid re-deriving the existing
  > product. Nothing else in the loop writes that section, so without this line it
  > freezes at the day `/loop:product` ran while the code moves under it — and the next
  > feature is framed against a description that is wrong with authority. Two
  > lines here, or a re-run of `/loop:product` nobody schedules.
- Write nothing to `docs/work/<slug>/` — it stays as the trace of the loop.

### 6. Next feature

Read the board and name the **topmost** `READY` line + the command that opens it:

```
/loop:orchestrate docs/specs/<next>.md          (light)
/loop:orchestrate docs/stories/<slug>/<n>.md    (full)
```

**Topmost, not "a" `READY`.** The order of the rows *is* the priority — the only
place the kit writes one down (`/loop:product`, "The board's state machine"). With five
`READY` lines, picking the one you noticed first hands a product decision to an
accident of parsing, and it is invisible: the answer looks exactly like a
priority. If the top line is wrong for today, say which one you would take and
**why**, and let the user answer — do not silently take the second.

If no line is `READY`, say so instead of inventing one. **`BLOCKED` is not a
candidate** — it is a line somebody put down on purpose, waiting for a person.
List the `BLOCKED` ones with their reason, and let the user decide whether one
comes back; naming one as "the next feature" re-opens a decision in silence.

**If the user answers "not that one, and not later", write `DROPPED`.** You are
one of the three commands allowed to (`/loop:product`, "The board's state machine"),
and only for a decision the user takes here, in this turn, in front of you. Never
for a line that merely looks stale — that is `/loop:product`'s conversation, not this
one — and never by deleting the row: a deleted line reads as a unit nobody ever
thought of, which is the one thing the board exists to prevent. "Not now" is not
`DROPPED`; it is the line staying `READY`, below the one you take next, or
`BLOCKED` with the reason if it is waiting on something.

**And on the full pipeline, the story file goes with it**: `Status` → `Dropped`,
the reason on one line in the Change Log. Step 5 above already writes that twin
for `SHIPPED` (`Status` → `Done`); this state has one too, and it is the half
`/loop:tracks` reads. Drop the row alone and the story stays `Approved`, so the next
`/loop:tracks` forks a unit the user just killed — `/loop:orchestrate` will stop on the
terminal row, but the worktree and the branch exist by then.

## Output

```
## Ship: <feature>
- Gates: typecheck ✓ | lint ✓ | test:run ✓ (<n> tests) | coverage ✓ (<n>%, or "no config") | build ✓
- Security: audit ✓ (<n> advisories, or "<pkg> — no fix published, your call") | bundle secrets ✓ (or "SCAN NOT RUN: <the missing path>")
- Audit: <surface> — <n> Critical / <n> Major   (or "not armed — profile <economy|standard>")
- Criteria: <n>/<n> met — <the unmet ones, if any>
- Deploy: <done / pending your validation / n/a>
- Commit: <hash> <subject>   (remote: <pushed / awaiting validation / not asked>)
- Branch: feat/<slug> <in main tree | in .claude/worktrees/<slug>> — <merged | awaiting your validation | still open>
- Board: <feature> → SHIPPED
- Next: <feature> — <command>
```

## Rules

- Report faithfully: a skipped gate is announced, not implied.
- Never the watch-mode script. Always the run-once one.
- Never push or open a PR without an explicit go-ahead.
- Same for a merge back into the base branch, and never two at once
  (`.claude/guides/10-worktrees.md`).

## Task: $ARGUMENTS
