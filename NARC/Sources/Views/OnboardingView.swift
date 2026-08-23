import SwiftUI

enum OnboardingPresentationPolicy {
    static let completionKey = "narc.onboarding.completed.v2"

    static func shouldPresent(hasCompleted: Bool, force: Bool = false) -> Bool {
        force || !hasCompleted
    }
}

struct OnboardingView: View {
    @ObservedObject var hotkeyService: HotkeyService

    let onOpenAssistant: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.xl) {
            header
            coreActions
            accessibilityStatus
            footer
        }
        .padding(NarcSpacing.xxl)
        .frame(width: 560)
        .background(Color.narcBackground)
    }

    private var header: some View {
        HStack(spacing: NarcSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.narcAccent.opacity(0.14))
                    .frame(width: 52, height: 52)
                Text("N")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.narcAccent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                Text("NARC 已在运行")
                    .font(.narcDisplay)
                    .foregroundColor(.narcText)
                Text("不用记菜单，先记住两个动作。")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
            }
        }
    }

    private var coreActions: some View {
        VStack(spacing: NarcSpacing.md) {
            OnboardingActionRow(
                icon: "cursorarrow.click.2",
                title: "点击悬浮 N",
                detail: "查看未读、监控应用和已标记窗口"
            )

            OnboardingActionRow(
                icon: "square.and.pencil",
                title: "按 ⌃⌥Q",
                detail: "随时记录一条 Todo 或 Note"
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("两个核心操作")
    }

    private var accessibilityStatus: some View {
        HStack(alignment: .top, spacing: NarcSpacing.md) {
            Image(systemName: hotkeyService.isAccessibilityGranted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill")
                .font(.narcSubtitle)
                .foregroundColor(hotkeyService.isAccessibilityGranted ? .narcSuccess : .narcWarn)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                Text(hotkeyService.isAccessibilityGranted
                    ? "窗口权限已开启"
                    : "窗口快捷键还未开启")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text("辅助功能只影响窗口排列、钉选和相关快捷键；Assistant、Todo/Note 和未读角标可直接使用。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: NarcSpacing.md)

            Button(hotkeyService.isAccessibilityGranted ? "查看设置" : "开启权限") {
                onOpenAccessibilitySettings()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(hotkeyService.isAccessibilityGranted
                ? "查看辅助功能设置"
                : "打开辅助功能设置")
        }
        .padding(NarcSpacing.lg)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                .strokeBorder(Color.narcBorder, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: NarcSpacing.md) {
            Button("稍后", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundColor(.narcTextMuted)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: onOpenAssistant) {
                Label("打开 Assistant", systemImage: "sparkles")
                    .font(.narcBody)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("完成使用指南并打开 Assistant")
        }
    }
}

private struct OnboardingActionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: NarcSpacing.lg) {
            Image(systemName: icon)
                .font(.narcTitle)
                .foregroundColor(.narcAccent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text(title)
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text(detail)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }

            Spacer()
        }
        .padding(NarcSpacing.lg)
        .background(Color.narcSurfaceMuted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
