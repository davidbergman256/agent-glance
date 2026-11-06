import AgentGlanceCore
import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let focuser = SessionFocuser()
    private var panel: FloatingPanel!
    private var statusItem: StatusItemController!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        panel = FloatingPanel(content: PanelView(
            model: model,
            onFocus: { [weak self] session in self?.focus(session) },
            onMic: { [weak self] session in self?.dictate(into: session) },
            onSize: { [weak self] size in self?.panel?.fit(size) },
            onToggleCompact: { [weak self] in self?.setCompact(!AppSettings.compactView) }
        ))
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.savePosition() }
        }
        statusItem = StatusItemController(model: model, app: self)
        hotKey = HotKey { [weak self] in self?.togglePanel() }
        ensureHooks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    // MARK: - Panel

    var panelVisible: Bool { panel?.isVisible == true }

    func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    func setCompact(_ compact: Bool) {
        AppSettings.compactView = compact
        model.compactView = compact
    }

    // MARK: - Rows

    func focus(_ session: Session) {
        Task {
            let verified = await focuser.focus(session)
            if session.state == .done { model.store.dismiss(session.key) }
            if !verified { model.showNotice("Opened \(Theme.sourceName(session.key.source)), but couldn't confirm the session.") }
        }
    }

    // MARK: - Dictation

    private let dictation = Dictation()
    private var keyMonitor: Any?

    /// Mic button: starts dictating into the session, or, on the recording row, finishes and sends.
    func dictate(into session: Session?) {
        guard let session else {
            model.showNotice("No session to dictate into yet.")
            return
        }
        if model.dictatingKey == session.key {
            finishDictation()
            return
        }
        dictation.cancel()
        model.dictatingKey = session.key
        model.transcript = ""
        dictation.onTranscript = { [weak self] text in self?.model.transcript = text }
        beginKeyboardCapture()
        Task {
            do {
                try await dictation.start(for: session.key)
            } catch {
                endDictationUI()
                model.showNotice(error.localizedDescription)
            }
        }
    }

    private func finishDictation() {
        guard let key = model.dictatingKey else { return }
        endKeyboardCapture()
        Task {
            let text = await dictation.finish()
            let session = model.store.sessions.first { $0.key == key }
            endDictationUI()
            guard let session else {
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                model.showNotice("That session ended. Text copied.")
                return
            }
            if let notice = await MessageSender(focuser: focuser).send(text, to: session) {
                model.showNotice(notice)
            }
        }
    }

    private func cancelDictation() {
        dictation.cancel()
        endDictationUI()
    }

    private func endDictationUI() {
        endKeyboardCapture()
        model.dictatingKey = nil
        model.transcript = ""
    }

    /// While dictating, the panel takes key status (without activating the app) so Return and Esc
    /// reach it; everything else is swallowed so stray keys don't go anywhere.
    private func beginKeyboardCapture() {
        panel.acceptsKeyboard = true
        panel.makeKey()
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                switch event.keyCode {
                case 36, 76: self?.finishDictation()  // Return, Enter
                case 53: self?.cancelDictation()  // Esc
                default: break
                }
            }
            return nil
        }
    }

    private func endKeyboardCapture() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.acceptsKeyboard = false
        panel.resignKey()
    }

    // MARK: - Hooks

    /// Hook command for a source. Quoted because the bundle path contains a space.
    func hookCommand(_ source: Source) -> String {
        "'\(Bundle.main.bundlePath)/Contents/MacOS/agent-glance-hook' --source \(source.rawValue)"
    }

    func installer(_ source: Source) -> HookInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch source {
        case .claude: HookInstaller(settingsURL: home.appendingPathComponent(".claude/settings.json"),
                                    command: hookCommand(.claude), events: HookInstaller.claudeEvents)
        case .codex: HookInstaller(settingsURL: home.appendingPathComponent(".codex/hooks.json"),
                                   command: hookCommand(.codex), events: HookInstaller.codexEvents)
        }
    }

    /// Asks once before touching the agents' settings; afterwards keeps enabled sources installed.
    private func ensureHooks() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }  // `swift run` builds: don't install
        if !AppSettings.hooksConsentAsked {
            AppSettings.hooksConsentAsked = true
            let alert = NSAlert()
            alert.messageText = "Connect Claude Code and Codex?"
            alert.informativeText = """
            Agent Glance adds small hooks to ~/.claude/settings.json and ~/.codex/hooks.json so it can see \
            when a session is working, waiting for you, or done. Your other settings stay as they are, \
            and you can remove the hooks from the menu at any time. Codex will ask you to trust the hooks once.
            """
            alert.addButton(withTitle: "Connect")
            alert.addButton(withTitle: "Not now")
            NSApp.activate()
            if alert.runModal() != .alertFirstButtonReturn {
                for source in Source.allCases { setSource(source, enabled: false) }
                return
            }
        }
        for source in Source.allCases where model.enabledSources.contains(source) {
            setSource(source, enabled: true)
        }
    }

    func setSource(_ source: Source, enabled: Bool) {
        do {
            let installer = installer(source)
            if enabled { if !installer.isInstalled() { try installer.install() } } else { try installer.uninstall() }
            AppSettings.setEnabled(source, enabled)
            if enabled { model.enabledSources.insert(source) } else { model.enabledSources.remove(source) }
        } catch {
            model.showNotice("Couldn't update \(Theme.sourceName(source)) settings: the file isn't valid JSON.")
        }
    }

    // MARK: - Launch at login

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func toggleLaunchAtLogin() {
        do {
            if launchesAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            model.showNotice("Couldn't change launch at login.")
        }
    }
}
