import Foundation
import Testing
@testable import NARC

@Test
@MainActor
func assistantStorePersistsTodoAndNoteAcrossReload() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.createTodo(title: "  Ship the assistant plan  ", now: createdAt))
    #expect(store.createNote(content: "  Keep Workspace as-is.  ", now: createdAt))
    #expect(store.todos.map(\.title) == ["Ship the assistant plan"])
    #expect(store.notes.map(\.content) == ["Keep Workspace as-is."])
    #expect(FileManager.default.fileExists(atPath: location.file.path))

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos == store.todos)
    #expect(reloaded.notes == store.notes)
    #expect(reloaded.lastError == nil)
}

@Test
@MainActor
func assistantStorePersistsTodoCompletion() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let completedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.createTodo(title: "Verify persistence", now: createdAt))
    let todoID = try #require(store.todos.first?.id)
    #expect(store.setTodoCompleted(id: todoID, completed: true, now: completedAt))
    #expect(store.incompleteTodos.isEmpty)
    #expect(store.completedTodos.first?.completedAt == completedAt)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.todos.first?.isCompleted == true)
    #expect(reloaded.todos.first?.completedAt == completedAt)
}

@Test
@MainActor
func assistantStoreRejectsBlankContentWithoutCreatingAFile() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)

    #expect(!store.createTodo(title: " \n\t "))
    #expect(store.lastError == .blankContent)
    #expect(store.todos.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: location.file.path))

    store.clearError()
    #expect(!store.createNote(content: "   "))
    #expect(store.lastError == .blankContent)
    #expect(store.notes.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: location.file.path))
}

@Test
@MainActor
func assistantStoreDoesNotOverwriteCorruptData() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let corruptData = Data("{not-valid-json".utf8)
    try corruptData.write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    guard case .loadFailed = store.lastError else {
        Issue.record("Expected corrupt data to produce a load failure")
        return
    }

    #expect(!store.createTodo(title: "Must not replace the file"))
    #expect(store.lastError == .writesBlockedAfterLoadFailure)
    #expect(try Data(contentsOf: location.file) == corruptData)
}

@Test
@MainActor
func assistantStoreSearchesAndDeletesNotesPersistently() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    #expect(store.createNote(content: "Alpha decision"))
    #expect(store.createNote(content: "Beta follow-up"))

    let matches = store.searchNotes(query: "ALPHA")
    #expect(matches.count == 1)
    #expect(matches.first?.content == "Alpha decision")

    let noteID = try #require(matches.first?.id)
    #expect(store.deleteNote(id: noteID))
    #expect(store.searchNotes(query: "alpha").isEmpty)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.notes.map(\.content) == ["Beta follow-up"])
}

private func makeAssistantTestLocation() throws -> (directory: URL, file: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("narc-assistant-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return (
        directory,
        directory.appendingPathComponent("assistant-v1.json", isDirectory: false)
    )
}
