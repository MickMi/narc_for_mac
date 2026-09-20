import Cocoa

/// Thin coordination layer for window management operations.
///
/// Delegates to:
/// - `AXWindowHelper` for low-level AX API operations
/// - `ScreenNavigator` for cross-screen detection and navigation
/// - `HotkeyService` for hotkey registration (managed by AppDelegate)
///
/// Provides the public API consumed by:
/// - `AppDelegate` (via `moveActiveWindow`, `summonAppWindow`)
/// - `AppMonitorService` (via `summonAppWindow`)
/// - `PinnedWindowService` (via `findAppWindow`)
/// - `WindowGridView` (via `moveWindow`)
class WindowManagerService: ObservableObject {

    private static let moveGenerations = WindowMoveGenerationStore()
    private static let firstVerificationDelay: TimeInterval = 0.016
    private static let settleVerificationDelay: TimeInterval = 0.024
    private static let finalVerificationDelay: TimeInterval = 0.032
    private static let anchorVerificationRetryLimit = 2
    private static let fullScreenPollDelay: TimeInterval = 0.05
    private static let fullScreenPollLimit = 24

    private struct MoveContext {
        let window: AXUIElement
        let windowID: CGWindowID
        let processID: pid_t
        let windowKey: UInt64
        let generation: UInt64
        let tracksCrossScreenIntent: Bool
        let crossesScreen: Bool
        let requestedLayout: WindowLayout
        let appliedLayout: WindowLayout
        let targetDisplayID: CGDirectDisplayID
        let targetScreenName: String
        let targetScreenBounds: CGRect
        let sourceFrame: WindowMoveFrame
        let requestedFrame: WindowMoveFrame
        let reducedInitialWrite: Bool
        var compatibilityAttempted = false
        let bundleID: String
        let startedAt: UInt64
    }

    // MARK: - Window Layout (Hotkey Entry Point)

    /// Move the currently active (frontmost) window to the specified layout position.
    ///
    /// Cross-screen logic uses NARC's last verified placement as an intent gate:
    /// press the same hotkey while the window is still at that placement → cross.
    static func moveActiveWindow(
        to layout: WindowLayout,
        receivedAt: UInt64? = nil,
        allowCrossScreen: Bool = false
    ) {
        let startedAt = receivedAt ?? DispatchTime.now().uptimeNanoseconds
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        guard let window = AXWindowHelper.getFocusedWindow(appElement) else {
            print("[NARC] Could not get focused window for \(frontApp.localizedName ?? "unknown")")
            return
        }

        let processID = frontApp.processIdentifier
        let windowID = AXWindowHelper.windowID(for: window)
        let windowKey = operationKey(window: window, windowID: windowID, processID: processID)
        let generation = moveGenerations.begin(windowKey: windowKey)
        let bundleID = frontApp.bundleIdentifier ?? "unknown"
        trace(
            startedAt: startedAt,
            bundleID: bundleID,
            layout: layout,
            stage: "window-captured",
            detail: "generation=\(generation)"
        )

        // Handle macOS native fullscreen (green button). A transient AX read
        // failure is not treated as "not fullscreen" during a Space transition.
        let fullScreenStatus = AXWindowHelper.nativeFullScreenStatus(window)
        if case .enabled = fullScreenStatus {
            print("[NARC] 🔲 Window is in native fullscreen, exiting first before applying \(layout.rawValue)")
            let exitResult = AXWindowHelper.requestNativeFullScreenExit(window)
            trace(
                startedAt: startedAt,
                bundleID: bundleID,
                layout: layout,
                stage: "fullscreen-exit-requested",
                detail: "generation=\(generation) result=\(exitResult.rawValue)"
            )
            guard exitResult == .success || exitResult == .cannotComplete else {
                finishFailedMove(windowID: windowID, windowKey: windowKey, generation: generation)
                return
            }
            schedule(after: fullScreenPollDelay) {
                waitForNativeFullScreenExit(
                    window: window,
                    windowID: windowID,
                    processID: processID,
                    windowKey: windowKey,
                    generation: generation,
                    requestedLayout: layout,
                    allowCrossScreen: allowCrossScreen,
                    bundleID: bundleID,
                    startedAt: startedAt,
                    attempt: 0,
                    exitRequestAcknowledged: exitResult == .success,
                    exitRequestAttempts: 1,
                    previousDesktopFrame: nil
                )
            }
            return
        }

        if case let .unreadable(error) = fullScreenStatus {
            guard error == .cannotComplete else {
                finishFailedMove(windowID: windowID, windowKey: windowKey, generation: generation)
                return
            }
            schedule(after: fullScreenPollDelay) {
                waitForNativeFullScreenExit(
                    window: window,
                    windowID: windowID,
                    processID: processID,
                    windowKey: windowKey,
                    generation: generation,
                    requestedLayout: layout,
                    allowCrossScreen: allowCrossScreen,
                    bundleID: bundleID,
                    startedAt: startedAt,
                    attempt: 0,
                    exitRequestAcknowledged: false,
                    exitRequestAttempts: 0,
                    previousDesktopFrame: nil
                )
            }
            return
        }

        applyCapturedWindow(
            window: window,
            windowID: windowID,
            processID: processID,
            windowKey: windowKey,
            generation: generation,
            requestedLayout: layout,
            allowCrossScreen: allowCrossScreen,
            bundleID: bundleID,
            appName: frontApp.localizedName ?? "unknown",
            startedAt: startedAt
        )
    }

    private static func applyCapturedWindow(
        window: AXUIElement,
        windowID: CGWindowID,
        processID: pid_t,
        windowKey: UInt64,
        generation: UInt64,
        requestedLayout layout: WindowLayout,
        allowCrossScreen: Bool,
        bundleID: String,
        appName: String,
        startedAt: UInt64,
        frameReadAttempt: Int = 0
    ) {
        guard moveGenerations.isCurrent(windowKey: windowKey, generation: generation),
              let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else {
            finishFailedMove(windowID: windowID, windowKey: windowKey, generation: generation)
            return
        }

        let current: (position: CGPoint, size: CGSize)
        switch AXWindowHelper.getFrameResult(window) {
        case let .success(position, size):
            current = (position, size)
        case let .failure(error)
            where WindowFrameReadRetryPolicy.shouldRetry(
                error: error,
                failuresSoFar: frameReadAttempt
            ):
            trace(
                startedAt: startedAt,
                bundleID: bundleID,
                layout: layout,
                stage: "initial-frame-read-retry",
                detail: "generation=\(generation) attempt=\(frameReadAttempt + 1)"
            )
            schedule(after: settleVerificationDelay) {
                applyCapturedWindow(
                    window: window,
                    windowID: windowID,
                    processID: processID,
                    windowKey: windowKey,
                    generation: generation,
                    requestedLayout: layout,
                    allowCrossScreen: allowCrossScreen,
                    bundleID: bundleID,
                    appName: appName,
                    startedAt: startedAt,
                    frameReadAttempt: frameReadAttempt + 1
                )
            }
            return
        case let .failure(error):
            trace(
                startedAt: startedAt,
                bundleID: bundleID,
                layout: layout,
                stage: "initial-frame-read-failed",
                detail: "generation=\(generation) error=\(error.rawValue)"
            )
            finishFailedMove(windowID: windowID, windowKey: windowKey, generation: generation)
            return
        }

        let currentFrame = WindowMoveFrame(position: current.position, size: current.size)
        let identifiedSourceScreen = AXWindowHelper.screenForFrame(position: current.position, size: current.size)
        let currentScreen = identifiedSourceScreen ?? fallbackScreen
        let currentDisplayID = WindowLayoutState.displayID(for: currentScreen)
        let currentScreenBounds = screenBounds(for: currentScreen)

        var targetScreen = currentScreen
        var targetLayout = layout
        var crossesScreen = false

        // Cross-screen requires a matching NARC intent plus an unchanged physical frame.
        if allowCrossScreen,
           windowID != 0,
           WindowLayoutState.shared.shouldCrossScreen(
               windowID: windowID,
               processID: processID,
               layout: layout,
               screenDisplayID: currentDisplayID,
               screenBounds: currentScreenBounds,
               currentFrame: currentFrame
           ),
           NSScreen.screens.count > 1,
           let nextScreen = ScreenNavigator.adjacentScreen(from: currentScreen, direction: layout) {
            targetScreen = nextScreen
            targetLayout = ScreenNavigator.crossScreenEntryLayout(for: layout)
            crossesScreen = true
            print("[NARC] ↔️ Cross-screen: \(currentScreen.localizedName) → \(nextScreen.localizedName), entry layout=\(targetLayout.rawValue)")
        }

        // Apply layout
        let (axPos, axSize) = AXWindowHelper.calculateLayoutFrame(layout: targetLayout, on: targetScreen)
        print("[NARC] 🖥 moveActiveWindow: app=\(appName), "
              + "layout=\(targetLayout.rawValue), screen=\(targetScreen.localizedName), "
              + "targetPos=(\(Int(axPos.x)),\(Int(axPos.y))), targetSize=\(Int(axSize.width))x\(Int(axSize.height))")
        trace(
            startedAt: startedAt,
            bundleID: bundleID,
            layout: layout,
            stage: "target-resolved",
            detail: "generation=\(generation) cross=\(crossesScreen)"
        )
        let writeReceipt = AXWindowHelper.setFrameFast(
            window, position: axPos, size: axSize, on: targetScreen,
            currentFrame: currentFrame,
            sameDisplay: identifiedSourceScreen != nil && currentScreen == targetScreen
        )
        let requestedFrame = WindowMoveFrame(position: axPos, size: axSize)
        let screenBounds = screenBounds(for: targetScreen)
        let targetDisplayID = WindowLayoutState.displayID(for: targetScreen)

        if windowID != 0 {
            if allowCrossScreen, writeReceipt.acceptedByAPI {
                WindowLayoutState.shared.recordPending(
                    windowID: windowID,
                    processID: processID,
                    layout: layout,
                    appliedLayout: targetLayout,
                    screenDisplayID: targetDisplayID,
                    screenBounds: screenBounds,
                    requestedFrame: requestedFrame,
                    generation: generation
                )
            } else if !allowCrossScreen {
                WindowLayoutState.shared.invalidate(windowID: windowID)
            }
        }

        let context = MoveContext(
            window: window,
            windowID: windowID,
            processID: processID,
            windowKey: windowKey,
            generation: generation,
            tracksCrossScreenIntent: allowCrossScreen,
            crossesScreen: crossesScreen,
            requestedLayout: layout,
            appliedLayout: targetLayout,
            targetDisplayID: targetDisplayID,
            targetScreenName: targetScreen.localizedName,
            targetScreenBounds: screenBounds,
            sourceFrame: currentFrame,
            requestedFrame: requestedFrame,
            reducedInitialWrite: writeReceipt.finalSize == nil,
            bundleID: bundleID,
            startedAt: startedAt
        )

        trace(
            context,
            stage: "fast-write-returned",
            detail: receiptTraceDetail(writeReceipt)
        )
        schedule(after: firstVerificationDelay) {
            verifyInitial(context, frameReadFailures: frameReadAttempt)
        }
        print("[NARC] ↗️ moveActiveWindow dispatched: \(layout.rawValue) on \(targetScreen.localizedName)")
    }

    private static func verifyInitial(_ context: MoveContext, frameReadFailures: Int) {
        guard canContinueVerification(context) else { return }
        guard let observed = readFrame(
            context,
            stage: "initial",
            failuresSoFar: frameReadFailures,
            retry: { verifyInitial(context, frameReadFailures: $0) }
        ) else { return }

        if finishIfExact(context, observed: observed, stage: "verified-first-frame") {
            return
        }

        if WindowMoveGeometry.sizeMatches(observed.size, context.requestedFrame.size) {
            correctAnchorIfNeeded(context, observed: observed)
            schedule(after: settleVerificationDelay) {
                verifyFinal(context, previous: observed, frameReadFailures: frameReadFailures)
            }
            return
        }

        schedule(after: settleVerificationDelay) {
            verifySettled(context, previous: observed, frameReadFailures: frameReadFailures)
        }
    }

    private static func verifySettled(
        _ context: MoveContext,
        previous: WindowMoveFrame?,
        frameReadFailures: Int
    ) {
        guard canContinueVerification(context) else { return }
        guard let observed = readFrame(
            context,
            stage: "settled",
            failuresSoFar: frameReadFailures,
            retry: {
                verifySettled(context, previous: previous, frameReadFailures: $0)
            }
        ) else { return }

        if finishIfExact(context, observed: observed, stage: "verified-settled") {
            return
        }
        if retryReducedWriteIfNeeded(context, observed: observed, frameReadFailures: frameReadFailures) { return }

        if let previous,
           WindowMoveGeometry.sizeIsStable(previous.size, observed.size),
           WindowMoveGeometry.sizeIsAcceptableForLayout(
               observed.size,
               requested: context.requestedFrame.size,
               layout: context.appliedLayout
           ) {
            if WindowMoveGeometry.crossScreenMoveNeedsCompatibilityRetry(
                observed: observed,
                requested: context.requestedFrame,
                crossesScreen: context.crossesScreen
            ) {
                trace(
                    context,
                    stage: "cross-screen-size-retry",
                    detail: frameTraceDetail(observed)
                )
                performCompatibilityRetry(
                    context,
                    previous: observed,
                    frameReadFailures: frameReadFailures
                )
                return
            }
            guard WindowMoveGeometry.constrainedFrameIsAcceptable(
                observed,
                requested: context.requestedFrame,
                layout: context.appliedLayout,
                sourceFrame: context.sourceFrame,
                allowsUnchangedConstraint: false
            ) else {
                performCompatibilityRetry(
                    context,
                    previous: observed,
                    frameReadFailures: frameReadFailures
                )
                return
            }
            if finishIfConstrained(context, observed: observed, stage: "verified-constrained") {
                return
            }
            correctAnchorIfNeeded(context, observed: observed)
            schedule(after: finalVerificationDelay) {
                verifyFinal(context, previous: observed, frameReadFailures: frameReadFailures)
            }
            return
        }

        // The app is still changing or rejected the fast write. Enter one bounded
        // compatibility path that gives Enhanced UI time to switch without ever
        // sleeping in the hotkey callback or blocking every cooperative app.
        performCompatibilityRetry(
            context,
            previous: observed,
            frameReadFailures: frameReadFailures
        )
    }

    private static func performCompatibilityRetry(
        _ context: MoveContext,
        previous: WindowMoveFrame,
        frameReadFailures: Int
    ) {
        guard canContinueVerification(context), !context.compatibilityAttempted else { return }
        var continuation = context
        continuation.compatibilityAttempted = true
        let context = continuation
        AXWindowHelper.setFrameCompatibilityAsync(
            context.window,
            position: context.requestedFrame.position,
            size: context.requestedFrame.size,
            shouldContinue: {
                // Screen topology is AppKit state, so inspect it on the main
                // thread even though the bounded compatibility AX work is not.
                DispatchQueue.main.sync {
                    canContinueVerification(context)
                }
            }
        ) { receipt in
            guard let receipt, canContinueVerification(context) else { return }
            trace(
                context,
                stage: "compatibility-retry-write",
                detail: receiptTraceDetail(receipt)
            )
            verifyFinal(
                context,
                previous: previous,
                frameReadFailures: frameReadFailures,
                allowsUnchangedConstraint: receipt.acceptedByAPI
            )
        }
    }

    private static func verifyFinal(
        _ context: MoveContext,
        previous: WindowMoveFrame,
        frameReadFailures: Int,
        allowsUnchangedConstraint: Bool = false
    ) {
        guard canContinueVerification(context) else { return }
        guard let observed = readFrame(
            context,
            stage: "final",
            failuresSoFar: frameReadFailures,
            retry: {
                verifyFinal(
                    context,
                    previous: previous,
                    frameReadFailures: $0,
                    allowsUnchangedConstraint: allowsUnchangedConstraint
                )
            }
        ) else { return }

        if finishIfExact(context, observed: observed, stage: "verified-final") {
            return
        }
        if retryReducedWriteIfNeeded(context, observed: observed, frameReadFailures: frameReadFailures) { return }

        guard WindowMoveGeometry.sizeIsStable(previous.size, observed.size) else {
            schedule(after: finalVerificationDelay) {
                verifyLastObservation(
                    context,
                    previous: observed,
                    frameReadFailures: frameReadFailures,
                    allowsUnchangedConstraint: allowsUnchangedConstraint
                )
            }
            return
        }

        if finishIfConstrained(
            context,
            observed: observed,
            stage: "verified-final-constrained",
            allowsUnchangedConstraint: allowsUnchangedConstraint
        ) {
            return
        }

        correctAnchorIfNeeded(context, observed: observed)
        schedule(after: finalVerificationDelay) {
            verifyAnchor(
                context,
                previous: observed,
                frameReadFailures: frameReadFailures,
                allowsUnchangedConstraint: allowsUnchangedConstraint
            )
        }
    }

    private static func verifyLastObservation(
        _ context: MoveContext,
        previous: WindowMoveFrame,
        frameReadFailures: Int,
        allowsUnchangedConstraint: Bool
    ) {
        guard canContinueVerification(context) else { return }
        guard let observed = readFrame(
            context,
            stage: "last",
            failuresSoFar: frameReadFailures,
            retry: {
                verifyLastObservation(
                    context,
                    previous: previous,
                    frameReadFailures: $0,
                    allowsUnchangedConstraint: allowsUnchangedConstraint
                )
            }
        ) else { return }

        if finishIfExact(context, observed: observed, stage: "verified-last") {
            return
        }
        if retryReducedWriteIfNeeded(context, observed: observed, frameReadFailures: frameReadFailures) { return }

        guard WindowMoveGeometry.sizeIsStable(previous.size, observed.size) else {
            failVerification(context, reason: "frame-never-settled")
            return
        }

        if finishIfConstrained(
            context,
            observed: observed,
            stage: "verified-last-constrained",
            allowsUnchangedConstraint: allowsUnchangedConstraint
        ) {
            return
        }

        correctAnchorIfNeeded(context, observed: observed)
        schedule(after: finalVerificationDelay) {
            verifyAnchor(
                context,
                previous: observed,
                frameReadFailures: frameReadFailures,
                allowsUnchangedConstraint: allowsUnchangedConstraint
            )
        }
    }

    private static func verifyAnchor(
        _ context: MoveContext,
        previous: WindowMoveFrame,
        frameReadFailures: Int,
        allowsUnchangedConstraint: Bool = false,
        attempt: Int = 0
    ) {
        guard canContinueVerification(context) else { return }
        guard let observed = readFrame(
            context,
            stage: "anchor",
            failuresSoFar: frameReadFailures,
            retry: {
                verifyAnchor(
                    context,
                    previous: previous,
                    frameReadFailures: $0,
                    allowsUnchangedConstraint: allowsUnchangedConstraint,
                    attempt: attempt
                )
            }
        ) else { return }

        if retryReducedWriteIfNeeded(context, observed: observed, frameReadFailures: frameReadFailures) { return }
        if WindowMoveGeometry.sizeIsStable(previous.size, observed.size),
           finishIfConstrained(
               context,
               observed: observed,
               stage: "verified-anchor",
               allowsUnchangedConstraint: allowsUnchangedConstraint
           ) {
            return
        }

        guard attempt < anchorVerificationRetryLimit else {
            trace(
                context,
                stage: "anchor-retry-exhausted",
                detail: frameTraceDetail(observed)
            )
            failVerification(context, reason: "anchor-correction-rejected")
            return
        }

        correctAnchorIfNeeded(context, observed: observed)
        trace(
            context,
            stage: "anchor-retry",
            detail: "attempt=\(attempt + 1) \(frameTraceDetail(observed))"
        )
        schedule(after: finalVerificationDelay) {
            verifyAnchor(
                context,
                previous: observed,
                frameReadFailures: frameReadFailures,
                allowsUnchangedConstraint: allowsUnchangedConstraint,
                attempt: attempt + 1
            )
        }
    }

    @discardableResult
    private static func finishIfExact(
        _ context: MoveContext,
        observed: WindowMoveFrame,
        stage: String
    ) -> Bool {
        guard WindowMoveGeometry.matches(observed, context.requestedFrame),
              frameIsOnTargetScreen(observed, context: context) else {
            return false
        }
        finishVerifiedMove(context, acceptedFrame: observed, stage: stage)
        return true
    }

    @discardableResult
    private static func finishIfConstrained(
        _ context: MoveContext,
        observed: WindowMoveFrame,
        stage: String,
        allowsUnchangedConstraint: Bool = false
    ) -> Bool {
        let anchored = WindowMoveGeometry.anchoredFrame(
            layout: context.appliedLayout,
            screenBounds: context.targetScreenBounds,
            actualSize: observed.size
        )
        guard WindowMoveGeometry.constrainedFrameIsAcceptable(
                  observed,
                  requested: context.requestedFrame,
                  layout: context.appliedLayout,
                  sourceFrame: context.sourceFrame,
                  allowsUnchangedConstraint: allowsUnchangedConstraint
              ),
              WindowMoveGeometry.positionMatches(observed.position, anchored.position),
              frameIsOnTargetScreen(observed, context: context) else {
            return false
        }
        finishVerifiedMove(context, acceptedFrame: observed, stage: stage)
        return true
    }

    private static func correctAnchorIfNeeded(_ context: MoveContext, observed: WindowMoveFrame) {
        let anchored = WindowMoveGeometry.anchoredFrame(
            layout: context.appliedLayout,
            screenBounds: context.targetScreenBounds,
            actualSize: observed.size
        )
        guard !WindowMoveGeometry.positionMatches(observed.position, anchored.position),
              isCurrent(context) else {
            return
        }
        AXWindowHelper.setPosition(context.window, anchored.position)
        trace(context, stage: "anchor-correction")
    }

    private static func finishVerifiedMove(
        _ context: MoveContext,
        acceptedFrame: WindowMoveFrame,
        stage: String
    ) {
        guard isCurrent(context) else { return }

        if context.windowID != 0, context.tracksCrossScreenIntent {
            WindowLayoutState.shared.confirm(
                windowID: context.windowID,
                processID: context.processID,
                layout: context.requestedLayout,
                appliedLayout: context.appliedLayout,
                screenDisplayID: context.targetDisplayID,
                screenBounds: context.targetScreenBounds,
                acceptedFrame: acceptedFrame,
                generation: context.generation
            )
        }
        trace(context, stage: stage, detail: frameTraceDetail(acceptedFrame))
        moveGenerations.finish(windowKey: context.windowKey, generation: context.generation)
        print("[NARC] ✅ moveActiveWindow verified: \(context.requestedLayout.rawValue) on \(context.targetScreenName)")
    }

    private static func failVerification(_ context: MoveContext, reason: String) {
        guard isCurrent(context) else { return }
        if context.windowID != 0 {
            WindowLayoutState.shared.invalidate(windowID: context.windowID, generation: context.generation)
        }
        trace(context, stage: "verification-failed", detail: "reason=\(reason)")
        moveGenerations.finish(windowKey: context.windowKey, generation: context.generation)
        print("[NARC] ⚠️ moveActiveWindow not verified: \(reason)")
    }

    private static func finishFailedMove(windowID: CGWindowID, windowKey: UInt64, generation: UInt64) {
        if windowID != 0 {
            WindowLayoutState.shared.invalidate(windowID: windowID, generation: generation)
        }
        moveGenerations.finish(windowKey: windowKey, generation: generation)
    }

    private static func readFrame(
        _ context: MoveContext,
        stage: String,
        failuresSoFar: Int,
        retry: @escaping (Int) -> Void
    ) -> WindowMoveFrame? {
        switch AXWindowHelper.getFrameResult(context.window) {
        case let .success(position, size):
            return WindowMoveFrame(position: position, size: size)
        case let .failure(error)
            where WindowFrameReadRetryPolicy.shouldRetry(
                error: error,
                failuresSoFar: failuresSoFar
            ):
            let nextFailureCount = failuresSoFar + 1
            trace(
                context,
                stage: "frame-read-retry",
                detail: "probe=\(stage) error=\(error.rawValue) attempt=\(nextFailureCount)"
            )
            schedule(after: settleVerificationDelay) {
                guard canContinueVerification(context) else { return }
                retry(nextFailureCount)
            }
            return nil
        case let .failure(error):
            failVerification(context, reason: "\(stage)-frame-read-error-\(error.rawValue)")
            return nil
        }
    }

    private static func frameIsOnTargetScreen(_ frame: WindowMoveFrame, context: MoveContext) -> Bool {
        guard let screen = AXWindowHelper.screenForFrame(position: frame.position, size: frame.size) else {
            return false
        }
        return WindowLayoutState.displayID(for: screen) == context.targetDisplayID
    }

    private static func targetScreenSnapshotIsCurrent(_ context: MoveContext) -> Bool {
        guard let screen = NSScreen.screens.first(where: {
            WindowLayoutState.displayID(for: $0) == context.targetDisplayID
        }) else {
            return false
        }
        return WindowMoveGeometry.screenBoundsMatch(
            screenBounds(for: screen),
            context.targetScreenBounds
        )
    }

    private static func screenBounds(for screen: NSScreen) -> CGRect {
        let bounds = AXWindowHelper.screenBoundsInAX(screen.visibleFrame)
        return CGRect(
            x: bounds.left,
            y: bounds.top,
            width: bounds.right - bounds.left,
            height: bounds.bottom - bounds.top
        )
    }

    private static func isCurrent(_ context: MoveContext) -> Bool {
        moveGenerations.isCurrent(windowKey: context.windowKey, generation: context.generation)
    }

    private static func canContinueVerification(_ context: MoveContext) -> Bool {
        guard isCurrent(context) else { return false }
        guard targetScreenSnapshotIsCurrent(context) else {
            failVerification(context, reason: "screen-geometry-changed")
            return false
        }
        return true
    }

    private static func schedule(after delay: TimeInterval, operation: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
    }

    private static func waitForNativeFullScreenExit(
        window: AXUIElement,
        windowID: CGWindowID,
        processID: pid_t,
        windowKey: UInt64,
        generation: UInt64,
        requestedLayout: WindowLayout,
        allowCrossScreen: Bool,
        bundleID: String,
        startedAt: UInt64,
        attempt: Int,
        exitRequestAcknowledged: Bool,
        exitRequestAttempts: Int,
        previousDesktopFrame: WindowMoveFrame?
    ) {
        guard moveGenerations.isCurrent(windowKey: windowKey, generation: generation) else { return }

        guard attempt < fullScreenPollLimit else {
            trace(
                startedAt: startedAt,
                bundleID: bundleID,
                layout: requestedLayout,
                stage: "fullscreen-exit-timeout",
                detail: "generation=\(generation)"
            )
            finishFailedMove(windowID: windowID, windowKey: windowKey, generation: generation)
            return
        }

        let status = AXWindowHelper.nativeFullScreenStatus(window)
        var nextExitRequestAcknowledged = exitRequestAcknowledged
        var nextExitRequestAttempts = exitRequestAttempts
        var nextPreviousFrame: WindowMoveFrame?

        switch status {
        case .enabled:
            if !exitRequestAcknowledged, exitRequestAttempts < 2 {
                let exitResult = AXWindowHelper.requestNativeFullScreenExit(window)
                nextExitRequestAcknowledged = exitResult == .success
                nextExitRequestAttempts += 1
                trace(
                    startedAt: startedAt,
                    bundleID: bundleID,
                    layout: requestedLayout,
                    stage: "fullscreen-exit-requested-after-retry",
                    detail: "generation=\(generation) result=\(exitResult.rawValue)"
                )
                guard exitResult == .success || exitResult == .cannotComplete else {
                    finishFailedMove(
                        windowID: windowID,
                        windowKey: windowKey,
                        generation: generation
                    )
                    return
                }
            }
        case .disabled, .unsupported:
            switch AXWindowHelper.getFrameResult(window) {
            case let .success(position, size):
                let frame = WindowMoveFrame(position: position, size: size)
                guard AXWindowHelper.screenForFrame(
                    position: frame.position,
                    size: frame.size
                ) != nil else {
                    break
                }
                if let previousDesktopFrame,
                   WindowMoveGeometry.matches(frame, previousDesktopFrame) {
                    applyCapturedWindow(
                        window: window,
                        windowID: windowID,
                        processID: processID,
                        windowKey: windowKey,
                        generation: generation,
                        requestedLayout: requestedLayout,
                        allowCrossScreen: allowCrossScreen,
                        bundleID: bundleID,
                        appName: NSRunningApplication(processIdentifier: processID)?.localizedName ?? "unknown",
                        startedAt: startedAt
                    )
                    return
                }
                nextPreviousFrame = frame
            case .failure(.cannotComplete):
                break
            case .failure:
                finishFailedMove(
                    windowID: windowID,
                    windowKey: windowKey,
                    generation: generation
                )
                return
            }
        case let .unreadable(error):
            guard error == .cannotComplete else {
                finishFailedMove(windowID: windowID, windowKey: windowKey, generation: generation)
                return
            }
        }

        schedule(after: fullScreenPollDelay) {
            waitForNativeFullScreenExit(
                window: window,
                windowID: windowID,
                processID: processID,
                windowKey: windowKey,
                generation: generation,
                requestedLayout: requestedLayout,
                allowCrossScreen: allowCrossScreen,
                bundleID: bundleID,
                startedAt: startedAt,
                attempt: attempt + 1,
                exitRequestAcknowledged: nextExitRequestAcknowledged,
                exitRequestAttempts: nextExitRequestAttempts,
                previousDesktopFrame: nextPreviousFrame
            )
        }
    }

    private static func operationKey(
        window: AXUIElement,
        windowID: CGWindowID,
        processID: pid_t
    ) -> UInt64 {
        if windowID != 0 {
            return UInt64(windowID)
        }
        let processPart = UInt64(UInt32(bitPattern: processID)) << 32
        let elementPart = UInt64(bitPattern: Int64(CFHash(window)))
        return processPart ^ elementPart
    }

    private static func trace(_ context: MoveContext, stage: String, detail: String = "") {
        trace(
            startedAt: context.startedAt,
            bundleID: context.bundleID,
            layout: context.requestedLayout,
            stage: stage,
            detail: "generation=\(context.generation) \(detail)"
        )
    }

    private static func retryReducedWriteIfNeeded(
        _ context: MoveContext,
        observed: WindowMoveFrame,
        frameReadFailures: Int
    ) -> Bool {
        guard WindowMoveGeometry.reducedWriteNeedsCompatibilityRetry(
            observed: observed, requested: context.requestedFrame,
            reducedInitialWrite: context.reducedInitialWrite,
            compatibilityAttempted: context.compatibilityAttempted
        ) else { return false }
        trace(context, stage: "reduced-write-size-retry", detail: frameTraceDetail(observed))
        performCompatibilityRetry(context, previous: observed, frameReadFailures: frameReadFailures)
        return true
    }

    private static func receiptTraceDetail(_ receipt: AXWindowHelper.FrameWriteReceipt) -> String {
        func milliseconds(_ nanoseconds: UInt64) -> String {
            String(format: "%.2f", Double(nanoseconds) / 1_000_000)
        }
        func result(_ error: AXError?) -> String { error.map { String($0.rawValue) } ?? "skipped" }
        return "size1=\(result(receipt.firstSize))/\(milliseconds(receipt.firstSizeNanoseconds))ms "
            + "position=\(receipt.position.rawValue)/\(milliseconds(receipt.positionNanoseconds))ms "
            + "size2=\(result(receipt.finalSize))/\(milliseconds(receipt.finalSizeNanoseconds))ms"
    }

    private static func frameTraceDetail(_ frame: WindowMoveFrame) -> String {
        "frame=(\(Int(frame.position.x)),\(Int(frame.position.y)),"
            + "\(Int(frame.size.width))x\(Int(frame.size.height)))"
    }

    private static func trace(
        startedAt: UInt64,
        bundleID: String,
        layout: WindowLayout,
        stage: String,
        detail: String = ""
    ) {
        guard ProcessInfo.processInfo.environment["NARC_WINDOW_PERF"] == "1" else { return }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
        print(
            "[NARC][WindowPerf] stage=\(stage) elapsed_ms=\(String(format: "%.2f", elapsedMilliseconds)) "
                + "bundle=\(bundleID) layout=\(layout.rawValue) \(detail)"
        )
    }

    /// Move the active window to a layout (instance method for UI binding).
    func moveWindow(to layout: WindowLayout) {
        Self.moveActiveWindow(to: layout)
    }

    // MARK: - Window Summoning (IM App Activation)

    /// Move a specific app's window to a target screen with a specific layout.
    static func moveAppWindow(bundleID: String, toScreen targetScreen: NSScreen, layout: WindowLayout = .center) {
        guard let window = findAppWindow(bundleID: bundleID) else { return }

        AXWindowHelper.raise(window)

        let (axPos, axSize) = AXWindowHelper.calculateLayoutFrame(layout: layout, on: targetScreen)
        AXWindowHelper.setFrame(window, position: axPos, size: axSize, on: targetScreen)

        print("[NARC] ✅ moveAppWindow: moved \(bundleID) to \(targetScreen.localizedName) at layout=\(layout.rawValue)")
    }

    /// Summon an app's window to the target screen with proportional scaling.
    /// Includes retry logic for apps that need time to restore windows after activation.
    static func summonAppWindow(bundleID: String, toScreen targetScreen: NSScreen) {
        if let window = findAppWindow(bundleID: bundleID) {
            summonWindow(window, toScreen: targetScreen)
        } else {
            print("[NARC] ⏳ summonAppWindow: no window found, retrying in 0.5s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = findAppWindow(bundleID: bundleID) {
                    summonWindow(window, toScreen: targetScreen)
                } else {
                    print("[NARC] ⚠️ summonAppWindow: still no window after retry for \(bundleID)")
                }
            }
        }
    }

    /// Summon a specific window to the target screen.
    ///
    /// Strategy: preserve original size and map relative position from source screen
    /// to target screen. If already on target screen, just raise in place.
    static func summonWindow(_ window: AXUIElement, toScreen targetScreen: NSScreen) {
        AXWindowHelper.raise(window)

        let sourceScreen = AXWindowHelper.screenForWindow(window)

        // If already on target screen, just raise — don't move
        if let source = sourceScreen, source == targetScreen {
            print("[NARC] ✅ summonWindow: already on target screen, raised in place")
            return
        }

        // Preserve original size, map relative position to target screen
        let currentSize = AXWindowHelper.getSize(window) ?? CGSize(width: 800, height: 600)
        let currentPos = AXWindowHelper.getPosition(window)
        let targetVisible = targetScreen.visibleFrame

        // Clamp size to fit within target screen
        let clampedWidth = min(currentSize.width, targetVisible.width)
        let clampedHeight = min(currentSize.height, targetVisible.height)
        let finalSize = CGSize(width: clampedWidth, height: clampedHeight)

        // Calculate relative position from source screen, apply to target screen
        var nsX: CGFloat
        var nsY: CGFloat

        if let source = sourceScreen, let pos = currentPos {
            let sourceBounds = AXWindowHelper.screenBoundsInAX(source.visibleFrame)
            let sourceWidth = source.visibleFrame.width
            let sourceHeight = source.visibleFrame.height

            // Relative position (0.0 ~ 1.0) within source screen
            let relX = (pos.x - sourceBounds.left) / sourceWidth
            let relY = (pos.y - sourceBounds.top) / sourceHeight

            // Map to target screen
            let targetBounds = AXWindowHelper.screenBoundsInAX(targetVisible)
            let mappedX = targetBounds.left + relX * targetVisible.width
            let mappedY = targetBounds.top + relY * targetVisible.height

            // Clamp to keep window within target screen bounds
            let axPos = CGPoint(
                x: max(targetBounds.left, min(mappedX, targetBounds.right - finalSize.width)),
                y: max(targetBounds.top, min(mappedY, targetBounds.bottom - finalSize.height))
            )
            AXWindowHelper.setFrame(window, position: axPos, size: finalSize, on: targetScreen)
            print("[NARC] ✅ summonWindow: moved to \(targetScreen.localizedName) at mapped position")
        } else {
            // No source screen info — center on target screen
            nsX = targetVisible.origin.x + (targetVisible.width - finalSize.width) / 2
            nsY = targetVisible.origin.y + (targetVisible.height - finalSize.height) / 2
            let axPos = AXWindowHelper.nsToAX(x: nsX, y: nsY, height: finalSize.height)
            AXWindowHelper.setFrame(window, position: axPos, size: finalSize, on: targetScreen)
            print("[NARC] ✅ summonWindow: moved to \(targetScreen.localizedName) centered (no source)")
        }
    }

    // MARK: - Window Finding

    /// Find the main window of an app by bundle ID.
    private static func findAppWindow(bundleID: String) -> AXUIElement? {
        return findAppWindow(bundleID: bundleID, matchingTitle: nil)
    }

    /// Find a specific window of an app by bundle ID and optional title.
    /// If matchingTitle is provided, only that window is unminimized.
    /// Otherwise, the main/first window is returned.
    static func findAppWindow(bundleID: String, matchingTitle: String?) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("[NARC] ⚠️ findAppWindow: app not found for \(bundleID)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Title-based search
        if let targetTitle = matchingTitle {
            if let windows = AXWindowHelper.getWindows(appElement) {
                for window in windows {
                    if let title = AXWindowHelper.getTitle(window), title == targetTitle {
                        if AXWindowHelper.isMinimized(window) {
                            AXWindowHelper.unminimize(window)
                            print("[NARC] 📤 findAppWindow: unminimized matched window '\(targetTitle)'")
                        }
                        print("[NARC] 📍 findAppWindow: matched window by title '\(targetTitle)'")
                        return window
                    }
                }
            }
            print("[NARC] ⚠️ findAppWindow: no window matched title '\(targetTitle)', falling back...")
        }

        // Strategy 1: Main window
        if let mainWindow = AXWindowHelper.getMainWindow(appElement) {
            print("[NARC] 📍 findAppWindow: using main window")
            return mainWindow
        }

        // Strategy 2: First window from list (unminimize if needed)
        if let windows = AXWindowHelper.getWindows(appElement), let firstWindow = windows.first {
            if AXWindowHelper.isMinimized(firstWindow) {
                AXWindowHelper.unminimize(firstWindow)
                print("[NARC] 📤 findAppWindow: unminimized first window for \(bundleID)")
            }
            print("[NARC] 📍 findAppWindow: using first window from list")
            return firstWindow
        }

        // Strategy 3: Focused window
        if let focusedWindow = AXWindowHelper.getFocusedWindow(appElement) {
            print("[NARC] 📍 findAppWindow: using focused window")
            return focusedWindow
        }

        print("[NARC] ⚠️ findAppWindow: could not get any window for \(bundleID)")
        return nil
    }
}
