import SwiftUI

/// The 22 pt mic button. While recording it turns into a solid red circle with a white glyph.
struct MicButton: View {
    var recording = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(recording ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background {
                    if recording { Circle().fill(Color(nsColor: .systemRed)) }
                }
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording ? "Stop dictation and send" : "Dictate")
    }
}
