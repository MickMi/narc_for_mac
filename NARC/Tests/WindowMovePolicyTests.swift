import Cocoa
import Testing
@testable import NARC

@Test func bottomRightConstraintKeepsBothEdgesAnchored() {
    let screen = CGRect(x: -1_440, y: 24, width: 1_440, height: 876)
    let acceptedSize = CGSize(width: 820, height: 560)

    let frame = WindowMoveGeometry.anchoredFrame(
        layout: .bottomRight,
        screenBounds: screen,
        actualSize: acceptedSize
    )

    #expect(frame.position.x == screen.maxX - acceptedSize.width)
    #expect(frame.position.y == screen.maxY - acceptedSize.height)
}

@Test func constrainedCenterUsesActualAcceptedSize() {
    let screen = CGRect(x: 0, y: 25, width: 1_920, height: 1_055)
    let acceptedSize = CGSize(width: 1_000, height: 700)

    let frame = WindowMoveGeometry.anchoredFrame(
        layout: .center,
        screenBounds: screen,
        actualSize: acceptedSize
    )

    #expect(frame.position.x == 460)
    #expect(frame.position.y == 202.5)
}

@Test func fullPlacementRequiresBothPositionAndSize() {
    let expected = WindowMoveFrame(
        position: CGPoint(x: 100, y: 80),
        size: CGSize(width: 900, height: 700)
    )
    let wrongPosition = WindowMoveFrame(
        position: CGPoint(x: 120, y: 80),
        size: expected.size
    )
    let wrongSize = WindowMoveFrame(
        position: expected.position,
        size: CGSize(width: 850, height: 700)
    )

    #expect(WindowMoveGeometry.matches(expected, expected))
    #expect(!WindowMoveGeometry.matches(wrongPosition, expected))
    #expect(!WindowMoveGeometry.matches(wrongSize, expected))
}

@Test func recentPendingPlacementSupportsFastDoublePress() {
    let state = WindowLayoutState(pendingTTL: 0.5)
    let requested = WindowMoveFrame(
        position: CGPoint(x: 960, y: 24),
        size: CGSize(width: 960, height: 1_056)
    )
    let beforeWrite = WindowMoveFrame(
        position: CGPoint(x: 100, y: 100),
        size: CGSize(width: 800, height: 600)
    )
    let start = Date(timeIntervalSince1970: 2_000)
    let screenBounds = CGRect(x: 0, y: 24, width: 1_920, height: 1_056)

    state.recordPending(
        windowID: 12,
        processID: 34,
        layout: .rightHalf,
        appliedLayout: .rightHalf,
        screenDisplayID: 56,
        screenBounds: screenBounds,
        requestedFrame: requested,
        generation: 1,
        now: start
    )

    #expect(state.shouldCrossScreen(
        windowID: 12,
        processID: 34,
        layout: .rightHalf,
        screenDisplayID: 56,
        screenBounds: screenBounds,
        currentFrame: beforeWrite,
        now: start.addingTimeInterval(0.1)
    ))
    #expect(!state.shouldCrossScreen(
        windowID: 12,
        processID: 34,
        layout: .rightHalf,
        screenDisplayID: 56,
        screenBounds: screenBounds,
        currentFrame: beforeWrite,
        now: start.addingTimeInterval(0.6)
    ))
}

@Test func staleGenerationCannotReplaceOrClearNewerPlacement() {
    let state = WindowLayoutState()
    let first = WindowMoveFrame(
        position: CGPoint(x: 0, y: 20),
        size: CGSize(width: 800, height: 900)
    )
    let second = WindowMoveFrame(
        position: CGPoint(x: 800, y: 20),
        size: CGSize(width: 800, height: 900)
    )
    let screenBounds = CGRect(x: 0, y: 20, width: 1_600, height: 900)

    state.recordPending(
        windowID: 77,
        processID: 88,
        layout: .rightHalf,
        appliedLayout: .rightHalf,
        screenDisplayID: 9,
        screenBounds: screenBounds,
        requestedFrame: second,
        generation: 2
    )
    state.recordPending(
        windowID: 77,
        processID: 88,
        layout: .leftHalf,
        appliedLayout: .leftHalf,
        screenDisplayID: 9,
        screenBounds: screenBounds,
        requestedFrame: first,
        generation: 1
    )

    #expect(!state.confirm(
        windowID: 77,
        processID: 88,
        layout: .leftHalf,
        appliedLayout: .leftHalf,
        screenDisplayID: 9,
        screenBounds: screenBounds,
        acceptedFrame: first,
        generation: 1
    ))
    state.invalidate(windowID: 77, generation: 1)

    #expect(state.shouldCrossScreen(
        windowID: 77,
        processID: 88,
        layout: .rightHalf,
        screenDisplayID: 9,
        screenBounds: screenBounds,
        currentFrame: second
    ))
}

@Test func stableFrameMustPreserveTheLayoutsDefiningDimensions() {
    let requested = CGSize(width: 960, height: 1_056)

    #expect(WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 960, height: 700),
        requested: requested,
        layout: .leftHalf
    ))
    #expect(WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 1_060, height: 1_056),
        requested: requested,
        layout: .leftHalf
    ))
    #expect(!WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 700, height: 1_056),
        requested: requested,
        layout: .leftHalf
    ))
    #expect(!WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 1_920, height: 1_056),
        requested: requested,
        layout: .leftHalf
    ))
    #expect(WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 1_400, height: 1_056),
        requested: requested,
        layout: .topHalf
    ))
    #expect(!WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 960, height: 700),
        requested: requested,
        layout: .topHalf
    ))
    #expect(!WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 1_400, height: 2_112),
        requested: requested,
        layout: .topHalf
    ))
    #expect(!WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 960, height: 700),
        requested: requested,
        layout: .topLeft
    ))
    #expect(WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 1_060, height: 1_100),
        requested: requested,
        layout: .topLeft
    ))
    #expect(!WindowMoveGeometry.sizeIsAcceptableForLayout(
        CGSize(width: 960, height: 700),
        requested: requested,
        layout: .fullScreen
    ))
    #expect(WindowMoveGeometry.sizeIsAcceptableForLayout(
        requested,
        requested: requested,
        layout: .fullScreen
    ))
}

@Test func unchangedNearFullFrameNeedsCompatibilityBeforeConstraintAcceptance() {
    let requested = WindowMoveFrame(
        position: CGPoint(x: 960, y: 24),
        size: CGSize(width: 960, height: 1_056)
    )
    let unchangedNearFull = WindowMoveFrame(
        position: CGPoint(x: 20, y: 24),
        size: CGSize(width: 1_900, height: 1_056)
    )
    let progressedConstraint = WindowMoveFrame(
        position: CGPoint(x: 860, y: 24),
        size: CGSize(width: 1_060, height: 1_056)
    )

    #expect(!WindowMoveGeometry.constrainedFrameIsAcceptable(
        unchangedNearFull,
        requested: requested,
        layout: .rightHalf,
        sourceFrame: unchangedNearFull,
        allowsUnchangedConstraint: false
    ))
    #expect(WindowMoveGeometry.constrainedFrameIsAcceptable(
        unchangedNearFull,
        requested: requested,
        layout: .rightHalf,
        sourceFrame: unchangedNearFull,
        allowsUnchangedConstraint: true
    ))
    #expect(WindowMoveGeometry.constrainedFrameIsAcceptable(
        progressedConstraint,
        requested: requested,
        layout: .rightHalf,
        sourceFrame: unchangedNearFull,
        allowsUnchangedConstraint: false
    ))
}

@Test func crossScreenHalfMoveRetriesWhenOnlyTargetWidthWasApplied() {
    let requested = WindowMoveFrame(
        position: CGPoint(x: -1_280, y: 24),
        size: CGSize(width: 1_280, height: 1_416)
    )
    let widthOnlyResult = WindowMoveFrame(
        position: requested.position,
        size: CGSize(width: requested.size.width, height: 876)
    )

    #expect(WindowMoveGeometry.crossScreenMoveNeedsCompatibilityRetry(
        observed: widthOnlyResult,
        requested: requested,
        crossesScreen: true
    ))
    #expect(!WindowMoveGeometry.crossScreenMoveNeedsCompatibilityRetry(
        observed: widthOnlyResult,
        requested: requested,
        crossesScreen: false
    ))
    #expect(!WindowMoveGeometry.crossScreenMoveNeedsCompatibilityRetry(
        observed: requested,
        requested: requested,
        crossesScreen: true
    ))
    #expect(WindowMoveGeometry.constrainedFrameIsAcceptable(
        widthOnlyResult,
        requested: requested,
        layout: .rightHalf,
        sourceFrame: WindowMoveFrame(
            position: CGPoint(x: 0, y: 24),
            size: CGSize(width: 720, height: 876)
        ),
        allowsUnchangedConstraint: false
    ))
}

@Test func crossScreenEntryMustFirstReturnToTheRequestedSide() {
    let state = WindowLayoutState()
    let screenBounds = CGRect(x: 1_920, y: 24, width: 1_920, height: 1_056)
    let entryFrame = WindowMoveFrame(
        position: CGPoint(x: 1_920, y: 24),
        size: CGSize(width: 960, height: 1_056)
    )

    state.confirm(
        windowID: 91,
        processID: 92,
        layout: .rightHalf,
        appliedLayout: .leftHalf,
        screenDisplayID: 93,
        screenBounds: screenBounds,
        acceptedFrame: entryFrame,
        generation: 1
    )

    #expect(!state.shouldCrossScreen(
        windowID: 91,
        processID: 92,
        layout: .rightHalf,
        screenDisplayID: 93,
        screenBounds: screenBounds,
        currentFrame: entryFrame
    ))
}

@Test func changedScreenWorkspaceInvalidatesOldCrossScreenIntent() {
    let state = WindowLayoutState()
    let oldBounds = CGRect(x: 0, y: 24, width: 1_920, height: 1_056)
    let changedBounds = CGRect(x: 0, y: 24, width: 1_920, height: 1_000)
    let frame = WindowMoveFrame(
        position: CGPoint(x: 960, y: 24),
        size: CGSize(width: 960, height: 1_056)
    )

    state.confirm(
        windowID: 94,
        processID: 95,
        layout: .rightHalf,
        appliedLayout: .rightHalf,
        screenDisplayID: 96,
        screenBounds: oldBounds,
        acceptedFrame: frame,
        generation: 1
    )

    #expect(!state.shouldCrossScreen(
        windowID: 94,
        processID: 95,
        layout: .rightHalf,
        screenDisplayID: 96,
        screenBounds: changedBounds,
        currentFrame: frame
    ))
}

@Test func oversizedConstrainedWindowKeepsItsTopLeftControlsReachable() {
    let screen = CGRect(x: -1_440, y: 24, width: 1_440, height: 876)
    let frame = WindowMoveGeometry.anchoredFrame(
        layout: .bottomRight,
        screenBounds: screen,
        actualSize: CGSize(width: 1_800, height: 1_000)
    )

    #expect(frame.position == screen.origin)
}

@Test func generationStoreCancelsOnlyOlderWorkForTheSameWindow() {
    let store = WindowMoveGenerationStore()
    let first = store.begin(windowKey: 100)
    let otherWindow = store.begin(windowKey: 200)
    let second = store.begin(windowKey: 100)

    #expect(!store.isCurrent(windowKey: 100, generation: first))
    #expect(store.isCurrent(windowKey: 100, generation: second))
    #expect(store.isCurrent(windowKey: 200, generation: otherWindow))

    store.finish(windowKey: 100, generation: first)
    #expect(store.isCurrent(windowKey: 100, generation: second))

    store.finish(windowKey: 100, generation: second)
    #expect(!store.isCurrent(windowKey: 100, generation: second))
    #expect(store.isCurrent(windowKey: 200, generation: otherWindow))
}

@Test func frameReadRetriesOnlyTransientFailuresWithinOneBoundedBudget() {
    #expect(WindowFrameReadRetryPolicy.shouldRetry(error: .cannotComplete, failuresSoFar: 0))
    #expect(WindowFrameReadRetryPolicy.shouldRetry(error: .cannotComplete, failuresSoFar: 1))
    #expect(!WindowFrameReadRetryPolicy.shouldRetry(error: .cannotComplete, failuresSoFar: 2))
    #expect(!WindowFrameReadRetryPolicy.shouldRetry(error: .invalidUIElement, failuresSoFar: 0))
    #expect(!WindowFrameReadRetryPolicy.shouldRetry(error: .apiDisabled, failuresSoFar: 0))
}

// Source-contract checks, not proof of real AX timing or visual smoothness.
@Test func windowMoveInitialWriteHasCompatibilityProtectionWithoutRetrySleeps() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourcesDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("Sources")
    let managerFile = sourcesDirectory.appendingPathComponent("Services/WindowManagerService.swift")
    let managerSource = try String(contentsOf: managerFile, encoding: .utf8)
    #expect(!managerSource.contains("usleep("))
    #expect(!managerSource.contains("Thread.sleep"))

    let helperFile = sourcesDirectory.appendingPathComponent("Utils/AXWindowHelper.swift")
    let helperSource = try String(contentsOf: helperFile, encoding: .utf8)
    let fastStart = try #require(helperSource.range(of: "static func setFrameFast("))
    let fastEnd = try #require(helperSource.range(
        of: "/// Retry once with the compatibility timing",
        range: fastStart.upperBound..<helperSource.endIndex
    ))
    let fastBody = helperSource[fastStart.lowerBound..<fastEnd.lowerBound]
    #expect(fastBody.contains("setFrameValues(window"))
    #expect(!fastBody.contains("usleep("))
    #expect(!fastBody.contains("Thread.sleep"))
    #expect(fastBody.contains("return withTemporarilyDisabledEnhancedUI(window, settleDelayMicroseconds: 20_000) {"))
    let protection = fastBody.range(of: "withTemporarilyDisabledEnhancedUI(")
    let frameWrite = try #require(fastBody.range(of: "setFrameValues(window"))
    if let protection {
        #expect(protection.lowerBound < frameWrite.lowerBound)
    }

    let guardStart = try #require(helperSource.range(of: "private static func withTemporarilyDisabledEnhancedUI<T>("))
    let guardEnd = try #require(helperSource.range(of: "private static func sizeIsClose(", range: guardStart.upperBound..<helperSource.endIndex))
    let guardBody = helperSource[guardStart.lowerBound..<guardEnd.lowerBound]
    #expect(guardBody.contains("== .success && (enhancedUIRef as? Bool) == true"))
    #expect(guardBody.contains("if enhancedUIWasEnabled {"))
    #expect(guardBody.contains("false as CFTypeRef"))
    let restoration = try #require(guardBody.range(of: "defer {"))
    let operation = try #require(guardBody.range(of: "return operation()", options: .backwards))
    #expect(restoration.lowerBound < operation.lowerBound)
    #expect(guardBody[restoration.lowerBound..<operation.lowerBound].contains("true as CFTypeRef"))

    let compatibilityStart = try #require(helperSource.range(
        of: "static func setFrameCompatibilityAsync("
    ))
    let compatibilityEnd = try #require(helperSource.range(
        of: "private static func restoreEnhancedUI(",
        range: compatibilityStart.upperBound..<helperSource.endIndex
    ))
    let compatibilityBody = helperSource[
        compatibilityStart.lowerBound..<compatibilityEnd.lowerBound
    ]
    #expect(compatibilityBody.contains("enhancedUICompatibilityQueue.async"))
    #expect(compatibilityBody.contains("usleep("))
}

@Test func windowMoveInitialWriteUsesExactSizeAndKnownDisplay() {
    let frame = WindowMoveFrame(position: CGPoint(x: 0, y: 24), size: CGSize(width: 960, height: 1_056))
    #expect(WindowFrameWritePlan.initial(current: frame, targetSize: frame.size, sameDisplay: true) == .positionOnly)
    #expect(WindowFrameWritePlan.initial(current: frame, targetSize: CGSize(width: 960, height: 1_057), sameDisplay: true) == .sizeThenPosition)
    #expect(WindowFrameWritePlan.initial(current: frame, targetSize: frame.size, sameDisplay: false) == .sizePositionSize)
    #expect(WindowFrameWritePlan.initial(current: nil, targetSize: frame.size, sameDisplay: true) == .sizePositionSize)
}

@Test func windowMoveWritesOnlyThePlannedAXOperations() {
    for (plan, expected) in [
        (WindowFrameWritePlan.positionOnly, ["position"]),
        (.sizeThenPosition, ["size", "position"]),
        (.sizePositionSize, ["size", "position", "size"])
    ] {
        var calls: [String] = []
        let receipt = AXWindowHelper.executeFrameWrite(
            plan,
            writeSize: { calls.append("size"); return .success },
            writePosition: { calls.append("position"); return .success }
        )
        #expect(calls == expected)
        #expect(receipt.acceptedByAPI)
        #expect((receipt.firstSize == nil) == (plan == .positionOnly))
        #expect((receipt.finalSize == nil) == (plan != .sizePositionSize))
    }
}

@Test func windowMoveSkippedWritesNeverHideAnAXFailure() {
    let failedPosition = AXWindowHelper.executeFrameWrite(.positionOnly, writeSize: { Issue.record("unexpected size write"); return .success }, writePosition: { .cannotComplete })
    #expect(!failedPosition.acceptedByAPI)
    #expect(failedPosition.firstSize == nil && failedPosition.finalSize == nil)
    let failedSize = AXWindowHelper.executeFrameWrite(.sizeThenPosition, writeSize: { .cannotComplete }, writePosition: { .success })
    #expect(!failedSize.acceptedByAPI)
    #expect(failedSize.firstSize == .cannotComplete && failedSize.finalSize == nil)
    var sizeCalls = 0
    let recoveredSize = AXWindowHelper.executeFrameWrite(.sizePositionSize, writeSize: {
        sizeCalls += 1
        return sizeCalls == 1 ? .cannotComplete : .success
    }, writePosition: { .success })
    #expect(recoveredSize.acceptedByAPI)
}

@Test func windowMoveReducedWriteCannotAcceptPartialHeightBeforeOneFullRetry() {
    let requested = WindowMoveFrame(position: CGPoint(x: 960, y: 24), size: CGSize(width: 960, height: 1_056))
    let partial = WindowMoveFrame(position: requested.position, size: CGSize(width: 960, height: 700))
    #expect(WindowMoveGeometry.reducedWriteNeedsCompatibilityRetry(observed: partial, requested: requested, reducedInitialWrite: true, compatibilityAttempted: false))
    #expect(!WindowMoveGeometry.reducedWriteNeedsCompatibilityRetry(observed: partial, requested: requested, reducedInitialWrite: true, compatibilityAttempted: true))
    #expect(!WindowMoveGeometry.reducedWriteNeedsCompatibilityRetry(observed: partial, requested: requested, reducedInitialWrite: false, compatibilityAttempted: false))
    #expect(!WindowMoveGeometry.reducedWriteNeedsCompatibilityRetry(observed: requested, requested: requested, reducedInitialWrite: true, compatibilityAttempted: false))
}

@Test func windowMoveEveryConstraintAcceptanceStageProtectsReducedWrites() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Services/WindowManagerService.swift"), encoding: .utf8)
    for stage in ["verifySettled", "verifyFinal", "verifyLastObservation", "verifyAnchor"] {
        let start = try #require(source.range(of: "private static func \(stage)("))
        let end = source.range(of: "private static func ", range: start.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
        let body = String(source[start.lowerBound..<end])
        let retry = try #require(body.range(of: "retryReducedWriteIfNeeded("))
        let acceptance = try #require(body.range(of: "finishIfConstrained("))
        #expect(retry.lowerBound < acceptance.lowerBound)
    }
    #expect(source.contains("continuation.compatibilityAttempted = true"))
}
