import AppKit
import SwiftUI

/// Standard resizable window for the built-in personal assistant pages.
@MainActor
final class AssistantHubWindow: NSWindow {
    init(store: AssistantStore, onQuickCapture: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "NARC Assistant"
        titlebarAppearsTransparent = true
        titleVisibility = .visible
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        minSize = NSSize(width: 620, height: 440)
        contentView = NSHostingView(
            rootView: AssistantHubView(
                store: store,
                onQuickCapture: onQuickCapture
            )
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present(on preferredScreen: NSScreen? = nil) {
        position(on: preferredScreen ?? screenUnderMouse() ?? NSScreen.main)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func position(on screen: NSScreen?) {
        guard let screen else {
            center()
            return
        }

        let visibleFrame = screen.visibleFrame
        var nextFrame = frame
        nextFrame.origin.x = visibleFrame.midX - nextFrame.width / 2
        nextFrame.origin.y = visibleFrame.midY - nextFrame.height / 2
        setFrame(nextFrame, display: false)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }
}
