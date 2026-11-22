# Research: PR screenshots via `pr-assets`   (entry: docs/specs/pr-screenshots.md)
Token profile: economy

> Line anchors below were taken from the main tree's staged copy (`audit/slim` + `app-roots-codegen` hunks). In this worktree (`e4837f2`) re-read each anchor before an edit.

## Pattern to follow
- PR body template lives only in `.claude/agents/github.md:58-98` (title 60-61, body 63-73, rules 75-92, example 94-98); S1 extends that block in place.
- Validation gate `github.md:100-114` (preview 108-112) is the model for S5/S6: show list + command, ask, run.
- e2e launch from review: `.claude/commands/loop/review.md:137-151` (one tester per flow, gets artifact, flow, spec path 140-142); stage 0 already speaks of desktop ~1280px + mobile (`review.md:49`).

## Wiring points
- `gh pr create --title … --body "<markdown>"` inline (`github.md:137`); the hook reads both `--body` and `--body-file` (`enforce-git-workflow.sh:1441-1442`).
- Ship calls the github agent at step 4 (`ship.md:114-125`), integrate 4bis (`ship.md:127-158`). E2E is excluded from ship gates (`ship.md:55-59`): screenshots must come from the review-stage run.
- e2e-tester output contract `e2e-tester.md:73-84` has no artifact/image field.
- e2e-playwright harness: `playwright.config.ts` root, specs in `e2e/`, `playwright-report/`, traces on failure only (`SKILL.md:17-22`); projects `public`/`authed` (`SKILL.md:47-61`); MSW mock layer with `onUnhandledRequest: "error"` (`SKILL.md:89-110`).
- `.gitignore:7-11` already ignores `test-results/`, `playwright-report/`, `blob-report/`; `install.sh:523-531,771` `ensure_gitignore` back-fills a fixed list and does not include those.

## Reusable
- Desktop/mobile wording at `review.md:49`.
- Contract greps: `test-workflow-contracts.sh` (`GITHUB_AGENT` line 15, `section` helper 287, examples 418-419, 469, 833-834).
- Nothing exists for viewports, colorScheme, screenshot settings, PR-state reading (`gh pr view`), or `pr-assets` (all greps empty).

## Blast radius
- Needles that break if edited: `test-workflow-contracts.sh:469` (`git commit -m "<one line>"`), `:833-834` (github.md body/commit sentence).
- `kit-doctor.py:655-753` reads `model:`/`effort:` frontmatter of `github.md:5-6`, `e2e-tester.md:5-6`: do not touch.
- `kit-doctor.py:1065-1087` resolves every "`name` agent" phrase in docs.
- No line budget on agents/skills (`kit-doctor.py:1204-1216`, `test-rules-floor.sh:31-36` cover rules + CLAUDE.md only).
- `kit-doctor.py:1090-1097` FILL scan does not cover `skills/e2e-playwright/`.
- Docs: `docs/Claude_Workflows.md` 152, 315, 321, 542-543, 670, 673; `README.md` 68, 122. None describes the PR body today.

## Live DB state
n/a (kit tooling).

## External surface
- `gh` cannot upload binaries to a PR body/comment; hosting must be a URL [fetched, this session's web research 2026-11-11: skillsmp pr-screenshots skill, shipyard.build].
- Rendering of `github.com/<o>/<r>/blob/pr-assets/<p>?raw=true` in a **private** repo for a signed-in collaborator: unproven — that is S0, settled empirically, not by docs.

## Traps (points of vigilance for the review)
- **Attribution conflict**: `github.md:30-35` forbids "Generated with"/Co-Authored lines in commits and PR bodies, and the hook denies them (`enforce-git-workflow.sh:1383,1468-1469,1476-1477`). The new template must not add a footer.
- Every push asks (`enforce-git-workflow.sh:1553-1559,1575-1577`) and `gh pr create` asks (`:1541-1542`): S5/S6 keep these asks; no `settings.json` allow may be added (spec OUT).
- Plumbing treatment: `hash-object`/`mktree` no hook decision (default prompt); `commit-tree` asks (`:1704`); `switch --orphan` asks; `checkout --orphan` default prompt; `update-ref` asks on `refs/heads/…` operand (`:756-771`) but **not on a short name** — a short-name update-ref would slip without the hook's ask; use the full ref and keep it asked.
- `cp x.png dir/` is not stopped by any hook (`prevent-destructive-commands.sh:671-690` targets source writers/guarded paths); the no-shell-write rule is prose only (CLAUDE.md). The chosen path must not rely on `cp` into a working tree.
- Mock-data guarantee is unfilled: `SKILL.md:63-79` backend-hazard FILL. Capture must be gated on the mock/disposable backend the skill declares, else no capture.
- e2e-tester owns exactly one spec file (`e2e-tester.md:33-35`) and may not edit the Playwright config: viewports/themes must be set inside the spec (e.g. `test.use`), not in the config.
- Kit repo itself has no UI: S2 must yield "no Screenshots" here.
- One line per commit (`github.md:53,80`) is unasserted today; add the grep so S1 cannot drop it.
- `loop-to-pr.md:20` future sections must still fit after S1's sections (append, no reorder).

## Open questions
1. Images to `pr-assets`: git plumbing with **no working tree** (`hash-object -w` on the files in `test-results/…`, `mktree`, `commit-tree -p <old>`, `update-ref refs/heads/pr-assets`, push) — or a `git worktree add` of `pr-assets` plus `cp`? Recommendation: plumbing (no shell write to a working file; every step already prompts or asks).
2. Where does the PNG-to-path mapping logic live (S4 path builder, S2 UI decision, section builder, cleanup selection — "Business logic to cover")? A kit script (e.g. `.claude/scripts/pr-assets.sh` or `.py`, tested by a new `test-pr-assets.sh`) or prose only in `github.md`? Recommendation: a small Python script with a test file, since the spec lists testable behaviours.
3. Capture switch: an env var (e.g. `PR_SHOTS=1`) read inside the flow's spec, writing to `test-results/pr-shots/`? And the bugfix "before": run the same spec on a `git worktree add` of the base, launched by the main thread?
4. Caps: max key steps per flow (proposal 3) and max images per PR (proposal 24)?
5. UI globs for S2 (proposal: `src/**/*.{tsx,jsx,css,scss}`, `src/**/*.module.*`, `public/**`, `index.html`, `tailwind.config.*`).
6. Body passing: switch `gh pr create` to `--body-file` (needed once the body carries a table of images)? The file must be written with Write, outside the repo tree (scratchpad) or under `docs/work/<slug>/`.
7. Cleanup trigger: ship has no PR-state read today; add a `gh pr view --json state` check at the next `/loop:ship` or session start, or a manual `/kit:…` step?
