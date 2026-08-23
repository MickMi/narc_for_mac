import SwiftUI

struct QuickCaptureView: View {
    @ObservedObject var store: AssistantStore

    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var selectedKind: CaptureKind = .todo
    @State private var content = ""
    @State private var validationMessage: String?
    @State private var isSaving = false
    @FocusState private var isInputFocused: Bool

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedContent.isEmpty && !isSaving
    }

    private var visibleError: String? {
        validationMessage ?? store.lastError?.errorDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.lg) {
            header
            kindPicker
            inputArea

            if let visibleError {
                Label(visibleError, systemImage: "exclamationmark.circle.fill")
                    .font(.narcCaption)
                    .foregroundColor(.narcDanger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("保存错误：\(visibleError)")
            }

            footer
        }
        .padding(NarcSpacing.xl)
        .frame(width: 440)
        .background(Color.narcBackground)
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: selectedKind) { _, _ in
            validationMessage = nil
            isInputFocused = true
        }
        .onChange(of: content) { _, _ in
            validationMessage = nil
        }
    }

    private var header: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.narcTitle)
                .foregroundColor(.narcAccent)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("Quick Capture")
                    .font(.narcTitle)
                    .foregroundColor(.narcText)
                Text("快速记下一条 Todo 或 Note")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }

            Spacer()
        }
    }

    private var kindPicker: some View {
        Picker("记录类型", selection: $selectedKind) {
            Label("Todo", systemImage: "checkmark.circle")
                .tag(CaptureKind.todo)
            Label("Note", systemImage: "note.text")
                .tag(CaptureKind.note)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("记录类型")
    }

    @ViewBuilder
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            Text(selectedKind == .todo ? "待办内容" : "便签内容")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)

            if selectedKind == .todo {
                TextField("例如：整理本周计划", text: $content)
                    .textFieldStyle(.plain)
                    .font(.narcBody)
                    .foregroundColor(.narcText)
                    .focused($isInputFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("Todo 内容")
            } else {
                ZStack(alignment: .topLeading) {
                    if content.isEmpty {
                        Text("写下想法、决定或需要保留的信息…")
                            .font(.narcBody)
                            .foregroundColor(.narcTextFaint)
                            .padding(.horizontal, NarcSpacing.xs)
                            .padding(.vertical, NarcSpacing.xs + NarcSpacing.xxs)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden)
                        .font(.narcBody)
                        .foregroundColor(.narcText)
                        .focused($isInputFocused)
                        .frame(minHeight: 92, maxHeight: 150)
                        .accessibilityLabel("Note 内容")
                }
            }
        }
        .padding(NarcSpacing.md)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                .strokeBorder(
                    visibleError == nil ? Color.narcBorder : Color.narcDanger.opacity(0.65),
                    lineWidth: 1
                )
        )
    }

    private var footer: some View {
        HStack(spacing: NarcSpacing.md) {
            Text(selectedKind == .todo ? "保存为 Todo" : "保存为 Note")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)

            Spacer()

            Button("取消", action: cancel)
                .buttonStyle(.plain)
                .foregroundColor(.narcTextMuted)
                .keyboardShortcut(.cancelAction)

            Button(action: submit) {
                HStack(spacing: NarcSpacing.xs) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSaving ? "保存中" : "保存")
                }
                .font(.narcBody)
                .padding(.horizontal, NarcSpacing.md)
                .padding(.vertical, NarcSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel(selectedKind == .todo ? "保存 Todo" : "保存 Note")
        }
    }

    private func submit() {
        guard !isSaving else { return }
        guard !trimmedContent.isEmpty else {
            validationMessage = AssistantStoreFailure.blankContent.errorDescription
            return
        }

        validationMessage = nil
        isSaving = true
        let saved = store.capture(content, as: selectedKind)
        isSaving = false

        guard saved else {
            isInputFocused = true
            return
        }

        content = ""
        onSaved()
    }

    private func cancel() {
        content = ""
        validationMessage = nil
        onCancel()
    }
}
