import Cocoa

/// Tracks NARC's last accepted placement for each physical window.
///
/// A recent pending placement lets a very fast double-press cross screens before
/// the first asynchronous readback completes. Long-lived crossing is permitted
/// only while the window still matches its last confirmed physical frame, so a
/// manual drag always resets the behavior naturally.
final class WindowLayoutState {

    static let shared = WindowLayoutState()

    enum Phase {
        case pending
        case confirmed
    }

    struct Entry {
        let processID: pid_t
        let layout: WindowLayout
        let appliedLayout: WindowLayout
        let screenDisplayID: CGDirectDisplayID
        let screenBounds: CGRect
        let acceptedFrame: WindowMoveFrame
        let generation: UInt64
        let phase: Phase
        let timestamp: Date
    }

    private var states: [CGWindowID: Entry] = [:]
    private let stateLock = NSLock()
    private let pendingTTL: TimeInterval

    init(pendingTTL: TimeInterval = 0.5) {
        self.pendingTTL = pendingTTL
    }

    func recordPending(
        windowID: CGWindowID,
        processID: pid_t,
        layout: WindowLayout,
        appliedLayout: WindowLayout,
        screenDisplayID: CGDirectDisplayID,
        screenBounds: CGRect,
        requestedFrame: WindowMoveFrame,
        generation: UInt64,
        now: Date = Date()
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let current = states[windowID], current.generation > generation {
            return
        }
        states[windowID] = Entry(
            processID: processID,
            layout: layout,
            appliedLayout: appliedLayout,
            screenDisplayID: screenDisplayID,
            screenBounds: screenBounds,
            acceptedFrame: requestedFrame,
            generation: generation,
            phase: .pending,
            timestamp: now
        )
    }

    /// Commit the readback frame. The generation check prevents an older
    /// verifier from replacing a newer hotkey's pending or confirmed placement.
    @discardableResult
    func confirm(
        windowID: CGWindowID,
        processID: pid_t,
        layout: WindowLayout,
        appliedLayout: WindowLayout,
        screenDisplayID: CGDirectDisplayID,
        screenBounds: CGRect,
        acceptedFrame: WindowMoveFrame,
        generation: UInt64,
        now: Date = Date()
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let current = states[windowID], current.generation > generation {
            return false
        }

        states[windowID] = Entry(
            processID: processID,
            layout: layout,
            appliedLayout: appliedLayout,
            screenDisplayID: screenDisplayID,
            screenBounds: screenBounds,
            acceptedFrame: acceptedFrame,
            generation: generation,
            phase: .confirmed,
            timestamp: now
        )
        return true
    }

    /// A matching confirmed frame can cross regardless of elapsed time. A
    /// matching pending command gets a short grace period for rapid double-press.
    func shouldCrossScreen(
        windowID: CGWindowID,
        processID: pid_t,
        layout: WindowLayout,
        screenDisplayID: CGDirectDisplayID,
        screenBounds: CGRect,
        currentFrame: WindowMoveFrame,
        now: Date = Date()
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let entry = states[windowID] else {
            return false
        }
        guard entry.processID == processID else {
            states.removeValue(forKey: windowID)
            return false
        }
        guard entry.layout == layout,
              entry.appliedLayout == layout,
              entry.screenDisplayID == screenDisplayID else {
            return false
        }
        guard WindowMoveGeometry.screenBoundsMatch(entry.screenBounds, screenBounds) else {
            states.removeValue(forKey: windowID)
            return false
        }

        if WindowMoveGeometry.matches(currentFrame, entry.acceptedFrame) {
            return true
        }

        if entry.phase == .pending, now.timeIntervalSince(entry.timestamp) <= pendingTTL {
            return true
        }

        // The user or target app moved the window after NARC's last placement.
        states.removeValue(forKey: windowID)
        return false
    }

    /// Remove state for a specific window. When a generation is supplied, an old
    /// verifier is not allowed to clear a newer command's state.
    func invalidate(windowID: CGWindowID, generation: UInt64? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let generation, states[windowID]?.generation != generation {
            return
        }
        states.removeValue(forKey: windowID)
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
