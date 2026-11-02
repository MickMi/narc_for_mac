import AppKit
import SwiftUI
import Testing
@testable import NARC

private final class TutorialSecrets: InstantQuestionSecretStore, @unchecked Sendable {
    var key: String? = "example-not-a-real-key"
    func containsValue(for account: String) throws -> Bool { key != nil }
    func value(for account: String) throws -> String? { key }
    func set(_ value: String, for account: String) throws { key = value }
    func removeValue(for account: String) throws { key = nil }
}
private struct TutorialAnswer: InstantQuestionAnswering {
    func answer(messages: [InstantQuestionMessage], attachment: InstantQuestionImageAttachment?,
                credentials: InstantQuestionCredentials) async throws -> InstantQuestionReply {
        InstantQuestionReply(answer: "可以分成两步：\n\n1. **先列出要做的事**，一次记录一项。\n2. **做完再勾掉**，剩余事项继续保留。", sources: [])
    }
}

/// Deliberate opt-in authoring: renders actual production views with isolated
/// example data. No real key, hook connection, window manipulation or web search.
@Test @MainActor func helpTutorialAssetsRenderFromProductionViews() async throws {
    guard let path = ProcessInfo.processInfo.environment["NARC_HELP_ASSET_OUTPUT"], path.hasPrefix("/private/tmp/") else { return }
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let suite = "narc-tutorial-assets-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let dataRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: dataRoot) }
    for topic in HelpTopic.allCases { OnboardingPresentationPolicy.dismissFeatureHint(topic, defaults: defaults) }
    let hotkeys = HotkeyService(accessibilityTrustCheck: { _ in true }, defaults: defaults,
        configurableHotkeyRegistrar: { _, _, slot in .success(HotkeyRegistrationToken(slotID: slot) { noErr }) },
        requiresInstalledEventHandlerForSelectedTextTodo: false, requiresInstalledEventHandlerForConfigurableHotkeys: false)
    let pins = PinnedWindowService(defaults: defaults, startsPolling: false)
    pins.pinnedWindows = [
        PinnedWindow(bundleID: "com.apple.Safari", windowTitle: "产品设计参考", appDisplayName: "Safari"),
        PinnedWindow(bundleID: "com.apple.TextEdit", windowTitle: "发布清单", appDisplayName: "文本编辑"),
        PinnedWindow(bundleID: "com.apple.finder", windowTitle: "项目资料", appDisplayName: "Finder")]
    for pin in pins.pinnedWindows {
        pins.runtimeStates[pin.id] = PinnedWindowRuntimeState(isAlive: true, currentTitle: pin.windowTitle)
    }
    hotkeys.updatePinnedWindowSlotCount(3)
    hotkeys.registerConfiguredHotkeys(noAX: false)
    let pinSelection = PinnedWindowSwitcherSelectionState()
    pinSelection.reset(itemCount: 3)
    let todoStore = AssistantStore(storageURL: dataRoot.appendingPathComponent("assistant.json"))
    #expect(todoStore.createTodo(title: "周五前寄出快递"))
    #expect(todoStore.createTodo(title: "整理会议待办"))
    let capture = InboxCaptureState(store: todoStore)
    capture.hideOnboardingHintForThisSession()
    capture.updateDraft("预约下周的检查")
    let records = InstantQuestionStore(storageURL: dataRoot.appendingPathComponent("questions.json"))
    let credentials = InstantQuestionCredentialManager(secretStore: TutorialSecrets(), defaults: defaults)
    let controller = InstantQuestionController(credentials: credentials, store: records,
        service: TutorialAnswer(), webSearchEnabled: false, preferences: defaults)
    let settings = InstantQuestionSettingsView(controller: controller)
    let replies = CodexCompletionService(defaults: defaults, eventFolder: dataRoot)
    let now = Date()
    replies.setEnabled(true, now: now.addingTimeInterval(-60))
    replies.ingest([CodexCompletionEvent(schemaVersion: 1,
        threadID: "00000000-0000-0000-0000-000000000001", turnID: "00000000-0000-0000-0000-000000000011",
        state: "replyReady", title: "整理发布清单", timestamp: now.timeIntervalSince1970 - 1, isPreview: true,
        roundSummary: "已整理待发布内容和需要确认的事项", nextStep: "确认清单后继续对话")], now: now)
    let monitor = AppMonitorService()
    monitor.filters = []
    monitor.notificationStates = [
        NotificationState(app: MonitoredApp(id: "com.tencent.xinWeChat", displayName: "微信", category: .im, isEnabled: true)),
        NotificationState(app: MonitoredApp(id: "com.electron.lark", displayName: "飞书", category: .im, isEnabled: true))]
    for (index,state) in monitor.notificationStates.enumerated() { state.isRunning = true; state.badgeCount = index == 0 ? 3 : 1 }
    let noPins = PinnedWindowService(defaults: defaults, startsPolling: false)
    noPins.pinnedWindows = []
    for (appearance, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        func render(_ name: String, size: NSSize, content: AnyView) async throws -> Data {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = NSHostingView(rootView: content.environment(\.colorScheme, scheme).background(Color.narcBackground))
            defer { window.close() }
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("tutorial-\(name)-\(appearance).png"))
            return png
        }
        _ = try await render("mark-result", size: NSSize(width: 400, height: 96), content: AnyView(
            AccessibilityReadyToastView(title: "窗口已标记", message: "按 ⌃⌥P 可随时用键盘召回。",
                                       systemImage: "pin.fill", accentColor: .narcSuccess, size: NSSize(width: 400, height: 96))))
        let todoPNG = try await render("todo", size: NSSize(width: 360, height: 350), content: AnyView(
            QuickCaptureView(store: todoStore, captureState: capture, compact: true, onboardingDefaults: defaults)))
        _ = try await render("pins", size: PinnedWindowSwitcherLayout.panelSize(itemCount: 3), content: AnyView(
            PinnedWindowSwitcherView(pinnedWindowService: pins, hotkeyService: hotkeys, selection: pinSelection,
                                     onActivate: { _ in }, onClose: {}, onItemCountChanged: { _ in })))
        _ = try await render("layouts", size: NSSize(width: 360, height: 440), content: AnyView(
            WindowGridView(windowManager: WindowManagerService(), hotkeyService: hotkeys)))
        _ = try await render("shortcuts", size: NSSize(width: 500, height: 400), content: AnyView(
            ConfigurableShortcutEditor(hotkeyService: hotkeys, action: .toggleCurrentWindowPin, onClose: {})))
        _ = try await render("ai-settings", size: NSSize(width: 590, height: 650), content: AnyView(settings))
        #expect(credentials.saveDeepSeekKey("example-not-a-real-key"))
        controller.clearCurrent()
        controller.draft = "怎样把想到的事整理成待办？"
        controller.sendDraft()
        for _ in 0..<100 { if !controller.isBusy { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(!controller.isBusy && controller.messages.count == 2)
        _ = try await render("ai", size: NSSize(width: 680, height: 520), content: AnyView(
            InstantQuestionView(controller: controller, store: records, onOpenPreferences: {}, onboardingDefaults: defaults)))
        try controller.attachImage(name: "示例截图.png", mediaType: "image/png", data: todoPNG)
        controller.draft = "请帮我整理截图上的待办"
        _ = try await render("ai-image", size: NSSize(width: 680, height: 520), content: AnyView(
            InstantQuestionView(controller: controller, store: records, onOpenPreferences: {}, onboardingDefaults: defaults)))
        controller.clearCurrent()
        _ = try await render("web", size: NSSize(width: 640, height: 150), content: AnyView(
            WebSearchView(provider: .bing, refreshToken: UUID(), query: .constant("Mac 快捷键"), pageURL: .constant(URL(string: "about:blank")!))))
        _ = try await render("replies", size: NSSize(width: 410, height: 280), content: AnyView(
            CodexCompletionCard(service: replies, layout: CodexCompletionCardLayout(), onResize: {}, onOpen: { _, _ in }, fillsAvailableHeight: true)))
        _ = try await render("messages", size: NSSize(width: 360, height: 300), content: AnyView(
            NotificationListView(appMonitor: monitor, pinnedWindowService: noPins, hotkeyService: hotkeys, onClose: {},
                                 narcScreenProvider: { nil }, keyboardSelection: KeyboardSelectionState())))
        for page in TutorialDesignPage.allCases {
            _ = try await render("design-" + page.rawValue, size: NSSize(width: 960, height: 720), content: AnyView(
                TutorialDesignMockup(page: page, imageRoot: output, appearance: appearance)))
        }
    }
}
