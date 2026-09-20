import Cocoa
import Combine

struct CurrentWindowPinCandidate: Equatable {
    let bundleID: String
    let windowTitle: String
    let appDisplayName: String
    let cgWindowID: CGWindowID
}

enum CurrentWindowPinFailure: Error, Equatable {
    case noFrontmostApplication
    case noFocusedWindow
    case maximumReached(Int)
}

enum CurrentWindowPinToggleResult: Equatable {
    case pinned(PinnedWindow)
    case unpinned(PinnedWindow)
    case failed(CurrentWindowPinFailure)
}

enum CurrentWindowPinDecision: Equatable {
    case pin
    case unpin(UUID)
    case maximumReached(Int)
}

enum PinnedWindowActivationResult: Equatable {
    case activated
    case unavailable
    case revealedOnOriginalDisplay
    case applicationOpened
    case applicationHasNoVisibleWindow
    case cancelled

    var preservesTargetApplication: Bool {
        switch self {
        case .activated, .revealedOnOriginalDisplay, .applicationOpened, .applicationHasNoVisibleWindow:
            return true
        case .unavailable, .cancelled:
            return false
        }
    }
}

struct PinnedWindowRecallObservation {
    var applicationActive: Bool
    var exactWindowFocused: Bool
    var exactWindowVisible: Bool
    var exactWindowOnTargetDisplay: Bool
    var applicationHasVisibleWindow: Bool
}

enum PinnedWindowMatchDecision: Equatable {
    case match(Int)
    case unavailable
    case ambiguous
}

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
    private var activationGeneration: UInt64 = 0

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
        guard case .success(let candidate) = currentWindowPinCandidate() else {
            return false
        }
        guard Self.pinToggleDecision(
            for: candidate,
            pinnedWindows: pinnedWindows,
            maximum: maxPinnedWindows
        ) == .pin else {
            return false
        }
        appendPin(for: candidate)
        return true
    }

    /// Mark or unmark the currently focused exact window.
    ///
    /// Matching happens before the capacity check, so a full list can always
    /// remove an existing Pin. CGWindowID is preferred; title is only a
    /// fallback for windows whose AX implementation does not expose an ID.
    @discardableResult
    func toggleCurrentWindowPin() -> CurrentWindowPinToggleResult {
        let candidateResult = currentWindowPinCandidate()
        guard case .success(let candidate) = candidateResult else {
            if case .failure(let failure) = candidateResult {
                return .failed(failure)
            }
            return .failed(.noFocusedWindow)
        }

        switch Self.pinToggleDecision(
            for: candidate,
            pinnedWindows: pinnedWindows,
            maximum: maxPinnedWindows
        ) {
        case .pin:
            return .pinned(appendPin(for: candidate))
        case .unpin(let id):
            guard let pinned = pinnedWindows.first(where: { $0.id == id }) else {
                return .failed(.noFocusedWindow)
            }
            unpin(id: id)
            return .unpinned(pinned)
        case .maximumReached(let maximum):
            print("[NARC] 📌 Cannot pin: maximum \(maximum) windows reached")
            return .failed(.maximumReached(maximum))
        }
    }

    static func pinToggleDecision(
        for candidate: CurrentWindowPinCandidate,
        pinnedWindows: [PinnedWindow],
        maximum: Int
    ) -> CurrentWindowPinDecision {
        if let existing = pinnedWindows.first(where: {
            pin($0, matches: candidate)
        }) {
            return .unpin(existing.id)
        }
        guard pinnedWindows.count < maximum else {
            return .maximumReached(maximum)
        }
        return .pin
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

    private func currentWindowPinCandidate() -> Result<CurrentWindowPinCandidate, CurrentWindowPinFailure> {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            print("[NARC] 📌 Cannot pin: no frontmost application")
            return .failure(.noFrontmostApplication)
        }
        guard bundleID != Bundle.main.bundleIdentifier else {
            print("[NARC] 📌 Cannot pin a NARC utility window")
            return .failure(.noFocusedWindow)
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        guard let focusedWindow = AXWindowHelper.getFocusedWindow(appElement) else {
            print("[NARC] 📌 Cannot pin: no focused window")
            return .failure(.noFocusedWindow)
        }

        let appName = frontApp.localizedName ?? bundleID
        return .success(CurrentWindowPinCandidate(
            bundleID: bundleID,
            windowTitle: AXWindowHelper.getTitle(focusedWindow) ?? appName,
            appDisplayName: appName,
            cgWindowID: AXWindowHelper.windowID(for: focusedWindow)
        ))
    }

    @discardableResult
    private func appendPin(for candidate: CurrentWindowPinCandidate) -> PinnedWindow {
        let pinned = PinnedWindow(
            bundleID: candidate.bundleID,
            windowTitle: candidate.windowTitle,
            appDisplayName: candidate.appDisplayName,
            cgWindowID: candidate.cgWindowID
        )
        pinnedWindows.append(pinned)
        runtimeStates[pinned.id] = PinnedWindowRuntimeState(
            isAlive: true,
            currentTitle: candidate.windowTitle
        )
        save()
        print("[NARC] 📌 Pinned window: \(candidate.windowTitle) (\(candidate.bundleID))")
        return pinned
    }

    private static func pin(_ pinned: PinnedWindow, matches candidate: CurrentWindowPinCandidate) -> Bool {
        if candidate.cgWindowID != 0, pinned.cgWindowID != 0 {
            return candidate.cgWindowID == pinned.cgWindowID
        }
        return pinned.bundleID == candidate.bundleID
            && pinned.windowTitle == candidate.windowTitle
    }

    // MARK: - Window Activation

    /// Recall a known window when possible, otherwise visibly open its app.
    /// AX window lists may temporarily omit windows in inactive Spaces.
    @MainActor
    func activatePinnedWindow(
        _ pinned: PinnedWindow,
        summonToScreen targetScreen: NSScreen? = nil,
        completion: @escaping (PinnedWindowActivationResult) -> Void = { _ in }
    ) {
        cancelPendingActivation()
        let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: pinned.bundleID).first
        let context = RecallContext(
            generation: activationGeneration,
            targetDisplayID: targetScreen.map(WindowLayoutState.displayID(for:)),
            initiallyVisibleIDs: Self.visibleWindowIDs(pid: nil),
            timeout: runningApp == nil ? 10.0 : 2.0
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + context.timeout + 1.0) { [weak self] in
            guard let self else { return }
            context.complete(
                self.activationGeneration == context.generation ? .unavailable : .cancelled,
                using: completion
            )
        }
        if let app = runningApp {
            beginRecall(pinned, app: app, context: context, completion: completion)
        } else {
            openRecallApplication(pinned, context: context) { [weak self] app in
                guard let self, self.activationGeneration == context.generation else {
                    context.complete(.cancelled, using: completion)
                    return
                }
                guard let app else {
                    context.complete(.unavailable, using: completion)
                    return
                }
                guard !context.finished else { return }
                self.beginRecall(pinned, app: app, context: context, completion: completion)
            }
        }
    }

    final class RecallContext {
        let generation: UInt64
        let targetDisplayID: CGDirectDisplayID?
        let initiallyVisibleIDs: Set<CGWindowID>
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timeout: TimeInterval
        var preparedWindow: AXUIElement?
        var attemptedReopen = false
        var finished = false

        func complete(_ result: PinnedWindowActivationResult, using completion: (PinnedWindowActivationResult) -> Void) {
            guard !finished else { return }
            finished = true
            completion(result)
        }

        init(generation: UInt64, targetDisplayID: CGDirectDisplayID?, initiallyVisibleIDs: Set<CGWindowID>, timeout: TimeInterval = 2.0) {
            self.generation = generation
            self.targetDisplayID = targetDisplayID
            self.initiallyVisibleIDs = initiallyVisibleIDs
            self.timeout = timeout
        }
    }

    @MainActor
    private func beginRecall(
        _ pinned: PinnedWindow,
        app: NSRunningApplication,
        context: RecallContext,
        completion: @escaping (PinnedWindowActivationResult) -> Void
    ) {
        guard !context.finished else { return }
        guard activationGeneration == context.generation else {
            context.complete(.cancelled, using: completion)
            return
        }
        if app.isHidden { app.unhide() }
        // First make a known exact window main, then activate. A generic app
        // activation alone can select a different window in the current Space.
        prepareRecallWindow(pinned, app: app, context: context)
        NSApp?.yieldActivation(to: app)
        app.activate()
        pollRecall(pinned, app: app, context: context, completion: completion)
    }

    @MainActor
    private func prepareRecallWindow(
        _ pinned: PinnedWindow,
        app: NSRunningApplication,
        context: RecallContext
    ) {
        guard context.preparedWindow == nil else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard let windows = AXWindowHelper.getWindows(appElement),
              case .found(let window) = Self.resolvePinnedWindow(
                in: windows,
                expectedWindowID: pinned.cgWindowID,
                titleHint: pinned.windowTitle,
                allowsTitleFallback: pinned.cgWindowID == 0
              ) else { return }

        context.preparedWindow = window
        AXUIElementSetMessagingTimeout(window, 0.15)
        let windowID = AXWindowHelper.windowID(for: window)
        if AXWindowHelper.isMinimized(window) { AXWindowHelper.unminimize(window) }

        // AX position changes don't move a window between Spaces. Only move a
        // window that was already on a visible desktop when recall started.
        if Self.shouldMoveRecalledWindow(
            wasOnScreen: context.initiallyVisibleIDs.contains(windowID),
            isNativeFullScreen: AXWindowHelper.nativeFullScreenState(window) != false
        ), let displayID = context.targetDisplayID,
           let target = NSScreen.screens.first(where: {
               WindowLayoutState.displayID(for: $0) == displayID
           }) {
            WindowManagerService.summonWindow(window, toScreen: target)
        }

        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXWindowHelper.raise(window)
        NSApp?.yieldActivation(to: app)
        app.activate()
        AXWindowHelper.raise(window)
    }

    @MainActor
    private func pollRecall(
        _ pinned: PinnedWindow,
        app: NSRunningApplication,
        context: RecallContext,
        completion: @escaping (PinnedWindowActivationResult) -> Void
    ) {
        guard !context.finished else { return }
        guard activationGeneration == context.generation else {
            context.complete(.cancelled, using: completion)
            return
        }
        guard !app.isTerminated else {
            context.complete(.unavailable, using: completion)
            return
        }

        prepareRecallWindow(pinned, app: app, context: context)
        let visibleIDs = Self.visibleWindowIDs(pid: app.processIdentifier)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        let focusedWindow = AXWindowHelper.getFocusedWindow(appElement)
        let exact = context.preparedWindow
        let exactID = exact.map { AXWindowHelper.windowID(for: $0) } ?? 0
        let focusedID = focusedWindow.map { AXWindowHelper.windowID(for: $0) } ?? 0
        let exactFocused = exactID != 0 ? exactID == focusedID : (exact.flatMap { expected in
            focusedWindow.map { CFEqual(expected, $0) }
        } ?? false)
        let onTarget = context.targetDisplayID == nil || exact.flatMap {
            AXWindowHelper.screenForWindow($0)
        }.map { WindowLayoutState.displayID(for: $0) } == context.targetDisplayID
        let observation = PinnedWindowRecallObservation(
            applicationActive: app.isActive,
            exactWindowFocused: exactFocused,
            exactWindowVisible: exactID != 0 && visibleIDs.contains(exactID),
            exactWindowOnTargetDisplay: onTarget,
            applicationHasVisibleWindow: !visibleIDs.isEmpty
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - context.startedAt
        if let result = Self.recallResult(observation, deadlineExpired: elapsed >= context.timeout) {
            print("[NARC] Pin recall result=\(result) app=\(pinned.bundleID) elapsed_ms=\(Int(elapsed * 1000))")
            context.complete(result, using: completion)
            return
        }

        // Reuse the application's normal reopen path, as the app monitor does.
        // WorkBuddy/Electron may expose no AX windows until this activation.
        // Don't reopen once an exact window is already being presented.
        if elapsed >= 0.35, context.preparedWindow == nil, !context.attemptedReopen {
            openRecallApplication(pinned, context: context) { [weak self] reopened in
                guard let self, !context.finished,
                      self.activationGeneration == context.generation else { return }
                if let reopened {
                    NSApp?.yieldActivation(to: reopened)
                    reopened.activate()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            self.pollRecall(pinned, app: app, context: context, completion: completion)
        }
    }

    @MainActor
    private func openRecallApplication(
        _ pinned: PinnedWindow,
        context: RecallContext,
        completion: @escaping (NSRunningApplication?) -> Void
    ) {
        context.attemptedReopen = true
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pinned.bundleID) else {
            completion(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        // Check generation before activating in the callback. A late launch
        // must not deliberately steal focus from a newer recall.
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async { completion(error == nil ? app : nil) }
        }
    }

    @MainActor
    func cancelPendingActivation() {
        activationGeneration &+= 1
    }

    static func shouldMoveRecalledWindow(wasOnScreen: Bool, isNativeFullScreen: Bool) -> Bool {
        wasOnScreen && !isNativeFullScreen
    }

    static func recallResult(
        _ observation: PinnedWindowRecallObservation,
        deadlineExpired: Bool
    ) -> PinnedWindowActivationResult? {
        if observation.applicationActive,
           observation.exactWindowFocused, observation.exactWindowVisible {
            return observation.exactWindowOnTargetDisplay ? .activated : .revealedOnOriginalDisplay
        }
        guard deadlineExpired else { return nil }
        guard observation.applicationActive else { return .unavailable }
        return observation.applicationHasVisibleWindow ? .applicationOpened : .applicationHasNoVisibleWindow
    }

    /// Presence is based on window ID + owner PID, never the optional title.
    static func visibleWindowIDs(pid: pid_t?) -> Set<CGWindowID> {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return Set(info.compactMap { row in
            guard let owner = row[kCGWindowOwnerPID as String] as? pid_t,
                  pid == nil || pid == owner,
                  let level = row[kCGWindowLayer as String] as? Int,
                  level == 0,
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let windowID = row[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return windowID
        })
    }

    private enum WindowResolution {
        case found(AXUIElement)
        case unavailable
        case ambiguous
    }

    private static func resolvePinnedWindow(
        in windows: [AXUIElement],
        expectedWindowID: CGWindowID,
        titleHint: String,
        allowsTitleFallback: Bool
    ) -> WindowResolution {
        windows.forEach { AXUIElementSetMessagingTimeout($0, 0.10) }
        let decision = pinnedWindowMatchDecision(
            windowIDs: windows.map { AXWindowHelper.windowID(for: $0) },
            titles: expectedWindowID == 0
                ? windows.map { AXWindowHelper.getTitle($0) }
                : Array(repeating: nil, count: windows.count),
            expectedWindowID: expectedWindowID,
            titleHint: titleHint,
            allowsTitleFallback: allowsTitleFallback
        )
        switch decision {
        case .match(let index): return .found(windows[index])
        case .unavailable: return .unavailable
        case .ambiguous: return .ambiguous
        }
    }

    static func pinnedWindowMatchDecision(
        windowIDs: [CGWindowID],
        titles: [String?],
        expectedWindowID: CGWindowID,
        titleHint: String,
        allowsTitleFallback: Bool
    ) -> PinnedWindowMatchDecision {
        guard windowIDs.count == titles.count else { return .unavailable }
        if expectedWindowID != 0 {
            guard let index = windowIDs.firstIndex(of: expectedWindowID) else { return .unavailable }
            return .match(index)
        }
        guard allowsTitleFallback,
              !titleHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable
        }
        let matches = titles.indices.filter { index in
            guard let title = titles[index] else { return false }
            return titleMatches(title, pinned: titleHint)
        }
        if matches.count > 1 { return .ambiguous }
        guard let index = matches.first else { return .unavailable }
        return .match(index)
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
        guard !pinned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

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

    // MARK: - Polling (Alive Status + Title Update)

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollPinnedWindows()
        }
    }

    private func pollPinnedWindows() {
        // Timer callbacks arrive on the main run loop. Snapshot here before
        // leaving it so switcher remove/toggle actions never race a background
        // iteration over the published array.
        let pinnedSnapshot = pinnedWindows
        let pollWorkItem = DispatchWorkItem {
            var newStates: [UUID: PinnedWindowRuntimeState] = [:]

            for pinned in pinnedSnapshot {
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

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let currentIDs = Set(self.pinnedWindows.map(\.id))
                self.runtimeStates = self.runtimeStates.filter {
                    currentIDs.contains($0.key)
                }
                for (id, state) in newStates where currentIDs.contains(id) {
                    self.runtimeStates[id] = state
                }
            }
        }
        DispatchQueue.global(qos: .utility).async(execute: pollWorkItem)
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
