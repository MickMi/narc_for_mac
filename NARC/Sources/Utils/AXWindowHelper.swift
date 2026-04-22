import Cocoa

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
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        let value = AXValueCreate(.cgPoint, &p)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    /// Set the window's size.
    static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        let value = AXValueCreate(.cgSize, &s)!
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    /// Set the window's size and position with multi-pass retry for resistant apps.
    ///
    /// Sets size FIRST, then position (avoids macOS auto-correction when a large window
    /// is repositioned before being shrunk). Then re-applies with verification to handle
    /// apps (especially Electron-based like VS Code) that ignore or defer AX size changes.
    ///
    /// Some apps (Electron, etc.) have their own layout engine that constrains window
    /// sizes (e.g., minimum height for editor panels). When we detect the size has
    /// stabilized (same value on consecutive reads), we accept it as the app's best
    /// effort and stop retrying — avoiding unnecessary delays.
    static func setFrame(_ window: AXUIElement, position: CGPoint, size: CGSize) {
        let tolerance: CGFloat = 5.0
        let maxRetries = 4
        let retryDelays: [UInt32] = [8_000, 15_000, 30_000, 50_000] // 8ms, 15ms, 30ms, 50ms

        var previousSize: CGSize? = nil
        // Track the best (closest to target) size we've ever seen during retries.
        // Electron apps may oscillate during resize — if we've seen the target width
        // or height at least once, we know the app CAN reach it.
        var bestWidthDelta: CGFloat = .greatestFiniteMagnitude
        var bestHeightDelta: CGFloat = .greatestFiniteMagnitude

        for attempt in 0..<maxRetries {
            // Each pass: size first, then position
            setSize(window, size)
            setPosition(window, position)

            // Wait for the app's layout engine to process
            usleep(retryDelays[attempt])

            // Verify the size actually took effect
            if let currentSize = getSize(window) {
                let widthDelta = abs(currentSize.width - size.width)
                let heightDelta = abs(currentSize.height - size.height)
                let widthOK = widthDelta <= tolerance
                let heightOK = heightDelta <= tolerance

                bestWidthDelta = min(bestWidthDelta, widthDelta)
                bestHeightDelta = min(bestHeightDelta, heightDelta)

                if widthOK && heightOK {
                    if attempt > 0 {
                        print("[NARC] ✅ setFrame: size verified after \(attempt + 1) attempts")
                    }
                    // Final position correction (some apps shift position after size change)
                    setPosition(window, position)
                    return
                }

                // Check if size has stabilized (same as last attempt).
                // Only accept "stabilized = app constraint" if at least ONE dimension
                // is already close to the target. This prevents false early-exit when
                // the app simply hasn't processed the resize yet (e.g., Electron going
                // from 735px to 1470px width — both reads return 735 but that's not
                // a constraint, it's just slow processing).
                if let prev = previousSize,
                   abs(currentSize.width - prev.width) <= tolerance &&
                   abs(currentSize.height - prev.height) <= tolerance {
                    // Size stabilized — but is it because the app is constraining,
                    // or because it hasn't processed the change yet?
                    let atLeastOneDimensionClose = widthOK || heightOK
                    if atLeastOneDimensionClose {
                        print("[NARC] 📌 setFrame: app constrains size to \(Int(currentSize.width))x\(Int(currentSize.height)) "
                              + "(requested \(Int(size.width))x\(Int(size.height))), accepting")
                        setPosition(window, position)
                        return
                    }
                    // Neither dimension is close — keep retrying, the app may be slow
                    print("[NARC] ⚠️ setFrame: attempt \(attempt + 1)/\(maxRetries) — "
                          + "size stable at \(Int(currentSize.width))x\(Int(currentSize.height)) "
                          + "but far from target \(Int(size.width))x\(Int(size.height)), retrying")
                } else {
                    print("[NARC] ⚠️ setFrame: attempt \(attempt + 1)/\(maxRetries) — "
                          + "expected \(Int(size.width))x\(Int(size.height)), "
                          + "got \(Int(currentSize.width))x\(Int(currentSize.height))")
                }
                previousSize = currentSize

                // Early accept for oscillating apps: if at least one dimension has
                // reached the target at some point during retries AND currently matches,
                // accept it. This handles Electron apps that bounce between sizes during
                // layout recalculation.
                // - For horizontal layouts (leftHalf/rightHalf/fullScreen): width is primary
                // - For vertical layouts (topHalf/bottomHalf): height is primary
                if attempt >= 2 {
                    let widthReachedAndHolds = bestWidthDelta <= tolerance && widthOK
                    let heightReachedAndHolds = bestHeightDelta <= tolerance && heightOK
                    if widthReachedAndHolds || heightReachedAndHolds {
                        let constrainedDim = widthReachedAndHolds
                            ? "height constrained at \(Int(currentSize.height))"
                            : "width constrained at \(Int(currentSize.width))"
                        print("[NARC] 📌 setFrame: primary dimension reached target (\(constrainedDim)), accepting after \(attempt + 1) attempts")
                        setPosition(window, position)
                        return
                    }
                }
            }
        }

        // Final attempt: force one more size→position pass
        setSize(window, size)
        setPosition(window, position)
        print("[NARC] ⚠️ setFrame: exhausted \(maxRetries) retries, applied final pass")
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
