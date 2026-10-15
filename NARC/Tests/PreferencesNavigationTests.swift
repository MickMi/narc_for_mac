import AppKit
import SwiftUI
import Testing
@testable import NARC

private struct PreferencesPreviewSecretStore: InstantQuestionSecretStore {
    func value(for account: String) throws -> String? { nil }
    func set(_ value: String, for account: String) throws {}
    func removeValue(for account: String) throws {}
}

private struct PreferencesPreviewAnswering: InstantQuestionAnswering {
    func answer(
        messages: [InstantQuestionMessage],
        attachment: InstantQuestionImageAttachment?,
        credentials: InstantQuestionCredentials
    ) async throws -> InstantQuestionReply {
        InstantQuestionReply(answer: "预览", sources: [])
    }
}

@Test
func preferencesNavigationKeepsEveryPrimarySectionVisible() {
    #expect(PreferencesSection.allCases.map(\.title) == [
        "通用", "悬浮球", "快捷键", "通知", "提醒", "AI 回复", "即时问答",
    ])
    #expect(Set(PreferencesSection.allCases.map(\.systemImage)).count == 7)
}

@Test @MainActor
func preferencesWindowHonorsNavigationMinimumSize() {
    _ = NSApplication.shared
    let window = PreferencesWindow(
        contentSize: PreferencesLayout.contentSize,
        minimumContentSize: PreferencesLayout.minimumContentSize
    )
    defer { window.close() }

    #expect(window.contentMinSize == PreferencesLayout.minimumContentSize)
    #expect(window.contentView?.frame.size == PreferencesLayout.contentSize)

    window.orderFront(nil)
    #expect(window.isVisible)
    window.close()
    #expect(!window.isVisible)
    window.makeKeyAndOrderFront(nil)
    #expect(window.isVisible)
}

@Test @MainActor
func preferencesNavigationRendersAllPrimarySections() async throws {
    _ = NSApplication.shared
    let suite = "preferences-navigation-preview-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let previewRoot = URL(fileURLWithPath: "/private/tmp")
        .appendingPathComponent(suite, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: previewRoot) }

    let hotkeyService = HotkeyService(
        accessibilityTrustCheck: { _ in false },
        defaults: defaults,
        configurableHotkeyRegistrar: { _, _, slotID in
            .success(HotkeyRegistrationToken(slotID: slotID) { noErr })
        },
        requiresInstalledEventHandlerForSelectedTextTodo: false,
        requiresInstalledEventHandlerForConfigurableHotkeys: false
    )
    let credentials = InstantQuestionCredentialManager(
        secretStore: PreferencesPreviewSecretStore()
    )
    let instantQuestionController = InstantQuestionController(
        credentials: credentials,
        store: InstantQuestionStore(
            storageURL: previewRoot.appendingPathComponent("instant-questions-v1.json")
        ),
        service: PreferencesPreviewAnswering()
    )
    let navigation = PreferencesNavigation()
    navigation.selectedSection = .instantQuestions

    var windows: [NSWindow] = []

    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PreferencesLayout.contentSize.width,
                height: PreferencesLayout.contentSize.height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(
            rootView: PreferencesView(
                appMonitor: AppMonitorService(),
                hotkeyService: hotkeyService,
                reminderSettings: TodoReminderSettings(defaults: defaults),
                codexCompletionService: CodexCompletionService(
                    defaults: defaults,
                    eventFolder: previewRoot.appendingPathComponent("codex-completion")
                ),
                instantQuestionController: instantQuestionController,
                navigation: navigation,
                onPreviewReminder: {}
            )
                .environment(\.colorScheme, scheme)
        )
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        #expect(view.bounds.size == NSSize(
            width: PreferencesLayout.contentSize.width,
            height: PreferencesLayout.contentSize.height
        ))

        if let path = ProcessInfo.processInfo.environment["NARC_PREFERENCES_SNAPSHOT_DIR"],
           path.hasPrefix("/private/tmp/") {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path)
                .appendingPathComponent("preferences-navigation-\(name).png"))
        }

        for section in PreferencesSection.allCases {
            navigation.selectedSection = section
            await Task.yield()
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            #expect(view.bounds.size == PreferencesLayout.contentSize)
        }
        navigation.selectedSection = .instantQuestions
        windows.append(window)
    }

    windows.forEach { $0.close() }
}
