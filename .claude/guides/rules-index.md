# The rules index — how rules load, and where a new line goes

Read when adding, moving or cutting a line of `CLAUDE.md` or `.claude/rules/`.
`CLAUDE.md` keeps one line pointing here.

## The `@` lines are the loader, not an index

Nothing walks `.claude/rules/` on its own — there is no `SessionStart` hook for
rules, and Claude Code reads `CLAUDE.md` plus its imports. A rule dropped into
that directory without an `@` line in `CLAUDE.md` **never reaches a session**,
silently. `/kit:doctor`'s `rules-loaded` compares the two lists.

## Every rule declares a line budget

A `<!-- budget: N -->` comment on its first line; `/kit:doctor`'s `rules-budget`
fails when a file passes it, and `test-rules-floor.sh` holds the total. The
budget is not tidiness: these files are re-read in full by every session **and by
every subagent**, so a paragraph added there is a paragraph multiplied by the
whole fan-out of the loop. Passing a budget is a decision — raise the number in
the same commit, and say what it bought.

## Three exits for anything that does not fit, in this order

1. **A hook's deny text already says it** → delete. The deny fires at the exact
   moment, names the file and prints the way out. Describing a refusal in a rule
   is paid by every session to prevent an attempt the hook stops for free.
2. **A pattern or template is read at the moment it applies** → move it there.
   That is why no settled fact lives in `01-stack.md` any more.
3. **It is a retrospective** → `.claude/guides/`, same authority, loaded by
   nobody, read when something names it by path.

The line that decides between 3 and staying: **a trap stays in the rule, a
retrospective goes to the guide.** A trap changes what an agent does when it has
never met it. And a whole rule moves out only when **something names it at the
moment it applies** — `05-testing.md` never qualifies, its freeze fires on a
write nobody announced.

## The gates run once or twice, never zero

`/loop:ship` runs them before every commit, on this machine — that copy exists
whatever the project's remote. When the project has one, `.github/workflows/ci.yml`
runs them again where nobody can skip them; a green CI is then not a reason to
stop running `/loop:ship`, since it reports on a diff already pushed. No remote →
no workflow installed at all, and the gates are unchanged
(`.claude/skills/templates/ci.md`).

## Why the loop's gates come in two kinds

`/loop:interface` and `/loop:plan` fix **what is to be built** — the retained
proposal is what makes `/loop:review` scoring a divergence as Major honest, and
the printed test plan is the last point where changing "correct" is free, since
those test files freeze right after. Neither substitutes for the other and
neither proceeds on silence. `/loop:ship`'s gates and `/loop:tracks`' fork decide
**what leaves the machine**, never what it should be.
