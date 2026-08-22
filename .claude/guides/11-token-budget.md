# Token budget — rationale

Read when changing `.claude/rules/11-token-budget.md`, or when auditing where a
session's time and tokens actually went. Not loaded at session start.

## Dead time is not free, and sleeping is how it gets created

Measured on this kit's reference project: one agent launched five children and
waited for them with `python3 -c "import time; time.sleep(285)"`, sixteen times.
It lived 43 minutes and spent **35 of them asleep**, doing 13 network calls in
the remainder. It was the single longest agent of the session, and it was the
one doing the least.

The failure mode is subtle because the transcript looks busy: the agent narrates
*"Four of five in. Waiting"*, then *"Still actively working"*, and neither line is
a lie from its point of view. Only the timestamps show that nothing happened for
five minutes.

That measurement is the whole reason the rule has no exception. An agent that
polls is not visibly broken — it has to be caught on the clock.

## Measure before optimising the loop

Method, tools and the three wrong hypotheses that motivated it:
**`docs/measuring-the-loop.md`**. Start from `.claude/hooks/hook-timings-report.sh`
and a pass over the session transcript.

It is out of the rules on purpose — it is read once when you audit the loop, not
in the session where you fix one line, and a token-budget rule that costs context
every turn would be a poor advertisement.

## Why the two threshold families are kept apart

The status line's three markers measure **context-window** use. `workflow.py`'s
two thresholds are parsed out of the CLI's *subscription* usage and land in
`.quota-warning`. They carry the same numbers, 90 and 95, and mean unrelated
things — which is exactly how a report ends up claiming the context is full when
the quota is.

The supervisor clears all four markers at the start of every `claude` launch and
reads `.codex-ready` alone. `.token-warning` and `.token-stop-agents` are
advisory: "start no new subagent at 95%" is a rule you honour, not one a process
enforces.

One hook detail worth keeping out of the rule: `token-statusline.py` clears
`.codex-ready` on a **hysteresis at 90**, not at its own 97, so a `/compact` does
not leave a stale handoff order behind.
