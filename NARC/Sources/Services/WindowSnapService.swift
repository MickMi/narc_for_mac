import Cocoa

/// Magnet-style drag-to-edge window snapping.
///
/// Monitors global mouse-drag events. When the user drags a window close to a
/// screen edge (~15 px zone), the frontmost window is snapped to the
/// corresponding half/quarter layout using the existing `WindowManagerService`.
///
/// A cooldown prevents rapid re-snapping (1 s minimum between snaps).
/// The service is toggled on/off from AppDelegate.
final class WindowSnapService {
    static let shared = WindowSnapService()

    private var dragMonitor: Any?
    private var lastSnapTime: Date = .distantPast
    private let snapCooldown: TimeInterval = 1.0
    private let edgeThreshold: CGFloat = 15

    private init() {}

    var isRunning: Bool { dragMonitor != nil }

    func start() {
        guard !isRunning else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDrag(event)
        }
    }

    func stop() {
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
    }

    private func handleDrag(_ event: NSEvent) {
        // Cooldown guard — prevent rapid re-snapping during a single drag.
        let now = Date()
        guard now.timeIntervalSince(lastSnapTime) >= snapCooldown else { return }

        let mouse = NSEvent.mouseLocation

        // Find which screen the mouse is on.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
        let frame = screen.visibleFrame

        // Compute distances to each edge.
        let distLeft   = mouse.x - frame.minX
        let distRight  = frame.maxX - mouse.x
        let distTop    = frame.maxY - mouse.y
        let distBottom = mouse.y - frame.minY

        // Only snap when the mouse is inside the edge threshold zone.
        let layout: WindowLayout?
        switch true {
        case distTop <= edgeThreshold && distLeft <= edgeThreshold:
            layout = .topLeft
        case distTop <= edgeThreshold && distRight <= edgeThreshold:
            layout = .topRight
        case distBottom <= edgeThreshold && distLeft <= edgeThreshold:
            layout = .bottomLeft
        case distBottom <= edgeThreshold && distRight <= edgeThreshold:
            layout = .bottomRight
        case distLeft <= edgeThreshold:
            layout = .leftHalf
        case distRight <= edgeThreshold:
            layout = .rightHalf
        case distTop <= edgeThreshold:
            layout = .topHalf
        case distBottom <= edgeThreshold:
            layout = .bottomHalf
        default:
            layout = nil
        }

        guard let snapLayout = layout else { return }

        lastSnapTime = now
        WindowManagerService.moveActiveWindow(to: snapLayout)
    }
}
