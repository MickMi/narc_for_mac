import Cocoa
import SwiftUI

/// Standalone resizable window summoned by right-clicking the floating widget.
/// Shows the Claude workspace: session list + detail + new/close actions.
///
/// Conforms to `NSWindowDelegate` so it can intercept ⌘W / close-button clicks
/// via `windowShouldClose`. The callback returns `true` to allow the close,
/// `false` to cancel it (e.g. when the user picks "收起" in the confirmation
/// alert).
final class DashboardWindow: NSWindow, NSWindowDelegate {

    /// Called when the user tries to close the window (⌘W, red button, etc.).
    /// Return `true` to allow, `false` to cancel.
    var onShouldClose: (() -> Bool)?

    convenience init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 760, height: 500)
        self.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.title = "NARC Dashboard"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .visible
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        self.delegate = self
        // Don't center here — the caller (AppDelegate.showDashboard) positions
        // the window relative to the floating widget's screen.
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return onShouldClose?() ?? true
    }
}
