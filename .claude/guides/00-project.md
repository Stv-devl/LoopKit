# Guide — the six gate roles

Read when someone asks why a gate is a gate, or proposes removing one. Nothing
loads this file; `.claude/rules/00-project.md` names it.

## Why five of the six run twice

`/loop:ship` runs them before the commit, on the machine that launched it;
`.github/workflows/ci.yml` runs them after the push, where nobody can skip them —
a disabled hook, a `--no-verify`, another machine, an agent that short-circuited
the step. The sixth, the dev server, is a local role with nothing to serve in CI.
Which role lands where, why no agent runs in CI, and what the deploy workflow
guarantees: `.claude/skills/templates/ci.md`; the enforced copy is the YAML
itself. The script **names** in the rule are a twin of its `run:` lines —
`/kit:doctor`'s `ci-scripts` compares them, and it is the only thing that does.
**A green CI is not a reason to stop running `/loop:ship`**: it reports on a diff
already pushed, `/loop:ship` reports while the fix is still free.

## Why the dependency audit is a gate

**Why the dependency audit is a gate.** It is the one security surface a
machine reads better than an agent, and the only one of the six in
`/audit:security` that a reviewer cannot see in a diff at all: a CVE published
last week changes nothing in your code. `11-token-budget.md` is explicit that a
deterministic gate costs **compute, not model context** — this one is free in
the only budget that is scarce here, so it runs on every ship rather than
waiting for someone to remember the audit.

**Its red is a decision, not a wall.** A high/critical advisory **with a fix
available** is a red gate: bump it. One with **no fix published** cannot be a
wall — announce it with the package, the advisory and the reachability (is the
vulnerable path even called?), and let the user decide. What is forbidden is
the third option: swallowing it silently because the release is due.

## Why lint is a gate and not just a hook

**Why lint is a gate and not just a hook.** `eslint-check.sh` enqueues after
every write and `eslint-batch.sh` lints the batch once, at the end of the turn
— and it is **non-blocking**: it prints a count, nothing more. `pnpm lint
--max-warnings=0` in `/loop:ship` is the only thing that stops the three classes of
defect nothing else sees: conditional hooks and exhaustive-deps; a component
the React Compiler **silently skipped** (a green build says nothing about
whether the code is actually memoized); and a test that asserts nothing, is
`.only`'d or `.skip`'d — `test:run` stays green on all three. Rules:
`01-stack.md`, "The lint on the tests"; config: `templates/tooling-config.md`.
