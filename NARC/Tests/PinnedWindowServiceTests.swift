import AppKit
import Testing
@testable import NARC

@Test
func currentWindowPinDecisionUnpinsExactIDBeforeCapacityCheck() {
    let existing = PinnedWindow(
        bundleID: "com.example.editor",
        windowTitle: "Document A",
        appDisplayName: "Editor",
        cgWindowID: 42
    )
    let candidate = CurrentWindowPinCandidate(
        bundleID: "com.example.editor",
        windowTitle: "Document A renamed",
        appDisplayName: "Editor",
        cgWindowID: 42
    )

    #expect(
        PinnedWindowService.pinToggleDecision(
            for: candidate,
            pinnedWindows: [existing],
            maximum: 1
        ) == .unpin(existing.id)
    )
}

@Test
func currentWindowPinDecisionDoesNotConfuseTwoWindowsFromTheSameApp() {
    let first = PinnedWindow(
        bundleID: "com.example.editor",
        windowTitle: "Document A",
        appDisplayName: "Editor",
        cgWindowID: 41
    )
    let candidate = CurrentWindowPinCandidate(
        bundleID: "com.example.editor",
        windowTitle: "Document B",
        appDisplayName: "Editor",
        cgWindowID: 42
    )

    #expect(
        PinnedWindowService.pinToggleDecision(
            for: candidate,
            pinnedWindows: [first],
            maximum: 10
        ) == .pin
    )
}

@Test
func currentWindowPinDecisionFallsBackToBundleAndTitleWhenWindowIDIsUnavailable() {
    let existing = PinnedWindow(
        bundleID: "com.example.browser",
        windowTitle: "Research",
        appDisplayName: "Browser",
        cgWindowID: 0
    )
    let candidate = CurrentWindowPinCandidate(
        bundleID: "com.example.browser",
        windowTitle: "Research",
        appDisplayName: "Browser",
        cgWindowID: 0
    )

    #expect(
        PinnedWindowService.pinToggleDecision(
            for: candidate,
            pinnedWindows: [existing],
            maximum: 10
        ) == .unpin(existing.id)
    )
}

@Test
func currentWindowPinDecisionReportsCapacityOnlyForANewWindow() {
    let existing = PinnedWindow(
        bundleID: "com.example.editor",
        windowTitle: "Document A",
        appDisplayName: "Editor",
        cgWindowID: 41
    )
    let candidate = CurrentWindowPinCandidate(
        bundleID: "com.example.browser",
        windowTitle: "Research",
        appDisplayName: "Browser",
        cgWindowID: 84
    )

    #expect(
        PinnedWindowService.pinToggleDecision(
            for: candidate,
            pinnedWindows: [existing],
            maximum: 1
        ) == .maximumReached(1)
    )
}

@Test
func exactPinnedWindowIDNeverFallsBackToASimilarlyNamedWindow() {
    let decision = PinnedWindowService.pinnedWindowMatchDecision(
        windowIDs: [41, 42],
        titles: ["Document A", "Document B"],
        expectedWindowID: 99,
        titleHint: "Document A",
        allowsTitleFallback: false
    )

    #expect(decision == .unavailable)
}

@Test
func IDLessPinnedWindowRequiresAUniqueNonEmptyTitleMatch() {
    #expect(
        PinnedWindowService.pinnedWindowMatchDecision(
            windowIDs: [0, 0],
            titles: ["Research", "Research"],
            expectedWindowID: 0,
            titleHint: "Research",
            allowsTitleFallback: true
        ) == .ambiguous
    )
    #expect(
        PinnedWindowService.pinnedWindowMatchDecision(
            windowIDs: [0],
            titles: ["Research"],
            expectedWindowID: 0,
            titleHint: "   ",
            allowsTitleFallback: true
        ) == .unavailable
    )
    #expect(
        PinnedWindowService.pinnedWindowMatchDecision(
            windowIDs: [0, 0],
            titles: ["Inbox", "Research"],
            expectedWindowID: 0,
            titleHint: "Research",
            allowsTitleFallback: true
        ) == .match(1)
    )
}

@Test
func recallResultActivatesOnlyAnExactFocusedCGVisibleWindowOnTargetDisplay() {
    let observation = PinnedWindowRecallObservation(
        applicationActive: true,
        exactWindowFocused: true,
        exactWindowVisible: true,
        exactWindowOnTargetDisplay: true,
        applicationHasVisibleWindow: true
    )

    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: false
        ) == .activated
    )
}

@Test
func recallResultDoesNotTreatAnAXOnlyWindowAsActivatedWhenCGStillHidesIt() {
    // The exact AX element exists and is focused, but its ID is absent from the
    // on-screen CG window list. This is the normal cross-Space waiting state,
    // not proof that the user can see the window.
    let observation = PinnedWindowRecallObservation(
        applicationActive: true,
        exactWindowFocused: true,
        exactWindowVisible: false,
        exactWindowOnTargetDisplay: true,
        applicationHasVisibleWindow: false
    )

    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: false
        ) == nil
    )
    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: true
        ) == .applicationHasNoVisibleWindow
    )
}

@Test
func recallResultWaitsForTheDeadlineBeforeAcceptingApplicationOnlyFallback() {
    let observation = PinnedWindowRecallObservation(
        applicationActive: true,
        exactWindowFocused: false,
        exactWindowVisible: false,
        exactWindowOnTargetDisplay: false,
        applicationHasVisibleWindow: true
    )

    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: false
        ) == nil
    )
}

@Test
func recallResultReportsAnExactWindowRevealedOnItsOriginalDisplay() {
    let observation = PinnedWindowRecallObservation(
        applicationActive: true,
        exactWindowFocused: true,
        exactWindowVisible: true,
        exactWindowOnTargetDisplay: false,
        applicationHasVisibleWindow: true
    )

    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: false
        ) == .revealedOnOriginalDisplay
    )
}

@Test
func recallResultReportsApplicationOnlySuccessAfterTheDeadline() {
    let observation = PinnedWindowRecallObservation(
        applicationActive: true,
        exactWindowFocused: false,
        exactWindowVisible: false,
        exactWindowOnTargetDisplay: false,
        applicationHasVisibleWindow: true
    )

    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: true
        ) == .applicationOpened
    )
}

@Test
func recallResultDoesNotMasqueradeAnActiveApplicationWithoutWindowsAsOpened() {
    let observation = PinnedWindowRecallObservation(
        applicationActive: true,
        exactWindowFocused: false,
        exactWindowVisible: false,
        exactWindowOnTargetDisplay: false,
        applicationHasVisibleWindow: false
    )

    #expect(
        PinnedWindowService.recallResult(
            observation,
            deadlineExpired: true
        ) == .applicationHasNoVisibleWindow
    )
}

@Test
func recalledWindowMovesOnlyWhenInitiallyOnScreenAndNotNativeFullScreen() {
    #expect(
        PinnedWindowService.shouldMoveRecalledWindow(
            wasOnScreen: true,
            isNativeFullScreen: false
        )
    )

    // A hidden or cross-Space window is absent from the initial on-screen CG
    // set. AX position writes must not be mistaken for a Space transition.
    #expect(
        !PinnedWindowService.shouldMoveRecalledWindow(
            wasOnScreen: false,
            isNativeFullScreen: false
        )
    )

    #expect(
        !PinnedWindowService.shouldMoveRecalledWindow(
            wasOnScreen: true,
            isNativeFullScreen: true
        )
    )
}

@Test
func exactNonzeroWindowIDMatchesEvenWhenItsTitleIsEmpty() {
    #expect(
        PinnedWindowService.pinnedWindowMatchDecision(
            windowIDs: [41, 42],
            titles: ["Other", ""],
            expectedWindowID: 42,
            titleHint: "",
            allowsTitleFallback: false
        ) == .match(1)
    )
}

@Test
func recallCompletionIsDeliveredOnceEvenWhenLaunchCallbackArrivesAfterDeadline() {
    let context = PinnedWindowService.RecallContext(
        generation: 1, targetDisplayID: nil, initiallyVisibleIDs: []
    )
    var results: [PinnedWindowActivationResult] = []
    context.complete(.unavailable) { results.append($0) }
    context.complete(.activated) { results.append($0) }
    #expect(context.finished)
    #expect(results == [.unavailable])
}

@Test
func recallCancellationCannotBeOverwrittenByALateSuccess() {
    let context = PinnedWindowService.RecallContext(
        generation: 1, targetDisplayID: nil, initiallyVisibleIDs: []
    )
    var results: [PinnedWindowActivationResult] = []
    context.complete(.cancelled) { results.append($0) }
    context.complete(.applicationOpened) { results.append($0) }
    #expect(results == [.cancelled])
}

@Test
func fallbackRecallPreservesTheTargetApplicationInsteadOfRestoringThePreviousApp() {
    #expect(PinnedWindowActivationResult.activated.preservesTargetApplication)
    #expect(PinnedWindowActivationResult.revealedOnOriginalDisplay.preservesTargetApplication)
    #expect(PinnedWindowActivationResult.applicationOpened.preservesTargetApplication)
    #expect(PinnedWindowActivationResult.applicationHasNoVisibleWindow.preservesTargetApplication)
    #expect(!PinnedWindowActivationResult.unavailable.preservesTargetApplication)
}

@Test
func recallDoesNotReportSuccessWhenTargetApplicationIsNotActive() {
    let observation = PinnedWindowRecallObservation(
        applicationActive: false, exactWindowFocused: true, exactWindowVisible: true,
        exactWindowOnTargetDisplay: true, applicationHasVisibleWindow: true
    )
    #expect(PinnedWindowService.recallResult(observation, deadlineExpired: false) == nil)
    #expect(PinnedWindowService.recallResult(observation, deadlineExpired: true) == .unavailable)
}
