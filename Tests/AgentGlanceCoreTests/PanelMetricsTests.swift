import Testing
@testable import AgentGlanceCore

struct PanelMetricsTests {
    @Test func widthIsClampedBetween260And640() {
        #expect(PanelMetrics.clampedWidth(100) == 260)
        #expect(PanelMetrics.clampedWidth(900) == 640)
        #expect(PanelMetrics.clampedWidth(400) == 400)
    }

    @Test func defaultWidthIs330() {
        #expect(PanelMetrics.defaultWidth == 330)
    }

    @Test func titleGetsAbout45PercentOfTheWidth() {
        #expect(PanelMetrics.titleMaxWidth(listWidth: 330) == 148.5)
        #expect(PanelMetrics.titleMaxWidth(listWidth: 640) == 288)
    }
}
