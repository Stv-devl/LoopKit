<!-- budget: 140 lines · /kit:doctor rules-budget -->
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

`/loop:ship` runs the gates before every commit, remote or not; CI repeats them
and never replaces them · `.claude/guides/rules-index.md`.

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

**Never write source from the shell** (redirection, `tee`, `sed -i`): it goes
around every `Write|Edit` guardrail. Delete specific files, never whole folders.

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
- SOLID's O, L, I have **one** enforcer, `/loop:review`'s `correctness` — no hook
  decides them from an Edit delta · `03-conventions.md`

## Routing

- **Git / GitHub** → the **`github` agent** (`.claude/agents/github.md`).
- **Schema changes** → **`/database:migration`**. Never write SQL by hand.

## Workflows

**One loop, two entries.** Use the lightest entry that does the job.

```
frame (once) : /loop:product   (the product frame + the backlog board)
               /loop:design-system   (extract from code, or --new to create it
                                      with you, once, from zero)
simple entry : /loop:spec
complex entry: /bmad:pm → /bmad:sm → /stories:review → /bmad:architect
parallelism  : /loop:tracks   (what can run at once right now — 3 max — and
                               the worktrees for it; recomputed after a merge)
loop (shared): /loop:research → /loop:interface → /loop:plan → EXECUTE
               → /loop:review → /loop:ship → next
               └── /loop:orchestrate <artifact> runs the whole loop ──┘
```

- `/loop:interface` and `/loop:plan` fix **what is built** and never proceed on
  silence; `/loop:ship` and `/loop:tracks` decide only **what leaves the machine**.
- Stories are sliced **functional, before the architecture**. External docs are
  researched once: `docs/research-cache/settled.md` is read before any fetch.
- **EXECUTE stays sequential**, except the RED leg (one `test-writer` per
  test-first layer). Separate tracks get separate worktrees, their number
  computed · `/loop:tracks`.
- Token profile `economy` by default, persisted in work artifacts ·
  `11-token-budget.md`. Launch sessions with `./workflow.sh`.
- Out of the loop, read-only, never a gate: `/audit:security`, `/audit:mutation`,
  `/audit:part <name>`, `/kit:doctor`. Their fixes come back through the loop.
  Exception: a `critical` profile arms one `/audit:security` surface at ship.

Full map: `docs/Claude_Workflows.md`.

**Reading a path in these files.** A `.claude/` path is shipped and must exist.
`docs/work/<slug>/`, `docs/product/`, `docs/prd/`, `docs/stories/`,
`docs/architecture/`, `docs/specs/` and `docs/design-system.md` are produced by
the loop: absent means "not generated yet". Write them with their full directory.

## Rules Index

The `@` lines below are the loader: a rule without one never loads. Each rule
has a line budget; where a new line goes · `.claude/guides/rules-index.md`.

@.claude/rules/00-project.md @.claude/rules/01-stack.md
@.claude/rules/02-architecture.md @.claude/rules/03-conventions.md
@.claude/rules/04-state.md @.claude/rules/05-testing.md
@.claude/rules/06-database.md

@.claude/rules/08-feedback.md @.claude/rules/09-icons.md
@.claude/rules/11-token-budget.md
