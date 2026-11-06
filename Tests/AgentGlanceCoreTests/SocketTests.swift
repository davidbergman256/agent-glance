import Foundation
import Testing
@testable import AgentGlanceCore

/// The hook binary built by `scripts/test.sh` before the tests run.
let hookBinary = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".build/debug/agent-glance-hook")

/// Short socket path: Unix socket paths are limited to 104 bytes.
func tempSocket() -> URL {
    URL(fileURLWithPath: "/tmp/ag-\(UUID().uuidString.prefix(8)).sock")
}

struct HookRun { let status: Int32; let stdout: Data; let seconds: Double }

func runHook(stdin: String, socket: URL, source: String = "claude") throws -> HookRun {
    let p = Process()
    p.executableURL = hookBinary
    p.arguments = ["--source", source, "--socket", socket.path]
    let input = Pipe(), output = Pipe()
    p.standardInput = input
    p.standardOutput = output
    p.standardError = output
    let start = Date()
    try p.run()
    input.fileHandleForWriting.write(Data(stdin.utf8))
    try input.fileHandleForWriting.close()
    p.waitUntilExit()
    let out = output.fileHandleForReading.readDataToEndOfFile()
    return HookRun(status: p.terminationStatus, stdout: out, seconds: Date().timeIntervalSince(start))
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HookEvent] = []
    func add(_ e: HookEvent) { lock.withLock { events.append(e) } }
    var all: [HookEvent] { lock.withLock { events } }
}

@Suite(.serialized)
struct SocketTests {
    @Test func serverReceivesEnvelope() async throws {
        let path = tempSocket()
        let box = EventBox()
        let server = try EventSocketServer(path: path) { box.add($0) }
        server.start()
        defer { server.stop() }
        let run = try runHook(stdin: #"{"hook_event_name":"Stop","session_id":"abc"}"#, socket: path)
        #expect(run.status == 0)
        for _ in 0..<100 where box.all.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(box.all.first?.name == "Stop")
        #expect(box.all.first?.sessionId == "abc")
        #expect(box.all.first?.source == .claude)
    }

    @Test func hookExitsZeroFastWithNoServer() throws {
        let run = try runHook(stdin: #"{"hook_event_name":"Stop","session_id":"abc"}"#,
                              socket: URL(fileURLWithPath: "/tmp/ag-missing-\(UUID().uuidString.prefix(6)).sock"))
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.seconds < 0.3)
    }

    @Test func hookExitsZeroOnGarbageStdin() throws {
        let path = tempSocket()
        let box = EventBox()
        let server = try EventSocketServer(path: path) { box.add($0) }
        server.start()
        defer { server.stop() }
        let run = try runHook(stdin: "not json {{{", socket: path)
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test func serverReplacesStaleSocketFile() throws {
        let path = tempSocket()
        FileManager.default.createFile(atPath: path.path, contents: Data("stale".utf8))
        let server = try EventSocketServer(path: path) { _ in }
        server.start()
        server.stop()
    }

    @Test func pathsSocketIsInSupportDir() {
        #expect(Paths.socket.lastPathComponent == "events.sock")
        #expect(Paths.socket.deletingLastPathComponent() == Paths.supportDir)
        #expect(Paths.supportDir.path.hasSuffix("Library/Application Support/AgentGlance"))
    }
}
