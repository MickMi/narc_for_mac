import SwiftUI

/// NARC - Notification & Application Resource Center
/// A native macOS floating widget app for unified notification and window management.
@main
struct NARCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (opened from menu bar or panel gear icon)
        Settings {
            PreferencesView()
        }
    }
}
