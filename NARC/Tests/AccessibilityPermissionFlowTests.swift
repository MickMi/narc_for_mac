import Testing
@testable import NARC

@Test
func accessibilityGuidanceMakesTheNoRestartPathExplicit() {
    let guidance = AccessibilityPermissionGuidance(
        shortcut: "⌃⌥←",
        appPath: "/Users/example/Applications/NARC.app"
    )

    #expect(guidance.explanation.contains("无需重启"))
    #expect(guidance.explanation.contains("打开系统设置"))
    #expect(guidance.explanation.contains("⌃⌥←"))
    #expect(guidance.ready.contains("无需重启"))
    #expect(guidance.ready.contains("回到要操作的窗口"))
    #expect(guidance.ready.contains("⌃⌥←"))
    #expect(guidance.recovery.contains("删除旧 NARC 条目"))
    #expect(guidance.recovery.contains("/Users/example/Applications/NARC.app"))
    #expect(guidance.recovery.contains("仍未生效时再退出并重开"))
}

@Test
func selectedTextGuidanceDisclosesMomentarySelectionReadingWithoutClipboardAccess() {
    let guidance = AccessibilityPermissionGuidance(
        shortcut: "⌃⌥T",
        capability: .selectedTextTodo,
        appPath: "/Users/example/Applications/NARC.app"
    )

    #expect(guidance.alertTitle.contains("划词创建 Todo"))
    #expect(guidance.explanation.contains("标准文本选区"))
    #expect(guidance.explanation.contains("不会持续监听"))
    #expect(guidance.explanation.contains("不会读取剪贴板"))
    #expect(guidance.ready.contains("重新确认选区"))
    #expect(guidance.ready.contains("⌃⌥T"))
}

@Test
func permissionGrantCanResolveAnExplanationThatIsStillOpen() {
    var flow = AccessibilityPermissionFlow()
    let guidance = AccessibilityPermissionGuidance(shortcut: "⌃⌥P")

    #expect(flow.responseToBlockedAction(guidance) == .explain)
    #expect(flow.isExplaining)
    #expect(flow.currentGuidance == guidance)
    #expect(flow.takeGuidanceAfterGrant() == guidance)
    #expect(flow.currentGuidance == nil)
}

@Test
func cancellingTheExplanationReturnsTheFlowToIdle() {
    var flow = AccessibilityPermissionFlow()
    let guidance = AccessibilityPermissionGuidance(shortcut: "⌃⌥P")

    #expect(flow.responseToBlockedAction(guidance) == .explain)
    flow.cancelExplanation()

    #expect(flow.currentGuidance == nil)
    #expect(flow.responseToBlockedAction(guidance) == .explain)
}

@Test
func deniedPermissionRetryUsesSettingsInsteadOfStackingAnotherPrompt() {
    var flow = AccessibilityPermissionFlow()
    let first = AccessibilityPermissionGuidance(shortcut: "⌃⌥←")
    let retry = AccessibilityPermissionGuidance(shortcut: "⌃⌥P")

    flow.beginAuthorization(with: first)

    #expect(flow.responseToBlockedAction(retry) == .openSettings)
    #expect(flow.currentGuidance == retry)
    #expect(flow.takeGuidanceAfterGrant() == retry)
    #expect(flow.currentGuidance == nil)
}

@Test
func successfulWindowActionConsumesAnyStaleReadyInstruction() {
    var flow = AccessibilityPermissionFlow()
    let guidance = AccessibilityPermissionGuidance(shortcut: "⌃⌥→")

    flow.beginAuthorization(with: guidance)
    flow.consumeForSuccessfulWindowAction()

    #expect(flow.currentGuidance == nil)
    #expect(flow.takeGuidanceAfterGrant() == nil)
}

@Test
func onboardingGuidanceConfirmsImmediateUseWithoutInventingARetryShortcut() {
    let guidance = AccessibilityPermissionGuidance.general

    #expect(guidance.explanation.contains("无需重启"))
    #expect(guidance.ready.contains("现在可以直接使用"))
    #expect(!guidance.ready.contains("再按一次"))
}

@Test
@MainActor
func accessibilityRequestUsesOneNativePromptWithoutAlsoOpeningSettings() {
    var promptValues: [Bool] = []
    var settingsOpenCount = 0
    let service = HotkeyService(
        accessibilityTrustCheck: { prompt in
            promptValues.append(prompt)
            return false
        },
        accessibilitySettingsOpener: {
            settingsOpenCount += 1
        },
        permissionPollInterval: 60
    )

    #expect(!service.requestAccessibilityPermission())
    #expect(promptValues == [true])
    #expect(settingsOpenCount == 0)
    #expect(service.isMonitoringAccessibilityPermission)

    service.openAccessibilitySettings()
    #expect(settingsOpenCount == 1)
}

@Test
@MainActor
func accessibilityGrantIsDetectedWithoutRestartAndEmittedOnce() {
    var trusted = false
    var grantCount = 0
    let service = HotkeyService(
        accessibilityTrustCheck: { _ in trusted },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60
    )
    service.onAccessibilityPermissionGranted = {
        grantCount += 1
    }

    #expect(!service.requestAccessibilityPermission())
    #expect(service.isMonitoringAccessibilityPermission)

    trusted = true
    #expect(service.pollAccessibilityPermissionOnce())
    #expect(service.isAccessibilityGranted)
    #expect(!service.isMonitoringAccessibilityPermission)
    #expect(grantCount == 1)

    #expect(service.pollAccessibilityPermissionOnce())
    #expect(grantCount == 1)
}

@Test
@MainActor
func revokedAccessibilityCanStartMonitoringAndRecoverAgain() {
    var trusted = true
    let service = HotkeyService(
        accessibilityTrustCheck: { _ in trusted },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60
    )

    #expect(service.checkAccessibilityPermission(prompt: false))
    #expect(service.isAccessibilityGranted)

    var regrantCount = 0
    service.onAccessibilityPermissionGranted = {
        regrantCount += 1
    }

    trusted = false
    #expect(!service.checkAccessibilityPermission(prompt: false))
    #expect(!service.isAccessibilityGranted)
    #expect(!service.requestAccessibilityPermission())
    #expect(service.isMonitoringAccessibilityPermission)

    trusted = true
    #expect(service.pollAccessibilityPermissionOnce())
    #expect(service.isAccessibilityGranted)
    #expect(!service.isMonitoringAccessibilityPermission)
    #expect(regrantCount == 1)
}

@Test
@MainActor
func prolongedDeniedPermissionReportsRecoveryOnceAndKeepsPolling() {
    var recoveryCount = 0
    let service = HotkeyService(
        accessibilityTrustCheck: { _ in false },
        accessibilitySettingsOpener: {},
        permissionPollInterval: 60,
        permissionRecoveryPollLimit: 2
    )
    service.onAccessibilityPermissionStillDenied = {
        recoveryCount += 1
    }

    #expect(!service.requestAccessibilityPermission())
    #expect(service.isMonitoringAccessibilityPermission)
    #expect(!service.pollAccessibilityPermissionOnce())
    #expect(recoveryCount == 0)
    #expect(!service.pollAccessibilityPermissionOnce())
    #expect(recoveryCount == 1)
    #expect(service.isMonitoringAccessibilityPermission)
    #expect(!service.pollAccessibilityPermissionOnce())
    #expect(recoveryCount == 1)

    #expect(!service.requestAccessibilityPermission())
    #expect(!service.pollAccessibilityPermissionOnce())
    #expect(!service.pollAccessibilityPermissionOnce())
    #expect(recoveryCount == 2)
}
