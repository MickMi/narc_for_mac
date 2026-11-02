import AppKit
import SwiftUI

@MainActor
final class InstantQuestionWindow: NSWindow, NSWindowDelegate {
    private let controller: InstantQuestionController
    private let modeSelection = InstantQuestionModeSelection()
    private var activationObserver: NSObjectProtocol?
    private var awaitingActivation = false
    var onClose: (() -> Void)?
    var selectedMode: InstantQuestionView.Mode { modeSelection.mode }

    init(
        controller: InstantQuestionController,
        store: InstantQuestionStore,
        onOpenPreferences: @escaping () -> Void,
        onboardingDefaults: UserDefaults = .standard,
        onOpenHelp: @escaping (HelpTopic) -> Void = { _ in }
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
                modeSelection: modeSelection,
                onboardingDefaults: onboardingDefaults,
                onOpenHelp: onOpenHelp
            )
        )
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishPresentation() }
        }
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowWillClose(_ notification: Notification) {
        awaitingActivation = false
        controller.clearCurrent()
        onClose?()
    }

    func present(on preferredScreen: NSScreen? = nil) {
        position(on: preferredScreen ?? screenUnderMouse() ?? NSScreen.main)
        awaitingActivation = true
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        if selectedMode == .ask { modeSelection.requestInputFocus() }
        // LSUIElement activation may finish after the Carbon hotkey callback.
        // Reassert focus once at the activation boundary, never on normal redraw.
        DispatchQueue.main.async { [weak self] in self?.finishPresentation() }
    }

    private func finishPresentation() {
        guard awaitingActivation, isVisible, NSApp.isActive else { return }
        awaitingActivation = false
        makeKeyAndOrderFront(nil)
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
