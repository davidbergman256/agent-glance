# Agent Glance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar-only macOS app that floats a Liquid Glass pill and list showing every Claude Code and Codex desktop session's live state, with per-session dictation that sends text straight into that session.

**Architecture:** Both desktop apps run a tiny bundled `agent-glance-hook` binary on their hook events. The binary forwards the hook JSON over a Unix socket to the app. A pure, tested core (`AgentGlanceCore`) turns those events into a session table. A thin SwiftUI and AppKit shell (`AgentGlance`) draws it in a non-activating floating `NSPanel` and a status item. Dictation uses on-device speech recognition. Delivery opens the session through a deep link, verifies the frontmost window through Accessibility, and pastes the text and presses Return.

**Tech Stack:** Swift 6.3 (Command Line Tools only, no Xcode), SwiftPM, SwiftUI with `glassEffect`, AppKit (`NSPanel`, `NSStatusItem`), the Network framework (Unix-domain `NWListener`), Speech (`SpeechAnalyzer`/`SpeechTranscriber`), ApplicationServices (AX API, `CGEvent`), ServiceManagement (`SMAppService`), and Swift Testing (`import Testing`; XCTest isn't available without Xcode).

**Spec:** `docs/superpowers/specs/2026-11-06-agent-glance-design.md`

## Global Constraints

- macOS 26.0 or later, Apple Silicon only: `platforms: [.macOS(.v26)]`, arm64.
- The build must work with Command Line Tools alone: `swift build`, `swift test`, and `scripts/bundle.sh` to assemble the `.app`. No `.xcodeproj`, asset catalogs or SwiftUI previews.
- `LSUIElement = YES`: no Dock icon and no app-switcher entry.
- Idle CPU is about 0%, with no timers except the dot pulse, which runs only while a session is working and the panel is visible. Resident memory stays under about 30 MB.
- The hook binary prints nothing to stdout, always exits 0, and finishes within 300 ms, even when the app isn't running.
- Colors: `systemBlue` for working (slow pulse), `systemRed` for permission (with a red row tint), `systemYellow` for a question (with a yellow row tint), `systemGreen` for done.
- Font: SF Pro Rounded (`.fontDesign(.rounded)`). Titles are semibold at about 12.5 pt, status lines regular at about 11.5 pt in the secondary label color.
- Layout: rows are 30 pt tall, the list is about 330 pt wide, and titles truncate at about 150 pt.
- Lifecycle: done stays until clicked or 10 minutes pass. A working session with no events for 30 minutes is removed. With no sessions, the pill shows one dim dot.
- Section headings ("Claude Code", "Codex") appear only when both sources have sessions.
- Dictated text is sent immediately on Return or a second mic click. Esc cancels. If the target can't be verified frontmost, nothing is sent: the text is copied and the notice "Couldn't reach <title>. Text copied." is shown.
- Bundle ids: Claude is `com.anthropic.claudefordesktop`, Codex is `com.openai.codex`, and this app is `com.agentglance.app`.
- Socket path: `~/Library/Application Support/AgentGlance/events.sock`.

## Review Focus

1. **App not running, or the socket is stale, when a hook fires.** The hook must exit 0 silently and quickly, and Claude or Codex must be unaffected. Tested in Task 3.
2. **Unusual existing settings files**: missing, empty, without a `hooks` key, with other hooks under the same event, or malformed JSON. The installer must never corrupt or drop the user's config, and must refuse to change a malformed file. Tested in Task 5.
3. **A permission prompt that gets denied, or is answered without a `PostToolUse`.** A red or yellow row must not stay stuck: any later event for that session (`Stop`, `UserPromptSubmit`, `PreToolUse`) replaces the state. Tested in Task 2.
4. **Two sessions with the same title, or the same id in both sources.** Rows are keyed by `(source, sessionId)` and never merged. Tested in Task 2.
5. **Delivery while the user's clipboard holds something else, or the wrong window is in front.** The previous clipboard is restored after pasting, and an unverified target never receives keystrokes. Tested in Task 10.

---

### Task 1: Spike — confirm hooks and deep links in both desktop apps

No product code. This produces `docs/spike-findings.md`, which fixes the field names, file paths and deep-link forms later tasks rely on. Where a finding differs from the expectation written in Tasks 2, 5, 8 or 10, update those tasks before starting them.

**Files:**
- Create: `docs/spike-findings.md`
- Create (temporary, deleted at the end): `scripts/spike-log-hook.sh`

- [ ] **Step 0: Set up the repository.** Run `git init` in the project folder if it isn't a repository yet, and commit `docs/` as-is.
- [ ] **Step 1: Back up both config files.** Copy `~/.claude/settings.json` to `~/.claude/settings.json.agentglance-bak`. Copy Codex's hooks file (if it exists) and `~/.codex/config.toml` the same way.
- [ ] **Step 2: Write `scripts/spike-log-hook.sh`.** It runs `cat >> ~/Library/Logs/AgentGlance/spike.jsonl; echo >> …; exit 0`, with the source name passed as `$1` and written into the line.
- [ ] **Step 3: Register it in `~/.claude/settings.json`.** Use matcher `"*"` where matchers apply. Events: `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`.
- [ ] **Step 4: Find where Codex loads hooks.** Try `~/.codex/hooks.json` first. Use the same `{"hooks": {Event: [{matcher, hooks: [{type, command}]}]}}` shape. Register the same events, trust the hooks in the Codex app when it asks, and record where the `trusted_hash` lands.
- [ ] **Step 5: Trigger each case in the Claude desktop app and in the Codex app.** For each app: a normal prompt, a command that needs permission (allow it once and deny it once), and a multiple-choice question (Claude: `AskUserQuestion`; Codex: Plan mode `request_user_input`).
- [ ] **Step 6: Record the findings in `docs/spike-findings.md`.** For each source:
  - The exact `hook_event_name` values that fired, in order.
  - The JSON keys present: expected `session_id`, `transcript_path`, `cwd`, `tool_name`, `tool_input` and `notification_type`.
  - Whether `PermissionRequest` fires while the app's own permission card is showing.
  - What fires after a denial.
  - Whether Codex's `session_id` equals the `id` in `~/.codex/session_index.jsonl`.
- [ ] **Step 7: Test the deep links.** Run `open "codex://threads/<id>"` with a real thread id. Run `open "claude://code/continue?session=<jsonl session id>"`, and the same with the desktop `local_…` id if one can be found. Record which links focus the exact session.
- [ ] **Step 8: Decide Claude's focus method.** Use the deep link if Step 7 worked. Otherwise, record the AX path to the sidebar row with that session's title: role, subrole and attribute names, found with Accessibility Inspector or an `AXUIElement` dump script.
- [ ] **Step 9: Clean up.** Restore both config files from the backups and delete `scripts/spike-log-hook.sh` and `spike.jsonl`.
- [ ] **Step 10: Commit.**

```bash
git add docs/spike-findings.md
git commit -m "docs: record hook payloads and deep links for Claude and Codex desktop apps"
```

### Task 2: Package scaffold, session model and state reducer

**Files:**
- Create: `Package.swift`, `.gitignore` (ignore `.build/` and `build/`)
- Create: `Sources/AgentGlanceCore/HookEvent.swift`, `Sources/AgentGlanceCore/Session.swift`, `Sources/AgentGlanceCore/SessionStore.swift`
- Test: `Tests/AgentGlanceCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum Source: String, Codable, Sendable { case claude, codex }`
  - `enum SessionState: Sendable, Equatable { case working, permission, question, done }`
  - `struct HookEvent: Decodable, Sendable { source: Source; name: String; sessionId: String; transcriptPath: String?; toolName: String?; toolInput: [String: JSONValue]?; notificationType: String?; message: String? }`. Decodes from the wire envelope `{"source": "...", "payload": {hook JSON}}`, mapping `hook_event_name` to `name` and `session_id` to `sessionId` (snake_case keys come from Task 1).
  - `enum JSONValue: Decodable, Sendable, Equatable`: string, number, bool, object, array and null.
  - `struct SessionKey: Hashable, Sendable { source: Source; id: String }`
  - `struct Session: Identifiable, Sendable, Equatable { key: SessionKey; title: String; state: SessionState; status: String; updatedAt: Date; transcriptPath: String? }`
  - `@Observable @MainActor final class SessionStore`, with:
    - `func apply(_ e: HookEvent, now: Date)`
    - `func setTitle(_ t: String, for: SessionKey)`
    - `func dismiss(_ key: SessionKey)`
    - `func expire(now: Date)`
    - `var sessions: [Session]`, ordered by first appearance
    - `var showsSectionHeadings: Bool`
    - `var mostRecentAttention: Session?`

- [ ] **Step 1: Write `Package.swift`.** Three targets: library `AgentGlanceCore`, executable `AgentGlance` (depends on Core), and executable `agent-glance-hook` (no dependencies), plus test target `AgentGlanceCoreTests`. Set `swiftLanguageModes: [.v6]`.
- [ ] **Step 2: Write the failing tests** in `SessionStoreTests.swift`, using `@Test` and `#expect`:
  - `userPromptSubmitCreatesWorkingSession`: the state is `.working` and the status is `"Thinking"`.
  - `preToolUseBashSetsRunningCommand`: tool `Bash` gives status `"Running command"`; `Edit` with `file_path: "/a/b/Foo.swift"` gives `"Editing Foo.swift"`; any other tool `X` gives `"Using X"`.
  - `askUserQuestionIsQuestion`: `PreToolUse` with `AskUserQuestion` and `questions[0].question = "Which provider?"` gives `.question` and status `"Asking: Which provider?"`. The same holds for Codex `request_user_input`.
  - `permissionRequestIsPermission`: `PermissionRequest` with tool `Bash` and command `"cargo build --release"` gives `.permission` and status `"Allow Bash: cargo build --release"`.
  - `notificationPermissionPromptIsPermission`: `Notification` with `notificationType == "permission_prompt"` gives `.permission`.
  - `deniedPermissionThenStopIsDone`: `PermissionRequest` then `Stop` gives `.done`. (Review Focus 3.)
  - `permissionThenPreToolUseIsWorking`.
  - `stopIsDoneWithStatusDone`: the status is `"Done"`.
  - `sessionEndRemovesRow`.
  - `sameIdDifferentSourceAreTwoRows`, and `sameTitleDifferentIdAreTwoRows`. (Review Focus 4.)
  - `doneExpiresAfter10Minutes`: still present at +599 s, gone at +601 s.
  - `workingExpiresAfter30MinutesIdle`: still present at +1799 s, gone at +1801 s.
  - `statusTruncatedTo80Chars`: a 200-character command gives a status of 80 characters ending in `"…"`.
  - `headingsOnlyWhenBothSources`: false with only Claude sessions, true once a Codex session is added.
  - `mostRecentAttentionPicksLatestRedOrYellow`: with a question at t1 and a permission at t2, it returns the permission. With none, it returns the most recently updated session.
  - `defaultTitleBeforeLookupIsUntitled`: before `setTitle` is called, the title is `"Untitled session"`.
- [ ] **Step 3: Run `swift test` and confirm it fails** (the types aren't defined yet).
- [ ] **Step 4: Implement `HookEvent`, `JSONValue`, `Session` and `SessionStore`** to make the tests pass. `apply` replaces the state on every event. That is the rule that prevents stuck red or yellow rows.
- [ ] **Step 5: Run `swift test`.** Expected: all `SessionStoreTests` pass.
- [ ] **Step 6: Commit.** `git add Package.swift .gitignore Sources/AgentGlanceCore Tests && git commit -m "feat: session model and hook-event reducer"`

### Task 3: Hook binary and socket server

**Files:**
- Create: `Sources/agent-glance-hook/main.swift`
- Create: `Sources/AgentGlanceCore/EventSocketServer.swift`, `Sources/AgentGlanceCore/Paths.swift`
- Test: `Tests/AgentGlanceCoreTests/SocketTests.swift`

**Interfaces:**
- Consumes: `HookEvent` (Task 2).
- Produces:
  - `enum Paths { static var supportDir: URL; static var socket: URL }`, where `socket` is `supportDir/events.sock` and `supportDir` is created on first access.
  - `final class EventSocketServer: Sendable { init(path: URL, onEvent: @escaping @Sendable (HookEvent) -> Void) throws; func start(); func stop() }`. It uses `NWListener` with a Unix endpoint, accepts one JSON message per connection (read to EOF), and removes any stale socket file before binding.
  - CLI: `agent-glance-hook --source claude|codex [--socket <path>]`. It reads stdin (capped at 1 MB), wraps it as `{"source":…, "payload":…}`, connects, writes and closes. Every failure path still exits 0, and it never writes to stdout or stderr.

- [ ] **Step 1: Write the failing tests:**
  - `serverReceivesEnvelope`: start the server on a temp path, run the built hook binary (`.build/debug/agent-glance-hook`) with `Stop` JSON on stdin, and expect `onEvent` to receive `name == "Stop"` within 1 s.
  - `hookExitsZeroFastWithNoServer`: point at a missing socket path. Expect exit status 0, empty stdout and wall time under 300 ms. (Review Focus 1.)
  - `hookExitsZeroOnGarbageStdin`.
  - `serverReplacesStaleSocketFile`.
- [ ] **Step 2: Run `swift test --filter SocketTests` and confirm it fails.**
- [ ] **Step 3: Implement the hook binary.** Use a blocking POSIX `socket(AF_UNIX)`, `connect` and `write`, with `SO_SNDTIMEO` set to 200 ms. No Foundation networking, to keep startup fast.
- [ ] **Step 4: Implement `EventSocketServer` and `Paths`.**
- [ ] **Step 5: Run `swift build && swift test --filter SocketTests`.** Expected: PASS.
- [ ] **Step 6: Commit.** `git commit -m "feat: hook forwarder binary and unix socket server"`

### Task 4: Session titles

**Files:**
- Create: `Sources/AgentGlanceCore/Titles.swift`
- Test: `Tests/AgentGlanceCoreTests/TitlesTests.swift`, with fixtures in `Tests/AgentGlanceCoreTests/Fixtures/claude-session.jsonl` and `Tests/AgentGlanceCoreTests/Fixtures/codex-index.jsonl`

**Interfaces:**
- Consumes: `SessionKey` (Task 2).
- Produces: `enum Titles { static func claude(transcriptPath: URL) -> String?; static func codex(threadId: String, index: URL = ~/.codex/session_index.jsonl) -> String? }`

- [ ] **Step 1: Write the failing tests:**
  - `claudeUsesLastCustomTitle`: the fixture has two `custom-title` lines, "Old" and then "Agent-pet installation". Expect `"Agent-pet installation"`.
  - `claudeFallsBackToFirstUserPromptSixWords`: with no custom-title, the first `user` text "please run an arbitrary task for thirty seconds now" gives `"please run an arbitrary task for…"`.
  - `claudeMissingFileIsNil`.
  - `codexUsesLastMatchingThreadName`: the fixture has two lines with the same id. Expect the later `thread_name`.
  - `codexUnknownIdIsNil`.
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement.** Claude: read only the last 256 KB for `custom-title`, and only the first 64 KB for the fallback. Codex: scan the file from the end.
- [ ] **Step 4: Run `swift test --filter TitlesTests`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat: title lookup for Claude and Codex sessions"`

### Task 5: Hook installer

**Files:**
- Create: `Sources/AgentGlanceCore/HookInstaller.swift`
- Test: `Tests/AgentGlanceCoreTests/HookInstallerTests.swift`

**Interfaces:**
- Produces:
  - `struct HookInstaller { let settingsURL: URL; let command: String; let events: [String]; func install() throws; func uninstall() throws; func isInstalled() -> Bool }`
  - `enum HookInstallerError: Error { case malformedSettings }`
  - `static let claudeEvents = ["UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","Notification","Stop","SessionEnd"]`
  - `static let codexEvents`: the Codex subset confirmed in Task 1.
  - The command is `"<app>/Contents/MacOS/agent-glance-hook --source claude"` (or `codex`). An entry counts as ours when its command contains `agent-glance-hook`.

- [ ] **Step 1: Write the failing tests** (Review Focus 2):
  - `installIntoMissingFileCreatesIt`.
  - `installPreservesUnrelatedKeysAndOtherHooks`: the fixture has `"model": "opus"` and an existing user `PreToolUse` hook. After install, both are unchanged and ours is appended alongside.
  - `installIsIdempotent`: installing twice gives exactly one entry of ours per event.
  - `uninstallRemovesOnlyOurs`, and also removes event arrays left empty.
  - `malformedJSONThrowsAndLeavesFileByteIdentical`.
  - `installWritesBackupOnce`: `settings.json.agentglance-bak` exists after the first install.
  - `matcherStarOnToolEvents`: `PreToolUse`, `PostToolUse` and `PermissionRequest` entries get `"matcher": "*"`, while `Stop` has no matcher.
- [ ] **Step 2: Run the tests and confirm they fail.**
- [ ] **Step 3: Implement** with `JSONSerialization`, writing atomically (`.atomic`) and keeping key order where possible. Each hook entry is `{"type": "command", "command": …, "timeout": 2}`.
- [ ] **Step 4: Run `swift test --filter HookInstallerTests`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat: idempotent hook installer for Claude and Codex settings"`

### Task 6: App shell — status item, floating panel, bundle script

**Files:**
- Create: `Sources/AgentGlance/main.swift`, `Sources/AgentGlance/AppDelegate.swift`, `Sources/AgentGlance/FloatingPanel.swift`, `Sources/AgentGlance/StatusItemController.swift`, `Sources/AgentGlance/HotKey.swift`
- Create: `Resources/Info.plist`, `scripts/bundle.sh`

**Interfaces:**
- Consumes:
  - `SessionStore`, `EventSocketServer`, `Paths` and `Titles` (Tasks 2–4).
  - `HookInstaller` (Task 5).
- Produces:
  - `final class FloatingPanel: NSPanel` with:
    - `.nonactivatingPanel`, `level = .floating`
    - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
    - draggable by background, position saved under `UserDefaults` key `panelOrigin`
    - `becomesKeyOnlyIfNeeded = true`
  - `@Observable @MainActor final class AppModel`. It owns the store and the server, looks up titles on the first event for each key and on `Stop`, and runs `expire(now:)` from a single 60-second timer. That one timer is allowed; it's suspended while there are no sessions.
  - `scripts/bundle.sh [--install]`. It runs `swift build -c release` and assembles `build/Agent Glance.app` with both binaries in `Contents/MacOS`. It signs ad hoc with `codesign -s - --force --deep`, and `--install` copies the app to `~/Applications/`.

- [ ] **Step 1: Write `Resources/Info.plist`** with:
  - `CFBundleIdentifier com.agentglance.app`
  - `LSUIElement true`
  - `LSMinimumSystemVersion 26.0`
  - `NSMicrophoneUsageDescription` "Dictate replies to your agent sessions."
  - `NSSpeechRecognitionUsageDescription` "Turn your dictation into text on this Mac."
- [ ] **Step 2: Implement the status item.** Its image is drawn from the current states: up to five 6 pt dots, redrawn only when states change. Menu items:
  - Show panel ⌥⌘A
  - Compact view ✓
  - Sources ▸ Claude Code ✓ / Codex ✓ (toggling one calls install or uninstall)
  - Launch at login (`SMAppService.mainApp`)
  - Quit ⌘Q
- [ ] **Step 3: Implement `HotKey` with Carbon `RegisterEventHotKey`** for ⌥⌘A, which toggles the panel.
- [ ] **Step 4: Implement `AppDelegate`.** On launch it starts the server, installs hooks for enabled sources (asking for confirmation in an `NSAlert` the first time), and shows the panel with placeholder content.
- [ ] **Step 5: Verify the bundle.** Run `scripts/bundle.sh --install && open ~/Applications/Agent\ Glance.app`. Expected:
  - No Dock icon, and dots appear in the menu bar.
  - The panel floats over a full-screen app and appears on every Space.
  - Clicking the panel doesn't take focus from the frontmost app.
- [ ] **Step 6: Verify the hook path end to end.** Send a prompt in the Claude desktop app. Expected: a row appears in the placeholder list within about 1 s with the session's title.
- [ ] **Step 7: Commit.** `git commit -m "feat: menu bar app shell, floating panel, bundle script"`

### Task 7: Panel UI — pill, list, glass

**Files:**
- Create: `Sources/AgentGlance/Views/PanelView.swift`, `Sources/AgentGlance/Views/CompactPill.swift`, `Sources/AgentGlance/Views/SessionRow.swift`, `Sources/AgentGlance/Views/StatusDot.swift`, `Sources/AgentGlance/Theme.swift`

**Interfaces:**
- Consumes: `AppModel.store.sessions`, `showsSectionHeadings` and `dismiss(_:)`.
- Produces:
  - `SessionRow(session:onFocus:onMic:)`, where `onMic` is handled in Task 9.
  - `enum Theme` with the colors and fonts from Global Constraints.
  - `PanelView`, which switches between compact and expanded: it expands on hover after 150 ms, pins on click, and collapses 400 ms after the pointer leaves if not pinned.

- [ ] **Step 1: Build `StatusDot`.** It's 9 pt. A working dot pulses its opacity between 1.0 and 0.45 over 1.6 s, using `.animation(.easeInOut.repeatForever)`, only while `scenePhase` is active and the panel is visible.
- [ ] **Step 2: Build `CompactPill`.** One dot per session, then a 0.5 pt divider and a mic button. Wrap it in `.glassEffect(.regular, in: .capsule)`. A session that newly turns red or yellow gets one bounce (scale 1.0 → 1.35 → 1.0, spring), and the panel stays closed.
- [ ] **Step 3: Build `SessionRow`.**
  - Contents: dot, title (semibold, truncated at about 150 pt), status (secondary, `.lineLimit(1)`), and the mic button. The row is 30 pt tall with a 9 pt corner radius.
  - Tints: `systemRed` or `systemYellow` at 16% opacity for red and yellow rows, drawn on top of the glass so they stay readable.
  - Clicking a done row calls `dismiss`.
- [ ] **Step 4: Build `PanelView`.** The list is 330 pt wide inside `.glassEffect(.regular, in: .rect(cornerRadius: 14))`, with section headings only when `showsSectionHeadings` is true. With no sessions, show a single dim dot. `GlassEffectContainer` wraps the pill and the list so they morph into each other.
- [ ] **Step 5: Verify visually.** Run `scripts/bundle.sh --install`, relaunch, and run a permission prompt plus a question in Claude and a task in Codex. Take a screenshot (`screencapture -l <windowid>`, or computer-use) and compare it with the approved v2 mockup: colors, rounded font, tints and headings.
- [ ] **Step 6: Check the "Reduce transparency" fallback.** Turn it on in System Settings → Accessibility → Display, and check the panel is still legible.
- [ ] **Step 7: Commit.** `git commit -m "feat: liquid glass pill and session list"`

### Task 8: Focusing a session

**Files:**
- Create: `Sources/AgentGlance/SessionFocuser.swift`, `Sources/AgentGlanceCore/DeepLinks.swift`
- Test: `Tests/AgentGlanceCoreTests/DeepLinksTests.swift`

**Interfaces:**
- Consumes: `Session` (Task 2), and the deep-link forms and AX path from `docs/spike-findings.md` (Task 1).
- Produces:
  - `enum DeepLinks { static func url(for: Session) -> URL? }`, a pure function.
  - `@MainActor struct SessionFocuser { func focus(_ s: Session) async -> Bool; func isFrontmost(_ s: Session) -> Bool }`.
    - `focus` opens the deep link, or uses the AX sidebar fallback, then waits up to 1.5 s for `isFrontmost`.
    - `isFrontmost` checks that the frontmost app's bundle id matches the session's source and that the focused window or selected sidebar item matches the session's title, using the AX attributes recorded in Task 1.

- [ ] **Step 1: Write the failing tests.**
  - `codexThreadURL`: an id `abc` gives `codex://threads/abc`.
  - `claudeURL`: the form confirmed in Task 1, or `nil` if Task 1 chose the AX fallback.
- [ ] **Step 2: Run the tests and confirm they fail.** Then implement `DeepLinks`, run the tests, and confirm they pass.
- [ ] **Step 3: Implement `SessionFocuser`.** If `AXIsProcessTrustedWithOptions` is false, prompt for Accessibility once.
- [ ] **Step 4: Verify manually.** With two Claude sessions and one Codex thread open, click each row in turn. Expected: the exact session comes to the front each time.
- [ ] **Step 5: Commit.** `git commit -m "feat: focus a session from its row"`

### Task 9: Dictation

**Files:**
- Create: `Sources/AgentGlance/Dictation.swift`
- Modify: `Sources/AgentGlance/Views/SessionRow.swift` (recording state), `Sources/AgentGlance/Views/CompactPill.swift` (pill mic)

**Interfaces:**
- Consumes: `SessionStore.mostRecentAttention` (Task 2) for the pill's mic.
- Produces:
  - `@Observable @MainActor final class Dictation { var target: SessionKey?; var transcript: String; func start(for: SessionKey) async throws; func finish() async -> String; func cancel() }`
  - Speech recognition uses `SpeechAnalyzer` with `SpeechTranscriber(locale: .current, preset: .progressiveTranscription)` and `AVAudioEngine` input. If the model isn't installed, request it through `AssetInventory` on first use. The audio engine stops on `finish` and `cancel`.

- [ ] **Step 1: Implement `Dictation`.** Only one dictation can run at a time; starting another cancels the first.
- [ ] **Step 2: Add the recording state to `SessionRow`.**
  - The mic becomes a solid `systemRed` circle with a white glyph.
  - The live transcript appears under the row, indented 27 pt, with the hint "Return to send · Esc to cancel".
  - The panel becomes key only while recording, so it can receive Return and Esc, then returns focus.
- [ ] **Step 3: Wire up the pill's mic** to dictate into `mostRecentAttention`, expanding the list to show that row while recording.
- [ ] **Step 4: Verify manually.** Dictate a sentence and check the transcript updates live. Press Esc and check nothing happens and the mic indicator in the menu bar turns off. Activity Monitor should show no microphone use afterwards.
- [ ] **Step 5: Commit.** `git commit -m "feat: on-device dictation per session"`

### Task 10: Sending dictated text

**Files:**
- Create: `Sources/AgentGlanceCore/DeliveryPlan.swift`, `Sources/AgentGlance/MessageSender.swift`
- Test: `Tests/AgentGlanceCoreTests/DeliveryPlanTests.swift`

**Interfaces:**
- Consumes: `SessionFocuser` (Task 8), `Dictation.finish()` (Task 9).
- Produces:
  - `enum DeliveryDecision: Equatable { case paste, copyOnly(notice: String) }`
  - `enum DeliveryPlan { static func decide(text: String, verifiedFrontmost: Bool, title: String) -> DeliveryDecision }`. Empty or whitespace-only text gives `.copyOnly(notice: "Nothing to send.")`.
  - `@MainActor struct MessageSender { func send(_ text: String, to: Session) async }`. It runs focus, then `isFrontmost`, then `decide`. For `.paste`, it saves the clipboard, sets the text, sends ⌘V and Return through `CGEvent`, and restores the clipboard after 300 ms. For `.copyOnly`, it sets the clipboard and shows the notice in the panel for 4 s.

- [ ] **Step 1: Write the failing tests** (Review Focus 5):
  - `verifiedTargetPastes`.
  - `unverifiedTargetCopiesWithNotice`: the notice is exactly `"Couldn't reach Socio platform auth. Text copied."`
  - `emptyTextNeverPastes`.
- [ ] **Step 2: Run the tests, confirm they fail, implement `DeliveryPlan`, and confirm they pass.**
- [ ] **Step 3: Implement `MessageSender`** and wire it to Return and to the second mic click.
- [ ] **Step 4: Verify manually:**
  - Dictate into a Codex thread and a Claude session. Each message appears in the right session and is sent.
  - Put "CLIPBOARD-SENTINEL" on the clipboard first. After sending, the clipboard still holds it.
  - Close the target session's window, then dictate. Nothing is typed anywhere, and the notice shows.
- [ ] **Step 5: Commit.** `git commit -m "feat: send dictated text to the verified session"`

### Task 11: Performance check and install

**Files:**
- Create: `README.md` with install, permissions, uninstalling hooks and rebuilding.

- [ ] **Step 1: Measure idle use.** Run `scripts/bundle.sh --install`, relaunch, and leave 3 sessions idle for 5 minutes. Expected: `top -l 2 -pid $(pgrep -x AgentGlance)` shows CPU under 0.5%, and `footprint AgentGlance` shows a footprint under 30 MB.
- [ ] **Step 2: Measure busy use.** With 2 sessions working and the panel visible, CPU should stay under about 2%.
- [ ] **Step 3: Time the hook.** With the app quit, run `time (echo '{}' | ~/Applications/Agent\ Glance.app/Contents/MacOS/agent-glance-hook --source claude)`. Expected: under 0.3 s.
- [ ] **Step 4: Check uninstall.** "Sources ▸ Claude Code" off should remove our hooks from `~/.claude/settings.json`, with a diff against the backup showing only our entries gone.
- [ ] **Step 5: Write the `README.md`.** Note that ad-hoc signing means Accessibility must be granted again after each rebuild.
- [ ] **Step 6: Commit.** `git commit -m "docs: readme and performance check"`
