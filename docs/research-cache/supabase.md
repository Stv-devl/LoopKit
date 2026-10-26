---
topic: supabase
checked: 2026-08-22
stability: pinned
sources:
  - addons/supabase/skills/patterns/supabase-client.md (shapes kept from the pattern before 2026-10, not re-fetched)
---

SDK shapes behind `addons/supabase/skills/patterns/`. Re-check against
supabase-js when its major version changes.

- `supabase.auth.onAuthStateChange((event, session) => …)` returns
  `{ data: { subscription } }`; the cleanup is
  `return () => data.subscription.unsubscribe();`.
- The gateway wraps it as `onChange: (event: string, session: unknown) => void`;
  the repository reads `(_event, session)`.
- `supabase.removeAllChannels()` returns
  `Promise<('ok' | 'timed out' | 'error')[]>` — one result per channel, so a
  partial failure is visible.
