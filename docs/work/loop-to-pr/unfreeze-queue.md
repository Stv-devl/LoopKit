# Unfreeze queue: loop-to-pr

Token profile: critical

## U1 — LP59.3 (.claude/hooks/test-hooks.sh:5486-5492)

- Reason: the round-5 contract amendment (plan `## Gate`, "Review round 5 route") drops the raw-text
  `it(`/`test(` check. LP59.3 pinned that check alone: U2 holds the string `"it('inner', () => {})"`,
  its brackets nest, so U2 is no longer ambiguous. The Edit of U3 is still denied (U3 is neither a
  row nor listed), but with the not-listed reason, so the `ambiguous` needle fails. Only red case
  of the full suite (3229, 1 failure).
- Old: `# LP59.3 (N1, the raw check alone): the brackets nest, but a string of U2 holds \`it(\`.`
  … `lp4_edit LP59.3 deny "$p" "$x" "$o3" "$n3" ambiguous`
- New: `# LP59.3 (FP, round-5 amendment): a string of U2 holding \`it(\` no longer makes it ambiguous;`
  `# the Edit of non-listed U3 is still denied, as not listed.`
  … `lp4_edit LP59.3 deny "$p" "$x" "$o3" "$n3" "neither a plan-gate row nor listed"`
- Hunk: needle `ambiguous` → `neither a plan-gate row nor listed` (verdict unchanged: deny), comment
  line rewritten. Plan line 551: LP59.3 reworded to match.
  Approved 2026-11-20, applied.

## Round 6 batch (lift removed, plan `## Gate` "Review round 6 route")

Reason for all: the `U2!` lift is removed; the ambiguity deny text now names
`python3 .claude/hooks/loop-record.py --clear` and no marker. Full suite: 8 failures in 3244 cases,
exactly these.

| id | where | old | new | kind |
|---|---|---|---|---|
| U2 LP54 | test-hooks.sh:5341-5342 | needle `'U2!'` | needle `'loop-record.py --clear'` | needle |
| U3 LP54.2 | test-hooks.sh:5349 | `lp_freeze LP54.2 pass …` (U2! lifts, Edit of U3 passes) | verdict `deny`, needle `'loop-record.py --clear'` | verdict (lift gone) |
| U4 LP62.8 | test-hooks.sh:5620 | `lp5_fp LP62.8 … '    render(<li>1) Adresse</li>)'` expects pass | verdict `deny`, needle `'loop-record.py --clear'` | verdict (NC two-direction rule: `1)` ends the char span early) |
| U5 LP63 | test-hooks.sh:5630 | `'no marker lifts it' 'lifts it with'` | `'loop-record.py --clear' 'lifts it with'` | needle |
| U6 LP63.2 | test-hooks.sh:5639 | same | same | needle |
| U7 LP63.3 | test-hooks.sh:5647 | same | same | needle |
| U8 LP65 | test-hooks.sh:5692 | same | same | needle |
| U9 LP65.2 | test-hooks.sh:5698 | same | same | needle |
