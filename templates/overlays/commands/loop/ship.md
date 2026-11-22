# Project overlay: /loop:ship

Read before following `.claude/commands/loop/ship.md`. Each `## <slot>` section holds this
project's value for the slot of the same name in the prompt; a section still holding its
`FILL` note counts as absent, and the prompt's default applies.

## extra-gates

<!-- FILL: a second unit runner (backend), added to the same gate batch when the diff touches
     its surface, e.g. `uv run pytest -q`. Never e2e: it runs after this batch is green. -->

## deploy

<!-- FILL: the real deploy commands, and their traps (a bulk deploy that resets per-unit
     flags, a migration push that applies every pending migration). -->

## Local rules

<!-- Optional: this project's extra rules for /loop:ship. The kit prompt itself is never edited. -->

## Recipes

<!-- Optional: one line per recipe that /kit:recipe wrote for this command. -->
