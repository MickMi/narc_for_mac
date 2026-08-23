import Cocoa
import SwiftUI

/// Standard NSWindow hosting the PreferencesView.
///
/// Previously the app relied on SwiftUI's `Settings` scene + `showSettingsWindow:`
/// selector, but that action travels up the responder chain — and since NARC's
/// floating widget and panel both use `canBecomeKey = false`, there's no first
/// responder to forward the action. A manual NSWindow avoids this entirely and
/// keeps the pattern consistent with DashboardWindow / PanelWindow.
final class PreferencesWindow: NSWindow {

    convenience init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 560, height: 460)
        self.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.title = "NARC 偏好设置"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .visible
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        self.center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
