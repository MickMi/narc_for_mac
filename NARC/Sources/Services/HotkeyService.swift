import Cocoa
import Carbon

/// Legacy persisted presets from the first selected-text Todo implementation.
/// New code uses `ConfigurableShortcut`; this type remains solely so existing
/// installs can migrate without rewriting or deleting the old preference.
enum SelectedTextTodoShortcut: String, CaseIterable, Identifiable {
    case controlOptionT = "control-option-t"
    case controlOptionR = "control-option-r"
    case controlOptionD = "control-option-d"
    case controlOptionA = "control-option-a"

    static let defaultValue: SelectedTextTodoShortcut = .controlOptionT

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionT: return 17
        case .controlOptionR: return 15
        case .controlOptionD: return 2
        case .controlOptionA: return 0
        }
    }

    var modifiers: UInt32 {
        UInt32(controlKey | optionKey)
    }

    var displayLabel: String {
        switch self {
        case .controlOptionT: return "⌃⌥T"
        case .controlOptionR: return "⌃⌥R"
        case .controlOptionD: return "⌃⌥D"
        case .controlOptionA: return "⌃⌥A"
        }
    }

    var configurableShortcut: ConfigurableShortcut {
        ConfigurableShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    init?(configurableShortcut: ConfigurableShortcut) {
        guard let preset = Self.allCases.first(where: {
            $0.keyCode == configurableShortcut.keyCode
                && $0.modifiers == configurableShortcut.modifiers
        }) else {
            return nil
        }
        self = preset
    }
}

enum HotkeyRegistrationFailure: Error, Equatable {
    case occupied
    case eventHandlerUnavailable
    case invalidShortcut
    case conflictsWithNARC(String)
    case unavailableInCurrentRuntime
    case actionCannotBeDisabled
    case registrationStateUnavailable
    case system(OSStatus)
    case couldNotUnregisterExisting(OSStatus)
    case couldNotRollbackCandidate(existing: OSStatus, candidate: OSStatus)

    var userMessage: String {
        switch self {
        case .occupied:
            return "已被 macOS 或其他 App 占用"
        case .eventHandlerUnavailable:
            return "全局快捷键监听尚未就绪"
        case .invalidShortcut:
            return "请选择至少两个有效修饰键和一个支持的主键"
        case .conflictsWithNARC(let feature):
            return "与 NARC 的“\(feature)”快捷键冲突"
        case .unavailableInCurrentRuntime:
            return "当前运行模式不会注册这个动作"
        case .actionCannotBeDisabled:
            return "这个全局动作不能停用"
        case .registrationStateUnavailable:
            return "上次切换未能安全清理，请重开 NARC 后再试"
        case .system(let status):
            return "macOS 拒绝了注册（错误 \(status)）"
        case .couldNotUnregisterExisting(let status):
            return "原组合无法安全释放（错误 \(status)）"
        case .couldNotRollbackCandidate(_, let candidate):
            return "切换未完成，候选组合清理也失败（错误 \(candidate)）"
        }
    }
}

/// The effective selected-text shortcut state. A rejected update retains the
/// previous active shortcut so Preferences never claims an unavailable choice
/// is in use.
enum SelectedTextTodoHotkeyState: Equatable {
    case notRegistered
    case active(SelectedTextTodoShortcut)
    case rejected(
        active: SelectedTextTodoShortcut,
        requested: SelectedTextTodoShortcut,
        reason: HotkeyRegistrationFailure
    )
    case unavailable(
        requested: SelectedTextTodoShortcut,
        reason: HotkeyRegistrationFailure
    )
}

enum SelectedTextTodoShortcutUpdateResult: Equatable {
    case unchanged
    case applied(SelectedTextTodoShortcut)
    case rejected(HotkeyRegistrationFailure)
}

/// An opaque, injectable registration handle. Tests can supply a token that
/// only records cancellation, while production captures the Carbon reference.
struct HotkeyRegistrationToken {
    let slotID: UInt32
    private let unregisterAction: () -> OSStatus

    init(slotID: UInt32, unregisterAction: @escaping () -> OSStatus) {
        self.slotID = slotID
        self.unregisterAction = unregisterAction
    }

    @discardableResult
    func unregister() -> OSStatus {
        unregisterAction()
    }
}

typealias HotkeyRegistrar = (
    _ keyCode: UInt32,
    _ modifiers: UInt32,
    _ slotID: UInt32
) -> Result<HotkeyRegistrationToken, HotkeyRegistrationFailure>

struct BuiltInHotkeyDefinition: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let id: UInt32
    let label: String
}

/// Manages global hotkey registration via Carbon Event API and Accessibility permission.
///
/// Extracted from WindowManagerService to separate hotkey infrastructure from
/// window movement logic. This class handles:
/// - Accessibility permission checking and polling
/// - Carbon Event hotkey registration/unregistration
/// - Dispatching hotkey events to the appropriate handlers
class HotkeyService: ObservableObject {

    // MARK: - Properties

    private var eventHandler: EventHandlerRef?
    private var permissionTimer: Timer?
    private let accessibilityTrustCheck: (Bool) -> Bool
    private let accessibilitySettingsOpener: () -> Void
    private let permissionPollInterval: TimeInterval
    private let permissionRecoveryPollLimit: Int
    private var permissionRecoveryPollCount = 0
    private var shouldReportPermissionRecovery = false
    private var didReportPermissionRecovery = false
    private let defaults: UserDefaults
    private let configurableHotkeyRegistrar: HotkeyRegistrar?
    private let requiresInstalledEventHandlerForSelectedTextTodo: Bool
    private let requiresInstalledEventHandlerForConfigurableHotkeys: Bool
    private var configurableRegistrations: [ConfigurableHotkeyAction: HotkeyRegistrationToken] = [:]
    private var configurableActiveSlotIDs: [ConfigurableHotkeyAction: UInt32] = [:]
    private var configurableSlotOwners: [UInt32: ConfigurableHotkeyAction] = [:]
    private var configurableRegistrationGenerations: [ConfigurableHotkeyAction: UInt64] = [:]
    private var configurableHotkeysPressed: Set<ConfigurableHotkeyAction> = []
    private var usedHotkeySlotIDs: Set<UInt32> = []
    private var nextDynamicHotkeySlotID: UInt32 = 1_000
    private var failedRollbackRegistrations: [HotkeyRegistrationToken] = []
    private var quarantinedHotkeySlotIDs: Set<UInt32> = []
    private var registeredActionScope: Set<ConfigurableHotkeyAction>?
    private var globalHotkeyEventHandlerFailure: OSStatus?
    private let selectedTextTodoHotkeyRegistrar: HotkeyRegistrar?
    @Published private(set) var selectedTextTodoShortcut: SelectedTextTodoShortcut
    @Published private(set) var selectedTextTodoHotkeyState: SelectedTextTodoHotkeyState = .notRegistered

    /// Callback invoked when the pinned-window switcher hotkey (⌃⌥P) is pressed.
    var onPinnedWindowSwitcherHotkeyPressed: (() -> Void)?

    /// Callback invoked when the current-window Pin toggle (⌃⌥⇧P) is pressed.
    var onToggleCurrentWindowPinHotkeyPressed: (() -> Void)?

    /// Callback invoked when the Summon Widget hotkey (⌃⌥N) is pressed.
    var onSummonWidgetHotkeyPressed: (() -> Void)?

    /// Callback invoked when the Quick Capture hotkey (⌃⌥Q) is pressed.
    var onQuickCaptureHotkeyPressed: (() -> Void)?

    /// Callback invoked once per physical press of the selected-text Todo
    /// shortcut. Key-repeat presses are ignored until Carbon sends a release.
    var onSelectedTextTodoHotkeyPressed: (() -> Void)?

    /// Callback invoked when a window layout hotkey is pressed.
    var onLayoutHotkeyPressed: ((WindowLayout) -> Void)?

    /// Callback invoked once when Accessibility changes from denied to granted.
    var onAccessibilityPermissionGranted: (() -> Void)?

    /// Callback invoked once when an explicit authorization request remains
    /// denied long enough to require stale-entry recovery guidance.
    var onAccessibilityPermissionStillDenied: (() -> Void)?

    /// Whether Accessibility permission has been granted.
    @Published var isAccessibilityGranted: Bool = false

    /// Effective configured values. A value advances only after Carbon accepts
    /// its candidate and the previous registration is safely removed.
    @Published private(set) var configurableShortcuts: [
        ConfigurableHotkeyAction: ConfigurableShortcut
    ]

    /// Registration truth for Preferences and runtime shortcut hints.
    @Published private(set) var configurableHotkeyStates: [
        ConfigurableHotkeyAction: ConfigurableHotkeyState
    ]

    /// Only layout actions can be disabled. Non-layout actions always read as
    /// enabled even if an unrelated value was written into UserDefaults.
    @Published private(set) var configurableHotkeyEnabled: [
        ConfigurableHotkeyAction: Bool
    ]

    /// Exposed internally so the permission lifecycle can be covered without
    /// changing the real macOS TCC database in tests.
    var isMonitoringAccessibilityPermission: Bool {
        permissionTimer != nil
    }

    init(
        accessibilityTrustCheck: @escaping (Bool) -> Bool = HotkeyService.systemAccessibilityTrustCheck,
        accessibilitySettingsOpener: @escaping () -> Void = HotkeyService.systemAccessibilitySettingsOpener,
        permissionPollInterval: TimeInterval = 3.0,
        permissionRecoveryPollLimit: Int = 4,
        defaults: UserDefaults = .standard,
        selectedTextTodoHotkeyRegistrar: HotkeyRegistrar? = nil,
        configurableHotkeyRegistrar: HotkeyRegistrar? = nil,
        requiresInstalledEventHandlerForSelectedTextTodo: Bool = true,
        requiresInstalledEventHandlerForConfigurableHotkeys: Bool = true
    ) {
        self.accessibilityTrustCheck = accessibilityTrustCheck
        self.accessibilitySettingsOpener = accessibilitySettingsOpener
        self.permissionPollInterval = permissionPollInterval
        self.permissionRecoveryPollLimit = max(1, permissionRecoveryPollLimit)
        self.defaults = defaults
        self.selectedTextTodoHotkeyRegistrar = selectedTextTodoHotkeyRegistrar
            ?? configurableHotkeyRegistrar
        self.configurableHotkeyRegistrar = configurableHotkeyRegistrar
            ?? selectedTextTodoHotkeyRegistrar
        self.requiresInstalledEventHandlerForSelectedTextTodo =
            requiresInstalledEventHandlerForSelectedTextTodo
        self.requiresInstalledEventHandlerForConfigurableHotkeys =
            requiresInstalledEventHandlerForConfigurableHotkeys
        let restored = HotkeyService.restoreConfigurableShortcuts(from: defaults)
        self.configurableShortcuts = restored
        self.selectedTextTodoShortcut = defaults.string(
            forKey: Self.selectedTextTodoShortcutDefaultsKey
        ).flatMap(SelectedTextTodoShortcut.init(rawValue:)) ?? .defaultValue
        self.configurableHotkeyEnabled = Dictionary(
            uniqueKeysWithValues: ConfigurableHotkeyAction.allCases.map { action in
                (action, HotkeyService.restoreEnabledState(for: action, from: defaults))
            }
        )
        self.configurableHotkeyStates = Dictionary(
            uniqueKeysWithValues: ConfigurableHotkeyAction.allCases.map {
                let state: ConfigurableHotkeyState = HotkeyService.restoreEnabledState(
                    for: $0,
                    from: defaults
                ) ? .notRegistered : .disabled(restored[$0] ?? $0.defaultShortcut)
                return ($0, state)
            }
        )
    }

    // MARK: - Stable Initial Registration IDs

    static let hotkeySignature = OSType(0x4E415243)
    private static let pinnedWindowSwitcherHotkeyID: UInt32 = 100
    private static let summonWidgetHotkeyID: UInt32 = 101
    private static let toggleCurrentWindowPinHotkeyID: UInt32 = 102
    private static let quickCaptureHotkeyID: UInt32 = 103
    private static let selectedTextTodoHotkeySlotA: UInt32 = 104
    private static let selectedTextTodoHotkeySlotB: UInt32 = 105
    private static let pinnedWindowSwitcherReplacementSlot: UInt32 = 106
    private static let toggleCurrentWindowPinReplacementSlot: UInt32 = 107
    private static let summonWidgetReplacementSlot: UInt32 = 118
    private static let quickCaptureReplacementSlot: UInt32 = 119
    static let selectedTextTodoShortcutDefaultsKey = "narc.selectedTextTodoShortcut"

    static let pinnedWindowSwitcherHotkey = BuiltInHotkeyDefinition(
        keyCode: ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultShortcut.keyCode,
        modifiers: ConfigurableHotkeyAction.pinnedWindowSwitcher.defaultShortcut.modifiers,
        id: pinnedWindowSwitcherHotkeyID,
        label: "Recall Pinned Windows ⌃⌥P"
    )
    static let toggleCurrentWindowPinHotkey = BuiltInHotkeyDefinition(
        keyCode: ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultShortcut.keyCode,
        modifiers: ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultShortcut.modifiers,
        id: toggleCurrentWindowPinHotkeyID,
        label: "Toggle Current Window Pin ⌃⌥⇧P"
    )

    // MARK: - Accessibility Permission

    /// Check Accessibility permission, optionally asking macOS to show its prompt.
    @discardableResult
    func checkAccessibilityPermission(prompt: Bool = true) -> Bool {
        let trusted = accessibilityTrustCheck(prompt)
        publishAccessibilityPermission(trusted)

        if !trusted {
            print("[NARC] ⚠️ Accessibility permission NOT granted.")
            print("[NARC] Please go to: System Settings → Privacy & Security → Accessibility")
            print("[NARC] and add the currently running app: \(Bundle.main.bundleURL.path)")
            print("[NARC] Authorization is usually detected automatically; reopen NARC only if it remains unavailable.")
        } else {
            print("[NARC] ✅ Accessibility permission granted.")
        }

        return trusted
    }

    /// Ask macOS for Accessibility access and keep observing until it changes.
    /// The native prompt already owns the route into System Settings, so this
    /// method deliberately does not open Settings at the same time.
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let trusted = checkAccessibilityPermission(prompt: true)
        if !trusted {
            permissionRecoveryPollCount = 0
            shouldReportPermissionRecovery = true
            didReportPermissionRecovery = false
            startPermissionPolling()
        }
        return trusted
    }

    /// Open the Accessibility pane only for an explicit "View settings" action.
    func openAccessibilitySettings() {
        accessibilitySettingsOpener()
    }

    // MARK: - Hotkey Registration

    /// Register all global hotkeys (layout hotkeys + Pin + Summon Widget).
    func registerGlobalHotkeys(promptForAccessibility: Bool = true) {
        guard eventHandler == nil else { return }

        let hasAccessibility = checkAccessibilityPermission(prompt: promptForAccessibility)
        if !hasAccessibility {
            // Carbon registration itself does not require Accessibility. Keep
            // every shortcut reachable so the first window action can explain
            // and request permission at the moment of intent.
            print("[NARC] Registering all hotkeys; window actions will request Accessibility when used.")
            startPermissionPolling()
        }

        guard installGlobalHotkeyEventHandler() else { return }
        registerConfiguredHotkeys(noAX: false)
    }

    /// Development no-AX mode: keep navigation hotkeys that do not require
    /// Accessibility, but skip pin/window-layout hotkeys that need AX windows.
    func registerDevNoAXHotkeys() {
        guard eventHandler == nil else { return }

        guard installGlobalHotkeyEventHandler() else { return }
        registerConfiguredHotkeys(noAX: true)
        print("[NARC] 🧪 Pin/layout hotkeys disabled in NARC_DEV_NO_AX because they require Accessibility.")
    }

    private func installGlobalHotkeyEventHandler() -> Bool {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            return service.handleCarbonHotkeyEvent(event)
        }

        let handlerStatus = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
        }
        guard handlerStatus == noErr else {
            eventHandler = nil
            globalHotkeyEventHandlerFailure = handlerStatus
            for action in ConfigurableHotkeyAction.allCases {
                configurableHotkeyStates[action] = isEnabled(for: action)
                    ? .unavailable(requested: shortcut(for: action), reason: .system(handlerStatus))
                    : .disabled(shortcut(for: action))
            }
            selectedTextTodoHotkeyState = .unavailable(
                requested: selectedTextTodoShortcut,
                reason: .system(handlerStatus)
            )
            print("[NARC] Failed to install the global hotkey event handler: \(handlerStatus)")
            return false
        }
        globalHotkeyEventHandlerFailure = nil
        return true
    }

    /// Shared registration policy; tests inject registrars and bypass only the
    /// actual Carbon event-handler installation to exercise no-AX safely.
    func registerConfiguredHotkeys(noAX: Bool) {
        registeredActionScope = Set(ConfigurableHotkeyAction.allCases.filter {
            !noAX || !$0.requiresAccessibility
        })
        for action in ConfigurableHotkeyAction.allCases {
            if !isEnabled(for: action) {
                configurableHotkeyStates[action] = .disabled(shortcut(for: action))
            } else if registeredActionScope?.contains(action) == true {
                _ = activateConfigurableShortcut(shortcut(for: action), for: action)
            } else {
                configurableHotkeyStates[action] = .unavailable(
                    requested: shortcut(for: action),
                    reason: .unavailableInCurrentRuntime
                )
            }
        }
    }

    /// Unregister all global hotkeys.
    func unregisterGlobalHotkeys() {
        for registration in configurableRegistrations.values {
            _ = registration.unregister()
        }
        configurableRegistrations.removeAll()
        configurableActiveSlotIDs.removeAll()
        configurableSlotOwners.removeAll()
        configurableHotkeysPressed.removeAll()
        for action in ConfigurableHotkeyAction.allCases {
            configurableRegistrationGenerations[action, default: 0] &+= 1
            configurableHotkeyStates[action] = isEnabled(for: action)
                ? .notRegistered
                : .disabled(shortcut(for: action))
        }

        for registration in failedRollbackRegistrations {
            _ = registration.unregister()
        }
        failedRollbackRegistrations.removeAll()
        quarantinedHotkeySlotIDs.removeAll()
        selectedTextTodoHotkeyState = .notRegistered

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        globalHotkeyEventHandlerFailure = nil
        registeredActionScope = nil

    }

    func shortcut(for action: ConfigurableHotkeyAction) -> ConfigurableShortcut {
        configurableShortcuts[action] ?? action.defaultShortcut
    }

    func hotkeyState(for action: ConfigurableHotkeyAction) -> ConfigurableHotkeyState {
        configurableHotkeyStates[action] ?? .notRegistered
    }

    /// The shortcut Carbon has actually accepted for this process. Runtime
    /// guidance must use this instead of the configured candidate so an
    /// unavailable cold-start registration is never advertised as usable.
    func activeShortcut(for action: ConfigurableHotkeyAction) -> ConfigurableShortcut? {
        guard configurableRegistrations[action] != nil else { return nil }
        switch hotkeyState(for: action) {
        case .active(let shortcut), .rejected(let shortcut, _, _):
            return shortcut
        case .notRegistered, .disabled, .unavailable:
            return nil
        }
    }

    func isEnabled(for action: ConfigurableHotkeyAction) -> Bool {
        action.supportsEnabledToggle
            ? (configurableHotkeyEnabled[action] ?? true)
            : true
    }

    /// Enable or disable one layout action. Disabling is transactional: the
    /// Carbon registration must be released before the disabled state is
    /// persisted. Non-layout actions are intentionally always enabled.
    @discardableResult
    func setEnabled(
        _ enabled: Bool,
        for action: ConfigurableHotkeyAction
    ) -> ConfigurableShortcutUpdateResult {
        guard action.supportsEnabledToggle else {
            return .rejected(.actionCannotBeDisabled)
        }

        let current = shortcut(for: action)
        let wasEnabled = isEnabled(for: action)
        if enabled == wasEnabled {
            configurableHotkeyStates[action] = enabled
                ? (configurableRegistrations[action] == nil ? .notRegistered : .active(current))
                : .disabled(current)
            return .unchanged
        }

        if !enabled {
            if let registration = configurableRegistrations[action] {
                let status = registration.unregister()
                guard status == noErr else {
                    let failure = HotkeyRegistrationFailure.couldNotUnregisterExisting(status)
                    configurableHotkeyStates[action] = .rejected(
                        active: current,
                        requested: current,
                        reason: failure
                    )
                    return .rejected(failure)
                }
                configurableRegistrations[action] = nil
                configurableActiveSlotIDs[action] = nil
            }
            configurableRegistrationGenerations[action, default: 0] &+= 1
            configurableHotkeysPressed.remove(action)
            configurableHotkeyEnabled[action] = false
            defaults.set(false, forKey: action.enabledDefaultsKey)
            configurableHotkeyStates[action] = .disabled(current)
            return .applied(current)
        }

        // Let the normal registration path validate conflicts, runtime scope,
        // and Carbon occupancy. Roll back the enabled flag if it cannot bind.
        configurableHotkeyEnabled[action] = true
        let result = activateConfigurableShortcut(current, for: action)
        switch result {
        case .applied, .unchanged:
            defaults.set(true, forKey: action.enabledDefaultsKey)
            return result
        case .rejected(let reason):
            configurableHotkeyEnabled[action] = false
            defaults.set(false, forKey: action.enabledDefaultsKey)
            configurableHotkeyStates[action] = .disabled(current)
            return .rejected(reason)
        }
    }

    /// Change one window shortcut without interrupting its current registration.
    /// Persistence follows a successful transactional replacement.
    @discardableResult
    func updateShortcut(
        _ requested: ConfigurableShortcut,
        for action: ConfigurableHotkeyAction
    ) -> ConfigurableShortcutUpdateResult {
        if action.supportsEnabledToggle, !isEnabled(for: action) {
            guard requested.isValid else {
                return rejectConfigurableShortcut(
                    requested,
                    for: action,
                    reason: .invalidShortcut
                )
            }
            if let conflict = internalConflict(for: requested, excluding: action) {
                return rejectConfigurableShortcut(
                    requested,
                    for: action,
                    reason: .conflictsWithNARC(conflict)
                )
            }
            configurableShortcuts[action] = requested
            persist(requested, for: action)
            configurableHotkeyStates[action] = .disabled(requested)
            return .applied(requested)
        }
        if configurableRegistrations[action] != nil, requested == shortcut(for: action) {
            configurableHotkeyStates[action] = .active(requested)
            return .unchanged
        }
        return activateConfigurableShortcut(requested, for: action)
    }

    /// Change the selected-text Todo shortcut without interrupting the current
    /// registration. Persistence follows registration, never precedes it.
    @discardableResult
    func updateSelectedTextTodoShortcut(
        _ requested: SelectedTextTodoShortcut
    ) -> SelectedTextTodoShortcutUpdateResult {
        if configurableRegistrations[.selectedTextTodo] != nil,
           requested.configurableShortcut == shortcut(for: .selectedTextTodo) {
            selectedTextTodoHotkeyState = .active(requested)
            return .unchanged
        }
        return activateSelectedTextTodoShortcut(requested)
    }

    /// Internal event seam used by the Carbon callback and deterministic tests.
    func handleCarbonHotkeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event,
              GetEventClass(event) == OSType(kEventClassKeyboard) else {
            return OSStatus(eventNotHandledErr)
        }
        let kind = GetEventKind(event)
        guard kind == UInt32(kEventHotKeyPressed)
                || kind == UInt32(kEventHotKeyReleased) else {
            return OSStatus(eventNotHandledErr)
        }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == Self.hotkeySignature,
              configurableSlotOwners[hotKeyID.id] != nil else {
            return OSStatus(eventNotHandledErr)
        }
        handleConfigurableHotkeyEvent(
            slotID: hotKeyID.id,
            isPressed: kind == UInt32(kEventHotKeyPressed)
        )
        return noErr
    }

    /// Internal event seam used by deterministic press/release tests.
    func handleConfigurableHotkeyEvent(slotID: UInt32, isPressed: Bool) {
        guard let action = configurableSlotOwners[slotID],
              configurableActiveSlotIDs[action] == slotID else {
            return
        }

        if !isPressed {
            configurableHotkeysPressed.remove(action)
            return
        }

        guard configurableHotkeysPressed.insert(action).inserted else { return }
        let generation = configurableRegistrationGenerations[action, default: 0]
        switch action {
        case .layoutLeftHalf, .layoutRightHalf, .layoutTopHalf, .layoutBottomHalf,
             .layoutFullScreen, .layoutCenter, .layoutTopLeft, .layoutTopRight,
             .layoutBottomLeft, .layoutBottomRight:
            if let layout = action.layout { onLayoutHotkeyPressed?(layout) }
        case .toggleCurrentWindowPin:
            onToggleCurrentWindowPinHotkeyPressed?()
        case .selectedTextTodo:
            onSelectedTextTodoHotkeyPressed?()
        case .pinnedWindowSwitcher:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.configurableActiveSlotIDs[action] == slotID,
                      self.configurableRegistrationGenerations[action] == generation else { return }
                self.onPinnedWindowSwitcherHotkeyPressed?()
            }
        case .summonWidget:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.configurableActiveSlotIDs[action] == slotID,
                      self.configurableRegistrationGenerations[action] == generation else { return }
                self.onSummonWidgetHotkeyPressed?()
            }
        case .quickCapture:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.configurableActiveSlotIDs[action] == slotID,
                      self.configurableRegistrationGenerations[action] == generation else { return }
                self.onQuickCaptureHotkeyPressed?()
            }
        }
    }

    /// Internal event seam used by the Carbon callback and deterministic tests.
    func handleSelectedTextTodoHotkeyEvent(slotID: UInt32, isPressed: Bool) {
        handleConfigurableHotkeyEvent(slotID: slotID, isPressed: isPressed)
    }

    // MARK: - Private

    private func activateConfigurableShortcut(
        _ requested: ConfigurableShortcut,
        for action: ConfigurableHotkeyAction
    ) -> ConfigurableShortcutUpdateResult {
        guard requested.isValid else {
            return rejectConfigurableShortcut(
                requested,
                for: action,
                reason: .invalidShortcut
            )
        }

        if let conflict = internalConflict(for: requested, excluding: action) {
            return rejectConfigurableShortcut(
                requested,
                for: action,
                reason: .conflictsWithNARC(conflict)
            )
        }

        if let registeredActionScope, !registeredActionScope.contains(action) {
            return rejectConfigurableShortcut(
                requested,
                for: action,
                reason: .unavailableInCurrentRuntime
            )
        }

        let requiresEventHandler = action == .selectedTextTodo
            ? requiresInstalledEventHandlerForSelectedTextTodo
            : requiresInstalledEventHandlerForConfigurableHotkeys
        if requiresEventHandler, eventHandler == nil {
            let failure = globalHotkeyEventHandlerFailure
                .map(HotkeyRegistrationFailure.system)
                ?? .eventHandlerUnavailable
            return rejectConfigurableShortcut(requested, for: action, reason: failure)
        }

        guard let replacementSlotID = nextConfigurableSlotID(for: action) else {
            return rejectConfigurableShortcut(
                requested,
                for: action,
                reason: .registrationStateUnavailable
            )
        }

        let injectedRegistrar = action == .selectedTextTodo
            ? selectedTextTodoHotkeyRegistrar
            : configurableHotkeyRegistrar
        let registration = injectedRegistrar?(
            requested.keyCode, requested.modifiers, replacementSlotID
        ) ?? Self.registerSystemHotkey(
            keyCode: requested.keyCode,
            modifiers: requested.modifiers,
            slotID: replacementSlotID,
            options: Self.registrationOptions(for: action)
        )
        switch registration {
        case .failure(let failure):
            return rejectConfigurableShortcut(requested, for: action, reason: failure)

        case .success(let replacement):
            if let previousRegistration = configurableRegistrations[action] {
                let unregisterExistingStatus = previousRegistration.unregister()
                guard unregisterExistingStatus == noErr else {
                    let rollbackStatus = replacement.unregister()
                    let failure: HotkeyRegistrationFailure
                    if rollbackStatus == noErr {
                        failure = .couldNotUnregisterExisting(unregisterExistingStatus)
                    } else {
                        failedRollbackRegistrations.append(replacement)
                        quarantinedHotkeySlotIDs.insert(replacement.slotID)
                        failure = .couldNotRollbackCandidate(
                            existing: unregisterExistingStatus,
                            candidate: rollbackStatus
                        )
                    }
                    return rejectConfigurableShortcut(
                        requested,
                        for: action,
                        reason: failure
                    )
                }
            }

            configurableRegistrations[action] = replacement
            configurableActiveSlotIDs[action] = replacement.slotID
            configurableRegistrationGenerations[action, default: 0] &+= 1
            configurableHotkeysPressed.remove(action)
            configurableShortcuts[action] = requested
            persist(requested, for: action)
            configurableHotkeyStates[action] = .active(requested)
            print("[NARC] ✅ Registered \(action.title) hotkey: \(requested.displayLabel)")
            return .applied(requested)
        }
    }

    private func rejectConfigurableShortcut(
        _ requested: ConfigurableShortcut,
        for action: ConfigurableHotkeyAction,
        reason: HotkeyRegistrationFailure
    ) -> ConfigurableShortcutUpdateResult {
        if configurableRegistrations[action] != nil {
            configurableHotkeyStates[action] = .rejected(
                active: shortcut(for: action),
                requested: requested,
                reason: reason
            )
        } else if action.supportsEnabledToggle, !isEnabled(for: action) {
            configurableHotkeyStates[action] = .disabled(shortcut(for: action))
        } else {
            configurableHotkeyStates[action] = .unavailable(
                requested: requested,
                reason: reason
            )
        }
        print("[NARC] Failed to register \(action.title) hotkey \(requested.displayLabel): \(reason)")
        return .rejected(reason)
    }

    private func internalConflict(
        for requested: ConfigurableShortcut,
        excluding action: ConfigurableHotkeyAction
    ) -> String? {
        return ConfigurableHotkeyAction.allCases.first(where: {
            $0 != action && isEnabled(for: $0) && shortcut(for: $0) == requested
        })?.title
    }

    private func legacySelectedTextState(
        requested: SelectedTextTodoShortcut,
        reason: HotkeyRegistrationFailure
    ) -> SelectedTextTodoHotkeyState {
        switch hotkeyState(for: .selectedTextTodo) {
        case .rejected(let active, _, _):
            return .rejected(
                active: SelectedTextTodoShortcut(configurableShortcut: active) ?? selectedTextTodoShortcut,
                requested: requested,
                reason: reason
            )
        case .unavailable:
            return .unavailable(requested: requested, reason: reason)
        case .disabled, .notRegistered, .active:
            return .unavailable(requested: requested, reason: reason)
        }
    }

    private func persist(
        _ shortcut: ConfigurableShortcut,
        for action: ConfigurableHotkeyAction
    ) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: action.defaultsKey)
    }

    private func nextConfigurableSlotID(for action: ConfigurableHotkeyAction) -> UInt32? {
        // A leaked candidate registration requires an app restart before this
        // action can change again, but must not prevent unrelated actions.
        guard !quarantinedHotkeySlotIDs.contains(where: {
            configurableSlotOwners[$0] == action
        }) else { return nil }

        let slotID: UInt32
        if let initial = Self.configurableSlotIDs(for: action).first(where: {
            !usedHotkeySlotIDs.contains($0)
        }) {
            slotID = initial
        } else {
            guard nextDynamicHotkeySlotID < UInt32.max else { return nil }
            slotID = nextDynamicHotkeySlotID
            nextDynamicHotkeySlotID += 1
        }
        // Never recycle an ID, including failed attempts and disabled actions:
        // queued Carbon events carry an ID but no registration generation.
        usedHotkeySlotIDs.insert(slotID)
        configurableSlotOwners[slotID] = action
        return slotID
    }

    private func activateSelectedTextTodoShortcut(
        _ requested: SelectedTextTodoShortcut
    ) -> SelectedTextTodoShortcutUpdateResult {
        let result = activateConfigurableShortcut(
            requested.configurableShortcut,
            for: .selectedTextTodo
        )
        switch result {
        case .unchanged:
            selectedTextTodoHotkeyState = .active(requested)
            return .unchanged
        case .applied:
            selectedTextTodoShortcut = requested
            defaults.set(requested.rawValue, forKey: Self.selectedTextTodoShortcutDefaultsKey)
            selectedTextTodoHotkeyState = .active(requested)
            return .applied(requested)
        case .rejected(let reason):
            selectedTextTodoHotkeyState = legacySelectedTextState(
                requested: requested,
                reason: reason
            )
            return .rejected(reason)
        }

    }

    private static func configurableSlotIDs(
        for action: ConfigurableHotkeyAction
    ) -> [UInt32] {
        switch action {
        case .layoutLeftHalf: return [0, 108]
        case .layoutRightHalf: return [1, 109]
        case .layoutTopHalf: return [2, 110]
        case .layoutBottomHalf: return [3, 111]
        case .layoutFullScreen: return [4, 112]
        case .layoutCenter: return [5, 113]
        case .layoutTopLeft: return [6, 114]
        case .layoutTopRight: return [7, 115]
        case .layoutBottomLeft: return [8, 116]
        case .layoutBottomRight: return [9, 117]
        case .pinnedWindowSwitcher:
            return [pinnedWindowSwitcherHotkeyID, pinnedWindowSwitcherReplacementSlot]
        case .toggleCurrentWindowPin:
            return [toggleCurrentWindowPinHotkeyID, toggleCurrentWindowPinReplacementSlot]
        case .summonWidget:
            return [summonWidgetHotkeyID, summonWidgetReplacementSlot]
        case .quickCapture:
            return [quickCaptureHotkeyID, quickCaptureReplacementSlot]
        case .selectedTextTodo:
            return [selectedTextTodoHotkeySlotA, selectedTextTodoHotkeySlotB]
        }
    }

    private static func restoreEnabledState(
        for action: ConfigurableHotkeyAction,
        from defaults: UserDefaults
    ) -> Bool {
        guard action.supportsEnabledToggle else { return true }
        return (defaults.object(forKey: action.enabledDefaultsKey) as? Bool) ?? true
    }

    private static func restoreConfigurableShortcuts(
        from defaults: UserDefaults
    ) -> [ConfigurableHotkeyAction: ConfigurableShortcut] {
        let legacySelectedTextShortcut = defaults.string(
            forKey: selectedTextTodoShortcutDefaultsKey
        ).flatMap(SelectedTextTodoShortcut.init(rawValue:)) ?? .defaultValue
        let persistedSelectedTextShortcut = defaults.data(
            forKey: ConfigurableHotkeyAction.selectedTextTodo.defaultsKey
        ).flatMap {
            try? JSONDecoder().decode(ConfigurableShortcut.self, from: $0)
        }.flatMap { $0.isValid ? $0 : nil }
        let selectedTextShortcut = persistedSelectedTextShortcut
            ?? legacySelectedTextShortcut.configurableShortcut

        var restored: [ConfigurableHotkeyAction: ConfigurableShortcut] = [:]
        for action in ConfigurableHotkeyAction.allCases {
            let decoded = defaults.data(forKey: action.defaultsKey).flatMap {
                try? JSONDecoder().decode(ConfigurableShortcut.self, from: $0)
            }
            let candidate: ConfigurableShortcut
            if let decoded, decoded.isValid {
                candidate = decoded
            } else if action == .selectedTextTodo {
                candidate = selectedTextShortcut
            } else {
                candidate = action.defaultShortcut
            }
            // Disabled layouts may legitimately share a chord with an active
            // action. Restore each saved value verbatim; registration and
            // re-enabling report conflicts without silently rewriting it.
            restored[action] = candidate
        }

        return restored
    }

    /// Keep the original Carbon policy: only the two Pin actions are exclusive.
    /// Applying exclusive registration to established layout/navigation keys
    /// can unexpectedly reject combinations that previously worked.
    static func registrationOptions(for action: ConfigurableHotkeyAction) -> OptionBits {
        switch action {
        case .pinnedWindowSwitcher, .toggleCurrentWindowPin:
            return OptionBits(kEventHotKeyExclusive)
        default:
            return 0
        }
    }

    private static func registerSystemHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        slotID: UInt32,
        options: OptionBits
    ) -> Result<HotkeyRegistrationToken, HotkeyRegistrationFailure> {
        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: slotID)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            options,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            if status == eventHotKeyExistsErr {
                return .failure(.occupied)
            }
            return .failure(.system(status == noErr ? OSStatus(paramErr) : status))
        }

        return .success(
            HotkeyRegistrationToken(slotID: slotID) {
                UnregisterEventHotKey(hotKeyRef)
            }
        )
    }

    /// Perform one live permission refresh. Internal for deterministic tests.
    @discardableResult
    func pollAccessibilityPermissionOnce() -> Bool {
        let trusted = accessibilityTrustCheck(false)
        publishAccessibilityPermission(trusted, countTowardsRecovery: true)
        return trusted
    }

    /// Periodically check if Accessibility permission has been granted.
    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }

        let timer = Timer(timeInterval: permissionPollInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            _ = self.pollAccessibilityPermissionOnce()
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func publishAccessibilityPermission(
        _ trusted: Bool,
        countTowardsRecovery: Bool = false
    ) {
        let update = { [weak self] in
            guard let self else { return }

            let becameGranted = trusted && !self.isAccessibilityGranted
            self.isAccessibilityGranted = trusted

            if trusted {
                self.resetPermissionRecoveryReporting()
                self.stopPermissionPolling()
                if becameGranted {
                    print("[NARC] ✅ Accessibility permission now granted; no restart required.")
                    self.onAccessibilityPermissionGranted?()
                }
            } else if countTowardsRecovery
                && self.shouldReportPermissionRecovery
                && !self.didReportPermissionRecovery {
                self.permissionRecoveryPollCount += 1
                if self.permissionRecoveryPollCount >= self.permissionRecoveryPollLimit {
                    self.didReportPermissionRecovery = true
                    self.onAccessibilityPermissionStillDenied?()
                }
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func resetPermissionRecoveryReporting() {
        permissionRecoveryPollCount = 0
        shouldReportPermissionRecovery = false
        didReportPermissionRecovery = false
    }

    private static func systemAccessibilityTrustCheck(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func systemAccessibilitySettingsOpener() {
        guard let accessibilityURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }

        if NSWorkspace.shared.open(accessibilityURL) {
            return
        }

        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [accessibilityURL.absoluteString]
        try? task.run()
    }

    deinit {
        stopPermissionPolling()
        unregisterGlobalHotkeys()
    }
}
