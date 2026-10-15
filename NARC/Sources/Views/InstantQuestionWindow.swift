import AppKit
import SwiftUI

@MainActor
final class InstantQuestionWindow: NSWindow, NSWindowDelegate {
    private let controller: InstantQuestionController
    private let modeSelection = InstantQuestionModeSelection()
    var onClose: (() -> Void)?
    var selectedMode: InstantQuestionView.Mode { modeSelection.mode }

    init(
        controller: InstantQuestionController,
        store: InstantQuestionStore,
        onOpenPreferences: @escaping () -> Void
    ) {
        self.controller = controller
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "NARC 搜索"
        titlebarAppearsTransparent = true
        titleVisibility = .visible
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        minSize = NSSize(width: 680, height: 520)
        delegate = self
        contentView = NSHostingView(
            rootView: InstantQuestionView(
                controller: controller,
                store: store,
                onOpenPreferences: onOpenPreferences,
                modeSelection: modeSelection
            )
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowWillClose(_ notification: Notification) {
        controller.clearCurrent()
        onClose?()
    }

    func present(on preferredScreen: NSScreen? = nil) {
        position(on: preferredScreen ?? screenUnderMouse() ?? NSScreen.main)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if selectedMode == .ask { modeSelection.requestInputFocus() }
    }

    func selectMode(_ mode: InstantQuestionView.Mode) {
        modeSelection.mode = mode
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
