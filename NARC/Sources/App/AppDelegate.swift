import Cocoa
import SwiftUI
import Combine

/// AppDelegate handles app lifecycle, floating window, and menu bar setup.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var floatingWindow: FloatingWidgetWindow?
    private var statusBarItem: NSStatusItem?
    private var panelWindow: NSPanel?
    private var keyEventMonitor: Any?
    private var globalKeyEventMonitor: Any?

    private let appMonitor = AppMonitorService()
    private let windowManager = WindowManagerService()
    private let pinnedWindowService = PinnedWindowService()
    private let hotkeyService = HotkeyService()
    private let claudeService = ClaudeSessionService.shared

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
        hotkeyService.onPinHotkeyPressed = { [weak self] in
            guard let self = self else { return }
            let success = self.pinnedWindowService.pinCurrentWindow()
            if success {
                self.showPinFeedback()
            }
        }
        hotkeyService.onTogglePanelHotkeyPressed = { [weak self] in
            self?.togglePanelAtMouseScreen()
        }
        hotkeyService.onLayoutHotkeyPressed = { layout in
            WindowManagerService.moveActiveWindow(to: layout)
        }
        hotkeyService.registerGlobalHotkeys()

        // Start Claude Code session monitoring
        claudeService.onAttentionNeeded = { [weak self] reason in
            switch reason {
            case .permissionRequest:
                self?.showApprovalPanel()
            case .stopped, .error, .stale:
                self?.showApprovalPanel()
            }
        }
        claudeService.startListening()

        print("[NARC] ✅ App launch complete. Look for the floating widget (bottom-right) and menu bar icon.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        appMonitor.stopMonitoring()
        claudeService.stopListening()
    }

    /// Show a brief visual feedback on the floating widget when a window is pinned.
    private func showPinFeedback() {
        guard let window = floatingWindow else { return }
        let originalAlpha = window.alphaValue

        // Quick flash animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            window.animator().alphaValue = 0.3
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                window.animator().alphaValue = originalAlpha
            })
        })
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
            claudeService: claudeService,
            onTap: { /* Handled at AppKit level via onWidgetTapped */ }
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

        // Handle tap at AppKit level — this fires reliably even on the first click
        // when NARC is not the frontmost application (bypasses SwiftUI gesture issues)
        window.onWidgetTapped = { [weak self] in
            self?.togglePanel()
        }

        // When the widget is dragged, reposition the panel
        window.onWindowMoved = { [weak self] in
            self?.repositionPanel()
        }

        self.floatingWindow = window
    }

    // MARK: - Panel

    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 420

    /// Toggle panel from widget click — panel appears near the widget.
    private func togglePanel() {
        if let panel = panelWindow, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Toggle panel from hotkey (⌃⌥N) — panel appears on the screen where the mouse cursor is.
    private func togglePanelAtMouseScreen() {
        if let panel = panelWindow, panel.isVisible {
            hidePanel()
        } else {
            showPanelAtMouseScreen()
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

    /// Calculate the panel frame at the bottom-right of the given screen.
    private func panelFrameOnScreen(_ screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame

        // Position at bottom-right corner with some padding
        let panelX = screenFrame.maxX - panelWidth - 20
        let panelY = screenFrame.minY + 20

        return NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
    }

    /// Shared keyboard selection state for the panel.
    /// Tracks which item is selected via ↑↓ keys.
    private let keyboardSelection = KeyboardSelectionState()

    /// Show panel near the floating widget (triggered by widget click).
    private func showPanel() {
        guard let widgetFrame = floatingWindow?.frame else { return }

        let frame = panelFrame()

        // Determine which screen the NARC widget is on
        let narcScreen = NSScreen.screens.first(where: { $0.frame.contains(widgetFrame.origin) }) ?? NSScreen.main

        presentPanel(frame: frame, narcScreen: narcScreen)
    }

    /// Show panel on the screen where the mouse cursor is (triggered by ⌃⌥N hotkey).
    private func showPanelAtMouseScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

        let frame = panelFrameOnScreen(mouseScreen!)

        presentPanel(frame: frame, narcScreen: mouseScreen)
    }

    /// Shared panel creation logic.
    private func presentPanel(frame: NSRect, narcScreen: NSScreen?) {
        // Reset keyboard selection when opening panel
        keyboardSelection.selectedIndex = -1

        let panelContentView = PanelView(
            appMonitor: appMonitor,
            windowManager: windowManager,
            pinnedWindowService: pinnedWindowService,
            onClose: { [weak self] in self?.hidePanel() },
            onOpenPreferences: { [weak self] in self?.openPreferences() },
            narcScreen: narcScreen,
            keyboardSelection: keyboardSelection
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

        // CRITICAL: Make NARC the active app so the LOCAL key event monitor can
        // intercept and CONSUME keyboard events (return nil). Without this,
        // when another app (e.g., VS Code) is active, the global monitor can
        // only observe events but cannot prevent them from reaching the active app.
        // This means Enter/Tab would both trigger NARC's action AND be sent to
        // the editor, causing unwanted edits.
        NSApp.activate(ignoringOtherApps: true)

        // Install key event monitor for panel keyboard navigation
        installKeyEventMonitor(narcScreen: narcScreen)
    }

    /// Update the panel position to follow the floating widget.
    private func repositionPanel() {
        guard let panel = panelWindow, panel.isVisible else { return }
        let frame = panelFrame()
        panel.setFrame(frame, display: true, animate: false)
    }

    private func hidePanel() {
        removeKeyEventMonitor()
        panelWindow?.orderOut(nil)
        panelWindow = nil
    }

    // MARK: - Claude Toast Notification

    private var toastWindow: NSPanel?
    private var toastCancellables = Set<AnyCancellable>()
    private var currentToastEvent: ClaudeToastEvent?

    /// Show a toast notification at the top-right of the focused screen.
    /// Stays visible until the user clicks (jump) or the event resolves.
    private func showApprovalPanel() {
        // Build toast event from the latest pending item
        guard let event = buildToastEvent() else { return }

        // If toast is already showing the same session, just update
        if let current = currentToastEvent, current.sessionId == event.sessionId,
           let window = toastWindow, window.isVisible {
            // Update in-place (the binding will handle it if we rebuild)
            updateToast(event: event)
            return
        }

        currentToastEvent = event
        presentToast(event: event)
    }

    private func buildToastEvent() -> ClaudeToastEvent? {
        // Priority: pending approvals first, then notifications
        if let approval = claudeService.pendingApprovals.last {
            return ClaudeToastEvent(
                type: .permissionRequest,
                projectName: approval.projectName,
                detail: approval.commandDescription,
                tty: approval.tty,
                cwd: approval.cwd,
                sessionId: approval.sessionId,
                approval: approval
            )
        }

        if let notification = claudeService.notifications.last {
            let type: ClaudeToastEvent.EventType
            switch notification.type {
            case .stopped: type = .waitingForInput
            case .error: type = .error
            case .stale: type = .stale
            }
            return ClaudeToastEvent(
                type: type,
                projectName: notification.projectName,
                detail: notification.message,
                tty: notification.tty,
                cwd: notification.cwd,
                sessionId: notification.sessionId
            )
        }

        return nil
    }

    private func presentToast(event: ClaudeToastEvent) {
        // Determine the focused screen (where mouse cursor is)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
        let screenFrame = screen.visibleFrame

        // Position: top-right corner with padding
        let toastWidth: CGFloat = 380
        let toastHeight: CGFloat = 56
        let x = screenFrame.maxX - toastWidth - 16
        let y = screenFrame.maxY - toastHeight - 12

        let toastView = ClaudeToastView(
            event: event,
            onJump: { [weak self] in
                self?.jumpToClaudeTerminal(event: event)
            },
            onDismiss: { [weak self] in
                self?.hideToast()
            },
            onAllow: event.approval != nil ? { [weak self] in
                guard let approval = event.approval else { return }
                self?.claudeService.approve(approval)
                self?.hideToast()
            } : nil,
            onDeny: event.approval != nil ? { [weak self] in
                guard let approval = event.approval else { return }
                self?.claudeService.deny(approval)
                self?.hideToast()
            } : nil
        )

        let hostingView = NSHostingView(rootView: toastView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: toastWidth, height: toastHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.orderFrontRegardless()

        // Clean up old toast
        toastWindow?.orderOut(nil)
        self.toastWindow = panel

        // Subscribe to approval cleanup — hide toast when resolved
        toastCancellables.removeAll()
        claudeService.$pendingApprovals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] approvals in
                guard let self = self, let current = self.currentToastEvent else { return }
                // If this was a permission request and it's been resolved, hide
                if current.type == .permissionRequest {
                    if !approvals.contains(where: { $0.sessionId == current.sessionId }) {
                        self.hideToast()
                    }
                }
            }
            .store(in: &toastCancellables)

        // Play a subtle sound
        NSSound.beep()
        print("[NARC] 🔔 Toast notification: \(event.statusLabel) — \(event.projectName)")
    }

    private func updateToast(event: ClaudeToastEvent) {
        currentToastEvent = event
        // Re-present with updated content
        hideToast()
        presentToast(event: event)
    }

    private func hideToast() {
        toastWindow?.orderOut(nil)
        toastWindow = nil
        currentToastEvent = nil
        toastCancellables.removeAll()
    }

    /// Jump to the Claude Code terminal window.
    /// Matching priority: TTY (exact tab) > CWD in title (directory name) > activate app
    private func jumpToClaudeTerminal(event: ClaudeToastEvent) {
        // Dismiss the approval if it's a permission request (user will handle in terminal)
        if let approval = event.approval {
            claudeService.dismissApproval(approval)
        }

        hideToast()

        // Build the AppleScript with multiple matching strategies
        let tty = event.tty ?? ""
        // Extract directory name from CWD for title-based fallback matching
        let cwdDirName: String
        if let cwd = event.cwd, !cwd.isEmpty {
            cwdDirName = (cwd as NSString).lastPathComponent
        } else if event.projectName != "?" {
            cwdDirName = event.projectName
        } else {
            cwdDirName = ""
        }

        let script: String
        if let _ = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
            script = buildTerminalScript(tty: tty, cwdHint: cwdDirName)
        } else if let _ = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first {
            script = buildITermScript(tty: tty, cwdHint: cwdDirName)
        } else {
            // Last resort: activate any terminal
            let terminalApps = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
            for bundleID in terminalApps {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    app.activate()
                    return
                }
            }
            return
        }

        print("[NARC] 🔌 Jumping to terminal (tty=\(tty.isEmpty ? "none" : tty), cwd=\(cwdDirName))")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    print("[NARC] ⚠️ Jump script error: \(err)")
                }
            } catch {
                print("[NARC] ⚠️ Jump failed: \(error)")
            }
        }
    }

    /// Build AppleScript for Terminal.app with TTY-first, CWD-fallback matching
    private func buildTerminalScript(tty: String, cwdHint: String) -> String {
        return """
        tell application "Terminal"
            -- Strategy 1: match by TTY (most precise)
            \(tty.isEmpty ? "-- TTY not available, skip" : """
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            """)

            -- Strategy 2: match by CWD in window title (fallback)
            \(cwdHint.isEmpty ? "-- CWD hint not available, skip" : """
            repeat with w in windows
                if name of w contains "\(cwdHint)" then
                    set index of w to 1
                    activate
                    return
                end if
            end repeat
            """)

            -- Strategy 3: just activate (last resort)
            activate
        end tell
        """
    }

    /// Build AppleScript for iTerm2 with TTY-first, CWD-fallback matching
    private func buildITermScript(tty: String, cwdHint: String) -> String {
        return """
        tell application "iTerm2"
            -- Strategy 1: match by TTY
            \(tty.isEmpty ? "-- TTY not available, skip" : """
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select s
                            select t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
            """)

            -- Strategy 2: match by CWD in window name
            \(cwdHint.isEmpty ? "-- CWD hint not available, skip" : """
            repeat with w in windows
                if name of w contains "\(cwdHint)" then
                    set index of w to 1
                    activate
                    return
                end if
            end repeat
            """)

            activate
        end tell
        """
    }

    // Keep old method name for compatibility but it's now unused
    private func hideApprovalPanel() {
        hideToast()
    }

    private var approvalCancellables = Set<AnyCancellable>()

    // MARK: - Keyboard Navigation

    /// Install key event monitors for panel keyboard navigation.
    /// Uses BOTH local + global monitors to handle all scenarios:
    /// - Local monitor: catches events when NARC is the active app (returns nil to consume)
    /// - Global monitor: catches events when another app is active (panel is floating/non-activating)
    /// Handles: ↑↓ to select items, ↩ to activate, Esc to close, number keys for quick access.
    private func installKeyEventMonitor(narcScreen: NSScreen?) {
        removeKeyEventMonitor()

        // Handler logic shared by both monitors
        let handleKeyEvent: (NSEvent) -> Bool = { [weak self] event in
            guard let self = self,
                  let panel = self.panelWindow, panel.isVisible else {
                return false
            }

            let keyCode = event.keyCode

            switch keyCode {
            case 53: // Esc — close panel
                self.hidePanel()
                return true

            case 126: // ↑ — select previous item
                self.selectPreviousItem()
                return true

            case 125: // ↓ — select next item
                self.selectNextItem()
                return true

            case 36: // ↩ — activate selected item
                self.activateSelectedItem(narcScreen: narcScreen)
                return true

            case 48: // Tab — select next item (same as ↓)
                if event.modifierFlags.contains(.shift) {
                    self.selectPreviousItem() // Shift+Tab = select previous
                } else {
                    self.selectNextItem()
                }
                return true

            case 18...29: // Number keys 1-0 (keyCodes 18=1, 19=2, ..., 29=0)
                let numberMap: [UInt16: Int] = [
                    18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
                    22: 5, 26: 6, 28: 7, 25: 8, 29: 9
                ]
                if let index = numberMap[keyCode] {
                    self.activateItemAtIndex(index, narcScreen: narcScreen)
                }
                return true

            default:
                return false
            }
        }

        // Local monitor: when NARC is the active app, consume the event (return nil)
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyEvent(event) {
                return nil // consume the event
            }
            return event
        }

        // Global monitor: when another app is active, the panel is still visible
        // (floating non-activating panel). We need this to handle keyboard input
        // after the user has activated another window and then re-opened the panel.
        globalKeyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handleKeyEvent(event)
        }
    }

    /// Remove both local and global key event monitors.
    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        if let monitor = globalKeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyEventMonitor = nil
        }
    }

    /// Build the flat list of all activatable items in the panel.
    private func allPanelItems() -> [PanelItem] {
        var items: [PanelItem] = []

        // Monitoring section
        for state in appMonitor.filteredStates {
            if state.isRunning {
                items.append(.monitoring(state))
            }
        }

        // Pinned section
        for pinned in pinnedWindowService.pinnedWindows {
            items.append(.pinned(pinned))
        }

        return items
    }

    private func selectNextItem() {
        let items = allPanelItems()
        guard !items.isEmpty else { return }
        let current = keyboardSelection.selectedIndex
        keyboardSelection.selectedIndex = min(current + 1, items.count - 1)
    }

    private func selectPreviousItem() {
        let items = allPanelItems()
        guard !items.isEmpty else { return }
        let current = keyboardSelection.selectedIndex
        keyboardSelection.selectedIndex = max(current - 1, 0)
    }

    private func activateSelectedItem(narcScreen: NSScreen?) {
        let items = allPanelItems()
        let index = keyboardSelection.selectedIndex
        guard index >= 0 && index < items.count else { return }
        activatePanelItem(items[index], narcScreen: narcScreen)
    }

    private func activateItemAtIndex(_ index: Int, narcScreen: NSScreen?) {
        let items = allPanelItems()
        guard index >= 0 && index < items.count else { return }
        keyboardSelection.selectedIndex = index
        activatePanelItem(items[index], narcScreen: narcScreen)
    }

    private func activatePanelItem(_ item: PanelItem, narcScreen: NSScreen?) {
        switch item {
        case .monitoring(let state):
            appMonitor.activateApp(
                bundleID: state.app.bundleID,
                summonToScreen: narcScreen
            )
        case .pinned(let pinned):
            pinnedWindowService.activatePinnedWindow(
                pinned,
                summonToScreen: narcScreen
            )
        }
        hidePanel()
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
