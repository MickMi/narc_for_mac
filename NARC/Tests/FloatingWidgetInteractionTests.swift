import Cocoa
import SwiftUI
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

@Test(arguments: [CGFloat(40), CGFloat(48), CGFloat(58)])
func codexReplyCueHasIndependentClickableTarget(visibleSize: CGFloat) {
    let canvasSize = visibleSize + 80
    let cue = WidgetPointerInteractionPolicy.codexCueRect(
        canvasSize: canvasSize, visibleSize: visibleSize
    )
    let circle = NSRect(x: 40, y: 40, width: visibleSize, height: visibleSize)
    #expect(cue.width == 32)
    #expect(cue.height == 19)
    #expect(cue.minX < circle.minX)
    #expect(cue.maxY > circle.maxY)
    #expect(cue.minX >= 0 && cue.maxY <= canvasSize)
    let cueCenter = NSPoint(x: cue.midX, y: cue.midY)
    #expect(WidgetPointerInteractionPolicy.tapTarget(
        at: cueCenter, canvasSize: canvasSize, visibleSize: visibleSize,
        showsCodexCue: true
    ) == .codexReply)
    #expect(WidgetPointerInteractionPolicy.tapTarget(
        at: NSPoint(x: cue.minX + 1, y: cue.maxY - 1),
        canvasSize: canvasSize, visibleSize: visibleSize, showsCodexCue: true
    ) == .codexReply)
    #expect(WidgetPointerInteractionPolicy.tapTarget(
        at: cueCenter, canvasSize: canvasSize, visibleSize: visibleSize,
        showsCodexCue: false
    ) == .widget)
    #expect(WidgetPointerInteractionPolicy.tapTarget(
        at: NSPoint(x: circle.midX, y: circle.midY), canvasSize: canvasSize,
        visibleSize: visibleSize, showsCodexCue: true
    ) == .widget)
    #expect(CodexReplyCuePresentation.resolve(count: 0).text == nil)
    #expect(CodexReplyCuePresentation.resolve(count: 1).text == "1")
    #expect(CodexReplyCuePresentation.resolve(count: 10).text == "9+")
}

@Test(arguments: [CGFloat(40), CGFloat(48), CGFloat(58)])
@MainActor
func visibleReplyAndTodoCuesAcceptClicksOutsideTheCircle(visibleSize: CGFloat) throws {
    _ = NSApplication.shared
    let window = FloatingWidgetWindow()
    defer { window.close() }
    window.applyWidgetSize(visibleSize)
    window.contentView = NSHostingView(rootView: FloatingWidgetView(
        state: .idle, availableTodoCount: 3, codexReplyCount: 2,
        widgetSize: visibleSize == 40 ? "Small" : (visibleSize == 58 ? "Large" : "Medium")
    ))
    let view = try #require(window.contentView)
    window.showsCodexCue = true
    window.todoCueCount = 3
    let canvas = window.canvasSize
    let reply = WidgetPointerInteractionPolicy.codexCueRect(
        canvasSize: canvas, visibleSize: visibleSize
    )
    let todo = WidgetPointerInteractionPolicy.todoCueRect(
        canvasSize: canvas, visibleSize: visibleSize, count: 3
    )
    let replyPoint = NSPoint(x: reply.minX + 2, y: reply.maxY - 2)
    let todoPoint = NSPoint(x: todo.minX + 2, y: todo.minY + 2)
    #expect(view.hitTest(replyPoint) != nil)
    #expect(view.hitTest(todoPoint) != nil)
    #expect(WidgetPointerInteractionPolicy.tapTarget(
        at: replyPoint, canvasSize: canvas, visibleSize: visibleSize,
        showsCodexCue: true, todoCueCount: 3
    ) == .codexReply)
    #expect(WidgetPointerInteractionPolicy.tapTarget(
        at: todoPoint, canvasSize: canvas, visibleSize: visibleSize,
        showsCodexCue: true, todoCueCount: 3
    ) == .todo)
    #expect(view.hitTest(NSPoint(x: 2, y: 2)) == nil)
    window.todoCueCount = 0
    window.showsCodexCue = false
    #expect(view.hitTest(replyPoint) == nil)
    #expect(view.hitTest(todoPoint) == nil)
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
        targetVisibleFrame: target
    )

    #expect(panel.size == NSSize(width: NarcSize.panelWidth, height: NarcSize.panelHeight))
    #expect(panel.minX >= target.minX)
    #expect(panel.maxX <= target.maxX)
    #expect(panel.minY >= target.minY)
    #expect(panel.maxY <= target.maxY)
}

@Test
func summonedPanelUsesCurrentContentSizeAtRightScreenEdge() {
    let target = NSRect(x: 0, y: 0, width: 1512, height: 982)
    let widgetFrame = NSRect(x: 1384, y: 427, width: 128, height: 128)

    let panel = FloatingPanelPlacement.frame(
        adjacentTo: widgetFrame,
        visibleWidgetSize: 48,
        targetVisibleFrame: target
    )

    #expect(panel.width == NarcSize.panelWidth)
    #expect(panel.height == NarcSize.panelHeight)
    #expect(panel.maxX == target.maxX - 4)
    #expect(panel.minX >= target.minX)
    #expect(panel.maxY <= target.maxY)
}

@Test @MainActor
func mainPanelAllowsBackgroundDraggingWithoutChangingOtherPanelWindows() {
    _ = NSApplication.shared
    let mainPanel = PanelWindow.mainPanel(
        contentRect: NSRect(x: 100, y: 100, width: 360, height: 480)
    )
    let regularPanel = PanelWindow(
        contentRect: NSRect(x: 100, y: 100, width: 320, height: 240),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    #expect(mainPanel.isMovable)
    #expect(mainPanel.isMovableByWindowBackground)
    #expect(!regularPanel.isMovableByWindowBackground)
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

@Test
func todoCueRemainsIndependentFromEveryUnreadPresentation() {
    let cases: [(count: Int, uncertain: Bool, text: String)] = [
        (14, false, "14"),
        (120, false, "99+"),
        (0, true, "?"),
    ]

    for item in cases {
        let state = FloatingWidgetState.resolve(
            badgeCount: item.count,
            isBadgeStatusUncertain: item.uncertain,
            isDragging: false
        )

        #expect(state.badgePresentation.text == item.text)
        #expect(state.showsTodoCue(availableTodoCount: 1))
    }
}

@Test
func todoCueRequiresAnAvailableTodoAndHidesDuringDrag() {
    #expect(
        !FloatingWidgetState.idle.showsTodoCue(availableTodoCount: 0)
    )
    #expect(
        !FloatingWidgetState.dragging.showsTodoCue(availableTodoCount: 2)
    )
}

@Test
func todoCueShowsItsOwnBoundedCount() {
    #expect(TodoCuePresentation.resolve(count: 0).text == nil)
    #expect(TodoCuePresentation.resolve(count: 1).text == "1")
    #expect(TodoCuePresentation.resolve(count: 14).text == "14")
    #expect(TodoCuePresentation.resolve(count: 99).text == "99")
    #expect(TodoCuePresentation.resolve(count: 100).text == "99+")
    #expect(TodoCuePresentation.resolve(count: 120).text == "99+")
}

@Test
func todoNudgePrefersTheWidgetsLeftSideAndStaysInsideNegativeDisplay() {
    let screen = NSRect(x: -1_920, y: -120, width: 1_920, height: 1_040)
    let widget = NSRect(x: -128, y: 120, width: 128, height: 128)
    let cardSize = NSSize(width: 320, height: 188)

    let result = TodoNudgePlacement.frame(
        adjacentTo: widget,
        visibleWidgetSize: 48,
        cardSize: cardSize,
        targetVisibleFrame: screen
    )
    let visibleWidget = FloatingWidgetPlacement.visibleWidgetRect(
        in: widget,
        visibleSize: 48
    )

    #expect(result.maxX == visibleWidget.minX - 10)
    #expect(result.minX >= screen.minX + 8)
    #expect(result.minY >= screen.minY + 8)
    #expect(result.maxY <= screen.maxY - 8)
}

@Test
func todoNudgeFallsBackToTheRightAndClampsVertically() {
    let screen = NSRect(x: 0, y: 24, width: 800, height: 576)
    let widget = NSRect(x: -40, y: 480, width: 128, height: 128)
    let cardSize = NSSize(width: 320, height: 188)

    let result = TodoNudgePlacement.frame(
        adjacentTo: widget,
        visibleWidgetSize: 48,
        cardSize: cardSize,
        targetVisibleFrame: screen
    )
    let visibleWidget = FloatingWidgetPlacement.visibleWidgetRect(
        in: widget,
        visibleSize: 48
    )

    #expect(result.minX == visibleWidget.maxX + 10)
    #expect(result.maxY == screen.maxY - 8)
}

@Test
func todoAttentionSelectionCoversEmptySingleAndMultipleCandidates() throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let first = TodoItem(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
        title: "First",
        createdAt: createdAt
    )
    let second = TodoItem(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
        title: "Second",
        createdAt: createdAt
    )

    let empty = TodoAttentionSelection.resolve(
        currentTodoID: nil,
        availableTodos: []
    )
    #expect(empty.todo == nil)
    #expect(!empty.canAdvance)

    let single = TodoAttentionSelection.resolve(
        currentTodoID: first.id,
        availableTodos: [first]
    )
    #expect(single.todo == first)
    #expect(single.position == 1)
    #expect(!single.canAdvance)

    let selectedSecond = TodoAttentionSelection.resolve(
        currentTodoID: second.id,
        availableTodos: [first, second]
    )
    #expect(selectedSecond.todo == second)
    #expect(selectedSecond.position == 2)
    #expect(selectedSecond.total == 2)
    #expect(selectedSecond.canAdvance)

    let missingFallsBackToFirst = TodoAttentionSelection.resolve(
        currentTodoID: UUID(),
        availableTodos: [first, second]
    )
    #expect(missingFallsBackToFirst.todo == first)
}
