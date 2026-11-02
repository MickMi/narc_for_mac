import AppKit
import LocalAuthentication
import Security
import SwiftUI
import Testing
@testable import NARC

private final class RestorablePreviewSecretStore: InstantQuestionSecretStore, @unchecked Sendable {
    var key: String? = "fixture-only"
    var silentError: Error?
    var silentReads = 0
    var interactiveReads = 0
    func containsValue(for account: String) throws -> Bool { key != nil }
    func value(for account: String) throws -> String? { interactiveReads += 1; return key }
    func valueWithoutInteraction(for account: String) throws -> String? {
        silentReads += 1
        if let silentError { throw silentError }
        return key
    }
    func set(_ value: String, for account: String) throws { key = value }
    func removeValue(for account: String) throws { key = nil }
}

@Test @MainActor func credentialConsentedRestartRestoresOnceWithoutInteractiveRead() async throws {
    let suite = "narc-restore-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RestorablePreviewSecretStore()
    let first = InstantQuestionCredentialManager(secretStore: store, defaults: defaults)
    await first.restoreAccessIfConsented()
    #expect(store.silentReads == 0 && store.interactiveReads == 0)
    #expect(!first.isReady)
    #expect(await first.authorizeRead())
    #expect(store.interactiveReads == 1)
    let restarted = InstantQuestionCredentialManager(secretStore: store, defaults: defaults)
    #expect(!restarted.isReady)
    await restarted.restoreAccessIfConsented()
    await restarted.restoreAccessIfConsented()
    #expect(restarted.isReady)
    #expect(store.silentReads == 1 && store.interactiveReads == 1)
    #expect(try restarted.credentials().deepSeekAPIKey == "fixture-only")
    #expect(restarted.removeDeepSeekKey())
    #expect(!defaults.bool(forKey: InstantQuestionCredentialManager.automaticReadConsentKey))
}

@Test @MainActor func credentialSilentFailureNeedsExplicitActionAndNeverFallsBackToPrompt() async throws {
    let suite = "narc-locked-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: InstantQuestionCredentialManager.automaticReadConsentKey)
    let store = RestorablePreviewSecretStore()
    store.silentError = InstantQuestionCredentialFailure.keychain(errSecInteractionNotAllowed)
    let manager = InstantQuestionCredentialManager(secretStore: store, defaults: defaults)
    await manager.restoreAccessIfConsented()
    await manager.restoreAccessIfConsented()
    #expect(store.silentReads == 1 && store.interactiveReads == 0)
    #expect(!manager.isReady && !manager.isAuthorizing)
    #expect(manager.lastError != nil)
    #expect(throws: InstantQuestionCredentialFailure.authorizationRequired) { _ = try manager.credentials() }
    #expect(await manager.authorizeRead())
    #expect(store.interactiveReads == 1 && manager.isReady)
}

@Test @MainActor func credentialSavingConsentsButMissingSecretCannotBecomeReady() async throws {
    let suite = "narc-save-restore-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RestorablePreviewSecretStore()
    let first = InstantQuestionCredentialManager(secretStore: store, defaults: defaults)
    #expect(first.saveDeepSeekKey("fixture-only"))
    let restarted = InstantQuestionCredentialManager(secretStore: store, defaults: defaults)
    store.key = nil
    await restarted.restoreAccessIfConsented()
    #expect(!restarted.isReady && !restarted.hasDeepSeekKey)
    #expect(store.interactiveReads == 0)
}

@Test func credentialSilentSecretQueryForbidsAuthenticationUI() throws {
    let query = KeychainInstantQuestionSecretStore.readQuery(for: "fixture", secret: true, allowInteraction: false)
    #expect(query[kSecReturnData as String] as? Bool == true)
    let context = try #require(query[kSecUseAuthenticationContext as String] as? LAContext)
    #expect(context.interactionNotAllowed)
}

private final class NoRequestPreviewAnswering: InstantQuestionAnswering, @unchecked Sendable {
    var requests = 0
    func answer(messages: [InstantQuestionMessage], attachment: InstantQuestionImageAttachment?,
                credentials: InstantQuestionCredentials) async throws -> InstantQuestionReply {
        requests += 1
        return InstantQuestionReply(answer: "fixture", sources: [])
    }
}

@Test @MainActor func credentialQuestionWindowRestoresOnOpeningWithoutAIRequest() async throws {
    _ = NSApplication.shared
    let suite = "narc-window-restore-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: InstantQuestionCredentialManager.automaticReadConsentKey)
    let secrets = RestorablePreviewSecretStore()
    let manager = InstantQuestionCredentialManager(secretStore: secrets, defaults: defaults)
    let service = NoRequestPreviewAnswering()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = InstantQuestionStore(storageURL: directory.appendingPathComponent("questions.json"))
    let controller = InstantQuestionController(credentials: manager, store: store, service: service, preferences: defaults)
    let window = InstantQuestionWindow(controller: controller, store: store, onOpenPreferences: {}, onboardingDefaults: defaults)
    defer { window.close() }
    window.present()
    for _ in 0..<20 {
        if manager.isReady { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(manager.isReady)
    #expect(secrets.silentReads == 1 && secrets.interactiveReads == 0)
    #expect(service.requests == 0)
    #expect(!FileManager.default.fileExists(atPath: store.storageURL.path))
}

@Test @MainActor func featureIntroductionDismissalPersistsIndependentlyOfOtherFeatures() throws {
    let suite = "narc-feature-progress-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    for topic in HelpTopic.allCases { #expect(OnboardingPresentationPolicy.shouldShowFeatureHint(topic, defaults: defaults)) }
    OnboardingPresentationPolicy.dismissFeatureHint(.ai, defaults: defaults)
    let reopened = try #require(UserDefaults(suiteName: suite))
    #expect(!OnboardingPresentationPolicy.shouldShowFeatureHint(.ai, defaults: reopened))
    for topic in HelpTopic.allCases where topic != .ai {
        #expect(OnboardingPresentationPolicy.shouldShowFeatureHint(topic, defaults: reopened))
    }
    #expect(!OnboardingPresentationPolicy.resolvedState(in: defaults).hasCompletedCurrentCoreFlow)
    OnboardingPresentationPolicy.markFirstCaptureCompleted(in: defaults)
    #expect(OnboardingPresentationPolicy.shouldShowFeatureHint(.windows, defaults: defaults))
}

@Test @MainActor func helpNavigationChangesReusedWindowWithoutMarkingFeaturesComplete() async throws {
    _ = NSApplication.shared
    let suite = "narc-help-jump-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let before = defaults.persistentDomain(forName: suite) ?? [:]
    let navigation = HelpCenterNavigation(.todo)
    let window = PreferencesWindow(contentSize: NSSize(width: 800, height: 560))
    defer { window.close() }
    window.contentView = NSHostingView(rootView: HelpCenterView(navigation: navigation, hotkeyService: HotkeyService(accessibilityTrustCheck: { _ in false }, defaults: defaults), onOpen: { _ in }))
    let view = try #require(window.contentView)
    func snapshot() async throws -> Data {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
    let todo = try await snapshot()
    navigation.selectedTopic = .ai
    let ai = try await snapshot()
    #expect(todo != ai)
    navigation.selectedTopic = .windows
    let windows = try await snapshot()
    #expect(ai != windows)
    #expect((defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary == before as NSDictionary)
}

/// Production SwiftUI hosted at the actual panel and minimum help-window sizes.
/// Preview data is isolated; no real Keychain, AI requests, or onboarding writes.
@Test @MainActor func userExperienceHelpAndCompactPanelPreview() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("narc-help-preview-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "narc-help-preview-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AssistantStore(storageURL: directory.appendingPathComponent("assistant.json"))
    for title in ["周五前寄出快递", "整理会议待办", "预约下周的检查"] { #expect(store.createTodo(title: title)) }
    let capture = InboxCaptureState(store: store)
    capture.hideOnboardingHintForThisSession()
    let hotkeys = HotkeyService(accessibilityTrustCheck: { _ in false }, defaults: defaults)
    let before = try Data(contentsOf: store.storageURL)
    func panel(for tab: PanelTab) -> AnyView {
        let selection = PanelSelectionState()
        selection.selectedTab = tab
        return AnyView(PanelView(appMonitor: AppMonitorService(), windowManager: WindowManagerService(),
            pinnedWindowService: PinnedWindowService(defaults: defaults), hotkeyService: hotkeys,
            assistantStore: store, inboxCaptureState: capture,
            codexCompletionService: CodexCompletionService(defaults: defaults, eventFolder: directory),
            panelSelection: selection, onClose: {}, onOpenPreferences: {}, onOpenAssistant: {},
            narcScreenProvider: { NSScreen.main }, keyboardSelection: KeyboardSelectionState(), onboardingDefaults: defaults))
    }
    let helpHotkeys = HotkeyService(accessibilityTrustCheck: { _ in true }, defaults: defaults,
        configurableHotkeyRegistrar: { _, _, slot in .success(HotkeyRegistrationToken(slotID: slot) { noErr }) },
        requiresInstalledEventHandlerForSelectedTextTodo: false, requiresInstalledEventHandlerForConfigurableHotkeys: false)
    helpHotkeys.registerConfiguredHotkeys(noAX: false)
    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        var samples: [(String, NSSize, AnyView)] = PanelTab.allCases.map {
            ($0 == .inbox ? "panel" : "panel-" + String(describing: $0.keyboardRoute),
             NSSize(width: 360, height: 480), panel(for: $0))
        }
        for topic in HelpTopic.allCases {
            samples.append(("help-" + topic.rawValue, NSSize(width: 800, height: 560), AnyView(HelpCenterView(initialTopic: topic, hotkeyService: hotkeys, onOpen: { _ in }))))
            samples.append(("help-wide-" + topic.rawValue, NSSize(width: 960, height: 720), AnyView(HelpCenterView(initialTopic: topic, hotkeyService: helpHotkeys, onOpen: { _ in }))))
            if topic != .todo {
                samples.append(("first-use-" + topic.rawValue, NSSize(width: 320, height: 110),
                                AnyView(FeatureIntroductionCard(topic: topic, defaults: defaults, onOpenHelp: { _ in }))))
            }
        }
        samples.append(("help-image-pins", NSSize(width: 728, height: 568), AnyView(HelpTutorialImagePreview(asset: .pins))))
        for (sample, size, content) in samples {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = NSHostingView(rootView: content.environment(\.colorScheme, scheme).background(Color.narcBackground))
            let view = try #require(window.contentView)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            #expect(view.fittingSize.width <= size.width, "\(sample) / \(name)")
            #expect(view.fittingSize.height <= size.height)
            if let path = ProcessInfo.processInfo.environment["NARC_HELP_PREVIEW_DIR"], path.hasPrefix("/private/tmp/") {
                let destination = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: destination.appendingPathComponent("\(sample)-\(name).png"))
            }
            window.close()
        }
    }
    #expect(try Data(contentsOf: store.storageURL) == before)
}
