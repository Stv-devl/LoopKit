---
topic: claude-code-permissions
checked: 2026-11-02
stability: volatile
sources:
  - https://code.claude.com/docs/en/permissions.md
  - https://code.claude.com/docs/en/permission-modes.md (first 100000 of 117027 chars)
  - https://code.claude.com/docs/en/hooks.md (chars 0-200000 of 282369)
  - https://code.claude.com/docs/en/hooks-guide.md
  - https://code.claude.com/docs/en/sandboxing.md (chars 0-100000 of 107564, fetched 2026-11-01)
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
- Output redirects (`> f`) add a check against Edit rules, protected paths and working dirs; a Bash allow rule covers the command, not the target. `tee` targets are checked the same way (v2.1.269+).
- Deny > ask > allow; "An allow rule can't carve an exception out of a deny rule" (permissions.md), and a matching ask rule prompts even when a narrower allow matches.

## 3. Hook decision precedence
- PreToolUse hooks run before the permission prompt. Hook `allow` does not bypass rules: "a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned `allow` or `ask`." So a hook `allow` loses to a deny rule and to an ask rule; it also still leaves prompts for network-path reads, `requiresUserInteraction` MCP tools, `always_ask` SDK tools, org-ask connector tools.
- Multiple hooks, different decisions: "precedence is `deny` > `defer` > `ask` > `allow`." (hooks.md). Hooks run in parallel.
- Hook `deny` (or exit 2) blocks the call. Hook `ask` = "show the user the normal permission prompt" (hooks-guide). Hook deny beating an allow RULE: follows from deny-first; docs state it for hooks in general ("A call that a PreToolUse hook blocked stays blocked").
- Hook `ask` vs an allow rule / `acceptEdits`: measured below (hook ask wins).
- `defer` only works in `-p` non-interactive mode.

## 4. Exit code 127 / crashed hook
Only exit 2 blocks (even if JSON said allow). Exit 1, 127 (script missing/not executable) and any other non-zero code are non-blocking errors: "The action goes ahead", i.e. falls through to the normal permission flow. A timed-out hook on PreToolUse also does not block. Exit 0 with no output = no decision, normal flow. Opt-in fail-closed: hook handler field `"onFailure": "block"` (then can't start / non-0-or-2 exit / timeout / invalid output all block). Windows without Git Bash: any code other than 0 or 2 counts as failure. Source: hooks.md exit-code section (via fetch summary, not read verbatim).

## 5. Are hook-process / Bash-child writes gated by PreToolUse?
Not stated in any page read. PreToolUse fires per tool call, matched by tool name. A file written by a child of an allowed Bash command is not a separate tool call. permissions.md: "For filesystem and network enforcement that doesn't depend on the command text, use sandboxing." sandboxing.md (2026-11-01): hooks run outside the sandbox (see section 9).

## 6. Built-in read-only Bash allowlist
Yes, built-in, not configurable, runs without prompt in every mode: includes `ls`, `cat`, `echo`, `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, and "read-only forms of `git`" (full list not enumerated in the page). To force a prompt add an ask/deny rule. Unquoted globs allowed only where every flag is read-only. Prompts anyway: unquoted glob with write/exec-capable-flag commands (`find`, `sort`, `sed`, `git`), `cd` into another dir + `git`, unparseable commands, commands over 10000 chars, writes to `PATH`/`IFS`. `find` with `-exec`, `-delete`, `-rm`, `-fprint`, `-files0-from` is NOT approved by a `find *` prefix rule.

## 7. `Read(...)` deny rule path syntax and carve-outs (read 2026-11-01, permissions.md "Read and Edit", CLI 2.1.316 era)
- "Read and Edit rules both use gitignore pattern syntax with four distinct pattern types": `//path` absolute from filesystem root (`Read(//Users/alice/secrets/**)`), `~/path` from home, `/path` relative to the **project root** (settings-file-relative for project settings; in user settings `Read(/secrets/**)` means `~/.claude/secrets/**`), `path` or `./path` relative to cwd (`Read(*.env)` -> `<cwd>/*.env`).
- Bare filenames follow gitignore: "`Read(.env)` and `Read(**/.env)` are equivalent" (any depth at or under cwd). Deny/ask `Read(secrets/**)` matches a `secrets` dir at any depth under cwd; as an allow rule it is cwd-only.
- Docs examples: `Read(./.env)`, `Read(./secrets/**)`. Paste-ready example: settings-reference.md#exclude-sensitive-files (not opened).
- Deny applies when either the requested path or its symlink target matches.
- **Carve-out is possible, but with a `!` deny entry, not an allow**: "A deny or ask pattern that starts with `!` is a gitignore negation. It carves the paths it matches out of the `path` or `./path` rules listed before it. In one settings file's `deny` list, `Read(*.env)` followed by `Read(!sample.env)` blocks every file whose name ends in `.env` at any depth, except files named `sample.env`. A `!` rule listed first carves nothing out."
- Limits: carve-out reaches only rules from the **same source** (a `Read(!.env)` in project settings does not cancel a managed-settings deny); `!` is read relative to cwd even with `/`, `~/`, `//` after it, so it cannot reach rules anchored with those prefixes; it "can't reopen a file inside a directory that a rule blocks as a whole" (`Read(secrets/**)` + `Read(!secrets/public/**)` still blocks `secrets/public`).
- An allow cannot carve out of a deny: "An allow rule can't carve an exception out of a deny rule."
- Consequence for `.env.example`: `"deny": ["Read(.env)", "Read(.env.*)", "Read(!.env.example)"]` in the SAME settings file, `!` entry after the broad one, relative (no `/`, `~/`, `//`) forms. `Read(**/.env*)` then `Read(!.env.example)` is the same shape. The exact spelling was derived from the quoted `*.env`/`sample.env` example, then measured 2026-11-01 on 2.1.316 with fake files: the Read tool and `cat` denied on `.env`, `.env.local`; `.env.example` read in both. Shipped as the kit's `permissions.deny` (harness-hooks DA1).
- `.claudeignore` "has no effect".

## 7b. The `grep` wrapper of the Bash tool — read 2026-11-02 on 2.1.316 (`type grep` in the tool's shell)
- `grep` is a shell function: it runs the claude binary as `ugrep -G --ignore-files --hidden -I --exclude-dir=.git …`, so a plain `grep -r KEY .` honours `.gitignore` and skips `.env` (first measured 2026-10-30).
- It falls back to the real `command grep` when an argument matches `-*-filter*`, `-*-pager*`, `-*-view*`, `-*-format-open*`, `-*-config*`, `---*`, `-@*`, `-*-save-config*`, `-[Zz]*`, `-[!-]*[Zz]*`, `--null`, `--null-data`, or when the binary is not executable. Any form that skips the function (`command grep`, `/usr/bin/grep`, `env grep`, `xargs grep`) also reaches the real grep. `\grep` is not one of them: a leading backslash only skips an alias, never a function, so `\grep -r` still goes through the wrapper. The hook asks on it anyway (conservative, frozen rows X26.22 and X26.35); it is not a wrapper bypass.
- `prevent-destructive-commands.sh` asks on a recursive grep with `-Z`/`--null` or past the function (harness-hooks A6). Not covered, stated gap: `-z`, `--null-data` and the long-option fallbacks above.
- Version-dependent: re-read `type grep` after a Claude Code upgrade.

## 8. Does a Read/Edit deny bind Bash? (permissions.md)
"Read and Edit deny rules apply to Claude's built-in file tools, to file commands Claude Code recognizes in Bash, such as `cat`, `head`, `tail`, `sed`, and `tee`, and to the targets of Bash redirections such as `> file` and `< file`. They don't apply to a command that reads files without naming them, such as `grep -r pattern .` run from the directory that holds the file, or to arbitrary subprocesses that read or write files indirectly, like a Python or Node script that opens files itself. For OS-level enforcement that blocks all processes from accessing a path, enable the sandbox."
So `cat .env` is covered (recognized file command); `python -c 'open(".env")'`, `grep -r x .`, `node script` are not. Also: "Claude makes a best-effort attempt to apply `Read` rules to all built-in tools that read files like Grep and Glob" and @-mentions/IDE context.

## 9. Sandbox on Linux (sandboxing.md, read 2026-11-01)
- Deps: "On Linux and WSL2, the sandbox relies on these packages: `bubblewrap` ... `socat`" (`sudo apt-get install bubblewrap socat`).
- Keys: `sandbox.enabled`, `sandbox.filesystem.{allowWrite,denyWrite,denyRead,allowRead}`, `sandbox.excludedCommands`, `sandbox.autoAllowBashIfSandboxed` (default `true`), `sandbox.network.{allowedDomains,deniedDomains}`.
- Read-deny for Bash children: "You can also deny write or read access using `sandbox.filesystem.denyWrite` and `sandbox.filesystem.denyRead`, and re-allow specific paths within a denied region using `sandbox.filesystem.allowRead`." and "These paths are enforced at the OS level, so all commands running inside the sandbox, including their child processes, respect them." So `allowRead` is the `.env.example` carve-out on the sandbox side.
- Default: "read access to the entire computer, except certain denied directories. This default still allows reading credential files".
- Path syntax differs from permission rules: "Sandbox filesystem paths use standard conventions: `/tmp/build` is absolute and `~/.kube` is relative to your home directory. This differs from Read and Edit permission rules, which use `//path` for absolute and `/path` for project-relative." (Relative-path/wildcard rules are on a "Sandbox path prefixes" reference, not read.)
- Scope: "The sandbox covers shell commands only. Claude's file tools, MCP servers, and hooks run outside it." Hooks, MCP servers, status line, `apiKeyHelper` run with full access. "A `denyRead` entry doesn't stop the Read tool" (built-in tools follow permission rules).

## 10. Sandbox x permissions (permissions.md "How permissions interact with sandboxing"; sandboxing.md)
- "Paths and domains from both sandbox settings and permission rules are merged into the final sandbox configuration." Table: "`Read` and `Edit` deny rules | Block access to specific files or directories"; "`Edit` allow rules | Grant write access ... the same way `sandbox.filesystem.allowWrite` does". So a `Read` deny rule feeds the sandbox's filesystem rules (when the sandbox is enabled), and so reaches Bash children at OS level. Whether `!` carve-outs in `Read` deny translate into the sandbox is NOT stated; use `sandbox.filesystem.allowRead` for the sandbox side to be explicit.
- "When you enable sandboxing and leave `autoAllowBashIfSandboxed` at its default of `true`, sandboxed Bash commands run without prompting even if your permissions include a bare `Bash` ask rule": enabling the sandbox changes the prompting of Bash (not deny rules). Commands run outside the sandbox (excluded commands) still follow the normal flow.
- Hooks and the sandbox: PreToolUse hooks still fire per tool call; hook processes themselves are unsandboxed.

## Not found
- No sentence on whether files written by hook scripts / Bash children are subject to PreToolUse (only construction; sandboxing.md confirms hooks are unsandboxed).
- No enumerated full read-only list; no statement on `sed -n` or `git diff --output=` classification.
- Whether `Read(!x)` negations are translated into the sandbox config: not stated.
- Sandbox path-prefix reference (relative paths, wildcards in `denyRead`) and the last 7.5k chars of sandboxing.md unread; settings-reference "Exclude sensitive files" example unread.
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

## Backslash-newline continuation vs an allow rule — measured 2026-10-29 (light-permissions-git K2b)
Claude Code 2.1.312, `claude -p --output-format stream-json --max-turns 2 --tools Bash --model sonnet --settings <target>/.claude/settings.json`, installed P1 (`acceptEdits`, `Bash(git add *)`). The model sent `git add \⏎  src/x.ts` (two physical lines): **not** in `permission_denials`, the file was staged. [measured]
- The matcher treats a `\`+newline continuation as one subcommand: `Bash(git add *)` approves it. A hook must join continuations itself (a newline split would hide flags after the `\`).
