import Combine
import Foundation

enum AssistantStoreFailure: LocalizedError, Equatable {
    case blankContent
    case unsupportedSchema(Int)
    case loadFailed(String)
    case saveFailed(String)
    case writesBlockedAfterLoadFailure

    var errorDescription: String? {
        switch self {
        case .blankContent:
            return "内容不能为空。"
        case .unsupportedSchema(let version):
            return "数据版本 \(version) 暂不受支持，请先升级 NARC。"
        case .loadFailed:
            return "无法读取个人助手数据，原文件已保留。"
        case .saveFailed:
            return "保存失败，请检查磁盘空间和文件权限后重试。"
        case .writesBlockedAfterLoadFailure:
            return "检测到无法读取的现有数据。为避免覆盖，当前已停止写入。"
        }
    }
}

/// The local source of truth for Inbox, Todo, and Note data.
///
/// Mutations are persisted before published state changes, so the UI cannot
/// report success when the atomic file write failed. A failed initial load also
/// blocks later writes to prevent replacing unreadable user data with an empty
/// snapshot.
@MainActor
final class AssistantStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []
    @Published private(set) var notes: [NoteItem] = []
    @Published private(set) var inboxItems: [InboxItem] = []
    @Published private(set) var lastError: AssistantStoreFailure?

    let storageURL: URL

    private let fileManager: FileManager
    private var writesBlocked = false

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        load()
    }

    var incompleteTodos: [TodoItem] {
        sortedTodos(todos.filter { !$0.isCompleted })
    }

    var completedTodos: [TodoItem] {
        todos
            .filter(\.isCompleted)
            .sorted {
                let lhsDate = $0.completedAt ?? $0.updatedAt
                let rhsDate = $1.completedAt ?? $1.updatedAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var recentInboxItems: [InboxItem] {
        inboxItems.sorted { $0.updatedAt > $1.updatedAt }
    }

    func availableTodos(now: Date = Date()) -> [TodoItem] {
        sortedTodos(
            todos.filter { todo in
                guard !todo.isCompleted else { return false }
                guard let deferredUntil = todo.deferredUntil else { return true }
                return deferredUntil <= now
            }
        )
    }

    func nextTodo(after id: UUID?, now: Date = Date()) -> TodoItem? {
        let candidates = availableTodos(now: now)
        guard !candidates.isEmpty else { return nil }
        guard let id,
              let currentIndex = candidates.firstIndex(where: { $0.id == id }) else {
            return candidates[0]
        }

        return candidates[(currentIndex + 1) % candidates.count]
    }

    @discardableResult
    func capture(_ content: String, as kind: CaptureKind, now: Date = Date()) -> Bool {
        switch kind {
        case .todo:
            return createTodo(title: content, now: now)
        case .note:
            return createNote(content: content, now: now)
        }
    }

    @discardableResult
    func createTodo(title: String, now: Date = Date()) -> Bool {
        createTodoItem(title: title, now: now) != nil
    }

    /// Persist a Todo and return the exact item that was committed.
    ///
    /// Callers that offer Undo must retain this UUID instead of searching by
    /// title or assuming the newest item is still the one they created.
    @discardableResult
    func createTodoItem(
        title: String,
        id: UUID = UUID(),
        now: Date = Date()
    ) -> TodoItem? {
        guard let title = normalizedContent(title) else {
            lastError = .blankContent
            return nil
        }

        let item = TodoItem(id: id, title: title, createdAt: now)
        var nextTodos = todos
        nextTodos.append(item)
        guard persist(todos: nextTodos, notes: notes, inboxItems: inboxItems) else {
            return nil
        }
        return item
    }

    /// Atomically delete one exact Todo. Used by the short-lived Undo token
    /// emitted from explicit selected-text capture.
    @discardableResult
    func deleteTodo(id: UUID) -> Bool {
        guard todos.contains(where: { $0.id == id }) else {
            return false
        }

        let nextTodos = todos.filter { $0.id != id }
        return persist(todos: nextTodos, notes: notes, inboxItems: inboxItems)
    }

    @discardableResult
    func setTodoCompleted(id: UUID, completed: Bool, now: Date = Date()) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return false
        }

        var nextTodos = todos
        nextTodos[index].completedAt = completed ? now : nil
        if completed { nextTodos[index].isNext = false }
        nextTodos[index].deferredUntil = nil
        nextTodos[index].updatedAt = now
        return persist(todos: nextTodos, notes: notes, inboxItems: inboxItems)
    }

    @discardableResult
    func setTodoDeferred(id: UUID, until: Date?, now: Date = Date()) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }),
              !todos[index].isCompleted else {
            return false
        }

        var nextTodos = todos
        nextTodos[index].deferredUntil = until
        nextTodos[index].updatedAt = now
        return persist(todos: nextTodos, notes: notes, inboxItems: inboxItems)
    }

    @discardableResult
    func createNote(content: String, now: Date = Date()) -> Bool {
        guard let content = normalizedContent(content) else {
            lastError = .blankContent
            return false
        }

        var nextNotes = notes
        nextNotes.append(NoteItem(content: content, createdAt: now))
        return persist(todos: todos, notes: nextNotes, inboxItems: inboxItems)
    }

    @discardableResult
    func deleteNote(id: UUID) -> Bool {
        guard notes.contains(where: { $0.id == id }) else {
            return false
        }

        let nextNotes = notes.filter { $0.id != id }
        return persist(todos: todos, notes: nextNotes, inboxItems: inboxItems)
    }

    @discardableResult
    func captureInbox(_ content: String, now: Date = Date()) -> Bool {
        guard let content = normalizedContent(content) else {
            lastError = .blankContent
            return false
        }

        var nextInboxItems = inboxItems
        nextInboxItems.append(InboxItem(content: content, createdAt: now))
        return persist(todos: todos, notes: notes, inboxItems: nextInboxItems)
    }

    @discardableResult
    func convertInbox(id: UUID, to kind: CaptureKind, now: Date = Date()) -> Bool {
        guard let item = inboxItems.first(where: { $0.id == id }) else {
            return false
        }
        guard let content = normalizedContent(item.content) else {
            lastError = .blankContent
            return false
        }

        var nextTodos = todos
        var nextNotes = notes
        let nextInboxItems = inboxItems.filter { $0.id != id }

        switch kind {
        case .todo:
            nextTodos.append(
                TodoItem(
                    id: item.id,
                    title: content,
                    createdAt: item.createdAt,
                    updatedAt: now
                )
            )
        case .note:
            nextNotes.append(
                NoteItem(
                    id: item.id,
                    content: content,
                    createdAt: item.createdAt,
                    updatedAt: now
                )
            )
        }

        return persist(
            todos: nextTodos,
            notes: nextNotes,
            inboxItems: nextInboxItems
        )
    }

    @discardableResult
    func deleteInbox(id: UUID) -> Bool {
        guard inboxItems.contains(where: { $0.id == id }) else {
            return false
        }

        let nextInboxItems = inboxItems.filter { $0.id != id }
        return persist(todos: todos, notes: notes, inboxItems: nextInboxItems)
    }

    func searchNotes(query: String) -> [NoteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedNotes = notes.sorted { $0.updatedAt > $1.updatedAt }
        guard !normalizedQuery.isEmpty else { return sortedNotes }

        return sortedNotes.filter {
            $0.content.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    func clearError() {
        lastError = nil
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let snapshot = try Self.makeDecoder().decode(AssistantSnapshot.self, from: data)
            guard (1...AssistantSnapshot.currentSchemaVersion).contains(snapshot.schemaVersion) else {
                writesBlocked = true
                lastError = .unsupportedSchema(snapshot.schemaVersion)
                return
            }

            todos = snapshot.todos
            notes = snapshot.notes
            inboxItems = snapshot.inboxItems
            lastError = nil
        } catch {
            writesBlocked = true
            lastError = .loadFailed(error.localizedDescription)
        }
    }

    private func persist(
        todos: [TodoItem],
        notes: [NoteItem],
        inboxItems: [InboxItem]
    ) -> Bool {
        guard !writesBlocked else {
            lastError = .writesBlockedAfterLoadFailure
            return false
        }

        let snapshot = AssistantSnapshot(
            todos: todos,
            notes: notes,
            inboxItems: inboxItems
        )

        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.makeEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)

            self.todos = todos
            self.notes = notes
            self.inboxItems = inboxItems
            lastError = nil
            return true
        } catch {
            lastError = .saveFailed(error.localizedDescription)
            return false
        }
    }

    private func normalizedContent(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Commit planning changes and the single explicit next task together.
    @discardableResult
    func updateTodoPlanning(
        id: UUID, priority: TodoPriority, dueAt: Date?, isNext: Bool,
        now: Date = Date()
    ) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id && !$0.isCompleted }) else {
            return false
        }
        var nextTodos = todos
        if isNext {
            for other in nextTodos.indices where nextTodos[other].isNext {
                nextTodos[other].isNext = false
                nextTodos[other].updatedAt = now
            }
            nextTodos[index].deferredUntil = nil
        }
        nextTodos[index].priority = priority
        nextTodos[index].dueAt = dueAt
        nextTodos[index].isNext = isNext
        nextTodos[index].updatedAt = now
        return persist(todos: nextTodos, notes: notes, inboxItems: inboxItems)
    }

    private func sortedTodos(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted {
            if $0.isNext != $1.isNext { return $0.isNext }
            if $0.priority != $1.priority { return $0.priority.rawValue < $1.priority.rawValue }
            if $0.dueAt != $1.dueAt {
                return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture)
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("NARC", isDirectory: true)
            .appendingPathComponent("assistant-v1.json", isDirectory: false)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
