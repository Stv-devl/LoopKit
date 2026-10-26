# Review checklist — `security`

Read by a `reviewer` assigned `security` (`.claude/agents/reviewer.md`). 

- [ ] The server-side authorization barrier (`.claude/rules/01-stack.md`) covers
      every touched table/endpoint — a client-side check is not a barrier
- [ ] Privileged keys never exposed client-side; secrets via env, not hardcoded
- [ ] Zod validation on all inputs; no unparameterized query
- [ ] Auth/guards correct; no data leak between users
