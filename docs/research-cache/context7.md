---
topic: context7
checked: 2026-11-18
stability: volatile
sources:
  - https://raw.githubusercontent.com/upstash/context7/master/README.md
  - https://context7.com/docs/resources/all-clients
  - https://api.github.com/repos/upstash/context7/releases?per_page=15
---

## What exact MCP tool names does the Context7 MCP server expose, and under which server name is it registered for Claude Code?
Tools (README and all-clients docs, both read 2026-11-18): `resolve-library-id` and `query-docs`.
Server name in the official Claude Code install: `context7`. Full Claude Code tool names:
- `mcp__context7__resolve-library-id`
- `mcp__context7__query-docs`

Registration commands (all-clients docs):
- Remote, HTTP, API key: `claude mcp add --scope user --header "Authorization: Bearer YOUR_API_KEY" --transport http context7 https://mcp.context7.com/mcp`
- Local, stdio: `claude mcp add --scope user context7 -- npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`
- OAuth endpoint instead of an API key: `https://mcp.context7.com/mcp/oauth` (no separate Claude Code command given).
- The README's own Claude Code route is `npx ctx7 setup --claude`, with no `claude mcp add` line. That route may register a different name (not checked). A plugin install may too, giving `mcp__plugin_<plugin>_<server>__...` (from model knowledge, not checked).

## Did a recent release rename tools?
- `@upstash/context7-mcp@4.7.3` (2026-11-17): the experimental `query-code` tool was removed and replaced by `grep-code`, `glob-code`, `read-code` and `find-symbol`. The README does not list these as core tools, so they may be gated or experimental. Not verified.
- `ctx7@0.12.2` (2026-11-17): installed rules and skills drop guidance for `query-code`, `ctx7 code` and `get-upgrade-guide`.
- The old `get-library-docs` -> `query-docs` rename is not in the 15 releases fetched. The README lists only `query-docs`. That `get-library-docs` was the older name comes from model knowledge, not checked.

## Not found
- No release note for the `get-library-docs` -> `query-docs` rename within the last 15 releases.
- The README does not mention any renames.
