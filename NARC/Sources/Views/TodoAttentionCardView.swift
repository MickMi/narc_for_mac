import SwiftUI

struct TodoAttentionSelection: Equatable {
    let todo: TodoItem?
    let position: Int?
    let total: Int

    var canAdvance: Bool { total > 1 }

    static func resolve(
        currentTodoID: UUID?,
        availableTodos: [TodoItem]
    ) -> TodoAttentionSelection {
        let index = currentTodoID
            .flatMap { id in availableTodos.firstIndex { $0.id == id } }
            ?? availableTodos.indices.first

        guard let index else {
            return TodoAttentionSelection(todo: nil, position: nil, total: 0)
        }

        return TodoAttentionSelection(
            todo: availableTodos[index],
            position: index + 1,
            total: availableTodos.count
        )
    }
}

enum TodoAttentionPresentation {
    case inbox
    case nudge
}

/// A single-item Todo surface for the lightweight floating panel.
///
/// The card never owns or copies Todo data. It keeps only the currently viewed
/// identifier locally and delegates every durable mutation to the app-level
/// `AssistantStore` supplied by `AppDelegate`.
struct TodoAttentionCardView: View {
    @ObservedObject var store: AssistantStore

    let presentation: TodoAttentionPresentation
    let onActionStarted: (() -> Void)?
    let onActionFailed: (() -> Void)?
    let onSuccessfulAction: (() -> Void)?
    let onDismiss: (() -> Void)?

    @State private var currentTodoID: UUID?
    @State private var actionError: String?

    init(
        store: AssistantStore,
        initialTodoID: UUID? = nil,
        presentation: TodoAttentionPresentation = .inbox,
        onActionStarted: (() -> Void)? = nil,
        onActionFailed: (() -> Void)? = nil,
        onSuccessfulAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.presentation = presentation
        self.onActionStarted = onActionStarted
        self.onActionFailed = onActionFailed
        self.onSuccessfulAction = onSuccessfulAction
        self.onDismiss = onDismiss
        _currentTodoID = State(initialValue: initialTodoID)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let availableTodos = store.availableTodos(now: context.date)
            let selection = TodoAttentionSelection.resolve(
                currentTodoID: currentTodoID,
                availableTodos: availableTodos
            )

            if let todo = selection.todo {
                card(
                    todo: todo,
                    selection: selection
                )
            } else {
                EmptyView()
            }
        }
        .onChange(of: store.todos) { _, _ in
            actionError = nil
        }
    }

    private func card(
        todo: TodoItem,
        selection: TodoAttentionSelection
    ) -> some View {
        cardSurface(
            VStack(alignment: .leading, spacing: NarcSpacing.md) {
                HStack(spacing: NarcSpacing.sm) {
                    Label("未完成 Todo", systemImage: "checklist")
                        .font(.narcCaption)
                        .foregroundColor(.narcTextMuted)

                    Spacer()

                    if let position = selection.position {
                        Text("\(position) / \(selection.total)")
                            .font(.narcCaption)
                            .foregroundColor(.narcTextMuted)
                            .accessibilityLabel("第 \(position) 项，共 \(selection.total) 项")
                    }
                }

                Text(todo.title)
                    .font(.system(size: presentation == .inbox ? 22 : 18, weight: .semibold))
                    .foregroundColor(.narcText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.circle.fill")
                        .font(.narcCaption)
                        .foregroundColor(.narcDanger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Todo 操作失败：\(actionError)")
                }

                HStack(spacing: NarcSpacing.sm) {
                    Button {
                        complete(todo)
                    } label: {
                        Label("完成", systemImage: "checkmark")
                    }
                    .buttonStyle(NarcFocusPrimaryButtonStyle())
                    .accessibilityLabel("完成 Todo：\(todo.title)")

                    Spacer(minLength: 0)

                    if presentation == .nudge {
                        Button {
                            onDismiss?()
                        } label: {
                            Label("收起", systemImage: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("收起 Todo 提醒")
                    } else {
                        Button {
                            showNext(after: todo.id)
                        } label: {
                            Image(systemName: "arrow.right")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("查看下一项 Todo")
                        .disabled(!selection.canAdvance)
                        .accessibilityLabel("查看下一项 Todo")
                    }
                }
                .controlSize(.small)
            }
            .padding(.vertical, NarcSpacing.sm)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func cardSurface<Content: View>(_ content: Content) -> some View {
        switch presentation {
        case .inbox:
            content
                .padding(.bottom, NarcSpacing.md)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.narcBorder.opacity(0.35)).frame(height: 0.5)
                }
        case .nudge:
            content
        }
    }

    private func complete(_ todo: TodoItem) {
        let now = Date()
        let successorID = store.nextTodo(after: todo.id, now: now)?.id
        store.clearError()
        onActionStarted?()

        guard store.setTodoCompleted(id: todo.id, completed: true, now: now) else {
            actionError = store.lastError?.errorDescription ?? "无法完成 Todo，请稍后重试。"
            store.clearError()
            onActionFailed?()
            return
        }

        actionError = nil
        currentTodoID = successorID
        onSuccessfulAction?()
    }

    private func showNext(after todoID: UUID) {
        let now = Date()
        actionError = nil
        currentTodoID = store.nextTodo(after: todoID, now: now)?.id
    }
}
