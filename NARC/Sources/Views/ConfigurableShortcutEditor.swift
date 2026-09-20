import Carbon
import SwiftUI

/// Shared shortcut form used by Preferences and the independent editor opened
/// from a Windows layout card. It edits a local draft so merely choosing a key
/// or modifier never changes the live Carbon registration.
struct ConfigurableShortcutEditor: View {
    @ObservedObject var hotkeyService: HotkeyService
    let action: ConfigurableHotkeyAction
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32
    @State private var failureMessage: String?

    init(
        hotkeyService: HotkeyService,
        action: ConfigurableHotkeyAction,
        onClose: (() -> Void)? = nil
    ) {
        self.hotkeyService = hotkeyService
        self.action = action
        self.onClose = onClose
        let current = hotkeyService.shortcut(for: action)
        _keyCode = State(initialValue: current.keyCode)
        _modifiers = State(initialValue: current.modifiers)
    }

    private var candidate: ConfigurableShortcut {
        ConfigurableShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private var isUnavailableInCurrentRuntime: Bool {
        DevRuntimeOptions.noAX && action.requiresAccessibility
    }

    private func modifierBinding(_ flag: UInt32) -> Binding<Bool> {
        Binding(
            get: { modifiers & flag != 0 },
            set: { enabled in
                if enabled { modifiers |= flag } else { modifiers &= ~flag }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NarcSpacing.lg) {
                Text(action.title)
                    .font(.narcSubtitle)

                Text("当前设置：\(hotkeyService.shortcut(for: action).displayLabel)")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)

                VStack(alignment: .leading, spacing: NarcSpacing.sm) {
                    Text("修饰键")
                        .font(.narcBody)
                    HStack(spacing: NarcSpacing.md) {
                        Toggle("⌃ Control", isOn: modifierBinding(UInt32(controlKey)))
                        Toggle("⌥ Option", isOn: modifierBinding(UInt32(optionKey)))
                        Toggle("⇧ Shift", isOn: modifierBinding(UInt32(shiftKey)))
                        Toggle("⌘ Command", isOn: modifierBinding(UInt32(cmdKey)))
                    }
                    .toggleStyle(.checkbox)
                }

                HStack {
                    Text("主键")
                        .font(.narcBody)
                    Picker("主键", selection: $keyCode) {
                        ForEach(ConfigurableShortcut.keyOptions) { key in
                            Text(key.label).tag(key.keyCode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)

                    Spacer()

                    Text(candidate.displayLabel)
                        .font(.narcMono)
                        .foregroundColor(.narcTextMuted)
                        .padding(.horizontal, NarcSpacing.sm)
                        .padding(.vertical, NarcSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: NarcRadius.xs)
                                .fill(Color.narcSurfaceMuted)
                        )
                }

                Text(editorGuidance)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if isUnavailableInCurrentRuntime {
                    Label("开发 no-AX 模式不会注册此动作的快捷键。", systemImage: "hammer.fill")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)
                }

                if let failureMessage {
                    Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.narcCaption)
                        .foregroundColor(.narcWarn)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shortcut-edit-error")
                }

                HStack {
                    Button("使用默认组合") {
                        keyCode = action.defaultShortcut.keyCode
                        modifiers = action.defaultShortcut.modifiers
                    }
                    .disabled(isUnavailableInCurrentRuntime)

                    Spacer()

                    Button("取消") { close() }
                        .keyboardShortcut(.cancelAction)
                    Button("应用") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!candidate.isValid || isUnavailableInCurrentRuntime)
                }
            }
            .padding(NarcSpacing.xl)
        }
        .frame(width: 500)
        .frame(minHeight: 360, idealHeight: 400, maxHeight: 460)
        .onChange(of: candidate) { _, _ in
            failureMessage = nil
        }
    }

    private var editorGuidance: String {
        let effect = hotkeyService.isEnabled(for: action)
            ? "点击应用后立即生效"
            : "当前动作已停用；组合会保存，并在重新启用时注册"
        return "至少选择两个修饰键。字母按标准键位显示；\(effect)，不会触发对应动作。"
    }

    private func apply() {
        let result = hotkeyService.updateShortcut(candidate, for: action)
        switch result {
        case .unchanged, .applied:
            close()
        case .rejected(let reason):
            failureMessage = "\(reason.userMessage)。原设置未改变，请换一个组合。"
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
