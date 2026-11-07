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

## Allow matching on B2 forms and ask reasons in the model — measured 2026-11-04 (harness-prompts D0)
Claude Code **2.1.318** (plan pinned 2.1.317; the session upgraded), `claude -p --output-format stream-json --verbose --include-hook-events --no-session-persistence --model sonnet --max-turns 2 --setting-sources project --settings <json> --tools Bash,Edit,Read --permission-prompts none`, scratch repo `/tmp/claude-1000/hp-db/repo` (not trusted, no `.claude/settings.json`). Every valid run's `tool_use.input.command` equals the pinned form. Runner and transcripts: `/tmp/claude-1000/hp-db/`. [measured]
- **DB1** — a PreToolUse Bash hook returning `ask` with reason `NONCE-7f3a9 reason text`: the hook event fired, the call was denied (no approval surface) and the Bash `tool_result` ends with `What required approval: NONCE-7f3a9 reason text`. **The ask reason reaches the model.** The `default` variant (no `--permission-prompts`) is **void**: `-p` exits 1 with "Input must be provided either through stdin or as a prompt argument". The interactive case (user answers the prompt) is not measurable headless.
- **DB2** — `--permission-mode acceptEdits`, no hook, Edit of `.claude/hooks/x.sh`: in `permission_denials`, file unchanged. **`acceptEdits` does not auto-approve an Edit under `.claude/`.**
- **DB3** — allow `Bash(bash .claude/hooks/test-probe.sh)` and, separately, `Bash(bash .claude/hooks/test-probe.sh *)`: both `bash .claude/hooks/test-probe.sh` and `bash .claude/hooks/test-probe.sh 2>&1` ran silently under **each** allow. Control (no allow): `… 2>&1` denied. **A trailing `2>&1` is matched by the bare allow.**
- **DB4** — allow `Bash(bash .claude/hooks/test-probe.sh *)`: `bash .claude/hooks/test-probe.sh x \` (dangling backslash) and `bash .claude/hooks/test-probe.sh $'a\'b'` were **denied** (not matched; they would prompt).
- **DB5** — same allow: `bash .claude/hooks/test-probe.sh $(( $(touch …/marker; echo 1) ))` and `bash .claude/hooks/test-probe.sh <(touch …/marker2)` were **denied**, no marker created. The native matcher does not let `$((…$(…)…))` or `<(…)` through a ` *` allow; B0f still closes the hook side.
- **DB6** — Claude Code 2.1.318, allow `Bash(bash .claude/hooks/test-probe.sh *)`: `{a,b}`, `--x={a,b}`, `pre{a,b}post`, `{a..c}` words were denied (not matched), also under acceptEdits; `pnpm test:run {--clearCache,…}` under `Bash(pnpm test:run *)` denied. Runner `/tmp/claude-1000/fb-brace/run.sh`. [measured 2026-11-05]

## Path-taking options of the B2 tools — inventory 2026-11-04 (harness-prompts B0c)
`tsc --all` (typescript 6.0.3), `vitest --help`, `--help --coverage`, `--help --cache` (vitest 4.1.11), `playwright test --help` (@playwright/test 1.63.0), installed in a scratch dir. One verdict per option that takes a path or writes. [measured]
**Retired (review 5, user decision A): the argument allows of these runners (`pnpm test:run *`, `vitest run *`, `tsc --noEmit *`, `playwright test *`…) are no longer shipped; only the exact no-argument forms stay allowed, and the safe-option tables below only add asks under a user's own allow.**
**Rule (review 2, user decision): the hook holds a safe-option allowlist, not a blocklist.** For vitest, vite, playwright test, tsc and their package scripts (`test:run`, `test:coverage`, `typecheck`, `build`), a word starting with `-` passes only if spelled exactly as a listed safe option (its value as `=value`, or the next word) or as a listed checked option below. Anything else asks, its reason quoting the word: a short bundle (`-wc`, `-xu`), `---x`, an empty `=`, an unlisted dotted key, a value on a boolean (`--clearCache=true`), an unknown option. `--reporter`, `--coverage.reporter`, `--pool`, `--environment` take only built-in names (comma lists allowed), never a path or a custom name. Kept: kebab aliases of checked options, tsc case and single-dash folding, the recorded `--tsconfig` loader; a tsc `@file` asks, so does `--diff` (a loader), a `vite`/`pnpm build` positional (project root), an unquoted word starting with a glob char, and `kit-doctor.py <arg>`. mri applies to vite, vitest and their scripts (`test:run`, `test:coverage`, `build`): their options do not consume a following word starting with `-`. Commander (playwright) and tsc (and `typecheck`) do consume it, so a `-`-leading word after a name option such as `--reporter` is its value and asks. A script of unknown parser (`lint`, `e2e`) checks that word both ways: as the option's value and as its own option. A listed script uses the safe table of its tool, so `--reporter` names are per tool. Vitest 4.1.11 built-in reporters: default, agent, minimal, blob, verbose, dot, json, tap, tap-flat, junit, tree, hanging-process, github-actions, html (resolves to @vitest/ui); playwright 1.63.0: list, line, dot, json, junit, html, blob, github, null, perfetto. A glob word consumed as an option's value, or leading a script's arguments (listed or not), asks.
- **ask, found by the review:** `--experimental.fsModuleCachePath` (vitest runs `rm -r` on it on a cache clear or a foreign `_metadata.json`), `--execArgv` (node flags: `--import`, `--require` run code), `--typecheck.checker` (runs the named binary), tsc `--incremental` (writes a `.tsbuildinfo`).
- **tsc writers, hook-covered:** `--outDir`, `--outFile`, `--declarationDir`, `--tsBuildInfoFile`, `--generateTrace`, `--generateCpuProfile` (flag-w/flag-r); `--init` (cfg-write ask); `-p/--project` (cfg). `--out` is listed but refused by tsc 6 (`TS5102: Option 'out' has been removed`): no row.
- **tsc non-writers:** `--rootDir`, `--rootDirs`, `--baseUrl`, `--paths`, `--typeRoots`, `--types`, `--mapRoot`, `--sourceRoot`, `--plugins`, `--listFiles`, `--listEmittedFiles`, `--explainFiles`, `--traceResolution`, `--showConfig`, watch options: they read or print, yet only the listed ones pass (`--listFiles`, `--explainFiles`, `--traceResolution`, `--showConfig`).
- **vitest writers, hook-covered:** `--outputFile[.<reporter>]` (flag-w), `--coverage.reportsDirectory`, `--attachmentsDir` (flag-r), `-r/--root`, `-c/--config` (not attached: vitest rejects `-cdocs/v.ts`, which asks as an unlisted word; only playwright's commander attaches), `--dir` (cfg), kebab forms of the first segment (`--attachments-dir`, `--clear-cache`), `-u/--update` (snapshot ask, also `-u=all`), `--coverage.thresholds.autoUpdate` (cfg-write ask).
- **vitest writers, now covered:** `--coverage.htmlDir <path>` (flag-r) and `--clearCache` (cache-clear ask), added by the review amendments.
- **vitest non-writers:** `--coverage.customProviderModule <path>` (loader: same as running a test), `--mergeReports [path]` (reads blobs), `--exclude`, `--coverage.include/exclude`, `--project <name>`, `--configLoader`: read-only, and pass only when listed (`--exclude`, `--coverage.include/exclude`, `--project`). `--diff <path>` is a loader that runs the file: not listed, it asks. `-u` accepts `none`; `--update=none` still asks (plan rule `--update[=*]`).
- **playwright writers, hook-covered:** `--output <dir>` (flag-r), `--last-failed-file <file>` (flag-w), `-c/--config` (cfg, also attached `-cdocs/p.ts`), `-u/--update-snapshots[=mode]` (snapshot ask, `=none` passes). `--update-source-method` acts only with `-u` (already asked).
- **playwright non-writers:** `--tsconfig <path>` (loader), `--test-list[-invert] <file>` (read), `--reporter`, `--trace <mode>`, `--shard`, `--last-failed`, `--only-changed`: read-only; the listed ones pass (`--tsconfig`, `--reporter` as a bare name, `--trace`, `--shard`, `--last-failed`).
