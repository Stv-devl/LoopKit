# Research: Fewer permission prompts, same guardrails   (entry: docs/specs/harness-prompts.md)
Token profile: critical

Base: `audit/slim` at `d38cd87` (harness-hooks shipped locally), Claude Code `2.1.317` on this machine (`claude --version`). Three explorers: kit wiring, hook verdicts on every B2 form, Claude Code matching facts + measure baseline. Hook measurements: JSON piped to `prevent-destructive-commands.sh` (PD) and `enforce-git-workflow.sh` (GIT) in a scratch project, `CWK_HEALTH_LOG=0 CWK_HOOK_TIMING=0`; runner and case files in the session scratchpad (`hp-run.sh`, `A.txt`…`H.txt`, `*.out`).

## Pattern to follow
- **Allow arrays held back on a stale guard api:** `install.sh:209-212` `P1_ALLOWS` (five git allows) and `P1_GATE_ALLOWS` (five `pnpm <gate> *`); hold-back at `install.sh:275-284` (`held="$(guard_api_missing "$TARGET")"`, kit side `.permissions.allow - $p1 - $gates` at :277-278, message :284), merge at :295-310 (`-=` of `$p1 + $gates` at :307-310 when held). `PROMPT_ALLOWS` plugs in at the same four places (define after :212; :277-278; jq args :295; `-=` :308).
- **Contract shape:** `test-workflow-contracts.sh` K1 (:457-472, `jq index` per allow + wide forms absent :465-467) and K1b (:493-497, array read from `install.sh` with `sed -n "/^P1_ALLOWS='/,/]'\$/p"` then compared). `HP-B1`/`HP-B2` follow K1/K1b. No `HP-` label exists yet.
- **Install cases:** `test-install.sh` helpers `p1_add_allow` :331, `p1_none` :321, `p1_all` :326, `p1_rerun` :138-140; held-back simulation deletes a target hook's `# cwk-guard-api:` line (`sed -i '/^# cwk-guard-api:/d'`), e.g. cases (a) :142-165, I3a :336-345 ("previous install's allows removed, others kept").
- **Hook rows for new allowed forms:** `fixtures/_harness/shell-guard.jsonl` X24.* (A4 flag matrix) and `git-guard.jsonl` G16.* (A2 fetch); next free ids follow X24.245, X28.57, G17.25.

## Wiring points
- `.claude/settings.json`: `defaultMode: acceptEdits` :3; `deny` :4-17 (12 entries); `allow` :18-50 (grep/rg/cat/ls/find/wc/head/tail/`sed -n`, git status/log/diff/show/rev-parse, P1 git five, `pnpm <gate>` bare + ` *` for test:run, typecheck, lint, build, test:coverage, audit). **None of B2's allows present; none of the "never listed" forms present** (`git switch -c *` :35 and `git branch --show-current` :36 are narrower than the forbidden forms; K1 :465-467 already rejects `git switch *`, `git branch *`).
- `install.sh`: `GUARD_FILES` :206-208 (8 files); api numbers today: hook-lib, hook-guarded, shell_targets.py, protect-files, prevent-destructive, enforce-git-workflow = 2; tdd-require-red, auto-approve-config = 1. `copy_file` :81-91 never overwrites (writes `.new`). `install_settings` :253-320; allow merge `((old + new) | unique)` :303 **sorts** the list. `add_py_hooks` :337-370 appends :364-368 (`python -m pytest`, `uv run pytest`, `mypy *`, `pyright *`, `ruff check .|app|app/`, `uv audit *`), `unique`, errors silenced :369; called only from `wire_fastapi` :382. `Claude_Workflows.md` shipped at `install.sh:629` (spec says :616).
- `kit-attempts.py` (118 lines): `attempts.json` = `args.artifact.parent / "attempts.json"` :92, created by `write_atomic` `mkdir parents=True` :24-28; board rewritten by `block_board` :63-79 (unit cell must match exactly one row). **No path validation** on artifact or board today. `test-attempts.sh` (29 lines, flat): absolute `ARTIFACT="$SCRATCH/docs/work/example/plan.md"` :8, `BOARD="$SCRATCH/docs/product/backlog.md"` :10.
- `CLAUDE.md`: 138/140 lines (budget header line 1); shell-write rule at :50-51 ("**Never write source from the shell** (redirection, `tee`, `sed -i`): it goes / around every `Write|Edit` guardrail. Delete specific files, never whole folders."). `test-rules-floor.sh` :5-7: `wc -l CLAUDE.md .claude/rules/*.md` ≤ 520, today **514**. Per-file budgets in `kit-doctor.py` `check_rules_budget` :1139-1182.
- Agent files: `implementer.md` (56 lines) Non-negotiable block :35-47, no shell-write line (closest :44-46); `test-writer.md` (182 lines) `## Non-negotiable` :125, closest :127-129. Precedent wording: `.claude/rules/05-testing.md:32-34`.
- `docs/Claude_Workflows.md`: `## Hors boucle` at **:452** (spec says :437), table :454-463; no suite-run instruction anywhere (`for` loops, `bash -x`, `2>&1`): nothing found in docs, commands, guides, skills, agents.
- `.claude/scripts/`: `small-dispatch-check.sh`, `small-lib.sh`, `small-paths.sh`, `small-plan.sh`, `small-scope.sh` (spec's four exist; `small-lib.sh` is sourced, not listed).
- Prescribed invocations: `orchestrate.md:55,88` `python3 .claude/hooks/kit-attempts.py fail …` (line :55 continues with ` \` onto `--board`); `kit/doctor.md:35-36` `python3 .claude/hooks/kit-doctor.py [/path]`.

## Reusable
- `P1_*` hold-back machinery, `guard_api_missing` :225-239, `test-install.sh` P1 helpers, K1/K1b contract pattern: reuse, do not rewrite.
- `kit-doctor.py` has **no** check of `P1_ALLOWS`/`GUARD_FILES`/install arrays (grep `P1` → none); `check_gate_allowlist` :354-408 checks only the `/loop:ship` gate lines. A `PROMPT_ALLOWS` doctor twin would be new; the spec places the twin in `HP-B2` only.
- `kit-measure.py` measures tokens, not prompts (CLI `--root`, `--session`, `--since`, `--json`); no prompt-audit script exists anywhere. The measure script is new (plan-only, not shipped).

## Blast radius
- `settings.json` allow list → every target via `install_settings`; `jq unique` reorders it (cosmetic, but a contract comparing order must not assume order).
- `install.sh` hold-back now covers three arrays; `test-install.sh` cases (a), A0-A7 loops, I3a-d assert P1/gates only: they must keep passing with `PROMPT_ALLOWS` added.
- `kit-attempts.py` path checks: callers `orchestrate.md:55,81,88`, `plan.md:84`, `interface.md:90`, `test-attempts.sh`; all pass `docs/work/<slug>/plan.md`, relative or absolute.
- `CLAUDE.md` +0/+1 line and agent files +1 each; `CLAUDE.md` ships to targets (merged as `.new`).
- `Claude_Workflows.md` ships to targets (`install.sh:629`).

## Live DB state
n/a (no database surface).

## External surface (Claude Code 2.1.317)
- Allow rules match the whole command text, `*` = any text; a trailing ` *` also matches the bare command; `Bash(ls *)` does not match `lsof` [cache 2026-11-02, `claude-code-permissions.md:17,21`]. `Bash(x)` with no `*` matching only the exact text is an inference, not stated.
- Compound commands: separators `&&`, `||`, `;`, `|`, `|&`, `&`, newline; every subcommand must be allowed or read-only; deny/ask fire on any subcommand incl. `$(…)`, subshells, `for` bodies [cache, :17-18]. A backslash-newline continuation is one subcommand approved by `Bash(git add *)` [cache, measured 2.1.312, :96-97].
- Stripped before matching: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`, bare `xargs`, safe env assignments; **not** stripped: `npx`, `docker exec`, `devbox run` [cache, :20]. `pnpm exec`, `uv run`, `env`, `2>&1`: not in cache.
- A PreToolUse hook `ask` overrides an allow rule and acceptEdits; hook `deny` blocks; precedence deny > defer > ask > allow [cache, measured 2026-10-28, :27-31, :84-92]. **The spec's citation `:48-55` is wrong** (that is the Read-deny section).
- Timed-out or non-zero (≠2) PreToolUse hook does not block unless `"onFailure": "block"` [cache, :34-35].
- acceptEdits prompts on writes to protected paths `.git`, `.claude` (except `.claude/worktrees/`) [cache, documented not measured, :14] — DB2 stays open.
- Ask reason reaching the model (DB1): **not in cache**. Repo evidence shows the reason in `permission_denials` (`docs/work/light-permissions-git/prior-gate.md:40`, `plan.md:137`), which proves the transcript holds it, not that the model receives it as `tool_result`.
- `x 2>&1` vs `Bash(x)` (DB3), and a command ending in a dangling ` \` (no newline) vs an allow rule: **not in cache**.
- Headless flags available in 2.1.317 (`claude --help`): `-p`, `--output-format json|stream-json`, `--verbose`, `--include-hook-events`, `--permission-mode`, `--max-turns`, `--tools`, `--model`, `--settings`, `--allowedTools`, `--permission-prompts none|host`, `--no-session-persistence`. `--bare` skips hooks: never use it. With `-p` in an untrusted workspace, project `permissions.allow` is ignored: pass the fixture with `--settings` (`prior-gate.md:15`).
- Cache measurements are on 2.1.310-2.1.316; this machine runs 2.1.317 (one minor ahead).

## Hook verdicts on B2's forms (measured, HEAD d38cd87)
- **Safe forms get no hook ask** (the allows do save prompts): `pnpm [exec] vitest run src/a.test.ts`, `pnpm exec tsc --noEmit`, `pnpm exec playwright test [e2e/x.spec.ts]`, `git fetch [origin [main]]`, `git stash list`, `bash .claude/hooks/test-*.sh [2>&1]`, `kit-attempts.py fail|pass|show docs/work/x/plan.md …`, `kit-doctor.py`.
- **Plain dangerous flags are caught** (A4/A2 hold): `--coverage.reportsDirectory=src` deny; `--outputFile=<test file>` deny; `--root|--dir docs`, `-c|--config docs/…` ask; `tsc --noEmit false` ask, `--tsBuildInfoFile <test file>` deny, `-p docs/x.json` ask; `playwright --output src` deny, `--output e2e` ask, `-c|--config` ask; `git fetch origin main:main`, `. feat:main`, `--refmap=…`, `--upload-pack=x`, `--upl=x`, `-u` ask. `2>&1` never changes a verdict.
- **Accepted over-match (as the spec says):** `git fetch origin feat/add-x`, `kit-attempts.py fail docs/work/git-x/plan.md review "add a test"` → GIT ask.

## Traps (points of vigilance for the review)
- **Trailing ` \` (or `; true \`) drops the hook verdict on every flag row B2 relies on** (`shell_targets.py` exits 1, PD's fallback asks only on `--output`/`>`): `pnpm [exec] vitest run --coverage.reportsDirectory=src \` pass; `--root|--dir docs \`, `-c|--config docs/v.ts \` pass; `pnpm exec tsc --noEmit --tsBuildInfoFile src/a/a.utils.test.ts \` pass; `-p docs/x.json \`, `--noEmit false \` pass; `playwright -c|--config … \` pass; GIT: `git fetch origin main:main \`, `git fetch --upload-pack=x . \`, `--refmap=… \` pass. The same already holds today for `pnpm test:run *`, `pnpm build *` (allowed). Whether Claude Code's allow rule matches a command ending in a dangling ` \` is unmeasured: if it does, each B2 allow becomes a silent path to these writes. Recorded follow-up (`harness-hardening.md`), not fixed.
- **Snapshot updates pass every hook:** `pnpm [exec] vitest run -u|--update`, `pnpm exec playwright test --update-snapshots|-u` → pass, plain and with ` \`. `05-testing.md:32-34` forbids snapshot updates that bypass Write/Edit; no hook decides it. Same today under `pnpm test:run *`.
- **Recorded runner gaps ride on `pnpm exec`:** `pnpm exec timeout --signal KILL 5 rm -rf .git`, `pnpm vitest run $(( $(rm -rf .git) ))`, `pnpm -c exec '…'`, `pnpm --shell-mode exec '…'` → no hook verdict. B2 allows only `pnpm exec vitest run *`, `pnpm exec tsc --noEmit[ *]`, `pnpm exec playwright test *`, so these match no allow unless an allowed prefix carries them (`pnpm exec vitest run $(( $(rm -rf .git) ))` would match `Bash(pnpm exec vitest run *)` if Claude Code does not split `$((…))`: unmeasured).
- **`kit-attempts.py` path refusal does not exist yet:** `fail .claude/hooks/x.md …` and `--board src/a.md` pass every hook today; once allowed they run silently until B2's refusal lands. Order: the refusal must land before (or with) the allow.
- **`kit-doctor.py <any arg>` is taken as ROOT** (`sys.argv[1]`, no `--fix`): `Bash(python3 .claude/hooks/kit-doctor.py *)` lets any path through; check it only reads.
- **Scripts and suites take free arguments:** `.claude/scripts/small-*.sh ../x`, `bash .claude/hooks/test-hooks.sh ../../x` pass every hook; what each script does with an unexpected argument is unmeasured.
- **`kit-attempts.py` in `orchestrate.md:55` is written as a two-line ` \` continuation**: the allow must match it, or the documented form keeps prompting (cache :96-97 says a continuation is one subcommand).
- **Budgets:** `CLAUDE.md` 138/140, floor 514/520: B1 must be net +0/+1.
- **Spec line references to correct:** `Claude_Workflows.md:437` → :452; `install.sh:616` → :629; `claude-code-permissions.md:48-55` → :27-31 and :84-92.
- **fastapi:** no `uv run` exists in `addons/fastapi`; the five `uv run ruff|mypy|pyright` allows are new forms, not a rewrite.
- `jq unique` at `install.sh:303` sorts allows: contracts compare sets, not order.

## Open questions
1. **DB1**: does a PreToolUse `ask` reason reach the model as `tool_result` text? Settle with one headless run: scratch repo outside LoopKit, fixture `--settings` holding a PreToolUse Bash hook that returns `ask` with a nonce in `permissionDecisionReason`, `claude -p --output-format stream-json --verbose --include-hook-events --permission-mode acceptEdits --max-turns 2 --tools Bash --model sonnet --settings <fixture>`; check the `tool_result` matching the Bash `tool_use_id`. Absent marker → reason left unchanged (spec). Who runs it, and when (before the plan gate)?
2. **DB3** (and its sibling): is `bash .claude/hooks/test-hooks.sh 2>&1` matched by `Bash(bash .claude/hooks/test-hooks.sh)` or only by the ` *` form? And is a command ending in a dangling ` \` matched by `Bash(pnpm vitest run *)`? Settle with headless runs, one allow per `--settings` fixture, a dummy `test-probe.sh`, checking `tool_use.input.command` equals the pinned form.
3. **Trailing-`\` exposure**: given the trap above, does B2 ship (a) as written, relying on the same exposure already accepted for `pnpm test:run *`/`pnpm build *`, (b) only after the recorded follow-up (`shell_targets.py` fails closed / strips a dangling `\`) lands, or (c) with the flag-bearing allows (`pnpm [exec] vitest run *`, `tsc --noEmit *`, `playwright test *`, `git fetch *`) narrowed?
4. **Snapshot updates**: should B2's `vitest`/`playwright` allows exclude `-u`/`--update`/`--update-snapshots` (a hook ask), or stay equal to today's `pnpm test:run *`, which already lets `-u` through?
5. **DB2**: run it now (informational) or leave it open?
6. **Measure baseline**: the five most recent ecocrew sessions are `b17a959f` (919 Bash lines), `0fb1fc01` (510), `b2e2316e` (481), `a7aad292` (5), `8b73ec29` (empty), newest 2026-10-26. Drop the empty and the 5-call session and take the next two older ones? Counts are approximate (`grep -c '"name":"Bash"'` per line).
7. `small-lib.sh` is not in B2's list (sourced, never invoked): confirm it stays out.
