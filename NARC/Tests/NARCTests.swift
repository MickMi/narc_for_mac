import Testing
import Cocoa
@testable import NARC

// MARK: - WindowLayoutState Tests
// Note: These tests require a running display (NSScreen.main).
// They pass when run from Xcode or `swift test` on a machine with a display,
// but may crash in headless CI. The ScreenNavigator tests below are pure logic.

@Test(.enabled(if: NSScreen.screens.count > 0))
func stateRecordsAndDetectsCrossScreen() async throws {
    let state = WindowLayoutState.shared
    let fakeWindowID: CGWindowID = 99999
    let screen = NSScreen.main!

    // Ensure clean state
    state.invalidate(windowID: fakeWindowID)

    // First press: no cross-screen (no prior state)
    #expect(!state.shouldCrossScreen(windowID: fakeWindowID, layout: .leftHalf, screen: screen))

    // Record the layout
    state.record(windowID: fakeWindowID, layout: .leftHalf, screen: screen)

    // Second press within TTL: should cross screen
    #expect(state.shouldCrossScreen(windowID: fakeWindowID, layout: .leftHalf, screen: screen))

    // Different layout: should NOT cross screen
    #expect(!state.shouldCrossScreen(windowID: fakeWindowID, layout: .rightHalf, screen: screen))

    // Clean up
    state.invalidate(windowID: fakeWindowID)
}

@Test(.enabled(if: NSScreen.screens.count > 0))
func stateInvalidatesCorrectly() async throws {
    let state = WindowLayoutState.shared
    let fakeWindowID: CGWindowID = 99998

    // Use screens.first which is safer in concurrent test environments
    guard let screen = NSScreen.screens.first else { return }

    state.record(windowID: fakeWindowID, layout: .fullScreen, screen: screen)
    #expect(state.shouldCrossScreen(windowID: fakeWindowID, layout: .fullScreen, screen: screen))

    state.invalidate(windowID: fakeWindowID)
    #expect(!state.shouldCrossScreen(windowID: fakeWindowID, layout: .fullScreen, screen: screen))
}

// MARK: - ScreenNavigator Tests

@Test func crossScreenEntryLayoutFlipsDirection() async throws {
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .leftHalf) == .rightHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .rightHalf) == .leftHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .topHalf) == .bottomHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .bottomHalf) == .topHalf)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .topLeft) == .topRight)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .topRight) == .topLeft)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .bottomLeft) == .bottomRight)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .bottomRight) == .bottomLeft)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .center) == .center)
    #expect(ScreenNavigator.crossScreenEntryLayout(for: .fullScreen) == .fullScreen)
}

@Test func fullScreenAndCenterHaveNoCrossScreenEdges() async throws {
    #expect(ScreenNavigator.crossScreenEdges(for: .fullScreen).isEmpty)
    #expect(ScreenNavigator.crossScreenEdges(for: .center).isEmpty)
}

@Test func directionalLayoutsHaveCorrectEdges() async throws {
    #expect(ScreenNavigator.crossScreenEdges(for: .leftHalf) == [.left])
    #expect(ScreenNavigator.crossScreenEdges(for: .rightHalf) == [.right])
    #expect(ScreenNavigator.crossScreenEdges(for: .topHalf) == [.top])
    #expect(ScreenNavigator.crossScreenEdges(for: .bottomHalf) == [.bottom])
}
