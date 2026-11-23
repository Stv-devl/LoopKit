# Research: auto-mode trial fixes   (entry: docs/specs/auto-mode-trial-fixes.md)
Token profile: critical

Three `explorer` probes (2026-11-23): fixes 1+2, fix 3+6, fixes 4+5. No external surface.

## Pattern to follow
- Fix 1: rows mode in `freeze_rows()` (`.claude/hooks/tdd-freeze-tests.sh:152-367`): an Edit-by-Edit allowlist where every touched case is a row, or in auto mode a case with a ledgered `unfreeze` verdict (`:185-196`). Case spans come from `cases()` (`:276`); `touched()` (`:326-331`) refuses any non-blank offset outside every case. That refusal is what blocks an added import.
- Fix 3: the gh path in `enforce-git-workflow.sh`: `gh_scan()` (`:1971-2019`) sets `GH_WRITE`; the asks are unanchored regexes over the whole command (`:2171` pr, `:2175` issue|release|repo|api, `:2179` comment).
- Fix 5: `kit-audit-surface.py:21-23` imports `project_config` (`sys.path.insert(0, HERE)`), the pattern for `kit-pr-assets.py`. The shell analogue is the ship bundle-secret fence `ship.md:44-58` (`jq '.app_roots[]? | . + "/src"'`, fallback `src`), pinned by PK21/PK23/PK24.
- Contract tests: `test-workflow-contracts.sh` helpers `pk/has/lacks/in_order` (`:1331-1336`).

## Wiring points
- Fix 1: verdict writer `loop-record.py:509-540` (`subagent_stop`, `ledger_entry` `:433`); reader `tdd-freeze-tests.sh:185-196`; arbiter rule `.claude/agents/arbiter.md:40-46` ("the hunk must touch only that case"); `.tdd-unfrozen` edit gate `protect-files.sh:240-245, :361`. Python twin: `addons/fastapi/hooks/tdd-freeze-tests-py.py` (not analysed).
- Fix 2: blocked-stop definition `orchestrate.md:74-80`, which itself prescribes `loop-record.py --clear`; the deny text `tdd-freeze-tests.sh:340` tells the agent to "end the rows pass with … --clear"; contract pin `test-workflow-contracts.sh:1459` (AMC2 requires `--clear` in the blocked-stop list). `--clear` is guarded only as an exact form (`prevent-destructive-commands.sh:966-970`) and allowlisted (`settings.json:51`).
- Fix 3: hook order `decide()` first-hit (`:111-125`): git deny, gh deny (`:2022-2035`), `record_allow` (`:2169`), gh asks (`:2171-2181`), push asks, segment ask loop. Auto conversion to `auto mode — blocked stop:` is NOT in this hook (`prevent-destructive-commands.sh:667-672`, `protect-files.sh`); its asks stay asks in auto.
- Fix 4: `.claude/agents/test-writer.md` (189 l., no overlay; shell bans `:135-136`), `.claude/agents/e2e-tester.md` (96 l.; run command `:62`, "never edit the Playwright config" `:34`). Skill `e2e-playwright/SKILL.md:21-28` owns the config and command forms.
- Fix 5: `kit-pr-assets.py:60-68` `is_ui_path` (`src/` literal `:64`), `ui` branch `:307-311`, refusal exit 2 `:327-333`; only caller `review.md:160` (`ui`/`none` → `PR_SHOTS` launch `:163-178`). `project_config.load()` (`:349-357`) returns `EMPTY` for absent project.json, raises status 3 on invalid. `/kit:init` detection is prose: `kit/init.md:46-56` (package.json + one root config, or pyproject.toml, ≤2 levels), writes at `:111-125`.
- Fix 6: `.gitignore:114-120` codex block; `install.sh` `ensure_gitignore()` `:633-690` (top-up loop `:639-641`, fresh heredoc `:651-681`), count text "20 chemins" `install.sh:940`; `test-install.sh:106,116` ignored-path loops (sed cleanups `:114,:118`).

## Reusable
- `cases()`/`touched()` spans (fix 1); `gh_skip_repo()` `:1962-1970` for `-R/--repo` (fix 3); `project_config.load` (fix 5); `lp_freeze_project`/`lp_freeze`/`am_freeze_rec`/`am_v` test helpers (`test-hooks.sh:4962, 4975, 6282, 6111`); git-guard JSONL fixtures `.claude/hooks/fixtures/_harness/git-guard.jsonl` (format `{"id","verdict","command","reason"?}`).

## Blast radius
- Fix 1: rows-mode cases LP51-LP71, auto cases AM37-AM47.4 must stay green; the arbiter prompt must widen in step with the hook or it refuses the hunk the hook would accept. Insertion path (`:439-680`) runs before rows mode for Edits: an import-only Edit is denied at `:593` ("no expect()"), then falls to `rows_verdict()`.
- Fix 2: AMC2 inverts; LP54-LP63 pin the `:340` deny text (`test-hooks.sh:5364-5375, 5652-5742`). Keep the finished-pass `--clear` sites: `orchestrate.md:137`, `ship.md:226`, `tracks.md:30`, PK31/PK45.3/PK45.6.
- Fix 3: G18 cases (G18.28 `gh pr view` pass, G18.29 `gh api` ask, G18.21/38 comment); next free G18.42.
- Fix 5: K1-K3 (`test-pr-assets.sh:133-150`, no project.json) must stay; next K27. A37 (`test-audit-surface.sh:253`) stubs `load_strict` with `app_roots` only; next A43.
- Fix 6: `test-install.sh` lists + install count text.
- Next ids: AM48, LP72, AMC20, PK46, G18.42, K27, A43.

## Live DB state
n/a (kit repo, no database)

## External surface
n/a

## Traps (points of vigilance for the review)
- The gh ask regexes read the whole command: a read-only exemption must be judged per gh call, so `gh repo view && gh repo delete x` still asks and `gh pr view 1 && gh pr merge 1` still asks (`:2171`).
- Today `gh pr list --search merge` or `gh issue list --label comment` ask through the unanchored `:2171`/`:2179`: narrowing must not open a write form, and does not need to fix these false asks.
- An `allow` decision in the gh path would short-circuit the later asks (first-hit `decide()`); the read-only forms must fall through to pass, not emit allow.
- `-R/--repo` flags sit between `gh` and the subcommand; every regex form must accept them (`gh_skip_repo`).
- Fix 1 must not accept an import edit without a verdict, an import removal or rewrite, a non-import line, or an import placed after the first case; the arbiter text and the hook must accept the same hunk.
- Fix 1's import detection is a new notion: a multi-line `import { a,\n b } from 'x'` and `import type` are real shapes; a line that only looks like an import (inside a template literal) must not open the gate.
- The Python twin of the freeze hook may hold the same refusal; leaving it out silently is a gap.
- Fix 2 removes `--clear` only from the blocked-stop path; the three finished-pass sites keep it and their pins stay.
- `kit-pr-assets.py` with an invalid project.json must not widen; absent must keep `[]` so K1-K3 hold.
- `kit-audit-surface.py` has no `src/` literal (only `shared/schemas/` `:81`): the handoff's premise is not supported; its acceptance criterion is probably already met.
- Fix 6 has two copies (repo `.gitignore` and `install.sh` block, fresh + top-up) plus a hardcoded count.

## Open questions
1. **Fix 2, what a blocked stop leaves behind.** `orchestrate.md:79` prescribes `--clear` on a blocked stop; the spec says a blocked stop "ends the turn with the record intact". If the record is kept, `./workflow.sh` resumes in auto, and the line "resumes in `moi` unless a new Contract gate is taken" changes meaning. Does the kept record mean the resume continues in auto (the record and its barrier are still valid), or does `workflow.sh` clear it at resume, so the user and not the agent decides? Settled by choosing which of the two the contract means.
2. **Fix 2, the `tdd-freeze-tests.sh:340` deny text** offers `--clear` as a way out of an ambiguous case mid-pass. Drop that option (only "correct it through the unfreeze queue" left), or keep it for `moi` and remove it in auto?
3. **Fix 3, native permission layer.** No `Bash(gh …)` allow entry exists in `settings.json` or `install.sh`. The EcoCrew asks came from the hook (`:2175`), so the spec's hook change removes them; are native allow entries for the read-only list in scope, or out (the spec names only `enforce-git-workflow.sh`)?
4. **Fix 3, `--web`.** The spec excludes `--web` from the read-only list (it opens a browser). Should `gh pr view --web` keep asking, or just pass as today?
5. **Fix 5, invalid project.json in `kit-pr-assets.py ui`.** Refuse (exit 2, no `ui`/`none` line, review.md must handle it) or fall back to `src/` only?
6. **Fix 5, audit-surface.** No `src/` literal exists. Pin the criterion with a test (no code change), and replace `shared/schemas/` (`:81`) with `<root>/shared/schemas/` per app root, or leave `:81` alone?
7. **Fix 5, `/kit:init` rule.** The spec's detection (package.json + `src/`) differs from the current rule (package.json + one root config, or pyproject.toml). Add the `src/` requirement for front-end roots only, keeping pyproject roots as today?
8. **Fix 1, Python twin.** Apply the same import allowance to `addons/fastapi/hooks/tdd-freeze-tests-py.py` (Python `import`/`from … import`), or record it as a follow-up?
