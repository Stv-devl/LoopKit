# Plan: Motion layer   (entry: docs/specs/motion-layer.md · research: docs/work/motion-layer/research.md · design: n/a)
Token profile: economy

## Skips
- INTERFACE : SKIP — kit tooling, no user surface.
- DB, Backend, TS front layers, hooks/gateway/UI tests : SKIP — markdown and bash only, nothing under `src/` or `shared/`, so no test-first hook applies.
- Impeccable step: n/a (no UI feature).

## Write chain (sequential)
1. **Contract greps first** — append the checks listed in the Test plan to `.claude/hooks/test-workflow-contracts.sh`; then show each new literal is individually unmet (a loop over the literals prints MISSING for every one; any literal that already exists is vacuous and gets a stricter phrase). The script itself stops at its first failing grep, which is expected.
2. `.claude/skills/patterns/motion.md` — default guide: Motion via `m` + `LazyMotion`, or CSS; `prefers-reduced-motion`; the standard block `## Acceptance criteria for animated features`; unverified items flagged (React 19/Compiler).
3. `.claude/skills/patterns/gsap.md` — on-demand guide: only when the spec declares `Motion: gsap - <reason>`, lazy `import()`, `useGSAP` + scope + cleanup, `gsap.matchMedia()` for reduced motion, licence caveat, never in the same component as Motion, bundle size "measure in your app".
4. `.claude/skills/project-rules/SKILL.md` — one router row for both patterns.
5. `.claude/rules/01-stack.md` — one table row + one or two lines: names, default, GSAP only on a `Motion: gsap` declaration, pointer to `docs/research-cache/motion.md` and `gsap.md` for versions (no versions written). Stay <= 45 lines.
6. `.claude/skills/patterns/a11y.md` — new section `Motion and reduced motion` before "A11y tests".
7. `.claude/agents/reviewer.md` `ui` dimension — one bullet `Animation conformance`.
8. `.claude/commands/loop/spec.md` — optional `Motion:` line in the template + one Rules bullet.
9. `docs/Claude_Workflows.md` and `docs/ADAPTATION.md` — motion mention, the stage-0 limit (still captures, animation feel not judged), and the Impeccable limit (its detector only catches known code patterns, e.g. bounce easing). `docs/ADAPTATION.md` is an explicit addition beyond the spec's Front surface list: it is where the install/limits notes for optional tooling already live.
10. Gates: `bash .claude/hooks/test-workflow-contracts.sh`, `python3 .claude/hooks/kit-doctor.py` (no divergence, no MISSING), `bash .claude/hooks/test-rules-floor.sh`, `[ ! -e package.json ]`, `git diff --stat -- .claude/settings.json .claude/settings.local.json` empty before shipping.

## Decisions taken from research's Open questions (confirm at the gate)
1. Motion with React 19 + Compiler/StrictMode: **not verified**; `motion.md` says so and points to the project's own check (issues unread). No extra fetch.
2. GSAP size and lazy guidance: not found; `gsap.md` says "measure in your app" and requires a dynamic `import()`, without a size figure.
3. The standard acceptance criteria for animated features live in `motion.md` (block heading `Acceptance criteria for animated features`); the reviewer bullet cites that block. The spec template only documents the optional `Motion:` line.
4. `01-stack.md` carries names and a pointer to the cache files, no versions.
5. Review severity: animated feature without `prefers-reduced-motion` handling is Major, like the two GSAP rules (the spec fixes only those two; this third one is my addition, drop it if you disagree).

## Parallel lots (inside this track, same tree)
none — fully sequential (small coupled wording changes; several files are cross-referenced).

## Track isolation
- Worktree: none, single track.
- Shared foundations touched: none of the listed ones (rules file `01-stack.md` is a hot rule but not a listed foundation).

## Files
| Path | Create/Edit | Role |
| --- | --- | --- |
| .claude/hooks/test-workflow-contracts.sh | Edit | new contracts |
| .claude/skills/patterns/motion.md | Create | default guide + animated-feature criteria |
| .claude/skills/patterns/gsap.md | Create | on-demand guide |
| .claude/skills/project-rules/SKILL.md | Edit | router row |
| .claude/rules/01-stack.md | Edit | stack row + pointer, <= 45 lines |
| .claude/skills/patterns/a11y.md | Edit | reduced-motion section |
| .claude/agents/reviewer.md | Edit | `ui` bullet |
| .claude/commands/loop/spec.md | Edit | optional `Motion:` line |
| docs/Claude_Workflows.md, docs/ADAPTATION.md | Edit | mention + stage-0 limit |
| docs/research-cache/motion.md, gsap.md | already written | facts cited, not copied |

## Contracts
- Declaration: a spec asks for GSAP with the exact line `Motion: gsap - <reason>` under `Front surface`; absent means Motion or CSS.
- Review (`ui`): GSAP not requested by the spec or `design.md` is Major; Motion and GSAP in one component is Major; animated feature without `prefers-reduced-motion` handling is Major (cited from `motion.md` criteria).
- Docs/patterns must not claim `reducedMotion="user"` disables everything (it still animates opacity) and must mention the GSAP licence restriction.
- No `.claude/...` path named in a doc unless it exists; `CLAUDE.md` does not import the patterns.

## Test plan (gate — validated by the user before EXECUTE)

### Test-first — front / backend
None: nothing under `src/` or `shared/`; the TDD hooks do not apply. The contracts below are added first and shown failing.

#### .claude/hooks/test-workflow-contracts.sh (bash contract checks, each phrase on a single line in its file)
**Core behaviour**
- [ ] `patterns/motion.md` and `patterns/gsap.md` exist, and `project-rules/SKILL.md` contains `../patterns/motion.md` and `../patterns/gsap.md`.
- [ ] `spec.md` contains `Motion: gsap - <reason>`, and `01-stack.md` contains `Motion: gsap`.
- [ ] `reviewer.md` contains `Animation conformance`, `GSAP not requested by the spec or design.md is Major`, and cites the reduced-motion rule with the literal `prefers-reduced-motion`.
- [ ] `motion.md` contains `Acceptance criteria for animated features` and `prefers-reduced-motion`; `a11y.md` contains `prefers-reduced-motion`.
**Business rules**
- [ ] `motion.md` contains `still animates opacity` (the reduced-motion caveat).
- [ ] `gsap.md` contains, each on one line and in this exact casing, `Standard no charge` (no quotes), `Webflow`, `dynamic import`, and `never in the same component`.
- [ ] `reviewer.md` contains `both libraries in one component` (lowercase, one line).
- [ ] `01-stack.md` is <= 45 lines; `CLAUDE.md` does not contain `patterns/motion`.
- [ ] Docs: `docs/Claude_Workflows.md` contains `ne juge pas le mouvement` and `motifs de code connus`; `docs/ADAPTATION.md` contains `patterns/motion.md` and `motifs de code connus` (the Impeccable limit).
**Edge cases**
- [ ] `.claude/commands/loop/*.md` count is still 12 (existing check stays).
- [ ] No `package.json` exists at the repo root (`[ ! -e package.json ]`, which also catches an untracked file).
- [ ] No version number is written in `motion.md`, `gsap.md` or `01-stack.md`: none of them contains a `motion@`, `gsap@`, `13.4.0` or `3.15.0` literal (versions stay in the cache files).
- [ ] `git diff --stat` for `.claude/settings*.json` is empty.

### Test-after — hooks, gateway, UI
n/a. `/kit:doctor` (no divergence, `rules-budget`, `shipped-paths`) and `test-rules-floor.sh` stay green.

## Vigilance (carried from research)
- Are the rejected explorer suggestions absent (Motion not called CSS-based; design.md path is `docs/work/<slug>/design.md`; no versions in `settled.md`)?
- No versions pinned from memory in `01-stack.md`; pointer to the cache files only.
- `01-stack.md` <= 45 lines, patterns not imported by `CLAUDE.md`.
- Reduced-motion wording does not over-claim; GSAP licence restriction present.
- Docs state review stage 0 cannot judge animation feel.
- No doc names a non-existent `.claude/skills/...` path; `Motion:` line wording exact.

## Acceptance criteria (carried from the entry artifact)
- [ ] `01-stack.md` names Motion (default, or CSS) and GSAP (only when a spec asks), stays within its line budget, and `/kit:doctor` `rules-budget` and `rules-loaded` stay green.
- [ ] `patterns/motion.md` and `patterns/gsap.md` exist, are routed from `project-rules/SKILL.md`, and are not imported by `CLAUDE.md` (cold, read on demand).
- [ ] A spec can request GSAP with the single line `Motion: gsap - <reason>`; the `/loop:spec` template documents it as optional, default absent.
- [ ] `reviewer.md` `ui` dimension flags GSAP not requested by the spec or `design.md`, and both libraries in one component, as Major.
- [ ] `patterns/a11y.md` states the `prefers-reduced-motion` rule, and the review's standard criterion for animated features cites it.
- [ ] Library versions and GSAP licence terms in the stack line and guides are sourced from `docs/research-cache/` (tagged `[cache]`/`[fetched]`), not written from memory.
- [ ] The docs say plainly that review stage 0 does not judge motion and Impeccable only catches known patterns.
- [ ] No new file under `.claude/commands/loop/`, no `package.json` or dependency added; `test-workflow-contracts.sh`, `kit-doctor` and `test-rules-floor.sh` pass.

## Plan critic
- completeness: 80 -> revised (Major fixed: Impeccable half of criterion 7 now written and contracted; Minors addressed)
- quality: 82 -> revised
- surviving blockers: none after rewrite (critic claims verified directly, no second pass on economy)
