import SwiftUI

/// Durable milestones for the menu-bar onboarding flow.
///
/// The stages are monotonic: reaching a later stage implies that the earlier
/// stages have also happened. Opening the entry alone is intentionally not
/// completion; the user has learned the core flow only after saving a capture.
enum OnboardingStage: Int, Equatable, Sendable {
    case notStarted = 0
    case entrySeen = 1
    case firstCaptureCompleted = 2
    case windowToolsIntroduced = 3

    var hasCompletedCoreFlow: Bool {
        rawValue >= Self.firstCaptureCompleted.rawValue
    }
}

struct OnboardingState: Equatable, Sendable {
    let version: Int?
    let stage: OnboardingStage
    let legacyCompletionRecorded: Bool

    var hasCompletedCurrentCoreFlow: Bool {
        guard let version,
              version >= OnboardingPresentationPolicy.currentVersion else {
            return false
        }
        return stage.hasCompletedCoreFlow
    }
}

enum OnboardingPresentationPolicy {
    /// Version 2 was represented only by `legacyCompletionKey`. Version 3 is
    /// the first versioned, staged menu-bar onboarding flow.
    static let currentVersion = 3
    static let versionKey = "narc.onboarding.version"
    static let stageKey = "narc.onboarding.stage"
    static let legacyCompletionKey = "narc.onboarding.completed.v2"

    static func resolvedState(
        storedVersion: Int?,
        storedStageRawValue: Int?,
        legacyCompleted: Bool
    ) -> OnboardingState {
        let stage = storedStageRawValue
            .flatMap(OnboardingStage.init(rawValue:)) ?? .notStarted

        return OnboardingState(
            version: storedVersion,
            stage: stage,
            legacyCompletionRecorded: legacyCompleted
        )
    }

    static func resolvedState(in defaults: UserDefaults = .standard) -> OnboardingState {
        let storedVersion = defaults.object(forKey: versionKey) == nil
            ? nil
            : defaults.integer(forKey: versionKey)
        let storedStage = defaults.object(forKey: stageKey) == nil
            ? nil
            : defaults.integer(forKey: stageKey)

        return resolvedState(
            storedVersion: storedVersion,
            storedStageRawValue: storedStage,
            legacyCompleted: defaults.bool(forKey: legacyCompletionKey)
        )
    }

    static func shouldPresent(state: OnboardingState, force: Bool = false) -> Bool {
        force || !state.hasCompletedCurrentCoreFlow
    }

    static func shouldPresent(
        defaults: UserDefaults = .standard,
        force: Bool = false
    ) -> Bool {
        shouldPresent(state: resolvedState(in: defaults), force: force)
    }

    static func markEntrySeen(in defaults: UserDefaults = .standard) {
        advance(to: .entrySeen, in: defaults)
    }

    /// Call only after the first Inbox item has been saved successfully.
    static func markFirstCaptureCompleted(in defaults: UserDefaults = .standard) {
        advance(to: .firstCaptureCompleted, in: defaults)
    }

    static func markWindowToolsIntroduced(in defaults: UserDefaults = .standard) {
        let state = resolvedState(in: defaults)
        guard state.hasCompletedCurrentCoreFlow else {
            // Window tools are an optional, independent path. Using them first
            // must not pretend that the user has already completed an Inbox
            // capture, which is the core-flow completion gate.
            markEntrySeen(in: defaults)
            return
        }
        advance(to: .windowToolsIntroduced, in: defaults)
    }

    private static func advance(to requestedStage: OnboardingStage, in defaults: UserDefaults) {
        let state = resolvedState(in: defaults)

        // Do not let an older binary overwrite state written by a newer one.
        if let storedVersion = state.version, storedVersion > currentVersion {
            return
        }

        let existingStage = state.version == currentVersion ? state.stage : .notStarted
        let nextStage = existingStage.rawValue >= requestedStage.rawValue
            ? existingStage
            : requestedStage

        defaults.set(currentVersion, forKey: versionKey)
        defaults.set(nextStage.rawValue, forKey: stageKey)
    }
}

struct OnboardingView: View {
    @ObservedObject var hotkeyService: HotkeyService

    let onOpenAssistant: () -> Void
    let onManageAccessibilityPermission: () -> Void
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
                Text("先记住两个动作，其余能力稍后再看。")
                    .font(.narcBody)
                    .foregroundColor(.narcTextMuted)
            }
        }
    }

    private var coreActions: some View {
        VStack(spacing: NarcSpacing.md) {
            OnboardingActionRow(
                icon: "scope",
                title: hotkeyService.activeShortcut(for: .summonWidget).map { "菜单栏 N 或 \($0.displayLabel)" } ?? "点击菜单栏 N",
                detail: "把桌面悬浮 N 召回当前屏幕，并展开面板"
            )

            OnboardingActionRow(
                icon: "square.and.pencil",
                title: hotkeyService.activeShortcut(for: .quickCapture).map { "按 \($0.displayLabel)" } ?? "打开面板中的随手记",
                detail: "直接写下内容并按 Return，先存入随手箱"
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
                    ? "可选工具权限已开启"
                    : "可选工具权限尚未开启")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text(hotkeyService.isAccessibilityGranted
                    ? "当前版本已确认权限，无需重启。辅助功能只用于窗口排列、窗口标记与召回，以及你主动触发的划词 Todo。"
                    : "开启后会自动确认，通常无需重启。若开关已开启仍提示，请删除旧 NARC 条目并重新添加当前 App。手动记录、Todo 管理、Notes 和未读角标不需要这项权限。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: NarcSpacing.md)

            Button(hotkeyService.isAccessibilityGranted ? "查看设置" : "开启权限") {
                onManageAccessibilityPermission()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(hotkeyService.isAccessibilityGranted
                ? "查看辅助功能设置"
                : "开启辅助功能权限")
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
                Label("打开随手箱", systemImage: "tray.and.arrow.down.fill")
                    .font(.narcBody)
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("关闭使用指南并打开随手箱")
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
