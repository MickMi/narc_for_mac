import SwiftUI

/// The main panel that expands from the floating widget.
/// Contains two tabs: Notifications and Window Management.
struct PanelView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var windowManager: WindowManagerService
    var onClose: () -> Void
    var onOpenPreferences: () -> Void
    /// The screen where NARC's floating widget is located.
    var narcScreen: NSScreen?

    @State private var selectedTab: PanelTab = .notifications

    enum PanelTab: String, CaseIterable {
        case notifications = "Notifications"
        case windows = "Windows"

        var icon: String {
            switch self {
            case .notifications: return "bell.fill"
            case .windows: return "macwindow"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            // Tab bar
            tabBar

            // Content
            Group {
                switch selectedTab {
                case .notifications:
                    NotificationListView(appMonitor: appMonitor, onClose: onClose, narcScreen: narcScreen)
                case .windows:
                    WindowGridView(windowManager: windowManager)
                }
            }
            .frame(maxHeight: .infinity)

            // Footer
            footerBar
        }
        .frame(width: 320, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text("NARC")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Divider()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            Text("Live")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green)

            Spacer()

            Text("Last updated: \(formattedTime)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
