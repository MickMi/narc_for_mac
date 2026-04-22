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
    /// Pinned windows are "workspace" windows — they must keep their original position and size.
    /// We only: unminimize the target window → raise it → give the app focus.
    ///
    /// IMPORTANT: We must NOT bring ALL windows of the app to the front.
    /// For multi-window apps (e.g., VS Code with 3 windows), only the pinned window
    /// should be raised. Other windows must remain in their current state.
    func activatePinnedWindow(_ pinned: PinnedWindow, summonToScreen targetScreen: NSScreen? = nil) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: pinned.bundleID).first else {
            print("[NARC] 📌 App not running: \(pinned.bundleID), attempting to launch...")
            // Try to launch the app
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pinned.bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            }
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Step 1: If the app is hidden, we must unhide it (this is app-level, unavoidable).
        // But we'll minimize non-target windows afterwards to keep only the target visible.
        let wasHidden = app.isHidden
        if wasHidden {
            app.unhide()
            print("[NARC] 👁 Unhid \(pinned.bundleID)")
        }

        // Step 2: Find the matching window by title (only unminimizes that specific window)
        let matchedWindow = WindowManagerService.findAppWindow(
            bundleID: pinned.bundleID,
            matchingTitle: pinned.windowTitle
        )

        // Step 3: Raise the matched window FIRST, before activating the app.
        if let window = matchedWindow {
            AXWindowHelper.raise(window)
        }

        // Step 4: Activate the app to give it keyboard focus.
        // On macOS, this brings all non-minimized windows to the front.
        // We'll handle that in Step 5.
        app.activate()

        // Step 5: If the app was hidden (all windows were restored by unhide),
        // re-minimize all windows EXCEPT the target one.
        // This prevents "all 3 VS Code windows appearing" when only 1 was requested.
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

        // Step 6: Raise the matched window again after activation to ensure it's on top.
        if let window = matchedWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AXWindowHelper.raise(window)
                print("[NARC] 📌 Raised pinned window '\(pinned.windowTitle)' in place (no move/resize)")
            }
        }
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

                    // If no exact title match but app has windows, still consider it alive
                    if !isAlive && !windows.isEmpty {
                        isAlive = true
                        if let title = AXWindowHelper.getTitle(windows[0]) {
                            currentTitle = title
                        }
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
