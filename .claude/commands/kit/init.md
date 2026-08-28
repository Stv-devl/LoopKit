---
description: Inspect this project, ask only the closed adaptation choices, fill every safe kit marker, then run /kit:doctor
argument-hint: "[--resume]"
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# /kit:init — adapt LoopKit to this project

Turn the installed template into this project's constitution. The ordered source
of truth is `docs/ADAPTATION.md`, sections 1–13. Read a section only when reaching
it; do not load the whole guide up front.

This command edits kit configuration and prose, never application behaviour. It
does not create a product brief, spec, plan, migration, commit, remote, or deploy.
Never read `.env*`, credentials, keys, or secret values. File existence, imports,
`.env.example`, package manifests, and variable names at usage sites are enough.

## Contract

- Observation is filled from evidence. A choice is asked as a closed question.
- Never compose a value and ask for approval. Present the finite choices first;
  the user's selection is the value.
- Never guess the data client, composition roots, deploy target, production host,
  scripts, languages, or backend. An unanswered item keeps its marker.
- Do not proceed on silence at a question gate. `--resume` repeats inspection,
  preserves already-resolved values, and asks only what remains open.
- A marker is removed only when its whole instruction is satisfied. Do not hide
  unfinished work by deleting the words `FILL` or `CONFIGURE`.
- Every paired value named by `/kit:doctor` moves in the same edit pass.

## Phase 1 — inspect, read-only

Build an evidence table with `value`, `evidence path`, and `confidence` for:

1. package manager, from lockfile existence (do not read the lockfile body);
2. framework and test/build/lint/typecheck scripts, from manifests and config;
3. source roots, feature roots, shared directories, and composition-root files;
4. data-client candidates, from imports and client creation sites — never from
   secret files; distinguish the module path from the exported instance;
5. backend and database presence, migrations, edge functions, and their runners;
6. Git repository, current branch convention visible in branches/docs, and
   whether a remote exists (`git remote`, without contacting it);
7. installed addons and existing GitHub workflows;
8. user-facing language and existing icon library/usage from authored code.

Absence is evidence only for optional capability (`no backend detected`, `no
remote detected`). It is not permission to invent the missing value.

## Phase 2 — closed question gate

Show the evidence table, then ask one compact batch of closed questions for every
choice observation cannot settle. Include only relevant questions, each with
explicit options and an `leave open` option:

- data client module + own path, and the short list of composition roots;
- default token profile: `economy`, `standard`, or `critical`;
- local command and production: detected target, `none yet`, or a named target;
- CI: install/keep it because a remote exists, or no workflow while local-only;
- forbidden icon set: keep LoopKit's default, provide a replacement set, or open;
- protected branches: `main`, `master`, both, or an explicit list;
- user-facing language and log/error language;
- backend/database policy when those surfaces exist.

If two plausible package managers, clients, roots, or scripts remain, ask between
those observed candidates. Do not add a synthetic recommendation.

## Phase 3 — apply `docs/ADAPTATION.md` in order

For every section, re-read that section immediately before editing it:

1. `01-stack.md`: data-client table and stack/scripts facts.
2. `enforce-architecture.py`: `DATA_CLIENT_MODULE`, `DATA_CLIENT_OWN_PATH`,
   `COMPOSITION_ROOTS`, `SHARED_DIRS`; then section 2 bis secret-template twins.
3. Scaffold `src/lib/result.ts`, `errors.ts`, `queryClient.ts` only when the
   detected stack matches the shipped template and the files do not exist.
4. `00-project.md`: exact run-once gates and the same script names in every twin;
   handle the CI mirror from section 4 bis.
5. `02-architecture.md`: backend declaration.
6. `06-database.md`: database and migration ownership.
7. `CLAUDE.md`: project name, Environment, protected directories, invariants.
8. `03-conventions.md`: user language and English logs/errors.
9. feedback/guard patterns.
10. E2E backend choice, only if that skill is installed.
11. icon rule and `no-forbidden-icons.sh` together.
12. worktree base and branch convention.
13. review level-zero browser capability; report absence, never fake it.

After each section, run only its deterministic probe from `docs/ADAPTATION.md`.
Do not run an application gate until its command has been resolved.

## Phase 4 — audit and handoff

Run:

```bash
grep -rnE "FILL|CONFIGURE" .claude/ CLAUDE.md docs/
```

Classify every remaining marker as:

- `needs user choice`;
- `needs missing project evidence`;
- `not applicable but marker retained pending an explicit decision`;
- `generated later by the loop`.

Print a final report with:

1. every file changed and the observations/choices applied;
2. every marker left open, one line each, with exact `path:line` and reason;
3. every scaffold or workflow deliberately skipped;
4. the exact next command.

Then invoke `/kit:doctor`. A divergence is not repaired by guessing: report both
files it says must move together and stop. When doctor is green, finish with:

```text
Adaptation complete. Next: /loop:spec <feature>
```
