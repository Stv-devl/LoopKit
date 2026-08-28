---
description: Distill one proven reusable procedure into a cold guide and wire one explicit on-demand citation
argument-hint: "<name> <evidence artifact> <invoking command/pattern path>"
---

# /kit:recipe — proved procedure to on-demand guide

A recipe is cold procedural memory, not an always-loaded rule. It is useful only
when one existing command, pattern, template or skill cites its exact path at the
moment the procedure applies.

Require a kebab-case name, evidence that the procedure succeeded, and the
existing invoking file. Stop if the lesson is speculative, one-off,
product-specific, already carried by a hook deny text, or has no invocation
point. Search rules, hooks, guides, patterns and templates first; update the
single authority instead of creating a duplicate.

Create `.claude/guides/<name>.md` containing only:

1. one-line `Read when …` trigger;
2. prerequisites and observable inputs;
3. the shortest ordered procedure reproducing the outcome;
4. deterministic verification and explicit stop conditions;
5. traps that change an action, not session history.

Write imperatively and link existing patterns/templates rather than copying.
Then add exactly one citation to the supplied invoking file where the procedure
becomes relevant. A guide with no caller is dangling; an `@` import or automatic
loader defeats progressive disclosure and is forbidden.

Run `/kit:doctor` and report the recipe, evidence, caller and what stayed out of
hot rules.

## Task: $ARGUMENTS
