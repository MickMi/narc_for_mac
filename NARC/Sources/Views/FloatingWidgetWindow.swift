import Cocoa

/// A transparent NSView that accepts the first mouse click even when the window is inactive.
/// This prevents macOS from "eating" the first click on a non-key window.
private class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// A borderless, always-on-top floating window for the NARC widget.
class FloatingWidgetWindow: NSPanel {

    /// Called whenever the window is moved (e.g. by dragging).
    var onWindowMoved: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidMoveNotification() {
        onWindowMoved?()
    }
}
