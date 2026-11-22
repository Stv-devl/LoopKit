# Debug: the /tmp and /dev/fd exemptions still let a shell write land in the project

Token profile: critical

## Symptom
`prevent-destructive-commands.sh` passes (no ask, no deny) a shell write that lands on a project
file, because the target is spelled under `/tmp` or as `/dev/fd/0-2`, `/dev/stdout`, `/dev/stderr`.
Each case below was proven in real bash 5.2.21 against a scratch project `$P` (the write
landed on the file):
1. fds 0-2 re-bound read-only to a project file: `echo x 1<$P/src/a.py >/dev/fd/1`,
   `exec 2<$P/.claude/settings.json; echo x > /dev/stderr` (also `/dev/fd/2`, `/dev/fd/0`).
2. Brace-hidden `..`: `echo x | tee /tmp/{.,}.$P/src/a.py` (also `tee -a`, `cp f <that> /tmp/`).
3. A glob matching `..` (`globskipdots` off, the default before bash 5.2):
   `shopt -u globskipdots; echo x > /tmp/.[.]$P/.claude/settings.json` (also `.?`, `.*`).
4. Symlinks under /tmp (`$S` = a folder under /tmp):
   - a link made in the same command: `ln -s $P/.claude $S/l && echo x > $S/l/settings.json`;
   - a link that already exists, followed by `..`: `echo x > $S/preB/../.claude/settings.json`
     (`preB` → `$P/src`);
   - a glob through a link: `echo x > $S/pre?/settings.json`;
   - a link as the final component (`$S/x.log` → `$P/src/a.py`), written by `>`, `tee` or `cp`.
Source: the `tmp-glob-escape` review, 2026-11-12. Recorded in `docs/specs/harness-hardening.md`.

## Environment
Main tree, branch `audit/slim` at `22fa7d9`. Fixtures: `.claude/hooks/test-hooks.sh`
(`pd_probe`, `g15_expect`), 2140 green.
Probe: `/tmp/claude-1000/-home-stevan-Travail-Projetperso-LoopKit/1994288a-fcd0-4f63-8e43-4db8ef366fda/scratchpad/probe.sh <hooks_dir> <project> "<cmd>"`.

## Expected / actual
- Expected: a write that may land in the project is guarded like the direct path (at least
  ask). These keep passing: `/tmp/<plain>` and `/tmp/<dir>/<plain>` when no link is involved,
  `/tmp/*.log` when no match is a link, and `/dev/null`. `>&2`, `2>&1`, `2>/dev/fd/2`,
  `>/dev/stderr` and `tee /dev/stderr` also keep passing when the command does not re-bind
  that fd to a file.
- Actual: pass.

## OUT
- Alias writes, output-option writers (`curl -o`, `sort -o`, `wget -O`, `dd of=`): stay follow-ups.
- In-project glob/extglob rules, and the ask message wording outside the new branches.
- `/proc/self/fd/N`: already asks.

## Reproduction
CG61-CG70 in `.claude/hooks/test-hooks.sh` (`run_codegen_cases`). Each was checked with the
probe against HEAD `22fa7d9`: CG61-CG69 give `pass`, CG70 gives `pass`.

## Candidate causes (ranked, one per finding family)
1. **The fd exemption is textual, and read redirects make no row**
   (`prevent-destructive-commands.sh:611`, `shell_targets.py:794-808`).
   - The hook sees only the `>` row `/dev/fd/1` or `/dev/stderr`. A `N<file` that re-binds the
     same fd leaves no trace in the rows, so nothing can be correlated.
   - Falsified if: the row output contains a `<` row carrying the fd number.
   - Validation point: the rows printed by `shell_targets.py <cmd> <base>`.
2. **The `..` check reads raw text, and `/tmp` exempts glob rows**
   (`shell_targets.py:1808`, `prevent-destructive-commands.sh:612-615`).
   - `{.,}.` and `.[.]`, `.?`, `.*` are not the text `..`, so they reach `?glob:/tmp…`, and the
     `/tmp` branch returns pass whatever `plain` is.
   - Falsified if: the row folder is anything other than `/tmp`.
3. **Path resolution is lexical first, then physical only up to the deepest existing folder**
   (`shell_targets.py:1818` `normpath`, `hook-guarded.sh:136` `__cwk_guard_norm`, `:277-284`).
   - `link/..` is folded before any link is seen.
   - A final component that is a link is never followed.
   - A glob row is never expanded.
   - A link made earlier in the same command does not exist yet when the hook runs.
   - Falsified if: the row for `$S/preB/../x` keeps `preB`, or `cwk_guard_rel $S/x.log` returns
     `src/a.py`.
4. (Less likely) **The `/tmp` exemption runs before the glob/shopt checks**
   (`prevent-destructive-commands.sh:612` vs `:622+`). This contributes to 2, but it cannot
   explain 1 or 3 alone.

## Validation (2026-11-12, at the tokenizer and resolver boundaries)
No `LOOPKIT_DEBUG` log was needed: both boundaries are standalone callables. `$SP` is the
scratchpad.
- `echo x 1<$P/src/a.py >/dev/fd/1` → a single row `>  /dev/fd/1`, with no `<` row. Cause 1 holds.
- `exec 2<$P/.claude/settings.json; echo x > /dev/stderr` → a single row `>  /dev/stderr`. Cause 1 holds.
- `echo x | tee /tmp/{.,}.$P/src/a.py` → `tee  ?glob:/tmp<US>a.py`. Cause 2 holds.
- `… > /tmp/.[.]$P/.claude/settings.json` → `>  ?glob:/tmp<US>settings.json`. Cause 2 holds.
- `… > $S/preB/../.claude/settings.json` → `>  $SP/s/.claude/settings.json` (`preB` folded
  away). Cause 3 holds.
- `… > $S/pre?/settings.json` → `>  ?glob:$SP/s<US>settings.json` (not expanded). Cause 3 holds.
- `cwk_guard_rel $S/x.log` → rc=1, empty, so the final link is not followed. `cwk_guard_rel
  $S/preB/a.py` → `src/a.py`, rc=0, so a link mid-path that already exists is followed.
  Cause 3 holds for the final component and for `..`, not for a plain link mid-path.

## Required close (2026-11-12)
- **Before** (HEAD `22fa7d9`): CG61-CG69, CG71-CG77, CG80-CG82 → `pass`. CG78-79 → `pass` at
  HEAD; they guard against the false asks revision 1 introduced.
- **After**: all of them ask or deny. The /tmp and stderr uses in CG70 and CG78-79 pass.
  - `test-hooks.sh`: 2192 cases, all green.
  - The other 8 kit suites: green.
- **Fix boundary**:
  - `shell_targets.py`:
    - `tmp_physical` resolves links in order, gives up on `/proc` and `/dev`, and treats a
      second hard link as unknown;
    - `?tmp:` rows;
    - `exec_rows` takes the physical root;
    - a unit separator gives `?unknown`.
  - `prevent-destructive-commands.sh`:
    - `guard_fd_bound` (R1) and `guard_makes_link` (R4);
    - the `?tmp:` branch (R3) and the /tmp glob branch (R2);
    - the `GUARD_ASK_T` message.
- **Removed diagnostics**: none were added. The boundaries were observed through the
  `shell_targets.py` CLI and `cwk_guard_rel`.
- **Regression tests**: `.claude/hooks/test-hooks.sh`, `run_codegen_cases`, CG61-CG83 and CG60-R2.
- **Review**: 3 attempts.
  - 1/3 FAIL: the lexical design was bypassed, so the user chose the fail-closed redesign.
  - 2/3 FAIL: one new regression (`find -exec`) and regex gaps.
  - 3/3 is revision 3, a regression-only fix, as the user chose. Its result was CONCERNS:
    1 Major introduced, in `exec_rows`. Fixed by running both roots (CG83), with no 4th
    review, by user decision.
  - What remains open: `docs/specs/harness-hardening.md`, spec `guard-tokenizer-fd-links`.

## Root cause
Causes 1, 2 and 3 are all observed. There is one root: the `/tmp` and fd exemptions trust the
target text, when that text can still be bound (fd), expanded (brace/glob) or redirected
(symlink) before the write happens.
