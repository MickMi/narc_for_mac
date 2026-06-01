import Cocoa

/// A transparent NSView that accepts the first mouse click even when the window is inactive,
/// AND restricts the window's hit-test region to the visible 48pt circle area in the
/// center of the panel. The 40pt of transparent padding around the circle (which exists
/// to give SwiftUI's drop shadow room to render — see FloatingWidgetView) must be
/// click-through, otherwise the "empty space" around the widget would steal clicks
/// from whatever app is below.
private final class FirstMouseView: NSView {
    /// Side length of the visible widget in the center of the canvas.
    var visibleSize: CGFloat = 48

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    /// Only the central `visibleSize × visibleSize` bbox is hit-testable.
    /// Clicks in the outer transparent shadow region pass through to the
    /// window/app below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate system. The contentView
        // has no superview, so it's already in window coords.
        let local = superview.map { convert(point, from: $0) } ?? point
        let inset = (bounds.width - visibleSize) / 2
        let visibleRect = NSRect(
            x: bounds.minX + inset,
            y: bounds.minY + inset,
            width: visibleSize,
            height: visibleSize
        )
        guard visibleRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// A borderless, always-on-top floating window for the NARC widget.
///
/// Conforms to spec §7:
/// - `isOpaque = false` + `backgroundColor = .clear` so the 48pt circle's
///   surroundings are fully transparent (otherwise the window degrades into
///   a "rounded rect with a circle painted on it").
/// - `hasShadow = false` because the SwiftUI view supplies its own dual-layer
///   drop shadow per spec §6.
///
/// Sized 128×128 even though the visible widget is 48×48: SwiftUI's
/// `.shadow(radius: 32)` is rendered into the host layer and clips to the
/// host's frame, so we need 40pt of transparent padding on each side for
/// the shadow to render fully (otherwise it leaves a hard rectangular halo
/// at the edge — the "方框" bug).
///
/// Handles the "first click eaten" problem on macOS:
/// When the app is not the frontmost application, the first click on a `nonactivatingPanel`
/// is consumed by the system to activate the window, and SwiftUI's `.onTapGesture` never fires.
///
/// Solution: We intercept `mouseDown` at the AppKit level and detect short clicks (< 0.3s)
/// that don't move significantly (< 5pt). This bypasses SwiftUI's gesture system entirely
/// for the initial tap, ensuring the first click always works.
final class FloatingWidgetWindow: NSPanel {

    /// Side length of the full panel (visible widget + transparent shadow padding).
    static let canvasSize: CGFloat = 128
    /// Side length of the visible (clickable) widget area.
    static let widgetSize: CGFloat = 48

    /// Called whenever the window is moved (e.g. by dragging).
    var onWindowMoved: (() -> Void)?

    /// Called when the widget is tapped (AppKit-level, bypasses SwiftUI gesture issues).
    /// This is the primary click handler — it fires reliably even on the first click
    /// when the app is not the frontmost application.
    var onWidgetTapped: (() -> Void)?

    /// Called when the widget is right-clicked (or Ctrl+clicked).
    /// Used to summon the Claude Dashboard window.
    var onWidgetRightClicked: (() -> Void)?

    /// Called when a drag gesture starts (mouse moved > 5pt while held).
    /// Spec §2: idle/hasNotification → dragging.
    var onDragStart: (() -> Void)?

    /// Called when the drag gesture ends. Spec §2: dragging → idle/hasNotification.
    var onDragEnd: (() -> Void)?

    /// Spec §7: the panel must never become key. Drag/click gestures still work
    /// because we override sendEvent.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Track mouse down for tap detection
    private var mouseDownTime: Date?
    private var mouseDownLocation: NSPoint?
    /// True after we've upgraded a mouse-down to a drag (movement > 5pt).
    /// Cleared on mouseUp.
    private var isDragging: Bool = false

    init() {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: FloatingWidgetWindow.canvasSize,
                height: FloatingWidgetWindow.canvasSize
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Spec §7
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isOpaque = false              // critical — keeps the 48pt circle's surroundings transparent
        self.backgroundColor = .clear      // critical — same reason
        self.hasShadow = false             // SwiftUI view supplies its own drop shadow
        self.isMovableByWindowBackground = true
        self.acceptsMouseMovedEvents = true
        self.animationBehavior = .none

        // Observe window move events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveNotification),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    /// Override contentView setter to wrap the provided view inside a FirstMouseView container.
    /// This ensures that clicks are accepted even when the app is not the active application.
    override var contentView: NSView? {
        get { super.contentView }
        set {
            if let newView = newValue {
                if newView is FirstMouseView {
                    super.contentView = newView
                } else {
                    let wrapper = FirstMouseView(frame: newView.frame)
                    wrapper.autoresizesSubviews = true
                    newView.autoresizingMask = [.width, .height]
                    wrapper.addSubview(newView)
                    super.contentView = wrapper
                }
            } else {
                super.contentView = newValue
            }
        }
    }

    // MARK: - AppKit-level tap / drag detection

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownTime = Date()
            mouseDownLocation = event.locationInWindow
            isDragging = false
            super.sendEvent(event)

        case .leftMouseDragged:
            // Once movement crosses 5pt threshold, upgrade to drag state.
            if !isDragging, let downLocation = mouseDownLocation {
                let here = event.locationInWindow
                let dx = here.x - downLocation.x
                let dy = here.y - downLocation.y
                if sqrt(dx * dx + dy * dy) >= 5.0 {
                    isDragging = true
                    onDragStart?()
                }
            }
            super.sendEvent(event)

        case .leftMouseUp:
            if isDragging {
                onDragEnd?()
            } else if let downTime = mouseDownTime, let downLocation = mouseDownLocation {
                let elapsed = Date().timeIntervalSince(downTime)
                let upLocation = event.locationInWindow
                let dx = upLocation.x - downLocation.x
                let dy = upLocation.y - downLocation.y
                let distance = sqrt(dx * dx + dy * dy)

                // Short click (< 0.3s) with minimal movement (< 5pt) = tap
                if elapsed < 0.3 && distance < 5.0 {
                    onWidgetTapped?()
                }
            }
            mouseDownTime = nil
            mouseDownLocation = nil
            isDragging = false
            super.sendEvent(event)

        case .rightMouseDown:
            // Right-click (or Ctrl+left-click on trackpads) summons the dashboard.
            // macOS auto-translates Ctrl+leftMouseDown into rightMouseDown for us.
            onWidgetRightClicked?()
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidMoveNotification() {
        onWindowMoved?()
    }
}
