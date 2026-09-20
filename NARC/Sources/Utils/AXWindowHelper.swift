import Cocoa

// Private Accessibility API for getting the CGWindowID of an AXUIElement.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Pure utility struct for Accessibility API window operations.
/// Eliminates boilerplate code for reading/writing AX attributes and coordinate conversion.
///
/// All methods are static — this is a stateless helper, not a service.
enum AXWindowHelper {

    enum FrameReadResult {
        case success(position: CGPoint, size: CGSize)
        case failure(AXError)
    }

    enum NativeFullScreenStatus {
        case enabled
        case disabled
        case unsupported
        case unreadable(AXError)
    }

    struct FrameWriteReceipt {
        let firstSize: AXError?
        let position: AXError
        let finalSize: AXError?
        let firstSizeNanoseconds: UInt64
        let positionNanoseconds: UInt64
        let finalSizeNanoseconds: UInt64

        /// AX success is only an acknowledgement. The caller must still verify
        /// the physical frame before treating the move as complete.
        var acceptedByAPI: Bool {
            position == .success
                && ((firstSize == nil && finalSize == nil) || firstSize == .success || finalSize == .success)
        }
    }

    private static let enhancedUICompatibilityQueue = DispatchQueue(
        label: "com.mickmi.narc.window-enhanced-ui",
        qos: .userInitiated
    )
    private static let enhancedUIMessagingTimeout: Float = 0.10

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
        guard case let .success(position, size) = getFrameResult(window) else { return nil }
        return (position, size)
    }

    /// Read the frame while preserving the AX failure reason. Callers on the
    /// hot path use this to retry only transient target-app timeouts without
    /// masking invalid elements or permission failures.
    static func getFrameResult(_ window: AXUIElement) -> FrameReadResult {
        let attributes = [
            kAXPositionAttribute as CFString,
            kAXSizeAttribute as CFString,
        ] as CFArray
        var values: CFArray?
        let multipleReadResult = AXUIElementCopyMultipleAttributeValues(
            window,
            attributes,
            AXCopyMultipleAttributeOptions(rawValue: 1),
            &values
        )
        guard multipleReadResult == .success else {
            switch multipleReadResult {
            case .notImplemented, .attributeUnsupported:
                return getFrameIndividuallyResult(window)
            default:
                // A timeout or invalid element must not trigger two more blocking
                // IPC calls. The asynchronous verifier will make the next probe.
                return .failure(multipleReadResult)
            }
        }
        guard let values,
        CFArrayGetCount(values) == 2,
        let positionValue = CFArrayGetValueAtIndex(values, 0),
        let sizeValue = CFArrayGetValueAtIndex(values, 1) else {
            return getFrameIndividuallyResult(window)
        }

        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        guard CFGetTypeID(positionAXValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeAXValue) == AXValueGetTypeID(),
              AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize else {
            return getFrameIndividuallyResult(window)
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return getFrameIndividuallyResult(window)
        }
        return .success(position: position, size: size)
    }

    private static func getFrameIndividuallyResult(_ window: AXUIElement) -> FrameReadResult {
        var positionRef: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionRef
        )
        guard positionResult == .success else { return .failure(positionResult) }

        var sizeRef: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeRef
        )
        guard sizeResult == .success else { return .failure(sizeResult) }
        guard let positionRef,
              let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return .failure(.noValue)
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize else {
            return .failure(.noValue)
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return .failure(.cannotComplete)
        }
        return .success(position: position, size: size)
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
    static func nativeFullScreenStatus(_ window: AXUIElement) -> NativeFullScreenStatus {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref)
        guard result == .success else {
            switch result {
            case .attributeUnsupported, .noValue, .notImplemented:
                return .unsupported
            default:
                return .unreadable(result)
            }
        }
        guard let value = ref as? Bool else { return .unreadable(.cannotComplete) }
        return value ? .enabled : .disabled
    }

    static func nativeFullScreenState(_ window: AXUIElement) -> Bool? {
        switch nativeFullScreenStatus(window) {
        case .enabled: return true
        case .disabled, .unsupported: return false
        case .unreadable: return nil
        }
    }

    static func isNativeFullScreen(_ window: AXUIElement) -> Bool {
        nativeFullScreenState(window) == true
    }

    @discardableResult
    static func requestNativeFullScreenExit(_ window: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
    }

    /// Exit macOS native fullscreen mode for a window.
    /// Returns true if the window was in native fullscreen and we initiated the exit.
    @discardableResult
    static func exitNativeFullScreen(_ window: AXUIElement) -> Bool {
        guard isNativeFullScreen(window) else { return false }
        let result = requestNativeFullScreenExit(window)
        if result == .success {
            print("[NARC] 🔲 Exited native fullscreen")
        }
        return result == .success
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

    /// Apply the first frame write inside the existing Enhanced UI protection.
    ///
    /// Known same-display moves omit unchanged/repeated size writes. Cross-display
    /// moves and unknown source frames retain Size → Position → Size. Every path
    /// still requires physical-frame verification and a bounded compatibility retry.
    ///
    /// The experiment changes only the placement of the existing protection:
    /// enabled Enhanced UI gets its existing 20ms settle before any frame write,
    /// then its previous state is restored. Verification/retry timing and the
    /// synchronous pin/summon path remain unchanged; AX IPC can still block.
    @discardableResult
    static func setFrameFast(
        _ window: AXUIElement,
        position: CGPoint,
        size: CGSize,
        on _: NSScreen? = nil,
        currentFrame: WindowMoveFrame? = nil,
        sameDisplay: Bool = false
    ) -> FrameWriteReceipt {
        let plan = WindowFrameWritePlan.initial(current: currentFrame, targetSize: size, sameDisplay: sameDisplay)
        return withTemporarilyDisabledEnhancedUI(window, settleDelayMicroseconds: 20_000) {
            setFrameValues(window, position: position, size: size, plan: plan)
        }
    }

    /// Retry once with the compatibility timing required by apps such as WeChat.
    /// All waits and recovery happen on a dedicated queue, never the main thread.
    static func setFrameCompatibilityAsync(
        _ window: AXUIElement,
        position: CGPoint,
        size: CGSize,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping (FrameWriteReceipt?) -> Void
    ) {
        enhancedUICompatibilityQueue.async {
            guard shouldContinue() else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            var pid: pid_t = 0
            let hasProcess = AXUIElementGetPid(window, &pid) == .success && pid != 0
            let appElement = hasProcess ? AXUIElementCreateApplication(pid) : nil
            var shouldRestoreEnhancedUI = false

            if let appElement {
                AXUIElementSetMessagingTimeout(appElement, enhancedUIMessagingTimeout)
                var enhancedUIRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    appElement,
                    "AXEnhancedUserInterface" as CFString,
                    &enhancedUIRef
                ) == .success,
                let enabled = enhancedUIRef as? Bool,
                enabled {
                    shouldRestoreEnhancedUI = true
                    let disableResult = AXUIElementSetAttributeValue(
                        appElement,
                        "AXEnhancedUserInterface" as CFString,
                        false as CFTypeRef
                    )
                    if disableResult == .success || disableResult == .cannotComplete {
                        usleep(20_000)
                    }
                }
            }

            guard shouldContinue() else {
                if shouldRestoreEnhancedUI, let appElement {
                    restoreEnhancedUI(
                        appElement: appElement,
                        processID: pid,
                        attempt: 0
                    )
                }
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let receipt = setFrameValuesIfCurrent(
                window,
                position: position,
                size: size,
                shouldContinue: shouldContinue
            )
            if receipt != nil {
                usleep(50_000)
            }
            if shouldRestoreEnhancedUI, let appElement {
                restoreEnhancedUI(
                    appElement: appElement,
                    processID: pid,
                    attempt: 0
                )
            }
            DispatchQueue.main.async { completion(receipt) }
        }
    }

    private static func restoreEnhancedUI(
        appElement: AXUIElement,
        processID: pid_t,
        attempt: Int
    ) {
        let result = AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            true as CFTypeRef
        )
        guard result == .cannotComplete,
              NSRunningApplication(processIdentifier: processID) != nil else {
            return
        }

        let exponent = min(attempt, 6)
        let delay = min(0.025 * pow(2, Double(exponent)), 1.0)
        enhancedUICompatibilityQueue.asyncAfter(deadline: .now() + delay) {
            restoreEnhancedUI(
                appElement: appElement,
                processID: processID,
                attempt: attempt + 1
            )
        }
    }

    private static func setFrameValues(
        _ window: AXUIElement,
        position: CGPoint,
        size: CGSize,
        plan: WindowFrameWritePlan
    ) -> FrameWriteReceipt {
        executeFrameWrite(plan, writeSize: { setSize(window, size) }, writePosition: { setPosition(window, position) })
    }

    /// Injectable operations let tests count actual writes without controlling
    /// any user window. nil receipts mean skipped, never fabricated AX success.
    static func executeFrameWrite(
        _ plan: WindowFrameWritePlan,
        writeSize: () -> AXError,
        writePosition: () -> AXError
    ) -> FrameWriteReceipt {
        let firstSizeStartedAt = DispatchTime.now().uptimeNanoseconds
        let firstSize = plan == .positionOnly ? nil : writeSize()
        let firstSizeFinishedAt = DispatchTime.now().uptimeNanoseconds
        let position = writePosition()
        let positionFinishedAt = DispatchTime.now().uptimeNanoseconds
        let finalSize = plan == .sizePositionSize ? writeSize() : nil
        let finalSizeFinishedAt = DispatchTime.now().uptimeNanoseconds
        return FrameWriteReceipt(
            firstSize: firstSize,
            position: position,
            finalSize: finalSize,
            firstSizeNanoseconds: firstSizeFinishedAt - firstSizeStartedAt,
            positionNanoseconds: positionFinishedAt - firstSizeFinishedAt,
            finalSizeNanoseconds: finalSizeFinishedAt - positionFinishedAt
        )
    }

    /// The compatibility write can be superseded by a newer hotkey press while
    /// it is waiting on the target app. Recheck the generation between every AX
    /// mutation so a stale retry stops at the earliest safe boundary.
    private static func setFrameValuesIfCurrent(
        _ window: AXUIElement,
        position: CGPoint,
        size: CGSize,
        shouldContinue: () -> Bool
    ) -> FrameWriteReceipt? {
        guard shouldContinue() else { return nil }
        let firstSizeStartedAt = DispatchTime.now().uptimeNanoseconds
        let firstSize = setSize(window, size)
        let firstSizeFinishedAt = DispatchTime.now().uptimeNanoseconds
        guard shouldContinue() else { return nil }
        let position = setPosition(window, position)
        let positionFinishedAt = DispatchTime.now().uptimeNanoseconds
        guard shouldContinue() else { return nil }
        let finalSize = setSize(window, size)
        let finalSizeFinishedAt = DispatchTime.now().uptimeNanoseconds
        return FrameWriteReceipt(
            firstSize: firstSize,
            position: position,
            finalSize: finalSize,
            firstSizeNanoseconds: firstSizeFinishedAt - firstSizeStartedAt,
            positionNanoseconds: positionFinishedAt - firstSizeFinishedAt,
            finalSizeNanoseconds: finalSizeFinishedAt - positionFinishedAt
        )
    }

    /// Compatibility-preserving synchronous path used by summon/pin flows that
    /// have not yet adopted WindowManagerService's asynchronous verifier.
    static func setFrame(
        _ window: AXUIElement,
        position: CGPoint,
        size: CGSize,
        on _: NSScreen? = nil
    ) {
        let tolerance: CGFloat = 8

        withTemporarilyDisabledEnhancedUI(window, settleDelayMicroseconds: 20_000) {
            setSize(window, size)
            setPosition(window, position)
            setSize(window, size)
            usleep(50_000)

            guard let firstRead = getSize(window), !sizeIsClose(firstRead, size, tolerance: tolerance) else {
                return
            }

            setSize(window, size)
            setPosition(window, position)
            usleep(100_000)
            guard let secondRead = getSize(window), !sizeIsClose(secondRead, size, tolerance: tolerance) else {
                return
            }

            setSize(window, size)
            setPosition(window, position)
            usleep(150_000)
        }
    }

    private static func withTemporarilyDisabledEnhancedUI<T>(
        _ window: AXUIElement,
        settleDelayMicroseconds: useconds_t,
        operation: () -> T
    ) -> T {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != 0 else {
            return operation()
        }

        let appElement = AXUIElementCreateApplication(pid)
        var enhancedUIRef: CFTypeRef?
        let enhancedUIWasEnabled = AXUIElementCopyAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            &enhancedUIRef
        ) == .success && (enhancedUIRef as? Bool) == true

        if enhancedUIWasEnabled {
            let disableResult = AXUIElementSetAttributeValue(
                appElement,
                "AXEnhancedUserInterface" as CFString,
                false as CFTypeRef
            )
            if (disableResult == .success || disableResult == .cannotComplete),
               settleDelayMicroseconds > 0 {
                usleep(settleDelayMicroseconds)
            }
        }
        defer {
            if enhancedUIWasEnabled {
                AXUIElementSetAttributeValue(
                    appElement,
                    "AXEnhancedUserInterface" as CFString,
                    true as CFTypeRef
                )
            }
        }
        return operation()
    }

    private static func sizeIsClose(_ observed: CGSize, _ expected: CGSize, tolerance: CGFloat) -> Bool {
        abs(observed.width - expected.width) <= tolerance
            && abs(observed.height - expected.height) <= tolerance
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

        return screenForFrame(position: frame.position, size: frame.size)
    }

    /// Determine which screen owns an already-read AX frame. This avoids two
    /// extra accessibility IPC reads on the layout hot path.
    static func screenForFrame(position: CGPoint, size: CGSize) -> NSScreen? {

        let axCenter = CGPoint(
            x: position.x + size.width / 2,
            y: position.y + size.height / 2
        )

        // Primary strategy: check which screen's AX rect contains the window center
        for screen in NSScreen.screens {
            let axRect = screenFrameInAX(screen.frame)
            if axRect.contains(axCenter) {
                return screen
            }
        }

        // Fallback: find the screen with the most overlap
        let axWindowRect = NSRect(origin: position, size: size)
        let overlaps = NSScreen.screens.map { screen -> (screen: NSScreen, area: CGFloat) in
            let intersection = screenFrameInAX(screen.frame).intersection(axWindowRect)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen, area)
        }
        guard let best = overlaps.max(by: { $0.area < $1.area }), best.area > 0 else {
            return nil
        }
        return best.screen
    }
}
