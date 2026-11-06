import Foundation
import Observation

/// The live table of sessions. Every hook event replaces the session's state, so a red or
/// yellow row can never get stuck once the agent moves on.
@Observable @MainActor
public final class SessionStore {
    public private(set) var sessions: [Session] = []

    public static let untitled = "Untitled session"
    static let doneLifetime: TimeInterval = 10 * 60
    static let workingIdleLimit: TimeInterval = 30 * 60
    static let needsUserIdleLimit: TimeInterval = 4 * 60 * 60
    static let statusLimit = 80

    public init() {}

    public var showsSectionHeadings: Bool { Set(sessions.map(\.key.source)).count > 1 }

    /// The session the pill's mic should dictate into.
    public var mostRecentAttention: Session? {
        sessions.filter(\.state.needsUser).max { $0.updatedAt < $1.updatedAt }
            ?? sessions.max { $0.updatedAt < $1.updatedAt }
    }

    public func apply(_ e: HookEvent, now: Date) {
        let key = SessionKey(source: e.source, id: e.sessionId)
        if e.name == "SessionEnd" {
            sessions.removeAll { $0.key == key }
            return
        }
        let current = sessions.first { $0.key == key }
        guard let next = Self.transition(e, current: current) else { return }
        if let i = sessions.firstIndex(where: { $0.key == key }) {
            sessions[i].state = next.state
            sessions[i].status = Self.truncate(next.status)
            sessions[i].awaitingAnswer = next.awaitingAnswer
            sessions[i].updatedAt = now
            if let path = e.transcriptPath { sessions[i].transcriptPath = path }
        } else {
            sessions.append(Session(key: key, title: Self.untitled, state: next.state, status: Self.truncate(next.status),
                                    updatedAt: now, transcriptPath: e.transcriptPath, awaitingAnswer: next.awaitingAnswer))
        }
    }

    public func setTitle(_ title: String, for key: SessionKey) {
        guard let i = sessions.firstIndex(where: { $0.key == key }) else { return }
        sessions[i].title = title
    }

    /// Called when the transcript shows the user denied a permission or stopped the turn.
    public func markInterrupted(_ key: SessionKey, now: Date) {
        guard let i = sessions.firstIndex(where: { $0.key == key }), sessions[i].state.needsUser else { return }
        sessions[i].state = .done
        sessions[i].status = "Stopped"
        sessions[i].updatedAt = now
    }

    public func dismiss(_ key: SessionKey) {
        sessions.removeAll { $0.key == key }
    }

    public func expire(now: Date) {
        sessions.removeAll { s in
            let idle = now.timeIntervalSince(s.updatedAt)
            switch s.state {
            case .done: return idle > Self.doneLifetime
            case .working: return idle > Self.workingIdleLimit
            case .permission, .question: return idle > Self.needsUserIdleLimit
            }
        }
    }

    // MARK: - Event mapping

    static let questionTools: Set<String> = ["AskUserQuestion", "request_user_input", "request_user_input_async"]
    /// Question tools that return before the user answers (the card keeps waiting).
    static let asyncQuestionTools: Set<String> = ["request_user_input_async"]
    static let shellTools: Set<String> = ["Bash", "shell", "exec_command", "local_shell"]
    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch"]

    struct Next { var state: SessionState; var status: String; var awaitingAnswer = false }

    /// Returns the row's next state, or nil when the event doesn't change it.
    static func transition(_ e: HookEvent, current: Session?) -> Next? {
        let tool = e.toolName ?? ""
        let waiting = current?.awaitingAnswer == true
        switch e.name {
        case "UserPromptSubmit":
            return Next(state: .working, status: "Thinking")
        case "PostToolUse":
            if waiting, let current { return Next(state: current.state, status: current.status, awaitingAnswer: true) }
            return Next(state: .working, status: "Thinking")
        case "PreToolUse":
            if questionTools.contains(tool) {
                return Next(state: .question, status: questionStatus(e), awaitingAnswer: asyncQuestionTools.contains(tool))
            }
            return Next(state: .working, status: toolStatus(tool, input: e.toolInput))
        case "PermissionRequest":
            if questionTools.contains(tool) { return Next(state: .question, status: questionStatus(e), awaitingAnswer: waiting) }
            return Next(state: .permission, status: permissionStatus(tool, input: e.toolInput))
        case "Notification":
            guard e.notificationType == "permission_prompt" else { return nil }
            if let current, current.state.needsUser {
                return Next(state: current.state, status: current.status, awaitingAnswer: current.awaitingAnswer)
            }
            return Next(state: .permission, status: "Needs permission")
        case "Stop":
            if waiting, let current { return Next(state: current.state, status: current.status, awaitingAnswer: true) }
            return Next(state: .done, status: "Done")
        default:
            return nil
        }
    }

    static func questionStatus(_ e: HookEvent) -> String {
        let first = e.toolInput?["questions"]?[0]
        let q = first?["question"]?.string ?? first?["title"]?.string
        return q.map { "Asking: \($0)" } ?? "Asking a question"
    }

    static func toolStatus(_ tool: String, input: [String: JSONValue]?) -> String {
        if shellTools.contains(tool) { return "Running command" }
        if editTools.contains(tool), let path = input?["file_path"]?.string {
            return "Editing \(URL(fileURLWithPath: path).lastPathComponent)"
        }
        return "Using \(tool)"
    }

    static func permissionStatus(_ tool: String, input: [String: JSONValue]?) -> String {
        if let command = input?["command"]?.string { return "Allow \(tool): \(command)" }
        if let path = input?["file_path"]?.string { return "Allow \(tool): \(URL(fileURLWithPath: path).lastPathComponent)" }
        return "Allow \(tool)?"
    }

    static func truncate(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        guard oneLine.count > statusLimit else { return oneLine }
        return String(oneLine.prefix(statusLimit - 1)) + "…"
    }
}
