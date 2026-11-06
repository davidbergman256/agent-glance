import Foundation

public enum Paths {
    /// `~/Library/Application Support/AgentGlance`, created on first access.
    public static var supportDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentGlance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The Unix socket `agent-glance-hook` writes to.
    public static var socket: URL { supportDir.appendingPathComponent("events.sock") }
}
