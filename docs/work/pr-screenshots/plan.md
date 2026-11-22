# Plan: PR screenshots via `pr-assets`   (entry: docs/specs/pr-screenshots.md · research: docs/work/pr-screenshots/research.md · design: n/a)
Token profile: economy

## Skips
- INTERFACE : SKIP — kit tooling, no app screen.
- DB, Backend, Front app layers : SKIP — no app code (spec: Data model none, Custom backend NONE).
- TDD hooks : not enforced here (matcher covers `src/`/`shared/` only, `05-testing.md`); the kit script is still written test-first by convention: `test-pr-assets.sh` RED observed before `kit-pr-assets.py` exists.

## Write chain (sequential)
0. **S0 proof (user-gated, stops the pass on failure).** On a private repo the user names: an orphan `pr-assets` holding one PNG, a draft PR whose body is one real K12-shaped `Screenshots` block (`<a><img width></a>` in a table) pointing at `https://github.com/<o>/<r>/blob/pr-assets/<p>?raw=true`; the user reports whether it renders. Every push/`gh` call asks. Result written to `docs/product/spikes/pr-assets-raw-url.md` (`Result: renders | broken`, date, repo visibility). Draft PR and branch deleted afterwards on the user's go.
1. **Script, test-first**: write `.claude/hooks/test-pr-assets.sh` (K1-K23), run it, observe RED (script missing) → write `.claude/hooks/kit-pr-assets.py` until green. Subcommands `ui`, `path`, `plan`, `section`, `commit`, `drop`. Pure stdout except `commit`/`drop`, which write only `refs/heads/pr-assets` through a temporary index (`GIT_INDEX_FILE` in the child env), a fixed one-line message with no footer (`chore(pr-assets): add <branch> <sha>` / `chore(pr-assets): drop <branch>`), and a compare-and-swap `update-ref refs/heads/pr-assets <new> <old>`. No `push`, no `fetch` in the script.
2. **Wiring of the script**: `.github/workflows/kit-ci.yml` step, `kit-doctor.py` shipped list (re-read the anchor here), `.gitignore` + `install.sh` `ensure_gitignore` gain `.pr-shots/`. No allow added anywhere: every `kit-pr-assets.py` call and `gh pr list` gets the default prompt (stated in `github.md`).
3. **Capture** (`e2e-playwright/SKILL.md`, new "PR screenshots" section; `e2e-tester.md`):
   - Env `PR_SHOTS=after|before` and `PR_SHOTS_DIR=.pr-shots/<slug>/<run-id>/`, both given by the main thread. A new review run = a new `<run-id>` (UTC `YYYYMMDDTHHMMSS`), so stale images are never in the published folder and nothing is deleted.
   - File name `<flow>/<NN>-<step>-<theme>-<viewport>[-before].png`, written by an inline `shot()` in the tester's own spec. **After mode: the shot is taken after the step's assertions** (they are what waits for the UI to settle, so no skeleton or spinner is published). **Before mode: `await <step anchor>.waitFor()` (non-asserting), then the shot, then the assertions**, so a base run that fails at the buggy step has already captured it.
   - After mode: light, plus dark when the project has one, × desktop 1280×800 / mobile 390×844. Before mode: desktop-light only.
   - **Dark detection**: `docs/design-system.md` declares the theme mechanism; `media` → `page.emulateMedia({ colorScheme: 'dark' })`; `class:<name>` or `attribute:<a>=<v>` → set on `<html>` via `page.locator('html').evaluate`. No design system, or no dark declared → light only, said in the output line.
   - Only on the mock/disposable backend the skill declares; unfilled backend section → no capture.
   - Before mode needs the project's Playwright config to honour `PW_BASE_URL` (skip `webServer` when set); absent → no before images, said in the output line.
   - `e2e-tester.md` output contract gains `Screenshots: <PR_SHOTS_DIR> (<n> files; dark: <mechanism|none: why>; before: <n|none: why>)` or `Screenshots: none (<why>)`.
4. **Review wiring** (`review.md`): the main thread computes the UI decision on the **working tree** — `git diff --name-only <base>` plus `git ls-files --others --exclude-standard`, `<base>` = `git merge-base HEAD <plan Base:, else the default branch>` — piped to `kit-pr-assets.py ui`. `ui` → launch e2e-tester with `PR_SHOTS=after` and a fresh `PR_SHOTS_DIR`; record `Screenshots run: <dir>` in the plan's `## Gate`, **replacing** any earlier `Screenshots run:` line (a re-review after fixes captures again; the last run is the one shipped). Older run dirs stay on disk, git-ignored, never published. Bugfix pass (`BUG` / `debug.md` entry): the main thread adds a base worktree `.claude/worktrees/<slug>-base` at `<base>`, installs, serves it on a free port, runs the same spec with `PR_SHOTS=before PW_BASE_URL=<that url>` into the same dir (its failing exit is expected and not a finding), then `git worktree remove .claude/worktrees/<slug>-base`. `none` → no capture, no `Screenshots run:` line.
5. **PR body + publishing** (`github.md`): template S1 in this order — summary, `Where to look` (1-3 lines), `Uncertain` (only if any), one line per commit, `Screenshots` (only if a `Screenshots run:` is recorded); body written with Write to `docs/work/<slug>/pr-body.md` and sent with `--body-file`. S5: `git fetch origin` → `kit-pr-assets.py plan` → show list + URLs → ask → `kit-pr-assets.py commit` → `git push origin refs/heads/pr-assets` (asked) → `section` into the body. `--sha` is the short sha of the pass's ship commit (publishing runs after it). S6: `git fetch origin` → `gh pr view <n> --json body --jq .body | kit-pr-assets.py drop --branch B` (the folders are read from the images the PR actually published, so a rebase or squash at merge changes nothing) → show the folders → push (asked).
6. **Ship wiring** (`ship.md`): step 4 hands the `Screenshots run:` dir (or none) and `<base>` to the github agent; step 5 offers cleanup for each merged PR (`gh pr list --state merged --json number,headRefName`, then its body as in S6, default prompts), skipping any branch name that also has an open PR (`gh pr list --state open --head <B>`).
7. **Contracts + docs**: `test-workflow-contracts.sh` greps (below), `test-install.sh` assertions; `docs/Claude_Workflows.md`, `README.md`, one cross-reference line in `docs/specs/loop-to-pr.md`.
8. Refactor under green suites; no test edited.

## Parallel lots (inside this track, same tree)
none — fully sequential.

## Track isolation
- Worktree `.claude/worktrees/pr-screenshots` on `feat/pr-screenshots`, forked from `e4837f2` (Q8, user 2026-11-11). The main tree keeps `audit/slim` with the staged `app-roots-codegen` hunks in `install.sh`, `kit-doctor.py`, `test-workflow-contracts.sh`, `test-install.sh`: the second pass to merge resolves the overlap and reruns every kit suite. Also overlaps later with `loop-to-pr.md` (`github.md` template, `ship.md`).
- Shared foundations touched: `install.sh`, `.gitignore`, `.github/workflows/kit-ci.yml`, `kit-doctor.py`, `test-workflow-contracts.sh`.

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| `docs/product/spikes/pr-assets-raw-url.md` | Create | S0 result |
| `.claude/hooks/test-pr-assets.sh` | Create | K1-K23 |
| `.claude/hooks/kit-pr-assets.py` | Create | ui/path/plan/section/commit/drop |
| `.github/workflows/kit-ci.yml` | Edit | run test-pr-assets.sh |
| `.claude/hooks/kit-doctor.py` | Edit | shipped list |
| `.gitignore`, `install.sh` | Edit | `.pr-shots/` ignored |
| `.claude/skills/e2e-playwright/SKILL.md` | Edit | capture section |
| `.claude/agents/e2e-tester.md` | Edit | capture duty + output line |
| `.claude/commands/loop/review.md` | Edit | working-tree UI decision, launch, before run |
| `.claude/agents/github.md` | Edit | S1 template, `--body-file`, S5, S6 |
| `.claude/commands/loop/ship.md` | Edit | hand-off of the run dir, cleanup on MERGED |
| `.claude/hooks/test-workflow-contracts.sh`, `.claude/hooks/test-install.sh` | Edit | greps / install assertions |
| `docs/Claude_Workflows.md`, `README.md`, `docs/specs/loop-to-pr.md` | Edit | docs |

## Contracts
`python3 .claude/hooks/kit-pr-assets.py <cmd>`; exit 0 ok, 2 refused (one-line English reason on stderr, nothing written, nothing on stdout).
- `ui` — paths on stdin, one per line → `ui` or `none`. UI globs: `src/**/*.{tsx,jsx,css,scss}`, `src/**/*.module.*`, `public/**`, `index.html`, `tailwind.config.*`.
- `path --branch B --sha S --flow F --step NN-slug --theme light|dark --viewport desktop|mobile [--before]` → `<B>/<S>/<F>-<NN>-<slug>-<theme>-<viewport>[-before].png`. The branch keeps its `/` (git refs cannot hold both `a` and `a/b`, so folders never collide). Branch `[A-Za-z0-9._/-]+` with no `..` or leading `/`; sha `[0-9a-f]{7,40}`; flow/slug `[a-z0-9-]+`.
- `plan --dir D --branch B --sha S --repo owner/name` → JSON list `{local, path, url}`, `url = https://github.com/<repo>/blob/pr-assets/<path>?raw=true`. Caps: 3 steps per flow, 32 images. Missing/empty `D` → `[]`.
- `section` — same args → the block below; empty output when no image.
- `commit` — same args, inside the repo → commit on `refs/heads/pr-assets` adding exactly the planned paths. Parent: `origin/pr-assets` when local is absent or an ancestor of it; local when origin is absent or an ancestor of local; diverged → exit 2 `fetch first`. Existing path → exit 2. Prints the new sha.
- `drop --branch B` with the merged PR's body on stdin → collects every `blob/pr-assets/<B>/<sha7>/` folder named in the body's URLs, then commits removing exactly those that exist (same parent rule); none → prints `nothing to clean`, writes nothing. Never removes `<B>/` wholesale, so a later branch nested under `<B>/` or a reused name keeps its images; URLs for another branch in the body are ignored.
- The folder sha is **always the first 7 hex chars** of `--sha` (any length 7-40 accepted), so `path`, `plan`, `commit` and `drop` agree whatever `git rev-parse --short` returns.

Section (one block per flow, steps in order; a missing variant cell is `—`; the `before` row only when the step has a before image):
```markdown
**Screenshots** — checkout
| 01 cart | light | dark |
| --- | --- | --- |
| desktop | <a href="U1"><img src="U1" width="400"></a> | <a href="U2"><img src="U2" width="400"></a> |
| mobile | <a href="U3"><img src="U3" width="180"></a> | <a href="U4"><img src="U4" width="180"></a> |
| before (desktop) | <a href="U5"><img src="U5" width="400"></a> | — |
```

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — `.claude/hooks/test-pr-assets.sh` (kit convention, not hook-enforced)
Each case runs in a `mktemp -d` scratch; git cases in a scratch repo with a bare `origin`. Expected values are the literals below.

**Core behaviour**
- [ ] K1 a diff listing only `.claude/agents/github.md` and `docs/specs/x.md` prints `none`
- [ ] K2 a diff containing `src/features/cart/Cart.tsx` prints `ui`
- [ ] K3 `src/styles/app.css`, `index.html` and `public/logo.svg` each print `ui`; `src/features/cart/cart.utils.ts` alone prints `none`
- [ ] K4 `path --branch feat/pr-shots --sha abc1234 --flow checkout --step 02-pay --theme dark --viewport mobile` prints `feat/pr-shots/abc1234/checkout-02-pay-dark-mobile.png`
- [ ] K5 the same with `--before` prints `feat/pr-shots/abc1234/checkout-02-pay-dark-mobile-before.png`
- [ ] K8 `plan` on `<D>/checkout/01-cart-light-desktop.png` + `01-cart-dark-desktop.png`, repo `o/r`, prints two entries whose urls are `https://github.com/o/r/blob/pr-assets/feat/pr-shots/abc1234/checkout-01-cart-light-desktop.png?raw=true` and its `dark` twin
- [ ] K12 `section` on one step with the four after variants prints exactly the hand-written fixture block (Contracts shape, without the before row)
- [ ] K15 `commit` with no `pr-assets` anywhere creates a parentless commit on `refs/heads/pr-assets` whose tree lists exactly the planned paths and whose message is `chore(pr-assets): add feat/pr-shots abc1234`; `HEAD`, every other ref, `.git/index` bytes and `git status --porcelain` are identical before and after
- [ ] K20 `drop --branch feat/x`, stdin a PR body embedding `https://github.com/o/r/blob/pr-assets/feat/x/abc1234/checkout-01-cart-light-desktop.png?raw=true` and `https://github.com/o/r/blob/pr-assets/feat/x-y/abc1234/c.png?raw=true`, on a `pr-assets` holding `feat/x/abc1234/a.png`, `feat/x/9999999/b.png`, `feat/x-y/abc1234/c.png`, `main/abc1234/d.png` leaves exactly `feat/x/9999999/b.png`, `feat/x-y/abc1234/c.png`, `main/abc1234/d.png` (the PR's commits are never consulted, so a rebased PR is covered)

**Business rules**
- [ ] K13 a step with a `-before` desktop-light image gets the `before (desktop)` row; a step without one has no such row
- [ ] K16 `commit` on a local `pr-assets` holding `other/…` makes a commit whose parent is the old tip and whose tree keeps `other/…`
- [ ] K17 `commit` whose planned path already exists on `pr-assets` exits 2 and leaves `refs/heads/pr-assets` unchanged
- [ ] K18 local `pr-assets` absent, `origin/pr-assets` present → parent is `origin/pr-assets`
- [ ] K22 local `pr-assets` an ancestor of `origin/pr-assets` → parent is `origin/pr-assets`; local and origin diverged → exit 2 `fetch first`, ref unchanged
- [ ] K19 `drop` leaves `HEAD`, every other ref, `.git/index` bytes and `git status --porcelain` identical
- [ ] K10 a fourth step in one flow exits 2; a 33rd image exits 2; nothing on stdout

**Edge cases**
- [ ] K6 a branch containing a space, or `..`, exits 2
- [ ] K7 a sha `xyz` or `abc12` exits 2
- [ ] K9 `<D>/checkout/shot.png` (unknown name) exits 2 naming that file
- [ ] K11 a missing `<D>` prints `[]` for `plan` and nothing for `section`, exit 0
- [ ] K14 `section` with zero images prints nothing, exit 0
- [ ] K21 `drop --branch feat/x` with a body naming `feat/x/1234567/` absent from `pr-assets`, or a body with no image URL, prints `nothing to clean`, exit 0, ref unchanged
- [ ] K23 `path --sha abc1234def5678` (14 chars) prints a path whose sha folder is `abc1234`
- [ ] K24 (added in review) a symlink or hard link in the run dir exits 2 (`commit`: stdout empty, `pr-assets` absent; `plan` for the hard link)
- [ ] K25 (added in review) `plan` on `checkout/01-cart-dark-mobile-before.png` (before outside light-desktop) exits 2
- [ ] K26 (added in review) `drop --branch feat/x` for `feat/x/abc1234/a.png` leaves the nested `feat/x/abc1234/1234567/n.png`

### Test-after — contract greps and install assertions
- `test-workflow-contracts.sh`:
  - `github.md` template block holds, **in this line order**, the summary line, `Where to look`, `Uncertain`, the commit-list line, `Screenshots` (awk line numbers strictly increasing); contains `one line per commit`, `--body-file`, `kit-pr-assets.py commit`, `kit-pr-assets.py drop`, `pr-assets`; existing needles (`git commit -m "<one line>"`, the PR-body/commit sentence) unchanged.
  - `e2e-playwright/SKILL.md` contains `PR_SHOTS`, `PR_SHOTS_DIR`, `.pr-shots/`, `emulateMedia`, `PW_BASE_URL`; `e2e-tester.md` contains `Screenshots:`; `review.md` contains `kit-pr-assets.py ui`, `ls-files --others --exclude-standard`, `PR_SHOTS=before`; `ship.md` contains `kit-pr-assets.py drop` and `MERGED`.
  - No image host other than `pr-assets` is named in `github.md`, `SKILL.md`, `e2e-tester.md`: none of `imgur`, `supabase`, `upload-artifact`, `s3.` appears.
- `test-install.sh`: installed `.gitignore` contains `.pr-shots/`; installed `settings.json` allow list contains none of `kit-pr-assets`, `Bash(git push`, `Bash(gh pr` (AC6).

### Acceptance criteria → check
| AC | Check |
| --- | --- |
| 1 S0 first | step 0; `docs/product/spikes/pr-assets-raw-url.md` has `Result: renders` before step 1's commit |
| 2 body order | ordered awk grep on `github.md` |
| 3 no UI → nothing | K1, K3, K11, K14; `review.md` grep |
| 4 variants, mock data | prompt contract greps (SKILL/e2e-tester); observed on the first real UI feature after ship (measure, stated as not provable here) |
| 5 storage | K4, K5, K8, K15, K17; `.gitignore` grep |
| 6 asks kept | `test-install.sh` allow-list assertions; push/gh asks unchanged in `test-hooks.sh` |
| 7 cleanup exact | K19, K20, K21 |
| 8 suites | all five pass at ship |

## Vigilance (carried from research)
- No "Generated with"/Co-Authored footer in the new template or in the script's commit messages (`github.md` attribution ban; `commit-tree` inside the script is invisible to the hook's attribution check).
- No new allow: every push, `gh pr`, `git worktree add`, `kit-pr-assets.py` call keeps its prompt.
- The script writes only `refs/heads/pr-assets` (full ref, compare-and-swap) via a temporary index (K15, K19).
- No `cp`/shell write of images into a working tree; images go `.pr-shots/` → blobs.
- UI decision on the working tree, untracked files included — never `<base>...HEAD` before the ship commit.
- One run dir per review run; publish only the recorded `Screenshots run:` dir.
- Capture only on the mock/disposable backend the skill declares.
- e2e-tester keeps one file and never edits the Playwright config; `PW_BASE_URL` support is a project prerequisite, absent → no before images.
- Kit repo diff is `none` → no `Screenshots` on this repo's own PRs.
- `one line per commit` stays and is asserted; `loop-to-pr.md` sections append after S1's.
- `kit-doctor.py` agent frontmatter (`model:`/`effort:`) untouched.
- Research line anchors come from the main tree's staged copy: re-read every anchor in this worktree before editing.

## Acceptance criteria (carried from the entry artifact)
- [ ] S0 is recorded with the observed render on a private repo before any other change lands; a failed proof stops the pass.
- [ ] A PR drafted by the `github` agent opens with the summary, then `Where to look` (1-3 lines), then `Uncertain` only when non-empty, then one line per commit with no cap.
- [ ] A pass whose diff touches no UI file produces no capture and no `Screenshots` section.
- [ ] A UI pass produces, per key step, light/dark × desktop/mobile images (dark only if the project has a dark theme), plus before images on a bugfix, all from mock/test data.
- [ ] Images land on `pr-assets` under `<branch>/<short-sha>/…`; no PNG is committed on the work branch; an existing path is never rewritten.
- [ ] The `pr-assets` push and the cleanup push each go through the ask, with the image list / folder shown first; nothing runs unasked that asks today.
- [ ] After `MERGED`, the cleanup commit removes exactly `<branch>/` from `pr-assets` and nothing else.
- [ ] `test-workflow-contracts.sh`, `test-hooks.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Open questions (answered at the gate)
- Q1 images to `pr-assets` → git plumbing in `kit-pr-assets.py`, temporary index, no working tree.
- Q2 where the logic lives → `kit-pr-assets.py` + `test-pr-assets.sh`.
- Q3 capture switch → `PR_SHOTS` + `PR_SHOTS_DIR` inline in the tester's spec; before via base worktree + `PW_BASE_URL`.
- Q4 caps → 3 steps per flow, 32 images; before desktop-light only.
- Q5 UI globs → as in Contracts.
- Q6 body passing → `--body-file docs/work/<slug>/pr-body.md`.
- Q7 cleanup trigger → `/loop:ship` step 5, `gh pr list --state merged`.
- Q8 isolation → **decided by the user 2026-11-11 (run in parallel)**: this worktree, see Track isolation.
- Q9 before images need the project's Playwright config to honour `PW_BASE_URL`; the kit ships no config and e2e-tester may not edit it → proposed: accept the narrowing — the `e2e-playwright` skill documents the 3-line config prerequisite, and a project without it prints `before: none (no PW_BASE_URL)`.
- Q10 dark detection reads the design system's free-prose "Dark mode" line → proposed: the tester interprets it and names the mechanism it used in its output line (visible in the PR); no new design-system format in this pass.

## Gate
- 2026-11-11 contract: `as written`; Q8 isolation: this worktree.
- 2026-11-11 test plan: **go** (K1-K23, test-after greps and install assertions, Q9 and Q10 as proposed, AC7 read as "exactly that PR's published folders under `<branch>/`", accepted Minor). Test-first cases frozen.

## Plan critic
- completeness: 90 (pass 4; 88, 85, 66 before)
- quality: 86 (pass 4; 80, 77, 52 before)
- surviving blockers: none
- History: blocked after pass 3 (S6 cleanup missed folders after the 4bis rebase); the user chose "apply the fix" (2026-11-11) and authorised pass 4, which cleared. Accepted Minor: a PR re-published with a body holding only the latest `Screenshots` block leaves the earlier `<sha7>/` folder on `pr-assets`.
