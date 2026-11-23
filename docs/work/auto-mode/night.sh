#!/usr/bin/env bash
# Overnight auto-mode run (user, 2026-11-20): validate up to the Plan gate, then sleep.
set -euo pipefail
cd /home/stevan/Travail/Projetperso/LoopKit
prompt="/loop:orchestrate docs/specs/auto-mode.md — en worktree. Je valide jusqu'au Plan gate puis je dors. Après mon go, applique docs/work/auto-mode/night-arbiter.md de l'arbre principal : chaque décision qui me reviendrait est tranchée par un agent reviewer arbitre neuf ; trace dans night-decisions.md et en tête de la PR. Ne merge jamais."
exec ./workflow.sh --dangerously-skip-permissions \
  --settings docs/work/auto-mode/night-settings.json \
  "$prompt"
