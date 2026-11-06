import AgentGlanceCore
import Foundation
import Observation

/// Owns the session table and the socket server, and keeps titles fresh.
@Observable @MainActor
final class AppModel {
    let store = SessionStore()
    /// One-line notice shown in the panel (for example after a failed delivery).
    var notice: String?
    var enabledSources: Set<Source> = Set(Source.allCases.filter { AppSettings.isEnabled($0) })
    /// When true the panel rests as the pill and expands on hover; when false the list stays open.
    var compactView = AppSettings.compactView
    /// Bumped when a session newly needs you; each bump plays one bounce of its dot.
    var bounces: [SessionKey: Int] = [:]
    /// The session being dictated into, and the live transcript (Task 9).
    var dictatingKey: SessionKey?
    var transcript = ""

    @ObservationIgnored private var server: EventSocketServer?
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let watchers = TranscriptWatchers()

    func start() {
        server = try? EventSocketServer(path: Paths.socket) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        server?.start()
    }

    func stop() {
        server?.stop()
    }

    func handle(_ event: HookEvent) {
        guard enabledSources.contains(event.source) else { return }
        let key = SessionKey(source: event.source, id: event.sessionId)
        let before = store.sessions.first { $0.key == key }
        let isNew = before == nil
        store.apply(event, now: Date())
        let after = store.sessions.first { $0.key == key }
        if after?.state.needsUser == true, before?.state.needsUser != true {
            bounces[key, default: 0] += 1
        }
        bounces = bounces.filter { k, _ in store.sessions.contains { $0.key == k } }
        if isNew || event.name == "UserPromptSubmit" || event.name == "Stop" {
            refreshTitle(key, transcriptPath: event.transcriptPath)
        }
        updateExpiryTimer()
        syncWatchers()
    }

    private func syncWatchers() {
        watchers.sync(store.sessions) { [weak self] key in
            self?.store.markInterrupted(key, now: Date())
            self?.syncWatchers()
        }
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    private func refreshTitle(_ key: SessionKey, transcriptPath: String?) {
        Task.detached(priority: .utility) {
            let title: String? = switch key.source {
            case .claude: transcriptPath.flatMap { Titles.claude(transcriptPath: URL(fileURLWithPath: $0)) }
            case .codex: Titles.codex(threadId: key.id)
            }
            guard let title else { return }
            await MainActor.run { [weak self] in self?.store.setTitle(title, for: key) }
        }
    }

    /// The only timer in the app: runs once a minute while there are sessions, otherwise stopped.
    private func updateExpiryTimer() {
        if store.sessions.isEmpty {
            expiryTimer?.invalidate()
            expiryTimer = nil
        } else if expiryTimer == nil {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.store.expire(now: Date())
                    self?.updateExpiryTimer()
                }
            }
            timer.tolerance = 10
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
        }
    }
}

/// Small persisted preferences.
enum AppSettings {
    static func isEnabled(_ source: Source) -> Bool {
        UserDefaults.standard.object(forKey: "source.\(source.rawValue)") as? Bool ?? true
    }

    static func setEnabled(_ source: Source, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "source.\(source.rawValue)")
    }

    static var compactView: Bool {
        get { UserDefaults.standard.object(forKey: "compactView") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "compactView") }
    }

    static var hooksConsentAsked: Bool {
        get { UserDefaults.standard.bool(forKey: "hooksConsentAsked") }
        set { UserDefaults.standard.set(newValue, forKey: "hooksConsentAsked") }
    }
}
