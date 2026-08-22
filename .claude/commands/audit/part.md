---
description: Multi-agent audit of ONE named part of the repo (react-query, zustand, ci-cd, testing, forms…) — fan-out on disjoint files, mandatory refutation, and a register so every run after the first is a diff
argument-hint: <part> [--economy|--standard|--critical] [--all]
---

# /audit:part — audit one part, properly

`/audit:part react-query`, `/audit:part zustand`, `/audit:part ci-cd`. One part
per call. It takes that part **as it stands** — the code, the rules that describe
it, the agents and gates that police it, the addon that overrides it — and asks:
do these files agree with each other, does the code do what its comments claim,
and are the external facts they rest on still true.

| Command | Asks |
| --- | --- |
| `/review` | is **this diff** correct — inside the loop |
| `/audit:security` | what is **exposed** today |
| `/audit:mutation` | do the tests **constrain** the code |
| `/kit:doctor` | do the values declared twice still **agree** — deterministic, free |
| **`/audit:part`** | is **this part** coherent, true, and actually enforced |

**It never fixes.** The output is a register plus a diff report; corrections go
back through the loop with their tests.

## The parts

Name one. The `Files` column is what the lanes receive — adjust it to the repo,
and delete a row this repo does not have.

| Part | Owns | Files (starting point) |
| --- | --- | --- |
| `react-query` | queries, mutations, keys, cache, realtime wiring | `patterns/react-query.md`, `templates/lib-core.md` (queryClient), `templates/feature.md` (hooks), `patterns/url-state.md`, `rules/04-state.md`, `rules/08-feedback.md`, `patterns/zustand.md` ("Async actions" — the only `useLogout`, `mutationKey` and `queryClient.clear()`), `src/**/hooks/hooks.ts` |
| `zustand` | client state, persistence, selectors | `patterns/zustand.md`, `rules/04-state.md`, `templates/feature.md` (stores), `src/stores/**`, `src/**/stores/**` |
| `url-state` | search params, `validateSearch`, shareable views | `patterns/url-state.md`, `src/routes/**` |
| `forms` | RHF + Zod, validation, error copy | `patterns/forms.md`, `shared/schemas/**`, `src/**/components/**Form*` |
| `architecture` | layer arrow, imports, composition root, thresholds | `rules/02-architecture.md`, `hooks/enforce-architecture.py`, `templates/feature.md`, `src/features/**/services/**` |
| `testing` | TDD apparatus, freeze, coverage floor, fixtures, MSW | `rules/05-testing.md`, `hooks/tdd-*.sh`, `patterns/tests.md`, `patterns/msw.md`, `templates/fixtures.md`, `templates/tooling-config.md` |
| `ci-cd` | the six gate roles, the workflows, the deploy | `templates/ci.md`, `.github/workflows/*.yml`, `rules/00-project.md` (scripts), `commands/ship.md`, `package.json` |
| `guardrails` | the hooks, and what they do **not** catch | `.claude/hooks/**`, `.claude/settings.json`, `rules/00-project.md` |
| `feedback-ui` | loading/error/empty, a11y, semantic HTML, design system | `patterns/feedback.md`, `patterns/a11y.md`, `templates/page.md`, `templates/component.md`, `rules/08-feedback.md`, `rules/03-conventions.md` |
| `database` | schema, migrations, authorization barrier | `rules/06-database.md`, `commands/database/migration.md`, `supabase/migrations/**` |
| `workflow` | the commands and agents themselves | `.claude/commands/**`, `.claude/agents/**`, `docs/Claude_Workflows.md` |
| `token-budget` | profiles, arity, model tiers | `rules/11-token-budget.md`, the `model:` lines, `hooks/token-statusline.py` |
| `addons` | an installed addon vs the vendor-neutral core | `addons/<name>/**` and the core files it replaces |

`--all` runs them in waves, riskiest first, one register each. It is the same
protocol N times, not a different one — and it costs N times as much, so name a
part unless you mean it.

## Why there is a register, and why it is not optional

A one-pass audit is a **sample**, not a proof: nothing compiles, nothing fails,
every finding costs reading two files side by side. Measured on this repo, on
`react-query`: a solo pass covered about half the part, produced one false
positive, one claim verified from memory and wrong, and four findings the part
already answered elsewhere. Four adversarial agents on disjoint files doubled the
real count and corrected the auditor twice — then a fifth, run on the **fixes**,
found four defects the fixes had introduced.

So each part owns **`docs/audits/<part>.md`**: one line per point ever checked,
including the clean ones and the refuted ones, with verdict, evidence, date and
run. Nothing is ever deleted — a deleted refutation is a finding the next run
rediscovers. The first run is a sample; every run after it is a **diff**.

## Process

### Stage 0 — frame (main thread, cheap)

1. **Deterministic checks first** — `/kit:doctor`, and for a part with code
   behind it `pnpm typecheck`, `pnpm lint`, `pnpm test:run`. Anything a script
   proves is not an agent's job.
2. Read `docs/audits/<part>.md` if it exists: its open findings are lane A's
   input, **all** its entries are the exclusion list for the others.
3. Take the `Files` row, complete it by grep (a part is what *mentions* it, not
   what is named after it), and **split it into disjoint lots** — no file in two
   lanes. Overlap is paid twice and returns the same finding twice.

### Stage 1 — fan-out (ONE message, all lanes at once)

Every lane gets its lot, the exclusion list, and the reporting contract:
`file:line`, the **exact quote**, a concrete failure scenario (inputs → wrong
behaviour), a one-line fix. No stylistic findings. "A section is missing" is not
a finding unless the absence produces a defect.

| Lane | Agent | Scope | Question |
| --- | --- | --- | --- |
| **A — refute** | `verifier` | the register's open entries, and its `fixed` ones if anything was corrected since | Kill each. **Read the neighbourhood** — a note twenty lines below, a header section, the rule file. And on a `fixed` entry: is the fix present, sufficient, and did it break something? |
| **B — sweep** | `reviewer` | the part's own files | Fresh defects, ranked: code that misbehaves if copied or run > two files contradicting each other > a rule the part violates in its own example > a wrong type |
| **C — cross** | `reviewer` | everything that *mentions* the part without owning it: rules, agents, commands, hooks, addons | Twin copies that diverged; a gate checking a rule no pattern teaches; a pattern no gate checks; a shipped snippet a hook would deny at write time |
| **D — external** | `doc-researcher` | vendor documentation | Only claims `docs/research-cache/settled.md` does not already answer. Version-pinned behaviour only. Returns a `Promote to the ledger` block; never edits a rule |

Arity (`11-token-budget.md`) — the **lane** is the unit, never the file count:
- **economy**: A+B merged into one `verifier`, plus C. D only if a finding rests
  on an unsettled version-pinned claim.
- **standard**: the four lanes.
- **critical**: the four, plus a second B at an opposite angle (one lane reads
  the code assuming the comments lie, the other reads the comments assuming the
  code lies), and stage 2 doubled.

Model tiers are already on the agents; a lane that **judges** never runs below
the session model.

### Stage 2 — refute, always (parallel)

Every Major and Critical goes to a `verifier`, batched by file. **A finding is
not reported until something tried to kill it.** "The part already answers this
elsewhere" is the most common outcome and it is a *downgrade*, not a dismissal:
it becomes a cross-reference fix — a real defect with a cheap correction.

### Stage 3 — spot-check, then write

**Open the citation of every finding you are about to report.** On this repo's
first run the auditor's own false positive was a missing import block the file
declared in its own header, and the strongest agent claim was a library behaviour
nobody had opened the source for. An agent's report is evidence, not a verdict.

Then:
1. Update `docs/audits/<part>.md` — verdict (`open` / `fixed` / `refuted` /
   `partial`), evidence, date, run. Append; never delete.
2. Promote settled external facts into `01-stack.md` — the main thread writes
   that table, never the agent.
3. Report a **diff**: new, dead, still open, and how much of the register changed
   verdict. A run that changes nothing is a good run; say so plainly.

**If fixes are applied afterwards, re-run the part.** Corrections written in
series, unbuilt and untested, are where the next defect lives — that is not a
hypothesis here, it is what the fifth lane found.
