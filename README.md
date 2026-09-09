# LoopKit

One loop from idea to commit for Claude Code — 30 commands, 12 subagents, 10
declarative rules and 14 hooks that mechanically refuse what the rules forbid.
Built for React + TypeScript; the backend is a parameter.

```
                                   /loop:product        (once per product)
                                        │
COMPLEX ENTRY (multi-epic)              ▼
  /bmad:pm ─▶ /bmad:sm ─▶ /stories:review ─▶ /bmad:architect ─▶ /loop:design-system
                                        │
SIMPLE ENTRY (one screen, CRUD, fix)    │
  /loop:spec ───────────────────────────┤
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
/kit:init                             # inspect, ask closed choices, adapt, doctor
/loop:spec my feature                 # then, inside the project
/loop:orchestrate docs/specs/<slug>.md
```

`install.sh` writes existing kit files as `.new`; the sole exception is
`.claude/settings.json`, whose selected hook blocks are merged idempotently while
preserving user keys. `/kit:init` adapts the markers it can prove, asks closed questions
for choices, and reports every marker it must leave open with its exact path.

## The loop

| Step | What it does | Produces |
| --- | --- | --- |
| `/loop:research` | Multi-modal fan-out: code, blast radius, **the real state of the database**, third-party APIs | `docs/work/<slug>/research.md` |
| `/loop:interface` | Competing UI proposals on an **editable canvas**, then **you decide**. SKIP when there is no UI | `docs/work/<slug>/design.md` |
| `/loop:plan` | Write chain + parallelisable lots + contracts + test plan | `docs/work/<slug>/plan.md` |
| EXECUTE | Inline, sequential, in the plan's order | the code |
| `/loop:review` | Visual pass (UI) · 5 dimensions in parallel · every finding refuted | PASS/CONCERNS/FAIL |
| `/loop:ship` | Parallel gates, commit via the `github` agent, board updated, next feature named | the commit |

Every step is callable on its own, so you can rejoin mid-loop.

## What makes it different

- **Hooks that block, not lint.** 14 `PreToolUse` guardrails refuse the write
  itself — a cross-feature import, an `any`, a secret read, a commit on `main`.
  A rule you can check beats a rule you re-read.
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
.claude/hooks/      14 wired guardrails + the status line
.claude/agents/     12 subagents
.claude/commands/   30 slash commands — loop/, bmad/, audit/, refactor/, kit/…
.claude/skills/     patterns, templates, the e2e-playwright skill
.claude/guides/     rationale + on-demand rules, never auto-loaded
addons/             supabase/ · fastapi/  (opt-in, see below)
```

Session floor: **557 lines / ~6,200 tokens**, loaded once per session and per
subagent — down 55% from 1,245 lines. Contextual detail is routed through
`.claude/skills/project-rules/`; traps and enforced twins stay hot.

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
