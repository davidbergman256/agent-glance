import AgentGlanceCore
import SwiftUI

/// The resting view: one dot per session, a hairline divider, and the mic.
struct CompactPill: View {
    let sessions: [Session]
    let bounces: [SessionKey: Int]
    let onMic: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if sessions.isEmpty {
                StatusDot(state: nil)
            }
            ForEach(sessions) { session in
                StatusDot(state: session.state, bounce: bounces[session.key] ?? 0)
            }
            Rectangle()
                .fill(.separator)
                .frame(width: 0.5, height: 14)
                .padding(.horizontal, 2)
            MicButton(action: onMic)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
    }
}
