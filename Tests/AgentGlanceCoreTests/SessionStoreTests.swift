import Foundation
import Testing
@testable import AgentGlanceCore

/// Builds a HookEvent the same way the app receives one: an envelope from the hook binary.
func event(
    _ name: String,
    source: Source = .claude,
    session: String = "s1",
    tool: String? = nil,
    input: [String: Any]? = nil,
    notificationType: String? = nil,
    message: String? = nil
) throws -> HookEvent {
    var payload: [String: Any] = ["hook_event_name": name, "session_id": session, "transcript_path": "/tmp/\(session).jsonl"]
    if let tool { payload["tool_name"] = tool }
    if let input { payload["tool_input"] = input }
    if let notificationType { payload["notification_type"] = notificationType }
    if let message { payload["message"] = message }
    let envelope: [String: Any] = ["source": source.rawValue, "payload": payload]
    let data = try JSONSerialization.data(withJSONObject: envelope)
    return try JSONDecoder().decode(HookEvent.self, from: data)
}

let t0 = Date(timeIntervalSinceReferenceDate: 0)

@MainActor
struct SessionStoreTests {
    let store = SessionStore()

    @Test func userPromptSubmitCreatesWorkingSession() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].state == .working)
        #expect(store.sessions[0].status == "Thinking")
    }

    @Test func preToolUseBashSetsRunningCommand() throws {
        store.apply(try event("PreToolUse", tool: "Bash", input: ["command": "ls"]), now: t0)
        #expect(store.sessions[0].status == "Running command")
        store.apply(try event("PreToolUse", tool: "Edit", input: ["file_path": "/a/b/Foo.swift"]), now: t0)
        #expect(store.sessions[0].status == "Editing Foo.swift")
        store.apply(try event("PreToolUse", tool: "WebSearch"), now: t0)
        #expect(store.sessions[0].status == "Using WebSearch")
        #expect(store.sessions[0].state == .working)
    }

    @Test func askUserQuestionIsQuestion() throws {
        let input: [String: Any] = ["questions": [["question": "Which provider?"]]]
        store.apply(try event("PreToolUse", tool: "AskUserQuestion", input: input), now: t0)
        #expect(store.sessions[0].state == .question)
        #expect(store.sessions[0].status == "Asking: Which provider?")
        store.apply(try event("PreToolUse", source: .codex, session: "c1", tool: "request_user_input", input: input), now: t0)
        #expect(store.sessions[1].state == .question)
    }

    @Test func askUserQuestionPermissionFlowStaysQuestion() throws {
        let input: [String: Any] = ["questions": [["question": "Which provider?"]]]
        store.apply(try event("PreToolUse", tool: "AskUserQuestion", input: input), now: t0)
        store.apply(try event("PermissionRequest", tool: "AskUserQuestion", input: input), now: t0)
        #expect(store.sessions[0].state == .question)
        store.apply(try event("Notification", notificationType: "permission_prompt",
                              message: "Claude needs your permission to use AskUserQuestion"), now: t0)
        #expect(store.sessions[0].state == .question)
        #expect(store.sessions[0].status == "Asking: Which provider?")
    }

    @Test func permissionRequestIsPermission() throws {
        store.apply(try event("PermissionRequest", tool: "Bash", input: ["command": "cargo build --release"]), now: t0)
        #expect(store.sessions[0].state == .permission)
        #expect(store.sessions[0].status == "Allow Bash: cargo build --release")
    }

    @Test func notificationPermissionPromptIsPermission() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        store.apply(try event("Notification", notificationType: "permission_prompt", message: "Claude needs your permission to use Bash"), now: t0)
        #expect(store.sessions[0].state == .permission)
    }

    @Test func deniedPermissionThenStopIsDone() throws {
        store.apply(try event("PermissionRequest", tool: "Bash", input: ["command": "rm x"]), now: t0)
        store.apply(try event("Stop"), now: t0)
        #expect(store.sessions[0].state == .done)
    }

    @Test func permissionThenPreToolUseIsWorking() throws {
        store.apply(try event("PermissionRequest", tool: "Bash", input: ["command": "rm x"]), now: t0)
        store.apply(try event("PreToolUse", tool: "Bash", input: ["command": "ls"]), now: t0)
        #expect(store.sessions[0].state == .working)
    }

    @Test func stopIsDoneWithStatusDone() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        store.apply(try event("Stop"), now: t0)
        #expect(store.sessions[0].state == .done)
        #expect(store.sessions[0].status == "Done")
    }

    @Test func sessionEndRemovesRow() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        store.apply(try event("SessionEnd"), now: t0)
        #expect(store.sessions.isEmpty)
    }

    @Test func sameIdDifferentSourceAreTwoRows() throws {
        store.apply(try event("UserPromptSubmit", source: .claude, session: "x"), now: t0)
        store.apply(try event("UserPromptSubmit", source: .codex, session: "x"), now: t0)
        #expect(store.sessions.count == 2)
    }

    @Test func sameTitleDifferentIdAreTwoRows() throws {
        store.apply(try event("UserPromptSubmit", session: "a"), now: t0)
        store.apply(try event("UserPromptSubmit", session: "b"), now: t0)
        store.setTitle("Same", for: SessionKey(source: .claude, id: "a"))
        store.setTitle("Same", for: SessionKey(source: .claude, id: "b"))
        #expect(store.sessions.count == 2)
    }

    @Test func doneExpiresAfter10Minutes() throws {
        store.apply(try event("Stop"), now: t0)
        store.expire(now: t0.addingTimeInterval(599))
        #expect(store.sessions.count == 1)
        store.expire(now: t0.addingTimeInterval(601))
        #expect(store.sessions.isEmpty)
    }

    @Test func workingExpiresAfter30MinutesIdle() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        store.expire(now: t0.addingTimeInterval(1799))
        #expect(store.sessions.count == 1)
        store.expire(now: t0.addingTimeInterval(1801))
        #expect(store.sessions.isEmpty)
    }

    @Test func statusTruncatedTo80Chars() throws {
        let long = String(repeating: "x", count: 200)
        store.apply(try event("PermissionRequest", tool: "Bash", input: ["command": long]), now: t0)
        #expect(store.sessions[0].status.count == 80)
        #expect(store.sessions[0].status.hasSuffix("…"))
    }

    @Test func headingsOnlyWhenBothSources() throws {
        store.apply(try event("UserPromptSubmit", source: .claude, session: "a"), now: t0)
        #expect(store.showsSectionHeadings == false)
        store.apply(try event("UserPromptSubmit", source: .codex, session: "b"), now: t0)
        #expect(store.showsSectionHeadings == true)
    }

    @Test func mostRecentAttentionPicksLatestRedOrYellow() throws {
        store.apply(try event("UserPromptSubmit", session: "w"), now: t0.addingTimeInterval(30))
        store.apply(try event("PreToolUse", session: "q", tool: "AskUserQuestion",
                              input: ["questions": [["question": "?"]]]), now: t0.addingTimeInterval(10))
        store.apply(try event("PermissionRequest", session: "p", tool: "Bash", input: ["command": "x"]),
                    now: t0.addingTimeInterval(20))
        #expect(store.mostRecentAttention?.key.id == "p")
    }

    @Test func mostRecentAttentionFallsBackToLatestUpdated() throws {
        store.apply(try event("UserPromptSubmit", session: "a"), now: t0)
        store.apply(try event("UserPromptSubmit", session: "b"), now: t0.addingTimeInterval(5))
        #expect(store.mostRecentAttention?.key.id == "b")
    }

    @Test func defaultTitleBeforeLookupIsUntitled() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        #expect(store.sessions[0].title == "Untitled session")
        store.setTitle("Agent-pet installation", for: SessionKey(source: .claude, id: "s1"))
        #expect(store.sessions[0].title == "Agent-pet installation")
    }

    @Test func rowsKeepFirstAppearanceOrder() throws {
        store.apply(try event("UserPromptSubmit", session: "a"), now: t0)
        store.apply(try event("UserPromptSubmit", session: "b"), now: t0)
        store.apply(try event("Stop", session: "a"), now: t0)
        #expect(store.sessions.map(\.key.id) == ["a", "b"])
    }
}

@MainActor
struct SpikeFindingTests {
    let store = SessionStore()
    let codexQuestion: [String: Any] = ["questions": [["title": "Which palette?", "options": ["Ocean", "Forest"]]]]

    @Test func codexAsyncQuestionStaysYellowThroughStop() throws {
        store.apply(try event("UserPromptSubmit", source: .codex, session: "c"), now: t0)
        store.apply(try event("PreToolUse", source: .codex, session: "c", tool: "request_user_input_async", input: codexQuestion), now: t0)
        store.apply(try event("PostToolUse", source: .codex, session: "c", tool: "request_user_input_async", input: codexQuestion), now: t0)
        store.apply(try event("Stop", source: .codex, session: "c"), now: t0)
        #expect(store.sessions[0].state == .question)
        #expect(store.sessions[0].status == "Asking: Which palette?")
    }

    @Test func codexAsyncQuestionClearedByNextPrompt() throws {
        store.apply(try event("PreToolUse", source: .codex, session: "c", tool: "request_user_input_async", input: codexQuestion), now: t0)
        store.apply(try event("Stop", source: .codex, session: "c"), now: t0)
        store.apply(try event("UserPromptSubmit", source: .codex, session: "c"), now: t0)
        #expect(store.sessions[0].state == .working)
        store.apply(try event("Stop", source: .codex, session: "c"), now: t0)
        #expect(store.sessions[0].state == .done)
    }

    @Test func claudeQuestionAnsweredGoesWorking() throws {
        let input: [String: Any] = ["questions": [["question": "Which?"]]]
        store.apply(try event("PreToolUse", tool: "AskUserQuestion", input: input), now: t0)
        store.apply(try event("PostToolUse", tool: "AskUserQuestion", input: input), now: t0)
        #expect(store.sessions[0].state == .working)
    }

    @Test func markInterruptedSetsStoppedDone() throws {
        store.apply(try event("PermissionRequest", tool: "Bash", input: ["command": "rm x"]), now: t0)
        store.markInterrupted(SessionKey(source: .claude, id: "s1"), now: t0)
        #expect(store.sessions[0].state == .done)
        #expect(store.sessions[0].status == "Stopped")
    }

    @Test func markInterruptedIgnoresWorkingRows() throws {
        store.apply(try event("UserPromptSubmit"), now: t0)
        store.markInterrupted(SessionKey(source: .claude, id: "s1"), now: t0)
        #expect(store.sessions[0].state == .working)
    }
}

struct TranscriptSignalsTests {
    func tail(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    @Test func rejectedToolUseIsInterrupted() {
        let t = tail([
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"The user doesn't want to proceed with this tool use."}]},"toolUseResult":"User rejected tool use"}"#,
            #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#,
        ])
        #expect(TranscriptSignals.isInterrupted(tail: t))
    }

    @Test func pendingToolUseIsNotInterrupted() {
        let t = tail([#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#])
        #expect(!TranscriptSignals.isInterrupted(tail: t))
    }

    @Test func interruptFollowedByNewAssistantOutputIsNotInterrupted() {
        let t = tail([
            #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#,
            #"{"type":"user","message":{"content":"try again"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
        ])
        #expect(!TranscriptSignals.isInterrupted(tail: t))
    }
}
