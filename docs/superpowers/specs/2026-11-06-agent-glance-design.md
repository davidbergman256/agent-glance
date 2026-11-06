# Agent Glance — design

Date: 2026-11-06
Status: draft for approval
Working name: "Agent Glance" (builder's call; rename freely)

## Why

agent-pet (the Tauri app tried earlier) only says "working" or "done" for whichever single log file changed last. It can't tell when an agent is blocked on you, it mixes sessions together, and it re-reads files every second. The goal is a small, always-visible status strip for every running Claude Code and Codex session. It should show at a glance which sessions are working, which need a decision, and which are finished, and let you reply to any of them by voice without hunting for its window.

The visual reference is the Codex app's floating task list: one card per task with a title and a status line. This should be more compact.

## Goals

1. Show every active Claude Code and Codex session as its own row, with its title and a short live status line ("Running command", "Allow Bash: cargo build?", "Asking: which provider?").
2. Mark each session's state with a color:
   - Working: blue, slowly pulsing.
   - Needs permission: red, and the row gets a light red tint.
   - Asking a multiple-choice question: yellow, and the row gets a light yellow tint.
   - Done: green.
3. Show a source only while it has active sessions. With only Claude Code active, there are no headings and Codex isn't mentioned. With both active, each gets a small heading.
4. Stay on top of other windows, like the Codex pet. The app lives only in the menu bar, with no Dock icon and no app-switcher entry.
5. Give each row a mic button. Clicking it starts dictation, shows the transcript live, and sends the text to that session as soon as you finish.
6. Be very light: Mac-native, close to 0% CPU while idle, and under about 30 MB of memory (to be measured, not assumed).

## Non-goals

- No pet sprites or character animations.
- No Windows or Linux support, and no other agents (opencode, OpenClaw and so on).
- No terminal or IDE sessions. You run Claude Code only in the Claude desktop app (Code tab) and Codex only in the Codex desktop app. Sessions started elsewhere may still appear in the list, since they write the same logs and hooks, but focusing them and dictating to them aren't supported.
- No history or analytics. Sessions that finish leave the list.
- No approving permissions from the panel. A red row tells you to go to the session; the panel doesn't approve for you.

## Anti-goals (failure even if it "works")

- Dictated text landing in the wrong session or the wrong app. Sending to the wrong place is worse than not sending.
- Any noticeable load on the Mac: constant redraws, polling loops or always-on audio.
- Slowing Claude Code down. Hooks must return almost instantly and never block or fail a turn if the app isn't running.
- A panel that steals keyboard focus when it updates or expands.

## Constraints

- macOS 26.6 on an Apple M5 with 24 GB of memory. Target only macOS 26 or later and Apple Silicon.
- Language and UI: Swift, with SwiftUI for the views and AppKit for the window and menu bar (`NSPanel`, `NSStatusItem`). This was my call over Rust: it's the most efficient and most native option on this Mac, and it gives direct access to Liquid Glass and on-device speech recognition.
- Look: Apple's Liquid Glass material for the pill and the list (`glassEffect` in SwiftUI). The status colors are the system colors `systemBlue`, `systemRed`, `systemYellow` and `systemGreen`. Their tints must stay readable over any wallpaper, so make them more opaque than the glass if needed. With "Reduce transparency" turned on, the app follows the system's frosted fallback.
- Font: SF Pro Rounded, the system font with the rounded design. Titles are semibold at about 12.5 pt; status lines are regular at about 11.5 pt in the secondary label color.
- The window is an `NSPanel` that doesn't activate on click, floats above normal windows, appears on all Spaces and over full-screen apps, and can be dragged anywhere. Its position is remembered.
- `LSUIElement = YES`, so there's no Dock icon.

## What it looks like

The approved mockup (v2 in chat) has four parts:

1. **Compact pill.** This is the default view. It shows one colored dot per active session, a thin divider and a mic button.
2. **Expanded list.** It opens on hover and stays open on click, and is about 330 pt wide. Each row is 30 pt tall and contains a status dot, the title (truncated at about 150 pt), the status line (truncated to fit) and a mic button. Section headings appear only when both sources are active.
3. **Dictation row.** The mic button turns into a solid red circle, the live transcript appears under the row, and a hint reads "Return to send · Esc to cancel".
4. **Menu bar.** The icon is a small row of dots matching the session states. The menu contains:
   - Show panel (⌥⌘A)
   - Compact view
   - Sources: Claude Code and Codex, each with an on/off checkmark
   - Launch at login
   - Quit

Clicking a row, outside its mic button, brings that session to the front.

## How session state is detected

The app keeps an in-memory table of sessions, keyed by source and session id, holding each one's title, state, status line and last update time. Nothing is polled. Every update arrives through a hook.

### Claude Code

- **Discovering sessions and titles:** conversation logs live at `~/.claude/projects/<project>/<sessionId>.jsonl`. The title comes from the latest `custom-title` entry (`customTitle`). If there isn't one, use the first user prompt, cut to a few words.
- **State comes from Claude Code hooks, not log parsing,** because the log doesn't record a permission prompt until you answer it. The app installs entries in `~/.claude/settings.json`, merged without touching your existing hooks and removable from the menu. Each hook runs a tiny bundled command that forwards the hook's JSON to the app over a local Unix socket. If the app isn't running, it exits immediately. It must never fail or hold up the turn.
  - `UserPromptSubmit` → working ("Thinking").
  - `PreToolUse` → working, with the status line built from the tool ("Running command", "Editing foo.swift"). `PreToolUse` for `AskUserQuestion` → question (yellow), with the status line "Asking: <question text>".
  - `PermissionRequest` → permission (red), with the status line "Allow <tool>: <short command>". `Notification` with a permission-prompt type is a fallback if `PermissionRequest` isn't available.
  - `PostToolUse` → back to working.
  - `Stop` → done (green).
  - `SessionEnd` → remove the row.
- **Spike first:** check the exact hook and field names against the current Claude Code docs. Also confirm that hooks from `~/.claude/settings.json` fire in Claude desktop app sessions, specifically `PermissionRequest` while the app's own permission card is showing. There's partial evidence already: a plugin's `SessionStart` hook fired in a desktop app session on 2026-11-06.

### Codex

- **State comes from Codex hooks, the same way as Claude Code.** Codex never writes approval requests to its rollout logs: on 2026-11-06 there were zero approval events across all `~/.codex/sessions` logs. The bundled Codex binary does support the same hook events, including `PermissionRequest`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop` and `SessionEnd`. Hooks are read from a `hooks.json` file and must be trusted once inside Codex, which stores a `trusted_hash` in `~/.codex/config.toml`.
  - `PreToolUse` for `request_user_input` → question (yellow).
  - The other events map the same way as for Claude Code.
- **Titles:** read from `~/.codex/session_index.jsonl` (`thread_name`, keyed by `id`).
- **Spike first:** confirm where Codex's `hooks.json` lives, what its payload fields are, and that the hook's `session_id` is the thread id.

### Lifecycle (builder's call where marked)

- A session appears when it first becomes active (a prompt is submitted, or a task starts).
- Done stays green until you click the row or 10 minutes pass, then it leaves the list (*my call*).
- A working session with no events for 30 minutes is treated as gone (*my call*).
- When no session is active, the pill shows a single dim dot. It doesn't disappear, so you know the app is alive (*my call*).
- When a session turns red or yellow, the panel doesn't open by itself. The new dot appears in the pill and gives one small bounce, so it never covers what you're working on (*my call*).

## Dictation and sending

- **Speech-to-text:** Apple's on-device speech recognition (the macOS 26 `SpeechAnalyzer` API, or `SFSpeechRecognizer` with on-device recognition required). The mic is used only while recording. The live transcript appears in the row.
- **Finishing:** press Return, or click the mic again, and the text is sent right away (your decision). Esc cancels and sends nothing.
- **The pill's mic button** dictates into the session that most recently needed you (red or yellow). If none did, it uses the most recently active session (*my call*).
- **Delivery,** per source:
  1. Bring the session to the front. Both targets are desktop apps.
     - Codex app (`com.openai.codex`): open `codex://threads/<id>`. The app registers this deep link.
     - Claude app (`com.anthropic.claudefordesktop`): use its `claude://code/...` deep links. The app registers `claude://code/continue?session=…` and `claude://code/needs-input`.
       - Still to confirm in the spike: whether `session=` accepts a specific session id, and whether that id is the one in the `.jsonl` filename.
       - If it doesn't, the fallback is to activate the Claude app and pick the session in its sidebar by title, through the Accessibility API.
  2. Check, through the Accessibility API, that the frontmost app and window really are that session.
  3. Paste the text into the input box and press Return, using synthesized keystrokes.
  4. If step 2 can't confirm the target, don't send. Put the text on the clipboard and show "Couldn't reach <session>. Text copied." This protects the wrong-session anti-goal.
- **Permissions requested on first use:** Microphone, Speech Recognition and Accessibility.
- **Spike first:** delivery is the riskiest part of the build. Prove it end to end for one Codex thread and one Claude desktop session before building the rest of the UI on top of it.

## Performance budget

- Idle: about 0% CPU. There are no timers except the dot pulse, and that runs only while a session is working and the panel is visible.
- Memory: under about 30 MB resident.
- Log reading: none in the background. Titles are read from the end of a log only when a hook event arrives for that session, and then cached.
- The glass is drawn by the system compositor, so it adds nothing in the app.
- Check the numbers after the build in Activity Monitor or with `footprint`, with several sessions running.

## Left to the builder

- The app's name, icon and bundle id.
- The project layout, with a Swift Package or Xcode project, plus code signing for local use.
- How the hook helper is built: a tiny Swift binary inside the app, or a one-line `nc -U` command.
- Exact animation curves and the pulse speed.
- Hover delays for expanding and collapsing.
- Where settings are stored (`UserDefaults` is fine).
