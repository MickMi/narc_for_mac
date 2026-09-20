import AppKit
import SwiftUI

/// Lightweight floating host for the shared Inbox capture surface.
///
/// Content is installed once. The draft state is owned by AppDelegate and is
/// intentionally preserved when the window is hidden and summoned again.
@MainActor
final class QuickCaptureWindow: NSPanel, NSWindowDelegate {
    private let store: AssistantStore
    private let captureState: InboxCaptureState
    private let onOpenAssistant: () -> Void

    init(
        store: AssistantStore,
        captureState: InboxCaptureState,
        onOpenAssistant: @escaping () -> Void
    ) {
        self.store = store
        self.captureState = captureState
        self.onOpenAssistant = onOpenAssistant

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
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

        contentView = NSHostingView(
            rootView: QuickCaptureView(
                store: store,
                captureState: captureState,
                onDismiss: { [weak self] in self?.dismiss() },
                onOpenAssistant: { [weak self] in
                    self?.dismiss()
                    self?.onOpenAssistant()
                }
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

    func dismiss() {
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
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
