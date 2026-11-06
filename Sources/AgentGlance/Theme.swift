import AgentGlanceCore
import AppKit
import SwiftUI

/// Colors and type from the approved mockup: Apple system colors at full strength, SF Pro Rounded.
enum Theme {
    static func nsColor(_ state: SessionState) -> NSColor {
        switch state {
        case .working: .systemBlue
        case .permission: .systemRed
        case .question: .systemYellow
        case .done: .systemGreen
        }
    }

    static func color(_ state: SessionState) -> Color { Color(nsColor: nsColor(state)) }

    /// Row tint for sessions that need you; opaque enough to read over glass on any wallpaper.
    static func tint(_ state: SessionState) -> Color? {
        switch state {
        case .permission: Color(nsColor: .systemRed).opacity(0.16)
        case .question: Color(nsColor: .systemYellow).opacity(0.2)
        default: nil
        }
    }

    static let title = Font.system(size: 12.5, weight: .semibold, design: .rounded)
    static let status = Font.system(size: 11.5, weight: .regular, design: .rounded)
    static let heading = Font.system(size: 11, weight: .semibold, design: .rounded)

    static let rowHeight: CGFloat = 30
    static let titleMaxWidth: CGFloat = 150
    static let dotSize: CGFloat = 9
    /// The pill is a capsule about 34 pt tall, so its corners are ~17 pt. The list uses the
    /// same radius so expanding reads as one shape growing; rows sit 4 pt inside, concentric.
    static let listCornerRadius: CGFloat = 18
    static let listPadding: CGFloat = 4
    static let rowCornerRadius: CGFloat = listCornerRadius - listPadding

    static func sourceName(_ source: Source) -> String {
        switch source {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}
