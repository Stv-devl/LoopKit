# State placement — rationale

Read when changing `.claude/rules/04-state.md`. Not loaded at session start.

## Why Context and Zustand split on origin rather than scope

Both are global, so scope decides nothing. The question is who owns the value.

Context carries what arrives as **wiring** — a session read through a repository,
a locale, config injected at the composition root. It is the right answer there
precisely because those values are handed in from outside the client and change
rarely.

Zustand carries what the **user** owns and the client persists: theme, density,
whether the sidebar is folded. Putting a persisted preference in a Context means
rewriting serialisation, boot-time read and versioning by hand — which is what
`persist` already does (`patterns/zustand.md`).

The corollary is the fourth anti-pattern: a Context has no selector, so anything
that changes often and is read widely re-renders the whole tree. If you find
yourself wanting selectors on a Context, you wanted a store.

## Why the realtime row is in a table about state

A subscription is a **transport**, not a sixth place to put state — what it
produces still lands in one of the five, in practice the React Query cache.

It is listed anyway because "where does the subscription live" is asked at the
same moment as "where does this state live", and answering it in a different file
is exactly how it ends up inside a hook. Keeping the two answers adjacent is the
whole point: raw I/O to the gateway (one of the two filenames
`enforce-architecture.py` allows the data client in), the repository maps the
payload to a domain entity, the hook only wires it to the cache.

## Why "the carrier does not change the verdict" leads the section

Server data mirrored out of React Query is the single most common defect of the
four, and it is usually argued about as three separate questions — "is a store
allowed to hold API data", "can I put the user list in a Context", "is this
`useState` fine". They are one question. Naming it once, before the table,
stops the discussion from being had three times with three different answers.
