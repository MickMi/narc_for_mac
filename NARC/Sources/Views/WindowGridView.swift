import SwiftUI

// MARK: - Layout Thumbnail

/// Visual representation of where the window goes on screen.
struct LayoutThumbnail: View {
    let layout: WindowLayout

    var body: some View {
        GeometryReader { geo in
            let rect = layout.fractionalFrame
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.narcAccent.opacity(0.25))
                .frame(
                    width: geo.size.width * rect.width,
                    height: geo.size.height * rect.height
                )
                .offset(
                    x: geo.size.width * rect.origin.x,
                    y: geo.size.height * (1 - rect.origin.y - rect.height)
                )
        }
        .background(Color.narcSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.xs))
    }
}

// MARK: - Grid Cell

/// A single layout card in the grid. The card configures the shortcut only;
/// it deliberately never moves the frontmost window when clicked.
private struct LayoutGridCell: View {
    let layout: WindowLayout
    @ObservedObject var hotkeyService: HotkeyService
    let onEditShortcut: (ConfigurableHotkeyAction) -> Void
    let onSetEnabled: (Bool) -> Void
    let issueMessage: String?
    @State private var isHovered = false

    private var action: ConfigurableHotkeyAction {
        .forLayout(layout)
    }

    private var isEnabled: Bool {
        hotkeyService.isEnabled(for: action)
    }

    var body: some View {
        VStack(spacing: NarcSpacing.xs) {
            HStack {
                Toggle("启用", isOn: enabledBinding)
                    .toggleStyle(.checkbox)
                    .font(.narcCaption)
                    .accessibilityLabel("启用\(layout.rawValue)")
                Spacer(minLength: 0)
                if let issueMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.narcCaption)
                        .foregroundColor(.narcWarn)
                        .help(issueMessage)
                        .accessibilityLabel(issueMessage)
                }
            }

            // Thumbnail
            LayoutThumbnail(layout: layout)
                .aspectRatio(16 / 10, contentMode: .fit)
                .opacity(isEnabled ? 1 : 0.5)

            // Layout name
            Text(layout.rawValue)
                .font(.narcCaption)
                .foregroundColor(.narcText)
                .lineLimit(1)

            Button {
                onEditShortcut(action)
            } label: {
                HStack(spacing: NarcSpacing.xxs) {
                    Text(hotkeyService.shortcut(for: action).displayLabel)
                        .font(.narcMonoSmall)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Image(systemName: "pencil")
                        .font(.narcMonoTiny)
                }
                    .foregroundColor(.narcAccent)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("修改\(layout.rawValue)快捷键：\(hotkeyService.shortcut(for: action).displayLabel)")
            .accessibilityLabel("修改\(layout.rawValue)快捷键")
            .accessibilityValue(hotkeyService.shortcut(for: action).displayLabel)

            if let statusLabel {
                Text(statusLabel)
                    .font(.narcMonoTiny)
                    .foregroundColor(issueMessage == nil ? .narcTextMuted : .narcWarn)
                    .help(issueMessage ?? statusLabel)
            }
        }
        .padding(NarcSpacing.sm)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.sm)
                .stroke(
                    isHovered ? Color.narcAccent : Color.narcBorder,
                    lineWidth: 0.5
                )
        )
        .animation(.narcEase, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusLabel: String? {
        if issueMessage != nil { return "需处理 · 见下方" }
        switch hotkeyService.hotkeyState(for: action) {
        case .disabled: return "已停用"
        case .notRegistered: return "等待注册"
        default: return nil
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { hotkeyService.isEnabled(for: action) },
            set: onSetEnabled
        )
    }
}

// MARK: - Window Grid View

/// Window management tab content: configure layout shortcuts without moving
/// the current window. Window movement remains a keyboard action.
struct WindowGridView: View {
    @ObservedObject var windowManager: WindowManagerService
    @ObservedObject var hotkeyService: HotkeyService
    var onEditShortcut: (ConfigurableHotkeyAction) -> Void = { _ in }
    @State private var actionFailureMessages: [ConfigurableHotkeyAction: String] = [:]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NarcSpacing.lg) {
                // Header
                HStack(spacing: NarcSpacing.sm) {
                    Image(systemName: "keyboard")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                    Text("Window Layouts")
                        .font(.narcSubtitle)
                        .foregroundColor(.narcTextMuted)
                    Spacer()
                }

                // 3-column layout grid
                LazyVGrid(columns: columns, spacing: NarcSpacing.sm) {
                    ForEach(WindowLayout.allCases) { layout in
                        LayoutGridCell(
                            layout: layout,
                            hotkeyService: hotkeyService,
                            onEditShortcut: onEditShortcut,
                            onSetEnabled: { enabled in
                                setEnabled(enabled, for: .forLayout(layout))
                            },
                            issueMessage: shortcutIssue(for: .forLayout(layout))
                        )
                    }
                }

                // Keep actionable reasons outside the narrow cards so they
                // stay fully readable, including on a three-column layout.
                ForEach(ConfigurableHotkeyAction.layoutActions) { action in
                    if let message = shortcutIssue(for: action) {
                        VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                            Label(action.title, systemImage: "exclamationmark.triangle.fill")
                            Text(message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.narcCaption)
                        .foregroundColor(.narcWarn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(message)
                    }
                }

                Divider()
                    .padding(.vertical, NarcSpacing.xs)

                // Tips
                VStack(alignment: .leading, spacing: NarcSpacing.xs + 2) {
                    tipRow(icon: "keyboard", text: "启用的布局快捷键用于移动当前窗口")
                    tipRow(icon: "pencil", text: "点击快捷键或铅笔改键；配置不会移动窗口")
                    tipRow(icon: "hand.draw", text: "拖拽 NARC 圆点可移动位置")
                    tipRow(icon: "pin.fill", text: hotkeyService.activeShortcut(for: .pinnedWindowSwitcher).map { "\($0.displayLabel) 召回已标记窗口" } ?? "召回快捷键未启用，请到偏好设置修改")
                    tipRow(icon: "pin.slash", text: hotkeyService.activeShortcut(for: .toggleCurrentWindowPin).map { "\($0.displayLabel) 标记 / 取消当前窗口" } ?? "标记快捷键未启用，请到偏好设置修改")
                }
            }
            .padding(NarcSpacing.lg)
        }
        .onChange(of: hotkeyService.configurableHotkeyStates) { oldStates, newStates in
            for action in ConfigurableHotkeyAction.layoutActions where oldStates[action] != newStates[action] {
                guard let state = newStates[action] else { continue }
                switch state {
                case .active, .disabled:
                    actionFailureMessages[action] = nil
                default:
                    break
                }
            }
        }
    }

    private func setEnabled(_ enabled: Bool, for action: ConfigurableHotkeyAction) {
        let result = hotkeyService.setEnabled(enabled, for: action)
        if case .rejected(let reason) = result {
            actionFailureMessages[action] = reason.userMessage
        } else {
            actionFailureMessages[action] = nil
        }
    }

    private func shortcutIssue(for action: ConfigurableHotkeyAction) -> String? {
        if let failure = actionFailureMessages[action] { return failure }
        switch hotkeyService.hotkeyState(for: action) {
        case .rejected(let active, let requested, let reason):
            return "\(requested.displayLabel) 未生效：\(reason.userMessage)。仍使用 \(active.displayLabel)。"
        case .unavailable(let requested, let reason):
            return "\(requested.displayLabel) 未启用：\(reason.userMessage)。"
        default:
            return nil
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: icon)
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
                .frame(width: NarcSpacing.lg)
            Text(text)
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
        }
    }
}
