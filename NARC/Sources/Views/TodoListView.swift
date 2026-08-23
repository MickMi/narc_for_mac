import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: AssistantStore
    let onCreate: () -> Void

    @State private var showsCompleted = false

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
                        sectionHeader(
                            title: "待完成",
                            count: store.incompleteTodos.count,
                            icon: "circle"
                        )

                        ForEach(store.incompleteTodos) { todo in
                            TodoItemRow(todo: todo) {
                                _ = store.setTodoCompleted(id: todo.id, completed: true)
                            }
                        }
                    }

                    if !store.completedTodos.isEmpty {
                        DisclosureGroup(isExpanded: $showsCompleted) {
                            LazyVStack(spacing: NarcSpacing.sm) {
                                ForEach(store.completedTodos) { todo in
                                    TodoItemRow(todo: todo) {
                                        _ = store.setTodoCompleted(id: todo.id, completed: false)
                                    }
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
        .background(Color.narcBackground)
    }

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundColor(.narcTextMuted)

            Text(store.completedTodos.isEmpty ? "还没有 Todo" : "当前没有待完成 Todo")
                .font(.narcSubtitle)
                .foregroundColor(.narcText)

            Text("快速记下下一件需要处理的事。")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)

            Button("新建 Todo", action: onCreate)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("新建 Todo")
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
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
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

            VStack(alignment: .leading, spacing: NarcSpacing.xs) {
                Text(todo.title)
                    .font(.narcBody)
                    .foregroundColor(todo.isCompleted ? .narcTextMuted : .narcText)
                    .strikethrough(todo.isCompleted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(todo.createdAt, style: .relative)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextFaint)
            }
        }
        .padding(NarcSpacing.md)
        .softRowBackground(
            isSelected: false,
            needsAttention: false,
            isHovering: isHovering
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
