import Foundation

/// Reads the end of a Claude Code transcript for things no hook reports. Denying a permission
/// (or stopping a question) writes a rejected tool result and an "interrupted" marker, then the
/// turn ends without a `Stop` hook.
public enum TranscriptSignals {
    public static let tailBytes = 16 * 1024
    static let interruptMarker = "[Request interrupted by user"

    /// True when the newest user/assistant entry is the interrupt marker or a rejected tool use.
    public static func isInterrupted(tail: Data) -> Bool {
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant" else { continue }
            if type == "assistant" { return false }
            if (obj["toolUseResult"] as? String) == "User rejected tool use" { return true }
            let content = (obj["message"] as? [String: Any])?["content"]
            if let text = content as? String { return text.hasPrefix(interruptMarker) }
            let parts = content as? [[String: Any]] ?? []
            return parts.contains { ($0["text"] as? String)?.hasPrefix(interruptMarker) == true }
        }
        return false
    }

    /// Reads the last `tailBytes` of a file.
    public static func readTail(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        return try? handle.readToEnd()
    }
}
