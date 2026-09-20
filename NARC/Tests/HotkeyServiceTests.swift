import Foundation
import Testing
@testable import NARC

@Test
func selectedTextTodoShortcutPresetsAreStableAndDoNotOverlapBuiltIns() {
    let presets = SelectedTextTodoShortcut.allCases
    let builtInControlOptionKeyCodes: Set<UInt32> = [
        123, 124, 126, 125, 36, 8, 32, 34, 38, 40, 35, 45, 12,
    ]

    #expect(presets == [
        .controlOptionT,
        .controlOptionR,
        .controlOptionD,
        .controlOptionA,
    ])
    #expect(presets.map(\.displayLabel) == ["⌃⌥T", "⌃⌥R", "⌃⌥D", "⌃⌥A"])
    #expect(Set(presets.map(\.keyCode)).count == presets.count)
    #expect(presets.allSatisfy { !builtInControlOptionKeyCodes.contains($0.keyCode) })
}

@Test
func pinnedWindowRecallAndToggleUseDistinctStableChords() {
    let recall = HotkeyService.pinnedWindowSwitcherHotkey
    let toggle = HotkeyService.toggleCurrentWindowPinHotkey

    #expect(recall.id == 100)
    #expect(toggle.id == 102)
    #expect(recall.keyCode == 35)
    #expect(toggle.keyCode == 35)
    #expect(recall.modifiers != toggle.modifiers)
    #expect(recall.label.contains("⌃⌥P"))
    #expect(toggle.label.contains("⌃⌥⇧P"))
}

@Test
@MainActor
func invalidPersistedSelectedTextTodoShortcutFallsBackToDefaultUntilRegistrationSucceeds() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("unsupported-shortcut", forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)

    #expect(service.selectedTextTodoShortcut == .controlOptionT)
    #expect(service.selectedTextTodoHotkeyState == .notRegistered)
    #expect(
        defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
            == "unsupported-shortcut"
    )

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    #expect(
        defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
            == SelectedTextTodoShortcut.controlOptionT.rawValue
    )
    #expect(service.selectedTextTodoHotkeyState == .active(.controlOptionT))
}

@Test
@MainActor
func selectedTextTodoShortcutCannotClaimActiveWithoutAnEventHandler() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = HotkeyService(
        accessibilityTrustCheck: { _ in false },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60,
        defaults: defaults,
        selectedTextTodoHotkeyRegistrar: registrar.register
    )

    #expect(
        service.updateSelectedTextTodoShortcut(.controlOptionT)
            == .rejected(.eventHandlerUnavailable)
    )
    #expect(
        service.selectedTextTodoHotkeyState == .unavailable(
            requested: .controlOptionT,
            reason: .eventHandlerUnavailable
        )
    )
    #expect(registrar.events.isEmpty)
    #expect(defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey) == nil)
}

@Test
@MainActor
func selectedTextTodoShortcutReplacementUsesFreshSlotsAndPersistsLast() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    #expect(service.updateSelectedTextTodoShortcut(.controlOptionR) == .applied(.controlOptionR))
    #expect(service.updateSelectedTextTodoShortcut(.controlOptionD) == .applied(.controlOptionD))

    #expect(registrar.events == [
        "register:104:17",
        "register:105:15",
        "unregister:104",
        "register:1000:2",
        "unregister:105",
    ])
    #expect(registrar.persistedValuesAtUnregister == [
        SelectedTextTodoShortcut.controlOptionT.rawValue,
        SelectedTextTodoShortcut.controlOptionR.rawValue,
    ])
    #expect(service.selectedTextTodoShortcut == .controlOptionD)
    #expect(service.selectedTextTodoHotkeyState == .active(.controlOptionD))
    #expect(
        defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
            == SelectedTextTodoShortcut.controlOptionD.rawValue
    )
}

@Test
@MainActor
func failedSelectedTextTodoShortcutReplacementKeepsEffectiveShortcutAndPersistence() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    registrar.failuresByKeyCode[SelectedTextTodoShortcut.controlOptionR.keyCode] = .occupied

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionR) == .rejected(.occupied))
    #expect(registrar.events == [
        "register:104:17",
        "register:105:15",
    ])
    #expect(service.selectedTextTodoShortcut == .controlOptionT)
    #expect(service.selectedTextTodoHotkeyState == .rejected(
        active: .controlOptionT,
        requested: .controlOptionR,
        reason: .occupied
    ))
    #expect(
        defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
            == SelectedTextTodoShortcut.controlOptionT.rawValue
    )
}

@Test
@MainActor
func selectingTheAlreadyActiveSelectedTextTodoShortcutIsANoOp() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .unchanged)
    #expect(registrar.events == ["register:104:17"])
    #expect(service.selectedTextTodoHotkeyState == .active(.controlOptionT))
}

@Test
@MainActor
func selectedTextTodoHotkeyLatchIgnoresRepeatsUntilRelease() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)
    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    var callbackCount = 0
    service.onSelectedTextTodoHotkeyPressed = {
        callbackCount += 1
    }

    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: true)
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: true)
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: true)
    #expect(callbackCount == 1)

    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: false)
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: true)
    #expect(callbackCount == 2)
}

@Test
@MainActor
func queuedEventFromReplacedSelectedTextTodoSlotIsIgnored() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)
    var callbackCount = 0
    service.onSelectedTextTodoHotkeyPressed = {
        callbackCount += 1
    }

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: true)
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: false)
    #expect(callbackCount == 1)

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionR) == .applied(.controlOptionR))
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: true)
    service.handleSelectedTextTodoHotkeyEvent(slotID: 104, isPressed: false)
    #expect(callbackCount == 1)

    service.handleSelectedTextTodoHotkeyEvent(slotID: 105, isPressed: true)
    #expect(callbackCount == 2)
}

@Test
@MainActor
func failedExistingUnregistrationRollsBackCandidateAndKeepsOldConfiguration() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)
    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    registrar.unregisterStatusesBySlotID[104] = OSStatus(-1)

    #expect(
        service.updateSelectedTextTodoShortcut(.controlOptionR)
            == .rejected(.couldNotUnregisterExisting(OSStatus(-1)))
    )
    #expect(registrar.events == [
        "register:104:17",
        "register:105:15",
        "unregister:104",
        "unregister:105",
    ])
    #expect(service.selectedTextTodoShortcut == .controlOptionT)
    #expect(service.selectedTextTodoHotkeyState == .rejected(
        active: .controlOptionT,
        requested: .controlOptionR,
        reason: .couldNotUnregisterExisting(OSStatus(-1))
    ))
    #expect(
        defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
            == SelectedTextTodoShortcut.controlOptionT.rawValue
    )
}

@Test
@MainActor
func unregisteringSelectedTextTodoHotkeyClearsItsPublishedState() {
    let (defaults, suiteName) = isolatedHotkeyDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let registrar = RecordingHotkeyRegistrar(defaults: defaults)
    let service = makeHotkeyService(defaults: defaults, registrar: registrar)

    #expect(service.updateSelectedTextTodoShortcut(.controlOptionT) == .applied(.controlOptionT))
    service.unregisterGlobalHotkeys()

    #expect(registrar.events == ["register:104:17", "unregister:104"])
    #expect(service.selectedTextTodoHotkeyState == .notRegistered)
}

private final class RecordingHotkeyRegistrar {
    let defaults: UserDefaults
    var failuresByKeyCode: [UInt32: HotkeyRegistrationFailure] = [:]
    var events: [String] = []
    var persistedValuesAtUnregister: [String?] = []
    var unregisterStatusesBySlotID: [UInt32: OSStatus] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        slotID: UInt32
    ) -> Result<HotkeyRegistrationToken, HotkeyRegistrationFailure> {
        events.append("register:\(slotID):\(keyCode)")
        if let failure = failuresByKeyCode[keyCode] {
            return .failure(failure)
        }

        return .success(
            HotkeyRegistrationToken(slotID: slotID) { [weak self] in
                guard let self else { return noErr }
                self.events.append("unregister:\(slotID)")
                self.persistedValuesAtUnregister.append(
                    self.defaults.string(forKey: HotkeyService.selectedTextTodoShortcutDefaultsKey)
                )
                return self.unregisterStatusesBySlotID[slotID] ?? noErr
            }
        )
    }
}

private func makeHotkeyService(
    defaults: UserDefaults,
    registrar: RecordingHotkeyRegistrar
) -> HotkeyService {
    HotkeyService(
        accessibilityTrustCheck: { _ in false },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60,
        defaults: defaults,
        selectedTextTodoHotkeyRegistrar: registrar.register,
        requiresInstalledEventHandlerForSelectedTextTodo: false
    )
}

private func isolatedHotkeyDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "HotkeyServiceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
