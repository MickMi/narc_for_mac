import SwiftUI

/// The main panel that expands from the floating widget.
/// Contains two tabs: Notifications and Window Management.
///
/// **Scope note**: this panel only surfaces NARC's "ambient awareness" data —
/// IM badges and pinned windows. Claude Code events (both external iTerm
/// sessions and Workspace tabs) are handled separately:
/// - External Claude → standalone stacked toast notifications (each event
///   gets its own dismissable popup that jumps to the source terminal window).
/// - Workspace Claude → the Dashboard sidebar's per-tab attention bar +
///   unseen-change red dot.
struct PanelView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var claudeService: ClaudeSessionService
    @ObservedObject var windowManager: WindowManagerService
    @ObservedObject var pinnedWindowService: PinnedWindowService
    var onClose: () -> Void
    var onOpenPreferences: () -> Void
    /// Toggle the standalone Workspace (Dashboard) window. Mirrors the
    /// `⌃⌥W` global hotkey and the right-click-on-widget gesture, so all
    /// three entry points share identical behavior.
    var onToggleWorkspace: () -> Void
    /// The screen where NARC's floating widget is located.
    var narcScreen: NSScreen?
    /// Keyboard selection state for ↑↓ navigation.
    @ObservedObject var keyboardSelection: KeyboardSelectionState

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
                    NotificationListView(
                        appMonitor: appMonitor,
                        claudeService: claudeService,
                        pinnedWindowService: pinnedWindowService,
                        onClose: onClose,
                        narcScreen: narcScreen,
                        keyboardSelection: keyboardSelection
                    )
                case .windows:
                    WindowGridView(windowManager: windowManager)
                }
            }
            .frame(maxHeight: .infinity)

            // Footer
            footerBar
        }
        .frame(width: NarcSize.panelWidth, height: NarcSize.panelHeight)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.xl)
                .strokeBorder(Color.narcBorder)
        )
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: NarcSpacing.xs) {
            Text("NARC")
                .font(.narcSubtitle)
                .foregroundColor(.narcText)

            Spacer()

            // Workspace toggle — mirrors ⌃⌥W and the right-click-on-widget
            // gesture. Placed at the leftmost position of the trailing button
            // group so it gets the most-used slot without crowding the close
            // button.
            Button(action: onToggleWorkspace) {
                Image(systemName: "macwindow")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("打开 / 隐藏 Workspace（⌃⌥W）")

            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("偏好设置")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("关闭面板（Esc）")
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.md)
    }

    // MARK: - Tab Bar (Pill Style)

    private var tabBar: some View {
        HStack(spacing: NarcSpacing.sm) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.narcSnap) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: NarcSpacing.xs + NarcSpacing.xxs) {
                        Image(systemName: tab.icon)
                            .font(.narcBody)
                        Text(tab.rawValue)
                            .font(.narcBody)
                    }
                    .foregroundColor(selectedTab == tab ? .narcAccent : .narcTextMuted)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.sm)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? Color.narcAccent.opacity(0.14) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.bottom, NarcSpacing.sm)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: NarcSpacing.xs) {
            // Keyboard hints
            Group {
                Text("↑↓")
                    .font(.narcMonoTiny)
                    .padding(.horizontal, NarcSpacing.xxs + 1)
                    .padding(.vertical, NarcSpacing.xxs / 2)
                    .background(Color.narcSurfaceMuted)
                    .cornerRadius(NarcRadius.xs / 2)
                Text("select")
                    .font(.narcMonoTiny)

                Text("↩")
                    .font(.narcMonoTiny)
                    .padding(.horizontal, NarcSpacing.xxs + 1)
                    .padding(.vertical, NarcSpacing.xxs / 2)
                    .background(Color.narcSurfaceMuted)
                    .cornerRadius(NarcRadius.xs / 2)
                Text("open")
                    .font(.narcMonoTiny)

                Text("esc")
                    .font(.narcMonoTiny)
                    .padding(.horizontal, NarcSpacing.xxs + 1)
                    .padding(.vertical, NarcSpacing.xxs / 2)
                    .background(Color.narcSurfaceMuted)
                    .cornerRadius(NarcRadius.xs / 2)
                Text("close")
                    .font(.narcMonoTiny)
            }
            .foregroundColor(.narcTextMuted)

            Spacer()

            Circle()
                .fill(Color.narcSuccess)
                .frame(width: 6, height: 6)

            Text("Live")
                .font(.narcCaption)
                .foregroundColor(.narcSuccess)
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcBackground)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
