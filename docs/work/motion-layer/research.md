# Research: Motion layer   (entry: docs/specs/motion-layer.md)
Token profile: economy

## Pattern to follow
Cold patterns under `.claude/skills/patterns/` (zustand.md, feedback.md, a11y.md: no frontmatter, `# <Name> Patterns`, ~250-350 lines, no budget), routed from a table in `.claude/skills/project-rules/SKILL.md` (l.11-21). The Impeccable integration (PR #9) is the analogue for the docs/contract/review wiring.

## Wiring points
- `.claude/rules/01-stack.md`: 38/45 lines (budget comment l.1). Table ends ~l.13, "Version changes are decisions" paragraph ~l.15: room for a table row + 1-2 lines.
- `.claude/skills/project-rules/SKILL.md`: add one row after the feedback/toast row.
- `.claude/skills/patterns/a11y.md`: sections end with "A11y tests" (~l.273 area); no mention of motion or reduced-motion today. New section goes before "A11y tests".
- `.claude/agents/reviewer.md` `ui` dimension (~l.296-336): bullet list; new bullet after the a11y paragraph, before forbidden icons.
- `.claude/commands/loop/spec.md` template `## Front surface` (~l.107): optional `Motion:` line + one Rules bullet. Nothing parses the template.
- `docs/Claude_Workflows.md` (Impeccable paragraph after the loop table) and `docs/ADAPTATION.md` (Impeccable subsection under section 13): motion mention + the stage-0 limit.
- `.claude/hooks/test-workflow-contracts.sh`: new greps after the Impeccable block.
- Line numbers come from an explorer summary; re-read before editing.

## Reusable
- Impeccable docs paragraph and contract style. `patterns/a11y.md` structure. No dependency is added (no package.json here).

## Blast radius
- Doctor: `rules-budget` counts 01-stack.md lines; `check_shipped_paths` flags any `.claude/...` path named in a doc that does not exist (new pattern files must exist before docs name them; do NOT name a `.claude/skills/...` path that is not shipped). No doctor check requires patterns to exist; the router row trusts the file.
- Contract tests cover none of the files to edit today except through the greps we add.
- Working tree was clean on `main` at the start; nothing of the user's is mixed in.

## Live DB state
n/a

## External surface
Full notes: `docs/research-cache/motion.md`, `docs/research-cache/gsap.md` (volatile, summarised page reads).
- Motion: npm `motion` 13.4.0, import `motion/react`, peers react ^18 || ^19, MIT [fetched]. Bundle: `motion` ~34kb, `m` ~4.6kb, LazyMotion+domAnimation +15kb, domMax +25kb; recommended `m` + LazyMotion [fetched, summarised]. Reduced motion: `<MotionConfig reducedMotion="user">` disables transform/layout animations but keeps opacity/colour; `useReducedMotion()` boolean [fetched, summarised]. React Compiler / StrictMode: not found; old issues (#2668 "Incompatible with React 19", #1533, #392) unread [not found].
- GSAP: `gsap` 3.15.0, `@gsap/react` 2.1.2 (`useGSAP`, peers gsap ^3.12.5, react >=17) [fetched]. Licence: "Standard no charge", all plugins free incl. ScrollTrigger/SplitText, commercial use OK; restriction: no use inside no-code visual animation builders competing with Webflow, no reverse engineering for competing products [fetched, summarised]. React: `useGSAP` reverts on unmount via gsap.context, `scope`, `contextSafe`; reduced motion via `gsap.matchMedia()` [fetched, summarised]. Lazy-import guidance and bundle size of core+ScrollTrigger: not found.

## Traps (points of vigilance for the review)
- Explorer suggestions to reject: it called Motion "CSS-based" (it is a JS library), pointed at `docs/design.md` (the path is `docs/work/<slug>/design.md`), and put versions in `settled.md` (volatile facts stay in the topic cache files, as decided for Impeccable).
- Do not pin versions in `01-stack.md` from memory: cite the cache files; "version changes are decisions" wording stays.
- `01-stack.md` must stay <= 45 lines and `rules-budget`/`rules-loaded` green; patterns must NOT be imported by `CLAUDE.md`.
- Reduced motion trap: Motion's `reducedMotion="user"` still animates opacity; the guide must not claim "all motion is disabled".
- The review check is a code-reading check: it cannot see animation feel (stage 0 uses still captures); docs must say so.
- GSAP licence restriction (visual builders) is a real clause; the gsap guide must mention it and not call GSAP "free" without it.
- Docs must not name a non-shipped `.claude/skills/...` path (doctor `shipped-paths`).
- `Motion:` declaration is grep-detected by the reviewer, not parsed: wording must be exact.

## Open questions
1. Motion with React 19 + Compiler/StrictMode: known blocking issue or not? (would settle: reading issues #2668/#1533/#392 on GitHub). Decision needed: state it as unverified in motion.md, or fetch before writing?
2. GSAP core + ScrollTrigger size and lazy-import guidance: not found. Write the guide as "measure in your app" (recommended), or research more?
3. Where the standard acceptance criterion for animated features lives: `motion.md` (explorer's pick; the reviewer `ui` bullet cites it) or the `/loop:spec` template. Which?
4. Should `01-stack.md` carry versions or only names plus a pointer to the cache files? (research suggests: names + pointer)
