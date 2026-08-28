# Rationale — why LoopKit is built this way

The [README](../README.md) says what the kit does and how to run it. This file
says **why**, and it is the only place that argues. Nothing here is required
reading to use the kit; everything here is required reading to change it.

---

## The product layer, above both entries

`/loop:product` runs **once per product** and writes two files nothing else can
replace.

`docs/product/brief.md` is the frame: what the product is, who it serves, the
surface that already exists — and two sections that are decisions rather than
observations, **chosen by you in a closed question**, never composed by the agent
and shown to you afterwards.

**`Product invariants`** are the rules no feature may break, and they are the only
construct in the kit with two independent enforcers: `story-critic` refuses a
*story* that contradicts one (Critical, escalated to you — never fixed by
softening the story), and `/loop:review`'s `correctness` dimension replays the same
invariants against the **code that was actually written**. Neither covers the
other, and a feature entering by `/loop:spec` only ever meets the second.

**`Out of product`** is the durable anti scope-creep, and it has exactly one
enforcer: `story-critic` refuses a story that delivers what it excludes (Major,
escalated — the boundary may be stale, and only you move it). Nothing replays it
against a diff, so on the light path `/loop:spec` checks it once, out loud, at the
moment the contract is written.

So write both as sentences somebody who was not in the conversation can refuse
something with, not as intentions. `/loop:product` reads them back and waits before it
opens the board: a frame you have not agreed to is a queue built against the
wrong product.

`docs/product/backlog.md` is the board — the thing `FEATURE READY` means in the
README's diagram. **One line per unit of loop**: a spec is one line, a full
pipeline is one line per story. Six states, one owner each: `/loop:product` writes
`DRAFT` (noticed, framed by nothing) and it alone, which is what makes the gate able to
refuse; `/loop:spec` and `/stories:review` write `READY` because a contract or a
reviewed slice exists behind the line (`/loop:orchestrate` too, for the one case of an
artifact on disk and on no line); `/loop:orchestrate` takes it to `IN LOOP`;
`/loop:ship` closes it as `SHIPPED` and names the next `READY`. The two that keep the
board honest are `BLOCKED` — a loop that stops without shipping *gives the line
back*, or the board claims forever that a session is on it — and `DROPPED`, so a
unit decided against does not read like one nobody thought of; that one is
written by the story gate, or by `/loop:product` and `/loop:ship` for a decision you take in
front of them, never inferred from a line looking old — and always with the story
file's `Status` moved in the same pass, since that is the half `/loop:tracks` reads.

**The order of the rows is the priority** — the only place the kit writes one
down. `/loop:ship` takes the *topmost* `READY`, `/loop:product` is the only command that
reorders, and everything else appends at the end. Without that, "the next
feature" is whichever line the reading landed on, and it looks exactly like a
decision.

The full state machine, its columns and its transitions live in `/loop:product` and
are cited from everywhere else, never restated.

Neither file is required: no brief and the commands say so and investigate more;
no board and the gate is announced skipped. They are what stops the twentieth
feature being framed against a product description written for the first.

## Two entry points, one loop

**Simple** — one screen, a CRUD, a fix: `/loop:spec` asks 3–4 questions, writes the
contract, stops. You review the acceptance criteria before anything ships.

**Complex** — several epics: `/bmad:pm` writes a PRD, `/bmad:sm` slices it into
**functional** stories, `/stories:review` puts them through a gate,
`/bmad:architect` builds the architecture on top. Then each story enters the same
loop — `/bmad:dev` runs the build for one story and keeps its bookkeeping,
`/bmad:qa` gates it and writes the verdict into the story file. `/bmad:flow`
drives the whole chain end to end.

> Stories come **before** the architecture. A badly sliced story is rewritten in
> two minutes while it is still functional; after an architecture has been built
> on it, it costs a day.

## The design system, a hard prerequisite of `/loop:interface`

Without `docs/design-system.md`, interface proposals invent components instead of
composing with the ones that exist. `/loop:design-system` produces that document, in
one of two automatically detected modes:

- **`extract`** — the system is already in the code: 4 explorers read it, the
  command writes it down. This is the normal case, and the only one after the
  first story.
- **`bootstrap`** — a product starting from zero, nothing to read: 3 `designer`
  agents each propose a complete system (tokens, primitives, two reference
  screens), the previews are published, and **you decide**. A visual direction is
  a matter of taste and positioning; agents have no eyes. No component is written
  at this stage — they arrive with the stories, with their tests.

`bootstrap` runs once in the life of a product.

> **`/loop:interface`, not `/design`.** Claude Code ships its own `/design` skill (the
> Claude Design canvas, research preview), and the step uses it to render the
> retained proposal as editable *artboards* before the gate — a graft is made by
> hand instead of being described. A project command with the same name would
> shadow the skill, hence the name. `design.md` stays the contract, the canvas is
> only its mirror: details in `Claude_Workflows.md`.

---

## The three ideas the system runs on

### 1. Parallelise independent information, share the common context

Genuinely independent probes, design angles and review dimensions can fan out.
Artifacts that read the same source are grouped: `/bmad:sm` writes up to 8
stories inline then in batches, and `/stories:review` uses at most 3 critics.
**EXECUTE stays strictly sequential**: two agents on coupled code cost more than
waiting. One exception, and it is not there for speed: the **RED** leg runs in an
isolated `test-writer`, so that the context writing the test is not the one about
to write the implementation.

What holds _inside_ a feature does not hold _between_ features: two distinct
pieces of work running at the same time each take their own **worktree** and
branch (`.claude/worktrees/<slug>`, `feat/<slug>`), and integrate one at a time,
with your go-ahead. What never forks: migrations and the database, `src/lib/`,
`shared/`, the router, the lockfile — they go through the main tree first.

**How many at once is computed, not chosen.** `/loop:tracks` reads the story map
against the code, works out what can genuinely run in parallel right now (3 at
most), and prepares the worktrees for it. It is recomputed after every merge,
because merging one track is what unblocks the next.
Rule: [`.claude/guides/10-worktrees.md`](../.claude/guides/10-worktrees.md).

#### Supervised launch, Claude → Codex

Use the wrapper instead of `claude`:

```bash
./workflow.sh
# or with Claude's usual arguments:
./workflow.sh /bmad:flow "my feature"
```

The status line watches the context window: checkpoint at 90%, no new subagent at
95%, controlled interruption and Codex launch at 97%. The supervisor also detects
usage-limit messages in Claude's output. Checkpoints are refreshed after every
phase and every TDD layer.

For the subscription quota, the supervisor reads the CLI's warnings: 90–94%
writes a checkpoint without interrupting Claude, 95% triggers Codex, and a real
limit hands over immediately. If the CLI's wording differs, the pattern can be
supplied through `CLAUDE_WORKFLOW_QUOTA_WARNING_REGEX`; the first capturing group
must be the percentage used.

The status line's thresholds are about the context window, separately.

#### Token profiles and the Codex handover

The loop uses `economy` by default. `standard` adds independent eyes on ambiguous
features; `critical` keeps the maximum fan-out for payment, authorization,
destructive changes or an explicit request — and it is also what arms the
security audit at `/loop:ship` (see below).

**The profile is chosen at the product step, not at launch.** `/loop:spec` and
`/bmad:pm` ask the closed question and write `Token profile:` at the top of the
spec or PRD, `/bmad:sm` copies it onto every story, and `/loop:orchestrate` inherits it
from the entry artifact. The flag below is an override, not the normal path — a
feature reaching the loop without the line ships `economy`, and with it the audit
that was supposed to be armed by the feature's own nature.

```bash
/loop:orchestrate --economy docs/stories/<slug>/1.1.md
/handoff:codex docs/work/<slug>/plan.md
./codex-handoff.sh docs/work/<slug>/handoff-codex.md
```

If Claude is cut off before the checkpoint, hand the launcher the last plan,
research, story file or spec directly. Codex rebuilds the phase from the
artifacts and the Git state. The launcher stays external: a Claude that has
already hit its limit cannot invoke anything.

### 2. Everything goes through disk

Subagents see neither the conversation nor each other. `docs/work/<slug>/` is the
loop's shared memory — and what makes it possible to resume in a fresh context,
three days later, without losing anything.

### 3. A gate that never rejects anything gates nothing

`/loop:review` has two stages. First `reviewer` agents whose default bias is "there is
a problem", one per dimension. Then, on every Critical or Major finding, a
`verifier` whose job is to **refute** it. What survives an honest attempt at
refutation deserves a fix; the rest is noise you paid for once and never have to
read again.

---

## The agents

| Agent          | Role                                                                                               | Writes?                                |
| -------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `explorer`     | Read-only cartography (patterns, wiring, what can be reused)                                       | no                                     |
| `doc-researcher` | Researches ONE third-party surface, hard network cap (6 searches, 12 fetches) — reads the cache before fetching | its cache file |
| `story-writer` | Writes a bounded batch of stories from the PRD — functional, never technical                       | 1 batch of files                       |
| `story-critic` | Judges a batch of stories and the overall coherence from their catalogue                           | no                                     |
| `plan-critic` | Scores plan completeness and quality independently before EXECUTE                                 | no                                     |
| `designer`     | Proposes a UI on an assigned angle, judges the 3, or (mode `system`) proposes a whole design system | its candidate folder, in `system` mode |
| `test-writer`  | Writes ONE test-first file, runs it, returns the failure — without ever reading the module under test | 1 file                                 |
| `reviewer`     | Adversarial review on one bounded group of dimensions                                              | no                                     |
| `e2e-tester`   | Writes and runs ONE Playwright spec — proves a flow in a real browser                              | 1 spec                                 |
| `verifier`     | Tries to **refute** a finding — what survives is real                                              | no                                     |
| `security-auditor` | Security audit of **one surface**, on the whole repository (not on a diff) — out of the loop, except on a `critical` profile where `/loop:ship` arms one | no |
| `github`       | Local commits; anything touching GitHub asks for your go-ahead                                     | yes                                    |

## The guardrails

The rules live in `.claude/rules/` and are loaded at every session. Whatever is
**mechanically detectable** is doubled by a hook, because a rule you can check
beats a rule you re-read.

**The loading mechanism is `CLAUDE.md`'s `@` import list**, and nothing else —
there is no `SessionStart` hook, and no directory is walked on its own. A rule
dropped into `.claude/rules/` without an `@` line **never reaches a session**;
`/kit:doctor`'s `rules-loaded` is what says so. A rule you want read on demand is
**moved** into `.claude/guides/`, which nobody loads and which is cited by path.

Those files are re-read in full by every session **and by every subagent**, so
each one declares a `<!-- budget: N lines -->` ceiling that `/kit:doctor`'s
`rules-budget` enforces, and the run prints the **session floor** — the token
floor is currently 557 lines / about 6,200 tokens, reduced from 1,245 lines by
routing contextual material through `.claude/skills/project-rules/` while
keeping traps and enforced twins in the hot rules. That is the cost paid
unconditionally, before any work. Three exits for what does not fit,
in order: a hook's deny text already says it (delete), a pattern is read at the
moment it applies (move it there), it is a retrospective (`.claude/guides/`).
What stays is a **trap** — something that changes what an agent does when it has
never met it.

| Hook                              | Event                  | Effect                                                                                           |
| --------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------ |
| `no-any-type`                     | before write           | refuses `: any`, `as any`, `<any>`                                                               |
| `enforce-architecture`            | before write           | refuses a cross-feature import, shared code depending on a feature, or the data client outside the data layer |
| `english-comments`                | before write           | refuses a non-English comment, a non-JSDoc implementation comment, a floating or overlong JSDoc block |
| `protect-files`                   | before write/read      | refuses `.env*`, `.pem`, `.key` in both directions; lock files, `.git/` and `node_modules/` on write only |
| `no-forbidden-icons`              | before write           | refuses the project's forbidden icon list                                                        |
| `prevent-destructive-commands`    | before Bash            | refuses `rm -rf` on protected directories, reading secrets from the shell, `chmod 777`, `dd`, force-removing a worktree, writing a test-first layer from the shell, and a snapshot `-u` on a frozen test |
| `enforce-git-workflow`            | before Bash            | refuses a commit on `main`/`master`, a signature (`-S`, `Co-Authored-By`); asks again for `git push`, `gh pr/issue/comment` and any merge into a protected branch |
| `tdd-require-red`                 | before write           | refuses to **create** `utils`/`mapper`/`repository`-`services` until its test has been seen failing |
| `tdd-freeze-tests`                | before write           | freezes those test files: adding a case passes, correcting a case is refused (`.claude/.tdd-unfrozen`) |
| `format-on-save`                  | after write            | formats the file just written (synchronous: what follows must read the formatted bytes)          |
| `eslint-check`                    | after write            | **queues** the file for linting — runs nothing, costs ~5 ms                                      |
| `eslint-batch`                    | end of turn / of agent | lints the whole queue in **one** ESLint process, non-blocking (the blocking lint stays `/loop:ship`)   |
| `tdd-prove-red`                   | after write            | runs the test just written, judges whether the red is real (symbols vs exports), and writes the marker `tdd-require-red` requires |
| `auto-approve-config`             | before read            | auto-approves reading config and documentation files                                             |

Hooks only catch what is mechanical and free of false positives; the ambiguous
part (business logic in a component, a dubious cast) stays the `reviewer` agent's
job.

The three `tdd-*` work as a trio, and it is the only place in the kit where a
rule is genuinely **impossible to route around**: `prove-red` observes,
`require-red` blocks while the observation is missing, `freeze` then stops the
test from drifting toward the code. Two things no hook can see are written down
in the rule instead: a fix opens with the test that **reproduces** the bug, and
an expected value never comes from the code under test — a `toEqual` that
re-spells the mapper's own transformation agrees with any implementation,
including a wrong one. Details: `.claude/rules/05-testing.md`.

### Security: three levels, one of which is a gate

| Level | What runs | When |
| --- | --- | --- |
| On the diff | `/loop:review`'s `security` dimension — the server-side barrier, exposed keys, Zod at the boundaries, leaks between users | every review; a Critical means FAIL |
| At ship | `pnpm audit --audit-level=high` + a grep for secret-shaped `VITE_*` names | every ship, deterministic, zero tokens |
| On the repository | `/audit:security` — 6 surfaces, `security-auditor` fan-out, then refutation | on demand; **and automatically on a `critical` profile**, one surface, before the commit |

The last row is the one that matters. An audit that only runs when someone
remembers is an audit that does not run — so the four triggers of the `critical`
profile (payment, authorization, destructive data changes, explicit request) arm
it, because they are word for word the features where a missing server-side
barrier is not a Minor. It costs one agent, and zero on every other feature.
Downgrading a feature to `economy` to skip it is a security decision wearing a
budget costume.

The two ship-time lines are there for the opposite reason: they are the only
checks that can turn red **without a single byte of the repository changing** — a
CVE published this week is invisible to any review of any diff.

### The allowlist, and why it excuses nothing

`settings.json` carries a `permissions.allow` block: read-only inspection
(`grep`, `cat`, `ls`, `find`, `sed -n`…), the git that changes nothing (`status`,
`log`, `diff`, `show`, `rev-parse`) and the project's six gates (`test:run`,
`typecheck`, `lint`, `build`, `test:coverage`, `audit`). Nothing else. `git
add`/`commit`/`merge`/`push` still ask — that is the `github` agent's convention
and it is deliberate.

Measured on a real project: out of 1925 tool calls, 22 blocked for more than two
minutes, including **107 minutes of unwanted prompts** — an agent stopped in the
middle of its work while nobody was watching. Not to be confused with the 79
minutes of **wanted** gates (`AskUserQuestion`, `ExitPlanMode`): those are the
loop working.

**Allowing is not bypassing the hooks.** A `PreToolUse` hook runs whatever
happens and its `deny` beats the allowlist: `cat` is allowed, `cat .env` is still
refused by `protect-files`. That is why the allowlist can be generous on reads —
the second layer holds. Widen it the same way: read your own transcripts, do not
guess.

`/kit:doctor`'s `gate-allowlist` check watches this list against `/loop:ship`'s gate
block, because this divergence is the only one that is **not** silent: a gate
without its allow entry does not fail, it *asks*, someone declines it by reflex
mid-batch, the other gates stay green and the ship reports success without it.

Every hook records its duration in `.claude/.hook-timings.log` (`CWK_HOOK_TIMING=0`
to turn it off). `.claude/hooks/hook-timings-report.sh` ranks them — read the
`TOTAL` column, not `AVERAGE`: a 40 ms hook fired 300 times costs more than a 3 s
hook fired twice. It is the only place where time spent in the guardrails becomes
visible; in a transcript it looks like the model thinking.

---

## The full repository layout

```
loopkit/
├── install.sh                 # drops the kit into a target project
├── CLAUDE.md                  # the project's constitution (a template to fill)
├── templates/github/          # ci.yml + the deploy.yml skeleton
│   └── publish/               # one Publish step per host — the CD target choice
├── docs/
│   ├── Claude_Workflows.md    # the full map of the workflow
│   ├── RATIONALE.md           # this file
│   └── ADAPTATION.md          # adaptation checklist, in order of importance
├── .claude/
│   ├── settings.json          # hook wiring + the allowlist
│   ├── rules/                 # 10 rules, loaded at every session
│   ├── guides/                # rationale + on-demand rules, never auto-loaded
│   ├── agents/                # 12 subagents
│   ├── commands/              # 30 slash commands
│   ├── hooks/                 # 14 wired guardrails, the status line, 3 standalone scripts
│   └── skills/                # patterns, templates, the e2e-playwright skill
└── addons/
    ├── supabase/              # everything that only makes sense on Supabase
    └── fastapi/               # Python backend: rules, /backend:*, hooks
```

**Commands** (26) — loop: `/loop:research` `/loop:interface` `/loop:plan`
`/loop:review` `/loop:ship` `/loop:orchestrate` · entries: `/loop:spec`,
`/bmad:pm` `/bmad:sm` `/stories:review` `/bmad:architect` `/bmad:dev` `/bmad:qa`
`/bmad:flow` · framing: `/loop:product` `/loop:design-system` · parallelism:
`/loop:tracks` · out of the loop: `/database:migration` `/audit:security`
`/audit:mutation` `/audit:part` `/refactor:split` `/refactor:clean`
`/refactor:types` `/kit:doctor` · handover: `/handoff:codex`.

## Addons, in full

**`addons/supabase/`** — stack + database rules (including **RLS**, the real
authorization barrier), the Supabase version of `/database:migration`, the
front-end patterns (client, generated types, realtime, storage) and edge
functions (auth, middlewares, cron, webhooks, tests). Installed with
`./install.sh <project> --supabase`.

It also ships `supabase/functions/_shared/`: the infrastructure layer the patterns
import, as real tested Deno code (`deno check` + 29 tests). Five more specific
helpers stay documented but **not shipped** — its
[README](../addons/supabase/README.md) says which, and reminds you to delete the
sections you do not implement. A pattern documenting a helper that does not exist
is an agent writing an import to nothing.

The addon does not duplicate the official Supabase plugin: it owns the project's
conventions, the plugin owns Postgres depth and whatever moves upstream.

**`addons/fastapi/`** — a Python backend with its own twin TDD cycle
(`app/services/**` test-first and frozen, its own three hooks, its own runner),
its `/backend:*` commands, and its own dependency-audit role — `pnpm audit` says
nothing about a Python tree.
