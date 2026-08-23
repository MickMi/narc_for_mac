import Foundation

/// Represents an application being monitored by NARC.
struct MonitoredApp: Identifiable, Codable, Equatable {
    let id: String           // Bundle ID, e.g. "com.tencent.xinWeChat"
    var displayName: String  // e.g. "WeChat"
    var category: AppCategory
    var isEnabled: Bool

    var bundleID: String { id }

    enum AppCategory: String, Codable, CaseIterable {
        case im = "Instant Messaging"
        case ide = "Development"
        case other = "Other"
    }
}

/// Runtime notification state for a monitored app.
class NotificationState: ObservableObject, Identifiable {
    var app: MonitoredApp

    @Published var badgeCount: Int = 0
    @Published var isRunning: Bool = false
    @Published var lastUpdated: Date = Date()

    var id: String { app.id }

    var hasNewNotification: Bool {
        badgeCount > 0
    }

    var statusDescription: String {
        if !isRunning { return "Not running" }
        if hasNewNotification { return "\(badgeCount) new" }
        return "No new messages"
    }

    init(app: MonitoredApp) {
        self.app = app
    }
}

/// A notification filter rule that determines how badge changes are handled.
struct NotificationFilter: Identifiable, Codable, Equatable {
    let id: UUID
    var appBundleID: String       // Which app this filter applies to ("*" = all apps)
    var filterType: FilterType
    var pattern: String           // The pattern to match (keyword, regex, or badge threshold)
    var action: FilterAction
    var isEnabled: Bool

    enum FilterType: String, Codable, CaseIterable {
        case badgeThreshold = "Badge Threshold"   // Only notify when badge >= threshold
        case keyword = "Keyword"                  // Match notification content (future use)
        case alwaysNotify = "Always Notify"       // Always show notification for this app
        case mute = "Mute"                        // Never show notification for this app
    }

    enum FilterAction: String, Codable, CaseIterable {
        case highlight = "Highlight"    // Show with emphasis (red badge)
        case normal = "Normal"          // Show normally
        case silent = "Silent"          // Show but no emphasis
        case hide = "Hide"             // Don't show at all
    }

    init(appBundleID: String = "*", filterType: FilterType = .alwaysNotify, pattern: String = "", action: FilterAction = .normal, isEnabled: Bool = true) {
        self.id = UUID()
        self.appBundleID = appBundleID
        self.filterType = filterType
        self.pattern = pattern
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// Predefined window layout positions.
enum WindowLayout: String, CaseIterable, Identifiable {
    case leftHalf = "Left Half"
    case rightHalf = "Right Half"
    case topHalf = "Top Half"
    case bottomHalf = "Bottom Half"
    case fullScreen = "Full Screen"
    case center = "Center"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    var id: String { rawValue }

    /// The frame rect as a fraction of the screen (x, y, width, height).
    var fractionalFrame: CGRect {
        switch self {
        case .leftHalf:    return CGRect(x: 0, y: 0, width: 0.5, height: 1.0)
        case .rightHalf:   return CGRect(x: 0.5, y: 0, width: 0.5, height: 1.0)
        case .topHalf:     return CGRect(x: 0, y: 0.5, width: 1.0, height: 0.5)
        case .bottomHalf:  return CGRect(x: 0, y: 0, width: 1.0, height: 0.5)
        case .fullScreen:  return CGRect(x: 0, y: 0, width: 1.0, height: 1.0)
        case .center:      return CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)
        case .topLeft:     return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight:    return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft:  return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        }
    }

    /// Default hotkey description for display.
    var hotkeyLabel: String {
        switch self {
        case .leftHalf:    return "⌃⌥←"
        case .rightHalf:   return "⌃⌥→"
        case .topHalf:     return "⌃⌥↑"
        case .bottomHalf:  return "⌃⌥↓"
        case .fullScreen:  return "⌃⌥↩"
        case .center:      return "⌃⌥C"
        case .topLeft:     return "⌃⌥U"
        case .topRight:    return "⌃⌥I"
        case .bottomLeft:  return "⌃⌥J"
        case .bottomRight: return "⌃⌥K"
        }
    }

    /// SF Symbol name for the layout thumbnail.
    var iconName: String {
        switch self {
        case .leftHalf:    return "rectangle.lefthalf.filled"
        case .rightHalf:   return "rectangle.righthalf.filled"
        case .topHalf:     return "rectangle.tophalf.filled"
        case .bottomHalf:  return "rectangle.bottomhalf.filled"
        case .fullScreen:  return "rectangle.fill"
        case .center:      return "rectangle.center.inset.filled"
        case .topLeft:     return "rectangle.inset.topleft.filled"
        case .topRight:    return "rectangle.inset.topright.filled"
        case .bottomLeft:  return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        }
    }
}

// MARK: - Pinned Window

/// Represents a window that the user has pinned to the NARC panel for quick access.
/// Each pinned window is treated as an independent entity identified by its CGWindowID,
/// regardless of which app it belongs to. This enables precise cross-Space operations.
struct PinnedWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var bundleID: String          // The app's Bundle ID
    var windowTitle: String       // Window title at pin time (display + fallback matching)
    var appDisplayName: String    // Human-readable app name
    var isPersistent: Bool        // false = temporary (📌), true = fixed (🔒)
    var pinnedAt: Date            // When the window was pinned
    var cgWindowID: UInt32        // CGWindowID — the unique window identifier (0 if unknown)

    init(bundleID: String, windowTitle: String, appDisplayName: String, isPersistent: Bool = false, cgWindowID: UInt32 = 0) {
        self.id = UUID()
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.appDisplayName = appDisplayName
        self.isPersistent = isPersistent
        self.pinnedAt = Date()
        self.cgWindowID = cgWindowID
    }
}
