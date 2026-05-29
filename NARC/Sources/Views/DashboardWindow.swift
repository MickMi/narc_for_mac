import Cocoa
import SwiftUI

/// Standalone resizable window summoned by right-clicking the floating widget.
/// Shows the Claude workspace: session list + detail + new/close actions.
final class DashboardWindow: NSWindow {

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
        self.center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
