import Testing
@testable import AgentGlanceCore

struct DeliveryPlanTests {
    @Test func verifiedTargetWithFocusedInputPastes() {
        #expect(DeliveryPlan.decide(text: "use google", verifiedFrontmost: true, inputFocused: true, title: "Socio platform auth") == .paste)
    }

    @Test func unverifiedTargetCopiesWithNotice() {
        #expect(DeliveryPlan.decide(text: "use google", verifiedFrontmost: false, inputFocused: true, title: "Socio platform auth")
                == .copyOnly(notice: "Couldn't reach Socio platform auth. Text copied."))
    }

    @Test func verifiedTargetWithoutFocusedInputCopies() {
        #expect(DeliveryPlan.decide(text: "use google", verifiedFrontmost: true, inputFocused: false, title: "Socio platform auth")
                == .copyOnly(notice: "Couldn't find the message box in Socio platform auth. Text copied."))
    }

    @Test func emptyTextNeverPastes() {
        #expect(DeliveryPlan.decide(text: "  \n ", verifiedFrontmost: true, inputFocused: true, title: "X") == .copyOnly(notice: "Nothing to send."))
        #expect(DeliveryPlan.decide(text: "", verifiedFrontmost: false, inputFocused: false, title: "X") == .copyOnly(notice: "Nothing to send."))
    }
}
