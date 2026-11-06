import AgentGlanceCore
import Foundation

/// Watches a Claude transcript only while its row is red or yellow, to catch a denied permission
/// (no hook fires for that). Uses kqueue file events, so it costs nothing until the file changes.
@MainActor
final class TranscriptWatchers {
    private var sources: [SessionKey: DispatchSourceFileSystemObject] = [:]

    func sync(_ sessions: [Session], onInterrupted: @escaping @MainActor (SessionKey) -> Void) {
        let wanted = Dictionary(uniqueKeysWithValues: sessions.compactMap { s -> (SessionKey, String)? in
            guard s.key.source == .claude, s.state.needsUser, let path = s.transcriptPath else { return nil }
            return (s.key, path)
        })
        for key in sources.keys where wanted[key] == nil {
            sources.removeValue(forKey: key)?.cancel()
        }
        for (key, path) in wanted where sources[key] == nil {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
            let url = URL(fileURLWithPath: path)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    if let tail = TranscriptSignals.readTail(url), TranscriptSignals.isInterrupted(tail: tail) {
                        onInterrupted(key)
                    }
                }
            }
            source.setCancelHandler { close(fd) }
            sources[key] = source
            source.resume()
        }
    }
}
