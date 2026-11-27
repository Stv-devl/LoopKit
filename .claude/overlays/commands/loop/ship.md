# Project overlay: /loop:ship — the LoopKit repo itself

Read before following `.claude/commands/loop/ship.md`. Each `## <slot>` section holds this
project's value for the slot of the same name in the prompt; a section still holding its
`FILL` note counts as absent, and the prompt's default applies. This file belongs to the kit
repo only: `install.sh` never copies it (targets are seeded from `templates/overlays/`).

## extra-gates

```bash
.claude/scripts/kit-lint.sh
```

The local twin of kit-ci.yml's lint (shellcheck, ruff, actionlint and the assembled target
workflows), at CI's versions and flags. A `MISSING` line is a red gate, never a note: CI would
run that step and could fail on it.

## deploy

<!-- FILL: the real deploy commands, and their traps (a bulk deploy that resets per-unit
     flags, a migration push that applies every pending migration). -->

## Local rules

<!-- Optional: this project's extra rules for /loop:ship. The kit prompt itself is never edited. -->

## Recipes

<!-- Optional: one line per recipe that /kit:recipe wrote for this command. -->
