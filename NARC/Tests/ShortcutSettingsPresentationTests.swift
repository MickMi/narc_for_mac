import Testing
@testable import NARC

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
