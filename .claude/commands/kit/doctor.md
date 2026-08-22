---
description: Kit doctor — checks that the values declared twice (rule + enforced copy) still agree, and that every shipped path, hook and command resolves
argument-hint: [nothing, or a project root to check instead of this one]
---

# /kit:doctor — do the two copies still agree?

Out of the loop, read-only, on the repository **as it stands**. Zero subagents:
everything here is deterministic, so it costs compute and not context
(`11-token-budget.md`).

**Never a gate.** Do not wire the exit code into `/ship`. A rule and its enforced
copy disagreeing is a decision to take — which of the two is right — and a build
is the wrong place to take it.

## Why this exists and the other guardrails do not replace it

Half a dozen values in this kit are written **twice**: a rule states them, a hook
enforces them. Every one of those places says "change both together, never one
alone" — and nothing checked it. The failure mode is the one `01-stack.md` names
itself: *a hook matching a module nobody imports is no guardrail at all,
silently, while the table says the layer is covered.*

| What already exists | What it proves |
| --- | --- |
| The hooks | the rule they carry is applied |
| `/review`, `/audit:security` | the **code** obeys the rules |
| **`/kit:doctor`** | **the rules and the hooks are still talking about the same thing** |

Nothing else in the kit reads a rule file and a hook file in the same pass.

## Run it

```bash
python3 .claude/hooks/kit-doctor.py          # this repo
python3 .claude/hooks/kit-doctor.py /path    # another checkout, after ./install.sh
```

`$ARGUMENTS`, when present, is that root. The script is in `.claude/hooks/`
because that directory ships with `install.sh`; it is **not a hook** and nothing
registers it in `settings.json` (same status as `hook-timings-report.sh`).

Exit 0 = no divergence. Exit 1 = at least one.

## What it checks

**Twins** — one value, two files, compared field by field:

| Check | The rule | The enforced copy |
| --- | --- | --- |
| `protected-dirs` | `CLAUDE.md`, "Recursive delete on" | `PROTECTED_DIRS` in `prevent-destructive-commands.sh` |
| `data-client` | `01-stack.md`, "Where does the client live?" | `DATA_CLIENT_MODULE` / `DATA_CLIENT_OWN_PATH` in `enforce-architecture.py` |
| `composition-roots` | `02-architecture.md`, the composition-root row | `COMPOSITION_ROOTS` in `enforce-architecture.py` |
| `shared-dirs` | `02-architecture.md`'s **Forbidden** list, plus `CLAUDE.md` and `reviewer.md` — which restates the list *and* its count | `SHARED_DIRS` in `enforce-architecture.py`. Four lines of output, one per copy plus the count; the "Allowed from anywhere" list of `02-architecture.md` stays manual |
| `coverage-floor` | `05-testing.md`, lines/functions/branches | `thresholds` in `templates/tooling-config.md` |
| `coverage-holes` | `05-testing.md`, "three wiring files and only three" | the coverage `exclude` array in `tooling-config.md` |
| `token-thresholds` | `11-token-budget.md`, the three markers | the `used >=` blocks in `token-statusline.py` |
| `tdd-layers` | — | `CWK_TDD_LAYERS`, `TEST_FIRST`, the `mutate` globs of `/audit:mutation` |
| `gate-allowlist` | the `pnpm` calls in `/ship`'s gate fence | `permissions.allow` in `settings.json` |
| `ci-scripts` | `00-project.md`, the command fence | the `run:` lines of `.github/workflows/ci.yml` |
| `workflow-names` | `ci.yml`'s `name:` | the `workflow_run` trigger and `--workflow=` of `deploy.yml` |
| `agent-models` | `11-token-budget.md`, the model-tier table | the `model:` line of every `.claude/agents/*.md` |
| `settled-ledger` | `01-stack.md` names `docs/research-cache/settled.md` | that no rule file, core or addon, grew a dated table back |

`gate-allowlist` is the only twin whose divergence is **not** silent — it
interrupts. That is exactly why it belongs here: a gate added to `/ship` without
its allow entry does not fail, it **asks**, someone declines it by reflex in the
middle of the batch, the other gates stay green and the ship reports success
without the check that was just added. The form matters too: a call carrying
flags (`pnpm audit --audit-level=high`) needs the `Bash(pnpm audit *)` entry, and
the bare one does not cover it. A grant living only in `settings.local.json` is
reported as missing, with a note — that file does not ship, so the next checkout
has the gap back.

`agent-models` reports three different things, and only the first is a
divergence: an agent whose `model:` contradicts its row; an agent **no row
covers** (add the row, or say in the rule why it is exempt — an agent nobody
priced is the gap the tier rule exists for); and a row naming an agent that has
no file. It reads the row's **last** cell only — the prose cell names an agent
too, and reading it would price that agent by accident. The direction of the
failure is always the same: a new agent is started by copying its nearest
neighbour, inherits that neighbour's tier, and a **judge** ends up on the cheap
model — which is the one thing `11-token-budget.md` forbids outright.

`tdd-layers` has no rule side on purpose: the four layer words appear in
`05-testing.md` as prose among a dozen other filenames, and a parser guessing
which ones are the layers would be the least reliable check in the file. The
three **mechanical** copies are compared instead — the freeze, the coverage
floor and the mutation scope must cover the same set, or a layer is frozen and
unmeasured, which `05-testing.md` calls the worst combination available.

**Budget** — the cost nothing else measures. `CLAUDE.md` and `.claude/rules/**`
are re-read in full by every session **and by every subagent**, so a paragraph
added there is a paragraph multiplied by the whole fan-out of the loop. Two
checks and one number:

- `rules-loaded` — the `@` lines of `CLAUDE.md` are the **loader**, not an index:
  there is no `SessionStart` hook, and nothing walks `.claude/rules/` on its own.
  A rule on disk with no `@` line never reaches a session, and until this check
  existed nothing said so — a guardrail everyone believes is on.
- `rules-budget` — every loaded file declares `<!-- budget: N lines -->` on its
  first line and stays under it. `OVER` is a **decision**, not a defect: raise
  the number in the same commit and say what it bought, or move the overflow.
  A file with no budget line is the same gap as an agent with no model row —
  nobody priced it.

The `ok` line prints the **session floor**: total lines, characters and the
token order of magnitude paid unconditionally, per session and per subagent.
Watch that number, not the individual budgets.

**Where the overflow goes**, in this order: a hook's deny text already says it
(delete — the deny fires at the exact moment and prints the way out); a pattern
or template is read when it applies (move it there); it is a retrospective
(`.claude/guides/`). What stays is a **trap**: something that changes what an
agent does when it has never met it.

**Wiring** — `hook-wiring`: every script in `.claude/hooks/` is registered in
`settings.json`, every registered path exists, every registered `.sh` is
executable. The standalone scripts (`hook-lib.sh` and `tdd_py_lib.py`, the two
shared libraries; `hook-timings-report.sh`; `kit-doctor.py`) are known and not
reported. A shell
hook without `+x` **fails open**: the guardrail does not run and the write goes
through.

**Links** — `shipped-paths`, `command-refs`, `agent-refs`: every `.claude/**`
path, every backticked slash-command and every `` `x` agent `` named by a doc has a
file behind it. A glob (`patterns/edge-function*.md`) is satisfied by one match.
Paths under `docs/work|product|prd|stories|architecture|specs` are **not**
checked — `CLAUDE.md` declares them produced by the loop, so absent is their
normal state.

**Only kit-owned docs are scanned** — `CLAUDE.md`, `AGENTS.md`, `.claude/**` and
the two `docs/` files the installer ships. An installed project's own README and
docs name that project's commands and paths, which this file knows nothing
about, and a doctor reporting someone else's vocabulary as broken is a doctor
that gets turned off. Same reason a backticked slash-token on a line carrying an
HTTP verb is read as a route, not a command.

**Placeholders** — `fill-markers`: counted, never a failure. The script says
which mode it is in, and that changes what the count means: in the kit source
they are the template's own `<FILL>`, in an installed project they are an
unfinished adaptation.

## Reading the output

| Status | Meaning | What you do |
| --- | --- | --- |
| `DIVERGENCE` | two copies of one value disagree | decide which side is right, fix **both** |
| `MISSING` | a path, hook or command named by a doc has nothing behind it | fix the link, or ship the file |
| `OVER` | a loaded file passed its declared line budget | move the overflow, or raise the number **and say what it bought** |
| `FILL` | a placeholder | informational |
| `skip` | source file absent, or shipped by an addon that is not installed | nothing |

## Your job, after the script

The script says the two files disagree. **It cannot say which one is right** —
that is the whole reason this is a command and not a hook.

1. For each `DIVERGENCE`, open both sides and decide. The default reading:
   **the hook is what actually runs, the rule is what everyone believes.** So a
   divergence is usually the rule being wrong in the reader's head and right on
   disk, or the reverse — say which, in one line, before touching anything.
2. **Both sides move together, in the same edit.** Fixing only the file that
   looked wrong is how the pair drifted in the first place.
3. A `MISSING` link is either a rename that missed a reference (fix the
   reference) or a file that was planned and never written (say so — do not
   invent it).
4. Then ask before writing. This command reports; the fixes are yours to
   approve, like every `/audit:*`.

Do **not** paste the raw output back as the answer. Report the divergences, the
decision each one needs, and nothing else — a clean run is one line.

## What it deliberately does not check

- **Prose that contradicts prose.** Two rules disagreeing in words is a
  `/review` matter, not a parser's.
- **The addon wiring beyond file presence** — `EXTERNAL_CLIENTS`, the backend
  gates in `commands/ship.md`, `07-backend.md` in the reviewer's dimensions. The
  addon README lists them; they are prose edits inside larger files, and a false
  positive there would cost more than the check is worth.
- **`package.json` scripts against `00-project.md`.** Worth adding the day this
  kit is checked inside a real app rather than as a template.

## Adding a twin

One function returning a `Finding` list, appended to `CHECKS` in
`kit-doctor.py`. Use `compare()` so the output keeps naming **both files** — a
finding that names one side is a finding nobody can act on. A check whose source
file is absent returns `skip`, never a failure: an installed project may have
dropped a template on purpose.
