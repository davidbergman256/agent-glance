import Foundation
import Testing
@testable import AgentGlanceCore

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

struct TitlesTests {
    @Test func claudeUsesLastCustomTitle() {
        #expect(Titles.claude(transcriptPath: fixtures.appendingPathComponent("claude-session.jsonl")) == "Agent-pet installation")
    }

    @Test func claudeFallsBackToFirstUserPromptSixWords() {
        #expect(Titles.claude(transcriptPath: fixtures.appendingPathComponent("claude-untitled.jsonl"))
                == "please run an arbitrary task for…")
    }

    @Test func claudeMissingFileIsNil() {
        #expect(Titles.claude(transcriptPath: fixtures.appendingPathComponent("nope.jsonl")) == nil)
    }

    @Test func codexUsesLastMatchingThreadName() {
        #expect(Titles.codex(threadId: "t-1", index: fixtures.appendingPathComponent("codex-index.jsonl"))
                == "Run a task for 30 seconds")
    }

    @Test func codexUnknownIdIsNil() {
        #expect(Titles.codex(threadId: "t-9", index: fixtures.appendingPathComponent("codex-index.jsonl")) == nil)
    }
}
