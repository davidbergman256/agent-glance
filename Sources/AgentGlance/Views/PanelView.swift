import AgentGlanceCore
import SwiftUI

/// Placeholder list for Task 6; Task 7 replaces it with the pill and glass list.
struct PanelView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.store.sessions.isEmpty {
                Text("No sessions").font(Theme.status).foregroundStyle(.secondary)
            }
            ForEach(model.store.sessions) { session in
                HStack(spacing: 8) {
                    Circle().fill(Theme.color(session.state)).frame(width: Theme.dotSize, height: Theme.dotSize)
                    Text(session.title).font(Theme.title)
                    Text(session.status).font(Theme.status).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .fixedSize()
    }
}
