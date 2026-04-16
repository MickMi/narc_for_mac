import SwiftUI

/// Notification tab content: list of monitored apps with their status.
struct NotificationListView: View {
    @ObservedObject var appMonitor: AppMonitorService
    var onClose: () -> Void
    /// The screen where NARC's floating widget is located.
    var narcScreen: NSScreen?

    var body: some View {
        let enabledStates = appMonitor.filteredStates

        if enabledStates.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(enabledStates) { state in
                        let filterAction = appMonitor.resolveFilterAction(for: state)
                        AppItemRow(state: state, filterAction: filterAction) {
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
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A single app item row in the notification list.
struct AppItemRow: View {
    @ObservedObject var state: NotificationState
    var filterAction: NotificationFilter.FilterAction = .normal
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
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
            isHovering ? Color.primary.opacity(0.06) :
            (filterAction == .highlight && state.hasNewNotification ? Color.orange.opacity(0.06) : Color.clear)
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
