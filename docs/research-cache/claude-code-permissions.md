---
topic: claude-code-permissions
checked: 2026-10-28
stability: volatile
sources:
  - https://code.claude.com/docs/en/permissions.md
  - https://code.claude.com/docs/en/permission-modes.md (first 100000 of 117027 chars)
  - https://code.claude.com/docs/en/hooks.md (chars 0-200000 of 282369)
  - https://code.claude.com/docs/en/hooks-guide.md
---

## 1. `acceptEdits`: what it auto-approves
File create/edit in the working directory, plus these Bash commands: `mkdir`, `touch`, `rm`, `rmdir`, `mv`, `cp`, `sed`. "Auto-approval applies only to paths inside your working directory or `additionalDirectories`" (symlink check applies too). Except `touch`, they also pass when prefixed by safe env vars (`LANG=C`) or wrappers (`timeout`, `nice`, `nohup`). Still prompts: paths outside scope; writes to protected paths (`.git`, `.claude`, except Claude's own `.claude/worktrees/`); recognized critical-path `rm`/`rmdir`; `touch` with options/globs/wrapper; every other Bash command except the built-in read-only set. Source: permission-modes.md, "acceptEdits mode" (permissions.md mode table says "common filesystem commands such as mkdir, touch, mv, cp").

## 2. Bash rule matching and compound commands
- Rules match the whole command text, `*` = any text. Recognized separators: `&&`, `||`, `;`, `|`, `|&`, `&`, newline. "Every subcommand must be allowed" (by an allow rule or read-only status), so `Bash(git add *)` does NOT approve `git add x && rm -rf y` (the `rm` part still needs its own approval).
- Deny and ask rules fire if ANY subcommand matches, including inside subshells, `$(...)`, and `for` bodies.
- `cmd &&` with nothing after: unparseable, not split, allow rule does not approve.
- Wrappers stripped before matching (fixed, not configurable): `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, zsh `noglob`; bare `xargs` (no flags); leading known-safe env assignments (allow rules do not match past other vars; deny/ask match past any assignment). `npx`, `docker exec`, `devbox run`, etc. are NOT stripped.
- Trailing ` *` (with space) also matches the bare command; the space is part of the rule (`Bash(ls *)` does not match `lsof`).
- `Bash(git commit -m *)` vs `git commit -m "x" --amend`: `*` stands for any text, so yes it matches (inferred from the wildcard rule "the `*` stands in for whatever text is in its place", docs example `Bash(git log * main)` matches `git log --output=<file> main`). No flag-aware matching is documented.
- Deny/ask are not a boundary: `Bash(git push *)` does not stop `git -C . push`, `git -c k=v push`, `git 'push'`; `Bash(rm *)` does not stop `/bin/rm` or `bash -c 'rm ...'`.
- Output redirects (`> f`) add a check against Edit rules, protected paths and working dirs; a Bash allow rule covers the command, not the target.
- Deny > ask > allow; an allow rule cannot carve an exception out of a deny, a matching ask rule prompts even when a narrower allow matches.

## 3. Hook decision precedence
- PreToolUse hooks run before the permission prompt. Hook `allow` does not bypass rules: "a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned `allow` or `ask`." So a hook `allow` loses to a deny rule and to an ask rule; it also still leaves prompts for network-path reads, `requiresUserInteraction` MCP tools, `always_ask` SDK tools, org-ask connector tools.
- Multiple hooks, different decisions: "precedence is `deny` > `defer` > `ask` > `allow`." (hooks.md). Hooks run in parallel.
- Hook `deny` (or exit 2) blocks the call. Hook `ask` = "show the user the normal permission prompt" (hooks-guide). Hook deny beating an allow RULE: follows from deny-first; docs state it for hooks in general ("A call that a PreToolUse hook blocked stays blocked").
- Hook `ask` vs an allow rule / `acceptEdits`: not stated in one sentence. Docs: "A call that a PreToolUse hook ... would prompt for still prompts you" (permissions.md, in the mod context) and permission-modes says Claude Code does not add the "don't ask again" option to prompts forced "by a hook". Reading: hook ask forces the prompt. Not verified by an explicit allow-rule/acceptEdits example.
- `defer` only works in `-p` non-interactive mode.

## 4. Exit code 127 / crashed hook
Only exit 2 blocks (even if JSON said allow). Exit 1, 127 (script missing/not executable) and any other non-zero code are non-blocking errors: "The action goes ahead", i.e. falls through to the normal permission flow. A timed-out hook on PreToolUse also does not block. Exit 0 with no output = no decision, normal flow. Opt-in fail-closed: hook handler field `"onFailure": "block"` (then can't start / non-0-or-2 exit / timeout / invalid output all block). Windows without Git Bash: any code other than 0 or 2 counts as failure. Source: hooks.md exit-code section (via fetch summary, not read verbatim).

## 5. Are hook-process / Bash-child writes gated by PreToolUse?
Not stated in any page read. PreToolUse fires per tool call, matched by tool name. By construction a file written by a hook script or by a child of an allowed Bash command is not a separate tool call. Docs point to sandboxing for enforcement independent of command text ("For filesystem and network enforcement that doesn't depend on the command text, use sandboxing"). Treat as: only tool calls are gated (inference, not a documented sentence).

## 6. Built-in read-only Bash allowlist
Yes, built-in, not configurable, runs without prompt in every mode: includes `ls`, `cat`, `echo`, `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, and "read-only forms of `git`" (full list not enumerated in the page). To force a prompt add an ask/deny rule. Unquoted globs allowed only where every flag is read-only. Prompts anyway: unquoted glob with write/exec-capable-flag commands (`find`, `sort`, `sed`, `git`), `cd` into another dir + `git`, unparseable commands, commands over 10000 chars, writes to `PATH`/`IFS`. `find` with `-exec`, `-delete`, `-rm`, `-fprint`, `-files0-from` is NOT approved by a `find *` prefix rule (prompts in Manual mode). Read-only classification is flag-based ("read-only forms of git"), but the exact status of `sed -n` and `git diff --output=` is not documented on these pages (docs example shows `git log --output=<file> main` matches a PATTERN rule, which is about rules not the read-only set).

## Not found
- No sentence on whether files written by hook scripts / Bash children are subject to PreToolUse (inference only).
- No explicit example of hook `ask` overriding an allow rule or `acceptEdits`.
- No enumerated full read-only list; no statement on `sed -n` or `git diff --output=` classification.
- Last 17k chars of permission-modes.md and last 82k of hooks.md unread; exit-code text came from a fetch summary.

## Hook `ask` vs `acceptEdits` and allow rules — measured 2026-10-28 (guard-writes spike)
Claude Code 2.x, headless `claude -p --permission-mode acceptEdits --output-format json --max-turns 2 --tools <tool>`, scratch git repo, a PreToolUse hook that logs and returns `ask`; each case paired with a control run without the hook. Headless cannot answer a prompt, so "asked" shows as an entry in `permission_denials`. [measured]
| Case | Hooked | Control (no hook) |
| --- | --- | --- |
| (a) Write `vite.config.ts` | hook ran, denied (asked), file absent | file written |
| (b) Bash `git commit -m x --allow-empty [--amend]`, allow rule `Bash(git commit -m *)` via `--allowedTools` | hook ran, denied (asked), HEAD unchanged | committed, **`--amend` last included** |
| (c) Bash `sed -i 's/a/b/' vite.config.ts` (acceptEdits' own Bash auto-approval) | hook ran, denied (asked), file unchanged | file edited |
- **A hook `ask` overrides both `acceptEdits` (Write and its auto-approved Bash verbs) and an allow rule.** P2's asks are effective under P1.
- `Bash(git commit -m *)` matches a trailing `--amend`: confirmed, the allow list is not the guard.
- In `-p`, the allow rule written in the scratch project's `.claude/settings.json` was **not** applied (even `git commit -m y --allow-empty` was denied) while `--allowedTools` was; likely the untrusted-workspace rule for headless runs. A headless smoke of installed settings (light-permissions-git) must account for it.
