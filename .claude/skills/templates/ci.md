# CI / CD — le miroir serveur de `/ship`

> Read this when **scaffolding the repo**, when a gate is added or removed, or
> when the project gains a deployment target. The files themselves are
> `.github/workflows/ci.yml` and `.github/workflows/deploy.yml`, installed by
> `install.sh` — **this file does not restate their content**. Two copies of a
> pipeline is exactly the failure mode `/kit:doctor` exists to catch.

## Why a CI at all, when `/ship` already runs the gates

`/ship` runs typecheck, lint, tests, audit and build **on one machine** — the
one that happened to run it, with its hooks enabled, its `node_modules` and its
cache. That is the right place for them: it is the fastest feedback, and it is
before the commit.

It is not a barrier. Nothing in this kit can stop a push that never went through
`/ship` — a disabled hook, a `--no-verify`, another machine, an agent that
short-circuited the step, a human in a hurry. **The CI is the copy nobody can
skip from their own machine**, and that is its whole job. It finds nothing
`/ship` would not have found; it finds it when `/ship` did not run.

The corollary matters as much: **a green CI is not a reason to stop running
`/ship`.** The CI reports after the fact, on a diff already pushed. `/ship`
reports before the commit, when the fix is still free.

## What runs where

`00-project.md` declares **six roles a gate needs**. Five of them are machine
roles and belong in both places; the sixth is not a CI role at all.

The table below has **eight rows for those six roles**, and the two extras are
not roles: the coverage floor is a *property of the test run* and the bundle
secret scan is `/ship`'s second deterministic security line. They are listed
because they are steps you can delete, not because `00-project.md` counts them.

| Role | `/ship` | `ci.yml` | Note |
| --- | --- | --- | --- |
| run-once tests | ✓ | ✓ | its **own** step (`test:run`) — see the note below the table |
| typecheck | ✓ | ✓ | |
| lint `--max-warnings=0` | ✓ | ✓ | the only thing that sees a React Compiler bail-out |
| dependency audit | ✓ | ✓ | its red is a **decision** — see below |
| build | ✓ | ✓ | CI uploads the result as the artefact the CD deploys |
| dev server | ✓ | — | a local role. There is nothing to serve in CI |
| *(not a role)* coverage floor | ✓ | ✓ | thresholds live in `vite.config.ts` (`tooling-config.md`), **not** in the YAML |
| *(not a role)* bundle secret scan | ✓ | ✓ | the other half of `/ship`'s deterministic security pair |
| `/audit:security` (one surface) | on a `critical` profile only | — | it needs an agent's judgement, not a runner's |

> **Why the tests and the floor are two steps and not one.** `test:coverage`
> covers both in one command, and that is exactly what made it dangerous: it
> needs `@vitest/coverage-v8`, a package separate from the Vitest core that
> nothing in this kit installs. When it was the workflow's only test invocation,
> a fresh scaffold's CI died before collection and the **mandatory** run-once
> role went down with an optional provider. Loud, not silent — but the most
> important step in the file must not depend on the least important one.
>
> Add the dependency when you scaffold: `pnpm add -D @vitest/coverage-v8`.

**No agent runs in CI.** Everything above is deterministic — `11-token-budget.md`
is explicit that those cost compute, not model context, which is why they are
free to duplicate. The reviewers, the verifier and the security auditor stay in
`/review` and `/ship`: putting a model in a required check makes the gate
non-reproducible and the bill unbounded.

## Working locally, with no remote

**The gates do not depend on any of this.** They are `/ship`'s, they run before
the commit, on your machine, and they ran there before this file existed. The CI
was never the gate — it is a *second copy* of it, covering the one thing `/ship`
structurally cannot: a machine that is not yours.

So a project with no GitHub remote installs **no workflow at all**
(`./install.sh <project> --no-ci`, or answer *non* to the installer's first
question). Not an empty one, not one that fails on purpose — none. Two files
that can never run are two files that rot, and an unfilled `deploy.yml` is a
`FILL` that `/kit:doctor` will report at every check for a decision nobody will
ever take.

| | Solo, local, no remote | Remote, no production | Remote + production |
| --- | --- | --- | --- |
| Gates before the commit | `/ship` | `/ship` | `/ship` |
| Gates after the push | — | `ci.yml` | `ci.yml` |
| Deploy | — | `--deploy=none` (fails until named) | `--deploy=<host>` |
| Install | `--no-ci` | `--deploy=none` | `--deploy=<host>` |

Adding the remote later is `./install.sh <project> --deploy=<target>` again: it
writes the workflows and leaves everything else as `.new`, so nothing you have
adapted since is touched.

**Wanting to run `ci.yml` itself locally is a different question**, and usually
the wrong one — `nektos/act` will do it, but it boots a container to run the
five commands `/ship` already runs natively, on the same tree, faster. Reach for
it to debug the *workflow file*, never to check the code.

## The two twins, and what checks them

The YAML is the only copy of the *pipeline*. Two other things are written
twice, and both failures are silent.

**The script names.** `00-project.md` declares them, `/ship` calls them locally,
`ci.yml` calls them on the runner — three copies of one list. `/kit:doctor`'s
`ci-scripts` compares them **in both directions**, so a rename cannot land as a
red `main` for a script nobody touched, and a gate role *deleted* from the YAML
cannot report `ok`. It reads inside `run: |` blocks too: reading only the `run:`
line made it report `ok` while checking nothing.

The second direction is the one that was missing, and it is the dangerous one:
`undeclared = called - declared` only ever noticed a script the workflow calls
and `00-project.md` does not. Deleting the Typecheck, Lint and Dependency-audit
steps outright left the check saying `No divergence.` — a green CI with no gate
in it, reported as healthy. The comparison is against **`/ship`'s gate fence**,
minus the local-only roles, not against every script in `00-project.md`: the
naive reverse flags `dev`, `test`, `test:run` and `test:ui`, which are not CI
roles and never were.

**The CI workflow's name.** `ci.yml` declares `name: CI`; `deploy.yml` names it
twice, in its `workflow_run` trigger and in `gh run list --workflow=`. Rename it
and the CD does not fail — `workflow_run` simply never matches, so nothing
triggers, nothing goes red, and the CI stays green while no deployment has
happened for weeks. `workflow-names` compares all three.

The thresholds are not a twin here: the coverage floor lives in
`vite.config.ts`, and the YAML only calls the script that reads it.

## The one gate a runner cannot decide

`pnpm audit --audit-level=high` red, **with no fix published**, is the case
`00-project.md` says cannot be a wall — and a CI step is, structurally, a wall.
The escape is not `--audit-level=critical`; it is
`pnpm.auditConfig.ignoreCves` in `package.json`, carrying the advisory id and a
one-line reason. That entry is dated, visible in a diff, and dies with its
dependency. Raising the level hides every future advisory too, silently.

## The deployment target is a declaration, not a default

`CLAUDE.md`'s **Environment** section is the single declaration of where this
project runs. It has two independent lines — how it runs locally, and whether
there is a production. They are not exclusive: a project can be developed
locally *and* deployed, and treating "local" as meaning "never deployed" is the
mistake that leaves a repo with no CD and no place to write one down.

**The choice is offered, not buried.** `install.sh` asks for the target — or
takes it as `--deploy=<x>` in a script — and assembles `deploy.yml` from one
skeleton plus the `Publish` step of that target
(`templates/github/publish/<target>.yml`). Each snippet carries the exact list
of GitHub secrets and variables to create, and the one permission it needs is
spliced in from a sibling `.perms` file rather than granted to everyone.

One skeleton, one file per target: the four properties below exist in exactly
one place and cannot drift between hosts. Adding a host is dropping a file in
that directory — the installer's question and its validation both read the
directory, never a hardcoded list.

- **No production yet** → `--deploy=none` (the default in a script). The
  `Publish` step is an `exit 1`, so an unconfigured deploy cannot silently
  succeed at nothing. Say `none yet` in `Environment` and delete the file if you
  prefer; keep `ci.yml` either way, it is worth having on day one.
- **A production exists** → pick the target at install time, then name it in
  `Environment` (host, URL, who may trigger). Changing your mind later is
  another `install.sh --deploy=<other>`, which writes `deploy.yml.new` beside
  the old one.

Whatever the answer, an agent reads that section before running anything that
touches a remote. Leave it stale and it guesses.

## What a publish snippet owns, and what the skeleton owns

Four fragments per target, one mandatory. A missing optional fragment drops its
marker; only the environment has a default.

| Fragment | Carries | Who has one |
| --- | --- | --- |
| `<target>.yml` | the `Publish` step | **every** target |
| `<target>.perms` | one extra job permission | `pages`, `ghcr` — never granted "just in case" |
| `<target>.environment` | the whole `environment:` block — name **and** url | `pages` (`github-pages`, recommended by the Pages action over a custom name, and its own `page_url`). Not `.env`: that suffix is the secrets convention, and `protect-files.sh` refuses to read it |
| `<target>.spa` | the client-routing fallback | `netlify`, `vercel`, `pages` |

**The SPA fallback is not optional knowledge.** The stack routes on the client
(`01-stack.md`, TanStack Router), so the server knows exactly one real file:
`index.html`. Navigating to /settings works — that is JavaScript. *Reloading*
/settings, or opening a shared link, asks the server for a file that does not
exist. Without the fallback the site looks fine and breaks on the first F5, in
production, found by a user.

`ssh` and `ghcr` have no `.spa` because the fallback is not the workflow's to
write there — it is `try_files` in nginx, or `FallbackResource` in Apache. Both
snippets say so, and `ghcr`'s carries the nginx line in its Dockerfile sketch.
The trap does not disappear with the fragment; it moves.

## The four properties of the CD, and why each is load-bearing

They are implemented in `deploy.yml` and commented there. Repeated here only
because deleting one is easy and looks harmless:

1. **It deploys only what a green CI produced — with no exception.** A manual
   `workflow_dispatch` used to rebuild from an arbitrary checkout, which shipped
   a binary no gate had seen while the file claimed the opposite. It now
   *resolves* the latest successful CI run on the default branch and deploys
   that run's artefact, or refuses to start. There is no rebuild branch left.
2. **It ships that run's artefact, never a rebuild.** Rebuilding sends a binary
   nothing tested — same commit, different output, and no one sees it happen.
3. **The job provides the environment; the `Publish` step never assumes it.**
   Checkout, pnpm and Node are set up unconditionally, before the artefact is
   downloaded — checkout must come first, since it cleans the workspace, and it
   pins `ref` to the triggering commit because `workflow_run` otherwise checks
   out the default branch. This one is written down because getting it wrong is
   silent: the workflow parses, the job starts, and the publish step dies on a
   missing Dockerfile or a `pnpm: command not found` (pnpm is **not** preinstalled
   on the ubuntu runner images — npm and yarn are). The checkout brings sources,
   never the published bytes: those still come from the CI's artefact alone.
4. **`environment: production` is the human gate.** It is inert until you set a
   required reviewer in Settings → Environments. Without that, the workflow
   deploys on every merge to `main` — which may well be what you want, but it
   should be a decision you made.

## What is deliberately not here

- **No release / version-bump job.** `/ship` owns the commit and the board;
  a second thing writing to the repo on push is how two mechanisms start
  disagreeing about what shipped.
- **No E2E in `ci.yml`.** `e2e-tester` runs at `/review`, against a real
  browser, on a bounded set of flows. Booting Playwright on every push buys
  minutes and a flake budget nobody is watching.
- **No matrix over Node versions.** `01-stack.md` pins a floor (20.19+ / 22.12+,
  Vite 8's constraint), not a support range. One version, the one you deploy.
- **No third-party secret scanner** (gitleaks, trufflehog). The `Bundle secrets`
  step is deliberately the *same* grep `/ship` runs and nothing more: it answers
  one question — did a real secret get a `VITE_` prefix and therefore ship in
  the bundle — and it answers it with no action to trust and no allowlist to
  maintain. History scanning is GitHub's push protection's job, at the forge,
  not a step here.
