import Foundation

enum AccessibilityCapability: Equatable, Sendable {
    case windowTools
    case selectedTextTodo
    case general
}

/// User-facing instructions for the window-tool permission handoff.
///
/// The original window action is intentionally not replayed after authorization:
/// System Settings is normally frontmost by then, so replaying could move or pin
/// the wrong window. The user returns to the intended window and repeats once.
struct AccessibilityPermissionGuidance: Equatable, Sendable {
    let shortcut: String?
    let appPath: String
    let capability: AccessibilityCapability

    init(
        shortcut: String,
        capability: AccessibilityCapability = .windowTools,
        appPath: String = Bundle.main.bundleURL.path
    ) {
        self.shortcut = shortcut
        self.appPath = appPath
        self.capability = capability
    }

    private init(
        shortcut: String?,
        capability: AccessibilityCapability,
        appPath: String
    ) {
        self.shortcut = shortcut
        self.appPath = appPath
        self.capability = capability
    }

    static var general: AccessibilityPermissionGuidance {
        AccessibilityPermissionGuidance(
            shortcut: nil,
            capability: .general,
            appPath: Bundle.main.bundleURL.path
        )
    }

    var alertTitle: String {
        switch capability {
        case .windowTools:
            return "窗口工具需要辅助功能权限"
        case .selectedTextTodo:
            return "划词创建 Todo 需要辅助功能权限"
        case .general:
            return "可选工具需要辅助功能权限"
        }
    }

    var cancelButtonTitle: String {
        capability == .windowTools ? "暂不使用窗口工具" : "暂不使用此功能"
    }

    var explanation: String {
        capabilityExplanation
            + "下一步请在 macOS 提示中选择“打开系统设置”，再开启 NARC。"
            + continuationInstruction
    }

    var ready: String {
        "NARC 已确认当前版本的辅助功能权限，无需重启。"
            + readyInstruction
    }

    var recovery: String {
        "macOS 仍未确认当前版本。若设置里 NARC 已开启，请先删除旧 NARC 条目，"
            + "再点“+”添加当前正在运行的 NARC.app（路径：\(appPath)）并开启。"
            + "通常无需重启；仍未生效时再退出并重开 NARC。"
    }

    private var continuationInstruction: String {
        guard let shortcut else {
            return "开启后 NARC 会自动确认，通常无需重启。"
        }
        return "开启后 NARC 会自动确认，通常无需重启；回到要操作的窗口，再按一次 \(shortcut)。"
    }

    private var readyInstruction: String {
        guard let shortcut else {
            return "现在可以直接使用窗口排列、窗口标记与召回，或划词创建 Todo。"
        }
        switch capability {
        case .selectedTextTodo:
            return "请关闭系统设置，回到原 App，重新确认选区后再按一次 \(shortcut)。"
        case .windowTools, .general:
            return "请关闭系统设置，回到要操作的窗口，再按一次 \(shortcut)。"
        }
    }

    private var capabilityExplanation: String {
        switch capability {
        case .windowTools:
            return "NARC 只在排列、标记或召回窗口时使用这项权限。"
        case .selectedTextTodo:
            return "NARC 只在你按下快捷键时读取当前标准文本选区并保存到本地 Todo；不会持续监听，也不会读取剪贴板。"
        case .general:
            return "NARC 只在排列、标记或召回窗口，以及你主动用快捷键读取当前文本选区时使用这项权限。"
        }
    }
}

enum AccessibilityBlockedActionResponse: Equatable, Sendable {
    case explain
    case openSettings
}

/// Minimal state machine for the permission handoff. Keeping it independent
/// from AppKit makes rejection, retry, grant, and immediate-action races
/// deterministic in tests.
struct AccessibilityPermissionFlow: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case explaining(AccessibilityPermissionGuidance)
        case waiting(AccessibilityPermissionGuidance)
    }

    private var phase: Phase = .idle

    var currentGuidance: AccessibilityPermissionGuidance? {
        switch phase {
        case .idle:
            return nil
        case .explaining(let guidance), .waiting(let guidance):
            return guidance
        }
    }

    var isExplaining: Bool {
        if case .explaining = phase {
            return true
        }
        return false
    }

    mutating func responseToBlockedAction(
        _ guidance: AccessibilityPermissionGuidance
    ) -> AccessibilityBlockedActionResponse {
        switch phase {
        case .idle:
            phase = .explaining(guidance)
            return .explain
        case .explaining:
            return .explain
        case .waiting:
            // A native request has already been made. A later explicit retry
            // goes straight to Settings instead of stacking another prompt.
            phase = .waiting(guidance)
            return .openSettings
        }
    }

    mutating func beginAuthorization(with guidance: AccessibilityPermissionGuidance) {
        phase = .waiting(guidance)
    }

    mutating func cancelExplanation() {
        guard case .explaining = phase else { return }
        phase = .idle
    }

    mutating func takeGuidanceAfterGrant() -> AccessibilityPermissionGuidance? {
        defer { phase = .idle }
        return currentGuidance
    }

    mutating func consumeForSuccessfulWindowAction() {
        phase = .idle
    }
}
