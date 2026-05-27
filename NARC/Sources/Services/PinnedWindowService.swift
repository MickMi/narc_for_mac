import Cocoa
import Combine

// MARK: - Private CGS API (verified from Amethyst source)

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: Int32) -> Int

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

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

        // Get the focused window's title and CGWindowID via AX API
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowTitle = appName // fallback to app name
        var cgWindowID: CGWindowID = 0

        if let focusedWindow = AXWindowHelper.getFocusedWindow(appElement) {
            if let title = AXWindowHelper.getTitle(focusedWindow) {
                windowTitle = title
            }
            cgWindowID = AXWindowHelper.windowID(for: focusedWindow)
        }

        // Check for duplicate (same CGWindowID, or same bundleID + title if ID is 0)
        if cgWindowID != 0 {
            if pinnedWindows.contains(where: { $0.cgWindowID == cgWindowID }) {
                print("[NARC] 📌 Window already pinned (ID: \(cgWindowID))")
                return false
            }
        } else if pinnedWindows.contains(where: { $0.bundleID == bundleID && $0.windowTitle == windowTitle }) {
            print("[NARC] 📌 Window already pinned: \(windowTitle) (\(bundleID))")
            return false
        }

        let pinned = PinnedWindow(
            bundleID: bundleID,
            windowTitle: windowTitle,
            appDisplayName: appName,
            cgWindowID: cgWindowID
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
    /// Each window is an independent entity identified by CGWindowID.
    /// Strategy:
    /// 1. Try AX API first (works if window is on current Space)
    /// 2. If window not found in AX list (on another Space), use AppleScript
    ///    minimize→unminiaturize trick to pull it to current Space
    /// 3. CGS API as last resort (known to be unreliable on macOS 15)
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

        if app.isHidden {
            app.unhide()
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Use stored CGWindowID if available, otherwise find by title
        var windowID = pinned.cgWindowID
        if windowID == 0 {
            windowID = Self.findWindowID(pid: pid, titleHint: pinned.windowTitle) ?? 0
        }

        // Strategy 1: Try AX API directly (window on current Space)
        if let windows = AXWindowHelper.getWindows(appElement) {
            for window in windows {
                let axWindowID = AXWindowHelper.windowID(for: window)
                // Match by CGWindowID if available, otherwise by title
                let isMatch: Bool
                if windowID != 0 {
                    isMatch = (axWindowID == windowID)
                } else {
                    if let title = AXWindowHelper.getTitle(window) {
                        isMatch = Self.titleMatches(title, pinned: pinned.windowTitle)
                    } else {
                        isMatch = false
                    }
                }

                if isMatch {
                    if AXWindowHelper.isMinimized(window) {
                        AXWindowHelper.unminimize(window)
                    }
                    AXWindowHelper.raise(window)
                    app.activate()
                    print("[NARC] 📌 Activated window via AX (ID: \(axWindowID), on current Space)")
                    return
                }
            }
        }

        // Window not found in AX list → it's on another Space
        // Strategy 2: AppleScript minimize→unminiaturize (proven cross-Space method)
        print("[NARC] 📌 Window not on current Space, using AppleScript summon...")
        Self.summonWindowViaAppleScript(
            appName: pinned.appDisplayName,
            windowTitleHint: pinned.windowTitle,
            windowID: windowID
        ) { success in
            if success {
                // After AppleScript brings window to current Space, raise it via AX
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if let windows = AXWindowHelper.getWindows(appElement) {
                        for window in windows {
                            let axWindowID = AXWindowHelper.windowID(for: window)
                            let isMatch: Bool
                            if windowID != 0 {
                                isMatch = (axWindowID == windowID)
                            } else if let title = AXWindowHelper.getTitle(window) {
                                isMatch = Self.titleMatches(title, pinned: pinned.windowTitle)
                            } else {
                                isMatch = false
                            }
                            if isMatch {
                                AXWindowHelper.raise(window)
                                app.activate()
                                print("[NARC] 📌 Raised window after AppleScript summon (ID: \(axWindowID))")
                                return
                            }
                        }
                    }
                    // If still can't find, just activate app
                    app.activate()
                    print("[NARC] ⚠️ Window not found after AppleScript summon, activated app")
                }
            } else {
                // AppleScript failed, fallback: just activate app
                app.activate()
                print("[NARC] ⚠️ AppleScript summon failed, activated app as fallback")
            }
        }
    }

    // MARK: - AppleScript Cross-Space Summon

    /// Use AppleScript to activate a window on another Space.
    /// Strategy (no-animation):
    ///   1. `set index of targetWindow to 1` — makes it the app's frontmost window
    ///   2. `activate` — macOS switches to the Space where that window lives
    /// This avoids the visible miniaturize/unminiaturize animation entirely.
    private static func summonWindowViaAppleScript(
        appName: String,
        windowTitleHint: String,
        windowID: CGWindowID,
        completion: @escaping (Bool) -> Void
    ) {
        // Extract a STABLE title prefix for matching.
        // Terminal titles format: "directory — ⠂ process — size"
        // The spinner character (⠂⠈⠐⠠⠄⠇ etc.) changes every frame,
        // so we only use the part BEFORE the first " — " as the match key.
        // This is typically the directory name, which is always stable.
        let stableHint = Self.extractStableTitleHint(from: windowTitleHint)

        let script: String

        if !stableHint.isEmpty {
            // Match by stable title prefix (contains check)
            // Strategy: set index to 1 + activate → macOS switches to window's Space
            script = """
            tell application "\(appName)"
                set targetWindow to missing value
                repeat with w in windows
                    if name of w contains "\(stableHint)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is not missing value then
                    set index of targetWindow to 1
                    activate
                end if
            end tell
            """
        } else {
            // No title hint, operate on first window
            script = """
            tell application "\(appName)"
                if (count of windows) > 0 then
                    set index of window 1 to 1
                    activate
                end if
            end tell
            """
        }

        // Run AppleScript asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let success = process.terminationStatus == 0
                if !success {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorStr = String(data: errorData, encoding: .utf8) ?? "unknown error"
                    print("[NARC] ⚠️ AppleScript error: \(errorStr)")
                }

                DispatchQueue.main.async {
                    completion(success)
                }
            } catch {
                print("[NARC] ⚠️ Failed to run osascript: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }


    // MARK: - Title Matching

    /// Extract the stable portion of a terminal window title for AppleScript matching.
    /// Terminal titles format: "directory — ⠂ Process — command — 80×24"
    /// Dynamic parts: spinner chars (⠂⠈⠐⠠⠄⠇), dimensions (80×24)
    /// Stable part: the directory name (first segment before " — ")
    ///
    /// Examples:
    ///   ".mick-brain — ⠂ Claude Code — caffeinate ◂ node ... — 80×24" → ".mick-brain"
    ///   "narc_for_mac — NARC — 136×68" → "narc_for_mac"
    ///   "~/Projects/foo" → "~/Projects/foo"
    static func extractStableTitleHint(from title: String) -> String {
        // Split by " — " (em dash with spaces) and take the first segment
        let emDashSeparator = " — "
        if let range = title.range(of: emDashSeparator) {
            let prefix = String(title[..<range.lowerBound])
            // If prefix is non-empty and doesn't contain dynamic chars, use it
            if !prefix.isEmpty {
                return prefix
            }
        }

        // No em-dash separator found — strip dimensions and use whole title
        let stripped = title.replacingOccurrences(
            of: #" — \d+[x×]\d+$"#, with: "", options: .regularExpression
        )
        return stripped
    }

    /// Fuzzy title matching for pinned windows.
    /// Terminal titles include dynamic info like window size ("136×72") that changes
    /// when switching Spaces or resizing. This extracts the stable "core" of both titles
    /// and compares them.
    ///
    /// Strategy: strip trailing dimension patterns (e.g., " — 136×72", " — 80x24")
    /// and compare the remaining prefix. Also handle cases where one title is a prefix of the other.
    static func titleMatches(_ current: String, pinned: String) -> Bool {
        // Exact match
        if current == pinned { return true }

        // Strip trailing terminal dimension patterns: " — NNNxNN" or " — NNN×NN"
        let dimensionPattern = #" — \d+[x×]\d+$"#
        let strippedCurrent = current.replacingOccurrences(of: dimensionPattern, with: "", options: .regularExpression)
        let strippedPinned = pinned.replacingOccurrences(of: dimensionPattern, with: "", options: .regularExpression)

        if strippedCurrent == strippedPinned { return true }

        // One is prefix of the other (handles partial title changes)
        if strippedCurrent.hasPrefix(strippedPinned) || strippedPinned.hasPrefix(strippedCurrent) {
            return true
        }

        // Stable prefix match: compare only the directory segment (before first " — ")
        // This handles dynamic content like spinners (⠂⠈⠐⠠⠄⠇) in terminal titles
        let stableCurrent = extractStableTitleHint(from: current)
        let stablePinned = extractStableTitleHint(from: pinned)
        if !stableCurrent.isEmpty && !stablePinned.isEmpty && stableCurrent == stablePinned {
            return true
        }

        return false
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

    // MARK: - Cross-Space Window Operations (Private API)

    /// Find a window's CGWindowID using CGWindowList (works across Spaces).
    static func findWindowID(pid: pid_t, titleHint: String) -> CGWindowID? {
        let options: CGWindowListOption = [.optionAll]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let strippedHint = titleHint.replacingOccurrences(
            of: #" — \d+[x×]\d+$"#, with: "", options: .regularExpression
        )

        for info in windowList {
            guard let windowPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            // Match by title (fuzzy)
            if let title = info[kCGWindowName as String] as? String {
                let strippedTitle = title.replacingOccurrences(
                    of: #" — \d+[x×]\d+$"#, with: "", options: .regularExpression
                )
                if strippedTitle == strippedHint || strippedTitle.hasPrefix(strippedHint) || strippedHint.hasPrefix(strippedTitle) {
                    return windowID
                }
            }
        }

        return nil
    }

    /// Move a window to the current Space via CGS API.
    /// ⚠️ DEPRECATED: This approach is unreliable on macOS 15+.
    /// Use AppleScript minimize→unminiaturize instead.
    /// Kept for reference only.
    @available(*, deprecated, message: "Use summonWindowViaAppleScript instead")
    static func moveWindowToCurrentSpace(windowID: CGWindowID) {
        let cid = CGSMainConnectionID()
        let currentSpace = CGSGetActiveSpace(cid)

        guard currentSpace > 0 else {
            print("[NARC] ⚠️ CGSGetActiveSpace returned \(currentSpace)")
            return
        }

        CGSAddWindowsToSpaces(cid, [windowID] as CFArray, [currentSpace] as CFArray)
        print("[NARC] 📌 CGSAddWindowsToSpaces: window \(windowID) → space \(currentSpace)")
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
                    // App not running
                    newStates[pinned.id] = PinnedWindowRuntimeState(isAlive: false, currentTitle: pinned.windowTitle)
                    continue
                }

                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var foundExactMatch = false
                var currentTitle = pinned.windowTitle

                // Check all windows (including minimized) for title match (fuzzy)
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement] {

                    for window in windows {
                        if let title = AXWindowHelper.getTitle(window),
                           Self.titleMatches(title, pinned: pinned.windowTitle) {
                            foundExactMatch = true
                            currentTitle = title
                            break
                        }
                    }
                }

                // If app is running but window not found in AX list, it might be on another Space.
                // macOS AX API doesn't always list windows from other Spaces.
                // Mark as alive if app is running — the window likely still exists.
                let appIsRunning = !app.isTerminated
                let isAlive = foundExactMatch || appIsRunning

                newStates[pinned.id] = PinnedWindowRuntimeState(
                    isAlive: isAlive,
                    currentTitle: currentTitle
                )
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
