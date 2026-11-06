import AgentGlanceCore
import AppKit
import ApplicationServices

/// Delivers dictated text: focus the session, verify it's in front with its message box focused,
/// paste and press Return, then put the user's clipboard back. Anything unverified is only copied.
@MainActor
struct MessageSender {
    let focuser: SessionFocuser
    static let restoreDelay: Duration = .milliseconds(300)
    static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]
    /// macOS's Accessibility prompt is shown at most once per launch; after that, only the notice.
    static var promptedThisLaunch = false

    /// Returns a notice for the panel, or nil when the text was sent.
    func send(_ text: String, to session: Session) async -> String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Nothing to send." }
        guard Self.accessibilityTrusted(prompt: !Self.promptedThisLaunch) else {
            Self.promptedThisLaunch = true
            copy(text)
            return "Allow Agent Glance in System Settings → Accessibility to send. Text copied."
        }
        let verified = await focuser.focus(session)
        let decision = DeliveryPlan.decide(text: text, verifiedFrontmost: verified,
                                           inputFocused: verified && Self.frontmostTextInputFocused(),
                                           title: session.title)
        switch decision {
        case .copyOnly(let notice):
            copy(text)
            return notice
        case .paste:
            let saved = Self.snapshotClipboard()
            copy(text)
            Self.press(key: 9, flags: .maskCommand)  // ⌘V
            try? await Task.sleep(for: .milliseconds(80))
            Self.press(key: 36, flags: [])  // Return
            try? await Task.sleep(for: Self.restoreDelay)
            Self.restoreClipboard(saved)
            return nil
        }
    }

    // MARK: - Accessibility

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// True when the frontmost app's focused element is a text input. Electron apps (Claude,
    /// Codex) only expose their web content to Accessibility after `AXManualAccessibility` is set.
    static func frontmostTextInputFocused() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
        return (role as? String).map(textRoles.contains) ?? false
    }

    static func press(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Clipboard

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func snapshotClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    static func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let board = NSPasteboard.general
        board.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { board.writeObjects(restored) }
    }
}
