import Cocoa
import Combine

/// Service that manages pinned windows — windows the user has "pinned" to the NARC panel
/// for quick access. Supports temporary (cleared on restart) and persistent (saved to disk) pins.
class PinnedWindowService: ObservableObject {

    // MARK: - Published State

    @Published var pinnedWindows: [PinnedWindow] = []

    /// Maximum number of pinned windows allowed.
    let maxPinnedWindows = 10

    // MARK: - Private

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0

    /// Runtime state for each pinned window (not persisted).
    /// Key = PinnedWindow.id
    @Published var runtimeStates: [UUID: PinnedWindowRuntimeState] = [:]

    // MARK: - Init

    init() {
        loadPersistentWindows()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - CRUD

    /// Pin the currently focused window. Returns true if successful.
    @discardableResult
    func pinCurrentWindow() -> Bool {
        guard pinnedWindows.count < maxPinnedWindows else {
            print("[NARC] 📌 Cannot pin: maximum \(maxPinnedWindows) windows reached")
            return false
        }

        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            print("[NARC] 📌 Cannot pin: no frontmost application")
            return false
        }

        let appName = frontApp.localizedName ?? bundleID

        // Get the focused window's title via AX API
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowTitle = appName // fallback to app name

        if let focusedWindow = AXWindowHelper.getFocusedWindow(appElement),
           let title = AXWindowHelper.getTitle(focusedWindow) {
            windowTitle = title
        }

        // Check for duplicate (same bundleID + same title)
        if pinnedWindows.contains(where: { $0.bundleID == bundleID && $0.windowTitle == windowTitle }) {
            print("[NARC] 📌 Window already pinned: \(windowTitle) (\(bundleID))")
            return false
        }

        let pinned = PinnedWindow(
            bundleID: bundleID,
            windowTitle: windowTitle,
            appDisplayName: appName
        )

        pinnedWindows.append(pinned)
        runtimeStates[pinned.id] = PinnedWindowRuntimeState(isAlive: true, currentTitle: windowTitle)
        save()

        print("[NARC] 📌 Pinned window: \(windowTitle) (\(bundleID))")
        return true
    }

    /// Remove a pinned window by ID.
    func unpin(id: UUID) {
        pinnedWindows.removeAll { $0.id == id }
        runtimeStates.removeValue(forKey: id)
        save()
        print("[NARC] 📌 Unpinned window: \(id)")
    }

    /// Toggle the persistence state of a pinned window (📌 ↔ 🔒).
    func togglePersistence(id: UUID) {
        guard let index = pinnedWindows.firstIndex(where: { $0.id == id }) else { return }
        pinnedWindows[index].isPersistent.toggle()
        save()
        let state = pinnedWindows[index].isPersistent ? "persistent 🔒" : "temporary 📌"
        print("[NARC] 📌 Toggled \(pinnedWindows[index].windowTitle) to \(state)")
    }

    // MARK: - Window Activation

    /// Activate (bring to front) a pinned window.
    ///
    /// Cross-Space behavior: macOS does not allow AX API to move windows across Spaces
    /// directly via setPosition. Instead, we activate the app first — macOS will switch
    /// to the Space where the target window lives. Then we raise the specific window
    /// and move it to the target screen while preserving its relative position.
    ///
    /// For multi-window apps (e.g., VS Code with 3 windows), only the pinned window
    /// should be raised. Other windows must remain in their current state.
    func activatePinnedWindow(_ pinned: PinnedWindow, summonToScreen targetScreen: NSScreen? = nil) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: pinned.bundleID).first else {
            print("[NARC] 📌 App not running: \(pinned.bundleID), attempting to launch...")
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pinned.bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            }
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Step 1: If the app is hidden, unhide it first.
        let wasHidden = app.isHidden
        if wasHidden {
            app.unhide()
            print("[NARC] 👁 Unhid \(pinned.bundleID)")
        }

        // Step 2: Find the matching window by title (unminimizes if needed)
        let matchedWindow = WindowManagerService.findAppWindow(
            bundleID: pinned.bundleID,
            matchingTitle: pinned.windowTitle
        )

        // Step 3: Raise the matched window before activation
        if let window = matchedWindow {
            AXWindowHelper.raise(window)
        }

        // Step 4: Activate the app — macOS will switch to the window's Space
        app.activate()

        // Step 5: If the app was hidden, re-minimize non-target windows
        if wasHidden, let window = matchedWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let windows = AXWindowHelper.getWindows(appElement) {
                    for w in windows {
                        if CFEqual(w, window) { continue }
                        AXWindowHelper.minimize(w)
                    }
                    print("[NARC] 📌 Re-minimized non-target windows for \(pinned.bundleID)")
                }
            }
        }

        // Step 6: After activation, move the window to the target screen
        // preserving its relative position from the source screen.
        // We delay slightly to let macOS finish the Space switch and activation.
        if let window = matchedWindow, let screen = targetScreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Self.moveWindowPreservingRelativePosition(window, toScreen: screen)
                AXWindowHelper.raise(window)
                print("[NARC] 📌 Activated pinned window '\(pinned.windowTitle)' on \(screen.localizedName)")
            }
        } else if let window = matchedWindow {
            // No target screen — just raise in place
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AXWindowHelper.raise(window)
                print("[NARC] 📌 Raised pinned window '\(pinned.windowTitle)' in place")
            }
        }
    }

    /// Move a window to the target screen using layout-aware positioning.
    ///
    /// Strategy:
    /// 1. If the window is already on the target screen, do nothing.
    /// 2. Detect if the window matches a known layout on its source screen.
    ///    If yes, apply the SAME layout on the target screen.
    /// 3. If no known layout matches, preserve original size and center on target screen.
    private static func moveWindowPreservingRelativePosition(_ window: AXUIElement, toScreen targetScreen: NSScreen) {
        let sourceScreen = AXWindowHelper.screenForWindow(window)

        // If window is already on the target screen, just raise it — don't move
        if let source = sourceScreen, source == targetScreen {
            print("[NARC] 📌 Window already on target screen, no move needed")
            return
        }

        // Preserve original size, center on target screen
        let currentSize = AXWindowHelper.getSize(window) ?? CGSize(width: 800, height: 600)
        let targetVisible = targetScreen.visibleFrame

        // Clamp size to fit within target screen
        let clampedWidth = min(currentSize.width, targetVisible.width)
        let clampedHeight = min(currentSize.height, targetVisible.height)
        let finalSize = CGSize(width: clampedWidth, height: clampedHeight)

        let nsX = targetVisible.origin.x + (targetVisible.width - finalSize.width) / 2
        let nsY = targetVisible.origin.y + (targetVisible.height - finalSize.height) / 2
        let axPos = AXWindowHelper.nsToAX(x: nsX, y: nsY, height: finalSize.height)
        AXWindowHelper.setFrame(window, position: axPos, size: finalSize)

        print("[NARC] 📌 Moved window to \(targetScreen.localizedName) centered (no matching layout)")
    }

    // MARK: - Polling (Alive Status + Title Update)

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollPinnedWindows()
        }
    }

    private func pollPinnedWindows() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var newStates: [UUID: PinnedWindowRuntimeState] = [:]

            for pinned in self.pinnedWindows {
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: pinned.bundleID)
                guard let app = apps.first else {
                    newStates[pinned.id] = PinnedWindowRuntimeState(isAlive: false, currentTitle: pinned.windowTitle)
                    continue
                }

                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var isAlive = false
                var currentTitle = pinned.windowTitle

                // Check windows for a matching title
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement] {

                    for window in windows {
                        if let title = AXWindowHelper.getTitle(window) {
                            if title == pinned.windowTitle {
                                isAlive = true
                                currentTitle = title
                                break
                            }
                        }
                    }

                    // If no exact title match but app has windows, still consider it alive.
                    // IMPORTANT: Do NOT replace currentTitle with windows[0]'s title.
                    // When the user switches desktops/spaces, the pinned window may not appear
                    // in the AX window list, but the app is still running. Using windows[0]'s
                    // title would incorrectly show a different window's name in the panel
                    // (e.g., showing "browser_tab_extractor.py" instead of "UML — narc_for_mac").
                    // Keep the original pinned title so the UI remains stable.
                    if !isAlive && !windows.isEmpty {
                        isAlive = true
                        // Keep currentTitle = pinned.windowTitle (already set above)
                    }
                }

                newStates[pinned.id] = PinnedWindowRuntimeState(isAlive: isAlive, currentTitle: currentTitle)
            }

            DispatchQueue.main.async {
                self.runtimeStates = newStates
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        // Only persist windows marked as persistent
        let persistentWindows = pinnedWindows.filter { $0.isPersistent }
        if let data = try? JSONEncoder().encode(persistentWindows) {
            UserDefaults.standard.set(data, forKey: "narc.pinnedWindows")
        }
    }

    private func loadPersistentWindows() {
        if let data = UserDefaults.standard.data(forKey: "narc.pinnedWindows"),
           let saved = try? JSONDecoder().decode([PinnedWindow].self, from: data) {
            pinnedWindows = saved
            for pinned in saved {
                runtimeStates[pinned.id] = PinnedWindowRuntimeState(isAlive: false, currentTitle: pinned.windowTitle)
            }
            print("[NARC] 📌 Loaded \(saved.count) persistent pinned windows")
        }
    }
}

// MARK: - Runtime State

/// Runtime state for a pinned window (not persisted to disk).
struct PinnedWindowRuntimeState {
    var isAlive: Bool           // Whether the window/app is still running
    var currentTitle: String    // Real-time window title
}
