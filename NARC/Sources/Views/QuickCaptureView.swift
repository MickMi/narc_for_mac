import SwiftUI

/// Shared Todo draft and feedback for every capture entry point.
///
/// AppDelegate owns one instance for the lifetime of the process. Reopening the
/// floating panel, Quick Capture, or Assistant therefore never discards text
/// that has not been saved yet.
@MainActor
final class InboxCaptureState: ObservableObject {
    @Published private(set) var draft = ""
    @Published private(set) var validationMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var isSaving = false
    @Published private(set) var isOnboardingHintHidden = false

    private let store: AssistantStore
    private let onCaptureCompleted: () -> Void

    init(
        store: AssistantStore,
        onCaptureCompleted: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onCaptureCompleted = onCaptureCompleted
    }

    var canSubmit: Bool {
        !trimmedDraft.isEmpty && !isSaving
    }

    func updateDraft(_ value: String) {
        draft = value
        validationMessage = nil
        successMessage = nil
        store.clearError()
    }

    func hideOnboardingHintForThisSession() {
        isOnboardingHintHidden = true
    }

    @discardableResult
    func submit() -> Bool {
        submit(
            save: { [store] content in
                store.createTodo(title: content)
            },
            success: "已创建 Todo"
        )
    }

    @discardableResult
    func submitTodo() -> Bool {
        submit()
    }

    private func submit(
        save: (String) -> Bool,
        success: String
    ) -> Bool {
        guard !isSaving else { return false }
        guard !trimmedDraft.isEmpty else {
            validationMessage = AssistantStoreFailure.blankContent.errorDescription
            return false
        }

        validationMessage = nil
        successMessage = nil
        isSaving = true
        let saved = save(trimmedDraft)
        isSaving = false

        guard saved else {
            validationMessage = store.lastError?.errorDescription
            return false
        }

        draft = ""
        onCaptureCompleted()
        successMessage = success
        return true
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The shared Todo surface used by the floating panel, global capture window,
/// and full Assistant.
struct QuickCaptureView: View {
    @ObservedObject var store: AssistantStore
    @ObservedObject var captureState: InboxCaptureState

    var compact = false
    var onDismiss: (() -> Void)?
    var onOpenAssistant: (() -> Void)?
    var onboardingDefaults: UserDefaults = .standard

    @FocusState private var isInputFocused: Bool

    private var draftBinding: Binding<String> {
        Binding(
            get: { captureState.draft },
            set: { captureState.updateDraft($0) }
        )
    }

    private var visibleError: String? {
        captureState.validationMessage ?? store.lastError?.errorDescription
    }

    private var shouldShowOnboardingHint: Bool {
        !captureState.isOnboardingHintHidden
            && OnboardingPresentationPolicy.shouldPresent(defaults: onboardingDefaults)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? NarcSpacing.md : NarcSpacing.lg) {
            if compact {
                compactContent
            } else {
                regularContent
            }
        }
        .padding(NarcSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(compact ? Color.clear : Color.narcBackground)
        .onAppear {
            OnboardingPresentationPolicy.markEntrySeen(in: onboardingDefaults)
            // The hosting view can appear before its NSPanel becomes key.
            // Defer one main-loop turn so a freshly opened capture surface is
            // immediately ready for typing without requiring an extra click.
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        inputArea
        feedback
        if shouldShowOnboardingHint {
            compactFirstUseHint
        }
        TodoListView(store: store, compact: true)
        footer
    }

    @ViewBuilder
    private var regularContent: some View {
        header
        if shouldShowOnboardingHint {
            firstUseHint
        }
        inputArea
        feedback
        TodoListView(store: store)
        footer
    }

    private var compactFirstUseHint: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.narcAccent)
                .accessibilityHidden(true)

            Text("按 ↵ 记下一件 Todo。")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)

            Spacer(minLength: NarcSpacing.xs)

            Button("知道了") {
                captureState.hideOnboardingHintForThisSession()
            }
            .buttonStyle(.plain)
            .font(.narcCaption)
            .foregroundColor(.narcAccent)
        }
        .padding(.horizontal, NarcSpacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var firstUseHint: some View {
        HStack(alignment: .top, spacing: NarcSpacing.sm) {
            Image(systemName: "1.circle.fill")
                .foregroundColor(.narcAccent)
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("记下第一件 Todo")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text("输入要做的事，按 Return 保存。")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NarcSpacing.xs)
            Button("稍后") {
                captureState.hideOnboardingHintForThisSession()
            }
            .buttonStyle(.plain)
            .font(.narcCaption)
            .foregroundColor(.narcTextMuted)
        }
        .padding(NarcSpacing.sm)
        .background(Color.narcAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous)
                .strokeBorder(Color.narcAccent.opacity(0.18), lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(compact ? .narcSubtitle : .narcTitle)
                .foregroundColor(.narcAccent)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("Todo")
                    .font(compact ? .narcSubtitle : .narcTitle)
                    .foregroundColor(.narcText)
                Text("记下一件事，做完勾掉")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var inputArea: some View {
        HStack(spacing: NarcSpacing.sm) {
            TextField("记下一件事…", text: draftBinding)
                .textFieldStyle(.plain)
                .font(.narcBody)
                .foregroundColor(.narcText)
                .focused($isInputFocused)
                .onSubmit(submit)
                .accessibilityLabel("Todo 内容")

            Button(action: submit) {
                if captureState.isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!captureState.canSubmit)
            .help("创建 Todo（Return）")
            .accessibilityLabel("创建 Todo")
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.sm)
        .background(compact ? Color.narcFocusInset : Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                .strokeBorder(
                    visibleError == nil ? (compact ? Color.clear : Color.narcBorder) : Color.narcDanger.opacity(0.65),
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let visibleError {
            Label(visibleError, systemImage: "exclamationmark.circle.fill")
                .font(.narcCaption)
                .foregroundColor(.narcDanger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("保存错误：\(visibleError)")
        } else if let successMessage = captureState.successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
                .font(.narcCaption)
                .foregroundColor(.narcSuccess)
        }
    }

    private var footer: some View {
        HStack(spacing: NarcSpacing.md) {
            if !compact || !shouldShowOnboardingHint {
                Text("↵ 添加待办")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }

            Spacer()

            if let onOpenAssistant {
                Button("全部待办", action: onOpenAssistant)
                    .buttonStyle(.plain)
                    .font(.narcCaption)
                    .foregroundColor(.narcAccent)
            }

            if !compact, let onDismiss {
                Button("关闭", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func submit() {
        _ = captureState.submit()
        isInputFocused = true
    }


}
