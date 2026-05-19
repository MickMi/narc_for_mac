import Cocoa

// Private Accessibility API for getting the CGWindowID of an AXUIElement.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Pure utility struct for Accessibility API window operations.
/// Eliminates boilerplate code for reading/writing AX attributes and coordinate conversion.
///
/// All methods are static — this is a stateless helper, not a service.
enum AXWindowHelper {

    // MARK: - Primary Screen Height (for coordinate conversion)

    /// The height of the primary screen, used for NS ↔ AX coordinate conversion.
    /// AX coordinate system: origin at top-left of primary screen, Y increases downward.
    /// NSScreen coordinate system: origin at bottom-left of primary screen, Y increases upward.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    // MARK: - Window Identification

    /// Get the stable CGWindowID for an AXUIElement window.
    /// Uses the private _AXUIElementGetWindow API (declared below).
    /// Returns 0 as fallback if the API is unavailable.
    static func windowID(for window: AXUIElement) -> CGWindowID {
        var wid: CGWindowID = 0
        let err = _AXUIElementGetWindow(window, &wid)
        return err == .success ? wid : 0
    }

    // MARK: - Read Window Attributes

    /// Read the window's position in AX coordinates (origin at top-left of primary screen).
    static func getPosition(_ window: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    /// Read the window's size.
    static func getSize(_ window: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }

    /// Read the window's position and size together.
    /// Returns nil if either attribute cannot be read.
    static func getFrame(_ window: AXUIElement) -> (position: CGPoint, size: CGSize)? {
        guard let pos = getPosition(window), let size = getSize(window) else { return nil }
        return (pos, size)
    }

    /// Read the window's title.
    static func getTitle(_ window: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String, !title.isEmpty else { return nil }
        return title
    }

    /// Check if the window is minimized.
    static func isMinimized(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref) == .success,
              let value = ref as? Bool else { return false }
        return value
    }

    /// Check if the window is in macOS native fullscreen (green button fullscreen).
    /// This is different from our "fullScreen" layout which just maximizes the window
    /// within the visible frame. Native fullscreen puts the window in a separate Space.
    static func isNativeFullScreen(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref) == .success,
              let value = ref as? Bool else { return false }
        return value
    }

    /// Exit macOS native fullscreen mode for a window.
    /// Returns true if the window was in native fullscreen and we initiated the exit.
    @discardableResult
    static func exitNativeFullScreen(_ window: AXUIElement) -> Bool {
        guard isNativeFullScreen(window) else { return false }
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
        print("[NARC] 🔲 Exited native fullscreen")
        return true
    }

    // MARK: - Write Window Attributes

    /// Set the window's position in AX coordinates.
    @discardableResult
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> AXError {
        var p = point
        let value = AXValueCreate(.cgPoint, &p)!
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    /// Set the window's size.
    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> AXError {
        var s = size
        let value = AXValueCreate(.cgSize, &s)!
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    /// Set the window's size and position — Magnet/Rectangle-equivalent implementation.
    ///
    /// Key techniques from Rectangle (open-source Magnet alternative):
    /// 1. Disable AXEnhancedUserInterface before resize (some apps like WeChat block
    ///    AX resize when this is enabled)
    /// 2. Set size first, then position, then size again (handles cross-display moves)
    /// 3. Re-enable enhanced UI after
    static func setFrame(_ window: AXUIElement, position: CGPoint, size: CGSize, on targetScreen: NSScreen? = nil) {
        let tolerance: CGFloat = 8.0

        // Get the application element for enhanced UI handling
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let appElement = AXUIElementCreateApplication(pid)

        // Step 1: Disable AXEnhancedUserInterface if enabled (critical for WeChat, etc.)
        var enhancedUIWasEnabled = false
        var enhancedUIRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &enhancedUIRef) == .success,
           let enabled = enhancedUIRef as? Bool, enabled {
            enhancedUIWasEnabled = true
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)
            usleep(20_000)  // 20ms for the change to take effect
        }

        // Step 2: Size → Position → Size (Rectangle's proven pattern, no intermediate moves)
        setSize(window, size)
        setPosition(window, position)
        setSize(window, size)
        usleep(50_000)  // 50ms for app to process

        // Step 3: Verify and retry if needed
        if let s = getSize(window), !(abs(s.width - size.width) <= tolerance && abs(s.height - size.height) <= tolerance) {
            setSize(window, size)
            setPosition(window, position)
            usleep(100_000)  // 100ms

            if let s2 = getSize(window), !(abs(s2.width - size.width) <= tolerance && abs(s2.height - size.height) <= tolerance) {
                setSize(window, size)
                setPosition(window, position)
                usleep(150_000)  // 150ms

                let finalSize = getSize(window)
                print("[NARC] 📏 setFrame: final \(Int(finalSize?.width ?? -1))x\(Int(finalSize?.height ?? -1)) "
                      + "(wanted \(Int(size.width))x\(Int(size.height)))")
            }
        }

        // Step 4: Re-enable AXEnhancedUserInterface if it was originally on
        if enhancedUIWasEnabled {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        }
    }

    /// Unminimize the window.
    static func unminimize(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    }

    /// Minimize the window.
    static func minimize(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    }

    /// Raise the window (bring to front on current Space).
    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    // MARK: - App-Level Queries

    /// Get the main window of an app element.
    static func getMainWindow(_ appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &ref) == .success,
              let window = ref else { return nil }
        return (window as! AXUIElement)
    }

    /// Get the focused window of an app element.
    static func getFocusedWindow(_ appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let window = ref else { return nil }
        return (window as! AXUIElement)
    }

    /// Get all windows of an app element.
    static func getWindows(_ appElement: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement], !windows.isEmpty else { return nil }
        return windows
    }

    // MARK: - Coordinate Conversion

    /// Convert NSScreen coordinates (origin at bottom-left, Y up) to AX coordinates
    /// (origin at top-left of primary screen, Y down).
    static func nsToAX(x: CGFloat, y: CGFloat, height: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: primaryScreenHeight - (y + height))
    }

    /// Convert an NSScreen visibleFrame to AX coordinate bounds.
    /// Returns (left, right, top, bottom) in AX coordinates.
    static func screenBoundsInAX(_ visibleFrame: NSRect) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let left = visibleFrame.origin.x
        let right = visibleFrame.origin.x + visibleFrame.width
        let top = primaryScreenHeight - (visibleFrame.origin.y + visibleFrame.height)
        let bottom = primaryScreenHeight - visibleFrame.origin.y
        return (left, right, top, bottom)
    }

    /// Convert an NSScreen frame to an AX coordinate rect (for containment checks).
    static func screenFrameInAX(_ screenFrame: NSRect) -> NSRect {
        return NSRect(
            x: screenFrame.origin.x,
            y: primaryScreenHeight - screenFrame.origin.y - screenFrame.height,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    /// Calculate the AX position and size for a layout on a given screen.
    static func calculateLayoutFrame(layout: WindowLayout, on screen: NSScreen) -> (position: CGPoint, size: CGSize) {
        let visibleFrame = screen.visibleFrame
        let fractional = layout.fractionalFrame

        let newWidth = visibleFrame.width * fractional.width
        let newHeight = visibleFrame.height * fractional.height
        let nsX = visibleFrame.origin.x + visibleFrame.width * fractional.origin.x
        let nsY = visibleFrame.origin.y + visibleFrame.height * fractional.origin.y

        let axPos = nsToAX(x: nsX, y: nsY, height: newHeight)
        return (axPos, CGSize(width: newWidth, height: newHeight))
    }

    // MARK: - Screen Detection

    /// Determine which screen a window is on based on its AX position and size.
    /// Uses center-point containment with overlap fallback.
    static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let frame = getFrame(window) else { return nil }

        let axCenter = CGPoint(
            x: frame.position.x + frame.size.width / 2,
            y: frame.position.y + frame.size.height / 2
        )

        // Primary strategy: check which screen's AX rect contains the window center
        for screen in NSScreen.screens {
            let axRect = screenFrameInAX(screen.frame)
            if axRect.contains(axCenter) {
                return screen
            }
        }

        // Fallback: find the screen with the most overlap
        let axWindowRect = NSRect(origin: frame.position, size: frame.size)
        return NSScreen.screens.max(by: { a, b in
            let rectA = screenFrameInAX(a.frame)
            let rectB = screenFrameInAX(b.frame)
            let areaA = rectA.intersection(axWindowRect).width * rectA.intersection(axWindowRect).height
            let areaB = rectB.intersection(axWindowRect).width * rectB.intersection(axWindowRect).height
            return areaA < areaB
        })
    }
}
