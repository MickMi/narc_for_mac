import AppKit
import SwiftUI

/// Lightweight floating host for Quick Capture.
///
/// The SwiftUI content is rebuilt for every presentation so a cancelled or
/// closed draft never reappears the next time the window is summoned.
@MainActor
final class QuickCaptureWindow: NSPanel, NSWindowDelegate {
    private let store: AssistantStore

    init(store: AssistantStore) {
        self.store = store

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 310),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        title = "Quick Capture"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present(on preferredScreen: NSScreen? = nil) {
        installFreshContent()
        position(on: preferredScreen ?? screenUnderMouse() ?? NSScreen.main)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    private func installFreshContent() {
        let rootView = QuickCaptureView(
            store: store,
            onSaved: { [weak self] in self?.dismiss() },
            onCancel: { [weak self] in self?.dismiss() }
        )
        contentView = NSHostingView(rootView: rootView)
    }

    private func position(on screen: NSScreen?) {
        guard let screen else {
            center()
            return
        }

        let visibleFrame = screen.visibleFrame
        var nextFrame = frame
        nextFrame.origin.x = visibleFrame.midX - nextFrame.width / 2
        nextFrame.origin.y = visibleFrame.midY - nextFrame.height / 2 + visibleFrame.height * 0.16
        setFrame(nextFrame, display: false)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }
}
