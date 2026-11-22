# Spec: PR screenshots — Playwright captures embedded in the PR body through an orphan `pr-assets` branch, and a PR body that says where to look
Status: READY — framed 2026-11-11 (user). Independent of `loop-to-pr.md` (not shipped): that pass later appends its own sections to the body defined here.
Token profile: economy (no guard is loosened: every push, including `pr-assets`, keeps today's ask)

## Objective
A PR whose diff changes the UI carries, in its body, Playwright screenshots of the key steps of each flow e2e-tester proved, hosted in the repo itself (orphan branch `pr-assets`, no external service, no secret), and every PR body opens with where the reviewer must look and what the author is unsure of.

## Evidence
Research 2026-11-11 (this session): agent-filled uniform PR templates stop being read (MSR 2026 study of 33,596 agent PRs; tianpan.co 2026-06-02); "where to look" and "what I am unsure of" are the sections reviewers use. `gh` cannot upload images to a PR body or comment, so images must be hosted at a URL; a branch of the repo keeps the repo's access rights (a private repo's images stay private), unlike a public bucket. Most of the user's projects no longer use Supabase.

## Scope
- IN :
  - **S0. Proof first.** Before any other work, prove on a private GitHub repo that `https://github.com/<owner>/<repo>/blob/pr-assets/<path>.png?raw=true` renders inline in a PR body for a signed-in collaborator. If it does not, stop and return to the user with the observed result; nothing else of this spec is built on a failed proof. Recorded in `docs/product/spikes/pr-assets-raw-url.md` (or the plan's chosen path).
  - **S1. PR body template** (`.claude/agents/github.md`, "PR title and body — the template"), extended, in this order:
    1. the one-line summary (unchanged);
    2. `Where to look` — 1 to 3 lines, each `path:line` or a named area, with why;
    3. `Uncertain` — the author's open doubts, or absent when there are none (never "none");
    4. the commit list, **one line per commit, no cap** (unchanged rule; the 8-line cap stays removed);
    5. `Screenshots` — only when S2 applies, else absent.
    The existing rules stay (no opening paragraph, no closing line, at most one caveat, numbers over adjectives). A single no-code commit still gets a one-line body. `loop-to-pr.md` later appends its own sections after these; it is not edited by this pass beyond a one-line cross-reference.
  - **S2. When screenshots are taken.** Only when both hold: e2e-tester ran in the pass's review, **and** the diff against the base touches UI files (the plan names the exact globs, at least `src/**/*.tsx` and style files). Otherwise no capture and no `Screenshots` section.
  - **S3. What is captured.** For each flow e2e-tester proved, its key steps (the plan bounds how many per flow). Each step in **light and dark** (dark only when the project has a dark theme), at **desktop and mobile** widths. For a **bugfix** pass, also the **before** state, captured on the base branch, next to the after. Captures are produced by Playwright from the mock/test data the `e2e-playwright` skill already mandates, never from real user data. They are a by-product of a run, never an assertion: no visual-diff gate.
  - **S4. Storage.** An orphan branch `pr-assets` in the same repo, never merged, holding only images. Path is immutable: `<branch>/<short-sha>/<flow>-<step>-<light|dark>-<desktop|mobile>[-before].png`; a new commit gets a new folder, an existing path is never rewritten. The branch is created on first use. Capture output folders are git-ignored on the work branch; no PNG is ever committed to the work branch.
  - **S5. Publishing.** The `github` agent commits the images to `pr-assets` and pushes it **with the same validation as any push**: it shows the image list and the URLs it will embed, then asks. The PR body embeds them in the `Screenshots` section, grouped by flow, in a compact table (light/dark × desktop/mobile), with before/after side by side for a bugfix.
  - **S6. Cleanup after merge.** When the PR reads `MERGED`, the agent prepares the commit deleting `<branch>/` on `pr-assets` and asks once for its push. Merged PRs' images then stop rendering; this is accepted (user, 2026-11-11).
- OUT :
  - V2: asking the agent questions in PR comments (`@claude`, `claude-code-action`), and the agent posting inline review comments. Deferred by the user.
  - Any external host (Supabase Storage, imgur, S3, CI artifacts links).
  - Visual regression testing / screenshot diffs as a gate.
  - Removing the push ask for `pr-assets` or allowing new git commands without a prompt: anything that would widen what runs unasked belongs to `loop-to-pr.md` or a later spec.
  - Videos, GIFs, Playwright traces in the PR body.

## Open questions (decide in the plan)
- How images reach `pr-assets` without a shell write to a working file (CLAUDE.md forbids writing files from the shell, and PNGs cannot go through Write): git plumbing (`hash-object -w` / `mktree` / `commit-tree` / `update-ref`, no checkout), or a dedicated worktree. Whichever is chosen keeps the commands' existing asks.
- Where the capture lives: inside the e2e-tester's spec (one file it owns) behind a tag/env switch, or a separate capture spec per flow. e2e-tester's one-file rule holds either way.
- How "before" is captured for a bugfix (a run on a base worktree vs. a stash) without touching another track's tree.
- Max key steps per flow, and a max image count per PR.
- The exact UI globs of S2, and how a kit-only repo (this one) answers "no UI" so no section appears.

## Data model
none

## Custom backend
NONE, kit tooling.

## Front surface
No app code. Expected files:
- Agents: `.claude/agents/github.md` (template S1, publishing S5, cleanup S6), `.claude/agents/e2e-tester.md` (capture S3, output contract listing the images).
- Skills: `.claude/skills/e2e-playwright/SKILL.md` (capture switch, viewports, themes, output folder); a cold pattern if the plan needs one (e.g. `.claude/skills/patterns/pr-screenshots.md`).
- Commands: `.claude/commands/loop/ship.md` (hands the image list to the github agent; cleanup on `MERGED`), `.claude/commands/loop/review.md` if it launches e2e-tester with the capture switch.
- Tooling: `.gitignore` template for capture output; `test-workflow-contracts.sh` greps.
- Docs: `docs/Claude_Workflows.md`, `README.md`, one cross-reference line in `docs/specs/loop-to-pr.md`.
No hot rule (`.claude/rules/`) grows.

## Acceptance criteria
- [ ] S0 is recorded with the observed render on a private repo before any other change lands; a failed proof stops the pass.
- [ ] A PR drafted by the `github` agent opens with the summary, then `Where to look` (1-3 lines), then `Uncertain` only when non-empty, then one line per commit with no cap.
- [ ] A pass whose diff touches no UI file produces no capture and no `Screenshots` section.
- [ ] A UI pass produces, per key step, light/dark × desktop/mobile images (dark only if the project has a dark theme), plus before images on a bugfix, all from mock/test data.
- [ ] Images land on `pr-assets` under `<branch>/<short-sha>/…`; no PNG is committed on the work branch; an existing path is never rewritten.
- [ ] The `pr-assets` push and the cleanup push each go through the ask, with the image list / folder shown first; nothing runs unasked that asks today.
- [ ] After `MERGED`, the cleanup commit removes exactly `<branch>/` from `pr-assets` and nothing else.
- [ ] `test-workflow-contracts.sh`, `test-hooks.sh`, `test-install.sh`, `kit-doctor.py` and `test-rules-floor.sh` pass.

## Business logic to cover
- The UI-touch decision: a diff with only non-UI paths → no capture; any UI path → capture.
- The image path builder: branch, short sha, flow, step, theme, viewport, before suffix → one immutable path; two commits never share a folder; names are filesystem- and URL-safe (branch slashes handled).
- The `Screenshots` section builder: images grouped by flow, table per step, before/after pairing, raw URLs pointing at `pr-assets`.
- The cleanup selection: only `<branch>/` of the merged PR, never another branch's folder.
- Contract greps: `github.md` keeps "one line per commit" and carries `Where to look` / `Uncertain` / `Screenshots`; no host other than `pr-assets` is named as the image store.
