import SwiftUI

/// Notification tab content: list of monitored apps and pinned windows.
/// Divided into two sections: Monitoring (IM badge tracking) and Pinned (user-pinned windows).
struct NotificationListView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var pinnedWindowService: PinnedWindowService
    var onClose: () -> Void
    /// The screen where NARC's floating widget is located.
    var narcScreen: NSScreen?
    /// Keyboard selection state for ↑↓ navigation.
    @ObservedObject var keyboardSelection: KeyboardSelectionState

    var body: some View {
        let enabledStates = appMonitor.filteredStates
        let pinnedWindows = pinnedWindowService.pinnedWindows

        if enabledStates.isEmpty && pinnedWindows.isEmpty {
            emptyState
        } else {
            // Build flat index for keyboard navigation:
            // running monitoring apps first, then pinned windows
            let runningStates = enabledStates.filter { $0.isRunning }
            let monitoringOffset = 0
            let pinnedOffset = runningStates.count

            ScrollView {
                LazyVStack(spacing: 0) {
                    // MARK: - Monitoring Section
                    if !enabledStates.isEmpty {
                        SectionHeader(title: "Monitoring", icon: "bell.fill")

                        ForEach(Array(enabledStates.enumerated()), id: \.element.id) { _, state in
                            let filterAction = appMonitor.resolveFilterAction(for: state)
                            // Only running apps get a keyboard index
                            let kbIndex = state.isRunning
                                ? monitoringOffset + runningStates.firstIndex(where: { $0.id == state.id })!
                                : -1
                            AppItemRow(
                                state: state,
                                filterAction: filterAction,
                                keyboardIndex: kbIndex,
                                isKeyboardSelected: kbIndex >= 0 && kbIndex == keyboardSelection.selectedIndex
                            ) {
                                appMonitor.activateApp(
                                    bundleID: state.app.bundleID,
                                    summonToScreen: narcScreen
                                )
                                onClose()
                            }

                            if state.id != enabledStates.last?.id {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    }

                    // MARK: - Pinned Section
                    if !pinnedWindows.isEmpty {
                        if !enabledStates.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }

                        SectionHeader(title: "Pinned", icon: "pin.fill")

                        ForEach(Array(pinnedWindows.enumerated()), id: \.element.id) { index, pinned in
                            let runtimeState = pinnedWindowService.runtimeStates[pinned.id]
                            let kbIndex = pinnedOffset + index
                            PinnedWindowRow(
                                pinned: pinned,
                                runtimeState: runtimeState,
                                keyboardIndex: kbIndex,
                                isKeyboardSelected: kbIndex == keyboardSelection.selectedIndex,
                                onTap: {
                                    pinnedWindowService.activatePinnedWindow(
                                        pinned,
                                        summonToScreen: narcScreen
                                    )
                                    onClose()
                                },
                                onTogglePersistence: {
                                    pinnedWindowService.togglePersistence(id: pinned.id)
                                },
                                onRemove: {
                                    pinnedWindowService.unpin(id: pinned.id)
                                }
                            )

                            if pinned.id != pinnedWindows.last?.id {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("😴")
                .font(.system(size: 40))
            Text("No monitored apps")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            Text("Go to Settings to add apps →")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("or press ⌃⌥P to pin a window")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Section Header

/// A section header with icon and title.
struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

// MARK: - Pinned Window Row

/// A single pinned window row in the notification list.
struct PinnedWindowRow: View {
    let pinned: PinnedWindow
    let runtimeState: PinnedWindowRuntimeState?
    /// Keyboard navigation index (0-based). -1 means not navigable.
    var keyboardIndex: Int = -1
    /// Whether this row is currently selected via keyboard.
    var isKeyboardSelected: Bool = false
    var onTap: () -> Void
    var onTogglePersistence: () -> Void
    var onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Keyboard shortcut number badge
            if keyboardIndex >= 0 && keyboardIndex < 10 {
                Text("\(keyboardIndex + 1 < 10 ? keyboardIndex + 1 : 0)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isKeyboardSelected ? .white : .secondary)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isKeyboardSelected ? Color.accentColor : Color.primary.opacity(0.08))
                    )
            }

            // App icon
            appIcon

            // Window info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isAlive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(pinned.appDisplayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    // Toggle persistence: 📌 ↔ 🔒
                    Button(action: onTogglePersistence) {
                        Image(systemName: pinned.isPersistent ? "lock.fill" : "pin.fill")
                            .font(.system(size: 11))
                            .foregroundColor(pinned.isPersistent ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(pinned.isPersistent ? "Unlock (temporary)" : "Lock (persistent)")

                    // Remove
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            } else {
                // Status indicator when not hovering
                if !isAlive {
                    // Gray dot — window/app not running
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                } else {
                    // Persistence indicator
                    Image(systemName: pinned.isPersistent ? "lock.fill" : "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(pinned.isPersistent ? .orange : .secondary.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isKeyboardSelected ? Color.accentColor.opacity(0.15) :
            (isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
    }

    // MARK: - Helpers

    private var isAlive: Bool {
        runtimeState?.isAlive ?? false
    }

    private var displayTitle: String {
        runtimeState?.currentTitle ?? pinned.windowTitle
    }

    private var appIcon: some View {
        Group {
            if let icon = getAppIcon(bundleID: pinned.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(isAlive ? 1.0 : 0.5)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "macwindow")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
            }
        }
    }

    private func getAppIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - App Item Row (Monitoring)

/// A single app item row in the notification list.
struct AppItemRow: View {
    @ObservedObject var state: NotificationState
    var filterAction: NotificationFilter.FilterAction = .normal
    /// Keyboard navigation index (0-based). -1 means not navigable.
    var keyboardIndex: Int = -1
    /// Whether this row is currently selected via keyboard.
    var isKeyboardSelected: Bool = false
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Keyboard shortcut number badge
            if keyboardIndex >= 0 && keyboardIndex < 10 {
                Text("\(keyboardIndex + 1 < 10 ? keyboardIndex + 1 : 0)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isKeyboardSelected ? .white : .secondary)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isKeyboardSelected ? Color.accentColor : Color.primary.opacity(0.08))
                    )
            }

            // App icon
            appIcon

            // App info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(state.app.displayName)
                        .font(.system(size: 14, weight: filterAction == .highlight ? .bold : .semibold))
                        .foregroundColor(filterAction == .silent ? .secondary : .primary)

                    // Highlight indicator
                    if filterAction == .highlight && state.hasNewNotification {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                Text(state.isRunning ? state.app.category.rawValue : "Not running")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status indicator
            statusIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            isKeyboardSelected ? Color.accentColor.opacity(0.15) :
            (isHovering ? Color.primary.opacity(0.06) :
            (filterAction == .highlight && state.hasNewNotification ? Color.orange.opacity(0.06) : Color.clear))
        )
        .opacity(filterAction == .silent ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if state.isRunning {
                onTap()
            }
        }
    }

    // MARK: - App Icon

    private var appIcon: some View {
        Group {
            if let icon = getAppIcon(bundleID: state.app.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "app.fill")
                            .foregroundColor(.secondary)
                    }
            }
        }
    }

    /// Get the app icon from its bundle ID.
    private func getAppIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if !state.isRunning {
            // Gray dot — not running
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 16, height: 16)
        } else if state.hasNewNotification {
            // Red badge with count
            ZStack {
                Capsule()
                    .fill(Color.red)
                    .frame(minWidth: 22, maxHeight: 22)

                Text("\(state.badgeCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
            }
            .fixedSize()
        } else {
            // Green checkmark — running, no notifications
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 22, height: 22)

                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
            }
        }
    }
}
