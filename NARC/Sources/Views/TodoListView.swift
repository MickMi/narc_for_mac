import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: AssistantStore
    let onCreate: () -> Void

    @State private var showsCompleted = false
    @State private var editingTodo: TodoItem?

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
                            TodoItemRow(
                                todo: todo,
                                onToggleCompleted: {
                                    _ = store.setTodoCompleted(id: todo.id, completed: true)
                                },
                                onResume: {
                                    _ = store.setTodoDeferred(id: todo.id, until: nil)
                                },
                                onPlan: { editingTodo = todo }
                            )
                        }
                    }

                    if !store.completedTodos.isEmpty {
                        DisclosureGroup(isExpanded: $showsCompleted) {
                            LazyVStack(spacing: NarcSpacing.sm) {
                                ForEach(store.completedTodos) { todo in
                                    TodoItemRow(
                                        todo: todo,
                                        onToggleCompleted: {
                                            _ = store.setTodoCompleted(id: todo.id, completed: false)
                                        },
                                        onResume: nil
                                    )
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
        .sheet(item: $editingTodo) { todo in
            TodoPlanningEditor(store: store, todo: todo)
        }
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
    let onResume: (() -> Void)?
    var onPlan: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            row(now: context.date)
        }
    }

    private func row(now: Date) -> some View {
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

                if !todo.isCompleted {
                    HStack(spacing: NarcSpacing.xs) {
                        if todo.isNext { Text("下一件事 ·") }
                        Text(todo.priority.label)
                        if let dueAt = todo.dueAt {
                            Text("· 截止")
                            Text(dueAt, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    .font(.narcCaption)
                    .foregroundColor(todo.isNext ? .narcAccent : .narcTextMuted)
                }

                if let deferredUntil = todo.deferredUntil,
                   deferredUntil > now,
                   let onResume {
                    HStack(spacing: NarcSpacing.sm) {
                        HStack(spacing: NarcSpacing.xs) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("稍后")
                            Text(deferredUntil, style: .relative)
                        }
                        .font(.narcCaption)
                        .foregroundColor(.narcWarn)

                        Button("现在处理", action: onResume)
                            .buttonStyle(.link)
                            .font(.narcCaption)
                            .accessibilityLabel("现在处理 Todo：\(todo.title)")
                    }
                }
            }
            if let onPlan {
                Button("安排", action: onPlan)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("安排 Todo：\(todo.title)")
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

private struct TodoPlanningEditor: View {
    @ObservedObject var store: AssistantStore
    let todo: TodoItem
    @Environment(\.dismiss) private var dismiss
    @State private var priority: TodoPriority
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var isNext: Bool
    @State private var saveError: String?

    init(store: AssistantStore, todo: TodoItem) {
        self.store = store
        self.todo = todo
        _priority = State(initialValue: todo.priority)
        _hasDueDate = State(initialValue: todo.dueAt != nil)
        _dueAt = State(initialValue: todo.dueAt ?? Date())
        _isNext = State(initialValue: todo.isNext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.md) {
            Text("安排 Todo").font(.narcTitle)
            Text(todo.title).font(.narcBody).lineLimit(3)
            Form {
                Toggle("设为下一件事", isOn: $isNext)
                Text("优先于其他任务；会替换此前指定的下一件事，并取消此任务的延期。")
                    .font(.narcCaption).foregroundStyle(.secondary)
                Picker("优先级", selection: $priority) {
                    ForEach(TodoPriority.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                Toggle("设置截止时间", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("截止", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                }
            }
            if let saveError { Text(saveError).font(.narcCaption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if store.updateTodoPlanning(id: todo.id, priority: priority,
                                                dueAt: hasDueDate ? dueAt : nil, isNext: isNext) {
                        dismiss()
                    } else {
                        saveError = store.lastError?.errorDescription ?? "任务已改变，请关闭后重试。"
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(NarcSpacing.xl)
        .frame(width: 420)
    }
}
