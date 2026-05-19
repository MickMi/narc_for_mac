import Cocoa

/// Multi-monitor screen navigation: finding adjacent screens and computing
/// cross-screen entry layouts.
///
/// Simplified: layout detection is now handled by WindowLayoutState (state machine),
/// so this module only needs directional navigation logic.
enum ScreenNavigator {

    // MARK: - Screen Edge

    /// The screen edges that a layout pushes the window toward.
    enum ScreenEdge { case left, right, top, bottom }

    /// Edges that define the cross-screen direction for a layout.
    /// fullScreen and center have no direction → never trigger cross-screen.
    static func crossScreenEdges(for layout: WindowLayout) -> [ScreenEdge] {
        switch layout {
        case .leftHalf:    return [.left]
        case .rightHalf:   return [.right]
        case .topHalf:     return [.top]
        case .bottomHalf:  return [.bottom]
        case .topLeft:     return [.top, .left]
        case .topRight:    return [.top, .right]
        case .bottomLeft:  return [.bottom, .left]
        case .bottomRight: return [.bottom, .right]
        case .fullScreen:  return []
        case .center:      return []
        }
    }

    // MARK: - Adjacent Screen

    /// Find the next screen to cross to, given the current screen and the layout direction.
    ///
    /// For 2-screen diagonal setups, uses a relaxed check: the candidate must not be
    /// clearly in the opposite direction on the primary axis.
    static func adjacentScreen(from current: NSScreen, direction layout: WindowLayout) -> NSScreen? {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return nil }

        let edges = crossScreenEdges(for: layout)
        guard !edges.isEmpty else { return nil }

        let currentCenter = CGPoint(x: current.frame.midX, y: current.frame.midY)

        var bestScreen: NSScreen? = nil
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for screen in screens {
            guard screen != current else { continue }

            let candidateCenter = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let dx = candidateCenter.x - currentCenter.x
            let dy = candidateCenter.y - currentCenter.y  // NSScreen Y: positive = up

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

            // For 2-screen diagonal setups, relax: candidate must not be clearly opposite
            if !isValid && screens.count == 2 {
                for edge in edges {
                    switch edge {
                    case .right:  if dx >= 0 { isValid = true }
                    case .left:   if dx <= 0 { isValid = true }
                    case .top:    if dy >= 0 { isValid = true }
                    case .bottom: if dy <= 0 { isValid = true }
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
            print("[NARC] 🧭 adjacentScreen: found \(best.localizedName) for \(layout.rawValue)")
        }
        return bestScreen
    }

    // MARK: - Cross-Screen Entry Layout

    /// When crossing to a new screen, the window enters from the opposite side.
    /// e.g., moving right → enter the new screen on the left half.
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
