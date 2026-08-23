import Cocoa

/// A borderless NSPanel subclass that reports mouse-down events inside the panel.
///
/// Used to detect when the user clicks anywhere in the panel — this signals
/// intent to interact, which un-gates keyboard navigation (number keys, Enter).
/// Without this, opening the panel and immediately typing a number key would
/// accidentally activate a panel item.
final class PanelWindow: NSPanel {

    /// Called on every mouseDown inside this panel (before SwiftUI handles it).
    var onMouseDown: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            onMouseDown?()
        }
        super.sendEvent(event)
    }
}
