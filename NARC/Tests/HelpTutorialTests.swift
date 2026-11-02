import AppKit
import SwiftUI
import Testing
@testable import NARC

@Test @MainActor func helpTutorialImagesLoadInBothThemesAndInstalledBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("help-installed-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = root.appendingPathComponent("NARC.app/Contents")
    let resources = contents.appendingPathComponent("Resources/NARC_NARC.bundle")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let plist = ["CFBundleIdentifier": "com.narc.help-test", "CFBundlePackageType": "APPL", "CFBundleExecutable": "NARC"]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contents.appendingPathComponent("Info.plist"))
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.narc.help-resources"], format: .xml, options: 0)
        .write(to: resources.appendingPathComponent("Info.plist"))
    // Populate the entire bundle before Foundation caches its resource listing.
    for asset in HelpTutorialAsset.allCases {
        for dark in [false, true] {
            let original = try #require(asset.url(dark: dark))
            try Data(contentsOf: original).write(to: resources.appendingPathComponent(original.lastPathComponent))
        }
    }
    let installed = try #require(Bundle(url: root.appendingPathComponent("NARC.app")))
    for asset in HelpTutorialAsset.allCases {
        for dark in [false, true] {
            let original = try #require(asset.url(dark: dark))
            let data = try Data(contentsOf: original)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.pixelsWide >= 640 && bitmap.pixelsHigh >= 190)
            let destination = resources.appendingPathComponent(original.lastPathComponent)
            let resolved = try #require(asset.url(dark: dark, applicationBundle: installed))
            #expect(resolved.standardizedFileURL == destination.standardizedFileURL)
            #expect(try Data(contentsOf: resolved) == data)
        }
    }
}

@Test func helpTutorialSeparatesRecallFromLayoutAndTeachesMarkFirst() {
    let steps = HelpTopic.windows.lessons
    #expect(steps.count == 2)
    #expect(steps[0].shortcut == .toggleCurrentWindowPin)
    #expect(steps[1].shortcut == .pinnedWindowSwitcher)
    if case .windowPicker = HelpTopic.windows.action.1 {} else { Issue.record("recall chapter must open the picker") }
    if case .windows = HelpTopic.layouts.action.1 {} else { Issue.record("layout chapter must open layout tools") }
    for topic in HelpTopic.allCases {
        #expect(!topic.lessons.isEmpty)
        #expect(topic.lessons.contains { $0.image != nil })
    }
}

@Test @MainActor func helpTutorialTracksRegisteredShortcutsAndImageSheetLifecycle() async throws {
    _ = NSApplication.shared
    let suite = "help-live-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hotkeys = HotkeyService(accessibilityTrustCheck: { _ in true }, defaults: defaults,
        configurableHotkeyRegistrar: { _, _, slot in .success(HotkeyRegistrationToken(slotID: slot) { noErr }) },
        requiresInstalledEventHandlerForSelectedTextTodo: false, requiresInstalledEventHandlerForConfigurableHotkeys: false)
    let navigation = HelpCenterNavigation(.windows)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = NSHostingView(rootView: HelpCenterView(navigation: navigation, hotkeyService: hotkeys, onOpen: { _ in }))
    window.orderFront(nil)
    let view = try #require(window.contentView)
    func snapshot() async throws -> Data {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
    #expect(hotkeys.activeShortcut(for: .toggleCurrentWindowPin) == nil)
    let unavailable = try await snapshot()
    hotkeys.registerConfiguredHotkeys(noAX: false)
    #expect(hotkeys.activeShortcut(for: .toggleCurrentWindowPin) == ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultShortcut)
    let registered = try await snapshot()
    #expect(unavailable != registered)
    let custom = ConfigurableShortcut(keyCode: 15, modifiers: ConfigurableHotkeyAction.toggleCurrentWindowPin.defaultShortcut.modifiers)
    #expect(hotkeys.updateShortcut(custom, for: .toggleCurrentWindowPin) == .applied(custom))
    #expect(hotkeys.activeShortcut(for: .toggleCurrentWindowPin) == custom)
    #expect(try await snapshot() != registered)
    navigation.expandedImage = .pins
    for _ in 0..<20 {
        if !window.sheets.isEmpty { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(window.sheets.count == 1)
    navigation.expandedImage = nil
    for _ in 0..<30 {
        if window.sheets.isEmpty { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(window.sheets.isEmpty)
    navigation.expandedImage = .markResult
    try await Task.sleep(for: .milliseconds(120))
    navigation.selectedTopic = .layouts
    for _ in 0..<30 {
        if window.sheets.isEmpty { break }
        try await Task.sleep(for: .milliseconds(30))
    }
    #expect(navigation.expandedImage == nil)
    #expect(window.sheets.isEmpty)
    #expect(hotkeys.setEnabled(false, for: .layoutLeftHalf) == .applied(ConfigurableHotkeyAction.layoutLeftHalf.defaultShortcut))
    #expect(hotkeys.activeShortcut(for: .layoutLeftHalf) == nil)
    _ = try await snapshot()
    func scrollViews(in node: NSView) -> [NSScrollView] {
        let current = (node as? NSScrollView).map { [$0] } ?? []
        return current + node.subviews.flatMap { scrollViews(in: $0) }
    }
    let scroll = try #require(scrollViews(in: view).first)
    let document = try #require(scroll.documentView)
    #expect(document.bounds.height > scroll.contentView.bounds.height)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
    scroll.reflectScrolledClipView(scroll.contentView)
    #expect(scroll.contentView.bounds.minY > 0)
    navigation.selectedTopic = .windows
    _ = try await snapshot()
    #expect(scroll.contentView.bounds.minY < 1)
    #expect(!OnboardingPresentationPolicy.resolvedState(in: defaults).hasCompletedCurrentCoreFlow)
}
