import Foundation

/// What to do with finished dictation. Text is only typed into a session that was verified to be
/// in front; anything else goes to the clipboard with a notice, so it can never land in the wrong place.
public enum DeliveryDecision: Equatable, Sendable {
    case paste
    case copyOnly(notice: String)
}

public enum DeliveryPlan {
    /// `inputFocused`: the frontmost app's keyboard focus is in a text box (its message composer).
    public static func decide(text: String, verifiedFrontmost: Bool, inputFocused: Bool, title: String) -> DeliveryDecision {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .copyOnly(notice: "Nothing to send.") }
        guard verifiedFrontmost else { return .copyOnly(notice: "Couldn't reach \(title). Text copied.") }
        guard inputFocused else { return .copyOnly(notice: "Couldn't find the message box in \(title). Text copied.") }
        return .paste
    }
}
