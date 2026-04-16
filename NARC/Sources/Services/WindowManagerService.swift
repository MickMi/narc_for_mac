import Cocoa
import Carbon

/// Service that manages window positioning via Accessibility API and global hotkeys.
class WindowManagerService: ObservableObject {

    // MARK: - Properties

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    // MARK: - Global Hotkeys

    /// Whether Accessibility permission has been granted.
    @Published var isAccessibilityGranted: Bool = false

    /// Check and request Accessibility permission.
    /// Returns true if already granted, false if user needs to grant it.
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        // Use takeUnretainedValue to avoid over-releasing
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        DispatchQueue.main.async { [weak self] in
            self?.isAccessibilityGranted = trusted
        }

        if !trusted {
            print("[NARC] ⚠️ Accessibility permission NOT granted.")
            print("[NARC] Please go to: System Settings → Privacy & Security → Accessibility")
            print("[NARC] and add the terminal app (or NARC.app) you are running from.")
            print("[NARC] Then restart NARC.")

            // Try to open System Settings → Accessibility directly
            // macOS 13+ (Ventura/Sonoma/Sequoia) uses different URL schemes
            let opened = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)

            if !opened {
                // Fallback: open via shell command which works on all macOS versions
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
                try? task.run()
            }

            // Second fallback: try to open the Privacy & Security pane directly
            if !opened {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
            }
        } else {
            print("[NARC] ✅ Accessibility permission granted.")
        }

        return trusted
    }

    /// Register global hotkeys for all window layouts.
    func registerGlobalHotkeys() {
        // Request Accessibility permission if needed
        guard checkAccessibilityPermission() else {
            print("[NARC] Skipping hotkey registration — no Accessibility permission.")
            // Start a background timer to re-check permission periodically
            startPermissionPolling()
            return
        }

        // Define hotkey mappings: (keyCode, modifiers) -> WindowLayout
        // Modifiers: controlKey = 0x1000, optionKey = 0x0800
        let controlOption: UInt32 = UInt32(controlKey | optionKey)

        let hotkeyMappings: [(keyCode: UInt32, modifiers: UInt32, layout: WindowLayout)] = [
            (123, controlOption, .leftHalf),     // ⌃⌥← Left arrow
            (124, controlOption, .rightHalf),     // ⌃⌥→ Right arrow
            (126, controlOption, .topHalf),       // ⌃⌥↑ Up arrow
            (125, controlOption, .bottomHalf),    // ⌃⌥↓ Down arrow
            (36,  controlOption, .fullScreen),    // ⌃⌥↩ Return
            (8,   controlOption, .center),        // ⌃⌥C
            (32,  controlOption, .topLeft),       // ⌃⌥U
            (34,  controlOption, .topRight),      // ⌃⌥I
            (38,  controlOption, .bottomLeft),    // ⌃⌥J
            (40,  controlOption, .bottomRight),   // ⌃⌥K
        ]

        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            let layoutIndex = Int(hotKeyID.id)
            let allLayouts = WindowLayout.allCases
            if layoutIndex < allLayouts.count {
                let layout = allLayouts[layoutIndex]
                WindowManagerService.moveActiveWindow(to: layout)
            }

            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        // Register each hotkey
        for (index, mapping) in hotkeyMappings.enumerated() {
            let hotKeyID = EventHotKeyID(signature: OSType(0x4E415243), id: UInt32(index)) // "NARC"
            var hotKeyRef: EventHotKeyRef?

            let status = RegisterEventHotKey(
                mapping.keyCode,
                mapping.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr {
                hotKeyRefs.append(hotKeyRef)
            } else {
                print("[NARC] Failed to register hotkey for \(mapping.layout.rawValue): \(status)")
                hotKeyRefs.append(nil)
            }
        }
    }

    /// Unregister all global hotkeys.
    func unregisterGlobalHotkeys() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    // MARK: - Window Movement

    /// Move the currently active (frontmost) window to the specified layout position.
    /// Supports multi-monitor with cross-screen switching:
    /// If the window is already at the target layout on the current screen,
    /// pressing the same direction again moves it to the adjacent screen.
    static func moveActiveWindow(to layout: WindowLayout) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get the focused window
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)

        guard result == .success, let window = windowRef else {
            print("[NARC] Could not get focused window for \(frontApp.localizedName ?? "unknown")")
            return
        }

        let windowElement = window as! AXUIElement

        // Determine which screen the window is currently on
        let currentScreen = screenForWindow(windowElement) ?? NSScreen.main ?? NSScreen.screens.first!

        // Check if the window is already at the target layout on the current screen.
        // If so, move to the adjacent screen instead.
        var targetScreen = currentScreen
        var targetLayout = layout

        if isWindowAtScreenEdge(windowElement, forLayout: layout, onScreen: currentScreen) && NSScreen.screens.count > 1 {
            if let nextScreen = adjacentScreen(from: currentScreen, direction: layout) {
                targetScreen = nextScreen
                // When crossing screens, use the "entry" layout for that direction
                targetLayout = crossScreenEntryLayout(for: layout)
                print("[NARC] ↔️ Cross-screen: \(currentScreen.localizedName) → \(nextScreen.localizedName), entry layout=\(targetLayout.rawValue)")
            }
        }

        let visibleFrame = targetScreen.visibleFrame
        let fractional = targetLayout.fractionalFrame

        print("[NARC] 🖥 moveActiveWindow: layout=\(targetLayout.rawValue), screen=\(targetScreen.localizedName), visibleFrame=\(visibleFrame)")

        // Calculate target size
        let newWidth = visibleFrame.width * fractional.width
        let newHeight = visibleFrame.height * fractional.height

        // Calculate target position in NSScreen coordinates (origin at bottom-left)
        let nsX = visibleFrame.origin.x + visibleFrame.width * fractional.origin.x
        let nsY = visibleFrame.origin.y + visibleFrame.height * fractional.origin.y

        // Convert to AX coordinates (origin at top-left of the primary screen)
        // AX Y = primaryScreenHeight - (nsY + height)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? targetScreen.frame.height
        let axX = nsX
        let axY = primaryScreenHeight - (nsY + newHeight)

        // Set position first, then size
        var position = CGPoint(x: axX, y: axY)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)

        var size = CGSize(width: newWidth, height: newHeight)
        let sizeValue = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
    }

    // MARK: - Cross-Screen Switching Helpers

    /// Check if the window is already at the edge of the current screen in the direction
    /// implied by the layout. This determines whether the next press should cross screens.
    ///
    /// The logic is edge-based: if the layout pushes the window toward a screen edge
    /// (e.g., rightHalf → right edge, bottomHalf → bottom edge), and the window is
    /// already touching that edge, then we should cross to the next screen.
    private static func isWindowAtScreenEdge(_ windowElement: AXUIElement, forLayout layout: WindowLayout, onScreen screen: NSScreen) -> Bool {
        // Read current window position and size in AX coordinates
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success,
              let posValue = posRef else { return false }
        var axOrigin = CGPoint.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &axOrigin)

        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef else { return false }
        var currentSize = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &currentSize)

        // Convert screen visibleFrame to AX coordinates
        let visibleFrame = screen.visibleFrame
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenAxLeft = visibleFrame.origin.x
        let screenAxRight = visibleFrame.origin.x + visibleFrame.width
        let screenAxTop = primaryScreenHeight - (visibleFrame.origin.y + visibleFrame.height)
        let screenAxBottom = primaryScreenHeight - visibleFrame.origin.y

        let windowRight = axOrigin.x + currentSize.width
        let windowBottom = axOrigin.y + currentSize.height

        let tolerance: CGFloat = 15.0

        // Determine which edges the layout "pushes toward"
        let edges = layoutTargetEdges(for: layout)

        for edge in edges {
            switch edge {
            case .right:
                if abs(windowRight - screenAxRight) > tolerance { return false }
            case .left:
                if abs(axOrigin.x - screenAxLeft) > tolerance { return false }
            case .top:
                if abs(axOrigin.y - screenAxTop) > tolerance { return false }
            case .bottom:
                if abs(windowBottom - screenAxBottom) > tolerance { return false }
            }
        }

        return true
    }

    /// The screen edges that a layout pushes the window toward.
    private enum ScreenEdge { case left, right, top, bottom }

    private static func layoutTargetEdges(for layout: WindowLayout) -> [ScreenEdge] {
        switch layout {
        case .leftHalf:    return [.left]
        case .rightHalf:   return [.right]
        case .topHalf:     return [.top]
        case .bottomHalf:  return [.bottom]
        case .topLeft:     return [.top, .left]
        case .topRight:    return [.top, .right]
        case .bottomLeft:  return [.bottom, .left]
        case .bottomRight: return [.bottom, .right]
        case .fullScreen:  return []  // no cross-screen
        case .center:      return []  // no cross-screen
        }
    }

    /// Find the next screen to cross to, given the current screen and the layout direction.
    ///
    /// Strategy for diagonal screen arrangements (e.g., top-left / bottom-right):
    /// - rightHalf or bottomHalf from the top-left screen → should reach the bottom-right screen
    /// - leftHalf or topHalf from the bottom-right screen → should reach the top-left screen
    ///
    /// We check if any other screen is "in the direction" of the layout by looking at
    /// the relative position of screen centers. For 2-screen setups, we always allow
    /// crossing as long as the direction makes geometric sense.
    private static func adjacentScreen(from current: NSScreen, direction layout: WindowLayout) -> NSScreen? {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return nil }

        // No cross-screen for fullScreen / center
        let edges = layoutTargetEdges(for: layout)
        guard !edges.isEmpty else { return nil }

        let currentCenter = CGPoint(x: current.frame.midX, y: current.frame.midY)

        // For each candidate screen, check if it is in the correct direction
        // relative to the current screen for ANY of the layout's target edges.
        // e.g., rightHalf → candidate must be to the right OR below (for diagonal)
        var bestScreen: NSScreen? = nil
        var bestDistance: CGFloat = CGFloat.greatestFiniteMagnitude

        for screen in screens {
            guard screen != current else { continue }

            let candidateCenter = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let dx = candidateCenter.x - currentCenter.x
            // NSScreen Y: positive = up
            let dy = candidateCenter.y - currentCenter.y

            // Check if the candidate is in a valid direction for any of the target edges
            var isValid = false
            for edge in edges {
                switch edge {
                case .right:  if dx > 0 { isValid = true }
                case .left:   if dx < 0 { isValid = true }
                case .top:    if dy > 0 { isValid = true }
                case .bottom: if dy < 0 { isValid = true }
                }
            }

            // For 2-screen setups, be more relaxed:
            // If the direction has both horizontal and vertical components
            // (e.g., topRight), we already check both. But for single-axis
            // directions (e.g., rightHalf), also accept diagonal neighbors.
            if !isValid && screens.count == 2 {
                // Accept if the candidate is at least partially in the right direction
                // For rightHalf: accept if candidate is to the right OR diagonally right
                // This handles the case where screens are arranged diagonally
                for edge in edges {
                    switch edge {
                    case .right:  if dx > -current.frame.width * 0.5 { isValid = true }
                    case .left:   if dx < current.frame.width * 0.5 { isValid = true }
                    case .top:    if dy > -current.frame.height * 0.5 { isValid = true }
                    case .bottom: if dy < current.frame.height * 0.5 { isValid = true }
                    }
                }
            }

            if isValid {
                let distance = sqrt(dx * dx + dy * dy)
                if distance < bestDistance {
                    bestDistance = distance
                    bestScreen = screen
                }
            }
        }

        return bestScreen
    }

    /// When crossing to a new screen, determine the "entry" layout.
    /// The entry layout keeps the same direction — the window enters the new screen
    /// from the opposite side.
    /// e.g., moving right → enter the new screen on the left half.
    /// e.g., moving down  → enter the new screen on the top half.
    private static func crossScreenEntryLayout(for layout: WindowLayout) -> WindowLayout {
        switch layout {
        case .rightHalf:   return .leftHalf
        case .leftHalf:    return .rightHalf
        case .topHalf:     return .bottomHalf
        case .bottomHalf:  return .topHalf
        case .topRight:    return .topLeft
        case .topLeft:     return .topRight
        case .bottomRight: return .bottomLeft
        case .bottomLeft:  return .bottomRight
        default:           return layout
        }
    }

    /// Determine which screen a window is on based on its current AX position and size.
    /// AX coordinate system: origin at top-left of PRIMARY screen, Y increases downward.
    /// NSScreen coordinate system: origin at bottom-left of PRIMARY screen, Y increases upward.
    private static func screenForWindow(_ windowElement: AXUIElement) -> NSScreen? {
        // Read window position (AX coordinates)
        var posRef: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef)
        guard posResult == .success, let posValue = posRef else { return nil }

        var axOrigin = CGPoint.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &axOrigin)

        // Read window size to calculate center point
        var sizeRef: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)

        var windowSize = CGSize(width: 100, height: 100) // fallback
        if sizeResult == .success, let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &windowSize)
        }

        // AX center point
        let axCenter = CGPoint(x: axOrigin.x + windowSize.width / 2,
                               y: axOrigin.y + windowSize.height / 2)

        // Log all screens and their frames for debugging
        let primaryScreen = NSScreen.screens.first
        let primaryHeight = primaryScreen?.frame.height ?? 0
        print("[NARC] 🔍 screenForWindow: axOrigin=\(axOrigin), size=\(windowSize), axCenter=\(axCenter)")
        print("[NARC] 🔍 primaryScreenHeight=\(primaryHeight)")
        for (i, s) in NSScreen.screens.enumerated() {
            print("[NARC] 🔍 Screen[\(i)] \(s.localizedName): frame=\(s.frame), visibleFrame=\(s.visibleFrame)")
        }

        // Strategy: Convert each screen's frame to AX coordinates and check containment.
        // This avoids error-prone NS<->AX coordinate conversion.
        // For a screen with NSScreen frame (sx, sy, sw, sh):
        //   AX top-left X = sx
        //   AX top-left Y = primaryHeight - (sy + sh)
        //   AX frame = (sx, primaryHeight - sy - sh, sw, sh)
        for screen in NSScreen.screens {
            let sf = screen.frame
            let axScreenRect = NSRect(
                x: sf.origin.x,
                y: primaryHeight - sf.origin.y - sf.height,
                width: sf.width,
                height: sf.height
            )
            print("[NARC] 🔍 \(screen.localizedName) in AX coords: \(axScreenRect), contains center: \(axScreenRect.contains(axCenter))")
            if axScreenRect.contains(axCenter) {
                print("[NARC] 🔍 → Matched screen: \(screen.localizedName)")
                return screen
            }
        }

        // Fallback: find the screen with the most overlap in AX coordinates
        let axWindowRect = NSRect(origin: axOrigin, size: windowSize)
        let bestScreen = NSScreen.screens.max(by: { screenA, screenB in
            let sfA = screenA.frame
            let axRectA = NSRect(x: sfA.origin.x, y: primaryHeight - sfA.origin.y - sfA.height, width: sfA.width, height: sfA.height)
            let sfB = screenB.frame
            let axRectB = NSRect(x: sfB.origin.x, y: primaryHeight - sfB.origin.y - sfB.height, width: sfB.width, height: sfB.height)
            return axRectA.intersection(axWindowRect).area < axRectB.intersection(axWindowRect).area
        })
        print("[NARC] 🔍 → Fallback matched screen: \(bestScreen?.localizedName ?? "none")")
        return bestScreen
    }

    /// Move a specific app's window to a target screen with a specific layout.
    /// Used by window management features (hotkeys, grid buttons).
    ///
    /// Handles:
    /// - Minimized windows (unminimize via AX API)
    /// - Windows on other Spaces (raise via AX API)
    /// - Multiple windows (operates on the main/first window)
    static func moveAppWindow(bundleID: String, toScreen targetScreen: NSScreen, layout: WindowLayout = .center) {
        guard let window = findAppWindow(bundleID: bundleID) else { return }

        // Raise the window to ensure it's on the current Space
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        // Calculate target frame based on layout
        let visibleFrame = targetScreen.visibleFrame
        let fractional = layout.fractionalFrame

        let newWidth = visibleFrame.width * fractional.width
        let newHeight = visibleFrame.height * fractional.height
        let nsX = visibleFrame.origin.x + visibleFrame.width * fractional.origin.x
        let nsY = visibleFrame.origin.y + visibleFrame.height * fractional.origin.y

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? targetScreen.frame.height
        let axX = nsX
        let axY = primaryScreenHeight - (nsY + newHeight)

        // Set position first, then size
        var position = CGPoint(x: axX, y: axY)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        var size = CGSize(width: newWidth, height: newHeight)
        let sizeValue = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        print("[NARC] ✅ moveAppWindow: moved \(bundleID) to \(targetScreen.localizedName) at layout=\(layout.rawValue)")
    }

    /// Summon an app's window to the target screen, preserving its relative layout position.
    /// If the window occupied the left 50% of the source screen, it will occupy the left 50%
    /// of the target screen. This preserves the user's intentional layout decisions.
    /// Used by the "click to summon" feature in the notification panel.
    static func summonAppWindow(bundleID: String, toScreen targetScreen: NSScreen) {
        guard let window = findAppWindow(bundleID: bundleID) else { return }

        // Raise the window to ensure it's on the current Space
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        // Read the window's current position and size in AX coordinates
        var posRef: CFTypeRef?
        var axOrigin = CGPoint.zero
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
           let posValue = posRef {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &axOrigin)
        }

        var sizeRef: CFTypeRef?
        var currentSize = CGSize(width: 800, height: 600) // fallback
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &currentSize)
        }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? targetScreen.frame.height

        // Determine the source screen (where the window currently is)
        // Convert AX origin to NSScreen coordinates to find the source screen
        let nsOriginX = axOrigin.x
        let nsOriginY = primaryScreenHeight - axOrigin.y - currentSize.height
        let windowNSRect = NSRect(x: nsOriginX, y: nsOriginY, width: currentSize.width, height: currentSize.height)

        // Find source screen by checking which screen contains the window center
        let windowCenter = NSPoint(x: windowNSRect.midX, y: windowNSRect.midY)
        let sourceScreen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) })
            ?? NSScreen.screens.max(by: { screenA, screenB in
                screenA.frame.intersection(windowNSRect).width * screenA.frame.intersection(windowNSRect).height
                < screenB.frame.intersection(windowNSRect).width * screenB.frame.intersection(windowNSRect).height
            })
            ?? NSScreen.main
            ?? targetScreen

        let sourceVisible = sourceScreen.visibleFrame
        let targetVisible = targetScreen.visibleFrame

        // Calculate the window's relative position and size within the source screen's visible frame
        // These are fractional values (0.0 ~ 1.0)
        let relX = sourceVisible.width > 0 ? (nsOriginX - sourceVisible.origin.x) / sourceVisible.width : 0
        let relY = sourceVisible.height > 0 ? (nsOriginY - sourceVisible.origin.y) / sourceVisible.height : 0
        let relW = sourceVisible.width > 0 ? currentSize.width / sourceVisible.width : 0.5
        let relH = sourceVisible.height > 0 ? currentSize.height / sourceVisible.height : 0.5

        // Apply the same relative position and size to the target screen
        let newWidth = targetVisible.width * relW
        let newHeight = targetVisible.height * relH
        let newNsX = targetVisible.origin.x + targetVisible.width * relX
        let newNsY = targetVisible.origin.y + targetVisible.height * relY

        // Clamp to target screen bounds (safety check for different screen sizes)
        let clampedNsX = max(targetVisible.origin.x, min(newNsX, targetVisible.maxX - newWidth))
        let clampedNsY = max(targetVisible.origin.y, min(newNsY, targetVisible.maxY - newHeight))

        // Convert to AX coordinates
        let axX = clampedNsX
        let axY = primaryScreenHeight - (clampedNsY + newHeight)

        // Set position and size
        var position = CGPoint(x: axX, y: axY)
        let positionValue = AXValueCreate(.cgPoint, &position)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        var size = CGSize(width: newWidth, height: newHeight)
        let sizeValue2 = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue2)

        print("[NARC] ✅ summonAppWindow: summoned \(bundleID) to \(targetScreen.localizedName), relative layout preserved (relX=\(String(format: "%.2f", relX)), relY=\(String(format: "%.2f", relY)), relW=\(String(format: "%.2f", relW)), relH=\(String(format: "%.2f", relH)))")
    }

    /// Find the main window of an app by bundle ID.
    /// Handles minimized windows by unminimizing them.
    /// Returns the AXUIElement of the window, or nil if not found.
    private static func findAppWindow(bundleID: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("[NARC] ⚠️ findAppWindow: app not found for \(bundleID)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowElement: AXUIElement?

        // Strategy 1: Get the main window
        var mainWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef) == .success,
           let mainWindow = mainWindowRef {
            windowElement = (mainWindow as! AXUIElement)
            print("[NARC] 📍 findAppWindow: using main window")
        }

        // Strategy 2: Get from windows list, unminimize if needed
        if windowElement == nil {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {

                // Unminimize all minimized windows
                for window in windows {
                    var minimizedRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                       let isMinimized = minimizedRef as? Bool, isMinimized {
                        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                        print("[NARC] 📤 findAppWindow: unminimized window for \(bundleID)")
                    }
                }

                windowElement = windows.first
                if windowElement != nil {
                    print("[NARC] 📍 findAppWindow: using first window from list")
                }
            }
        }

        // Strategy 3: Get focused window
        if windowElement == nil {
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
               let focused = focusedRef {
                windowElement = (focused as! AXUIElement)
                print("[NARC] 📍 findAppWindow: using focused window")
            }
        }

        if windowElement == nil {
            print("[NARC] ⚠️ findAppWindow: could not get any window for \(bundleID)")
        }

        return windowElement
    }

    /// Move the active window to a layout (instance method for UI binding).
    func moveWindow(to layout: WindowLayout) {
        Self.moveActiveWindow(to: layout)
    }

    // MARK: - Permission Polling

    private var permissionTimer: Timer?

    /// Periodically check if Accessibility permission has been granted.
    /// Once granted, automatically register hotkeys.
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            // Don't prompt again — just check silently
            let options = [key: false] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)

            if trusted {
                print("[NARC] ✅ Accessibility permission now granted! Registering hotkeys...")
                timer.invalidate()
                self.permissionTimer = nil

                DispatchQueue.main.async {
                    self.isAccessibilityGranted = true
                    self.registerGlobalHotkeys()
                }
            }
        }
    }

    deinit {
        permissionTimer?.invalidate()
        unregisterGlobalHotkeys()
    }
}

// MARK: - NSRect Extension

private extension NSRect {
    /// The area of the rectangle.
    var area: CGFloat {
        return width * height
    }
}
