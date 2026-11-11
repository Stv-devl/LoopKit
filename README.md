# LoopKit

One loop from idea to commit for Claude Code — 31 commands, 13 subagents, 10
declarative rules and 15 hooks that mechanically refuse what the rules forbid.
Built for React + TypeScript; the backend is a parameter.

```
                                   /loop:product        (once per product)
                                        │
COMPLEX ENTRY (multi-epic)              ▼
  /bmad:pm ─▶ /bmad:sm ─▶ /stories:review ─▶ /bmad:architect ─▶ /loop:design-system
                                        │
SIMPLE ENTRY (one screen, CRUD, fix)    │
  /loop:spec ───────────────────────────┤
SMALL ENTRY (bounded change)             │
  /loop:small ───────────────────────────┤
BUG ENTRY (symptom → reproduction)      │
  /loop:debug ──────────────────────────┤
                                        ▼
                              FEATURE READY   (a READY line on the board)
                                        │
THE LOOP (identical for both)           ▼
  /loop:research ─▶ /loop:interface ─▶ /loop:plan ─▶ EXECUTE ─▶ /loop:review ─▶ /loop:ship ─▶ next
       └───────────────── /loop:orchestrate runs the whole thing ─────────────────┘
```

## Install

```bash
git clone <this-repo> loopkit && cd loopkit
./install.sh /path/to/my-project      # core: language-agnostic guardrails
# add --react-ts, --supabase (includes React/TS), and/or --fastapi
# CI/CD: --deploy=none|netlify|vercel|pages|ssh|ghcr, --no-ci, --lefthook
/kit:init                             # inspect, ask closed choices, adapt, doctor
/loop:spec my feature                 # then, inside the project: it writes the
                                      # spec and chains /loop:orchestrate
```

`install.sh` writes existing kit files as `.new`; the sole exception is
`.claude/settings.json`, whose selected hook blocks are merged idempotently while
preserving user keys. `/kit:init` adapts the markers it can prove, asks closed questions
for choices, and reports every marker it must leave open with its exact path. It also
writes `.claude/project.json`: the app roots (`frontend/`, `backend/`) whose configs are
guarded like the root's, and the code generators allowed to redirect into a source.

**Updating** an installed project is the same command: new kit files land
directly, changed ones as `.new` beside your adapted copy, and `settings.json`
merges (retired allows removed, deny list unioned in order). The narrow
permissions (P1: `acceptEdits` plus exact git and gate allows) are held back,
with a `P1 held back: …` line, until every guard hook of the project is at the
kit's `cwk-guard-api` version — merge those `.new` first, then re-run.

**CI/CD.** Unless `--no-ci`, the project gets `ci.yml` (the same gates as
`/loop:ship`), a push-only `deploy.yml` assembled for the chosen target,
`dependabot.yml` and `CODEOWNERS` — actions pinned by SHA, CLIs by version, the
SSH host key pinned. `--lefthook` adds a pre-push running typecheck, lint and
tests. Projects without a remote use `--no-ci`: the gates stay in `/loop:ship`.

## The loop

| Step | What it does | Produces |
| --- | --- | --- |
| `/loop:research` | Multi-modal fan-out: code, blast radius, **the real state of the database**, third-party APIs | `docs/work/<slug>/research.md` |
| `/loop:interface` | Competing UI proposals on an **editable canvas**, then **you decide**. SKIP when there is no UI | `docs/work/<slug>/design.md` |
| `/loop:plan` | Write chain + parallelisable lots + contracts + test plan | `docs/work/<slug>/plan.md` |
| EXECUTE | Sequential, in the plan's order; RED legs to `test-writer`, GREEN past 70% context and every fix batch to `implementer` | the code |
| `/loop:review` | Visual pass (UI) · 5 dimensions in parallel · every finding refuted | PASS/CONCERNS/FAIL |
| `/loop:ship` | Parallel gates, commit via the `github` agent, board updated, next feature named | the commit |

Every step is callable on its own, so you can rejoin mid-loop.

A pass whose diff touches UI gets PR screenshots: `/loop:review` has
`e2e-tester` capture the key steps (light/dark × desktop/mobile, test data only,
plus a "before" image on a bugfix) into the git-ignored `.pr-shots/`. The
`github` agent publishes them as blobs on the orphan branch `pr-assets`, embeds
them in the PR body (summary, `Where to look`, `Uncertain`, one line per commit,
`Screenshots`), and removes them once the PR is `MERGED`, from the tip of
`pr-assets` only: they stay in its git history. Every push asks first.

`/loop:small` dispatches a bounded, non-foundation change into a dedicated
worktree after one spec approval; it then follows the normal plan, execute,
review and ship path and merges one ticket at a time. Its `.claude/scripts/small-*`
helpers check the dispatch, compute the allowed paths and refuse a diff that
leaves them.

`/loop:spec` chains straight into the loop; its contract is validated at the
first gate and its acceptance cases carry ids that frozen tests cite. After
`/loop:ship`, `/clear` reopens on the next feature (a `SessionStart` hook names
it), and at 97% context `./workflow.sh` restarts Claude on the disk handoff —
twice per feature at most.

## What makes it different

- **Hooks that block, not lint.** `PreToolUse` guardrails refuse the write
  itself — a cross-feature import, an `any`, a secret read, a commit on `main`.
  A rule you can check beats a rule you re-read.
- **Guardrails that guard themselves.** Writing a hook, `settings.json`, an
  escape-hatch file, a gate config or a workflow asks you first — through
  Write/Edit or through the shell (redirections, `sed -i`, `perl -i`, heredocs,
  `python3 -c`, tool output flags). Guard hooks fail closed and never execute
  repo config; destructive git asks, `.git/` writes are denied.
- **Fewer prompts, not fewer checks.** Edits run in `acceptEdits`, and only the
  exact gate commands and strict git forms (`git add`, `git commit -m`,
  `git switch -c`…) are pre-allowed — the argument wildcards on the test, lint,
  build and typecheck runners were retired.
- **A TDD trio that cannot be routed around.** `prove-red` observes the failure,
  `require-red` blocks the module until it exists, `freeze` stops the test
  drifting toward the code. Closed on the shell side too.
- **A review gate that refutes itself.** Adversarial `reviewer` agents find, then
  a `verifier` tries to **destroy** every Critical and Major. What survives is
  real; the rest is noise you never read.
- **A board with states, not a to-do list.** Six states, one owner each. A loop
  that stops without shipping gives its line back — the queue cannot lie.
- **A handover when the quota runs out.** The status line watches the context
  window and the subscription; at the threshold it checkpoints to disk and hands
  the phase to Codex, which rebuilds from the artifacts and the Git state.
  Some mechanical steps (`execute-green`, `review-fixes`) can also run on Codex
  by declaration — one pilot preference per role in
  `.claude/workflow-routing.yml` — always falling back to Claude when the CLI
  isn't installed.

## What's in here

```
.claude/rules/      10 rules, loaded every session (and by every subagent)
.claude/hooks/      15 wired hooks + the status line + fixture suites
.claude/scripts/    the /loop:small helpers
.claude/agents/     13 subagents
.claude/commands/   31 slash commands — loop/, bmad/, audit/, refactor/, kit/…
.claude/skills/     patterns, templates, the e2e-playwright skill
.claude/guides/     rationale + on-demand rules, never auto-loaded
templates/          github/ (ci, deploy + publish targets, dependabot, CODEOWNERS) · lefthook.yml
addons/             supabase/ · fastapi/  (opt-in, see below)
```

Session floor: **515 lines / ~5,600 tokens**, loaded once per session and per
subagent — down 59% from 1,245 lines. `test-rules-floor.sh` holds the core at
520; an addon rule declares its extra (`addon +N` in its budget header, checked
against the core rule it replaces), so FastAPI may add 375 lines and Supabase
220. Contextual detail is routed through `.claude/skills/project-rules/`; traps
and enforced twins stay hot.

The kit's own CI (`.github/workflows/kit-ci.yml`, never installed) runs every
fixture suite, lints the hooks and the assembled targets with pinned tools.

**`addons/supabase/`** — stack + DB rules (including **RLS**), the Supabase
`/database:migration`, front-end patterns and edge functions, plus a real tested
`_shared/` Deno layer. **`addons/fastapi/`** — a Python backend with its own twin
TDD cycle, its `/backend:*` commands and its own dependency audit.

## Install profiles

| Profile | Adds |
| --- | --- |
| `core` (no flag) | loop/review/board plus secret, destructive-shell, Git and English-comment guardrails |
| `--react-ts` | architecture, no-`any`, icons, formatter/lint and the TypeScript TDD trio |
| `--supabase` | React/TS plus the Supabase rules, migration command, patterns and edge-function layer |
| `--fastapi` | FastAPI rules, commands, patterns and the six Python hooks; usable directly on core |

Profiles are cumulative. Reinstallation merges selected hook blocks into the
active `.claude/settings.json`, preserves user keys and never duplicates a hook.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `bash`, `python3`, `jq` (for the hooks)
- A package manager is needed only for the React/TS profile. `pnpm` is the
  shipped default, replaceable in `00-project.md`, `/loop:ship` and its runners.

## Read next

- [`docs/Claude_Workflows.md`](docs/Claude_Workflows.md) — the full map of the workflow
- [`docs/RATIONALE.md`](docs/RATIONALE.md) — why the kit is built this way: the
  product layer, the three ideas, the guardrail catalogue, the security levels,
  the allowlist and what it does not excuse
- [`docs/ADAPTATION.md`](docs/ADAPTATION.md) — `/kit:init`'s ordered reference

## License

[MIT](LICENSE)
