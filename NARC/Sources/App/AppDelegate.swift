import Cocoa
import SwiftUI
import Combine
import UserNotifications

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
    private let moduleRegistry = ModuleRegistry()
    @MainActor private lazy var assistantStore = AssistantStore()
    @MainActor private var quickCaptureWindow: QuickCaptureWindow?
    @MainActor private var assistantHubWindow: AssistantHubWindow?
    @MainActor private var onboardingWindow: OnboardingWindow?
    private let claudeService = ClaudeSessionService.shared
    /// Owned at the app level (not by DashboardView) so that closing the
    /// dashboard window doesn't tear down running terminals. The user can
    /// dismiss the window and re-open it later to find their tabs intact.
    private let terminalManager = TerminalSessionManager()
    /// Drives FloatingWidgetView's `.dragging` state transitions per spec §2.
    /// Flipped by FloatingWidgetWindow's onDragStart / onDragEnd callbacks.
    private let widgetDragState = WidgetDragState()

    // MARK: - App Lifecycle

    /// Checks all required system permissions on startup. If any are missing,
    /// shows a single consolidated alert explaining what won't work and how to
    /// fix it. Runs once per launch, before any features initialize.
    private func checkRequiredPermissions() {
        // UNUserNotificationCenter.current() crashes if the process has no
        // bundle identifier (e.g. `swift run`). Guard early — the system-
        // notifications setup method below does the same.
        let notificationsAvailable = Bundle.main.bundleIdentifier != nil

        // Brief delay then check all permissions and alert if any are missing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            let missingAccess = !AXIsProcessTrusted()

            guard notificationsAvailable else {
                // No bundle ID — skip notification checks entirely.
                if missingAccess {
                    if DevRuntimeOptions.terminalHost {
                        print("[NARC] ⚠️ Terminal-host dev mode needs Accessibility on the terminal app launching NARC.")
                        print("[NARC]    Grant Accessibility to Terminal / iTerm / Codex, then restart this script.")
                    } else {
                        self.showPermissionsAlert(missingAccessibility: true, missingNotifications: false)
                    }
                } else {
                    print("[NARC] ✅ Accessibility OK (notifications unavailable — no bundle ID)")
                }
                return
            }

            let noteCenter = UNUserNotificationCenter.current()
            noteCenter.getNotificationSettings { settings in
                let missingNotifs = (settings.authorizationStatus == .denied)

                guard missingAccess || missingNotifs else {
                    print("[NARC] ✅ All permissions OK")
                    return
                }

                DispatchQueue.main.async {
                    self.showPermissionsAlert(
                        missingAccessibility: missingAccess,
                        missingNotifications: missingNotifs
                    )
                }
            }

            // Always request notification auth on launch.
            noteCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                print("[NARC] 🔔 Notification permission granted=\(granted)")
            }
        }
    }

    /// Show a single alert listing missing permissions and their impact.
    private func showPermissionsAlert(missingAccessibility: Bool, missingNotifications: Bool) {
        let alert = NSAlert()
        alert.messageText = "NARC 需要系统权限"
        alert.alertStyle = .warning

        var lines: [String] = []
        if missingAccessibility {
            lines.append("⚠️ 辅助功能 — 未授权")
            lines.append("  影响：窗口管理、钉选和相关快捷键")
        }
        if missingNotifications {
            lines.append("⚠️ 通知 — 未授权")
            lines.append("  影响：Claude 事件横幅提醒")
        }
        alert.informativeText = """
            以下权限未授权，部分功能将无法正常工作：

            \(lines.joined(separator: "\n"))

            打开系统设置 → 隐私与安全性，找到 NARC 并开启对应权限。
            """

        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后设置")

        if alert.runModal() == .alertFirstButtonReturn {
            // Open Privacy & Security → Accessibility (the most critical one)
            if missingAccessibility {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            } else {
                // If only notifications missing, open Notifications prefs
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                )
            }
        }
    }

    // MARK: - Menu Bar

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[NARC] 🚀 App launching...")

        if DevRuntimeOptions.terminalHost {
            // Terminal-host dev mode mirrors the early high-frequency workflow:
            // no Dock icon, but keep AX-powered hotkeys and window pinning.
            NSApp.setActivationPolicy(.accessory)
            print("[NARC] 🧪 Terminal-host dev mode — Dock icon hidden; AX features remain enabled.")
        } else {
            // Regular Dock app — reopening from the Dock fronts Assistant.
            NSApp.setActivationPolicy(.regular)
        }

        let shouldPresentOnboarding = OnboardingPresentationPolicy.shouldPresent(
            hasCompleted: UserDefaults.standard.bool(
                forKey: OnboardingPresentationPolicy.completionKey
            )
        )

        if DevRuntimeOptions.noAX {
            print("[NARC] 🧪 NARC_DEV_NO_AX=1 — skipping permission prompts and AX-dependent startup paths.")
        } else if !shouldPresentOnboarding {
            // Existing users keep the consolidated permission check. First-run
            // users get the guide instead of stacked alerts and System Settings.
            // Show a clear alert once so the user knows what to fix, rather than
            // silently failing for feature after feature.
            checkRequiredPermissions()
        }

        print("[NARC] Setting up menu bar icon...")
        setupMenuBarIcon()

        print("[NARC] Setting up floating widget...")
        setupFloatingWidget()

        print("[NARC] Starting app monitor...")
        appMonitor.startMonitoring()

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
        hotkeyService.onQuickCaptureHotkeyPressed = { [weak self] in
            Task { @MainActor in
                self?.showQuickCapture()
            }
        }
        hotkeyService.onLayoutHotkeyPressed = { layout in
            WindowManagerService.moveActiveWindow(to: layout)
        }
        if DevRuntimeOptions.noAX {
            print("[NARC] 🧪 Registering panel/quick-capture hotkeys for dev no-AX mode.")
            hotkeyService.registerDevNoAXHotkeys()
        } else {
            print("[NARC] Registering global hotkeys...")
            hotkeyService.registerGlobalHotkeys(
                promptForAccessibility: !shouldPresentOnboarding
            )
        }

        // Start Claude Code session monitoring
        claudeService.onAttentionNeeded = { [weak self] reason in
            guard let self = self else { return }
            switch reason {
            case .permissionRequest:
                // Workspace-owned Claude sessions surface in the Workspace sidebar.
                break
            case .interactiveQuestion(let sessionId, _):
                // 回答（阻塞型提问）：中等强度 = 响一声（按会话去重）。内外一致。
                self.playAnswerSound(for: sessionId)
            case .stopped:
                // Workspace-owned Claude sessions surface in the Workspace sidebar.
                break
            case .error:
                // No standalone Claude notification surface; round cards will own this later.
                break
            case .stale:
                // 卡住：仅侧边栏体现，不打扰
                break
            }
        }
        claudeService.startListening()
        // Opt-in only — default OFF. Global drag-snap snaps the frontmost window
        // on ANY left-drag near a screen edge (selecting text, dragging a file,
        // a slider…), so it must not run unless the user explicitly enabled it.
        if !DevRuntimeOptions.noAX, UserDefaults.standard.bool(forKey: "windowSnapEnabled") {
            WindowSnapService.shared.start()
        } else if DevRuntimeOptions.noAX {
            print("[NARC] 🧪 Window snap disabled for dev no-AX mode.")
        }

        if DevRuntimeOptions.noAX {
            print("[NARC] 🧪 System notification authorization disabled for dev no-AX mode.")
        } else {
            // Register for macOS system notifications (for click-to-jump support)
            setupSystemNotifications(
                requestAuthorization: !shouldPresentOnboarding
            )
        }

        // Listen for preferences-triggered actions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResetWidgetPosition),
            name: .resetWidgetPosition,
            object: nil
        )

        if shouldPresentOnboarding, !DevRuntimeOptions.noAX {
            Task { @MainActor in
                showOnboarding(force: false)
            }
        }

        print("[NARC] ✅ App launch complete. Look for the floating widget (bottom-right) and menu bar icon.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        appMonitor.stopMonitoring()
        claudeService.stopListening()
    }

    /// Keep the app alive when its windows are closed; the menu bar item and
    /// floating widget remain available as Assistant entry points.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Dock icon clicked (or `open -a NARC` while already running). If no window
    /// is visible, open Assistant. Otherwise let macOS handle un-minimize.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            Task { @MainActor in
                showAssistantHub()
            }
        }
        return true
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
        let guideItem = NSMenuItem(
            title: "User Guide",
            action: #selector(showUserGuide),
            keyEquivalent: ""
        )
        guideItem.target = self
        menu.addItem(guideItem)
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About NARC", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NARC", action: #selector(quitApp), keyEquivalent: "q"))

        statusBarItem?.menu = menu
    }

    // MARK: - Floating Widget

    private func setupFloatingWidget() {
        let widgetView = FloatingWidgetContainer(
            appMonitor: appMonitor,
            dragState: widgetDragState
        )

        // The panel canvas is 128×128 (visible 48pt circle + 40pt of
        // transparent shadow padding on each side). The hostingView fills
        // the full canvas; only the central 48pt is hit-testable thanks to
        // FirstMouseView.hitTest. Without this padding, SwiftUI's drop
        // shadow gets clipped at the host's frame edge and shows up as a
        // hard rectangular halo around the circle (the "方框" bug).
        let canvas = FloatingWidgetWindow.canvasSize
        let widgetSide = FloatingWidgetWindow.widgetSize
        let widgetInset = (canvas - widgetSide) / 2  // 40pt

        let hostingView = NSHostingView(rootView: widgetView)
        hostingView.frame = NSRect(x: 0, y: 0, width: canvas, height: canvas)
        // Force the hosting view's backing layer to be transparent — without
        // this, NSHostingView can render an opaque default fill that shows up
        // as a square chrome around the round widget on some macOS versions.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        // Position: bottom-right corner of the screen, or saved position if it exists.
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let screenFrame = activeScreen?.visibleFrame ?? .zero
        let defaultX = screenFrame.maxX - widgetSide - 40 - widgetInset
        let defaultY = screenFrame.minY + 100 - widgetInset
        let savedOrigin = UserDefaults.standard.string(forKey: "widgetOrigin")
        let origin: NSPoint
        if let saved = savedOrigin {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let savedPoint = NSPoint(x: parts[0], y: parts[1])
                // Only use saved position if it's on a visible screen
                if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -50, dy: -50).contains(savedPoint) }) {
                    origin = savedPoint
                } else {
                    origin = NSPoint(x: defaultX, y: defaultY)
                }
            } else {
                origin = NSPoint(x: defaultX, y: defaultY)
            }
        } else {
            origin = NSPoint(x: defaultX, y: defaultY)
        }

        // Spec §7: window configuration is fully encapsulated in FloatingWidgetWindow.init().
        let window = FloatingWidgetWindow()
        window.setFrameOrigin(origin)
        window.contentView = hostingView
        window.orderFrontRegardless()

        // Handle tap at AppKit level — this fires reliably even on the first click
        // when NARC is not the frontmost application (bypasses SwiftUI gesture issues)
        window.onWidgetTapped = { [weak self] in
            self?.togglePanel()
        }

        // Right-click (or Ctrl+left-click) exposes the two durable destinations:
        // Assistant and Preferences.
        window.onWidgetRightClicked = { [weak self] event in
            self?.showWidgetContextMenu(for: event)
        }

        // Spec §2: drag flips state to .dragging; bloom + ripple + mark hide
        // and the widget tilts/scales (spec §5).
        window.onDragStart = { [weak self] in
            self?.widgetDragState.isDragging = true
        }
        window.onDragEnd = { [weak self] in
            self?.widgetDragState.isDragging = false
        }

        // When the widget is dragged, reposition the panel and persist the origin.
        window.onWindowMoved = { [weak self] in
            self?.repositionPanel()
            if let win = self?.floatingWindow {
                let origin = win.frame.origin
                UserDefaults.standard.set("\(Int(origin.x)),\(Int(origin.y))", forKey: "widgetOrigin")
            }
        }

        self.floatingWindow = window

        // Observe widget size changes from Preferences and resize the window.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let newSize = FloatingWidgetWindow.widgetSize
            self?.floatingWindow?.applyWidgetSize(newSize)
        }
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

        // The widget panel is 128×128 with a 40pt transparent padding around
        // the visible 48pt circle. To place the popup adjacent to the visible
        // circle (not the invisible frame edge), strip the inset.
        let widgetInset = (FloatingWidgetWindow.canvasSize - FloatingWidgetWindow.widgetSize) / 2
        let visibleTop = widgetFrame.maxY - widgetInset
        let visibleBottom = widgetFrame.minY + widgetInset

        // Default: panel above the widget, centered horizontally
        var panelX = widgetFrame.midX - panelWidth / 2
        var panelY = visibleTop + 8

        // If panel would go above the screen, show it below the widget
        if panelY + panelHeight > screenFrame.maxY {
            panelY = visibleBottom - panelHeight - 8
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
        // Reset keyboard selection when opening panel.
        // wantsKeyboardNavigation starts false — the user must explicitly signal
        // intent (↑↓/Tab or click in panel) before number keys / Enter work.
        keyboardSelection.selectedIndex = -1
        keyboardSelection.wantsKeyboardNavigation = false

        let panelContentView = PanelView(
            appMonitor: appMonitor,
            windowManager: windowManager,
            pinnedWindowService: pinnedWindowService,
            onClose: { [weak self] in self?.hidePanel() },
            onOpenPreferences: { [weak self] in self?.openPreferences() },
            onOpenAssistant: { [weak self] in
                self?.hidePanel()
                Task { @MainActor in
                    self?.showAssistantHub()
                }
            },
            onOpenQuickCapture: { [weak self] in
                self?.hidePanel()
                Task { @MainActor in
                    self?.showQuickCapture()
                }
            },
            narcScreen: narcScreen,
            keyboardSelection: keyboardSelection
        )

        let hostingView = NSHostingView(rootView: panelContentView)
        // Make the hosting view's layer background transparent so SwiftUI material shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let panel = PanelWindow(
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

        // When the user clicks anywhere in the panel, they've shown intent to
        // interact — un-gate keyboard navigation so ↑↓/numbers/Enter work.
        panel.onMouseDown = { [weak self] in
            self?.keyboardSelection.wantsKeyboardNavigation = true
        }

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

    // MARK: - Personal Assistant

    @MainActor
    private func showQuickCapture() {
        guard moduleRegistry.module(id: "assistant") != nil else { return }

        if quickCaptureWindow == nil {
            quickCaptureWindow = QuickCaptureWindow(store: assistantStore)
        }
        quickCaptureWindow?.present()
    }

    @MainActor
    private func showAssistantHub() {
        guard moduleRegistry.module(id: "assistant") != nil else { return }

        if assistantHubWindow == nil {
            assistantHubWindow = AssistantHubWindow(
                store: assistantStore,
                onQuickCapture: { [weak self] in
                    Task { @MainActor in
                        self?.showQuickCapture()
                    }
                }
            )
        }
        assistantHubWindow?.present()
    }

    // MARK: - Claude Dashboard (standalone window)

    private var dashboardWindow: DashboardWindow?

    /// Retained for one release as the rollback boundary for Workspace.
    private func toggleDashboard() {
        if let window = dashboardWindow, window.isVisible {
            hideDashboard()
        } else {
            showDashboard()
        }
    }

    /// Show (or front) the dashboard window. Lazy-creates on first call.
    /// If `selectingNarcSessionId` is non-nil and matches an existing
    /// terminal tab, that tab becomes the active one — used when the user
    /// clicks a Claude notification in the panel and expects to land on
    /// the originating session, not whatever was last selected.
    ///
    /// The window always opens on the same screen as the floating widget
    /// so the user doesn't have to hunt across displays.
    private func showDashboard(selectingNarcSessionId narcSessionId: String? = nil) {
        // Figure out which screen the dashboard should land on.
        // Priority: floating widget screen > mouse screen > main screen.
        let targetScreen: NSScreen? = {
            if let widgetFrame = floatingWindow?.frame {
                return NSScreen.screens.first(where: { $0.frame.contains(widgetFrame.origin) })
            }
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
        }()

        if let window = dashboardWindow {
            // If the window already exists, bring it to the target screen
            // so it doesn't stay stranded on a different display.
            if let screen = targetScreen {
                let sf = screen.visibleFrame
                var frame = window.frame
                frame.origin.x = sf.midX - frame.width / 2
                frame.origin.y = sf.midY - frame.height / 2
                window.setFrame(frame, display: false)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            applyTabSelectionIfMatches(narcSessionId)
            return
        }

        let window = DashboardWindow()
        let dashboardView = DashboardView(
            claudeService: claudeService,
            terminals: terminalManager
        )
        window.contentView = NSHostingView(rootView: dashboardView)
        window.onShouldClose = { [weak self] in
            return self?.handleWorkspaceShouldClose() ?? true
        }

        // Center on the target screen
        if let screen = targetScreen {
            let sf = screen.visibleFrame
            var frame = window.frame
            frame.origin.x = sf.midX - frame.width / 2
            frame.origin.y = sf.midY - frame.height / 2
            window.setFrame(frame, display: false)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.dashboardWindow = window
        applyTabSelectionIfMatches(narcSessionId)
    }

    /// Push the desired tab selection into the manager. Resolved match-by-match
    /// so we don't clobber the user's current selection if the notification's
    /// session no longer exists in the workspace (e.g. external iTerm session).
    private func applyTabSelectionIfMatches(_ narcSessionId: String?) {
        guard let raw = narcSessionId,
              let uuid = UUID(uuidString: raw),
              terminalManager.sessions.contains(where: { $0.id == uuid }) else {
            return
        }
        // Defer one runloop turn so DashboardView has wired its onAppear /
        // onChange before we mutate; otherwise the very-first-summon path
        // would set selectedId before the view subscribed.
        DispatchQueue.main.async { [weak self] in
            self?.terminalManager.selectedId = uuid
        }
    }

    private func hideDashboard() {
        dashboardWindow?.orderOut(nil)
    }

    // MARK: - Claude Toast Notification (stacked)

    /// Per-session toast windows. Each external Claude event (running outside
    /// the workspace) gets its own dismissable popup at the top-right of the
    /// active screen. Workspace-internal events are NOT shown here — they
    /// surface via the Dashboard sidebar's attention bar instead.
    private var toastWindows: [String: NSPanel] = [:]
    /// Mirror of the events behind toastWindows, kept so we can rebuild a
    /// toast in place when its underlying event is updated.
    private var toastEvents: [String: ClaudeToastEvent] = [:]
    /// Combine subscription that drives `syncToasts()` whenever the service's
    /// pendingApprovals or notifications arrays change (new event arrives,
    /// user dismisses one, etc.).
    private var toastSyncCancellables = Set<AnyCancellable>()

    /// 仅"回答"态(阻塞型提问)触发的轻音效，按会话 5s 去重，避免连响成噪音。
    private var lastAnswerSoundAt: [String: Date] = [:]
    private func playAnswerSound(for sessionId: String) {
        let now = Date()
        if let last = lastAnswerSoundAt[sessionId], now.timeIntervalSince(last) < 5 { return }
        lastAnswerSoundAt[sessionId] = now
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    /// Hook the service's published arrays so toasts auto-add/auto-remove
    /// when the underlying data changes. Called once from
    /// `applicationDidFinishLaunching`.
    private func setupToastSync() {
        Publishers.CombineLatest(
            claudeService.$pendingApprovals,
            claudeService.$notifications
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.syncToasts()
        }
        .store(in: &toastSyncCancellables)
    }

    /// Reconcile the on-screen toast stack against the desired state derived
    /// from `claudeService`. Adds toasts for new external events, removes
    /// toasts whose underlying event is gone, repositions surviving ones.
    private func syncToasts() {
        // Build desired event list — external only (narcSessionId == nil).
        // Order: pending approvals first (more urgent), then notifications,
        // both newest-first so the freshest event sits on top of the stack.
        var desired: [(String, ClaudeToastEvent)] = []

        for approval in claudeService.pendingApprovals.reversed() where approval.narcSessionId == nil {
            // Use a per-event key so two pending approvals from the same session
            // (rare but possible for sequential PreToolUse + PermissionRequest)
            // both get their own toast.
            let key = "approval:\(approval.id.uuidString)"
            let event = ClaudeToastEvent(
                type: .permissionRequest,
                projectName: approval.projectName,
                detail: approval.commandDescription,
                tty: approval.tty,
                cwd: approval.cwd,
                sessionId: approval.sessionId,
                approval: approval
            )
            desired.append((key, event))
        }

        for notification in claudeService.notifications.reversed()
            where notification.narcSessionId == nil && notification.type == .error {
            let key = "notif:\(notification.id.uuidString)"
            let type: ClaudeToastEvent.EventType
            switch notification.type {
            case .stopped: type = .waitingForInput
            case .error:   type = .error
            case .stale:   type = .stale
            }
            let event = ClaudeToastEvent(
                type: type,
                projectName: notification.projectName,
                detail: notification.message,
                tty: notification.tty,
                cwd: notification.cwd,
                sessionId: notification.sessionId
            )
            desired.append((key, event))
        }

        let desiredKeys = Set(desired.map { $0.0 })

        // Remove toasts whose underlying event is gone (user dismissed it
        // via Allow/Deny/Jump, or it timed out, etc.).
        for (key, panel) in toastWindows where !desiredKeys.contains(key) {
            panel.orderOut(nil)
            toastWindows[key] = nil
            toastEvents[key] = nil
        }

        // Add missing toasts and reposition all surviving ones.
        for (index, (key, event)) in desired.enumerated() {
            if let existing = toastWindows[key] {
                repositionToast(existing, atIndex: index)
                toastEvents[key] = event
            } else {
                presentToast(event: event, key: key, atIndex: index)
            }
        }
    }

    private func presentToast(event: ClaudeToastEvent, key: String, atIndex index: Int) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
        let screenFrame = screen.visibleFrame

        let toastWidth: CGFloat = 380
        let toastHeight: CGFloat = 56
        let gap: CGFloat = 8
        let x = screenFrame.maxX - toastWidth - 16
        let y = screenFrame.maxY - toastHeight - 12 - CGFloat(index) * (toastHeight + gap)

        let toastView = ClaudeToastView(
            event: event,
            onJump: { [weak self] in
                self?.jumpToClaudeTerminal(event: event, key: key)
            },
            onDismiss: { [weak self] in
                self?.dismissToast(key: key, alsoClearService: true)
            },
            onAllow: event.approval != nil ? { [weak self] in
                guard let approval = event.approval else { return }
                self?.claudeService.approve(approval)
                // syncToasts will fire when pendingApprovals changes
            } : nil,
            onDeny: event.approval != nil ? { [weak self] in
                guard let approval = event.approval else { return }
                self?.claudeService.deny(approval)
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

        toastWindows[key] = panel
        toastEvents[key] = event

        print("[NARC] 🔔 Toast: \(event.statusLabel) — \(event.projectName) [stack #\(index)]")
    }

    private func repositionToast(_ panel: NSPanel, atIndex index: Int) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main!
        let screenFrame = screen.visibleFrame

        let toastWidth: CGFloat = 380
        let toastHeight: CGFloat = 56
        let gap: CGFloat = 8
        let x = screenFrame.maxX - toastWidth - 16
        let y = screenFrame.maxY - toastHeight - 12 - CGFloat(index) * (toastHeight + gap)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Hide a single toast by key. If `alsoClearService` is true, also clear
    /// the underlying event from the service so the floating-widget badge
    /// count reflects the dismissal.
    private func dismissToast(key: String, alsoClearService: Bool) {
        guard let event = toastEvents[key] else { return }

        if alsoClearService {
            // Strip the prefix to figure out which array to mutate.
            if key.hasPrefix("approval:"), let approval = event.approval {
                // Closing the socket lets the CLI prompt take over.
                claudeService.dismissApproval(approval)
            } else if key.hasPrefix("notif:") {
                // Find the matching notification by sessionId + timestamp-ish.
                if let notif = claudeService.notifications.first(where: { $0.sessionId == event.sessionId }) {
                    claudeService.dismissNotification(notif.id)
                }
            }
        }
        // syncToasts will pick up the array change and tear down the window.
        // For an immediate visual response if nothing else fires, also remove
        // the panel here.
        toastWindows[key]?.orderOut(nil)
        toastWindows[key] = nil
        toastEvents[key] = nil
    }

    private func hideAllToasts() {
        for panel in toastWindows.values {
            panel.orderOut(nil)
        }
        toastWindows.removeAll()
        toastEvents.removeAll()
    }

    /// Jump to the source Claude Code terminal window — only ever called for
    /// external events (workspace-internal events don't get toasts in the
    /// first place). Delegates to TerminalJumper for AppleScript orchestration.
    private func jumpToClaudeTerminal(event: ClaudeToastEvent, key: String) {
        // If the event was an approval, dismissing closes the socket so the
        // CLI prompt takes over — the user wants to handle it in the terminal.
        dismissToast(key: key, alsoClearService: true)

        TerminalJumper.jump(
            tty: event.tty,
            cwd: event.cwd,
            projectName: event.projectName
        )
    }

    // MARK: - System Notifications

    /// UserInfo keys carried in UNNotificationContent so the delegate can jump back
    /// to the right terminal when the user clicks the banner.
    private enum NotifKey {
        static let tty = "narc.tty"
        static let cwd = "narc.cwd"
        static let project = "narc.project"
        static let sessionId = "narc.sessionId"
    }

    /// Whether UNUserNotificationCenter is usable. False under `swift run`
    /// (raw executable, no bundle identifier — accessing the notification
    /// center throws an NSException). True in a proper .app bundle.
    private var systemNotificationsAvailable = false

    /// Request authorization and register as the delegate so click-to-jump works.
    private func setupSystemNotifications(requestAuthorization: Bool = true) {
        // UNUserNotificationCenter.current() requires a real .app bundle. When
        // running via `swift run`, mainBundle has no bundleIdentifier and the
        // first access throws (NSInternalInconsistencyException). Guard against
        // that so the dev workflow doesn't crash on launch.
        guard Bundle.main.bundleIdentifier != nil else {
            print("[NARC] ⚠️  No bundle identifier (running from `swift run`?) — system notifications disabled.")
            print("[NARC]    Workspace-internal status indicators still work.")
            return
        }

        systemNotificationsAvailable = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        guard requestAuthorization else {
            print("[NARC] 🔔 Notification authorization deferred until after onboarding.")
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NARC] ⚠️ Notification auth error: \(error)")
            } else {
                print("[NARC] 🔔 Notification auth granted=\(granted)")
            }
        }
    }

    /// Generic poster — builds a content object and submits it to the center.
    private func postNotification(
        title: String,
        body: String,
        tty: String?,
        cwd: String?,
        projectName: String?,
        sessionId: String?,
        sound: UNNotificationSound? = .default
    ) {
        guard systemNotificationsAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        var userInfo: [String: Any] = [:]
        if let tty = tty { userInfo[NotifKey.tty] = tty }
        if let cwd = cwd { userInfo[NotifKey.cwd] = cwd }
        if let projectName = projectName { userInfo[NotifKey.project] = projectName }
        if let sessionId = sessionId { userInfo[NotifKey.sessionId] = sessionId }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NARC] ⚠️ Notification post failed: \(error)")
            }
        }
    }

    private func postErrorNotification() {
        guard let notif = claudeService.notifications.last else { return }
        postNotification(
            title: "❌ Claude 出错 — \(notif.projectName)",
            body: notif.message,
            tty: notif.tty,
            cwd: notif.cwd,
            projectName: notif.projectName,
            sessionId: notif.sessionId
        )
    }

    private var approvalCancellables = Set<AnyCancellable>()

    // MARK: - Widget Context Menu

    static let workspaceCloseActionKey = "workspaceCloseAction"
    private enum WorkspaceCloseAction: String {
        case ask       // default — show alert every time
        case terminate // kill all terminals + close
        case hide      // keep terminals running, just hide window
    }

    /// Show a right-click context menu on the floating widget.
    private func showWidgetContextMenu(for event: NSEvent) {
        let menu = NSMenu(title: "")

        let assistantItem = NSMenuItem(
            title: "打开 Assistant",
            action: #selector(widgetMenuOpenAssistant),
            keyEquivalent: ""
        )
        assistantItem.target = self
        assistantItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(assistantItem)

        let guideItem = NSMenuItem(
            title: "使用指南",
            action: #selector(widgetMenuOpenUserGuide),
            keyEquivalent: ""
        )
        guideItem.target = self
        guideItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        menu.addItem(guideItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "偏好设置…",
            action: #selector(widgetMenuOpenPreferences),
            keyEquivalent: ""
        )
        prefsItem.target = self
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(prefsItem)

        // Pop up at the click location. Convert window-relative point to screen coords.
        let clickLocationInWindow = event.locationInWindow
        let screenLocation = floatingWindow?.convertPoint(toScreen: clickLocationInWindow)
            ?? NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: screenLocation, in: nil)
    }

    @objc private func widgetMenuOpenAssistant() {
        Task { @MainActor in
            showAssistantHub()
        }
    }

    @objc private func widgetMenuOpenPreferences() {
        openPreferences()
    }

    @objc private func widgetMenuOpenUserGuide() {
        Task { @MainActor in
            showOnboarding(force: true)
        }
    }

    // MARK: - Workspace Close Interception

    /// Called by DashboardWindow.windowShouldClose. If there are live terminal
    /// sessions, shows a confirmation alert (first time only — subsequent closes
    /// honour the saved preference).
    private func handleWorkspaceShouldClose() -> Bool {
        let hasLiveSessions = terminalManager.sessions.contains { $0.isAlive }
        guard hasLiveSessions else {
            // No live sessions — allow close without asking.
            return true
        }

        let savedRaw = UserDefaults.standard.string(forKey: Self.workspaceCloseActionKey)
            ?? WorkspaceCloseAction.ask.rawValue
        let savedAction = WorkspaceCloseAction(rawValue: savedRaw) ?? .ask

        switch savedAction {
        case .terminate:
            terminalManager.terminateAll()
            hideDashboard()
            return true
        case .hide:
            hideDashboard()
            return true
        case .ask:
            return showWorkspaceCloseAlert()
        }
    }

    /// Show the "终端仍在后台运行" confirmation alert.
    /// Returns `true` to allow close, `false` to cancel.
    private func showWorkspaceCloseAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "终端仍在后台运行"
        alert.informativeText = """
            关闭窗口不会自动结束终端进程。

            选择「关闭终端」将结束所有终端进程。
            选择「收起窗口」将隐藏窗口但保留终端运行。
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "收起窗口")     // default (rightmost)
        alert.addButton(withTitle: "取消")          // middle
        alert.addButton(withTitle: "关闭终端")      // leftmost (destructive-ish)

        // "记住我的选择" checkbox
        alert.suppressionButton?.title = "记住我的选择，不再询问"
        alert.showsSuppressionButton = true

        let response = alert.runModal()

        // Save preference if the user checked "记住"
        if let suppressionButton = alert.suppressionButton,
           suppressionButton.state == .on {
            let action: WorkspaceCloseAction
            switch response {
            case .alertFirstButtonReturn:  // 收起窗口
                action = .hide
            case .alertThirdButtonReturn:  // 关闭终端
                action = .terminate
            default:
                // User picked "取消" — don't save cancel as a preference.
                return false
            }
            UserDefaults.standard.set(action.rawValue, forKey: Self.workspaceCloseActionKey)
        }

        switch response {
        case .alertFirstButtonReturn:  // 收起窗口
            hideDashboard()
            return true
        case .alertThirdButtonReturn:  // 关闭终端
            terminalManager.terminateAll()
            hideDashboard()
            return true
        default:  // 取消 (middle button or Escape)
            return false
        }
    }

    // MARK: - Keyboard Navigation

    /// Install key event monitors for panel keyboard navigation.
    /// Uses BOTH local + global monitors to handle all scenarios:
    /// - Local monitor: catches events when NARC is the active app (returns nil to consume)
    /// - Global monitor: catches events when another app is active (panel is floating/non-activating)
    /// Handles: ↑↓ to select items, ↩ to activate, Esc to close, number keys for quick access.
    ///
    /// CRITICAL: addLocalMonitorForEvents is APP-WIDE — it sees keyDown for every
    /// window in NARC, not just the panel. We must short-circuit when the event
    /// is targeted at any other window (Dashboard, Preferences, etc.) so the
    /// terminal in the workspace can receive characters like `-` and Enter that
    /// happen to overlap with our numeric/Return shortcuts.
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

            case 126: // ↑ — select previous item (also signals nav intent)
                self.keyboardSelection.wantsKeyboardNavigation = true
                self.selectPreviousItem()
                return true

            case 125: // ↓ — select next item (also signals nav intent)
                self.keyboardSelection.wantsKeyboardNavigation = true
                self.selectNextItem()
                return true

            case 36: // ↩ — activate selected item (gated: user must have signaled nav intent)
                guard self.keyboardSelection.wantsKeyboardNavigation else { return false }
                self.activateSelectedItem(narcScreen: narcScreen)
                return true

            case 48: // Tab — select next item (same as ↓), also signals nav intent
                self.keyboardSelection.wantsKeyboardNavigation = true
                if event.modifierFlags.contains(.shift) {
                    self.selectPreviousItem() // Shift+Tab = select previous
                } else {
                    self.selectNextItem()
                }
                return true

            // Number keys 1–0. Listed explicitly because the surrounding
            // keyCodes 24 (`=`) and 27 (`-`) are NOT digits and must not be
            // swallowed — otherwise typing a `-` in the workspace terminal
            // when the panel happens to still be visible would silently
            // disappear.
            //
            // Gated behind wantsKeyboardNavigation: number-key activation is
            // only honored after the user has signaled intent (↑↓/Tab or
            // click). This prevents accidental activation when the panel opens
            // while the user is mid-typing in another app.
            case 18, 19, 20, 21, 22, 23, 25, 26, 28, 29:
                guard self.keyboardSelection.wantsKeyboardNavigation else { return false }
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

        // Local monitor: when NARC is the active app, consume the event (return nil).
        // The `event.window === panelWindow` guard is critical — without it,
        // every keyDown into the Dashboard window would be filtered through
        // panel-navigation logic (and Enter / `-` / `=` etc. would get eaten).
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if let eventWindow = event.window,
               eventWindow !== self.panelWindow {
                return event
            }
            if handleKeyEvent(event) {
                return nil // consume the event
            }
            return event
        }

        // Global monitor: when another app is active, the panel is still visible
        // (floating non-activating panel). We need this to handle keyboard input
        // after the user has activated another window and then re-opened the panel.
        // No window-target guard here because global monitor only fires for events
        // outside NARC entirely; observation-only (cannot consume).
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

    @objc private func showUserGuide() {
        Task { @MainActor in
            showOnboarding(force: true)
        }
    }

    @MainActor
    private func showOnboarding(force: Bool) {
        let hasCompleted = UserDefaults.standard.bool(
            forKey: OnboardingPresentationPolicy.completionKey
        )
        guard OnboardingPresentationPolicy.shouldPresent(
            hasCompleted: hasCompleted,
            force: force
        ) else {
            return
        }

        if let window = onboardingWindow {
            window.present()
            return
        }

        let window = OnboardingWindow(
            hotkeyService: hotkeyService,
            onOpenAssistant: { [weak self] in
                Task { @MainActor in
                    self?.showAssistantHub()
                }
            },
            onOpenAccessibilitySettings: {
                guard let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) else {
                    return
                }
                NSWorkspace.shared.open(url)
            },
            onDismiss: { [weak self] in
                UserDefaults.standard.set(
                    true,
                    forKey: OnboardingPresentationPolicy.completionKey
                )
                self?.onboardingWindow = nil
            }
        )
        onboardingWindow = window
        window.present()
    }

    private var preferencesWindow: PreferencesWindow?

    @objc private func handleResetWidgetPosition() {
        UserDefaults.standard.removeObject(forKey: "widgetOrigin")
        guard let window = floatingWindow else { return }
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let screenFrame = activeScreen?.visibleFrame ?? .zero
        let widgetSide = FloatingWidgetWindow.widgetSize
        let widgetInset = (FloatingWidgetWindow.canvasSize - widgetSide) / 2
        let widgetX = screenFrame.maxX - widgetSide - 40 - widgetInset
        let widgetY = screenFrame.minY + 100 - widgetInset
        window.setFrameOrigin(NSPoint(x: widgetX, y: widgetY))
    }

    @objc private func openPreferences() {
        if let window = preferencesWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = PreferencesWindow()
        window.contentView = NSHostingView(rootView: PreferencesView(appMonitor: appMonitor))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.preferencesWindow = window
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Allow banners to appear even while NARC is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// User clicked the banner — extract carried tty/cwd/project and jump.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let tty = userInfo["narc.tty"] as? String
        let cwd = userInfo["narc.cwd"] as? String
        let projectName = userInfo["narc.project"] as? String
        TerminalJumper.jump(tty: tty, cwd: cwd, projectName: projectName)
        completionHandler()
    }
}
