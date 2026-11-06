import AgentGlanceCore
import SwiftUI

/// The whole floating surface. In compact view it rests as the pill, expands on hover after
/// 150 ms, pins open on click, and collapses 400 ms after the pointer leaves unless pinned.
struct PanelView: View {
    let model: AppModel
    var onFocus: (Session) -> Void = { _ in }
    var onMic: (Session?) -> Void = { _ in }
    var onSize: (CGSize) -> Void = { _ in }

    @State private var hovering = false
    @State private var pinned = false
    @State private var hoverTask: Task<Void, Never>?
    @Namespace private var glass
    static let motion = Animation.spring(duration: 0.32, bounce: 0.12)

    private var expanded: Bool {
        !model.compactView || pinned || hovering || model.dictatingKey != nil
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
                        .glassEffect(.regular, in: .rect(cornerRadius: Theme.listCornerRadius, style: .continuous))
                        .glassEffectID("surface", in: glass)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity),
                            removal: .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity)))
                } else {
                    CompactPill(sessions: model.store.sessions, bounces: model.bounces) {
                        onMic(model.store.mostRecentAttention)
                    }
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("surface", in: glass)
                    .transition(.opacity)
                    .onTapGesture { withAnimation(Self.motion) { pinned = true } }
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
                                   bounce: model.bounces[session.key] ?? 0,
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
        .onTapGesture(count: 2) { withAnimation(Self.motion) { pinned.toggle() } }
    }

    private struct Section { let source: Source; let sessions: [Session] }

    private var sections: [Section] {
        Source.allCases.compactMap { source in
            let rows = model.store.sessions.filter { $0.key.source == source }
            return rows.isEmpty ? nil : Section(source: source, sessions: rows)
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
                pinned = false
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
