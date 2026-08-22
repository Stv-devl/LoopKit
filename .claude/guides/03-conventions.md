# Conventions — rationale

Read when changing `.claude/rules/03-conventions.md`. Not loaded at session start.

## Why the SOLID section names shapes instead of principles

The five-word summary this section used to be — "one job, compose, small
interfaces, abstractions" — is true of every codebase and actionable in none. It
was also the only rule in the kit with no enforcer named, which is how a
principle becomes decoration: everyone agrees with it and nobody can point at a
diff and say it is violated.

So each row names what the violation looks like **here**, and who catches it. Two
of the five are already carried by the layering and by
`enforce-architecture.py` — listing them is about the seam, not a second check.
The remaining three are review checkboxes and nothing else, because no hook can
decide them from an Edit delta.

## Why injection is restricted rather than encouraged

"Depend on abstractions" applied literally produces an interface and a container
in front of every repository. Inside a feature, the module boundary already **is**
the seam: the abstraction is the repository's signature, and `vi.mock` swaps it
in tests. A second seam there buys nothing and costs a level of indirection on
every read.

Injection earns its keep only where the layer arrow would otherwise point the
wrong way — shared leaf code or a route helper needing feature behaviour. That is
also ISP done right: one method, named for one need.

## Why a plain container is the right answer sometimes

A `section` without a heading or an `aria-label` is exposed as a generic
container — so it is a plain wrapper that claimed otherwise. A wrapper with no
name to give should stay a plain wrapper. The lint has no opinion here:
`jsx-a11y` checks accessibility defects, not the choice of tag, so this one lives
or dies on review.

## Why manual memoization is a Major and not a Minor

Adding memoization back to "help" the compiler is the failure mode the rule
exists to prevent, and it is self-reinforcing: the hand-written version hides
whichever component the compiler actually skipped, so the real bail-out never
gets found. The measurable signal is `pnpm lint` naming the bail-out — a
`useMemo` written around it removes the symptom and keeps the cause.
