import AppKit
import SwiftUI
import Testing
@testable import NARC

@Test @MainActor
func shortcutSettingsRenderInstantSearchActions() async throws {
    _ = NSApplication.shared
    let suite = "shortcut-search-preview-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let registrar: HotkeyRegistrar = { _, _, slotID in
        .success(HotkeyRegistrationToken(slotID: slotID) { noErr })
    }
    let service = HotkeyService(
        accessibilityTrustCheck: { _ in false },
        defaults: defaults,
        configurableHotkeyRegistrar: registrar,
        requiresInstalledEventHandlerForSelectedTextTodo: false,
        requiresInstalledEventHandlerForConfigurableHotkeys: false
    )
    service.registerConfiguredHotkeys(noAX: true)
    #expect(ConfigurableHotkeyAction.globalActions.contains(.askAI))
    #expect(ConfigurableHotkeyAction.globalActions.contains(.webSearch))
    #expect(ConfigurableHotkeyAction.globalActions.contains(.googleSearch))

    var windows: [NSWindow] = []
    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 760),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(
            rootView: ShortcutsTab(hotkeyService: service)
                .environment(\.colorScheme, scheme)
        )
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        #expect(view.bounds.size == NSSize(width: 620, height: 760))
        if let path = ProcessInfo.processInfo.environment["NARC_SHORTCUT_SNAPSHOT_DIR"],
           path.hasPrefix("/private/tmp/") {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path)
                .appendingPathComponent("search-shortcuts-\(name).png"))
        }
        windows.append(window)
    }
    windows.forEach { $0.close() }
}

@Test
func shortcutSettingsActiveShowsRuntimeChordOnlyOnce() {
    let configured = ConfigurableHotkeyAction.quickCapture.defaultShortcut
    let active = ConfigurableHotkeyAction.summonWidget.defaultShortcut
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: configured,
        state: .active(active)
    )

    #expect(presentation.shortcut == active)
    #expect(presentation.message == "已启用")
    #expect(!presentation.message.contains(active.displayLabel))
    #expect(presentation.detailMessage == nil)
    #expect(!presentation.needsAttention)
}

@Test
func shortcutSettingsDisabledDoesNotRepeatChordOrClaimFailure() {
    let shortcut = ConfigurableHotkeyAction.layoutLeftHalf.defaultShortcut
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: shortcut,
        state: .disabled(shortcut)
    )

    #expect(presentation.shortcut == shortcut)
    #expect(presentation.message == "已停用")
    #expect(!presentation.message.contains(shortcut.displayLabel))
    #expect(presentation.detailMessage == nil)
    #expect(!presentation.needsAttention)
}

@Test
func shortcutSettingsRejectedSeparatesActiveBadgeFromRequestedFailure() {
    let active = ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultShortcut
    let requested = ConfigurableHotkeyAction.quickCapture.defaultShortcut
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: active,
        state: .rejected(active: active, requested: requested, reason: .occupied)
    )

    #expect(presentation.shortcut == active)
    #expect(presentation.message == "原组合仍生效")
    #expect(presentation.detailMessage?.contains(requested.displayLabel) == true)
    #expect(presentation.detailMessage?.contains(HotkeyRegistrationFailure.occupied.userMessage) == true)
    #expect(presentation.detailMessage?.contains(active.displayLabel) == false)
    #expect(presentation.needsAttention)
}

@Test
func shortcutSettingsUnavailableDoesNotAdvertiseAnActiveChord() {
    let shortcut = ConfigurableHotkeyAction.selectedTextTodo.defaultShortcut
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: shortcut,
        state: .unavailable(requested: shortcut, reason: .eventHandlerUnavailable)
    )

    #expect(presentation.shortcut == shortcut)
    #expect(presentation.message == "未启用")
    #expect(presentation.detailMessage == HotkeyRegistrationFailure.eventHandlerUnavailable.userMessage)
    #expect(presentation.needsAttention)
}

@Test
func shortcutSettingsNoAXOverridesAnyStaleActivePresentation() {
    let shortcut = ConfigurableHotkeyAction.layoutFullScreen.defaultShortcut
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: shortcut,
        state: .active(shortcut),
        isRuntimeUnavailable: true
    )

    #expect(presentation.message == "未启用")
    #expect(presentation.symbolName == "hammer.fill")
    #expect(presentation.detailMessage?.contains("no-AX") == true)
    #expect(presentation.needsAttention)
}

@Test
func shortcutSettingsFailedEnableStaysDisabledAndAppearsInGroupSummary() {
    let shortcut = ConfigurableHotkeyAction.layoutLeftHalf.defaultShortcut
    let failure = HotkeyRegistrationFailure.conflictsWithNARC("快速记录").userMessage
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: shortcut,
        state: .disabled(shortcut),
        operationFailure: failure
    )

    #expect(presentation.shortcut == shortcut)
    #expect(presentation.message == "已停用")
    #expect(presentation.detailMessage == failure)
    #expect(presentation.needsAttention)
}

@Test
func shortcutSettingsFailureReasonIsNotDuplicatedByLocalResult() {
    let active = ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultShortcut
    let requested = ConfigurableHotkeyAction.quickCapture.defaultShortcut
    let presentation = ShortcutStatusPresentation(
        configuredShortcut: active,
        state: .rejected(active: active, requested: requested, reason: .occupied),
        operationFailure: HotkeyRegistrationFailure.occupied.userMessage
    )

    #expect(
        presentation.detailMessage
            == "\(requested.displayLabel) 未生效：\(HotkeyRegistrationFailure.occupied.userMessage)。"
    )
}

@Test
func shortcutSettingsGroupAttentionIncludesPendingAndFailureNotDisabled() {
    let shortcut = ConfigurableHotkeyAction.layoutLeftHalf.defaultShortcut
    let states: [ConfigurableHotkeyState] = [
        .active(shortcut),
        .disabled(shortcut),
        .notRegistered,
        .unavailable(requested: shortcut, reason: .occupied),
    ]
    let presentations = states.map {
        ShortcutStatusPresentation(configuredShortcut: shortcut, state: $0)
    }

    #expect(presentations.filter(\.needsAttention).count == 2)
    #expect(presentations[2].message == "等待注册")
}
