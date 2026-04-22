import SwiftUI

/// Observable state for keyboard selection in the panel.
/// Shared between AppDelegate (key event handler) and SwiftUI views (highlight rendering).
class KeyboardSelectionState: ObservableObject {
    @Published var selectedIndex: Int = -1
}

/// Represents an activatable item in the panel list.
/// Used to build a flat index for keyboard navigation across both
/// Monitoring and Pinned sections.
enum PanelItem {
    case monitoring(NotificationState)
    case pinned(PinnedWindow)
}
