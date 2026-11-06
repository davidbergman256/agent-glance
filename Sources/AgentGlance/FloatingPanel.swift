import AppKit
import SwiftUI

/// A borderless panel that floats above other windows on every Space (including full-screen
/// apps), never activates the app when clicked, and keeps its top edge fixed as it resizes.
final class FloatingPanel: NSPanel {
    /// Set while dictating, so Return and Esc reach the panel.
    var acceptsKeyboard = false

    init<Content: View>(content: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 34),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        contentViewController = host
        restorePosition()
    }

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    /// Grow and shrink downward from a fixed top edge.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if frame.size != .zero, rect.size != frame.size, rect.origin == frame.origin {
            rect.origin.y = frame.maxY - rect.height
        }
        super.setFrame(rect, display: flag)
    }

    // MARK: - Position

    private static let originKey = "panelTopLeft"

    func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.originKey)
    }

    private func restorePosition() {
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let topLeft = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -20, dy: -20).contains(topLeft) }) {
                setFrameTopLeftPoint(topLeft)
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameTopLeftPoint(NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - 8))
    }
}
