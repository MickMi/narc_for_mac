import AppKit
import SwiftUI

@MainActor
final class OnboardingWindow: NSWindow, NSWindowDelegate {
    private let onDismiss: () -> Void
    private var didNotifyDismiss = false

    init(
        hotkeyService: HotkeyService,
        onOpenAssistant: @escaping () -> Void,
        onOpenAccessibilitySettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "欢迎使用 NARC"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        delegate = self

        contentView = NSHostingView(
            rootView: OnboardingView(
                hotkeyService: hotkeyService,
                onOpenAssistant: { [weak self] in
                    self?.dismiss()
                    onOpenAssistant()
                },
                onOpenAccessibilitySettings: onOpenAccessibilitySettings,
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        didNotifyDismiss = false
        positionOnActiveScreen()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
        notifyDismissOnce()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    private func notifyDismissOnce() {
        guard !didNotifyDismiss else { return }
        didNotifyDismiss = true
        onDismiss()
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main else {
            center()
            return
        }

        let visibleFrame = screen.visibleFrame
        var nextFrame = frame
        nextFrame.origin.x = visibleFrame.midX - nextFrame.width / 2
        nextFrame.origin.y = visibleFrame.midY - nextFrame.height / 2
        setFrame(nextFrame, display: false)
    }
}
