import Cocoa
import Carbon

/// Manages global hotkey registration via Carbon Event API and Accessibility permission.
///
/// Extracted from WindowManagerService to separate hotkey infrastructure from
/// window movement logic. This class handles:
/// - Accessibility permission checking and polling
/// - Carbon Event hotkey registration/unregistration
/// - Dispatching hotkey events to the appropriate handlers
class HotkeyService: ObservableObject {

    // MARK: - Properties

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var permissionTimer: Timer?

    /// Callback invoked when the Pin hotkey (⌃⌥P) is pressed.
    var onPinHotkeyPressed: (() -> Void)?

    /// Callback invoked when the Toggle Panel hotkey (⌃⌥N) is pressed.
    var onTogglePanelHotkeyPressed: (() -> Void)?

    /// Callback invoked when the Quick Capture hotkey (⌃⌥Q) is pressed.
    var onQuickCaptureHotkeyPressed: (() -> Void)?

    /// Callback invoked when a window layout hotkey is pressed.
    var onLayoutHotkeyPressed: ((WindowLayout) -> Void)?

    /// Whether Accessibility permission has been granted.
    @Published var isAccessibilityGranted: Bool = false

    // MARK: - Static Handlers (for C callback)

    private static var pinHandler: (() -> Void)?
    private static var togglePanelHandler: (() -> Void)?
    private static var quickCaptureHandler: (() -> Void)?
    private static var layoutHandler: ((WindowLayout) -> Void)?

    private static let pinHotkeyID: UInt32 = 100
    private static let togglePanelHotkeyID: UInt32 = 101
    private static let quickCaptureHotkeyID: UInt32 = 103

    // MARK: - Accessibility Permission

    /// Check Accessibility permission, optionally asking macOS to show its prompt.
    @discardableResult
    func checkAccessibilityPermission(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        DispatchQueue.main.async { [weak self] in
            self?.isAccessibilityGranted = trusted
        }

        if !trusted {
            print("[NARC] ⚠️ Accessibility permission NOT granted.")
            print("[NARC] Please go to: System Settings → Privacy & Security → Accessibility")
            print("[NARC] and add the terminal app (or NARC.app) you are running from.")
            print("[NARC] NARC will enable window hotkeys automatically after authorization.")

            guard prompt else { return false }

            let opened = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            if !opened {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
                try? task.run()
            }
            if !opened {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
            }
        } else {
            print("[NARC] ✅ Accessibility permission granted.")
        }

        return trusted
    }

    // MARK: - Hotkey Registration

    /// Register all global hotkeys (layout hotkeys + Pin + Toggle Panel).
    func registerGlobalHotkeys(promptForAccessibility: Bool = true) {
        guard checkAccessibilityPermission(prompt: promptForAccessibility) else {
            print("[NARC] Registering panel/quick-capture hotkeys without Accessibility.")
            registerDevNoAXHotkeys()
            startPermissionPolling()
            return
        }

        let controlOption: UInt32 = UInt32(controlKey | optionKey)

        let hotkeyMappings: [(keyCode: UInt32, modifiers: UInt32, layout: WindowLayout)] = [
            (123, controlOption, .leftHalf),     // ⌃⌥←
            (124, controlOption, .rightHalf),     // ⌃⌥→
            (126, controlOption, .topHalf),       // ⌃⌥↑
            (125, controlOption, .bottomHalf),    // ⌃⌥↓
            (36,  controlOption, .fullScreen),    // ⌃⌥↩
            (8,   controlOption, .center),        // ⌃⌥C
            (32,  controlOption, .topLeft),       // ⌃⌥U
            (34,  controlOption, .topRight),      // ⌃⌥I
            (38,  controlOption, .bottomLeft),    // ⌃⌥J
            (40,  controlOption, .bottomRight),   // ⌃⌥K
        ]

        // Store handlers in static vars so the C callback can access them
        HotkeyService.pinHandler = { [weak self] in self?.onPinHotkeyPressed?() }
        HotkeyService.togglePanelHandler = { [weak self] in self?.onTogglePanelHotkeyPressed?() }
        HotkeyService.quickCaptureHandler = { [weak self] in self?.onQuickCaptureHotkeyPressed?() }
        // Layout handler does NOT use [weak self] — it must always work, even from C callbacks.
        // The onLayoutHotkeyPressed closure is set once at startup and never changes.
        let layoutCallback = self.onLayoutHotkeyPressed
        HotkeyService.layoutHandler = { layout in layoutCallback?(layout) }

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            let id = hotKeyID.id

            if id == HotkeyService.pinHotkeyID {
                DispatchQueue.main.async { HotkeyService.pinHandler?() }
                return noErr
            }

            if id == HotkeyService.togglePanelHotkeyID {
                DispatchQueue.main.async { HotkeyService.togglePanelHandler?() }
                return noErr
            }

            if id == HotkeyService.quickCaptureHotkeyID {
                DispatchQueue.main.async { HotkeyService.quickCaptureHandler?() }
                return noErr
            }

            let layoutIndex = Int(id)
            let allLayouts = WindowLayout.allCases
            if layoutIndex < allLayouts.count {
                let layout = allLayouts[layoutIndex]
                // Layout hotkeys MUST be called synchronously — not via DispatchQueue.main.async.
                // moveActiveWindow reads NSWorkspace.shared.frontmostApplication to determine
                // which window to move. If we dispatch async, the frontmost app may have changed
                // by the time the callback executes (e.g., NARC itself may have taken focus).
                HotkeyService.layoutHandler?(layout)
            }

            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        // Register layout hotkeys
        for (index, mapping) in hotkeyMappings.enumerated() {
            registerHotkey(keyCode: mapping.keyCode, modifiers: mapping.modifiers, id: UInt32(index),
                           label: mapping.layout.rawValue)
        }

        // Register Pin hotkey: ⌃⌥P
        registerHotkey(keyCode: 35, modifiers: controlOption, id: HotkeyService.pinHotkeyID, label: "Pin ⌃⌥P")

        // Register Toggle Panel hotkey: ⌃⌥N
        registerHotkey(keyCode: 45, modifiers: controlOption, id: HotkeyService.togglePanelHotkeyID, label: "Toggle Panel ⌃⌥N")

        // Register Quick Capture: ⌃⌥Q (Q = keyCode 12).
        registerHotkey(keyCode: 12, modifiers: controlOption, id: HotkeyService.quickCaptureHotkeyID, label: "Quick Capture ⌃⌥Q")
    }

    /// Development no-AX mode: keep navigation hotkeys that do not require
    /// Accessibility, but skip pin/window-layout hotkeys that need AX windows.
    func registerDevNoAXHotkeys() {
        let controlOption: UInt32 = UInt32(controlKey | optionKey)

        HotkeyService.togglePanelHandler = { [weak self] in self?.onTogglePanelHotkeyPressed?() }
        HotkeyService.quickCaptureHandler = { [weak self] in self?.onQuickCaptureHotkeyPressed?() }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if hotKeyID.id == HotkeyService.togglePanelHotkeyID {
                DispatchQueue.main.async { HotkeyService.togglePanelHandler?() }
                return noErr
            }
            if hotKeyID.id == HotkeyService.quickCaptureHotkeyID {
                DispatchQueue.main.async { HotkeyService.quickCaptureHandler?() }
                return noErr
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)
        registerHotkey(keyCode: 45, modifiers: controlOption, id: HotkeyService.togglePanelHotkeyID, label: "Toggle Panel ⌃⌥N")
        registerHotkey(keyCode: 12, modifiers: controlOption, id: HotkeyService.quickCaptureHotkeyID, label: "Quick Capture ⌃⌥Q")
        print("[NARC] 🧪 Pin/layout hotkeys disabled in NARC_DEV_NO_AX because they require Accessibility.")
    }

    /// Unregister all global hotkeys.
    func unregisterGlobalHotkeys() {
        for ref in hotKeyRefs {
            if let ref = ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Private

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, id: UInt32, label: String) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E415243), id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
            if id >= 100 { // Only log special hotkeys, not layout ones
                print("[NARC] ✅ Registered hotkey: \(label)")
            }
        } else {
            print("[NARC] Failed to register hotkey \(label): \(status)")
            hotKeyRefs.append(nil)
        }
    }

    /// Periodically check if Accessibility permission has been granted.
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: false] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)

            if trusted {
                print("[NARC] ✅ Accessibility permission now granted! Registering hotkeys...")
                timer.invalidate()
                self.permissionTimer = nil
                DispatchQueue.main.async {
                    self.isAccessibilityGranted = true
                    self.unregisterGlobalHotkeys()
                    self.registerGlobalHotkeys(promptForAccessibility: false)
                }
            }
        }
    }

    deinit {
        permissionTimer?.invalidate()
        unregisterGlobalHotkeys()
    }
}
