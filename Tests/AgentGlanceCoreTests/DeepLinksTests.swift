import Foundation
import Testing
@testable import AgentGlanceCore

struct DeepLinksTests {
    func session(_ source: Source, _ id: String) -> Session {
        Session(key: SessionKey(source: source, id: id), title: "T", state: .working, status: "", updatedAt: .distantPast)
    }

    @Test func codexThreadURL() {
        #expect(DeepLinks.url(for: session(.codex, "abc"), claudeLocalId: nil)?.absoluteString == "codex://threads/abc")
    }

    @Test func claudeURLUsesLocalId() {
        #expect(DeepLinks.url(for: session(.claude, "cli-1"), claudeLocalId: "local_x")?.absoluteString
                == "claude://claude.ai/epitaxy/local_x")
    }

    @Test func claudeURLNilWithoutLocalId() {
        #expect(DeepLinks.url(for: session(.claude, "cli-1"), claudeLocalId: nil) == nil)
    }

    @Test func bundleIdentifiers() {
        #expect(DeepLinks.bundleId(.claude) == "com.anthropic.claudefordesktop")
        #expect(DeepLinks.bundleId(.codex) == "com.openai.codex")
    }

    @Test func indexFindsLocalIdByCliSessionId() {
        let root = fixtures.appendingPathComponent("claude-code-sessions")
        #expect(ClaudeSessionIndex.localId(cliSessionId: "cli-222", root: root) == "local_bbb")
        #expect(ClaudeSessionIndex.localId(cliSessionId: "cli-111", root: root) == "local_aaa")
    }

    @Test func indexUnknownOrMissingRootIsNil() {
        #expect(ClaudeSessionIndex.localId(cliSessionId: "cli-999", root: fixtures.appendingPathComponent("claude-code-sessions")) == nil)
        #expect(ClaudeSessionIndex.localId(cliSessionId: "cli-111", root: fixtures.appendingPathComponent("nope")) == nil)
    }
}

struct ClaudeFocusTests {
    let root = fixtures.appendingPathComponent("claude-code-sessions")

    @Test func mostRecentlyFocusedIsTheLatestLastFocusedAt() {
        #expect(ClaudeSessionIndex.isMostRecentlyFocused(localId: "local_bbb", root: root))
        #expect(!ClaudeSessionIndex.isMostRecentlyFocused(localId: "local_aaa", root: root))
    }

    @Test func unknownLocalIdIsNotFocused() {
        #expect(!ClaudeSessionIndex.isMostRecentlyFocused(localId: "local_zzz", root: root))
    }
}
