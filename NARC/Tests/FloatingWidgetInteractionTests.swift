import Cocoa
import Testing
@testable import NARC

@Test
func deliberateLongPressWithoutMovementStillCountsAsATap() {
    #expect(
        WidgetPointerInteractionPolicy.isTap(
            duration: 0.8,
            distance: 0,
            isDragging: false
        )
    )
}

@Test
func movementBelowDragThresholdStillCountsAsATap() {
    #expect(
        WidgetPointerInteractionPolicy.isTap(
            duration: 0.8,
            distance: WidgetPointerInteractionPolicy.dragThreshold - 0.1,
            isDragging: false
        )
    )
}

@Test
func draggingNeverCountsAsATap() {
    #expect(
        !WidgetPointerInteractionPolicy.isTap(
            duration: 0.1,
            distance: WidgetPointerInteractionPolicy.dragThreshold,
            isDragging: true
        )
    )
}

@Test
func mouseLocationSelectsNegativeCoordinateDisplay() {
    let screens = [
        NSRect(x: 0, y: 0, width: 1512, height: 982),
        NSRect(x: -1920, y: -120, width: 1920, height: 1080),
    ]

    #expect(
        FloatingWidgetPlacement.targetScreenIndex(
            containing: NSPoint(x: -900, y: 500),
            screenFrames: screens
        ) == 1
    )
}

@Test
func mouseLocationUsesWholeScreenInsteadOfVisibleFrame() {
    let fullScreen = NSRect(x: 0, y: 0, width: 1512, height: 982)

    #expect(
        FloatingWidgetPlacement.targetScreenIndex(
            containing: NSPoint(x: 700, y: 975),
            screenFrames: [fullScreen]
        ) == 0
    )
}

@Test
func summonPreservesValidManualPositionOnTargetScreen() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1512, height: 944)
    let currentFrame = NSRect(x: 500, y: 300, width: 128, height: 128)

    let result = FloatingWidgetPlacement.summonedFrame(
        currentFrame: currentFrame,
        targetVisibleFrame: visibleFrame,
        visibleSize: 48
    )

    #expect(result == currentFrame)
}

@Test
func summonMovesWidgetToSafeAnchorOnTargetScreen() {
    let target = NSRect(x: -1920, y: -120, width: 1920, height: 1040)
    let currentFrame = NSRect(x: 1200, y: 200, width: 128, height: 128)

    let result = FloatingWidgetPlacement.summonedFrame(
        currentFrame: currentFrame,
        targetVisibleFrame: target,
        visibleSize: 48
    )
    let visibleWidget = FloatingWidgetPlacement.visibleWidgetRect(
        in: result,
        visibleSize: 48
    )

    #expect(visibleWidget.maxX == target.maxX - 40)
    #expect(visibleWidget.minY == target.minY + 100)
    #expect(target.contains(NSPoint(x: visibleWidget.minX, y: visibleWidget.minY)))
    #expect(target.contains(NSPoint(x: visibleWidget.maxX - 0.1, y: visibleWidget.maxY - 0.1)))
}

@Test(arguments: [CGFloat(40), CGFloat(48), CGFloat(58)])
func everyWidgetSizeStaysVisibleAfterCrossScreenSummon(visibleSize: CGFloat) {
    let target = NSRect(x: 1512, y: 40, width: 1280, height: 720)
    let canvasSize = visibleSize + 80
    let currentFrame = NSRect(x: 100, y: 100, width: canvasSize, height: canvasSize)

    let result = FloatingWidgetPlacement.summonedFrame(
        currentFrame: currentFrame,
        targetVisibleFrame: target,
        visibleSize: visibleSize
    )
    let visibleWidget = FloatingWidgetPlacement.visibleWidgetRect(
        in: result,
        visibleSize: visibleSize
    )

    #expect(visibleWidget.minX >= target.minX)
    #expect(visibleWidget.maxX <= target.maxX)
    #expect(visibleWidget.minY >= target.minY)
    #expect(visibleWidget.maxY <= target.maxY)
}

@Test
func summonClampsPartiallyHiddenWidgetOnTargetScreen() {
    let target = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let currentFrame = NSRect(x: 1360, y: 300, width: 128, height: 128)

    let result = FloatingWidgetPlacement.summonedFrame(
        currentFrame: currentFrame,
        targetVisibleFrame: target,
        visibleSize: 48
    )
    let visibleWidget = FloatingWidgetPlacement.visibleWidgetRect(
        in: result,
        visibleSize: 48
    )

    #expect(visibleWidget.maxX == target.maxX - FloatingWidgetPlacement.safeEdgeMargin)
}

@Test
func changingFromSmallToLargeKeepsWidgetVisible() {
    let target = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let smallFrame = FloatingWidgetPlacement.clampedFrame(
        NSRect(x: 1360, y: 300, width: 120, height: 120),
        to: target,
        visibleSize: 40
    )

    let largeFrame = FloatingWidgetPlacement.resizedFrame(
        currentFrame: smallFrame,
        newWindowSize: NSSize(width: 138, height: 138),
        newVisibleSize: 58,
        targetVisibleFrame: target
    )
    let visibleWidget = FloatingWidgetPlacement.visibleWidgetRect(
        in: largeFrame,
        visibleSize: 58
    )

    #expect(visibleWidget.maxX == target.maxX - FloatingWidgetPlacement.safeEdgeMargin)
    #expect(visibleWidget.minX >= target.minX)
    #expect(visibleWidget.minY >= target.minY)
    #expect(visibleWidget.maxY <= target.maxY)
}

@Test
func panelPlacementKeepsPanelInsideNegativeCoordinateDisplay() {
    let target = NSRect(x: -1920, y: -120, width: 1920, height: 1040)
    let widgetFrame = NSRect(x: -128, y: 752, width: 128, height: 128)

    let panel = FloatingPanelPlacement.frame(
        adjacentTo: widgetFrame,
        visibleWidgetSize: 48,
        panelSize: NSSize(width: 320, height: 420),
        targetVisibleFrame: target
    )

    #expect(panel.minX >= target.minX)
    #expect(panel.maxX <= target.maxX)
    #expect(panel.minY >= target.minY)
    #expect(panel.maxY <= target.maxY)
}

@Test
func repeatedSummonKeepsVisiblePanelOpen() {
    #expect(
        FloatingPanelSummonAction.resolve(
            panelIsVisible: true,
            panelIsOnTargetScreen: true
        ) == .keepVisible
    )
}

@Test
func crossScreenSummonReplacesPanelWithoutClosingTheFlow() {
    #expect(
        FloatingPanelSummonAction.resolve(
            panelIsVisible: true,
            panelIsOnTargetScreen: false
        ) == .replace
    )
    #expect(
        FloatingPanelSummonAction.resolve(
            panelIsVisible: false,
            panelIsOnTargetScreen: false
        ) == .present
    )
}

@Test
func floatingWidgetKeepsUnreadUncertaintyVisible() {
    #expect(
        FloatingWidgetState.resolve(
            badgeCount: 14,
            isBadgeStatusUncertain: true,
            isDragging: false
        ) == .badgeUnavailable(lastKnownCount: 14)
    )
    #expect(
        FloatingWidgetState.resolve(
            badgeCount: 0,
            isBadgeStatusUncertain: true,
            isDragging: false
        ).badgePresentation.text == "?"
    )
}
