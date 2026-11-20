---
topic: claude-code-hook-input
checked: 2026-11-18
stability: volatile
sources:
  - https://code.claude.com/docs/en/hooks.md (read via fetch summaries: chars 0-100000, 60000-160000, 100000-200000, 200000-end; 294376 chars total on 2026-11-18)
  - https://code.claude.com/docs/en/agent-sdk/user-input
  - web search (issue-tracker snippets only, not opened)
---

## 1. Does PostToolUse fire for AskUserQuestion, can a matcher select it, caveats?
- Matcher: yes. PostToolUse "Matches on tool name, same values as PreToolUse"; the PreToolUse list reads: "built-in tools such as `Bash`, `PowerShell`, `Edit`, `Write`, `Read`, `Glob`, `Grep`, `Agent`, `Workflow`, `WebFetch`, `WebSearch`, `AskUserQuestion`, and `ExitPlanMode`". So matcher `AskUserQuestion` is a documented tool name.
- PostToolUse "Runs immediately after a tool completes successfully." No page sentence says "PostToolUse fires for AskUserQuestion" explicitly; the only PostToolUse + AskUserQuestion text is the `updatedToolOutput` row: "In a Cowork cloud session, Claude Code ignores this field when the tool is `AskUserQuestion` or `ExitPlanMode`, and Claude reads the original answer or plan" (which implies the hook runs on it).
- Caveats documented: AskUserQuestion is a "requires user interaction" tool: in PreToolUse, `allow` alone is not enough, it needs `updatedInput` (with `answers`). PermissionRequest hooks also receive it, and `updatedInput` is required there too. `defer` (non-interactive `-p` only) names AskUserQuestion as the typical case. A third-party issue snippet (not opened, unofficial) says a PreToolUse hook can make AskUserQuestion return empty answers while PostToolUse works; unverified.

## 2. Shape of tool_input / tool_response for AskUserQuestion in PostToolUse
- `tool_input` (hooks.md, PreToolUse tool-input table, verbatim): `questions` array "each with a `question` string, short `header`, `options` array, and optional `multiSelect` flag", example `[{"question": "Which framework?", "header": "Framework", "options": [{"label": "React", "description": "Component library"}, ...], "multiSelect": false}]`; `answers` object, example `{"Which framework?": "React"}`: "Optional. Maps question text to the selected option label. Multi-select answers join labels with commas. Claude doesn't set this field; supply it via `updatedInput` to answer programmatically".
- Agent SDK user-input doc (the shape a `canUseTool`/`updatedInput` caller RETURNS, input side): `answers` keys are the `question` text, values the option `label`; multi-select "pass an array of labels or join them with `", "`"; free text / "Other": "put the user's text in `answers[question]`" ("not the word Other"); optional `response` freeform string ("Claude receives 'The user responded: ...'"). Options may carry `preview` (TS SDK only, opt-in).
- `tool_response` for PostToolUse: hooks.md says only "The exact schema for both depends on the tool." The AskUserQuestion `tool_response` shape is NOT documented anywhere read. Whether the TUI-answered answers appear in `tool_input.answers`, in `tool_response`, or both is not documented: measure in a spike. Do not infer it from the SDK `updatedInput` shape.

## 3. Subagent identification, absence on main thread, can a subagent call AskUserQuestion?
- hooks.md common-input text (verbatim): "`agent_id` and `agent_type` tell your script which agent a hook fired in, such as a subagent, an in-process teammate, or the agent you chose with `--agent`". `agent_id`: "Unique identifier for the subagent or in-process teammate the hook fires in." `agent_type`: "Agent name (for example, "Explore" or "security-reviewer"). Present when the session uses `--agent` or the hook fires inside a subagent. For subagents, the subagent's type takes precedence over the session's `--agent` value."
- Consequences: `agent_type` is also present on the MAIN thread when the session was started with `--agent`, so its presence alone does not mean subagent; `agent_id` is documented as the subagent/teammate identifier. "Absent on main-thread calls" is implied for `agent_id` but never stated verbatim (the TaskCreated/TaskCompleted rows say "May be absent"). Other fields seen in the common table: `prompt_id`, `scratchpad_dir`, `effort`.
- Subagent AskUserQuestion: Agent SDK doc, Limitations: "`AskUserQuestion` is not currently available in subagents spawned via the Agent tool". hooks.md says nothing on it. (SDK doc, not the interactive CLI doc; CLI behaviour unverified.)

## 4. Common input fields; is cwd the project root?
- Table (verbatim): `session_id` "Current session identifier"; `transcript_path` "Path to conversation JSON. The transcript file is written asynchronously and may lag the in-memory conversation..."; `cwd` "Current working directory when the hook is invoked"; `permission_mode` one of `"default"`, `"plan"`, `"acceptEdits"`, `"auto"`, `"dontAsk"`, `"bypassPermissions"`; `hook_event_name` "Name of the event that fired". Also `prompt_id`, `scratchpad_dir`, `effort`.
- No guarantee of project root. Verbatim: "`cwd` follows Claude: the `cwd` field in the hook's input JSON is the worktree root after Claude enters a worktree, and the new directory after Claude runs `cd`." If the directory no longer exists, command hooks run from a fallback directory with a logged warning. The project root is exposed through `$CLAUDE_PROJECT_DIR` (from model knowledge, not re-read this run).

## 5. Can PostToolUse modify or block for AskUserQuestion? Ordering?
- PostToolUse decision fields (verbatim): `decision: "block"` "adds the `reason` next to the tool result. Claude still sees the original output; to replace it, use `updatedToolOutput`"; `additionalContext` "String added to Claude's context alongside the tool result"; `updatedToolOutput` "Replaces the tool's output with the provided value before it is sent to Claude. The value must match the tool's output shape" (ignored for AskUserQuestion/ExitPlanMode in a Cowork cloud session); `updatedMCPToolOutput` MCP only.
- It cannot undo the call: exit 2 on PostToolUse "Shows stderr to Claude; the tool already ran." "`updatedToolOutput` only changes what Claude sees. The tool has already run by the time the hook fires, so any files written, commands executed, or network requests sent have already taken effect." So not a gate, but it can add context or rewrite what Claude sees.
- Ordering: a synchronous (non-`async`) hook finishes before Claude Code records the tool result: "Synchronous responses only: Claude Code ignores the field in the response of a hook that runs in the background, because that response arrives after Claude Code records the tool result." `async: true` "runs in the background without blocking" and "can't block or rewrite the result". Matching hooks of one event run in parallel. Not stated in one sentence: "a sync PostToolUse hook's file write precedes the model's next tool call"; it follows from the above (sync hooks complete before the result is recorded and sent) but is inference, not a quote. A PostToolBatch event exists "after a full batch of parallel tool calls resolves, before the next model call".

## 6. Measured 2026-11-18 (interactive CLI, main thread, `permission_mode: auto`) [measured]
Temporary PostToolUse hook, matcher `AskUserQuestion`, added to `.claude/settings.local.json` mid-session, dumping raw stdin; removed after. Two calls, 3 questions each.
- **PostToolUse fires for AskUserQuestion** and a settings edit mid-session took effect without restart.
- Answers land in **both** `tool_input.answers` and `tool_response.answers`, identical, `{"<question text>": "<label>"}`; `tool_response` = `{questions, answers, annotations}` (same `questions` as the input); `annotations` was `{}`. `tool_use_id`, `prompt_id`, `duration_ms: 0` present.
- Main-thread call: **no `agent_id`, no `agent_type`** key.
- A rejected AskUserQuestion (user declined the tool) wrote **no** hook input: PostToolUse does not fire on rejection.
- **Not measured** (user picked the first option each time): the value for a typed "Other" answer, and multiSelect with two labels. Working assumption: a typed `go` is indistinguishable from the `go` label (the SDK doc says the typed text goes in `answers[question]`), so a record must not rely on telling them apart.

## Not found
- AskUserQuestion `tool_response` schema for PostToolUse (and where TUI-chosen answers land): not documented in hooks.md, nor the SDK doc.
- An explicit statement that PostToolUse fires for AskUserQuestion in interactive sessions.
- Explicit "absent on main thread" wording for `agent_id` on tool events.
- CLI (non-SDK) statement on subagents calling AskUserQuestion.
- A quoted guarantee about hook write ordering vs the next tool call.
