import SwiftUI

enum PanelTab: String, CaseIterable {
    case inbox = "Todo"
    case codexReplies = "AI 回复"
    case notifications = "消息"
    case windows = "窗口"

    var keyboardRoute: PanelKeyboardRoute {
        switch self {
        case .inbox: return .inbox
        case .codexReplies: return .codexReplies
        case .notifications: return .notifications
        case .windows: return .windows
        }
    }
}

final class PanelSelectionState: ObservableObject {
    @Published var selectedTab: PanelTab = .inbox
}

/// The main panel that expands from the floating widget.
/// Starts with the shared Todo capture flow, with Notifications and Window
/// Management as secondary tabs.
struct PanelView: View {
    @ObservedObject var appMonitor: AppMonitorService
    @ObservedObject var windowManager: WindowManagerService
    @ObservedObject var pinnedWindowService: PinnedWindowService
    @ObservedObject var hotkeyService: HotkeyService
    @ObservedObject var assistantStore: AssistantStore
    @ObservedObject var inboxCaptureState: InboxCaptureState
    @ObservedObject var codexCompletionService: CodexCompletionService
    @ObservedObject var panelSelection: PanelSelectionState
    var onClose: () -> Void
    var onOpenPreferences: () -> Void
    var onEditShortcut: (ConfigurableHotkeyAction) -> Void = { _ in }
    var onOpenAssistant: () -> Void = {}
    var onOpenInstantQuestion: () -> Void = {}
    var onOpenCodexReply: (CodexCompletionEvent, @escaping (Bool) -> Void) -> Void = { _, completion in
        completion(false)
    }
    /// Resolves the floating widget's current screen at action time.
    var narcScreenProvider: () -> NSScreen?
    /// Keyboard selection state for ↑↓ navigation.
    @ObservedObject var keyboardSelection: KeyboardSelectionState

    @StateObject private var codexReplyLayout = CodexCompletionCardLayout()

    private var selectedTab: PanelTab { panelSelection.selectedTab }

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
                    QuickCaptureView(
                        store: assistantStore,
                        captureState: inboxCaptureState,
                        compact: true,
                        onDismiss: onClose,
                        onOpenAssistant: onOpenAssistant
                    )
                case .codexReplies:
                    if codexCompletionService.pendingEvents.isEmpty {
                        ContentUnavailableView("没有待看的 AI 回复",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text("收到新回复后，会在这里和悬浮数字中同步显示。"))
                    } else {
                        CodexCompletionCard(
                            service: codexCompletionService,
                            layout: codexReplyLayout,
                            onResize: {},
                            onOpen: onOpenCodexReply,
                            fillsAvailableHeight: true
                        )
                        .padding(.horizontal, NarcSpacing.xs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .top)
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
        .background(Color.narcFocusSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.focus, style: .continuous))
        .onAppear {
            keyboardSelection.route = selectedTab.keyboardRoute
        }
        .onChange(of: panelSelection.selectedTab) { _, newTab in
            keyboardSelection.route = newTab.keyboardRoute
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: NarcSpacing.xs) {
            Text("NARC")
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.narcText)

            Spacer()

            Button {
                panelSelection.selectedTab = .inbox
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(hotkeyService.activeShortcut(for: .quickCapture).map { "记 Todo（\($0.displayLabel)）" } ?? "记 Todo")

            Button(action: onOpenInstantQuestion) {
                Image(systemName: "sparkles")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("AI / 网页搜索")

            Button(action: onOpenAssistant) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("打开 Assistant")

            Button(action: onOpenPreferences) {
                Image(systemName: "slider.horizontal.3")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("偏好设置")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("关闭面板（Esc）")
        }
        .padding(.horizontal, NarcSpacing.xl)
        .padding(.vertical, NarcSpacing.md)
    }

    // MARK: - Tab Bar (Pill Style)

    private var tabBar: some View {
        HStack(spacing: NarcSpacing.xs) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.narcSnap) {
                        panelSelection.selectedTab = tab
                    }
                }) {
                    HStack(spacing: NarcSpacing.xs + NarcSpacing.xxs) {
                        Text(tab.rawValue)
                            .font(.narcBody)
                            .lineLimit(1)
                        if tab == .codexReplies,
                           !codexCompletionService.pendingEvents.isEmpty {
                            Text("\(codexCompletionService.pendingEvents.count)")
                                .font(.narcCaption)
                                .monospacedDigit()
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(selectedTab == tab ? .narcAccent : .narcTextMuted)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous)
                            .fill(selectedTab == tab ? Color.narcAccent.opacity(0.09) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NarcSpacing.xl)
        .padding(.bottom, NarcSpacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.narcBorder.opacity(0.35)).frame(height: 0.5)
                .padding(.horizontal, NarcSpacing.xl)
        }
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
                    Text("选择")
                        .font(.narcMonoTiny)

                    Text("↩")
                        .font(.narcMonoTiny)
                        .padding(.horizontal, NarcSpacing.xxs + 1)
                        .padding(.vertical, NarcSpacing.xxs / 2)
                        .background(Color.narcSurfaceMuted)
                        .cornerRadius(NarcRadius.xs / 2)
                    Text("打开")
                        .font(.narcMonoTiny)

                    Text("esc")
                        .font(.narcMonoTiny)
                        .padding(.horizontal, NarcSpacing.xxs + 1)
                        .padding(.vertical, NarcSpacing.xxs / 2)
                        .background(Color.narcSurfaceMuted)
                        .cornerRadius(NarcRadius.xs / 2)
                    Text("关闭")
                        .font(.narcMonoTiny)
                }
                .foregroundColor(.narcTextMuted)
            } else if selectedTab == .codexReplies {
                Text("待看的回复 · 点击继续对话")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextMuted)
            } else {
                Text("勾选启用布局 · 点击快捷键修改")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextMuted)
            }

            Spacer()
        }
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcFocusSurface)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
