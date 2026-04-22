import Cocoa

/// A transparent NSView that accepts the first mouse click even when the window is inactive.
/// This prevents macOS from "eating" the first click on a non-key window.
private class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// A borderless, always-on-top floating window for the NARC widget.
///
/// Handles the "first click eaten" problem on macOS:
/// When the app is not the frontmost application, the first click on a `nonactivatingPanel`
/// is consumed by the system to activate the window, and SwiftUI's `.onTapGesture` never fires.
///
/// Solution: We intercept `mouseDown` at the AppKit level and detect short clicks (< 0.3s)
/// that don't move significantly (< 5pt). This bypasses SwiftUI's gesture system entirely
/// for the initial tap, ensuring the first click always works.
class FloatingWidgetWindow: NSPanel {

    /// Called whenever the window is moved (e.g. by dragging).
    var onWindowMoved: (() -> Void)?

    /// Called when the widget is tapped (AppKit-level, bypasses SwiftUI gesture issues).
    /// This is the primary click handler — it fires reliably even on the first click
    /// when the app is not the frontmost application.
    var onWidgetTapped: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Track mouse down for tap detection
    private var mouseDownTime: Date?
    private var mouseDownLocation: NSPoint?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
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
                // If the new view is already a FirstMouseView, use it directly
                if newView is FirstMouseView {
                    super.contentView = newView
                } else {
                    // Wrap the provided view in a FirstMouseView
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

    // MARK: - AppKit-level tap detection

    /// Intercept all events to detect taps at the AppKit level.
    /// This fires before SwiftUI's gesture system, ensuring the first click always works.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownTime = Date()
            mouseDownLocation = event.locationInWindow
            super.sendEvent(event)

        case .leftMouseUp:
            if let downTime = mouseDownTime, let downLocation = mouseDownLocation {
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
