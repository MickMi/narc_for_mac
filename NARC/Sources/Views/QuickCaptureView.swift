import SwiftUI

/// Shared draft and feedback for every Inbox entry point.
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
        guard !isSaving else { return false }
        guard !trimmedDraft.isEmpty else {
            validationMessage = AssistantStoreFailure.blankContent.errorDescription
            return false
        }

        validationMessage = nil
        successMessage = nil
        isSaving = true
        let saved = store.captureInbox(trimmedDraft)
        isSaving = false

        guard saved else {
            validationMessage = store.lastError?.errorDescription
            return false
        }

        draft = ""
        onCaptureCompleted()
        successMessage = "已存入随手箱"
        return true
    }

    @discardableResult
    func convert(_ item: InboxItem, to kind: CaptureKind) -> Bool {
        validationMessage = nil
        successMessage = nil
        guard store.convertInbox(id: item.id, to: kind) else {
            validationMessage = store.lastError?.errorDescription ?? "转换失败，请稍后重试。"
            return false
        }

        successMessage = kind == .todo ? "已转为 Todo" : "已转为 Note"
        return true
    }

    @discardableResult
    func delete(_ item: InboxItem) -> Bool {
        validationMessage = nil
        successMessage = nil
        guard store.deleteInbox(id: item.id) else {
            validationMessage = store.lastError?.errorDescription ?? "删除失败，请稍后重试。"
            return false
        }
        return true
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The shared Inbox surface used by the floating panel, global capture window,
/// and full Assistant. Capture is intentionally classification-free: users
/// save first, then explicitly convert an item to Todo or Note.
struct QuickCaptureView: View {
    @ObservedObject var store: AssistantStore
    @ObservedObject var captureState: InboxCaptureState

    var compact = false
    var onDismiss: (() -> Void)?
    var onOpenAssistant: (() -> Void)?

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

    private var recentItems: [InboxItem] {
        Array(store.recentInboxItems.prefix(3))
    }

    private var shouldShowOnboardingHint: Bool {
        !captureState.isOnboardingHintHidden
            && OnboardingPresentationPolicy.shouldPresent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? NarcSpacing.md : NarcSpacing.lg) {
            header
            if shouldShowOnboardingHint {
                firstUseHint
            }
            inputArea
            feedback
            recentInbox
            footer
        }
        .padding(compact ? NarcSpacing.md : NarcSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(compact ? Color.clear : Color.narcBackground)
        .onAppear {
            OnboardingPresentationPolicy.markEntrySeen()
            // The hosting view can appear before its NSPanel becomes key.
            // Defer one main-loop turn so a freshly opened capture surface is
            // immediately ready for typing without requiring an extra click.
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    private var firstUseHint: some View {
        HStack(alignment: .top, spacing: NarcSpacing.sm) {
            Image(systemName: "1.circle.fill")
                .foregroundColor(.narcAccent)
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("先完成一次随手记")
                    .font(.narcSubtitle)
                    .foregroundColor(.narcText)
                Text("输入现在想到的事，按 Return 保存。以后再转成 Todo 或 Note。")
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
            Image(systemName: "tray.and.arrow.down.fill")
                .font(compact ? .narcSubtitle : .narcTitle)
                .foregroundColor(.narcAccent)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("随手箱")
                    .font(compact ? .narcSubtitle : .narcTitle)
                    .foregroundColor(.narcText)
                Text("先记下来，之后再决定放到哪里")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var inputArea: some View {
        HStack(spacing: NarcSpacing.sm) {
            TextField("现在想到什么？", text: draftBinding)
                .textFieldStyle(.plain)
                .font(.narcBody)
                .foregroundColor(.narcText)
                .focused($isInputFocused)
                .onSubmit(submit)
                .accessibilityLabel("随手记内容")

            Button(action: submit) {
                if captureState.isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.turn.down.left")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!captureState.canSubmit)
            .help("按 Return 存入随手箱")
            .accessibilityLabel("存入随手箱")
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                .strokeBorder(
                    visibleError == nil ? Color.narcBorder : Color.narcDanger.opacity(0.65),
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

    private var recentInbox: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            HStack {
                Text("最近记录")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
                Spacer()
                Text("\(store.inboxItems.count) 条待整理")
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextFaint)
            }

            if recentItems.isEmpty {
                HStack(spacing: NarcSpacing.sm) {
                    Image(systemName: "tray")
                    Text("还没有记录。输入后按 Return 即可保存。")
                }
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, NarcSpacing.md)
            } else {
                ForEach(recentItems) { item in
                    InboxItemRow(
                        item: item,
                        compact: compact,
                        onConvert: { kind in
                            _ = captureState.convert(item, to: kind)
                            isInputFocused = true
                        },
                        onDelete: {
                            _ = captureState.delete(item)
                            isInputFocused = true
                        }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: NarcSpacing.md) {
            Text("Return 保存 · 再转 Todo / Note")
                .font(.narcMonoTiny)
                .foregroundColor(.narcTextFaint)

            Spacer()

            if let onOpenAssistant {
                Button("完整 Assistant", action: onOpenAssistant)
                    .buttonStyle(.plain)
                    .font(.narcCaption)
                    .foregroundColor(.narcAccent)
            }

            if let onDismiss {
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

private struct InboxItemRow: View {
    let item: InboxItem
    let compact: Bool
    let onConvert: (CaptureKind) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: NarcSpacing.sm) {
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text(item.content)
                    .font(.narcBody)
                    .foregroundColor(.narcText)
                    .lineLimit(compact ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.updatedAt, style: .relative)
                    .font(.narcMonoTiny)
                    .foregroundColor(.narcTextFaint)
            }

            Button(action: { onConvert(.todo) }) {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(.narcTextMuted)
            .help("转为 Todo")
            .accessibilityLabel("把记录转为 Todo")

            Button(action: { onConvert(.note) }) {
                Image(systemName: "note.text")
            }
            .buttonStyle(.plain)
            .foregroundColor(.narcTextMuted)
            .help("转为 Note")
            .accessibilityLabel("把记录转为 Note")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.narcTextFaint)
            .help("删除记录")
            .accessibilityLabel("删除记录")
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, compact ? NarcSpacing.xs : NarcSpacing.sm)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous)
                .strokeBorder(Color.narcBorder.opacity(0.7), lineWidth: 0.5)
        }
    }
}
