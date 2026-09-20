import SwiftUI

/// The panel surface currently receiving keyboard input.
///
/// Only Notifications owns the legacy flat list of monitored apps and pinned
/// windows. Inbox and Windows must leave their editing and interaction keys to
/// SwiftUI instead of routing them through that hidden list.
enum PanelKeyboardRoute: Equatable {
    case inbox
    case notifications
    case windows

    var supportsItemNavigation: Bool {
        self == .notifications
    }

    func decision(for keyCode: UInt16, isTextEditing: Bool) -> PanelKeyboardDecision {
        if keyCode == 53 {
            return .dismissPanel
        }
        if isTextEditing || !supportsItemNavigation {
            return .passThrough
        }
        return .legacyItemNavigation
    }
}

enum PanelKeyboardDecision: Equatable {
    case dismissPanel
    case passThrough
    case legacyItemNavigation
}

/// Observable state for keyboard selection in the panel.
/// Shared between AppDelegate (key event handler) and SwiftUI views (highlight rendering).
class KeyboardSelectionState: ObservableObject {
    @Published var selectedIndex: Int = -1

    /// The panel always opens on Inbox. PanelView updates this value when the
    /// user explicitly changes tabs.
    @Published var route: PanelKeyboardRoute = .inbox {
        didSet {
            guard route != oldValue else { return }
            selectedIndex = -1
            wantsKeyboardNavigation = false
        }
    }

    /// Whether the user has shown intent to navigate the panel via keyboard.
    /// Starts false when the panel opens. Set to true on:
    /// - ↑↓ / Tab press (the natural "I want to navigate" gesture)
    /// - Mouse click inside the panel
    ///
    /// Number keys and Enter are gated behind this flag so that accidental
    /// keystrokes don't activate panel items when the user opens the panel
    /// and continues typing in their original app.
    @Published var wantsKeyboardNavigation: Bool = false
}

/// Represents an activatable item in the panel list.
/// Used to build a flat index for keyboard navigation across both
/// Monitoring and Pinned sections.
enum PanelItem {
    case monitoring(NotificationState)
    case pinned(PinnedWindow)
}

/// A keyboard action for the dedicated pinned-window switcher.
///
/// This route is intentionally independent from `PanelKeyboardRoute`: the
/// switcher is a keyboard-first launcher, so it must never inherit the main
/// panel's click/Tab intent gate or the Monitoring section's index offset.
enum PinnedWindowSwitcherCommand: Equatable {
    case select(Int)
    case activate(Int)
    case dismiss
    case passThrough
}

enum PinnedWindowSwitcherKeyboard {
    private static let digitIndexByKeyCode: [UInt16: Int] = [
        18: 0, // 1
        19: 1, // 2
        20: 2, // 3
        21: 3, // 4
        23: 4, // 5
        22: 5, // 6
        26: 6, // 7
        28: 7, // 8
        25: 8, // 9
    ]

    static func command(
        for keyCode: UInt16,
        selectedIndex: Int,
        itemCount: Int
    ) -> PinnedWindowSwitcherCommand {
        if keyCode == 53 {
            return .dismiss
        }

        guard itemCount > 0 else {
            return .passThrough
        }

        switch keyCode {
        case 126: // ↑
            return .select(max(0, min(selectedIndex - 1, itemCount - 1)))
        case 125: // ↓
            return .select(max(0, min(selectedIndex + 1, itemCount - 1)))
        case 36: // Return
            guard selectedIndex >= 0, selectedIndex < itemCount else {
                return .passThrough
            }
            return .activate(selectedIndex)
        default:
            guard let index = digitIndexByKeyCode[keyCode], index < itemCount else {
                return .passThrough
            }
            return .activate(index)
        }
    }
}

@MainActor
final class PinnedWindowSwitcherSelectionState: ObservableObject {
    @Published var selectedIndex: Int = -1

    func reset(itemCount: Int) {
        selectedIndex = itemCount > 0 ? 0 : -1
    }

    func clamp(itemCount: Int) {
        guard itemCount > 0 else {
            selectedIndex = -1
            return
        }
        selectedIndex = max(0, min(selectedIndex, itemCount - 1))
    }
}
