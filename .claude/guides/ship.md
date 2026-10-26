# /loop:ship — why the last step is shaped this way

Read when changing `.claude/commands/loop/ship.md`, or when one of its rules
looks arbitrary. The command keeps the instructions; the reasons live here.

## The local gates are the gate, CI is the backstop

`.github/workflows/ci.yml` is the copy nobody can skip from their own machine;
the `/loop:ship` batch is the copy that runs while the fix is still free, before
the commit exists. Skipping it because "the CI will catch it" turns a local red
into a pushed red, a force-push and a broken `main` for everyone else.

The coverage gate is a floor, not a verdict: it makes an unwalked branch
impossible to ship silently, and says nothing about whether the assertions bite —
that is `/loop:review`'s `tests` dimension. Passing it is not an argument against
a review finding.

## The security lines

Both are the deterministic half of `/audit:security`'s `supply-chain` and
`secrets` surfaces: no network, no agent, no tokens, run on every ship because
nobody has to remember them. Anything named `VITE_*` is compiled into the bundle
and readable by every visitor, so a secret-shaped name there is either a misnamed
public value or a leak that shipping would publish.

The bundle grep is written with `set -o pipefail` and without `2>/dev/null` on
purpose. The previous spelling threw away grep's exit 2 (a path it could not
read), and without `pipefail` the pipeline returned the second grep's status:
measured on an empty tree, the piped form exits 1 — "clean" — where the bare
first grep exits 2. `install.sh` scaffolds no `.env.example`, so grep #1 exited 2
on essentially every run and the check reported clean without having run. The
`$( [ -f .env.example ] && … )` keeps an absent template from being an error; a
missing `src/` still is one, and is named. The pattern is a **name** heuristic,
not a value scanner: it catches `VITE_STRIPE_SECRET`, not a real key behind a
bland name. It is a floor.

## Why `critical` arms an audit

`11-token-budget.md` reserves `critical` for payment, authorization, destructive
data changes or an explicit request — the list of features where a missing
server-side barrier is not a Minor. The same condition arms both: the profile is
the repo's statement that this feature is one of the dangerous ones. One surface
is one `security-auditor`, so the cost is that agent on `critical` and zero
elsewhere. Running it unasked on every feature is the token cost the audit was
put out of the loop to avoid.

## Why advancing the state comes after the merge

`docs/product/backlog.md` and `docs/product/brief.md` are on `10-worktrees.md`'s
"never in a worktree" list — one file, every track. Moving the state before the
merge puts a conflict on the shared product files at every integration.

`Current surface` in the brief is what `/bmad:pm` narrows its exploration on and
`/loop:spec` leans on. Nothing else in the loop writes it, so without the ship
update it freezes at the day `/loop:product` ran while the code moves, and the
next feature is framed against a description that is wrong with authority.

## Why the topmost `READY`, and when to write `DROPPED`

Row order is the priority — the only place the kit writes one down. Picking the
`READY` line noticed first hands a product decision to an accident of parsing,
and the answer looks exactly like a priority. `BLOCKED` is a line somebody put
down on purpose, waiting for a person; naming it as next re-opens a decision in
silence.

`DROPPED` only for the user's decision taken in this turn, never for a line that
merely looks stale, and never by deleting the row: a deleted line reads as a unit
nobody ever thought of. On the full pipeline the story's `Status` → `Dropped`
too: drop the row alone and the story stays `Approved`, so the next
`/loop:tracks` forks a unit the user just killed.

## Giving the line back

A track that stops without shipping leaves its line `IN LOOP`, which asserts a
session holds it right now: `/loop:tracks` will not fork it and step 6 will not
name it, so the unit vanishes from the loop while looking healthy.
