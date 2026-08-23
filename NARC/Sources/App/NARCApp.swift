import SwiftUI

/// NARC - Notification & Application Resource Center
/// A native macOS floating widget app for unified notification and window management.
///
/// All real windows (floating widget, panel, dashboard, preferences) are managed
/// by AppDelegate via AppKit. The `Settings` scene here is a no-op placeholder —
/// SwiftUI `App` requires at least one Scene, but `Settings` never auto-opens
/// a window. Actual preferences are handled by AppDelegate's `PreferencesWindow`.
@main
struct NARCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
