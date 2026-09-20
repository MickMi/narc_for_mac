import AppKit
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
