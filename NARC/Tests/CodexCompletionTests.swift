import Foundation
import Testing
@testable import NARC

private let codexTestNow = Date(timeIntervalSince1970: 1_000_000)
private func codexEvent(state: String = "replyReady", turn: String = "00000000-0000-0000-0000-000000000002",
                        timestamp: Double = 1_000_000, preview: Bool = false,
                        thread: String = "00000000-0000-0000-0000-000000000001",
                        startedAt: Double? = nil) -> CodexCompletionEvent {
    .init(schemaVersion: 1, threadID: thread, turnID: turn,
          state: state, title: "Test", timestamp: timestamp, isPreview: preview, startedAt: startedAt)
}

@Test func codexCompletionValidatesEnvelopeAndURL() throws {
    let event = codexEvent()
    #expect(CodexCompletionEvent.decode(try JSONEncoder().encode(event), now: codexTestNow) == event)
    #expect(event.threadURL?.absoluteString == "codex://threads/00000000-0000-0000-0000-000000000001")
    #expect(!codexEvent(state: "failed").isValid(now: codexTestNow))
    #expect(!codexEvent(turn: "../unsafe").isValid(now: codexTestNow))
    #expect(CodexCompletionEvent.decode(Data(repeating: 65, count: 8193), now: codexTestNow) == nil)
}

@Test func codexCompletionRejectsExpiredAndFutureEvents() {
    #expect(!codexEvent(timestamp: 995_000).isValid(now: codexTestNow))
    #expect(!codexEvent(timestamp: 1_000_031).isValid(now: codexTestNow))
    #expect(!codexEvent(timestamp: .infinity).isValid(now: codexTestNow))
}

@Test func codexCompletionAcknowledgementSurvivesRestartAndDeduplicates() {
    var state = CodexCompletionState()
    state.receive(codexEvent(), now: codexTestNow)
    state.acknowledgePending()
    var restarted = CodexCompletionState(acknowledged: state.acknowledged)
    restarted.receive(codexEvent(), now: codexTestNow)
    #expect(restarted.pending == nil)
    restarted.receive(codexEvent(turn: "00000000-0000-0000-0000-000000000003"), now: codexTestNow)
    #expect(restarted.pending != nil)
}

@Test func codexCompletionStartingOrInterruptingClearsOldCue() {
    for nextState in ["running", "interrupted"] {
        var state = CodexCompletionState()
        state.receive(codexEvent(), now: codexTestNow)
        state.receive(codexEvent(state: nextState, timestamp: 1_000_001), now: codexTestNow)
        #expect(state.pending == nil)
        state.receive(codexEvent(), now: codexTestNow)
        #expect(state.pending == nil)
    }
}

@Test func codexCompletionExpiresPendingAndKeepsPreviewSeparate() {
    var state = CodexCompletionState()
    state.receive(codexEvent(preview: true), now: codexTestNow)
    state.acknowledgePending()
    state.receive(codexEvent(), now: codexTestNow)
    #expect(state.pending != nil)
    state.receive(nil, now: codexTestNow.addingTimeInterval(3601))
    #expect(state.pending == nil)
}

@Test func codexCompletionAggregatesAndClearsOnlyMatchingThread() {
    let first = codexEvent()
    let second = codexEvent(thread: "00000000-0000-0000-0000-000000000003")
    var state = CodexCompletionState()
    state.receive(first, now: codexTestNow)
    state.receive(second, now: codexTestNow)
    #expect(state.pendingEvents.count == 2)
    state.receive(codexEvent(state: "running", timestamp: 1_000_001), now: codexTestNow)
    #expect(state.pendingEvents == [second])
    state.acknowledge(identity: first.identity)
    #expect(state.pendingEvents == [second])
}

@Test func codexCompletionLateStopCannotResurrectSupersededOrInterruptedTurn() {
    var state = CodexCompletionState()
    state.receive(codexEvent(state: "running", startedAt: 999_900), now: codexTestNow)
    let newer = codexEvent(state: "running", turn: "00000000-0000-0000-0000-000000000004",
                          timestamp: 1_000_001, startedAt: 1_000_001)
    state.receive(newer, now: codexTestNow)
    state.receive(codexEvent(timestamp: 1_000_002, startedAt: 999_900), now: codexTestNow)
    #expect(state.pending == nil)
    state.receive(codexEvent(state: "interrupted", turn: newer.turnID, timestamp: 1_000_003, startedAt: 1_000_001), now: codexTestNow)
    state.receive(codexEvent(turn: newer.turnID, timestamp: 1_000_004, startedAt: 1_000_001), now: codexTestNow)
    #expect(state.pending == nil)
}

@Test @MainActor func codexCompletionFreshInstallStaysDisabledAcrossRestart() throws {
    let suite = "narc-codex-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    #expect(!service.preferences.enabled)
    service.ingest([], now: codexTestNow)
    #expect(!CodexCompletionService(defaults: defaults).preferences.enabled)
}

@Test @MainActor func codexCompletionMuteRestoreAndGlobalToggleDoNotReplay() throws {
    let suite = "narc-codex-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    let first = codexEvent()
    let other = codexEvent(thread: "00000000-0000-0000-0000-000000000003")
    service.ingest([first, other], now: codexTestNow)
    #expect(service.pendingEvents.count == 2)
    service.setMuted(true, threadID: first.threadID, now: codexTestNow)
    #expect(service.pendingEvents == [other])
    service.setName("My ", threadID: first.threadID)
    #expect(service.preferences.names[first.threadID] == "My ")
    service.setName("My work", threadID: first.threadID)
    let restarted = CodexCompletionService(defaults: defaults)
    #expect(restarted.preferences.muted.contains(first.threadID))
    #expect(restarted.displayTitle(threadID: first.threadID, fallback: "ignored") == "My work")
    restarted.setMuted(false, threadID: first.threadID, now: codexTestNow)
    restarted.ingest([first, other], now: codexTestNow)
    #expect(restarted.pendingEvents == [other])
    let next = codexEvent(turn: "00000000-0000-0000-0000-000000000004", timestamp: 1_000_001)
    restarted.ingest([next], now: codexTestNow)
    #expect(restarted.pendingEvents.count == 2)
    restarted.setEnabled(false, now: codexTestNow.addingTimeInterval(2))
    #expect(restarted.pendingEvents.isEmpty)
    restarted.setEnabled(true, now: codexTestNow.addingTimeInterval(3))
    restarted.ingest([next, other], now: codexTestNow)
    #expect(restarted.pendingEvents.isEmpty)
}

@Test @MainActor func codexCompletionPreviewDoesNotClaimRealConnectionOrPolluteDirectory() throws {
    let suite = "narc-codex-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    service.ingest([codexEvent(preview: true)], now: codexTestNow)
    #expect(service.pendingEvents.count == 1)
    #expect(service.lastReceivedAt == nil)
    #expect(service.conversations.isEmpty)
    service.ingest([codexEvent()], now: codexTestNow)
    #expect(service.lastReceivedAt == codexTestNow)
    #expect(service.conversations.count == 1)
    #expect(service.connectionInfo == nil) // Neither Hook nor preview proves the new notify connection.
}

@Test func codexCompletionConnectionGuidanceHasNoTerminalStep() throws {
    for status in [CodexConnectionState.notConfigured, .waiting, .connected, .error] {
        #expect(!status.guidance.contains("/hooks"))
        #expect(!status.guidance.contains("hooks.json"))
        #expect(!status.title.isEmpty)
    }
    let info = try JSONDecoder().decode(CodexConnectionInfo.self, from: Data(#"{"status":"waiting","receivedAt":null}"#.utf8))
    #expect(info.status == .waiting)
    #expect(info.receivedAt == nil)
    #expect(info.status.guidance.contains("发一条消息"))
    #expect(info.status.actionTitle == "打开 ChatGPT")
    #expect(CodexConnectionState.notConfigured.actionTitle == "开始连接")
    #expect(CodexConnectionState.error.actionTitle == "重新检查")
    #expect(CodexConnectionState.connected.actionTitle == nil)
    #expect(CodexConnectionState.connected.guidance.contains("无需操作"))
}
