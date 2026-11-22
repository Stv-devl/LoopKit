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

Where it goes depends on the repo. In an installed project (`.claude/INSTALL_PROFILE`
present, or `install.sh` and `addons/` not both at the root) the kit prompts are denied:
write `.claude/recipes/<name>.md` and cite it in the invoking prompt's overlay,
`.claude/overlays/<the prompt's path under .claude/>`, under `## Recipes`. In the LoopKit
repo, write `.claude/guides/<name>.md` and cite it in the invoking prompt, as below.

Create the recipe file containing only:

1. one-line `Read when …` trigger;
2. prerequisites and observable inputs;
3. the shortest ordered procedure reproducing the outcome;
4. deterministic verification and explicit stop conditions;
5. traps that change an action, not session history.

Write imperatively and link existing patterns/templates rather than copying.
Then add exactly one citation to the supplied invoking file (installed project: its
overlay's `## Recipes` section) where the procedure becomes relevant. A guide with no caller is dangling; an `@` import or automatic
loader defeats progressive disclosure and is forbidden.

Run `/kit:doctor` and report the recipe, evidence, caller and what stayed out of
hot rules.

## Task: $ARGUMENTS
