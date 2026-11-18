# Plan critic, pass 2 (2026-11-18, profile critical, effort high, rerun after rewrite)
Scores: completeness 84 · quality 76.

## Pass-1 findings (against the verifier-corrected closures in route-plan-1.json)
F1, F2, F3, F4, Q1, Q2, Q3, Q4: **fixed**. AC re-walk: AC1 → steps 6-7, AC2 → steps 1-4,
AC3 → step 8, AC4 → IN46/IN51/IN52, AC5 → step 9; none dropped.

## New
- **F7 Major, b, demonstrated** — the winner map knows only the addons chosen this run: a
  re-install with no addon flag (as install.sh:831-834 itself advises for `--deploy`) over a
  `--fastapi`/`--supabase` project overwrites the addon `commands/database/migration.md` with core
  (today: copy_file → core to `.new`). No case.
  Closure: step 5 defines the winner for a destination an addon installed in an earlier run;
  IN case: after `--fastapi`, a re-install with no addon flag leaves migration.md byte-identical
  to the fastapi copy, no backup, no adapted line.
- F8 Minor, vigilance — other twins with a prompt side: audit-flags (ship.md fence), ci-scripts,
  gate-allowlist (ship.md), agent-models/agent-efforts (agents/*) (`kit-doctor.py:644-670,
  :597-606, :458-499`): each needs a project-owned side that can always be brought into line.
- **Q9 Major, c, demonstrated** — step 5 cannot go green: removing the supabase rewrites makes a
  fresh `--supabase` install report DIVERGENCE client-copies / coverage-holes until step 7;
  `test-install.sh` (`set -euo pipefail`) aborts at :86/:87, IN13 :481-482 exits 1.
  Closure: the kit-source-only gating of client-copies/tdd-layers/coverage-holes/coverage-floor
  (and the :86/:87 SKIP assertions) lands before or with step 5.
- Q10 Minor, vigilance — shipped-paths rstrips `./\`,;:)` before the exemption
  (`kit-doctor.py:1043-1045`): `.claude/overlays/<x>` → `.claude/overlays`; startswith with a
  trailing slash misses; the recipes exemption must hold in installed mode too.
- Q11 Minor, vigilance — IN55/PK20 predicates not mechanical; strict form: every four-dir path in
  README §3/§4 and the summary is prefixed by `.claude/overlays/`.
- Q12 Minor, vigilance — FASTAPI-ADDON.md (`install.sh:778`) / SUPABASE-ADDON.md (`:744`) copy mode
  + manifest undecided (pass-1 V4): an upgraded project keeps stale guidance to edit ship.md.
- Q13 Minor, vigilance — KD22's fixture must list the same 7 shared_dirs in 02-architecture.md and
  CLAUDE.md, or their (kept) twins fire.
- Q14 Minor, demonstrated — stale text outside rewritten sections: Files table case ranges, no
  `addons/fastapi/README.md` / `guides/review/security.md` rows; OQ7 still says copy_override
  keeps its precedence.
