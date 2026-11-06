import AppKit
import SwiftUI

/// A borderless panel that floats above other windows on every Space (including full-screen
/// apps), never activates the app when clicked, and keeps its top edge fixed as it resizes.
final class FloatingPanel: NSPanel {
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
        host.sizingOptions = []  // sized by fit(_:) so collapse animations aren't clipped
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        contentViewController = host
        restorePosition()
    }

    override var canBecomeKey: Bool { false }  // never takes keyboard focus from your app
    override var canBecomeMain: Bool { false }

    // MARK: - Size

    private var pendingShrink: DispatchWorkItem?
    /// How long a collapse animation runs before the window shrinks to fit.
    static let shrinkDelay: TimeInterval = 0.32

    /// The window is always as big as the expanded list (the area around the pill is fully
    /// transparent, so clicks there fall through to the windows below). It only resizes when
    /// rows come or go: at once when growing, after the collapse animation when shrinking.
    /// The top-left corner stays put, so the pill never moves and the list grows to the right.
    func fit(_ size: CGSize) {
        let target = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard target != frame.size else { return }
        pendingShrink?.cancel()
        if target.width >= frame.width && target.height >= frame.height {
            resize(to: target)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.resize(to: target) }
            pendingShrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
        }
    }

    private func resize(to size: NSSize) {
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: - Position

    private static let originKey = "panelTopLeftCorner"

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
        setFrameTopLeftPoint(NSPoint(x: visible.midX - 40, y: visible.maxY - 8))
    }
}
