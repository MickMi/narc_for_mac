import AppKit
import SwiftUI
import Testing
@testable import NARC

/// Render production views with isolated fixtures, never the personal Todo store.
/// Optional PNG output is for visual review, not proof of live click behavior.
@Test @MainActor func softFocusProductionViewsRenderInBothAppearances() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-soft-focus-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AssistantStore(storageURL: directory.appendingPathComponent("assistant.json"))
    #expect(store.createTodo(title: "把 NARC 测试版发给体验者"))
    #expect(store.createTodo(title: "整理第一轮测试反馈"))
    #expect(store.createTodo(title: "确认 README 安装说明"))
    let capture = InboxCaptureState(store: store)
    let navigation = AssistantHubNavigation()
    capture.hideOnboardingHintForThisSession()
    let suite = "narc-soft-focus-hotkeys-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hotkeys = HotkeyService(accessibilityTrustCheck: { _ in false }, defaults: defaults)
    let codexDefaultsName = "narc-cue-preview-" + UUID().uuidString
    let codexDefaults = try #require(UserDefaults(suiteName: codexDefaultsName))
    defer { codexDefaults.removePersistentDomain(forName: codexDefaultsName) }
    let codex = CodexCompletionService(defaults: codexDefaults, eventFolder: directory)
    let now = Date()
    codex.setEnabled(true, now: now.addingTimeInterval(-60))
    codex.ingest([
        CodexCompletionEvent(schemaVersion: 1,
            threadID: "00000000-0000-0000-0000-000000000001",
            turnID: "00000000-0000-0000-0000-000000000011",
            state: "replyReady", title: "整理窗口快捷键方案",
            timestamp: now.timeIntervalSince1970 - 2, isPreview: true,
            roundSummary: "已整理待确认的操作", nextStep: "检查悬浮入口"),
        CodexCompletionEvent(schemaVersion: 1,
            threadID: "00000000-0000-0000-0000-000000000002",
            turnID: "00000000-0000-0000-0000-000000000022",
            state: "replyReady", title: "查看第二条 AI 回复",
            timestamp: now.timeIntervalSince1970 - 1, isPreview: true),
        CodexCompletionEvent(schemaVersion: 1,
            threadID: "00000000-0000-0000-0000-000000000003",
            turnID: "00000000-0000-0000-0000-000000000033",
            state: "replyReady", title: "第三条回复的按钮可以滚动查看",
            timestamp: now.timeIntervalSince1970 - 3, isPreview: true)
    ], now: now)
    #expect(codex.pendingEvents.count == 3)
    let panelSelection = PanelSelectionState()
    panelSelection.selectedTab = .codexReplies
    let before = try Data(contentsOf: store.storageURL)

    let samples: [(String, NSSize, AnyView)] = [
        ("todo-compact", NSSize(width: 360, height: 390), AnyView(
            QuickCaptureView(store: store, captureState: capture, compact: true)
        )),
        ("todo-list", NSSize(width: 620, height: 500), AnyView(
            QuickCaptureView(store: store, captureState: capture)
        )),
        ("todo-review", TodoNudgeWindow.cardSize, AnyView(TodoNudgeCardView(
            store: store, onActionStarted: {}, onActionFailed: {}, onSuccessfulAction: {},
            onDismiss: {}, onSnooze: {}, onViewAll: {}
        ))),
        ("window-layouts", NSSize(width: 360, height: 420), AnyView(
            WindowGridView(windowManager: WindowManagerService(), hotkeyService: hotkeys)
        )),
        ("orb", NSSize(width: 128, height: 128), AnyView(
            FloatingWidgetView(state: .hasNotification(count: 5),
                               availableTodoCount: 3, codexReplyCount: 2)
        )),
        ("orb-reply-hover", NSSize(width: 128, height: 128), AnyView(
            FloatingWidgetView(state: .hasNotification(count: 5),
                               availableTodoCount: 3, codexReplyCount: 2,
                               hoveredCue: .codexReply)
        )),
        ("orb-todo-hover", NSSize(width: 128, height: 128), AnyView(
            FloatingWidgetView(state: .hasNotification(count: 5),
                               availableTodoCount: 3, codexReplyCount: 2,
                               hoveredCue: .todo)
        )),
        ("orb-small", NSSize(width: 120, height: 120), AnyView(
            FloatingWidgetView(state: .hasNotification(count: 5),
                               availableTodoCount: 3, codexReplyCount: 2,
                               widgetSize: "Small")
        )),
        ("orb-large", NSSize(width: 138, height: 138), AnyView(
            FloatingWidgetView(state: .hasNotification(count: 5),
                               availableTodoCount: 3, codexReplyCount: 2,
                               widgetSize: "Large")
        )),
        ("panel-ai-replies", NSSize(width: NarcSize.panelWidth, height: NarcSize.panelHeight),
         AnyView(PanelView(
            appMonitor: AppMonitorService(), windowManager: WindowManagerService(),
            pinnedWindowService: PinnedWindowService(defaults: defaults),
            hotkeyService: hotkeys, assistantStore: store, inboxCaptureState: capture,
            codexCompletionService: codex, panelSelection: panelSelection,
            onClose: {}, onOpenPreferences: {},
            narcScreenProvider: { NSScreen.main },
            keyboardSelection: KeyboardSelectionState()
         ))),
        ("assistant-empty-notes", NSSize(width: 800, height: 600), AnyView(
            AssistantHubView(store: store, captureState: capture, navigation: navigation)
        )),
    ]
    for (appearanceName, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        for (name, size, content) in samples {
            let window = TodoNudgeWindow(rootView: content.environment(\.colorScheme, scheme)
                .background(Color.narcFocusSurface))
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.setContentSize(size)
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            if name == "todo-review" {
                window.setContentSize(NSSize(width: size.width, height: ceil(view.fittingSize.height)))
                view.layoutSubtreeIfNeeded()
            }
            #expect(view.bounds.width == size.width)
            #expect(view.bounds.height <= size.height)
            #expect(!window.canBecomeKey && !window.canBecomeMain)
            if let path = ProcessInfo.processInfo.environment["NARC_CARD_SNAPSHOT_DIR"],
               path.hasPrefix("/private/tmp/") {
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path)
                    .appendingPathComponent("\(name)-\(appearanceName).png"))
            }
            window.close()
        }
    }
    #expect(try Data(contentsOf: store.storageURL) == before)
}

@Test @MainActor func softFocusTodoReviewFitsContentAndShrinksWithoutTakingFocus() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-review-size-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AssistantStore(storageURL: directory.appendingPathComponent("assistant.json"))
    #expect(store.createTodo(title: "发送测试版"))
    var measuredHeight: CGFloat = 0
    let window = TodoNudgeWindow(rootView: TodoNudgeCardView(
        store: store, onActionStarted: {}, onActionFailed: {}, onSuccessfulAction: {},
        onDismiss: {}, onSnooze: {}, onViewAll: {}, onHeightChange: { measuredHeight = $0 }
    ))
    defer { window.close() }
    let view = try #require(window.contentView)
    func fit() async throws -> CGFloat {
        for _ in 0..<3 {
            window.setContentSize(NSSize(width: 360, height: ceil(view.fittingSize.height)))
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        #expect(abs(measuredHeight - window.frame.height) <= 1)
        #expect(!window.canBecomeKey && !window.canBecomeMain)
        return window.frame.height
    }
    let single = try await fit()
    #expect(single > 150 && single < 270)
    for index in 0..<3 { #expect(store.createTodo(title: "核对长标题换行和其他待办的展示，不要挤压操作按钮 \(index)")) }
    let multiple = try await fit()
    #expect(multiple > single)
    #expect(multiple < 420)
    for todo in Array(store.todos) { #expect(store.setTodoCompleted(id: todo.id, completed: true)) }
    let empty = try await fit()
    #expect(empty < single)
    print("Todo review content heights: single=\(single), multiple=\(multiple), empty=\(empty)")
}
