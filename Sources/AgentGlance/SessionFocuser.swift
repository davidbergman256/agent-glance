import AgentGlanceCore
import AppKit
import ApplicationServices

/// Brings a session to the front with its deep link, then checks it really is the one showing.
/// The check is what makes dictation safe: text is only ever typed into a verified session.
@MainActor
final class SessionFocuser {
    private var claudeLocalIds: [String: String] = [:]
    static let settle: Duration = .milliseconds(300)
    static let attempts = 12

    /// Opens the session and returns true once it is verified frontmost (gives up after ~1.5 s).
    func focus(_ session: Session) async -> Bool {
        let localId = session.key.source == .claude ? await claudeLocalId(session.key.id) : nil
        guard let url = DeepLinks.url(for: session, claudeLocalId: localId) else {
            NSRunningApplication.runningApplications(withBundleIdentifier: DeepLinks.bundleId(session.key.source))
                .first?.activate()
            return false  // the app is in front, but which session it shows can't be verified
        }
        NSWorkspace.shared.open(url)
        try? await Task.sleep(for: Self.settle)  // let the app navigate before checking
        for _ in 0..<Self.attempts {
            if await isFrontmost(session, claudeLocalId: localId) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func isFrontmost(_ session: Session, claudeLocalId: String?) async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == DeepLinks.bundleId(session.key.source) else {
            return false
        }
        switch session.key.source {
        case .claude:
            guard let localId = claudeLocalId else { return false }
            return await Task.detached(priority: .userInitiated) {
                ClaudeSessionIndex.isMostRecentlyFocused(localId: localId)
            }.value
        case .codex:
            return codexWindowMatches(session)
        }
    }

    private func claudeLocalId(_ cliSessionId: String) async -> String? {
        if let cached = claudeLocalIds[cliSessionId] { return cached }
        let found = await Task.detached(priority: .userInitiated) {
            ClaudeSessionIndex.localId(cliSessionId: cliSessionId)
        }.value
        if let found { claudeLocalIds[cliSessionId] = found }
        return found
    }

    /// Codex has no focus record, so after its (exact) deep link we also read the focused window's
    /// title when Accessibility is granted. A title naming a different thread fails the check.
    private func codexWindowMatches(_ session: Session) -> Bool {
        guard AXIsProcessTrusted(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return true }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return true }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        guard let text = title as? String, !text.isEmpty, text != "Codex", session.title != SessionStore.untitled else {
            return true
        }
        return text.localizedCaseInsensitiveContains(session.title)
    }
}
