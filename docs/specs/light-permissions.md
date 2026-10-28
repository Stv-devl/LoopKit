# Spec: Light loop without permission prompts
> **Superseded 2026-10-28** (plan-critic BLOCKED 3x, `docs/work/light-permissions/handoff.md`). Split into three passes, in order: `docs/specs/guard-writes.md` → `docs/specs/guard-shell.md` → `docs/specs/light-permissions-git.md`. Kept as the trace; do not orchestrate this file.

Token profile: critical (it widens what the agent may do without a prompt and hardens the hooks that compensate)
Split from: `docs/specs/light-fewer-gates.md` (2026-10-27), which keeps the loop change only. Ships before `docs/specs/fast-lane.md`.

## Objective
Permission prompts disappear for commands the hooks already police, and every guardrail the hooks rely on (their own files, their escape hatches, their RED markers, the gate configs) stays in front of the user, whatever tool or shell verb reaches it. Evidence for the gain: `docs/measuring-the-loop.md`, "5 minutes of work behind one unapproved `Write`".

Threat model: a **mistaken** agent in `acceptEdits` with the allow list below. Not a deliberately adversarial one. P1 never ships without P2.

## Scope
- IN :
  - **P1. Permissions, narrow.** `.claude/settings.json`: `permissions.defaultMode: "acceptEdits"`, plus allow `git add *`, `git commit -m *`, `git switch -c *`, `git branch --show-current`, `git worktree list`.
    These prefixes match **any trailing argument**: `git commit -m x --amend` and `git switch -c x --discard-changes` match them. The allow list is therefore not the guard; the hooks of P2 are, and every dangerous flag has an H case with the flag placed last. `git branch *`, `git switch *`, `git commit *` stay unlisted so that the forms without `-m`/`-c` still prompt.
    `github.md` fixes the commit form to `git commit -m "<one line>"` (no heredoc, no `$(...)`) and the staging form to `git add <explicit paths>` (never `.`, `-A`, `--all`, `-u`, a directory or a glob).
    Research, written in this spec's research, **informs but no longer decides** P2: what `acceptEdits` auto-approves besides Write/Edit (`mkdir`, `touch`, `rm`, `mv`, `cp`, `sed`?); which of the existing allows (`cat`, `sed -n`, `find`, `git diff`, `rg`) can write a file or run a program (`>`, `sed -n -i`, sed `w`, `find -exec`, `git diff --output=`, `rg --pre`).
  - **P2. Hook hardening that P1 makes necessary.**
    - **Guarded set**, one list, used by both hooks below: `.claude/hooks/**` (fixtures and `hook-lib.sh` included), `.claude/scripts/**` (kit scripts, `docs/specs/fast-lane.md` F7b), `.claude/settings*.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `.claude/.tdd-red/**` (only `tdd-prove-red.sh` writes a RED marker; a hand-written one creates a module with no RED), `vitest.config.*`, `eslint.config.*` (the coverage floor and the lint that forbids assertionless tests).
      It lives in `.claude/hooks/hook-guarded.sh` (new), a file with **no side effect** when sourced (no trap, no log, no output), exposing `cwk_is_guarded <repo-relative-path>`: exit 0 when the path is guarded, 1 otherwise, nothing printed. `hook-lib.sh` sources it; so does `.claude/scripts/fast-paths.sh` (`docs/specs/fast-lane.md` F2), which must stay read-only. Glob semantics: `**` crosses `/`, `*` does not.
    - **Running is not writing.** An interpreter or a script naming a guarded path is a write marker only when the guarded path is the write's target (Open findings, "Marker operand"). Running a kit script with its arguments passes: `python3 .claude/hooks/kit-attempts.py fail|pass …` runs on every gate of every loop, and asking on it would put a prompt on each.
    - `protect-files.sh` gains an `ask` (same shape as `enforce-git-workflow.sh`'s) and asks on Write/Edit of the guarded set. Existing denies unchanged.
    - `prevent-destructive-commands.sh` asks, **unconditionally**, on any shell segment that names a guarded path and carries a write marker: `>`, `>>`, `>|`, `tee`, `cp`, `mv`, `rm`, `rmdir`, `touch`, `ln`, `install`, `rsync`, `truncate`, `patch`, `sed`/`perl` with `-i`/`--in-place` (short flags bundled or separate), `--output`, `-exec`, an interpreter (`python`, `node`, `perl`, `ruby`, `bash -c`). Reading a guarded path (`cat`, `grep`, `sed -n` without `-i`) passes. A moved or deleted hook exits 127, which a PreToolUse hook reads as allow (`hook-lib.sh:52-53`): this rule is what keeps a hook from being removed silently.
    - `enforce-git-workflow.sh`, flags matched anywhere in the command, bundled (`-am`, `-Af`) and abbreviated (git accepts any unique prefix: `--am`, `--forc`, `--no-v`):
      - `git commit` with `--amend`, `--no-verify`/`-n`, `-a`/`--all`: ask.
      - `git switch`/`git checkout` with `--discard-changes`, `-f`/`--force`, `-C`: ask.
      - `git add` with `-f`/`--force`: deny. `git add` naming a path matching `.env*` (except `.env.example`, `.env.sample`, `.env.template`), `*.pem`, `*.key`, `credentials.*`: deny. `git add` with `.`, `-A`, `--all`, `-u`, a directory or a glob: the hook runs `git add --dry-run` with the same arguments (read-only) and denies if any listed path matches those patterns.
    - `.gitignore` and the install template gain `*.pem`, `*.key`, `credentials.*`: today only `.env*` is ignored, so `git add .` would stage the other three untracked.
    - The deny texts of `tdd-require-red.sh` and `tdd-freeze-tests.sh` keep naming `.tdd-unfrozen`, and add: "this write will ask the user".
  - **P3. Docs.** `docs/ADAPTATION.md`: `install.sh` merges `allow` as a union and keeps the user's `defaultMode` (`install.sh:247`), so a reinstall switches to `acceptEdits` only where no mode was set; writing the guarded set (kit hooks and scripts, RED markers, vitest/eslint configs) now prompts on every write, by design. `docs/Claude_Workflows.md`: the permission prompts that remain on a light pass.
- OUT :
  - No change to the loop's human gates (`docs/specs/light-fewer-gates.md`).

## Open findings from the 2026-10-27 reviews — settled 2026-10-28, all nine IN
Decided with the user before `/loop:plan` (research: `docs/work/light-permissions/research.md`). They amend P2 as follows, and the cases H9-H15 below cover them:
- The guarded set gains `vite.config.*`, `package.json`, `tsconfig*.json` and `.github/workflows/**` (from harness-hardening H1).
- `.claude/.tdd-red/**` is **denied**, not asked, by Write/Edit and by every shell write marker (aligned with harness-hardening H1: its only writer is `tdd-prove-red.sh`, a hook process PreToolUse never sees).
- A recursive `rm`/`mv` under a protected dir **asks** (not deny, unlike harness-hardening H3; `CLAUDE.md`: "without explicit user confirmation").
- Every item below is integrated as written.
- **Coverage floor unguarded.** The thresholds live in `vite.config.ts` (`.claude/skills/templates/tooling-config.md:9-49`), not `vitest.config.*`: add `vite.config.*` to the guarded set, H3 case.
- **Gate scripts unguarded.** `package.json` `scripts` (`"lint": "… || true"`, `--passWithNoTests`) and `tsconfig*.json` disable ship gates without a prompt: guard them, or ask when `scripts` changes.
- **Path resolution.** Match the resolved target, not text: Write/Edit send absolute paths (H3 needs absolute and worktree cases); shell operands resolve against the hook's `cwd` plus any earlier `cd` (`cd .claude/hooks && sed -i …`); unknown targets (`$VAR`, `$(`, a glob next to a guarded dir) ask.
- **Marker operand.** The guarded path must be the write's *target* (redirect target, `cp`/`install`/`ln` destination, any `mv`/`rm` operand, an interpreter with `-c`/`-e`), as `SRC_WRITE_RE` does (`prevent-destructive-commands.sh:338`). Otherwise `check-script … 2>&1` and `python3 .claude/hooks/kit-doctor.py` ask; add pass cases.
- **`git add` dry-run.** Always run it, not only on `.`/`-A`/dir/glob; deny `$(`, backticks, `$VAR`, `--pathspec-from-file`; never `eval`. Deny on timeout or nonzero exit (the 5 s hook timeout otherwise fails open).
- **Recursive `rm` under `src/`.** `prevent-destructive-commands.sh:94-101` lets `rm -rf src/features/x` through, and `acceptEdits` may approve it: ask on any recursive `rm`/`mv` under a protected dir.
- **Git flags.** Add `--force-create` (and prefixes) next to `-C`. Add sed's `w` command, `rg --pre`, `find -fprint` to the markers.
- **`.gitignore` on reinstall.** `install.sh:431-439` appends only 4 named lines to an existing block; the new patterns must reach existing installs. The ignore block is a heredoc in `install.sh:441`, not a template file.
- **Kit development.** In this repo every hook edit will prompt: say so in P3, or add a kit-dev toggle that is itself in the guarded set.
- **Measure.** `kit-measure.py` has no dead-time measure: name the transcript-timestamp method (`docs/measuring-the-loop.md:28-30`) for the before/after.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Files: `.claude/settings.json`, `.claude/agents/github.md`, `.gitignore`, `install.sh`, `.claude/hooks/{hook-lib.sh,protect-files.sh,prevent-destructive-commands.sh,enforce-git-workflow.sh,tdd-require-red.sh,tdd-freeze-tests.sh}` and their fixtures, `docs/ADAPTATION.md`. `.claude/hooks/hook-guarded.sh` (new).

## Acceptance criteria
- [ ] On a real light pass: no prompt for edits, `git add <paths>`, `git commit -m "<one line>"`, gates; `git push`, `gh pr *`, `git commit -m x --amend`, `git switch -c x --discard-changes` still prompt.
- [ ] Writing any guarded path prompts, by Write/Edit and by every shell write marker of P2, from the main tree and from a worktree; writing `.claude/.tdd-red/**` is denied.
- [ ] `git add -f .env`, `git add --forc .env.local`, and `git add .` with an untracked `certs/a.pem` are denied; `git add .env.example` and `git add src/x.ts` pass.
- [ ] `test-hooks.sh`, `kit-doctor`, `test-install.sh` pass.

## Business logic to cover
No TypeScript. Hook fixtures (`test-hooks.sh`):
- H1 `git commit -m x --amend`, `git commit --am -m x`, `git commit -am x`, `git commit -m x --no-verify`: ask each.
- H2 `git switch -c x --discard-changes`, `git checkout -f main`, `git switch -C x`: ask each.
- H3 Write on `.claude/hooks/a.sh`, `.claude/hooks/fixtures/x.json`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.tdd-unfrozen`, `.claude/.size-exempt`, `vitest.config.ts`, `eslint.config.js`, `vite.config.ts`, `package.json`, `tsconfig.json`, `tsconfig.app.json`, `.github/workflows/ci.yml`: ask each. Write on `.claude/.tdd-red/m`: deny. The same paths given absolute, and under `.claude/worktrees/x/`: same verdicts.
- H4 Write on `src/x.ts`: passes.
- H5 `mv .claude/hooks/tdd-freeze-tests.sh /tmp/`, `cp x .claude/.tdd-unfrozen`, `echo x >> .claude/.size-exempt`, `sed -n -i 's/a/b/' .claude/settings.json`, `git diff --output=.claude/.tdd-unfrozen`, `find .claude/hooks -name a -exec cp x {} \;`: ask each. `python3 -c "open('.claude/.tdd-red/m','w')"`, `touch .claude/.tdd-red/m`: deny each. `cat .claude/hooks/a.sh`, `grep x .claude/settings.json`: pass.
- H7 `python3 .claude/hooks/kit-attempts.py fail docs/work/x/plan.md test "r"`, `python3 .claude/hooks/kit-attempts.py pass docs/work/x/plan.md test`: pass. Write on `.claude/scripts/a.sh`: ask.
- H8 `source .claude/hooks/hook-guarded.sh; cwk_is_guarded .claude/scripts/a.sh` exits 0 and `cwk_is_guarded src/x.ts` exits 1, both printing nothing and leaving `.claude/.hook-timings.log` unchanged.
- H9 Path resolution: `cd .claude/hooks && sed -i 's/a/b/' a.sh`, `echo x > $T` (unknown target), `cp x .claude/hooks/*`: ask each.
- H10 Marker operand: `python3 .claude/hooks/kit-doctor.py`, `.claude/hooks/test-hooks.sh 2>&1 | tail -1`, `bash .claude/hooks/test-small-lane.sh`: pass.
- H11 `git add` dry-run: `git add $(cat list)`, ``git add `x` ``, `git add $F`, `git add --pathspec-from-file=l`: deny each; `git add src/x.ts` runs the dry-run and passes.
- H12 `rm -rf src/features/x`, `mv src/features/x /tmp/`: ask each.
- H13 `git switch --force-create x`, `git switch --force-c x`: ask each; `sed 'w .claude/.size-exempt' f`, `rg --pre ./x pat`, `find . -fprint .claude/.size-exempt`: ask each.
- H14 `test-install.sh`: `.gitignore` of a fresh and of an upgraded install holds `*.pem`, `*.key`, `credentials.*`.
- H15 `docs/ADAPTATION.md` names the kit-development prompts (every hook/script/settings edit asks in this repo).
- H6 `git add -f x`, `git add --forc x`, `git add -Af`, `git add .env.local`, `git add certs/a.pem`: deny each; `git add .` with an untracked `certs/a.pem` in the fixture repo: deny; `git add src/x.ts`, `git add .env.example`: pass.
