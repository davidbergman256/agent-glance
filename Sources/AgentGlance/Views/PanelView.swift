import AgentGlanceCore
import SwiftUI

/// The whole floating surface. In compact view it rests as the pill and peeks open on hover.
/// Clicking an empty spot in the open list toggles compact view (remembered, same as the menu
/// item): off keeps the list open, on folds it back right away.
struct PanelView: View {
    let model: AppModel
    var onFocus: (Session) -> Void = { _ in }
    var onMic: (Session?) -> Void = { _ in }
    var onSize: (CGSize) -> Void = { _ in }
    var onToggleCompact: () -> Void = {}

    @State private var hovering = false
    /// After folding the list by click, ignore hover until the pointer leaves once.
    @State private var hoverSuppressed = false
    @State private var hoverTask: Task<Void, Never>?
    @Namespace private var glass
    static let motion = Animation.smooth(duration: 0.3)

    private var expanded: Bool {
        !model.compactView || (hovering && !hoverSuppressed) || model.dictatingKey != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible copy of the expanded list: sizes the window so expanding never resizes it.
            list.hidden()
                .environment(\.isMeasuringCopy, true)
                .transaction { $0.animation = nil }
                .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSize)
            GlassEffectContainer {
                if expanded {
                    list
                        .glassEffect(.clear, in: .rect(cornerRadius: Theme.listCornerRadius, style: .continuous))
                        .glassEffectID("surface", in: glass)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity),
                            removal: .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity)))
                } else {
                    CompactPill(sessions: model.store.sessions) {
                        onMic(model.store.mostRecentAttention)
                    }
                    .glassEffect(.clear, in: .capsule)
                    .glassEffectID("surface", in: glass)
                    .transition(.opacity)
                    .onTapGesture(perform: toggleCompact)
                }
            }
            .onHover(perform: hoverChanged)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.store.sessions.isEmpty {
                HStack(spacing: 8) {
                    StatusDot(state: nil)
                    Text("No active sessions").font(Theme.status).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: Theme.rowHeight)
            }
            ForEach(sections, id: \.source) { section in
                if model.store.showsSectionHeadings {
                    Text(Theme.sourceName(section.source))
                        .font(Theme.heading)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                }
                ForEach(section.sessions) { session in
                    VStack(alignment: .leading, spacing: 0) {
                        SessionRow(session: session,
                                   recording: model.dictatingKey == session.key,
                                   onFocus: { onFocus(session) },
                                   onMic: { onMic(session) })
                        if model.dictatingKey == session.key {
                            DictationLine(transcript: model.transcript)
                        }
                    }
                }
            }
            if let notice = model.notice {
                Text(notice)
                    .font(Theme.status)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .padding(Theme.listPadding)
        .frame(width: Theme.listWidth, alignment: .leading)
        .contentShape(.rect(cornerRadius: Theme.listCornerRadius, style: .continuous))
        .onTapGesture(perform: toggleCompact)  // rows and mic buttons handle their own clicks first
    }

    private struct Section { let source: Source; let sessions: [Session] }

    private var sections: [Section] {
        Source.allCases.compactMap { source in
            let rows = model.store.sessions.filter { $0.key.source == source }
            return rows.isEmpty ? nil : Section(source: source, sessions: rows)
        }
    }

    private func toggleCompact() {
        withAnimation(Self.motion) {
            if !model.compactView { hoverSuppressed = true }  // folding while hovered: close now
            onToggleCompact()
        }
    }

    /// Opens at once; closes after a short grace period so crossing the edge doesn't flicker.
    private func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            withAnimation(Self.motion) { hovering = true }
            return
        }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(Self.motion) {
                hovering = false
                hoverSuppressed = false
            }
        }
    }
}

/// The live transcript under a row while dictating.
struct DictationLine: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcript.isEmpty ? "Listening…" : transcript)
                .font(Theme.title.weight(.regular))
                .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Return to send · Esc to cancel")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 27)
        .padding(.trailing, 10)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}
