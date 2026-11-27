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

Through the whole ship the session cwd stays at the project root (or the track's
worktree root): a subfolder gate runs as `pnpm --dir <sub> …`, `git -C <tree> …` or
one `(cd <sub> && …)` subshell, never a bare `cd <sub> && …` that persists — the
`github` agent launched after it inherits the subfolder and its push leaves the exact
form the hook allows.

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
roots="$(jq -r '.app_roots[]? | . + "/src"' .claude/project.json 2>/dev/null)"
[ -n "$roots" ] || roots=src
dirs=""
for d in $roots; do
  if test -d "$d"; then dirs="$dirs $d"; else echo "SCAN NOT RUN: no $d"; fi
  [ -f "${d%/src}/.env.example" ] && dirs="$dirs ${d%/src}/.env.example"
done
[ -n "$dirs" ] || dirs=/dev/null
grep -rnE 'VITE_[A-Z0-9_]*(SECRET|PRIVATE|SERVICE_ROLE|PASSWORD|TOKEN|_KEY)' \
     $dirs $( [ -f .env.example ] && echo .env.example ) \
  | grep -vE '(ANON|PUBLIC|PUBLISHABLE)_KEY'   # everything VITE_* ships in the
                        # bundle — the second grep drops the keys that are
                        # public by design, or this line cries wolf every run
```

**Project slot `extra-gates`** — `## extra-gates` in `.claude/overlays/commands/loop/ship.md`; absent → none: only the fence above runs.
A second unit runner (backend) listed there joins the same batch when the diff touches its
surface. E2E is NOT added here: it runs in its own command AFTER this batch is green, never
alongside vitest and coverage — sharing the machine with them is what makes a browser suite
flaky (`e2e-playwright` skill, "When it runs").

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

### 1bis. Security audit — armed by the profile, aimed by the diff

Read the profile carried by the artifact. `economy` and `standard`: no auditor,
the report prints `not armed — profile <…>`. **On `critical` only**, before the
commit:

1. `<base>` is the plan's `Base:`, else `git merge-base HEAD <default branch>`.
   Run `python3 .claude/hooks/kit-audit-surface.py select --base <base>`: it reads
   the working tree against `<base>`, untracked files included, and returns the
   surfaces the diff touches with one reason each — `authz` for a path under a
   declared server root, `session` and `input-output` for added trigger lines.
   The ship stops like a red gate on any non-zero exit of the script.
2. The profile reason is kept as the record of why the work is `critical`; its
   surface counts only when the diff touches it, so the selection is the script's:

   | What made it `critical` | Its surface, when the diff touches it |
   | --- | --- |
   | authorization, roles, guards, a new table or endpoint | `authz` |
   | payment, billing, anything with a money amount | `authz`, and `input-output` if a webhook or a callback is involved |
   | destructive data change (delete, bulk update, migration with data loss) | `authz` |
   | session, login, logout, token handling | `session` |

3. The main thread may add a surface the script missed, printing `Audit added:
   <surface> — <reason>`; it **never drops** one the script returned. An explicit user request runs
   the surfaces the user named, whatever the script returned.
4. Something selected → launch **one `security-auditor`** directly with every
   selected surface, each surface's definition from `/audit:security`, the changed
   files and the script's reasons — never `/audit:security <list>`, which runs all
   six. Nothing selected → no auditor; the report prints `Audit: not armed — diff
   touches no audit surface (<the script's reason>); review security ran`.
5. Write the auditor's Critical, Major and Minor items with Write to
   `docs/work/<slug>/audit-1.json`, an object `{"findings": [...]}` (a bare list is refused;
   each item holds `surface`, `severity`, `path`, `line` or
   `null`, `problem`) and run
   `python3 .claude/hooks/kit-audit-surface.py follow-ups docs/work/<slug>/audit-1.json`:
   every Major and Minor lands in `follow-ups.md`. Exit 2 means that JSON is wrong:
   correct it and rerun, never invent a line or drop a finding.

Skeleton (accepted as written by `kit-audit-surface.py follow-ups`; copy it and change the values):

```json
{
  "findings": [
    {
      "surface": "authz",
      "severity": "Major",
      "path": "server/routes/orders.py",
      "line": 42,
      "problem": "the delete route does not check the caller owns the order"
    }
  ]
}
```

`next: stop` — a Critical — stops the ship like a red gate: the track stays in its
worktree and the fix comes back through the loop with its reproduction test, never inline here. Not `critical` but the diff
seems to deserve it → say so in one line and ask.

### 2. Acceptance criteria

Walk the entry artifact's criteria one by one. For each: checked, and **how it was
observed**. A criterion nobody can observe is not met.

**Frozen cases amended during the pass.** Every `amended` line of `plan.md`'s
`## Gate` (a plan-gate row, or an EXECUTE batch, `orchestrate.md` Phase 4) goes
into the PR body (`Frozen cases`), each with its test hunk, on `4bis-PR`, and is
the user's to confirm in the merge presentation only on `4bis-local`. A refused
amendment goes back to EXECUTE, then `/loop:review` and this command from step 1.

### 3. Deploy (only if the diff requires it, and only on request)

**Project slot `deploy`** — `## deploy` in `.claude/overlays/commands/loop/ship.md`; absent → no deploy known: ask the user.
The section holds the real deploy commands and their traps. Two that bite everywhere: a bulk
deploy silently resets per-unit flags, and a migration push applies EVERY pending migration —
including ones another session wrote. List the pending state before pushing.

Announce what needs deploying and **ask** before running it.

### 4. Commit

First remove the applied `.tdd-unfrozen` entries in one Edit (delete the lines
or comment them out with the bare `# ` prefix of the exact line, nothing else: an annotated
`#` line is denied; that Edit narrows the freeze and does not ask). Then
hand the `github` agent the subject only — never body bullets; a body belongs
to the PR. Delegate to the **`github` agent**: it stages, writes the Conventional Commit
message, commits locally, and never signs. It commits **on a branch, never on
`main`** (`enforce-git-workflow.sh` refuses it) — the track's `feat/<slug>`; on the base
branch, `git switch -c feat/<slug>` first. The pass's own push and PR follow
`4bis-PR` with no chat confirmation; any other remote action keeps the user's
go-ahead — that gate belongs to the agent, don't bypass it. Nothing leaves the
machine without its `amended` lines: the PR body carries each with its test hunk.

Also hand the agent the `Screenshots run:` dir from `## Gate` (or `none`) and
`<base>`. The order, when a PR is opened: (a) the agent commits; (b) on a PR with
a recorded run, the agent runs Publish steps 1-5 (`github.md`, "PR screenshots on
`pr-assets`") and returns the `section` text; (c) the main thread then writes
`docs/work/<slug>/pr-body.md` with Write, `Screenshots` block included; (d) the
agent is called again to run `gh pr create ... --body-file`.

### 4bis. Integrate

Every loop pass ends on a branch, worktree or not — so this step always applies.
`git remote get-url origin` picks the subsection: a remote → `4bis-PR`, none →
`4bis-local`. **One integration at a time** — never two merges in flight.

#### 4bis-PR (a remote exists)

Nothing is replayed or merged locally and nothing is force-pushed: the server
merges. Via the `github` agent, in this order:

1. `git push -u origin <branch>` — the pass's `feat/<slug>`.
2. The main thread writes `docs/work/<slug>/pr-body.md` with Write, on `github.md`'s
   PR template: `Frozen cases` (every `amended` line with its test hunk), `Open
   questions` (answers taken), `Review` (surviving findings), `Gates`, and
   `Screenshots` when a run is recorded (step 4's order). The block comes only after the `github` agent
   reported the commit and the push (never in parallel with them: it is computed on the
   shipped HEAD and ends on a `head:` line naming it): run `git fetch origin <base>`, then
   `python3 .claude/hooks/loop-record.py --guarded-block`: in `auto` or on a released record (it prints a
   non-empty block) the body also carries `Decided without you` (the record's arbiter verdicts) and
   `Contract contradiction` (when any) after the summary, and `Guarded files touched`: paste that output
   verbatim — the git hook recomputes it and denies `gh pr create` unless the body holds it byte for byte.
3. `gh pr create --repo <owner/repo> --base <recorded base> --head <branch> --title "<title>" --body-file docs/work/<slug>/pr-body.md`.
4. After `gh pr create` returns its URL, and only when a `Screenshots run:` is recorded in `plan.md`'s
   `## Gate`: the main thread runs `python3 .claude/hooks/kit-pr-assets.py prune-local --slug <slug> --keep <the
   plan's Screenshots run: dir>`, alone in its own Bash call. It deletes the PNGs of the slug's older
   run dirs under `.pr-shots/<slug>/` and their emptied dirs, keeps the shipped run, and refuses a
   `--keep` that is not a run dir of that slug (exit 2: report it, delete nothing by hand).

In `auto`, a red gate after its fix budget, or any other blocked-stop cause
(`/loop:orchestrate`, "Validation mode"), ends here: a blocked stop pushes nothing and
opens no PR; the commits stay local and the record is kept, marked by `python3 .claude/hooks/loop-record.py --block` (`/loop:orchestrate`, "Blocked stop"). The record allow does not hold on a blocked record; only the user's `python3 .claude/hooks/loop-record.py --release` lifts it (the pass resumes in `moi`); `--clear` deletes the record and its ledger.

With the tree's valid loop record (the user's plan-gate go) and the server barrier,
and unless the record is released (then each asks), 1 and 3 run without a prompt and **without a chat confirmation**; otherwise each asks
once, through the hook. Report the PR URL, and for a stacked pass the merge order
(its base's PR first). Write the handoff with `phase: awaiting-merge` and
`pr: <url>`; the main tree stays on `feat/<slug>` (the board line and story status
committed with the pass stay visible). Closing belongs to the **closing check**
(`orchestrate.md` Phase 0 step 0, `tracks.md`): `.claude/scripts/loop-pr-state.sh --chain feat/<slug>`
reads the PR's `MERGED` state and `baseRefName`; `closable` runs step 5, then
`4bis-local` item 3's clean-up — except a kit-local worktree, which runs
`kit-track.py close <slug> --merged` first, then step 5 (`orchestrate.md` Phase 0 step 0).

#### 4bis-local (no remote)

Via the `github` agent:

1. Rebase `feat/<slug>` on the current base branch. If the rebase moved anything,
   **re-run the gates** — the code that merges is not the code you tested.
2. Present the branch, the diff summary, every `amended` frozen case of
   `## Gate` (section 2 above) — id, old and new case line, reason, and the test hunk
   from the diff, so the user confirms the change itself, not its description —
   the count of lines in `docs/work/<slug>/follow-ups.md` with its path (or
   `follow-ups: none`), no board line written from it,
   and the exact merge command, and **wait for the go-ahead**. Merging is as gated
   as pushing. A refused amendment first re-adds its
   `.tdd-unfrozen` entry (`<path>  # <id>: <reason>`), then goes back to EXECUTE and `/loop:review`.
3. After the merge, clean up. No worktree → `git branch -d feat/<slug>`, done.
   A **kit-local** worktree (its `.claude/.kit-snapshot` exists) → from a main-tree session, never the
   track's own: `python3 .claude/scripts/kit-track.py close <slug>` copies the track's docs back, reports kit
   drift and removes the tree, before step 5; then the main-tree handoff → `phase: shipped` and
   `git branch -d feat/<slug>`. The track session (it stands in the worktree) writes its handoff
   `phase: awaiting-merge` with `pr: none`, prints the exact main-tree command
   `python3 .claude/scripts/kit-track.py close <slug>` and stops: the closing check picks it up
   once `feat/<slug>` is an ancestor of the main tree's HEAD. It replaces everything below; never a bare `git worktree remove`.
   Otherwise, before any removal, check the track's `docs/`: `git -C <tree> status --porcelain -- docs/`
   must print nothing (an untracked or modified file there never reached the merge: name each one,
   stop, and route it through a commit on the branch); then list the
   ignored files under `docs/work/<slug>/` (`git -C <tree> ls-files --others --ignored --exclude-standard -- docs/work/<slug>/`)
   that the removal deletes — the handoff and `pr-body.md` are the pass's trace, the PR already
   carries the body — so the user sees them before they go. Tracked `docs/` reach the main tree
   only through the merge and the `--ff-only` sync, whose conflicts stop rather than overwrite.
   Then **mind who is standing where**:
   - the session is **inside** the worktree → `ExitWorktree` with `keep`, then
     `git worktree remove .claude/worktrees/<slug>`, then `git branch -d feat/<slug>`
     (a `remove` exit would delete the tree around a record that stays valid in it).
     Git cannot delete the tree you are standing in, and the `github` agent has no
     such tool: leaving it is the main thread's job.
   - the worktree belongs to **another** track → `git worktree remove
     .claude/worktrees/<slug>` then `git branch -d feat/<slug>`.

   Never `--force`, never `rm -rf` (the Bash hook denies or asks on both). A refusal means
   uncommitted work: report it, don't override it. Then
   `python3 .claude/hooks/loop-record.py --clear`: the record authorised this pass only.

A red gate or a failed review means the track stays in its worktree and loops on
the fix. It does not merge. **Not fixing it today → give the line back**: board
line → `BLOCKED` with its reason, from the main tree, story `Status` →
`Approved`. Still fixing it in this session → leave it `IN LOOP`.

### 5. Advance the state

In the main tree, after 4bis — the product files never change in a worktree.
`4bis-local` runs this step right after the merge (after `kit-track.py close` for a kit-local worktree). On `4bis-PR` the story stays
`InProgress` and the board line `IN LOOP` until the closing check prints
`closable`; then it runs (a `closed` PR → board `BLOCKED` "PR closed unmerged",
story `Approved`).

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
- **`pr-assets` cleanup**, when the repo has a remote `pr-assets` branch: list the
  `MERGED` PRs (`gh pr list --state merged --json number,headRefName`). Skip any
  branch name that still has an open PR (`gh pr list --state open --head <B>`).
  For each of the others, offer the cleanup: `kit-pr-assets.py drop` on that
  PR's body, as in `github.md`. Each `gh` call and the push keep their default
  prompt.

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

## Small-ticket integration

For `Pipeline: small`, step 4 runs `small-scope.sh <name>` before the commit; a
refusal ejects. With a remote, push `feat/small-<name>` and open its PR on the
spec's `Base:` with `gh pr create --repo <owner/repo> --base <Base> --head feat/small-<name> --title "<title>" --body-file docs/work/small-<name>/pr-body.md`;
both ask once (a small pass has no loop record), then print the PR URL.
With no remote: in 4bis.1, rebase onto the spec's `Base:` branch. In 4bis.2,
confirm `git -C <main-tree> branch --show-current` equals that Base and that no
main-tree loop is active; otherwise print `main tree on <x>, not <base>: merge later`.
Then merge with `git -C <main-tree> merge --ff-only feat/small-<name>`. The
`<main-tree>` is the first worktree from `git worktree list --porcelain`; the
merge asks through `enforce-git-workflow.sh` on main/master, through the default
permission prompt otherwise. In 4bis.3 print, but do not run here,
`git worktree remove .claude/worktrees/small-<name>` and `git branch -d feat/small-<name>`.

Step 5 has no board line to move. Step 6 and the closing line print that cleanup,
then `/loop:small --status` to run in the main session, then `close this terminal`.

## Output

```
## Ship: <feature>
- Gates: typecheck ✓ | lint ✓ | test:run ✓ (<n> tests) | coverage ✓ (<n>%, or "no config") | build ✓
- Security: audit ✓ (<n> advisories, or "<pkg> — no fix published, your call") | bundle secrets ✓ (or "SCAN NOT RUN: <the missing path>")
- Audit: <surfaces> — <n> Critical / <n> Major / <n> Minor → <k> in docs/work/<slug>/follow-ups.md   (or "not armed — profile <economy|standard>", or "not armed — diff touches no audit surface (<reason>); review security ran")
- Criteria: <n>/<n> met — <the unmet ones, if any>
- Deploy: <done / pending your validation / n/a>
- Commit: <hash> <subject>   (remote: <pushed / awaiting validation / not asked>)
- Branch: feat/<slug> <in main tree | in .claude/worktrees/<slug>> — <merged | awaiting your validation | still open>
- PR: <url> — awaiting merge   (4bis-PR; "none — no remote" on 4bis-local)
- Follow-ups: <n> in docs/work/<slug>/follow-ups.md   (or "none")
- Board: <feature> → SHIPPED   (4bis-PR: "<feature> stays IN LOOP until the PR merges")
- Next: <feature> — <command>
```

Then end the turn with one line to the user, in their language: the feature is
shipped. For a small ticket, print its cleanup, `/loop:small --status` to run in
the main session, then `close this terminal`. A session that chains
features rereads every previous one at each turn; `/clear` is the user's command
(it works from Remote Control), and after it the SessionStart hook
`next-feature-on-clear.py` hands the fresh session the feature `go` starts.

## Rules

- Report faithfully: a skipped gate is announced, not implied.
- Never the watch-mode script. Always the run-once one.
- The pass's own push and PR follow `4bis-PR`; any other push or PR needs an
  explicit go-ahead.
- So does a local merge back into the base branch, and never two at once
  (`.claude/guides/10-worktrees.md`).

## Task: $ARGUMENTS
