import Foundation
import AppKit
import SwiftUI
import Testing
import SQLite3
@testable import NARC

private let codexTestNow = Date(timeIntervalSince1970: 1_000_000)
private func codexEvent(state: String = "replyReady", turn: String = "00000000-0000-0000-0000-000000000002",
                        timestamp: Double = 1_000_000, preview: Bool = false,
                        thread: String = "00000000-0000-0000-0000-000000000001",
                        startedAt: Double? = nil, roundSummary: String? = nil,
                        nextStep: String? = nil, blocker: String? = nil) -> CodexCompletionEvent {
    .init(schemaVersion: 1, threadID: thread, turnID: turn,
          state: state, title: "Test", timestamp: timestamp, isPreview: preview,
          startedAt: startedAt, roundSummary: roundSummary, nextStep: nextStep, blocker: blocker)
}

// State/layout fixtures explicitly represent known user conversations.
private extension CodexCompletionService {
    func ingestKnown(_ events: [CodexCompletionEvent], now: Date,
                     metadata: [String: CodexThreadMetadata]? = nil) {
        let ids = Set(events.map(\.threadID) + conversations.map(\.id))
        let known = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, CodexThreadMetadata(title: nil, isInternal: false))
        })
        ingest(events, now: now, metadata: metadata ?? known)
    }
}

@Test @MainActor func codexCompletionUnknownIDsStayHiddenAndCannotOpen() async throws {
    let suite = "narc-unknown-thread-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults,
        codexFolder: URL(fileURLWithPath: "/private/tmp/narc-missing-" + UUID().uuidString))
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    var event = codexEvent()
    event.title = "对话 " + event.threadID.suffix(8)
    service.ingest([event], now: codexTestNow, metadata: [:])
    #expect(service.pendingEvents.isEmpty)
    #expect(service.conversations.isEmpty)
    #expect(service.lastReceivedAt == nil)
    service.ingestKnown([event], now: codexTestNow)
    #expect(service.pending?.identity == event.identity)
    let result: CodexCompletionEvent? = await withCheckedContinuation { continuation in
        service.resolveForOpening(event) { continuation.resume(returning: $0) }
    }
    #expect(result == nil) // A previously accepted event must be checked again at click time.
    service.ingest([event], now: codexTestNow, metadata: [:])
    #expect(service.pendingEvents.isEmpty)
    #expect(!(defaults.stringArray(forKey: "codexCompletionAcknowledgedV1") ?? []).contains(event.identity))
    service.ingestKnown([event], now: codexTestNow,
        metadata: [event.threadID: .init(title: "标题生成后的正式会话", isInternal: false)])
    #expect(service.pending?.identity == event.identity) // Recover after a transient metadata failure.
    #expect(service.pending?.title == "标题生成后的正式会话")
}

@Test func codexCompletionValidatesEnvelopeAndURL() throws {
    let event = codexEvent()
    #expect(CodexCompletionEvent.decode(try JSONEncoder().encode(event), now: codexTestNow) == event)
    #expect(event.threadURL?.absoluteString == "codex://threads/00000000-0000-0000-0000-000000000001")
    #expect(!codexEvent(state: "failed").isValid(now: codexTestNow))
    #expect(!codexEvent(turn: "../unsafe").isValid(now: codexTestNow))
    #expect(CodexCompletionEvent.decode(Data(repeating: 65, count: 8193), now: codexTestNow) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["NARC_VERIFY_LIVE_REPLY_METADATA"] == "1"))
@MainActor func codexCompletionLiveReplyMetadataExcludesScreenshotID() throws {
    let suite = "narc-live-reply-probe-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let events = CodexCompletionService.readEvents(home.appendingPathComponent("Library/Application Support/NARC/codex-completion"))
    let metadata = CodexThreadMetadata.read(folder: home.appendingPathComponent(".codex"), threadIDs: Set(events.map(\.threadID)))
    let rejectedID = try #require(ProcessInfo.processInfo.environment["NARC_VERIFY_REJECTED_THREAD_ID"])
    #expect(UUID(uuidString: rejectedID) != nil)
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: Date().addingTimeInterval(-3600))
    service.ingest(events, metadata: metadata)
    #expect(service.pendingEvents.allSatisfy { $0.isPreview || metadata[$0.threadID]?.isInternal == false })
    #expect(!service.pendingEvents.contains { $0.threadID == rejectedID })
    #expect(service.pendingEvents.contains { !$0.isPreview }) // Keep genuine replies.
    print("Live metadata probe: \(events.count) event files, \(service.pendingEvents.count) verified user replies; screenshot ID excluded")
}

@Test func codexCompletionRejectsExpiredAndFutureEvents() {
    #expect(!codexEvent(timestamp: 995_000).isValid(now: codexTestNow))
    #expect(!codexEvent(timestamp: 1_000_031).isValid(now: codexTestNow))
    #expect(!codexEvent(timestamp: .infinity).isValid(now: codexTestNow))
}

@Test @MainActor func codexCompletionRefreshesSameTurnTitleAndFiltersLegacyInternalEvents() throws {
    let suite = "narc-metadata-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    var event = codexEvent()
    event.title = "对话 " + event.threadID.suffix(8)
    service.ingestKnown([event], now: codexTestNow)
    service.ingestKnown([event], now: codexTestNow,
                   metadata: [event.threadID: .init(title: "首次回答后生成的标题", isInternal: false)])
    #expect(service.pendingEvents.count == 1)
    #expect(service.pending?.identity == event.identity)
    #expect(service.pending?.title == "首次回答后生成的标题")
    #expect(service.displayTitle(threadID: event.threadID, fallback: event.title) == "首次回答后生成的标题")
    service.ingestKnown([event], now: codexTestNow)
    #expect(service.pending?.title == "首次回答后生成的标题") // Metadata temporarily unavailable.
    service.setName("我的别名", threadID: event.threadID)
    #expect(service.displayTitle(threadID: event.threadID, fallback: event.title) == "我的别名")
    service.ingestKnown([event], now: codexTestNow,
                   metadata: [event.threadID: .init(title: nil, isInternal: true)])
    #expect(service.pendingEvents.isEmpty)
    #expect(service.preferences.conversations.isEmpty)
}

@Test @MainActor func codexCompletionOpeningRejectsAStaleReplyIdentity() async throws {
    let suite = "narc-open-identity-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = URL(fileURLWithPath: "/private/tmp/narc-open-identity-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var db: OpaquePointer?
    #expect(sqlite3_open(folder.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK)
    #expect(sqlite3_exec(db, "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, source TEXT); INSERT INTO threads VALUES ('00000000-0000-0000-0000-000000000001','正式会话','vscode');", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    let service = CodexCompletionService(defaults: defaults, codexFolder: folder)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    let old = codexEvent()
    let newer = codexEvent(turn: UUID().uuidString, timestamp: 1_000_001)
    service.ingestKnown([old, newer], now: codexTestNow)
    let stale: CodexCompletionEvent? = await withCheckedContinuation { continuation in
        service.resolveForOpening(old) { continuation.resume(returning: $0) }
    }
    #expect(stale == nil)
    let current: CodexCompletionEvent? = await withCheckedContinuation { continuation in
        service.resolveForOpening(newer) { continuation.resume(returning: $0) }
    }
    #expect(current?.threadID == newer.threadID)
    #expect(current?.identity == newer.identity)
}

@Test @MainActor func codexCompletionEmbeddedCardScrollsToEntireThirdReply() async throws {
    _ = NSApplication.shared
    let suite = "narc-scroll-regression-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    let events = (1...3).map { index -> CodexCompletionEvent in
        var event = codexEvent(thread: String(format: "00000000-0000-0000-0000-%012d", index + 30),
                               roundSummary: "已有回合摘要，不另行生成")
        event.title = "第\(index)条回复 · 检查首次回答生成标题之后继续对话的完整操作"
        return event
    }
    service.ingestKnown(events, now: codexTestNow)
    let layout = CodexCompletionCardLayout()
    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        let window = TodoNudgeWindow(rootView: CodexCompletionCard(
            service: service, layout: layout, onResize: {}, onOpen: { _, done in done(false) },
            fillsAvailableHeight: true).environment(\.colorScheme, scheme))
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        defer { window.close() }
        window.setContentSize(NSSize(width: 350, height: 260))
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        let scroll = try #require(scrollViews(view).first)
        let document = try #require(scroll.documentView)
        #expect(layout.contentHeight > scroll.contentView.bounds.height)
        #expect(scroll.convert(scroll.bounds, to: view).maxY <= view.bounds.maxY)
        let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? bottom : 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        #expect(abs(scroll.contentView.bounds.minY - (document.isFlipped ? bottom : 0)) <= 1)
        #expect(document.bounds.height - scroll.contentView.bounds.maxY <= 1 || !document.isFlipped)
        if let path = ProcessInfo.processInfo.environment["NARC_CARD_SNAPSHOT_DIR"], path.hasPrefix("/private/tmp/") {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("reply-third-scrolled-\(name).png"))
        }
        print("Embedded \(name): document=\(document.bounds.height), viewport=\(scroll.contentView.bounds.height), bottom=\(scroll.contentView.bounds.minY)")
    }
}

@Test func codexCompletionMetadataReadsOnlyExactIDsAndSupportsOlderSchemas() throws {
    let folder = URL(fileURLWithPath: "/private/tmp/narc-thread-metadata-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        if folder.deletingLastPathComponent().path == "/private/tmp",
           folder.lastPathComponent.hasPrefix("narc-thread-metadata-") {
            try? FileManager.default.removeItem(at: folder)
        }
    }
    var db: OpaquePointer?
    let url = folder.appendingPathComponent("state_5.sqlite")
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, source TEXT); INSERT INTO threads VALUES ('00000000-0000-0000-0000-000000000001','正确会话','vscode'), ('00000000-0000-0000-0000-000000000003','', '{\"subagent\":{}}');", nil, nil, nil) == SQLITE_OK)
    let metadata = CodexThreadMetadata.read(folder: folder, threadIDs: [codexEvent().threadID, "00000000-0000-0000-0000-000000000003", "../unsafe"])
    #expect(metadata.count == 2)
    #expect(metadata[codexEvent().threadID]?.title == "正确会话")
    #expect(metadata[codexEvent().threadID]?.isInternal == false)
    #expect(metadata["00000000-0000-0000-0000-000000000003"]?.isInternal == true)
    let link = folder.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
    #expect(CodexThreadMetadata.read(folder: link, threadIDs: [codexEvent().threadID]).isEmpty)
}

@Test func codexCompletionDecodesOptionalHarnessFieldsAndRejectsUnsafeOnes() throws {
    let legacy = #"{"schemaVersion":1,"threadID":"00000000-0000-0000-0000-000000000001","turnID":"00000000-0000-0000-0000-000000000002","state":"replyReady","title":"Test","timestamp":1000000,"isPreview":false}"#
    let decodedLegacy = try #require(CodexCompletionEvent.decode(Data(legacy.utf8), now: codexTestNow))
    #expect(decodedLegacy.roundSummary == nil)
    #expect(!decodedLegacy.hasRoundDetails)
    #expect(!decodedLegacy.canExpand(eventCount: 4))
    let event = codexEvent(roundSummary: "直接复用已有摘要", nextStep: "确认字号", blocker: "等待确认")
    let decoded = try #require(CodexCompletionEvent.decode(try JSONEncoder().encode(event), now: codexTestNow))
    #expect(decoded.hasRoundDetails)
    #expect(!decoded.canExpand(eventCount: 1))
    #expect(decoded.canExpand(eventCount: 2))
    #expect(decoded.roundSummary == "直接复用已有摘要")
    #expect(decoded.nextStep == "确认字号")
    #expect(decoded.blocker == "等待确认")
    #expect(!codexEvent(roundSummary: "第一行\n第二行").isValid(now: codexTestNow))
    #expect(!codexEvent(nextStep: String(repeating: "长", count: 161)).isValid(now: codexTestNow))
    #expect(codexEvent(nextStep: "继续验证").hasRoundDetails)
    #expect(codexEvent(blocker: "等待用户确认").hasRoundDetails)
    #expect(codexEvent(blocker: "等待用户确认").canExpand(eventCount: 4))
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
    service.ingestKnown([], now: codexTestNow)
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
    service.ingestKnown([first, other], now: codexTestNow)
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
    restarted.ingestKnown([first, other], now: codexTestNow)
    #expect(restarted.pendingEvents == [other])
    let next = codexEvent(turn: "00000000-0000-0000-0000-000000000004", timestamp: 1_000_001)
    restarted.ingestKnown([next], now: codexTestNow)
    #expect(restarted.pendingEvents.count == 2)
    restarted.setEnabled(false, now: codexTestNow.addingTimeInterval(2))
    #expect(restarted.pendingEvents.isEmpty)
    restarted.setEnabled(true, now: codexTestNow.addingTimeInterval(3))
    restarted.ingestKnown([next, other], now: codexTestNow)
    #expect(restarted.pendingEvents.isEmpty)
}

@Test @MainActor func codexCompletionPreviewDoesNotClaimRealConnectionOrPolluteDirectory() throws {
    let suite = "narc-codex-tests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    service.ingestKnown([codexEvent(preview: true)], now: codexTestNow)
    #expect(service.pendingEvents.count == 1)
    #expect(service.lastReceivedAt == nil)
    #expect(service.conversations.isEmpty)
    service.ingestKnown([codexEvent()], now: codexTestNow)
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
    #expect(CodexCompletionCardLayout.preferredWidth == 420)
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

@Test @MainActor func codexCompletionCardDisclosureIsPerConversation() {
    let layout = CodexCompletionCardLayout()
    #expect(layout.isExpanded("first", eventCount: 1))
    #expect(!layout.isExpanded("first", eventCount: 2))
    #expect(!layout.isExpanded("second", eventCount: 2))
    layout.toggleDetails("first")
    #expect(layout.isExpanded("first", eventCount: 2))
    #expect(!layout.isExpanded("second", eventCount: 2))
    layout.toggleDetails("second")
    #expect(layout.isExpanded("first", eventCount: 2))
    #expect(layout.isExpanded("second", eventCount: 2))
    layout.toggleDetails("first")
    #expect(!layout.isExpanded("first", eventCount: 2))
    #expect(layout.isExpanded("second", eventCount: 2))
    layout.retainEvents(["first"])
    #expect(!layout.isExpanded("second", eventCount: 2))
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
        service.ingestKnown([event], now: codexTestNow)
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
            // AppKit rounds origins to whole points. Odd measured card heights
            // can put the geometric center at .5pt; this is not anchor drift.
            #expect(panel.frame.size == expected.size)
            #expect(abs(panel.frame.minX - expected.minX) <= 0.5)
            #expect(abs(panel.frame.minY - expected.minY) <= 0.5)
        }
        service.acknowledge(identity: event.identity)
        try await Task.sleep(for: .milliseconds(250))
        #expect(service.pendingEvents.isEmpty)
        #expect(!presenter.isVisible)
        #expect(panels().isEmpty)
    }
}

@Test @MainActor func codexReplyCardAutoHidesWithoutAcknowledgingAndBadgeReopensIt() async throws {
    let suite = "narc-presenter-auto-hide-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = CodexCompletionService(defaults: defaults)
    service.setEnabled(true, now: codexTestNow.addingTimeInterval(-1))
    let presenter = CodexCompletionPresenter(
        service: service, automaticDisplayDuration: .milliseconds(80)
    )
    _ = NSApplication.shared
    presenter.anchor = {
        (NSRect(x: 900, y: 450, width: 128, height: 128), 48,
         NSRect(x: 0, y: 0, width: 1600, height: 1000))
    }
    presenter.isBlocked = { false }
    service.onRefresh = { [weak presenter] in presenter?.reconcile() }
    defer { presenter.stop() }

    let first = codexEvent()
    service.ingestKnown([first], now: codexTestNow)
    #expect(presenter.isVisible)
    try await Task.sleep(for: .milliseconds(160))
    #expect(!presenter.isVisible)
    #expect(service.pendingEvents.map(\.identity) == [first.identity])

    presenter.reconcile() // Polling the same unread event must not re-open the card.
    #expect(!presenter.isVisible)
    presenter.toggleFromBadge()
    #expect(presenter.isVisible)
    try await Task.sleep(for: .milliseconds(160))
    #expect(presenter.isVisible) // Manually opened details have no reading deadline.
    presenter.toggleFromBadge()
    #expect(!presenter.isVisible)
    #expect(service.pendingEvents.count == 1)

    let second = codexEvent(thread: "00000000-0000-0000-0000-000000000003")
    service.ingestKnown([second], now: codexTestNow)
    #expect(presenter.isVisible)
    #expect(service.pendingEvents.count == 2)
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
        events.append(codexEvent(
            thread: thread,
            roundSummary: index < 2 ? (index == 1
                ? "核对了计划与工作区，确认当前实现、安装状态以及仍需继续处理的验证路径，相关内容直接复用回答末尾已经生成的 Harness 回合字段。"
                : "提醒直接复用回答末尾已生成的 Harness 回合内容") : nil,
            nextStep: index < 2 ? (index == 1
                ? "确认长中文内容能够自然换行完整显示，按钮仍保持单行，并保留极端内容的卡片内滚动。"
                : "确认标题与正文的字号层级") : nil
        ))
        service.setName(title, threadID: thread)
    }
    var singleHeight: CGFloat = 0
    var pairCollapsedHeight: CGFloat = 0
    for (name, sample) in [("single", [events[0]]), ("long", [events[1]]),
                           ("pair-collapsed", [events[0], events[2]]),
                           ("pair-long-collapsed", [events[1], events[2]]),
                           ("pair-expanded", [events[0], events[2]]),
                           ("pair-legacy-expanded", [events[0], events[2]]),
                           ("multiple", events), ("reduced", [events[0]])] {
        // Keep the same view/window alive to verify content changes shrink it too.
        if name == "reduced" {
            for event in service.pendingEvents where event.threadID != events[0].threadID {
                service.acknowledge(identity: event.identity)
            }
        } else {
            for event in service.pendingEvents { service.acknowledge(identity: event.identity) }
            let fresh = sample.map { event in
                codexEvent(turn: UUID().uuidString.lowercased(), thread: event.threadID,
                           roundSummary: event.roundSummary, nextStep: event.nextStep, blocker: event.blocker)
            }
            service.ingestKnown(fresh, now: codexTestNow)
        }
        if name == "pair-expanded" {
            layout.toggleDetails(try #require(service.pendingEvents.first?.identity))
        } else if name == "pair-legacy-expanded" {
            layout.toggleDetails(try #require(service.pendingEvents.last?.identity))
        }
        for _ in 0..<5 {
            panel.setContentSize(NSSize(
                width: CodexCompletionCardLayout.preferredWidth,
                height: layout.cardHeight
            ))
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        if name == "single" {
            singleHeight = layout.cardHeight
            #expect(singleHeight > 160 && singleHeight < 230)
        } else if name == "long" {
            #expect(layout.cardHeight > singleHeight)
        } else if name == "pair-collapsed" {
            pairCollapsedHeight = layout.cardHeight
            #expect(pairCollapsedHeight < 360)
        } else if name == "pair-long-collapsed" {
            #expect(layout.cardHeight > pairCollapsedHeight && layout.cardHeight < 360)
        } else if name == "pair-expanded" {
            #expect(layout.cardHeight > pairCollapsedHeight)
        } else if name == "pair-legacy-expanded" {
            #expect(layout.cardHeight == pairCollapsedHeight)
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
