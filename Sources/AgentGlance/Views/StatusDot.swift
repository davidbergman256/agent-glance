import AgentGlanceCore
import SwiftUI

/// A 9 pt state dot. Working dots pulse slowly; the pulse only runs while the dot is on screen.
struct StatusDot: View {
    let state: SessionState?
    var size: CGFloat = Theme.dotSize
    /// Increments when the session newly needs you; each change plays one bounce.
    var bounce: Int = 0
    @State private var dim = false
    @Environment(\.isMeasuringCopy) private var measuring

    var body: some View {
        Circle()
            .fill(state.map(Theme.color) ?? Color(nsColor: .tertiaryLabelColor))
            .frame(width: size, height: size)
            .opacity(state == .working && dim ? 0.45 : 1)
            .keyframeAnimator(initialValue: 1.0, trigger: bounce) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.35, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            }
            .onAppear { startPulse() }
            .onChange(of: state) { startPulse() }
            .onDisappear { dim = false }
            .accessibilityHidden(true)
    }

    private func startPulse() {
        guard state == .working, !measuring else {
            dim = false
            return
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { dim = true }
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
