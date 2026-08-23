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

/// The local source of truth for Todo and Note data.
///
/// Mutations are persisted before published state changes, so the UI cannot
/// report success when the atomic file write failed. A failed initial load also
/// blocks later writes to prevent replacing unreadable user data with an empty
/// snapshot.
@MainActor
final class AssistantStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []
    @Published private(set) var notes: [NoteItem] = []
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
        todos
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var completedTodos: [TodoItem] {
        todos
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
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
        guard let title = normalizedContent(title) else {
            lastError = .blankContent
            return false
        }

        var nextTodos = todos
        nextTodos.append(TodoItem(title: title, createdAt: now))
        return persist(todos: nextTodos, notes: notes)
    }

    @discardableResult
    func setTodoCompleted(id: UUID, completed: Bool, now: Date = Date()) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return false
        }

        var nextTodos = todos
        nextTodos[index].completedAt = completed ? now : nil
        nextTodos[index].updatedAt = now
        return persist(todos: nextTodos, notes: notes)
    }

    @discardableResult
    func createNote(content: String, now: Date = Date()) -> Bool {
        guard let content = normalizedContent(content) else {
            lastError = .blankContent
            return false
        }

        var nextNotes = notes
        nextNotes.append(NoteItem(content: content, createdAt: now))
        return persist(todos: todos, notes: nextNotes)
    }

    @discardableResult
    func deleteNote(id: UUID) -> Bool {
        guard notes.contains(where: { $0.id == id }) else {
            return false
        }

        let nextNotes = notes.filter { $0.id != id }
        return persist(todos: todos, notes: nextNotes)
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
            guard snapshot.schemaVersion == AssistantSnapshot.currentSchemaVersion else {
                writesBlocked = true
                lastError = .unsupportedSchema(snapshot.schemaVersion)
                return
            }

            todos = snapshot.todos
            notes = snapshot.notes
            lastError = nil
        } catch {
            writesBlocked = true
            lastError = .loadFailed(error.localizedDescription)
        }
    }

    private func persist(todos: [TodoItem], notes: [NoteItem]) -> Bool {
        guard !writesBlocked else {
            lastError = .writesBlockedAfterLoadFailure
            return false
        }

        let snapshot = AssistantSnapshot(todos: todos, notes: notes)

        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.makeEncoder().encode(snapshot)
            try data.write(to: storageURL, options: .atomic)

            self.todos = todos
            self.notes = notes
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
