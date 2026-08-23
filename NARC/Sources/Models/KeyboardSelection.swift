import SwiftUI

/// Observable state for keyboard selection in the panel.
/// Shared between AppDelegate (key event handler) and SwiftUI views (highlight rendering).
class KeyboardSelectionState: ObservableObject {
    @Published var selectedIndex: Int = -1

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
