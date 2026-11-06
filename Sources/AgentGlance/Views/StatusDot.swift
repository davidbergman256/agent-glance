import AgentGlanceCore
import AppKit
import SwiftUI

/// A 9 pt state dot. A working dot pulses its opacity with a Core Animation layer animation:
/// it runs in the window server (no per-frame work in the app) and can't leak into layout.
struct StatusDot: View {
    let state: SessionState?
    var size: CGFloat = Theme.dotSize
    @Environment(\.isMeasuringCopy) private var measuring

    var body: some View {
        DotLayerView(color: state.map(Theme.nsColor) ?? .tertiaryLabelColor,
                     pulsing: state == .working && !measuring)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct DotLayerView: NSViewRepresentable {
    let color: NSColor
    let pulsing: Bool

    func makeNSView(context: Context) -> DotNSView { DotNSView() }

    func updateNSView(_ view: DotNSView, context: Context) {
        view.update(color: color, pulsing: pulsing)
    }
}

final class DotNSView: NSView {
    private static let pulseKey = "pulse"
    private var color: NSColor = .clear

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }

    /// Resolves the (dynamic) system color for the current light or dark appearance.
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }

    func update(color: NSColor, pulsing: Bool) {
        self.color = color
        needsDisplay = true
        let running = layer?.animation(forKey: Self.pulseKey) != nil
        if pulsing, !running {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.45
            pulse.duration = 1.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.isRemovedOnCompletion = false
            layer?.add(pulse, forKey: Self.pulseKey)
        } else if !pulsing, running {
            layer?.removeAnimation(forKey: Self.pulseKey)
        }
    }
}

private struct MeasuringCopyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the invisible copy of the list used only to size the window: no animations there.
    var isMeasuringCopy: Bool {
        get { self[MeasuringCopyKey.self] }
        set { self[MeasuringCopyKey.self] = newValue }
    }
}
