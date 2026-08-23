import Testing
@testable import NARC

@Test
func onboardingAppearsBeforeTheUserCompletesIt() {
    #expect(
        OnboardingPresentationPolicy.shouldPresent(hasCompleted: false)
    )
}

@Test
func onboardingStaysHiddenAfterCompletion() {
    #expect(
        !OnboardingPresentationPolicy.shouldPresent(hasCompleted: true)
    )
}

@Test
func userCanForceTheGuideToOpenAgain() {
    #expect(
        OnboardingPresentationPolicy.shouldPresent(
            hasCompleted: true,
            force: true
        )
    )
}
