import Foundation
import Testing
@testable import NARC

@Test
func legacyCompletionDoesNotSuppressCurrentOnboarding() {
    let state = OnboardingPresentationPolicy.resolvedState(
        storedVersion: nil,
        storedStageRawValue: nil,
        legacyCompleted: true
    )

    #expect(state.legacyCompletionRecorded)
    #expect(state.stage == .notStarted)
    #expect(OnboardingPresentationPolicy.shouldPresent(state: state))
}

@Test
func entrySeenIsStillInProgress() {
    let state = OnboardingPresentationPolicy.resolvedState(
        storedVersion: OnboardingPresentationPolicy.currentVersion,
        storedStageRawValue: OnboardingStage.entrySeen.rawValue,
        legacyCompleted: false
    )

    #expect(!state.hasCompletedCurrentCoreFlow)
    #expect(OnboardingPresentationPolicy.shouldPresent(state: state))
}

@Test
func firstCaptureCompletesTheCurrentCoreFlow() {
    let state = OnboardingPresentationPolicy.resolvedState(
        storedVersion: OnboardingPresentationPolicy.currentVersion,
        storedStageRawValue: OnboardingStage.firstCaptureCompleted.rawValue,
        legacyCompleted: false
    )

    #expect(state.hasCompletedCurrentCoreFlow)
    #expect(!OnboardingPresentationPolicy.shouldPresent(state: state))
}

@Test
func anOlderVersionCannotCompleteTheCurrentGuide() {
    let state = OnboardingPresentationPolicy.resolvedState(
        storedVersion: OnboardingPresentationPolicy.currentVersion - 1,
        storedStageRawValue: OnboardingStage.windowToolsIntroduced.rawValue,
        legacyCompleted: true
    )

    #expect(!state.hasCompletedCurrentCoreFlow)
    #expect(OnboardingPresentationPolicy.shouldPresent(state: state))
}

@Test
func forceAlwaysPresentsAfterCoreCompletion() {
    let state = OnboardingPresentationPolicy.resolvedState(
        storedVersion: OnboardingPresentationPolicy.currentVersion,
        storedStageRawValue: OnboardingStage.windowToolsIntroduced.rawValue,
        legacyCompleted: true
    )

    #expect(OnboardingPresentationPolicy.shouldPresent(state: state, force: true))
}

@Test
func markingEntrySeenMigratesLegacyStateWithoutCompletingTheGuide() {
    let (defaults, suiteName) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: OnboardingPresentationPolicy.legacyCompletionKey)

    OnboardingPresentationPolicy.markEntrySeen(in: defaults)

    let state = OnboardingPresentationPolicy.resolvedState(in: defaults)
    #expect(state.version == OnboardingPresentationPolicy.currentVersion)
    #expect(state.stage == .entrySeen)
    #expect(state.legacyCompletionRecorded)
    #expect(OnboardingPresentationPolicy.shouldPresent(defaults: defaults))
}

@Test
func firstCaptureAdvancesTheStageAndEntryCannotDowngradeIt() {
    let (defaults, suiteName) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    OnboardingPresentationPolicy.markEntrySeen(in: defaults)
    OnboardingPresentationPolicy.markFirstCaptureCompleted(in: defaults)
    OnboardingPresentationPolicy.markEntrySeen(in: defaults)

    let state = OnboardingPresentationPolicy.resolvedState(in: defaults)
    #expect(state.stage == .firstCaptureCompleted)
    #expect(!OnboardingPresentationPolicy.shouldPresent(defaults: defaults))
}

@Test
func windowToolsRemainASeparateLaterMilestone() {
    let (defaults, suiteName) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    OnboardingPresentationPolicy.markFirstCaptureCompleted(in: defaults)
    OnboardingPresentationPolicy.markWindowToolsIntroduced(in: defaults)

    let state = OnboardingPresentationPolicy.resolvedState(in: defaults)
    #expect(state.stage == .windowToolsIntroduced)
    #expect(state.hasCompletedCurrentCoreFlow)
}

@Test
func windowToolsCannotCompleteTheCoreFlowBeforeFirstCapture() {
    let (defaults, suiteName) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    OnboardingPresentationPolicy.markWindowToolsIntroduced(in: defaults)

    let state = OnboardingPresentationPolicy.resolvedState(in: defaults)
    #expect(state.stage == .entrySeen)
    #expect(!state.hasCompletedCurrentCoreFlow)
    #expect(OnboardingPresentationPolicy.shouldPresent(defaults: defaults))
}

@Test
@MainActor
func successfulInboxCaptureCompletesTheCurrentGuide() throws {
    let (defaults, suiteName) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-onboarding-capture-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    OnboardingPresentationPolicy.markEntrySeen(in: defaults)
    let store = AssistantStore(storageURL: directory.appendingPathComponent("assistant.json"))
    let captureState = InboxCaptureState(store: store) {
        OnboardingPresentationPolicy.markFirstCaptureCompleted(in: defaults)
    }

    captureState.updateDraft("First real capture")
    #expect(captureState.submit())
    #expect(!OnboardingPresentationPolicy.shouldPresent(defaults: defaults))
}

@Test
@MainActor
func rejectedInboxCaptureDoesNotCompleteTheCurrentGuide() throws {
    let (defaults, suiteName) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-onboarding-rejected-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    OnboardingPresentationPolicy.markEntrySeen(in: defaults)
    let store = AssistantStore(storageURL: directory.appendingPathComponent("assistant.json"))
    let captureState = InboxCaptureState(store: store) {
        OnboardingPresentationPolicy.markFirstCaptureCompleted(in: defaults)
    }

    captureState.updateDraft("   ")
    #expect(!captureState.submit())
    #expect(OnboardingPresentationPolicy.shouldPresent(defaults: defaults))
}

private func isolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "OnboardingTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
