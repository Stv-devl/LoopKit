# Spike: does a private-repo `pr-assets` blob URL render in a PR body?
Date: 2026-11-11 · Token profile: economy · Source spec: `docs/specs/pr-screenshots.md` (S0)

Result: renders

## Question
Does an image committed on an orphan `pr-assets` branch of a **private** repo render in that repo's PR body when the body references it as `https://github.com/<o>/<r>/blob/pr-assets/<path>?raw=true`, inside the K12-shaped `<a><img width></a>` table cell?

## Method
Scratch repo `Stv-devl/pr-assets-s0` (private, created by hand by the user: the `gh` fine-grained token has no Administration permission).
- Orphan `pr-assets` root commit `0dda244`, tree = `feat/s0/abc1234/proof-01-home-light-desktop.png` only.
- Branch `feat/s0` (`9f2dc9d`, empty commit), draft PR https://github.com/Stv-devl/pr-assets-s0/pull/1.
- Body: one `**Screenshots** — proof` table, desktop row, light cell `<a href="U"><img src="U" width="400"></a>`, dark cell `—`.

## Evidence
The user opened the PR, signed in, and reported the image displayed (2026-11-11).

## Answer
```yaml
answer: decided
decision: renders — blob/pr-assets/<path>?raw=true works in a private repo's PR body
evidence: [https://github.com/Stv-devl/pr-assets-s0/pull/1, pr-assets 0dda244]
confidence: high
```
Repo visibility: private. Viewers must have read access to the repo, as for any private PR.

## Consequence
S0 passes; the pass proceeds to step 1. Scratch PR, branches and repo are removed afterwards on the user's go.
