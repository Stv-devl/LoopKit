# Plan critic, pass 3 (2026-11-18, profile critical, effort high, rerun after rewrite — last pass)
Scores: completeness 88 · quality 78. AC re-walk: AC1 → steps 6-7, AC2 → steps 1-4, AC3 → step 8,
AC4 → IN46/IN51/IN52/IN56/IN57, AC5 → step 9; none dropped. Pass-2 minors in Vigilance, Q14 fixed.

## Pass-2 findings
- F7: **fixed** (winner order + IN56/IN57; marker rule sound against install.sh:744, :778).
- **Q9: not fixed** — the supabase-rewrite removal did move to step 7, but step 5's copy_kit arm
  still breaks IN13 (`test-install.sh:470-472`): run 1 `--supabase` rewrites the 4 templates; run 2
  `--fastapi` copy_kit-overwrites them with the kit copies; run 3 `--supabase --fastapi` never
  re-runs the perl rewrite (`data_client` already lib/supabase, install.sh:489-501,
  project_config.py:451-453) → `:477` fails under `set -e`; moved, `:481-482` still exits 1 on
  DIVERGENCE client-copies (not gated until step 7).
  Closure: the client-copies/coverage-holes installed-mode SKIP gating (with :86/:87 SKIP pins)
  lands before or with step 5's copy_kit arm; or IN13 :477 / :481-482 are satisfiable at step 5.

## New
- **F9 Major, b, demonstrated** — winner rule (3) (both addon markers, no flag → left in place,
  named in the summary) has no case; install.sh:781-785 tells a two-addon user to hand-merge
  migration.md, the state rule 3 protects.
  Closure: IN case after `--supabase` then `--fastapi`, migration.md edited, re-install with no
  addon flag → migration.md byte-identical to the edited copy, no kit-backup copy, path named in
  the summary.
