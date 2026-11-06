import AgentGlanceCore
import AppKit
import Observation

/// The menu bar item: a row of colored dots mirroring the sessions, plus the app's menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private weak var app: AppDelegate?
    static let maxDots = 5

    init(model: AppModel, app: AppDelegate) {
        self.model = model
        self.app = app
        super.init()
        item.button?.toolTip = "Agent Glance"
        render()
        observe()
        item.menu = buildMenu()
    }

    // MARK: - Icon

    private func observe() {
        withObservationTracking {
            _ = model.store.sessions.map(\.state)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.render()
                self?.observe()
            }
        }
    }

    private func render() {
        let states = model.store.sessions.prefix(Self.maxDots).map(\.state)
        item.button?.image = Self.dotsImage(states)
    }

    static func dotsImage(_ states: [SessionState]) -> NSImage {
        let dot: CGFloat = 6, gap: CGFloat = 3
        let colors: [NSColor] = states.isEmpty ? [.tertiaryLabelColor] : states.map(Theme.nsColor)
        let width = CGFloat(colors.count) * dot + CGFloat(colors.count - 1) * gap
        return NSImage(size: NSSize(width: width, height: 16), flipped: false) { _ in
            for (i, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: CGFloat(i) * (dot + gap), y: 5, width: dot, height: dot)).fill()
            }
            return true
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let show = NSMenuItem(title: "Show panel", action: #selector(togglePanel), keyEquivalent: "a")
        show.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(show)
        menu.addItem(NSMenuItem(title: "Compact view", action: #selector(toggleCompact), keyEquivalent: ""))
        menu.addItem(.separator())
        let header = NSMenuItem(title: "Sources", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for source in Source.allCases {
            let entry = NSMenuItem(title: Theme.sourceName(source), action: #selector(toggleSource(_:)), keyEquivalent: "")
            entry.representedObject = source.rawValue
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for entry in menu.items where entry.action != #selector(NSApplication.terminate(_:)) { entry.target = self }
        return menu
    }

    @objc private func togglePanel() { app?.togglePanel() }
    @objc private func toggleCompact() { app?.setCompact(!AppSettings.compactView) }
    @objc private func toggleLaunchAtLogin() { app?.toggleLaunchAtLogin() }
    @objc private func toggleSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = Source(rawValue: raw) else { return }
        app?.setSource(source, enabled: !model.enabledSources.contains(source))
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for entry in menu.items {
            switch entry.action {
            case #selector(togglePanel): entry.title = app?.panelVisible == true ? "Hide panel" : "Show panel"
            case #selector(toggleCompact): entry.state = AppSettings.compactView ? .on : .off
            case #selector(toggleLaunchAtLogin): entry.state = app?.launchesAtLogin == true ? .on : .off
            case #selector(toggleSource(_:)):
                let source = (entry.representedObject as? String).flatMap(Source.init(rawValue:))
                entry.state = source.map { model.enabledSources.contains($0) } == true ? .on : .off
            default: break
            }
        }
    }
}
