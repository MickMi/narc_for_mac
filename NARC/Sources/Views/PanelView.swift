import SwiftUI

/// The main panel that expands from the floating widget.
/// Starts with the shared Inbox capture flow, with Notifications and Window
/// Management as secondary tabs.
struct PanelView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var windowManager: WindowManagerService
    @ObservedObject var pinnedWindowService: PinnedWindowService
    @ObservedObject var hotkeyService: HotkeyService
    @ObservedObject var assistantStore: AssistantStore
    @ObservedObject var inboxCaptureState: InboxCaptureState
    var onClose: () -> Void
    var onOpenPreferences: () -> Void
    var onEditShortcut: (ConfigurableHotkeyAction) -> Void = { _ in }
    var onOpenAssistant: () -> Void = {}
    /// Resolves the floating widget's current screen at action time.
    var narcScreenProvider: () -> NSScreen?
    /// Keyboard selection state for ↑↓ navigation.
    @ObservedObject var keyboardSelection: KeyboardSelectionState

    @State private var selectedTab: PanelTab = .inbox

    enum PanelTab: String, CaseIterable {
        case inbox = "Inbox"
        case notifications = "Notifications"
        case windows = "Windows"

        var icon: String {
            switch self {
            case .inbox: return "tray.fill"
            case .notifications: return "bell.fill"
            case .windows: return "macwindow"
            }
        }

        var keyboardRoute: PanelKeyboardRoute {
            switch self {
            case .inbox: return .inbox
            case .notifications: return .notifications
            case .windows: return .windows
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
                case .inbox:
                    ScrollView {
                        QuickCaptureView(
                            store: assistantStore,
                            captureState: inboxCaptureState,
                            compact: true,
                            onDismiss: onClose,
                            onOpenAssistant: onOpenAssistant
                        )
                    }
                case .notifications:
                    NotificationListView(
                        appMonitor: appMonitor,
                        pinnedWindowService: pinnedWindowService,
                        hotkeyService: hotkeyService,
                        onClose: onClose,
                        narcScreenProvider: narcScreenProvider,
                        keyboardSelection: keyboardSelection
                    )
                case .windows:
                    WindowGridView(
                        windowManager: windowManager,
                        hotkeyService: hotkeyService,
                        onEditShortcut: onEditShortcut
                    )
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
        .onAppear {
            keyboardSelection.route = selectedTab.keyboardRoute
        }
        .onChange(of: selectedTab) { _, newTab in
            keyboardSelection.route = newTab.keyboardRoute
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: NarcSpacing.xs) {
            Text("NARC")
                .font(.narcSubtitle)
                .foregroundColor(.narcText)

            Spacer()

            Button {
                selectedTab = .inbox
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help(hotkeyService.activeShortcut(for: .quickCapture).map { "随手记（\($0.displayLabel)）" } ?? "随手记")

            Button(action: onOpenAssistant) {
                Image(systemName: "sparkles")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .help("打开 Assistant")

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
            if selectedTab == .inbox {
                Text("↵")
                    .font(.narcMonoTiny)
                    .padding(.horizontal, NarcSpacing.xs)
                    .padding(.vertical, NarcSpacing.xxs)
                    .background(Color.narcSurfaceMuted)
                    .cornerRadius(NarcRadius.xs / 2)
                Text("记录")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextMuted)

                Text("⌘↵")
                    .font(.narcMonoTiny)
                    .padding(.horizontal, NarcSpacing.xs)
                    .padding(.vertical, NarcSpacing.xxs)
                    .background(Color.narcSurfaceMuted)
                    .cornerRadius(NarcRadius.xs / 2)
                Text("Todo")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextMuted)
            } else if selectedTab == .notifications {
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
            } else {
                Text("勾选启用布局 · 点击快捷键修改")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextMuted)
            }

            if selectedTab != .inbox {
                Spacer()

                Circle()
                    .fill(Color.narcSuccess)
                    .frame(width: 6, height: 6)

                Text("Live")
                    .font(.narcCaption)
                    .foregroundColor(.narcSuccess)
            } else {
                Spacer()
            }
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
