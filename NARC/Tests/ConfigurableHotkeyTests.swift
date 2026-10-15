import Carbon
import Foundation
import Testing
@testable import NARC

@Test
func configurableShortcutValidationAndDisplayUseExplicitStableKeys() {
    let controlOption = UInt32(controlKey | optionKey)
    let controlShift = UInt32(controlKey | shiftKey)

    #expect(ConfigurableShortcut(keyCode: 0, modifiers: controlOption).isValid)
    #expect(ConfigurableShortcut(keyCode: 122, modifiers: controlShift).isValid)
    #expect(ConfigurableShortcut(keyCode: 123, modifiers: controlOption).isValid)
    #expect(!ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey)).isValid)
    #expect(!ConfigurableShortcut(keyCode: 999, modifiers: controlOption).isValid)
    #expect(
        !ConfigurableShortcut(
            keyCode: 0,
            modifiers: controlOption | UInt32(1 << 20)
        ).isValid
    )
    #expect(
        ConfigurableShortcut(keyCode: 35, modifiers: UInt32(controlKey | optionKey | shiftKey))
            .displayLabel == "⌃⌥⇧P"
    )

    let options = ConfigurableShortcut.keyOptions
    #expect(Set(options.map(\.keyCode)).count == options.count)
    #expect(options.contains(ShortcutKeyOption(keyCode: 0, label: "A")))
    #expect(options.contains(ShortcutKeyOption(keyCode: 25, label: "9")))
    #expect(options.contains(ShortcutKeyOption(keyCode: 111, label: "F12")))
    #expect(options.contains(ShortcutKeyOption(keyCode: 126, label: "↑")))
}

@Test
func configurableHotkeyActionsKeepStableDefaultsAndStorageKeys() {
    #expect(ConfigurableHotkeyAction.allCases == [
        .layoutLeftHalf,
        .layoutRightHalf,
        .layoutTopHalf,
        .layoutBottomHalf,
        .layoutFullScreen,
        .layoutCenter,
        .layoutTopLeft,
        .layoutTopRight,
        .layoutBottomLeft,
        .layoutBottomRight,
        .pinnedWindowSwitcher,
        .toggleCurrentWindowPin,
        .pinnedWindowSlot1,
        .pinnedWindowSlot2,
        .pinnedWindowSlot3,
        .pinnedWindowSlot4,
        .pinnedWindowSlot5,
        .pinnedWindowSlot6,
        .pinnedWindowSlot7,
        .pinnedWindowSlot8,
        .pinnedWindowSlot9,
        .summonWidget,
        .quickCapture,
        .selectedTextTodo,
        .askAI,
        .webSearch,
        .googleSearch,
    ])
    #expect(ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultShortcut.displayLabel == "⌃⌥P")
    #expect(ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultShortcut.displayLabel == "⌃⌥⇧P")
    #expect(ConfigurableHotkeyAction.pinnedWindowSlotActions.map(\.defaultShortcut.displayLabel) == [
        "⌃⌥1", "⌃⌥2", "⌃⌥3", "⌃⌥4", "⌃⌥5", "⌃⌥6", "⌃⌥7", "⌃⌥8", "⌃⌥9",
    ])
    #expect(ConfigurableHotkeyAction.askAI.defaultShortcut.displayLabel == "⌃⌥⇧D")
    #expect(ConfigurableHotkeyAction.webSearch.defaultShortcut.displayLabel == "⌃⌥B")
    #expect(ConfigurableHotkeyAction.googleSearch.defaultShortcut.displayLabel == "⌃⌥G")
    #expect(
        ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultsKey
            != ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultsKey
    )
}

@Test
@MainActor
func instantSearchHotkeysDispatchOncePerPhysicalPress() async {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    var actions: [String] = []
    service.onAskAIHotkeyPressed = { actions.append("ask") }
    service.onWebSearchHotkeyPressed = { actions.append("bing") }
    service.onGoogleSearchHotkeyPressed = { actions.append("google") }

    let askShortcut = ConfigurableHotkeyAction.askAI.defaultShortcut
    let searchShortcut = ConfigurableHotkeyAction.webSearch.defaultShortcut
    #expect(service.updateShortcut(askShortcut, for: .askAI) == .applied(askShortcut))
    #expect(service.updateShortcut(searchShortcut, for: .webSearch) == .applied(searchShortcut))
    let googleShortcut = ConfigurableHotkeyAction.googleSearch.defaultShortcut
    #expect(service.updateShortcut(googleShortcut, for: .googleSearch) == .applied(googleShortcut))
    service.handleConfigurableHotkeyEvent(slotID: 120, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 120, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 120, isPressed: false)
    service.handleConfigurableHotkeyEvent(slotID: 121, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 124, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 124, isPressed: true)
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
    #expect(actions == ["ask", "bing", "google"])
}

@Test
@MainActor
func newSearchDefaultDoesNotDisplaceAnOlderSavedShortcut() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(
        SelectedTextTodoShortcut.controlOptionD.rawValue,
        forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey
    )
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)

    service.registerConfiguredHotkeys(noAX: false)

    #expect(
        service.activeShortcut(for: .selectedTextTodo)
            == SelectedTextTodoShortcut.controlOptionD.configurableShortcut
    )
    #expect(service.activeShortcut(for: .askAI) == ConfigurableHotkeyAction.askAI.defaultShortcut)
}

@Test @MainActor
func googleSearchDefaultPreservesOlderBingCustomization() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let shortcut = ConfigurableHotkeyAction.googleSearch.defaultShortcut
    defaults.set(try JSONEncoder().encode(shortcut), forKey: ConfigurableHotkeyAction.webSearch.defaultsKey)
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    service.registerConfiguredHotkeys(noAX: true)
    #expect(service.activeShortcut(for: .webSearch) == shortcut)
    #expect(service.activeShortcut(for: .googleSearch) == nil)
    #expect(service.hotkeyState(for: .googleSearch) == .unavailable(
        requested: shortcut, reason: .conflictsWithNARC("Bing 搜索")))
    #expect(defaults.data(forKey: ConfigurableHotkeyAction.googleSearch.defaultsKey) == nil)
}

@Test @MainActor
func googleSearchCustomizationPersistsAndUsesReplacementSlot() async throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    service.registerConfiguredHotkeys(noAX: true)
    let custom = ConfigurableShortcut(keyCode: 5, modifiers: UInt32(controlKey | optionKey | shiftKey))
    #expect(service.updateShortcut(custom, for: .googleSearch) == .applied(custom))
    var count = 0
    service.onGoogleSearchHotkeyPressed = { count += 1 }
    service.handleConfigurableHotkeyEvent(slotID: 124, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 125, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 125, isPressed: true)
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
    #expect(count == 1)
    let restored = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    #expect(restored.shortcut(for: .googleSearch) == custom)
}

@Test @MainActor
func oldAskAIDefaultMigratesWithoutRewritingCustomShortcuts() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let oldDefault = ConfigurableShortcut(keyCode: 2, modifiers: UInt32(controlKey | optionKey))
    defaults.set(try JSONEncoder().encode(oldDefault), forKey: ConfigurableHotkeyAction.askAI.defaultsKey)
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    #expect(service.shortcut(for: .askAI) == ConfigurableHotkeyAction.askAI.defaultShortcut)
    service.registerConfiguredHotkeys(noAX: false)
    #expect(service.activeShortcut(for: .askAI) == ConfigurableHotkeyAction.askAI.defaultShortcut)
    let saved = try #require(defaults.data(forKey: ConfigurableHotkeyAction.askAI.defaultsKey))
    #expect(
        try JSONDecoder().decode(ConfigurableShortcut.self, from: saved)
            == ConfigurableHotkeyAction.askAI.defaultShortcut
    )

    let custom = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    defaults.set(try JSONEncoder().encode(custom), forKey: ConfigurableHotkeyAction.askAI.defaultsKey)
    let restored = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    #expect(restored.shortcut(for: .askAI) == custom)
}

@Test
@MainActor
func persistedConfigurableShortcutIsRestoredWithoutClaimingRegistration() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let saved = ConfigurableShortcut(
        keyCode: 0,
        modifiers: UInt32(controlKey | cmdKey)
    )
    defaults.set(
        try JSONEncoder().encode(saved),
        forKey: ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultsKey
    )

    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)

    #expect(service.shortcut(for: .pinnedWindowSwitcher) == saved)
    #expect(service.hotkeyState(for: .pinnedWindowSwitcher) == .notRegistered)
    #expect(service.updateShortcut(saved, for: .pinnedWindowSwitcher) == .applied(saved))
    #expect(service.hotkeyState(for: .pinnedWindowSwitcher) == .active(saved))
}

@Test
@MainActor
func malformedOrInvalidPersistedShortcutFallsBackToDefault() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(
        try JSONEncoder().encode(
            ConfigurableShortcut(keyCode: 999, modifiers: UInt32(controlKey | optionKey))
        ),
        forKey: ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultsKey
    )
    defaults.set(
        Data("not-json".utf8),
        forKey: ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultsKey
    )

    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)

    #expect(
        service.shortcut(for: .pinnedWindowSwitcher)
            == ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultShortcut
    )
    #expect(
        service.shortcut(for: .toggleCurrentWindowPin)
            == ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultShortcut
    )
}

@Test
@MainActor
func configurableShortcutRejectsInvalidAndEveryInternalConflictClass() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let controlOption = UInt32(controlKey | optionKey)

    #expect(
        service.updateShortcut(
            ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey)),
            for: .pinnedWindowSwitcher
        ) == .rejected(.invalidShortcut)
    )
    #expect(
        service.updateShortcut(
            ConfigurableShortcut(keyCode: 123, modifiers: controlOption),
            for: .pinnedWindowSwitcher
        ) == .rejected(.conflictsWithNARC("窗口布局：左半屏"))
    )
    #expect(
        service.updateShortcut(
            ConfigurableShortcut(keyCode: 45, modifiers: controlOption),
            for: .pinnedWindowSwitcher
        ) == .rejected(.conflictsWithNARC("召回悬浮球"))
    )
    #expect(
        service.updateShortcut(
            ConfigurableShortcut(keyCode: 12, modifiers: controlOption),
            for: .pinnedWindowSwitcher
        ) == .rejected(.conflictsWithNARC("快速记录"))
    )
    #expect(
        service.updateShortcut(
            ConfigurableShortcut(keyCode: 17, modifiers: controlOption),
            for: .pinnedWindowSwitcher
        ) == .rejected(.conflictsWithNARC("划词创建 Todo"))
    )

    let shared = ConfigurableShortcut(
        keyCode: 0,
        modifiers: UInt32(controlKey | cmdKey)
    )
    #expect(service.updateShortcut(shared, for: .pinnedWindowSwitcher) == .applied(shared))
    #expect(
        service.updateShortcut(shared, for: .toggleCurrentWindowPin)
            == .rejected(.conflictsWithNARC("召回已标记窗口"))
    )
}

@Test
@MainActor
func selectedTextTodoCannotTakeAConfiguredWindowShortcut() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let controlOptionR = ConfigurableShortcut(
        keyCode: SelectedTextTodoShortcut.controlOptionR.keyCode,
        modifiers: SelectedTextTodoShortcut.controlOptionR.modifiers
    )

    #expect(
        service.updateShortcut(controlOptionR, for: .pinnedWindowSwitcher)
            == .applied(controlOptionR)
    )
    #expect(
        service.updateSelectedTextTodoShortcut(.controlOptionR)
            == .rejected(.conflictsWithNARC("召回已标记窗口"))
    )
}

@Test
@MainActor
func carbonConflictKeepsEffectiveWindowShortcutAndPersistence() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.pinnedWindowSwitcher
    let original = action.defaultShortcut
    let requested = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))

    #expect(service.updateShortcut(original, for: action) == .applied(original))
    registrar.failuresByShortcut[requested] = .occupied
    #expect(service.updateShortcut(requested, for: action) == .rejected(.occupied))

    #expect(service.shortcut(for: action) == original)
    #expect(service.activeShortcut(for: action) == original)
    #expect(
        service.hotkeyState(for: action)
            == .rejected(active: original, requested: requested, reason: .occupied)
    )
    let persisted = try JSONDecoder().decode(
        ConfigurableShortcut.self,
        from: #require(defaults.data(forKey: action.defaultsKey))
    )
    #expect(persisted == original)
}

@Test
@MainActor
func coldStartRegistrationFailureHasNoActiveRuntimeShortcut() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.pinnedWindowSwitcher
    registrar.failuresByShortcut[action.defaultShortcut] = .occupied

    #expect(
        service.updateShortcut(action.defaultShortcut, for: action)
            == .rejected(.occupied)
    )
    #expect(service.shortcut(for: action) == action.defaultShortcut)
    #expect(service.activeShortcut(for: action) == nil)
}

@Test
@MainActor
func configurableReplacementRegistersCandidateBeforeRemovingOldAndThenPersists() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.pinnedWindowSwitcher
    let first = action.defaultShortcut
    let second = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    let third = ConfigurableShortcut(keyCode: 11, modifiers: UInt32(optionKey | cmdKey))

    #expect(service.updateShortcut(first, for: action) == .applied(first))
    #expect(service.updateShortcut(second, for: action) == .applied(second))
    #expect(service.updateShortcut(third, for: action) == .applied(third))

    #expect(registrar.events == [
        "register:100:35",
        "register:106:0",
        "unregister:100",
        "register:1000:11",
        "unregister:106",
    ])
    #expect(registrar.persistedRecallAtUnregister == [first, second])
    #expect(service.shortcut(for: action) == third)
    #expect(service.hotkeyState(for: action) == .active(third))
}

@Test
@MainActor
func failedOldUnregistrationRollsBackCandidateAndKeepsOldWindowShortcut() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.pinnedWindowSwitcher
    let original = action.defaultShortcut
    let requested = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))

    #expect(service.updateShortcut(original, for: action) == .applied(original))
    registrar.unregisterStatusesBySlotID[100] = OSStatus(-1)
    #expect(
        service.updateShortcut(requested, for: action)
            == .rejected(.couldNotUnregisterExisting(OSStatus(-1)))
    )
    #expect(registrar.events == [
        "register:100:35",
        "register:106:0",
        "unregister:100",
        "unregister:106",
    ])
    #expect(service.shortcut(for: action) == original)
}

@Test
@MainActor
func failedRollbackQuarantinesCandidateSlotAndItsEventsRemainInert() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.toggleCurrentWindowPin
    let original = action.defaultShortcut
    let requested = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    let later = ConfigurableShortcut(keyCode: 11, modifiers: UInt32(optionKey | cmdKey))
    var callbackCount = 0
    service.onToggleCurrentWindowPinHotkeyPressed = { callbackCount += 1 }

    #expect(service.updateShortcut(original, for: action) == .applied(original))
    registrar.unregisterStatusesBySlotID[102] = OSStatus(-1)
    registrar.unregisterStatusesBySlotID[107] = OSStatus(-2)
    #expect(
        service.updateShortcut(requested, for: action)
            == .rejected(.couldNotRollbackCandidate(
                existing: OSStatus(-1),
                candidate: OSStatus(-2)
            ))
    )

    service.handleConfigurableHotkeyEvent(slotID: 107, isPressed: true)
    #expect(callbackCount == 0)
    service.handleConfigurableHotkeyEvent(slotID: 102, isPressed: true)
    #expect(callbackCount == 1)
    #expect(
        service.updateShortcut(later, for: action)
            == .rejected(.registrationStateUnavailable)
    )
    #expect(registrar.events.filter { $0.hasPrefix("register:") }.count == 2)
    let recall = ConfigurableHotkeyAction.pinnedWindowSwitcher
    #expect(service.updateShortcut(recall.defaultShortcut, for: recall) == .applied(recall.defaultShortcut))
}

@Test
@MainActor
func configurableEventsIgnoreReplacedSlotsAndPhysicalKeyRepeat() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.toggleCurrentWindowPin
    let replacement = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    var callbackCount = 0
    service.onToggleCurrentWindowPinHotkeyPressed = { callbackCount += 1 }

    #expect(service.updateShortcut(action.defaultShortcut, for: action) == .applied(action.defaultShortcut))
    #expect(service.updateShortcut(replacement, for: action) == .applied(replacement))

    service.handleConfigurableHotkeyEvent(slotID: 102, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 102, isPressed: false)
    #expect(callbackCount == 0)

    service.handleConfigurableHotkeyEvent(slotID: 107, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 107, isPressed: true)
    #expect(callbackCount == 1)
    service.handleConfigurableHotkeyEvent(slotID: 107, isPressed: false)
    service.handleConfigurableHotkeyEvent(slotID: 107, isPressed: true)
    #expect(callbackCount == 2)
}

@Test
@MainActor
func queuedRecallIsCancelledWhenRegistrationGenerationChanges() async {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.pinnedWindowSwitcher
    let replacement = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    var callbackCount = 0
    service.onPinnedWindowSwitcherHotkeyPressed = { callbackCount += 1 }

    #expect(service.updateShortcut(action.defaultShortcut, for: action) == .applied(action.defaultShortcut))
    service.handleConfigurableHotkeyEvent(slotID: 100, isPressed: true)
    #expect(service.updateShortcut(replacement, for: action) == .applied(replacement))

    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
    #expect(callbackCount == 0)
}

@Test
@MainActor
func unregisterCleansActiveAndFailedRollbackTokensAndPublishedStates() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let recall = ConfigurableHotkeyAction.pinnedWindowSwitcher
    let toggle = ConfigurableHotkeyAction.toggleCurrentWindowPin

    #expect(service.updateShortcut(recall.defaultShortcut, for: recall) == .applied(recall.defaultShortcut))
    #expect(service.updateShortcut(toggle.defaultShortcut, for: toggle) == .applied(toggle.defaultShortcut))
    registrar.unregisterStatusesBySlotID[100] = OSStatus(-1)
    registrar.unregisterStatusesBySlotID[106] = OSStatus(-2)
    _ = service.updateShortcut(
        ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey)),
        for: recall
    )

    registrar.unregisterStatusesBySlotID.removeAll()
    service.unregisterGlobalHotkeys()

    #expect(service.hotkeyState(for: recall) == .notRegistered)
    #expect(service.hotkeyState(for: toggle) == .notRegistered)
    let cleanupEvents = Array(registrar.events.suffix(3))
    #expect(cleanupEvents.count == 3)
    #expect(Set(cleanupEvents.prefix(2)) == Set([
        "unregister:100",
        "unregister:102",
    ]))
    #expect(cleanupEvents.last == "unregister:106")
    #expect(cleanupEvents.filter { $0 == "unregister:106" }.count == 1)
}

@Test
@MainActor
func configurableShortcutCannotClaimActiveWithoutEventHandler() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = HotkeyService(
        accessibilityTrustCheck: { _ in false },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60,
        defaults: defaults,
        configurableHotkeyRegistrar: registrar.register
    )
    let action = ConfigurableHotkeyAction.pinnedWindowSwitcher

    #expect(
        service.updateShortcut(action.defaultShortcut, for: action)
            == .rejected(.eventHandlerUnavailable)
    )
    #expect(
        service.hotkeyState(for: action)
            == .unavailable(requested: action.defaultShortcut, reason: .eventHandlerUnavailable)
    )
    #expect(registrar.events.isEmpty)
}

@Test
@MainActor
func disabledLayoutReleasesItsShortcutAndReenableChecksConflicts() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let layout = ConfigurableHotkeyAction.layoutLeftHalf
    let recall = ConfigurableHotkeyAction.pinnedWindowSwitcher

    #expect(service.updateShortcut(layout.defaultShortcut, for: layout) == .applied(layout.defaultShortcut))
    #expect(service.setEnabled(false, for: layout) == .applied(layout.defaultShortcut))
    #expect(!service.isEnabled(for: layout))
    #expect(service.hotkeyState(for: layout) == .disabled(layout.defaultShortcut))
    #expect(registrar.events == ["register:0:123", "unregister:0"])

    // A disabled layout no longer blocks another action from taking its chord.
    #expect(service.updateShortcut(layout.defaultShortcut, for: recall) == .applied(layout.defaultShortcut))
    #expect(
        service.setEnabled(true, for: layout)
            == .rejected(.conflictsWithNARC(recall.title))
    )
    #expect(!service.isEnabled(for: layout))
    #expect(defaults.bool(forKey: layout.enabledDefaultsKey) == false)
}

@Test
@MainActor
func nonLayoutActionsCannotBeDisabled() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)

    #expect(
        service.setEnabled(false, for: .quickCapture)
            == .rejected(.actionCannotBeDisabled)
    )
    #expect(service.isEnabled(for: .quickCapture))
}

@Test
@MainActor
func disabledLayoutKeepsSharedSelectedTextShortcutAcrossRestart() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let layout = ConfigurableHotkeyAction.layoutTopLeft
    let shared = SelectedTextTodoShortcut.controlOptionA.configurableShortcut

    #expect(service.updateShortcut(shared, for: layout) == .applied(shared))
    #expect(service.setEnabled(false, for: layout) == .applied(shared))
    #expect(service.updateShortcut(shared, for: .selectedTextTodo) == .applied(shared))
    service.unregisterGlobalHotkeys()

    let restored = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    #expect(!restored.isEnabled(for: layout))
    #expect(restored.shortcut(for: layout) == shared)
    #expect(restored.shortcut(for: .selectedTextTodo) == shared)
    #expect(restored.hotkeyState(for: layout) == .disabled(shared))
    #expect(restored.setEnabled(true, for: layout) == .rejected(.conflictsWithNARC("划词创建 Todo")))
    #expect(!restored.isEnabled(for: layout))
    #expect(try JSONDecoder().decode(
        ConfigurableShortcut.self,
        from: #require(defaults.data(forKey: layout.defaultsKey))
    ) == shared)
}

@Test
@MainActor
func selectedTextMigrationPrefersNewValueAndPreservesPinPreferences() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(SelectedTextTodoShortcut.controlOptionR.rawValue,
                 forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let migrated = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    #expect(migrated.shortcut(for: .selectedTextTodo) == SelectedTextTodoShortcut.controlOptionR.configurableShortcut)

    let customTodo = ConfigurableShortcut(keyCode: 2, modifiers: UInt32(controlKey | cmdKey))
    let customPin = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(optionKey | cmdKey))
    defaults.set(try JSONEncoder().encode(customTodo), forKey: ConfigurableHotkeyAction.selectedTextTodo.defaultsKey)
    defaults.set(try JSONEncoder().encode(customPin), forKey: ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultsKey)
    let restored = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    #expect(restored.shortcut(for: .selectedTextTodo) == customTodo)
    #expect(restored.shortcut(for: .pinnedWindowSwitcher) == customPin)
    #expect(defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
            == SelectedTextTodoShortcut.controlOptionR.rawValue)
}

@Test
@MainActor
func thirdShortcutRegistrationRejectsOldCarbonPressAndRelease() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.toggleCurrentWindowPin
    let second = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    let third = ConfigurableShortcut(keyCode: 11, modifiers: UInt32(optionKey | cmdKey))
    var callbackCount = 0
    service.onToggleCurrentWindowPinHotkeyPressed = { callbackCount += 1 }
    #expect(service.updateShortcut(action.defaultShortcut, for: action) == .applied(action.defaultShortcut))
    #expect(service.updateShortcut(second, for: action) == .applied(second))
    #expect(service.updateShortcut(third, for: action) == .applied(third))

    let stalePress = try makeConfigurableHotkeyEvent(slotID: 102, isPressed: true)
    let staleRelease = try makeConfigurableHotkeyEvent(slotID: 102, isPressed: false)
    let currentPress = try makeConfigurableHotkeyEvent(slotID: 1_000, isPressed: true)
    let currentRelease = try makeConfigurableHotkeyEvent(slotID: 1_000, isPressed: false)
    defer {
        [stalePress, staleRelease, currentPress, currentRelease].forEach { ReleaseEvent($0) }
    }
    #expect(service.handleCarbonHotkeyEvent(stalePress) == noErr)
    #expect(callbackCount == 0)
    #expect(service.handleCarbonHotkeyEvent(currentPress) == noErr)
    #expect(callbackCount == 1)
    _ = service.handleCarbonHotkeyEvent(staleRelease)
    _ = service.handleCarbonHotkeyEvent(currentPress)
    #expect(callbackCount == 1) // Stale release cannot re-arm the current key.
    _ = service.handleCarbonHotkeyEvent(currentRelease)
    _ = service.handleCarbonHotkeyEvent(currentPress)
    #expect(callbackCount == 2)
}

@Test
@MainActor
func disabledAndReenabledLayoutNeverReusesItsPreviousEventSlot() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.layoutLeftHalf
    var layouts: [WindowLayout] = []
    service.onLayoutHotkeyPressed = { layouts.append($0) }
    #expect(service.updateShortcut(action.defaultShortcut, for: action) == .applied(action.defaultShortcut))
    #expect(service.setEnabled(false, for: action) == .applied(action.defaultShortcut))
    #expect(service.setEnabled(true, for: action) == .applied(action.defaultShortcut))
    service.handleConfigurableHotkeyEvent(slotID: 0, isPressed: true)
    #expect(layouts.isEmpty)
    service.handleConfigurableHotkeyEvent(slotID: 108, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 0, isPressed: false)
    service.handleConfigurableHotkeyEvent(slotID: 108, isPressed: true)
    #expect(layouts == [.leftHalf])
    service.handleConfigurableHotkeyEvent(slotID: 108, isPressed: false)
    service.handleConfigurableHotkeyEvent(slotID: 108, isPressed: true)
    #expect(layouts == [.leftHalf, .leftHalf])
}

@Test
@MainActor
func carbonHotkeyEventRejectsMissingParameterForeignSignatureAndUnknownSlot() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    let action = ConfigurableHotkeyAction.layoutLeftHalf
    var callbackCount = 0
    service.onLayoutHotkeyPressed = { _ in callbackCount += 1 }
    #expect(service.updateShortcut(action.defaultShortcut, for: action) == .applied(action.defaultShortcut))
    let missing = try makeConfigurableHotkeyEvent(slotID: nil, isPressed: true)
    let foreign = try makeConfigurableHotkeyEvent(slotID: 0, isPressed: true, signature: 1)
    let unknown = try makeConfigurableHotkeyEvent(slotID: 9_999, isPressed: true)
    defer { [missing, foreign, unknown].forEach { ReleaseEvent($0) } }
    for event in [missing, foreign, unknown] {
        #expect(service.handleCarbonHotkeyEvent(event) == OSStatus(eventNotHandledErr))
    }
    #expect(callbackCount == 0)
}

@Test
@MainActor
func noAXRegistrationPolicyUsesSavedNavigationShortcutsAndBlocksAXActions() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let summon = ConfigurableShortcut(keyCode: 0, modifiers: UInt32(controlKey | cmdKey))
    let capture = ConfigurableShortcut(keyCode: 11, modifiers: UInt32(optionKey | cmdKey))
    defaults.set(try JSONEncoder().encode(summon), forKey: ConfigurableHotkeyAction.summonWidget.defaultsKey)
    defaults.set(try JSONEncoder().encode(capture), forKey: ConfigurableHotkeyAction.quickCapture.defaultsKey)
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    service.registerConfiguredHotkeys(noAX: true)

    #expect(registrar.events == [
        "register:101:0", "register:103:11", "register:120:2", "register:121:11",
        "register:124:5",
    ])
    #expect(service.activeShortcut(for: .summonWidget) == summon)
    #expect(service.activeShortcut(for: .quickCapture) == capture)
    #expect(service.activeShortcut(for: .askAI) == ConfigurableHotkeyAction.askAI.defaultShortcut)
    #expect(service.activeShortcut(for: .webSearch) == ConfigurableHotkeyAction.webSearch.defaultShortcut)
    #expect(service.activeShortcut(for: .googleSearch) == ConfigurableHotkeyAction.googleSearch.defaultShortcut)
    for action in ConfigurableHotkeyAction.allCases where action.requiresAccessibility {
        #expect(service.activeShortcut(for: action) == nil)
        #expect(service.updateShortcut(action.defaultShortcut, for: action)
                == .rejected(.unavailableInCurrentRuntime))
    }
    #expect(registrar.events.count == 5)
}

@Test
func configurableHotkeyRegistrationRetainsHistoricalExclusivity() {
    for action in ConfigurableHotkeyAction.allCases {
        let expected: OptionBits = ([.pinnedWindowSwitcher, .toggleCurrentWindowPin].contains(action)
            || action.pinnedWindowSlotIndex != nil)
            ? OptionBits(kEventHotKeyExclusive) : 0
        #expect(HotkeyService.registrationOptions(for: action) == expected)
    }
}

@Test
@MainActor
func numericPinSlotsRegisterOnlyWhenOccupiedAndIgnoreReleasedSlots() async {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    var recalledIndices: [Int] = []
    service.onPinnedWindowSlotHotkeyPressed = { recalledIndices.append($0) }

    service.registerConfiguredHotkeys(noAX: false)
    #expect(service.pinnedWindowSlotCount == 0)
    #expect(service.activeShortcut(for: .pinnedWindowSlot1) == nil)
    #expect(!registrar.events.contains(where: { $0.hasPrefix("register:130:") }))

    service.updatePinnedWindowSlotCount(2)
    #expect(service.activeShortcut(for: .pinnedWindowSlot1)?.displayLabel == "⌃⌥1")
    #expect(service.activeShortcut(for: .pinnedWindowSlot2)?.displayLabel == "⌃⌥2")
    #expect(service.activeShortcut(for: .pinnedWindowSlot3) == nil)
    service.handleConfigurableHotkeyEvent(slotID: 130, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 130, isPressed: true)
    service.handleConfigurableHotkeyEvent(slotID: 131, isPressed: true)
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
    #expect(recalledIndices == [0, 1])

    service.updatePinnedWindowSlotCount(1)
    #expect(registrar.events.contains("unregister:131"))
    service.handleConfigurableHotkeyEvent(slotID: 131, isPressed: true)
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
    #expect(recalledIndices == [0, 1])
    service.updatePinnedWindowSlotCount(2)
    #expect(registrar.events.contains("register:141:19"))
}

@Test
@MainActor
func numericPinSlotConflictDoesNotBlockOtherOccupiedSlots() {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    registrar.failuresByShortcut[ConfigurableHotkeyAction.pinnedWindowSlot2.defaultShortcut] = .occupied
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    service.registerConfiguredHotkeys(noAX: false)
    service.updatePinnedWindowSlotCount(2)

    #expect(service.activeShortcut(for: .pinnedWindowSlot1) != nil)
    #expect(service.activeShortcut(for: .pinnedWindowSlot2) == nil)
    #expect(service.hotkeyState(for: .pinnedWindowSlot2) == .unavailable(
        requested: ConfigurableHotkeyAction.pinnedWindowSlot2.defaultShortcut,
        reason: .occupied
    ))
}

@Test
@MainActor
func newNumericPinDefaultDoesNotDisplaceAnOlderSavedShortcut() throws {
    let (defaults, suiteName) = isolatedConfigurableHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let oldChoice = ConfigurableHotkeyAction.pinnedWindowSlot1.defaultShortcut
    defaults.set(try JSONEncoder().encode(oldChoice), forKey: ConfigurableHotkeyAction.summonWidget.defaultsKey)
    let registrar = RecordingConfigurableHotkeyRegistrar(defaults: defaults)
    let service = makeConfigurableHotkeyService(defaults: defaults, registrar: registrar)
    service.updatePinnedWindowSlotCount(1)
    service.registerConfiguredHotkeys(noAX: false)

    #expect(service.activeShortcut(for: .summonWidget) == oldChoice)
    #expect(service.activeShortcut(for: .pinnedWindowSlot1) == nil)
    #expect(service.hotkeyState(for: .pinnedWindowSlot1) == .unavailable(
        requested: oldChoice,
        reason: .conflictsWithNARC(ConfigurableHotkeyAction.summonWidget.title)
    ))
}

private func makeConfigurableHotkeyEvent(
    slotID: UInt32?,
    isPressed: Bool,
    signature: OSType = HotkeyService.hotkeySignature
) throws -> EventRef {
    var created: EventRef?
    let status = CreateEvent(
        nil,
        OSType(kEventClassKeyboard),
        UInt32(isPressed ? kEventHotKeyPressed : kEventHotKeyReleased),
        0,
        0,
        &created
    )
    #expect(status == noErr)
    let event = try #require(created)
    if let slotID {
        var id = EventHotKeyID(signature: signature, id: slotID)
        #expect(SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &id
        ) == noErr)
    }
    return event
}

private final class RecordingConfigurableHotkeyRegistrar {
    let defaults: UserDefaults
    var failuresByShortcut: [ConfigurableShortcut: HotkeyRegistrationFailure] = [:]
    var unregisterStatusesBySlotID: [UInt32: OSStatus] = [:]
    var events: [String] = []
    var persistedRecallAtUnregister: [ConfigurableShortcut?] = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        slotID: UInt32
    ) -> Result<HotkeyRegistrationToken, HotkeyRegistrationFailure> {
        let shortcut = ConfigurableShortcut(keyCode: keyCode, modifiers: modifiers)
        events.append("register:\(slotID):\(keyCode)")
        if let failure = failuresByShortcut[shortcut] {
            return .failure(failure)
        }

        return .success(
            HotkeyRegistrationToken(slotID: slotID) { [weak self] in
                guard let self else { return noErr }
                self.events.append("unregister:\(slotID)")
                let persisted = self.defaults
                    .data(forKey: ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultsKey)
                    .flatMap { try? JSONDecoder().decode(ConfigurableShortcut.self, from: $0) }
                self.persistedRecallAtUnregister.append(persisted)
                return self.unregisterStatusesBySlotID[slotID] ?? noErr
            }
        )
    }
}

private func makeConfigurableHotkeyService(
    defaults: UserDefaults,
    registrar: RecordingConfigurableHotkeyRegistrar
) -> HotkeyService {
    HotkeyService(
        accessibilityTrustCheck: { _ in false },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60,
        defaults: defaults,
        selectedTextTodoHotkeyRegistrar: registrar.register,
        configurableHotkeyRegistrar: registrar.register,
        requiresInstalledEventHandlerForSelectedTextTodo: false,
        requiresInstalledEventHandlerForConfigurableHotkeys: false
    )
}

private func isolatedConfigurableHotkeyDefaults() -> (
    defaults: UserDefaults,
    suiteName: String
) {
    let suiteName = "ConfigurableHotkeyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
