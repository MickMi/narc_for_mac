import Cocoa

/// Value-only snapshot used by the window move verifier.
/// Keeping this separate from AXUIElement makes geometry and race handling testable.
struct WindowMoveFrame: Equatable {
    let position: CGPoint
    let size: CGSize

    init(position: CGPoint, size: CGSize) {
        self.position = position
        self.size = size
    }

    init(rect: CGRect) {
        self.init(position: rect.origin, size: rect.size)
    }

    var rect: CGRect {
        CGRect(origin: position, size: size)
    }
}

/// Use the already captured frame, never an extra AX read, to avoid redundant
/// size writes on a known same-display move. Unknown/cross-display stays conservative.
enum WindowFrameWritePlan: Equatable {
    case positionOnly
    case sizeThenPosition
    case sizePositionSize

    static func initial(current: WindowMoveFrame?, targetSize: CGSize, sameDisplay: Bool) -> Self {
        guard sameDisplay, let current else { return .sizePositionSize }
        // Do not use the verifier's 8-point tolerance to skip a requested resize.
        return current.size == targetSize ? .positionOnly : .sizeThenPosition
    }
}

/// Pure geometry rules for accepting and anchoring a window move.
enum WindowMoveGeometry {
    static let positionTolerance: CGFloat = 3
    static let sizeTolerance: CGFloat = 8
    static let stabilityTolerance: CGFloat = 1

    static func matches(_ observed: WindowMoveFrame, _ expected: WindowMoveFrame) -> Bool {
        positionMatches(observed.position, expected.position)
            && sizeMatches(observed.size, expected.size)
    }

    static func positionMatches(_ observed: CGPoint, _ expected: CGPoint) -> Bool {
        abs(observed.x - expected.x) <= positionTolerance
            && abs(observed.y - expected.y) <= positionTolerance
    }

    static func sizeMatches(_ observed: CGSize, _ expected: CGSize) -> Bool {
        abs(observed.width - expected.width) <= sizeTolerance
            && abs(observed.height - expected.height) <= sizeTolerance
    }

    static func sizeIsStable(_ first: CGSize, _ second: CGSize) -> Bool {
        abs(first.width - second.width) <= stabilityTolerance
            && abs(first.height - second.height) <= stabilityTolerance
    }

    static func screenBoundsMatch(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= stabilityTolerance
            && abs(first.minY - second.minY) <= stabilityTolerance
            && abs(first.width - second.width) <= stabilityTolerance
            && abs(first.height - second.height) <= stabilityTolerance
    }

    /// A layout's defining dimension must still be present before a stable
    /// app-constrained frame can be accepted. The other dimension may differ,
    /// but tiny popovers are not mistaken for a half-screen window.
    static func sizeIsAcceptableForLayout(
        _ observed: CGSize,
        requested: CGSize,
        layout: WindowLayout
    ) -> Bool {
        let widthMatches = abs(observed.width - requested.width) <= sizeTolerance
        let heightMatches = abs(observed.height - requested.height) <= sizeTolerance
        // A constrained app may be larger than the requested half/quadrant, but
        // an unchanged full-screen frame (2x the defining dimension) must never
        // masquerade as a successful half-screen move.
        let hardWidthIsAcceptable = observed.width >= requested.width - sizeTolerance
            && observed.width < requested.width * 2 - sizeTolerance
        let hardHeightIsAcceptable = observed.height >= requested.height - sizeTolerance
            && observed.height < requested.height * 2 - sizeTolerance
        let softWidthIsPlausible = widthMatches || observed.width >= requested.width * 0.5
        let softHeightIsPlausible = heightMatches || observed.height >= requested.height * 0.5

        switch layout {
        case .leftHalf, .rightHalf:
            return hardWidthIsAcceptable && softHeightIsPlausible
        case .topHalf, .bottomHalf:
            return hardHeightIsAcceptable && softWidthIsPlausible
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return hardWidthIsAcceptable && hardHeightIsAcceptable
        case .center:
            return softWidthIsPlausible && softHeightIsPlausible
        case .fullScreen:
            return widthMatches && heightMatches
        }
    }

    /// A non-exact constrained size is accepted immediately only when this
    /// command produced observable progress. If the frame is unchanged, the
    /// caller must first run its one bounded compatibility attempt; otherwise a
    /// stale near-full-screen frame could be recorded as a half-screen result.
    static func constrainedFrameIsAcceptable(
        _ observed: WindowMoveFrame,
        requested: WindowMoveFrame,
        layout: WindowLayout,
        sourceFrame: WindowMoveFrame,
        allowsUnchangedConstraint: Bool
    ) -> Bool {
        guard sizeIsAcceptableForLayout(
            observed.size,
            requested: requested.size,
            layout: layout
        ) else {
            return false
        }
        return sizeMatches(observed.size, requested.size)
            || allowsUnchangedConstraint
            || !matches(observed, sourceFrame)
    }

    /// The first cross-display write may move the window and update one size
    /// axis before the target app has adopted the destination screen. Do not
    /// treat that partial frame as an app constraint until one bounded retry has
    /// run with the window already resident on the target display.
    static func crossScreenMoveNeedsCompatibilityRetry(
        observed: WindowMoveFrame,
        requested: WindowMoveFrame,
        crossesScreen: Bool
    ) -> Bool {
        crossesScreen && !sizeMatches(observed.size, requested.size)
    }

    /// A reduced first write must get a full retry before any non-exact size is
    /// accepted as an app constraint, including after a later anchor correction.
    static func reducedWriteNeedsCompatibilityRetry(
        observed: WindowMoveFrame,
        requested: WindowMoveFrame,
        reducedInitialWrite: Bool,
        compatibilityAttempted: Bool
    ) -> Bool {
        reducedInitialWrite && !compatibilityAttempted && !sizeMatches(observed.size, requested.size)
    }

    /// Re-anchor using the size the app actually accepted. This is important for
    /// fixed-size and minimum-size windows: a right/bottom layout must still touch
    /// both requested edges even when AX refuses the requested dimensions.
    static func anchoredFrame(
        layout: WindowLayout,
        screenBounds: CGRect,
        actualSize: CGSize
    ) -> WindowMoveFrame {
        let x: CGFloat
        let y: CGFloat

        switch layout {
        case .rightHalf, .topRight, .bottomRight:
            x = actualSize.width >= screenBounds.width
                ? screenBounds.minX
                : screenBounds.maxX - actualSize.width
        case .center:
            x = actualSize.width >= screenBounds.width
                ? screenBounds.minX
                : screenBounds.midX - actualSize.width / 2
        default:
            x = screenBounds.minX
        }

        switch layout {
        case .bottomHalf, .bottomLeft, .bottomRight:
            y = actualSize.height >= screenBounds.height
                ? screenBounds.minY
                : screenBounds.maxY - actualSize.height
        case .center:
            y = actualSize.height >= screenBounds.height
                ? screenBounds.minY
                : screenBounds.midY - actualSize.height / 2
        default:
            y = screenBounds.minY
        }

        return WindowMoveFrame(position: CGPoint(x: x, y: y), size: actualSize)
    }
}

/// A target app may briefly return `cannotComplete` while processing a frame
/// change. Only that error is transient, and the budget belongs to the whole
/// move so verifier stages cannot multiply retries.
enum WindowFrameReadRetryPolicy {
    static let limit = 2

    static func shouldRetry(error: AXError, failuresSoFar: Int) -> Bool {
        error == .cannotComplete && failuresSoFar < limit
    }
}

/// Monotonic per-window operation tokens. A delayed verification may touch a
/// window only while its token is still current, so rapid hotkeys cannot be
/// overwritten by an older correction.
final class WindowMoveGenerationStore {
    private var nextGeneration: UInt64 = 0
    private var latestByWindow: [UInt64: UInt64] = [:]
    private let lock = NSLock()

    func begin(windowKey: UInt64) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        nextGeneration &+= 1
        if nextGeneration == 0 {
            nextGeneration = 1
        }
        latestByWindow[windowKey] = nextGeneration
        return nextGeneration
    }

    func isCurrent(windowKey: UInt64, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return latestByWindow[windowKey] == generation
    }

    func finish(windowKey: UInt64, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard latestByWindow[windowKey] == generation else { return }
        latestByWindow.removeValue(forKey: windowKey)
    }
}
