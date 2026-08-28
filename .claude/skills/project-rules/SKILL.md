---
name: project-rules
description: Route implementation and review work to the exact LoopKit pattern, template, or cold guide needed for architecture, state, testing, UI feedback, accessibility, gates, and token-budget decisions. Use when creating or reviewing application code, tests, project tooling, CI, or loop orchestration and a hot rule points here.
---

# Project rules router

Read only the route matching the current write or decision:

| Work | Read |
| --- | --- |
| Bootstrap shared primitives/tooling/CI | `../templates/lib-core.md`, `tooling-config.md`, `ci.md` |
| Create feature layers | `../templates/feature.md`; architecture authority remains `../../rules/02-architecture.md` |
| Create component/page | `../templates/component.md` or `page.md`; interactive UI also `../patterns/a11y.md` |
| Query, URL, store, local state, Context | one of `../patterns/react-query.md`, `url-state.md`, `zustand.md`, `local-state.md`, `context.md` |
| Write unit/repository/hook/component tests | `../patterns/tests.md`; gateway query construction also `../patterns/msw.md` |
| Create feedback/toast UI | `../patterns/feedback.md` |
| Need a shared guard seam | `../patterns/guards.md` |
| Argue about a rule or exception | matching cold guide in `../../guides/` |
| Audit mutation strength | `../../commands/audit/mutation.md` and `../../guides/05-testing.md` |

Never load every pattern “for completeness.” Rules decide; patterns implement;
guides explain. If the requested surface has no route, inspect the nearest
template index before inventing a convention.
