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

    /// Optional window-local keyboard handler. The dedicated Pin switcher uses
    /// this instead of the main panel's app-wide event monitor, so its digits
    /// and Return can be consumed without affecting other NARC windows.
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            onMouseDown?()
        }
        super.sendEvent(event)
    }
}
