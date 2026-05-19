import Cocoa

/// Thin coordination layer for window management operations.
///
/// Delegates to:
/// - `AXWindowHelper` for low-level AX API operations
/// - `ScreenNavigator` for cross-screen detection and navigation
/// - `HotkeyService` for hotkey registration (managed by AppDelegate)
///
/// Provides the public API consumed by:
/// - `AppDelegate` (via `moveActiveWindow`, `summonAppWindow`)
/// - `AppMonitorService` (via `summonAppWindow`)
/// - `PinnedWindowService` (via `findAppWindow`)
/// - `WindowGridView` (via `moveWindow`)
class WindowManagerService: ObservableObject {

    // MARK: - Window Layout (Hotkey Entry Point)

    /// Move the currently active (frontmost) window to the specified layout position.
    ///
    /// Cross-screen logic uses a state machine instead of frame detection:
    /// press same hotkey within 5s → cross to adjacent screen.
    static func moveActiveWindow(to layout: WindowLayout) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        guard let window = AXWindowHelper.getFocusedWindow(appElement) else {
            print("[NARC] Could not get focused window for \(frontApp.localizedName ?? "unknown")")
            return
        }

        // Handle macOS native fullscreen (green button).
        if AXWindowHelper.isNativeFullScreen(window) {
            print("[NARC] 🔲 Window is in native fullscreen, exiting first before applying \(layout.rawValue)")
            AXWindowHelper.exitNativeFullScreen(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                moveActiveWindow(to: layout)
            }
            return
        }

        let currentScreen = AXWindowHelper.screenForWindow(window) ?? NSScreen.main ?? NSScreen.screens.first!
        let windowID = AXWindowHelper.windowID(for: window)

        var targetScreen = currentScreen
        var targetLayout = layout

        // Cross-screen: state machine decides, not frame detection
        if windowID != 0,
           WindowLayoutState.shared.shouldCrossScreen(windowID: windowID, layout: layout, screen: currentScreen),
           NSScreen.screens.count > 1,
           let nextScreen = ScreenNavigator.adjacentScreen(from: currentScreen, direction: layout) {
            targetScreen = nextScreen
            targetLayout = ScreenNavigator.crossScreenEntryLayout(for: layout)
            print("[NARC] ↔️ Cross-screen: \(currentScreen.localizedName) → \(nextScreen.localizedName), entry layout=\(targetLayout.rawValue)")
        }

        // Apply layout
        let (axPos, axSize) = AXWindowHelper.calculateLayoutFrame(layout: targetLayout, on: targetScreen)
        print("[NARC] 🖥 moveActiveWindow: app=\(frontApp.localizedName ?? "?"), "
              + "layout=\(targetLayout.rawValue), screen=\(targetScreen.localizedName), "
              + "targetPos=(\(Int(axPos.x)),\(Int(axPos.y))), targetSize=\(Int(axSize.width))x\(Int(axSize.height))")
        AXWindowHelper.setFrame(window, position: axPos, size: axSize, on: targetScreen)

        // Record state for next cross-screen decision
        if windowID != 0 {
            WindowLayoutState.shared.record(windowID: windowID, layout: layout, screen: targetScreen)
        }

        print("[NARC] ✅ moveActiveWindow: \(layout.rawValue) on \(targetScreen.localizedName)")
    }

    /// Move the active window to a layout (instance method for UI binding).
    func moveWindow(to layout: WindowLayout) {
        Self.moveActiveWindow(to: layout)
    }

    // MARK: - Window Summoning (IM App Activation)

    /// Move a specific app's window to a target screen with a specific layout.
    static func moveAppWindow(bundleID: String, toScreen targetScreen: NSScreen, layout: WindowLayout = .center) {
        guard let window = findAppWindow(bundleID: bundleID) else { return }

        AXWindowHelper.raise(window)

        let (axPos, axSize) = AXWindowHelper.calculateLayoutFrame(layout: layout, on: targetScreen)
        AXWindowHelper.setFrame(window, position: axPos, size: axSize, on: targetScreen)

        print("[NARC] ✅ moveAppWindow: moved \(bundleID) to \(targetScreen.localizedName) at layout=\(layout.rawValue)")
    }

    /// Summon an app's window to the target screen with proportional scaling.
    /// Includes retry logic for apps that need time to restore windows after activation.
    static func summonAppWindow(bundleID: String, toScreen targetScreen: NSScreen) {
        if let window = findAppWindow(bundleID: bundleID) {
            summonWindow(window, toScreen: targetScreen)
        } else {
            print("[NARC] ⏳ summonAppWindow: no window found, retrying in 0.5s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = findAppWindow(bundleID: bundleID) {
                    summonWindow(window, toScreen: targetScreen)
                } else {
                    print("[NARC] ⚠️ summonAppWindow: still no window after retry for \(bundleID)")
                }
            }
        }
    }

    /// Summon a specific window to the target screen.
    ///
    /// Strategy: preserve original size, center on target screen.
    /// If already on target screen, just raise.
    static func summonWindow(_ window: AXUIElement, toScreen targetScreen: NSScreen) {
        AXWindowHelper.raise(window)

        let sourceScreen = AXWindowHelper.screenForWindow(window)

        // If already on target screen, just raise — don't move
        if let source = sourceScreen, source == targetScreen {
            print("[NARC] ✅ summonWindow: already on target screen, raised in place")
            return
        }

        // Preserve original size, center on target screen
        let currentSize = AXWindowHelper.getSize(window) ?? CGSize(width: 800, height: 600)
        let targetVisible = targetScreen.visibleFrame

        // Clamp size to fit within target screen
        let clampedWidth = min(currentSize.width, targetVisible.width)
        let clampedHeight = min(currentSize.height, targetVisible.height)
        let finalSize = CGSize(width: clampedWidth, height: clampedHeight)

        let nsX = targetVisible.origin.x + (targetVisible.width - finalSize.width) / 2
        let nsY = targetVisible.origin.y + (targetVisible.height - finalSize.height) / 2
        let axPos = AXWindowHelper.nsToAX(x: nsX, y: nsY, height: finalSize.height)
        AXWindowHelper.setFrame(window, position: axPos, size: finalSize, on: targetScreen)

        print("[NARC] ✅ summonWindow: moved to \(targetScreen.localizedName) centered")
    }

    // MARK: - Window Finding

    /// Find the main window of an app by bundle ID.
    private static func findAppWindow(bundleID: String) -> AXUIElement? {
        return findAppWindow(bundleID: bundleID, matchingTitle: nil)
    }

    /// Find a specific window of an app by bundle ID and optional title.
    /// If matchingTitle is provided, only that window is unminimized.
    /// Otherwise, the main/first window is returned.
    static func findAppWindow(bundleID: String, matchingTitle: String?) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("[NARC] ⚠️ findAppWindow: app not found for \(bundleID)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Title-based search
        if let targetTitle = matchingTitle {
            if let windows = AXWindowHelper.getWindows(appElement) {
                for window in windows {
                    if let title = AXWindowHelper.getTitle(window), title == targetTitle {
                        if AXWindowHelper.isMinimized(window) {
                            AXWindowHelper.unminimize(window)
                            print("[NARC] 📤 findAppWindow: unminimized matched window '\(targetTitle)'")
                        }
                        print("[NARC] 📍 findAppWindow: matched window by title '\(targetTitle)'")
                        return window
                    }
                }
            }
            print("[NARC] ⚠️ findAppWindow: no window matched title '\(targetTitle)', falling back...")
        }

        // Strategy 1: Main window
        if let mainWindow = AXWindowHelper.getMainWindow(appElement) {
            print("[NARC] 📍 findAppWindow: using main window")
            return mainWindow
        }

        // Strategy 2: First window from list (unminimize if needed)
        if let windows = AXWindowHelper.getWindows(appElement), let firstWindow = windows.first {
            if AXWindowHelper.isMinimized(firstWindow) {
                AXWindowHelper.unminimize(firstWindow)
                print("[NARC] 📤 findAppWindow: unminimized first window for \(bundleID)")
            }
            print("[NARC] 📍 findAppWindow: using first window from list")
            return firstWindow
        }

        // Strategy 3: Focused window
        if let focusedWindow = AXWindowHelper.getFocusedWindow(appElement) {
            print("[NARC] 📍 findAppWindow: using focused window")
            return focusedWindow
        }

        print("[NARC] ⚠️ findAppWindow: could not get any window for \(bundleID)")
        return nil
    }
}
