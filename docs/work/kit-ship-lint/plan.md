# Plan: kit ship runs the CI lint locally   (entry: docs/specs/kit-ship-lint.md · research: docs/work/kit-ship-lint/research.md · design: n/a)
Token profile: economy
Base: 7ebc764

## Skips
- DB, backend, front, wiring: SKIP. This is kit tooling: one shell script, one overlay, install.sh, settings and suites.
- INTERFACE: SKIP, no screen.
- Test-first layers: none. Kit shell suites fall outside the freeze matcher (`05-testing.md`). Each new case is written first and observed red against the code as it stands, then the code is written. Cases are never rewritten.

## Write chain (sequential)
1. `.claude/hooks/test-kit-lint.sh`: the KL cases (below). Uses a stub `uvx` on `PATH` and a scratch kit-source tree. Run it and observe it red: `kit-lint.sh` is absent.
2. `.claude/scripts/kit-lint.sh`: the gate. It refuses outside kit source. It runs 4 steps, shellcheck, ruff, actionlint, and actionlint on the assembled targets (one per `templates/github/publish/*.yml`). It runs every step even after a failure, then prints one line per step: `ok`, `FAIL` (with the tool output) or `MISSING` (with the reason). It exits non-zero unless every step is `ok`. Pinned runners: `uvx --from shellcheck-py==0.11.0.1 shellcheck`, `uvx ruff@0.17.4`, `uvx --from actionlint-py==1.7.12.24 actionlint`. Temp dirs are removed by a trap. Write until test-kit-lint is green.
3. `.claude/hooks/test-workflow-contracts.sh`: pins K4a-K4f (below), written now and observed red (the overlay, the allows, the RETIRED_ALLOWS entries, the prune and the CI step are all absent).
4. `.claude/overlays/commands/loop/ship.md` (kit repo only, versioned): the template's slots, with `## extra-gates` = `.claude/scripts/kit-lint.sh` and one line on why. The other slots keep their FILL notes. In the same step, `.claude/settings.json` gains the 4 allow forms listed in step 5, so IN72 sees them leak before step 5 retires them.
5. `.claude/hooks/test-install.sh`: IN70-IN72, observed red with step 4's overlay in place (on a fresh install, copy_tree writes the kit overlay as the target's `ship.md` and seed_overlays then only adds the template as `.new`). Then `install.sh`:
   - `copy_tree` gets `-path "$src/overlays" -prune`, scoped to the kit's top-level `.claude/overlays`;
   - the 4 forms `Bash(.claude/scripts/kit-lint.sh)`, `Bash(.claude/scripts/kit-lint.sh *)`, `Bash(bash .claude/hooks/test-kit-lint.sh)` and `Bash(bash .claude/hooks/test-kit-lint.sh *)` join `RETIRED_ALLOWS`, the kit-development class that C2 pins (`test-workflow-contracts.sh:778`).
6. `.github/workflows/kit-ci.yml`: a `Test kit lint gate` step running `.claude/hooks/test-kit-lint.sh`, with CI's lint steps unchanged. `kit-doctor.py` `NON_HOOKS` gains `test-kit-lint.sh` (once the allow is retired in targets, it would otherwise read "registered nowhere" there).
7. Run test-workflow-contracts, test-install and test-kit-doctor until green. Then run the new gate on the real repo (`.claude/scripts/kit-lint.sh`) and every kit suite: green.

## Parallel lots (inside this track, same tree)
none: fully sequential (small surface, the pins read every file).

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: `install.sh` (copy_tree), `.claude/settings.json`, `.github/workflows/kit-ci.yml`. No other kit pass runs beside this one until it merges.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `.claude/scripts/kit-lint.sh` | Create | kit-repo lint gate, the twin of kit-ci.yml's lint |
| `.claude/hooks/test-kit-lint.sh` | Create | KL fixture suite (stub uvx) |
| `.claude/overlays/commands/loop/ship.md` | Create | kit-repo `extra-gates` → the gate |
| `install.sh` | Edit | prune the kit's `.claude/overlays` in copy_tree; RETIRED_ALLOWS gains the 4 kit-lint forms |
| `.claude/hooks/test-install.sh` | Edit | IN70-IN72 |
| `.claude/hooks/kit-doctor.py` | Edit | NON_HOOKS gains test-kit-lint.sh |
| `.claude/settings.json` | Edit | allow the gate and its suite |
| `.github/workflows/kit-ci.yml` | Edit | run test-kit-lint.sh |
| `.claude/hooks/test-workflow-contracts.sh` | Edit | K4 parity and wiring pins; K2a suite list gains test-kit-lint |

## Contracts
- `kit-lint.sh` takes no arguments, and its root is the repo of the script (`KIT_LINT_ROOT` overrides it, for fixtures only).
- Exit codes: 0 when every step is ok. 1 when any step is FAIL or MISSING. 2 when refused (not kit source: root `install.sh` + `addons/` present and `.claude/INSTALL_PROFILE` absent, the same rule as kit-doctor `is_kit_source`).
- Output: one line per step, `kit-lint: <step> ok|FAIL|MISSING[: <reason>]`. Step names: `shellcheck`, `ruff`, `actionlint`, `actionlint-targets:<name>`. The tool's own output (file:line and rule) is printed in full above its FAIL line.
- MISSING vs FAIL: before each tool runs, a probe `uvx <runner spec> --version` is made. If `uvx` is absent or the probe exits non-zero, the step is `MISSING: <reason>` and the tool does not run. If the probe passes and the lint run then exits non-zero, the step is `FAIL`.
- The exact tool arguments are kit-ci.yml's: `-S warning .claude/hooks/*.sh .claude/scripts/*.sh`, `check --select E4,E7,E9,F .claude/hooks .claude/scripts`, `.github/workflows/*.yml`, and for the targets `./install.sh "$d" --deploy="$t" </dev/null` then `"$d"/.github/workflows/*.yml`.

## Test plan (gate — validated before EXECUTE)

### Test-after — kit shell fixture suites (outside the freeze matcher; written first, observed red, never rewritten)

#### .claude/hooks/test-kit-lint.sh (new suite, ids KL)
A stub `uvx` on `PATH` logs its argv. For each tool, the case sets the exit code and output, separately for the `--version` probe and for the lint run. The tree is a scratch kit-source tree with:
- `install.sh`, a stub that writes `.github/workflows/<deploy value>.yml` into its target, so the uvx stub can tell `one` from `two` by path;
- `addons/`, `.claude/hooks/a.sh`, `.github/workflows/w.yml`, and `templates/github/publish/{one,two}.yml`.

**Reproduction**
- [ ] KL1 a shellcheck finding (stub shellcheck prints `.claude/hooks/a.sh:3:1: warning SC1010` and exits 1): the gate exits 1, its output holds that whole line (file and rule), and it prints `kit-lint: shellcheck FAIL`.

**Core behaviour**
- [ ] KL2 every tool clean: exit 0, and the lines `kit-lint: shellcheck ok`, `kit-lint: ruff ok`, `kit-lint: actionlint ok`, `kit-lint: actionlint-targets:one ok`, `kit-lint: actionlint-targets:two ok`.
- [ ] KL3 a ruff finding (stub prints `.claude/hooks/x.py:4:5: F841`): exit 1, that line in the output, and `kit-lint: ruff FAIL`, while `kit-lint: shellcheck ok` and `kit-lint: actionlint ok` are still printed (every step runs).
- [ ] KL4 an actionlint finding on `.github/workflows`: exit 1 and `kit-lint: actionlint FAIL`.
- [ ] KL5 the runners receive kit-ci.yml's arguments. The stub log holds `--from shellcheck-py==0.11.0.1 shellcheck -S warning .claude/hooks/a.sh`, `ruff@0.17.4 check --select E4,E7,E9,F .claude/hooks .claude/scripts`, and `--from actionlint-py==1.7.12.24 actionlint .github/workflows/w.yml`. (The argv is the contract here: no other trace exists.)

**Business rules**
- [ ] KL6 no `uvx` on `PATH`: exit 1, each of shellcheck, ruff and actionlint reported `MISSING: uvx not found`, and no line says `ok`.
- [ ] KL7 the ruff runner cannot be fetched (its `--version` probe exits 2 with `failed to fetch`): `kit-lint: ruff MISSING` with that reason, the ruff lint run is never called (absent from the stub log), the other steps still run, and the exit is 1.
- [ ] KL8 an actionlint finding only for a path under a `two.yml` target workflow: exit 1, `kit-lint: actionlint-targets:two FAIL`, `kit-lint: actionlint-targets:one ok`.

**Edge cases**
- [ ] KL9 after a run, green or red, none of the gate's temp install dirs remain (the gate's own `TMPDIR` is empty).
- [ ] KL10 run against a tree with `.claude/INSTALL_PROFILE` (an installed project): exit 2 with `kit source only`, and uvx is never called.

#### .claude/hooks/test-install.sh (new ids IN70-IN72, after the highest existing IN)
**Reproduction**
- [ ] IN70 a fresh install from the kit, which holds `.claude/overlays/commands/loop/ship.md`: the target's `.claude/overlays/commands/loop/ship.md` is byte-identical to `templates/overlays/commands/loop/ship.md`, and no file under the target's `.claude/overlays/` (`*.new` included) contains `kit-lint.sh`.

**Business rules**
- [ ] IN71 a re-install over a project whose overlay ship.md equals the seeded template: no file under `.claude/overlays/` (`*.new` included) contains `kit-lint.sh`, and the project's ship.md is byte-identical afterwards. IN48 (an edited overlay is kept) stays green.
- [ ] IN72 a fresh install: the target's `.claude/settings.json` has no allow entry containing `kit-lint`.

#### Open questions (from research, proposed answers)
1. Placement → a kit-repo overlay `.claude/overlays/commands/loop/ship.md` `## extra-gates`, plus pruning `overlays` in copy_tree (IN70, IN71, K4c, K4e). ship.md is unchanged.
2. Runner shape → one script, `.claude/scripts/kit-lint.sh`, with explicit allow entries in the kit (KL*, K4d).
3. Parity → pins in test-workflow-contracts.sh (K4a, K4b), next to K2a. No kit-doctor check.
4. Do the kit's allow entries reach targets? → no. They join `RETIRED_ALLOWS` like the other kit-development suites, and C2 covers them (IN72, K4f). The script file itself still ships, like every `.claude/scripts/*`, and is inert there: it refuses outside kit source (KL10).
5. Does CI call kit-lint.sh? → no. CI keeps its own lint steps (spec OUT). It only gains the hermetic `test-kit-lint.sh` step.
6. (critic F2) What is "the gate batch" in the kit repo, which has no `package.json`? → the ship.md fence's pnpm lines do not apply there (no package.json, nothing to run); the kit repo's gates are its `extra-gates`, which hold kit-lint.sh. The kit suites stay as each pass's plan lists them, which is unchanged. AC5 = kit-lint.sh green on main plus every kit suite green (write-chain step 7).

#### .claude/hooks/test-workflow-contracts.sh (pins, K4 family)
- [ ] K4a kit-ci.yml's shellcheck version (`shellcheck-v0.11.0`) and kit-lint.sh's `shellcheck-py==0.11.0.` agree on 0.11.0. Same for ruff (`version: 0.17.4` ↔ `ruff@0.17.4`) and actionlint (`v1.7.12` ↔ `actionlint-py==1.7.12.`). The case extracts each version from both files and compares them, so a bump on one side alone goes red.
- [ ] K4b the argument strings `-S warning .claude/hooks/*.sh .claude/scripts/*.sh`, `check --select E4,E7,E9,F` and `.claude/hooks .claude/scripts` (ruff's src) appear in both files.
- [ ] K4c `.claude/overlays/commands/loop/ship.md`'s `## extra-gates` section holds `.claude/scripts/kit-lint.sh`.
- [ ] K4d `.claude/settings.json` allows `Bash(.claude/scripts/kit-lint.sh)`.
- [ ] K4e install.sh's copy_tree prunes `"$src/overlays"`. The K2a suite list gains `test-kit-lint`.
- [ ] K4f C2's kit-development loop covers `kit-lint` (the `.claude/scripts/kit-lint.sh` forms) and `test-kit-lint`: each form is in the kit's settings allow list and in `RETIRED_ALLOWS`.

## Vigilance (carried from research)
- No kit-only gate wiring may reach an installed project: the overlay is pruned, there are no lint lines in a target's ship gates, and the allows are retired (open question 4).
- The prune is scoped to `$src/overlays`; `templates/overlays` seeding (seed_overlays) is untouched, and IN48 stays green.
- MISSING comes only from the probe, FAIL only from a lint run after a passing probe.
- test-kit-lint.sh is in kit-doctor NON_HOOKS; kit-doctor stays clean in kit source and in a fresh install.
- Flags, paths and versions must equal kit-ci.yml's. A drift must fail K4a/K4b, not be found by CI.
- A runner that cannot run is `MISSING`, red: never a skip, never `ok`, never a note.
- No `|| true` and no `set -e` early exit that hides later steps. Every step runs, and the exit code is the aggregate.
- kit-lint.sh and test-kit-lint.sh pass shellcheck themselves (kit-lint runs on its own file).
- Assembled targets: `install.sh` stdin is closed (`</dev/null`), and temp dirs are removed even on failure.

## Acceptance criteria (carried from the entry artifact)
- [ ] Shipping a pass in the kit repo with a shellcheck warning, a ruff E4/E7/E9/F
      finding, or an actionlint error in a workflow stops at the gate batch,
      before the commit, naming the file and rule.
- [ ] The three commands match kit-ci.yml's flags, paths and ruff version; a drift
      between the two is reported by a kit check, not found by CI.
- [ ] A lint tool that cannot be run makes the gate red with the reason "missing",
      it is not skipped and not downgraded to a note.
- [ ] `install.sh` into a fresh project and into an existing one ships none of the
      kit-repo-only gate wiring (no kit overlay, no lint lines in the target's
      ship gates).
- [ ] The kit's own suites stay green and the gate batch passes on current main.

## Gate
- 2026-11-27 go
- Contract: as written
- Q1 placement → kit overlay extra-gates + copy_tree prune
- Q2 runner → .claude/scripts/kit-lint.sh, pinned uvx runners
- Q3 parity → test-workflow-contracts K4a/K4b
- Q4 allows → kit only, RETIRED_ALLOWS + C2 (IN72, K4f)
- Q5 CI → lint steps unchanged, gains test-kit-lint.sh step
- Q6 kit-repo gate batch → kit-lint.sh + every kit suite

## Plan critic
- pass 1: completeness 82, quality 68 (F3, F4 Major, verified on the main thread → rewrite)
- pass 2: completeness 92, quality 88 (F3, F4 closures met; F9 vigilance, fixed in step 4)
- surviving blockers: none
