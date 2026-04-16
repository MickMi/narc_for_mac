import Cocoa
import SwiftUI

/// AppDelegate handles app lifecycle, floating window, and menu bar setup.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var floatingWindow: FloatingWidgetWindow?
    private var statusBarItem: NSStatusItem?
    private var panelWindow: NSPanel?

    private let appMonitor = AppMonitorService()
    private let windowManager = WindowManagerService()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[NARC] 🚀 App launching...")

        // Hide from Dock (accessory app — no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        print("[NARC] Setting up menu bar icon...")
        setupMenuBarIcon()

        print("[NARC] Setting up floating widget...")
        setupFloatingWidget()

        print("[NARC] Starting app monitor...")
        appMonitor.startMonitoring()

        print("[NARC] Registering global hotkeys...")
        windowManager.registerGlobalHotkeys()

        print("[NARC] ✅ App launch complete. Look for the floating widget (bottom-right) and menu bar icon.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        appMonitor.stopMonitoring()
    }

    // MARK: - Menu Bar

    private func setupMenuBarIcon() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "n.circle.fill", accessibilityDescription: "NARC")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(menuBarIconClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show NARC", action: #selector(showFloatingWidget), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About NARC", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NARC", action: #selector(quitApp), keyEquivalent: "q"))

        statusBarItem?.menu = menu
    }

    // MARK: - Floating Widget

    private func setupFloatingWidget() {
        let widgetView = FloatingWidgetView(
            appMonitor: appMonitor,
            onTap: { [weak self] in self?.togglePanel() }
        )

        let hostingView = NSHostingView(rootView: widgetView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 48, height: 48)

        // Position: bottom-right corner of the screen with the mouse cursor
        // This ensures the widget appears on the screen the user is actively using
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let screenFrame = activeScreen?.visibleFrame ?? .zero
        let widgetX = screenFrame.maxX - 48 - 20
        let widgetY = screenFrame.minY + 80

        let window = FloatingWidgetWindow(
            contentRect: NSRect(x: widgetX, y: widgetY, width: 48, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()

        // When the widget is dragged, reposition the panel
        window.onWindowMoved = { [weak self] in
            self?.repositionPanel()
        }

        self.floatingWindow = window
    }

    // MARK: - Panel

    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 420

    private func togglePanel() {
        if let panel = panelWindow, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Calculate the panel frame relative to the current floating widget position.
    private func panelFrame() -> NSRect {
        guard let widgetFrame = floatingWindow?.frame else { return .zero }

        // Use the screen where the widget is located, not always the main screen
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(widgetFrame.origin) }) ?? NSScreen.main else { return .zero }

        let screenFrame = screen.visibleFrame

        // Default: panel above the widget, centered horizontally
        var panelX = widgetFrame.midX - panelWidth / 2
        var panelY = widgetFrame.maxY + 8

        // If panel would go above the screen, show it below the widget
        if panelY + panelHeight > screenFrame.maxY {
            panelY = widgetFrame.minY - panelHeight - 8
        }

        // Clamp horizontal position to screen bounds
        panelX = max(screenFrame.minX + 4, min(panelX, screenFrame.maxX - panelWidth - 4))

        return NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
    }

    private func showPanel() {
        guard let widgetFrame = floatingWindow?.frame else { return }

        let frame = panelFrame()

        // Determine which screen the NARC widget is on
        let narcScreen = NSScreen.screens.first(where: { $0.frame.contains(widgetFrame.origin) }) ?? NSScreen.main

        let panelContentView = PanelView(
            appMonitor: appMonitor,
            windowManager: windowManager,
            onClose: { [weak self] in self?.hidePanel() },
            onOpenPreferences: { [weak self] in self?.openPreferences() },
            narcScreen: narcScreen
        )

        let hostingView = NSHostingView(rootView: panelContentView)
        // Make the hosting view's layer background transparent so SwiftUI material shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        panel.orderFrontRegardless()
        self.panelWindow = panel
    }

    /// Update the panel position to follow the floating widget.
    private func repositionPanel() {
        guard let panel = panelWindow, panel.isVisible else { return }
        let frame = panelFrame()
        panel.setFrame(frame, display: true, animate: false)
    }

    private func hidePanel() {
        panelWindow?.orderOut(nil)
        panelWindow = nil
    }

    // MARK: - Actions

    @objc private func menuBarIconClicked() {
        togglePanel()
    }

    @objc private func showFloatingWidget() {
        floatingWindow?.orderFrontRegardless()
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
