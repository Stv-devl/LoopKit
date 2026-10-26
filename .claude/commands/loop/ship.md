---
description: SHIP step — parallel gates (typecheck/test/build/audit), a security audit when the profile is critical, commit via the github agent, advance the board, name the next feature
argument-hint: [path docs/work/<slug>/plan.md or the entry artifact]
---

# /loop:ship — close the loop

Last step. Nothing ships on a green review alone: the review reads code, the
gates run it. Reasons for every rule below: `.claude/guides/ship.md`.

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
pnpm audit --prod --audit-level=high   # known CVEs in what ships — the one
                        # security surface a machine reads better than a reviewer
pnpm audit --dev --audit-level=high || true   # dev-only CVEs: reported, never
                        # blocking — a build tool never reaches a user
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

<!-- FILL: if this repo has a second unit runner (backend), add it to the same
     batch when the diff touches its surface. E2E is NOT added here: it runs in its
     own command AFTER this batch is green, never alongside vitest and coverage —
     sharing the machine with them is what makes a browser suite flaky
     (`e2e-playwright` skill, "When it runs"). -->

All green is the condition to continue. **Red = stop and fix** — never ship
"green except one", and never skip this batch because CI repeats it.
`pnpm test:run` green is not enough: the diff must **add** the tests for its new
business logic (`.claude/rules/05-testing.md`). Coverage is a floor, not an
argument against a review finding.

**The security lines read differently.** `pnpm audit --prod` red with a fix →
bump and re-run; with **no published fix** → announce the package, the advisory
and whether the path is reachable, and the user decides (`00-project.md`). A hit
on the `grep` is never negotiable: `VITE_*` ships in the bundle, so rename a
public value or stop on a leak. **Read the grep's exit code, not its silence**:
exit 1 with no output is clean; exit 2 means a path could not be read — name it
and say the check did not run. Do not change a character of that pipeline without
reading the guide.

### 1bis. Security audit — armed by the token profile, not by memory

Read the profile carried by the artifact. **On `critical` only**, one
`/audit:security` runs before the commit, scoped to **one surface** — one
`security-auditor`:

| What made it `critical` | The surface to audit |
| --- | --- |
| authorization, roles, guards, a new table or endpoint | `authz` |
| payment, billing, anything with a money amount | `authz`, and `input-output` if a webhook or a callback is involved |
| destructive data change (delete, bulk update, migration with data loss) | `authz` |
| session, login, logout, token handling | `session` |
| explicit user request | ask which surface, or run `everything` if they said so |

A Critical finding stops the ship like a red gate: the track stays in its
worktree and the fix comes back through the loop with its reproduction test, never inline here. Not `critical` but the diff
seems to deserve it → say so in one line and ask.

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
the fix. It does not merge. **Not fixing it today → give the line back**: board
line → `BLOCKED` with its reason, from the main tree, story `Status` →
`Approved`. Still fixing it in this session → leave it `IN LOOP`.

### 5. Advance the state

In the main tree, after 4bis — the product files never change in a worktree.

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
  move on. Nothing else writes `Current surface`.

- Write nothing to `docs/work/<slug>/` — it stays as the trace of the loop.

### 6. Next feature

Read the board and name the **topmost** `READY` line + the command that opens it:

```
/loop:orchestrate docs/specs/<next>.md          (light)
/loop:orchestrate docs/stories/<slug>/<n>.md    (full)
```

**Topmost**, not "a" `READY`: row order is the priority. If the top line is wrong
for today, say which one you would take and **why**, and let the user answer.
No `READY` line → say so, never invent one. `BLOCKED` is not a candidate: list
those with their reason and let the user decide.

The user answers "not that one, and not later" → write `DROPPED` (you are one of
the three commands allowed to), only for that decision taken here, never for a
line that looks stale and never by deleting the row. On the full pipeline the
story goes with it: `Status` → `Dropped`, the reason in its Change Log. "Not now"
is the line staying `READY` below, or `BLOCKED` with its reason.

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

Then end the turn with one line to the user, in their language: the feature is
shipped, type `/clear` then `go` to start the next one. A session that chains
features rereads every previous one at each turn; `/clear` is the user's command
(it works from Remote Control), and after it the SessionStart hook
`next-feature-on-clear.py` hands the fresh session the feature `go` starts.

## Rules

- Report faithfully: a skipped gate is announced, not implied.
- Never the watch-mode script. Always the run-once one.
- Never push or open a PR without an explicit go-ahead.
- Same for a merge back into the base branch, and never two at once
  (`.claude/guides/10-worktrees.md`).

## Task: $ARGUMENTS
