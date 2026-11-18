# Project overlay: the `e2e-playwright` skill

Read before following `.claude/skills/e2e-playwright/SKILL.md`. Each `## <slot>` section
holds this project's value for the slot of the same name in the prompt; a section still
holding its `FILL` note counts as absent, and the prompt's default applies.

## drivers

<!-- FILL: if this repo also drives a browser for something else (a scraper, a worker), say
     so and state that it shares nothing with this harness. -->

## harness

<!-- FILL: the real paths and scripts of the Playwright harness. -->

## backend-case

<!-- FILL: the most important section. State exactly one: A (disposable local stack, reset
     per run), B (seeded shared test project) or C (the real project, partially mocked:
     read-only, name what the mock covers and the actions that must never fire). Absent:
     the skill stops and asks. Unsure means C. -->

## Local rules

<!-- Optional: this project's extra rules for the skill. The kit prompt itself is never edited. -->

## Recipes

<!-- Optional: one line per recipe that /kit:recipe wrote for this skill. -->
