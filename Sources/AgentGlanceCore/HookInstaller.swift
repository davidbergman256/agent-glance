import Foundation

public enum HookInstallerError: Error, Equatable {
    case malformedSettings
}

/// Adds and removes Agent Glance's hook entries in a Claude Code `settings.json` or a Codex
/// `hooks.json`, leaving every other key and every other hook untouched. Our entries are
/// recognised by their command containing `agent-glance-hook`.
public struct HookInstaller: Sendable {
    public let settingsURL: URL
    public let command: String
    public let events: [String]

    public static let claudeEvents = [
        "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Notification", "Stop", "SessionEnd",
    ]
    /// Codex has no `Notification` hook.
    public static let codexEvents = [
        "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd",
    ]
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PermissionRequest"]
    static let marker = "agent-glance-hook"
    static let timeoutSeconds = 2

    public init(settingsURL: URL, command: String, events: [String]) {
        self.settingsURL = settingsURL
        self.command = command
        self.events = events
    }

    public func install() throws {
        var root = try load()
        writeBackupIfNeeded()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var list = (hooks[event] as? [[String: Any]] ?? []).filter { !Self.isOurs($0) }
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": Self.timeoutSeconds]]]
            if Self.toolEvents.contains(event) { entry["matcher"] = "*" }
            list.append(entry)
            hooks[event] = list
        }
        root["hooks"] = hooks
        try save(root)
    }

    public func uninstall() throws {
        var root = try load()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            let kept = list.filter { !Self.isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try save(root)
    }

    public func isInstalled() -> Bool {
        guard let root = try? load(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in (hooks[event] as? [[String: Any]] ?? []).contains(where: Self.isOurs) }
    }

    // MARK: - File handling

    static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    /// Missing or blank files count as `{}`; anything else that isn't a JSON object is refused.
    func load() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw HookInstallerError.malformedSettings
        }
        return dict
    }

    func save(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    func writeBackupIfNeeded() {
        let backup = settingsURL.appendingPathExtension("agentglance-bak")
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.copyItem(at: settingsURL, to: backup)
    }
}
