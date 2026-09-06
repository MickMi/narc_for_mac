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
    #expect(reloaded.inboxItems.isEmpty)
    #expect(reloaded.lastError == nil)
}

@Test
@MainActor
func assistantStorePersistsSortsAndDeletesInboxItems() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newerDate = Date(timeIntervalSince1970: 1_700_000_100)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.captureInbox("  First thought  ", now: olderDate))
    #expect(store.captureInbox("Second thought", now: newerDate))
    #expect(store.inboxItems.map(\.content) == ["First thought", "Second thought"])
    #expect(store.recentInboxItems.map(\.content) == ["Second thought", "First thought"])

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.inboxItems == store.inboxItems)
    #expect(reloaded.recentInboxItems.map(\.content) == ["Second thought", "First thought"])

    let firstID = try #require(reloaded.inboxItems.first?.id)
    #expect(reloaded.deleteInbox(id: firstID))

    let afterDeletion = AssistantStore(storageURL: location.file)
    #expect(afterDeletion.inboxItems.map(\.content) == ["Second thought"])
}

@Test
@MainActor
func inboxCaptureStatePersistsDraftUntilASuccessfulSave() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    var completionCount = 0
    let captureState = InboxCaptureState(store: store) {
        completionCount += 1
    }

    captureState.updateDraft("  Keep this draft  ")
    #expect(captureState.draft == "  Keep this draft  ")
    #expect(captureState.submit())
    #expect(captureState.draft.isEmpty)
    #expect(captureState.successMessage == "已存入随手箱")
    #expect(completionCount == 1)
    #expect(store.inboxItems.map(\.content) == ["Keep this draft"])
}

@Test
@MainActor
func inboxCaptureStateKeepsTextAndDoesNotCompleteWhenPersistenceFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let corruptData = Data("{not-valid-json".utf8)
    try corruptData.write(to: location.file, options: .atomic)
    let store = AssistantStore(storageURL: location.file)
    var completionCount = 0
    let captureState = InboxCaptureState(store: store) {
        completionCount += 1
    }

    captureState.updateDraft("Do not lose this")
    #expect(!captureState.submit())
    #expect(captureState.draft == "Do not lose this")
    #expect(captureState.validationMessage != nil)
    #expect(completionCount == 0)
    #expect(try Data(contentsOf: location.file) == corruptData)
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

    store.clearError()
    #expect(!store.captureInbox(" \n\t "))
    #expect(store.lastError == .blankContent)
    #expect(store.inboxItems.isEmpty)
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

@Test
@MainActor
func assistantStoreLoadsV1AndWritesV2WithoutLosingData() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let legacyTodo = TodoItem(title: "Existing Todo", createdAt: createdAt)
    let legacyNote = NoteItem(content: "Existing Note", createdAt: createdAt)
    let legacySnapshot = LegacyAssistantSnapshot(
        schemaVersion: 1,
        todos: [legacyTodo],
        notes: [legacyNote]
    )
    try makeAssistantEncoder().encode(legacySnapshot).write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    #expect(store.todos == [legacyTodo])
    #expect(store.notes == [legacyNote])
    #expect(store.inboxItems.isEmpty)
    #expect(store.lastError == nil)

    #expect(store.captureInbox("First Inbox", now: createdAt.addingTimeInterval(60)))

    let migrated = try makeAssistantDecoder().decode(
        AssistantSnapshot.self,
        from: Data(contentsOf: location.file)
    )
    #expect(migrated.schemaVersion == AssistantSnapshot.currentSchemaVersion)
    #expect(migrated.todos == [legacyTodo])
    #expect(migrated.notes == [legacyNote])
    #expect(migrated.inboxItems.map(\.content) == ["First Inbox"])
}

@Test
@MainActor
func assistantStoreConvertsInboxToTodoAndNoteAtomically() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let todoCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let noteCreatedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let convertedAt = Date(timeIntervalSince1970: 1_700_000_200)
    let store = AssistantStore(storageURL: location.file)

    #expect(store.captureInbox("Plan release", now: todoCreatedAt))
    #expect(store.captureInbox("Remember this decision", now: noteCreatedAt))
    let todoInbox = try #require(store.inboxItems.first { $0.content == "Plan release" })
    let noteInbox = try #require(store.inboxItems.first { $0.content == "Remember this decision" })

    #expect(store.convertInbox(id: todoInbox.id, to: .todo, now: convertedAt))
    #expect(store.convertInbox(id: noteInbox.id, to: .note, now: convertedAt))
    #expect(store.inboxItems.isEmpty)
    #expect(store.todos.first?.id == todoInbox.id)
    #expect(store.todos.first?.title == todoInbox.content)
    #expect(store.todos.first?.createdAt == todoCreatedAt)
    #expect(store.todos.first?.updatedAt == convertedAt)
    #expect(store.notes.first?.id == noteInbox.id)
    #expect(store.notes.first?.content == noteInbox.content)
    #expect(store.notes.first?.createdAt == noteCreatedAt)
    #expect(store.notes.first?.updatedAt == convertedAt)

    let reloaded = AssistantStore(storageURL: location.file)
    #expect(reloaded.inboxItems.isEmpty)
    #expect(reloaded.todos == store.todos)
    #expect(reloaded.notes == store.notes)
}

@Test
@MainActor
func assistantStoreLeavesInboxUntouchedWhenConversionTargetIsMissing() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    #expect(store.captureInbox("Keep me"))
    let originalInbox = store.inboxItems

    #expect(!store.convertInbox(id: UUID(), to: .todo))
    #expect(store.inboxItems == originalInbox)
    #expect(store.todos.isEmpty)
    #expect(store.notes.isEmpty)
}

@Test
@MainActor
func assistantStoreDoesNotPublishPartialConversionWhenSaveFails() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let store = AssistantStore(storageURL: location.file)
    #expect(store.captureInbox("Do not lose me"))
    let item = try #require(store.inboxItems.first)

    try FileManager.default.removeItem(at: location.directory)
    try Data("blocks-directory-recreation".utf8).write(to: location.directory)

    #expect(!store.convertInbox(id: item.id, to: .todo))
    guard case .saveFailed = store.lastError else {
        Issue.record("Expected a failed atomic write to surface saveFailed")
        return
    }
    #expect(store.inboxItems == [item])
    #expect(store.todos.isEmpty)
    #expect(store.notes.isEmpty)
}

@Test
@MainActor
func assistantStoreBlocksWritesForFutureSchema() throws {
    let location = try makeAssistantTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }

    let futureVersion = AssistantSnapshot.currentSchemaVersion + 1
    let futureSnapshot = AssistantSnapshot(
        schemaVersion: futureVersion,
        inboxItems: [InboxItem(content: "Future data")]
    )
    let originalData = try makeAssistantEncoder().encode(futureSnapshot)
    try originalData.write(to: location.file, options: .atomic)

    let store = AssistantStore(storageURL: location.file)
    #expect(store.lastError == .unsupportedSchema(futureVersion))
    #expect(!store.captureInbox("Must not overwrite future data"))
    #expect(store.lastError == .writesBlockedAfterLoadFailure)
    #expect(try Data(contentsOf: location.file) == originalData)
}

private struct LegacyAssistantSnapshot: Encodable {
    let schemaVersion: Int
    let todos: [TodoItem]
    let notes: [NoteItem]
}

private func makeAssistantEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func makeAssistantDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
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
