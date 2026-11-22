# Prior gate (plan v1, deleted 2026-10-29 on contract amendment) — decisions to carry, not a plan
Token profile: critical

## Gate
- 2026-10-29 go
- Contract: as written
- OQ1 smoke vs headless trust → probe first; `--settings <target>/.claude/settings.json` if the installed allows are ignored; never `~/.claude.json`; piped-hook reason valid only if add/commit are absent from the denials in the same configuration.
- OQ2 ambiguous long prefixes → count as the dangerous flag.
- OQ3 G5 shim → sleeps only on `add --dry-run`.
- OQ4 `git add -p`/`-i` → denied (`failed`).
- OQ5 `checkout -B` → asks.
- OQ6 globals / `GIT_*` before `add` → deny `hides`, except `-C`, `--no-pager`, `-P`.
- OQ7 hook timeout fails open → accepted; carried to `docs/specs/harness-hardening.md`.
- OQ8 wrapped git calls → add denied, commit/switch/checkout with a dangerous flag asks; parsed-add-in-unread over-match accepted.
- 2026-10-29 K2 smoke (claude 2.1.312, `--model sonnet`, scratch target, core install, P1 present: `acceptEdits`, 31 allows). Probe with the installed settings only: `-p` printed "Ignoring 31 permissions.allow entries … workspace has not been trusted" → per OQ1, rerun with `--settings <target>/.claude/settings.json`; `~/.claude.json` untouched. In that configuration: Write `src/x.ts`, `git add src/x.ts`, `git commit -m "x"`, `pnpm test:run` → no denial, effects observed (file written, commit `x` on `feat/x`, exit 0). `git push`, `gh pr list`, `git commit -m x --amend`, `git switch -c y --discard-changes` → in `permission_denials`; the last two carry the hook's own reason in the transcript ("This commit uses --amend …", "This git switch uses --discard-changes …"), the same as the target's hook piped the same input. K2 green.
- amended 2026-10-29 Files: + `.claude/hooks/english-comments.py` (`PY_DIRECTIVE` accepts `cwk-guard-api: <n>`) and its fixtures `29-guard-api-directive-pass`, `30-guard-api-prose-deny`, found staged from outside this session; kept by the user minus a whole-file reformat. `shell_targets.py` carries the api line as a line-2 comment like the other five (replaces the docstring placement). Steps 6 and 7 rerun: gates green (545 cases), K2 green again (same 8 verdicts, hook reasons for --amend and --discard-changes).

## Execution notes
- 2026-10-29 step 1: cases G1-G9b packaged as `fixtures/_harness/git-guard.jsonl` + `run_git_guard_cases` (guard-shell's `shell-guard.jsonl` precedent: one guarded write instead of ~60), G10 as `run_git_add_lock_case`. Case ids and verdicts unchanged.
- 2026-10-29 step 1: fallback scan, line shlex fails → words lose their quotes and are classified without stopping at `--` (replaces "any quote character counts as a flag", which turned fixture `50-h2` into an ask). G9.11 still asks.
- 2026-10-29 step 1 GREEN: `test-hooks.sh` 543 cases green (G1-G10, fixtures 01-85 unchanged).
- 2026-10-29 step 3 GREEN: `shell_targets.py` carries `# cwk-guard-api: 1` as its own line inside the module docstring (the comment hook denies a `#` comment; `install.sh` reads lines, so the regex holds). `test-install.sh` and `test-workflow-contracts.sh` green.
- 2026-10-29 step 4 GREEN (K1 docs), step 5 refactor, step 6 gates: test-hooks 545 green, kit-doctor no divergence, test-install green, contracts green.
- 2026-10-29 step 7: K2 green (see `## Gate`). Observed while preparing it, for review: the add dry-run runs in the hook's base dir, so `cd X && git add f`, a file created earlier in the same command, or `git -C $T add f` (variable unexpanded) → `failed` deny. Fail-closed, inside the contract (args verbatim; `$` in `-C` is not an add arg).

# Gate of plan v2 (amendment 1, deleted 2026-10-29 on amendment 2) — decisions to carry
## Gate
- 2026-10-29 go
- Contract: as written (amendment 2026-10-29: P2 git amendment, P2 shell rm -r, hold-back removal); R-OQ2 applied after the go: "inside stays deny" → "a protected root stays deny, a protected subtree keeps its ask".
- Prior gate OQ1-OQ8 and the K2 method carried from `prior-gate.md`.
- R-OQ1 rm -r outside the project → no hook decision (X22.10).
- R-OQ2 → spec wording amended as above (X22.05, X22.06).
- R-OQ3 rm -r on a plain file asks (X22.03).
- R-OQ4 `settings.local.json` out of scope, one sentence in ADAPTATION §15 (K1c).
- R-OQ5 cap: every commit/switch/checkout asked (G11.07b).
- R-OQ6 P1 twin in K1b only.
- R-OQ7 K2b probes the matcher on backslash-newline.
- R-OQ8 minors in (header, `failed` wording, `.gitignore` comment, back-fill message); bare `credentials` dropped; follow-ups out: back-fill list's 9 entries, quoted `">"` redirection, heredoc-apostrophe main-parse fail-open.
- 2026-10-29 EXECUTE (amendment) done. Step 7 gates green: `test-hooks.sh` 592 cases, `kit-doctor.py` no divergence, `test-install.sh`, `test-workflow-contracts.sh` (K1b, K1c). Note: run inside a `$( … )` capture, `test-hooks.sh` W1 sees an inherited `trap -- '' SIGTSTP` and fails; run directly it is green (harness sensitivity to the caller, not this change).
- 2026-10-29 K2 rerun (claude 2.1.312, `--model sonnet`, `--settings <target>/.claude/settings.json`, core install: `acceptEdits`, 31 allows, no held-back line): Write `src/x.ts`, `git add src/x.ts`, `git commit -m "x"`, `pnpm test:run` → no denial, effects observed (commit `x` on `feat/x`); `git push`, `gh pr list`, `git commit -m x --amend`, `git switch -c y --discard-changes` → in `permission_denials`, the last two with the hook's reasons ("This commit uses --amend (it rewrites history, …)", "This git switch uses --discard-changes …"). K2 green.
- 2026-10-29 K2b: `git add \⏎  src/x.ts` sent as two lines → not denied, staged: the matcher treats a continuation as one call under `Bash(git add *)` (the pre-fix G11.01 bypass was auto-approved). Promoted to `docs/research-cache/claude-code-permissions.md`.
