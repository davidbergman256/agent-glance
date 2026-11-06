import Foundation

/// Links that open one exact session in its desktop app (both confirmed by hand, see docs/spike-findings.md).
public enum DeepLinks {
    public static func bundleId(_ source: Source) -> String {
        switch source {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    /// `codex://threads/<id>`, or `claude://claude.ai/epitaxy/<local id>` once the desktop id is known.
    public static func url(for session: Session, claudeLocalId: String?) -> URL? {
        switch session.key.source {
        case .codex: URL(string: "codex://threads/\(session.key.id)")
        case .claude: claudeLocalId.flatMap { URL(string: "claude://claude.ai/epitaxy/\($0)") }
        }
    }
}

/// Maps a Claude Code CLI session id (the hook's `session_id`) to the Claude desktop app's
/// `local_<uuid>` id, using the app's per-session records.
public enum ClaudeSessionIndex {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// Scans `<root>/<account>/<org>/local_*.json` for the record whose `cliSessionId` matches.
    /// Each file is only parsed when its bytes contain the id, so a scan stays cheap.
    public static func localId(cliSessionId: String, root: URL = defaultRoot) -> String? {
        let needle = Data(cliSessionId.utf8)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker
        where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.range(of: needle) != nil,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  obj["cliSessionId"] as? String == cliSessionId else { continue }
            return obj["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent
        }
        return nil
    }

    /// True when this session's record has the newest `lastFocusedAt` of all records, which is
    /// how the Claude app marks the session its window is showing.
    public static func isMostRecentlyFocused(localId: String, root: URL = defaultRoot) -> Bool {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
        var newest: (id: String, at: Double)?
        for case let url as URL in walker
        where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let at = (obj["lastFocusedAt"] as? NSNumber)?.doubleValue else { continue }
            let id = obj["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent
            if newest == nil || at > newest!.at { newest = (id, at) }
        }
        return newest?.id == localId
    }
}
