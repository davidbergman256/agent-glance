import Foundation

public enum SessionState: Sendable, Equatable {
    case working, permission, question, done

    /// Red and yellow rows: the session is blocked on the user.
    public var needsUser: Bool { self == .permission || self == .question }
}

public struct SessionKey: Hashable, Sendable {
    public let source: Source
    public let id: String
    public init(source: Source, id: String) {
        self.source = source
        self.id = id
    }
}

public struct Session: Identifiable, Sendable, Equatable {
    public var key: SessionKey
    public var title: String
    public var state: SessionState
    public var status: String
    public var updatedAt: Date
    public var transcriptPath: String?
    /// Codex's async question tool returns at once and the turn ends while the card still
    /// waits; this keeps the row yellow until the next prompt.
    public var awaitingAnswer = false

    public var id: SessionKey { key }
}
