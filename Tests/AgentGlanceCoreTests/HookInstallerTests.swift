import Foundation
import Testing
@testable import AgentGlanceCore

struct HookInstallerTests {
    let dir: URL
    let settings: URL
    let command = "/Apps/Agent Glance.app/Contents/MacOS/agent-glance-hook --source claude"

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings = dir.appendingPathComponent("settings.json")
    }

    var installer: HookInstaller {
        HookInstaller(settingsURL: settings, command: command, events: HookInstaller.claudeEvents)
    }

    func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    }

    func entries(_ event: String) throws -> [[String: Any]] {
        ((try read())["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    func ours(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains("agent-glance-hook") == true }
    }

    @Test func installIntoMissingFileCreatesIt() throws {
        try installer.install()
        #expect(try entries("Stop").filter(ours).count == 1)
        #expect(installer.isInstalled())
    }

    @Test func installIntoEmptyFileTreatsItAsEmptyObject() throws {
        try Data().write(to: settings)
        try installer.install()
        #expect(try entries("Stop").filter(ours).count == 1)
    }

    @Test func installPreservesUnrelatedKeysAndOtherHooks() throws {
        let user: [String: Any] = [
            "model": "opus",
            "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-linter"]]]]],
        ]
        try JSONSerialization.data(withJSONObject: user).write(to: settings)
        try installer.install()
        #expect((try read())["model"] as? String == "opus")
        let pre = try entries("PreToolUse")
        #expect(pre.count == 2)
        #expect((pre[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "my-linter")
        #expect(ours(pre[1]))
    }

    @Test func installIsIdempotent() throws {
        try installer.install()
        try installer.install()
        for event in HookInstaller.claudeEvents {
            #expect(try entries(event).filter(ours).count == 1)
        }
    }

    @Test func uninstallRemovesOnlyOurs() throws {
        let user: [String: Any] = ["hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-linter"]]]]]]
        try JSONSerialization.data(withJSONObject: user).write(to: settings)
        try installer.install()
        try installer.uninstall()
        #expect(try entries("PreToolUse").count == 1)
        #expect(((try read())["hooks"] as? [String: Any])?["Stop"] == nil)
        #expect(installer.isInstalled() == false)
    }

    @Test func uninstallDropsEmptyHooksKey() throws {
        try JSONSerialization.data(withJSONObject: ["model": "opus"]).write(to: settings)
        try installer.install()
        try installer.uninstall()
        #expect((try read())["hooks"] == nil)
        #expect((try read())["model"] as? String == "opus")
    }

    @Test func malformedJSONThrowsAndLeavesFileByteIdentical() throws {
        let bad = Data("{ \"model\": \"opus\", ".utf8)
        try bad.write(to: settings)
        #expect(throws: HookInstallerError.malformedSettings) { try installer.install() }
        #expect(try Data(contentsOf: settings) == bad)
    }

    @Test func installWritesBackupOnce() throws {
        try JSONSerialization.data(withJSONObject: ["model": "first"]).write(to: settings)
        try installer.install()
        let backup = dir.appendingPathComponent("settings.json.agentglance-bak")
        let original = try Data(contentsOf: backup)
        try installer.install()
        #expect(try Data(contentsOf: backup) == original)
        #expect((try JSONSerialization.jsonObject(with: original) as? [String: Any])?["model"] as? String == "first")
    }

    @Test func matcherStarOnToolEvents() throws {
        try installer.install()
        for event in ["PreToolUse", "PostToolUse", "PermissionRequest"] {
            #expect(try entries(event).first(where: ours)?["matcher"] as? String == "*")
        }
        #expect(try entries("Stop").first(where: ours)?["matcher"] == nil)
        let hook = (try entries("Stop").first(where: ours)?["hooks"] as? [[String: Any]])?.first
        #expect(hook?["type"] as? String == "command")
        #expect(hook?["command"] as? String == command)
        #expect(hook?["timeout"] as? Int == 2)
    }

    @Test func pathsAreNotSlashEscaped() throws {
        try installer.install()
        let text = String(decoding: try Data(contentsOf: settings), as: UTF8.self)
        #expect(text.contains("/Apps/Agent Glance.app/Contents/MacOS/agent-glance-hook"))
    }
}
