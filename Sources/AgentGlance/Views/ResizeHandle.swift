import AppKit
import SwiftUI

/// The right-edge width handle. Plain AppKit on purpose: Agent Glance never becomes the active
/// app, and SwiftUI's pointer styles and drag gestures don't fire reliably in an inactive
/// app's panel. This view tracks the mouse itself, sets the ↔ cursor, and never moves the window.
struct ResizeHandle: NSViewRepresentable {
    var onBegin: () -> Void
    /// Horizontal distance dragged since the press, in points.
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.callbacks = (onBegin, onDrag, onEnd)
        return view
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.callbacks = (onBegin, onDrag, onEnd)
    }
}

final class ResizeHandleView: NSView {
    var callbacks: (begin: () -> Void, drag: (CGFloat) -> Void, end: () -> Void) = ({}, { _ in }, {})
    private var startX: CGFloat?
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Nearly invisible, but not fully transparent: macOS passes clicks on fully transparent
        // pixels straight through to the window below.
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    // While the pointer is over the handle the panel must not move, or the drag would
    // carry the whole panel along (it is otherwise movable by its background).
    override func mouseEntered(with event: NSEvent) {
        window?.isMovable = false
        NSCursor.resizeLeftRight.set()
    }

    override func mouseMoved(with event: NSEvent) { NSCursor.resizeLeftRight.set() }

    override func mouseExited(with event: NSEvent) {
        guard startX == nil else { return }
        window?.isMovable = true
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.isMovable = false
        startX = NSEvent.mouseLocation.x
        NSCursor.resizeLeftRight.set()
        callbacks.begin()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startX else { return }
        NSCursor.resizeLeftRight.set()
        callbacks.drag(NSEvent.mouseLocation.x - startX)
    }

    /// The list folded while the pointer was on the handle: make the panel movable again.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            window?.isMovable = true
            startX = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseUp(with event: NSEvent) {
        startX = nil
        callbacks.end()
        if !bounds.contains(convert(event.locationInWindow, from: nil)) {
            window?.isMovable = true
            NSCursor.arrow.set()
        }
    }
}
