# Prior plan critic: superseded 2a plan
Token profile: critical

Copied on 2026-11-16 from the superseded `docs/work/kit-boundary/plan.md` `## Plan critic`, before that plan was deleted for the 2a-3 re-entry. The full superseded plan, with the pass 1 finding texts it tags, is in git history: `git show 364f906:docs/work/kit-boundary/plan.md`. Findings on values, readers, APP_ROOTS and CODEGEN belong to passes 2a-1 and 2a-2, both shipped. The git-route, installed-check and install findings carry over to this pass.

## Plan critic
- **Pass 1** (2026-11-10, effort high): completeness 52, quality 38.
- **Verifier** (2026-11-10, effort high, against HEAD e4837f2); `attempts.json` plan-critic 1/3.
  - Survive: C1 (a contract conflict), C2, M1-M8, M11, M12, M14, M16, M18.
  - Partial: M9, M10, M13, M15.
  - Refuted: M17, M19.
  - Minors survive: m1, m2, m4, m5; partial: m3, m6, m7.
  - Outcome: the user split the spec on 2026-11-10 (pass 2b `kit-prompts.md`). This rewrite 2 tags each fix with its finding id.
- **Pass 2** (2026-11-10, effort high): completeness 68, quality 42, **not yet verified**.
  - Critical: the test setups contradict Q1/Q3. Fixtures run the kit's own hooks with a tmp `CLAUDE_PROJECT_DIR`, so a config and kit markers found from the hook's own dir always see the kit repo (`test-hooks.sh:538`).
  - Majors:
    - Install and frozen rows:
      - 9 frozen "P1 held back" blocks of `test-install.sh` beyond `:147-250` flip with the overwrite but are missing from `## Gate`, as are `test-kit-doctor.sh:44-58` and (d) `:259-269`;
      - the hold-back becomes dead code while W5 extends it;
      - the upgrade migration is specified for only 4 of the keys.
    - Values and readers:
      - `hook-lib.sh:287-294` still holds the fastapi mirror (`CWK_TDD_PY_TARGET_RE`);
      - the fastapi addon hooks cannot find the reader from `addons/fastapi/hooks/` in the kit repo;
      - fail closed is undefined for the PostToolUse/Stop hooks (`format-on-save`, `tdd-prove-red`, `eslint-batch`);
      - the `kit-doctor.py <root>` argument breaks.
    - `/kit:init`: APP_ROOTS and CODEGEN detection/proposal are not planned.
    - Git routes:
      - three-dot is wrong for switch/checkout `<branch>`;
      - apply misses unified `---`/`+++` patches and the `-C` prefix of patch paths;
      - git `rm`/`mv` miss directory and pathspec-magic operands;
      - `merge-file`, `checkout-index`, `read-tree -u` and `reset --keep|--merge` are unruled.
    - The `apply` deny is a text match only.
  - Minors:
    - V13 needs step 3; G19.11 is not RED;
    - Q3 can be partly faked by `cp -r … .`;
    - no latency budget for the per-key python spawns;
    - X23 surely flips;
    - `check_tdd_layers` twin;
    - older-schema "denies nothing new" untested.
