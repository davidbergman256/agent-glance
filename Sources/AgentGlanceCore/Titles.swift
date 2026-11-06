import Foundation

/// Looks up a session's display title. Called only when a hook event arrives, never polled,
/// and it reads just the slice of the log it needs.
public enum Titles {
    static let tailBytes = 256 * 1024
    static let headBytes = 64 * 1024
    static let fallbackWords = 6

    /// The latest `custom-title` in a Claude Code transcript, or the first words of the
    /// first real user prompt when the session has no title yet.
    public static func claude(transcriptPath: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: transcriptPath) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        let tail = (try? handle.readToEnd()) ?? Data()
        for line in lines(tail).reversed() {
            if let obj = json(line), obj["type"] as? String == "custom-title",
               let title = obj["customTitle"] as? String, !title.isEmpty {
                return title
            }
        }
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: headBytes)) ?? Data()
        for line in lines(head) {
            guard let obj = json(line), obj["type"] as? String == "user",
                  let text = userText(obj), !text.hasPrefix("<") else { continue }
            return firstWords(text)
        }
        return nil
    }

    /// The latest `thread_name` for a Codex thread in `~/.codex/session_index.jsonl`.
    public static func codex(
        threadId: String,
        index: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/session_index.jsonl")
    ) -> String? {
        guard let data = try? Data(contentsOf: index, options: .mappedIfSafe) else { return nil }
        let needle = Data("\"\(threadId)\"".utf8)
        for line in lines(data).reversed() where line.range(of: needle) != nil {
            if let obj = json(line), obj["id"] as? String == threadId, let name = obj["thread_name"] as? String {
                return name
            }
        }
        return nil
    }

    // MARK: - Helpers

    static func lines(_ data: Data) -> [Data] {
        data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
    }

    static func json(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    static func userText(_ obj: [String: Any]) -> String? {
        guard let message = obj["message"] as? [String: Any] else { return nil }
        if let s = message["content"] as? String { return s }
        let parts = message["content"] as? [[String: Any]] ?? []
        return parts.first { $0["type"] as? String == "text" }?["text"] as? String
    }

    static func firstWords(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let head = words.prefix(fallbackWords).joined(separator: " ")
        return words.count > fallbackWords ? head + "…" : head
    }
}
