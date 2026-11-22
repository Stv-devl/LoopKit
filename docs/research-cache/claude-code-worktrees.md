---
topic: claude-code-worktrees
checked: 2026-10-28
stability: volatile
sources:
  - https://code.claude.com/docs/en/worktrees
  - https://code.claude.com/docs/en/sessions.md
  - https://code.claude.com/docs/en/hooks.md (first 100000 chars only)
  - https://claudeissues.com/issue/70466-bug-enterworktree-tool-does-not-process-worktreeinclude-gitignored-files-not-cop
---

## 1. What is `.worktreeinclude`: format, location, what it copies
A file at the **project root** named `.worktreeinclude`, in `.gitignore` syntax. "Only files that match a pattern and are also gitignored are copied, so tracked files are never duplicated." Typical content: `.env`, `.env.local`, `config/secrets.json`. So yes, gitignored `.env` files are copied from the main repo into a new worktree. Gotcha: a `**/` pattern reaches into a wholly ignored directory only if that directory matches or the first name after `**/` is in the directory path (name the directory instead: `vendor/**/config.json`). Before v2.1.239 the rule was stricter. Source: worktrees docs, "Copy gitignored files into worktrees". A third-party bug report (claudeissues #83098) claims a matched ignored directory was only partly copied (110 of 564 files), not verified here.

## 2. Only Claude-created worktrees, or also plain `git worktree add`?
Docs: "This applies to every worktree Claude Code creates with git: `--worktree` worktrees, subagent worktrees, and parallel sessions in the desktop app." Nothing in the docs makes it fire for a `git worktree add` run from Bash or a terminal: no Claude Code code path runs, so it is NOT applied (inferred from the docs' scoping, no explicit "not applied" sentence). `EnterWorktree` is NOT in the list: issue #70466 (v2.1.187, opened 2026-06-24) reports it does not copy; closed "not planned" 2026-08-07 with no maintainer reply visible. Treat EnterWorktree as not copying, unverified on a current build. With a `WorktreeCreate` hook, `.worktreeinclude` is not processed at all (copy inside the hook).

## 3. Does ExitWorktree / cleanup remove only worktrees Claude created?
Cleanup rules "apply to worktrees Claude created with git"; hook-created ones go through `WorktreeRemove`. Exit prompt: clean + unnamed session = removed with its branch; named session or dirty/extra commits/unverifiable = prompt. Periodic sweep (age > `cleanupPeriodDays`) removes only subagent and background-session worktrees; it keeps any worktree without the marker Claude Code writes into the git metadata of worktrees it creates, and keeps a worktree "you created ... yourself with `git worktree add`, even if you then ran a `--worktree <name>` session in it". So a manual `git worktree add` worktree is never swept; remove it with `git worktree remove`. The ExitWorktree tool is only named in the docs ("Claude can still exit it with the ExitWorktree tool" after resume); its exact removal semantics for a manually created worktree are not spelled out in what was read (see Not found).

## 4. `claude` started with cwd inside a manual `git worktree`: project dir, CLAUDE_PROJECT_DIR, transcripts
- Transcripts: `~/.claude/projects/<project>/<session-id>.jsonl`, `<project>` = "your working directory path with non-alphanumeric characters replaced by `-`" (truncated to 200 chars + hash). So a session launched in the worktree is keyed on the **worktree path**, not the main repo (sessions.md). Picker shows the current worktree's sessions by default; Ctrl+W widens to all worktrees of the repo. `claude --resume <id>` searches the current project and its git worktrees first.
- `CLAUDE_PROJECT_DIR`: documented only as "the project root where the session started"; the resolution rule (launch dir vs git root vs main repo) is not stated. For a session entered into a worktree mid-session (EnterWorktree) it stays at the original root; hook input `cwd` follows Claude. For desktop-app worktree sessions, settings/hooks/skills/agents/commands/.mcp.json are read from the **main checkout root** and `${CLAUDE_PROJECT_DIR}` points there, while CLAUDE.md and `.claude/rules/` load from the worktree. For a CLI launch inside a manual worktree the docs do not say; the natural reading ("where the session started") is the worktree path, UNVERIFIED.
- Docs also say: shared with the main checkout whether created by `--worktree` or `git worktree add`: the `.git` dir, project-scope plugins, "don't ask again" permission approvals (saved to the main checkout's `.claude/settings.local.json`), and read-through of untracked `.claude/skills|agents|commands` when the worktree has no `.claude/skills` dir (skills need v2.1.277+).
- Resuming: launching from inside a worktree you made with `git worktree add` re-enters it only if Claude Code can vouch for it; a launch from a subdirectory of such a worktree declines ("launch those from the main checkout").

## Not found
- Explicit statement that `.worktreeinclude` is ignored for a plain `git worktree add` (only the inclusion list above implies it).
- Where `CLAUDE_PROJECT_DIR` resolves for a CLI `claude` launched inside a manual worktree (hooks page read only through char 100000 of 282369; the "ExitWorktree" tool reference page was not opened).
- Whether current Claude Code makes EnterWorktree honour `.worktreeinclude` (issue closed not planned; docs list unchanged).
- ExitWorktree's behaviour on a worktree not created by EnterWorktree / --worktree (tools-reference page not opened).
