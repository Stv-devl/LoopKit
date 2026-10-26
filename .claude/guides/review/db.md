# Review checklist — `db`

Read by a `reviewer` assigned `db` (`.claude/agents/reviewer.md`). 

- [ ] **Supersession**: for any object redefined by stacking migrations
      (`CREATE OR REPLACE`), the new version is diffed against the **latest**
      prior definition — not the one the artifact cites. A silently reverted
      improvement is **Critical**.
- [ ] Authorization and grants: new tables are covered by the barrier
      `.claude/rules/06-database.md` names (row-level security, API middleware…);
      new functions have the execute rights their callers need.
- [ ] Nullability matches reality: a column the code reads as non-null is
      declared and populated as such; Zod `.nullable()` where the column is.
- [ ] Indexes for the queries the diff introduces; no unindexed scan on a hot path.
- [ ] Cron/trigger paths: who else writes the same state? Does the change create a
      second writer, or a job that can never fire?
- [ ] Migration is a file in the migrations folder, never inline SQL run by hand.
