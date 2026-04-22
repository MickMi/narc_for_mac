import Cocoa

/// Handles multi-monitor screen navigation: detecting which screen a window is on,
/// determining if a window is at a screen edge, finding adjacent screens, and
/// computing cross-screen entry layouts.
///
/// Extracted from WindowManagerService to separate cross-screen logic from
/// window movement and hotkey registration concerns.
enum ScreenNavigator {

    // MARK: - Screen Edge Detection

    /// The screen edges that a layout pushes the window toward.
    enum ScreenEdge { case left, right, top, bottom }

    /// Check if the window is already at the target layout on the current screen.
    /// This determines whether the next hotkey press should cross screens.
    ///
    /// We verify BOTH:
    /// 1. The window's size approximately matches the layout's expected size
    /// 2. The window's edges match the layout's target edges
    ///
    /// This prevents false positives: e.g., a fullScreen window touches ALL edges,
    /// but its size doesn't match rightHalf, so pressing ⌃⌥→ should first apply
    /// rightHalf on the current screen, not cross to another screen.
    static func isWindowAtLayout(_ window: AXUIElement, layout: WindowLayout, onScreen screen: NSScreen) -> Bool {
        guard let frame = AXWindowHelper.getFrame(window) else { return false }
        let axOrigin = frame.position
        let currentSize = frame.size

        let bounds = AXWindowHelper.screenBoundsInAX(screen.visibleFrame)
        let windowRight = axOrigin.x + currentSize.width
        let windowBottom = axOrigin.y + currentSize.height

        let tolerance: CGFloat = 15.0

        // --- Check 1: Verify the window's SIZE matches the target layout ---
        let fractional = layout.fractionalFrame
        let expectedWidth = screen.visibleFrame.width * fractional.width
        let expectedHeight = screen.visibleFrame.height * fractional.height

        let widthDelta = abs(currentSize.width - expectedWidth)
        let heightDelta = abs(currentSize.height - expectedHeight)

        if widthDelta > tolerance || heightDelta > tolerance {
            print("[NARC] 📐 isWindowAtLayout: SIZE mismatch for \(layout.rawValue) — "
                  + "current=\(Int(currentSize.width))x\(Int(currentSize.height)), "
                  + "expected=\(Int(expectedWidth))x\(Int(expectedHeight)), "
                  + "delta=\(Int(widthDelta))x\(Int(heightDelta))")
            return false
        }

        // --- Check 2: Verify the window's EDGES match the layout's target edges ---
        let edges = targetEdges(for: layout)

        for edge in edges {
            switch edge {
            case .right:
                if abs(windowRight - bounds.right) > tolerance {
                    print("[NARC] 📐 isWindowAtLayout: EDGE mismatch for \(layout.rawValue) — "
                          + "right edge: window=\(Int(windowRight)), screen=\(Int(bounds.right))")
                    return false
                }
            case .left:
                if abs(axOrigin.x - bounds.left) > tolerance {
                    print("[NARC] 📐 isWindowAtLayout: EDGE mismatch for \(layout.rawValue) — "
                          + "left edge: window=\(Int(axOrigin.x)), screen=\(Int(bounds.left))")
                    return false
                }
            case .top:
                if abs(axOrigin.y - bounds.top) > tolerance {
                    print("[NARC] 📐 isWindowAtLayout: EDGE mismatch for \(layout.rawValue) — "
                          + "top edge: window=\(Int(axOrigin.y)), screen=\(Int(bounds.top))")
                    return false
                }
            case .bottom:
                if abs(windowBottom - bounds.bottom) > tolerance {
                    print("[NARC] 📐 isWindowAtLayout: EDGE mismatch for \(layout.rawValue) — "
                          + "bottom edge: window=\(Int(windowBottom)), screen=\(Int(bounds.bottom))")
                    return false
                }
            }
        }

        print("[NARC] 📐 isWindowAtLayout: ✅ MATCH for \(layout.rawValue) on \(screen.localizedName)")
        return true
    }

    /// The screen edges that a layout pushes the window toward.
    static func targetEdges(for layout: WindowLayout) -> [ScreenEdge] {
        switch layout {
        case .leftHalf:    return [.left]
        case .rightHalf:   return [.right]
        case .topHalf:     return [.top]
        case .bottomHalf:  return [.bottom]
        case .topLeft:     return [.top, .left]
        case .topRight:    return [.top, .right]
        case .bottomLeft:  return [.bottom, .left]
        case .bottomRight: return [.bottom, .right]
        case .fullScreen:  return []  // no cross-screen
        case .center:      return []  // no cross-screen
        }
    }

    // MARK: - Adjacent Screen

    /// Find the next screen to cross to, given the current screen and the layout direction.
    ///
    /// Strategy for diagonal screen arrangements (e.g., top-left / bottom-right):
    /// - rightHalf or bottomHalf from the top-left screen → should reach the bottom-right screen
    /// - leftHalf or topHalf from the bottom-right screen → should reach the top-left screen
    ///
    /// For 2-screen diagonal setups, we use a relaxed check that requires the candidate
    /// screen to be at least partially in the correct direction (not strictly, but the
    /// primary axis component must not be in the opposite direction).
    static func adjacentScreen(from current: NSScreen, direction layout: WindowLayout) -> NSScreen? {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return nil }

        // No cross-screen for fullScreen / center
        let edges = targetEdges(for: layout)
        guard !edges.isEmpty else { return nil }

        let currentCenter = CGPoint(x: current.frame.midX, y: current.frame.midY)

        var bestScreen: NSScreen? = nil
        var bestDistance: CGFloat = CGFloat.greatestFiniteMagnitude

        for screen in screens {
            guard screen != current else { continue }

            let candidateCenter = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let dx = candidateCenter.x - currentCenter.x
            // NSScreen Y: positive = up
            let dy = candidateCenter.y - currentCenter.y

            // Strict check: candidate is clearly in the target direction
            var isValid = false
            for edge in edges {
                switch edge {
                case .right:  if dx > 0 { isValid = true }
                case .left:   if dx < 0 { isValid = true }
                case .top:    if dy > 0 { isValid = true }
                case .bottom: if dy < 0 { isValid = true }
                }
            }

            // For 2-screen diagonal setups, use a relaxed check.
            // The key insight: for diagonal arrangements, a single direction key
            // (e.g., right) should still cross to the other screen even if it's
            // diagonally placed, BUT only if the candidate is not clearly in the
            // OPPOSITE direction on the primary axis.
            //
            // Example: main screen (right-bottom) + secondary (left-top)
            //   - Press ⌃⌥→ (rightHalf): dx < 0, secondary is to the LEFT → should NOT cross
            //   - Press ⌃⌥← (leftHalf):  dx < 0, secondary is to the LEFT → should cross
            //   - Press ⌃⌥↑ (topHalf):   dy > 0, secondary is ABOVE → should cross
            //   - Press ⌃⌥↓ (bottomHalf): dy > 0, secondary is ABOVE → should NOT cross
            if !isValid && screens.count == 2 {
                // For each target edge, check if the candidate is at least "not clearly opposite".
                // We require the primary axis delta to be >= 0 (not opposite) for the direction.
                // This handles diagonal: e.g., pressing ↑ when screen is diagonally up-left,
                // dy > 0 passes strict check. But pressing → when screen is left, dx < 0 fails
                // both strict and relaxed.
                for edge in edges {
                    switch edge {
                    case .right:
                        // Candidate must not be clearly to the left (allow dx ~= 0 for stacked screens)
                        if dx >= 0 { isValid = true }
                    case .left:
                        // Candidate must not be clearly to the right
                        if dx <= 0 { isValid = true }
                    case .top:
                        // Candidate must not be clearly below
                        if dy >= 0 { isValid = true }
                    case .bottom:
                        // Candidate must not be clearly above
                        if dy <= 0 { isValid = true }
                    }
                }
            }

            if isValid {
                let distance = sqrt(dx * dx + dy * dy)
                if distance < bestDistance {
                    bestDistance = distance
                    bestScreen = screen
                }
            }
        }

        if let best = bestScreen {
            print("[NARC] 🧭 adjacentScreen: found \(best.localizedName) for direction \(layout.rawValue)")
        } else {
            print("[NARC] 🧭 adjacentScreen: no screen found for direction \(layout.rawValue) from \(current.localizedName)")
        }

        return bestScreen
    }

    // MARK: - Cross-Screen Entry Layout

    /// When crossing to a new screen, determine the "entry" layout.
    /// The window enters the new screen from the opposite side.
    /// e.g., moving right → enter the new screen on the left half.
    /// e.g., moving down  → enter the new screen on the top half.
    static func crossScreenEntryLayout(for layout: WindowLayout) -> WindowLayout {
        switch layout {
        case .rightHalf:   return .leftHalf
        case .leftHalf:    return .rightHalf
        case .topHalf:     return .bottomHalf
        case .bottomHalf:  return .topHalf
        case .topRight:    return .topLeft
        case .topLeft:     return .topRight
        case .bottomRight: return .bottomLeft
        case .bottomLeft:  return .bottomRight
        default:           return layout
        }
    }
}
