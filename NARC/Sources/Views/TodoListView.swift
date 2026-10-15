import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: AssistantStore
    var compact = false

    @State private var showsCompleted = false
    @State private var editingTodo: TodoItem?
    @State private var pendingDeletion: TodoItem?

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.lastError?.errorDescription {
                errorBanner(error)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: NarcSpacing.sm) {
                    if store.incompleteTodos.isEmpty {
                        emptyState
                    } else {
                        sectionHeader(title: "待完成", count: store.incompleteTodos.count, icon: "circle")
                        ForEach(store.incompleteTodos) { todo in
                            row(todo)
                        }
                    }

                    if !store.completedTodos.isEmpty {
                        DisclosureGroup(isExpanded: $showsCompleted) {
                            LazyVStack(spacing: NarcSpacing.sm) {
                                ForEach(store.completedTodos) { todo in
                                    row(todo)
                                }
                            }
                            .padding(.top, NarcSpacing.sm)
                        } label: {
                            HStack(spacing: NarcSpacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("已完成")
                                Text("\(store.completedTodos.count)")
                                    .font(.narcMonoSmall)
                                    .foregroundColor(.narcTextFaint)
                            }
                            .font(.narcSubtitle)
                            .foregroundColor(.narcTextMuted)
                        }
                        .padding(.top, NarcSpacing.md)
                    }
                }
                .padding(NarcSpacing.lg)
            }
        }
        .background(compact ? Color.clear : Color.narcBackground)
        .sheet(item: $editingTodo) { todo in
            TodoTitleEditor(store: store, todo: todo)
        }
        .alert("删除这条 Todo？", isPresented: deletionConfirmation) {
            Button("删除", role: .destructive) {
                if let pendingDeletion {
                    _ = store.deleteTodo(id: pendingDeletion.id)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("删除后将从本机数据中移除，当前版本不提供撤销。")
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        TodoItemRow(
            todo: todo,
            onToggleCompleted: {
                _ = store.setTodoCompleted(id: todo.id, completed: !todo.isCompleted)
            },
            onEdit: { editingTodo = todo },
            onDelete: { pendingDeletion = todo }
        )
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundColor(.narcTextMuted)
            Text(store.completedTodos.isEmpty ? "还没有 Todo" : "当前没有待完成 Todo")
                .font(.narcSubtitle)
                .foregroundColor(.narcText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NarcSpacing.xxxxl)
    }

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: icon)
            Text(title)
            Text("\(count)")
                .font(.narcMonoSmall)
                .foregroundColor(.narcTextFaint)
            Spacer()
        }
        .font(.narcSubtitle)
        .foregroundColor(.narcTextMuted)
        .padding(.bottom, NarcSpacing.xs)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .font(.narcCaption)
        .foregroundColor(.narcDanger)
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcDanger.opacity(0.08))
        .accessibilityLabel("Todo 保存错误：\(message)")
    }
}

private struct TodoItemRow: View {
    let todo: TodoItem
    let onToggleCompleted: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: NarcSpacing.md) {
            Button(action: onToggleCompleted) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.narcSubtitle)
                    .foregroundColor(todo.isCompleted ? .narcSuccess : .narcTextMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "将 Todo 标记为未完成" : "将 Todo 标记为已完成")

            Text(todo.title)
                .font(.narcBody)
                .foregroundColor(todo.isCompleted ? .narcTextMuted : .narcText)
                .strikethrough(todo.isCompleted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("修改 Todo")
            .accessibilityLabel("修改 Todo：\(todo.title)")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("删除 Todo")
            .accessibilityLabel("删除 Todo：\(todo.title)")
        }
        .padding(NarcSpacing.md)
        .softRowBackground(isSelected: false, needsAttention: false, isHovering: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct TodoTitleEditor: View {
    @ObservedObject var store: AssistantStore
    let todo: TodoItem
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var saveError: String?

    init(store: AssistantStore, todo: TodoItem) {
        self.store = store
        self.todo = todo
        _title = State(initialValue: todo.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.md) {
            Text("修改 Todo").font(.narcTitle)
            TextField("要做什么？", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let saveError {
                Text(saveError).font(.narcCaption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(NarcSpacing.xl)
        .frame(width: 420)
    }

    private func save() {
        if store.updateTodoTitle(id: todo.id, title: title) {
            dismiss()
        } else {
            saveError = store.lastError?.errorDescription ?? "任务已改变，请关闭后重试。"
        }
    }
}
