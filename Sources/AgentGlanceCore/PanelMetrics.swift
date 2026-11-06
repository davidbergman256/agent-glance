/// The open list's adjustable width. Only the width can be dragged: the height always fits
/// every session.
public enum PanelMetrics {
    public static let defaultWidth: Double = 330
    public static let minWidth: Double = 260
    public static let maxWidth: Double = 640
    /// Share of the list's width a title may use before it truncates; the status line gets the rest.
    public static let titleShare: Double = 0.45

    public static func clampedWidth(_ width: Double) -> Double {
        min(max(width, minWidth), maxWidth)
    }

    public static func titleMaxWidth(listWidth: Double) -> Double {
        listWidth * titleShare
    }
}
