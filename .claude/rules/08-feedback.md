<!-- budget: 30 lines · /kit:doctor rules-budget -->
# Feedback States

- Initial pending: full loading state.
- Refetch: keep data visible with a discreet `isFetching` indicator.
- Changed key: keep previous data via `placeholderData`, mark region stale.
- Disabled query: render “not selected”; it is pending but not loading, so branch
  on `isLoading` when `enabled` can be false.
- Always handle error and empty. Log technical English; map error code to the
  user language. Never show raw errors.
- Mutation pending disables repeat submission.

<!-- FILL: actual state/loading component names. -->

Read `.claude/skills/patterns/feedback.md` when creating loading/error/empty or
toast UI, and `patterns/react-query.md` when a query key changes.
