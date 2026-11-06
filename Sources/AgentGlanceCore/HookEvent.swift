import Foundation

/// Which desktop app a session belongs to.
public enum Source: String, Codable, Sendable, CaseIterable {
    case claude, codex
}

/// Any JSON value, used for free-form hook fields such as `tool_input`.
public enum JSONValue: Decodable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public subscript(key: String) -> JSONValue? { if case .object(let o) = self { o[key] } else { nil } }
    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { a[index] } else { nil }
    }
}

/// One hook invocation, as forwarded by `agent-glance-hook`: `{"source": "...", "payload": {hook JSON}}`.
public struct HookEvent: Decodable, Sendable {
    public let source: Source
    public let name: String
    public let sessionId: String
    public let transcriptPath: String?
    public let toolName: String?
    public let toolInput: [String: JSONValue]?
    public let notificationType: String?
    public let message: String?

    private enum EnvelopeKeys: String, CodingKey { case source, payload }
    private enum PayloadKeys: String, CodingKey {
        case name = "hook_event_name", sessionId = "session_id", transcriptPath = "transcript_path"
        case toolName = "tool_name", toolInput = "tool_input"
        case notificationType = "notification_type", message
    }

    public init(from decoder: Decoder) throws {
        let env = try decoder.container(keyedBy: EnvelopeKeys.self)
        source = try env.decode(Source.self, forKey: .source)
        let p = try env.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        name = try p.decode(String.self, forKey: .name)
        sessionId = try p.decode(String.self, forKey: .sessionId)
        transcriptPath = try p.decodeIfPresent(String.self, forKey: .transcriptPath)
        toolName = try p.decodeIfPresent(String.self, forKey: .toolName)
        toolInput = try? p.decodeIfPresent([String: JSONValue].self, forKey: .toolInput)
        notificationType = try p.decodeIfPresent(String.self, forKey: .notificationType)
        message = try p.decodeIfPresent(String.self, forKey: .message)
    }
}
