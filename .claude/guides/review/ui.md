# Review checklist — `ui`

Read by a `reviewer` assigned `ui` (`.claude/agents/reviewer.md`). Design conformance, accessibility and feedback states.

- [ ] **The diff implements the retained design.** If `docs/work/<slug>/design.md`
      exists, read it: screens, states, edge cases and user-facing copy must
      match. A screen silently built differently from what was validated is a **Major**
      (Critical if it drops an acceptance criterion). Say which section diverges.
      **The document is the reference, never the canvas it links to**: an artboard
      edited after the gate was validated by nobody. Do not open the canvas URL.
- [ ] **Design system respected**: components come from `src/components/ui/`; any
      new component in the diff is justified in `design.md` or it is a Major.
      Tokens, not hardcoded colors/spacing (`docs/design-system.md`).
- [ ] React Query: `isPending` + `isError` + empty + `isFetching` (data kept on refetch)
- [ ] A hook whose **key carries a filter, a sort or a page** and no
      `placeholderData`: the list collapses to the loading state on every change
      (`patterns/react-query.md`, "When the key changes"). **Minor**, **Major** on
      a list the user types into — it is the "keep data on refetch" rule failing
      exactly where it is visible
- [ ] Forms: `label`+`id`, `aria-invalid`, `role="alert"`, anti double-submit (`isPending`)
- [ ] Logs in the technical language, user messages in the user language
      (`.claude/rules/03-conventions.md`), no raw error exposed
- [ ] **Semantic HTML — the half no rule can see.** `jsx-a11y` already fails the
      build on `onClick` over a `<div>` and on an `<a>` with no `href`, so do not
      re-report those. What is yours: an **action** wired to an `<a href>` with a
      `preventDefault` (it breaks middle-click, ctrl-click and the back button)
      and a **navigation** driven by a `<button>` + `navigate()` (invisible to a
      crawler, impossible to open in a new tab) — both **Major**, they are broken
      behaviour, not tag taste. Then, as Minor: a `<div>` where
      `<article>`/`<nav>`/`<aside>`/`<table>` exists, repeated elements not in a
      `<ul>`/`<ol>`, and a `<section>` with neither heading nor `aria-label`
      (`.claude/rules/03-conventions.md`, `templates/page.md`).
- [ ] **A11y beyond what the lint sees.** Same rule as above about `jsx-a11y`:
      its static defects (missing `alt`, unnamed icon button) are already build
      failures — do not re-report them. What no rule catches,
      and what this dimension owns: focus returned to the trigger after a modal
      or menu closes, keyboard navigation inside a widget claiming a `role`
      (`menu`, `tablist`, `combobox`), a live region mounted at the same time as
      its content, heading levels skipping, and an accessible name that exists
      but says nothing (`aria-label="button"`). Shapes: `.claude/skills/patterns/a11y.md`.
- [ ] **Animation conformance** (only when the diff animates something; read the
      spec's `Motion:` line and `docs/work/<slug>/design.md`; GSAP counts as
      requested only by a `Motion: gsap` line, or a design.md that names GSAP with
      its reason). Each of these is
      **Major**:
      GSAP not requested by the spec or design.md is Major,
      both libraries in one component (Motion and GSAP) is Major,
      and an animated feature without `prefers-reduced-motion` handling is Major.
      Check the diff against the block "Acceptance criteria for animated
      features" in `.claude/skills/patterns/motion.md`, and `patterns/gsap.md` when
      GSAP is declared. Still captures cannot show animation feel: review the code,
      say what was not observed.
- [ ] **Forbidden icons** (`.claude/rules/09-icons.md`): no star, rocket or
      lightning icon/emoji anywhere in the diff — UI, imports (`Star`, `Stars`,
      `Sparkle`, `Sparkles`, `Rocket`, `RocketLaunch`, `Zap`, `Bolt`,
      `LightningBolt`), user-facing text, labels, toasts. **Major.**
