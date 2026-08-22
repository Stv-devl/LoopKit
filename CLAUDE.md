<!-- budget: 200 lines · /kit:doctor rules-budget -->
# <Project name — FILL> (React 19 + TS + Vite 8 + <backend — FILL> + TanStack Query)

<!-- FILL: this file is the project's constitution. Everything in it is loaded
     into every session, so it stays short — details live in .claude/rules/.
     Anything you leave as a placeholder is a rule that will not be enforced. -->

## Environment

<!-- FILL: two independent lines. They are not exclusive — a project is
     developed locally AND may have a production. Reading "local" as "never
     deployed" is what leaves a repo with no CD and nowhere to write one down.
     This section decides whether an agent may run a deploy at all. -->

- **Local**: <how it runs on a dev machine — `pnpm dev`, ports, seeded data>
- **Production**: <host + URL + who may trigger a deploy>, or `none yet` — and
  if `none yet`, delete `.github/workflows/deploy.yml` rather than leaving it
  unfilled.

The gates run **once or twice, never zero**. `/ship` runs them before every
commit, on this machine — that copy exists whatever the answers above. When the
project has a remote, `.github/workflows/ci.yml` runs them again where nobody
can skip them; a green CI is then not a reason to stop running `/ship`, since it
reports on a diff already pushed. No remote → no workflow installed at all, and
the gates are unchanged · `.claude/skills/templates/ci.md`.

## Security

### Protected Files

**NEVER read, edit, write, or access these files:**

- `.env`, `.env.*`, `.env.local`, `.env.production`, `.env.development`
- Any file containing secrets, API keys, or credentials
- `*.pem`, `*.key`, `credentials.*`

If a task requires environment variables, ask the user to provide the variable
names (not values) or check `.env.example`.

### Destructive Commands

**NEVER run these commands:**

- `rm -rf` on directories without explicit user confirmation
- `rm -rf *`, `rm -rf .`, `rm -rf ..`
- Recursive delete on: `src/`, `shared/`, `.claude/`, `public/`, `node_modules/`,
  `dist/` <!-- FILL: add yours. The enforced copy is PROTECTED_DIRS in
  .claude/hooks/prevent-destructive-commands.sh — change both together, never one
  alone. -->
- `chmod 777`, `mkfs`, `dd` to devices
- `git worktree remove --force`, or deleting a worktree with `rm` — use
  `git worktree remove` (it refuses a dirty tree, and that refusal is the point)

**Never write source from the shell.** A redirection, a `tee` or an in-place
`sed` onto a TypeScript file goes around every `Write|Edit` guardrail at once.
Use Write/Edit. The Bash hook denies it on the test-first layers and on any test
file, and asks elsewhere · `05-testing.md`, "What the hooks refuse".

When deleting, always target specific files/subdirectories, not entire folders.

## Non-negotiables

<!-- FILL: keep the ones that hold here, add the two or three this project can
     never break. **One line each**, the rule file named at the end being the
     authority — this list is a checklist for the subagents that read only part
     of `.claude/rules/`, never a second copy of the rule. -->

- No `any` — `unknown`, generics, proper types · `03-conventions.md`
- No cross-feature import, and shared leaf code (`components/`, `hooks/`,
  `lib/`, `types/`, `stores/`, `config/`) never imports a feature: it takes the
  behaviour as a parameter. `routes/`, `providers/` are wiring and may ·
  `02-architecture.md`
- No business logic in pages/components · `02-architecture.md`
- No data-client call outside `*.gateway.ts` / `services.ts` and the composition
  root · `02-architecture.md`
- `hooks.ts` calls the repository, never the data client · `02-architecture.md`
- `Result<T>`, `unwrap`, `ServiceError` come from `src/lib/`, scaffolded once ·
  `02-architecture.md`
- User messages in the language declared by `03-conventions.md`, logs and errors
  in English
- Handle every React Query state: pending, error, empty, data kept on refetch ·
  `08-feedback.md`
- `utils.ts`, `mapper.ts`, `repository.ts`/`services.ts` are **test-first, one
  layer at a time, then frozen** · `05-testing.md`
- Assert the **behaviour**, never that a mock was called; never mock a pure
  function · `05-testing.md`
- SOLID's O, L, I have **one** enforcer, `/review`'s `correctness` — no hook
  decides them from an Edit delta · `03-conventions.md`

## Routing

Two kinds of work have one entry point, and going around it is the failure mode:

- **Git / GitHub** → the **`github` agent**. The convention lives there
  (`.claude/agents/github.md`); `enforce-git-workflow.sh` enforces it.
- **Schema changes** → **`/database:migration`**. Never write SQL by hand.

## Workflows

**One loop, two entries.** Use the lightest entry that does the job.

```
frame (once) : /product   (the product frame + the backlog board)
               /design-system   (extract from code, or --new to create it
                                 with you, once, from zero)
simple entry : /spec
complex entry: /bmad:pm → /bmad:sm → /stories:review → /bmad:architect
parallelism  : /tracks   (what can run at once right now — 3 max — and the
                          worktrees for it; recomputed after every merge)
loop (shared): /research → /interface → /plan → EXECUTE → /review → /ship → next
               └── /orchestrate <artifact> runs the whole loop ──┘
```

**The loop's gates come in two kinds, and only one of them defines the work.**
`/interface` and `/plan` fix **what is to be built** — the retained proposal is
what makes `/review` scoring a divergence as Major honest, and the printed test
plan is the last point where changing "correct" is free, since those test files
freeze right after. Neither substitutes for the other and **neither proceeds on
silence**. `/ship`'s gates and `/tracks`' fork are the other kind: they decide
**what leaves the machine**, never what it should be.

- Stories are sliced **functional, before the architecture**; `/plan` injects the
  technical context per feature.
- **External documentation is researched once** — `docs/research-cache/`, whose
  `settled.md` ledger `/research` reads before it fetches anything.
- Parallelise independent information, never repeated reading of the same source
  · `11-token-budget.md`. **EXECUTE stays sequential** — one exception, the RED
  leg, one `test-writer` per test-first layer.
- Separate tracks get separate worktrees; how many at once is **computed** ·
  `/tracks`, `.claude/guides/10-worktrees.md`.
- Agents: `explorer`, `doc-researcher`, `story-writer`, `story-critic`,
  `designer`, `test-writer`, `reviewer`, `verifier`, `e2e-tester`,
  `security-auditor`, `github`.
- Token profile: `economy` by default, persisted in work artifacts ·
  `11-token-budget.md`. Launch sessions with `./workflow.sh`; manual fallback
  `/handoff:codex` then `./codex-handoff.sh`.
- Out of the loop, read-only: `/audit:security`, `/audit:mutation`,
  `/audit:part <name>` (one named part, disjoint fan-out, every finding refuted,
  a register in `docs/audits/<part>.md` so every run after the first is a diff)
  and `/kit:doctor`. They report; the fixes come back through the loop with their
  tests, never inline. **Never a gate** — with one exception: on a `critical`
  profile `/ship` arms one surface of `/audit:security` before the commit, and a
  Critical finding stops the ship (`/ship` step 1bis · `11-token-budget.md`).

Full map: `docs/Claude_Workflows.md`. Everything respects `.claude/rules/` and
the guardrail hooks.

**Reading a path in these files.** A path under `.claude/` is shipped and must
exist — a missing one is a broken link. A path under `docs/work/<slug>/`,
`docs/product/`, `docs/prd/`, `docs/stories/`, `docs/architecture/`,
`docs/specs/` is **produced by the loop**, as are `docs/design-system.md` and
`docs/product/backlog.md`: absent simply means "not generated yet". Always write
the second kind with its full directory, never as a bare `plan.md`.

## Rules Index

**The `@` lines below are the loader, not an index.** Nothing walks
`.claude/rules/` on its own — there is no `SessionStart` hook, and Claude Code
reads this file plus its imports. A rule dropped into that directory without an
`@` line here **never reaches a session**, silently. `/kit:doctor`'s
`rules-loaded` compares the two lists.

**Every rule declares a line budget**, in a `<!-- budget: N -->` comment on its
first line, and `/kit:doctor`'s `rules-budget` fails when a file passes it. The
budget is not tidiness: these files are re-read in full by every session **and by
every subagent**, so a paragraph added here is a paragraph multiplied by the
whole fan-out of the loop. Passing a budget is a decision — raise the number in
the same commit, and say what it bought.

**Three exits for anything that does not fit**, in this order:

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

@.claude/rules/00-project.md @.claude/rules/01-stack.md
@.claude/rules/02-architecture.md @.claude/rules/03-conventions.md
@.claude/rules/04-state.md @.claude/rules/05-testing.md
@.claude/rules/06-database.md

@.claude/rules/08-feedback.md @.claude/rules/09-icons.md
@.claude/rules/11-token-budget.md
