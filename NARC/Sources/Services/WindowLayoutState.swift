import Cocoa

/// Tracks the last layout applied to each window, replacing frame-based detection
/// for cross-screen decisions. This eliminates AX API jitter and makes behavior
/// predictable: press same hotkey again within TTL → cross screen.
///
/// Design:
/// - Key: CGWindowID (stable per-window identifier)
/// - TTL: 5 seconds — if user presses same key within 5s → cross screen;
///   after 5s → re-apply layout (matches user intuition)
/// - Thread safety: main-thread only (all hotkey callbacks are on main)
final class WindowLayoutState {

    static let shared = WindowLayoutState()

    struct Entry {
        let layout: WindowLayout
        let screenDisplayID: CGDirectDisplayID
        let timestamp: Date
    }

    private var states: [CGWindowID: Entry] = [:]

    /// How long a layout record stays valid for cross-screen decisions.
    private let ttl: TimeInterval = 5.0

    private init() {}

    // MARK: - Public API

    /// Record that a layout was just applied to a window.
    func record(windowID: CGWindowID, layout: WindowLayout, screen: NSScreen) {
        let displayID = Self.displayID(for: screen)
        states[windowID] = Entry(layout: layout, screenDisplayID: displayID, timestamp: Date())
        pruneStale()
    }

    /// Should we cross to the adjacent screen?
    /// True when: same window + same layout + same screen + within TTL.
    func shouldCrossScreen(windowID: CGWindowID, layout: WindowLayout, screen: NSScreen) -> Bool {
        guard let entry = states[windowID] else { return false }

        // Expired?
        if Date().timeIntervalSince(entry.timestamp) > ttl { return false }

        let displayID = Self.displayID(for: screen)

        // Same layout on same screen → cross
        return entry.layout == layout && entry.screenDisplayID == displayID
    }

    /// Remove state for a specific window (e.g., window closed).
    func invalidate(windowID: CGWindowID) {
        states.removeValue(forKey: windowID)
    }

    /// Remove all expired entries.
    func pruneStale() {
        let now = Date()
        states = states.filter { now.timeIntervalSince($0.value.timestamp) <= 30.0 }
    }

    // MARK: - Private

    /// Safely extract CGDirectDisplayID from an NSScreen.
    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] else { return 0 }
        if let num = screenNumber as? NSNumber {
            return CGDirectDisplayID(num.uint32Value)
        }
        return 0
    }
}
