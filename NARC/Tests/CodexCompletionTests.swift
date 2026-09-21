import Foundation
import AppKit
import SwiftUI
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

@Test @MainActor func codexCompletionCardFitsMeasuredContentAndShrinks() {
    let layout = CodexCompletionCardLayout()
    #expect(layout.measure(52))
    #expect(layout.cardHeight == 116)
    #expect(!layout.measure(52)) // Avoid repeated resize/layout feedback.
    layout.measure(80) // Wrapped title or an open-failure message.
    #expect(layout.cardHeight == 144)
    layout.measure(900)
    #expect(layout.cardHeight == 360)
    #expect(layout.listHeight == 296)
    layout.measure(52) // Dismiss all but one conversation.
    #expect(layout.cardHeight == 116)
    layout.maximumHeight = 100
    #expect(layout.cardHeight == 100)
    #expect(!layout.measure(.nan))
    #expect(!layout.measure(-1))
}

@Test @MainActor func codexCompletionPresenterOwnsOneAnchoredPanelAndClearsIt() async throws {
    let suite = "narc-presenter-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    let presenter = CodexCompletionPresenter(service: service)
    let app = NSApplication.shared
    let previous = Set(app.windows.map(\.windowNumber))
    func panels() -> [NSWindow] {
        app.windows.filter { $0 is TodoNudgeWindow && !previous.contains($0.windowNumber) && $0.isVisible }
    }
    defer {
        presenter.stop()
        for window in panels() { window.close() }
    }
    var widget = NSRect(x: 900, y: 450, width: 100, height: 100)
    var screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    var blocked = false
    presenter.anchor = { (widget, 48, screen) }
    presenter.isBlocked = { blocked }
    service.onRefresh = { [weak presenter] in presenter?.reconcile() }
    for _ in 0..<3 {
        let event = codexEvent(turn: UUID().uuidString.lowercased())
        service.ingest([event], now: codexTestNow)
        try await Task.sleep(for: .milliseconds(250))
        #expect(panels().count == 1)
        if let panel = panels().first {
            let expected = TodoNudgePlacement.frame(adjacentTo: widget, visibleWidgetSize: 48,
                cardSize: panel.frame.size, targetVisibleFrame: screen)
            #expect(abs(panel.frame.midY - expected.midY) < 1)
            #expect(abs(panel.frame.minX - expected.minX) < 1)
        }
        blocked = true // Dragging hides the card immediately.
        presenter.reconcile()
        #expect(panels().isEmpty)
        screen.origin.x -= 1600 // Recall onto an adjacent display.
        widget.origin.x -= 1600
        widget.origin.y += 30
        blocked = false
        presenter.reconcile()
        try await Task.sleep(for: .milliseconds(100))
        #expect(panels().count == 1)
        if let panel = panels().first {
            let expected = TodoNudgePlacement.frame(adjacentTo: widget, visibleWidgetSize: 48,
                cardSize: panel.frame.size, targetVisibleFrame: screen)
            #expect(panel.frame == expected)
        }
        service.acknowledge(identity: event.identity)
        try await Task.sleep(for: .milliseconds(250))
        #expect(service.pendingEvents.isEmpty)
        #expect(!presenter.isVisible)
        #expect(panels().isEmpty)
    }
}

@Test @MainActor func codexCompletionCardRealLayoutPreview() async throws {
    let suite = "narc-card-layout-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    let layout = CodexCompletionCardLayout()
    let panel = TodoNudgeWindow(rootView: CodexCompletionCard(
        service: service, layout: layout, onResize: {}, onOpen: { _, done in done(false) }
    ).environment(\.colorScheme, .light))
    defer { panel.close() }
    let titles = ["检查服务状态", "核对新版本发布前的安装流程与多屏幕窗口召回体验，整理需要继续处理的问题", "整理今天的项目进度", "确认明天的日程", "回顾本周待办", "准备项目说明"]
    var events: [CodexCompletionEvent] = []
    for (index, title) in titles.enumerated() {
        let thread = String(format: "00000000-0000-0000-0000-%012d", index + 10)
        events.append(codexEvent(thread: thread))
        service.setName(title, threadID: thread)
    }
    var singleHeight: CGFloat = 0
    for (name, sample) in [("single", [events[0]]), ("long", [events[1]]), ("multiple", events), ("reduced", [events[0]])] {
        // Keep the same view/window alive to verify content changes shrink it too.
        if name == "reduced" {
            for event in service.pendingEvents where event.threadID != events[0].threadID {
                service.acknowledge(identity: event.identity)
            }
        } else {
            for event in service.pendingEvents { service.acknowledge(identity: event.identity) }
            let fresh = sample.map { event in
                codexEvent(turn: UUID().uuidString.lowercased(), thread: event.threadID)
            }
            service.ingest(fresh, now: codexTestNow)
        }
        for _ in 0..<5 {
            panel.setContentSize(NSSize(width: 340, height: layout.cardHeight))
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        if name == "single" {
            singleHeight = layout.cardHeight
            #expect(singleHeight > 95 && singleHeight < 155)
        } else if name == "long" {
            #expect(layout.cardHeight > singleHeight)
        } else if name == "multiple" {
            #expect(layout.cardHeight == 360)
            #expect(layout.contentHeight > layout.listHeight)
        } else {
            #expect(layout.cardHeight == singleHeight)
        }
        if let path = ProcessInfo.processInfo.environment["NARC_CARD_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
            let view = try #require(panel.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("reply-\(name).png"))
        }
        print("Card layout \(name): \(layout.cardHeight)pt; content \(layout.contentHeight)pt")
    }
}
