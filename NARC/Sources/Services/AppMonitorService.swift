import Cocoa
import Combine

/// Reads Dock badge values from LaunchServices while handling apps that expose
/// more than one application serial number (ASN) for the same bundle ID.
struct DockBadgeReader {
    typealias Runner = ([String]) -> String?

    private let runLSAppInfo: Runner

    init(runLSAppInfo: @escaping Runner) {
        self.runLSAppInfo = runLSAppInfo
    }

    init() {
        self.runLSAppInfo = Self.runSystemLSAppInfo
    }

    /// Returns nil only when LaunchServices cannot provide a trustworthy value.
    /// Duplicate app registrations represent one app, so their values are never added.
    func badgeCount(for bundleID: String) -> Int? {
        let directArguments = ["info", "-only", "StatusLabel", bundleID]
        if let directCount = Self.parseBadgeCount(runLSAppInfo(directArguments)) {
            return directCount
        }

        guard let listOutput = runLSAppInfo(["list"]) else { return nil }
        let applicationIdentifiers = Self.applicationIdentifiers(
            in: listOutput,
            matching: bundleID
        )
        guard !applicationIdentifiers.isEmpty else { return nil }

        let counts = applicationIdentifiers.compactMap { identifier in
            Self.parseBadgeCount(
                runLSAppInfo(["info", "-only", "StatusLabel", identifier])
            )
        }
        return counts.max()
    }

    private static func parseBadgeCount(_ output: String?) -> Int? {
        guard let output,
              let labelRange = output.range(of: "\"label\"=") else {
            return nil
        }
        let afterLabel = output[labelRange.upperBound...]
        guard afterLabel.first == "\"" else { return nil }

        let valueStart = afterLabel.index(after: afterLabel.startIndex)
        guard let valueEnd = afterLabel[valueStart...].firstIndex(of: "\"") else {
            return nil
        }

        let value = String(afterLabel[valueStart..<valueEnd])
        if value.isEmpty { return 0 }
        return Int(value) ?? 1
    }

    private static func applicationIdentifiers(
        in listOutput: String,
        matching bundleID: String
    ) -> [String] {
        var currentIdentifier: String?
        var matches: [String] = []
        var seen = Set<String>()

        for rawLine in listOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let range = line.range(
                of: #"ASN:0x[0-9A-Fa-f]+-0x[0-9A-Fa-f]+"#,
                options: .regularExpression
            ) {
                currentIdentifier = String(line[range])
            }

            guard line.contains("bundleID=\"\(bundleID)\""),
                  let identifier = currentIdentifier,
                  seen.insert(identifier).inserted else {
                continue
            }
            matches.append(identifier)
        }

        return matches
    }

    private static func runSystemLSAppInfo(arguments: [String]) -> String? {
        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/lsappinfo"),
            arguments: arguments
        )
    }

    static func runProcess(executableURL: URL, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = executableURL
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        // Drain stdout while the process is still running. Waiting first can deadlock
        // when `lsappinfo list` fills the pipe buffer before it can exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Service that monitors running applications for Dock badge changes.
/// Uses NSWorkspace notifications + periodic polling of Dock badge via LaunchServices.
class AppMonitorService: ObservableObject {

    // MARK: - Published State

    @Published var notificationStates: [NotificationState] = []
    @Published var totalBadgeCount: Int = 0
    @Published var filters: [NotificationFilter] = []

    /// Filtered notification states based on active filter rules.
    var filteredStates: [NotificationState] {
        notificationStates.filter { state in
            guard state.app.isEnabled else { return false }
            let action = resolveFilterAction(for: state)
            return action != .hide
        }
    }

    // MARK: - Private

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let pollingInterval: TimeInterval = 2.0
    private let dockBadgeReader = DockBadgeReader()

    /// Default apps to monitor (can be customized via preferences).
    private let defaultMonitoredApps: [MonitoredApp] = [
        MonitoredApp(id: "com.tencent.xinWeChat", displayName: "WeChat", category: .im, isEnabled: true),
        MonitoredApp(id: "com.tencent.WeWorkMac", displayName: "WeCom", category: .im, isEnabled: true),
        MonitoredApp(id: "com.electron.lark", displayName: "Lark", category: .im, isEnabled: true),
        MonitoredApp(id: "com.microsoft.VSCode", displayName: "VS Code", category: .ide, isEnabled: false),
    ]

    // MARK: - Init

    init() {
        notificationStates = Self.loadMonitoredApps().map { NotificationState(app: $0) }
        loadFilters()
    }

    // MARK: - Monitored App Management

    /// Toggle whether an app is monitored.
    func toggleApp(bundleID: String) {
        guard let idx = notificationStates.firstIndex(where: { $0.app.bundleID == bundleID }) else { return }
        notificationStates[idx].app.isEnabled.toggle()
        saveMonitoredApps()
    }

    /// Add a new app to the monitoring list.
    func addApp(_ app: MonitoredApp) {
        guard !notificationStates.contains(where: { $0.app.bundleID == app.bundleID }) else { return }
        notificationStates.append(NotificationState(app: app))
        saveMonitoredApps()
    }

    /// Remove an app from the monitoring list.
    func removeApp(bundleID: String) {
        notificationStates.removeAll { $0.app.bundleID == bundleID }
        saveMonitoredApps()
    }

    private func saveMonitoredApps() {
        let apps = notificationStates.map { $0.app }
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: "narc.monitoredApps")
        }
    }

    private static func loadMonitoredApps() -> [MonitoredApp] {
        guard let data = UserDefaults.standard.data(forKey: "narc.monitoredApps"),
              let saved = try? JSONDecoder().decode([MonitoredApp].self, from: data),
              !saved.isEmpty else {
            return [
                MonitoredApp(id: "com.tencent.xinWeChat", displayName: "WeChat", category: .im, isEnabled: true),
                MonitoredApp(id: "com.tencent.WeWorkMac", displayName: "WeCom", category: .im, isEnabled: true),
                MonitoredApp(id: "com.electron.lark", displayName: "Lark", category: .im, isEnabled: true),
            ]
        }
        var merged = saved
        let requiredDefaults = [
            MonitoredApp(id: "com.tencent.xinWeChat", displayName: "WeChat", category: .im, isEnabled: true),
            MonitoredApp(id: "com.tencent.WeWorkMac", displayName: "WeCom", category: .im, isEnabled: true),
            MonitoredApp(id: "com.electron.lark", displayName: "Lark", category: .im, isEnabled: true),
        ]
        for app in requiredDefaults where !merged.contains(where: { $0.bundleID == app.bundleID }) {
            merged.append(app)
        }
        return merged
    }

    // MARK: - Filter Rules

    /// Resolve the filter action for a given notification state.
    func resolveFilterAction(for state: NotificationState) -> NotificationFilter.FilterAction {
        let activeFilters = filters.filter { $0.isEnabled }

        // Check app-specific filters first, then wildcard filters
        let appFilters = activeFilters.filter { $0.appBundleID == state.app.bundleID }
        let wildcardFilters = activeFilters.filter { $0.appBundleID == "*" }

        let applicableFilters = appFilters.isEmpty ? wildcardFilters : appFilters

        for filter in applicableFilters {
            switch filter.filterType {
            case .mute:
                return .hide
            case .alwaysNotify:
                return filter.action
            case .badgeThreshold:
                let threshold = Int(filter.pattern) ?? 1
                if state.badgeCount >= threshold {
                    return filter.action
                } else {
                    return .silent
                }
            case .keyword:
                // Future: match against notification content
                return filter.action
            }
        }

        // Default: show normally
        return .normal
    }

    /// Add a new filter rule.
    func addFilter(_ filter: NotificationFilter) {
        filters.append(filter)
        saveFilters()
    }

    /// Remove a filter rule.
    func removeFilter(id: UUID) {
        filters.removeAll { $0.id == id }
        saveFilters()
    }

    /// Update a filter rule.
    func updateFilter(_ filter: NotificationFilter) {
        if let index = filters.firstIndex(where: { $0.id == filter.id }) {
            filters[index] = filter
            saveFilters()
        }
    }

    private func saveFilters() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: "narc.filters")
        }
    }

    private func loadFilters() {
        if let data = UserDefaults.standard.data(forKey: "narc.filters"),
           let saved = try? JSONDecoder().decode([NotificationFilter].self, from: data) {
            filters = saved
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // Listen for app launch/termination
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] _ in self?.pollAppStates() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] _ in self?.pollAppStates() }
            .store(in: &cancellables)

        // Periodic polling for badge changes
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollAppStates()
        }

        // Initial poll
        pollAppStates()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    // MARK: - Polling

    private func pollAppStates() {
        let runningApps = NSWorkspace.shared.runningApplications

        // Collect bundle IDs of enabled, running apps
        let enabledBundleIDs = self.notificationStates
            .filter { $0.app.isEnabled }
            .map { $0.app.bundleID }

        let runningBundleIDs = Set(runningApps.compactMap { $0.bundleIdentifier })

        // Read all badges in one batch on a background thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            // Batch-read badges for all running monitored apps
            let badgeMap = self.readAllDockBadges(
                for: enabledBundleIDs.filter { runningBundleIDs.contains($0) }
            )

            DispatchQueue.main.async {
                for state in self.notificationStates {
                    guard state.app.isEnabled else { continue }

                    let isRunning = runningBundleIDs.contains(state.app.bundleID)

                    // Log state changes
                    if state.isRunning != isRunning {
                        print("[NARC] \(state.app.displayName): \(isRunning ? "▶️ now running" : "⏹ stopped")")
                    }

                    state.isRunning = isRunning

                    if isRunning, let badge = badgeMap[state.app.bundleID] {
                        if badge != state.badgeCount {
                            print("[NARC] \(state.app.displayName): badge changed \(state.badgeCount) → \(badge)")
                        }
                        state.badgeCount = badge
                    } else if isRunning {
                        print("[NARC] ⚠️ \(state.app.displayName): Dock badge unavailable; keeping \(state.badgeCount)")
                    } else {
                        state.badgeCount = 0
                    }

                    state.lastUpdated = Date()
                }

                self.totalBadgeCount = self.notificationStates
                    .filter { $0.app.isEnabled }
                    .reduce(0) { $0 + $1.badgeCount }
            }
        }
    }

    /// Batch-read Dock badge counts for multiple apps using `lsappinfo`.
    /// Returns a dictionary of [bundleID: badgeCount].
    private func readAllDockBadges(for bundleIDs: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for bundleID in bundleIDs {
            if let badgeCount = dockBadgeReader.badgeCount(for: bundleID) {
                result[bundleID] = badgeCount
            }
        }
        return result
    }

    // MARK: - App Activation

    /// Activate (bring to front) the app with the given bundle ID,
    /// and move its window to the specified screen (NARC's screen).
    ///
    /// Handles three difficult cases:
    /// 1. Window is minimized (in Dock) → unminimize via AX API
    /// 2. Window is on another desktop/Space → use NSRunningApplication.activate with proper options
    /// 3. Window is hidden → unhide first
    func activateApp(bundleID: String, summonToScreen targetScreen: NSScreen? = nil) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("[NARC] ⚠️ App not running: \(bundleID)")
            return
        }

        if DevRuntimeOptions.noAX {
            print("[NARC] 🧪 Activating \(app.localizedName ?? bundleID) without AX window management.")
            app.activate()
            return
        }

        print("[NARC] 🔄 Activating \(app.localizedName ?? bundleID)...")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Step 1: If the app is hidden, unhide it first
        var wasHidden = false
        if app.isHidden {
            app.unhide()
            wasHidden = true
            print("[NARC] 👁 Unhid \(bundleID)")
        }

        // Step 2: Unminimize the main window via AX API (only the main one, not all)
        // Track whether AX API can see any windows at all — some apps (e.g., WeChat)
        // return no windows when hidden, requiring NSWorkspace.openApplication as fallback.
        var hasMinimizedWindows = false
        var hasAnyWindow = false

        if let mainWindow = AXWindowHelper.getMainWindow(appElement) {
            hasAnyWindow = true
            if AXWindowHelper.isMinimized(mainWindow) {
                AXWindowHelper.unminimize(mainWindow)
                hasMinimizedWindows = true
                print("[NARC] 📤 Unminimized main window for \(bundleID)")
            }
        } else if let windows = AXWindowHelper.getWindows(appElement), let firstWindow = windows.first {
            hasAnyWindow = true
            if AXWindowHelper.isMinimized(firstWindow) {
                AXWindowHelper.unminimize(firstWindow)
                hasMinimizedWindows = true
                print("[NARC] 📤 Unminimized first window for \(bundleID)")
            }
        }

        // Step 3: Pre-position the window BEFORE activating the app.
        // This eliminates the visible "flash" where the window appears at its old position
        // and then jumps to the target screen. By moving it first (while still in the
        // background), the window will already be at the correct position when it becomes visible.
        if let screen = targetScreen, hasAnyWindow {
            // We can see the window via AX — move it to the target screen now,
            // before the app is activated and the window becomes visible.
            WindowManagerService.summonAppWindow(bundleID: bundleID, toScreen: screen)
            print("[NARC] 📍 Pre-positioned \(bundleID) to target screen before activation")
        }

        // Step 4: Activate the app
        // For apps where AX API can see windows, use app.activate() only — this avoids
        // NSWorkspace.openApplication which restores windows to their original screen positions.
        // For apps where AX API returns NO windows (e.g., WeChat after ⌘H), we MUST use
        // NSWorkspace.openApplication as a fallback to force the app to restore its windows.
        app.activate()

        if !hasAnyWindow {
            // AX API found no windows — the app is likely fully hidden (e.g., WeChat ⌘H).
            // Use NSWorkspace.openApplication to force window restoration.
            // This will restore windows to their original screen, but our summonAppWindow
            // (Step 6) will move them to the correct screen afterwards.
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                print("[NARC] 🚀 No AX windows found — using NSWorkspace.openApplication for \(bundleID)")
            }
        }

        // Step 5: Use AX API to raise the main window (ensures it comes to current Space)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.raiseMainWindow(appElement: appElement, bundleID: bundleID)
        }

        // Step 6: Post-activation position correction.
        // For apps where we could pre-position (Step 3), do a quick follow-up to ensure
        // the position wasn't reset by the activation process.
        // For apps where AX found no windows, we need a longer delay for window restoration.
        if let screen = targetScreen {
            let delay: Double
            if !hasAnyWindow {
                delay = 1.0  // NSWorkspace.openApplication needs the most time
            } else if wasHidden {
                delay = 0.3  // Shorter delay — we already pre-positioned in Step 3
            } else if hasMinimizedWindows {
                delay = 0.3
            } else {
                delay = 0.2  // Quick follow-up to confirm position
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                WindowManagerService.summonAppWindow(bundleID: bundleID, toScreen: screen)
                print("[NARC] ✅ Summoned \(app.localizedName ?? bundleID) to NARC screen")
            }
        }
    }

    /// Raise the main window of an app using AX API.
    /// This is critical for bringing windows from other Spaces to the current one.
    private func raiseMainWindow(appElement: AXUIElement, bundleID: String) {
        if let mainWindow = AXWindowHelper.getMainWindow(appElement) {
            AXWindowHelper.raise(mainWindow)
            print("[NARC] 🔝 Raised main window for \(bundleID)")
            return
        }

        if let windows = AXWindowHelper.getWindows(appElement), let firstWindow = windows.first {
            AXWindowHelper.raise(firstWindow)
            print("[NARC] 🔝 Raised first window for \(bundleID)")
            return
        }

        if let focusedWindow = AXWindowHelper.getFocusedWindow(appElement) {
            AXWindowHelper.raise(focusedWindow)
            print("[NARC] 🔝 Raised focused window for \(bundleID)")
        }
    }
}
