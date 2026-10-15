import AppKit
import SwiftUI
import Testing
@testable import NARC

@Test
func pinnedSwitcherDigitsActivatePinsImmediatelyWithoutIntentGate() {
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 18,
            selectedIndex: -1,
            itemCount: 4
        ) == .activate(0)
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 21,
            selectedIndex: -1,
            itemCount: 4
        ) == .activate(3)
    )
}

@Test
func pinnedSwitcherNavigationClampsAndReturnActivatesSelection() {
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 125,
            selectedIndex: -1,
            itemCount: 3
        ) == .select(0)
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 125,
            selectedIndex: 2,
            itemCount: 3
        ) == .select(2)
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 126,
            selectedIndex: 0,
            itemCount: 3
        ) == .select(0)
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 36,
            selectedIndex: 1,
            itemCount: 3
        ) == .activate(1)
    )
}

@Test
func pinnedSwitcherOnlyAssignsDirectDigitsOneThroughNine() {
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 25,
            selectedIndex: 0,
            itemCount: 10
        ) == .activate(8)
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 29,
            selectedIndex: 0,
            itemCount: 10
        ) == .passThrough
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 125,
            selectedIndex: 8,
            itemCount: 10
        ) == .select(9)
    )
}

@Test
func pinnedSwitcherEscapeAlwaysDismissesAndInvalidDigitsDoNotActivate() {
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 53,
            selectedIndex: -1,
            itemCount: 0
        ) == .dismiss
    )
    #expect(
        PinnedWindowSwitcherKeyboard.command(
            for: 20,
            selectedIndex: 0,
            itemCount: 2
        ) == .passThrough
    )
}

@Test
@MainActor
func pinnedSwitcherSelectionStartsAtFirstItemAndClampsAfterRemoval() {
    let state = PinnedWindowSwitcherSelectionState()

    state.reset(itemCount: 3)
    #expect(state.selectedIndex == 0)

    state.selectedIndex = 2
    state.clamp(itemCount: 1)
    #expect(state.selectedIndex == 0)

    state.clamp(itemCount: 0)
    #expect(state.selectedIndex == -1)
}

@Test
func pinnedSwitcherFrameStaysInsideNegativeCoordinateDisplay() {
    let visibleFrame = NSRect(x: -1728, y: 24, width: 1728, height: 1056)
    let frame = PinnedWindowSwitcherLayout.frame(itemCount: 10, in: visibleFrame)

    #expect(frame.minX >= visibleFrame.minX)
    #expect(frame.maxX <= visibleFrame.maxX)
    #expect(frame.minY >= visibleFrame.minY)
    #expect(frame.maxY <= visibleFrame.maxY)
    #expect(frame.width == PinnedWindowSwitcherLayout.width)
    #expect(frame.height == PinnedWindowSwitcherLayout.maximumHeight)
}

@Test
@MainActor
func pinnedSwitcherRendersReorderControlsWithinThePanel() async throws {
    _ = NSApplication.shared
    let suite = "PinnedSwitcherPreview.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pins = PinnedWindowService(defaults: defaults, startsPolling: false)
    pins.pinnedWindows = [
        PinnedWindow(bundleID: "com.apple.TextEdit", windowTitle: "ChatGPT 主窗口", appDisplayName: "ChatGPT"),
        PinnedWindow(bundleID: "com.apple.TextEdit", windowTitle: "微信会话窗口", appDisplayName: "微信"),
        PinnedWindow(bundleID: "com.apple.TextEdit", windowTitle: "待办窗口", appDisplayName: "待办"),
    ]
    let hotkeys = HotkeyService(accessibilityTrustCheck: { _ in false }, defaults: defaults)
    hotkeys.updatePinnedWindowSlotCount(3)
    let selection = PinnedWindowSwitcherSelectionState()
    selection.reset(itemCount: 3)
    let size = PinnedWindowSwitcherLayout.panelSize(itemCount: 3)

    for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
        let content = PinnedWindowSwitcherView(
            pinnedWindowService: pins,
            hotkeyService: hotkeys,
            selection: selection,
            onActivate: { _ in },
            onClose: {},
            onItemCountChanged: { _ in }
        )
        let window = TodoNudgeWindow(rootView: content.environment(\.colorScheme, scheme))
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        #expect(view.bounds.width == size.width)
        #expect(view.bounds.height == size.height)
        if let path = ProcessInfo.processInfo.environment["NARC_PIN_SNAPSHOT_DIR"],
           path.hasPrefix("/private/tmp/") {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path)
                .appendingPathComponent("pinned-slots-\(name).png"))
        }
        window.close()
    }
}
