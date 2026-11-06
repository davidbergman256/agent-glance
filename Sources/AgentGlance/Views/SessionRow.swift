import AgentGlanceCore
import SwiftUI

/// One session: state dot, title, live status line, mic. Red and yellow rows get a tint.
struct SessionRow: View {
    let session: Session
    var recording = false
    var titleMaxWidth = Theme.titleMaxWidth
    let onFocus: () -> Void
    let onMic: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: session.state)
            Text(session.title)
                .font(Theme.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: titleMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.status)
                .font(Theme.status)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            MicButton(recording: recording, action: onMic)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: Theme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.tint(session.state) ?? (hovering ? Color.primary.opacity(0.06) : .clear))
        }
        .contentShape(.rect(cornerRadius: Theme.rowCornerRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onFocus)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
