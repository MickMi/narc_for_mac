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
