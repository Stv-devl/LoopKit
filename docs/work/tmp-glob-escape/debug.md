# Debug: /tmp glob + `..` and /dev/fd/N/ writes escape the shell write guard

Token profile: critical

## Symptom
`prevent-destructive-commands.sh` passes (no ask, no deny) a shell write whose target starts
under `/tmp` or `/dev/fd/` but resolves inside the project:
- `echo x > /tmp/claude-1*/../../<project>/.claude/settings.json` → pass (direct path asks)
- `echo x > /tmp/<glob>/../..<project>/src/a.py`, `…/src/a.utils.t?` → pass (direct path denied)
- `exec 9<"$PROJECT"; echo x > /dev/fd/9/.claude/settings.json` → pass
Proven in real bash (scratchpad): the write lands on the project file.
Source: `app-roots-codegen` batch-5 security re-review, 2026-11-11; recorded in
`docs/specs/harness-hardening.md` follow-ups.

## Environment
Main tree, branch `audit/slim` at `093c262`, clean. Fixtures: `.claude/hooks/test-hooks.sh`
(`pd_probe`, `g15_expect`), 2128 green.

## Expected / actual
- Expected: a write target that may resolve inside the project is guarded like the direct
  path (at least ask). `/tmp/<plain>`, `/tmp/<glob without ..>`, `/dev/null`, `/dev/stdout`,
  `/dev/stderr`, `/dev/fd/0-2` keep passing.
- Actual: pass.

## OUT
- Alias writes (`shopt -s expand_aliases; alias w='echo x > src/a.py'; w`): stays a follow-up.
- Output-option writers (`curl -o`, `sort -o`, `wget -O`, `dd of=`): stay follow-ups.
- No change to the in-project glob/extglob rules.

## Candidate causes (ranked)
1. **Tokenizer drops everything after the first glob character** (`shell_targets.py:1805-1812`,
   `target()`): a glob word becomes `?glob:<dirname of the pre-glob prefix>` + the last segment,
   so `/tmp/*/../..<project>/x` is reported as folder `/tmp`; the `..` that climbs back out is
   lost, `cwk_guard_rel` fails (outside the project), and the `/tmp` exemption
   (`prevent-destructive-commands.sh:612-614`) returns pass.
   - For: the folder is computed from `word[:min(cuts)]` only. Against: none found.
   - Falsified if: the row for the CG54 word holds anything under the project path.
   - Validation point: the rows `shell_targets.py <command> <base>` prints (the hook's input).
2. **The `/tmp` exemption ignores the target kind** (`:612`, applies to `plain=0` glob rows):
   even with a correct folder, a glob row rooted at `/tmp` is exempt.
   - For: no `plain` test on the branch. Against: if cause 1 is fixed, the folder is no longer
     `/tmp`, so this alone does not leak a project write.
   - Falsified if: a glob row whose folder resolves inside the project still passes.
3. **`/dev/fd/*` is a textual exemption** (`:611`): any `/dev/fd/<n>/…` passes before resolution.
   - For: `case … /dev/fd/*) return 0`. Falsified if: `/dev/fd/9/x` row is not `/dev/fd/…`.

## Validation (2026-11-11, observed at the tokenizer boundary)
No `LOOPKIT_DEBUG` log was needed: the boundary is a standalone CLI whose stdout is the hook's
input. `python3 -I .claude/hooks/shell_targets.py "<cmd>" <project>`:
- `echo x > /tmp/*/../..<P>/.claude/settings.json` → `>  ?glob:/tmp<US>settings.json`
- `echo x > /tmp/*/../..<P>/src/a.utils.t?` → `>  ?glob:/tmp<US>a.utils.t?`
- `echo x > /tmp/../tmp/x/src/a.py` → `>  /tmp/x/src/a.py` (no glob: `..` normalised correctly)
- `echo x > /dev/fd/9/.claude/settings.json` → `>  /dev/fd/9/.claude/settings.json`

## Root cause
Cause 1 (predicted row observed): a `..` segment after the first glob character is discarded by
`target()`, so the hook sees a `/tmp` folder. Cause 3 holds independently for `/dev/fd/N/`.
Cause 2 is not a leak on its own once cause 1 is fixed.

## Fix boundary
- `shell_targets.py` `target()`: a glob word whose text after the first glob cut holds a `..`
  segment returns `?unknown:<word>` (asks; bash's expansion of `*/..` cannot be resolved
  lexically).
- `prevent-destructive-commands.sh:611`: exempt `/dev/fd/0`, `/dev/fd/1`, `/dev/fd/2` only.

## Required close (2026-11-12)
- Before (HEAD `093c262`): CG54, CG55, CG56, CG58 (both spellings), CG59 → `pass`. CG57 → `deny`
  already (no glob: `..` was normalised), kept as a regression guard.
- After: CG54-CG59 → `ask` (CG57 `deny`); CG60 (`/tmp/out.txt`, `/tmp/d/out.txt`, `/tmp/*.log`,
  `/dev/fd/2`, `/dev/null`) → `pass`. `test-hooks.sh`: 2140 cases, all green.
- Regression test: `.claude/hooks/test-hooks.sh`, `run_codegen_cases`, CG54-CG60.
- Review (security+correctness, critical): fix sound, no regression; verdict FAIL on pre-existing
  escapes outside this boundary (fd 0-2 re-bound, brace-hidden `..`, glob matching `..`, /tmp
  symlinks). Debug's "cause 2 is not a leak once cause 1 is fixed" is false (symlinks). The user
  chose to commit this fix and open a new debug; findings in `docs/specs/harness-hardening.md`.
