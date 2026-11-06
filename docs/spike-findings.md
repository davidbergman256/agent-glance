# Spike findings — hooks and deep links (2026-11-06)

These findings come from logging every hook event in the Claude desktop app (Code tab) and the Codex desktop app, then triggering each case by hand.

## Claude Code (desktop app)

- **Where hooks come from:** hooks in `~/.claude/settings.json` fire in desktop sessions and are picked up live, with no restart needed.
- **Payload keys:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`, `prompt_id`, `effort`. Tool events add `tool_name`, `tool_use_id`, `tool_input` and, on `PostToolUse`, `tool_response`. Notifications add `notification_type` and `message`.
- **Event sequences:**
  - **Allow:** `PreToolUse` → `PermissionRequest` → `PostToolUse` → `Stop`.
  - **Deny:** `PreToolUse` → `PermissionRequest`, then **no further hook**. The transcript gets a `tool_result` with `is_error: true` and `toolUseResult: "User rejected tool use"`, then a user text entry starting `[Request interrupted by user`. Handled by watching the transcript while a row is red or yellow (`TranscriptSignals`).
  - **Question (`AskUserQuestion`):** `PreToolUse(AskUserQuestion)` → `PermissionRequest(AskUserQuestion)` → `Notification(permission_prompt, "Claude needs your permission to use AskUserQuestion")` → `PostToolUse(AskUserQuestion)` once you answer. A question must therefore never be shown as a permission prompt.
- **Session ids:** the hook's `session_id` is the CLI session id. The desktop session id (`local_<uuid>`) is in `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<uuid>.json`, whose `cliSessionId` field equals the hook's `session_id`.
- **Deep link:** `claude://claude.ai/epitaxy/local_<uuid>` switches the Claude window to exactly that session. Confirmed by hand.

## Codex (desktop app)

- **Where hooks come from:** `~/.codex/hooks.json`, in the same `{"hooks": {Event: [{matcher, hooks: [{type, command, timeout}]}]}}` shape. Codex asks you to trust new hooks and stores the trust in `~/.codex/config.toml` as `[hooks.state."<file>:<event>:<index>:0"]` with a `trusted_hash`. Trust is keyed by position, so changing the order of entries asks again.
- **Events seen:** `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse` and `Stop`. `PermissionRequest` wasn't observed because this Codex is set to `approval_policy = "never"`.
- **Payload keys:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, `permission_mode` and `turn_id`. `UserPromptSubmit` adds `prompt`; `Stop` adds `last_assistant_message`.
- **Tool names:** the shell tool is `Bash`. The question tool is **`request_user_input_async`**, with `tool_input.questions[].title` and `.options`. It returns `{"accepted": true}` straight away, and the turn ends with `Stop` while the question card is still waiting. The row stays yellow (`Session.awaitingAnswer`) until the next prompt.
- **Session ids:** the hook's `session_id` is the thread id (for example `01a1b216-4632-7b80-84c3-a26990f6802f`).
- **Deep link:** `codex://threads/<thread id>` opens exactly that thread. Confirmed by hand.

## Consequences for the plan

- **Task 8:** focusing uses deep links for both apps, and no Accessibility sidebar walk is needed. For Claude, look up `local_<uuid>` from `cliSessionId` on demand and cache it.
- **Task 5:** `codexEvents` keeps `PermissionRequest`, because Codex supports it and it fires once approvals are turned on. `Notification` stays Claude-only.
