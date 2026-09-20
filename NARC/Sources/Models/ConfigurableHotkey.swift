import Carbon
import Foundation

/// Every NARC action backed by a Carbon global shortcut.
///
/// Raw values are persistence identifiers. In particular, the two Pin cases
/// must not be renamed because released builds already store user choices
/// under those names.
enum ConfigurableHotkeyAction: String, CaseIterable, Identifiable {
    case layoutLeftHalf
    case layoutRightHalf
    case layoutTopHalf
    case layoutBottomHalf
    case layoutFullScreen
    case layoutCenter
    case layoutTopLeft
    case layoutTopRight
    case layoutBottomLeft
    case layoutBottomRight
    case pinnedWindowSwitcher
    case toggleCurrentWindowPin
    case summonWidget
    case quickCapture
    case selectedTextTodo

    static let layoutActions: [ConfigurableHotkeyAction] = WindowLayout.allCases.map(forLayout)

    static let globalActions: [ConfigurableHotkeyAction] = [
        .pinnedWindowSwitcher,
        .toggleCurrentWindowPin,
        .summonWidget,
        .quickCapture,
        .selectedTextTodo,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layoutLeftHalf: return "窗口布局：左半屏"
        case .layoutRightHalf: return "窗口布局：右半屏"
        case .layoutTopHalf: return "窗口布局：上半屏"
        case .layoutBottomHalf: return "窗口布局：下半屏"
        case .layoutFullScreen: return "窗口布局：全屏"
        case .layoutCenter: return "窗口布局：居中"
        case .layoutTopLeft: return "窗口布局：左上"
        case .layoutTopRight: return "窗口布局：右上"
        case .layoutBottomLeft: return "窗口布局：左下"
        case .layoutBottomRight: return "窗口布局：右下"
        case .pinnedWindowSwitcher:
            return "召回已标记窗口"
        case .toggleCurrentWindowPin:
            return "标记 / 取消当前窗口"
        case .summonWidget:
            return "召回悬浮球"
        case .quickCapture:
            return "快速记录"
        case .selectedTextTodo:
            return "划词创建 Todo"
        }
    }

    var defaultShortcut: ConfigurableShortcut {
        let controlOption = UInt32(controlKey | optionKey)
        switch self {
        case .layoutLeftHalf:
            return ConfigurableShortcut(keyCode: 123, modifiers: controlOption)
        case .layoutRightHalf:
            return ConfigurableShortcut(keyCode: 124, modifiers: controlOption)
        case .layoutTopHalf:
            return ConfigurableShortcut(keyCode: 126, modifiers: controlOption)
        case .layoutBottomHalf:
            return ConfigurableShortcut(keyCode: 125, modifiers: controlOption)
        case .layoutFullScreen:
            return ConfigurableShortcut(keyCode: 36, modifiers: controlOption)
        case .layoutCenter:
            return ConfigurableShortcut(keyCode: 8, modifiers: controlOption)
        case .layoutTopLeft:
            return ConfigurableShortcut(keyCode: 32, modifiers: controlOption)
        case .layoutTopRight:
            return ConfigurableShortcut(keyCode: 34, modifiers: controlOption)
        case .layoutBottomLeft:
            return ConfigurableShortcut(keyCode: 38, modifiers: controlOption)
        case .layoutBottomRight:
            return ConfigurableShortcut(keyCode: 40, modifiers: controlOption)
        case .pinnedWindowSwitcher:
            return ConfigurableShortcut(keyCode: 35, modifiers: controlOption)
        case .toggleCurrentWindowPin:
            return ConfigurableShortcut(
                keyCode: 35,
                modifiers: UInt32(controlKey | optionKey | shiftKey)
            )
        case .summonWidget:
            return ConfigurableShortcut(keyCode: 45, modifiers: controlOption)
        case .quickCapture:
            return ConfigurableShortcut(keyCode: 12, modifiers: controlOption)
        case .selectedTextTodo:
            return ConfigurableShortcut(keyCode: 17, modifiers: controlOption)
        }
    }

    var defaultsKey: String {
        "narc.configurableHotkey.\(rawValue)"
    }

    var enabledDefaultsKey: String {
        "narc.configurableHotkeyEnabled.\(rawValue)"
    }

    var layout: WindowLayout? {
        switch self {
        case .layoutLeftHalf: return .leftHalf
        case .layoutRightHalf: return .rightHalf
        case .layoutTopHalf: return .topHalf
        case .layoutBottomHalf: return .bottomHalf
        case .layoutFullScreen: return .fullScreen
        case .layoutCenter: return .center
        case .layoutTopLeft: return .topLeft
        case .layoutTopRight: return .topRight
        case .layoutBottomLeft: return .bottomLeft
        case .layoutBottomRight: return .bottomRight
        case .pinnedWindowSwitcher, .toggleCurrentWindowPin, .summonWidget,
             .quickCapture, .selectedTextTodo:
            return nil
        }
    }

    static func forLayout(_ layout: WindowLayout) -> ConfigurableHotkeyAction {
        switch layout {
        case .leftHalf: return .layoutLeftHalf
        case .rightHalf: return .layoutRightHalf
        case .topHalf: return .layoutTopHalf
        case .bottomHalf: return .layoutBottomHalf
        case .fullScreen: return .layoutFullScreen
        case .center: return .layoutCenter
        case .topLeft: return .layoutTopLeft
        case .topRight: return .layoutTopRight
        case .bottomLeft: return .layoutBottomLeft
        case .bottomRight: return .layoutBottomRight
        }
    }

    var requiresAccessibility: Bool {
        switch self {
        case .summonWidget, .quickCapture:
            return false
        case .layoutLeftHalf, .layoutRightHalf, .layoutTopHalf, .layoutBottomHalf,
             .layoutFullScreen, .layoutCenter, .layoutTopLeft, .layoutTopRight,
             .layoutBottomLeft, .layoutBottomRight, .pinnedWindowSwitcher,
             .toggleCurrentWindowPin, .selectedTextTodo:
            return true
        }
    }

    var supportsEnabledToggle: Bool {
        layout != nil
    }
}

struct ShortcutKeyOption: Identifiable, Equatable {
    let keyCode: UInt32
    let label: String

    var id: UInt32 { keyCode }
}

/// A keyboard-layout-independent Carbon shortcut selected through explicit
/// modifier toggles and a known-key picker rather than a global key recorder.
struct ConfigurableShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var displayLabel: String {
        let modifierLabels: [(value: UInt32, label: String)] = [
            (UInt32(controlKey), "⌃"),
            (UInt32(optionKey), "⌥"),
            (UInt32(shiftKey), "⇧"),
            (UInt32(cmdKey), "⌘"),
        ]
        let prefix = modifierLabels
            .filter { modifiers & $0.value != 0 }
            .map(\.label)
            .joined()
        let keyLabel = Self.keyOptions.first(where: { $0.keyCode == keyCode })?.label
            ?? "Key \(keyCode)"
        return prefix + keyLabel
    }

    var isValid: Bool {
        let allowedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let requiredPrimaryModifiers = UInt32(controlKey | optionKey | cmdKey)
        guard modifiers & ~allowedModifiers == 0,
              modifiers.nonzeroBitCount >= 2,
              modifiers & requiredPrimaryModifiers != 0 else {
            return false
        }
        return Self.keyOptions.contains { $0.keyCode == keyCode }
    }

    func matches(keyCode: UInt32, modifiers: UInt32) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// Deliberately fixed macOS virtual key codes. They are stable regardless
    /// of the user's keyboard layout and keep Preferences free of key capture.
    static let keyOptions: [ShortcutKeyOption] = [
        ShortcutKeyOption(keyCode: 0, label: "A"),
        ShortcutKeyOption(keyCode: 11, label: "B"),
        ShortcutKeyOption(keyCode: 8, label: "C"),
        ShortcutKeyOption(keyCode: 2, label: "D"),
        ShortcutKeyOption(keyCode: 14, label: "E"),
        ShortcutKeyOption(keyCode: 3, label: "F"),
        ShortcutKeyOption(keyCode: 5, label: "G"),
        ShortcutKeyOption(keyCode: 4, label: "H"),
        ShortcutKeyOption(keyCode: 34, label: "I"),
        ShortcutKeyOption(keyCode: 38, label: "J"),
        ShortcutKeyOption(keyCode: 40, label: "K"),
        ShortcutKeyOption(keyCode: 37, label: "L"),
        ShortcutKeyOption(keyCode: 46, label: "M"),
        ShortcutKeyOption(keyCode: 45, label: "N"),
        ShortcutKeyOption(keyCode: 31, label: "O"),
        ShortcutKeyOption(keyCode: 35, label: "P"),
        ShortcutKeyOption(keyCode: 12, label: "Q"),
        ShortcutKeyOption(keyCode: 15, label: "R"),
        ShortcutKeyOption(keyCode: 1, label: "S"),
        ShortcutKeyOption(keyCode: 17, label: "T"),
        ShortcutKeyOption(keyCode: 32, label: "U"),
        ShortcutKeyOption(keyCode: 9, label: "V"),
        ShortcutKeyOption(keyCode: 13, label: "W"),
        ShortcutKeyOption(keyCode: 7, label: "X"),
        ShortcutKeyOption(keyCode: 16, label: "Y"),
        ShortcutKeyOption(keyCode: 6, label: "Z"),
        ShortcutKeyOption(keyCode: 29, label: "0"),
        ShortcutKeyOption(keyCode: 18, label: "1"),
        ShortcutKeyOption(keyCode: 19, label: "2"),
        ShortcutKeyOption(keyCode: 20, label: "3"),
        ShortcutKeyOption(keyCode: 21, label: "4"),
        ShortcutKeyOption(keyCode: 23, label: "5"),
        ShortcutKeyOption(keyCode: 22, label: "6"),
        ShortcutKeyOption(keyCode: 26, label: "7"),
        ShortcutKeyOption(keyCode: 28, label: "8"),
        ShortcutKeyOption(keyCode: 25, label: "9"),
        ShortcutKeyOption(keyCode: 122, label: "F1"),
        ShortcutKeyOption(keyCode: 120, label: "F2"),
        ShortcutKeyOption(keyCode: 99, label: "F3"),
        ShortcutKeyOption(keyCode: 118, label: "F4"),
        ShortcutKeyOption(keyCode: 96, label: "F5"),
        ShortcutKeyOption(keyCode: 97, label: "F6"),
        ShortcutKeyOption(keyCode: 98, label: "F7"),
        ShortcutKeyOption(keyCode: 100, label: "F8"),
        ShortcutKeyOption(keyCode: 101, label: "F9"),
        ShortcutKeyOption(keyCode: 109, label: "F10"),
        ShortcutKeyOption(keyCode: 103, label: "F11"),
        ShortcutKeyOption(keyCode: 111, label: "F12"),
        ShortcutKeyOption(keyCode: 123, label: "←"),
        ShortcutKeyOption(keyCode: 124, label: "→"),
        ShortcutKeyOption(keyCode: 126, label: "↑"),
        ShortcutKeyOption(keyCode: 125, label: "↓"),
        ShortcutKeyOption(keyCode: 115, label: "Home"),
        ShortcutKeyOption(keyCode: 119, label: "End"),
        ShortcutKeyOption(keyCode: 116, label: "Page Up"),
        ShortcutKeyOption(keyCode: 121, label: "Page Down"),
        ShortcutKeyOption(keyCode: 36, label: "Return"),
        ShortcutKeyOption(keyCode: 49, label: "Space"),
    ]
}

enum ConfigurableHotkeyState: Equatable {
    case notRegistered
    case disabled(ConfigurableShortcut)
    case active(ConfigurableShortcut)
    case rejected(
        active: ConfigurableShortcut,
        requested: ConfigurableShortcut,
        reason: HotkeyRegistrationFailure
    )
    case unavailable(
        requested: ConfigurableShortcut,
        reason: HotkeyRegistrationFailure
    )
}

enum ConfigurableShortcutUpdateResult: Equatable {
    case unchanged
    case applied(ConfigurableShortcut)
    case rejected(HotkeyRegistrationFailure)
}
